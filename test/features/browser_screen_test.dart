/// Widget tests for the screens behind onboarding.
///
/// The welcome flow is covered in `widget_test.dart`. These are the screens a
/// user actually lives in, and they need a live-looking repository — which is
/// what [FakeTransport] plus [InMemoryNodeCache] provide without a server.
///
/// The point of most of these is **layout at scale**. Flutter throws on a
/// `RenderFlex` overflow, so rendering a screen at 1.6× text and reaching the
/// end of the test is the assertion. That matters here because the previous
/// design had a card that overflowed by 59px at a modest scale increase, and
/// nothing caught it until a test happened to scroll past it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/app/app.dart';
import 'package:puter_cloud_storage/app/providers.dart';
import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/network/request_scheduler.dart';
import 'package:puter_cloud_storage/core/ui/components.dart';
import 'package:puter_cloud_storage/data/database/node_cache.dart';
import 'package:puter_cloud_storage/data/platform/device_files.dart';
import 'package:puter_cloud_storage/data/repositories/file_repository.dart';
import 'package:puter_cloud_storage/data/repositories/settings_repository.dart';
import 'package:puter_cloud_storage/data/transfer/transfer_store.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';
import 'package:puter_cloud_storage/features/browser/file_browser_screen.dart';
import 'package:puter_cloud_storage/features/search/search_screen.dart';

import '../support/fake_transport.dart';

void main() {
  const AppConfig config = AppConfig();

  late FakeTransport transport;
  late InMemoryNodeCache cache;
  late FileRepository repository;

  setUp(() {
    transport = FakeTransport(
      tree: <String, List<RemoteNode>>{
        '/': <RemoteNode>[
          RemoteNode(
            path: '/Documents',
            name: 'Documents',
            isDirectory: true,
            modifiedAt: DateTime(2026, 5, 1),
          ),
          RemoteNode(
            path: '/holiday photo with a deliberately long name.jpg',
            name: 'holiday photo with a deliberately long name.jpg',
            isDirectory: false,
            sizeBytes: 2400000,
            modifiedAt: DateTime(2026, 9, 1),
          ),
          const RemoteNode(
            path: '/notes.txt',
            name: 'notes.txt',
            isDirectory: false,
            sizeBytes: 2048,
          ),
        ],
        '/Documents': <RemoteNode>[
          const RemoteNode(
            path: '/Documents/report.pdf',
            name: 'report.pdf',
            isDirectory: false,
            sizeBytes: 340000,
          ),
        ],
      },
    );
    cache = InMemoryNodeCache();
    repository = FileRepository(transport: transport, cache: cache);
  });

  /// The real theme, so these tests exercise the shipped look rather than a
  /// default one that happens to be forgiving.
  Widget wrap(Widget screen, {double textScale = 1.0}) => ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          requestSchedulerProvider.overrideWithValue(
            RequestScheduler(config: config),
          ),
          fileRepositoryProvider.overrideWithValue(repository),
          nodeCacheProvider.overrideWithValue(cache),
          transferStoreProvider.overrideWithValue(InMemoryTransferStore()),
          preferencesStoreProvider
              .overrideWithValue(InMemoryPreferencesStore()),
          deviceFilesProvider
              .overrideWithValue(const UnavailableDeviceFiles()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: screen,
          ),
        ),
      );

  void usePhoneViewport(WidgetTester tester, {double textScale = 1.0}) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  group('browser', () {
    testWidgets('lists the folder contents', (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const FileBrowserScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
    });

    testWidgets('shows one header bar and no standing notices',
        (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const FileBrowserScreen()));
      await tester.pumpAndSettle();

      // The path lives in the app bar subtitle rather than in a breadcrumb bar
      // of its own.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Puter'), findsOneWidget);

      // Nothing worth warning about when there is plenty of space and the
      // listing is complete — the storage bar does not occupy space it has not
      // earned.
      expect(find.byType(InlineBanner), findsNothing);
    });

    testWidgets('renders at a large text scale without overflowing',
        (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const FileBrowserScreen(), textScale: 1.6));
      await tester.pumpAndSettle();

      expect(find.text('notes.txt'), findsOneWidget);
    });

    testWidgets('an empty folder offers a way to fill it',
        (WidgetTester tester) async {
      transport.tree['/Documents'] = <RemoteNode>[];
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const FileBrowserScreen()));
      await tester.pumpAndSettle();

      // Descend into the empty folder.
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      expect(find.text('This folder is empty'), findsOneWidget);
      expect(find.text('Upload a file'), findsOneWidget);
      expect(find.text('New folder'), findsOneWidget);
    });

    testWidgets('a long filename is truncated rather than overflowing',
        (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const FileBrowserScreen(), textScale: 1.6));
      await tester.pumpAndSettle();

      final Finder title = find.text(
        'holiday photo with a deliberately long name.jpg',
      );
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
    });
  });

  group('search', () {
    testWidgets('finds a file saved on the device',
        (WidgetTester tester) async {
      // Populate the index the way browsing would.
      await repository.listDirectory('/');
      usePhoneViewport(tester);

      await tester.pumpWidget(wrap(const SearchScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Find a file'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'holiday');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('1 result'), findsOneWidget);
    });

    testWidgets('says what it covered instead of just finding nothing',
        (WidgetTester tester) async {
      await repository.listDirectory('/');
      usePhoneViewport(tester);

      await tester.pumpWidget(wrap(const SearchScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing found'), findsOneWidget);
      // The explanation has to say why, in the user's terms.
      expect(find.textContaining('saved on this phone'), findsOneWidget);
    });

    testWidgets('renders at a large text scale without overflowing',
        (WidgetTester tester) async {
      await repository.listDirectory('/');
      usePhoneViewport(tester);

      await tester.pumpWidget(wrap(const SearchScreen(), textScale: 1.6));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'notes');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(find.text('1 result'), findsOneWidget);
    });
  });
}
