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

  Future<void> pumpHost(
    WidgetTester tester, {
    bool Function(List<TreeNode<Object?>> nodes)? canDrag,
    bool Function(DirectoryTreeDropDetails<Object?> details)? canDrop,
    Widget Function(TreeRow<Object?> row)? rowContent,
  }) => tester.pumpWidget(
    DndHost(
      controller: controller,
      dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
        onDrop: recorder.onDrop,
        canDrag: canDrag,
        canDrop: canDrop,
      ),
      onLongPressWithoutDrag: recorder.onLongPress,
      rowContent: rowContent,
    ),
  );

  Offset center(WidgetTester tester, String path) =>
      tester.getCenter(recorder.row(path));

  /// Drags the row [from] to the row [to] with a mouse and releases it.
  Future<void> mouseDrop(WidgetTester tester, String from, String to) async {
    final gesture = await startMouseDrag(
      tester,
      center(tester, from),
      center(tester, to),
    );
    await gesture.up();
    await tester.pump();
  }

  void select(List<String> paths) {
    controller.selection = SelectionState(
      mode: SelectionMode.multiple,
      selected: [for (final path in paths) recorder.id(path)],
    );
  }

  group('dragged nodes', () {
    testWidgets('dragging an unselected row drags only its node', (
      tester,
    ) async {
      select(['/r/a/a2.txt', '/r/b']);
      await pumpHost(tester);

      await mouseDrop(tester, '/r/a/a1.txt', '/r/c');

      expect(recorder.drops, hasLength(1));
      expect(pathsOf(recorder.drops.single.nodes), ['/r/a/a1.txt']);
      expect(recorder.drops.single.target.path.toString(), '/r/c');
      // Dragging changes neither the selection nor the tree.
      expect(controller.selection.selected, {
        recorder.id('/r/a/a2.txt'),
        recorder.id('/r/b'),
      });
      expect(controller.tree.contains(recorder.id('/r/a/a1.txt')), isTrue);
    });

    testWidgets('dragging a selected row drags the selection in pre-order, '
        'without the nodes inside another dragged node', (tester) async {
      // Selected in scrambled order: s1.txt is inside the selected b, and
      // c1.txt has no row because c is collapsed.
      select([
        '/r/top.txt',
        '/r/b/sub/s1.txt',
        '/r/b',
        '/r/c/c1.txt',
        '/r/a/a2.txt',
      ]);
      await pumpHost(tester);

      await mouseDrop(tester, '/r/a/a2.txt', '/r/c');

      expect(recorder.drops, hasLength(1));
      final drop = recorder.drops.single;
      expect(pathsOf(drop.nodes), [
        '/r/a/a2.txt',
        '/r/b',
        '/r/c/c1.txt',
        '/r/top.txt',
      ]);
      expect(drop.target.path.toString(), '/r/c');
      expect(() => drop.nodes.add(drop.target), throwsUnsupportedError);
    });

    testWidgets('a selected row inside a selected directory drags that '
        'directory', (tester) async {
      select(['/r/b', '/r/b/sub/s1.txt']);
      await pumpHost(tester);

      await mouseDrop(tester, '/r/b/sub/s1.txt', '/r/a');

      expect(pathsOf(recorder.drops.single.nodes), ['/r/b']);
      expect(recorder.drops.single.target.path.toString(), '/r/a');
    });
  });

  group('targets', () {
    testWidgets('a drop on a directory row targets that directory', (
      tester,
    ) async {
      await pumpHost(tester);

      await mouseDrop(tester, '/r/top.txt', '/r/b/sub');

      expect(recorder.drops.single.target.path.toString(), '/r/b/sub');
      expect(recorder.drops.single.target, isA<DirectoryNode<Object?>>());
    });

    testWidgets('a drop on a file row targets the file\'s directory', (
      tester,
    ) async {
      await pumpHost(tester);

      await mouseDrop(tester, '/r/top.txt', '/r/b/sub/s1.txt');
      await mouseDrop(tester, '/r/a/a1.txt', '/r/b/b1.txt');

      expect(
        [for (final drop in recorder.drops) drop.target.path.toString()],
        ['/r/b/sub', '/r/b'],
      );
      expect(
        [for (final drop in recorder.drops) pathsOf(drop.nodes)],
        [
          ['/r/top.txt'],
          ['/r/a/a1.txt'],
        ],
      );
    });

    testWidgets('a drop on a compacted row targets its deepest directory', (
      tester,
    ) async {
      controller.tree = DirectoryTree.fromPaths(const [
        '/r/',
        '/r/lib/src/utils/u.dart',
        '/r/x.txt',
      ]);
      controller
        ..compactFolders = true
        ..expandAll();
      await pumpHost(tester);
      // One row stands for lib, src, and utils; its id is utils'.
      final compacted = recorder.row('/r/lib/src/utils');
      expect(find.text('lib/src/utils'), findsOneWidget);

      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/x.txt'),
        tester.getCenter(compacted),
      );
      expect(isTinted(tester, compacted), isTrue);
      expect(isTinted(tester, recorder.row('/r/lib/src/utils/u.dart')), isTrue);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops.single.target.path.toString(), '/r/lib/src/utils');
    });

    testWidgets('the space below the rows is no target', (tester) async {
      await pumpHost(tester);

      // The ten rows end at y = 300; the list is 600 pixels high.
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        const Offset(200, 450),
      );
      expect(find.text('a1.txt'), findsNWidgets(2), reason: 'dragging');
      await gesture.up();
      await tester.pump();

      expect(recorder.drops, isEmpty);
    });

    testWidgets('with hidden roots, a depth-0 file row targets the hidden '
        'root', (tester) async {
      controller.showRoots = false;
      await pumpHost(tester);
      expect(recorder.row('/r'), findsNothing);

      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/top.txt'),
      );
      // The whole list is the root's block.
      expect(isTinted(tester, recorder.row('/r/a')), isTrue);
      expect(isTinted(tester, recorder.row('/r/top.txt')), isTrue);
      await gesture.up();
      await tester.pump();

      expect(recorder.drops.single.target.path.toString(), '/r');
    });
  });

  group('default canDrop', () {
    testWidgets('refuses a dragged directory and every directory inside it', (
      tester,
    ) async {
      await pumpHost(tester);
      final b = center(tester, '/r/b');

      // On itself, after moving far enough to start the drag.
      final gesture = await startMouseDrag(tester, b, b + const Offset(40, 0));
      await gesture.up();
      await tester.pump();
      await mouseDrop(tester, '/r/b', '/r/b/sub');
      await mouseDrop(tester, '/r/b', '/r/b/sub/s1.txt');
      await mouseDrop(tester, '/r/b', '/r/b/b1.txt');

      expect(recorder.drops, isEmpty);
    });

    testWidgets('refuses the directory that already holds every dragged '
        'node', (tester) async {
      await pumpHost(tester);

      await mouseDrop(tester, '/r/a/a1.txt', '/r/a');
      await mouseDrop(tester, '/r/a/a1.txt', '/r/a/a2.txt');
      select(['/r/a/a1.txt', '/r/a/a2.txt']);
      await tester.pump();
      await mouseDrop(tester, '/r/a/a1.txt', '/r/a');
      expect(recorder.drops, isEmpty);

      // a holds a1.txt but not b1.txt, so the move changes something.
      select(['/r/a/a1.txt', '/r/b/b1.txt']);
      await tester.pump();
      await mouseDrop(tester, '/r/a/a1.txt', '/r/a');

      expect(recorder.drops, hasLength(1));
      expect(pathsOf(recorder.drops.single.nodes), [
        '/r/a/a1.txt',
        '/r/b/b1.txt',
      ]);
      expect(recorder.drops.single.target.path.toString(), '/r/a');
    });
  });

  group('canDrag', () {
    testWidgets('gets the nodes once per drag and can refuse it', (
      tester,
    ) async {
      final asked = <List<String>>[];
      await pumpHost(
        tester,
        canDrag: (nodes) {
          asked.add(pathsOf(nodes));
          return nodes.every((node) => node.isFile);
        },
      );

      await mouseDrop(tester, '/r/b', '/r/a');
      expect(find.text('b'), findsOneWidget, reason: 'no feedback');
      expect(recorder.drops, isEmpty);

      select(['/r/a/a1.txt', '/r/top.txt']);
      await tester.pump();
      await mouseDrop(tester, '/r/top.txt', '/r/b');

      expect(asked, [
        ['/r/b'],
        ['/r/a/a1.txt', '/r/top.txt'],
      ]);
      expect(pathsOf(recorder.drops.single.nodes), [
        '/r/a/a1.txt',
        '/r/top.txt',
      ]);
    });

    testWidgets('a refused drag leaves the press to the row\'s own '
        'gestures', (tester) async {
      final taps = <String>[];
      await pumpHost(
        tester,
        canDrag: (nodes) => nodes.single.name != 'a1.txt',
        rowContent: (row) => GestureDetector(
          onTap: () => taps.add(row.label),
          child: Text(row.label),
        ),
      );

      // 10 pixels is past the drag slop but within the tap slop.
      for (final path in ['/r/a/a1.txt', '/r/a/a2.txt']) {
        final start = center(tester, path);
        final gesture = await startMouseDrag(
          tester,
          start,
          start + const Offset(10, 0),
        );
        await gesture.up();
        await tester.pump();
      }

      // a1.txt may not be dragged, so its press stayed a tap; a2.txt was
      // dragged, which cancelled its tap.
      expect(taps, ['a1.txt']);
      expect(recorder.drops, isEmpty);
    });
  });

  group('canDrop', () {
    testWidgets('decides for every target outside the dragged nodes', (
      tester,
    ) async {
      final asked = <String>[];
      await pumpHost(
        tester,
        canDrop: (details) {
          asked.add(details.target.name);
          return details.target.name != 'c';
        },
      );

      await mouseDrop(tester, '/r/a/a1.txt', '/r/c');
      // The same parent is allowed: a custom canDrop replaces that rule.
      await mouseDrop(tester, '/r/a/a1.txt', '/r/a');
      // A directory inside the dragged one is refused without asking.
      await mouseDrop(tester, '/r/b', '/r/b/sub');

      expect(
        [for (final drop in recorder.drops) drop.target.path.toString()],
        ['/r/a'],
      );
      expect(asked, isNot(contains('sub')));
      expect(asked.toSet(), {'c', 'a'});
    });

    testWidgets('is asked when the target changes and on release, not on '
        'every move', (tester) async {
      var asked = 0;
      await pumpHost(
        tester,
        canDrop: (details) {
          asked++;
          return true;
        },
      );
      final gesture = await startMouseDrag(
        tester,
        center(tester, '/r/a/a1.txt'),
        center(tester, '/r/b'),
      );
      expect(asked, 1);

      // Within the row of b, then to b1.txt, whose target is b as well.
      await gesture.moveBy(const Offset(30, 2));
      await gesture.moveBy(const Offset(-60, 3));
      await gesture.moveTo(center(tester, '/r/b/b1.txt'));
      await tester.pump();
      expect(asked, 1);

      await gesture.moveTo(center(tester, '/r/c'));
      await gesture.moveTo(center(tester, '/r/b'));
      await tester.pump();
      expect(asked, 3);

      await gesture.up();
      await tester.pump();
      expect(asked, 4, reason: 'checked again on release');
      expect(recorder.drops.single.target.path.toString(), '/r/b');
    });
  });

  testWidgets('onDrop runs after the drag ended, and a new tree from it is '
      'shown', (tester) async {
    late DirectoryTreeDropDetails<Object?> received;
    await tester.pumpWidget(
      DndHost(
        controller: controller,
        dragAndDrop: DirectoryTreeDragAndDrop<Object?>(
          onDrop: (details) {
            received = details;
            // Move a1.txt into the target, as an app would.
            final node = details.nodes.single;
            controller.updateTree(
              (builder) => builder
                ..remove(node.path.toString())
                ..addFile('${details.target.path}/${node.name}'),
            );
          },
        ),
      ),
    );

    await mouseDrop(tester, '/r/a/a1.txt', '/r/b');

    expect(pathsOf(received.nodes), ['/r/a/a1.txt']);
    expect(recorder.row('/r/a/a1.txt'), findsNothing);
    expect(recorder.row('/r/b/a1.txt'), findsOneWidget);
    expect(find.text('a1.txt'), findsOneWidget, reason: 'feedback removed');
    expect(isTinted(tester, recorder.row('/r/b')), isFalse);
  });
}
