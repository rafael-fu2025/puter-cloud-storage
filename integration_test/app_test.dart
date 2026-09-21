/// On-device tests for the things that only exist on Android.
///
/// The widget tests run on the host, where the SQLite native library, the
/// Keystore, `path_provider` and the `MethodChannel` in `MainActivity.kt` do not
/// exist. Those are precisely the pieces that fail at runtime rather than at
/// compile time, so they need a real device:
///
/// ```
/// flutter test integration_test -d <device>
/// ```
///
/// Everything here is deterministic and offline. The live-account path — a real
/// token against `dav.puter.com` — cannot be tested without a credential, and is
/// covered instead by `tool/verify/verify_transport.dart` against the local
/// WebDAV fixture.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:puter_cloud_storage/core/security/token_vault.dart';
import 'package:puter_cloud_storage/data/database/app_database.dart';
import 'package:puter_cloud_storage/data/database/node_cache.dart';
import 'package:puter_cloud_storage/data/platform/device_files.dart';
import 'package:puter_cloud_storage/data/platform/platform_bridge.dart';
import 'package:puter_cloud_storage/data/repositories/settings_repository.dart';
import 'package:puter_cloud_storage/data/transfer/transfer_store.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';

// ignore: depend_on_referenced_packages
import 'package:puter_cloud_storage/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The app opens its own database handle in `main()`, and these tests open a
  // second one to assert against it directly. That is a test-process artifact,
  // not a design problem — in the app there is exactly one handle — so drift's
  // "multiple databases" warning is silenced here rather than worked around.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// Wait until [finder] matches, tolerating slow platform calls.
  ///
  /// `pumpAndSettle` waits for *frames*, and the first frame here is a spinner.
  /// The welcome screen does not exist until a Keystore read resolves, which on
  /// a cold start after a fresh install can take seconds — so settling on
  /// frames alone returns too early and the test fails intermittently. This
  /// waits on the condition instead.
  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Timed out waiting for $finder');
  }

  /// Give the test a viewport tall enough for the whole welcome screen.
  ///
  /// Scrolling to a widget on a cold start is timing-dependent — the first
  /// frame after a fresh install can take long enough that the list has not
  /// laid out when the drag begins, which made this suite flaky. A temporary
  /// taller viewport removes the scroll, and with it the flakiness, while
  /// leaving the real device size for every other test.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// The real app, on the real device, with every real dependency.
  testWidgets('the app launches and reaches the access key screen', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    await app.main();
    await waitFor(tester, find.text('Your files, on Puter'));

    expect(
      find.text('Your files, on Puter'),
      findsOneWidget,
      reason: 'the welcome screen must render with the real plugin set',
    );

    await tester.tap(find.text('Add my access key'));
    await waitFor(tester, find.text('Paste your access key'));

    expect(find.text('Paste your access key'), findsOneWidget);
  });

  testWidgets('the key field validates before spending an attempt', (
    WidgetTester tester,
  ) async {
    useTallViewport(tester);
    await app.main();
    await waitFor(tester, find.text('Add my access key'));
    await tester.tap(find.text('Add my access key'));
    await tester.pumpAndSettle();

    // A key that cannot possibly be one must be refused locally. Reaching the
    // network here would spend failed-sign-in budget on an obvious typo, and
    // ten of those lock the account out of WebDAV for fifteen minutes.
    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('too short'), findsOneWidget);
    expect(find.text('Paste your access key'), findsOneWidget);
  });

  testWidgets('the Keystore-backed vault round-trips a credential', (
    WidgetTester tester,
  ) async {
    final vault = SecureTokenVault();

    await vault.clear();
    expect(await vault.hasToken, isFalse);

    await vault.write('integration-test-token');
    expect(await vault.read(), 'integration-test-token');
    expect(await vault.hasToken, isTrue);

    // The value must not survive a clear, and clearing twice must not throw.
    await vault.clear();
    expect(await vault.read(), isNull);
    await vault.clear();
  });

  testWidgets('the local index opens, writes, searches and clears', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase.open();

    // Proves the bundled SQLite native library loaded and that
    // path_provider resolved a writable directory.
    await database.writeSetting('integration.probe', 'ok');
    expect(await database.readSetting('integration.probe'), 'ok');

    final cache = DriftNodeCache(database);
    await cache.clear();

    await cache.replaceChildren('/', <RemoteNode>[
      const RemoteNode(
        path: '/Documents',
        name: 'Documents',
        isDirectory: true,
      ),
      const RemoteNode(
        path: '/holiday photo.jpg',
        name: 'holiday photo.jpg',
        isDirectory: false,
        sizeBytes: 1024,
      ),
    ]);

    expect(await cache.nodeCount(), 2);
    final children = await cache.childrenOf('/');
    expect(children, hasLength(2));

    // Search is the feature that depends entirely on the index, because Puter
    // has no server-side filesystem search.
    final hits = await cache.search('holiday');
    expect(hits, hasLength(1));
    expect(hits.single.path, '/holiday photo.jpg');

    // A name with a LIKE wildcard must not widen the match. This is the case
    // the escape handling in AppDatabase exists for.
    await cache.replaceChildren('/Documents', <RemoteNode>[
      const RemoteNode(
        path: '/Documents/100%_report.pdf',
        name: '100%_report.pdf',
        isDirectory: false,
        sizeBytes: 10,
      ),
      const RemoteNode(
        path: '/Documents/other.pdf',
        name: 'other.pdf',
        isDirectory: false,
        sizeBytes: 10,
      ),
    ]);
    final escaped = await cache.search('100%_report');
    expect(escaped, hasLength(1));

    await cache.clear();
    expect(await cache.nodeCount(), 0);
  });

  testWidgets('the transfer queue persists across a store restart', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase.open();
    final store = DriftTransferStore(database);

    const task = TransferTask(
      id: 'integration-transfer',
      direction: TransferDirection.upload,
      remotePath: '/Documents/report.pdf',
      localPath: '/tmp/report.pdf',
      totalBytes: 4096,
      bytesDone: 1024,
      state: TransferState.paused,
    );

    await store.save(task);
    final loaded = await store.load();
    final found = loaded.firstWhere(
      (TransferTask t) => t.id == 'integration-transfer',
    );

    expect(found.bytesDone, 1024);
    expect(found.state, TransferState.paused);
    expect(found.direction, TransferDirection.upload);

    await store.remove(task.id);
    expect(
      (await store.load()).where((TransferTask t) => t.id == task.id),
      isEmpty,
    );
  });

  testWidgets('preferences persist through the real database', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase.open();
    final repository = SettingsRepository(DriftPreferencesStore(database));

    await repository.saveBrowser(
      const BrowserPreferences(
        sortField: NodeSortField.size,
        viewMode: BrowserViewMode.grid,
        foldersFirst: false,
      ),
    );

    final loaded = await repository.loadBrowser();
    expect(loaded.sortField, NodeSortField.size);
    expect(loaded.viewMode, BrowserViewMode.grid);
    expect(loaded.foldersFirst, isFalse);
  });

  testWidgets('the platform channel answers instead of crashing', (
    WidgetTester tester,
  ) async {
    final files = PlatformDeviceFiles();

    // Downloads must land somewhere writable. This exercises path_provider
    // through the app-specific external directory.
    final directory = await files.downloadDirectory();
    expect(directory.existsSync(), isTrue);
    expect(directory.path, contains('Downloads'));

    // A missing file must be reported as a failure, not thrown as a crash.
    // `openFile` on a non-existent path is the case that would otherwise take
    // out the app from a menu action.
    expect(
      await files.openFile(localPath: '${directory.path}/does-not-exist.bin'),
      isFalse,
    );

    // And an export of a missing file likewise.
    expect(
      await files.exportFile(
        localPath: '${directory.path}/does-not-exist.bin',
        suggestedName: 'does-not-exist.bin',
      ),
      isFalse,
    );

    // Clean up the probe directory if it was created empty.
    if (directory.listSync().isEmpty) {
      directory.deleteSync();
    }
  });

  testWidgets('the URL opener refuses anything that is not http(s)', (
    WidgetTester tester,
  ) async {
    // This is reachable from strings that came off the network, so a remote
    // value must not be able to launch another app's deep link.
    expect(await PlatformBridge.openUrl(''), isFalse);
    expect(await PlatformBridge.openUrl('file:///etc/passwd'), isFalse);
    expect(await PlatformBridge.openUrl('javascript:alert(1)'), isFalse);
    expect(
      await PlatformBridge.openUrl('content://com.other/secret'),
      isFalse,
    );
  });

  testWidgets('the staging cleaner refuses paths outside its own area', (
    WidgetTester tester,
  ) async {
    final files = PlatformDeviceFiles();

    // Whatever the channel is handed, it must not delete outside the directory
    // the app stages uploads in. A deletion helper that trusts its argument is
    // one bug away from removing a file the user cares about.
    final Directory downloads = await files.downloadDirectory();
    final File bystander = File('${downloads.path}/do-not-delete.txt')
      ..writeAsStringSync('still here');

    expect(await files.discardStagedUpload(bystander.path), isFalse);
    expect(
      bystander.existsSync(),
      isTrue,
      reason: 'a path outside the staging area must be left alone',
    );
    bystander.deleteSync();

    // And an unrelated absolute path is refused too.
    expect(await files.discardStagedUpload('/data/local/tmp/x.txt'), isFalse);
    expect(await files.discardStagedUpload(''), isFalse);
  });

  testWidgets('the app-specific download directory is writable', (
    WidgetTester tester,
  ) async {
    final files = PlatformDeviceFiles();
    final directory = await files.downloadDirectory();
    final probe = File('${directory.path}/write-probe.txt')
      ..writeAsStringSync('ok');

    expect(probe.readAsStringSync(), 'ok');
    probe.deleteSync();
  });
}
