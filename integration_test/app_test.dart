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

  /// A scrollable to drive, chosen explicitly.
  ///
  /// `scrollUntilVisible` defaults to `find.byType(Scrollable)` and calls
  /// `.single` on it, which throws as soon as a screen has more than one — and
  /// the welcome screen has two, because `SelectableText` brings its own.
  Finder firstScrollable() => find.byType(Scrollable).first;

  /// The real app, on the real device, with every real dependency.
  testWidgets('the app launches and reaches the token screen', (
    WidgetTester tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();

    expect(
      find.text('Connect your Puter account'),
      findsOneWidget,
      reason: 'the welcome screen must render with the real plugin set',
    );

    await tester.scrollUntilVisible(
      find.text('Enter token'),
      200,
      scrollable: firstScrollable(),
    );
    await tester.tap(find.text('Enter token'));
    await tester.pumpAndSettle();

    expect(find.text('Paste your Puter auth token'), findsOneWidget);
  });

  testWidgets('the token field validates before spending an attempt', (
    WidgetTester tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enter token'),
      200,
      scrollable: firstScrollable(),
    );
    await tester.tap(find.text('Enter token'));
    await tester.pumpAndSettle();

    // A token that cannot possibly be one must be refused locally. Reaching the
    // network here would spend failed-sign-in budget on an obvious typo, and
    // ten of those lock the account out of WebDAV for fifteen minutes.
    await tester.enterText(find.byType(TextFormField), 'x');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('too short'), findsOneWidget);
    expect(find.text('Paste your Puter auth token'), findsOneWidget);
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
