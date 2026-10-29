import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

/// Shift+F10; returns whether a widget handled F10.
Future<bool> shiftF10(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final handled = await tester.sendKeyEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  await tester.pump();
  return handled;
}

/// Ctrl+Down: moves the cursor without changing the selection (not on
/// macOS, the platform under test being Android).
Future<void> ctrlDown(WidgetTester tester) => pressWith(
  tester,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.arrowDown,
);

/// A touch long-press at [position] released without moving.
Future<void> longPress(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(position);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pumpAndSettle();
}

List<NodeId> selectedIds(DirectoryTreeController<Object?> controller) => [
  for (final node in controller.selectedNodes) node.id,
];

/// A controller over the sample tree with README.md and main_test.dart
/// selected (as checkboxes would leave them).
DirectoryTreeController<int> pickedController() => DirectoryTreeController<int>(
  tree: sampleTree(),
  expansion: const ExpansionState.expanded(),
  selection: SelectionState(
    mode: SelectionMode.multiple,
    selected: const [readme, mainTest],
  ),
);

void main() {
  group('selectOnTap: false keeps the selection when a menu opens', () {
    late List<List<NodeId>> menus;

    Widget view(
      DirectoryTreeController<int> controller, {
      DirectoryTreeDragAndDrop<int>? dragAndDrop,
    }) => hostApp(
      DirectoryTreeView<int>(
        controller: controller,
        selectOnTap: false,
        dragAndDrop: dragAndDrop,
        contextMenuBuilder: (context, details) {
          menus.add(idsOf(details.nodes));
          return [MenuItemButton(onPressed: () {}, child: const Text('Item'))];
        },
      ),
    );

    setUp(() => menus = []);

    testWidgets('a right-click on an unselected row', (tester) async {
      final controller = pickedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(view(controller));
      await rightClick(tester, rowCenter(tester, aDart));
      await tester.pumpAndSettle();
      expect(menus, [
        [aDart],
      ]);
      expect(selectedIds(controller), [mainTest, readme]);
      expect(controller.focusedId, aDart);
    });

    testWidgets('a touch long-press with drag and drop', (tester) async {
      final controller = pickedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        view(controller, dragAndDrop: DirectoryTreeDragAndDrop(onDrop: (_) {})),
      );
      await longPress(tester, rowCenter(tester, aDart));
      expect(menus, [
        [aDart],
      ]);
      expect(selectedIds(controller), [mainTest, readme]);
    });

    testWidgets('Shift+F10 on an unselected focused row', (tester) async {
      final controller = pickedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(view(controller));
      await click(tester, rowCenter(tester, bDart));
      await ctrlDown(tester);
      expect(controller.focusedId, mainDart);
      expect(await shiftF10(tester), isTrue);
      await tester.pumpAndSettle();
      expect(menus, [
        [mainDart],
      ]);
      expect(selectedIds(controller), [mainTest, readme]);
    });

    testWidgets('a selected row opens the menu of the whole selection', (
      tester,
    ) async {
      final controller = pickedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(view(controller));
      await rightClick(tester, rowCenter(tester, readme));
      await tester.pumpAndSettle();
      expect(menus, [
        [mainTest, readme],
      ]);
    });
  });

  group('Shift+F10 without a contextMenuBuilder', () {
    late List<(NodeId, Offset, bool)> taps;

    Widget view(
      DirectoryTreeController<int> controller, {
      bool selectOnTap = true,
      TextDirection textDirection = TextDirection.ltr,
      Map<Type, Action<Intent>>? ancestorActions,
    }) {
      Widget result = DirectoryTreeView<int>(
        controller: controller,
        selectOnTap: selectOnTap,
        onRowSecondaryTap: (row, position) =>
            taps.add((row.id, position, controller.isSelected(row.id))),
      );
      if (ancestorActions != null) {
        result = Actions(actions: ancestorActions, child: result);
      }
      return hostApp(result, textDirection: textDirection);
    }

    setUp(() => taps = []);

    testWidgets('selects an unselected focused row first, then calls back '
        'at its bottom-left corner', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(view(controller));
      await click(tester, rowCenter(tester, bDart));
      await ctrlDown(tester);
      expect(controller.isSelected(mainDart), isFalse);
      expect(await shiftF10(tester), isTrue);
      final rect = tester.getRect(rowOf(mainDart));
      expect(taps, [(mainDart, rect.bottomLeft, true)]);
      expect(selectedIds(controller), [mainDart]);
    });

    testWidgets('with selectOnTap false, the selection stays', (tester) async {
      final controller = pickedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(view(controller, selectOnTap: false));
      await click(tester, rowCenter(tester, bDart));
      expect(await shiftF10(tester), isTrue);
      expect(taps.single.$1, bDart);
      expect(taps.single.$3, isFalse);
      expect(selectedIds(controller), [mainTest, readme]);
    });

    testWidgets('right-to-left uses the bottom-right corner', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        view(controller, textDirection: TextDirection.rtl),
      );
      await click(tester, rowCenter(tester, readme));
      expect(await shiftF10(tester), isTrue);
      expect(taps.single.$2, tester.getRect(rowOf(readme)).bottomRight);
    });

    testWidgets('a focused row out of view gets the center of the view', (
      tester,
    ) async {
      final controller = wideController(300);
      addTearDown(controller.dispose);
      await tester.pumpWidget(view(controller));
      await click(tester, rowCenter(tester, wideId(2)));
      scrollPositionOf(tester).jumpTo(250 * rowExtent);
      await tester.pump();
      expect(rowOf(wideId(2)), findsNothing);
      expect(await shiftF10(tester), isTrue);
      final viewRect = tester.getRect(find.byType(DirectoryTreeView<int>));
      expect(taps.single.$1, wideId(2));
      expect(taps.single.$2, viewRect.center);
    });

    testWidgets('with nothing focused, the keys reach the widgets above', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var above = 0;
      await tester.pumpWidget(
        hostApp(
          Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.f10, shift: true):
                  ActivateIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) => above++,
                ),
              },
              child: DirectoryTreeView<int>(
                controller: controller,
                focusNode: focusNode,
                onRowSecondaryTap: (row, position) =>
                    taps.add((row.id, position, false)),
              ),
            ),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();
      controller.focus(null);
      await tester.pump();
      await shiftF10(tester);
      expect(taps, isEmpty);
      expect(above, 1);
    });

    testWidgets('an ancestor Actions replaces it', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      var overrides = 0;
      await tester.pumpWidget(
        view(
          controller,
          ancestorActions: <Type, Action<Intent>>{
            OpenTreeContextMenuIntent:
                CallbackAction<OpenTreeContextMenuIntent>(
                  onInvoke: (_) => overrides++,
                ),
          },
        ),
      );
      await click(tester, rowCenter(tester, readme));
      expect(await shiftF10(tester), isTrue);
      expect(overrides, 1);
      expect(taps, isEmpty);
    });
  });

  testWidgets('selectionFollowsFocus false keeps the selection on arrows', (
    tester,
  ) async {
    final controller = pickedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreeView<int>(
          controller: controller,
          selectOnTap: false,
          expandOnTap: false,
          selectionFollowsFocus: false,
          checkboxMode: DirectoryTreeCheckboxMode.selection,
        ),
      ),
    );
    await click(tester, rowCenter(tester, lib));
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await typeTextInto(tester, 'm');
    expect(controller.focusedId, mainDart);
    expect(selectedIds(controller), [mainTest, readme]);
  });
}

/// Types the lowercase letter [letter] into the focused tree.
Future<void> typeTextInto(WidgetTester tester, String letter) async {
  await tester.sendKeyEvent(
    LogicalKeyboardKey.findKeyByKeyId(letter.codeUnitAt(0))!,
    character: letter,
  );
  await tester.pump();
}
