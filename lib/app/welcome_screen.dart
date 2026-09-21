/// First run.
///
/// Two things have to coexist here: this is the friendliest screen in the app,
/// and it is also where the user hands over a credential that grants full
/// access to their account (`docs/security.md` §5). The previous version tried
/// to resolve that tension by shouting — a pink `errorContainer` card with a
/// warning triangle, before the user had seen a single file. That reads as
/// "something has already gone wrong", which is not the feeling to open on.
///
/// The disclosure is still here, in full, and still says what the key can do. It
/// is simply delivered as information rather than as an alarm, because the
/// honest framing is "here is what you are about to do" and not "danger".
library;

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/ui/components.dart';
import '../core/ui/design.dart';
import '../data/platform/platform_bridge.dart';
import '../features/auth/token_entry_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xxl,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: <Widget>[
            Column(
              children: <Widget>[
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_rounded,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Your files, on Puter',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Browse, search and move the files in your own Puter '
                  'account, from your phone.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            // What the user is about to hand over, stated plainly and without
            // alarm. This is the security disclosure required by
            // docs/security.md §5 — it is not optional copy.
            SectionCard(
              title: 'What you will need',
              children: <Widget>[
                const _Step(
                  number: 1,
                  title: 'Open your Puter account',
                  detail: 'In a browser, go to puter.com and sign in.',
                ),
                const _Step(
                  number: 2,
                  title: 'Create an access key',
                  detail: 'On the Account page, find the API token section and '
                      'tap Create token. Puter copies it for you.',
                ),
                const _Step(
                  number: 3,
                  title: 'Paste it here',
                  detail: 'Come back and paste it in. This app will keep it '
                      'securely on this device.',
                  isLast: true,
                ),
                const AppDivider(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.shield_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'An access key lets this app read, change and delete '
                          'anything in your Puter account — it is as powerful '
                          'as your password. Keep it private, and revoke it '
                          'from the same Puter page whenever you like.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TokenEntryScreen(),
                ),
              ),
              icon: const Icon(Icons.key_rounded),
              label: const Text('Add my access key'),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: TextButton.icon(
                onPressed: () => PlatformBridge.openUrl(
                  PuterEndpoints.dashboardAccount,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open Puter to get a key'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Text(
                'Built on Puter · developer.puter.com',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One numbered step.
///
/// A real numbered badge rather than "1." in bold text, so the sequence is
/// something the eye can follow without reading every line.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
    this.isLast = false,
  });

  final int number;
  final String title;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
                const SizedBox(height: 2),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
