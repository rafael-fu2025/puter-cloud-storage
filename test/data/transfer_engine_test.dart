/// Tests for the transfer engine.
///
/// This is the phase the product is judged on, so the suite pins the four
/// behaviours that make it trustworthy rather than merely functional:
///
/// * the queue survives a restart, and a task that was `running` when the
///   process died comes back `queued` — never stuck;
/// * a permanent failure (`413`, revoked token) stops dead instead of burning
///   the request budget on retries that cannot work;
/// * cancelling is not failing;
/// * concurrency never exceeds the cap, because WebDAV allows only 10
///   concurrent requests for the whole network.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/error/puter_exception.dart';
import 'package:puter_cloud_storage/data/database/node_cache.dart';
import 'package:puter_cloud_storage/data/repositories/file_repository.dart';
import 'package:puter_cloud_storage/data/transfer/transfer_engine.dart';
import 'package:puter_cloud_storage/data/transfer/transfer_store.dart';
import 'package:puter_cloud_storage/data/transport/puter_transport.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';

import '../support/fake_transport.dart';

void main() {
  /// A real directory, because the upload path measures the file on disk.
  late Directory tempDir;
  late FakeTransport transport;
  late InMemoryNodeCache cache;
  late InMemoryTransferStore store;
  late FileRepository repository;

  /// Build an engine over the current fakes.
  TransferEngine buildEngine({AppConfig config = const AppConfig()}) =>
      TransferEngine(
        repository: repository,
        store: store,
        config: config,
      );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('puter_transfer_test');
    transport = FakeTransport(
      tree: <String, List<RemoteNode>>{
        '/': <RemoteNode>[],
        '/Documents': <RemoteNode>[],
      },
    );
    cache = InMemoryNodeCache();
    store = InMemoryTransferStore();
    repository = FileRepository(transport: transport, cache: cache);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Wait until [predicate] holds, or give up.
  ///
  /// The engine is deliberately event-driven with no polling loop, so a test
  /// has to wait on the stream rather than on a sleep of guessed length.
  Future<void> waitFor(
    TransferEngine engine,
    bool Function(List<TransferTask> tasks) predicate, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (predicate(engine.snapshot)) return;
    final completer = Completer<void>();
    late StreamSubscription<List<TransferTask>> subscription;
    subscription = engine.updates.listen((List<TransferTask> tasks) {
      if (predicate(tasks) && !completer.isCompleted) completer.complete();
    });
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      fail('Timed out waiting. Queue: ${engine.snapshot}');
    } finally {
      await subscription.cancel();
    }
  }

  group('queueing', () {
    test('an upload runs and completes', () async {
      final engine = buildEngine();
      await engine.restore();

      final task = await engine.enqueueUpload(
        localPath: '/tmp/photo.jpg',
        remotePath: '/Documents/photo.jpg',
        sizeBytes: 100,
      );

      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks
            .any((TransferTask t) => t.id == task.id && t.isFinished),
      );

      final finished =
          engine.snapshot.firstWhere((TransferTask t) => t.id == task.id);
      expect(finished.state, TransferState.completed);
      expect(finished.attempts, 1);
      expect(transport.uploads, hasLength(1));
      await engine.dispose();
    });

    test('an upload reconciles the folder it landed in', () async {
      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: '/tmp/photo.jpg',
        remotePath: '/Documents/photo.jpg',
        sizeBytes: 100,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      expect(
        transport.listCalls,
        contains('/Documents'),
        reason: 'the browser must see a new file without a manual refresh',
      );
      await engine.dispose();
    });

    test('progress is reported on the task', () async {
      final engine = buildEngine();
      await engine.restore();

      final progress = <int>[];
      transport.onUpload = (UploadRequest request) async {
        request.onProgress?.call(50, 200);
        request.onProgress?.call(200, 200);
      };

      final task = await engine.enqueueUpload(
        localPath: '/tmp/big.bin',
        remotePath: '/Documents/big.bin',
        sizeBytes: 200,
      );
      engine.updates.listen((List<TransferTask> tasks) {
        for (final TransferTask t in tasks) {
          if (t.id == task.id) progress.add(t.bytesDone);
        }
      });

      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.any((TransferTask t) => t.id == task.id && t.isFinished),
      );

      expect(progress, contains(200));
      await engine.dispose();
    });
  });

  group('durability', () {
    test('restore demotes a task that was running when the process died',
        () async {
      // Simulate a row left behind by a killed process.
      await store.save(
        TransferTask(
          id: 'resumed',
          direction: TransferDirection.upload,
          remotePath: '/Documents/half.bin',
          localPath: '/tmp/half.bin',
          totalBytes: 1000,
          bytesDone: 400,
          state: TransferState.running,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final engine = buildEngine();
      final states = <TransferState>[];
      final subscription = engine.updates.listen((List<TransferTask> tasks) {
        for (final TransferTask t in tasks) {
          if (t.id == 'resumed') states.add(t.state);
        }
      });
      addTearDown(subscription.cancel);

      // Hold the transfer open so the state sequence can be observed rather
      // than raced past.
      final hold = Completer<void>();
      transport.onUpload = (UploadRequest request) => hold.future;

      await engine.restore();
      await Future<void>.delayed(Duration.zero);

      expect(
        states.first,
        TransferState.queued,
        reason: 'nothing is running after a restart, and saying otherwise '
            'would leave the row stuck forever',
      );
      expect(engine.snapshot.single.bytesDone, 400);

      hold.complete();
      await engine.dispose();
    });

    test('a completed task is not re-run after a restart', () async {
      await store.save(
        TransferTask(
          id: 'done',
          direction: TransferDirection.download,
          remotePath: '/Documents/report.pdf',
          localPath: '/tmp/report.pdf',
          totalBytes: 10,
          bytesDone: 10,
          state: TransferState.completed,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final engine = buildEngine();
      await engine.restore();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(transport.downloads, isEmpty);
      await engine.dispose();
    });

    test('an unfinished queue resumes on restore', () async {
      await store.save(
        TransferTask(
          id: 'pending',
          direction: TransferDirection.download,
          remotePath: '/Documents/report.pdf',
          localPath: '/tmp/report.pdf',
          totalBytes: 10,
          state: TransferState.queued,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final engine = buildEngine();
      await engine.restore();
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      expect(transport.downloads, hasLength(1));
      await engine.dispose();
    });
  });

  group('failure policy', () {
    test('a quota rejection blocks instead of retrying', () async {
      transport.uploadError = const PuterException(
        PuterErrorKind.storageLimitReached,
        'Storage is full.',
        statusCode: 413,
        code: 'storage_limit_reached',
      );

      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: '/tmp/big.bin',
        remotePath: '/Documents/big.bin',
        sizeBytes: 100,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      final task = engine.snapshot.single;
      expect(task.state, TransferState.blocked);
      expect(
        task.attempts,
        1,
        reason: 'retrying a full quota changes nothing — it must not be tried',
      );
      expect(transport.uploads, hasLength(1));
      await engine.dispose();
    });

    test('a revoked token blocks', () async {
      transport.uploadError = const PuterException(
        PuterErrorKind.authInvalid,
        'Token rejected.',
        statusCode: 401,
      );

      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: '/tmp/a.bin',
        remotePath: '/Documents/a.bin',
        sizeBytes: 10,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      expect(engine.snapshot.single.state, TransferState.blocked);
      await engine.dispose();
    });

    test('a retryable error consumes the budget, then fails', () async {
      transport.uploadError = const PuterException(
        PuterErrorKind.network,
        'Connection reset.',
      );

      // One attempt means the first failure exhausts the budget, so the test
      // does not have to wait out a real backoff.
      final engine = buildEngine(
        config: const AppConfig(maxRetryAttempts: 1),
      );
      await engine.restore();

      await engine.enqueueUpload(
        localPath: '/tmp/a.bin',
        remotePath: '/Documents/a.bin',
        sizeBytes: 10,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      final task = engine.snapshot.single;
      expect(task.state, TransferState.failed);
      expect(task.lastError, isNotNull);
      await engine.dispose();
    });

    test('retry puts a failed task back in the queue and clears its error',
        () async {
      transport.uploadError = const PuterException(
        PuterErrorKind.network,
        'Connection reset.',
      );

      final engine = buildEngine(
        config: const AppConfig(maxRetryAttempts: 1),
      );
      await engine.restore();

      final queued = await engine.enqueueUpload(
        localPath: '/tmp/a.bin',
        remotePath: '/Documents/a.bin',
        sizeBytes: 10,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );
      expect(engine.snapshot.single.state, TransferState.failed);

      // The server recovers, and the user retries.
      transport.uploadError = null;
      engine.retry(queued.id);

      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.any((TransferTask t) => t.id == queued.id && t.isFinished),
      );

      final retried =
          engine.snapshot.firstWhere((TransferTask t) => t.id == queued.id);
      expect(retried.state, TransferState.completed);
      expect(retried.lastError, isNull);
      await engine.dispose();
    });

    test('a blocked upload does not stop the others', () async {
      // The ADR-0004 case: one file fails on quota, the rest must finish, and
      // the failure must be attributed to the right file.
      final engine = buildEngine();
      await engine.restore();

      transport.onUpload = (UploadRequest request) async {
        if (request.remotePath.contains('big')) {
          throw const PuterException(
            PuterErrorKind.storageLimitReached,
            'Storage is full.',
            statusCode: 413,
          );
        }
        request.onProgress?.call(10, 10);
      };

      await engine.enqueueUpload(
        localPath: '/tmp/small.bin',
        remotePath: '/Documents/small.bin',
        sizeBytes: 10,
      );
      await engine.enqueueUpload(
        localPath: '/tmp/big.bin',
        remotePath: '/Documents/big.bin',
        sizeBytes: 10,
      );

      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.every((TransferTask t) => t.isFinished),
      );

      final small = engine.snapshot.firstWhere(
        (TransferTask t) => t.remotePath.endsWith('small.bin'),
      );
      final big = engine.snapshot.firstWhere(
        (TransferTask t) => t.remotePath.endsWith('big.bin'),
      );

      expect(small.state, TransferState.completed);
      expect(big.state, TransferState.blocked);
      await engine.dispose();
    });
  });

  group('cancellation', () {
    test('cancelling a running upload marks it cancelled, not failed', () async {
      final engine = buildEngine();
      await engine.restore();

      final started = Completer<void>();
      final hold = Completer<void>();
      transport.onUpload = (UploadRequest request) async {
        started.complete();
        // Stand in for a slow transfer: the engine must interrupt this.
        await Future.any(<Future<void>>[
          request.cancelSignal ?? Completer<void>().future,
          hold.future,
        ]);
        if (request.cancelSignal != null) {
          await request.cancelSignal;
          throw const TransferCancelled();
        }
      };

      final task = await engine.enqueueUpload(
        localPath: '/tmp/big.bin',
        remotePath: '/Documents/big.bin',
        sizeBytes: 100,
      );

      await started.future;
      engine.cancel(task.id);

      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      final cancelled =
          engine.snapshot.firstWhere((TransferTask t) => t.id == task.id);
      expect(cancelled.state, TransferState.cancelled);
      expect(
        cancelled.isFinished,
        isTrue,
        reason: 'a cancellation the user asked for is not a failure',
      );
      await engine.dispose();
    });

    test('pause then resume runs the task again', () async {
      final engine = buildEngine();
      await engine.restore();

      final started = Completer<void>();
      // The first attempt is interruptible; after the pause it completes.
      var attempt = 0;
      transport.onUpload = (UploadRequest request) async {
        attempt++;
        if (attempt == 1) {
          started.complete();
          await request.cancelSignal;
          throw const TransferCancelled();
        }
        request.onProgress?.call(100, 100);
      };

      final task = await engine.enqueueUpload(
        localPath: '/tmp/big.bin',
        remotePath: '/Documents/big.bin',
        sizeBytes: 100,
      );
      await started.future;

      engine.pause(task.id);
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks
            .any((TransferTask t) => t.id == task.id && t.state == TransferState.paused),
      );

      engine.resume(task.id);
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks
            .any((TransferTask t) => t.id == task.id && t.state == TransferState.completed),
      );

      expect(transport.uploads, hasLength(2));
      await engine.dispose();
    });
  });

  group('concurrency', () {
    test('never runs more transfers at once than the cap allows', () async {
      final engine = buildEngine(
        config: const AppConfig(
          maxConcurrentTransfers: 2,
          maxConcurrentRequests: 5,
        ),
      );
      await engine.restore();

      var inFlight = 0;
      var peak = 0;
      final release = Completer<void>();

      transport.onUpload = (UploadRequest request) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await release.future;
        inFlight--;
      };

      for (var i = 0; i < 6; i++) {
        await engine.enqueueUpload(
          localPath: '/tmp/f$i.bin',
          remotePath: '/Documents/f$i.bin',
          sizeBytes: 10,
        );
      }

      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.where((TransferTask t) => t.isActive).length >= 2,
      );

      expect(
        peak,
        lessThanOrEqualTo(2),
        reason: 'WebDAV allows 10 concurrent for the whole network',
      );

      release.complete();
      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.every((TransferTask t) => t.isFinished),
        timeout: const Duration(seconds: 10),
      );
      expect(transport.uploads, hasLength(6));
      await engine.dispose();
    });
  });

  group('quota pre-flight', () {
    test('an upload that cannot fit is refused before any bytes move', () async {
      transport.capabilities = const TransportCapabilities(canReportUsage: true);
      transport.usageResult = const StorageUsage(
        capacityBytes: 100,
        usedBytes: 95,
      );

      // A real file, because the pre-flight measures what is actually on disk
      // rather than trusting the size the picker reported — that number can be
      // stale, and the file is the thing being sent.
      final file = File(p.join(tempDir.path, 'huge.bin'))
        ..writeAsBytesSync(List<int>.filled(50, 0));

      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: file.path,
        remotePath: '/Documents/huge.bin',
        sizeBytes: 50,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      expect(engine.snapshot.single.state, TransferState.blocked);
      expect(
        transport.uploads,
        isEmpty,
        reason: 'the whole point is not spending the upload at all',
      );
      await engine.dispose();
    });

    test('an upload that fits proceeds', () async {
      transport.capabilities = const TransportCapabilities(canReportUsage: true);
      transport.usageResult = const StorageUsage(
        capacityBytes: 1000,
        usedBytes: 10,
      );

      final file = File(p.join(tempDir.path, 'small.bin'))
        ..writeAsBytesSync(List<int>.filled(50, 0));

      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: file.path,
        remotePath: '/Documents/small.bin',
        sizeBytes: 50,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      expect(engine.snapshot.single.state, TransferState.completed);
      await engine.dispose();
    });

    test('an unreadable quota does not block the upload', () async {
      // canReportUsage stays false, so usage() throws `unsupported`.
      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: '/tmp/small.bin',
        remotePath: '/Documents/small.bin',
        sizeBytes: 50,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) => tasks.every((TransferTask t) => t.isFinished),
      );

      expect(engine.snapshot.single.state, TransferState.completed);
      await engine.dispose();
    });

    test('a quota read that fails unexpectedly still lets the upload through',
        () async {
      // A transport can leak something that is not a PuterException — a raw
      // parse error from a body that was not the XML it expected. Quota is
      // advisory, so the pre-flight must not be able to fail a transfer. Note
      // that only uploads consult it, which is exactly the shape of "downloads
      // work, uploads do not".
      transport.capabilities =
          const TransportCapabilities(canReportUsage: true);
      transport.usageError = const FormatException('body was not XML');

      final engine = buildEngine();
      await engine.restore();

      await engine.enqueueUpload(
        localPath: '/tmp/small.bin',
        remotePath: '/Documents/small.bin',
        sizeBytes: 50,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.every((TransferTask t) => t.isFinished),
      );

      expect(
        engine.snapshot.single.state,
        TransferState.completed,
        reason: 'a failed quota read must not fail the transfer',
      );
      expect(transport.uploads, hasLength(1));
      await engine.dispose();
    });
  });

  group('housekeeping', () {
    test('clearFinished removes only finished tasks', () async {
      final engine = buildEngine();
      await engine.restore();

      final done = await engine.enqueueUpload(
        localPath: '/tmp/a.bin',
        remotePath: '/Documents/a.bin',
        sizeBytes: 10,
      );
      await waitFor(
        engine,
        (List<TransferTask> tasks) =>
            tasks.any((TransferTask t) => t.id == done.id && t.isFinished),
      );

      await engine.clearFinished();

      expect(engine.snapshot, isEmpty);
      expect(await store.load(), isEmpty, reason: 'persisted rows must go too');
      await engine.dispose();
    });

    test('dismiss removes one task and its persisted row', () async {
      final engine = buildEngine();
      await engine.restore();

      final task = await engine.enqueueUpload(
        localPath: '/tmp/a.bin',
        remotePath: '/Documents/a.bin',
        sizeBytes: 10,
      );
      await engine.dismiss(task.id);

      expect(engine.snapshot, isEmpty);
      expect(await store.load(), isEmpty);
      await engine.dispose();
    });
  });
}
