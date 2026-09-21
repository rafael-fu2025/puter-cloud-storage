/// Settings, and the technical screen behind a gate.
///
/// Settings is written for the person who owns the phone. It says "Connected
/// to Puter", not a hostname; "Storage space", not "quota"; "Saved on this
/// phone", not "local index". Everything an engineer would want —
/// the endpoint, the per-class request budget, the breaker state — moved into
/// [DiagnosticsScreen], reached by tapping the version row seven times.
///
/// That gate is not hiding anything. It is the difference between an app that
/// looks like it was built for its user and one that looks like it was built
/// for its author.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../core/config/app_config.dart';
import '../../core/format/formatters.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/platform/platform_bridge.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/remote_node.dart';
import '../browser/browser_providers.dart';
import '../browser/sort_sheet.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState? session = ref.watch(sessionProvider).valueOrNull;
    final FileRepository? repository = ref.watch(fileRepositoryProvider);
    final bool canWrite = repository?.capabilities.canWrite ?? true;
    final BrowserPreferences preferences =
        ref.watch(browserPreferencesProvider).valueOrNull ??
            const BrowserPreferences();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xxl),
        children: <Widget>[
          SectionCard(
            title: 'Account',
            children: <Widget>[
              AppListRow(
                leading: const Icon(Icons.cloud_done_rounded),
                title: const Text('Connected to Puter'),
                subtitle: Text(
                  session?.status == SessionStatus.ready
                      ? 'Your files are in your own Puter account'
                      : 'Not connected',
                ),
              ),
              const AppDivider(),
              AppListRow(
                leading: Icon(
                  Icons.logout_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Disconnect'),
                subtitle: const Text(
                  'Forgets the access key and removes saved file lists from '
                  'this phone. Nothing is deleted from Puter.',
                ),
                isDestructive: true,
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),

          SectionCard(
            title: 'Storage',
            children: <Widget>[
              const _StorageRow(),
              if (!canWrite) ...<Widget>[
                const AppDivider(),
                const AppListRow(
                  leading: Icon(Icons.lock_outline_rounded),
                  title: Text('Read-only account'),
                  subtitle: Text(
                    'This Puter account does not allow changes, so uploading '
                    'and creating folders are unavailable.',
                  ),
                ),
              ],
            ],
          ),

          SectionCard(
            title: 'Browsing',
            children: <Widget>[
              AppListRow(
                leading: const Icon(Icons.view_list_rounded),
                title: const Text('How files are laid out'),
                subtitle: Text(
                  preferences.viewMode == BrowserViewMode.grid
                      ? 'Grid'
                      : 'List',
                ),
                trailing: SegmentedButton<BrowserViewMode>(
                  segments: const <ButtonSegment<BrowserViewMode>>[
                    ButtonSegment<BrowserViewMode>(
                      value: BrowserViewMode.list,
                      icon: Icon(Icons.view_list_rounded, size: 18),
                      tooltip: 'List',
                    ),
                    ButtonSegment<BrowserViewMode>(
                      value: BrowserViewMode.grid,
                      icon: Icon(Icons.grid_view_rounded, size: 18),
                      tooltip: 'Grid',
                    ),
                  ],
                  selected: <BrowserViewMode>{preferences.viewMode},
                  onSelectionChanged: (Set<BrowserViewMode> selection) => ref
                      .read(browserPreferencesProvider.notifier)
                      .apply(
                        (BrowserPreferences current) =>
                            current.copyWith(viewMode: selection.first),
                      ),
                  showSelectedIcon: false,
                ),
              ),
              const AppDivider(),
              AppListRow(
                leading: const Icon(Icons.sort_rounded),
                title: const Text('Sort files by'),
                subtitle: Text(
                  '${sortFieldLabel(preferences.sortField)} · '
                  '${preferences.sortOrder == SortOrder.ascending ? 'A–Z' : 'Z–A'}',
                ),
                onTap: () => showSortSheet(context, ref, preferences),
              ),
              const AppDivider(),
              SwitchListTile(
                value: preferences.foldersFirst,
                onChanged: (bool value) => ref
                    .read(browserPreferencesProvider.notifier)
                    .apply(
                      (BrowserPreferences current) =>
                          current.copyWith(foldersFirst: value),
                    ),
                title: const Text('Folders at the top'),
                subtitle: const Text('Keep folders above files in every list'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
              ),
            ],
          ),

          const _AboutCard(),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: Icon(
          Icons.logout_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Disconnect this phone?'),
        content: const Text(
          'The access key will be erased from this device, and the list of '
          'files saved for offline browsing will be cleared. Your files stay '
          'exactly where they are in your Puter account.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(sessionProvider.notifier).signOut();
  }
}

/// Storage space, with the numbers only when they are known.
class _StorageRow extends ConsumerWidget {
  const _StorageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StorageUsage? usage = ref.watch(storageUsageProvider).valueOrNull;
    final int? saved = ref.watch(cacheSizeProvider).valueOrNull;
    final theme = Theme.of(context);
    final double threshold = ref.watch(appConfigProvider).quotaWarningThreshold;
    final bool isNearlyFull = usage != null && usage.isNearLimit(threshold);

    return Column(
      children: <Widget>[
        AppListRow(
          leading: Icon(
            isNearlyFull ? Icons.sd_card_alert_outlined : Icons.pie_chart_outline_rounded,
            color: isNearlyFull ? theme.colorScheme.error : null,
          ),
          title: const Text('Puter storage space'),
          subtitle: Text(
            usage == null
                ? 'Puter did not report how much space is left. The Puter '
                    'website shows it.'
                : '${ByteFormat.format(usage.usedBytes)} of '
                    '${ByteFormat.format(usage.capacityBytes)} used · '
                    '${ByteFormat.format(usage.freeBytes)} free',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Check again',
            onPressed: () => ref.invalidate(storageUsageProvider),
          ),
        ),
        if (usage != null) ...<Widget>[
          const AppDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usage.usedFraction,
                semanticsLabel: 'Puter storage space used',
                color: isNearlyFull
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        ],
        const AppDivider(),
        AppListRow(
          leading: const Icon(Icons.smartphone_rounded),
          title: const Text('Files saved on this phone'),
          subtitle: Text(
            saved == null || saved == 0
                ? 'Nothing saved yet. Opening a folder saves it for offline '
                    'browsing and search.'
                : '$saved files · used for offline browsing and search',
          ),
          trailing: saved == null || saved == 0
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    color: theme.colorScheme.error,
                  ),
                  tooltip: 'Clear saved files',
                  onPressed: () => _confirmClear(context, ref),
                ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear saved files?'),
        content: const Text(
          'Frees space on this phone. Nothing is removed from Puter — the '
          'files come back the next time you open their folders.',
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
    if (confirmed != true) return;

    final repository = ref.read(fileRepositoryProvider);
    if (repository == null) return;
    await repository.clearCache();
    ref.invalidate(cacheSizeProvider);
  }
}

/// Version row — and, seven taps in, the way into diagnostics.
class _AboutCard extends ConsumerStatefulWidget {
  const _AboutCard();

  @override
  ConsumerState<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends ConsumerState<_AboutCard> {
  static const int _tapsRequired = 7;
  int _taps = 0;

  void _onVersionTap() {
    _taps++;
    if (_taps < _tapsRequired) {
      // Tell the user something is happening after the third tap, so the
      // gesture is discoverable rather than a secret.
      if (_taps >= 3) {
        final int remaining = _tapsRequired - _taps;
        ScaffoldMessenger.maybeOf(context)?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 1),
              content: Text(
                '$remaining more ${remaining == 1 ? 'tap' : 'taps'} for '
                'technical details',
              ),
            ),
          );
      }
      return;
    }

    _taps = 0;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      children: <Widget>[
        AppListRow(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('Puter Cloud Storage'),
          subtitle: const Text('Version 0.1.0'),
          onTap: _onVersionTap,
        ),
        const AppDivider(),
        AppListRow(
          leading: const Icon(Icons.favorite_outline_rounded),
          title: const Text('Built on Puter'),
          subtitle: const Text(PuterEndpoints.attributionUrl),
          onTap: () => _open(context, PuterEndpoints.attributionUrl),
        ),
        const AppDivider(),
        AppListRow(
          leading: const Icon(Icons.key_rounded),
          title: const Text('Manage your access keys'),
          subtitle: const Text('Create or revoke keys on your Puter account'),
          onTap: () => _open(context, PuterEndpoints.dashboardAccount),
        ),
        const AppDivider(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'This app talks to your own Puter account. It keeps no servers '
            'and no copy of your files — only the folder listings it needs to '
            'work offline.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final bool opened = await PlatformBridge.openUrl(url);
    if (opened || !context.mounted) return;
    // A device with no browser still gets the address, as selectable text
    // rather than a dead tap.
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: SelectableText(url)),
    );
  }
}
