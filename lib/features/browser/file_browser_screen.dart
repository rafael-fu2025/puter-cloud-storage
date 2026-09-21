/// The file browser.
///
/// Four things about this screen are load-bearing rather than decorative.
///
/// **The header is one bar, not four.** The previous version stacked an app bar,
/// a storage meter, a breadcrumb strip and a failure banner above the file list
/// — up to 200dp of chrome before a single filename. The path now lives in the
/// app bar's subtitle, where it is still readable and can be tapped to jump
/// anywhere above; the storage meter appears only when it has something to say.
///
/// **Partial listings are shown as partial.** A WebDAV `207 Multistatus` can
/// carry per-entry failures while the response as a whole succeeds, so a folder
/// can be genuinely incomplete. Entries the server refused are reported — in
/// plain language, without status codes — because dropping them silently makes
/// files invisible with no explanation.
///
/// **Empty is not the same as broken.** An empty folder, a folder that has never
/// been opened offline, and a folder that failed to load are three different
/// states with three different messages and three different actions.
///
/// **Long-press opens the actions.** Tapping a file used to open a sheet, which
/// made a plain tap feel like a commitment; now a tap on a file also opens the
/// sheet but a long-press does too, matching what people expect from a file
/// manager on either platform.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/format/file_kinds.dart';
import '../../core/format/formatters.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import 'browser_providers.dart';
import 'file_actions.dart';
import 'sort_sheet.dart';

class FileBrowserScreen extends ConsumerWidget {
  const FileBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String path = ref.watch(browserPathProvider);
    final AsyncValue<DirectoryListing> listing =
        ref.watch(directoryListingProvider(path));
    final BrowserPreferences preferences =
        ref.watch(browserPreferencesProvider).valueOrNull ??
            const BrowserPreferences();

    return Scaffold(
      appBar: _FolderAppBar(path: path),
      floatingActionButton: FloatingActionButton.extended(
        // A tooltip on a FAB is what a screen reader announces; without it the
        // button is just "button".
        tooltip: 'Upload files to this folder',
        onPressed: () => FileActions.upload(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Upload'),
      ),
      body: Column(
        children: <Widget>[
          const _Notices(),
          Expanded(
            child: listing.when(
              loading: () => const LoadingState(),
              error: (Object error, StackTrace _) => _BrowserError(
                error: error,
                onRetry: () =>
                    ref.read(directoryListingProvider(path).notifier).refresh(),
              ),
              data: (DirectoryListing value) => RefreshIndicator(
                onRefresh: () =>
                    ref.read(directoryListingProvider(path).notifier).refresh(),
                child: value.items.isEmpty
                    ? _EmptyFolder(path: path, listing: value)
                    : _NodeList(
                        listing: value,
                        preferences: preferences,
                        onOpen: (RemoteNode node) => _open(context, ref, node),
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
    await FileActions.showActions(context, ref, node);
  }
}

/// Folder name, path, and the actions that apply to the folder itself.
class _FolderAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _FolderAppBar({required this.path});

  final String path;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 22);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bool isRoot = path == RemotePath.root;
    final String title = isRoot ? 'Files' : RemotePath.name(path);

    return AppBar(
      // Two-line title: the name is what the eye needs, the path is what it
      // needs when it is lost. Showing both costs 22dp and removes the need for
      // a permanent breadcrumb bar.
      toolbarHeight: kToolbarHeight + 22,
      leading: isRoot
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Up one level',
              onPressed: () =>
                  ref.read(browserPathProvider.notifier).state =
                      RemotePath.parent(path) ?? RemotePath.root,
            ),
      titleSpacing: isRoot ? AppSpacing.gutter : 0,
      title: InkWell(
        onTap: () => _showPathSheet(context, ref, path),
        borderRadius: AppRadius.action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                isRoot ? 'Puter' : _readablePath(path),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort',
          onPressed: () => showSortSheet(
            context,
            ref,
            ref.read(browserPreferencesProvider).valueOrNull ??
                const BrowserPreferences(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: 'New folder',
          onPressed: () => FileActions.createFolder(context, ref),
        ),
      ],
    );
  }

  /// `/Photos/2026` → `Photos  ›  2026`.
  static String _readablePath(String path) =>
      RemotePath.segments(path).join('  ›  ');
}

/// Jump to any folder above the current one.
///
/// Replaces the horizontally-scrolling breadcrumb strip, which read
/// right-to-left (`reverse: true`) and only ever showed a window of a long
/// path. A sheet lists the whole trail at once, which is what someone who is
/// lost actually wants.
Future<void> _showPathSheet(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final List<({String label, String path})> crumbs =
      RemotePath.breadcrumbs(path);

  await showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => AppSheet(
      title: 'Go to folder',
      subtitle: path == RemotePath.root ? 'Puter' : path,
      children: <Widget>[
        for (final ({String label, String path}) crumb
            in crumbs.reversed.toList(growable: false))
          AppListRow(
            title: Text(crumb.label),
            subtitle: Text(
              crumb.path == RemotePath.root ? 'Top level' : crumb.path,
            ),
            leading: Icon(
              crumb.path == path
                  ? Icons.folder_rounded
                  : Icons.folder_outlined,
            ),
            trailing: crumb.path == path
                ? Icon(
                    Icons.check_rounded,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  )
                : null,
            onTap: () {
              Navigator.of(sheetContext).pop();
              ref.read(browserPathProvider.notifier).state = crumb.path;
            },
          ),
      ],
    ),
  );
}

/// Conditions worth mentioning, in one place, only when true.
///
/// The storage meter used to occupy a permanent bar. Here it appears only when
/// the account is nearly full — the moment it becomes actionable — and the
/// partial-listing notice only when the server actually withheld something.
class _Notices extends ConsumerWidget {
  const _Notices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String path = ref.watch(browserPathProvider);
    final DirectoryListing? listing =
        ref.watch(directoryListingProvider(path)).valueOrNull;
    final StorageUsage? usage = ref.watch(storageUsageProvider).valueOrNull;
    final double threshold = ref.watch(appConfigProvider).quotaWarningThreshold;

    final bool isNearlyFull = usage != null && usage.isNearLimit(threshold);
    final List<NodeFailure> failures =
        listing?.failures ?? const <NodeFailure>[];

    return Column(
      children: <Widget>[
        if (isNearlyFull)
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.sd_card_alert_outlined,
            title: 'Almost out of storage space',
            message: '${ByteFormat.format(usage.freeBytes)} left of '
                '${ByteFormat.format(usage.capacityBytes)}. Uploads will be '
                'refused once it is full — free space in the Puter app to keep '
                'going.',
          ),
        if (failures.isNotEmpty)
          InlineBanner(
            tone: BannerTone.info,
            icon: Icons.warning_amber_rounded,
            title: failures.length == 1
                ? 'One item could not be shown'
                : '${failures.length} items could not be shown',
            message: 'This folder may be incomplete. Pull down to try again.',
            action: TextButton(
              onPressed: () =>
                  ref.read(directoryListingProvider(path).notifier).refresh(),
              child: const Text('Try again'),
            ),
          ),
      ],
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
    final List<RemoteNode> sorted = applySort(listing.items, preferences);

    if (preferences.viewMode == BrowserViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          104,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          childAspectRatio: 0.86,
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
        ),
        itemCount: sorted.length,
        itemBuilder: (BuildContext context, int index) =>
            _GridTile(node: sorted[index], onOpen: onOpen),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 104),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: sorted.length,
      separatorBuilder: (BuildContext context, int index) => const AppDivider(),
      itemBuilder: (BuildContext context, int index) =>
          _FileRow(node: sorted[index], onOpen: onOpen),
    );
  }
}

/// One file or folder in the list.
class _FileRow extends ConsumerWidget {
  const _FileRow({required this.node, required this.onOpen});

  final RemoteNode node;
  final Future<void> Function(RemoteNode node) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String modified = node.modifiedAt == null
        ? ''
        : ' · ${DateFormatting.relative(node.modifiedAt)}';
    final String meta = node.isDirectory
        ? 'Folder$modified'
        : '${ByteFormat.format(node.sizeBytes)}$modified';

    return AppListRow(
      leading: FileKindIcon(node: node, size: 26),
      title: Text(node.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(meta),
      trailing: node.isDirectory
          ? const Icon(Icons.chevron_right_rounded)
          : null,
      onTap: () => onOpen(node),
      onLongPress: () => FileActions.showActions(context, ref, node),
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

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(node),
        onLongPress: () => FileActions.showActions(context, ref, node),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FileKindIcon(node: node, size: 38),
              const SizedBox(height: AppSpacing.md),
              Text(
                node.name,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
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

/// The type icon for a node, tinted by category.
class FileKindIcon extends StatelessWidget {
  const FileKindIcon({super.key, required this.node, this.size = 24});

  final RemoteNode node;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final FileCategory category =
        FileKinds.of(node.name, isDirectory: node.isDirectory);
    return Icon(
      FileKinds.iconFor(category),
      size: size,
      color: FileKinds.tintFor(category, scheme),
    );
  }
}

/// Nothing here yet — and, when browsing offline, why that might mean nothing.
class _EmptyFolder extends ConsumerWidget {
  const _EmptyFolder({required this.path, required this.listing});

  final String path;
  final DirectoryListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isRoot = path == RemotePath.root;
    final bool isOfflineCopy = listing.fromCache;

    return AppEmptyState(
      icon:
          isOfflineCopy ? Icons.cloud_off_rounded : Icons.folder_open_rounded,
      title: isOfflineCopy
          ? 'Nothing saved from this folder'
          : 'This folder is empty',
      message: isOfflineCopy
          ? 'This folder has not been opened on this device yet, so there is '
              'nothing to show offline. Pull down to load it.'
          : 'Add a file from your phone, or make a folder to organise things.',
      primaryAction: FilledButton.icon(
        onPressed: () => FileActions.upload(context, ref, intoPath: path),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Upload a file'),
      ),
      secondaryActions: <Widget>[
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
            icon: const Icon(Icons.arrow_upward_rounded),
            label: const Text('Go up'),
          ),
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
    final ErrorPresentation presentation = ErrorPresenter.describe(error);
    return AppErrorView(
      icon: presentation.icon,
      title: presentation.title,
      message: presentation.message,
      onRetry: presentation.canRetry ? onRetry : null,
    );
  }
}
