/// Every operation the browser can perform on a node, and the dialogs that
/// collect what each one needs.
///
/// Kept out of the screen widget for one reason that matters: **every mutation
/// here reports its own outcome**. A rename that fails because the name is
/// taken, a delete refused for permissions, an upload blocked by quota — each
/// surfaces as a message the user can act on, next to the thing they asked for.
/// A silent failure in a storage app is indistinguishable from data loss.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/error/puter_exception.dart';
import '../../core/format/file_kinds.dart';
import '../../core/format/formatters.dart';
import '../../data/repositories/file_repository.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import 'browser_providers.dart';

/// Operations the browser offers on files and folders.
abstract final class FileActions {
  // ------------------------------------------------------------- create folder

  /// Ask for a name and create the folder.
  static Future<void> createFolder(BuildContext context, WidgetRef ref) async {
    final parent = ref.read(browserPathProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => const _NameDialog(
        title: 'New folder',
        label: 'Folder name',
        initialValue: 'Untitled folder',
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
    final name = await showDialog<String>(
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Delete “${node.name}”?'),
        content: Text(
          node.isDirectory
              ? 'The folder and everything inside it will be deleted from your '
                  'Puter account. This cannot be undone.'
              : 'This file will be deleted from your Puter account. This '
                  'cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
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
    final start = RemotePath.parent(node.path) ?? RemotePath.root;
    final destination = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _FolderPickerDialog(
        title: isCopy ? 'Copy “${node.name}” to' : 'Move “${node.name}” to',
        startPath: start,
        // Moving a folder into itself would be refused by the server or, worse,
        // executed destructively. Excluding the subtree from the picker makes
        // the mistake impossible rather than merely rejected.
        excludeSubtreeOf: isCopy || !node.isDirectory ? null : node.path,
      ),
    );
    if (destination == null || !context.mounted) return;

    final target = RemotePath.join(destination, node.name);
    if (target == node.path) return;

    await _run(
      context,
      ref,
      success: isCopy
          ? 'Copied to ${_displayPath(destination)}.'
          : 'Moved to ${_displayPath(destination)}.',
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
    final repository = ref.read(fileRepositoryProvider);
    RemoteNode shown = node;

    // A cached row can be days old. Refresh it first so the dialog does not
    // report a stale size as fact — and if that fails, say so in the dialog
    // rather than quietly showing old numbers.
    var isStale = false;
    if (repository != null) {
      try {
        shown = await repository.stat(node.path);
      } on PuterException {
        isStale = true;
      }
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _DetailsDialog(node: shown, isStale: isStale),
    );
  }

  // -------------------------------------------------------------------- upload

  /// Pick files from the device and queue them for upload.
  static Future<void> upload(
    BuildContext context,
    WidgetRef ref, {
    String? intoPath,
  }) async {
    final files = ref.read(deviceFilesProvider);
    final String target = intoPath ?? ref.read(browserPathProvider);

    final picked = await files.pickFiles();
    if (picked.isEmpty || !context.mounted) return;

    final engine = ref.read(transferEngineProvider);
    if (engine == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    for (final file in picked) {
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
        onPressed: () => _goToTransfers(ref),
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
    final engine = ref.read(transferEngineProvider);
    if (engine == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    final directory = await ref.read(deviceFilesProvider).downloadDirectory();
    if (!context.mounted) return;

    final localPath = p.join(directory.path, node.name);
    await engine.enqueueDownload(
      remotePath: node.path,
      localPath: localPath,
      sizeBytes: node.sizeBytes,
    );

    if (!context.mounted) return;
    _snack(
      context,
      'Downloading “${node.name}”.',
      action: SnackBarAction(
        label: 'View',
        onPressed: () => _goToTransfers(ref),
      ),
    );
  }

  // ------------------------------------------------------------------ plumbing

  /// Run one repository mutation, reporting success or failure.
  static Future<void> _run(
    BuildContext context,
    WidgetRef ref, {
    required String success,
    required Future<void> Function(FileRepository repository) action,
  }) async {
    final repository = ref.read(fileRepositoryProvider);
    if (repository == null) {
      _report(context, 'Not connected to Puter.');
      return;
    }

    try {
      await action(repository);
      if (context.mounted) _snack(context, success);
    } on PuterException catch (error) {
      if (!context.mounted) return;
      final presentation = ErrorPresenter.describe(error);
      _snack(
        context,
        '${presentation.title}. ${presentation.message}',
        isError: true,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      _snack(context, 'Something went wrong: $error', isError: true);
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          backgroundColor:
              isError ? Theme.of(context).colorScheme.errorContainer : null,
          duration: Duration(seconds: isError ? 6 : 3),
        ),
      );
  }

  static void _goToTransfers(WidgetRef ref) =>
      ref.read(homeTabProvider.notifier).state = HomeTab.transfers;

  static String _displayPath(String path) =>
      path == RemotePath.root ? 'Home' : RemotePath.name(path);
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
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
          ),
          validator: (String? value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return 'A name is required.';
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
    final listing = ref.watch(directoryListingProvider(_path));

    final excluded = widget.excludeSubtreeOf;
    final cannotConfirm =
        excluded != null && RemotePath.isWithin(excluded, _path);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.folder_open,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _path == RemotePath.root ? 'Home' : _path,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: listing.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      ErrorPresenter.describe(error).message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                data: (DirectoryListing value) {
                  final folders = value.items
                      .where((RemoteNode node) => node.isDirectory)
                      .toList(growable: false);

                  if (folders.isEmpty) {
                    return Center(
                      child: Text(
                        'No folders here.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: folders.length,
                    itemBuilder: (BuildContext context, int index) {
                      final folder = folders[index];
                      final isExcluded = excluded != null &&
                          RemotePath.isWithin(excluded, folder.path);
                      return ListTile(
                        leading: Icon(
                          Icons.folder_outlined,
                          color: isExcluded
                              ? theme.disabledColor
                              : theme.colorScheme.primary,
                        ),
                        title: Text(folder.name),
                        enabled: !isExcluded,
                        subtitle: isExcluded ? const Text('Cannot move here') : null,
                        onTap: () => setState(() => _path = folder.path),
                      );
                    },
                  );
                },
              ),
            ),
            if (_path != RemotePath.root)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _path = RemotePath.parent(_path) ?? RemotePath.root,
                    ),
                    icon: const Icon(Icons.arrow_upward, size: 18),
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
          onPressed: cannotConfirm
              ? null
              : () => Navigator.of(context).pop(_path),
          child: Text(cannotConfirm ? 'Cannot use this folder' : 'Choose'),
        ),
      ],
    );
  }
}

/// Everything known about one node.
class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({required this.node, required this.isStale});

  final RemoteNode node;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = FileKinds.of(node.name, isDirectory: node.isDirectory);

    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(
            FileKinds.iconFor(category),
            color: FileKinds.tintFor(category, theme.colorScheme),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(node.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isStale)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.cloud_off,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing cached details — the server could not be reached.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _Row(label: 'Path', value: node.path),
          if (!node.isDirectory)
            _Row(label: 'Size', value: ByteFormat.format(node.sizeBytes)),
          _Row(
            label: 'Modified',
            value: DateFormatting.absolute(node.modifiedAt),
          ),
          if (node.mimeType != null)
            _Row(label: 'Type', value: node.mimeType!),
          if (node.isShared != null)
            _Row(
              label: 'Sharing',
              value: node.isShared! ? 'Shared by you' : 'Not shared',
            ),
          if (node.indexedAt != null)
            _Row(
              label: 'Last checked',
              value: DateFormatting.relative(node.indexedAt),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
