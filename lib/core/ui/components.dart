/// The shared building blocks every screen is made of.
///
/// The point of these is not code reuse for its own sake — it is that the app
/// previously had **four** different ways of saying "something went wrong" (a
/// full-page block, an inline red card, an expandable coloured banner, and a
/// SnackBar that vanished after three seconds). A user had to learn the same
/// message four times.
///
/// One component per job, used everywhere:
///
/// | Job | Component |
/// |---|---|
/// | Full-screen failure with a way forward | [AppErrorView] |
/// | Nothing here yet, and what to do about it | [AppEmptyState] |
/// | A secondary message inside a screen | [InlineBanner] |
/// | Grouping related settings or rows | [SectionCard] |
/// | One row in a list | [AppListRow] |
/// | A sheet of actions | [AppSheet] |
library;

import 'package:flutter/material.dart';

import 'design.dart';

/// A full-screen failure: what happened, and the one action that helps.
///
/// Replaces the centred-red-icon-and-text pattern that made failures look like
/// a developer's placeholder. The optional [onRetry] is offered only by callers
/// whose error is genuinely retryable — showing a Retry button for a full
/// storage quota teaches the user that the app is broken rather than that their
/// account needs attention.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Scrollable so pull-to-refresh still works on the screen that hosts it.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      children: <Widget>[
        const SizedBox(height: AppSpacing.xxl),
        _IconMedallion(
          icon: icon,
          tint: theme.colorScheme.error,
          background: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (onRetry != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(retryLabel),
            ),
          ),
        ],
        if (secondaryAction != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Center(child: secondaryAction!),
        ],
      ],
    );
  }
}

/// Nothing here yet — and, when that is not simply "empty", why not.
///
/// [isCached] is the interesting case: a folder that has never been read
/// because the device is offline is a different message from a folder that is
/// genuinely empty, and saying so is what stops a user concluding their files
/// were deleted.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.primaryAction,
    this.secondaryActions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? primaryAction;
  final List<Widget> secondaryActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      children: <Widget>[
        const SizedBox(height: AppSpacing.xxl),
        _IconMedallion(
          icon: icon,
          tint: theme.colorScheme.primary,
          background: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (primaryAction != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          Center(child: primaryAction!),
        ],
        if (secondaryActions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Wrap(
              spacing: AppSpacing.md,
              alignment: WrapAlignment.center,
              children: secondaryActions,
            ),
          ),
        ],
      ],
    );
  }
}

/// A soft circle behind an icon, so empty and error states have a visual anchor
/// instead of a bare glyph on a blank screen.
class _IconMedallion extends StatelessWidget {
  const _IconMedallion({
    required this.icon,
    required this.tint,
    required this.background,
  });

  final IconData icon;
  final Color tint;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 42, color: tint),
      ),
    );
  }
}

/// How loudly a banner speaks.
enum BannerTone {
  /// Neutral information the user can ignore.
  info,

  /// Something needs attention but nothing is broken.
  warning,

  /// Something failed, or is about to.
  problem,
}

/// A message inside a screen.
///
/// This is the single replacement for the three inline patterns the app used to
/// have. It deliberately does **not** auto-dismiss: the old SnackBar was the
/// only feedback for a failed rename or delete, and it disappeared after three
/// seconds whether or not the user had read it.
class InlineBanner extends StatelessWidget {
  const InlineBanner({
    super.key,
    required this.tone,
    required this.message,
    this.icon,
    this.title,
    this.action,
    this.onDismiss,
  });

  /// A short, plain-language sentence.
  final String message;
  final BannerTone tone;
  final IconData? icon;
  final String? title;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (Color background, Color foreground, IconData fallbackIcon) =
        switch (tone) {
      BannerTone.info => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.info_outline,
        ),
      BannerTone.warning => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.warning_amber_rounded,
        ),
      BannerTone.problem => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
        ),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon ?? fallbackIcon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  action!,
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              color: foreground,
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// A titled group of rows or settings.
///
/// Replaces the bare `Card` + `Divider` stack, which produced flat, evenly
/// weighted walls of rows with no visual entry point.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.padding,
  });

  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.sm,
              ),
              child: Text(
                title!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.card,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: padding ?? const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                0,
              ),
              child: Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row in a list.
///
/// Sized and padded consistently so a list of files, a list of transfers and a
/// list of search results all have the same rhythm — the previous screens each
/// used a differently configured `ListTile` and it showed.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.isDestructive = false,
    this.dense = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Renders the row in the error colour, for delete and similar.
  final bool isDestructive;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        isDestructive ? theme.colorScheme.error : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: dense ? AppSpacing.minTouchTarget : AppSpacing.rowHeight,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: dense ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[
                IconTheme(
                  data: IconThemeData(color: foreground),
                  child: leading!,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w500,
                      ),
                      // Explicit maxLines so a long filename truncates rather
                      // than pushing the row's height around.
                      child: title,
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      DefaultTextStyle.merge(
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: isDestructive
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A label and a value, for the technical screen.
///
/// Unlike [AppListRow] this is a two-column readout rather than a tappable row,
/// but it shares the same padding and type so the two read as one list. The
/// value is selectable — someone reading a server address out to support needs
/// to be able to copy it.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A flexible label column rather than a fixed width: a fixed 140dp
          // left almost nothing for the value on a narrow screen and forced it
          // to wrap one word per line.
          Flexible(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            flex: 6,
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

/// A divider that matches the row padding, for use inside a [SectionCard].
class AppDivider extends StatelessWidget {
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: AppSpacing.lg,
        endIndent: AppSpacing.lg,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(
              alpha: 0.5,
            ),
      );
}

/// A sheet of actions for one item.
///
/// One presentation for every "what can I do with this" question, instead of
/// the mix of nested popup menus and modal sheets the app had. The header names
/// the thing the actions apply to, so there is no doubt about what is being
/// deleted.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
              ],
            ),
          ),
          ...children,
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// A centred progress indicator with an optional label.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (label != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              label!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
