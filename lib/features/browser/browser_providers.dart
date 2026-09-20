/// State the file browser reads.
///
/// The listing provider does something slightly unusual and worth stating
/// plainly: it renders from the **local index first** and corrects itself from
/// the network behind that render. Cold start is the reason. Puter caps WebDAV
/// at 600 requests/min shared per network, so a browser that waits for a
/// round trip before showing anything feels broken on a slow connection, when
/// in fact every folder the user has opened is already on disk.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/puter_exception.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';

/// The browser's remembered shape, loaded from and saved to preferences.
final browserPreferencesProvider =
    AsyncNotifierProvider<BrowserPreferencesController, BrowserPreferences>(
  BrowserPreferencesController.new,
);

/// Reads the stored preferences and writes them back on change.
class BrowserPreferencesController extends AsyncNotifier<BrowserPreferences> {
  @override
  Future<BrowserPreferences> build() =>
      ref.watch(settingsRepositoryProvider).loadBrowser();

  /// Apply a change and persist it.
  ///
  /// The in-memory state is updated before the write completes, so the UI
  /// responds to the tap immediately and a slow disk never feels like a lag.
  Future<void> apply(
    BrowserPreferences Function(BrowserPreferences current) change,
  ) async {
    final next = change(state.valueOrNull ?? const BrowserPreferences());
    state = AsyncValue<BrowserPreferences>.data(next);
    await ref.read(settingsRepositoryProvider).saveBrowser(next);
  }
}

/// Which folder the browser is showing, and how it got there.
final browserPathProvider = StateProvider<String>((ref) => RemotePath.root);

/// One folder's contents.
///
/// Keyed by path so navigating back to a folder is instant: the provider for
/// the previous folder is rebuilt from the index rather than refetched.
final directoryListingProvider = AsyncNotifierProvider.autoDispose
    .family<DirectoryListingController, DirectoryListing, String>(
  DirectoryListingController.new,
);

/// Loads and refreshes one directory listing.
class DirectoryListingController
    extends AutoDisposeFamilyAsyncNotifier<DirectoryListing, String> {
  StreamSubscription<Set<String>>? _changes;
  bool _isRefreshing = false;

  /// Set by `ref.onDispose`. `AsyncNotifierProviderRef` has no `mounted`, so
  /// this is how the async work below knows the provider is gone.
  bool _disposed = false;

  /// Whether a network refresh is in flight over an already-rendered listing.
  ///
  /// Distinct from `state.isLoading`: the browser shows content *and* a
  /// refreshing indicator, rather than replacing one with the other.
  bool get isRefreshing => _isRefreshing;

  @override
  Future<DirectoryListing> build(String path) async {
    final repository = ref.watch(fileRepositoryProvider);
    if (repository == null) {
      throw const PuterException(
        PuterErrorKind.authInvalid,
        'Not connected to Puter.',
      );
    }

    // Any mutation that touches this folder — or a folder above it, since a
    // rename reparents a whole subtree — invalidates this listing.
    _changes = repository.changes.listen((Set<String> changed) {
      final affected = changed.any(
        (String changedPath) =>
            changedPath == path || RemotePath.isWithin(changedPath, path),
      );
      if (affected) unawaited(refresh(force: false));
    });
    ref.onDispose(() {
      _disposed = true;
      _changes?.cancel();
    });

    // Index first. This is what makes a cold start instant.
    final cached = await repository.cachedChildren(path);
    if (cached.isNotEmpty) {
      final cachedAt = await repository.cachedAt(path);
      // Correct it in the background; the caller already has something to draw.
      unawaited(refresh(force: false));
      return DirectoryListing(
        path: path,
        items: cached,
        cachedAt: cachedAt,
        fromCache: true,
      );
    }

    return repository.listDirectory(path);
  }

  /// Refetch from the server.
  ///
  /// [force] bypasses the freshness window, which is what pull-to-refresh
  /// wants and what an automatic correction does not — an unforced refresh
  /// inside the TTL is served from the index and costs nothing.
  Future<void> refresh({bool force = true}) async {
    final repository = ref.read(fileRepositoryProvider);
    if (repository == null || _isRefreshing) return;

    _isRefreshing = true;
    try {
      final listing = await repository.listDirectory(arg, force: force);
      if (_disposed) return;
      state = AsyncValue<DirectoryListing>.data(listing);
    } on PuterException catch (error, stack) {
      if (_disposed) return;
      // Only replace content with an error when there is no content. Losing a
      // rendered folder because a background refresh failed would be a
      // regression in what the user can see.
      if (!state.hasValue) {
        state = AsyncValue<DirectoryListing>.error(error, stack);
      } else {
        state = AsyncValue<DirectoryListing>.data(
          state.requireValue.copyWith(failures: <NodeFailure>[
            NodeFailure(path: arg, message: error.message),
          ]),
        );
      }
    } finally {
      _isRefreshing = false;
    }
  }
}

/// Sort [nodes] the way the user chose.
///
/// Directories-first is a separate switch rather than part of the comparison,
/// because "newest first" and "folders at the top" are not the same preference
/// and most file managers let you hold both at once.
List<RemoteNode> applySort(
  List<RemoteNode> nodes,
  BrowserPreferences preferences,
) {
  final sorted = List<RemoteNode>.from(nodes);
  final direction = preferences.sortOrder == SortOrder.ascending ? 1 : -1;

  sorted.sort((RemoteNode a, RemoteNode b) {
    if (preferences.foldersFirst && a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }

    if (preferences.sortField == NodeSortField.modified) {
      // Handled before the direction multiplier, and deliberately so. A node
      // with no timestamp must sink to the bottom in *both* directions;
      // folding it into the comparison below would make `null` sort low and
      // then let the descending multiplier float every undated entry to the
      // top of a "newest first" list.
      final left = a.modifiedAt;
      final right = b.modifiedAt;
      if (left == null || right == null) {
        if (left == null && right == null) return _tiebreak(a, b);
        return left == null ? 1 : -1;
      }
      final byDate = left.compareTo(right);
      return byDate != 0 ? byDate * direction : _tiebreak(a, b);
    }

    final comparison = switch (preferences.sortField) {
      NodeSortField.name =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      NodeSortField.size => a.sizeBytes.compareTo(b.sizeBytes),
      // Unreachable: `modified` is handled above. Kept so the switch stays
      // total without a wildcard, which would silently swallow a future field.
      NodeSortField.modified => 0,
      NodeSortField.type => _extensionOf(a).compareTo(_extensionOf(b)),
    };

    if (comparison != 0) return comparison * direction;
    return _tiebreak(a, b);
  });

  return sorted;
}

/// Stable tiebreak, so two entries of the same size or age keep a fixed order
/// instead of shuffling between refreshes.
int _tiebreak(RemoteNode a, RemoteNode b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

String _extensionOf(RemoteNode node) {
  if (node.isDirectory) return '';
  return node.extension;
}

/// A human label for a sort field.
String sortFieldLabel(NodeSortField field) => switch (field) {
      NodeSortField.name => 'Name',
      NodeSortField.modified => 'Date modified',
      NodeSortField.size => 'Size',
      NodeSortField.type => 'Type',
    };
