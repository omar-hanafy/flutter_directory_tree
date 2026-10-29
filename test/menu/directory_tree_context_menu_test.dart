import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_context_menu.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_test_utils.dart';

void main() {
  late DirectoryTreeController<int> controller;
  late FocusNode treeFocus;
  late MenuLog log;

  setUp(() {
    controller = expandedController();
    treeFocus = FocusNode(debugLabel: 'tree');
    log = MenuLog();
  });

  tearDown(() {
    controller.dispose();
    treeFocus.dispose();
  });

  group('opening at a position', () {
    testWidgets('a right-click opens the menu of the row with its top-left '
        'corner at the pointer', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final point = rowCenter(tester, lib);

      await rightClick(tester, point);

      expect(menuState(tester).isOpen, isTrue);
      expect(menuLabels(tester), ['Rename lib', 'Delete 1', 'Copy path']);
      expect(log.opened, hasLength(1));
      expect(log.opened.single.row.id, lib);
      expect(log.opened.single.globalPosition, point);
      expect(identical(log.opened.single.controller, controller), isTrue);
      // The anchor is a zero-size box at the pointer, not the whole tree.
      expect(
        tester.getRect(find.byType(MenuAnchor)),
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
      );
      final first = itemRect(tester, 'Rename lib');
      expect(first.left, moreOrLessEquals(point.dx));
      expect(first.top, greaterThanOrEqualTo(point.dy));
      // Only the panel's top padding separates the item from the pointer.
      expect(first.top - point.dy, lessThan(16));
      expect(tester.takeException(), isNull);
    });

    testWidgets('in right-to-left text the menu ends at the pointer', (
      tester,
    ) async {
      await tester.pumpWidget(
        menuApp(
          controller: controller,
          builder: log.builder(),
          textDirection: TextDirection.rtl,
        ),
      );
      // Far enough from the left edge for the menu to fit before the point.
      final point = rowCenter(tester, src) + const Offset(120, 0);

      await rightClick(tester, point);

      final first = itemRect(tester, 'Rename src');
      expect(first.right, moreOrLessEquals(point.dx));
      expect(first.top, greaterThanOrEqualTo(point.dy));
      expect(first.top - point.dy, lessThan(16));
    });

    testWidgets('a menu that does not fit below the position opens above '
        'it, next to the position', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      const point = Offset(120, 580);

      menuState(tester)
          .open(row: controller.rows.rowOf(lib)!, globalPosition: point);
      await tester.pump();

      final last = itemRect(tester, 'Copy path');
      expect(last.bottom, lessThanOrEqualTo(point.dy));
      // Only the panel's bottom padding separates the item from the point.
      expect(point.dy - last.bottom, lessThan(16));
      expect(itemRect(tester, 'Rename lib').left, moreOrLessEquals(point.dx));
    });

    testWidgets('open is effective immediately and the menu appears in the '
        'next frame', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      expect(state.isOpen, isFalse);

      state.open(
        row: controller.rows.rowOf(testDir)!,
        globalPosition: const Offset(40, 200),
      );

      expect(state.isOpen, isTrue);
      expect(find.byType(MenuItemButton), findsNothing);
      await tester.pump();
      expect(menuLabels(tester), ['Rename test', 'Delete 1', 'Copy path']);
    });
  });

  group('details and selection', () {
    testWidgets('opening on a row that is not selected selects it and the '
        'menu acts on that row', (tester) async {
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: const [lib, testDir],
        anchor: lib,
      );
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );

      await rightClick(tester, rowCenter(tester, src));

      expect(controller.selection.selected, {src});
      expect(controller.focusedId, src);
      final details = log.opened.single;
      expect(details.nodes.map((node) => node.id), [src]);
      expect(details.row.id, src);
      expect(() => details.nodes.add(details.row.node), throwsUnsupportedError);
      expect(menuLabels(tester), contains('Delete 1'));
    });

    testWidgets('opening on a selected row keeps the selection and the menu '
        'acts on all of it in pre-order', (tester) async {
      // Selected in reverse order, with a.dart hidden in a collapsed src.
      controller
        ..selection = SelectionState(
          mode: SelectionMode.multiple,
          selected: const [readme, aDart, lib],
          anchor: readme,
        )
        ..collapse(src);
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );

      await rightClick(tester, rowCenter(tester, readme));

      expect(controller.selection.selected, {readme, aDart, lib});
      final details = log.opened.single;
      expect(details.row.id, readme);
      expect(details.nodes.map((node) => node.id), [lib, aDart, readme]);
      expect(details.nodes, controller.selectedNodes);
      expect(menuLabels(tester), contains('Delete 3'));
    });

    testWidgets('a row the selectable predicate rejects stays unselected '
        'and the menu acts on it alone', (tester) async {
      controller.dispose();
      controller = expandedController(
        selectable: (node) => node is FileNode<int>,
      );
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: const [mainDart, readme],
        anchor: mainDart,
      );
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );

      await rightClick(tester, rowCenter(tester, lib));

      expect(controller.selection.selected, {mainDart, readme});
      expect(controller.focusedId, lib);
      expect(log.opened.single.nodes.map((node) => node.id), [lib]);
      expect(menuState(tester).isOpen, isTrue);
    });

    testWidgets('the details hold the current row of the node', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final stale = controller.rows.rowOf(src)!;
      controller.collapse(src);
      await tester.pump();

      menuState(tester).open(row: stale, globalPosition: const Offset(50, 75));
      await tester.pump();

      final details = log.opened.single;
      expect(details.row.isExpanded, isFalse);
      expect(identical(details.row, controller.rows.rowOf(src)), isTrue);
    });

    testWidgets('a row whose node left the tree opens nothing', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final stale = controller.rows.rowOf(readme)!;
      controller.updateTree((builder) => builder.remove('/repo/README.md'));
      await tester.pump();

      menuState(tester).open(row: stale, globalPosition: const Offset(50, 75));
      await tester.pump();

      expect(menuState(tester).isOpen, isFalse);
      expect(log.opened, isEmpty);
      expect(find.byType(MenuItemButton), findsNothing);
    });
  });

  group('an empty builder result', () {
    testWidgets('opens nothing', (tester) async {
      await tester.pumpWidget(
        menuApp(
          controller: controller,
          builder: log.builder(emptyFor: (row) => row.node is FileNode<int>),
        ),
      );

      await rightClick(tester, rowCenter(tester, readme));

      expect(log.opened.single.row.id, readme);
      expect(controller.selection.selected, {readme});
      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closes the menu that is open', (tester) async {
      await tester.pumpWidget(
        menuApp(
          controller: controller,
          builder: log.builder(emptyFor: (row) => row.node is FileNode<int>),
        ),
      );
      await rightClick(tester, rowCenter(tester, lib));
      expect(menuLabels(tester), contains('Rename lib'));

      menuState(tester).open(
        row: controller.rows.rowOf(readme)!,
        globalPosition: const Offset(30, 255),
      );
      await tester.pump();

      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
    });
  });

  group('one menu at a time', () {
    for (final trigger in OpenTrigger.values) {
      testWidgets('a right-click on a second row replaces the first menu '
          '(opened on ${trigger.name})', (tester) async {
        await tester.pumpWidget(
          menuApp(
            controller: controller,
            builder: log.builder(),
            treeFocus: treeFocus,
            trigger: trigger,
          ),
        );
        treeFocus.requestFocus();
        await tester.pump();

        // The first menu covers x >= 210 from y 45 down; the second click
        // is on a row to its left.
        await rightClick(tester, rowCenter(tester, lib) + const Offset(60, 0));
        expect(menuLabels(tester), ['Rename lib', 'Delete 1', 'Copy path']);

        final second = Offset(40, rowCenter(tester, mainDart).dy);
        expect(menuPanelRect(tester).contains(second), isFalse);
        await rightClick(tester, second);

        expect(menuState(tester).isOpen, isTrue);
        expect(find.byType(MenuAnchor), findsOneWidget);
        expect(menuLabels(tester), [
          'Rename main.dart',
          'Delete 1',
          'Copy path',
        ]);
        expect(
          tester.getRect(find.byType(MenuAnchor)),
          Rect.fromLTWH(second.dx, second.dy, 0, 0),
        );
        expect(itemHasFocus(tester, 'Rename main.dart'), isTrue);
        expect(log.opened.map((details) => details.row.id), [lib, mainDart]);
        // Another frame changes nothing: no late close of the new menu.
        await tester.pump(const Duration(milliseconds: 500));
        expect(menuLabels(tester), [
          'Rename main.dart',
          'Delete 1',
          'Copy path',
        ]);

        // The first menu's focus was the tree's, and closing returns it.
        await press(tester, LogicalKeyboardKey.escape);
        expect(menuState(tester).isOpen, isFalse);
        expect(treeFocus.hasPrimaryFocus, isTrue);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('open while a menu is open replaces it', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      state.open(
        row: controller.rows.rowOf(lib)!,
        globalPosition: const Offset(40, 40),
      );
      await tester.pump();

      state.open(
        row: controller.rows.rowOf(testDir)!,
        globalPosition: const Offset(60, 190),
      );
      await tester.pump();
      await tester.pump();

      expect(state.isOpen, isTrue);
      expect(menuLabels(tester), ['Rename test', 'Delete 1', 'Copy path']);
      expect(
        tester.getRect(find.byType(MenuAnchor)),
        const Rect.fromLTWH(60, 190, 0, 0),
      );
      expect(itemHasFocus(tester, 'Rename test'), isTrue);
    });

    testWidgets('close then open in the same event shows the new menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      state.open(
        row: controller.rows.rowOf(lib)!,
        globalPosition: const Offset(40, 40),
      );
      await tester.pump();

      state
        ..close()
        ..open(
          row: controller.rows.rowOf(readme)!,
          globalPosition: const Offset(40, 250),
        );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(state.isOpen, isTrue);
      expect(menuLabels(tester), ['Rename README.md', 'Delete 1', 'Copy path']);
    });
  });

  group('closing', () {
    testWidgets('close hides the menu; isOpen turns false at once', (
      tester,
    ) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      await rightClick(tester, rowCenter(tester, lib));
      expect(state.isOpen, isTrue);

      state.close();

      expect(state.isOpen, isFalse);
      await tester.pump();
      expect(find.byType(MenuItemButton), findsNothing);
      // Closing twice is harmless.
      state.close();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('isOpen turns false as soon as the menu starts closing by '
        'itself', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      await rightClick(tester, rowCenter(tester, lib));

      // What an item, Escape, or a tap outside does: ask the menu's own
      // controller to close. The menu hides a microtask later.
      MenuController.maybeOf(tester.element(find.text('Copy path')))!.close();

      expect(state.isOpen, isFalse);
      expect(find.text('Copy path'), findsOneWidget);
      await tester.pump();
      expect(find.text('Copy path'), findsNothing);
      expect(state.isOpen, isFalse);
    });

    testWidgets('close before the menu appeared opens nothing', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);

      state
        ..open(
          row: controller.rows.rowOf(lib)!,
          globalPosition: const Offset(40, 40),
        )
        ..close();
      await tester.pump();
      await tester.pump();

      expect(state.isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('a click outside the menu closes it, and a click on another '
        'row reaches the row', (tester) async {
      final tapped = <NodeId>[];
      await tester.pumpWidget(
        menuApp(
          controller: controller,
          builder: log.builder(),
          onRowTap: tapped.add,
        ),
      );
      await rightClick(tester, rowCenter(tester, lib));
      expect(menuState(tester).isOpen, isTrue);

      // README.md (row 8) is below the menu, which ends near y 220.
      await click(tester, rowCenter(tester, readme));

      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tapped, [readme]);
    });

    testWidgets('a right-click outside the tree closes the menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      await rightClick(tester, rowCenter(tester, lib));

      await rightClick(tester, const Offset(600, 500));

      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(log.opened, hasLength(1));
    });

    testWidgets('choosing an item with the mouse runs it and closes the '
        'menu', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      await rightClick(tester, rowCenter(tester, lib));

      await click(tester, tester.getCenter(find.text('Copy path')));

      expect(log.pressed, ['copy path']);
      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('the user scrolling the tree closes the menu', (tester) async {
      await tester.pumpWidget(
        menuApp(
          controller: controller,
          builder: log.builder(),
          wrapTree: (rows) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 120,
              child: SingleChildScrollView(child: rows),
            ),
          ),
        ),
      );
      await rightClick(tester, rowCenter(tester, lib) + const Offset(80, 0));
      expect(menuState(tester).isOpen, isTrue);

      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(20, 100)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
      await tester.pump();
      await tester.pump();

      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('replacing the controller closes the menu', (tester) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      await rightClick(tester, rowCenter(tester, lib));
      final state = menuState(tester);
      final other = expandedController();
      addTearDown(other.dispose);

      await tester.pumpWidget(
        menuApp(controller: other, builder: log.builder()),
      );
      await tester.pump();

      expect(identical(menuState(tester), state), isTrue);
      expect(state.isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing the host while the menu is open is safe', (
      tester,
    ) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      await rightClick(tester, rowCenter(tester, lib));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(find.byType(MenuItemButton), findsNothing);
      expect(state.mounted, isFalse);
      // Calls on an unmounted state do nothing.
      state.open(row: controller.rows.rowOf(lib)!, globalPosition: Offset.zero);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('maybeOf', () {
    testWidgets('finds the host from inside its child and from a menu item', (
      tester,
    ) async {
      await tester.pumpWidget(
        menuApp(controller: controller, builder: log.builder()),
      );
      final state = menuState(tester);
      final inside = tester.element(find.text('lib'));

      expect(DirectoryTreeContextMenu.maybeOf<int>(inside), same(state));
      expect(DirectoryTreeContextMenu.maybeOf<Object?>(inside), same(state));
      expect(DirectoryTreeContextMenu.maybeOf<String>(inside), isNull);
      // The page's Material is above the host.
      final above = tester.element(find.byType(Material).first);
      expect(DirectoryTreeContextMenu.maybeOf<int>(above), isNull);

      await rightClick(tester, rowCenter(tester, lib));
      final item = tester.element(find.text('Copy path'));
      expect(DirectoryTreeContextMenu.maybeOf<int>(item), same(state));
    });
  });

  testWidgets('debugFillProperties describes the controller, the builder, '
      'and whether a menu is open', (tester) async {
    final widget = DirectoryTreeContextMenu<int>(
      controller: controller,
      builder: log.builder(),
      child: const SizedBox(),
    );
    final builder = DiagnosticPropertiesBuilder();
    widget.debugFillProperties(builder);
    final names = [for (final property in builder.properties) property.name];
    expect(names, containsAll(<String>['controller', 'builder']));

    await tester.pumpWidget(
      menuApp(controller: controller, builder: log.builder()),
    );
    await rightClick(tester, rowCenter(tester, lib));
    expect(menuState(tester).toString(), contains('open'));
  });
}
