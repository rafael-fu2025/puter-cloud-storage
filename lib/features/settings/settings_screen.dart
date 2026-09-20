/// Settings and diagnostics.
///
/// Diagnostics is not a debug screen bolted on at the end — it is the answer to
/// a real support question. The app's most likely failure mode is not a crash,
/// it is a connection that is *working but slow*, because WebDAV's 600
/// requests/min is shared per network (`docs/puter-api-research.md` §5). When
/// that happens the user needs to see which request class is saturated, and
/// which host is actually serving them, without a debugger.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/format/formatters.dart';
import '../../core/network/request_scheduler.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/remote_node.dart';
import '../browser/browser_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider).valueOrNull;
    final repository = ref.watch(fileRepositoryProvider);
    final preferences = ref.watch(browserPreferencesProvider).valueOrNull ??
        const BrowserPreferences();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          const _SectionHeader(label: 'Account'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: const Text('Connected'),
                  subtitle: Text(
                    session?.endpoint ?? 'unknown host',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Transport'),
                  subtitle: Text(
                    repository == null
                        ? 'none'
                        : '${repository.transportName} · '
                            '${repository.capabilities}',
                    maxLines: 2,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Sign out',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: const Text(
                    'Forgets the token and clears the local index',
                  ),
                  onTap: () => _confirmSignOut(context, ref),
                ),
              ],
            ),
          ),
          const _SectionHeader(label: 'Browsing'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.view_list_outlined),
                  title: const Text('Default view'),
                  trailing: SegmentedButton<BrowserViewMode>(
                    segments: const <ButtonSegment<BrowserViewMode>>[
                      ButtonSegment<BrowserViewMode>(
                        value: BrowserViewMode.list,
                        icon: Icon(Icons.view_list),
                        tooltip: 'List',
                      ),
                      ButtonSegment<BrowserViewMode>(
                        value: BrowserViewMode.grid,
                        icon: Icon(Icons.grid_view),
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
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sort),
                  title: const Text('Default sort'),
                  subtitle: Text(sortFieldLabel(preferences.sortField)),
                  onTap: () => _pickSort(context, ref, preferences),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.folder_outlined),
                  title: const Text('Folders first'),
                  subtitle: const Text('Keep directories above files'),
                  value: preferences.foldersFirst,
                  onChanged: (bool value) => ref
                      .read(browserPreferencesProvider.notifier)
                      .apply(
                        (BrowserPreferences current) =>
                            current.copyWith(foldersFirst: value),
                      ),
                ),
              ],
            ),
          ),
          const _SectionHeader(label: 'Storage'),
          const _StorageSection(),
          const _SectionHeader(label: 'Diagnostics'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Connection and rate limits'),
              subtitle: const Text(
                'Transport, request budget and quota',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DiagnosticsScreen(),
                ),
              ),
            ),
          ),
          const _SectionHeader(label: 'About'),
          const _AboutSection(),
        ],
      ),
    );
  }

  Future<void> _pickSort(
    BuildContext context,
    WidgetRef ref,
    BrowserPreferences preferences,
  ) async {
    // Plain ListTiles with a check mark rather than RadioListTile: the radio
    // group API was deprecated in Flutter 3.32 in favour of a RadioGroup
    // ancestor, and a ticked list needs neither.
    final field = await showDialog<NodeSortField>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('Sort by'),
        children: <Widget>[
          for (final option in NodeSortField.values)
            ListTile(
              leading: Icon(
                option == preferences.sortField
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: option == preferences.sortField
                    ? Theme.of(dialogContext).colorScheme.primary
                    : null,
              ),
              title: Text(sortFieldLabel(option)),
              onTap: () => Navigator.of(dialogContext).pop(option),
            ),
        ],
      ),
    );
    if (field == null) return;
    await ref.read(browserPreferencesProvider.notifier).apply(
          (BrowserPreferences current) => current.copyWith(sortField: field),
        );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'The stored token will be erased from this device, and the local '
          'index will be cleared so one account’s file names can never appear '
          'under another. Nothing is deleted from your Puter account, and your '
          'transfer list is cleared.',
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // The gate above reacts to the session state, so there is no navigation to
    // perform here — which is what keeps this the only place sign-out happens.
    await ref.read(sessionProvider.notifier).signOut();
  }
}

/// Quota and cache, side by side because they are the same question: what is
/// taking up room, here and there.
class _StorageSection extends ConsumerWidget {
  const _StorageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final usage = ref.watch(storageUsageProvider).valueOrNull;
    final cacheSize = ref.watch(cacheSizeProvider).valueOrNull;
    final repository = ref.watch(fileRepositoryProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.pie_chart_outline),
            title: const Text('Puter storage'),
            subtitle: usage == null
                ? const Text(
                    'This server does not report quota over WebDAV. The Puter '
                    'web app shows it.',
                  )
                : Text(
                    '${ByteFormat.format(usage.usedBytes)} of '
                    '${ByteFormat.format(usage.capacityBytes)} used '
                    '(${usage.percentage.toStringAsFixed(1)}%)',
                  ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(storageUsageProvider),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Local index'),
            subtitle: Text(
              cacheSize == null || cacheSize == 0
                  ? 'Nothing indexed yet'
                  : '$cacheSize entries on this device',
            ),
          ),
          if (cacheSize != null && cacheSize > 0) ...<Widget>[
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_sweep_outlined, color: theme.colorScheme.error),
              title: Text(
                'Clear local index',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: const Text(
                'Frees space on the device. Nothing is removed from Puter; '
                'folders are re-indexed the next time you open them.',
              ),
              onTap: repository == null
                  ? null
                  : () async {
                      await repository.clearCache();
                      ref.invalidate(cacheSizeProvider);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Local index cleared.')),
                      );
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Puter Cloud Storage'),
            subtitle: Text('Version 0.1.0 · Android client for Puter'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Built on Puter'),
            subtitle: const Text(PuterEndpoints.attributionUrl),
            onTap: () => _showCopyHint(context, PuterEndpoints.attributionUrl),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Manage your API token'),
            subtitle: const Text(PuterEndpoints.dashboardAccount),
            onTap: () =>
                _showCopyHint(context, PuterEndpoints.dashboardAccount),
          ),
        ],
      ),
    );
  }

  /// The URLs are shown as copyable text rather than being opened.
  ///
  /// Launching a browser from here would need `url_launcher`, and the app
  /// deliberately keeps its plugin surface to what it cannot do itself — see
  /// `docs/build-assessment.md` §4.4. A selectable string costs the user one
  /// long-press.
  static void _showCopyHint(BuildContext context, String url) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Long-press the address to copy it, then open it in '
              'your browser.'),
        ),
      );
  }
}

// ------------------------------------------------------------------ diagnostics

/// What is actually happening on the wire.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduler = ref.watch(requestSchedulerProvider);
    final repository = ref.watch(fileRepositoryProvider);
    final config = ref.watch(appConfigProvider);
    final session = ref.watch(sessionProvider).valueOrNull;
    final usage = ref.watch(storageUsageProvider).valueOrNull;
    final health = scheduler.health;

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          const _SectionHeader(label: 'Connection'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: <Widget>[
                _InfoRow(
                  label: 'Endpoint',
                  value: session?.endpoint ?? 'not connected',
                ),
                _InfoRow(
                  label: 'Transport',
                  value: repository?.transportName ?? 'none',
                ),
                _InfoRow(
                  label: 'Auth attempts left',
                  value: scheduler.authAttemptSafe
                      ? 'safe to retry'
                      : 'LOCKED — wait 15 minutes',
                  isProblem: !scheduler.authAttemptSafe,
                ),
                _InfoRow(
                  label: 'Capabilities',
                  value: repository?.capabilities.toString() ?? '—',
                ),
              ],
            ),
          ),
          const _SectionHeader(label: 'Request budget'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: <Widget>[
                _InfoRow(label: 'Queued now', value: '${scheduler.queuedCount}'),
                _InfoRow(
                  label: 'In flight now',
                  value: '${scheduler.totalInFlight} of '
                      '${config.maxConcurrentRequests}',
                ),
                const Divider(height: 1),
                for (final entry in health.entries)
                  _ClassRow(klass: entry.key, health: entry.value),
              ],
            ),
          ),
          const _SectionHeader(label: 'Quota'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: <Widget>[
                if (usage == null)
                  const ListTile(
                    leading: Icon(Icons.help_outline),
                    title: Text('Quota unavailable'),
                    subtitle: Text(
                      'The server did not report RFC 4331 quota properties.',
                    ),
                  )
                else ...<Widget>[
                  _InfoRow(
                    label: 'Used',
                    value: ByteFormat.format(usage.usedBytes),
                  ),
                  _InfoRow(
                    label: 'Capacity',
                    value: ByteFormat.format(usage.capacityBytes),
                  ),
                  _InfoRow(
                    label: 'Free',
                    value: ByteFormat.format(usage.freeBytes),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Re-check quota and connection'),
                  onTap: () {
                    ref.invalidate(storageUsageProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Re-checking…')),
                    );
                  },
                ),
              ],
            ),
          ),
          const _SectionHeader(label: 'Configuration'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: <Widget>[
                _InfoRow(
                  label: 'Plan tier',
                  value: config.planTier.name,
                ),
                _InfoRow(
                  label: 'Page size',
                  value: '${config.listingPageSize} entries',
                ),
                _InfoRow(
                  label: 'Concurrent transfers',
                  value: '${config.maxConcurrentTransfers}',
                ),
                _InfoRow(
                  label: 'Retry budget',
                  value: '${config.maxRetryAttempts} attempts',
                ),
                _InfoRow(
                  label: 'Cache TTL',
                  value: '${config.listingCacheTtl.inSeconds}s',
                ),
                _InfoRow(
                  label: 'Configured mode',
                  value: config.transportMode.name,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Text(
              'Rate limits are shared per network, not per app: WebDAV allows '
              '600 requests a minute and 10 concurrent across everything on '
              'this connection. When a request class shows as saturated, the '
              'app serves cached data and waits rather than failing.\n\n'
              'WebDAV is currently the only implemented transport. The WebView '
              'bridge described in ADR 0002 cannot be built against the current '
              'toolchain, so the configured mode above records an intention '
              'rather than a choice (§4.4 of the build assessment).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One request class's current state.
class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.klass, required this.health});

  final RequestClass klass;
  final ClassHealth health;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Out of budget this minute, or the breaker has tripped for this class:
    // either way the scheduler is serving cached data instead of calling out.
    final isSaturated = health.breakerOpen || health.remainingThisMinute <= 0;

    return ListTile(
      dense: true,
      leading: Icon(
        isSaturated ? Icons.pause_circle_outline : Icons.check_circle_outline,
        size: 20,
        color:
            isSaturated ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      title: Text(klass.name),
      subtitle: Text(
        health.breakerOpen
            ? 'Circuit open — serving cached data'
            : '${health.inFlight} in flight · '
                '${health.remainingThisMinute} left this minute',
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isProblem = false,
  });

  final String label;
  final String value;
  final bool isProblem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isProblem ? theme.colorScheme.error : null,
                fontWeight: isProblem ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
