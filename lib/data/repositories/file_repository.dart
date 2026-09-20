/// Coordinates the transport, the local index and the presentation layer.
///
/// Three rules shape everything here.
///
/// 1. **Never re-classify a transport error.** The transport already returns a
///    [PuterException] with the right [PuterErrorKind], and that kind decides
///    whether the UI offers Retry. Wrapping everything as `network` — which an
///    earlier revision of this file did — turns "your storage is full" into
///    "check your connection" and sends the user to fix the wrong problem.
///
/// 2. **The cache is the first answer, the network is the correction.** A
///    listing renders from the index immediately and is refetched behind it,
///    so a cold start shows folders before any request returns.
///
/// 3. **Every mutation reconciles.** Puter's write path is not atomic: a
///    partial failure leaves earlier files written and is never rolled back
///    (ADR 0004). So after any change the affected folders are re-read from
///    the server rather than patched by guesswork.
library;

import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/error/puter_exception.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import '../database/node_cache.dart';
import '../transport/puter_transport.dart';

/// A directory listing together with where it came from.
///
/// Provenance is part of the value, not a side channel: the browser needs to be
/// able to say "refreshing", rather than presenting possibly stale data as
/// current.
class DirectoryListing {
  const DirectoryListing({
    required this.path,
    required this.items,
    this.failures = const <NodeFailure>[],
    this.cachedAt,
    this.fromCache = false,
  });

  /// The folder this listing describes.
  final String path;

  final List<RemoteNode> items;

  /// Entries the server refused to describe. Surfaced, never silently dropped:
  /// a file that exists but cannot be read should look different from a file
  /// that is not there.
  final List<NodeFailure> failures;

  /// When these rows were last confirmed against the server.
  final DateTime? cachedAt;

  /// Whether this came from the index without a network round trip.
  final bool fromCache;

  bool get isPartial => failures.isNotEmpty;

  DirectoryListing copyWith({
    List<RemoteNode>? items,
    List<NodeFailure>? failures,
    DateTime? cachedAt,
    bool? fromCache,
  }) {
    return DirectoryListing(
      path: path,
      items: items ?? this.items,
      failures: failures ?? this.failures,
      cachedAt: cachedAt ?? this.cachedAt,
      fromCache: fromCache ?? this.fromCache,
    );
  }

  @override
  String toString() => 'DirectoryListing($path, ${items.length} items'
      '${fromCache ? ', cached' : ''})';
}

/// File operations, with the local index in front of the transport.
class FileRepository {
  FileRepository({
    required PuterTransport transport,
    required NodeCache cache,
    AppConfig config = const AppConfig(),
  })  : _transport = transport,
        _cache = cache,
        _config = config;

  final PuterTransport _transport;
  final NodeCache _cache;
  final AppConfig _config;

  final StreamController<Set<String>> _changes =
      StreamController<Set<String>>.broadcast();

  /// Folders whose contents changed, emitted after every mutation.
  ///
  /// Carries the affected paths rather than a bare ping, so a listener can
  /// ignore changes that do not concern it — otherwise one rename would refetch
  /// every open listing.
  Stream<Set<String>> get changes => _changes.stream;

  /// What the active transport can actually do, so the UI hides rather than
  /// fails at the point of use.
  TransportCapabilities get capabilities => _transport.capabilities;

  /// Identifier of the active transport, for diagnostics.
  String get transportName => _transport.name;

  /// The live transport. The transfer engine needs it directly: it streams
  /// large payloads and reports its own progress, which is not something the
  /// repository should sit in the middle of.
  PuterTransport get transport => _transport;

  // ------------------------------------------------------------------ reading

  /// Cached children of [path], without touching the network.
  ///
  /// This is the cold-start path: it is what makes a previously visited folder
  /// render before any request has a chance to return.
  Future<List<RemoteNode>> cachedChildren(String path) =>
      _cache.childrenOf(RemotePath.normalise(path));

  /// When [path] was last confirmed against the server, or `null`.
  Future<DateTime?> cachedAt(String path) =>
      _cache.lastCachedAt(RemotePath.normalise(path));

  /// List [path], serving from the index when it is fresh.
  ///
  /// A listing counts as fresh for [AppConfig.listingCacheTtl]; pass [force] to
  /// bypass that on an explicit pull-to-refresh.
  ///
  /// On a network failure with cached content present, the cached content is
  /// returned with [DirectoryListing.fromCache] set rather than throwing.
  /// Refusing to show folders the app already knows about is worse than showing
  /// them slightly stale, and offline browsing is a stated feature.
  Future<DirectoryListing> listDirectory(
    String path, {
    bool force = false,
  }) async {
    final normalised = RemotePath.normalise(path);
    final cached = await _cache.childrenOf(normalised);
    final cachedAt = await _cache.lastCachedAt(normalised);

    final isFresh = cachedAt != null &&
        DateTime.now().difference(cachedAt) < _config.listingCacheTtl;

    if (!force && cached.isNotEmpty && isFresh) {
      return DirectoryListing(
        path: normalised,
        items: _sorted(cached),
        cachedAt: cachedAt,
        fromCache: true,
      );
    }

    try {
      final page = await _transport.list(
        ListRequest(path: normalised, limit: _config.listingPageSize),
      );
      await _cache.replaceChildren(normalised, page.items);
      return DirectoryListing(
        path: normalised,
        items: _sorted(page.items),
        failures: page.failures,
        cachedAt: DateTime.now(),
      );
    } on PuterException {
      if (cached.isNotEmpty) {
        return DirectoryListing(
          path: normalised,
          items: _sorted(cached),
          cachedAt: cachedAt,
          fromCache: true,
        );
      }
      rethrow;
    }
  }

  /// Metadata for one path, refreshing the cache entry.
  Future<RemoteNode> stat(String path) async {
    final node = await _transport.stat(RemotePath.normalise(path));
    await _cache.upsert(node);
    return node;
  }

  /// Live quota.
  Future<StorageUsage> usage() => _transport.usage();

  /// Identity of the signed-in account.
  Future<PuterIdentity> identity() => _transport.identity();

  /// Search the local index. Never touches the network.
  Future<List<RemoteNode>> search(
    String query, {
    String? scopePath,
    int limit = 200,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <RemoteNode>[];
    final results = await _cache.search(
      trimmed,
      scopePath: scopePath == null ? null : RemotePath.normalise(scopePath),
      limit: limit,
    );
    return _sorted(results);
  }

  /// How many entries the index holds.
  Future<int> cacheSize() => _cache.nodeCount();

  /// Folder paths known to the index.
  Future<List<String>> knownFolders() => _cache.folderPaths();

  // ----------------------------------------------------------------- mutating

  /// Create a folder, then reconcile its parent.
  Future<void> createDirectory(String path) async {
    final normalised = RemotePath.normalise(path);
    await _transport.createDirectory(normalised);
    await _reconcile(RemotePath.parent(normalised) ?? RemotePath.root);
  }

  /// Delete [node], then reconcile its parent.
  ///
  /// The cache is cleared only after the server confirms: a delete that fails
  /// must not leave the index claiming the file is gone.
  Future<void> delete(RemoteNode node) async {
    await _transport.delete(node.path, recursive: node.isDirectory);
    await _cache.deleteSubtree(node.path);
    await _reconcile(RemotePath.parent(node.path) ?? RemotePath.root);
  }

  /// Rename [node] in place, returning its new path.
  Future<String> rename(RemoteNode node, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const PuterException(
        PuterErrorKind.badRequest,
        'A name is required.',
      );
    }
    if (trimmed.contains('/')) {
      throw const PuterException(
        PuterErrorKind.badRequest,
        'A name cannot contain “/”.',
      );
    }
    final parent = RemotePath.parent(node.path) ?? RemotePath.root;
    final destination = RemotePath.join(parent, trimmed);
    if (destination == node.path) return destination;
    await move(node, destination);
    return destination;
  }

  /// Move [node] to [destinationPath], reconciling both ends.
  Future<void> move(RemoteNode node, String destinationPath) async {
    final destination = RemotePath.normalise(destinationPath);

    // Moving a folder into its own subtree would either be refused by the
    // server or, worse, execute destructively. Reject it here, where the
    // message can explain why rather than surfacing a protocol error.
    if (node.isDirectory && RemotePath.isWithin(node.path, destination)) {
      throw PuterException(
        PuterErrorKind.badRequest,
        '“${node.name}” cannot be moved inside itself.',
        path: node.path,
      );
    }

    await _transport.move(node.path, destination);
    await _cache.rewriteSubtree(node.path, destination);
    await _reconcile(RemotePath.parent(node.path) ?? RemotePath.root);
    await _reconcile(RemotePath.parent(destination) ?? RemotePath.root);
  }

  /// Copy [node] to [destinationPath].
  Future<void> copy(RemoteNode node, String destinationPath) async {
    final destination = RemotePath.normalise(destinationPath);
    if (node.isDirectory && RemotePath.isWithin(node.path, destination)) {
      throw PuterException(
        PuterErrorKind.badRequest,
        '“${node.name}” cannot be copied inside itself.',
        path: node.path,
      );
    }
    await _transport.copy(node.path, destination);
    await _reconcile(RemotePath.parent(destination) ?? RemotePath.root);
  }

  /// Throw away the index. Called on sign-out, and from Settings.
  Future<void> clearCache() => _cache.clear();

  /// Re-read [path] from the server and tell listeners it changed.
  ///
  /// Public because the transfer engine needs it: an upload that lands is a
  /// change the browser must see, and the engine has no other way to say so.
  Future<void> reconcile(String path) => _reconcile(path);

  /// Stop emitting change notifications.
  Future<void> dispose() => _changes.close();

  // ------------------------------------------------------------------ private

  /// Re-read [path] from the server and mark it dirty for any listener.
  ///
  /// A failure here is deliberately swallowed. The mutation itself already
  /// succeeded, and turning a successful delete into a visible error because
  /// the follow-up listing timed out would misreport what happened. The folder
  /// stays stale and the next refresh corrects it.
  Future<void> _reconcile(String path) async {
    final normalised = RemotePath.normalise(path);
    try {
      final page = await _transport.list(
        ListRequest(path: normalised, limit: _config.listingPageSize),
      );
      await _cache.replaceChildren(normalised, page.items);
    } on PuterException {
      // Leave the cached rows in place; they are the best information we have.
    }
    if (!_changes.isClosed) _changes.add(<String>{normalised});
  }

  /// Directories first, then by name.
  ///
  /// Done here rather than in SQL or on the wire because Puter's ordering is
  /// not guaranteed and every surface — browser, search, move picker — needs
  /// the same answer.
  List<RemoteNode> _sorted(List<RemoteNode> nodes) {
    final copy = List<RemoteNode>.from(nodes)
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return copy;
  }
}
