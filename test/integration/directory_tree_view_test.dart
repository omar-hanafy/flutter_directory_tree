import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

void main() {
  group('pointer and keyboard', () {
    testWidgets('a click selects a row and gives the tree the keyboard', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(DirectoryTreeView<int>(controller: controller)),
      );
      await click(tester, rowCenter(tester, mainDart));
      expect(controller.selection.selected, {mainDart});
      expect(controller.focusedId, mainDart);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.focusedId, testDir);
      expect(controller.selection.selected, {testDir});
    });

    testWidgets('a double-click toggles a directory once, then activates', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            onActivate: (row) => activated.add(row.id),
          ),
        ),
      );
      await doubleClick(tester, rowCenter(tester, src));
      expect(controller.isExpanded(src), isFalse);
      expect(activated, [src]);
    });

    testWidgets('Enter activates the focused file through the view', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            onActivate: (row) => activated.add(row.id),
          ),
        ),
      );
      await click(tester, rowCenter(tester, readme));
      await press(tester, LogicalKeyboardKey.enter);
      expect(activated, [readme]);
    });

    testWidgets('selectOnTap false only focuses, onRowTap follows', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final tapped = <NodeId>[];
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            selectOnTap: false,
            onRowTap: (row) => tapped.add(row.id),
          ),
        ),
      );
      await click(tester, rowCenter(tester, aDart));
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, aDart);
      expect(tapped, [aDart]);
    });

    testWidgets('an external focus node is the keyboard focus node', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(controller: controller, focusNode: focusNode),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.focusedId, repo);
      await click(tester, rowCenter(tester, readme));
      expect(focusNode.hasPrimaryFocus, isTrue);
    });

    testWidgets('autofocus focuses the tree', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(controller: controller, autofocus: true),
        ),
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.end);
      expect(controller.focusedId, readme);
    });
  });

  group('context menu', () {
    testWidgets('a secondary click selects, reports, then opens the menu', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final reports = <(NodeId, Offset)>[];
      List<NodeId>? menuNodes;
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            onRowSecondaryTap: (row, position) =>
                reports.add((row.id, position)),
            contextMenuBuilder: (context, details) {
              menuNodes = idsOf(details.nodes);
              return [
                MenuItemButton(onPressed: () {}, child: const Text('Rename')),
              ];
            },
          ),
        ),
      );
      final position = rowCenter(tester, aDart);
      await rightClick(tester, position);
      expect(controller.selection.selected, {aDart});
      expect(reports, [(aDart, position)]);
      expect(find.text('Rename'), findsOneWidget);
      expect(menuNodes, [aDart]);
    });

    testWidgets('a secondary click on a selected row acts on the selection', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      List<NodeId>? menuNodes;
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            contextMenuBuilder: (context, details) {
              menuNodes = idsOf(details.nodes);
              return [
                MenuItemButton(onPressed: () {}, child: const Text('Delete')),
              ];
            },
          ),
        ),
      );
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: [readme, aDart],
      );
      await tester.pump();
      await rightClick(tester, rowCenter(tester, readme));
      expect(menuNodes, [aDart, readme]);
      expect(controller.selection.selected, {aDart, readme});
    });

    testWidgets('Shift+F10 opens the menu of the focused row', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            contextMenuBuilder: (context, details) => [
              MenuItemButton(
                onPressed: () {},
                child: Text('Open ${details.row.label}'),
              ),
            ],
          ),
        ),
      );
      await click(tester, rowCenter(tester, bDart));
      await pressWith(
        tester,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.f10,
      );
      expect(find.text('Open b.dart'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Open b.dart'), findsNothing);
    });

    testWidgets(
      'without a menu builder, Shift+F10 reports the focused row corner',
      (tester) async {
        final controller = expandedController();
        addTearDown(controller.dispose);
        final reports = <(NodeId, Offset)>[];
        await tester.pumpWidget(
          hostApp(
            DirectoryTreeView<int>(
              controller: controller,
              onRowSecondaryTap: (row, position) =>
                  reports.add((row.id, position)),
            ),
          ),
        );
        await click(tester, rowCenter(tester, mainDart));
        await pressWith(
          tester,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.f10,
        );
        expect(reports, [(mainDart, tester.getBottomLeft(rowOf(mainDart)))]);
      },
    );
  });

  group('drag and drop', () {
    testWidgets('a mouse drag drops the row onto a directory', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final drops = <DirectoryTreeDropDetails<int>>[];
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            dragAndDrop: DirectoryTreeDragAndDrop<int>(onDrop: drops.add),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        rowCenter(tester, aDart),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(rowCenter(tester, testDir));
      await tester.pump();
      await gesture.moveTo(rowCenter(tester, testDir) + const Offset(0, 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(drops, hasLength(1));
      expect(idsOf(drops.single.nodes), [aDart]);
      expect(drops.single.target.id, testDir);
    });

    testWidgets('a touch long-press without moving opens the menu', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final drops = <DirectoryTreeDropDetails<int>>[];
      final reports = <NodeId>[];
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            dragAndDrop: DirectoryTreeDragAndDrop<int>(onDrop: drops.add),
            onRowSecondaryTap: (row, position) => reports.add(row.id),
            contextMenuBuilder: (context, details) => [
              MenuItemButton(onPressed: () {}, child: const Text('Copy')),
            ],
          ),
        ),
      );
      final gesture = await tester.startGesture(rowCenter(tester, bDart));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(drops, isEmpty);
      expect(reports, [bDart]);
      expect(controller.selection.selected, {bDart});
      expect(find.text('Copy'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('emptyBuilder shows for an empty tree and for no matches', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            emptyBuilder: (context) => const Text('Nothing here'),
          ),
        ),
      );
      expect(find.text('Nothing here'), findsNothing);
      controller.query = 'no-such-name';
      await tester.pump();
      expect(find.text('Nothing here'), findsOneWidget);
      expect(rowOf(repo), findsNothing);
      controller.query = '';
      await tester.pump();
      expect(find.text('Nothing here'), findsNothing);
      expect(rowOf(repo), findsOneWidget);
      controller.tree = DirectoryTree<int>.empty();
      await tester.pump();
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('padding insets the rows inside the scroll view', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            padding: const EdgeInsets.only(top: 12, left: 8),
          ),
        ),
      );
      expect(tester.getTopLeft(rowOf(repo)), const Offset(8, 12));
    });

    testWidgets('showScrollbar adds one scrollbar, false removes all', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      // Material and Cupertino scrollbars both extend RawScrollbar.
      final scrollbars = find.byWidgetPredicate(
        (widget) => widget is RawScrollbar,
      );
      await tester.pumpWidget(
        hostApp(DirectoryTreeView<int>(controller: controller)),
      );
      expect(scrollbars, findsOneWidget);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(controller: controller, showScrollbar: false),
        ),
      );
      expect(scrollbars, findsNothing);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('an external scroll controller drives the rows', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            scrollController: scrollController,
          ),
        ),
      );
      scrollController.jumpTo(rowExtent * 50);
      await tester.pump();
      expect(tester.getTopLeft(rowOf(wideId(49))).dy, 0);
      // Swapping in another controller keeps the view working.
      final other = ScrollController();
      addTearDown(other.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            scrollController: other,
          ),
        ),
      );
      other.jumpTo(0);
      await tester.pump();
      expect(tester.getTopLeft(rowOf(wideDir)).dy, 0);
    });

    testWidgets('semanticLabel names the tree', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            semanticLabel: 'Project files',
          ),
        ),
      );
      expect(find.bySemanticsLabel('Project files'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('levelSemanticsHint localizes the row hints', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            levelSemanticsHint: (level) => 'Niveau $level',
          ),
        ),
      );
      expect(
        tester.getSemantics(rowOf(lib)),
        matchesSemantics(
          label: 'lib',
          hint: 'Niveau 2',
          isSelected: false,
          isExpanded: true,
          hasExpandedState: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a new controller takes over the rows', (tester) async {
      final first = expandedController();
      addTearDown(first.dispose);
      final second = wideController(3);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: first,
            emptyBuilder: (context) => const Text('Empty'),
          ),
        ),
      );
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: second,
            emptyBuilder: (context) => const Text('Empty'),
          ),
        ),
      );
      expect(rowOf(repo), findsNothing);
      expect(rowOf(wideDir), findsOneWidget);
      second.query = 'missing';
      await tester.pump();
      expect(find.text('Empty'), findsOneWidget);
      // The old controller no longer drives the view.
      first.query = 'missing';
      second.query = '';
      await tester.pump();
      expect(find.text('Empty'), findsNothing);
    });
  });

  group('large trees', () {
    testWidgets('100k rows build only what is visible while jumping', (
      tester,
    ) async {
      final controller = wideController(100000);
      addTearDown(controller.dispose);
      final counter = BuildCounter<int>();
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            rowBuilder: counter.build,
          ),
        ),
      );
      // Ten visible rows plus the default cache extent (250 px) on each
      // side bound every frame's work.
      const bound = (viewportHeight + 2 * 250) ~/ rowExtent + 2;
      expect(counter.take().length, lessThanOrEqualTo(bound));
      final position = scrollPositionOf(tester);
      for (final row in [99990, 50000, 12345, 0, 75000]) {
        position.jumpTo(row * rowExtent);
        await tester.pump();
        expect(counter.take().length, lessThanOrEqualTo(bound));
        expect(rowOf(wideId(row - 1 < 0 ? 0 : row - 1)), findsOneWidget);
      }
      // A selection change rebuilds only the rows whose details changed.
      controller.select(wideId(75000));
      await tester.pump();
      expect(counter.take(), {wideId(75000)});
    });
  });
}
