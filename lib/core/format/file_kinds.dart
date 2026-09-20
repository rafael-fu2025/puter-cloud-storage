/// Which icon and tint a file gets, derived from its name.
///
/// Kept in `core/format` rather than in the browser widget because three
/// surfaces need the same answer — the browser, the transfer list and search
/// results — and an icon that changes between them reads as a bug.
library;

import 'package:flutter/material.dart';

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
  static IconData iconFor(FileCategory category) => switch (category) {
        FileCategory.folder => Icons.folder_rounded,
        FileCategory.image => Icons.image_outlined,
        FileCategory.video => Icons.movie_outlined,
        FileCategory.audio => Icons.audiotrack_outlined,
        FileCategory.document => Icons.description_outlined,
        FileCategory.spreadsheet => Icons.table_chart_outlined,
        FileCategory.presentation => Icons.slideshow_outlined,
        FileCategory.archive => Icons.folder_zip_outlined,
        FileCategory.code => Icons.code,
        FileCategory.text => Icons.article_outlined,
        FileCategory.pdf => Icons.picture_as_pdf_outlined,
        FileCategory.apk => Icons.android,
        FileCategory.font => Icons.text_fields,
        FileCategory.unknown => Icons.insert_drive_file_outlined,
      };

  /// Convenience for the common case.
  static IconData iconForName(String name, {bool isDirectory = false}) =>
      iconFor(of(name, isDirectory: isDirectory));

  /// A tint per category.
  ///
  /// Derived from [ColorScheme] rather than hard-coded hues so the palette
  /// stays legible in both light and dark themes — a fixed amber on a dark
  /// surface is the usual way this goes wrong.
  static Color tintFor(FileCategory category, ColorScheme scheme) =>
      switch (category) {
        FileCategory.folder => scheme.primary,
        FileCategory.image => scheme.tertiary,
        FileCategory.video => scheme.secondary,
        FileCategory.audio => scheme.secondary,
        FileCategory.pdf => scheme.error,
        FileCategory.archive => scheme.tertiary,
        FileCategory.apk => scheme.primary,
        _ => scheme.onSurfaceVariant,
      };

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
}
