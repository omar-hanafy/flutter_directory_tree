// Internal helpers shared by the row widgets and SliverDirectoryTree. This
// library is not exported by the package.
import 'package:flutter/widgets.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

/// Marks the widgets of one row that [SliverDirectoryTree] built and gave
/// its own semantics node (label, flags, and actions).
///
/// [DirectoryTreeRow] checks for it to leave the row label out of the
/// semantics tree inside the sliver, where the row node already carries the
/// label, while keeping the label readable when the row is used elsewhere.
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
/// it (or a widget inside it, such as a rename field) already has focus.
void requestTreeFocus(BuildContext context) {
  final node = Focus.maybeOf(context, createDependency: false);
  if (node == null || node.hasFocus || !node.canRequestFocus) return;
  node.requestFocus();
}
