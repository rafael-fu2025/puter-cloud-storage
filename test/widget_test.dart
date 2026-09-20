import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/app/app.dart';
import 'package:puter_cloud_storage/app/providers.dart';
import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/network/request_scheduler.dart';
import 'package:puter_cloud_storage/core/security/token_vault.dart';

void main() {
  const config = AppConfig();

  Widget wrap(Widget child, {String? token}) => ProviderScope(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(config),
          tokenVaultProvider.overrideWithValue(InMemoryTokenVault(token)),
          requestSchedulerProvider.overrideWithValue(
            RequestScheduler(config: config),
          ),
        ],
        child: child,
      );

  testWidgets(
    'first run shows the welcome screen with the credential disclosure',
    (tester) async {
      await tester.pumpWidget(wrap(const PuterCloudApp()));
      await tester.pumpAndSettle();

      expect(find.text('Connect your Puter account'), findsOneWidget);

      // The disclosure is a security requirement, not copy polish: the user is
      // handing over an account-wide root credential. See docs/security.md §5.
      expect(
        find.textContaining('grants full access to your Puter account'),
        findsOneWidget,
      );
      expect(find.textContaining('Powered by Puter'), findsOneWidget);
    },
  );

  testWidgets('an existing token routes past onboarding', (tester) async {
    await tester.pumpWidget(
      wrap(const PuterCloudApp(), token: 'test-token-not-real'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Foundation ready'), findsOneWidget);
    expect(find.text('Connect your Puter account'), findsNothing);
  });

  testWidgets('the raw token is never rendered', (tester) async {
    const secret = 'super-secret-token-value';

    await tester.pumpWidget(wrap(const PuterCloudApp(), token: secret));
    await tester.pumpAndSettle();

    // Walk the whole tree looking for the credential. This is the regression
    // test for docs/security.md §3: no provider and no widget may expose it.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .toList();
    for (final text in texts) {
      expect(text.contains(secret), isFalse, reason: 'found token in "$text"');
    }
  });
}
