/// First run: what this app is, what it will ask for, and why.
///
/// The disclosure here is a security requirement, not copy polish. The user is
/// being asked to hand over an account-wide root credential, and is entitled to
/// know that before pasting it — docs/security.md §5.
library;

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/token_entry_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
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
            const SizedBox(height: 28),
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
                        // Expanded, not a bare Text: the heading is the first
                        // thing to overflow on a narrow screen or at a large
                        // font scale, and an overlong title is a far better
                        // failure than a clipped one.
                        Expanded(
                          child: Text(
                            'Before you continue',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
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
            const SizedBox(height: 28),
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
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TokenEntryScreen(),
                ),
              ),
              icon: const Icon(Icons.key_outlined),
              label: const Text('Enter token'),
            ),
            const SizedBox(height: 20),
            const _Attribution(),
          ],
        ),
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

/// Required attribution: apps built on Puter are expected to link back.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text(
          'Powered by Puter',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          PuterEndpoints.attributionUrl,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
