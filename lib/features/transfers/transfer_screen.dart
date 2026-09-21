/// The transfer queue.
///
/// Grouped by what the user can do about each task, not by chronology:
///
/// * **In progress** — moving, or waiting its turn.
/// * **Needs you** — stopped, and only the user can restart it. A full account
///   is in here, not in "failed", because no amount of retrying frees space.
/// * **Finished** — done, or cancelled.
///
/// The grouping is the point. A single chronological list makes a blocked
/// upload look like a slow one, and the user waits for something that will
/// never move.
///
/// Two wording choices matter more than they look. **"Transferring", not
/// "moving"** — in a file manager "move" already means relocating a file to
/// another folder, and reusing it for uploads makes the queue read as though
/// files are being reorganised. And **"Pause", not "Stop"** — the button always
/// did pause, and calling it Stop made the app look like it had lost work.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format/formatters.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/transfer/transfer_engine.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';

class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TransferTask> transfers =
        ref.watch(transfersProvider).valueOrNull ?? const <TransferTask>[];
    final TransferEngine? engine = ref.watch(transferEngineProvider);

    final List<TransferTask> inProgress = transfers
        .where((TransferTask t) =>
            t.state == TransferState.running ||
            t.state == TransferState.queued ||
            t.state == TransferState.paused)
        .toList(growable: false);
    final List<TransferTask> needsYou = transfers
        .where((TransferTask t) =>
            t.state == TransferState.failed ||
            t.state == TransferState.blocked)
        .toList(growable: false);
    final List<TransferTask> finished = transfers
        .where((TransferTask t) =>
            t.state == TransferState.completed ||
            t.state == TransferState.cancelled)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: <Widget>[
          if (finished.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.playlist_remove_rounded),
              tooltip: 'Clear finished',
              onPressed: engine == null
                  ? null
                  : () => _confirmClear(context, engine),
            ),
        ],
      ),
      body: transfers.isEmpty
          ? const _NoTransfers()
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: <Widget>[
                if (inProgress.isNotEmpty)
                  _AggregateSummary(active: inProgress, engine: engine),
                if (inProgress.isNotEmpty)
                  _Section(title: 'In progress', tasks: inProgress, engine: engine),
                if (needsYou.isNotEmpty)
                  _Section(
                    title: 'Needs you',
                    subtitle: 'These are stopped until you do something.',
                    tasks: needsYou,
                    engine: engine,
                  ),
                if (finished.isNotEmpty)
                  _Section(title: 'Finished', tasks: finished, engine: engine),
              ],
            ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    TransferEngine engine,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear finished transfers?'),
        content: const Text(
          'Completed and cancelled entries will be removed from this list. '
          'Files already uploaded or downloaded are not affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await engine.clearFinished();
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.tasks,
    required this.engine,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<TransferTask> tasks;
  final TransferEngine? engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xl,
            AppSpacing.gutter,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$title · ${tasks.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        for (final TransferTask task in tasks)
          TransferTile(task: task, engine: engine),
      ],
    );
  }
}

/// Overall progress, and the control that applies to all of it.
///
/// Visually distinct from the rows below — the previous version styled this as
/// just another card, so the queue-level control read as one more task.
class _AggregateSummary extends ConsumerWidget {
  const _AggregateSummary({required this.active, required this.engine});

  final List<TransferTask> active;
  final TransferEngine? engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final int totalBytes = active.fold<int>(
      0,
      (int sum, TransferTask task) => sum + task.totalBytes,
    );
    final int doneBytes = active.fold<int>(
      0,
      (int sum, TransferTask task) => sum + task.bytesDone,
    );
    final double fraction =
        totalBytes <= 0 ? 0 : (doneBytes / totalBytes).clamp(0.0, 1.0);
    final Iterable<TransferTask> running =
        active.where((TransferTask task) => task.state == TransferState.running);
    final bool isPaused = running.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isPaused ? Icons.pause_circle_outline_rounded : Icons.sync_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    isPaused
                        ? 'Waiting to start'
                        : 'Transferring ${running.length} of ${active.length}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${(fraction * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(
              value: fraction,
              semanticsLabel: 'Overall upload and download progress',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${ByteFormat.format(doneBytes)} of '
              '${ByteFormat.format(totalBytes)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: engine == null
                    ? null
                    : () {
                        for (final TransferTask task in active) {
                          if (task.state == TransferState.running) {
                            engine!.pause(task.id);
                          } else if (task.state == TransferState.paused) {
                            engine!.resume(task.id);
                          } else if (task.state == TransferState.queued) {
                            engine!.cancel(task.id);
                          }
                        }
                      },
                icon: Icon(
                  isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
                label: Text(isPaused ? 'Resume all' : 'Pause all'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One transfer.
class TransferTile extends ConsumerStatefulWidget {
  const TransferTile({super.key, required this.task, required this.engine});

  final TransferTask task;
  final TransferEngine? engine;

  @override
  ConsumerState<TransferTile> createState() => _TransferTileState();
}

class _TransferTileState extends ConsumerState<TransferTile> {
  /// Sampled locally rather than stored on the task.
  ///
  /// A rate is a presentation concern with a short lifetime; putting it in the
  /// domain entity would mean a database column that is meaningless the moment
  /// the app restarts.
  int? _lastBytes;
  DateTime? _lastSampleAt;
  double? _rate;

  @override
  void didUpdateWidget(TransferTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.task.state != TransferState.running) {
      if (widget.task.state != oldWidget.task.state) {
        _lastBytes = null;
        _lastSampleAt = null;
        _rate = null;
      }
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? previousAt = _lastSampleAt;
    final int? previousBytes = _lastBytes;

    if (previousAt == null || previousBytes == null) {
      _lastSampleAt = now;
      _lastBytes = widget.task.bytesDone;
      return;
    }

    final Duration elapsed = now.difference(previousAt);
    if (elapsed.inMilliseconds < 400) return;

    final int delta = widget.task.bytesDone - previousBytes;
    if (delta < 0) return;

    final double instant = delta / (elapsed.inMilliseconds / 1000);
    _rate = _rate == null ? instant : (_rate! * 0.6) + (instant * 0.4);
    _lastSampleAt = now;
    _lastBytes = widget.task.bytesDone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final TransferTask task = widget.task;
    final bool isUpload = task.direction == TransferDirection.upload;
    final String name = RemotePath.name(task.remotePath);

    // The one thing a blocked upload usually needs: permission to replace.
    final bool isNameCollision =
        task.state == TransferState.blocked && _looksLikeCollision(task);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isUpload
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 20,
                  color: _stateColour(task.state, theme.colorScheme),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                _StateChip(state: task.state),
              ],
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(
                isUpload
                    ? 'Uploading to ${_folderLabel(task.remotePath)}'
                    : 'Saving to this phone',
                style: theme.textTheme.bodySmall,
              ),
            ),

            if (task.state == TransferState.running) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              LinearProgressIndicator(
                value: task.totalBytes <= 0 ? null : task.progress,
                semanticsLabel: isUpload
                    ? 'Uploading $name'
                    : 'Downloading $name',
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: <Widget>[
                    Text(
                      task.totalBytes <= 0
                          ? ByteFormat.format(task.bytesDone)
                          : '${ByteFormat.format(task.bytesDone)} of '
                              '${ByteFormat.format(task.totalBytes)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (_rate != null)
                      Text(
                        ByteFormat.rate(_rate!.round()),
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],

            if (task.lastError != null &&
                task.state != TransferState.running) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: isNameCollision
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        task.lastError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isNameCollision
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (task.state == TransferState.completed) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      task.totalBytes > 0
                          ? '${ByteFormat.format(task.totalBytes)} transferred'
                          : 'Finished',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],

            // The primary action for this row, out where it can be seen.
            // The previous version buried Pause and Cancel in a three-dot menu,
            // which is where actions go when the designer has run out of room.
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _actions(context, task, isNameCollision),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    TransferTask task,
    bool isNameCollision,
  ) {
    final TransferEngine? engine = widget.engine;
    final List<Widget> actions = <Widget>[];

    if (isNameCollision) {
      actions.add(
        FilledButton.icon(
          onPressed: engine == null ? null : () => engine.replaceExisting(task.id),
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: const Text('Replace the existing file'),
        ),
      );
    }

    switch (task.state) {
      case TransferState.running:
        actions.add(
          OutlinedButton(
            onPressed: engine == null ? null : () => engine.pause(task.id),
            child: const Text('Pause'),
          ),
        );
      case TransferState.paused:
        actions.add(
          FilledButton(
            onPressed: engine == null ? null : () => engine.resume(task.id),
            child: const Text('Resume'),
          ),
        );
      case TransferState.queued:
        actions.add(
          OutlinedButton(
            onPressed: engine == null ? null : () => engine.cancel(task.id),
            child: const Text('Cancel'),
          ),
        );
      case TransferState.failed:
        actions.add(
          FilledButton(
            onPressed: engine == null ? null : () => engine.retry(task.id),
            child: const Text('Try again'),
          ),
        );
      case TransferState.blocked:
        if (!isNameCollision) break;
      case TransferState.completed:
      case TransferState.cancelled:
        break;
    }

    // A finished download has a file on this phone worth acting on.
    if (task.direction == TransferDirection.download &&
        task.state == TransferState.completed) {
      actions.addAll(<Widget>[
        OutlinedButton(
          onPressed: () => _openDownload(context, task),
          child: const Text('Open'),
        ),
        OutlinedButton(
          onPressed: () => _saveDownload(context, task),
          child: const Text('Save to device'),
        ),
      ]);
    }

    if (task.isFinished) {
      actions.add(
        TextButton(
          onPressed: engine == null ? null : () => engine.dismiss(task.id),
          child: const Text('Remove'),
        ),
      );
    }

    return actions;
  }

  /// Whether a blocked upload is blocked because the name is taken.
  ///
  /// Matched on the message rather than the kind, because the transport folds
  /// a `412 Precondition Failed` into `alreadyExists` and the task keeps only
  /// the text. Narrow on purpose: offering "Replace" for anything else would
  /// invite the user to destroy a file for no reason.
  static bool _looksLikeCollision(TransferTask task) {
    final String? message = task.lastError?.toLowerCase();
    if (message == null) return false;
    return message.contains('already') || message.contains('exists');
  }

  Future<void> _openDownload(BuildContext context, TransferTask task) async {
    final bool opened =
        await ref.read(deviceFilesProvider).openFile(localPath: task.localPath);
    if (opened || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'No app on this phone can open that file. Use “Save to device” to '
          'put it somewhere you can reach.',
        ),
      ),
    );
  }

  Future<void> _saveDownload(BuildContext context, TransferTask task) async {
    final bool saved = await ref.read(deviceFilesProvider).exportFile(
          localPath: task.localPath,
          suggestedName: RemotePath.name(task.localPath),
        );
    if (!saved || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Saved.')),
    );
  }

  static Color _stateColour(TransferState state, ColorScheme scheme) =>
      switch (state) {
        TransferState.running => scheme.primary,
        TransferState.completed => scheme.primary,
        TransferState.blocked || TransferState.failed => scheme.error,
        _ => scheme.onSurfaceVariant,
      };
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String label = switch (state) {
      TransferState.queued => 'Waiting',
      TransferState.running => 'Transferring',
      TransferState.paused => 'Paused',
      TransferState.completed => 'Done',
      TransferState.failed => 'Did not finish',
      TransferState.blocked => 'Needs you',
      TransferState.cancelled => 'Cancelled',
    };
    final bool isProblem =
        state == TransferState.failed || state == TransferState.blocked;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: isProblem
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isProblem
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NoTransfers extends ConsumerWidget {
  const _NoTransfers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppEmptyState(
      icon: Icons.swap_vert_rounded,
      title: 'Nothing transferring',
      message: 'Uploads and downloads show up here with their progress, so you '
          'can see exactly what is happening.',
      primaryAction: FilledButton.icon(
        onPressed: () =>
            ref.read(homeTabProvider.notifier).state = HomeTab.files,
        icon: const Icon(Icons.folder_rounded),
        label: const Text('Go to my files'),
      ),
    );
  }
}

/// The folder a remote path lives in, for the subtitle.
String _folderLabel(String remotePath) {
  final String? parent = RemotePath.parent(remotePath);
  if (parent == null || parent == RemotePath.root) return 'your top-level folder';
  return RemotePath.name(parent);
}
