/// Domain entities.
///
/// Pure Dart. No Flutter, no HTTP, no Puter protocol types. The domain layer
/// describes *what* the app manipulates; the transport layer describes *how*
/// those things travel.
///
/// Staying Flutter-free keeps this layer testable with `dart test` and usable
/// from a future CLI or desktop shell without dragging in the framework.
library;

/// A file or directory in the remote Puter filesystem.
class RemoteNode {
  const RemoteNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.mimeType,
    this.etag,
    this.isShared,
    this.indexedAt,
  });

  /// Absolute path, rooted at the user's home rather than the app sandbox, so
  /// the same folders appear in Puter's own desktop UI.
  final String path;

  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final String? mimeType;

  /// Server-side version marker, used to skip no-op index writes.
  final String? etag;

  /// `true` when shared by the user, `false` when not, `null` when the item
  /// belongs to someone else. Puter reports exactly this tri-state.
  final bool? isShared;

  /// When this row was last confirmed against the server.
  final DateTime? indexedAt;

  /// Parent path, or `null` at the root.
  String? get parentPath {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf('/');
    if (index <= 0) return null;
    return trimmed.substring(0, index);
  }

  /// File extension without the dot, lowercased. Empty when there is none.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  RemoteNode copyWith({
    String? path,
    String? name,
    bool? isDirectory,
    int? sizeBytes,
    DateTime? modifiedAt,
    String? mimeType,
    String? etag,
    bool? isShared,
    DateTime? indexedAt,
  }) {
    return RemoteNode(
      path: path ?? this.path,
      name: name ?? this.name,
      isDirectory: isDirectory ?? this.isDirectory,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      mimeType: mimeType ?? this.mimeType,
      etag: etag ?? this.etag,
      isShared: isShared ?? this.isShared,
      indexedAt: indexedAt ?? this.indexedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteNode &&
      other.path == path &&
      other.sizeBytes == sizeBytes &&
      other.etag == etag &&
      other.modifiedAt == modifiedAt;

  @override
  int get hashCode => Object.hash(path, sizeBytes, etag, modifiedAt);

  @override
  String toString() =>
      'RemoteNode($path, ${isDirectory ? 'dir' : '$sizeBytes bytes'})';
}

/// A page of directory entries.
///
/// Puter's `readdir` returns a cursor when more pages exist; the cursor pins
/// the sort order, so later pages must not change [ListRequest.sortBy] or
/// [ListRequest.sortOrder].
class RemoteNodePage {
  const RemoteNodePage({
    required this.items,
    this.cursor,
    this.total,
    this.failures = const <NodeFailure>[],
  });

  final List<RemoteNode> items;

  /// Present while more pages exist. Pass to the next request verbatim.
  final String? cursor;

  /// Total entry count, when the request asked for it.
  final int? total;

  /// Entries the server refused to describe.
  ///
  /// WebDAV answers `PROPFIND` with `207 Multistatus`, which is **not** blanket
  /// success: individual entries can fail while the response as a whole
  /// succeeds. Dropping those entries silently would make files invisible with
  /// no explanation, so they are carried up and surfaced in the UI.
  final List<NodeFailure> failures;

  bool get hasMore => cursor != null;

  /// True when the listing is incomplete — some entries could not be read.
  bool get isPartial => failures.isNotEmpty;

  @override
  String toString() => 'RemoteNodePage(${items.length} items'
      '${failures.isEmpty ? '' : ', ${failures.length} failed'}'
      ', hasMore=$hasMore)';
}

/// An entry the server returned in a multistatus response but refused to
/// describe, so it could not be turned into a [RemoteNode].
class NodeFailure {
  const NodeFailure({
    required this.path,
    required this.message,
    this.statusCode,
  });

  final String path;
  final String message;
  final int? statusCode;

  @override
  String toString() => '$path: $message';
}

/// How a directory listing should be shaped.
enum NodeSortField { name, modified, type, size }

enum SortOrder { ascending, descending }

/// Parameters for a directory listing.
class ListRequest {
  const ListRequest({
    required this.path,
    this.limit,
    this.cursor,
    this.sortBy = NodeSortField.name,
    this.sortOrder = SortOrder.ascending,
    this.recursive = false,
    this.depth,
    this.includeTotal = false,
  });

  final String path;
  final int? limit;
  final String? cursor;
  final NodeSortField sortBy;
  final SortOrder sortOrder;

  /// Walk the subtree. Prefer this over N per-file `stat` calls — it is the
  /// single largest saving against WebDAV's shared request ceiling.
  final bool recursive;
  final int? depth;
  final bool includeTotal;

  /// Whether this request opts into cursor paging. Puter returns a plain array
  /// unless a pagination parameter is present, so the presence of `cursor`
  /// (even `null`) changes the response shape.
  bool get isPaginated => cursor != null || includeTotal;
}

/// Live storage quota, from `fs.space()`.

class StorageUsage {
  const StorageUsage({required this.capacityBytes, required this.usedBytes});

  final int capacityBytes;
  final int usedBytes;

  int get freeBytes => (capacityBytes - usedBytes).clamp(0, capacityBytes);

  double get usedFraction =>
      capacityBytes <= 0 ? 0 : (usedBytes / capacityBytes).clamp(0.0, 1.0);

  /// Used space as a percentage in `[0, 100]`, ready for display.
  ///
  /// A convenience over [usedFraction] so the storage meter does not repeat
  /// the `* 100` in three places.
  double get percentage => usedFraction * 100;

  bool isNearLimit(double threshold) => usedFraction >= threshold;

  /// Whether a file of [bytes] fits without exceeding the quota.
  bool canFit(int bytes) => bytes <= freeBytes;

  @override
  String toString() => 'StorageUsage($usedBytes / $capacityBytes bytes)';
}

/// Identity of the authenticated Puter account.

class PuterIdentity {
  const PuterIdentity({
    required this.username,
    this.email,
    this.planTier,
  });

  final String username;
  final String? email;

  /// Detected plan, used to select the correct rate-limit column.
  final String? planTier;

  @override
  String toString() => 'PuterIdentity($username)';
}

/// Direction of a transfer.
enum TransferDirection { upload, download }

/// Lifecycle of a transfer task.
///
/// Modelled explicitly because Puter's transfers are **not atomic**: a partial
/// failure leaves earlier files written and is never rolled back, so each task
/// must carry its own honest state.
enum TransferState {
  /// Waiting for capacity or connectivity.
  queued,

  /// Actively moving bytes.
  running,

  /// Paused by the user.
  paused,

  /// Finished successfully.
  completed,

  /// Failed transiently; eligible for retry.
  failed,

  /// Failed permanently and requires the user to act — quota exhausted,
  /// plan restriction, or revoked credentials. Retrying changes nothing.
  blocked,

  /// Superseded or cancelled by the user.
  cancelled,
}

/// One file moving in one direction.
///
/// Per ADR 0004 this is deliberately per-file rather than per-batch, so a
/// single failure cannot obscure the outcome of the others.

class TransferTask {
  const TransferTask({
    required this.id,
    required this.direction,
    required this.remotePath,
    required this.localPath,
    required this.totalBytes,
    this.bytesDone = 0,
    this.state = TransferState.queued,
    this.attempts = 0,
    this.lastError,
    this.createdAt,
    this.overwrite = false,
  });

  final String id;
  final TransferDirection direction;
  final String remotePath;
  final String localPath;
  final int totalBytes;
  final int bytesDone;
  final TransferState state;
  final int attempts;
  final String? lastError;
  final DateTime? createdAt;

  /// Whether an upload may replace a file that is already there.
  ///
  /// Deliberately **not persisted**. A restart mid-replace therefore falls back
  /// to refusing the collision, which is the safe direction — and recoverable,
  /// because the user simply gets the Replace option again. Persisting it would
  /// mean a schema migration for a transient user decision.
  final bool overwrite;

  double get progress =>
      totalBytes <= 0 ? 0 : (bytesDone / totalBytes).clamp(0.0, 1.0);

  bool get isTerminal =>
      state == TransferState.completed ||
      state == TransferState.cancelled ||
      state == TransferState.blocked;

  /// Whether the task is finished with, either way. Distinct from [isTerminal]:
  /// a failed task is still waiting on the user to retry it, so it stays in the
  /// queue, but it is no longer competing for transfer capacity.
  bool get isFinished => isTerminal || state == TransferState.failed;

  /// Whether bytes are moving right now.
  bool get isActive => state == TransferState.running;

  /// Whether the user can still do something to move this task forward.
  bool get canRetry =>
      state == TransferState.failed || state == TransferState.cancelled;

  TransferTask copyWith({
    int? totalBytes,
    int? bytesDone,
    TransferState? state,
    int? attempts,
    String? lastError,
    bool? overwrite,

    /// Clear [lastError] explicitly.
    ///
    /// Needed because `lastError: null` cannot distinguish "leave it alone"
    /// from "remove it" on a nullable field — and a task that has just
    /// succeeded must not keep displaying the error from its last attempt.
    bool clearError = false,
  }) {
    return TransferTask(
      id: id,
      direction: direction,
      remotePath: remotePath,
      localPath: localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesDone: bytesDone ?? this.bytesDone,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: clearError ? null : (lastError ?? this.lastError),
      createdAt: createdAt,
      overwrite: overwrite ?? this.overwrite,
    );
  }

  @override
  String toString() =>
      'TransferTask(${direction.name} $remotePath ${state.name} '
      '${(progress * 100).toStringAsFixed(1)}%)';
}
