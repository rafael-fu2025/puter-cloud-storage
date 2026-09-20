/// The file browser.
///
/// Three things about this screen are load-bearing rather than decorative.
///
/// **The storage meter is not a progress bar.** `413 storage_limit_reached` is
/// not retryable — when the account is full, uploads simply stop until the user
/// frees space elsewhere. So the meter turns into a warning at 90% and says what
/// to do, rather than letting the user discover the limit by watching an upload
/// fail.
///
/// **Partial listings are shown as partial.** A WebDAV `207 Multistatus` can
/// carry per-entry failures while the response as a whole succeeds, so a folder
/// can be genuinely incomplete. Entries the server refused are reported in a
/// banner — dropping them silently would make files invisible with no
/// explanation, which is the failure mode that destroys trust in a file manager.
///
/// **Empty is not the same as broken.** An empty folder, a folder that has never
/// been visited offline, and a folder that failed to load are three different
/// states, and they get three different screens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/format/file_kinds.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import 'browser_providers.dart';
import 'file_actions.dart';

class FileBrowserScreen extends ConsumerWidget {
  const FileBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(browserPathProvider);
    final listing = ref.watch(directoryListingProvider(path));
    final preferences = ref.watch(browserPreferencesProvider).valueOrNull ??
        const BrowserPreferences();

    return Scaffold(
      appBar: _BrowserAppBar(path: path),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => FileActions.upload(context, ref),
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload'),
      ),
      body: Column(
        children: <Widget>[
          const StorageMeter(),
          Breadcrumbs(path: path),
          const _PartialFailureBanner(),
          Expanded(
            child: listing.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace _) => _BrowserError(
                error: error,
                onRetry: () =>
                    ref.read(directoryListingProvider(path).notifier).refresh(),
              ),
              data: (DirectoryListing value) => RefreshIndicator(
                onRefresh: () =>
                    ref.read(directoryListingProvider(path).notifier).refresh(),
                child: value.items.isEmpty
                    ? _EmptyFolder(path: path)
                    : _NodeList(
                        listing: value,
                        preferences: preferences,
                        onOpen: (RemoteNode node) =>
                            _open(context, ref, node),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A folder descends; a file offers its actions.
  static Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    if (node.isDirectory) {
      ref.read(browserPathProvider.notifier).state = node.path;
      return;
    }
    await _showNodeSheet(context, ref, node);
  }
}

/// Title, view toggle, sort menu and the overflow.
class _BrowserAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _BrowserAppBar({required this.path});

  final String path;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(browserPreferencesProvider).valueOrNull ??
        const BrowserPreferences();
    final isRoot = path == RemotePath.root;

    return AppBar(
      title: Text(isRoot ? 'Files' : RemotePath.name(path)),
      leading: isRoot
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Up one level',
              onPressed: () => ref.read(browserPathProvider.notifier).state =
                  RemotePath.parent(path) ?? RemotePath.root,
            ),
      actions: <Widget>[
        IconButton(
          icon: Icon(
            preferences.viewMode == BrowserViewMode.grid
                ? Icons.view_list
                : Icons.grid_view,
          ),
          tooltip: preferences.viewMode == BrowserViewMode.grid
              ? 'Show as list'
              : 'Show as grid',
          onPressed: () => ref.read(browserPreferencesProvider.notifier).apply(
                (BrowserPreferences current) => current.copyWith(
                  viewMode: current.viewMode == BrowserViewMode.grid
                      ? BrowserViewMode.list
                      : BrowserViewMode.grid,
                ),
              ),
        ),
        _SortMenu(preferences: preferences),
        PopupMenuButton<_BrowserMenuAction>(
          tooltip: 'More',
          onSelected: (_BrowserMenuAction action) => switch (action) {
            _BrowserMenuAction.newFolder => FileActions.createFolder(context, ref),
            _BrowserMenuAction.uploadHere => FileActions.upload(context, ref),
            _BrowserMenuAction.refresh => ref
                .read(directoryListingProvider(path).notifier)
                .refresh(force: true),
          },
          itemBuilder: (BuildContext context) =>
              const <PopupMenuEntry<_BrowserMenuAction>>[
            PopupMenuItem<_BrowserMenuAction>(
              value: _BrowserMenuAction.newFolder,
              child: ListTile(
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('New folder'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem<_BrowserMenuAction>(
              value: _BrowserMenuAction.uploadHere,
              child: ListTile(
                leading: Icon(Icons.upload_file),
                title: Text('Upload here'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem<_BrowserMenuAction>(
              value: _BrowserMenuAction.refresh,
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Refresh'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _BrowserMenuAction { newFolder, uploadHere, refresh }

/// Sort field and direction.
class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.preferences});

  final BrowserPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<NodeSortField>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort),
      initialValue: preferences.sortField,
      onSelected: (NodeSortField field) =>
          ref.read(browserPreferencesProvider.notifier).apply(
                (BrowserPreferences current) =>
                    current.copyWith(sortField: field),
              ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<NodeSortField>>[
        for (final field in NodeSortField.values)
          PopupMenuItem<NodeSortField>(
            value: field,
            child: Row(
              children: <Widget>[
                if (field == preferences.sortField)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 12),
                Text(sortFieldLabel(field)),
                const Spacer(),
                if (field == preferences.sortField)
                  Icon(
                    preferences.sortOrder == SortOrder.ascending
                        ? Icons.arrow_upward
                        : Icons.arrow_downward,
                    size: 16,
                  ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<NodeSortField>(
          // A sentinel that flips the direction without changing the field.
          value: preferences.sortField,
          onTap: () =>
              ref.read(browserPreferencesProvider.notifier).apply(
                    (BrowserPreferences current) => current.copyWith(
                      sortOrder: current.sortOrder == SortOrder.ascending
                          ? SortOrder.descending
                          : SortOrder.ascending,
                    ),
                  ),
          child: const ListTile(
            leading: Icon(Icons.swap_vert),
            title: Text('Reverse order'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<NodeSortField>(
          value: preferences.sortField,
          onTap: () =>
              ref.read(browserPreferencesProvider.notifier).apply(
                    (BrowserPreferences current) => current.copyWith(
                      foldersFirst: !current.foldersFirst,
                    ),
                  ),
          child: ListTile(
            leading: Icon(
              preferences.foldersFirst
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
            ),
            title: const Text('Folders first'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Quota, with the warning that arrives before the error does.
class StorageMeter extends ConsumerWidget {
  const StorageMeter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usage = ref.watch(storageUsageProvider).valueOrNull;
    final config = ref.watch(appConfigProvider);
    if (usage == null) return const SizedBox.shrink();

    final isNearLimit =
        usage.isNearLimit(config.quotaWarningThreshold);
    final background =
        isNearLimit ? theme.colorScheme.errorContainer : Colors.transparent;
    final foreground = isNearLimit
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      child: InkWell(
        onTap: () => ref.invalidate(storageUsageProvider),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '${ByteFormat.format(usage.usedBytes)} of '
                    '${ByteFormat.format(usage.capacityBytes)} used',
                    style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                  ),
                  const Spacer(),
                  Text(
                    '${usage.percentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: usage.usedFraction,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: isNearLimit
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              if (isNearLimit) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Almost out of space. Uploads will be refused once the quota '
                  'is full — free space in the Puter web app to keep going.',
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the user is, and how to get back up.
class Breadcrumbs extends ConsumerWidget {
  const Breadcrumbs({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final crumbs = RemotePath.breadcrumbs(path);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        // A deep path can exceed the width, so the list is reversed to keep the
        // current folder reachable without scrolling.
        reverse: true,
        itemCount: crumbs.length,
        itemBuilder: (BuildContext context, int index) {
          final crumb = crumbs[crumbs.length - 1 - index];
          final isLast = crumb.path == path;
          return Row(
            children: <Widget>[
              if (index > 0)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              TextButton(
                onPressed: isLast
                    ? null
                    : () =>
                        ref.read(browserPathProvider.notifier).state = crumb.path,
                child: Text(
                  crumb.label,
                  style: TextStyle(
                    fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Reports entries the server returned but refused to describe.
class _PartialFailureBanner extends ConsumerWidget {
  const _PartialFailureBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(browserPathProvider);
    final listing = ref.watch(directoryListingProvider(path)).valueOrNull;
    final failures = listing?.failures ?? const <NodeFailure>[];
    if (failures.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: ExpansionTile(
        leading: Icon(
          Icons.warning_amber_outlined,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        title: Text(
          '${failures.length} item${failures.length == 1 ? '' : 's'} could not '
          'be read',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onTertiaryContainer,
          ),
        ),
        children: <Widget>[
          for (final failure in failures)
            ListTile(
              dense: true,
              title: Text(
                failure.path,
                style: theme.textTheme.bodySmall,
              ),
              subtitle: Text(
                failure.statusCode == null
                    ? failure.message
                    : '${failure.message} (HTTP ${failure.statusCode})',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// List or grid, per the saved preference.
class _NodeList extends ConsumerWidget {
  const _NodeList({
    required this.listing,
    required this.preferences,
    required this.onOpen,
  });

  final DirectoryListing listing;
  final BrowserPreferences preferences;
  final Future<void> Function(RemoteNode node) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sorted = applySort(listing.items, preferences);

    if (preferences.viewMode == BrowserViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          childAspectRatio: 0.82,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: sorted.length,
        itemBuilder: (BuildContext context, int index) => _GridTile(
          node: sorted[index],
          onOpen: onOpen,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sorted.length,
      itemBuilder: (BuildContext context, int index) => _ListTile(
        node: sorted[index],
        onOpen: onOpen,
      ),
    );
  }
}

/// Trailing actions shared by both layouts.
List<PopupMenuEntry<_NodeAction>> _nodeMenuItems() =>
    const <PopupMenuEntry<_NodeAction>>[
  PopupMenuItem<_NodeAction>(
    value: _NodeAction.download,
    child: ListTile(
      leading: Icon(Icons.download_outlined),
      title: Text('Download'),
      contentPadding: EdgeInsets.zero,
    ),
  ),
  PopupMenuItem<_NodeAction>(
    value: _NodeAction.rename,
    child: ListTile(
      leading: Icon(Icons.drive_file_rename_outline),
      title: Text('Rename'),
      contentPadding: EdgeInsets.zero,
    ),
  ),
  PopupMenuItem<_NodeAction>(
    value: _NodeAction.move,
    child: ListTile(
      leading: Icon(Icons.drive_file_move_outlined),
      title: Text('Move'),
      contentPadding: EdgeInsets.zero,
    ),
  ),
  PopupMenuItem<_NodeAction>(
    value: _NodeAction.copy,
    child: ListTile(
      leading: Icon(Icons.content_copy_outlined),
      title: Text('Copy'),
      contentPadding: EdgeInsets.zero,
    ),
  ),
  PopupMenuItem<_NodeAction>(
    value: _NodeAction.details,
    child: ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('Details'),
      contentPadding: EdgeInsets.zero,
    ),
  ),
  PopupMenuDivider(),
  PopupMenuItem<_NodeAction>(
    value: _NodeAction.delete,
    child: ListTile(
      leading: Icon(Icons.delete_outline),
      title: Text('Delete'),
      contentPadding: EdgeInsets.zero,
    ),
  ),
];

enum _NodeAction { download, rename, move, copy, details, delete }

/// Runs the action chosen from a node's menu.
Future<void> _handleNodeAction(
  BuildContext context,
  WidgetRef ref,
  RemoteNode node,
  _NodeAction action,
) async {
  switch (action) {
    case _NodeAction.download:
      await FileActions.download(context, ref, node);
    case _NodeAction.rename:
      await FileActions.rename(context, ref, node);
    case _NodeAction.move:
      await FileActions.move(context, ref, node);
    case _NodeAction.copy:
      await FileActions.copy(context, ref, node);
    case _NodeAction.details:
      await FileActions.showDetails(context, ref, node);
    case _NodeAction.delete:
      await FileActions.delete(context, ref, node);
  }
}

/// The same sheet, reachable by tapping a file.
Future<void> _showNodeSheet(
  BuildContext context,
  WidgetRef ref,
  RemoteNode node,
) async {
  final theme = Theme.of(context);
  final category = FileKinds.of(node.name, isDirectory: node.isDirectory);

  final action = await showModalBottomSheet<_NodeAction>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: Icon(
              FileKinds.iconFor(category),
              color: FileKinds.tintFor(category, theme.colorScheme),
            ),
            title: Text(node.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${ByteFormat.format(node.sizeBytes)} · '
              '${DateFormatting.relative(node.modifiedAt)}',
            ),
          ),
          const Divider(height: 1),
          for (final item in _nodeMenuItems())
            if (item is PopupMenuItem<_NodeAction>)
              ListTile(
                leading: (item.child as ListTile).leading,
                title: (item.child as ListTile).title,
                onTap: () =>
                    Navigator.of(sheetContext).pop(item.value),
              ),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;
  await _handleNodeAction(context, ref, node, action);
}

class _ListTile extends ConsumerWidget {
  const _ListTile({required this.node, required this.onOpen});

  final RemoteNode node;
  final Future<void> Function(RemoteNode node) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = node.isDirectory
        ? (node.modifiedAt == null
            ? 'Folder'
            : 'Folder · ${DateFormatting.relative(node.modifiedAt)}')
        : '${ByteFormat.format(node.sizeBytes)} · '
            '${DateFormatting.relative(node.modifiedAt)}';

    return ListTile(
      leading: _NodeIcon(node: node),
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: PopupMenuButton<_NodeAction>(
        tooltip: 'Actions for ${node.name}',
        onSelected: (_NodeAction action) =>
            _handleNodeAction(context, ref, node, action),
        itemBuilder: (BuildContext context) => _nodeMenuItems(),
      ),
      onTap: () => onOpen(node),
    );
  }
}

class _GridTile extends ConsumerWidget {
  const _GridTile({required this.node, required this.onOpen});

  final RemoteNode node;
  final Future<void> Function(RemoteNode node) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => onOpen(node),
        onLongPress: () => _handleNodeAction(
          context,
          ref,
          node,
          _NodeAction.details,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _NodeIcon(node: node, size: 40),
              const SizedBox(height: 12),
              Text(
                node.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                node.isDirectory ? 'Folder' : ByteFormat.format(node.sizeBytes),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Type icon, tinted by category.
class _NodeIcon extends StatelessWidget {
  const _NodeIcon({required this.node, this.size = 24});

  final RemoteNode node;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = FileKinds.of(node.name, isDirectory: node.isDirectory);
    return Icon(
      FileKinds.iconFor(category),
      size: size,
      color: FileKinds.tintFor(category, scheme),
    );
  }
}

/// Nothing here yet — and, when browsing offline, why that might mean nothing.
class _EmptyFolder extends ConsumerWidget {
  const _EmptyFolder({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repository = ref.watch(fileRepositoryProvider);
    final listing = ref.watch(directoryListingProvider(path)).valueOrNull;
    final isCached = listing?.fromCache ?? false;
    final isRoot = path == RemotePath.root;

    return ListView(
      // Scrollable so pull-to-refresh still works on an empty folder.
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        Icon(
          Icons.folder_open,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          'This folder is empty',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            isCached
                ? 'Showing what was saved locally. Pull down to check the '
                    'server — this folder has not been read since you were last '
                    'online.'
                : 'Upload a file, or create a folder to get started.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => FileActions.createFolder(context, ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('New folder'),
              ),
              if (!isRoot)
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(browserPathProvider.notifier).state =
                          RemotePath.parent(path) ?? RemotePath.root,
                  icon: const Icon(Icons.arrow_upward),
                  label: const Text('Go up'),
                ),
            ],
          ),
        ),
        if (repository != null && !repository.capabilities.canWrite) ...<Widget>[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'The active transport cannot write to this account, so uploads '
              'and new folders are unavailable.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The folder could not be read at all.
class _BrowserError extends StatelessWidget {
  const _BrowserError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = ErrorPresenter.describe(error);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        Icon(presentation.icon, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          presentation.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            presentation.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (presentation.canRetry)
          Center(
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ),
      ],
    );
  }
}
