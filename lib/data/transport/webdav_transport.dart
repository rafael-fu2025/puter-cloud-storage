/// WebDAV transport — the primary path to Puter (ADR 0002).
///
/// Chosen because it is the only documented route that yields pure-Dart
/// streaming, `Range` resume, background transfers and standard HTTP tooling.
/// See `docs/puter-api-research.md` §4.
///
/// **The host is unverified.** Phase 0 confirms it against the live account;
/// [PuterEndpoints.webdavHostCandidates] lists the candidates and [probe]
/// selects the first that answers.
///
/// Two WebDAV specifics drive the implementation:
///
/// 1. **207 Multistatus may carry per-entry errors.** A 207 is not blanket
///    success. Every response element is inspected and partial failures are
///    surfaced rather than swallowed.
/// 2. **The ceiling is shared per network** — 600 requests/min, 10 concurrent.
///    Every request goes through the scheduler for that reason.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../core/config/app_config.dart';
import '../../core/error/puter_exception.dart';
import '../../core/network/request_scheduler.dart';
import '../../domain/entities/remote_node.dart';
import 'puter_transport.dart';

/// Talks to Puter's WebDAV endpoint.
class WebDavTransport implements PuterTransport {
  WebDavTransport({
    required RequestScheduler scheduler,
    required AppConfig config,
    Dio? client,
    String? baseUrl,
  })  : _scheduler = scheduler,
        _config = config,
        _baseUrl = baseUrl,
        _client = client ?? _defaultClient(config);

  static Dio _defaultClient(AppConfig config) => Dio(
        BaseOptions(
          connectTimeout: config.requestTimeout,
          receiveTimeout: config.transferTimeout,
          // WebDAV legitimately returns 207, 4xx and 5xx bodies we must read in
          // order to classify them, so status validation is explicit rather
          // than delegated to Dio.
          validateStatus: (_) => true,
        ),
      );

  final RequestScheduler _scheduler;
  final AppConfig _config;
  final Dio _client;

  String? _baseUrl;
  TokenCredential? _credential;
  bool _authenticated = false;

  @override
  String get name => 'webdav';

  /// The base URL that answered the probe, or `null` before authentication.
  ///
  /// Exposed for the diagnostics screen: when two of the three candidate hosts
  /// exist, which one is actually serving the account is the first thing worth
  /// knowing about a connection problem.
  String? get endpoint => _baseUrl;

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canList: true,
        canStat: true,
        canWrite: true,
        canRead: true,
        canMutate: true,
        // Pending Phase 0: WebDAV PUT with Content-Range is not universally
        // implemented. Enabled only once a ranged PUT is observed to work.
        canResumeUpload: false,
        canResumeDownload: true,
        // RFC 4331 quota properties, when the server reports them.
        canReportUsage: true,
        canSignReadUrl: false,
        canShare: false,
        supportsSearch: false,
      );

  // ---------------------------------------------------------------- lifecycle

  /// Probe the candidate hosts and return the first that answers a `PROPFIND`.
  ///
  /// **Attempts are counted against the failed-sign-in lockout.** Ten failures
  /// in 15 minutes return 429 even for a correct token, so this must be called
  /// once per user action and never inside a retry loop.
  static Future<String> probe({
    required TokenCredential credential,
    Dio? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final owned = client == null;
    final http = client ??
        Dio(
          BaseOptions(
            connectTimeout: timeout,
            receiveTimeout: timeout,
            validateStatus: (_) => true,
          ),
        );

    try {
      for (final candidate in PuterEndpoints.webdavHostCandidates) {
        try {
          final response = await http.request<dynamic>(
            candidate,
            data: _propfindBody(includeQuota: false),
            options: Options(
              method: 'PROPFIND',
              headers: <String, dynamic>{
                'Depth': '0',
                'Authorization': _basicAuthHeader(credential),
                'Content-Type': 'application/xml; charset=utf-8',
              },
              responseType: ResponseType.plain,
              followRedirects: false,
            ),
          );
          // 207 is the success case for PROPFIND.
          if (response.statusCode == 207 || response.statusCode == 200) {
            return candidate;
          }
        } on Object {
          // Host unreachable; try the next candidate.
          continue;
        }
      }
    } finally {
      if (owned) http.close(force: true);
    }

    throw const PuterException(
      PuterErrorKind.network,
      'No WebDAV host responded to a PROPFIND probe. Confirm the endpoint '
      'against the live account before falling back to the WebView transport.',
    );
  }

  @override
  Future<void> authenticate(TokenCredential credential) async {
    _credential = credential;
    _baseUrl ??= await probe(credential: credential);

    // Exactly one attempt. No retry — see the class documentation.
    final response = await _send<Response<dynamic>>(
      RequestClass.stat,
      () => _client.request<dynamic>(
        _baseUrl!,
        data: _propfindBody(includeQuota: true),
        options: Options(
          method: 'PROPFIND',
          headers: _headers(depth: '0'),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      _scheduler.recordAuthFailure();
      throw PuterException(
        PuterErrorKind.authInvalid,
        'Puter rejected the auth token. Check that it is current and has not '
        'been revoked at ${PuterEndpoints.dashboardAccount}.',
        statusCode: status,
      );
    }
    if (status == 429) {
      _scheduler.recordAuthFailure();
      throw const PuterException(
        PuterErrorKind.rateLimited,
        'Too many failed sign-ins. WebDAV locks the account for 15 minutes '
        'after 10 failures and then returns 429 even for a correct token. Wait '
        'before retrying — the Puter desktop and web UI still work meanwhile, '
        'so your token itself is probably fine.',
        statusCode: 429,
      );
    }
    if (status != 207 && status != 200) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'WebDAV authentication probe failed.',
      );
    }

    _scheduler.recordAuthSuccess();
    _authenticated = true;
  }

  @override
  Future<PuterIdentity> identity() async {
    _assertAuthenticated();
    // WebDAV exposes no identity endpoint. The account name is surfaced from
    // the WebView transport when available, or reported as unknown here.
    return const PuterIdentity(username: 'unknown');
  }

  // ------------------------------------------------------------------ listing

  @override
  Future<RemoteNodePage> list(ListRequest request) async {
    _assertAuthenticated();

    final response = await _send<Response<dynamic>>(
      RequestClass.readdir,
      () => _client.request<dynamic>(
        _url(request.path),
        data: _propfindBody(includeQuota: false),
        options: Options(
          method: 'PROPFIND',
          headers: _headers(depth: request.recursive ? 'infinity' : '1'),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 404) {
      throw PuterException(
        PuterErrorKind.notFound,
        'Directory not found.',
        statusCode: status,
        path: request.path,
      );
    }
    if (status != 207) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'PROPFIND failed for ${request.path}.',
        path: request.path,
      );
    }

    final parsed = _parseMultistatus(_bodyOf(response));

    // The first entry of a depth-1 PROPFIND is the collection itself.
    final requested = _normalisePath(request.path);
    final items = parsed.nodes
        .where((node) => _normalisePath(node.path) != requested)
        .toList(growable: false);

    final sorted = _applySort(items, request);

    // WebDAV has no cursor. Paging is a window over the parsed result, and the
    // local index absorbs the cost rather than the network.
    final limit = request.limit ?? _config.listingPageSize;
    final offset = int.tryParse(request.cursor ?? '0') ?? 0;
    final window = sorted.skip(offset).take(limit).toList(growable: false);
    final nextOffset = offset + window.length;

    return RemoteNodePage(
      items: window,
      cursor: nextOffset < sorted.length ? '$nextOffset' : null,
      total: request.includeTotal ? sorted.length : null,
      // A 207 can succeed overall while individual entries fail. Carrying these
      // up is the difference between "this folder has 3 files" and "this folder
      // has 6 files, 3 of which could not be read" — the user deserves the
      // second answer.
      failures: parsed.failures
          .map(
            (failure) => NodeFailure(
              path: failure.path,
              message: failure.message,
              statusCode: failure.statusCode,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<RemoteNode> stat(String path) async {
    _assertAuthenticated();

    final response = await _send<Response<dynamic>>(
      RequestClass.stat,
      () => _client.request<dynamic>(
        _url(path),
        data: _propfindBody(includeQuota: false),
        options: Options(
          method: 'PROPFIND',
          headers: _headers(depth: '0'),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 404) {
      throw PuterException(
        PuterErrorKind.notFound,
        'Path not found.',
        statusCode: status,
        path: path,
      );
    }
    if (status != 207) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'stat failed for $path.',
        path: path,
      );
    }

    final parsed = _parseMultistatus(_bodyOf(response));
    if (parsed.nodes.isEmpty) {
      throw PuterException(
        PuterErrorKind.notFound,
        'Path not found.',
        path: path,
      );
    }
    return parsed.nodes.first;
  }

  // ----------------------------------------------------------------- mutation

  @override
  Future<void> createDirectory(String path, {bool createParents = true}) async {
    _assertAuthenticated();

    if (!createParents) {
      await _mkcol(path);
      return;
    }

    // MKCOL does not create intermediate collections, so walk the path.
    var current = '';
    for (final segment in _segments(path)) {
      current = '$current/$segment';
      final isLeaf = current == _normalisePath(path);
      try {
        await _mkcol(current);
      } on PuterException catch (error) {
        // 405 means the collection already exists. Acceptable while creating
        // parents; an error for the leaf, where the caller expects a new one.
        if (error.kind == PuterErrorKind.alreadyExists && !isLeaf) continue;
        rethrow;
      }
    }
  }

  Future<void> _mkcol(String path) async {
    final response = await _send<Response<dynamic>>(
      RequestClass.mutation,
      () => _client.request<dynamic>(
        _url(path),
        options: Options(
          method: 'MKCOL',
          headers: _headers(),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 405) {
      throw PuterException(
        PuterErrorKind.alreadyExists,
        'A directory already exists at this path.',
        statusCode: status,
        path: path,
      );
    }
    if (status != 201 && status != 200 && status != 204) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'Could not create directory.',
        path: path,
      );
    }
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    _assertAuthenticated();

    final response = await _send<Response<dynamic>>(
      RequestClass.mutation,
      () => _client.request<dynamic>(
        _url(path),
        options: Options(
          method: 'DELETE',
          headers: _headers(depth: recursive ? 'infinity' : '0'),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 404) {
      throw PuterException(
        PuterErrorKind.notFound,
        'Path not found.',
        statusCode: status,
        path: path,
      );
    }
    if (status != 204 && status != 200) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'Delete failed.',
        path: path,
      );
    }
  }

  @override
  Future<void> move(String from, String to, {bool overwrite = false}) =>
      _destination('MOVE', from, to, overwrite: overwrite);

  @override
  Future<void> copy(String from, String to, {bool overwrite = false}) =>
      _destination('COPY', from, to, overwrite: overwrite);

  Future<void> _destination(
    String method,
    String from,
    String to, {
    required bool overwrite,
  }) async {
    _assertAuthenticated();

    final response = await _send<Response<dynamic>>(
      RequestClass.mutation,
      () => _client.request<dynamic>(
        _url(from),
        options: Options(
          method: method,
          headers: _headers(
            destination: _url(to),
            overwrite: overwrite ? 'T' : 'F',
          ),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 412) {
      throw PuterException(
        PuterErrorKind.alreadyExists,
        'A file already exists at the destination.',
        statusCode: status,
        path: to,
      );
    }
    if (status != 201 && status != 204 && status != 200) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: '$method failed.',
        path: from,
      );
    }
  }

  // ----------------------------------------------------------------- transfer

  @override
  Future<RemoteNode> upload(UploadRequest request) async {
    _assertAuthenticated();

    final file = File(request.localPath);
    if (!file.existsSync()) {
      throw PuterException(
        PuterErrorKind.notFound,
        'Local file does not exist.',
        path: request.localPath,
      );
    }

    if (request.createMissingParents) {
      final parent = _parentOf(request.remotePath);
      if (parent != null && parent.isNotEmpty) {
        await createDirectory(parent);
      }
    }

    // Streamed body: never load the file into memory. This is the whole reason
    // WebDAV was chosen over the WebView bridge.
    final total = file.lengthSync();
    final cancelled = _watchCancellation(request.cancelSignal);

    // Count bytes as they leave rather than relying on Dio's `onSendProgress`,
    // which does not fire reliably for a streamed body whose length Dio cannot
    // infer. Progress that silently reports zero is worse than no progress:
    // the user sees a stalled transfer and assumes it has hung.
    var sent = 0;
    final body = file.openRead().map((chunk) {
      // Checked per chunk, which is as promptly as a chunked PUT can be
      // interrupted: the connection has to be abandoned at a chunk boundary or
      // the server sees a truncated body with no way to tell it from a network
      // failure.
      if (cancelled()) throw const TransferCancelled();
      sent += chunk.length;
      request.onProgress?.call(sent, total);
      return chunk;
    });

    final response = await _asCancellation(
      () => _send<Response<dynamic>>(
        RequestClass.write,
        () => _client.put<dynamic>(
          _url(request.remotePath),
          data: body,
          options: Options(
            headers: _headers(
              contentType: 'application/octet-stream',
              extra: <String, dynamic>{
                // Declared explicitly so the server can enforce its quota before
                // receiving the whole body, and so Dio does not chunk-encode.
                Headers.contentLengthHeader: '$total',
                if (!request.overwrite) 'If-None-Match': '*',
              },
            ),
            followRedirects: false,
          ),
        ),
        // A file transfer is not an interactive request. The default request
        // timeout would abort every upload that takes longer than 30 seconds,
        // which is most of them.
        timeout: _config.transferTimeout,
      ),
    );

    final status = response.statusCode ?? 0;
    if (status == 412) {
      throw PuterException(
        PuterErrorKind.alreadyExists,
        'A file already exists at this path and overwrite was not requested.',
        statusCode: status,
        path: request.remotePath,
      );
    }
    if (status == 413) {
      throw PuterException(
        PuterErrorKind.storageLimitReached,
        'Upload exceeds the storage quota. Free space or upgrade the plan, '
        'then retry. Existing files are unaffected and remain readable.',
        statusCode: status,
        code: 'storage_limit_reached',
        path: request.remotePath,
      );
    }
    if (status != 201 && status != 204 && status != 200) {
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'Upload failed.',
        path: request.remotePath,
      );
    }

    return stat(request.remotePath);
  }

  @override
  Future<void> download(DownloadRequest request) async {
    _assertAuthenticated();

    final target = File(request.localPath);
    target.parent.createSync(recursive: true);

    // Resume is derived from disk, not from the caller. The staging file *is*
    // the transfer state: whatever it holds is what we already have. Trusting
    // a caller-supplied offset would allow a mismatch, and writing at the wrong
    // offset yields a file that looks plausible but is corrupt.
    final staging = File(request.stagingPath);
    final offset = staging.existsSync() ? staging.lengthSync() : 0;
    final cancelled = _watchCancellation(request.cancelSignal);

    final response = await _send<Response<dynamic>>(
      RequestClass.read,
      () => _client.get<ResponseBody>(
        _url(request.remotePath),
        options: Options(
          headers: _headers(
            extra: <String, dynamic>{
              if (offset > 0) 'Range': 'bytes=$offset-',
            },
          ),
          responseType: ResponseType.stream,
          followRedirects: false,
        ),
      ),
      timeout: _config.transferTimeout,
    );

    final status = response.statusCode ?? 0;
    if (status != 200 && status != 206) {
      if (staging.existsSync()) staging.deleteSync();
      throw ErrorMapper.fromResponse(
        status: status,
        message: 'Download failed.',
        path: request.remotePath,
      );
    }

    // 200 in answer to a Range request means the server ignored the header and
    // is resending from the start. Appending would corrupt the file, so discard
    // the partial data and retry cleanly — the recursion sees offset 0.
    if (status == 200 && offset > 0) {
      staging.deleteSync();
      return download(
        DownloadRequest(
          remotePath: request.remotePath,
          localPath: request.localPath,
          onProgress: request.onProgress,
          cancelSignal: request.cancelSignal,
        ),
      );
    }

    // Annotated explicitly: response.data is dynamic, and letting that
    // propagate would make chunk.length a num rather than an int.
    final ResponseBody? body = response.data as ResponseBody?;
    if (body == null) {
      if (staging.existsSync()) staging.deleteSync();
      throw const PuterException(
        PuterErrorKind.protocol,
        'Download response had no body.',
      );
    }

    final declared =
        int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ??
            0;
    final expectedTotal = declared + offset;
    final sink = staging.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var written = offset;

    try {
      await for (final chunk in body.stream) {
        // Cancellation is checked here rather than mid-chunk: whatever has
        // already been written stays in the staging file, which is what makes
        // the next attempt resume instead of restart.
        if (cancelled()) throw const TransferCancelled();
        sink.add(chunk);
        written += chunk.length;
        request.onProgress?.call(written, expectedTotal);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // Leave the staging file in place so the next attempt can resume from it
      // rather than starting the whole transfer again.
      await sink.close();
      rethrow;
    }

    // Promote only once the whole body has landed.
    if (target.existsSync()) target.deleteSync();
    staging.renameSync(request.localPath);
  }

  // -------------------------------------------------------------------- usage

  @override
  Future<StorageUsage> usage() async {
    _assertAuthenticated();

    // RFC 4331 quota properties. Servers are free not to implement them, in
    // which case the caller falls back to the WebView transport's `fs.space()`
    // rather than guessing a capacity.
    final response = await _send<Response<dynamic>>(
      RequestClass.usage,
      () => _client.request<dynamic>(
        _url('/'),
        data: _propfindBody(includeQuota: true),
        options: Options(
          method: 'PROPFIND',
          headers: _headers(depth: '0'),
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      ),
    );

    if ((response.statusCode ?? 0) != 207) {
      throw const PuterException(
        PuterErrorKind.unsupported,
        'This endpoint does not report quota over WebDAV. Use the WebView '
        'transport for fs.space().',
      );
    }

    final document = XmlDocument.parse(_bodyOf(response));
    final available = _numeric(document, 'quota-available-bytes');
    final used = _numeric(document, 'quota-used-bytes');

    if (available == null || used == null) {
      throw const PuterException(
        PuterErrorKind.unsupported,
        'Quota properties are absent from the WebDAV response. Use the '
        'WebView transport for fs.space().',
      );
    }

    return StorageUsage(capacityBytes: available + used, usedBytes: used);
  }

  @override
  Future<Uri> signedReadUrl(
    String path, {
    Duration ttl = const Duration(hours: 1),
  }) async {
    // WebDAV has no signing mechanism. The application falls back to the
    // WebView transport's fs.getReadURL(), which is exactly the division of
    // labour ADR 0002 describes.
    throw const PuterException(
      PuterErrorKind.unsupported,
      'WebDAV cannot generate signed read URLs. Use the WebView transport.',
    );
  }

  @override
  Future<void> dispose() async {
    _client.close(force: true);
    _credential = null;
    _authenticated = false;
  }

  // ------------------------------------------------------------------ internals

  void _assertAuthenticated() {
    if (!_authenticated) {
      throw const PuterException(
        PuterErrorKind.authInvalid,
        'Transport is not authenticated. Complete onboarding first.',
      );
    }
  }

  /// Route a request through the scheduler so it counts against the budget.
  ///
  /// [timeout] bounds the whole call — queue wait *and* execution — so file
  /// transfers pass [AppConfig.transferTimeout] rather than the interactive
  /// default. Using the request timeout for an upload would abort it after 30
  /// seconds regardless of how well it was progressing.
  Future<T> _send<T>(
    RequestClass klass,
    Future<T> Function() operation, {
    RequestPriority priority = RequestPriority.interactive,
    Duration? timeout,
  }) {
    return _scheduler.schedule<T>(
      klass,
      operation,
      priority: priority,
      timeout: timeout ?? _config.requestTimeout,
    );
  }

  /// Build a pollable view of a cooperative cancel signal.
  ///
  /// The interface takes a `Future` because that is what a caller can complete
  /// from anywhere, but the streaming loops above need to ask a question
  /// synchronously at each chunk boundary. Subscribing once and setting a flag
  /// is the entire mechanism.
  ///
  /// A signal that completes *after* the transfer has finished is harmless: the
  /// engine drops the task, and nothing reads the flag again.
  static bool Function() _watchCancellation(Future<void>? signal) {
    if (signal == null) return () => false;
    var cancelled = false;
    unawaited(signal.then((_) => cancelled = true, onError: (_) {}));
    return () => cancelled;
  }

  /// Run [operation], normalising a cancellation back to [TransferCancelled].
  ///
  /// Dio wraps an error thrown from a request body stream in its own
  /// [DioException], so a bare `throw TransferCancelled()` inside the upload
  /// stream would otherwise reach the caller as an unclassified protocol
  /// failure and be reported to the user as one.
  Future<T> _asCancellation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error) {
      if (error is TransferCancelled) rethrow;
      if (error is DioException && error.error is TransferCancelled) {
        throw const TransferCancelled();
      }
      rethrow;
    }
  }

  Map<String, dynamic> _headers({
    String? depth,
    String? destination,
    String? overwrite,
    String? contentType,
    Map<String, dynamic>? extra,
  }) {
    final credential = _credential;
    if (credential == null) {
      throw const PuterException(
        PuterErrorKind.authInvalid,
        'No credential is bound to this transport.',
      );
    }
    return <String, dynamic>{
      'Authorization': _basicAuthHeader(credential),
      if (depth != null) 'Depth': depth,
      if (destination != null) 'Destination': destination,
      if (overwrite != null) 'Overwrite': overwrite,
      'Content-Type': contentType ?? 'application/xml; charset=utf-8',
      ...?extra,
    };
  }

  /// Puter's documented WebDAV convention: username `-token`, password is the
  /// API token. This skips the per-account sign-in ceiling, and the token is
  /// revocable from the dashboard without changing the account password.
  static String _basicAuthHeader(TokenCredential credential) {
    final raw = '-token:${credential.token}';
    return 'Basic ${base64Encode(utf8.encode(raw))}';
  }

  String _url(String path) {
    final base = _baseUrl;
    if (base == null) {
      throw const PuterException(
        PuterErrorKind.network,
        'WebDAV base URL has not been resolved. Call authenticate() first.',
      );
    }
    final normalised = path.startsWith('/') ? path : '/$path';
    return '$base${Uri.encodeFull(normalised)}';
  }

  static String _bodyOf(Response<dynamic> response) {
    final data = response.data;
    if (data is String) return data;
    if (data is List<int>) return utf8.decode(data, allowMalformed: true);
    return data?.toString() ?? '';
  }

  static String _propfindBody({required bool includeQuota}) {
    final quota =
        includeQuota ? '<d:quota-available-bytes/><d:quota-used-bytes/>' : '';
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:displayname/>'
        '<d:getcontentlength/>'
        '<d:getlastmodified/>'
        '<d:getcontenttype/>'
        '<d:getetag/>'
        '<d:resourcetype/>'
        '$quota'
        '</d:prop></d:propfind>';
  }

  static String _normalisePath(String path) {
    if (path.isEmpty) return '/';
    var result = path.startsWith('/') ? path : '/$path';
    if (result.length > 1 && result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return Uri.decodeFull(result);
  }

  static List<String> _segments(String path) => path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  static String? _parentOf(String path) {
    final normalised = _normalisePath(path);
    final index = normalised.lastIndexOf('/');
    if (index <= 0) return null;
    return normalised.substring(0, index);
  }

  /// Parse a WebDAV `207 Multistatus` body.
  ///
  /// Inspects every `response` element's `propstat` status. A 207 is **not**
  /// blanket success: individual entries can fail, and a client that treats
  /// 207 as success will silently lose files.
  static _ParsedMultistatus _parseMultistatus(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException catch (error) {
      throw PuterException(
        PuterErrorKind.protocol,
        'Could not parse the WebDAV response as XML.',
        cause: error,
      );
    }

    final nodes = <RemoteNode>[];
    final failures = <FailedItem>[];

    for (final response
        in document.findAllElements('response', namespace: 'DAV:')) {
      final href = response
          .findElements('href', namespace: 'DAV:')
          .map((element) => element.innerText.trim())
          .firstOrNull;
      if (href == null) continue;

      final path = Uri.decodeFull(Uri.parse(href).path);

      // Properties often come back split across several propstat blocks with
      // different statuses; find the one that actually succeeded.
      XmlElement? successfulProp;
      String? failingStatus;
      for (final propstat
          in response.findElements('propstat', namespace: 'DAV:')) {
        final status = propstat
            .findElements('status', namespace: 'DAV:')
            .map((element) => element.innerText)
            .firstOrNull;
        if (status != null && status.contains('200')) {
          successfulProp =
              propstat.findElements('prop', namespace: 'DAV:').firstOrNull;
          break;
        }
        failingStatus ??= status;
      }

      if (successfulProp == null) {
        // Every propstat failed for this entry. Record it rather than dropping
        // it silently. Note the status lives *inside* the propstat, not as a
        // direct child of response — reading only response-level children
        // loses the reason the entry failed.
        failures.add(
          FailedItem(
            path: path,
            message: 'No successful propstat in the WebDAV response.',
            statusCode: _statusCodeOf(failingStatus),
          ),
        );
        continue;
      }

      final isDirectory = successfulProp
          .findElements('resourcetype', namespace: 'DAV:')
          .expand(
            (element) => element.findElements('collection', namespace: 'DAV:'),
          )
          .isNotEmpty;

      final displayName = _textOf(successfulProp, 'displayname');
      final name = (displayName != null && displayName.isNotEmpty)
          ? displayName
          : _lastSegment(path);

      nodes.add(
        RemoteNode(
          path: path,
          name: name,
          isDirectory: isDirectory,
          sizeBytes: _intOf(successfulProp, 'getcontentlength') ?? 0,
          modifiedAt: _dateOf(successfulProp, 'getlastmodified'),
          mimeType: _textOf(successfulProp, 'getcontenttype'),
          etag: _textOf(successfulProp, 'getetag')?.replaceAll('"', ''),
          indexedAt: DateTime.now(),
        ),
      );
    }

    return _ParsedMultistatus(nodes: nodes, failures: failures);
  }

  static String? _textOf(XmlElement parent, String localName) {
    final element =
        parent.findElements(localName, namespace: 'DAV:').firstOrNull;
    final text = element?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static int? _intOf(XmlElement parent, String localName) {
    final text = _textOf(parent, localName);
    return text == null ? null : int.tryParse(text);
  }

  static DateTime? _dateOf(XmlElement parent, String localName) {
    final text = _textOf(parent, localName);
    if (text == null) return null;
    // WebDAV mandates RFC 1123 for getlastmodified, but servers vary. Try both
    // that and ISO 8601 before giving up.
    return _tryParseHttpDate(text) ?? DateTime.tryParse(text);
  }

  static DateTime? _tryParseHttpDate(String text) {
    try {
      return HttpDate.parse(text);
    } on Object {
      return null;
    }
  }

  static int? _statusCodeOf(String? statusLine) {
    if (statusLine == null) return null;
    final match = RegExp(r'\s(\d{3})\s').firstMatch(statusLine);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int? _numeric(XmlDocument document, String localName) {
    final element =
        document.findAllElements(localName, namespace: 'DAV:').firstOrNull;
    final text = element?.innerText.trim();
    return (text == null || text.isEmpty) ? null : int.tryParse(text);
  }

  static String _lastSegment(String path) {
    final segments = _segments(path);
    return segments.isEmpty ? '/' : segments.last;
  }

  static List<RemoteNode> _applySort(
    List<RemoteNode> items,
    ListRequest request,
  ) {
    final sorted = List<RemoteNode>.from(items)
      ..sort((a, b) {
        // Directories first is a UI convention the server does not provide.
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        final comparison = switch (request.sortBy) {
          NodeSortField.name =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          NodeSortField.size => a.sizeBytes.compareTo(b.sizeBytes),
          NodeSortField.modified =>
            (a.modifiedAt ?? DateTime(0)).compareTo(b.modifiedAt ?? DateTime(0)),
          NodeSortField.type => a.extension.compareTo(b.extension),
        };
        return request.sortOrder == SortOrder.ascending
            ? comparison
            : -comparison;
      });
    return sorted;
  }
}

class _ParsedMultistatus {
  const _ParsedMultistatus({required this.nodes, required this.failures});

  final List<RemoteNode> nodes;
  final List<FailedItem> failures;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
