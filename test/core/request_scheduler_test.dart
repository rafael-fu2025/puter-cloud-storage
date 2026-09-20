import 'dart:math';

// package:test rather than flutter_test, so this runs under `dart test` with no
// Flutter harness. lib/core is deliberately Flutter-free for exactly this
// reason — see the note at the top of app_config.dart.
import 'package:test/test.dart';
import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/error/puter_exception.dart';
import 'package:puter_cloud_storage/core/network/request_scheduler.dart';

/// Run a scheduled operation, capturing either its value or its error.
Future<Object?> _capture(Future<void> future) =>
    future.then<Object?>((_) => null).catchError((Object error) => error);

void main() {
  group('TokenBucket', () {
    test('allows exactly capacity requests per window', () {
      final now = DateTime(2026, 9, 20, 12);
      final bucket = TokenBucket(
        capacity: 3,
        window: const Duration(minutes: 1),
        clock: () => now,
      );

      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isFalse, reason: 'fourth exceeds capacity');
      expect(bucket.remaining, 0);
    });

    test('refills once the window rolls', () {
      var now = DateTime(2026, 9, 20, 12);
      final bucket = TokenBucket(
        capacity: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );

      expect(bucket.tryConsume(), isTrue);
      expect(bucket.tryConsume(), isFalse);

      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(bucket.tryConsume(), isTrue);
    });

    test('reports time until a token frees up', () {
      var now = DateTime(2026, 9, 20, 12);
      final bucket = TokenBucket(
        capacity: 1,
        window: const Duration(minutes: 1),
        clock: () => now,
      );

      bucket.tryConsume();
      expect(bucket.timeUntilAvailable, const Duration(minutes: 1));

      now = now.add(const Duration(seconds: 30));
      expect(bucket.timeUntilAvailable, const Duration(seconds: 30));
    });
  });

  group('RequestScheduler concurrency', () {
    test('never exceeds the global concurrency cap', () async {
      const config = AppConfig(maxConcurrentRequests: 3);
      final scheduler = RequestScheduler(config: config);

      var peak = 0;

      final futures = List<Future<void>>.generate(
        20,
        (index) => scheduler.schedule<void>(RequestClass.stat, () async {
          peak = max(peak, scheduler.totalInFlight);
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }),
      );

      await Future.wait(futures);

      expect(
        peak,
        lessThanOrEqualTo(3),
        reason: 'the global cap is what keeps the client inside the '
            'per-network WebDAV ceiling',
      );
      expect(scheduler.totalInFlight, 0);
    });

    test('serves interactive work before background work', () async {
      const config = AppConfig(maxConcurrentRequests: 1);
      final scheduler = RequestScheduler(config: config);

      final order = <String>[];

      // Occupy the single slot so both waiters queue behind it.
      final blocker = scheduler.schedule<void>(RequestClass.stat, () async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });

      final background = scheduler.schedule<void>(
        RequestClass.stat,
        () async {
          order.add('background');
        },
        priority: RequestPriority.background,
      );
      final interactive = scheduler.schedule<void>(
        RequestClass.stat,
        () async {
          order.add('interactive');
        },
        priority: RequestPriority.interactive,
      );

      await Future.wait(<Future<void>>[blocker, background, interactive]);

      expect(
        order,
        <String>['interactive', 'background'],
        reason: 'a queued background refresh must never delay a user tap',
      );
    });
  });

  group('RequestScheduler rate limiting', () {
    test('rejects once the per-class burst budget is exhausted', () async {
      const config = AppConfig(maxConcurrentRequests: 10);
      final scheduler = RequestScheduler(config: config);

      // readdir's free tier allows a 60-per-10s burst. Fire 61 and the last
      // one must be refused rather than sent.
      final futures = <Future<Object?>>[
        for (var i = 0; i < 61; i++)
          _capture(
            scheduler.schedule<void>(
              RequestClass.readdir,
              () async => Future<void>.value(),
              timeout: const Duration(milliseconds: 250),
            ),
          ),
      ];

      final results = await Future.wait(futures);
      final rateLimited = results
          .whereType<PuterException>()
          .where((error) => error.kind == PuterErrorKind.rateLimited);

      expect(
        rateLimited,
        isNotEmpty,
        reason: 'the 10s burst budget of 60 must reject the 61st readdir',
      );
    });

    test('cancelWhere drops queued requests', () async {
      const config = AppConfig(maxConcurrentRequests: 1);
      final scheduler = RequestScheduler(config: config);

      final blocker = scheduler.schedule<void>(RequestClass.stat, () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      var ran = false;
      final queued = _capture(
        scheduler.schedule<void>(RequestClass.stat, () async {
          ran = true;
        }),
      );

      final cancelled = scheduler.cancelWhere((k) => k == RequestClass.stat);
      await Future.wait(<Future<Object?>>[blocker, queued]);

      expect(cancelled, 1);
      expect(ran, isFalse, reason: 'a cancelled request must never be sent');
    });
  });

  group('RequestScheduler auth lockout guard', () {
    test('permits attempts below the documented failure ceiling', () {
      final scheduler = RequestScheduler(config: const AppConfig());

      for (var i = 0; i < 9; i++) {
        expect(scheduler.recordAuthFailure(), isTrue);
      }
      expect(
        scheduler.recordAuthFailure(),
        isFalse,
        reason: "the 10th failure reaches WebDAV's lockout threshold, so the "
            'client must refuse to make another attempt',
      );
      expect(scheduler.authAttemptSafe, isFalse);
    });

    test('a successful authentication clears the counter', () {
      final scheduler = RequestScheduler(config: const AppConfig());

      for (var i = 0; i < 5; i++) {
        scheduler.recordAuthFailure();
      }
      scheduler.recordAuthSuccess();

      expect(scheduler.authAttemptSafe, isTrue);
      for (var i = 0; i < 9; i++) {
        expect(scheduler.recordAuthFailure(), isTrue);
      }
    });
  });

  group('RequestScheduler backoff', () {
    test('honours Retry-After when supplied', () {
      final scheduler = RequestScheduler(
        config: const AppConfig(),
        random: Random(1),
      );
      expect(
        scheduler.backoffFor(0, retryAfter: const Duration(seconds: 12)),
        const Duration(seconds: 12),
      );
    });

    test('clamps Retry-After to the configured ceiling', () {
      final scheduler = RequestScheduler(
        config: const AppConfig(maxRetryBackoff: Duration(seconds: 60)),
        random: Random(1),
      );
      expect(
        scheduler.backoffFor(0, retryAfter: const Duration(hours: 5)),
        const Duration(seconds: 60),
      );
    });

    test('applies full jitter within the exponential envelope', () {
      final scheduler = RequestScheduler(
        config: const AppConfig(),
        random: Random(42),
      );

      for (var attempt = 0; attempt < 6; attempt++) {
        final delay = scheduler.backoffFor(attempt);
        expect(delay, lessThanOrEqualTo(const Duration(seconds: 60)));
        expect(delay.isNegative, isFalse);
      }
    });
  });
}
