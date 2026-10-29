import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dnd_test_host.dart';

/// r, a (a1.txt, a2.txt), b (b1.txt), each node's data its name.
DirectoryTree<String> stringTree() => DirectoryTree<String>.build(const [
  TreeEntry<String>.directory('/r', data: 'r'),
  TreeEntry<String>.directory('/r/a', data: 'a'),
  TreeEntry<String>.file('/r/a/a1.txt', data: 'a1'),
  TreeEntry<String>.file('/r/a/a2.txt', data: 'a2'),
  TreeEntry<String>.directory('/r/b', data: 'b'),
  TreeEntry<String>.file('/r/b/b1.txt', data: 'b1'),
]);

/// A string-typed configuration that records every callback.
final class TypedCallbacks {
  final List<List<String?>> dragged = [];
  final List<String?> asked = [];
  final List<DirectoryTreeDropDetails<String>> dropped = [];
  int feedbacks = 0;

  DirectoryTreeDragAndDrop<String> get config =>
      DirectoryTreeDragAndDrop<String>(
        canDrag: (nodes) {
          dragged.add([for (final node in nodes) node.data]);
          return true;
        },
        canDrop: (details) {
          asked.add(details.target.data);
          return true;
        },
        feedbackBuilder: (context, nodes) {
          feedbacks++;
          return Text('${nodes.length} ${nodes.first.data}');
        },
        onDrop: dropped.add,
      );
}

/// A mouse drag from [from] to [to] in small steps.
Future<void> mouseDrag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: from);
  await gesture.down(from);
  await tester.pump();
  const steps = 8;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump();
  }
  await gesture.up();
  await gesture.removePointer();
  await tester.pump();
}

Offset centerOf(WidgetTester tester, String label) =>
    tester.getCenter(find.text(label).first);

void main() {
  testWidgets('a String configuration works in a DirectoryTreeView<Object?> '
      'of a String controller', (tester) async {
    final controller = DirectoryTreeController<String>(
      tree: stringTree(),
      expansion: const ExpansionState.expanded(),
    );
    addTearDown(controller.dispose);
    final callbacks = TypedCallbacks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: DirectoryTreeView<Object?>(
              controller: controller,
              dragAndDrop: callbacks.config,
            ),
          ),
        ),
      ),
    );
    await mouseDrag(tester, centerOf(tester, 'a1.txt'), centerOf(tester, 'b'));
    expect(tester.takeException(), isNull);
    expect(callbacks.dragged, [
      ['a1'],
    ]);
    expect(callbacks.feedbacks, 1);
    expect(callbacks.asked, contains('b'));
    expect(callbacks.dropped, hasLength(1));
    final drop = callbacks.dropped.single;
    expect(drop.target.data, 'b');
    expect([for (final node in drop.nodes) node.data], ['a1']);
  });

  testWidgets('a String configuration works in a scope of Object?', (
    tester,
  ) async {
    final controller = DirectoryTreeController<String>(
      tree: stringTree(),
      expansion: const ExpansionState.expanded(),
    );
    addTearDown(controller.dispose);
    final callbacks = TypedCallbacks();
    // DndHost builds a DirectoryTreeDragAndDropScope<Object?>.
    await tester.pumpWidget(
      DndHost(controller: controller, dragAndDrop: callbacks.config),
    );
    await mouseDrag(
      tester,
      centerOf(tester, 'a2.txt'),
      centerOf(tester, 'b1.txt'),
    );
    expect(tester.takeException(), isNull);
    expect(callbacks.dragged, [
      ['a2'],
    ]);
    expect(callbacks.dropped.single.target.data, 'b');
  });

  testWidgets('without canDrop and canDrag, a narrower configuration drops', (
    tester,
  ) async {
    final controller = DirectoryTreeController<String>(
      tree: stringTree(),
      expansion: const ExpansionState.expanded(),
    );
    addTearDown(controller.dispose);
    final dropped = <DirectoryTreeDropDetails<String>>[];
    await tester.pumpWidget(
      DndHost(
        controller: controller,
        dragAndDrop: DirectoryTreeDragAndDrop<String>(onDrop: dropped.add),
      ),
    );
    await mouseDrag(tester, centerOf(tester, 'a1.txt'), centerOf(tester, 'b'));
    expect(tester.takeException(), isNull);
    expect(dropped.single.nodes.single.data, 'a1');
  });

  group('a configuration narrower than the controller', () {
    late DirectoryTreeController<Object?> controller;
    late List<String> menus;
    late int drops;

    Widget view() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: DirectoryTreeView<Object?>(
            controller: controller,
            dragAndDrop: DirectoryTreeDragAndDrop<String>(
              onDrop: (_) => drops++,
            ),
            contextMenuBuilder: (context, details) {
              menus.add(details.row.label);
              return [
                MenuItemButton(onPressed: () {}, child: const Text('Item')),
              ];
            },
          ),
        ),
      ),
    );

    Future<void> pumpView(WidgetTester tester) async {
      controller = DirectoryTreeController<Object?>(
        tree: sampleTree(),
        expansion: const ExpansionState.expanded(),
      );
      addTearDown(controller.dispose);
      menus = [];
      drops = 0;
      await tester.pumpWidget(view());
    }

    testWidgets('is reported once in debug mode', (tester) async {
      await pumpView(tester);
      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(
        error.toString(),
        contains('a configuration for other nodes than its controller holds'),
      );
      // The same mismatch is not reported again on every build.
      await tester.pumpWidget(view());
      expect(tester.takeException(), isNull);
    });

    testWidgets('drags nothing, but a touch long-press opens the menu', (
      tester,
    ) async {
      await pumpView(tester);
      tester.takeException();
      final gesture = await tester.startGesture(centerOf(tester, 'a1.txt'));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(menus, ['a1.txt']);
      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();
      await mouseDrag(
        tester,
        centerOf(tester, 'a1.txt'),
        centerOf(tester, 'b'),
      );
      expect(tester.takeException(), isNull);
      expect(drops, 0);
    });
  });
}
