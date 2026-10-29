import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

DirectoryTreeController<int> expandedController() =>
    DirectoryTreeController<int>(
      tree: sampleTree(),
      expansion: const ExpansionState.expanded(),
    );

/// A directory `w` holding `f00.txt` to `f29.txt`: 31 rows when expanded.
DirectoryTreeController<int> wideController() => DirectoryTreeController<int>(
  tree: DirectoryTree<int>.build([
    for (var i = 0; i < 30; i++)
      TreeEntry<int>.file('/w/f${i.toString().padLeft(2, '0')}.txt'),
  ]),
  expansion: const ExpansionState.expanded(),
);

void main() {
  // Expanded rows of the sample tree:
  // 0 repo, 1 lib, 2 src, 3 a.dart, 4 b.dart, 5 main.dart, 6 test,
  // 7 main_test.dart, 8 README.md
  group('focus', () {
    test('focuses a row and scrolls to it', () {
      final viewport = FakeViewport();
      final controller = expandedController()..attachViewport(viewport);
      late bool result;
      expect(
        notificationsOf(controller, () {
          result = controller.focus(mainDart);
        }),
        1,
      );
      expect(result, isTrue);
      expect(controller.focusedId, mainDart);
      expect(controller.focusedIndex, 5);
      expect(controller.focusedRow!.id, mainDart);
      expect(controller.selection.isEmpty, isTrue);
      expect(viewport.shown.single, (
        index: 5,
        duration: Duration.zero,
        curve: viewport.shown.single.curve,
        alignment: null,
      ));
      // Focusing again changes nothing but still scrolls.
      expect(notificationsOf(controller, () => controller.focus(mainDart)), 0);
      expect(viewport.shown, hasLength(2));
      controller.focus(readme, scroll: false);
      expect(viewport.shown, hasLength(2));
    });

    test('returns false without a row and clears with null', () {
      final controller = expandedController()..focus(aDart);
      for (final id in [unknown]) {
        expect(
          notificationsOf(controller, () {
            expect(controller.focus(id), isFalse);
          }),
          0,
        );
      }
      controller.collapse(src);
      expect(controller.focusedId, src);
      expect(controller.focus(aDart), isFalse);
      expect(controller.focusedId, src);
      expect(
        notificationsOf(controller, () {
          expect(controller.focus(null), isTrue);
        }),
        1,
      );
      expect(controller.focusedId, isNull);
      expect(notificationsOf(controller, () => controller.focus(null)), 0);
    });
  });

  group('moveFocus', () {
    test('with nothing focused goes to the first or the last row', () {
      for (final move in TreeFocusMove.values) {
        final controller = expandedController();
        expect(controller.moveFocus(move), isTrue, reason: '$move');
        final expected =
            move == TreeFocusMove.last || move == TreeFocusMove.previous
            ? readme
            : repo;
        expect(controller.focusedId, expected, reason: '$move');
      }
    });

    test('steps, jumps, and clamps', () {
      final controller = expandedController()..focus(repo);
      expect(controller.moveFocus(TreeFocusMove.previous), isFalse);
      expect(controller.moveFocus(TreeFocusMove.first), isFalse);
      expect(controller.moveFocus(TreeFocusMove.next), isTrue);
      expect(controller.focusedId, lib);
      expect(controller.moveFocus(TreeFocusMove.last), isTrue);
      expect(controller.focusedId, readme);
      expect(controller.moveFocus(TreeFocusMove.next), isFalse);
      expect(controller.moveFocus(TreeFocusMove.last), isFalse);
      expect(controller.moveFocus(TreeFocusMove.first), isTrue);
      expect(controller.focusedId, repo);
    });

    test('parent and firstChild follow the rows', () {
      final controller = expandedController()..focus(bDart);
      expect(controller.moveFocus(TreeFocusMove.parent), isTrue);
      expect(controller.focusedId, src);
      expect(controller.moveFocus(TreeFocusMove.parent), isTrue);
      expect(controller.focusedId, lib);
      expect(controller.moveFocus(TreeFocusMove.firstChild), isTrue);
      expect(controller.focusedId, src);
      controller.collapse(src);
      expect(controller.moveFocus(TreeFocusMove.firstChild), isFalse);
      controller.focus(repo);
      expect(controller.moveFocus(TreeFocusMove.parent), isFalse);
      controller.focus(readme);
      expect(controller.moveFocus(TreeFocusMove.firstChild), isFalse);
    });

    test('pages by the argument, the largest viewport, or 10', () {
      final controller = wideController()..focus(const NodeId('/w'));
      expect(controller.moveFocus(TreeFocusMove.pageDown), isTrue);
      expect(controller.focusedIndex, 10);
      final small = FakeViewport(pageRowCount: 3);
      final large = FakeViewport(pageRowCount: 7);
      controller
        ..attachViewport(small)
        ..attachViewport(large);
      expect(controller.moveFocus(TreeFocusMove.pageDown), isTrue);
      expect(controller.focusedIndex, 17);
      expect(controller.moveFocus(TreeFocusMove.pageUp, pageSize: 2), isTrue);
      expect(controller.focusedIndex, 15);
      expect(controller.moveFocus(TreeFocusMove.pageUp, pageSize: 0), isTrue);
      expect(controller.focusedIndex, 14);
      expect(
        controller.moveFocus(TreeFocusMove.pageDown, pageSize: 99),
        isTrue,
      );
      expect(controller.focusedIndex, 30);
      expect(controller.moveFocus(TreeFocusMove.pageDown), isFalse);
      expect(controller.moveFocus(TreeFocusMove.pageUp, pageSize: 99), isTrue);
      expect(controller.focusedIndex, 0);
      // Each move scrolled every viewport to the new row.
      expect(large.shown.map((call) => call.index), [17, 15, 14, 30, 0]);
      expect(small.shown, hasLength(5));
    });

    test('replace selects, extend extends, keep leaves the selection', () {
      final controller = expandedController();
      expect(
        notificationsOf(controller, () {
          controller.moveFocus(TreeFocusMove.next);
        }),
        1,
      );
      expect(controller.selection.selected, {repo});
      controller
        ..moveFocus(TreeFocusMove.next, selection: TreeSelectionUpdate.extend)
        ..moveFocus(TreeFocusMove.next, selection: TreeSelectionUpdate.extend);
      expect(controller.selection.selected, {repo, lib, src});
      expect(controller.selection.anchor, repo);
      controller.moveFocus(
        TreeFocusMove.last,
        selection: TreeSelectionUpdate.keep,
      );
      expect(controller.focusedId, readme);
      expect(controller.selection.selected, {repo, lib, src});
      controller.moveFocus(TreeFocusMove.previous);
      expect(controller.selection.selected, {mainTest});
    });

    test('does nothing when the focus cannot move', () {
      final controller = expandedController()
        ..focus(readme)
        ..select(aDart, focus: false);
      expect(
        notificationsOf(controller, () {
          expect(controller.moveFocus(TreeFocusMove.next), isFalse);
        }),
        0,
      );
      expect(controller.selection.selected, {aDart});
      final empty = DirectoryTreeController<int>();
      expect(empty.moveFocus(TreeFocusMove.first), isFalse);
    });

    test('keeps the selection on an unselectable row', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        expansion: const ExpansionState.expanded(),
        selectable: (node) => node.isFile,
      )..select(aDart);
      controller.moveFocus(TreeFocusMove.parent);
      expect(controller.focusedId, src);
      expect(controller.selection.selected, {aDart});
    });
  });
}
