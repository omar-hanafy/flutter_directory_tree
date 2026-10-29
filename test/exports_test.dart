// The Flutter libraries apps import next to this package. Referencing every
// exported name below with all of them in scope makes any name clash an
// "ambiguous import" compile error.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every type the barrel exports: the Flutter layer and the re-exported
/// `package:directory_tree` core.
const List<Type> exportedTypes = <Type>[
  // Controller.
  DirectoryTreeController<Object?>,
  TreeRowsChange,
  DirectoryTreeViewport,
  DirectoryChildrenLoader<Object?>,
  DirectoryLoadErrorCallback,
  DirectoryLoadStatus,
  TreeFocusMove,
  TreeSelectionUpdate,
  // Theme and rendering.
  DirectoryTreeGuideStyle,
  DirectoryTreeIconSet,
  DirectoryTreeIndentGuides,
  DirectoryTreeLabel,
  DirectoryTreeTheme,
  DirectoryTreeThemeData,
  // Rows.
  DirectoryTreeCheckboxMode,
  DirectoryTreeRowBuilder<Object?>,
  DirectoryTreeRowDecorator<Object?>,
  DirectoryTreeRowDetails<Object?>,
  DirectoryTreeRow<Object?>,
  DirectoryTreeExpander<Object?>,
  DirectoryTreeCheckbox<Object?>,
  SliverDirectoryTree<Object?>,
  // Keyboard
  DirectoryTreeKeyboard<Object?>,
  DirectoryTreeShortcuts,
  MoveTreeFocusIntent,
  ExpandTreeNodeIntent,
  CollapseTreeNodeIntent,
  ExpandTreeSubtreeIntent,
  ActivateTreeNodeIntent,
  ToggleTreeSelectionIntent,
  SelectAllTreeNodesIntent,
  ClearTreeSelectionIntent,
  OpenTreeContextMenuIntent,
  // Context menu
  DirectoryTreeContextMenu<Object?>,
  DirectoryTreeContextMenuState<Object?>,
  DirectoryTreeMenuBuilder<Object?>,
  DirectoryTreeMenuDetails<Object?>,
  // Drag and drop
  DirectoryTreeDragAndDrop<Object?>,
  DirectoryTreeDragAndDropScope<Object?>,
  DirectoryTreeDropDetails<Object?>,
  // Search and toolbar
  DirectoryTreeSearchField,
  DirectoryTreeToolbar,
  // Core.
  CheckState,
  DirectoryNode<Object?>,
  DirectoryTree<Object?>,
  DirectoryTreeBuilder<Object?>,
  ExpansionState,
  FileNode<Object?>,
  ListDiff,
  NodeComparator,
  NodeId,
  PathPolicy,
  SelectionMode,
  SelectionState,
  TreeDiff,
  TreeEntry<Object?>,
  TreeFilter,
  TreeIssue<Object?>,
  TreeIssueKind,
  TreeNode<Object?>,
  TreeNodeKind,
  TreeOptions,
  TreeOrder,
  TreePath,
  TreeQuery,
  TreeRoots,
  TreeRow<Object?>,
  TreeRows<Object?>,
  TreeStyle,
];

void main() {
  test('exports every name without a clash', () {
    expect(exportedTypes.toSet(), hasLength(exportedTypes.length));
    // The Flutter libraries stay usable in the same file.
    expect(Colors.transparent, isA<Color>());
    expect(CupertinoColors.white, isA<Color>());
    expect(LogicalKeyboardKey.enter, isA<LogicalKeyboardKey>());
  });

  test('re-exports the directory_tree core', () {
    final tree = DirectoryTree.fromPaths(['/repo/lib/main.dart']);
    expect(tree.fileCount, 1);
  });

  test('the controller works through the barrel', () {
    final controller = DirectoryTreeController(
      tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/README.md']),
      showRoots: false,
    );
    addTearDown(controller.dispose);
    expect(controller.showRoots, isFalse);
    expect(controller.rows.map((row) => row.label), ['lib', 'README.md']);
    expect(controller.moveFocus(TreeFocusMove.last), isTrue);
    expect(controller.selection.selected, {
      controller.tree.idOf('/repo/README.md'),
    });
    expect(controller.lastRowsChange.isReset, isTrue);
    expect(
      controller.loadStatusOf(controller.tree.roots.single),
      DirectoryLoadStatus.loaded,
    );
  });
}
