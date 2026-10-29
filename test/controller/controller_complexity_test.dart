import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

void main() {
  test('commands on a 100k-node tree touch only the rows that change', () {
    // 1 + 100 + 1000 + 99,000 = 100,101 nodes.
    final tree = DirectoryTree<int>.build([
      for (var a = 0; a < 100; a++)
        for (var b = 0; b < 10; b++)
          for (var c = 0; c < 99; c++)
            TreeEntry<int>.file('/big/d$a/s$b/f$c.txt'),
    ], options: const TreeOptions(roots: TreeRoots.commonAncestor()));
    expect(tree.length, 100101);
    var filterCalls = 0;
    final filter = TreeFilter.where<Object?>((node) {
      filterCalls++;
      return !node.name.endsWith('7.txt');
    });
    final controller = DirectoryTreeController<int>(
      tree: tree,
      expansion: const ExpansionState.expanded(),
      filter: filter,
    );
    expect(filterCalls, tree.length);
    filterCalls = 0;

    final folder = tree.idOf('/big/d50/s5')!;
    final before = controller.rows;
    final index = before.indexOfNode(folder);
    // 99 files, of which the 10 ending in 7 (7, 17, ..., 97) are filtered.
    const visibleFiles = 89;

    controller.collapse(folder);
    final collapsed = controller.rows;
    expect(filterCalls, 0);
    expect(
      controller.lastRowsChange,
      TreeRowsChange.splice(
        previous: before,
        index: index + 1,
        removed: visibleFiles,
        inserted: 0,
      ),
    );
    expect(collapsed.length, before.length - visibleFiles);
    var rebuilt = 0;
    for (var i = 0; i < collapsed.length; i++) {
      final old = i <= index ? before[i] : before[i + visibleFiles];
      if (!identical(collapsed[i], old)) rebuilt++;
    }
    expect(rebuilt, 1, reason: 'only the collapsed row itself is new');

    controller.expand(folder);
    final expanded = controller.rows;
    expect(filterCalls, 0);
    expect(
      controller.lastRowsChange,
      TreeRowsChange.splice(
        previous: collapsed,
        index: index + 1,
        removed: 0,
        inserted: visibleFiles,
      ),
    );
    rebuilt = 0;
    for (var i = 0; i < expanded.length; i++) {
      if (i > index && i <= index + visibleFiles) continue;
      final old = i <= index ? collapsed[i] : collapsed[i - visibleFiles];
      if (!identical(expanded[i], old)) rebuilt++;
    }
    expect(rebuilt, 1, reason: 'only the expanded row itself is new');

    // Focus and selection commands never touch the rows or the filter.
    final viewport = FakeViewport(pageRowCount: 30);
    controller
      ..attachViewport(viewport)
      ..select(folder)
      ..moveFocus(TreeFocusMove.next)
      ..moveFocus(TreeFocusMove.pageDown, selection: TreeSelectionUpdate.extend)
      ..toggleSelected(tree.idOf('/big/d99/s9/f98.txt')!)
      ..focus(tree.idOf('/big/d0')!);
    expect(identical(controller.rows, expanded), isTrue);
    expect(filterCalls, 0);
    expect(controller.selection.length, 32);

    // Checking a folder updates the counts of its subtree and ancestors.
    expect(controller.checkStateOf(folder), CheckState.unchecked);
    controller.toggleChecked(folder);
    expect(controller.checkStateOf(folder), CheckState.checked);
    expect(controller.checkStateOf(tree.idOf('/big/d50')!), CheckState.partial);
    expect(filterCalls, 0);

    // The incremental rows still equal a full flatten.
    expectConsistentRows(controller);
  });
}
