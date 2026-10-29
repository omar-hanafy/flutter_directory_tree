import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/controller/check_counts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

DirectoryTreeController<int> expandedController({
  bool Function(TreeNode<int> node)? selectable,
  SelectionState checks = const SelectionState.empty(
    mode: SelectionMode.multiple,
  ),
}) => DirectoryTreeController<int>(
  tree: sampleTree(),
  expansion: const ExpansionState.expanded(),
  selectable: selectable,
  checks: checks,
);

void main() {
  // Expanded rows of the sample tree:
  // 0 repo, 1 lib, 2 src, 3 a.dart, 4 b.dart, 5 main.dart, 6 test,
  // 7 main_test.dart, 8 README.md
  group('selection', () {
    test('select replaces the selection, sets the anchor, and focuses', () {
      final viewport = FakeViewport();
      final controller = expandedController()..attachViewport(viewport);
      expect(notificationsOf(controller, () => controller.select(aDart)), 1);
      expect(controller.selection.selected, {aDart});
      expect(controller.selection.anchor, aDart);
      expect(controller.focusedId, aDart);
      expect(viewport.shown.single.index, 3);
      expect(viewport.shown.single.alignment, isNull);
      expect(notificationsOf(controller, () => controller.select(aDart)), 0);
      controller.select(readme, focus: false);
      expect(controller.selection.selected, {readme});
      expect(controller.focusedId, aDart);
    });

    test('select ignores unknown ids and selects hidden nodes', () {
      final controller = DirectoryTreeController<int>(tree: sampleTree());
      expect(notificationsOf(controller, () => controller.select(unknown)), 0);
      controller.select(aDart);
      expect(controller.selection.selected, {aDart});
      expect(controller.focusedId, isNull);
    });

    test('an unselectable node takes the focus but not the selection', () {
      final controller = expandedController(selectable: (node) => node.isFile)
        ..select(aDart);
      expect(controller.isSelectable(lib), isFalse);
      expect(controller.isSelectable(aDart), isTrue);
      expect(controller.isSelectable(unknown), isFalse);
      controller.select(lib);
      expect(controller.selection.selected, {aDart});
      expect(controller.focusedId, lib);
      controller.toggleSelected(lib);
      expect(controller.selection.selected, {aDart});
      controller.extendSelection(src);
      expect(controller.selection.selected, {aDart});
    });

    test('toggleSelected adds and removes in multiple mode', () {
      final controller = expandedController()
        ..select(aDart)
        ..toggleSelected(mainDart);
      expect(controller.selection.selected, {aDart, mainDart});
      expect(controller.selection.anchor, mainDart);
      expect(controller.focusedId, mainDart);
      controller.toggleSelected(aDart, focus: false);
      expect(controller.selection.selected, {mainDart});
      expect(controller.selection.anchor, aDart);
      expect(controller.focusedId, mainDart);
    });

    test('toggleSelected in single mode replaces or clears', () {
      final controller = expandedController()
        ..selectionMode = SelectionMode.single
        ..toggleSelected(aDart)
        ..toggleSelected(bDart);
      expect(controller.selection.selected, {bDart});
      controller.toggleSelected(bDart);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('extendSelection selects the visible range from the anchor', () {
      final controller = expandedController()
        ..select(bDart)
        ..extendSelection(mainTest);
      expect(controller.selection.selected, {
        bDart,
        mainDart,
        testDir,
        mainTest,
      });
      expect(controller.selection.anchor, bDart);
      expect(controller.focusedId, mainTest);
      controller.extendSelection(lib);
      expect(controller.selection.selected, {lib, src, aDart, bDart});
      expect(controller.selection.anchor, bDart);
    });

    test('extendSelection skips unselectable rows', () {
      final controller = expandedController(selectable: (node) => node.isFile)
        ..select(aDart)
        ..extendSelection(readme);
      expect(controller.selection.selected, {
        aDart,
        bDart,
        mainDart,
        mainTest,
        readme,
      });
    });

    test('extendSelection skips rows inside collapsed directories', () {
      final controller = expandedController()
        ..select(lib)
        ..collapse(src)
        ..extendSelection(mainDart);
      expect(controller.selection.selected, {lib, src, mainDart});
    });

    test('extendSelection falls back to select', () {
      final controller = expandedController()..extendSelection(bDart);
      expect(controller.selection.selected, {bDart});
      expect(controller.selection.anchor, bDart);
      // The anchor has no row anymore.
      controller
        ..collapse(src)
        ..extendSelection(readme);
      expect(controller.selection.selected, {readme});
      expect(controller.selection.anchor, readme);
      controller
        ..selectionMode = SelectionMode.single
        ..extendSelection(mainDart);
      expect(controller.selection.selected, {mainDart});
    });

    test('selectAll selects the visible selectable rows', () {
      final controller =
          expandedController(selectable: (node) => node.name != 'b.dart')
            ..select(mainDart)
            ..collapse(testDir);
      expect(notificationsOf(controller, controller.selectAll), 1);
      expect(controller.selection.selected, {
        repo,
        lib,
        src,
        aDart,
        mainDart,
        testDir,
        readme,
      });
      expect(controller.selection.anchor, mainDart);
      expect(notificationsOf(controller, controller.selectAll), 0);
    });

    test('selectAll moves an anchor without a row to the first row', () {
      final controller = expandedController()
        ..select(mainTest)
        ..collapse(testDir)
        ..selectAll();
      expect(controller.selection.anchor, repo);
      expect(controller.selection.isSelected(mainTest), isFalse);
    });

    test('selectAll does nothing in single mode', () {
      final controller = expandedController()
        ..selectionMode = SelectionMode.single
        ..select(aDart);
      expect(notificationsOf(controller, controller.selectAll), 0);
      expect(controller.selection.selected, {aDart});
    });

    test('clearSelection keeps the mode', () {
      final controller = expandedController()..select(aDart);
      expect(notificationsOf(controller, controller.clearSelection), 1);
      expect(
        controller.selection,
        const SelectionState.empty(mode: SelectionMode.multiple),
      );
      expect(notificationsOf(controller, controller.clearSelection), 0);
    });

    test('the selection setter prunes and compares by value', () {
      final controller = expandedController();
      expect(
        notificationsOf(controller, () {
          controller.selection = SelectionState(
            mode: SelectionMode.multiple,
            selected: [readme, unknown, aDart],
            anchor: readme,
          );
        }),
        1,
      );
      expect(controller.selection.selected, {readme, aDart});
      expect(
        notificationsOf(controller, () {
          controller.selection = SelectionState(
            mode: SelectionMode.multiple,
            selected: [aDart, readme],
            anchor: readme,
          );
        }),
        0,
      );
      expect(controller.selectedNodes.map((node) => node.id), [aDart, readme]);
    });

    test('selectionMode converts with withMode', () {
      final controller = expandedController()
        ..select(aDart)
        ..toggleSelected(bDart);
      expect(controller.selectionMode, SelectionMode.multiple);
      expect(
        notificationsOf(controller, () {
          controller.selectionMode = SelectionMode.single;
        }),
        1,
      );
      expect(controller.selection.selected, {bDart});
      expect(
        notificationsOf(controller, () {
          controller.selectionMode = SelectionMode.single;
        }),
        0,
      );
    });

    test('hidden selected nodes stay selected', () {
      final controller = expandedController()
        ..select(aDart)
        ..toggleSelected(mainTest)
        ..collapseAll()
        ..query = 'readme';
      expect(controller.selection.selected, {aDart, mainTest});
      expect(controller.isSelected(aDart), isTrue);
      expect(controller.selectedNodes.map((node) => node.id), [
        aDart,
        mainTest,
      ]);
    });
  });

  group('checks', () {
    test('toggleChecked checks a whole directory and undoes it', () {
      final controller = expandedController();
      expect(
        notificationsOf(controller, () => controller.toggleChecked(lib)),
        1,
      );
      expect(controller.checks.selected, {aDart, bDart, mainDart});
      expect(controller.checkStateOf(lib), CheckState.checked);
      expect(controller.checkStateOf(src), CheckState.checked);
      expect(controller.checkStateOf(repo), CheckState.partial);
      expect(controller.checkStateOf(testDir), CheckState.unchecked);
      expect(controller.checkStateOf(unknown), CheckState.unchecked);
      controller.toggleChecked(lib);
      expect(controller.checks.selected, isEmpty);
      expect(controller.checkStateOf(repo), CheckState.unchecked);
    });

    test('a partial directory becomes checked', () {
      final controller = expandedController()..toggleChecked(aDart);
      expect(controller.checkStateOf(lib), CheckState.partial);
      controller.toggleChecked(lib);
      expect(controller.checkStateOf(lib), CheckState.checked);
    });

    test('setChecked checks and unchecks', () {
      final controller = expandedController()..setChecked(repo, checked: true);
      expect(controller.checkStateOf(repo), CheckState.checked);
      expect(
        notificationsOf(controller, () {
          controller.setChecked(repo, checked: true);
        }),
        0,
      );
      controller.setChecked(src, checked: false);
      expect(controller.checkStateOf(repo), CheckState.partial);
      expect(controller.checkStateOf(src), CheckState.unchecked);
      expect(
        notificationsOf(controller, () {
          controller.setChecked(unknown, checked: true);
        }),
        0,
      );
    });

    test('counts stay right through incremental updates', () {
      final controller = expandedController();
      // Build the counts first, then update them incrementally.
      expect(controller.checkStateOf(repo), CheckState.unchecked);
      for (final id in [aDart, testDir, lib, readme, src, repo, bDart]) {
        controller.toggleChecked(id);
        for (final node in controller.tree.nodes) {
          expect(
            controller.checkStateOf(node.id),
            controller.checks.checkStateOf(controller.tree, node.id),
            reason: 'after toggling $id, ${node.id}',
          );
        }
      }
    });

    test('single-mode clicks update the counts instead of recounting', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        expansion: const ExpansionState.expanded(),
        checks: const SelectionState.empty(mode: SelectionMode.single),
      );
      expect(controller.checkStateOf(repo), CheckState.unchecked);
      final builds = CheckCounts.debugBuildCount;
      controller.toggleChecked(aDart);
      expect(controller.checkStateOf(aDart), CheckState.checked);
      expect(controller.checkStateOf(src), CheckState.partial);
      controller.toggleChecked(readme);
      expect(controller.checkStateOf(aDart), CheckState.unchecked);
      expect(controller.checkStateOf(src), CheckState.unchecked);
      expect(controller.checkStateOf(readme), CheckState.checked);
      expect(controller.checkStateOf(repo), CheckState.partial);
      controller.setChecked(readme, checked: false);
      expect(controller.checkStateOf(repo), CheckState.unchecked);
      expect(CheckCounts.debugBuildCount, builds);
    });

    test('checkAll and uncheckAll', () {
      final controller = expandedController();
      expect(notificationsOf(controller, controller.checkAll), 1);
      expect(controller.checkStateOf(repo), CheckState.checked);
      expect(notificationsOf(controller, controller.checkAll), 0);
      expect(notificationsOf(controller, controller.uncheckAll), 1);
      expect(controller.checks.selected, isEmpty);
      expect(notificationsOf(controller, controller.uncheckAll), 0);
    });

    test('checkedLeaves and checkedRoots in pre-order', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a/one.txt'),
        TreeEntry.file('/r/a/two.txt'),
        TreeEntry.directory('/r/empty'),
        TreeEntry.file('/r/b/three.txt'),
        TreeEntry.file('/r/b/four.txt'),
        TreeEntry.file('/r/z.txt'),
      ]);
      final controller = DirectoryTreeController<int>(tree: tree)
        ..toggleChecked(const NodeId('/r/z.txt'))
        ..toggleChecked(const NodeId('/r/a'))
        ..toggleChecked(const NodeId('/r/empty'))
        ..toggleChecked(const NodeId('/r/b/three.txt'));
      expect(controller.checkedLeaves.map((node) => node.id.value), [
        '/r/a/one.txt',
        '/r/a/two.txt',
        '/r/b/three.txt',
        '/r/empty',
        '/r/z.txt',
      ]);
      expect(controller.checkedRoots.map((node) => node.id.value), [
        '/r/a',
        '/r/b/three.txt',
        '/r/empty',
        '/r/z.txt',
      ]);
      controller.toggleChecked(const NodeId('/r/b'));
      expect(controller.checkedRoots.map((node) => node.id.value), ['/r']);
      controller.uncheckAll();
      expect(controller.checkedRoots, isEmpty);
      expect(controller.checkedLeaves, isEmpty);
    });

    test('single mode never throws for directories with several leaves', () {
      final controller = expandedController(
        checks: const SelectionState.empty(),
      );
      expect(
        notificationsOf(controller, () => controller.toggleChecked(lib)),
        0,
      );
      expect(
        notificationsOf(controller, () {
          controller.setChecked(repo, checked: true);
        }),
        0,
      );
      expect(notificationsOf(controller, controller.checkAll), 0);
      controller.toggleChecked(testDir);
      expect(controller.checks.selected, {mainTest});
      controller.toggleChecked(aDart);
      expect(controller.checks.selected, {aDart});
      expect(controller.checkStateOf(testDir), CheckState.unchecked);
      controller.setChecked(src, checked: false);
      expect(controller.checks.selected, isEmpty);
    });

    test('the selectable predicate never affects checks', () {
      final controller = expandedController(selectable: (node) => false)
        ..toggleChecked(repo);
      expect(controller.checkStateOf(repo), CheckState.checked);
      controller.select(aDart);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('the checks setter prunes and compares by value', () {
      final controller = expandedController();
      expect(
        notificationsOf(controller, () {
          controller.checks = SelectionState(
            mode: SelectionMode.multiple,
            selected: [aDart, unknown],
          );
        }),
        1,
      );
      expect(controller.checks.selected, {aDart});
      expect(controller.checkStateOf(src), CheckState.partial);
      expect(
        notificationsOf(controller, () {
          controller.checks = SelectionState(
            mode: SelectionMode.multiple,
            selected: [aDart],
          );
        }),
        0,
      );
    });
  });
}
