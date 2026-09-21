/// A scriptable [PuterTransport] for tests.
///
/// Hand-written rather than generated, for the same reason the fixture server
/// is hand-written: what matters here is being able to make a specific call
/// *fail* in a specific way, and a mock's default of "returns null for
/// everything" makes that harder to read than a small class that says
/// `listError = ...` and then asserts on what the caller did about it.
///
/// Pure Dart apart from the domain entities, so it works under both
/// `flutter test` and `dart test`.
library;

import 'package:puter_cloud_storage/core/error/puter_exception.dart';
import 'package:puter_cloud_storage/data/transport/puter_transport.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';
import 'package:puter_cloud_storage/domain/entities/remote_path.dart';

/// A transport whose every behaviour is set by the test.
class FakeTransport implements PuterTransport {
  FakeTransport({
    this.capabilities = const TransportCapabilities(),
    Map<String, List<RemoteNode>>? tree,
    this.identityResult = const PuterIdentity(username: 'tester'),
    this.usageResult,
  }) : tree = tree ?? <String, List<RemoteNode>>{};

  /// Directories, keyed by parent path — the shape `list` answers from.
  final Map<String, List<RemoteNode>> tree;

  @override
  TransportCapabilities capabilities;

  final PuterIdentity identityResult;
  StorageUsage? usageResult;

  /// Thrown by [usage] when set, taking precedence over [usageResult].
  ///
  /// Exists to model a failure that is **not** a [PuterException] — a transport
  /// leaking a raw parse error, say. Quota is advisory, so nothing a quota read
  /// does may be allowed to fail a transfer.
  Object? usageError;

  // ------------------------------------------------------------ observations

  /// Paths passed to [list], in order. Lets a test assert the request budget
  /// rather than guess at it.
  final List<String> listCalls = <String>[];

  final List<({String from, String to})> moves = <({String from, String to})>[];
  final List<({String from, String to})> copies = <({String from, String to})>[];
  final List<String> createdDirectories = <String>[];
  final List<String> deletedPaths = <String>[];
  final List<UploadRequest> uploads = <UploadRequest>[];
  final List<DownloadRequest> downloads = <DownloadRequest>[];

  int disposeCalls = 0;
  TokenCredential? credential;

  // --------------------------------------------------------------- behaviour

  /// Thrown by [list] when set. Cleared by the test when it wants success.
  PuterException? listError;

  /// Thrown by [upload] when set.
  PuterException? uploadError;

  /// Thrown by [download] when set.
  PuterException? downloadError;

  /// Thrown by [move] when set.
  PuterException? moveError;

  /// Replaces the default upload behaviour.
  Future<void> Function(UploadRequest request)? onUpload;

  /// Replaces the default download behaviour.
  Future<void> Function(DownloadRequest request)? onDownload;

  /// Pages returned by [list] instead of [tree].
  RemoteNodePage? nextPage;

  @override
  String get name => 'fake';

  @override
  Future<void> authenticate(TokenCredential credential) async {
    this.credential = credential;
  }

  @override
  Future<PuterIdentity> identity() async => identityResult;

  @override
  Future<RemoteNodePage> list(ListRequest request) async {
    final normalised = RemotePath.normalise(request.path);
    listCalls.add(normalised);
    final error = listError;
    if (error != null) throw error;
    final page = nextPage;
    if (page != null) return page;
    return RemoteNodePage(
      items: tree[normalised] ?? const <RemoteNode>[],
    );
  }

  @override
  Future<RemoteNode> stat(String path) async {
    final normalised = RemotePath.normalise(path);
    for (final List<RemoteNode> children in tree.values) {
      for (final RemoteNode node in children) {
        if (node.path == normalised) return node;
      }
    }
    throw PuterException(
      PuterErrorKind.notFound,
      'No such node.',
      path: normalised,
    );
  }

  @override
  Future<void> createDirectory(String path, {bool createParents = true}) async {
    final normalised = RemotePath.normalise(path);
    createdDirectories.add(normalised);
    (tree[RemotePath.parent(normalised) ?? RemotePath.root] ??= <RemoteNode>[])
        .add(
      RemoteNode(
        path: normalised,
        name: RemotePath.name(normalised),
        isDirectory: true,
      ),
    );
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final normalised = RemotePath.normalise(path);
    deletedPaths.add(normalised);
    for (final bucket in tree.values) {
      bucket.removeWhere(
        (RemoteNode node) =>
            node.path == normalised || node.path.startsWith('$normalised/'),
      );
    }
  }

  @override
  Future<void> move(String from, String to, {bool overwrite = false}) async {
    final error = moveError;
    if (error != null) throw error;
    final source = RemotePath.normalise(from);
    final destination = RemotePath.normalise(to);
    moves.add((from: source, to: destination));
    _relocate(source, destination);
  }

  @override
  Future<void> copy(String from, String to, {bool overwrite = false}) async {
    final source = RemotePath.normalise(from);
    final destination = RemotePath.normalise(to);
    copies.add((from: source, to: destination));
    _relocate(source, destination, leaveOriginal: true);
  }

  /// Apply a path change to the tree, the way a server would.
  ///
  /// This matters more than it looks. The repository reconciles from the server
  /// after every mutation, so a fake that only *recorded* the call would hand
  /// back the pre-move listing and quietly undo the move in the index — making
  /// a correct cache look broken and a broken one look correct.
  void _relocate(String from, String to, {bool leaveOriginal = false}) {
    RemoteNode? moved;
    for (final List<RemoteNode> bucket in tree.values) {
      final index = bucket.indexWhere((RemoteNode n) => n.path == from);
      if (index >= 0) {
        moved = leaveOriginal ? bucket[index] : bucket.removeAt(index);
        break;
      }
    }
    if (moved == null) return;

    (tree[RemotePath.parent(to) ?? RemotePath.root] ??= <RemoteNode>[]).add(
      moved.copyWith(path: to, name: RemotePath.name(to)),
    );

    // Descendants: the bucket key moves, and so does every path inside it.
    final affected = tree.keys
        .where((String key) => key == from || key.startsWith('$from/'))
        .toList(growable: false);

    for (final String key in affected) {
      final bucket = tree.remove(key);
      if (bucket == null) continue;
      final newKey = key == from ? to : '$to${key.substring(from.length)}';
      tree[newKey] = bucket
          .map(
            (RemoteNode node) => node.copyWith(
              path: node.path == from
                  ? to
                  : '$to${node.path.substring(from.length)}',
              name: node.name,
            ),
          )
          .toList(growable: true);
    }
  }

  @override
  Future<RemoteNode> upload(UploadRequest request) async {
    uploads.add(request);
    final error = uploadError;
    if (error != null) throw error;

    final override = onUpload;
    if (override != null) {
      await override(request);
    } else {
      request.onProgress?.call(100, 100);
    }

    final node = RemoteNode(
      path: RemotePath.normalise(request.remotePath),
      name: RemotePath.name(request.remotePath),
      isDirectory: false,
      sizeBytes: 100,
    );
    (tree[RemotePath.parent(node.path) ?? RemotePath.root] ??=
            <RemoteNode>[])
        .add(node);
    return node;
  }

  @override
  Future<void> download(DownloadRequest request) async {
    downloads.add(request);
    final error = downloadError;
    if (error != null) throw error;

    final override = onDownload;
    if (override != null) {
      await override(request);
    } else {
      request.onProgress?.call(100, 100);
    }
  }

  @override
  Future<StorageUsage> usage() async {
    final failure = usageError;
    if (failure != null) throw failure;

    final result = usageResult;
    if (result == null) {
      throw const PuterException(
        PuterErrorKind.unsupported,
        'No quota over this transport.',
      );
    }
    return result;
  }

  @override
  Future<Uri> signedReadUrl(
    String path, {
    Duration ttl = const Duration(hours: 1),
  }) async =>
      throw const PuterException(
        PuterErrorKind.unsupported,
        'Signing is not supported.',
      );

  @override
  Future<void> dispose() async => disposeCalls++;
}
