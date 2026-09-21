/// Application shell.
///
/// The root decides which of three things the user sees: onboarding, a
/// connecting state, or the app itself. That decision lives in one place so
/// there is no path into the signed-in UI without a live transport behind it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/error/error_presenter.dart';
import '../core/ui/components.dart';
import '../core/ui/design.dart';
import 'home_shell.dart';
import 'providers.dart';
import 'session.dart';
import 'welcome_screen.dart';

/// Root widget.
class PuterCloudApp extends StatelessWidget {
  const PuterCloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Puter Cloud Storage',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const SessionGate(),
    );
  }

  static final ThemeData lightTheme = buildAppTheme(Brightness.light);
  static final ThemeData darkTheme = buildAppTheme(Brightness.dark);
}

/// Build the app's theme for one brightness.
///
/// Exposed so tests and the widget gallery can render the real thing rather
/// than an approximation of it.
ThemeData buildAppTheme(Brightness brightness) {
  final bool isLight = brightness == Brightness.light;

  // Built from the brand colour, then corrected. `fromSeed` on its own assigns
  // container and tertiary tones algorithmically — they are harmonious but
  // nobody chose them, which is exactly why the app looked like unstyled
  // Material. The overrides below are the choices.
  final ColorScheme base = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
  );

  final ColorScheme scheme = base.copyWith(
    primary: isLight ? AppColors.brand : const Color(0xFF8FAEFF),
    onPrimary: isLight ? Colors.white : const Color(0xFF06256B),
    // A calm, slightly cool neutral ramp. The default generated surfaces carry
    // a lavender cast that reads as unintentional against blue.
    surface: isLight ? const Color(0xFFFBFBFD) : const Color(0xFF111318),
    surfaceContainerLowest:
        isLight ? const Color(0xFFFFFFFF) : const Color(0xFF0C0E12),
    surfaceContainerLow:
        isLight ? const Color(0xFFF5F6FA) : const Color(0xFF16181E),
    surfaceContainer: isLight ? const Color(0xFFEFF1F7) : const Color(0xFF1B1E25),
    surfaceContainerHigh:
        isLight ? const Color(0xFFE8EBF3) : const Color(0xFF22262E),
    surfaceContainerHighest:
        isLight ? const Color(0xFFE1E5EF) : const Color(0xFF2A2F39),
    onSurface: isLight ? const Color(0xFF14161C) : const Color(0xFFE6E8EE),
    onSurfaceVariant:
        isLight ? const Color(0xFF525A6B) : const Color(0xFFA6AEBD),
    outlineVariant:
        isLight ? const Color(0xFFDCE0EA) : const Color(0xFF333944),
  );

  final TextTheme text = _textTheme(scheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,

    // Flat by default. Depth comes from the surface ramp; a shadow under every
    // list row is noise, not hierarchy.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
      actionsIconTheme: IconThemeData(color: scheme.onSurface, size: 24),
    ),

    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
    ),

    // One primary action per screen, and it is always this.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.action),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.action),
        side: BorderSide(color: scheme.outlineVariant),
        foregroundColor: scheme.onSurface,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppSpacing.minTouchTarget),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.action),
        textStyle: text.labelLarge,
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.action,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.action,
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.action,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.action,
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.action,
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      hintStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
      ),
      titleTextStyle: text.titleMedium,
      contentTextStyle: text.bodyMedium,
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      textStyle: text.bodyMedium,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primaryContainer.withValues(alpha: 0.55),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => text.labelSmall?.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      minVerticalPadding: AppSpacing.md,
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.action),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      thickness: 1,
      space: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.action),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 6,
      linearTrackColor: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(3),
      color: scheme.primary,
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelMedium),
        visualDensity: VisualDensity.compact,
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AppRadius.action),
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: BorderSide.none,
      labelStyle: text.labelSmall,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
    ),

    expansionTileTheme: ExpansionTileThemeData(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurface,
      iconColor: scheme.onSurfaceVariant,
      collapsedIconColor: scheme.onSurfaceVariant,
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: AppRadius.action,
      ),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
  );
}

/// An explicit type scale.
///
/// Flutter's defaults are close but not deliberate: titles want tighter
/// tracking than body text, and body copy at 1.45 line height is what makes a
/// paragraph of explanation readable on a phone rather than merely present.
TextTheme _textTheme(ColorScheme scheme) {
  final TextTheme base = ThemeData(brightness: scheme.brightness).textTheme;

  return base.copyWith(
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: 24,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: scheme.onSurface,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 20,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: scheme.onSurface,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      color: scheme.onSurface,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 14.5,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.4,
      color: scheme.onSurface,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.45,
      color: scheme.onSurface,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 13,
      height: 1.4,
      color: scheme.onSurfaceVariant,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    ),
  );
}

/// Routes between onboarding and the app based on the session state.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const Scaffold(body: LoadingState(label: 'Connecting…')),
      error: (Object error, StackTrace _) => _SessionFailure(error: error),
      data: (SessionState value) => switch (value.status) {
        SessionStatus.signedOut => const WelcomeScreen(),
        SessionStatus.failed =>
          _SessionFailure(error: value.error ?? 'Unknown failure'),
        SessionStatus.connecting =>
          const Scaffold(body: LoadingState(label: 'Connecting…')),
        SessionStatus.ready => const HomeShell(),
      },
    );
  }
}

/// The session could not be established.
///
/// Retry appears only when the error kind says a retry could plausibly succeed.
/// Offering it for a `429` lockout would walk the user straight back into the
/// failed-sign-in limit that produced it — the one mistake this app cannot
/// afford, because it locks the account out of its own storage.
class _SessionFailure extends ConsumerWidget {
  const _SessionFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presentation = ErrorPresenter.describe(error);

    return Scaffold(
      appBar: AppBar(title: const Text('Puter Cloud Storage')),
      body: SafeArea(
        child: AppErrorView(
          icon: presentation.icon,
          title: presentation.title,
          message: presentation.message,
          onRetry: presentation.canRetry
              ? () => ref.invalidate(sessionProvider)
              : null,
          secondaryAction: TextButton(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            child: const Text('Use a different access key'),
          ),
        ),
      ),
    );
  }
}
