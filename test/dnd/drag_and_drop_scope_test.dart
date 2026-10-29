import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  Offset center(WidgetTester tester, String path) =>
      tester.getCenter(recorder.row(path));

  Future<void> pumpHost(
    WidgetTester tester, {
    DirectoryTreeDragAndDrop<Object?>? dragAndDrop,
    TextDirection textDirection = TextDirection.ltr,
  }) => tester.pumpWidget(
    DndHost(
      controller: controller,
      dragAndDrop:
          dragAndDrop ??
          DirectoryTreeDragAndDrop<Object?>(onDrop: recorder.onDrop),
      onLongPressWithoutDrag: recorder.onLongPress,
      textDirection: textDirection,
    ),
  );

  group('data changes during a drag', () {
    testWidgets('a new tree keeps the drag on the same ids', (tester) async {
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/b'),
      );
      controller.updateTree((builder) => builder.addFile('/r/b/new.txt'));
      await tester.pump();
      await tester.pump();
      expect(isTinted(tester, recorder.row('/r/b/new.txt')), isTrue);

      await gesture.moveTo(center(tester, '/r/b/new.txt'));
      await gesture.up();
      await tester.pump();

      final drop = recorder.drops.single;
      // The nodes come from the current tree, not the one the drag began in.
      expect(
        drop.nodes.single,
        same(controller.tree[recorder.id('/r/a/a1.txt')]),
      );
      expect(drop.target, same(controller.tree[recorder.id('/r/b')]));
    });

    testWidgets('the target is checked again when its data changes', (
      tester,
    ) async {
      DirectoryTree<Object?> treeWith({required bool locked}) =>
          DirectoryTree<Object?>.build([
            const TreeEntry.directory('/r/'),
            TreeEntry.directory('/r/b/', data: locked ? 'locked' : null),
            const TreeEntry.file('/r/b/b1.txt'),
            const TreeEntry.file('/r/a/a1.txt'),
          ]);
      controller.tree = treeWith(locked: false);
      controller.expandAll();
      await pumpHost(
        tester,
        dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
          onDrop: recorder.onDrop,
          canDrop: (details) => details.target.data != 'locked',
        ),
      );
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/b/b1.txt'),
      );
      expect(isTinted(tester, recorder.row('/r/b')), isTrue);

      // A refresh (a file watcher, say) brings new data for b.
      controller.tree = treeWith(locked: true);
      await tester.pump();
      await tester.pump();
      expect(isTinted(tester, recorder.row('/r/b')), isFalse);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops, isEmpty);
    });

    testWidgets('a drag whose nodes all disappear ends without a drop', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/b'),
      );
      expect(find.text('a1.txt'), findsNWidgets(2));

      controller.updateTree((builder) => builder.remove('/r/a/a1.txt'));
      await tester.pump();
      expect(find.text('a1.txt'), findsNothing, reason: 'feedback removed');
      expect(isTinted(tester, recorder.row('/r/b')), isFalse);

      await gesture.moveTo(center(tester, '/r/c'));
      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
    });

    testWidgets('a dragged selection keeps the nodes that remain', (
      tester,
    ) async {
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: [recorder.id('/r/a/a1.txt'), recorder.id('/r/top.txt')],
      );
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/b'),
      );
      controller.updateTree((builder) => builder.remove('/r/top.txt'));
      await tester.pump();
      await gesture.moveTo(center(tester, '/r/b'));
      await gesture.up();
      await tester.pump();

      expect(pathsOf(recorder.drops.single.nodes), ['/r/a/a1.txt']);
    });
  });

  group('lifecycle', () {
    testWidgets('disposing the scope during a drag cleans up', (tester) async {
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/c'),
      );
      expect(find.text('a1.txt'), findsNWidgets(2));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(find.text('a1.txt'), findsNothing);
      await gesture.moveBy(const Offset(0, 30));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));

      expect(recorder.drops, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new controller ends the drag of the old one', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/c'),
      );
      final other = controllerFor(sampleTree(), collapsed: ['/r/c']);
      addTearDown(other.dispose);
      await tester.pumpWidget(
        DndHost(
          controller: other,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('a1.txt'), findsOneWidget, reason: 'feedback removed');

      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
    });

    testWidgets('a new configuration applies to the drag in progress', (
      tester,
    ) async {
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/c'),
      );
      expect(isTinted(tester, recorder.row('/r/c')), isTrue);

      final drops = <DirectoryTreeDropDetails<Object?>>[];
      await pumpHost(
        tester,
        dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
          onDrop: drops.add,
          canDrop: (details) => details.target.name != 'c',
        ),
      );
      await tester.pump();
      expect(isTinted(tester, recorder.row('/r/c')), isFalse);

      await gesture.moveTo(center(tester, '/r/b'));
      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
      expect(drops.single.target.path.toString(), '/r/b');
    });

    testWidgets('rows of another scope are never targets', (tester) async {
      final other = controllerFor(sampleTree(), collapsed: ['/r/c']);
      addTearDown(other.dispose);
      final otherRecorder = DndRecorder(other);
      Widget scope(
        DirectoryTreeController<Object?> rowsOf,
        DndRecorder record,
      ) => Expanded(
        child: DirectoryTreeDragAndDropScope<Object?>(
          controller: rowsOf,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(onDrop: record.onDrop),
          child: DecoratedRows(controller: rowsOf),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              scope(controller, recorder),
              scope(other, otherRecorder),
            ],
          ),
        ),
      );
      final left = find.descendant(
        of: find.byType(DirectoryTreeDragAndDropScope<Object?>).first,
        matching: recorder.row('/r/a/a1.txt'),
      );
      final right = find.descendant(
        of: find.byType(DirectoryTreeDragAndDropScope<Object?>).last,
        matching: otherRecorder.row('/r/c'),
      );

      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(left),
        tester.getCenter(right),
      );
      expect(isTinted(tester, right), isFalse);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops, isEmpty);
      expect(otherRecorder.drops, isEmpty);
    });

    testWidgets('works without an overlay, without feedback', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DirectoryTreeDragAndDropScope<Object?>(
            controller: controller,
            dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
              onDrop: recorder.onDrop,
            ),
            child: DecoratedRows(controller: controller),
          ),
        ),
      );
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/c'),
      );
      expect(find.text('a1.txt'), findsOneWidget);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops.single.target.path.toString(), '/r/c');
    });
  });

  group('feedback', () {
    testWidgets('the default shows the pressed node and the node count', (
      tester,
    ) async {
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: [
          recorder.id('/r/a/a1.txt'),
          recorder.id('/r/a/a2.txt'),
          recorder.id('/r/b/b1.txt'),
        ],
      );
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a2.txt'),
        center(tester, '/r/c'),
      );

      expect(find.text('a2.txt'), findsNWidgets(2));
      expect(find.text('a1.txt'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a single node shows no count', (tester) async {
      await pumpHost(tester);
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a2.txt'),
        center(tester, '/r/c'),
      );

      expect(find.text('a2.txt'), findsNWidgets(2));
      expect(find.text('1'), findsNothing);
      await gesture.up();
      await tester.pump();
    });

    for (final direction in TextDirection.values) {
      testWidgets('feedbackBuilder gets the nodes and follows the pointer '
          '(${direction.name})', (tester) async {
        const key = Key('feedback');
        final built = <List<String>>[];
        await pumpHost(
          tester,
          textDirection: direction,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
            feedbackBuilder: (context, nodes) {
              built.add(pathsOf(nodes));
              expect(Directionality.of(context), direction);
              return const SizedBox(key: key, width: 100, height: 20);
            },
          ),
        );

        final at = center(tester, '/r/b');
        final gesture = await startMouseDrag(
          tester,
          center(tester, '/r/a/a1.txt'),
          at,
        );
        Rect expected(Offset pointer) => direction == TextDirection.ltr
            ? Rect.fromLTWH(pointer.dx - 16, pointer.dy - 10, 100, 20)
            : Rect.fromLTWH(pointer.dx + 16 - 100, pointer.dy - 10, 100, 20);
        expect(tester.getRect(find.byKey(key)), expected(at));

        await gesture.moveBy(const Offset(-30, 40));
        await tester.pump();
        expect(
          tester.getRect(find.byKey(key)),
          expected(at + const Offset(-30, 40)),
        );
        await gesture.up();
        await tester.pump();

        expect(find.byKey(key), findsNothing);
        expect(built, [
          ['/r/a/a1.txt'],
        ]);
      });
    }

    testWidgets('the feedback ignores the pointer, so drops land on the '
        'rows under it', (tester) async {
      await pumpHost(
        tester,
        dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
          onDrop: recorder.onDrop,
          // A big opaque feedback that covers the target.
          feedbackBuilder: (context, nodes) => const ColoredBox(
            color: Color(0xFF000000),
            child: SizedBox(width: 300, height: 200),
          ),
        ),
      );
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/c'),
      );
      expect(isTinted(tester, recorder.row('/r/c')), isTrue);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops.single.target.path.toString(), '/r/c');
    });
  });

  group('decorateRow', () {
    // One row, so one row reports the error.
    DirectoryTreeController<Object?> oneRow() {
      final single = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(const ['/r/']),
      );
      addTearDown(single.dispose);
      return single;
    }

    testWidgets('throws without a scope', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DecoratedRows(controller: oneRow())),
      );

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(
        error.toString(),
        contains('without a DirectoryTreeDragAndDropScope'),
      );
    });

    testWidgets('throws for the rows of another controller', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryTreeDragAndDropScope<Object?>(
            controller: controller,
            dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
              onDrop: recorder.onDrop,
            ),
            child: DecoratedRows(controller: oneRow()),
          ),
        ),
      );

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(error.toString(), contains('another controller'));
    });

    testWidgets('keeps the size of the row and its own gestures', (
      tester,
    ) async {
      final taps = <String>[];
      await tester.pumpWidget(
        DndHost(
          controller: controller,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
          ),
          rowContent: (row) => GestureDetector(
            onTap: () => taps.add(row.label),
            child: Text(row.label),
          ),
        ),
      );

      expect(
        tester.getSize(recorder.row('/r/a/a1.txt')),
        const Size(listWidth, rowExtent),
      );
      await tester.tap(recorder.row('/r/a/a1.txt'));
      await tester.tap(
        recorder.row('/r/a/a2.txt'),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(taps, ['a1.txt', 'a2.txt']);
      expect(recorder.drops, isEmpty);
    });
  });

  group('large and deep trees', () {
    testWidgets('a drag of 10000 selected files asks canDrag once and canDrop '
        'once per target', (tester) async {
      final tree = DirectoryTree.fromPaths([
        '/r/',
        for (var folder = 0; folder < 100; folder++)
          for (var file = 0; file < 100; file++) '/r/d$folder/f$file.txt',
      ]);
      final big = controllerFor(tree);
      addTearDown(big.dispose);
      big.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: [for (final node in tree.files) node.id],
      );
      final bigRecorder = DndRecorder(big);
      var dragAsks = 0;
      var dropAsks = 0;
      await tester.pumpWidget(
        DndHost(
          controller: big,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: bigRecorder.onDrop,
            canDrag: (nodes) {
              dragAsks++;
              return true;
            },
            canDrop: (details) {
              dropAsks++;
              return true;
            },
          ),
        ),
      );

      // Rows: r, d0, d0/f0 ... (directories first, then files by name).
      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(bigRecorder.row('/r/d0/f1.txt')),
        tester.getCenter(bigRecorder.row('/r/d0/f10.txt')),
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, 3));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(dragAsks, 1);
      expect(dropAsks, 2, reason: 'one target, asked again on release');
      expect(bigRecorder.drops.single.nodes, hasLength(10000));
      expect(bigRecorder.drops.single.target.path.toString(), '/r/d0');
    });

    testWidgets('targets deep inside a 1500-level chain', (tester) async {
      final deep = StringBuffer('/r');
      for (var level = 0; level < 1500; level++) {
        deep.write('/n$level');
      }
      final tree = DirectoryTree.fromPaths([
        '/r/',
        '$deep/leaf.txt',
        '/r/x.txt',
      ]);
      final deepController = DirectoryTreeController<Object?>(
        tree: tree,
        expansion: const ExpansionState.expanded(),
        compactFolders: true,
      );
      addTearDown(deepController.dispose);
      final deepRecorder = DndRecorder(deepController);
      await tester.pumpWidget(
        DndHost(
          controller: deepController,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: deepRecorder.onDrop,
          ),
        ),
      );

      // Rows: r, the chain n0/.../n1499 compacted into one row, leaf.txt,
      // x.txt. A drop on leaf.txt goes to n1499, 1501 levels down.
      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(deepRecorder.row('/r/x.txt')),
        tester.getCenter(deepRecorder.row('$deep/leaf.txt')),
      );
      expect(isTinted(tester, deepRecorder.row('$deep/leaf.txt')), isTrue);
      await gesture.up();
      await tester.pump();

      expect(deepRecorder.drops.single.target.path.toString(), '$deep');
    });
  });
}
