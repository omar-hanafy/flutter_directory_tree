import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
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

  /// Pumps the app with the tree focused and [focused] as the focused row.
  Future<void> pumpFocused(
    WidgetTester tester, {
    NodeId? focused = src,
    Rect? Function(int index)? viewportRect = rowRect,
    TextDirection textDirection = TextDirection.ltr,
    Widget Function(Widget host)? wrapHost,
    Widget? outside,
    ValueChanged<NodeId>? onRowTap,
    DirectoryTreeMenuBuilder<int>? builder,
  }) async {
    controller.focus(focused);
    await tester.pumpWidget(
      menuApp(
        controller: controller,
        builder: builder ?? log.builder(treeFocus: treeFocus),
        treeFocus: treeFocus,
        viewportRect: viewportRect,
        textDirection: textDirection,
        wrapHost: wrapHost,
        outside: outside,
        onRowTap: onRowTap,
      ),
    );
    treeFocus.requestFocus();
    await tester.pump();
  }

  group('OpenTreeContextMenuIntent', () {
    testWidgets('opens the menu of the focused row just below the rect its '
        'viewport reports', (tester) async {
      // An offset rect, so the menu provably follows the viewport.
      Rect reported(int index) =>
          Rect.fromLTWH(12, rowExtent * index + 3, 220, 24);
      await pumpFocused(tester, viewportRect: reported);

      expect(await pressShiftF10(tester), isTrue);

      final rect = reported(2);
      expect(menuState(tester).isOpen, isTrue);
      expect(
        tester.state<FakeViewportState>(find.byType(FakeViewport)).rectQueries,
        [2],
      );
      expect(tester.getRect(find.byType(MenuAnchor)), rect);
      final details = log.opened.single;
      expect(details.row.id, src);
      expect(details.globalPosition, rect.bottomLeft);
      expect(details.nodes.map((node) => node.id), [src]);
      final first = itemRect(tester, 'Rename src');
      expect(first.left, moreOrLessEquals(rect.left));
      expect(first.top, greaterThanOrEqualTo(rect.bottom));
      expect(first.top - rect.bottom, lessThan(16));
    });

    testWidgets('selects the focused row first when it is not selected', (
      tester,
    ) async {
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: const [lib, readme],
        anchor: lib,
      );
      await pumpFocused(tester, focused: mainDart);

      await pressShiftF10(tester);

      expect(controller.selection.selected, {mainDart});
      expect(log.opened.single.nodes.map((node) => node.id), [mainDart]);
    });

    testWidgets('acts on the whole selection when the focused row is '
        'selected', (tester) async {
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: const [readme, src, lib],
        anchor: lib,
      );
      await pumpFocused(tester, focused: src);

      await pressShiftF10(tester);

      expect(controller.selection.selected, {readme, src, lib});
      expect(log.opened.single.nodes.map((node) => node.id), [
        lib,
        src,
        readme,
      ]);
      expect(menuLabels(tester), contains('Delete 3'));
    });

    testWidgets('in right-to-left text the menu ends at the row end and the '
        'position is the bottom-right corner', (tester) async {
      await pumpFocused(tester, textDirection: TextDirection.rtl);

      await pressShiftF10(tester);

      final rect = rowRect(2);
      expect(log.opened.single.globalPosition, rect.bottomRight);
      expect(
        itemRect(tester, 'Rename src').right,
        moreOrLessEquals(rect.right),
      );
    });

    testWidgets('opens at the center of the host when the viewport has not '
        'laid out the row', (tester) async {
      await pumpFocused(tester, viewportRect: (_) => null);

      await pressShiftF10(tester);

      final center = Offset(hostSize.width / 2, hostSize.height / 2);
      expect(menuState(tester).isOpen, isTrue);
      expect(log.opened.single.row.id, src);
      expect(log.opened.single.globalPosition, center);
      expect(
        tester.getRect(find.byType(MenuAnchor)),
        Rect.fromLTWH(center.dx, center.dy, 0, 0),
      );
    });

    testWidgets('opens at the center of the host without any viewport', (
      tester,
    ) async {
      await pumpFocused(tester, viewportRect: null);

      await pressShiftF10(tester);

      final center = Offset(hostSize.width / 2, hostSize.height / 2);
      expect(log.opened.single.globalPosition, center);
      expect(menuLabels(tester), ['Rename src', 'Delete 1', 'Copy path']);
    });

    testWidgets('is disabled without a focused row: the key is not handled '
        'and nothing opens', (tester) async {
      await pumpFocused(tester, focused: null);

      expect(await pressShiftF10(tester), isFalse);

      expect(menuState(tester).isOpen, isFalse);
      expect(log.opened, isEmpty);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    testWidgets('an ancestor Actions can override it', (tester) async {
      var overridden = 0;
      await pumpFocused(
        tester,
        wrapHost: (host) => Actions(
          actions: <Type, Action<Intent>>{
            OpenTreeContextMenuIntent:
                CallbackAction<OpenTreeContextMenuIntent>(
                  onInvoke: (_) => overridden++,
                ),
          },
          child: host,
        ),
      );

      expect(await pressShiftF10(tester), isTrue);

      expect(overridden, 1);
      expect(menuState(tester).isOpen, isFalse);
      expect(log.opened, isEmpty);
    });

    testWidgets('the menu anchored on the focused row does not block clicks '
        'on that row', (tester) async {
      final tapped = <NodeId>[];
      await pumpFocused(tester, onRowTap: tapped.add);
      await pressShiftF10(tester);
      expect(menuState(tester).isOpen, isTrue);

      // The focused row (src, row 2) lies under the menu's anchor box.
      await click(tester, rowCenter(tester, src));

      expect(tapped, [src]);
      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
    });
  });

  group('keyboard focus', () {
    testWidgets('the arrow keys move between the items and Enter chooses '
        'one after focus is back on the tree', (tester) async {
      await pumpFocused(tester);
      await pressShiftF10(tester);
      expect(itemHasFocus(tester, 'Rename src'), isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(itemHasFocus(tester, 'Delete 1'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(itemHasFocus(tester, 'Copy path'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(itemHasFocus(tester, 'Delete 1'), isTrue);
      // The tree's own keys stay inert while the menu has focus.
      expect(controller.focusedId, src);

      await press(tester, LogicalKeyboardKey.enter);

      expect(log.pressed, ['delete 1']);
      expect(log.treeFocusedWhenPressed, [true]);
      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(treeFocus.hasPrimaryFocus, isTrue);
    }, variant: TargetPlatformVariant.all());

    testWidgets('Escape closes the menu and focus returns to the tree', (
      tester,
    ) async {
      controller.selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: const [src],
        anchor: src,
      );
      await pumpFocused(tester);
      await pressShiftF10(tester);

      await press(tester, LogicalKeyboardKey.escape);

      expect(menuState(tester).isOpen, isFalse);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(treeFocus.hasPrimaryFocus, isTrue);
      // The tree's Escape (clear the selection) did not run.
      expect(controller.selection.selected, {src});
      expect(log.pressed, isEmpty);

      // With the menu closed, the tree's keys work again.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.focusedId, aDart);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('a key pressed right after Escape, before the next frame, '
        'goes to the tree', (tester) async {
      await pumpFocused(tester);
      await pressShiftF10(tester);

      // No frame runs between the two keys: the hidden menu is still
      // mounted, but focus is back on the tree already.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

      expect(treeFocus.hasPrimaryFocus, isTrue);
      expect(controller.focusedId, aDart);
    });

    testWidgets('a click that focuses the tree as it opens the menu returns '
        'focus to the tree, not to the widget focused before', (tester) async {
      final fieldFocus = FocusNode(debugLabel: 'field');
      addTearDown(fieldFocus.dispose);
      controller.focus(null);
      await tester.pumpWidget(
        menuApp(
          controller: controller,
          builder: log.builder(),
          treeFocus: treeFocus,
          trigger: OpenTrigger.pointerDown,
          onRowPointerDown: treeFocus.requestFocus,
          outside: TextField(focusNode: fieldFocus),
        ),
      );
      fieldFocus.requestFocus();
      await tester.pump();

      // The tree asks for focus and opens the menu in one pointer down.
      await rightClick(tester, rowCenter(tester, lib));
      expect(itemHasFocus(tester, 'Rename lib'), isTrue);

      await press(tester, LogicalKeyboardKey.escape);

      expect(treeFocus.hasPrimaryFocus, isTrue);
      expect(fieldFocus.hasFocus, isFalse);
    });

    testWidgets('a right-click moves focus into the menu and Escape returns '
        'it to the tree', (tester) async {
      await pumpFocused(tester, focused: null);

      await rightClick(tester, rowCenter(tester, testDir));

      expect(itemHasFocus(tester, 'Rename test'), isTrue);
      await press(tester, LogicalKeyboardKey.escape);
      expect(treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('a click on empty space outside the menu returns focus to '
        'the tree', (tester) async {
      await pumpFocused(tester);
      await pressShiftF10(tester);

      await click(tester, const Offset(600, 500));

      expect(menuState(tester).isOpen, isFalse);
      expect(treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('close returns focus to the tree', (tester) async {
      await pumpFocused(tester);
      await pressShiftF10(tester);
      expect(treeFocus.hasPrimaryFocus, isFalse);

      menuState(tester).close();
      await tester.pump();
      await tester.pump();

      expect(treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('a click into a text field keeps the focus there', (
      tester,
    ) async {
      final fieldFocus = FocusNode(debugLabel: 'field');
      addTearDown(fieldFocus.dispose);
      await pumpFocused(tester, outside: TextField(focusNode: fieldFocus));
      await pressShiftF10(tester);

      await click(tester, tester.getCenter(find.byType(TextField)));

      expect(menuState(tester).isOpen, isFalse);
      expect(fieldFocus.hasPrimaryFocus, isTrue);
      expect(treeFocus.hasFocus, isFalse);
    });

    testWidgets('a widget that takes focus on pointer down keeps it', (
      tester,
    ) async {
      final otherFocus = FocusNode(debugLabel: 'other');
      addTearDown(otherFocus.dispose);
      await pumpFocused(
        tester,
        outside: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => otherFocus.requestFocus(),
          child: Focus(
            focusNode: otherFocus,
            child: const SizedBox(height: 100),
          ),
        ),
      );
      await pressShiftF10(tester);

      await click(tester, const Offset(550, 150));

      expect(menuState(tester).isOpen, isFalse);
      expect(otherFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('replacing a menu keeps the focus to return to', (
      tester,
    ) async {
      await pumpFocused(tester);
      await pressShiftF10(tester);
      expect(itemHasFocus(tester, 'Rename src'), isTrue);

      menuState(tester).open(
        row: controller.rows.rowOf(readme)!,
        globalPosition: const Offset(20, 250),
      );
      await tester.pump();
      await tester.pump();
      expect(itemHasFocus(tester, 'Rename README.md'), isTrue);

      await press(tester, LogicalKeyboardKey.escape);
      expect(treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('focus does not go back to a node that left the focus tree '
        'while the menu was open', (tester) async {
      final replacement = FocusNode(debugLabel: 'replacement');
      addTearDown(replacement.dispose);
      Widget app(FocusNode focus) => menuApp(
        controller: controller,
        builder: log.builder(),
        treeFocus: focus,
        viewportRect: rowRect,
      );
      await pumpFocused(tester);
      await pressShiftF10(tester);
      expect(itemHasFocus(tester, 'Rename src'), isTrue);

      // The tree swaps its focus node while the menu is open.
      await tester.pumpWidget(app(replacement));
      expect(menuState(tester).isOpen, isTrue);
      await press(tester, LogicalKeyboardKey.escape);
      expect(menuState(tester).isOpen, isFalse);
      expect(treeFocus.hasFocus, isFalse);

      // Attaching the old node again does not pull focus to it.
      await tester.pumpWidget(app(treeFocus));
      await tester.pump();
      expect(treeFocus.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a menu without an enabled item takes focus and still '
        'closes with Escape', (tester) async {
      await pumpFocused(
        tester,
        builder: (context, details) => const [
          MenuItemButton(child: Text('Nothing to do')),
        ],
      );
      await pressShiftF10(tester);
      expect(find.text('Nothing to do'), findsOneWidget);
      expect(treeFocus.hasFocus, isFalse);

      await press(tester, LogicalKeyboardKey.escape);

      expect(find.text('Nothing to do'), findsNothing);
      expect(menuState(tester).isOpen, isFalse);
      expect(treeFocus.hasPrimaryFocus, isTrue);
    });
  });
}
