/// Every operation the browser performs on a node, and the sheets that collect
/// what each one needs.
///
/// Kept out of the screen widget for one reason that matters: **every mutation
/// reports its own outcome**. A rename that fails because the name is taken, a
/// delete refused for permissions, an upload blocked because the account is
/// full — each surfaces as a message the user can act on. A silent failure in a
/// storage app is indistinguishable from data loss.
///
/// Two structural rules, both fixing things the previous version got wrong:
///
/// * **Destructive actions are separated.** Delete used to sit directly beneath
///   Download and Details in a list of equally weighted rows, one stray tap
///   from irreversibly removing a folder.
/// * **Primary actions are labelled.** Every row says what it does, rather than
///   putting the verb in a menu the user has to open to read.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/error/puter_exception.dart';
import '../../core/format/file_kinds.dart';
import '../../core/format/formatters.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/platform/device_files.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/transfer/transfer_engine.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import 'browser_providers.dart';

/// Operations the browser offers on files and folders.
abstract final class FileActions {
  // --------------------------------------------------------------- the sheet

  /// Everything that can be done with [node], in one sheet.
  ///
  /// Ordering is deliberate: the thing you most often want first, metadata
  /// next, destructive last and behind a divider. A folder's primary action is
  /// to open it — tapping the row already does that, so the sheet leads with
  /// the operations that a row tap cannot express.
  static Future<void> showActions(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final FileRepository? repository = ref.read(fileRepositoryProvider);
    if (repository == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    final FileCategory category =
        FileKinds.of(node.name, isDirectory: node.isDirectory);
    final bool canWrite = repository.capabilities.canWrite;

    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => AppSheet(
        title: node.name,
        subtitle: node.isDirectory
            ? 'Folder · ${DateFormatting.relative(node.modifiedAt)}'
            : '${ByteFormat.format(node.sizeBytes)} · '
                '${DateFormatting.relative(node.modifiedAt)}',
        leading: Icon(
          FileKinds.iconFor(category),
          size: 30,
          color: FileKinds.tintFor(
            category,
            Theme.of(sheetContext).colorScheme,
          ),
        ),
        children: <Widget>[
          if (!node.isDirectory)
            AppListRow(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Download to this phone'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                download(context, ref, node);
              },
            ),
          if (canWrite)
            AppListRow(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                rename(context, ref, node);
              },
            ),
          if (canWrite)
            AppListRow(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to another folder'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                move(context, ref, node);
              },
            ),
          if (canWrite)
            AppListRow(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Make a copy'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                copy(context, ref, node);
              },
            ),
          AppListRow(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Details'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showDetails(context, ref, node);
            },
          ),
          if (canWrite) ...<Widget>[
            // Separated, and coloured. Everything above is reversible; this is
            // not, so it does not sit in the same visual group as the rest.
            const AppDivider(),
            AppListRow(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              subtitle: const Text('This cannot be undone'),
              isDestructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                delete(context, ref, node);
              },
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- create folder

  static Future<void> createFolder(BuildContext context, WidgetRef ref) async {
    final String parent = ref.read(browserPathProvider);
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _NameDialog(
        title: 'New folder',
        label: 'Folder name',
        initialValue: 'New folder',
        confirmLabel: 'Create',
      ),
    );
    if (name == null || !context.mounted) return;

    await _run(
      context,
      ref,
      success: 'Created “$name”.',
      action: (FileRepository repository) =>
          repository.createDirectory(RemotePath.join(parent, name)),
    );
  }

  // -------------------------------------------------------------------- rename

  static Future<void> rename(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _NameDialog(
        title: 'Rename',
        label: 'New name',
        initialValue: node.name,
        confirmLabel: 'Rename',
      ),
    );
    if (name == null || name == node.name || !context.mounted) return;

    await _run(
      context,
      ref,
      success: 'Renamed to “$name”.',
      action: (FileRepository repository) => repository.rename(node, name),
    );
  }

  // -------------------------------------------------------------------- delete

  static Future<void> delete(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: Icon(
          Icons.delete_outline_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text('Delete “${node.name}”?'),
        content: Text(
          node.isDirectory
              ? 'The folder and everything inside it will be permanently '
                  'removed from your Puter account.'
              : 'This file will be permanently removed from your Puter '
                  'account.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await _run(
      context,
      ref,
      success: 'Deleted “${node.name}”.',
      action: (FileRepository repository) => repository.delete(node),
    );
  }

  // --------------------------------------------------------------- move / copy

  static Future<void> move(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) =>
      _relocate(context, ref, node, isCopy: false);

  static Future<void> copy(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) =>
      _relocate(context, ref, node, isCopy: true);

  static Future<void> _relocate(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node, {
    required bool isCopy,
  }) async {
    final String start = RemotePath.parent(node.path) ?? RemotePath.root;
    final String? destination = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _FolderPickerDialog(
        title: isCopy ? 'Copy “${node.name}” into…' : 'Move “${node.name}” into…',
        startPath: start,
        // Moving a folder inside itself would be refused by the server or,
        // worse, executed destructively. Excluding the subtree from the picker
        // makes the mistake impossible rather than merely rejected.
        excludeSubtreeOf: isCopy || !node.isDirectory ? null : node.path,
      ),
    );
    if (destination == null || !context.mounted) return;

    final String target = RemotePath.join(destination, node.name);
    if (target == node.path) return;

    await _run(
      context,
      ref,
      success: isCopy
          ? 'Copied into ${_displayPath(destination)}.'
          : 'Moved into ${_displayPath(destination)}.',
      action: (FileRepository repository) => isCopy
          ? repository.copy(node, target)
          : repository.move(node, target),
    );
  }

  // ------------------------------------------------------------------- details

  static Future<void> showDetails(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final FileRepository? repository = ref.read(fileRepositoryProvider);
    RemoteNode shown = node;

    // A cached row can be days old. Refresh before reporting, and if that
    // fails say so in the dialog rather than presenting stale numbers as fact.
    bool isStale = false;
    if (repository != null) {
      try {
        shown = await repository.stat(node.path);
      } on PuterException {
        isStale = true;
      }
    }
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) =>
          _DetailsSheet(node: shown, isStale: isStale),
    );
  }

  // -------------------------------------------------------------------- upload

  /// Pick files from the device and queue them for upload.
  static Future<void> upload(
    BuildContext context,
    WidgetRef ref, {
    String? intoPath,
  }) async {
    final String target = intoPath ?? ref.read(browserPathProvider);
    final TransferEngine? engine = ref.read(transferEngineProvider);
    if (engine == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    final List<PickedFile> picked =
        await ref.read(deviceFilesProvider).pickFiles();
    if (picked.isEmpty || !context.mounted) return;

    for (final PickedFile file in picked) {
      await engine.enqueueUpload(
        localPath: file.path,
        remotePath: RemotePath.join(target, file.name),
        sizeBytes: file.sizeBytes,
      );
    }

    if (!context.mounted) return;
    _snack(
      context,
      picked.length == 1
          ? 'Uploading “${picked.first.name}”.'
          : 'Uploading ${picked.length} files.',
      action: SnackBarAction(
        label: 'View',
        onPressed: () =>
            ref.read(homeTabProvider.notifier).state = HomeTab.transfers,
      ),
    );
  }

  // ------------------------------------------------------------------ download

  /// Queue [node] for download into the app's downloads folder.
  static Future<void> download(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final TransferEngine? engine = ref.read(transferEngineProvider);
    if (engine == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    final Directory directory =
        await ref.read(deviceFilesProvider).downloadDirectory();
    if (!context.mounted) return;

    await engine.enqueueDownload(
      remotePath: node.path,
      localPath: p.join(directory.path, node.name),
      sizeBytes: node.sizeBytes,
    );

    if (!context.mounted) return;
    _snack(
      context,
      'Downloading “${node.name}”.',
      action: SnackBarAction(
        label: 'View',
        onPressed: () =>
            ref.read(homeTabProvider.notifier).state = HomeTab.transfers,
      ),
    );
  }

  // ------------------------------------------------------------------ plumbing

  static Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required String success,
    required Future<void> Function(FileRepository repository) action,
  }) async {
    final FileRepository? repository = ref.read(fileRepositoryProvider);
    if (repository == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    try {
      await action(repository);
      if (context.mounted) _snack(context, success);
    } on PuterException catch (error) {
      if (!context.mounted) return;
      final ErrorPresentation presentation = ErrorPresenter.describe(error);
      _snack(
        context,
        '${presentation.title}. ${presentation.message}',
        isError: true,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      _snack(context, 'That did not work. $error', isError: true);
    }
  }

  static void _report(BuildContext context, String message) =>
      _snack(context, message, isError: true);

  static void _snack(
    BuildContext context,
    String message, {
    bool isError = false,
    SnackBarAction? action,
  }) {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          backgroundColor: isError
              ? Theme.of(context).colorScheme.errorContainer
              : null,
          duration: Duration(seconds: isError ? 6 : 3),
        ),
      );
  }

  static String _displayPath(String path) =>
      path == RemotePath.root ? 'your top-level folder' : RemotePath.name(path);
}

/// A single-line text prompt, used for creating and renaming.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Select the whole name so a rename starts by replacing rather than
    // appending — the common case by a wide margin.
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(labelText: widget.label),
          validator: (String? value) {
            final String text = value?.trim() ?? '';
            if (text.isEmpty) return 'Give it a name.';
            if (text.contains('/')) return 'A name cannot contain “/”.';
            if (text == '.' || text == '..') return 'That name is reserved.';
            return null;
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Browse the remote tree and pick a folder.
class _FolderPickerDialog extends ConsumerStatefulWidget {
  const _FolderPickerDialog({
    required this.title,
    required this.startPath,
    this.excludeSubtreeOf,
  });

  final String title;
  final String startPath;

  /// A subtree the user must not be able to select.
  final String? excludeSubtreeOf;

  @override
  ConsumerState<_FolderPickerDialog> createState() =>
      _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<_FolderPickerDialog> {
  late String _path = widget.startPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AsyncValue<DirectoryListing> listing =
        ref.watch(directoryListingProvider(_path));

    final String? excluded = widget.excludeSubtreeOf;
    final bool cannotConfirm =
        excluded != null && RemotePath.isWithin(excluded, _path);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        // Sized against the viewport rather than a fixed 400dp, which is what
        // used to overflow on a short screen or with the keyboard open.
        height: MediaQuery.sizeOf(context).height * 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _path == RemotePath.root ? 'Puter' : _path,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: listing.when(
                loading: () => const LoadingState(),
                error: (Object error, StackTrace _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      ErrorPresenter.describe(error).message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                data: (DirectoryListing value) {
                  final List<RemoteNode> folders = value.items
                      .where((RemoteNode node) => node.isDirectory)
                      .toList(growable: false);

                  if (folders.isEmpty) {
                    return Center(
                      child: Text(
                        'No folders inside this one.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: folders.length,
                    itemBuilder: (BuildContext context, int index) {
                      final RemoteNode folder = folders[index];
                      final bool isExcluded = excluded != null &&
                          RemotePath.isWithin(excluded, folder.path);
                      return AppListRow(
                        dense: true,
                        leading: Icon(
                          isExcluded
                              ? Icons.block_rounded
                              : Icons.folder_outlined,
                        ),
                        title: Text(folder.name),
                        subtitle: isExcluded ? const Text('Cannot move here') : null,
                        onTap: isExcluded
                            ? null
                            : () => setState(() => _path = folder.path),
                      );
                    },
                  );
                },
              ),
            ),
            if (_path != RemotePath.root)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () =>
                          _path = RemotePath.parent(_path) ?? RemotePath.root,
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    label: const Text('Up one level'),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              cannotConfirm ? null : () => Navigator.of(context).pop(_path),
          child: Text(cannotConfirm ? 'Cannot use this folder' : 'Move here'),
        ),
      ],
    );
  }
}

/// Everything known about one node, in plain language.
class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({required this.node, required this.isStale});

  final RemoteNode node;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final FileCategory category =
        FileKinds.of(node.name, isDirectory: node.isDirectory);

    return AppSheet(
      title: node.name,
      subtitle: FileKinds.describeCategory(
        node.name,
        isDirectory: node.isDirectory,
      ),
      leading: Icon(
        FileKinds.iconFor(category),
        size: 30,
        color: FileKinds.tintFor(category, theme.colorScheme),
      ),
      children: <Widget>[
        if (isStale)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: InlineBanner(
              tone: BannerTone.info,
              icon: Icons.cloud_off_rounded,
              message: 'Showing saved details — Puter could not be reached to '
                  'confirm them.',
            ),
          ),
        _DetailRow(
          label: 'Location',
          value: RemotePath.parent(node.path) ?? RemotePath.root,
          copyable: true,
        ),
        if (!node.isDirectory)
          _DetailRow(
            label: 'Size',
            value: ByteFormat.format(node.sizeBytes),
          ),
        _DetailRow(
          label: 'Type',
          value: FileKinds.describeCategory(
            node.name,
            isDirectory: node.isDirectory,
          ),
        ),
        _DetailRow(
          label: 'Last changed',
          value: DateFormatting.absolute(node.modifiedAt),
        ),
        if (node.isShared != null)
          _DetailRow(
            label: 'Sharing',
            value: node.isShared! ? 'Shared by you' : 'Private',
          ),
        if (node.indexedAt != null)
          _DetailRow(
            label: 'Saved on this phone',
            value: DateFormatting.relative(node.indexedAt),
          ),
      ],
    );
  }
}

/// One labelled fact, selectable so it can be copied.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (copyable) ...<Widget>[
          Icon(
            Icons.copy_rounded,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ] else
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: copyable
                ? content
                : Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: content,
                  ),
          ),
        ],
      ),
    );
  }
}
