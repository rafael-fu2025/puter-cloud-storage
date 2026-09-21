/// The one place sorting is chosen.
///
/// The same preference used to be set through two unrelated controls: a popup
/// menu in the browser with hand-rolled checkmarks and a "reverse order" row,
/// and a radio-style dialog in Settings. Two idioms for one setting is the kind
/// of inconsistency that makes an app feel unfinished, so both now open this.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/entities/remote_node.dart';
import 'browser_providers.dart';

/// Choose how the current folder is ordered.
Future<void> showSortSheet(
  BuildContext context,
  WidgetRef ref,
  BrowserPreferences preferences,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) {
      // A local mirror so the sheet reflects each tap immediately, without
      // waiting for the preference write to round-trip.
      var current = preferences;

      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          void apply(BrowserPreferences next) {
            setSheetState(() => current = next);
            ref.read(browserPreferencesProvider.notifier).apply(
                  (BrowserPreferences _) => next,
                );
          }

          return AppSheet(
            title: 'Sort by',
            children: <Widget>[
              for (final NodeSortField field in NodeSortField.values)
                AppListRow(
                  title: Text(sortFieldLabel(field)),
                  leading: Icon(
                    field == current.sortField
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: field == current.sortField
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onTap: () => apply(current.copyWith(sortField: field)),
                ),
              const AppDivider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SegmentedButton<SortOrder>(
                        segments: const <ButtonSegment<SortOrder>>[
                          ButtonSegment<SortOrder>(
                            value: SortOrder.ascending,
                            icon: Icon(Icons.arrow_upward_rounded, size: 18),
                            label: Text('A–Z'),
                          ),
                          ButtonSegment<SortOrder>(
                            value: SortOrder.descending,
                            icon: Icon(Icons.arrow_downward_rounded, size: 18),
                            label: Text('Z–A'),
                          ),
                        ],
                        selected: <SortOrder>{current.sortOrder},
                        onSelectionChanged: (Set<SortOrder> selection) =>
                            apply(current.copyWith(sortOrder: selection.first)),
                        showSelectedIcon: false,
                      ),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                value: current.foldersFirst,
                onChanged: (bool value) =>
                    apply(current.copyWith(foldersFirst: value)),
                title: const Text('Folders first'),
                subtitle: const Text('Keep folders at the top of the list'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
