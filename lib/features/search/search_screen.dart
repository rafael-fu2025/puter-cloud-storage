/// Search across the files this device has seen.
///
/// The hardest thing this screen has to do is be honest about its own limits
/// without sounding broken. Puter offers **no server-side filesystem search**
/// (`docs/puter-api-research.md` §5), so results come from the copy the app
/// keeps on the device and cover only folders that have been opened.
///
/// The previous version said so in the app's own vocabulary — "nothing is
/// indexed yet", "42 indexed entries", "the local index" — which describes the
/// implementation rather than what the user can expect. It now says "saved on
/// this phone", which is both true and understandable.
///
/// It is also the reason search is instant: no request is made at all.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/error_presenter.dart';
import '../../core/format/formatters.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../domain/entities/remote_node.dart';
import '../../domain/entities/remote_path.dart';
import '../browser/browser_providers.dart';
import '../browser/file_actions.dart';
import '../browser/file_browser_screen.dart';

/// Whether search covers one folder or everything saved.
enum SearchScope { everywhere, currentFolder }

/// The current query.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// The current scope.
final searchScopeProvider =
    StateProvider<SearchScope>((ref) => SearchScope.everywhere);

/// Results for the current query.
final searchResultsProvider = FutureProvider<List<RemoteNode>>((ref) async {
  final String query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return const <RemoteNode>[];

  final repository = ref.watch(fileRepositoryProvider);
  if (repository == null) return const <RemoteNode>[];

  final SearchScope scope = ref.watch(searchScopeProvider);
  final String? scopePath = scope == SearchScope.currentFolder
      ? ref.watch(browserPathProvider)
      : null;

  return repository.search(query, scopePath: scopePath);
});

/// How many files are saved on this device — the honest denominator.
final savedFileCountProvider = FutureProvider<int>((ref) async {
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
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String query = ref.watch(searchQueryProvider);
    final AsyncValue<List<RemoteNode>> results =
        ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: TextField(
          controller: _controller,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search your files',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded),
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
      body: Column(
        children: <Widget>[
          // On its own line. Beside the search field it competed for width on
          // a narrow screen and truncated.
          const _ScopeSelector(),
          Expanded(
            child: results.when(
              loading: () => const LoadingState(),
              error: (Object error, StackTrace _) {
                final ErrorPresentation presentation =
                    ErrorPresenter.describe(error);
                return AppErrorView(
                  icon: presentation.icon,
                  title: presentation.title,
                  message: presentation.message,
                  onRetry: () => ref.invalidate(searchResultsProvider),
                );
              },
              data: (List<RemoteNode> nodes) {
                if (query.trim().length < 2) return const _SearchIntro();
                if (nodes.isEmpty) return _NoMatches(query: query);
                return _ResultList(nodes: nodes, query: query);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Where to look, in words rather than in database terms.
class _ScopeSelector extends ConsumerWidget {
  const _ScopeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SearchScope scope = ref.watch(searchScopeProvider);
    final String folder = ref.watch(browserPathProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<SearchScope>(
          segments: <ButtonSegment<SearchScope>>[
            const ButtonSegment<SearchScope>(
              value: SearchScope.everywhere,
              label: Text('Everywhere'),
            ),
            ButtonSegment<SearchScope>(
              value: SearchScope.currentFolder,
              label: Text(
                folder == RemotePath.root
                    ? 'In top level'
                    : 'In ${RemotePath.name(folder)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: <SearchScope>{scope},
          onSelectionChanged: (Set<SearchScope> selection) =>
              ref.read(searchScopeProvider.notifier).state = selection.first,
          showSelectedIcon: false,
        ),
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm,
            AppSpacing.gutter,
            AppSpacing.xs,
          ),
          child: Text(
            '${nodes.length} ${nodes.length == 1 ? 'result' : 'results'}',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: nodes.length,
            separatorBuilder: (BuildContext context, int index) =>
                const AppDivider(),
            itemBuilder: (BuildContext context, int index) {
              final RemoteNode node = nodes[index];
              final String? parent = RemotePath.parent(node.path);
              return AppListRow(
                leading: FileKindIcon(node: node, size: 24),
                title: _Highlighted(text: node.name, query: query),
                subtitle: Text(
                  parent == null || parent == RemotePath.root
                      ? 'Top level'
                      : parent,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: node.isDirectory
                    ? const Icon(Icons.chevron_right_rounded)
                    : Text(
                        ByteFormat.format(node.sizeBytes),
                        style: theme.textTheme.bodySmall,
                      ),
                onTap: () => _reveal(context, ref, node),
                onLongPress: () => FileActions.showDetails(context, ref, node),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Show the hit where it actually lives.
  ///
  /// A folder opens in the browser. A file opens its containing folder and
  /// then its details — rather than the previous behaviour, which silently
  /// overwrote whatever folder the user had open with no way back.
  Future<void> _reveal(
    BuildContext context,
    WidgetRef ref,
    RemoteNode node,
  ) async {
    final String target = node.isDirectory
        ? node.path
        : (RemotePath.parent(node.path) ?? RemotePath.root);

    ref.read(browserPathProvider.notifier).state = target;
    // Switching tabs is what makes the move visible; setting the path alone
    // would relocate a browser the user cannot see.
    ref.read(homeTabProvider.notifier).state = HomeTab.files;

    if (!node.isDirectory) {
      await FileActions.showDetails(context, ref, node);
    }
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
    final int index = text.toLowerCase().indexOf(query.toLowerCase().trim());

    if (index < 0 || query.trim().isEmpty) {
      return Text(text, overflow: TextOverflow.ellipsis);
    }

    final int matchLength = query.trim().length;
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

class _SearchIntro extends ConsumerWidget {
  const _SearchIntro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int saved = ref.watch(savedFileCountProvider).valueOrNull ?? 0;

    return AppEmptyState(
      icon: Icons.search_rounded,
      title: 'Find a file',
      message: saved == 0
          ? 'Nothing is saved on this phone yet. Open a few folders and their '
              'contents become searchable — files are looked up here rather '
              'than on Puter, which is why results appear instantly.'
          : 'Searching the $saved files saved on this phone. Folders you have '
              'not opened yet are not included, so open one to add it.',
    );
  }
}

class _NoMatches extends ConsumerWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SearchScope scope = ref.watch(searchScopeProvider);
    final String folder = ref.watch(browserPathProvider);

    return AppEmptyState(
      icon: Icons.search_off_rounded,
      title: 'Nothing found for “${query.trim()}”',
      message: scope == SearchScope.currentFolder
          ? 'Only searched inside '
              '${folder == RemotePath.root ? 'the top level' : RemotePath.name(folder)}.'
          : 'Only files saved on this phone are searched. Opening the folder a '
              'file lives in adds it.',
      primaryAction: scope == SearchScope.currentFolder
          ? FilledButton.icon(
              onPressed: () =>
                  ref.read(searchScopeProvider.notifier).state =
                      SearchScope.everywhere,
              icon: const Icon(Icons.public_rounded),
              label: const Text('Search everywhere'),
            )
          : FilledButton.icon(
              onPressed: () =>
                  ref.read(homeTabProvider.notifier).state = HomeTab.files,
              icon: const Icon(Icons.folder_rounded),
              label: const Text('Browse folders'),
            ),
    );
  }
}
