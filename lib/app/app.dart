/// Application shell.
///
/// The root decides which of three things the user sees: onboarding, a
/// connecting state, or the app itself. That decision lives in one place so
/// there is no path into the signed-in UI without a live transport behind it —
/// which is what makes "the browser is always either working or explaining why
/// it is not" true rather than aspirational.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error/error_presenter.dart';
import 'home_shell.dart';
import 'providers.dart';
import 'session.dart';
import 'welcome_screen.dart';

/// Root widget.
class PuterCloudApp extends StatelessWidget {
  const PuterCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puter Cloud Storage',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const SessionGate(),
    );
  }

  /// Puter's own blue, so the app reads as a client of the platform rather than
  /// a separate product that happens to use it.
  static const Color _seed = Color(0xFF3B6EF6);

  static final ThemeData lightTheme = _buildTheme(Brightness.light);
  static final ThemeData darkTheme = _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // A flat visual language suits a file list, where the content is the
      // decoration and elevation on every row reads as noise.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 1,
      ),
      cardTheme: const CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        linearMinHeight: 4,
      ),
    );
  }
}

/// Routes between onboarding and the app based on the session state.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const _SessionLoading(),
      error: (Object error, StackTrace _) => _SessionFailure(error: error),
      data: (SessionState value) => switch (value.status) {
        SessionStatus.signedOut => const WelcomeScreen(),
        SessionStatus.failed =>
          _SessionFailure(error: value.error ?? 'Unknown failure'),
        SessionStatus.connecting => const _SessionLoading(),
        SessionStatus.ready => const HomeShell(),
      },
    );
  }
}

/// Shown while the stored credential is being turned into a session.
class _SessionLoading extends StatelessWidget {
  const _SessionLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'Connecting to Puter…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The last attempt failed. Says what happened and offers the one action that
/// can help.
///
/// Retry appears only when the error kind says a retry could plausibly succeed.
/// Offering it for a `429` lockout would walk the user straight back into the
/// failed-sign-in limit that produced it — the one mistake this app cannot
/// afford to make, because it locks the account out of its own storage.
class _SessionFailure extends ConsumerWidget {
  const _SessionFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final presentation = ErrorPresenter.describe(error);

    return Scaffold(
      appBar: AppBar(title: const Text('Puter Cloud Storage')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(presentation.icon, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 20),
              Text(
                presentation.title,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                presentation.message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (presentation.canRetry)
                FilledButton.icon(
                  onPressed: () => ref.invalidate(sessionProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              const SizedBox(height: 8),
              // Always available: a fresh token fixes a revoked one, and is the
              // only way forward when the stored credential is the problem.
              TextButton(
                onPressed: () => ref.read(sessionProvider.notifier).signOut(),
                child: const Text('Use a different token'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
