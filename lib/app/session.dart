/// The signed-in session: one token, one transport, one repository.
///
/// Authentication is the highest-risk operation in the app, and the shape here
/// is a direct consequence. WebDAV locks an account out for 15 minutes after
/// ten failed sign-ins, returning 429 *even for a correct token*
/// (docs/security.md §4, `docs/puter-api-research.md` §5). So:
///
/// * **One attempt per user action.** There is no retry loop anywhere on this
///   path, not even for a transient-looking failure. A user who mistypes a
///   token twice is fine; a client that retries is locked out of its own
///   storage.
/// * **Failure is a value, not an exception.** [SessionState] carries the
///   error, so the onboarding screen renders it as a message next to the input
///   rather than as a crashed provider. That also keeps the token field usable
///   for a corrected retry.
/// * **Sign-out destroys everything it created.** The transport is disposed,
///   the transfer queue is stopped and the local index is dropped, so one
///   account's file names can never appear under another's token.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error/puter_exception.dart';
import '../data/repositories/file_repository.dart';
import '../data/transport/puter_transport.dart';
import '../data/transport/webdav_transport.dart';
import '../domain/entities/remote_node.dart';
import '../domain/entities/remote_path.dart';
import 'providers.dart';

/// Where the session is in its lifecycle.
enum SessionStatus {
  /// No token stored. The onboarding flow is shown.
  signedOut,

  /// A token exists and a transport is being established.
  connecting,

  /// A transport is live and the file browser is usable.
  ready,

  /// The last attempt failed. [SessionState.error] says how.
  failed,
}

/// The state of the session, including the failure that produced it.
class SessionState {
  const SessionState._({
    required this.status,
    this.repository,
    this.error,
    this.endpoint,
  });

  /// No token has been stored yet.
  const SessionState.signedOut() : this._(status: SessionStatus.signedOut);

  /// Establishing the transport.
  const SessionState.connecting() : this._(status: SessionStatus.connecting);

  /// A live session.
  const SessionState.ready({
    required FileRepository repository,
    required String endpoint,
  }) : this._(
          status: SessionStatus.ready,
          repository: repository,
          endpoint: endpoint,
        );

  /// The attempt failed. [error] is a [PuterException] in practice.
  const SessionState.failed(Object error)
      : this._(status: SessionStatus.failed, error: error);

  final SessionStatus status;

  /// Non-null exactly when [status] is [SessionStatus.ready].
  final FileRepository? repository;

  /// Why the attempt failed, when it did.
  final Object? error;

  /// The WebDAV host that answered, for the settings screen.
  final String? endpoint;

  bool get isReady => status == SessionStatus.ready && repository != null;
  bool get isBusy => status == SessionStatus.connecting;
}

/// Owns the lifecycle of the session.
class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    final vault = ref.watch(tokenVaultProvider);
    final token = await vault.read();

    if (token == null) return const SessionState.signedOut();

    // Returning is not the same as validating, but it is deliberately *not* a
    // silent re-authentication: a background probe that fails would spend
    // failed-sign-in budget the user never asked to spend. The transport
    // proves the token on the first real request instead, and a 401 there is
    // handled once, in [handleAuthRevoked].
    return _connect(token, persist: false);
  }

  /// Validate [token] and, if it works, store it and install the session.
  ///
  /// Called once per user action. Never retried internally.
  Future<void> signIn(String token) async {
    state = const AsyncValue<SessionState>.loading();
    final result = await _connect(token, persist: true);
    state = AsyncValue<SessionState>.data(result);
  }

  /// Forget the credential and everything derived from it.
  Future<void> signOut() async {
    // Captured before the state changes: once it is `loading`, the repository
    // is no longer reachable from `state` and there would be nothing to
    // dispose.
    final previous = state.valueOrNull?.repository;
    state = const AsyncValue<SessionState>.loading();

    final vault = ref.read(tokenVaultProvider);
    await vault.clear();

    // Drop the index and the queue, both of which belong to the account that
    // created them. Leaving either behind would show one account's file names
    // under another's token.
    await previous?.clearCache();
    await previous?.dispose();
    await ref.read(transferStoreProvider).removeInStates(
          TransferState.values.toSet(),
        );

    state = const AsyncValue<SessionState>.data(SessionState.signedOut());
  }

  /// Handle a `401` discovered by an ordinary request.
  ///
  /// Clears the credential rather than retrying: a retry loop here walks
  /// straight into the failed-sign-in lockout. The user is returned to
  /// onboarding, where a single fresh attempt is safe.
  Future<void> handleAuthRevoked() async {
    if (state.valueOrNull?.status == SessionStatus.signedOut) return;
    final vault = ref.read(tokenVaultProvider);
    final previous = state.valueOrNull?.repository;
    await vault.clear();
    await previous?.dispose();
    state = const AsyncValue<SessionState>.data(
      SessionState.failed(_revoked),
    );
  }

  static const PuterException _revoked = PuterException(
    PuterErrorKind.authInvalid,
    'Puter rejected the stored token. It may have been revoked from the '
    'dashboard.',
  );

  /// Build a transport, authenticate it once, and wrap it in a repository.
  ///
  /// Errors are returned as [SessionState.failed] rather than thrown, so the
  /// onboarding screen can show them beside the input and keep the user's
  /// typed token for a correction.
  Future<SessionState> _connect(String token, {required bool persist}) async {
    final config = ref.read(appConfigProvider);
    final scheduler = ref.read(requestSchedulerProvider);
    final vault = ref.read(tokenVaultProvider);

    // One look at the lockout budget before spending any of it.
    if (!scheduler.authAttemptSafe) {
      return const SessionState.failed(
        PuterException(
          PuterErrorKind.rateLimited,
          'Too many failed sign-in attempts in the last 15 minutes. WebDAV '
          'locks the account for 15 minutes after 10, and returns 429 even '
          'for a correct token. Wait, then try once more.',
        ),
      );
    }

    WebDavTransport? transport;
    try {
      transport = WebDavTransport(scheduler: scheduler, config: config);
      await transport.authenticate(TokenCredential(token));

      if (persist) await vault.write(token);

      final repository = FileRepository(
        transport: transport,
        cache: ref.read(nodeCacheProvider),
        config: config,
      );

      // Warm the index so the first render has something to show and the root
      // listing exists for offline browse. Failure is not fatal and is not
      // reported: the browser surfaces it on its own first refresh, where the
      // user can do something about it.
      unawaited(
        _warmUp(repository),
      );

      return SessionState.ready(
        repository: repository,
        endpoint: transport.endpoint ?? 'unknown',
      );
    } on PuterException catch (error) {
      await transport?.dispose();
      return SessionState.failed(error);
    } catch (error) {
      await transport?.dispose();
      return SessionState.failed(
        PuterException(
          PuterErrorKind.unknown,
          'Could not establish a session: $error',
          cause: error,
        ),
      );
    }
  }

  /// Fetch the root listing once, ignoring the outcome.
  ///
  /// The point is the side effect: the index now holds a browsable root, which
  /// is what a cold start renders before any network call returns.
  static Future<void> _warmUp(FileRepository repository) async {
    try {
      await repository.listDirectory(RemotePath.root);
    } on PuterException {
      // Not fatal, and not reported here — the browser shows the failure on
      // its own first refresh, where the user can retry it.
    } on Object {
      // Same reasoning for anything unexpected: a warm-up that fails must not
      // take down a session that just authenticated successfully.
    }
  }
}