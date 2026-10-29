import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';

/// A file, or a directory without children: what check states count.
bool isCheckLeaf(TreeNode<Object?> node) => switch (node) {
  FileNode<Object?>() => true,
  DirectoryNode<Object?>(:final hasChildren) => !hasChildren,
};

/// Leaf and checked-leaf counts per pre-order index of one tree, from which
/// every check state follows in O(1).
///
/// Not exported: the controller keeps one per tree and checks state.
final class CheckCounts {
  CheckCounts._(this.leaves, this.checked);

  /// Counts every node of [tree] for [checks] in one reverse pre-order
  /// pass: a node's descendants come after it, so they are complete before
  /// they are added to their parent. O(n).
  factory CheckCounts.build(
    DirectoryTree<Object?> tree,
    SelectionState checks,
  ) {
    assert(() {
      debugBuildCount++;
      return true;
    }(), 'counts the builds in debug builds only');
    final nodes = tree.nodes;
    final count = nodes.length;
    final leaves = Int32List(count);
    final checked = Int32List(count);
    for (var i = count - 1; i >= 0; i--) {
      final node = nodes[i];
      if (isCheckLeaf(node)) {
        leaves[i] = 1;
        if (checks.isSelected(node.id)) checked[i] = 1;
      }
      final parent = node.parent;
      if (parent != null) {
        final parentIndex = tree.indexOf(parent);
        leaves[parentIndex] += leaves[i];
        checked[parentIndex] += checked[i];
      }
    }
    return CheckCounts._(leaves, checked);
  }

  /// How many times [CheckCounts.build] ran, in debug builds; tests use it
  /// to tell an incremental update from a full recount.
  @visibleForTesting
  static int debugBuildCount = 0;

  /// The number of leaves in the subtree at each pre-order index.
  final Int32List leaves;

  /// The number of checked leaves in the subtree at each pre-order index.
  final Int32List checked;

  /// The check state of the node at pre-order [index]. O(1).
  CheckState stateAt(int index) {
    final count = checked[index];
    if (count == 0) return CheckState.unchecked;
    return count == leaves[index] ? CheckState.checked : CheckState.partial;
  }

  /// Recounts the subtree at [index] for [checks] and adds the difference
  /// to its ancestors, after a change confined to that subtree.
  ///
  /// Each call recounts its subtree from scratch, so several calls for the
  /// subtrees of one change are correct in any order, nested or not.
  void updateSubtree(
    DirectoryTree<Object?> tree,
    SelectionState checks,
    int index,
  ) {
    final nodes = tree.nodes;
    final root = nodes[index];
    final end = index + tree.subtreeSizeOf(root.id);
    final before = checked[index];
    checked.fillRange(index, end, 0);
    for (var i = end - 1; i >= index; i--) {
      final node = nodes[i];
      if (isCheckLeaf(node) && checks.isSelected(node.id)) checked[i] += 1;
      if (i > index) checked[tree.indexOf(node.parent!)] += checked[i];
    }
    final delta = checked[index] - before;
    if (delta == 0) return;
    for (final ancestor in tree.ancestorsOf(root.id)) {
      checked[tree.indexOf(ancestor.id)] += delta;
    }
  }
}
