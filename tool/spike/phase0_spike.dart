// Phase 0 feasibility spike.
//
// Throwaway diagnostic, not production code. It answers the eight questions in
// docs/roadmap.md that gate the whole project, and prints a report that gets
// appended to docs/puter-api-research.md.
//
// Deliberately self-contained: it does not import from lib/, because lib/
// depends on Flutter and this runs under plain `dart run`.
//
// Usage:
//   PUTER_AUTH_TOKEN=<token> dart run tool/spike/phase0_spike.dart
//
// Create the token at https://puter.com/dashboard#account -> Create token.
//
// WARNING: authentication failures are counted against WebDAV's lockout budget.
// Ten failed sign-ins in 15 minutes return 429 even for a correct token. This
// script attempts each host ONCE and never retries.

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

const List<String> _hostCandidates = <String>[
  'https://dav.puter.com',
  'https://webdav.puter.com',
  'https://api.puter.com/dav',
];

const String _driverCall = 'https://api.puter.com/drivers/call';

Future<void> main(List<String> args) async {
  final token = Platform.environment['PUTER_AUTH_TOKEN']?.trim();
  if (token == null || token.isEmpty) {
    stderr.writeln('PUTER_AUTH_TOKEN is not set.');
    stderr.writeln('Create one at https://puter.com/dashboard#account');
    exitCode = 64;
    return;
  }

  stdout.writeln('=== Phase 0 spike: Puter feasibility ===\n');

  // ---------------------------------------------------------------- Q2 and Q3
  stdout.writeln('Q2/Q3. Probing WebDAV host candidates and verbs.');
  stdout.writeln('       One attempt per host — failures count toward the '
      '15-minute lockout.\n');

  String? workingHost;
  for (final host in _hostCandidates) {
    stdout.writeln('  $host');
    final result = await _probeHost(host, token);
    stdout.writeln('    PROPFIND depth 0 -> ${result.describe()}');
    if (result.isSuccess) {
      workingHost = host;
      stdout.writeln('    ^ selected');
      break;
    }
  }

  if (workingHost == null) {
    stdout.writeln(
      '\n  NO WEBDAV HOST RESPONDED.\n'
      '  → ADR 0002 inverts: the WebView bridge becomes the primary transport\n'
      '    and the transfer engine must be redesigned around base64 chunking.\n',
    );
  } else {
    stdout.writeln('\n  Selected host: $workingHost\n');

    // ------------------------------------------------------------------ verbs
    stdout.writeln('Q3. Probing implemented verbs on $workingHost');
    await _probeVerbs(workingHost, token);

    // ------------------------------------------------------------- Q4 and Q1
    stdout.writeln('\nQ4/Q1. Root listing and quota.');
    await _probeRootAndQuota(workingHost, token);

    // ------------------------------------------------------------------- Q5
    stdout.writeln('\nQ5. Does PUT honour Content-Range (resumable upload)?');
    await _probeRangedPut(workingHost, token);

    // ------------------------------------------------------------------- Q6
    stdout.writeln('\nQ6. Sustained request rate before 429.');
    await _probeSustainedRate(workingHost, token);

    // ------------------------------------------------------------------- Q7
    stdout.writeln('\nQ7. Throughput on a 100 MB transfer.');
    await _probeThroughput(workingHost, token);
  }

  // -------------------------------------------------------------- Q1 (API)
  stdout.writeln('\nQ1. Live quota via the driver interface (fs.space).');
  await _probeQuotaViaDriver(token);

  stdout.writeln('\n=== Spike complete ===');
  stdout.writeln(
    'Record every answer in docs/puter-api-research.md §8 before writing any\n'
    'feature code. In particular: if capacity is ~104,857,600 bytes (100 MiB)\n'
    'rather than ~332,860,000,000 (310 GiB), the project premise is wrong.',
  );
}

// --------------------------------------------------------------------- probes

class ProbeResult {
  const ProbeResult(this.status, this.note);

  final int? status;
  final String note;

  bool get isSuccess => status == 207 || status == 200;

  String describe() => status == null ? 'FAILED ($note)' : '$status $note';
}

Future<ProbeResult> _probeHost(String host, String token) async {
  final dio = _client();
  try {
    final response = await dio.request<dynamic>(
      host,
      data: _propfindBody(includeQuota: false),
      options: Options(
        method: 'PROPFIND',
        headers: <String, dynamic>{
          'Depth': '0',
          'Authorization': _basicAuth(token),
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
        followRedirects: false,
      ),
    );
    return ProbeResult(response.statusCode, _explain(response.statusCode));
  } on Object catch (error) {
    return ProbeResult(null, error.toString());
  } finally {
    dio.close(force: true);
  }
}

Future<void> _probeVerbs(String host, String token) async {
  final dio = _client();
  final probePath = '$host/__phase0_probe__';

  Future<void> attempt(String verb, Future<Response<dynamic>> Function() run) async {
    try {
      final response = await run();
      stdout.writeln('    $verb -> ${response.statusCode} '
          '${_explain(response.statusCode)}');
    } on Object catch (error) {
      stdout.writeln('    $verb -> FAILED ($error)');
    }
  }

  await attempt('OPTIONS', () => dio.request<dynamic>(
        host,
        options: Options(
          method: 'OPTIONS',
          headers: _authHeaders(token),
          followRedirects: false,
        ),
      ));

  await attempt('MKCOL', () => dio.request<dynamic>(
        probePath,
        options: Options(
          method: 'MKCOL',
          headers: _authHeaders(token),
          followRedirects: false,
        ),
      ));

  await attempt('PUT', () => dio.request<dynamic>(
        '$probePath/probe.txt',
        data: 'phase0',
        options: Options(
          method: 'PUT',
          headers: _authHeaders(token),
          followRedirects: false,
        ),
      ));

  await attempt('GET', () => dio.get<dynamic>(
        '$probePath/probe.txt',
        options: Options(headers: _authHeaders(token), followRedirects: false),
      ));

  await attempt('HEAD', () => dio.request<dynamic>(
        '$probePath/probe.txt',
        options: Options(
          method: 'HEAD',
          headers: _authHeaders(token),
          followRedirects: false,
        ),
      ));

  await attempt('COPY', () => dio.request<dynamic>(
        '$probePath/probe.txt',
        options: Options(
          method: 'COPY',
          headers: <String, dynamic>{
            ..._authHeaders(token),
            'Destination': '$probePath/probe-copy.txt',
            'Overwrite': 'T',
          },
          followRedirects: false,
        ),
      ));

  await attempt('MOVE', () => dio.request<dynamic>(
        '$probePath/probe-copy.txt',
        options: Options(
          method: 'MOVE',
          headers: <String, dynamic>{
            ..._authHeaders(token),
            'Destination': '$probePath/probe-moved.txt',
            'Overwrite': 'T',
          },
          followRedirects: false,
        ),
      ));

  await attempt('DELETE', () => dio.request<dynamic>(
        probePath,
        options: Options(
          method: 'DELETE',
          headers: <String, dynamic>{
            ..._authHeaders(token),
            'Depth': 'infinity',
          },
          followRedirects: false,
        ),
      ));

  dio.close(force: true);
}

Future<void> _probeRootAndQuota(String host, String token) async {
  final dio = _client();
  try {
    final response = await dio.request<dynamic>(
      host,
      data: _propfindBody(includeQuota: true),
      options: Options(
        method: 'PROPFIND',
        headers: <String, dynamic>{
          'Depth': '1',
          'Authorization': _basicAuth(token),
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
        followRedirects: false,
      ),
    );

    stdout.writeln('    PROPFIND depth 1 on root -> ${response.statusCode}');
    final body = response.data?.toString() ?? '';
    if (body.isEmpty) {
      stdout.writeln('    (empty body)');
      return;
    }

    final document = XmlDocument.parse(body);
    final responses = document.findAllElements('response', namespace: 'DAV:');
    stdout.writeln('    ${responses.length} entries at the root');

    final available = _numeric(document, 'quota-available-bytes');
    final used = _numeric(document, 'quota-used-bytes');

    if (available != null && used != null) {
      final capacity = available + used;
      stdout.writeln('    Q1 ANSWER — quota from WebDAV (RFC 4331):');
      stdout.writeln('      used      : ${_bytes(used)}');
      stdout.writeln('      available : ${_bytes(available)}');
      stdout.writeln('      capacity  : ${_bytes(capacity)}  '
          '<-- compare against 310 GiB');
      if (capacity < 1024 * 1024 * 1024) {
        stdout.writeln(
          '      !! Under 1 GiB. The 310 GB premise does not hold for this '
          'endpoint.\n'
          '         Confirm with fs.space() before concluding.',
        );
      }
    } else {
      stdout.writeln('    Quota properties absent. WebDAV cannot report '
          'capacity here —\n    use fs.space() via the WebView transport '
          '(see Q1 below).');
    }
  } on Object catch (error) {
    stdout.writeln('    FAILED ($error)');
  } finally {
    dio.close(force: true);
  }
}

Future<void> _probeRangedPut(String host, String token) async {
  final dio = _client();
  final path = '$host/__phase0_ranged__.bin';
  try {
    // Establish a 20-byte file first.
    await dio.put<dynamic>(
      path,
      data: List<int>.filled(20, 0x41),
      options: Options(headers: _authHeaders(token), followRedirects: false),
    );

    // Then attempt a ranged continuation. A conforming server returns 204 or
    // 200; one that ignores Content-Range returns 200 and clobbers the file.
    final response = await dio.put<dynamic>(
      path,
      data: List<int>.filled(10, 0x42),
      options: Options(
        headers: <String, dynamic>{
          ..._authHeaders(token),
          'Content-Range': 'bytes 20-29/30',
        },
        followRedirects: false,
      ),
    );

    final size = await _remoteSize(dio, host, path, token);
    stdout.writeln('    ranged PUT -> ${response.statusCode}');
    stdout.writeln('    resulting size -> ${size ?? 'unknown'} bytes');
    stdout.writeln(
      size == 30
          ? '    RESUME SUPPORTED — enable canResumeUpload.'
          : '    RESUME NOT SUPPORTED (expected 30 bytes, got $size).\n'
              '    → Drop resumable upload from MVP; keep resume for downloads.',
    );

    await dio.delete<dynamic>(
      path,
      options: Options(headers: _authHeaders(token), followRedirects: false),
    );
  } on Object catch (error) {
    stdout.writeln('    FAILED ($error)');
  } finally {
    dio.close(force: true);
  }
}

Future<void> _probeSustainedRate(String host, String token) async {
  final dio = _client();
  var issued = 0;
  int? firstFailureAt;
  try {
    for (var i = 0; i < 700; i++) {
      final response = await dio.request<dynamic>(
        host,
        data: _propfindBody(includeQuota: false),
        options: Options(
          method: 'PROPFIND',
          headers: <String, dynamic>{
            'Depth': '0',
            'Authorization': _basicAuth(token),
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
          followRedirects: false,
        ),
      );
      issued++;
      if (response.statusCode == 429) {
        firstFailureAt = issued;
        break;
      }
    }
  } on Object catch (error) {
    stdout.writeln('    stopped at $issued requests ($error)');
  } finally {
    dio.close(force: true);
  }

  if (firstFailureAt != null) {
    stdout.writeln('    first 429 after $firstFailureAt requests');
    stdout.writeln('    Documented ceiling is 600/min per network. If this is '
        'materially lower,\n    the scheduler defaults in AppConfig need '
        'tightening.');
  } else {
    stdout.writeln('    $issued requests completed with no 429. Either the '
        'ceiling is per-network\n    and this network is quiet, or the '
        'documented 600/min is not enforced.');
  }
}

Future<void> _probeThroughput(String host, String token) async {
  final dio = _client();
  final path = '$host/__phase0_speed__.bin';
  const size = 100 * 1024 * 1024;
  try {
    stdout.writeln('    uploading ${_bytes(size)}…');
    final uploadWatch = Stopwatch()..start();
    await dio.put<dynamic>(
      path,
      data: _repeatingStream(size),
      options: Options(
        headers: <String, dynamic>{
          ..._authHeaders(token),
          'Content-Length': '$size',
        },
        followRedirects: false,
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    uploadWatch.stop();
    final uploadSeconds = uploadWatch.elapsedMilliseconds / 1000;
    stdout.writeln('    upload: ${uploadSeconds.toStringAsFixed(1)}s '
        '(${(size / 1024 / 1024 / uploadSeconds).toStringAsFixed(1)} MiB/s)');

    stdout.writeln('    downloading…');
    final downloadWatch = Stopwatch()..start();
    final response = await dio.get<ResponseBody>(
      path,
      options: Options(
        headers: _authHeaders(token),
        responseType: ResponseType.stream,
        followRedirects: false,
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    var received = 0;
    await for (final chunk in response.data!.stream) {
      received += chunk.length;
    }
    downloadWatch.stop();
    final downloadSeconds = downloadWatch.elapsedMilliseconds / 1000;
    stdout.writeln('    download: ${downloadSeconds.toStringAsFixed(1)}s '
        '(${(received / 1024 / 1024 / downloadSeconds).toStringAsFixed(1)} MiB/s, '
        '$received bytes)');

    await dio.delete<dynamic>(
      path,
      options: Options(headers: _authHeaders(token), followRedirects: false),
    );
  } on Object catch (error) {
    stdout.writeln('    FAILED ($error)');
  } finally {
    dio.close(force: true);
  }
}

/// The authoritative quota answer.
///
/// `fs.space()` is reachable through Puter's driver interface, which Puter.js
/// posts to as `{ interface, method, args }`. The contract is undocumented, so
/// this probe is best-effort: a failure here does not mean the quota is wrong,
/// only that this particular call shape was not accepted.
Future<void> _probeQuotaViaDriver(String token) async {
  final dio = _client();
  try {
    final response = await dio.post<dynamic>(
      _driverCall,
      data: <String, dynamic>{
        'interface': 'puter-fs',
        'method': 'space',
        'args': <String, dynamic>{},
      },
      options: Options(
        headers: <String, dynamic>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        followRedirects: false,
      ),
    );

    stdout.writeln('    POST $_driverCall -> ${response.statusCode}');
    final body = response.data;
    stdout.writeln('    response: ${_truncate('$body', 400)}');

    if (body is Map) {
      final capacity = body['capacity'] ?? body['result']?['capacity'];
      final used = body['used'] ?? body['result']?['used'];
      if (capacity is num) {
        stdout.writeln('    Q1 ANSWER — fs.space() reports:');
        stdout.writeln('      capacity : ${_bytes(capacity.toInt())}');
        stdout.writeln('      used     : ${_bytes((used as num?)?.toInt() ?? 0)}');
        final gib = capacity / 1024 / 1024 / 1024;
        stdout.writeln(
          gib >= 300
              ? '      -> Consistent with the 310 GB premise. PROCEED.'
              : '      -> ${gib.toStringAsFixed(2)} GiB, NOT 310 GB.\n'
                  '         The premise does not hold. Re-scope before Phase 1.',
        );
      }
    }
  } on Object catch (error) {
    stdout.writeln('    FAILED ($error)');
    stdout.writeln('    The driver contract is undocumented, so this is '
        'expected to be brittle.\n    Confirm quota in the Puter web UI '
        'instead, which is authoritative.');
  } finally {
    dio.close(force: true);
  }
}

// -------------------------------------------------------------------- helpers

Dio _client() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 10),
      validateStatus: (_) => true,
    ));

Map<String, dynamic> _authHeaders(String token) => <String, dynamic>{
      'Authorization': _basicAuth(token),
    };

/// Puter's documented WebDAV convention: username `-token`, password is the
/// API token. This skips the per-account sign-in ceiling.
String _basicAuth(String token) =>
    'Basic ${base64Encode(utf8.encode('-token:$token'))}';

String _propfindBody({required bool includeQuota}) {
  final quota =
      includeQuota ? '<d:quota-available-bytes/><d:quota-used-bytes/>' : '';
  return '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:getcontentlength/><d:getlastmodified/>'
      '<d:getcontenttype/><d:getetag/><d:resourcetype/>'
      '$quota'
      '</d:prop></d:propfind>';
}

Stream<List<int>> _repeatingStream(int totalBytes) async* {
  const chunkSize = 1024 * 1024;
  final chunk = List<int>.filled(chunkSize, 0x41);
  var sent = 0;
  while (sent < totalBytes) {
    final size = (totalBytes - sent) < chunkSize
        ? totalBytes - sent
        : chunkSize;
    yield chunk.sublist(0, size);
    sent += size;
  }
}

Future<int?> _remoteSize(
  Dio dio,
  String host,
  String path,
  String token,
) async {
  final response = await dio.request<dynamic>(
    path,
    data: _propfindBody(includeQuota: false),
    options: Options(
      method: 'PROPFIND',
      headers: <String, dynamic>{
        'Depth': '0',
        'Authorization': _basicAuth(token),
        'Content-Type': 'application/xml; charset=utf-8',
      },
      responseType: ResponseType.plain,
      followRedirects: false,
    ),
  );
  final body = response.data?.toString() ?? '';
  if (body.isEmpty) return null;
  final document = XmlDocument.parse(body);
  return _numeric(document, 'getcontentlength');
}

int? _numeric(XmlDocument document, String localName) {
  final element =
      document.findAllElements(localName, namespace: 'DAV:').firstOrNull;
  final text = element?.innerText.trim();
  return (text == null || text.isEmpty) ? null : int.tryParse(text);
}

String _explain(int? status) => switch (status) {
      200 => 'OK',
      201 => 'Created',
      204 => 'No Content',
      207 => 'Multistatus',
      301 || 302 || 307 || 308 => 'Redirect',
      401 => 'Unauthorized — host is right, credential rejected',
      403 => 'Forbidden',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      412 => 'Precondition Failed',
      413 => 'Storage Limit Reached',
      429 => 'Too Many Requests — LOCKOUT RISK, stop probing',
      501 => 'Not Implemented',
      _ => '',
    };

String _bytes(int value) {
  const units = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var size = value.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(2)} ${units[unit]} ($value bytes)';
}

String _truncate(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
