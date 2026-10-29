// Internal helpers shared by the row widgets and SliverDirectoryTree. This
// library is not exported by the package.
import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/widgets.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/directory_tree_checkbox.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_expander.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

/// Marks the widgets of one row that [SliverDirectoryTree] built and gave
/// its own semantics node (label, flags, and actions).
///
/// [DirectoryTreeRow] checks for it to leave the row label out of the
/// semantics tree inside the sliver, where the row node already carries the
/// label, while keeping the label readable when the row is used elsewhere.
/// [DirectoryTreeExpander] and [DirectoryTreeCheckbox] check for it to add
/// no node of their own, since the row node carries their state and
/// actions.
class RowSemanticsScope extends InheritedWidget {
  /// Marks [child] as the content of a row with sliver-provided semantics.
  const RowSemanticsScope({super.key, required super.child});

  /// Whether [context] is inside a row of [SliverDirectoryTree].
  ///
  /// Registers no dependency: the answer never changes for a mounted
  /// element.
  static bool isInside(BuildContext context) =>
      context.getInheritedWidgetOfExactType<RowSemanticsScope>() != null;

  @override
  bool updateShouldNotify(RowSemanticsScope oldWidget) => false;
}

/// Gives keyboard focus to the tree that contains [context], as a click on
/// a desktop tree does.
///
/// The tree is the nearest [Focus] above [context] that is not a
/// [FocusScope], usually the focus node of the tree's keyboard handling.
/// Nothing happens when there is none, when it cannot take focus, or when
/// it has the primary focus already. A focusable widget inside a row (a
/// button, a rename field) that has the focus loses it to the tree, so
/// the tree's keys act and the rows paint as focused; a click inside such
/// a widget is that widget's own and does not reach the row.
void requestTreeFocus(BuildContext context) {
  final node = Focus.maybeOf(context, createDependency: false);
  if (node == null || node.hasPrimaryFocus || !node.canRequestFocus) return;
  node.requestFocus();
}

/// Whether the checkbox of the row [details] describes can be clicked: in
/// [DirectoryTreeCheckboxMode.checks] when the node is checked (unchecking
/// is always allowed) or [SelectionState.canCheck] accepts it, in
/// [DirectoryTreeCheckboxMode.selection] when the row is selectable, and
/// never in [DirectoryTreeCheckboxMode.none].
bool canToggleCheckbox<T>(DirectoryTreeRowDetails<T> details) {
  final controller = details.controller;
  final id = details.row.id;
  return switch (details.checkboxMode) {
    DirectoryTreeCheckboxMode.none => false,
    DirectoryTreeCheckboxMode.checks =>
      details.checkState == CheckState.checked ||
          controller.checks.canCheck(controller.tree, id),
    DirectoryTreeCheckboxMode.selection => controller.isSelectable(id),
  };
}

/// What a click on the checkbox of the row [details] describes does: gives
/// the tree keyboard focus, then toggles the node's check (and focuses the
/// row) or the row's selection, for the checkbox mode.
void toggleCheckbox<T>(
  BuildContext context,
  DirectoryTreeRowDetails<T> details,
) {
  final controller = details.controller;
  final id = details.row.id;
  requestTreeFocus(context);
  switch (details.checkboxMode) {
    case DirectoryTreeCheckboxMode.checks:
      controller
        ..toggleChecked(id)
        ..focus(id);
    case DirectoryTreeCheckboxMode.selection:
      controller.toggleSelected(id);
    case DirectoryTreeCheckboxMode.none:
      break;
  }
}
