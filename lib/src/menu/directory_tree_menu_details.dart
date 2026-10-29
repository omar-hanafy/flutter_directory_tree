import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/menu/directory_tree_context_menu.dart';

/// Builds the items of the context menu that a [DirectoryTreeContextMenu]
/// opens for a row.
///
/// The builder runs once each time a menu opens, after the row became the
/// selection if it was not selected, and the widgets it returns become the
/// menu's children: usually [MenuItemButton]s, [SubmenuButton]s, and
/// dividers. Read the row and the nodes to act on from `details`; act on
/// [DirectoryTreeMenuDetails.nodes] so that a command applies to the whole
/// selection when the user opened the menu on a selected row.
///
/// Return an empty list to open no menu for this row, for example when no
/// command applies to it. A [MenuItemButton] closes the menu when chosen,
/// and keyboard focus then returns to where it was before the menu opened,
/// before the item's `onPressed` runs.
typedef DirectoryTreeMenuBuilder<T> = List<Widget> Function(
  BuildContext context,
  DirectoryTreeMenuDetails<T> details,
);

/// The row a context menu opened on and the nodes its commands act on,
/// passed to a [DirectoryTreeMenuBuilder].
///
/// [nodes] follows the convention of file managers: when the user opens the
/// menu on a row that is part of the selection, the menu acts on the whole
/// selection (so "Delete" deletes every selected node); on any other row it
/// acts on that row alone. [DirectoryTreeContextMenu] selects a row that was
/// not selected before it builds the menu, unless the controller's
/// `selectable` predicate rejects the row.
///
/// Details are immutable values. Equality compares [controller] by identity
/// and [row], [nodes], and [globalPosition] by value.
@immutable
final class DirectoryTreeMenuDetails<T> {
  /// Creates the details of one context menu.
  ///
  /// [DirectoryTreeContextMenu] creates these when a menu opens; tests and
  /// custom menu hosts may create them too. [nodes] should be unmodifiable,
  /// as the ones the menu host creates are.
  const DirectoryTreeMenuDetails({
    required this.controller,
    required this.row,
    required this.nodes,
    required this.globalPosition,
  });

  /// The controller of the tree.
  ///
  /// Menu items call its commands, for example
  /// [DirectoryTreeController.expandSubtree] for an "Expand all below"
  /// item or [DirectoryTreeController.reloadChildren] for "Refresh".
  final DirectoryTreeController<T> controller;

  /// The row the menu opened on: the row the user right-clicked or
  /// long-pressed, or the focused row when the menu opened from the
  /// keyboard.
  ///
  /// The menu host passes the controller's current row for the node, so
  /// [TreeRow.isExpanded] and [TreeRow.label] describe what the user sees.
  final TreeRow<T> row;

  /// The nodes the menu's commands act on, in pre-order (display order).
  ///
  /// [DirectoryTreeController.selectedNodes] when [row] is selected, which
  /// also holds selected nodes inside collapsed directories; otherwise a
  /// list holding only the node of [row]. Never empty for details that
  /// [DirectoryTreeContextMenu] creates.
  final List<TreeNode<T>> nodes;

  /// Where the menu opened, in global coordinates.
  ///
  /// The pointer position of the right-click or long press that opened it.
  /// For a menu opened from the keyboard, the bottom-start corner of the
  /// focused row (bottom-left in left-to-right text, bottom-right in
  /// right-to-left text), or the center of the [DirectoryTreeContextMenu]
  /// when the row's bounds are unknown.
  final Offset globalPosition;

  /// Whether [other] holds the same controller and equal [row], [nodes],
  /// and [globalPosition].
  ///
  /// [controller] compares by identity. Runs in O(number of nodes) plus the
  /// cost of comparing two rows (see [TreeRow.==]).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryTreeMenuDetails<T> &&
          identical(other.controller, controller) &&
          other.row == row &&
          other.globalPosition == globalPosition &&
          listEquals(other.nodes, nodes);

  /// A hash consistent with [operator ==], in O(number of nodes).
  @override
  int get hashCode => Object.hash(
    identityHashCode(controller),
    row,
    globalPosition,
    Object.hashAll(nodes),
  );

  /// A description with the row label, the number of nodes, and the
  /// position, such as
  /// `DirectoryTreeMenuDetails(lib, nodes: 2, globalPosition: Offset(40.0, 75.0))`.
  @override
  String toString() =>
      'DirectoryTreeMenuDetails(${row.label}, nodes: ${nodes.length}, '
      'globalPosition: $globalPosition)';
}
