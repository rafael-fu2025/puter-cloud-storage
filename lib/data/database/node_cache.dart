/// The local index, as the repository needs it.
///
/// An interface rather than a direct `AppDatabase` dependency for two reasons:
///
/// 1. Widget tests run on the host, where the bundled SQLite native library is
///    not guaranteed to exist. An in-memory implementation keeps the browse UI
///    testable without a device.
/// 2. The repository is the only component that should know how rows map to
///    domain entities, so that mapping lives here and nowhere else.
library;

import 'package:drift/drift.dart';

import '../../domain/entities/remote_node.dart';
import 'app_database.dart';

/// Read and write access to the cached filesystem index.
abstract class NodeCache {
  /// Cached children of [parentPath], unordered.
  Future<List<RemoteNode>> childrenOf(String parentPath);

  /// When [parentPath] was last refreshed from the server, or `null`.
  Future<DateTime?> lastCachedAt(String parentPath);

  /// Replace every cached child of [parentPath] with [nodes], atomically.
  Future<void> replaceChildren(String parentPath, List<RemoteNode> nodes);

  /// Insert or update a single node without disturbing its siblings.
  Future<void> upsert(RemoteNode node);

  /// Remove [path] and everything beneath it.
  Future<void> deleteSubtree(String path);

  /// Rewrite the paths of a moved or renamed subtree.
  Future<void> rewriteSubtree(String from, String to);

  /// Cached entries whose name contains [query].
  ///
  /// [scopePath] limits the search to one subtree. Local-only: the index is
  /// what makes search possible at all, since Puter offers no server-side
  /// filesystem search.
  Future<List<RemoteNode>> search(
    String query, {
    String? scopePath,
    int limit = 200,
  });

  /// Total entries held, for cache management.
  Future<int> nodeCount();

  /// Every folder path in the index, for the refresh sweep.
  Future<List<String>> folderPaths();

  /// Drop the entire index — on sign-out, so accounts never bleed together.
  Future<void> clear();
}

/// [NodeCache] backed by the Drift database.
class DriftNodeCache implements NodeCache {
  DriftNodeCache(this._db);

  final AppDatabase _db;

  @override
  Future<List<RemoteNode>> childrenOf(String parentPath) async {
    final rows = await _db.childrenOf(parentPath);
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<DateTime?> lastCachedAt(String parentPath) =>
      _db.lastCachedAt(parentPath);

  @override
  Future<void> replaceChildren(String parentPath, List<RemoteNode> nodes) {
    return _db.replaceChildren(
      parentPath,
      nodes.map(_toCompanion).toList(growable: false),
    );
  }

  @override
  Future<void> upsert(RemoteNode node) => _db.upsertAll(<RemoteNodesCompanion>[
        _toCompanion(node),
      ]);

  @override
  Future<void> deleteSubtree(String path) => _db.deleteSubtree(path);

  @override
  Future<void> rewriteSubtree(String from, String to) =>
      _db.rewriteSubtreePath(from, to);

  @override
  Future<List<RemoteNode>> search(
    String query, {
    String? scopePath,
    int limit = 200,
  }) async {
    final rows = await _db.searchByName(query, scopePath: scopePath, limit: limit);
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<int> nodeCount() => _db.cachedNodeCount();

  @override
  Future<List<String>> folderPaths() => _db.indexedFolderPaths();

  @override
  Future<void> clear() => _db.clearIndex();

  // ------------------------------------------------------------------ mapping

  /// The parent directory a node's row should be filed under.
  ///
  /// Root-level entries report `'/'` rather than `null`, so `childrenOf('/')`
  /// is a plain equality lookup. The domain's `parentPath` getter returns
  /// `null` at the root, which is correct for display but useless as a key.
  static String? parentKeyOf(String path) {
    if (path == '/' || path.isEmpty) return null;
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final index = trimmed.lastIndexOf('/');
    if (index < 0) return null;
    return index == 0 ? '/' : trimmed.substring(0, index);
  }

  static RemoteNode _toDomain(RemoteNodeRow row) => RemoteNode(
        path: row.path,
        name: row.name,
        isDirectory: row.isFolder,
        sizeBytes: row.size,
        modifiedAt: row.modified,
        mimeType: row.mimeType,
        etag: row.etag,
        isShared: row.isShared,
        indexedAt: row.cachedAt,
      );

  static RemoteNodesCompanion _toCompanion(RemoteNode node) =>
      RemoteNodesCompanion.insert(
        path: node.path,
        name: node.name,
        type: node.isDirectory ? 'folder' : 'file',
        size: Value<int>(node.sizeBytes),
        modified: Value<DateTime?>(node.modifiedAt),
        parentPath: Value<String?>(parentKeyOf(node.path)),
        isFolder: Value<bool>(node.isDirectory),
        cachedAt: node.indexedAt ?? DateTime.now(),
        mimeType: Value<String?>(node.mimeType),
        etag: Value<String?>(node.etag),
        isShared: Value<bool?>(node.isShared),
      );
}

/// Volatile [NodeCache] for tests and for a database that failed to open.
///
/// Never used in a release build for real data — nothing survives a restart.
class InMemoryNodeCache implements NodeCache {
  final Map<String, Map<String, RemoteNode>> _byParent =
      <String, Map<String, RemoteNode>>{};
  final Map<String, DateTime> _refreshedAt = <String, DateTime>{};

  @override
  Future<List<RemoteNode>> childrenOf(String parentPath) async {
    final bucket = _byParent[parentPath];
    return bucket == null ? const <RemoteNode>[] : bucket.values.toList();
  }

  @override
  Future<DateTime?> lastCachedAt(String parentPath) async =>
      _refreshedAt[parentPath];

  @override
  Future<void> replaceChildren(String parentPath, List<RemoteNode> nodes) async {
    _byParent[parentPath] = <String, RemoteNode>{
      for (final node in nodes) node.path: node,
    };
    _refreshedAt[parentPath] = DateTime.now();
  }

  @override
  Future<void> upsert(RemoteNode node) async {
    final parent = DriftNodeCache.parentKeyOf(node.path);
    if (parent == null) return;
    (_byParent[parent] ??= <String, RemoteNode>{})[node.path] = node;
  }

  @override
  Future<void> deleteSubtree(String path) async {
    for (final bucket in _byParent.values) {
      bucket.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    }
  }

  /// Rewrite the paths of a moved or renamed subtree.
  ///
  /// Rebuilds the whole map rather than editing buckets in place, because a
  /// move changes **two** things: the paths of the entries, and the key of the
  /// bucket that holds them. Renaming `/Documents` to `/Archive` has to move
  /// `/Documents`'s child list to the key `/Archive` — rewriting only the entry
  /// paths would leave every child filed under a folder that no longer exists,
  /// and the moved folder would then appear empty.
  @override
  Future<void> rewriteSubtree(String from, String to) async {
    final rebuilt = <String, Map<String, RemoteNode>>{};
    for (final MapEntry<String, Map<String, RemoteNode>> entry
        in _byParent.entries) {
      final bucket = rebuilt.putIfAbsent(
        _rewritePath(entry.key, from, to),
        () => <String, RemoteNode>{},
      );
      for (final RemoteNode node in entry.value.values) {
        final path = _rewritePath(node.path, from, to);
        bucket[path] = path == node.path
            ? node
            : node.copyWith(path: path, name: _nameOf(path));
      }
    }

    final refreshed = <String, DateTime>{
      for (final MapEntry<String, DateTime> entry in _refreshedAt.entries)
        _rewritePath(entry.key, from, to): entry.value,
    };

    _byParent
      ..clear()
      ..addAll(rebuilt);
    _refreshedAt
      ..clear()
      ..addAll(refreshed);
  }

  /// Rewrite one path if it is [from] or sits beneath it.
  ///
  /// The `'$from/'` guard matters: without it, renaming `/Documents` would also
  /// rewrite `/Documents-2019`, which is a different folder.
  static String _rewritePath(String path, String from, String to) {
    if (path == from) return to;
    if (path.startsWith('$from/')) return '$to${path.substring(from.length)}';
    return path;
  }

  @override
  Future<List<RemoteNode>> search(
    String query, {
    String? scopePath,
    int limit = 200,
  }) async {
    final needle = query.toLowerCase();
    final scope = scopePath;
    final results = <RemoteNode>[];
    for (final bucket in _byParent.values) {
      for (final node in bucket.values) {
        if (!node.name.toLowerCase().contains(needle)) continue;
        if (scope != null && scope != '/' && !node.path.startsWith('$scope/')) {
          continue;
        }
        results.add(node);
        if (results.length >= limit) return results;
      }
    }
    return results;
  }

  @override
  Future<int> nodeCount() async =>
      _byParent.values.fold<int>(0, (sum, bucket) => sum + bucket.length);

  @override
  Future<List<String>> folderPaths() async => <String>[
        for (final bucket in _byParent.values)
          for (final node in bucket.values)
            if (node.isDirectory) node.path,
      ];

  @override
  Future<void> clear() async {
    _byParent.clear();
    _refreshedAt.clear();
  }

  static String _nameOf(String path) {
    if (path == '/') return '/';
    return path.substring(path.lastIndexOf('/') + 1);
  }
}
