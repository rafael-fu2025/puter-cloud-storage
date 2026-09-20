/// Presentation formatting for sizes and timestamps.
///
/// Pure Dart, no Flutter, so the same rules apply to the transfer list, the
/// storage meter and the file browser without three copies drifting apart.
library;

import 'package:intl/intl.dart';

/// Human-readable byte sizes.
abstract final class ByteFormat {
  static const List<String> _units = <String>['B', 'KB', 'MB', 'GB', 'TB'];

  /// Format [bytes] with a unit that keeps the number readable.
  ///
  /// Binary units (1024), because that is what every other storage tool
  /// reports and a Puter quota shown as "104.9 MB" against a dashboard that
  /// says "100 MiB" would look like a discrepancy rather than a rounding
  /// choice.
  static String format(int bytes) {
    if (bytes < 0) return '—';
    if (bytes < 1024) return '$bytes B';

    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < _units.length - 1) {
      value /= 1024;
      unit++;
    }

    // One decimal below 10 so "1.4 GB" keeps its precision, none above it so
    // "147 MB" does not gain a digit that means nothing.
    final decimals = value < 10 ? 1 : 0;
    return '${value.toStringAsFixed(decimals)} ${_units[unit]}';
  }

  /// Transfer rates, e.g. `2.4 MB/s`.
  static String rate(int bytesPerSecond) =>
      bytesPerSecond <= 0 ? '—' : '${format(bytesPerSecond)}/s';

  /// A coarse duration for an estimated remaining time.
  static String duration(Duration duration) {
    if (duration.inSeconds < 1) return 'less than a second';
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    if (duration.inMinutes < 60) {
      final seconds = duration.inSeconds % 60;
      return seconds == 0
          ? '${duration.inMinutes}m'
          : '${duration.inMinutes}m ${seconds}s';
    }
    final minutes = duration.inMinutes % 60;
    return minutes == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${minutes}m';
  }
}

/// Human-readable timestamps.
abstract final class DateFormatting {
  static final DateFormat _sameYear = DateFormat('d MMM, HH:mm');
  static final DateFormat _otherYear = DateFormat('d MMM yyyy');

  /// Format [time] relative to [now], falling back to a calendar date.
  ///
  /// Relative wording only for the last week: past that, "43 days ago" is
  /// harder to place than a date, so the date is what the user gets.
  static String relative(DateTime? time, {DateTime? now}) {
    if (time == null) return 'Unknown';
    final reference = now ?? DateTime.now();
    final difference = reference.difference(time);

    if (difference.isNegative) return absolute(time, now: reference);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    }
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return absolute(time, now: reference);
  }

  /// A calendar date, dropping the year when it is the current one.
  static String absolute(DateTime? time, {DateTime? now}) {
    if (time == null) return 'Unknown';
    final reference = now ?? DateTime.now();
    final local = time.toLocal();
    return local.year == reference.year
        ? _sameYear.format(local)
        : _otherYear.format(local);
  }
}
