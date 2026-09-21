/// The design language.
///
/// One place that decides what the app looks like, so a screen never has to.
/// Before this existed the theme was `ColorScheme.fromSeed(...)` and nothing
/// else, which is why every surface rendered as unmodified Material 3 and the
/// app had no identity of its own.
///
/// Four decisions carry the look:
///
/// * **Tonal, not shadowed.** Depth comes from the surface ramp
///   (`surfaceContainerLowest` → `Highest`), not from elevation. Shadows are
///   reserved for things that genuinely float — sheets and the FAB. A list of
///   500 files with a drop shadow under every row is noise.
/// * **One accent.** Puter's blue, used for exactly one thing per screen: the
///   primary action and the current location. Everything else is neutral, so
///   "what can I press here" is never a question.
/// * **Rounded and open.** A 12/16/20/28 radius scale and generous spacing.
///   Roominess is what makes an interface legible to someone who does not
///   already know how it works.
/// * **Semantic colour is scarce.** Red means something is wrong and the user
///   must act. It is never decoration — which is why PDFs are no longer red and
///   the onboarding disclosure is no longer an error card.
library;

import 'package:flutter/material.dart';

/// Brand and semantic colours.
///
/// Held as constants rather than read from the generated scheme, because a
/// seed-derived palette assigns container tones algorithmically and nobody
/// chose them. These were chosen.
abstract final class AppColors {
  /// The brand anchor, shared with Puter's own UI.
  static const Color brand = Color(0xFF3B6EF6);

  /// A second, cooler accent for informational emphasis.
  static const Color brandDeep = Color(0xFF1F4BD8);

  /// Category accents.
  ///
  /// Distinct hues so a spreadsheet, a slide deck and a source file are told
  /// apart at a glance. Muted enough to sit behind a filename without
  /// competing with it, and each legible on both light and dark surfaces.
  static const Color folder = Color(0xFF3B6EF6);
  static const Color image = Color(0xFF0E9F6E);
  static const Color video = Color(0xFF8B5CF6);
  static const Color audio = Color(0xFFD946A0);
  static const Color document = Color(0xFF2563EB);
  static const Color spreadsheet = Color(0xFF16794C);
  static const Color presentation = Color(0xFFD97706);
  static const Color pdf = Color(0xFFDC2626);

  /// Deliberately *not* the error red above.
  ///
  /// A PDF is a normal thing to have. Tinting it with the colour that means
  /// "something is broken" made every document in a list look like a warning.
  static const Color archive = Color(0xFFB45309);
  static const Color code = Color(0xFF0E7490);
  static const Color text = Color(0xFF64748B);
  static const Color apk = Color(0xFF16A34A);
  static const Color font = Color(0xFF7C3AED);

  /// Neutral for anything unclassified.
  static const Color unknown = Color(0xFF94A3B8);

  /// Adjust a category colour for the current brightness.
  ///
  /// The palette is tuned for light surfaces; on a dark background the same
  /// values lose contrast, so they are lightened rather than reused. A single
  /// set of fixed tints is the usual reason a carefully chosen palette looks
  /// muddy in dark mode.
  static Color adapt(Color color, Brightness brightness) {
    if (brightness == Brightness.light) return color;
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + 0.24).clamp(0.0, 0.86))
        .withSaturation((hsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
  }
}

/// Spacing scale.
///
/// A fixed set rather than arbitrary numbers, which is what keeps 90dp in one
/// place from becoming 92dp in the next.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal screen margin.
  static const double gutter = 20;

  /// Minimum height of an interactive row. Below this, thumbs miss.
  static const double rowHeight = 60;

  /// Minimum touch target, per the accessibility guidelines both platforms
  /// publish.
  static const double minTouchTarget = 48;
}

/// Corner radii.
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
  static const BorderRadius action = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// How long things take.
abstract final class AppMotion {
  /// The default for a state change the user caused.
  static const Duration quick = Duration(milliseconds: 180);

  /// For a larger transition, such as opening a sheet.
  static const Duration medium = Duration(milliseconds: 240);

  static const Curve ease = Curves.easeOutCubic;
}
