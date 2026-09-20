/// Persistence for the transfer queue.
///
/// ADR 0004 makes every transfer a per-file task with its own state, precisely
/// because Puter's write path is not atomic. That design only pays off if the
/// state outlives the process: Android kills backgrounded apps routinely, and
/// a queue that lives only in memory would lose the fact that a 2 GB upload
/// got 1.7 GB in.
///
/// The store is an interface so the engine can be driven in tests without a
/// database — the same reason [NodeCache] has one.
library;

import 'package:drift/drift.dart';

import '../../domain/entities/remote_node.dart';
import '../database/app_database.dart';

/// Reads and writes [TransferTask]s.
abstract class TransferStore {
  /// Every persisted task, oldest first.
  Future<List<TransferTask>> load();

  /// Insert or update one task.
  Future<void> save(TransferTask task);

  /// Remove one task.
  Future<void> remove(String id);

  /// Remove every task whose state is in [states].
  Future<void> removeInStates(Set<TransferState> states);
}

/// [TransferStore] backed by the Drift database.
class DriftTransferStore implements TransferStore {
  DriftTransferStore(this._db);

  final AppDatabase _db;

  @override
  Future<List<TransferTask>> load() async {
    final rows = await _db.allTransferTasks();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<void> save(TransferTask task) =>
      _db.upsertTransferTask(_toCompanion(task));

  @override
  Future<void> remove(String id) => _db.deleteTransferTask(id);

  @override
  Future<void> removeInStates(Set<TransferState> states) =>
      _db.deleteTransferTasksInStates(
        states.map((state) => state.name).toList(growable: false),
      );

  // ------------------------------------------------------------------ mapping

  static TransferTask _toDomain(TransferTaskRow row) => TransferTask(
        id: row.id,
        direction: _directionFrom(row.direction),
        remotePath: row.remotePath,
        localPath: row.localPath,
        totalBytes: row.totalBytes,
        bytesDone: row.bytesDone,
        state: _stateFrom(row.state),
        attempts: row.attempts,
        lastError: row.lastError,
        createdAt: row.createdAt,
      );

  static TransferTasksCompanion _toCompanion(TransferTask task) =>
      TransferTasksCompanion.insert(
        id: task.id,
        direction: task.direction.name,
        remotePath: task.remotePath,
        localPath: task.localPath,
        totalBytes: Value<int>(task.totalBytes),
        bytesDone: Value<int>(task.bytesDone),
        state: task.state.name,
        attempts: Value<int>(task.attempts),
        lastError: Value<String?>(task.lastError),
        createdAt: Value<DateTime?>(task.createdAt),
      );

  /// Unknown values fall back rather than throwing.
  ///
  /// A row written by a newer build, or a hand-edited database, must not take
  /// out the whole queue on startup. Resuming as `queued` is the safe recovery:
  /// the task is retried, and a file that was already complete simply gets
  /// re-verified.
  static TransferDirection _directionFrom(String value) =>
      value == TransferDirection.download.name
          ? TransferDirection.download
          : TransferDirection.upload;

  static TransferState _stateFrom(String value) {
    for (final state in TransferState.values) {
      if (state.name == value) return state;
    }
    return TransferState.queued;
  }
}

/// Volatile [TransferStore] for tests, and for a database that failed to open.
class InMemoryTransferStore implements TransferStore {
  final Map<String, TransferTask> _tasks = <String, TransferTask>{};

  @override
  Future<List<TransferTask>> load() async {
    final tasks = _tasks.values.toList()
      ..sort((a, b) {
        final left = a.createdAt;
        final right = b.createdAt;
        if (left == null || right == null) return 0;
        return left.compareTo(right);
      });
    return tasks;
  }

  @override
  Future<void> save(TransferTask task) async => _tasks[task.id] = task;

  @override
  Future<void> remove(String id) async => _tasks.remove(id);

  @override
  Future<void> removeInStates(Set<TransferState> states) async =>
      _tasks.removeWhere((_, task) => states.contains(task.state));
}
