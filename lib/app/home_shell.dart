/// The signed-in shell: four destinations over one persistent state.
///
/// `IndexedStack` rather than swapping widgets, so switching tabs does not
/// throw away a folder the user was three levels deep into, and does not
/// re-issue the requests that got them there. Against a shared 600
/// requests/min ceiling, preserving a rendered list is worth more than the
/// memory it costs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/browser/file_browser_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transfers/transfer_screen.dart';
import 'providers.dart';

/// The bottom-navigation shell.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    final transfers = ref.watch(transfersProvider).valueOrNull ?? const [];

    // Only unfinished work earns a badge. A count that includes completed
    // transfers would sit there permanently and mean nothing.
    final pending =
        transfers.where((task) => !task.isFinished).length;

    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const <Widget>[
          FileBrowserScreen(),
          TransferScreen(),
          SearchScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (int index) =>
            ref.read(homeTabProvider.notifier).state = HomeTab.values[index],
        destinations: <Widget>[
          const NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.swap_vert_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.swap_vert),
            ),
            label: 'Transfers',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
