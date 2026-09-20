/// A minimal in-process WebDAV server for testing the transport.
///
/// Pure Dart — no test framework, no Flutter — so it runs under the Dart VM
/// alone. That matters here: `flutter test` and `dart test` both fail in some
/// environments (WebSocket upgrade, native-assets hooks), but `dart run` always
/// works. See `tool/verify/verify_transport.dart`.
///
/// This exists because `WebDavTransport` is the largest and most defect-prone
/// file in the project and, until now, had never been executed against a
/// server. Pointing it at this fixture exercises real HTTP, real status codes,
/// real XML parsing and real streaming — none of which a mock would catch.
///
/// It is deliberately *not* a general WebDAV implementation. It covers exactly
/// the surface the transport uses, plus the failure modes the transport must
/// handle correctly:
///
/// * per-entry errors inside a `207 Multistatus`
/// * `413` storage quota exhaustion
/// * `429` rate limiting
/// * `401` credential rejection
/// * `412` precondition failure on non-overwriting writes
/// * `Range` requests and `206 Partial Content`
/// * `MKCOL` returning `405` for an existing collection
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A node in the fixture's in-memory tree.
class _Node {
  _Node({
    required this.isDirectory,
    this.bytes = const <int>[],
    DateTime? modified,
  })  : modified = modified ?? DateTime.utc(2026, 1, 1),
        etag = _nextEtag();

  final bool isDirectory;
  List<int> bytes;
  DateTime modified;
  String etag;

  static int _etagCounter = 0;
  static String _nextEtag() => '"etag-${++_etagCounter}"';
}

/// A minimal WebDAV server, bound to an ephemeral port on loopback.
///
/// Start it, point a transport at [baseUrl], and stop it in a `finally`.
class WebDavFixture {
  WebDavFixture({this.quotaBytes = 100 * 1024 * 1024, this.requireAuth = true});

  /// Simulated storage quota. Writes beyond it return `413`.
  int quotaBytes;

  /// When true, requests without a `-token:` basic-auth header get `401`.
  bool requireAuth;

  /// When true, every request returns `429`. Used to verify backoff and
  /// circuit-breaker behaviour.
  bool rateLimited = false;

  /// When true, `PROPFIND` returns a `207` in which some entries carry a
  /// failing `propstat`. Verifies that partial failure is detected rather than
  /// treated as success.
  bool injectPartialFailure = false;

  /// When true, `GET` ignores `Range` and always returns the whole file with
  /// `200`. Some servers do this. The transport must notice and restart cleanly
  /// rather than appending the full body to a partial prefix, which would
  /// produce a corrupt file that looks plausible.
  bool ignoreRange = false;

  /// Credential the fixture accepts, when [requireAuth] is set.
  String expectedToken = 'fixture-token';

  late final HttpServer _server;
  final Map<String, _Node> _tree = <String, _Node>{};

  /// Requests received, for assertions about request counts.
  final List<String> requestLog = <String>[];

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  int get usedBytes => _tree.entries
      .where((entry) => !entry.value.isDirectory)
      .fold(0, (sum, entry) => sum + entry.value.bytes.length);

  Future<void> start() async {
    _tree['/'] = _Node(isDirectory: true);
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }

  /// Seed a file, creating parent collections as needed.
  void seedFile(String path, String content) {
    final normalised = _normalise(path);
    _ensureParents(normalised);
    _tree[normalised] = _Node(
      isDirectory: false,
      bytes: utf8.encode(content),
    );
  }

  /// Seed an empty collection.
  void seedDirectory(String path) {
    final normalised = _normalise(path);
    _ensureParents(normalised);
    _tree[normalised] = _Node(isDirectory: true);
  }

  /// Read a file's bytes, or `null` if absent.
  List<int>? read(String path) => _tree[_normalise(path)]?.bytes;

  String? readAsString(String path) {
    final bytes = read(path);
    return bytes == null ? null : utf8.decode(bytes);
  }

  bool exists(String path) => _tree.containsKey(_normalise(path));

  void clearLog() => requestLog.clear();

  // ------------------------------------------------------------------ serving

  Future<void> _serve() async {
    await for (final request in _server) {
      requestLog.add('${request.method} ${request.uri.path}');
      try {
        await _handle(request);
      } on Object catch (error) {
        // A fixture bug should surface as a 500, not a hung socket.
        _respond(request, 500, 'fixture error: $error');
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (rateLimited) {
      _respond(request, 429, 'rate limited');
      return;
    }

    if (requireAuth && !_authorised(request)) {
      request.response.headers.set('WWW-Authenticate', 'Basic realm="puter"');
      _respond(request, 401, 'unauthorised');
      return;
    }

    final path = _normalise(Uri.decodeFull(request.uri.path));

    switch (request.method) {
      case 'OPTIONS':
        request.response.headers.set('DAV', '1, 2');
        request.response.headers.set(
          'Allow',
          'OPTIONS, PROPFIND, GET, PUT, DELETE, MKCOL, MOVE, COPY, HEAD',
        );
        _respond(request, 200, '');
      case 'PROPFIND':
        await _propfind(request, path);
      case 'MKCOL':
        _mkcol(request, path);
      case 'PUT':
        await _put(request, path);
      case 'GET':
      case 'HEAD':
        _get(request, path);
      case 'DELETE':
        _delete(request, path);
      case 'MOVE':
        _moveOrCopy(request, path, move: true);
      case 'COPY':
        _moveOrCopy(request, path, move: false);
      default:
        _respond(request, 405, 'method not allowed');
    }
  }

  bool _authorised(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Basic ')) return false;
    try {
      final decoded = utf8.decode(base64Decode(header.substring(6)));
      // Puter's documented convention: username `-token`, password is the token.
      return decoded == '-token:$expectedToken';
    } on Object {
      return false;
    }
  }

  Future<void> _propfind(HttpRequest request, String path) async {
    final node = _tree[path];
    if (node == null) {
      _respond(request, 404, 'not found');
      return;
    }

    final depth = request.headers.value('depth') ?? '1';
    final entries = <MapEntry<String, _Node>>[MapEntry(path, node)];

    if (node.isDirectory && depth != '0') {
      final prefix = path == '/' ? '/' : '$path/';
      for (final entry in _tree.entries) {
        if (entry.key == path) continue;
        if (!entry.key.startsWith(prefix)) continue;
        // Depth 1 means immediate children only.
        final remainder = entry.key.substring(prefix.length);
        if (depth == '1' && remainder.contains('/')) continue;
        entries.add(entry);
      }
    }

    final buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write('<d:multistatus xmlns:d="DAV:">');

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final isRoot = i == 0;

      // Simulate a 207 carrying a per-entry failure. A client that treats 207
      // as blanket success will silently lose these entries.
      if (injectPartialFailure && !isRoot && i.isEven) {
        buffer
          ..write('<d:response>')
          ..write('<d:href>${_encodeHref(entry.key)}</d:href>')
          ..write('<d:propstat><d:prop><d:displayname/></d:prop>')
          ..write('<d:status>HTTP/1.1 403 Forbidden</d:status></d:propstat>')
          ..write('</d:response>');
        continue;
      }

      final value = entry.value;
      buffer
        ..write('<d:response>')
        ..write('<d:href>${_encodeHref(entry.key)}</d:href>')
        ..write('<d:propstat><d:prop>')
        ..write('<d:displayname>${_escape(_basename(entry.key))}</d:displayname>')
        ..write(
          '<d:getcontentlength>'
          '${value.isDirectory ? 0 : value.bytes.length}'
          '</d:getcontentlength>',
        )
        ..write(
          '<d:getlastmodified>${HttpDate.format(value.modified.toUtc())}'
          '</d:getlastmodified>',
        )
        ..write('<d:getetag>${value.etag}</d:getetag>');

      if (value.isDirectory) {
        buffer.write('<d:resourcetype><d:collection/></d:resourcetype>');
      } else {
        buffer
          ..write('<d:resourcetype/>')
          ..write('<d:getcontenttype>${_mimeFor(entry.key)}</d:getcontenttype>');
      }

      // RFC 4331 quota properties, on the root only.
      if (isRoot) {
        buffer
          ..write(
            '<d:quota-available-bytes>${max(0, quotaBytes - usedBytes)}'
            '</d:quota-available-bytes>',
          )
          ..write('<d:quota-used-bytes>$usedBytes</d:quota-used-bytes>');
      }

      buffer
        ..write('</d:prop>')
        ..write('<d:status>HTTP/1.1 200 OK</d:status>')
        ..write('</d:propstat>')
        ..write('</d:response>');
    }

    buffer.write('</d:multistatus>');

    request.response
      ..statusCode = 207
      ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
      ..write(buffer.toString());
    await request.response.close();
  }

  void _mkcol(HttpRequest request, String path) {
    if (_tree.containsKey(path)) {
      // 405 is the standard "collection already exists" signal, and the
      // transport relies on it to tell parents apart from the leaf.
      _respond(request, 405, 'already exists');
      return;
    }
    if (!_parentExists(path)) {
      _respond(request, 409, 'parent does not exist');
      return;
    }
    _tree[path] = _Node(isDirectory: true);
    _respond(request, 201, '');
  }

  Future<void> _put(HttpRequest request, String path) async {
    if (_tree[path]?.isDirectory ?? false) {
      _respond(request, 405, 'is a collection');
      return;
    }

    // Honour If-None-Match: * as "refuse to overwrite".
    if (request.headers.value('if-none-match') == '*' &&
        _tree.containsKey(path)) {
      _respond(request, 412, 'precondition failed');
      return;
    }

    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
    }

    // Quota enforcement. The transport must surface this as a non-retryable
    // storageLimitReached, and the existing file must stay intact.
    final projected =
        usedBytes - (_tree[path]?.bytes.length ?? 0) + chunks.length;
    if (projected > quotaBytes) {
      _respond(request, 413, 'storage limit reached');
      return;
    }

    if (!_parentExists(path)) {
      _respond(request, 409, 'parent does not exist');
      return;
    }

    final existed = _tree.containsKey(path);
    _tree[path] = _Node(isDirectory: false, bytes: chunks);
    _respond(request, existed ? 204 : 201, '');
  }

  void _get(HttpRequest request, String path) {
    final node = _tree[path];
    if (node == null) {
      _respond(request, 404, 'not found');
      return;
    }
    if (node.isDirectory) {
      _respond(request, 405, 'is a collection');
      return;
    }

    final range = request.headers.value('range');
    var bytes = node.bytes;
    var status = 200;

    if (!ignoreRange && range != null && range.startsWith('bytes=')) {
      final start = int.tryParse(range.substring(6).split('-').first) ?? 0;
      if (start < bytes.length) {
        bytes = bytes.sublist(start);
        status = 206;
        request.response.headers.set(
          'Content-Range',
          'bytes $start-${node.bytes.length - 1}/${node.bytes.length}',
        );
      }
    }

    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.binary
      ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..headers.set(HttpHeaders.contentLengthHeader, '${bytes.length}');

    if (request.method == 'HEAD') {
      unawaited(request.response.close());
      return;
    }
    request.response.add(bytes);
    unawaited(request.response.close());
  }

  void _delete(HttpRequest request, String path) {
    if (!_tree.containsKey(path)) {
      _respond(request, 404, 'not found');
      return;
    }
    final prefix = path == '/' ? '/' : '$path/';
    _tree.removeWhere((key, _) => key == path || key.startsWith(prefix));
    _respond(request, 204, '');
  }

  void _moveOrCopy(HttpRequest request, String path, {required bool move}) {
    final node = _tree[path];
    if (node == null) {
      _respond(request, 404, 'not found');
      return;
    }

    final destination = request.headers.value('destination');
    if (destination == null) {
      _respond(request, 400, 'missing Destination');
      return;
    }

    final target = _normalise(Uri.parse(destination).path);
    final overwrite = (request.headers.value('overwrite') ?? 'T') != 'F';

    if (_tree.containsKey(target) && !overwrite) {
      _respond(request, 412, 'precondition failed');
      return;
    }

    if (node.isDirectory) {
      _tree[target] = _Node(isDirectory: true);
      final prefix = '$path/';
      for (final entry in _tree.entries
          .where((e) => e.key.startsWith(prefix))
          .toList(growable: false)) {
        final suffix = entry.key.substring(prefix.length);
        _tree['$target/$suffix'] = _Node(
          isDirectory: entry.value.isDirectory,
          bytes: List<int>.from(entry.value.bytes),
        );
      }
    } else {
      _tree[target] = _Node(
        isDirectory: false,
        bytes: List<int>.from(node.bytes),
      );
    }

    if (move) {
      final prefix = '$path/';
      _tree.removeWhere((key, _) => key == path || key.startsWith(prefix));
    }

    _respond(request, 201, '');
  }

  // ------------------------------------------------------------------ helpers

  bool _parentExists(String path) {
    if (path == '/') return true;
    final parent = path.substring(0, path.lastIndexOf('/'));
    return parent.isEmpty || _tree.containsKey(parent);
  }

  void _ensureParents(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    var current = '';
    for (var i = 0; i < parts.length - 1; i++) {
      current = '$current/${parts[i]}';
      _tree.putIfAbsent(current, () => _Node(isDirectory: true));
    }
  }

  void _respond(HttpRequest request, int status, String body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..write(body);
    unawaited(request.response.close());
  }

  static String _normalise(String path) {
    if (path.isEmpty) return '/';
    var result = path.startsWith('/') ? path : '/$path';
    while (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _basename(String path) =>
      path == '/' ? '/' : path.substring(path.lastIndexOf('/') + 1);

  static String _encodeHref(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _mimeFor(String path) {
    if (path.endsWith('.txt')) return 'text/plain';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}
