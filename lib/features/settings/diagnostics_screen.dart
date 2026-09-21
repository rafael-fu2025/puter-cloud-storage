/// Technical details, behind a deliberate gate.
///
/// Seven taps on the version row in Settings opens this. It is not secret — it
/// tells the user how — but it is out of the way, because everything here is
/// for diagnosing a problem rather than for using the app.
///
/// The previous version of this screen was a primary Settings entry that
/// rendered `TransportCapabilities(canResumeUpload: false, …)`, cited "ADR 0002"
/// and "§4.4 of the build assessment", and explained RFC 4331. That is a
/// developer's console, and putting it one tap from the settings a normal
/// person changes made the whole app feel like an internal tool.
///
/// The labels here are still plain, because the person reading them is a user
/// who was asked by support to read them out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../core/config/app_config.dart';
import '../../core/format/formatters.dart';
import '../../core/network/request_scheduler.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/repositories/file_repository.dart';
import '../../domain/entities/remote_node.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RequestScheduler scheduler = ref.watch(requestSchedulerProvider);
    final FileRepository? repository = ref.watch(fileRepositoryProvider);
    final AppConfig config = ref.watch(appConfigProvider);
    final SessionState? session = ref.watch(sessionProvider).valueOrNull;
    final StorageUsage? usage = ref.watch(storageUsageProvider).valueOrNull;
    final bool authSafe = scheduler.authAttemptSafe;

    return Scaffold(
      appBar: AppBar(title: const Text('Technical details')),
      body: ListView(
        padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xxl),
        children: <Widget>[
          SectionCard(
            title: 'Connection',
            children: <Widget>[
              InfoRow(
                label: 'Status',
                value: repository == null ? 'Not connected' : 'Connected',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Server',
                value: session?.endpoint ?? 'unknown',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Can I upload?',
                value: (repository?.capabilities.canWrite ?? false)
                    ? 'Yes'
                    : 'No — this account is read-only',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Can I resume a paused upload?',
                value: (repository?.capabilities.canResumeUpload ?? false)
                    ? 'Yes'
                    : 'No — a paused upload starts again from the beginning',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Sign-in attempts',
                value: authSafe
                    ? 'Safe to try again'
                    : 'Blocked for 15 minutes after too many failures',
                isProblem: !authSafe,
              ),
            ],
          ),

          SectionCard(
            title: 'How much is being requested',
            description:
                'Puter limits how many requests an account can make each '
                'minute, and how many can be in flight at once. When a line '
                'below runs out, the app shows saved information and waits '
                'rather than failing.',
            children: <Widget>[
              InfoRow(label: 'Waiting to send', value: '${scheduler.queuedCount}'),
              const AppDivider(),
              InfoRow(
                label: 'In flight now',
                value: '${scheduler.totalInFlight} of '
                    '${config.maxConcurrentRequests}',
              ),
              const AppDivider(),
              for (final MapEntry<RequestClass, ClassHealth> entry
                  in scheduler.health.entries)
                _ClassRow(klass: entry.key, health: entry.value),
            ],
          ),

          SectionCard(
            title: 'Storage space',
            children: <Widget>[
              if (usage == null)
                const InfoRow(
                  label: 'Reported',
                  value: 'Not available from this connection',
                )
              else ...<Widget>[
                InfoRow(label: 'Used', value: ByteFormat.format(usage.usedBytes)),
                const AppDivider(),
                InfoRow(
                  label: 'Total',
                  value: ByteFormat.format(usage.capacityBytes),
                ),
                const AppDivider(),
                InfoRow(
                  label: 'Free',
                  value: ByteFormat.format(usage.freeBytes),
                ),
              ],
              const AppDivider(),
              AppListRow(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Check the connection again'),
                onTap: () {
                  ref.invalidate(storageUsageProvider);
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('Checking…')),
                  );
                },
              ),
            ],
          ),

          SectionCard(
            title: 'How this app is set up',
            children: <Widget>[
              InfoRow(label: 'Plan assumed', value: config.planTier.name),
              const AppDivider(),
              InfoRow(
                label: 'Files fetched per page',
                value: '${config.listingPageSize}',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Uploads at once',
                value: '${config.maxConcurrentTransfers}',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Retries before giving up',
                value: '${config.maxRetryAttempts}',
              ),
              const AppDivider(),
              InfoRow(
                label: 'Saved listings stay fresh for',
                value: '${config.listingCacheTtl.inSeconds} seconds',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One request category's current state, in words.
class _ClassRow extends StatelessWidget {
  const _ClassRow({required this.klass, required this.health});

  final RequestClass klass;
  final ClassHealth health;

  /// Plain names for the internal request categories.
  static String _label(RequestClass klass) => switch (klass) {
        RequestClass.stat => 'Checking a file',
        RequestClass.readdir => 'Listing a folder',
        RequestClass.read => 'Downloading',
        RequestClass.write => 'Uploading',
        RequestClass.mutation => 'Renaming, moving, deleting',
        RequestClass.search => 'Searching',
        RequestClass.signedUrl => 'Creating links',
        RequestClass.usage => 'Checking storage space',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isSaturated =
        health.breakerOpen || health.remainingThisMinute <= 0;

    return AppListRow(
      dense: true,
      leading: Icon(
        isSaturated
            ? Icons.hourglass_bottom_rounded
            : Icons.check_circle_outline_rounded,
        size: 20,
        color: isSaturated
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
      ),
      title: Text(_label(klass)),
      subtitle: Text(
        health.breakerOpen
            ? 'Paused — showing saved information until Puter catches up'
            : '${health.inFlight} in flight · '
                '${health.remainingThisMinute} left this minute',
      ),
    );
  }
}
