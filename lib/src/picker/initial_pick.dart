// The initial state of a DirectoryTreePicker. This library is not exported
// by the package.
import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';

/// How many state values [revealPicks] and [checkPicks] have built since
/// the last reset; each builds at most one per call, whatever the number of
/// picks. For tests only.
@visibleForTesting
int debugInitialPickStateBuilds = 0;

/// [expansion] with every ancestor of every id of [picks] in [tree]
/// expanded, so that each picked node has a row.
///
/// Walks up from each pick until it meets an ancestor it already collected,
/// so the walk visits every ancestor once: O(picks + ancestors), plus one
/// [ExpansionState.expandAll] (O(ancestors + exceptions)). Revealing the
/// picks one by one would copy the exceptions once per pick instead.
@internal
ExpansionState revealPicks(
  DirectoryTree<Object?> tree,
  Iterable<NodeId> picks,
  ExpansionState expansion,
) {
  final ancestors = <NodeId>{};
  for (final id in picks) {
    var parent = tree[id]?.parent;
    while (parent != null && ancestors.add(parent)) {
      parent = tree[parent]?.parent;
    }
  }
  if (ancestors.isEmpty) return expansion;
  debugInitialPickStateBuilds++;
  return expansion.expandAll(ancestors);
}

/// A multiple-mode check state in which every id of [picks] (an id of
/// [tree]) is checked: the leaves of the picked subtrees, as
/// [SelectionState.check] selects them.
///
/// Sorts the picks by tree index and skips the picks inside an earlier
/// picked subtree, so each node is visited at most once: O(k log k + the
/// size of the picked subtrees) for k picks, and one [SelectionState].
/// Checking the picks one by one would copy the check set once per pick.
@internal
SelectionState checkPicks(DirectoryTree<Object?> tree, Iterable<NodeId> picks) {
  final indices = <int>[
    for (final id in picks)
      if (tree.indexOf(id) case final index when index >= 0) index,
  ]..sort();
  final nodes = tree.nodes;
  final leaves = <NodeId>[];
  var end = -1;
  for (final index in indices) {
    if (index < end) continue;
    end = index + tree.subtreeSizeOf(nodes[index].id);
    for (var i = index; i < end; i++) {
      final node = nodes[i];
      final leaf = switch (node) {
        FileNode<Object?>() => true,
        DirectoryNode<Object?>(:final hasChildren) => !hasChildren,
      };
      if (leaf) leaves.add(node.id);
    }
  }
  debugInitialPickStateBuilds++;
  return SelectionState(mode: SelectionMode.multiple, selected: leaves);
}
