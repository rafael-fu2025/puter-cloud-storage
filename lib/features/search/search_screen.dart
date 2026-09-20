/// Search over the local index.
///
/// The single most important thing this screen does is tell the truth about
/// what it searched. Puter has **no server-side filesystem search**
/// (`docs/puter-api-research.md` §5), so results come from the local index and
/// cover only folders the app has already visited. A search box that silently
/// returns nothing for a file that exists is worse than one that says "I have
/// not indexed that folder yet".
///
/// It is also the reason search is instant: no request is made at all, which is
/// the exit criterion Phase 4 sets — results in under 200 ms with no network
/// call.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/format/file_kinds.dart';
import '../../core/format/formatters.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import '../browser/browser_providers.dart';
import '../browser/file_actions.dart';

/// Whether search covers one folder or everything indexed.
enum SearchScope { everywhere, currentFolder }

/// The current query.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// The current scope.
final searchScopeProvider =
    StateProvider<SearchScope>((ref) => SearchScope.everywhere);

/// Results for the current query.
final searchResultsProvider = FutureProvider<List<RemoteNode>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return const <RemoteNode>[];

  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return const <RemoteNode>[];

  final scope = ref.watch(searchScopeProvider);
  final scopePath =
      scope == SearchScope.currentFolder ? ref.watch(browserPathProvider) : null;

  return repository.search(query, scopePath: scopePath);
});

/// How many entries the index holds — the denominator for "searched N files".
final indexedCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return 0;
  return repository.cacheSize();
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced so a fast typist does not re-query on every keystroke.
  ///
  /// The query itself is local and cheap, but rebuilding the whole result list
  /// per character makes the field stutter on a large index.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);
    final indexed = ref.watch(indexedCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search indexed files',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              _debounce?.cancel();
                              ref.read(searchQueryProvider.notifier).state = '';
                            },
                          ),
                  ),
                ),
              ),
              _ScopeSelector(indexed: indexed),
            ],
          ),
        ),
      ),
      body: results.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => _SearchMessage(
          icon: ErrorPresenter.describe(error).icon,
          title: ErrorPresenter.describe(error).title,
          body: ErrorPresenter.describe(error).message,
          isError: true,
        ),
        data: (List<RemoteNode> nodes) {
          if (query.trim().length < 2) return _SearchIntro(indexed: indexed);
          if (nodes.isEmpty) return _NoMatches(query: query, indexed: indexed);
          return _ResultList(nodes: nodes, query: query);
        },
      ),
    );
  }
}

/// Scope toggle, with the count that makes its limits concrete.
class _ScopeSelector extends ConsumerWidget {
  const _ScopeSelector({required this.indexed});

  final int indexed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(searchScopeProvider);
    final theme = Theme.of(context);
    final folder = ref.watch(browserPathProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SegmentedButton<SearchScope>(
              segments: <ButtonSegment<SearchScope>>[
                const ButtonSegment<SearchScope>(
                  value: SearchScope.everywhere,
                  label: Text('Everything'),
                ),
                ButtonSegment<SearchScope>(
                  value: SearchScope.currentFolder,
                  label: Text(
                    folder == RemotePath.root ? 'In Home' : 'In ${RemotePath.name(folder)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: <SearchScope>{scope},
              onSelectionChanged: (Set<SearchScope> selection) => ref
                  .read(searchScopeProvider.notifier)
                  .state = selection.first,
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'Entries in the local index',
            child: Text(
              '$indexed indexed',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultList extends ConsumerWidget {
  const _ResultList({required this.nodes, required this.query});

  final List<RemoteNode> nodes;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${nodes.length} match${nodes.length == 1 ? '' : 'es'} in the local '
            'index',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: nodes.length,
            itemBuilder: (BuildContext context, int index) {
              final node = nodes[index];
              final parent = RemotePath.parent(node.path);
              return ListTile(
                leading: _ResultIcon(node: node),
                title: _Highlighted(text: node.name, query: query),
                subtitle: Text(
                  parent == null || parent == RemotePath.root
                      ? 'Home'
                      : parent,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: node.isDirectory
                    ? const Icon(Icons.chevron_right)
                    : Text(
                        ByteFormat.format(node.sizeBytes),
                        style: theme.textTheme.bodySmall,
                      ),
                onTap: () => _open(context, ref, node),
                onLongPress: () => FileActions.showDetails(context, ref, node),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Reveal the hit in place.
  ///
  /// A folder navigates the browser to it; a file navigates to its containing
  /// folder, since the browser has no single-file view and pretending otherwise
  /// would be a dead end.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final target = node.isDirectory
        ? node.path
        : (RemotePath.parent(node.path) ?? RemotePath.root);

    ref.read(browserPathProvider.notifier).state = target;
    // Switching tabs is what makes the navigation visible; setting the path
    // alone would move a browser the user cannot see.
    ref.read(homeTabProvider.notifier).state = HomeTab.files;

    if (!node.isDirectory && context.mounted) {
      await FileActions.showDetails(context, ref, node);
    }
  }
}

class _ResultIcon extends StatelessWidget {
  const _ResultIcon({required this.node});

  final RemoteNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = FileKinds.of(node.name, isDirectory: node.isDirectory);
    return Icon(
      FileKinds.iconFor(category),
      color: FileKinds.tintFor(category, scheme),
    );
  }
}

/// A name with the matched run emphasised.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = text.toLowerCase().indexOf(query.toLowerCase().trim());

    if (index < 0 || query.trim().isEmpty) {
      return Text(text, overflow: TextOverflow.ellipsis);
    }

    final matchLength = query.trim().length;
    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + matchLength),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          TextSpan(text: text.substring(index + matchLength)),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SearchIntro extends StatelessWidget {
  const _SearchIntro({required this.indexed});

  final int indexed;

  @override
  Widget build(BuildContext context) {
    return _SearchMessage(
      icon: Icons.search,
      title: 'Search your Puter files',
      body: indexed == 0
          ? 'Nothing is indexed yet. Browse a few folders and they become '
              'searchable — Puter offers no server-side search, so this app '
              'searches the copy it keeps on your device.'
          : 'Typing searches the $indexed entries this app has indexed so far. '
              'Folders you have not opened yet are not included.',
    );
  }
}

class _NoMatches extends ConsumerWidget {
  const _NoMatches({required this.query, required this.indexed});

  final String query;
  final int indexed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(searchScopeProvider);
    final folder = ref.watch(browserPathProvider);

    final explanation = scope == SearchScope.currentFolder
        ? 'Searching only in '
            '${folder == RemotePath.root ? 'Home' : RemotePath.name(folder)}. '
            'Switch to “Everything” to search all $indexed indexed entries.'
        : 'Searched all $indexed indexed entries. A folder you have not opened '
            'yet is not indexed, and will not match.';

    return _SearchMessage(
      icon: Icons.search_off,
      title: 'No matches for “${query.trim()}”',
      body: explanation,
      action: scope == SearchScope.currentFolder
          ? FilledButton.icon(
              onPressed: () => ref.read(searchScopeProvider.notifier).state =
                  SearchScope.everywhere,
              icon: const Icon(Icons.public),
              label: const Text('Search everything'),
            )
          : null,
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 56,
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
