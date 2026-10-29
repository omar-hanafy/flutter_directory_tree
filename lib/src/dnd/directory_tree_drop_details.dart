import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';

/// A drop of tree nodes on a directory: which nodes the user dragged and
/// the directory they released them on.
///
/// A `DirectoryTreeDragAndDropScope` creates one for every drop the user
/// makes, asks the `canDrop` callback of `DirectoryTreeDragAndDrop` about
/// it while the pointer hovers over the target, and passes it to `onDrop`
/// when the pointer is released. The package never changes the tree: move
/// the data in your `onDrop` handler, then give the controller the new tree.
///
/// Create your own instances to test drop handlers.
@immutable
final class DirectoryTreeDropDetails<T> {
  /// Creates the details of a drop of [nodes] on [target].
  const DirectoryTreeDropDetails({required this.nodes, required this.target});

  /// The dragged nodes in pre-order (display order), with no node inside
  /// another node of the list.
  ///
  /// When the user dragged a selected row this is the selection, including
  /// selected nodes that have no row (inside collapsed directories or hidden
  /// by a search), but without the selected nodes that lie inside another
  /// selected directory: moving the directory moves them. Otherwise it is
  /// only the dragged row's node. Never empty when a drag and drop scope
  /// creates it, and unmodifiable.
  final List<TreeNode<T>> nodes;

  /// The directory that receives [nodes].
  ///
  /// The directory of the row under the pointer, or the parent directory of
  /// the file row under the pointer. For a compacted row (such as
  /// `lib/src/utils`) it is the row's deepest directory.
  final DirectoryNode<T> target;

  /// Whether [other] drops equal nodes, in the same order, on an equal
  /// target.
  ///
  /// Nodes compare with [TreeNode.operator ==], so details built from two
  /// versions of a tree are equal only where those nodes are. Runs in
  /// O(nodes).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryTreeDropDetails<T> &&
          other.target == target &&
          listEquals(other.nodes, nodes);

  /// A hash consistent with [operator ==]. Runs in O(nodes).
  @override
  int get hashCode => Object.hash(target, Object.hashAll(nodes));

  /// A description with the target path and up to three node paths, such as
  /// `DirectoryTreeDropDetails(2 nodes: /repo/a.txt, /repo/b.txt -> /repo/lib)`.
  @override
  String toString() {
    const shown = 3;
    final paths = nodes.take(shown).map((node) => node.path).join(', ');
    final more = nodes.length > shown ? ', ...' : '';
    final noun = nodes.length == 1 ? 'node' : 'nodes';
    return 'DirectoryTreeDropDetails(${nodes.length} $noun: $paths$more '
        '-> ${target.path})';
  }
}
