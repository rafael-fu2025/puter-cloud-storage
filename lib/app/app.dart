/// Application shell.
///
/// At this stage the app renders the onboarding gate, which is the only screen
/// Phase 1 requires. Feature screens land in Phases 2 to 4 — see
/// `docs/roadmap.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Root widget.
class PuterCloudApp extends ConsumerWidget {
  const PuterCloudApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Puter Cloud Storage',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      home: const OnboardingGate(),
    );
  }

  static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B6EF6),
    ),
  );

  static final ThemeData _darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B6EF6),
      brightness: Brightness.dark,
    ),
  );
}

/// Routes between onboarding and the main shell based on whether a token is
/// present.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authenticated = ref.watch(isAuthenticatedProvider);

    return authenticated.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not read stored credentials: $error'),
          ),
        ),
      ),
      data: (hasToken) =>
          hasToken ? const _FoundationStatusScreen() : const _WelcomeScreen(),
    );
  }
}

/// First-run screen.
///
/// The disclosure text here is a security requirement, not copy polish: the
/// user is being asked to hand over an account-wide root credential and is
/// entitled to know that before pasting it. See `docs/security.md` §5.
class _WelcomeScreen extends StatelessWidget {
  const _WelcomeScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Puter Cloud Storage')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Icon(
            Icons.cloud_outlined,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Connect your Puter account',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'This app reaches your Puter storage directly. It signs in with an '
            'auth token you create yourself, so there is no password to share '
            'and no OAuth popup.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Before you continue',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your Puter auth token grants full access to your Puter '
                    'account. Anyone who obtains it can read, modify, and '
                    'delete your files.\n\n'
                    'Store it as you would a password. You can revoke it at '
                    'any time from your Puter dashboard.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Create a token', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Steps(
            steps: <String>[
              'Sign in at puter.com/dashboard#account',
              'Find the API token section',
              'Click Create token — it is copied to your clipboard',
              'Return here and paste it on the next screen',
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () {
              // Phase 2 wires this to the token entry screen and a single
              // validation attempt. Validation must never retry automatically:
              // ten failed WebDAV sign-ins lock the account for 15 minutes.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Token entry arrives in Phase 2.'),
                ),
              );
            },
            child: const Text('Enter token'),
          ),
          const SizedBox(height: 12),
          Text(
            'Powered by Puter',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${i + 1}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(steps[i], style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Placeholder shown when a token exists.
///
/// Phase 2 replaces this with the file browser.
class _FoundationStatusScreen extends ConsumerWidget {
  const _FoundationStatusScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final scheduler = ref.watch(requestSchedulerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Foundation ready')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Phase 1 foundation is in place'),
              subtitle: Text(
                'Transport, scheduler, token vault, domain model and error '
                'taxonomy are implemented. Feature screens arrive in Phase 2.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('Transport mode'),
                  trailing: Text(config.transportMode.name),
                ),
                ListTile(
                  title: const Text('Plan tier'),
                  trailing: Text(config.planTier.name),
                ),
                ListTile(
                  title: const Text('Max concurrent requests'),
                  trailing: Text('${config.maxConcurrentRequests}'),
                ),
                ListTile(
                  title: const Text('Queued now'),
                  trailing: Text('${scheduler.queuedCount}'),
                ),
                ListTile(
                  title: const Text('In flight now'),
                  trailing: Text('${scheduler.totalInFlight}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
