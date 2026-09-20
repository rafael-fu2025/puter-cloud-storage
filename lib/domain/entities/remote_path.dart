/// POSIX path arithmetic for remote paths.
///
/// Deliberately not `package:path`. That package resolves against the *host*
/// platform, so on Windows it would produce `\Documents\a.txt` for a path that
/// is sent verbatim to Puter. Remote paths are always POSIX, so the rules are
/// written out here once rather than being re-derived (and re-broken) at every
/// call site.
///
/// Every function is pure and total: bad input yields a sane root rather than
/// an exception, because these run inside list builders where a throw would
/// take out a whole frame.
library;

abstract final class RemotePath {
  /// The filesystem root.
  static const String root = '/';

  /// Collapse duplicate and trailing separators. `//a//b/` → `/a/b`.
  static String normalise(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return root;
    final segments = trimmed.split('/').where((s) => s.isNotEmpty);
    final joined = segments.join('/');
    return joined.isEmpty ? root : '/$joined';
  }

  /// Join a parent path and a child name.
  static String join(String parent, String child) {
    if (child.isEmpty) return normalise(parent);
    if (child.startsWith('/')) return normalise(child);
    final base = normalise(parent);
    return base == root ? '/$child' : '$base/$child';
  }

  /// The containing directory, or `null` at the root.
  static String? parent(String path) {
    final normalised = normalise(path);
    if (normalised == root) return null;
    final index = normalised.lastIndexOf('/');
    return index <= 0 ? root : normalised.substring(0, index);
  }

  /// The final segment. `'/'` for the root.
  static String name(String path) {
    final normalised = normalise(path);
    if (normalised == root) return root;
    return normalised.substring(normalised.lastIndexOf('/') + 1);
  }

  /// Whether [child] is [ancestor] itself or sits beneath it.
  ///
  /// Used to reject a move into a node's own subtree, which the server would
  /// either refuse or, worse, execute destructively.
  static bool isWithin(String ancestor, String child) {
    final a = normalise(ancestor);
    final c = normalise(child);
    if (a == c) return true;
    if (a == root) return true;
    return c.startsWith('$a/');
  }

  /// Root-first segments of [path], excluding the root itself.
  ///
  /// `/a/b` → `['a', 'b']`. Drives breadcrumb construction.
  static List<String> segments(String path) => normalise(path)
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  /// Breadcrumb pairs from the root down to [path].
  ///
  /// Each entry is the display label and the absolute path it navigates to.
  static List<({String label, String path})> breadcrumbs(String path) {
    final result = <({String label, String path})>[
      (label: 'Home', path: root),
    ];
    var current = '';
    for (final segment in segments(path)) {
      current = '$current/$segment';
      result.add((label: segment, path: current));
    }
    return result;
  }
}
