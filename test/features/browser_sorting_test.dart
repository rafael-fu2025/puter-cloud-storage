/// Tests for browser sorting and the preferences that drive it.
///
/// Sorting runs on every render of every folder, so the interesting cases are
/// the ones that make a list look wrong: a missing timestamp floating to the
/// top of a descending sort, two equal entries swapping places between
/// refreshes, and "folders first" being silently conflated with the sort field.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/data/repositories/settings_repository.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';
import 'package:puter_cloud_storage/features/browser/browser_providers.dart';

RemoteNode _file(
  String name, {
  int size = 0,
  DateTime? modified,
}) =>
    RemoteNode(
      path: '/$name',
      name: name,
      isDirectory: false,
      sizeBytes: size,
      modifiedAt: modified,
    );

RemoteNode _folder(String name, {DateTime? modified}) => RemoteNode(
      path: '/$name',
      name: name,
      isDirectory: true,
      modifiedAt: modified,
    );

List<String> _names(List<RemoteNode> nodes) =>
    nodes.map((RemoteNode n) => n.name).toList();

void main() {
  group('applySort', () {
    test('sorts by name, ascending by default', () {
      final sorted = applySort(
        <RemoteNode>[_file('c.txt'), _file('a.txt'), _file('b.txt')],
        const BrowserPreferences(),
      );
      expect(_names(sorted), <String>['a.txt', 'b.txt', 'c.txt']);
    });

    test('name sorting ignores case', () {
      final sorted = applySort(
        <RemoteNode>[_file('Zebra.txt'), _file('apple.txt')],
        const BrowserPreferences(),
      );
      expect(_names(sorted), <String>['apple.txt', 'Zebra.txt']);
    });

    test('puts folders first by default, whatever the sort field', () {
      final sorted = applySort(
        <RemoteNode>[_file('a.txt'), _folder('zebra')],
        const BrowserPreferences(sortField: NodeSortField.name),
      );
      expect(_names(sorted), <String>['zebra', 'a.txt']);
    });

    test('folders first can be turned off', () {
      // A real preference for people who sort by date and want the newest
      // thing at the top whatever it is.
      final sorted = applySort(
        <RemoteNode>[_file('a.txt'), _folder('zebra')],
        const BrowserPreferences(foldersFirst: false),
      );
      expect(_names(sorted), <String>['a.txt', 'zebra']);
    });

    test('reverses for descending', () {
      final sorted = applySort(
        <RemoteNode>[_file('a.txt'), _file('b.txt')],
        const BrowserPreferences(foldersFirst: false, sortOrder: SortOrder.descending),
      );
      expect(_names(sorted), <String>['b.txt', 'a.txt']);
    });

    test('sorts by size', () {
      final sorted = applySort(
        <RemoteNode>[
          _file('small.txt', size: 10),
          _file('large.txt', size: 5000),
          _file('medium.txt', size: 300),
        ],
        const BrowserPreferences(
          sortField: NodeSortField.size,
          foldersFirst: false,
        ),
      );
      expect(_names(sorted), <String>['small.txt', 'medium.txt', 'large.txt']);
    });

    test('sorts by type, grouping extensions', () {
      final sorted = applySort(
        <RemoteNode>[
          _file('notes.txt'),
          _file('photo.jpg'),
          _file('report.pdf'),
        ],
        const BrowserPreferences(
          sortField: NodeSortField.type,
          foldersFirst: false,
        ),
      );
      expect(_names(sorted), <String>['photo.jpg', 'report.pdf', 'notes.txt']);
    });

    test('sorts by modified date', () {
      final sorted = applySort(
        <RemoteNode>[
          _file('newer.txt', modified: DateTime(2026, 5, 1)),
          _file('older.txt', modified: DateTime(2026, 1, 1)),
          _file('newest.txt', modified: DateTime(2026, 9, 1)),
        ],
        const BrowserPreferences(
          sortField: NodeSortField.modified,
          foldersFirst: false,
        ),
      );
      expect(_names(sorted), <String>['older.txt', 'newer.txt', 'newest.txt']);
    });

    test('an unknown date sorts last in both directions', () {
      // The bug this prevents: `null` is low, so a descending sort would float
      // every undated entry to the top and push real dates off-screen.
      final nodes = <RemoteNode>[
        _file('undated.txt'),
        _file('dated.txt', modified: DateTime(2026, 1, 1)),
      ];

      final ascending = applySort(
        nodes,
        const BrowserPreferences(
          sortField: NodeSortField.modified,
          foldersFirst: false,
        ),
      );
      final descending = applySort(
        nodes,
        const BrowserPreferences(
          sortField: NodeSortField.modified,
          foldersFirst: false,
          sortOrder: SortOrder.descending,
        ),
      );

      expect(_names(ascending), <String>['dated.txt', 'undated.txt']);
      expect(_names(descending), <String>['dated.txt', 'undated.txt']);
    });

    test('breaks ties by name so results do not shuffle', () {
      final nodes = <RemoteNode>[
        _file('b.txt', size: 10),
        _file('a.txt', size: 10),
        _file('c.txt', size: 10),
      ];
      final first = applySort(
        nodes,
        const BrowserPreferences(
          sortField: NodeSortField.size,
          foldersFirst: false,
        ),
      );
      final second = applySort(
        nodes.reversed.toList(),
        const BrowserPreferences(
          sortField: NodeSortField.size,
          foldersFirst: false,
        ),
      );

      expect(_names(first), _names(second));
      expect(_names(first), <String>['a.txt', 'b.txt', 'c.txt']);
    });

    test('does not mutate the list it was given', () {
      final original = <RemoteNode>[_file('b.txt'), _file('a.txt')];
      applySort(original, const BrowserPreferences());
      expect(_names(original), <String>['b.txt', 'a.txt']);
    });

    test('an empty folder sorts to an empty list', () {
      expect(applySort(<RemoteNode>[], const BrowserPreferences()), isEmpty);
    });
  });

  group('sortFieldLabel', () {
    test('names every field', () {
      for (final NodeSortField field in NodeSortField.values) {
        expect(sortFieldLabel(field), isNotEmpty);
      }
    });
  });

  group('BrowserPreferences', () {
    test('defaults match a fresh install', () {
      const BrowserPreferences preferences = BrowserPreferences();
      expect(preferences.sortField, NodeSortField.name);
      expect(preferences.sortOrder, SortOrder.ascending);
      expect(preferences.viewMode, BrowserViewMode.list);
      expect(preferences.foldersFirst, isTrue);
    });

    test('copyWith changes only what it is given', () {
      const BrowserPreferences original = BrowserPreferences();
      final changed = original.copyWith(viewMode: BrowserViewMode.grid);

      expect(changed.viewMode, BrowserViewMode.grid);
      expect(changed.sortField, original.sortField);
      expect(changed.foldersFirst, original.foldersFirst);
    });

    test('equality is structural', () {
      expect(const BrowserPreferences(), const BrowserPreferences());
      expect(
        const BrowserPreferences(),
        isNot(const BrowserPreferences(viewMode: BrowserViewMode.grid)),
      );
    });
  });

  group('SettingsRepository', () {
    test('round-trips preferences', () async {
      final InMemoryPreferencesStore store = InMemoryPreferencesStore();
      final SettingsRepository repository = SettingsRepository(store);

      await repository.saveBrowser(
        const BrowserPreferences(
          sortField: NodeSortField.size,
          sortOrder: SortOrder.descending,
          viewMode: BrowserViewMode.grid,
          foldersFirst: false,
        ),
      );

      final loaded = await repository.loadBrowser();
      expect(loaded.sortField, NodeSortField.size);
      expect(loaded.sortOrder, SortOrder.descending);
      expect(loaded.viewMode, BrowserViewMode.grid);
      expect(loaded.foldersFirst, isFalse);
    });

    test('an empty store yields the defaults', () async {
      final repository = SettingsRepository(InMemoryPreferencesStore());
      final loaded = await repository.loadBrowser();
      expect(loaded, const BrowserPreferences());
    });

    test('an unrecognised stored value falls back rather than throwing',
        () async {
      // A preference written by a future build, or a corrupted row, must not
      // stop the app from opening.
      final store = InMemoryPreferencesStore();
      await store.write('browser.sortField', 'somethingRemoved');
      await store.write('browser.viewMode', 'carousel');

      final loaded = await SettingsRepository(store).loadBrowser();

      expect(loaded.sortField, NodeSortField.name);
      expect(loaded.viewMode, BrowserViewMode.list);
    });
  });
}
