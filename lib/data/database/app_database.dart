/// Local index — the client's own copy of the remote filesystem.
///
/// This is **not** a throwaway cache. Puter offers no server-side search and
/// caps WebDAV at 600 requests/min shared per network, so the only way to
/// browse a large account without burning the budget is to keep an
/// authoritative-enough local copy and serve from it. See
/// `docs/architecture.md` §6.1.
///
/// The schema mirrors the domain model rather than the wire format, so a
/// transport change (WebDAV → WebView) never forces a migration.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/remote_path.dart';

part 'app_database.g.dart';

/// One cached entry in the remote filesystem.
///
/// [path] is the primary key because a path uniquely identifies a node in
/// Puter's namespace and every listing arrives with it already known. A
/// synthetic id would only buy a join.
@DataClassName('RemoteNodeRow')
@TableIndex(name: 'idx_remote_nodes_parent', columns: {#parentPath})
@TableIndex(name: 'idx_remote_nodes_name', columns: {#name})
class RemoteNodes extends Table {
  /// Absolute remote path including the node's own name, e.g.
  /// `/Documents/report.pdf`.
  TextColumn get path => text()();

  /// Display name without the path, e.g. `report.pdf`.
  TextColumn get name => text()();

  /// Coarse category — `folder` or `file`.
  TextColumn get type => text()();

  /// File size in bytes. `0` for folders.
  IntColumn get size => integer().withDefault(const Constant(0))();

  /// Last modified time, or `null` when the server did not report one.
  DateTimeColumn get modified => dateTime().nullable()();

  /// Parent directory path, or `null` for the root itself. Indexed, because
  /// every folder render is a lookup by this column.
  TextColumn get parentPath => text().nullable()();

  /// Whether this node is a folder.
  BoolColumn get isFolder => boolean().withDefault(const Constant(false))();

  /// When this row was last confirmed against the server.
  DateTimeColumn get cachedAt => dateTime()();

  TextColumn get mimeType => text().nullable()();

  /// Server-side version marker. Used to skip no-op writes on refresh.
  TextColumn get etag => text().nullable()();

  /// `null` when unknown, matching the domain's tri-state sharing flag.
  BoolColumn get isShared => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{path};
}

/// Persistent transfer queue.
///
/// The schema is one version-1 shape, including these columns, so Phase 3 did
/// not need a migration on the first transfer.
@DataClassName('TransferTaskRow')
class TransferTasks extends Table {
  /// Domain-supplied task id. Text, not autoincrement, so a task keeps its
  /// identity across a process restart.
  TextColumn get id => text()();

  /// `upload` or `download`.
  TextColumn get direction => text()();

  TextColumn get remotePath => text()();
  TextColumn get localPath => text()();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  IntColumn get bytesDone => integer().withDefault(const Constant(0))();

  /// One of `TransferState`'s names.
  TextColumn get state => text()();

  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Non-secret user preferences.
///
/// Sort field, sort order and view mode live here so the browser reopens the
/// way the user left it. The auth token is never here — it belongs to the
/// Keystore-backed vault alone.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}

/// The application database.
@DriftDatabase(tables: <Type>[RemoteNodes, TransferTasks, Settings])
class AppDatabase extends _$AppDatabase {
  /// Construct with an explicit executor — used by tests and by [AppDatabase.open].
  AppDatabase(super.e);

  /// Open the on-device database.
  AppDatabase.open() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Schema version 1 is the first release. Future migrations are added
          // here one `if (from < n)` step at a time — never by dropping and
          // recreating, which would throw away the local index that offline
          // browse depends on.
        },
        beforeOpen: (OpeningDetails details) async {
          // Not used by the current schema, but enabling it now means a later
          // foreign key behaves as written rather than silently not enforcing.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // -------------------------------------------------------------- index reads

  /// Immediate children of [parentPath].
  ///
  /// Ordering is left to the caller: the domain sorts client-side anyway
  /// because Puter's ordering is not guaranteed and directories must sort
  /// before files.
  Future<List<RemoteNodeRow>> childrenOf(String parentPath) {
    final query = select(remoteNodes)
      ..where((RemoteNodes t) => t.parentPath.equals(parentPath));
    return query.get();
  }

  /// The single row at [path], or `null` when it is not cached.
  Future<RemoteNodeRow?> nodeAt(String path) {
    final query = select(remoteNodes)
      ..where((RemoteNodes t) => t.path.equals(path));
    return query.getSingleOrNull();
  }

  /// Every cached row at [path] or beneath it.
  ///
  /// Uses a prefix match so a rename or delete reconciles a whole subtree
  /// without walking it in Dart. The prefix is escaped for `LIKE` first — a
  /// directory literally named `100%` would otherwise match far more than
  /// intended.
  Future<List<RemoteNodeRow>> subtreeOf(String path) {
    final prefix = '${_escapeLike(path)}/%';
    final query = select(remoteNodes)
      ..where((RemoteNodes t) =>
          t.path.equals(path) | t.path.like(prefix, escapeChar: _likeEscape));
    return query.get();
  }

  /// When [parentPath]'s children were last confirmed, or `null` if never.
  Future<DateTime?> lastCachedAt(String parentPath) async {
    final query = selectOnly(remoteNodes)
      ..addColumns(<Expression<Object>>[remoteNodes.cachedAt.max()])
      ..where(remoteNodes.parentPath.equals(parentPath));
    final row = await query.getSingleOrNull();
    return row?.read(remoteNodes.cachedAt.max());
  }

  /// Rows whose *name* contains [query].
  ///
  /// Served entirely from the local index. Puter has no server-side search over
  /// the filesystem, and WebDAV's 600 requests/min is shared per network, so a
  /// search that walked the remote tree would spend the budget browsing needs.
  /// Results therefore cover what has been indexed so far, which the search
  /// screen states plainly rather than pretending to be exhaustive.
  ///
  /// [scopePath] restricts results to one subtree. Ordering is left to the
  /// caller, matching [childrenOf].
  Future<List<RemoteNodeRow>> searchByName(
    String query, {
    String? scopePath,
    int limit = 200,
  }) {
    final pattern = '%${_escapeLike(query)}%';
    var predicate = remoteNodes.name.like(pattern, escapeChar: _likeEscape);

    final scope = scopePath;
    if (scope != null && scope != rootPath) {
      final prefix = '${_escapeLike(scope)}/%';
      predicate = predicate & remoteNodes.path.like(prefix,
          escapeChar: _likeEscape);
    }

    final statement = select(remoteNodes)
      ..where((RemoteNodes t) => predicate)
      ..limit(limit);
    return statement.get();
  }

  /// How many entries the index holds, for cache management.
  Future<int> cachedNodeCount() async {
    final count = remoteNodes.path.count();
    final query = selectOnly(remoteNodes)
      ..addColumns(<Expression<Object>>[count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Every folder path in the index.
  ///
  /// Used by the background refresh sweep, which walks known folders rather
  /// than the remote tree — the same request-budget reasoning as search.
  Future<List<String>> indexedFolderPaths() async {
    final query = select(remoteNodes)
      ..where((RemoteNodes t) => t.isFolder.equals(true));
    final rows = await query.get();
    return rows.map((row) => row.path).toList(growable: false);
  }

  // ------------------------------------------------------------ index writes

  /// Insert or replace a batch of rows in one transaction.
  ///
  /// A listing that is half-written would make a folder look like it lost
  /// files, which is exactly the failure the local index exists to prevent.
  Future<void> upsertAll(List<RemoteNodesCompanion> rows) {
    if (rows.isEmpty) return Future<void>.value();
    return transaction(() async {
      for (final row in rows) {
        await into(remoteNodes).insertOnConflictUpdate(row);
      }
    });
  }

  /// Replace every child of [parentPath] with [rows], atomically.
  ///
  /// Delete and insert share a transaction so a crash mid-refresh cannot leave
  /// the folder empty.
  Future<void> replaceChildren(
    String parentPath,
    List<RemoteNodesCompanion> rows,
  ) {
    return transaction(() async {
      await (delete(remoteNodes)
            ..where((RemoteNodes t) => t.parentPath.equals(parentPath)))
          .go();
      await upsertAll(rows);
    });
  }

  /// Remove one row. Children are untouched — the caller decides whether the
  /// node is a leaf.
  Future<void> deleteAt(String path) {
    return (delete(remoteNodes)..where((RemoteNodes t) => t.path.equals(path)))
        .go();
  }

  /// Remove [path] and everything beneath it.
  Future<void> deleteSubtree(String path) {
    final prefix = '${_escapeLike(path)}/%';
    return (delete(remoteNodes)
          ..where((RemoteNodes t) => t.path.equals(path) | t.path.like(prefix)))
        .go();
  }

  /// Rewrite the paths of a moved or renamed subtree.
  ///
  /// Done row by row rather than as one `UPDATE ... replace()` because SQLite's
  /// `replace()` would also rewrite any *other* occurrence of the prefix inside
  /// a path, not only the leading one.
  Future<void> rewriteSubtreePath(String from, String to) {
    return transaction(() async {
      final rows = await subtreeOf(from);
      for (final row in rows) {
        final newPath =
            row.path == from ? to : '$to${row.path.substring(from.length)}';
        await (update(remoteNodes)
              ..where((RemoteNodes t) => t.path.equals(row.path)))
            .write(
          RemoteNodesCompanion(
            path: Value<String>(newPath),
            parentPath: Value<String?>(_parentOf(newPath)),
          ),
        );
      }
    });
  }

  /// Drop the whole index.
  ///
  /// Called on sign-out so one account's paths can never appear under
  /// another's token.
  Future<void> clearIndex() => delete(remoteNodes).go();

  // ---------------------------------------------------------------- settings

  /// Read a non-secret preference, or `null` when unset.
  Future<String?> readSetting(String key) async {
    final query = select(settings)..where((Settings t) => t.key.equals(key));
    final row = await query.getSingleOrNull();
    return row?.value;
  }

  /// Persist a non-secret preference.
  Future<void> writeSetting(String key, String value) {
    return into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: value),
    );
  }

  // --------------------------------------------------------------- transfers

  /// The whole persisted transfer queue, oldest first.
  ///
  /// Read once at startup rather than being paged: ADR 0004 makes a task
  /// per-file and the list is bounded by what the user started, so a single
  /// query is both simpler and fast enough.
  Future<List<TransferTaskRow>> allTransferTasks() {
    final query = select(transferTasks)
      ..orderBy(<OrderClauseGenerator<TransferTasks>>[
        (TransferTasks t) => OrderingTerm(expression: t.createdAt),
      ]);
    return query.get();
  }

  /// Insert or update one task.
  Future<void> upsertTransferTask(TransferTasksCompanion row) =>
      into(transferTasks).insertOnConflictUpdate(row);

  /// Remove one task.
  Future<void> deleteTransferTask(String id) =>
      (delete(transferTasks)..where((TransferTasks t) => t.id.equals(id))).go();

  /// Remove every task in a terminal state.
  ///
  /// Called by the transfer screen's "Clear finished" action. Deliberately
  /// keyed on the state strings rather than on `isTerminal`, because the
  /// database layer must not depend on the domain enum's current definition —
  /// a future state added to the enum should not silently start deleting rows.
  Future<void> deleteTransferTasksInStates(List<String> states) {
    if (states.isEmpty) return Future<void>.value();
    return (delete(transferTasks)
          ..where((TransferTasks t) => t.state.isIn(states)))
        .go();
  }

  // ------------------------------------------------------------------ helpers

  /// Escape character the `LIKE` patterns above are built with.
  ///
  /// SQLite treats `\` as an ordinary character unless `ESCAPE` says
  /// otherwise, so passing this alongside [AppDatabase._escapeLike] is what
  /// makes the escaping mean anything.
  static const String _likeEscape = r'\';

  /// The remote filesystem root.
  static const String rootPath = RemotePath.root;

  /// Escape `LIKE` wildcards so a literal `%` or `_` in a name cannot widen a
  /// prefix match.
  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static String? _parentOf(String path) {
    if (path == '/' || path.isEmpty) return null;
    final trimmed =
        path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final index = trimmed.lastIndexOf('/');
    if (index < 0) return null;
    if (index == 0) return '/';
    return trimmed.substring(0, index);
  }
}

/// Opens the on-device database lazily, off the UI thread.
///
/// `LazyDatabase` defers the file lookup until the first query, so startup is
/// never blocked by path resolution or by opening SQLite.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'puter_index.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
