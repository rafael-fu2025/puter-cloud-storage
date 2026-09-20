/// Persisted user preferences.
///
/// Non-secret only. The auth token is never here — it belongs to the
/// Keystore-backed vault alone (docs/security.md §3), and keeping the two
/// apart is what stops a preferences export from being a credential leak.
///
/// Every preference has a default that matches how the app behaved before the
/// setting existed, so a fresh install and an upgraded install look the same.
library;

import '../../domain/entities/remote_node.dart';
import '../database/app_database.dart';

/// How the browser lays a folder out.
enum BrowserViewMode { list, grid }

/// The browser's remembered shape.
class BrowserPreferences {
  const BrowserPreferences({
    this.sortField = NodeSortField.name,
    this.sortOrder = SortOrder.ascending,
    this.viewMode = BrowserViewMode.list,
    this.foldersFirst = true,
  });

  final NodeSortField sortField;
  final SortOrder sortOrder;
  final BrowserViewMode viewMode;

  /// Whether directories sort above files regardless of [sortOrder].
  ///
  /// On by default because it is what every file manager does; off is a real
  /// preference for people who sort by date and want the newest thing first
  /// whatever it is.
  final bool foldersFirst;

  BrowserPreferences copyWith({
    NodeSortField? sortField,
    SortOrder? sortOrder,
    BrowserViewMode? viewMode,
    bool? foldersFirst,
  }) {
    return BrowserPreferences(
      sortField: sortField ?? this.sortField,
      sortOrder: sortOrder ?? this.sortOrder,
      viewMode: viewMode ?? this.viewMode,
      foldersFirst: foldersFirst ?? this.foldersFirst,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrowserPreferences &&
      other.sortField == sortField &&
      other.sortOrder == sortOrder &&
      other.viewMode == viewMode &&
      other.foldersFirst == foldersFirst;

  @override
  int get hashCode =>
      Object.hash(sortField, sortOrder, viewMode, foldersFirst);
}

/// A place to keep small non-secret strings.
abstract class PreferencesStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// [PreferencesStore] backed by the Drift `settings` table.
class DriftPreferencesStore implements PreferencesStore {
  DriftPreferencesStore(this._db);

  final AppDatabase _db;

  @override
  Future<String?> read(String key) => _db.readSetting(key);

  @override
  Future<void> write(String key, String value) =>
      _db.writeSetting(key, value);

  @override
  Future<void> remove(String key) =>
      ( _db.delete(_db.settings)..where((t) => t.key.equals(key))).go();
}

/// Volatile [PreferencesStore] for tests.
class InMemoryPreferencesStore implements PreferencesStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

/// Typed access to the preferences above.
class SettingsRepository {
  SettingsRepository(this._store);

  final PreferencesStore _store;

  static const String _sortFieldKey = 'browser.sortField';
  static const String _sortOrderKey = 'browser.sortOrder';
  static const String _viewModeKey = 'browser.viewMode';
  static const String _foldersFirstKey = 'browser.foldersFirst';

  /// Load the browser's remembered shape.
  ///
  /// Unrecognised stored values fall back to the default rather than throwing:
  /// a preference written by a future build, or a corrupted row, must not stop
  /// the app from opening.
  Future<BrowserPreferences> loadBrowser() async {
    return BrowserPreferences(
      sortField: _enumFrom(
        await _store.read(_sortFieldKey),
        NodeSortField.values,
        NodeSortField.name,
      ),
      sortOrder: _enumFrom(
        await _store.read(_sortOrderKey),
        SortOrder.values,
        SortOrder.ascending,
      ),
      viewMode: _enumFrom(
        await _store.read(_viewModeKey),
        BrowserViewMode.values,
        BrowserViewMode.list,
      ),
      foldersFirst: await _store.read(_foldersFirstKey) != 'false',
    );
  }

  /// Persist the browser's shape.
  Future<void> saveBrowser(BrowserPreferences preferences) async {
    await _store.write(_sortFieldKey, preferences.sortField.name);
    await _store.write(_sortOrderKey, preferences.sortOrder.name);
    await _store.write(_viewModeKey, preferences.viewMode.name);
    await _store.write(
      _foldersFirstKey,
      preferences.foldersFirst ? 'true' : 'false',
    );
  }

  static T _enumFrom<T extends Enum>(
    String? value,
    List<T> values,
    T fallback,
  ) {
    if (value == null) return fallback;
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    return fallback;
  }
}
