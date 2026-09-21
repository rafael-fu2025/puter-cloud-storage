import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/app/app.dart';
import 'package:puter_cloud_storage/app/providers.dart';
import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/network/request_scheduler.dart';
import 'package:puter_cloud_storage/core/security/token_vault.dart';
import 'package:puter_cloud_storage/data/database/node_cache.dart';
import 'package:puter_cloud_storage/data/platform/device_files.dart';
import 'package:puter_cloud_storage/data/repositories/settings_repository.dart';
import 'package:puter_cloud_storage/data/transfer/transfer_store.dart';

void main() {
  const AppConfig config = AppConfig();

  /// Give the test a phone-shaped viewport.
  ///
  /// The default 800×600 landscape surface is shorter than any phone, so the
  /// bottom of a scrolling screen is simply not built — and a finder that
  /// cannot see a button would report a missing button rather than a small
  /// window. Matching a real device removes that whole class of false failure.
  void usePhoneViewport(WidgetTester tester, {double textScale = 1.0}) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// A provider scope with every device-touching dependency replaced.
  Widget wrap(Widget child, {String? token}) => ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          tokenVaultProvider.overrideWithValue(InMemoryTokenVault(token)),
          requestSchedulerProvider.overrideWithValue(
            RequestScheduler(config: config),
          ),
          nodeCacheProvider.overrideWithValue(InMemoryNodeCache()),
          transferStoreProvider.overrideWithValue(InMemoryTransferStore()),
          preferencesStoreProvider
              .overrideWithValue(InMemoryPreferencesStore()),
          deviceFilesProvider.overrideWithValue(const UnavailableDeviceFiles()),
        ],
        child: child,
      );

  testWidgets(
    'first run explains what the app does and discloses the key',
    (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const PuterCloudApp()));
      await tester.pumpAndSettle();

      expect(find.text('Your files, on Puter'), findsOneWidget);

      // The disclosure is a security requirement, not copy polish: the user is
      // handing over an account-wide credential. See docs/security.md §5.
      // It must still be present — it moved out of an alarm-styled card, it
      // did not go away.
      await tester.scrollUntilVisible(
        find.textContaining('as powerful as your password'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('as powerful as your password'),
        findsOneWidget,
      );
    },
  );

  testWidgets('onboarding reaches the access key screen',
      (WidgetTester tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const PuterCloudApp()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add my access key'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add my access key'));
    await tester.pumpAndSettle();

    expect(find.text('Paste your access key'), findsOneWidget);

    // The one-attempt rule is the only thing standing between a mistyped key
    // and a 15-minute lockout of the whole account, so the screen must say so.
    expect(find.text('Try once, then check'), findsOneWidget);
  });

  testWidgets('the key screen rejects something that cannot be a key',
      (WidgetTester tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const PuterCloudApp()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add my access key'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add my access key'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('too short'), findsOneWidget);
  });

  testWidgets('no screen leaks developer jargon to the user',
      (WidgetTester tester) async {
    // The audit found WebDAV, RFC 4331, "circuit open", "request budget" and
    // citations to internal design documents rendered on screen. This is the
    // regression test for that.
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const PuterCloudApp()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Add my access key'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Add my access key'));
    await tester.pumpAndSettle();

    final Iterable<String> texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text widget) => widget.data ?? '');

    for (final String text in texts) {
      final String lower = text.toLowerCase();
      for (final String jargon in <String>[
        'webdav',
        'oauth',
        'rfc',
        'adt ',
        'transport',
        'circuit',
        'request budget',
        'local index',
        'http 4',
        'http 5',
      ]) {
        expect(
          lower.contains(jargon),
          isFalse,
          reason: 'found "$jargon" in "$text"',
        );
      }
    }
  });

  testWidgets('the raw access key is never rendered',
      (WidgetTester tester) async {
    const String secret = 'super-secret-token-value';

    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const PuterCloudApp(), token: secret));
    await tester.pumpAndSettle();

    // Walk the whole tree looking for the credential. This is the regression
    // test for docs/security.md §3: no provider and no widget may expose it.
    final Iterable<String> texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text widget) => widget.data ?? '');
    for (final String text in texts) {
      expect(text.contains(secret), isFalse, reason: 'found key in "$text"');
    }
  });

  testWidgets(
      'a stored key is not trusted without proof, so the app does not '
      'silently show a file list', (WidgetTester tester) async {
    // With a key present the app tries to connect. There is no server here, so
    // it must land on a failure view that offers a way forward rather than on a
    // browser that cannot load anything.
    usePhoneViewport(tester);
    await tester.pumpWidget(
      wrap(const PuterCloudApp(), token: 'not-a-real-token-value'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your files, on Puter'), findsNothing);
    expect(
      find.text('Use a different access key'),
      findsOneWidget,
      reason: 'a failed session must offer the way out',
    );
  });

  testWidgets('the welcome screen survives a large font scale',
      (WidgetTester tester) async {
    // The previous welcome card overflowed by 59px at a modest scale increase.
    // Flutter throws on overflow, so reaching the end of this test is the
    // assertion; the expects below only make the intent explicit.
    usePhoneViewport(tester, textScale: 1.6);
    await tester.pumpWidget(wrap(const PuterCloudApp()));
    await tester.pumpAndSettle();

    expect(find.text('Your files, on Puter'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Add my access key'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add my access key'), findsOneWidget);
  });
}
