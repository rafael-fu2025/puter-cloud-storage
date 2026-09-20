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
  /// cannot see the "Enter token" button would report a missing button rather
  /// than a small window. Matching a real device removes that whole class of
  /// false failure.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// A provider scope with every device-touching dependency replaced.
  ///
  /// The defaults declared in `providers.dart` cover the database and the
  /// platform channel already, so a widget test never needs a device — which is
  /// the reason those defaults exist rather than the providers being
  /// unimplemented.
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
    'first run shows the welcome screen with the credential disclosure',
    (WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(wrap(const PuterCloudApp()));
      await tester.pumpAndSettle();

      expect(find.text('Connect your Puter account'), findsOneWidget);

      // The disclosure is a security requirement, not copy polish: the user is
      // handing over an account-wide root credential. See docs/security.md §5.
      expect(
        find.textContaining('grants full access to your Puter account'),
        findsOneWidget,
      );

      // The attribution sits below the fold on a phone, so it is reached the
      // way a user reaches it.
      await tester.scrollUntilVisible(
        find.textContaining('Powered by Puter'),
        200,
      );
      expect(find.textContaining('Powered by Puter'), findsOneWidget);
    },
  );

  testWidgets('onboarding reaches the token screen', (WidgetTester tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const PuterCloudApp()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Enter token'), 200);
    await tester.tap(find.text('Enter token'));
    await tester.pumpAndSettle();

    expect(find.text('Paste your Puter auth token'), findsOneWidget);

    // The one-attempt rule is the only thing standing between a mistyped token
    // and a 15-minute lockout of the whole account, so the screen must say so.
    expect(find.text('One attempt per tap'), findsOneWidget);
  });

  testWidgets('the token screen rejects a token that cannot be one',
      (WidgetTester tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const PuterCloudApp()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Enter token'), 200);
    await tester.tap(find.text('Enter token'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('too short to be a Puter token'),
      findsOneWidget,
    );
  });

  testWidgets('the raw token is never rendered', (WidgetTester tester) async {
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
      expect(text.contains(secret), isFalse, reason: 'found token in "$text"');
    }
  });

  testWidgets(
      'a stored token is not trusted without proof, so the app does not '
      'silently show a file list', (WidgetTester tester) async {
    // With a token present the app tries to connect. There is no server here,
    // so it must land on a failure screen that offers a way forward rather than
    // on a browser that cannot load anything.
    usePhoneViewport(tester);
    await tester.pumpWidget(
      wrap(const PuterCloudApp(), token: 'not-a-real-token-value'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect your Puter account'), findsNothing);
    expect(
      find.text('Use a different token'),
      findsOneWidget,
      reason: 'a failed session must offer the way out',
    );
  });
}
