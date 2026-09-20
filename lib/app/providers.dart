/// Composition root.
///
/// Every dependency is declared here and overridden in `main.dart`, so the
/// object graph is visible in one place and testable by substitution.
///
/// Two deliberate absences:
///
/// * **No provider for the raw token.** Nothing in the widget tree may hold
///   credential material — see `docs/security.md` §3. The token is read from
///   the vault at the moment of use, inside [SessionController], and never
///   enters a widget.
/// * **No transport provider.** A transport is not a singleton the app looks
///   up; it belongs to a session. [FileRepository] owns it, and the repository
///   travels inside [SessionState], so there is no window in which a widget
///   holds a live transport for a token the user has just revoked.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/error/puter_exception.dart';
import '../core/network/request_scheduler.dart';
import '../core/security/token_vault.dart';
import '../data/database/app_database.dart';
import '../data/database/node_cache.dart';
import '../data/platform/device_files.dart';
import '../data/repositories/file_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/transfer/transfer_engine.dart';
import '../data/transfer/transfer_store.dart';
import '../domain/entities/remote_node.dart';
import '../domain/entities/remote_path.dart';
import 'session.dart';

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

/// The on-device SQLite handle.
///
/// Overridden at startup. The default is refused rather than guessed so a
/// missing override is a loud startup failure instead of a silently volatile
/// index.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider must be overridden in main()');
});

/// The local index.
///
/// Overridden with the Drift-backed cache in `main.dart`. The default is the
/// in-memory implementation so widget tests — which run on the host, where the
/// bundled SQLite native library is not guaranteed to exist — can render the
/// browse UI without a database.
final nodeCacheProvider = Provider<NodeCache>((ref) => InMemoryNodeCache());

/// The persisted transfer queue.
final transferStoreProvider =
    Provider<TransferStore>((ref) => InMemoryTransferStore());

/// Non-secret preferences.
final preferencesStoreProvider =
    Provider<PreferencesStore>((ref) => InMemoryPreferencesStore());

/// Device-side file handling.
///
/// Overridden with the platform-channel implementation on Android. The default
/// answers "nothing was chosen", which is what the platform itself returns when
/// the user cancels a picker.
final deviceFilesProvider =
    Provider<DeviceFileService>((ref) => const UnavailableDeviceFiles());

/// Typed preferences on top of [preferencesStoreProvider].
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(preferencesStoreProvider)),
);

/// The signed-in session. Drives onboarding, the browser and sign-out.
final sessionProvider = AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// The repository for the active session, or `null` when signed out.
final fileRepositoryProvider = Provider<FileRepository?>(
  (ref) => ref.watch(sessionProvider).valueOrNull?.repository,
);

/// The transfer engine for the active session, or `null` when signed out.
///
/// Creating the engine restores its queue from storage, which is what makes a
/// task survive the process being killed. That happens here rather than from a
/// screen because transfers must resume whether or not the user opens the
/// transfers tab — a queue that only resumes while watched is not a queue.
final transferEngineProvider = Provider<TransferEngine?>((ref) {
  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return null;

  final engine = TransferEngine(
    repository: repository,
    store: ref.watch(transferStoreProvider),
    config: ref.watch(appConfigProvider),
  );
  unawaited(engine.restore());

  ref.onDispose(engine.dispose);
  return engine;
});

/// The live transfer queue.
final transfersProvider = StreamProvider<List<TransferTask>>((ref) {
  final engine = ref.watch(transferEngineProvider);
  if (engine == null) return Stream<List<TransferTask>>.value(const []);
  return engine.updates;
});

/// Live quota, refetchable.
final storageUsageProvider = FutureProvider<StorageUsage?>((ref) async {
  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return null;
  if (!repository.capabilities.canReportUsage) return null;
  try {
    return await repository.usage();
  } on PuterException {
    // The meter is informational. A transport that cannot report quota hides
    // the bar rather than showing a wrong one.
    return null;
  }
});

/// Identity of the signed-in account.
final identityProvider = FutureProvider<PuterIdentity?>((ref) async {
  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return null;
  try {
    return await repository.identity();
  } on PuterException {
    return null;
  }
});

/// How many entries the local index holds.
final cacheSizeProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return 0;
  return repository.cacheSize();
});

/// The folder the browser is showing.
final currentPathProvider = StateProvider<String>((ref) => RemotePath.root);
