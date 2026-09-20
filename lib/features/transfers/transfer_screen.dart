/// The transfer queue.
///
/// Grouped by what the user can do about each task, not by chronology:
///
/// * **Active** — moving, or waiting its turn.
/// * **Needs attention** — stopped, and only the user can restart it. A `413`
///   is in here, not in "failed", because no amount of retrying frees space.
/// * **Finished** — done, or cancelled.
///
/// The grouping is the point. A single chronological list makes a blocked
/// upload look like a slow one, and the user waits for something that will
/// never move.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/format/formatters.dart';
import '../../data/transfer/transfer_engine.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';

class TransferScreen extends ConsumerWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(transfersProvider).valueOrNull ?? const [];
    final engine = ref.watch(transferEngineProvider);

    final active = transfers
        .where((TransferTask task) =>
            task.state == TransferState.running ||
            task.state == TransferState.queued ||
            task.state == TransferState.paused)
        .toList(growable: false);
    final attention = transfers
        .where((TransferTask task) =>
            task.state == TransferState.failed ||
            task.state == TransferState.blocked)
        .toList(growable: false);
    final finished = transfers
        .where((TransferTask task) =>
            task.state == TransferState.completed ||
            task.state == TransferState.cancelled)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
        actions: <Widget>[
          if (finished.isNotEmpty || attention.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.playlist_remove),
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
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                if (active.isNotEmpty)
                  _AggregateHeader(active: active, engine: engine),
                if (active.isNotEmpty)
                  _Section(
                    title: 'Active',
                    tasks: active,
                    engine: engine,
                  ),
                if (attention.isNotEmpty)
                  _Section(
                    title: 'Needs attention',
                    subtitle: 'These will not move until you act on them.',
                    tasks: attention,
                    engine: engine,
                  ),
                if (finished.isNotEmpty)
                  _Section(
                    title: 'Finished',
                    tasks: finished,
                    engine: engine,
                  ),
              ],
            ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    TransferEngine engine,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear finished transfers?'),
        content: const Text(
          'Completed, cancelled and failed entries will be removed from this '
          'list. Files already uploaded or downloaded are not affected.',
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
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$title · ${tasks.length}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final task in tasks)
          TransferTile(task: task, engine: engine),
      ],
    );
  }
}

/// Overall progress and the controls that apply to all of it.
class _AggregateHeader extends ConsumerWidget {
  const _AggregateHeader({required this.active, required this.engine});

  final List<TransferTask> active;
  final TransferEngine? engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final totalBytes = active.fold<int>(
      0,
      (int sum, TransferTask task) => sum + task.totalBytes,
    );
    final doneBytes = active.fold<int>(
      0,
      (int sum, TransferTask task) => sum + task.bytesDone,
    );
    final fraction = totalBytes <= 0 ? 0.0 : doneBytes / totalBytes;
    final moving =
        active.where((TransferTask task) => task.state == TransferState.running);
    final isPaused = moving.isEmpty;

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isPaused ? Icons.pause_circle_outline : Icons.sync,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isPaused
                        ? 'Waiting to start'
                        : 'Moving ${moving.length} of ${active.length}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${(fraction * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction.clamp(0.0, 1.0)),
            const SizedBox(height: 8),
            Text(
              '${ByteFormat.format(doneBytes)} of '
              '${ByteFormat.format(totalBytes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: engine == null
                      ? null
                      : () {
                          for (final task in active) {
                            if (task.state == TransferState.running) {
                              engine!.pause(task.id);
                            } else if (task.state == TransferState.paused) {
                              engine!.resume(task.id);
                            } else {
                              engine!.cancel(task.id);
                            }
                          }
                        },
                  icon: Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                  ),
                  label: Text(isPaused ? 'Resume all' : 'Stop all'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      ref.read(homeTabProvider.notifier).state = HomeTab.files,
                  child: const Text('Back to files'),
                ),
              ],
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
  /// Sampled locally rather than on the task itself.
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

    final now = DateTime.now();
    final previousAt = _lastSampleAt;
    final previousBytes = _lastBytes;

    if (previousAt == null || previousBytes == null) {
      _lastSampleAt = now;
      _lastBytes = widget.task.bytesDone;
      return;
    }

    final elapsed = now.difference(previousAt);
    if (elapsed.inMilliseconds < 400) return;

    final delta = widget.task.bytesDone - previousBytes;
    if (delta < 0) return;

    final instant = delta / (elapsed.inMilliseconds / 1000);
    _rate = _rate == null ? instant : (_rate! * 0.6) + (instant * 0.4);
    _lastSampleAt = now;
    _lastBytes = widget.task.bytesDone;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final engine = widget.engine;
    final isUpload = task.direction == TransferDirection.upload;
    final name = RemotePath.name(task.remotePath);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isUpload ? Icons.upload : Icons.download,
                  size: 20,
                  color: _stateColor(task.state, theme.colorScheme),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                _StateChip(task: task),
                _TaskMenu(task: task, engine: engine),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isUpload
                  ? 'Uploading to ${_folderLabel(task.remotePath)}'
                  : 'Downloading to your device',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            if (task.state == TransferState.running) ...<Widget>[
              LinearProgressIndicator(
                value: task.totalBytes <= 0 ? null : task.progress,
              ),
              const SizedBox(height: 8),
              Row(
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (isUpload && !_canResumeUpload()) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Pausing an upload restarts it from the beginning — this '
                  'server does not support resuming a partial upload.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else if (task.lastError != null) ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.lastError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (task.state == TransferState.completed) ...<Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    task.totalBytes > 0
                        ? '${ByteFormat.format(task.totalBytes)} transferred'
                        : 'Completed',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (task.state == TransferState.paused)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  isUpload
                      ? 'Paused. Resuming starts this upload again from the '
                          'beginning.'
                      : 'Paused. Resuming continues from where it stopped.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _canResumeUpload() {
    final repository = ref.read(fileRepositoryProvider);
    return repository?.capabilities.canResumeUpload ?? false;
  }

  static Color _stateColor(TransferState state, ColorScheme scheme) =>
      switch (state) {
        TransferState.running => scheme.primary,
        TransferState.completed => scheme.primary,
        TransferState.queued => scheme.onSurfaceVariant,
        TransferState.paused => scheme.onSurfaceVariant,
        TransferState.blocked || TransferState.failed => scheme.error,
        TransferState.cancelled => scheme.onSurfaceVariant,
      };
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (task.state) {
      TransferState.queued => 'Queued',
      TransferState.running => 'Moving',
      TransferState.paused => 'Paused',
      TransferState.completed => 'Done',
      TransferState.failed => 'Failed',
      TransferState.blocked => 'Blocked',
      TransferState.cancelled => 'Cancelled',
    };
    final isProblem =
        task.state == TransferState.failed || task.state == TransferState.blocked;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isProblem
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
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
      ),
    );
  }
}

enum _TaskAction { pause, resume, cancel, retry, dismiss, open, export }

class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({required this.task, required this.engine});

  final TransferTask task;
  final TransferEngine? engine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDownload = task.direction == TransferDirection.download;
    final isDone = task.state == TransferState.completed;

    return PopupMenuButton<_TaskAction>(
      tooltip: 'Transfer actions',
      onSelected: (_TaskAction action) =>
          _handle(context, ref, action),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_TaskAction>>[
        if (task.state == TransferState.running)
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.pause,
            child: Text('Pause'),
          ),
        if (task.state == TransferState.paused ||
            task.state == TransferState.queued)
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.resume,
            child: Text('Resume'),
          ),
        if (task.state == TransferState.failed ||
            task.state == TransferState.blocked)
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.retry,
            child: Text('Retry'),
          ),
        if (!task.isFinished)
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.cancel,
            child: Text('Cancel'),
          ),
        // Only a finished download has a file on disk to act on.
        if (isDownload && isDone) ...<PopupMenuEntry<_TaskAction>>[
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.open,
            child: Text('Open'),
          ),
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.export,
            child: Text('Save to device…'),
          ),
        ],
        if (task.isFinished)
          const PopupMenuItem<_TaskAction>(
            value: _TaskAction.dismiss,
            child: Text('Remove from list'),
          ),
      ],
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    _TaskAction action,
  ) async {
    final engine = this.engine;
    final devices = ref.read(deviceFilesProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);

    switch (action) {
      case _TaskAction.pause:
        engine?.pause(task.id);
      case _TaskAction.resume:
        engine?.resume(task.id);
      case _TaskAction.retry:
        engine?.retry(task.id);
      case _TaskAction.cancel:
        engine?.cancel(task.id);
      case _TaskAction.dismiss:
        await engine?.dismiss(task.id);
      case _TaskAction.open:
        final opened = await devices.openFile(localPath: task.localPath);
        if (!opened) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                'No installed app can open this file. Use “Save to device” to '
                'put it somewhere you can.',
              ),
            ),
          );
        }
      case _TaskAction.export:
        final exported = await devices.exportFile(
          localPath: task.localPath,
          suggestedName: RemotePath.name(task.localPath),
        );
        if (exported) {
          messenger?.showSnackBar(
            const SnackBar(content: Text('Saved to the location you chose.')),
          );
        }
    }
  }
}

class _NoTransfers extends ConsumerWidget {
  const _NoTransfers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.swap_vert,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No transfers yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Uploads and downloads appear here, one row per file, so a single '
              'failure never hides the files that did move.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.files,
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Browse files'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The folder a remote path lives in, for the subtitle.
String _folderLabel(String remotePath) {
  final parent = RemotePath.parent(remotePath);
  if (parent == null || parent == RemotePath.root) return 'Home';
  return RemotePath.name(parent);
}

/// Re-exported so the screen and the engine agree on the copy for a failure.
String transferFailureLabel(Object error) => ErrorPresenter.transferLabel(error);
