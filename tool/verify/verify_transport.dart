// Contract verification for `WebDavTransport`.
//
// Runs the transport against `test/support/webdav_fixture.dart` — a real HTTP
// server on loopback — so every check exercises real sockets, real status
// codes, real XML and real streaming. No mock would catch what this catches.
//
//   dart run tool/verify/verify_transport.dart
//
// Dependency-free on purpose: `flutter test` fails here on the WebSocket
// upgrade to flutter_tester, and `dart test` fails on the native-assets build
// hook. This always runs.
//
// It needs no Puter account and no network, so it can be run freely without
// touching rate limits or storage quota.

import 'dart:io';

import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/error/puter_exception.dart';
import 'package:puter_cloud_storage/core/network/request_scheduler.dart';
import 'package:puter_cloud_storage/data/transport/puter_transport.dart';
import 'package:puter_cloud_storage/data/transport/webdav_transport.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';

import '../../test/support/webdav_fixture.dart';

int _passed = 0;
final List<String> _failures = <String>[];

void _check(String label, bool condition, [String? detail]) {
  if (condition) {
    _passed++;
    stdout.writeln('  PASS  $label');
  } else {
    _failures.add(label);
    stdout.writeln('  FAIL  $label${detail == null ? '' : ' — $detail'}');
  }
}

/// Assert that [body] throws a [PuterException] of [kind].
Future<void> _checkThrows(
  String label,
  PuterErrorKind kind,
  Future<void> Function() body,
) async {
  try {
    await body();
    _check(label, false, 'expected ${kind.name}, but nothing was thrown');
  } on PuterException catch (error) {
    _check(
      label,
      error.kind == kind,
      'expected ${kind.name}, got ${error.kind.name} (${error.message})',
    );
  } on Object catch (error) {
    _check(label, false, 'expected ${kind.name}, got $error');
  }
}

Future<void> main() async {
  stdout.writeln('Puter Cloud Storage — WebDAV transport contract checks\n');

  final tempDir = Directory.systemTemp.createTempSync('pcs_transport_');
  const config = AppConfig();

  try {
    // ---------------------------------------------------------------- listing
    stdout.writeln('Listing and metadata');
    {
      final fixture = WebDavFixture();
      await fixture.start();
      fixture
        ..seedFile('/notes.txt', 'hello world')
        ..seedFile('/photo.jpg', 'not really a jpeg')
        ..seedDirectory('/documents');

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );

      await transport.authenticate(const TokenCredential('fixture-token'));

      final page = await transport.list(const ListRequest(path: '/'));
      final names = page.items.map((node) => node.name).toSet();

      _check('lists seeded files', names.containsAll(<String>['notes.txt', 'photo.jpg']));
      _check('lists seeded directory', names.contains('documents'));
      _check(
        'directories sort before files',
        page.items.first.isDirectory,
        'first was ${page.items.first.name}',
      );
      _check('excludes the collection itself', !names.contains('/'));
      _check(
        'reports size for files',
        page.items.firstWhere((n) => n.name == 'notes.txt').sizeBytes == 11,
      );
      _check(
        'infers mime type from the server',
        page.items.firstWhere((n) => n.name == 'notes.txt').mimeType ==
            'text/plain',
      );
      _check(
        'parses last-modified',
        page.items.firstWhere((n) => n.name == 'notes.txt').modifiedAt != null,
      );
      _check('reports a clean listing as complete', !page.isPartial);

      final stat = await transport.stat('/notes.txt');
      _check('stat returns the node', stat.name == 'notes.txt');
      _check('stat marks files as non-directories', !stat.isDirectory);

      await _checkThrows(
        'stat on a missing path is notFound',
        PuterErrorKind.notFound,
        () => transport.stat('/nope.txt'),
      );

      // --------------------------------------------------------- path resolution
      final nested = await transport.list(const ListRequest(path: '/documents'));
      _check('lists an empty subdirectory', nested.items.isEmpty);

      await transport.dispose();
      await fixture.stop();
    }

    // ------------------------------------------------------------- credentials
    stdout.writeln('\nAuthentication');
    {
      final fixture = WebDavFixture()..expectedToken = 'right-token';
      await fixture.start();

      final good = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await good.authenticate(const TokenCredential('right-token'));
      _check('accepts the correct token', true);
      await good.dispose();

      final bad = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await _checkThrows(
        'rejects a wrong token as authInvalid',
        PuterErrorKind.authInvalid,
        () => bad.authenticate(const TokenCredential('wrong-token')),
      );
      await bad.dispose();

      await fixture.stop();
    }

    // ---------------------------------------------------------------- mutation
    stdout.writeln('\nMutations');
    {
      final fixture = WebDavFixture();
      await fixture.start();
      fixture.seedFile('/a.txt', 'original');

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await transport.authenticate(const TokenCredential('fixture-token'));

      await transport.createDirectory('/one/two/three');
      _check('creates nested collections', fixture.exists('/one/two/three'));

      await _checkThrows(
        're-creating an existing collection is alreadyExists',
        PuterErrorKind.alreadyExists,
        () => transport.createDirectory('/one/two/three'),
      );

      await transport.move('/a.txt', '/moved.txt');
      _check('move relocates the file', fixture.exists('/moved.txt'));
      _check('move removes the original', !fixture.exists('/a.txt'));
      _check(
        'move preserves content',
        fixture.readAsString('/moved.txt') == 'original',
      );

      await transport.copy('/moved.txt', '/copied.txt');
      _check('copy creates the destination', fixture.exists('/copied.txt'));
      _check('copy keeps the source', fixture.exists('/moved.txt'));

      await transport.delete('/copied.txt');
      _check('delete removes the file', !fixture.exists('/copied.txt'));

      await _checkThrows(
        'deleting a missing path is notFound',
        PuterErrorKind.notFound,
        () => transport.delete('/ghost.txt'),
      );

      await transport.dispose();
      await fixture.stop();
    }

    // ---------------------------------------------------------------- transfer
    stdout.writeln('\nTransfers');
    {
      final fixture = WebDavFixture();
      await fixture.start();

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await transport.authenticate(const TokenCredential('fixture-token'));

      // --- upload
      final source = File('${tempDir.path}/upload.txt')
        ..writeAsStringSync('uploaded payload');
      var lastProgress = 0;
      var progressCalls = 0;

      await transport.upload(
        UploadRequest(
          localPath: source.path,
          remotePath: '/upload.txt',
          onProgress: (done, total) {
            progressCalls++;
            lastProgress = done;
          },
        ),
      );

      _check(
        'upload stores the content',
        fixture.readAsString('/upload.txt') == 'uploaded payload',
      );
      _check('upload reports progress', progressCalls > 0);
      _check(
        'upload reports the full byte count',
        lastProgress == 'uploaded payload'.length,
        'reported $lastProgress',
      );

      // --- overwrite protection
      await _checkThrows(
        'upload refuses to overwrite by default',
        PuterErrorKind.alreadyExists,
        () => transport.upload(
          UploadRequest(localPath: source.path, remotePath: '/upload.txt'),
        ),
      );
      _check(
        'a refused overwrite leaves the original intact',
        fixture.readAsString('/upload.txt') == 'uploaded payload',
      );

      await transport.upload(
        UploadRequest(
          localPath: source.path,
          remotePath: '/upload.txt',
          overwrite: true,
        ),
      );
      _check('explicit overwrite succeeds', true);

      // --- upload creates missing parents
      await transport.upload(
        UploadRequest(
          localPath: source.path,
          remotePath: '/deep/nested/created.txt',
          createMissingParents: true,
        ),
      );
      _check(
        'upload creates missing parents',
        fixture.exists('/deep/nested/created.txt'),
      );

      // --- upload of a missing local file
      await _checkThrows(
        'uploading a missing local file is notFound',
        PuterErrorKind.notFound,
        () => transport.upload(
          UploadRequest(
            localPath: '${tempDir.path}/does-not-exist.txt',
            remotePath: '/x.txt',
          ),
        ),
      );

      // --- download
      fixture.seedFile('/download.txt', 'downloaded payload');
      final target = '${tempDir.path}/download.txt';
      var downloadProgress = 0;

      await transport.download(
        DownloadRequest(
          remotePath: '/download.txt',
          localPath: target,
          onProgress: (done, total) => downloadProgress = done,
        ),
      );

      _check(
        'download writes the file',
        File(target).readAsStringSync() == 'downloaded payload',
      );
      _check('download reports progress', downloadProgress == 18);
      _check(
        'download leaves no staging file behind',
        !File('$target.part').existsSync(),
      );

      // --- resume
      // Resume state lives in the staging file; the transport derives the
      // offset from it rather than trusting a caller-supplied number.
      final resumed = '${tempDir.path}/resumed.txt';
      File('$resumed.part').writeAsStringSync('downloaded');
      await transport.download(
        DownloadRequest(remotePath: '/download.txt', localPath: resumed),
      );
      _check(
        'resumes automatically from the staging file',
        File(resumed).readAsStringSync() == 'downloaded payload',
        'got "${File(resumed).readAsStringSync()}"',
      );
      _check(
        'clears the staging file after a completed resume',
        !File('$resumed.part').existsSync(),
      );

      // --- a server that ignores Range
      // Appending a full body to a partial prefix would produce a corrupt file
      // that still looks plausible — the worst failure mode for a storage app.
      // The transport must detect the 200 and start over.
      final stubborn = '${tempDir.path}/stubborn.txt';
      File('$stubborn.part').writeAsStringSync('downloaded');
      fixture.ignoreRange = true;
      await transport.download(
        DownloadRequest(remotePath: '/download.txt', localPath: stubborn),
      );
      fixture.ignoreRange = false;
      _check(
        'restarts cleanly when the server ignores Range',
        File(stubborn).readAsStringSync() == 'downloaded payload',
        'got "${File(stubborn).readAsStringSync()}"',
      );

      await _checkThrows(
        'downloading a missing path is notFound',
        PuterErrorKind.notFound,
        () => transport.download(
          DownloadRequest(
            remotePath: '/missing.txt',
            localPath: '${tempDir.path}/missing.txt',
          ),
        ),
      );

      await transport.dispose();
      await fixture.stop();
    }

    // ------------------------------------------------------------------- quota
    stdout.writeln('\nQuota and limits');
    {
      final fixture = WebDavFixture(quotaBytes: 40);
      await fixture.start();
      fixture.seedFile('/small.txt', '0123456789');

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await transport.authenticate(const TokenCredential('fixture-token'));

      final usage = await transport.usage();
      _check(
        'reads RFC 4331 quota',
        usage.capacityBytes == 40,
        'capacity was ${usage.capacityBytes}',
      );
      _check('reports used bytes', usage.usedBytes == 10);
      _check('derives free bytes', usage.freeBytes == 30);

      // --- 413
      final big = File('${tempDir.path}/big.txt')
        ..writeAsStringSync('x' * 100);
      await _checkThrows(
        'a write past the quota is storageLimitReached',
        PuterErrorKind.storageLimitReached,
        () => transport.upload(
          UploadRequest(
            localPath: big.path,
            remotePath: '/big.txt',
            overwrite: true,
          ),
        ),
      );
      _check(
        'a quota-rejected upload leaves existing files intact',
        fixture.readAsString('/small.txt') == '0123456789',
      );
      _check('a quota-rejected upload writes nothing', !fixture.exists('/big.txt'));

      // storageLimitReached must not be retried — retrying cannot help.
      try {
        await transport.upload(
          UploadRequest(
            localPath: big.path,
            remotePath: '/big.txt',
            overwrite: true,
          ),
        );
        _check('storageLimitReached is not retryable', false, 'nothing thrown');
      } on PuterException catch (error) {
        _check('storageLimitReached is not retryable', !error.isRetryable);
        _check('storageLimitReached needs the user', error.requiresUserAction);
      }

      await transport.dispose();
      await fixture.stop();
    }

    // ------------------------------------------------------------ 429 handling
    stdout.writeln('\nRate limiting');
    {
      final fixture = WebDavFixture();
      await fixture.start();

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await transport.authenticate(const TokenCredential('fixture-token'));

      fixture.rateLimited = true;
      await _checkThrows(
        'a 429 becomes rateLimited',
        PuterErrorKind.rateLimited,
        () => transport.list(const ListRequest(path: '/')),
      );

      try {
        await transport.list(const ListRequest(path: '/'));
      } on PuterException catch (error) {
        _check('rateLimited is retryable', error.isRetryable);
        _check('rateLimited does not need the user', !error.requiresUserAction);
      }

      fixture.rateLimited = false;
      final recovered = await transport.list(const ListRequest(path: '/'));
      _check('recovers once the limit lifts', recovered.items.isEmpty);

      await transport.dispose();
      await fixture.stop();
    }

    // -------------------------------------------------------- partial failures
    stdout.writeln('\nPartial failure handling');
    {
      final fixture = WebDavFixture()..injectPartialFailure = true;
      await fixture.start();
      fixture
        ..seedFile('/a.txt', 'a')
        ..seedFile('/b.txt', 'b')
        ..seedFile('/c.txt', 'c')
        ..seedFile('/d.txt', 'd');

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await transport.authenticate(const TokenCredential('fixture-token'));

      final page = await transport.list(const ListRequest(path: '/'));

      // This is the check that matters. A 207 is not blanket success: entries
      // whose propstat failed must be reported, not silently dropped. Treating
      // 207 as success would make files invisible with no explanation.
      _check(
        'a 207 with failed entries reports them',
        page.isPartial,
        'listed ${page.items.length} items with ${page.failures.length} failures',
      );
      _check(
        'still returns the entries that succeeded',
        page.items.isNotEmpty,
      );
      _check(
        'names the path of each failure',
        page.failures.every((failure) => failure.path.isNotEmpty),
      );
      _check(
        'carries the failure status code',
        page.failures.any((failure) => failure.statusCode == 403),
      );
      _check(
        'reports fewer items than the folder holds',
        page.items.length < 4,
        'got ${page.items.length} of 4',
      );

      await transport.dispose();
      await fixture.stop();
    }

    // ------------------------------------------------------------ capabilities
    stdout.writeln('\nCapability honesty');
    {
      final fixture = WebDavFixture();
      await fixture.start();

      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: fixture.baseUrl.toString(),
      );
      await transport.authenticate(const TokenCredential('fixture-token'));

      final caps = transport.capabilities;

      _check('declares readdir support', caps.canList);
      _check('declares write support', caps.canWrite);
      _check('declares resume-download support', caps.canResumeDownload);
      _check('declares usage support', caps.canReportUsage);
      _check('declares no signed-URL support', !caps.canSignReadUrl);
      _check('declares no share support', !caps.canShare);
      _check(
        'declares no resume-upload support until Phase 0 proves it',
        !caps.canResumeUpload,
      );

      // Anything declared unsupported must throw, not silently misbehave.
      await _checkThrows(
        'signedReadUrl is explicitly unsupported',
        PuterErrorKind.unsupported,
        () => transport.signedReadUrl('/notes.txt'),
      );

      await transport.dispose();
      await fixture.stop();
    }

    // ------------------------------------------------------------- unauthed use
    stdout.writeln('\nUninitialised transport');
    {
      final transport = WebDavTransport(
        scheduler: RequestScheduler(config: config),
        config: config,
        baseUrl: 'http://127.0.0.1:1',
      );

      await _checkThrows(
        'using a transport before authenticating is authInvalid',
        PuterErrorKind.authInvalid,
        () => transport.list(const ListRequest(path: '/')),
      );
      await transport.dispose();
    }
  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  stdout.writeln('\n${'-' * 60}');
  stdout.writeln('passed: $_passed    failed: ${_failures.length}');
  if (_failures.isNotEmpty) {
    stdout.writeln('\nFailures:');
    for (final failure in _failures) {
      stdout.writeln('  - $failure');
    }
    stdout.writeln('\nRESULT: FAIL');
    exitCode = 1;
  } else {
    stdout.writeln('RESULT: PASS');
  }
}
