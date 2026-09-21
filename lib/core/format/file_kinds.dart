/// Which icon and tint a file gets, derived from its name.
///
/// Kept in `core/format` rather than in the browser widget because three
/// surfaces need the same answer — the browser, the transfer list and search
/// results — and an icon that changes between them reads as a bug.
library;

import 'package:flutter/material.dart';

import '../ui/design.dart';

/// Broad category a file belongs to, for icon and colour selection.
enum FileCategory {
  folder,
  image,
  video,
  audio,
  document,
  spreadsheet,
  presentation,
  archive,
  code,
  text,
  pdf,
  apk,
  font,
  unknown,
}

/// Extension-to-category mapping.
abstract final class FileKinds {
  static const Map<String, FileCategory> _byExtension =
      <String, FileCategory>{
    'jpg': FileCategory.image,
    'jpeg': FileCategory.image,
    'png': FileCategory.image,
    'gif': FileCategory.image,
    'webp': FileCategory.image,
    'bmp': FileCategory.image,
    'heic': FileCategory.image,
    'heif': FileCategory.image,
    'svg': FileCategory.image,
    'tif': FileCategory.image,
    'tiff': FileCategory.image,
    'mp4': FileCategory.video,
    'mkv': FileCategory.video,
    'mov': FileCategory.video,
    'avi': FileCategory.video,
    'webm': FileCategory.video,
    '3gp': FileCategory.video,
    'm4v': FileCategory.video,
    'mp3': FileCategory.audio,
    'm4a': FileCategory.audio,
    'aac': FileCategory.audio,
    'wav': FileCategory.audio,
    'flac': FileCategory.audio,
    'ogg': FileCategory.audio,
    'opus': FileCategory.audio,
    'pdf': FileCategory.pdf,
    'doc': FileCategory.document,
    'docx': FileCategory.document,
    'odt': FileCategory.document,
    'rtf': FileCategory.document,
    'pages': FileCategory.document,
    'xls': FileCategory.spreadsheet,
    'xlsx': FileCategory.spreadsheet,
    'ods': FileCategory.spreadsheet,
    'csv': FileCategory.spreadsheet,
    'numbers': FileCategory.spreadsheet,
    'ppt': FileCategory.presentation,
    'pptx': FileCategory.presentation,
    'odp': FileCategory.presentation,
    'key': FileCategory.presentation,
    'zip': FileCategory.archive,
    'rar': FileCategory.archive,
    '7z': FileCategory.archive,
    'tar': FileCategory.archive,
    'gz': FileCategory.archive,
    'bz2': FileCategory.archive,
    'xz': FileCategory.archive,
    'apk': FileCategory.apk,
    'ttf': FileCategory.font,
    'otf': FileCategory.font,
    'woff': FileCategory.font,
    'woff2': FileCategory.font,
    'json': FileCategory.code,
    'xml': FileCategory.code,
    'yaml': FileCategory.code,
    'yml': FileCategory.code,
    'html': FileCategory.code,
    'htm': FileCategory.code,
    'css': FileCategory.code,
    'js': FileCategory.code,
    'ts': FileCategory.code,
    'dart': FileCategory.code,
    'py': FileCategory.code,
    'java': FileCategory.code,
    'kt': FileCategory.code,
    'swift': FileCategory.code,
    'c': FileCategory.code,
    'h': FileCategory.code,
    'cpp': FileCategory.code,
    'rs': FileCategory.code,
    'go': FileCategory.code,
    'sh': FileCategory.code,
    'sql': FileCategory.code,
    'txt': FileCategory.text,
    'md': FileCategory.text,
    'log': FileCategory.text,
    'ini': FileCategory.text,
    'cfg': FileCategory.text,
    'conf': FileCategory.text,
  };

  /// Category for a file name or extension. Folders are their own category.
  static FileCategory of(String name, {bool isDirectory = false}) {
    if (isDirectory) return FileCategory.folder;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return FileCategory.unknown;
    return _byExtension[name.substring(dot + 1).toLowerCase()] ??
        FileCategory.unknown;
  }

  /// The icon shown for [category].
  ///
  /// One family — `_rounded` throughout — at a consistent weight. The previous
  /// mapping mixed filled and outlined glyphs in the same list, so adjacent
  /// rows had visibly different optical weight.
  static IconData iconFor(FileCategory category) => switch (category) {
        FileCategory.folder => Icons.folder_rounded,
        FileCategory.image => Icons.image_rounded,
        FileCategory.video => Icons.movie_rounded,
        FileCategory.audio => Icons.audiotrack_rounded,
        FileCategory.document => Icons.description_rounded,
        FileCategory.spreadsheet => Icons.table_chart_rounded,
        FileCategory.presentation => Icons.slideshow_rounded,
        FileCategory.archive => Icons.folder_zip_rounded,
        FileCategory.code => Icons.code_rounded,
        FileCategory.text => Icons.article_rounded,
        FileCategory.pdf => Icons.picture_as_pdf_rounded,
        FileCategory.apk => Icons.android_rounded,
        FileCategory.font => Icons.text_fields_rounded,
        FileCategory.unknown => Icons.insert_drive_file_rounded,
      };

  /// Convenience for the common case.
  static IconData iconForName(String name, {bool isDirectory = false}) =>
      iconFor(of(name, isDirectory: isDirectory));

  /// A tint per category, from the design language's own palette.
  ///
  /// Each family gets its own hue so a spreadsheet, a slide deck and a source
  /// file are distinguishable at a glance. Two things this deliberately does
  /// not do, both of which the previous version got wrong:
  ///
  /// * **PDFs are not error-red.** Red means something is broken and needs the
  ///   user. A PDF is a normal document.
  /// * **Documents do not all collapse to one grey.** That made four different
  ///   file types visually identical.
  ///
  /// [AppColors.adapt] lightens each hue for dark surfaces, where the light-mode
  /// values would otherwise lose contrast.
  static Color tintFor(FileCategory category, ColorScheme scheme) {
    final Color base = switch (category) {
      FileCategory.folder => AppColors.folder,
      FileCategory.image => AppColors.image,
      FileCategory.video => AppColors.video,
      FileCategory.audio => AppColors.audio,
      FileCategory.document => AppColors.document,
      FileCategory.spreadsheet => AppColors.spreadsheet,
      FileCategory.presentation => AppColors.presentation,
      FileCategory.pdf => AppColors.pdf,
      FileCategory.archive => AppColors.archive,
      FileCategory.code => AppColors.code,
      FileCategory.text => AppColors.text,
      FileCategory.apk => AppColors.apk,
      FileCategory.font => AppColors.font,
      FileCategory.unknown => AppColors.unknown,
    };
    return AppColors.adapt(base, scheme.brightness);
  }

  /// Whether [name] is something the browser can render a thumbnail for.
  ///
  /// Only raster formats: an SVG or a HEIC would need a decoder the app does
  /// not ship, and claiming otherwise produces a broken-image placeholder.
  static bool isThumbnailable(String name) {
    const Set<String> raster = <String>{
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
    };
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return false;
    return raster.contains(name.substring(dot + 1).toLowerCase());
  }

  /// A plain-language description of what a file is.
  ///
  /// Used instead of the MIME type. Nobody outside a standards committee knows
  /// what `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
  /// means, and printing it in a Details dialog tells the user nothing while
  /// looking like a bug.
  static String describeCategory(
    String name, {
    bool isDirectory = false,
    String? mimeType,
  }) {
    if (isDirectory) return 'Folder';

    final category = of(name);
    final label = switch (category) {
      FileCategory.folder => 'Folder',
      FileCategory.image => 'Image',
      FileCategory.video => 'Video',
      FileCategory.audio => 'Audio',
      FileCategory.document => 'Document',
      FileCategory.spreadsheet => 'Spreadsheet',
      FileCategory.presentation => 'Presentation',
      FileCategory.archive => 'Archive',
      FileCategory.code => 'Code',
      FileCategory.text => 'Text',
      FileCategory.pdf => 'PDF',
      FileCategory.apk => 'Android app',
      FileCategory.font => 'Font',
      FileCategory.unknown => 'File',
    };

    final extension = of(name) == FileCategory.unknown
        ? ''
        : _extensionOf(name).toUpperCase();
    return extension.isEmpty ? label : '$label · $extension';
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1 ? '' : name.substring(dot + 1);
  }
}
