/// Composition root.
///
/// Every dependency is declared here and overridden in `main.dart`, so the
/// object graph is visible in one place and testable by substitution.
///
/// Deliberately **absent**: a provider for the raw token. Nothing in the
/// widget tree may hold credential material — see `docs/security.md` §3.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/network/request_scheduler.dart';
import '../core/security/token_vault.dart';
import '../data/transport/puter_transport.dart';

/// Active configuration. Overridden at startup.
final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider must be overridden in main()');
});

/// Secure token storage. Overridden at startup.
final tokenVaultProvider = Provider<TokenVault>((ref) {
  throw UnimplementedError('tokenVaultProvider must be overridden in main()');
});

/// The single request scheduler through which all Puter traffic passes.
final requestSchedulerProvider = Provider<RequestScheduler>((ref) {
  throw UnimplementedError(
    'requestSchedulerProvider must be overridden in main()',
  );
});

/// The active transport.
///
/// Assigned once authentication succeeds and the transport is probed. Until
/// then it is `null`, which is the state the onboarding flow renders.
///
/// Kept as a `NotifierProvider` rather than a plain `Provider` because the
/// transport can change mid-session: the app falls back from WebDAV to the
/// WebView bridge when the former is unavailable.
final activeTransportProvider =
    NotifierProvider<ActiveTransportNotifier, PuterTransport?>(
  ActiveTransportNotifier.new,
);

/// Holds the currently selected transport.
class ActiveTransportNotifier extends Notifier<PuterTransport?> {
  @override
  PuterTransport? build() => null;

  /// Install a transport, disposing whatever it replaces.
  Future<void> install(PuterTransport transport) async {
    final previous = state;
    state = transport;
    if (previous != null && previous != transport) {
      await previous.dispose();
    }
  }

  /// Tear the transport down — on sign-out, or on a revoked credential.
  Future<void> clear() async {
    final previous = state;
    state = null;
    await previous?.dispose();
  }
}

/// Whether the app holds a token.
///
/// Exposes a boolean, never the token itself, so no widget can accidentally
/// render or serialise the credential.
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  final vault = ref.watch(tokenVaultProvider);
  return vault.hasToken;
});

/// Whether the app is running in degraded mode because WebDAV was unavailable.
///
/// The UI surfaces this as a persistent banner, so the user knows why features
/// are missing rather than assuming the app is broken.
final degradedModeProvider = StateProvider<bool>((ref) => false);
