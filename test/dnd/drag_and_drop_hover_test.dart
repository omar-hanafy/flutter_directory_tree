import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/dnd/directory_tree_drag_and_drop.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dnd_test_host.dart';

void main() {
  group('tint', () {
    late DirectoryTreeController<Object?> controller;
    late DndRecorder recorder;

    setUp(() {
      controller = controllerFor(sampleTree(), collapsed: ['/r/c']);
      recorder = DndRecorder(controller);
    });
    tearDown(() => controller.dispose());

    const allRows = [
      '/r',
      '/r/a',
      '/r/a/a1.txt',
      '/r/a/a2.txt',
      '/r/b',
      '/r/b/sub',
      '/r/b/sub/s1.txt',
      '/r/b/b1.txt',
      '/r/c',
      '/r/top.txt',
    ];

    List<String> tinted(WidgetTester tester) => [
      for (final path in allRows)
        if (isTinted(tester, recorder.row(path))) path,
    ];

    testWidgets('covers the accepted target row and its visible subtree', (
      tester,
    ) async {
      await tester.pumpWidget(
        DndHost(
          controller: controller,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
          ),
        ),
      );
      expect(tinted(tester), isEmpty);

      // Over b1.txt: the target is b.
      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(recorder.row('/r/a/a1.txt')),
        tester.getCenter(recorder.row('/r/b/b1.txt')),
      );
      expect(tinted(tester), [
        '/r/b',
        '/r/b/sub',
        '/r/b/sub/s1.txt',
        '/r/b/b1.txt',
      ]);

      await gesture.moveTo(tester.getCenter(recorder.row('/r/c')));
      await tester.pump();
      expect(tinted(tester), ['/r/c']);

      // a already holds a1.txt, so it refuses the drop and shows no tint.
      await gesture.moveTo(tester.getCenter(recorder.row('/r/a/a2.txt')));
      await tester.pump();
      expect(tinted(tester), isEmpty);

      await gesture.moveTo(tester.getCenter(recorder.row('/r/b/sub')));
      await tester.pump();
      expect(tinted(tester), ['/r/b/sub', '/r/b/sub/s1.txt']);

      await gesture.up();
      await tester.pump();
      expect(tinted(tester), isEmpty);
    });

    testWidgets('follows the theme\'s dropTargetColor', (tester) async {
      const color = Color(0x5500FF00);
      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryTreeTheme(
            data: const DirectoryTreeThemeData(dropTargetColor: color),
            child: DirectoryTreeDragAndDropScope<Object?>(
              controller: controller,
              dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
                onDrop: recorder.onDrop,
              ),
              child: DecoratedRows(controller: controller),
            ),
          ),
        ),
      );
      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(recorder.row('/r/a/a1.txt')),
        tester.getCenter(recorder.row('/r/c')),
      );

      expect(dropTargetColorOf(tester), color);
      expect(
        tester.renderObject(recorder.row('/r/c')),
        paints..rect(color: color),
      );
      await gesture.up();
      await tester.pump();
    });

    testWidgets('does not rebuild the rows\' contents', (tester) async {
      final builds = <String, int>{};
      await tester.pumpWidget(
        DndHost(
          controller: controller,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
          ),
          rowContent: (row) => _CountingLabel(row.label, builds),
        ),
      );
      final before = Map<String, int>.of(builds);

      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(recorder.row('/r/a/a1.txt')),
        tester.getCenter(recorder.row('/r/b/b1.txt')),
      );
      for (final path in ['/r/c', '/r/b/sub', '/r/top.txt', '/r/b']) {
        await gesture.moveTo(tester.getCenter(recorder.row(path)));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      // The default feedback shows its own label; no row content rebuilt.
      expect(builds, before);
    });
  });

  group('auto-expand', () {
    late DirectoryTreeController<Object?> controller;
    late DndRecorder recorder;

    setUp(() {
      controller = controllerFor(sampleTree(), collapsed: ['/r/c']);
      recorder = DndRecorder(controller);
    });
    tearDown(() => controller.dispose());

    Future<TestGesture> dragOver(
      WidgetTester tester,
      String from,
      String to, {
      Duration? autoExpandDelay = const Duration(milliseconds: 700),
    }) async {
      await tester.pumpWidget(
        DndHost(
          controller: controller,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
            autoExpandDelay: autoExpandDelay,
          ),
        ),
      );
      return startMouseDrag(
        tester,
        tester.getCenter(recorder.row(from)),
        tester.getCenter(recorder.row(to)),
      );
    }

    testWidgets('expands a collapsed directory after the delay', (
      tester,
    ) async {
      final c = recorder.id('/r/c');
      final gesture = await dragOver(tester, '/r/a/a1.txt', '/r/c');
      // Moving within the row keeps the timer.
      await gesture.moveBy(const Offset(20, 3));
      await tester.pump(const Duration(milliseconds: 650));
      expect(controller.isExpanded(c), isFalse);

      await tester.pump(const Duration(milliseconds: 60));
      expect(controller.isExpanded(c), isTrue);
      await tester.pump();
      // The new row is in the target's block.
      expect(isTinted(tester, recorder.row('/r/c/c1.txt')), isTrue);

      await gesture.moveTo(tester.getCenter(recorder.row('/r/c/c1.txt')));
      await gesture.up();
      await tester.pump();
      expect(recorder.drops.single.target.path.toString(), '/r/c');
    });

    testWidgets('leaving the row before the delay keeps it collapsed', (
      tester,
    ) async {
      final gesture = await dragOver(tester, '/r/a/a1.txt', '/r/c');
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.moveTo(tester.getCenter(recorder.row('/r/top.txt')));
      await tester.pump(const Duration(seconds: 2));

      expect(controller.isExpanded(recorder.id('/r/c')), isFalse);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a null delay never expands', (tester) async {
      final gesture = await dragOver(
        tester,
        '/r/a/a1.txt',
        '/r/c',
        autoExpandDelay: null,
      );
      await tester.pump(const Duration(seconds: 5));

      expect(controller.isExpanded(recorder.id('/r/c')), isFalse);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a dragged directory never expands', (tester) async {
      controller.collapse(controller.tree.idOf('/r/b')!);
      final b = recorder.id('/r/b');
      final start = Offset(100, 4 * rowExtent + rowExtent / 2);
      await tester.pumpWidget(
        DndHost(
          controller: controller,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: recorder.onDrop,
          ),
        ),
      );
      expect(tester.getCenter(recorder.row('/r/b')).dy, start.dy);

      final gesture = await startMouseDrag(
        tester,
        start,
        start + const Offset(60, 0),
      );
      await tester.pump(const Duration(seconds: 2));

      expect(controller.isExpanded(b), isFalse);
      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
    });

    testWidgets('expanding a lazy directory loads it', (tester) async {
      final load = Completer<Iterable<TreeEntry<Object?>>>();
      final tree = DirectoryTree.fromPaths(const [
        '/r/',
        '/r/lazy/',
        '/r/x.txt',
      ]);
      final lazyController = DirectoryTreeController<Object?>(
        tree: tree,
        expansion: ExpansionState.withExpanded(tree.roots),
        loadChildren: (directory) => load.future,
      );
      addTearDown(lazyController.dispose);
      final lazyRecorder = DndRecorder(lazyController);
      final lazy = lazyRecorder.id('/r/lazy');
      await tester.pumpWidget(
        DndHost(
          controller: lazyController,
          dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
            onDrop: lazyRecorder.onDrop,
          ),
        ),
      );
      expect(lazyController.loadStatusOf(lazy), DirectoryLoadStatus.notLoaded);

      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(lazyRecorder.row('/r/x.txt')),
        tester.getCenter(lazyRecorder.row('/r/lazy')),
      );
      await tester.pump(const Duration(milliseconds: 710));
      expect(lazyController.loadStatusOf(lazy), DirectoryLoadStatus.loading);

      load.complete([TreeEntry<Object?>.file('/r/lazy/inside.txt')]);
      await tester.pump();
      await tester.pump();
      expect(lazyController.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      final inside = lazyRecorder.row('/r/lazy/inside.txt');
      expect(inside, findsOneWidget);
      expect(isTinted(tester, inside), isTrue);

      await gesture.moveTo(tester.getCenter(inside));
      await gesture.up();
      await tester.pump();
      expect(lazyRecorder.drops.single.target.path.toString(), '/r/lazy');
      expect(pathsOf(lazyRecorder.drops.single.nodes), ['/r/x.txt']);
    });
  });

  group('auto-scroll', () {
    late DirectoryTreeController<Object?> controller;
    late DndRecorder recorder;
    late ScrollController scroll;

    setUp(() {
      controller = controllerFor(bigTree());
      recorder = DndRecorder(controller);
      scroll = ScrollController();
    });
    tearDown(() {
      controller.dispose();
      scroll.dispose();
    });

    Future<void> pumpBigHost(WidgetTester tester) => tester.pumpWidget(
      DndHost(
        controller: controller,
        dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
          onDrop: recorder.onDrop,
          autoExpandDelay: null,
        ),
        scrollController: scroll,
        height: 300,
      ),
    );

    Future<void> pumpFrames(WidgetTester tester, int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    /// The directory a drop at [y] (global) goes to, from the rows.
    String targetAt(double y) {
      final row = controller.rows[(scroll.offset + y) ~/ rowExtent];
      final node = row.node;
      return node.isDirectory
          ? node.path.toString()
          : controller.tree[node.parent!]!.path.toString();
    }

    testWidgets('scrolls near the bottom edge and drops on the row under the '
        'pointer', (tester) async {
      await pumpBigHost(tester);
      final pressed = recorder.row('/r/d0/f01.txt');

      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(pressed),
        const Offset(200, 295),
      );
      await pumpFrames(tester, 100);
      expect(scroll.offset, greaterThan(600));
      // The pressed row scrolled away and was disposed; the drag goes on.
      expect(pressed, findsNothing);

      // Away from the edge, scrolling stops.
      await gesture.moveTo(const Offset(200, 150));
      await pumpFrames(tester, 3);
      final stopped = scroll.offset;
      await pumpFrames(tester, 20);
      expect(scroll.offset, stopped);

      final expected = targetAt(150);
      expect(expected, isNot('/r/d0'));
      // The tint followed the rows that moved under the pointer.
      expect(isTinted(tester, recorder.row(expected)), isTrue);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops.single.target.path.toString(), expected);
      expect(pathsOf(recorder.drops.single.nodes), ['/r/d0/f01.txt']);
    });

    testWidgets('while the list scrolls, the tint follows the rows and a '
        'release drops on the row under the pointer', (tester) async {
      await pumpBigHost(tester);
      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(recorder.row('/r/d0/f01.txt')),
        const Offset(200, 295),
      );
      // Past d0's eleven rows, so the rows under the pointer belong to
      // another folder; the auto-scroller is mid-step after every frame.
      await pumpFrames(tester, 40);
      expect(scroll.offset, greaterThan(11 * rowExtent));
      // The rows at least partly inside the 300-pixel viewport.
      final first = scroll.offset ~/ rowExtent;
      final last = (scroll.offset + 299) ~/ rowExtent;
      final visible = [
        for (var index = first; index <= last; index++)
          controller.rows[index].node.path.toString(),
      ];
      expect(
        visible.where((path) => isTinted(tester, recorder.row(path))),
        isNotEmpty,
      );

      final expected = targetAt(295);
      await gesture.up();
      await tester.pump();
      expect(recorder.drops.single.target.path.toString(), expected);
    });

    testWidgets('scrolls up near the top edge, faster past it', (tester) async {
      await pumpBigHost(tester);
      scroll.jumpTo(1500);
      await tester.pump();

      // 20 pixels from the edge: 10 pixels into the 30-pixel zone.
      final gesture = await startMouseDrag(
        tester,
        const Offset(200, 150),
        const Offset(200, 20),
      );
      await pumpFrames(tester, 20);
      final nearEdge = 1500 - scroll.offset;
      expect(nearEdge, greaterThan(0));

      await gesture.moveTo(const Offset(200, -40));
      await pumpFrames(tester, 20);
      final pastEdge = 1500 - nearEdge - scroll.offset;
      expect(pastEdge, greaterThan(nearEdge * 1.5));

      await gesture.up();
      await tester.pump();
    });

    testWidgets('does not scroll while the pointer is beside the list', (
      tester,
    ) async {
      await pumpBigHost(tester);

      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(recorder.row('/r/d0/f01.txt')),
        const Offset(listWidth + 50, 295),
      );
      await pumpFrames(tester, 20);
      expect(scroll.offset, 0);

      await gesture.up();
      await tester.pump();
      expect(recorder.drops, isEmpty);
    });

    testWidgets('a mouse wheel scroll during a drag moves the target with '
        'the rows', (tester) async {
      await pumpBigHost(tester);
      final gesture = await startMouseDrag(
        tester,
        tester.getCenter(recorder.row('/r/d0/f01.txt')),
        const Offset(200, 150),
      );
      expect(targetAt(150), '/r/d0');

      scroll.jumpTo(30 * rowExtent);
      // One frame lays the rows out at the new offset and hit tests again;
      // the next one paints the new tint.
      await tester.pump();
      await tester.pump();
      final expected = targetAt(150);
      expect(expected, isNot('/r/d0'));
      expect(isTinted(tester, recorder.row(expected)), isTrue);

      await gesture.up();
      await tester.pump();
      expect(recorder.drops.single.target.path.toString(), expected);
    });
  });
}

/// A label that counts its builds.
class _CountingLabel extends StatelessWidget {
  const _CountingLabel(this.label, this.builds);

  final String label;
  final Map<String, int> builds;

  @override
  Widget build(BuildContext context) {
    builds.update(label, (count) => count + 1, ifAbsent: () => 1);
    return Text(label);
  }
}
