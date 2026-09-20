// Dependency-free verification of the core layer.
//
// The Flutter test harness cannot run in every environment (it needs a
// WebSocket upgrade to the flutter_tester process), and `dart test` needs the
// native-assets build hook. This script verifies the same invariants using
// nothing but the Dart VM, so the core logic can always be checked.
//
// The suites under test/ remain the source of truth for CI. This is the
// fallback that always runs.
//
//   dart run tool/verify/verify_core.dart
//
// Exits non-zero on failure, so it is usable as a gate.

import 'dart:math';

import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/error/puter_exception.dart';
import 'package:puter_cloud_storage/core/network/request_scheduler.dart';

int _passed = 0;
int _failed = 0;
final List<String> _failures = <String>[];

Future<void> main() async {
  say('Puter Cloud Storage — core verification');
  say('');

  // ------------------------------------------------------- error classification

  check('ErrorMapper: 413 maps to storageLimitReached', () {
    eq(ErrorMapper.fromHttpStatus(413), PuterErrorKind.storageLimitReached);
  });

  check('ErrorMapper: 401 maps to authInvalid', () {
    eq(ErrorMapper.fromHttpStatus(401), PuterErrorKind.authInvalid);
  });

  check('ErrorMapper: 429 maps to rateLimited', () {
    eq(ErrorMapper.fromHttpStatus(429), PuterErrorKind.rateLimited);
  });

  check('ErrorMapper: an explicit code beats the bare status', () {
    // A 402 carries two very different meanings; only the code disambiguates.
    eq(
      ErrorMapper.fromHttpStatus(402, code: 'subscription_required'),
      PuterErrorKind.subscriptionRequired,
    );
    eq(
      ErrorMapper.fromHttpStatus(402, code: 'insufficient_funds'),
      PuterErrorKind.insufficientFunds,
    );
  });

  check('ErrorMapper: 5xx is treated as transient', () {
    eq(ErrorMapper.fromHttpStatus(503), PuterErrorKind.network);
  });

  check('only transient failures are retryable', () {
    const retryable = <PuterErrorKind>{
      PuterErrorKind.rateLimited,
      PuterErrorKind.network,
      PuterErrorKind.unknown,
    };
    for (final kind in PuterErrorKind.values) {
      eq(
        PuterException(kind, 'x').isRetryable,
        retryable.contains(kind),
        detail: 'kind=${kind.name}',
      );
    }
  });

  check('authInvalid is never retryable and needs the user', () {
    // Retrying a failed sign-in can trip WebDAV's 15-minute lockout, which
    // returns 429 even for a correct token. See docs/security.md §4.
    final e = PuterException(PuterErrorKind.authInvalid, 'x');
    eq(e.isRetryable, false);
    eq(e.requiresUserAction, true);
  });

  check('money-shaped errors require the user and are not retryable', () {
    for (final kind in <PuterErrorKind>[
      PuterErrorKind.insufficientFunds,
      PuterErrorKind.subscriptionRequired,
      PuterErrorKind.storageLimitReached,
    ]) {
      eq(PuterException(kind, 'x').requiresUserAction, true, detail: kind.name);
      eq(PuterException(kind, 'x').isRetryable, false, detail: kind.name);
    }
  });

  // -------------------------------------------------------------- token bucket

  check('TokenBucket: allows exactly capacity per window', () {
    final now = DateTime(2026, 9, 20, 12);
    final bucket = TokenBucket(
      capacity: 3,
      window: const Duration(minutes: 1),
      clock: () => now,
    );
    eq(bucket.tryConsume(), true);
    eq(bucket.tryConsume(), true);
    eq(bucket.tryConsume(), true);
    eq(bucket.tryConsume(), false);
    eq(bucket.remaining, 0);
  });

  check('TokenBucket: refills when the window rolls', () {
    var now = DateTime(2026, 9, 20, 12);
    final bucket = TokenBucket(
      capacity: 1,
      window: const Duration(minutes: 1),
      clock: () => now,
    );
    eq(bucket.tryConsume(), true);
    eq(bucket.tryConsume(), false);
    now = now.add(const Duration(minutes: 1, seconds: 1));
    eq(bucket.tryConsume(), true);
  });

  check('TokenBucket: reports time until a token frees up', () {
    var now = DateTime(2026, 9, 20, 12);
    final bucket = TokenBucket(
      capacity: 1,
      window: const Duration(minutes: 1),
      clock: () => now,
    );
    bucket.tryConsume();
    eq(bucket.timeUntilAvailable, const Duration(minutes: 1));
    now = now.add(const Duration(seconds: 30));
    eq(bucket.timeUntilAvailable, const Duration(seconds: 30));
  });

  // ----------------------------------------------------------- scheduler

  await checkAsync('scheduler never exceeds the global concurrency cap', () async {
    const config = AppConfig(maxConcurrentRequests: 3);
    final scheduler = RequestScheduler(config: config);

    var peak = 0;
    await Future.wait(
      List<Future<void>>.generate(
        24,
        (_) => scheduler.schedule<void>(RequestClass.stat, () async {
          peak = max(peak, scheduler.totalInFlight);
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }),
      ),
    );

    // This is the guarantee that keeps the client inside WebDAV's shared
    // per-network ceiling.
    le(peak, 3, detail: 'peak concurrency was $peak');
    eq(scheduler.totalInFlight, 0);
  });

  await checkAsync('interactive work outranks background work', () async {
    const config = AppConfig(maxConcurrentRequests: 1);
    final scheduler = RequestScheduler(config: config);
    final order = <String>[];

    final blocker = scheduler.schedule<void>(RequestClass.stat, () async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    final background = scheduler.schedule<void>(
      RequestClass.stat,
      () async => order.add('background'),
      priority: RequestPriority.background,
    );
    final interactive = scheduler.schedule<void>(
      RequestClass.stat,
      () async => order.add('interactive'),
      priority: RequestPriority.interactive,
    );

    await Future.wait(<Future<void>>[blocker, background, interactive]);
    eq(order.join(','), 'interactive,background');
  });

  await checkAsync('the 10s burst budget rejects the 61st readdir', () async {
    const config = AppConfig(maxConcurrentRequests: 10);
    final scheduler = RequestScheduler(config: config);

    var rateLimited = 0;
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 61; i++)
        scheduler
            .schedule<void>(
              RequestClass.readdir,
              () async => Future<void>.value(),
              timeout: const Duration(milliseconds: 250),
            )
            .catchError((Object error) {
          if (error is PuterException &&
              error.kind == PuterErrorKind.rateLimited) {
            rateLimited++;
          }
        }),
    ]);

    ge(rateLimited, 1, detail: 'rejected $rateLimited of 61');
  });

  await checkAsync('cancelWhere prevents dispatch', () async {
    const config = AppConfig(maxConcurrentRequests: 1);
    final scheduler = RequestScheduler(config: config);

    final blocker = scheduler.schedule<void>(RequestClass.stat, () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    var ran = false;
    final queued = scheduler
        .schedule<void>(RequestClass.stat, () async => ran = true)
        .catchError((Object _) {});
    final cancelled = scheduler.cancelWhere((k) => k == RequestClass.stat);

    await Future.wait(<Future<void>>[blocker, queued]);
    eq(cancelled, 1);
    eq(ran, false);
  });

  // ------------------------------------------------------- auth lockout guard

  check('refuses a 10th authentication attempt', () {
    final scheduler = RequestScheduler(config: const AppConfig());
    for (var i = 0; i < 9; i++) {
      eq(scheduler.recordAuthFailure(), true, detail: 'attempt ${i + 1}');
    }
    eq(scheduler.recordAuthFailure(), false);
    eq(scheduler.authAttemptSafe, false);
  });

  check('a successful authentication clears the counter', () {
    final scheduler = RequestScheduler(config: const AppConfig());
    for (var i = 0; i < 5; i++) {
      scheduler.recordAuthFailure();
    }
    scheduler.recordAuthSuccess();
    eq(scheduler.authAttemptSafe, true);
  });

  // ---------------------------------------------------------------- backoff

  check('backoff honours and clamps Retry-After', () {
    final scheduler = RequestScheduler(
      config: const AppConfig(maxRetryBackoff: Duration(seconds: 60)),
      random: Random(7),
    );
    eq(
      scheduler.backoffFor(0, retryAfter: const Duration(seconds: 12)),
      const Duration(seconds: 12),
    );
    eq(
      scheduler.backoffFor(0, retryAfter: const Duration(hours: 5)),
      const Duration(seconds: 60),
    );
  });

  check('backoff stays inside the envelope', () {
    final scheduler = RequestScheduler(
      config: const AppConfig(),
      random: Random(99),
    );
    for (var attempt = 0; attempt < 6; attempt++) {
      final delay = scheduler.backoffFor(attempt);
      eq(delay.isNegative, false, detail: 'attempt $attempt');
      le(delay, const Duration(seconds: 60), detail: 'attempt $attempt');
    }
  });

  // ------------------------------------------------------------ documented limits

  check('limits are seeded conservatively at the free tier', () {
    final write = PuterLimits.filesystem[RequestClass.write]!;
    eq(write.perMinute(PlanTier.free), 120);
    eq(write.perMinute(PlanTier.paid), 300);

    final readdir = PuterLimits.filesystem[RequestClass.readdir]!;
    eq(readdir.burstPer10s(PlanTier.free), 60);

    eq(PuterLimits.globalCallsPerMinute, 8000);
    eq(PuterLimits.webdavRequestsPerMinute, 600);
    eq(PuterLimits.webdavConcurrent, 10);
    eq(PuterLimits.webdavFailedSignInsPerAccount, 10);
  });

  check('default concurrency sits under every documented ceiling', () {
    const config = AppConfig();
    le(config.maxConcurrentRequests, PuterLimits.webdavConcurrent);
    le(
      config.maxConcurrentRequests,
      PuterLimits.filesystem[RequestClass.read]!.concurrent(PlanTier.free),
    );
  });

  // ------------------------------------------------------------------- report

  say('');
  say('-' * 60);
  say('passed: $_passed    failed: $_failed');
  if (_failed > 0) {
    say('');
    say('Failures:');
    for (final failure in _failures) {
      say('  - $failure');
    }
    say('RESULT: FAIL');
    throw StateError('$_failed verification(s) failed');
  }
  say('RESULT: PASS');
}

// -------------------------------------------------------------------- harness

void say(String message) {
  // ignore: avoid_print
  print(message);
}

void check(String name, void Function() body) {
  try {
    body();
    _pass(name);
  } on Object catch (error) {
    _fail(name, error);
  }
}

Future<void> checkAsync(String name, Future<void> Function() body) async {
  try {
    await body();
    _pass(name);
  } on Object catch (error) {
    _fail(name, error);
  }
}

void _pass(String name) {
  _passed++;
  say('  PASS  $name');
}

void _fail(String name, Object error) {
  _failed++;
  _failures.add('$name -> $error');
  say('  FAIL  $name');
  say('        $error');
}

void eq(Object? actual, Object? expected, {String? detail}) {
  if (actual != expected) {
    throw StateError(
      'expected <$expected> but got <$actual>${detail == null ? '' : ' [$detail]'}',
    );
  }
}

void le(Comparable<Object> actual, Comparable<Object> bound, {String? detail}) {
  if (actual.compareTo(bound) > 0) {
    throw StateError(
      'expected <= $bound but got $actual${detail == null ? '' : ' [$detail]'}',
    );
  }
}

void ge(Comparable<Object> actual, Comparable<Object> bound, {String? detail}) {
  if (actual.compareTo(bound) < 0) {
    throw StateError(
      'expected >= $bound but got $actual${detail == null ? '' : ' [$detail]'}',
    );
  }
}
