/// The transfer engine — per-file tasks, persistent, resumable.
///
/// This is the phase the product is judged on, and ADR 0004 is why it is shaped
/// the way it is. Puter's write path is **not atomic**: a batch that fails
/// halfway leaves the earlier files written and rolls nothing back. So a
/// transfer is never "a batch"; it is one file with its own state, its own
/// retry budget and its own error. That is what makes "file 7 of 12 failed
/// because the quota filled" a sentence the app can actually say.
///
/// Three properties the tests hold it to:
///
/// * **The queue survives the process.** Android kills backgrounded apps
///   routinely. A task that was `running` when the process died is recovered as
///   `queued`, because nothing is running any more and saying otherwise would
///   leave a permanently stuck row.
/// * **Resume comes from disk.** For downloads the transport derives its offset
///   from the `.part` staging file, never from a number this engine remembered.
///   A remembered offset that drifts writes at the wrong position and produces a
///   file that looks fine and is not.
/// * **A permanent failure is not retried.** `413`, `402` and a revoked token
///   are classified `blocked` and stop dead. Retrying them burns the request
///   budget and teaches the user that the app is broken rather than their
///   account.
library;

import 'dart:async';
import 'dart:io';

import '../../core/config/app_config.dart';
import '../../core/error/error_presenter.dart';
import '../../core/error/puter_exception.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import '../platform/device_files.dart';
import '../repositories/file_repository.dart';
import '../transport/puter_transport.dart';
import 'transfer_store.dart';

/// Why a transfer stopped, in a form the UI can act on.
enum TransferStopReason {
  /// The user asked for it. Not a failure.
  cancelled,

  /// Retryable, and the retry budget is spent.
  retriesExhausted,

  /// Permanent. The user must change something.
  blocked,
}

/// Runs the transfer queue.
class TransferEngine {
  TransferEngine({
    required FileRepository repository,
    required TransferStore store,
    AppConfig config = const AppConfig(),
    DateTime Function()? clock,
    DeviceFileService deviceFiles = const UnavailableDeviceFiles(),
  })  : _repository = repository,
        _store = store,
        _config = config,
        _clock = clock ?? DateTime.now,
        _deviceFiles = deviceFiles;

  final FileRepository _repository;
  final TransferStore _store;
  final AppConfig _config;
  final DateTime Function() _clock;

  /// Used to release the staged copy of an uploaded file once it has landed.
  ///
  /// The engine owns the lifecycle of what it transfers, but only the platform
  /// layer knows which files the app staged itself — and deleting a file the
  /// user chose from elsewhere would be catastrophic. So the decision is
  /// delegated rather than guessed at.
  final DeviceFileService _deviceFiles;

  final Map<String, TransferTask> _tasks = <String, TransferTask>{};
  final Map<String, _ActiveTransfer> _active = <String, _ActiveTransfer>{};
  final StreamController<List<TransferTask>> _updates =
      StreamController<List<TransferTask>>.broadcast();
  bool _disposed = false;

  /// The queue, ordered oldest first. Emitted on every change.
  Stream<List<TransferTask>> get updates => _updates.stream;

  /// The current queue.
  List<TransferTask> get snapshot => _ordered();

  /// How many tasks are moving bytes right now.
  int get activeCount => _active.length;

  /// Whether anything is still in flight or waiting.
  bool get hasWork =>
      _tasks.values.any((task) => !task.isFinished);

  /// Reload the queue from storage and start anything that was left unfinished.
  ///
  /// Called once, after sign-in. Tasks persisted as `running` are demoted to
  /// `queued`: the process that was running them no longer exists, and a row
  /// that claims to be running would never be picked up again.
  Future<void> restore() async {
    final persisted = await _store.load();
    _tasks.clear();
    for (final task in persisted) {
      final recovered = switch (task.state) {
        TransferState.running => task.copyWith(
            state: TransferState.queued,
            clearError: true,
          ),
        _ => task,
      };
      _tasks[recovered.id] = recovered;
    }
    _emit();
    _pump();
  }

  /// Queue a file to upload.
  ///
  /// Returns immediately; the transfer runs in the background and reports
  /// through [updates].
  Future<TransferTask> enqueueUpload({
    required String localPath,
    required String remotePath,
    required int sizeBytes,
    bool overwrite = false,
  }) async {
    final task = TransferTask(
      id: _newId(),
      direction: TransferDirection.upload,
      remotePath: RemotePath.normalise(remotePath),
      // The overwrite choice travels with the task rather than being read at
      // run time, so a retry reproduces what the user actually asked for.
      localPath: overwrite ? '$localPath\u0000overwrite' : localPath,
      totalBytes: sizeBytes,
      state: TransferState.queued,
      createdAt: _clock(),
    );
    await _admit(task);
    return task;
  }

  /// Queue a file to download.
  ///
  /// [sizeBytes] may be `0` when the size is not yet known; the transport
  /// reports the real total once the response headers arrive.
  Future<TransferTask> enqueueDownload({
    required String remotePath,
    required String localPath,
    int sizeBytes = 0,
  }) async {
    final task = TransferTask(
      id: _newId(),
      direction: TransferDirection.download,
      remotePath: RemotePath.normalise(remotePath),
      localPath: localPath,
      totalBytes: sizeBytes,
      state: TransferState.queued,
      createdAt: _clock(),
    );
    await _admit(task);
    return task;
  }

  /// Cancel a task. Safe on a task that is queued, running or finished.
  void cancel(String id) {
    final task = _tasks[id];
    if (task == null) return;

    final active = _active[id];
    if (active != null) {
      // Ask the transport to stop; `_run` sees TransferCancelled and records
      // the cancellation itself, so the state is set in exactly one place.
      active.requestStop(TransferState.cancelled);
    } else {
      _update(task.copyWith(state: TransferState.cancelled));
    }
  }

  /// Pause a running task.
  ///
  /// Pausing an upload restarts it from zero on resume, because WebDAV `PUT`
  /// with `Content-Range` is not confirmed to work (see
  /// [TransportCapabilities.canResumeUpload]). Pausing a download resumes from
  /// the staging file. The UI says which is which rather than implying both
  /// are free.
  void pause(String id) {
    final task = _tasks[id];
    if (task == null || task.state != TransferState.running) return;
    _active[id]?.requestStop(TransferState.paused);
  }

  /// Put a paused, failed or cancelled task back in the queue.
  void resume(String id) {
    final task = _tasks[id];
    if (task == null || task.state == TransferState.running) return;
    if (task.state == TransferState.completed) return;
    _update(
      task.copyWith(
        state: TransferState.queued,
        clearError: true,
      ),
    );
    _pump();
  }

  /// Retry a failed task, resetting its attempt budget.
  void retry(String id) {
    final task = _tasks[id];
    if (task == null) return;
    _update(
      task.copyWith(
        state: TransferState.queued,
        attempts: 0,
        clearError: true,
      ),
    );
    _pump();
  }

  /// Retry an upload that was refused because the name is already taken, this
  /// time replacing what is there.
  ///
  /// The one thing the previous version could not do at all: a name collision
  /// was a dead end that told the user to choose a different name, with no way
  /// to say "no, replace it".
  void replaceExisting(String id) {
    final task = _tasks[id];
    if (task == null || task.direction != TransferDirection.upload) return;
    _update(
      task.copyWith(
        state: TransferState.queued,
        attempts: 0,
        overwrite: true,
        clearError: true,
      ),
    );
    _pump();
  }

  /// Remove one task from the list, cancelling it first if it is still going.
  Future<void> dismiss(String id) async {
    final TransferTask? task = _tasks[id];
    cancel(id);
    _tasks.remove(id);
    _active.remove(id);
    await _store.remove(id);
    // An abandoned upload's staged copy is dead weight from here on.
    if (task != null && task.direction == TransferDirection.upload) {
      unawaited(_deviceFiles.discardStagedUpload(task.localPath));
    }
    _emit();
  }

  /// Remove every finished task.
  Future<void> clearFinished() async {
    const finished = <TransferState>{
      TransferState.completed,
      TransferState.cancelled,
      TransferState.blocked,
      TransferState.failed,
    };
    _tasks.removeWhere((id, task) => finished.contains(task.state));
    await _store.removeInStates(finished);
    _emit();
  }

  /// Stop everything and release the stream. Called on sign-out.
  Future<void> dispose() async {
    _disposed = true;
    for (final active in _active.values) {
      active.requestStop(TransferState.cancelled);
    }
    _active.clear();
    await _updates.close();
  }

  // ------------------------------------------------------------------ private

  Future<void> _admit(TransferTask task) async {
    _tasks[task.id] = task;
    await _store.save(task);
    _emit();
    _pump();
  }

  /// Start queued tasks until the concurrency cap is reached.
  ///
  /// The cap is [AppConfig.maxConcurrentTransfers], itself constrained to stay
  /// under [AppConfig.maxConcurrentRequests] — every transfer is also a
  /// request, and WebDAV allows only 10 concurrent for the whole network
  /// regardless of how many files the user started.
  void _pump() {
    if (_disposed) return;
    final cap = _config.maxConcurrentTransfers < _config.maxConcurrentRequests
        ? _config.maxConcurrentTransfers
        : _config.maxConcurrentRequests;

    if (_active.length >= cap) return;

    final now = _clock();
    for (final task in _ordered()) {
      if (_active.length >= cap) return;
      if (task.state != TransferState.queued) continue;
      final retryAt = _retryAt(task.id);
      if (retryAt != null && retryAt.isAfter(now)) continue;
      unawaited(_run(task.id));
    }
  }

  /// Run one task to completion, classifying what happened.
  Future<void> _run(String id) async {
    final task = _tasks[id];
    if (task == null || _disposed) return;

    final active = _ActiveTransfer();
    _active[id] = active;
    _setRetryAt(id, null);

    var current = _update(
      task.copyWith(
        state: TransferState.running,
        attempts: task.attempts + 1,
        clearError: true,
      ),
    );

    try {
      await _transfer(current, active);
      if (active.stopState != null) {
        // The transport returned normally, but a stop was requested while it
        // was finishing. Honour the user's intent over the result.
        current = _update(current.copyWith(state: active.stopState!));
        return;
      }
      current = _update(
        current.copyWith(
          state: TransferState.completed,
          bytesDone: current.totalBytes,
          clearError: true,
        ),
      );
      await _afterSuccess(current);
    } on TransferCancelled {
      final stop = active.stopState ?? TransferState.cancelled;
      _update(current.copyWith(state: stop));
    } on PuterException catch (error) {
      if (active.stopState != null) {
        _update(current.copyWith(state: active.stopState!));
        return;
      }
      await _fail(current, error);
    } catch (error) {
      if (active.stopState != null) {
        _update(current.copyWith(state: active.stopState!));
        return;
      }
      await _fail(
        current,
        PuterException(
          PuterErrorKind.unknown,
          'Transfer failed: $error',
          path: current.remotePath,
          cause: error,
        ),
      );
    } finally {
      _active.remove(id);
      if (!_disposed) _pump();
    }
  }

  /// Perform the transfer itself.
  Future<void> _transfer(TransferTask task, _ActiveTransfer active) async {
    final transport = _repository.transport;

    switch (task.direction) {
      case TransferDirection.upload:
        final String localPath = task.localPath;
        final int source = await _lengthOf(localPath);

        // Pre-flight the quota. The server enforces it anyway and answers 413,
        // but checking first means a large unwanted upload is refused before a
        // single byte crosses the network — which matters when the account is
        // metered.
        final usage = await _tryUsage(transport);
        if (usage != null && !usage.canFit(source)) {
          throw const PuterException(
            PuterErrorKind.storageLimitReached,
            'Not enough space in your Puter account for this file.',
            code: 'storage_limit_reached',
          );
        }

        await transport.upload(
          UploadRequest(
            localPath: localPath,
            remotePath: task.remotePath,
            overwrite: task.overwrite,
            onProgress: (done, total) => _reportProgress(
              task.id,
              done,
              total > 0 ? total : source,
            ),
            cancelSignal: active.signal,
          ),
        );

      case TransferDirection.download:
        await transport.download(
          DownloadRequest(
            remotePath: task.remotePath,
            localPath: task.localPath,
            onProgress: (done, total) => _reportProgress(
              task.id,
              done,
              total > 0 ? total : task.totalBytes,
            ),
            cancelSignal: active.signal,
          ),
        );
    }
  }

  /// Classify a failure and decide whether it is worth retrying.
  Future<void> _fail(TransferTask task, PuterException error) async {
    final presentation = ErrorPresenter.describe(error);

    // Permanent conditions first. Retrying a full quota or a revoked token
    // changes nothing, and each attempt spends request budget the browse UI
    // needs.
    if (error.requiresUserAction || !error.isRetryable) {
      _update(
        task.copyWith(
          state: TransferState.blocked,
          lastError: presentation.shortMessage,
        ),
      );
      return;
    }

    if (task.attempts >= _config.maxRetryAttempts) {
      _update(
        task.copyWith(
          state: TransferState.failed,
          lastError: '${presentation.shortMessage} '
              'Gave up after ${task.attempts} attempts.',
        ),
      );
      return;
    }

    // Retryable and within budget. Back off, then let the pump pick it up.
    final delay = Duration(
      milliseconds: (500 * (1 << (task.attempts - 1).clamp(0, 6))).clamp(500, 60000),
    );
    _update(
      task.copyWith(
        state: TransferState.queued,
        lastError: '${presentation.shortMessage} '
            'Retrying in ${delay.inSeconds}s.',
      ),
    );
    _setRetryAt(task.id, _clock().add(delay));
    unawaited(
      Future<void>.delayed(delay, () {
        if (!_disposed) _pump();
      }),
    );
  }

  /// Bookkeeping for a transfer that landed.
  ///
  /// The upload path is the important one: the browser must show the new file
  /// without the user pulling to refresh, and the index is the only thing that
  /// can make that happen.
  Future<void> _afterSuccess(TransferTask task) async {
    if (task.direction != TransferDirection.upload) return;
    final parent = RemotePath.parent(task.remotePath) ?? RemotePath.root;
    await _repository.reconcile(parent);

    // The staged copy has done its job. Releasing it here is what keeps a long
    // session of uploading from filling the device.
    await _deviceFiles.discardStagedUpload(task.localPath);
  }

  // ---------------------------------------------------------- progress plumbing

  final Map<String, DateTime> _lastEmit = <String, DateTime>{};

  void _reportProgress(String id, int done, int total) {
    final task = _tasks[id];
    if (task == null) return;

    // Progress arrives once per streamed chunk — tens of thousands of times for
    // a large file. Coalescing to ~8 frames a second keeps the list smooth
    // without dropping the final value, which is what the user reads.
    final now = _clock();
    final previous = _lastEmit[id];
    final isFinal = total > 0 && done >= total;
    if (!isFinal &&
        previous != null &&
        now.difference(previous) < const Duration(milliseconds: 120)) {
      _tasks[id] = task.copyWith(bytesDone: done, totalBytes: total);
      return;
    }
    _lastEmit[id] = now;
    _update(task.copyWith(bytesDone: done, totalBytes: total));
  }

  final Map<String, DateTime> _retrySchedule = <String, DateTime>{};

  DateTime? _retryAt(String id) => _retrySchedule[id];
  void _setRetryAt(String id, DateTime? value) {
    if (value == null) {
      _retrySchedule.remove(id);
    } else {
      _retrySchedule[id] = value;
    }
  }

  // ---------------------------------------------------------------- small stuff

  TransferTask _update(TransferTask task) {
    _tasks[task.id] = task;
    unawaited(_store.save(task));
    _emit();
    return task;
  }

  void _emit() {
    if (_disposed || _updates.isClosed) return;
    _updates.add(_ordered());
  }

  List<TransferTask> _ordered() {
    final tasks = _tasks.values.toList()
      ..sort((a, b) {
        final left = a.createdAt;
        final right = b.createdAt;
        if (left == null || right == null) return 0;
        return left.compareTo(right);
      });
    return tasks;
  }

  Future<int> _lengthOf(String path) async {
    try {
      final File file = File(path);
      return file.existsSync() ? file.lengthSync() : 0;
    } on Object {
      return 0;
    }
  }

  /// Read the quota, or `null` when it cannot be read.
  ///
  /// Catches **everything**, not just [PuterException]. Quota is advisory here:
  /// the server enforces its own limit and answers `413`, which is a perfectly
  /// clear answer that blocks exactly one task. Letting any failure of this
  /// advisory read fail the transfer is how "uploads do not work but downloads
  /// do" happens, because only uploads call it.
  Future<StorageUsage?> _tryUsage(PuterTransport transport) async {
    if (!transport.capabilities.canReportUsage) return null;
    try {
      return await transport.usage();
    } on Object {
      return null;
    }
  }

  static int _sequence = 0;
  static String _newId() =>
      't${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
}

/// Cancellation channel for one running task.
class _ActiveTransfer {
  final Completer<void> _stopped = Completer<void>();

  /// Why the stop was requested, or `null` if it was not.
  TransferState? stopState;

  Future<void> get signal => _stopped.future;

  void requestStop(TransferState state) {
    stopState = state;
    if (!_stopped.isCompleted) _stopped.complete();
  }
}
