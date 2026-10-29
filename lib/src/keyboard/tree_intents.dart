// Imported only so documentation references resolve.
import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';

/// An intent to move the keyboard focus of a tree view to another row, as
/// an arrow, Home, End, or Page key does, and then update the selection.
///
/// [DirectoryTreeKeyboard] handles it with
/// [DirectoryTreeController.moveFocus], passing [move] and [selection]. The
/// page moves go by the page size of the controller: the largest
/// [DirectoryTreeViewport.pageRowCount] among the attached views, or 10
/// without one. The action is always enabled, so a move at the first or
/// last row consumes its key and changes nothing: arrow keys never move the
/// keyboard focus out of the tree.
///
/// [DirectoryTreeShortcuts.defaults] binds it to Up, Down, Home, End,
/// PageUp, and PageDown (Shift extends the selection, Ctrl keeps it on
/// platforms other than macOS and iOS), and on macOS and iOS to Cmd+Up for
/// [TreeFocusMove.parent].
class MoveTreeFocusIntent extends Intent {
  /// Creates an intent that moves the focus by [move] and then updates the
  /// selection as [selection] says (by default, the newly focused row
  /// becomes the selection).
  const MoveTreeFocusIntent(
    this.move, {
    this.selection = TreeSelectionUpdate.replace,
  });

  /// Where the focus goes, relative to the focused row.
  ///
  /// With no row focused, [TreeFocusMove.last] and [TreeFocusMove.previous]
  /// go to the last row and every other move goes to the first row.
  final TreeFocusMove move;

  /// What happens to the selection when the focus moved.
  ///
  /// [TreeSelectionUpdate.replace] selects the new row alone,
  /// [TreeSelectionUpdate.extend] selects the range from the anchor to it,
  /// and [TreeSelectionUpdate.keep] leaves the selection alone. Nothing
  /// changes when the focus did not move.
  final TreeSelectionUpdate selection;

  /// Whether [other] is a [MoveTreeFocusIntent] with the same [move] and
  /// [selection].
  @override
  bool operator ==(Object other) =>
      other is MoveTreeFocusIntent &&
      other.runtimeType == runtimeType &&
      other.move == move &&
      other.selection == selection;

  /// A hash of [move] and [selection].
  @override
  int get hashCode => Object.hash(runtimeType, move, selection);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<TreeFocusMove>('move', move))
      ..add(EnumProperty<TreeSelectionUpdate>('selection', selection));
  }
}

/// An intent to expand the focused row, or to step into it when it is
/// expanded already (the right arrow in a left-to-right layout).
///
/// [DirectoryTreeKeyboard] handles it on [DirectoryTreeController.focusedRow]:
///
/// * A collapsed row that [DirectoryTreeController.isExpandable] accepts
///   expands with [DirectoryTreeController.expand], which starts loading a
///   lazily loaded directory whose children are not loaded yet.
/// * An expanded row moves the focus to its first child row and selects it,
///   with [TreeFocusMove.firstChild].
/// * An expanded row without child rows whose lazy load never ran (as
///   after [DirectoryTreeController.expandAll]) or failed is expanded
///   again, which starts that load.
/// * Anything else (a file, an empty directory, no focused row) changes
///   nothing.
///
/// The action is always enabled, so the key is consumed even when nothing
/// changes. [DirectoryTreeShortcuts.defaults] binds it to the right arrow
/// (the left arrow in right-to-left layouts) and NumpadAdd.
class ExpandTreeNodeIntent extends Intent {
  /// Creates an intent that expands the focused row or moves into it.
  const ExpandTreeNodeIntent();
}

/// An intent to collapse the focused row, or to step out of it when it is
/// collapsed already (the left arrow in a left-to-right layout).
///
/// [DirectoryTreeKeyboard] handles it on [DirectoryTreeController.focusedRow]:
/// an expanded row ([TreeRow.isExpanded]) collapses with
/// [DirectoryTreeController.collapse]; any other row moves the focus to its
/// parent row and selects it, with [TreeFocusMove.parent]; a top-level row
/// stays where it is.
///
/// The action is always enabled, so the key is consumed even when nothing
/// changes. [DirectoryTreeShortcuts.defaults] binds it to the left arrow
/// (the right arrow in right-to-left layouts) and NumpadSubtract.
class CollapseTreeNodeIntent extends Intent {
  /// Creates an intent that collapses the focused row or moves to its
  /// parent row.
  const CollapseTreeNodeIntent();
}

/// An intent to expand the focused directory and every directory below it.
///
/// [DirectoryTreeKeyboard] handles it with
/// [DirectoryTreeController.expandSubtree] on the focused row, which starts
/// no lazy loads; a focused file changes nothing. The action is enabled
/// while a row is focused. [DirectoryTreeShortcuts.defaults] binds it to
/// the `*` character and NumpadMultiply.
class ExpandTreeSubtreeIntent extends Intent {
  /// Creates an intent that expands the focused row's whole subtree.
  const ExpandTreeSubtreeIntent();
}

/// An intent to activate the focused row, as Enter does.
///
/// [DirectoryTreeKeyboard] handles it on [DirectoryTreeController.focusedRow]:
/// a directory first toggles with [DirectoryTreeController.toggleExpansion],
/// then [DirectoryTreeKeyboard.onActivate] (when given) is called with the
/// row, for files and directories alike. So without `onActivate` a file
/// does nothing. The action is enabled while a row is focused, so with
/// nothing focused Enter reaches the widgets above the tree.
///
/// [DirectoryTreeShortcuts.defaults] binds it to Enter and NumpadEnter, and
/// on macOS and iOS also to Cmd+Down.
class ActivateTreeNodeIntent extends Intent {
  /// Creates an intent that activates the focused row.
  const ActivateTreeNodeIntent();
}

/// An intent to toggle the focused row's selection, or its checkbox in
/// [DirectoryTreeCheckboxMode.checks] mode, as Space does.
///
/// [DirectoryTreeKeyboard] handles it on the focused row: with
/// [DirectoryTreeKeyboard.checkboxMode] set to
/// [DirectoryTreeCheckboxMode.checks] it calls
/// [DirectoryTreeController.toggleChecked]; otherwise, in
/// [SelectionMode.multiple] it calls [DirectoryTreeController.toggleSelected]
/// and in [SelectionMode.single] [DirectoryTreeController.select]. The
/// action is enabled while a row is focused.
///
/// [DirectoryTreeShortcuts.defaults] binds it to Space and Ctrl+Space.
/// While a type-ahead search is in progress, Space belongs to the search
/// instead (see [DirectoryTreeKeyboard.typeAhead]).
class ToggleTreeSelectionIntent extends Intent {
  /// Creates an intent that toggles the focused row's selection or check.
  const ToggleTreeSelectionIntent();
}

/// An intent to select every visible row.
///
/// [DirectoryTreeKeyboard] handles it with
/// [DirectoryTreeController.selectAll]. The action is enabled only in
/// [SelectionMode.multiple], so in single mode the key reaches the widgets
/// above the tree. [DirectoryTreeShortcuts.defaults] binds it to Ctrl+A, and
/// to Cmd+A on macOS and iOS.
class SelectAllTreeNodesIntent extends Intent {
  /// Creates an intent that selects every visible row.
  const SelectAllTreeNodesIntent();
}

/// An intent to clear the selection, as Escape does.
///
/// [DirectoryTreeKeyboard] handles it with
/// [DirectoryTreeController.clearSelection]. The action is enabled only
/// while the selection is not empty, so a second Escape reaches the widgets
/// above the tree, for example to close the dialog that shows it.
/// [DirectoryTreeShortcuts.defaults] binds it to Escape.
class ClearTreeSelectionIntent extends Intent {
  /// Creates an intent that clears the selection.
  const ClearTreeSelectionIntent();
}

/// An intent to open the context menu of the focused row, as Shift+F10 and
/// the context menu key do.
///
/// [DirectoryTreeKeyboard] has no action for it: the context menu host
/// (`DirectoryTreeContextMenu`) registers one in an [Actions] widget above
/// the keyboard widget, which opens the menu of the focused row. Without
/// such an action the key does nothing and is not consumed.
/// [DirectoryTreeShortcuts.defaults] binds it to Shift+F10 and the context
/// menu key.
class OpenTreeContextMenuIntent extends Intent {
  /// Creates an intent that opens the focused row's context menu.
  const OpenTreeContextMenuIntent();
}
