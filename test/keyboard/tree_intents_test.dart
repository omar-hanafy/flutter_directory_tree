import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoveTreeFocusIntent', () {
    test('replaces the selection by default', () {
      expect(
        const MoveTreeFocusIntent(TreeFocusMove.next).selection,
        TreeSelectionUpdate.replace,
      );
    });

    test('compares by move and selection update', () {
      final next = MoveTreeFocusIntent(TreeFocusMove.next);
      expect(next, const MoveTreeFocusIntent(TreeFocusMove.next));
      expect(
        next.hashCode,
        const MoveTreeFocusIntent(TreeFocusMove.next).hashCode,
      );
      expect(next, isNot(const MoveTreeFocusIntent(TreeFocusMove.previous)));
      expect(
        next,
        isNot(
          const MoveTreeFocusIntent(
            TreeFocusMove.next,
            selection: TreeSelectionUpdate.keep,
          ),
        ),
      );
      expect(next, isNot(const _MoveSubclass(TreeFocusMove.next)));
    });

    test('describes its move and selection update', () {
      expect(
        const MoveTreeFocusIntent(
          TreeFocusMove.pageDown,
          selection: TreeSelectionUpdate.extend,
        ).toString(),
        contains('move: pageDown, selection: extend'),
      );
    });
  });

  test('every intent is a distinct Intent type', () {
    const intents = <Intent>[
      MoveTreeFocusIntent(TreeFocusMove.next),
      ExpandTreeNodeIntent(),
      CollapseTreeNodeIntent(),
      ExpandTreeSubtreeIntent(),
      ActivateTreeNodeIntent(),
      ToggleTreeSelectionIntent(),
      SelectAllTreeNodesIntent(),
      ClearTreeSelectionIntent(),
      OpenTreeContextMenuIntent(),
    ];
    expect({for (final intent in intents) intent.runtimeType}, hasLength(9));
  });
}

final class _MoveSubclass extends MoveTreeFocusIntent {
  const _MoveSubclass(super.move);
}
