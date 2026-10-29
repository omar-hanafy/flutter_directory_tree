import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dnd_test_host.dart';

void main() {
  late DirectoryTreeController<Object?> controller;
  late DndRecorder recorder;

  setUp(() {
    controller = controllerFor(sampleTree(), collapsed: ['/r/c']);
    recorder = DndRecorder(controller);
  });
  tearDown(() => controller.dispose());

  Future<void> pumpHost(
    WidgetTester tester, {
    bool Function(List<TreeNode<Object?>> nodes)? canDrag,
    bool Function(DirectoryTreeDropDetails<Object?> details)? canDrop,
    ScrollController? scrollController,
    double height = 600,
  }) => tester.pumpWidget(
    DndHost(
      controller: controller,
      dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
        onDrop: recorder.onDrop,
        canDrag: canDrag,
        canDrop: canDrop,
      ),
      onLongPressWithoutDrag: recorder.onLongPress,
      scrollController: scrollController,
      height: height,
    ),
  );

  Offset center(WidgetTester tester, String path) =>
      tester.getCenter(recorder.row(path));

  /// Whether the default feedback of the row labelled [label] is shown.
  bool showsFeedback(String label) => find.text(label).evaluate().length == 2;

  group('mouse', () {
    testWidgets('a drag starts only once the pointer moved past the slop', (
      tester,
    ) async {
      await pumpHost(tester);
      final start = center(tester, '/r/a/a1.txt');
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(showsFeedback('a1.txt'), isFalse, reason: 'pressed only');

      await gesture.moveBy(const Offset(3, 0));
      await tester.pump();
      expect(showsFeedback('a1.txt'), isFalse, reason: 'within the slop');

      await gesture.moveBy(const Offset(2, 0));
      await tester.pump();
      expect(showsFeedback('a1.txt'), isTrue, reason: 'past the slop');

      await gesture.moveTo(center(tester, '/r/b'));
      await gesture.up();
      await tester.pump();
      expect(showsFeedback('a1.txt'), isFalse);
      expect(recorder.drops.single.target.path.toString(), '/r/b');
    });

    testWidgets('a click never drops, even on a target that would accept', (
      tester,
    ) async {
      // a1.txt and b1.txt selected: a press on a1.txt would target a, which
      // accepts them because b1.txt lives elsewhere.
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: [recorder.id('/r/a/a1.txt'), recorder.id('/r/b/b1.txt')],
      );
      await pumpHost(tester);

      final gesture = await tester.startGesture(
        center(tester, '/r/a/a1.txt'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(2, 1));
      await gesture.up();
      await tester.pump();

      expect(recorder.drops, isEmpty);
      expect(recorder.longPresses, isEmpty);
    });

    testWidgets('other buttons never drag', (tester) async {
      await pumpHost(tester);
      final gesture = await tester.startGesture(
        center(tester, '/r/a/a1.txt'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.moveTo(center(tester, '/r/b'));
      await tester.pump();
      expect(showsFeedback('a1.txt'), isFalse);

      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
    });

    testWidgets('a stylus drags after the touch slop without a long press', (
      tester,
    ) async {
      await pumpHost(tester);
      final start = center(tester, '/r/a/a1.txt');
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.stylus,
      );
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(showsFeedback('a1.txt'), isFalse, reason: 'within the slop');

      await gesture.moveTo(center(tester, '/r/c'));
      await tester.pump();
      expect(showsFeedback('a1.txt'), isTrue);
      await gesture.up();
      await tester.pump();
      expect(recorder.drops.single.target.path.toString(), '/r/c');
    });
  });

  group('touch', () {
    testWidgets('a drag starts after a long press', (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpHost(tester);
      final gesture = await tester.startGesture(center(tester, '/r/a/a1.txt'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(showsFeedback('a1.txt'), isFalse);

      await tester.pump(const Duration(milliseconds: 110));
      expect(showsFeedback('a1.txt'), isTrue, reason: 'lifted');
      expect(haptics, ['HapticFeedbackType.selectionClick']);

      await gesture.moveTo(center(tester, '/r/c'));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(recorder.drops.single.target.path.toString(), '/r/c');
      expect(recorder.longPresses, isEmpty);
    });

    testWidgets('moving before the long press gives the pointer up', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await tester.startGesture(center(tester, '/r/a/a1.txt'));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(center(tester, '/r/c'));
      await tester.pump(const Duration(seconds: 1));
      expect(showsFeedback('a1.txt'), isFalse);

      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
      expect(recorder.longPresses, isEmpty);
    });

    testWidgets('a vertical swipe scrolls the list instead of dragging', (
      tester,
    ) async {
      controller.tree = bigTree();
      controller.expandAll();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpHost(tester, scrollController: scroll, height: 300);

      await tester.drag(recorder.row('/r/d0/f03.txt'), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(scroll.offset, greaterThan(100));
      expect(recorder.drops, isEmpty);
      expect(recorder.longPresses, isEmpty);
    });

    testWidgets('once the long press started a drag, moving does not '
        'scroll', (tester) async {
      controller.tree = bigTree();
      controller.expandAll();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpHost(tester, scrollController: scroll, height: 300);

      final gesture = await startLongPress(
        tester,
        center(tester, '/r/d0/f03.txt'),
      );
      // Up into the middle of the list: no edge, so no auto-scroll either.
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(scroll.offset, 0);
      expect(showsFeedback('f03.txt'), isTrue);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('a long press released without moving reports the row and '
        'drops nothing', (tester) async {
      // A canDrop that accepts everything: any drop would get through.
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: [recorder.id('/r/a/a1.txt'), recorder.id('/r/b/b1.txt')],
      );
      await pumpHost(tester, canDrop: (details) => true);
      final start = center(tester, '/r/a/a1.txt');

      final gesture = await startLongPress(tester, start);
      expect(showsFeedback('a1.txt'), isTrue);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops, isEmpty);
      expect(recorder.longPresses, hasLength(1));
      expect(
        recorder.longPresses.single.row,
        same(controller.rows.rowOf(recorder.id('/r/a/a1.txt'))),
      );
      expect(recorder.longPresses.single.position, start);
      expect(showsFeedback('a1.txt'), isFalse);
    });

    testWidgets('moving within the touch slop still counts as a long press', (
      tester,
    ) async {
      await pumpHost(tester, canDrop: (details) => true);
      final start = center(tester, '/r/a/a1.txt');

      final gesture = await startLongPress(tester, start);
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-6, 8));
      await tester.pump();
      expect(isTinted(tester, recorder.row('/r/a')), isFalse);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops, isEmpty);
      expect(recorder.longPresses.single.position, start);
    });

    testWidgets('moving past the slop makes it a drag for good', (
      tester,
    ) async {
      await pumpHost(tester, canDrop: (details) => true);
      final start = center(tester, '/r/a/a1.txt');

      final gesture = await startLongPress(tester, start);
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      // Back where it started: a drop on a1.txt's own directory, accepted.
      await gesture.moveTo(start);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(recorder.longPresses, isEmpty);
      expect(recorder.drops.single.target.path.toString(), '/r/a');
    });

    testWidgets('a long press on a row that may not be dragged is still '
        'reported', (tester) async {
      await pumpHost(tester, canDrag: (nodes) => false);
      final start = center(tester, '/r/b');

      final gesture = await startLongPress(tester, start);
      expect(showsFeedback('b'), isFalse);
      // Moving and coming back does not turn it into anything else.
      await gesture.moveTo(center(tester, '/r/a'));
      await tester.pump();
      expect(isTinted(tester, recorder.row('/r/a')), isFalse);
      await gesture.up();
      await tester.pump();
      expect(recorder.longPresses, isEmpty, reason: 'it moved');

      final second = await startLongPress(tester, start);
      await second.up();
      await tester.pump();
      expect(recorder.longPresses.single.row.id, recorder.id('/r/b'));
      expect(recorder.drops, isEmpty);
    });

    testWidgets('a long press whose row disappeared is not reported', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await startLongPress(
        tester,
        center(tester, '/r/a/a1.txt'),
      );
      controller.collapse(recorder.id('/r/a'));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(recorder.longPresses, isEmpty);
      expect(recorder.drops, isEmpty);
    });

    testWidgets('a cancelled pointer ends the drag without a drop', (
      tester,
    ) async {
      await pumpHost(tester, canDrop: (details) => true);
      final gesture = await startLongPress(
        tester,
        center(tester, '/r/a/a1.txt'),
      );
      await gesture.moveTo(center(tester, '/r/c'));
      await tester.pump();
      expect(isTinted(tester, recorder.row('/r/c')), isTrue);

      await gesture.cancel();
      await tester.pump();

      expect(recorder.drops, isEmpty);
      expect(recorder.longPresses, isEmpty);
      expect(isTinted(tester, recorder.row('/r/c')), isFalse);
      expect(showsFeedback('a1.txt'), isFalse);
    });

    testWidgets('a second finger does not start another drag', (tester) async {
      await pumpHost(tester);
      final first = await startLongPress(tester, center(tester, '/r/a/a1.txt'));
      final second = await startLongPress(tester, center(tester, '/r/top.txt'));
      expect(showsFeedback('top.txt'), isFalse);

      await second.up();
      await first.moveTo(center(tester, '/r/c'));
      await first.up();
      await tester.pump();

      expect(pathsOf(recorder.drops.single.nodes), ['/r/a/a1.txt']);
      expect(recorder.longPresses, isEmpty);
    });
  });
}
