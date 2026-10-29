import 'dart:math' as math;

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_directory_tree/src/widgets/row_scope.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

/// The checkbox of a row, for [DirectoryTreeRowDetails.checkboxMode].
///
/// [DirectoryTreeRow] shows one between the expander and the icon; use it
/// in a custom row to keep the standard behavior:
///
/// * [DirectoryTreeCheckboxMode.checks]: a tri-state Material [Checkbox]
///   showing [DirectoryTreeRowDetails.checkState], so a directory with some
///   checked leaves shows a dash. A click calls
///   [DirectoryTreeController.toggleChecked]: a partial or unchecked node
///   becomes checked with its whole subtree, a checked one unchecked. An
///   unchecked or partial box that [SelectionState.canCheck] rejects is
///   disabled: in [SelectionMode.single], a directory with more than one
///   leaf below it.
/// * [DirectoryTreeCheckboxMode.selection]: a two-state checkbox that
///   mirrors [DirectoryTreeRowDetails.isSelected]. A click calls
///   [DirectoryTreeController.toggleSelected] for this row only, so a
///   directory never selects its children. Rows that
///   [DirectoryTreeController.isSelectable] rejects show a disabled box.
/// * [DirectoryTreeCheckboxMode.none]: nothing (an empty box of no size).
///
/// A click also moves the controller's focus to the row and gives the tree
/// keyboard focus, but never selects the row in checks mode or activates
/// it: the click does not reach the row's own click handling. The checkbox
/// takes no keyboard focus of its own (the tree's keys toggle it). It is a
/// square of [DirectoryTreeThemeData.expanderSize] and brings its own
/// transparent [Material], so it works without a [Scaffold] around the
/// tree.
///
/// Inside a [SliverDirectoryTree] the checkbox adds nothing to the
/// semantics tree: the row's node already reports the checked or mixed
/// state, and its tap action toggles the box. Elsewhere it is a checkbox
/// labeled with [TreeRow.label].
class DirectoryTreeCheckbox<T> extends StatelessWidget {
  /// Creates the checkbox of the row described by [details].
  const DirectoryTreeCheckbox({super.key, required this.details});

  /// The row this checkbox belongs to.
  final DirectoryTreeRowDetails<T> details;

  @override
  Widget build(BuildContext context) {
    final mode = details.checkboxMode;
    if (mode == DirectoryTreeCheckboxMode.none) return const SizedBox.shrink();
    final theme = DirectoryTreeTheme.of(context);
    final size = math.max(0.0, theme.expanderSize!);
    final state =
        details.checkState ??
        (details.isSelected ? CheckState.checked : CheckState.unchecked);
    final tristate = mode == DirectoryTreeCheckboxMode.checks;
    final bool? value = switch (state) {
      CheckState.checked => true,
      // A two-state checkbox has no third value; partial only exists for
      // directories in checks mode.
      CheckState.partial => tristate ? null : false,
      CheckState.unchecked => false,
    };
    final enabled = canToggleCheckbox(details);
    Widget checkbox = Checkbox(
      value: value,
      tristate: tristate,
      onChanged: enabled ? (_) => toggleCheckbox(context, details) : null,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      splashRadius: size / 2,
    );
    // In a sliver row the row's node is the checkbox for screen readers; a
    // second, smaller node would repeat the state without a label.
    checkbox = RowSemanticsScope.isInside(context)
        ? ExcludeSemantics(child: checkbox)
        : MergeSemantics(
            child: Semantics(label: details.row.label, child: checkbox),
          );
    return ExcludeFocus(
      child: SizedBox.square(
        dimension: size,
        child: Material(type: MaterialType.transparency, child: checkbox),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<DirectoryTreeRowDetails<T>>('details', details),
    );
  }
}
