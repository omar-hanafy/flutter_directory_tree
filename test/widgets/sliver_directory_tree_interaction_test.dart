import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_utils.dart';

/// Whether the current test platform toggles the selection with Command.
bool get _commandKeyPlatform =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

LogicalKeyboardKey get _toggleKey => _commandKeyPlatform
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

Future<void> _tapWith(
  WidgetTester tester,
  Finder finder,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(key);
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.sendKeyUpEvent(key);
}

/// Waits until the double-click window of the latest click has closed.
Future<void> _waitPastDoubleClick(WidgetTester tester) =>
    tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));

void main() {
  group('primary click', () {
    testWidgets('acts on pointer up, with no double-click delay', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));

      final gesture = await tester.startGesture(
        tester.getCenter(rowOf(readme)),
        kind: PointerDeviceKind.mouse,
      );
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, isNull);
      await gesture.up();
      // No frame and no kDoubleTapTimeout wait: the click already applied.
      expect(controller.selection.selected, {readme});
      expect(controller.focusedId, readme);
    });

    testWidgets('a plain click on a directory toggles it with expandOnTap', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));

      await tester.tap(rowOf(lib));
      expect(controller.isExpanded(lib), isFalse);
      expect(controller.selection.selected, {lib});
      await tester.pump();
      expect(rowOf(mainDart), findsNothing);
      await _waitPastDoubleClick(tester);

      await tester.tap(rowOf(lib));
      expect(controller.isExpanded(lib), isTrue);
      await tester.pump();
      expect(rowOf(mainDart), findsOneWidget);
    });

    testWidgets('expandOnTap false only selects directories', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, expandOnTap: false),
      );
      await tester.tap(rowOf(lib));
      expect(controller.isExpanded(lib), isTrue);
      expect(controller.selection.selected, {lib});
    });

    testWidgets(
      'Shift extends; the command key toggles (Command on Apple platforms, '
      'Control elsewhere)',
      (tester) async {
        final controller = expandedController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(treeApp(controller: controller));

        await tester.tap(rowOf(mainDart), kind: PointerDeviceKind.mouse);
        await _tapWith(tester, rowOf(readme), LogicalKeyboardKey.shiftLeft);
        expect(controller.selection.selected, {
          mainDart,
          testDir,
          mainTest,
          readme,
        });
        expect(controller.selection.anchor, mainDart);
        expect(controller.focusedId, readme);
        // A modified click never toggles the directory it lands on.
        expect(controller.isExpanded(testDir), isTrue);

        await _tapWith(tester, rowOf(testDir), _toggleKey);
        expect(controller.selection.selected, {mainDart, mainTest, readme});
        expect(controller.isExpanded(testDir), isTrue);
        await _tapWith(tester, rowOf(aDart), _toggleKey);
        expect(controller.selection.selected, {
          mainDart,
          mainTest,
          readme,
          aDart,
        });
        expect(controller.focusedId, aDart);
        await tester.pump();
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('the other platform modifier does not toggle the selection', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final secondary = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowSecondaryTap: (row, _) => secondary.add(row.id),
        ),
      );
      await tester.tap(rowOf(mainDart), kind: PointerDeviceKind.mouse);
      final other = _commandKeyPlatform
          ? LogicalKeyboardKey.controlLeft
          : LogicalKeyboardKey.metaLeft;
      await _tapWith(tester, rowOf(readme), other);
      // Meta is no modifier off Apple platforms, so the click is plain;
      // on macOS Control-click is a secondary click, which also selects
      // the unselected row.
      expect(controller.selection.selected, {readme});
      expect(
        secondary,
        defaultTargetPlatform == TargetPlatform.macOS ? [readme] : isEmpty,
      );
      await tester.pump();
    }, variant: TargetPlatformVariant.all());

    testWidgets('selectOnTap false: clicks only focus', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, selectOnTap: false),
      );
      await tester.tap(rowOf(readme));
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, readme);
      await _tapWith(tester, rowOf(mainDart), LogicalKeyboardKey.shiftLeft);
      await _tapWith(tester, rowOf(aDart), LogicalKeyboardKey.controlLeft);
      await _tapWith(tester, rowOf(bDart), LogicalKeyboardKey.metaLeft);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, bDart);
      // expandOnTap still applies to plain clicks.
      await tester.tap(rowOf(lib));
      expect(controller.isExpanded(lib), isFalse);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, lib);
    });

    testWidgets('onRowTap runs after the built-in handling', (tester) async {
      final controller = expandedController()..collapse(lib);
      addTearDown(controller.dispose);
      final seen = <(NodeId, bool, bool, bool)>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowTap: (row) => seen.add((
            row.id,
            row.isExpanded,
            controller.isSelected(row.id),
            controller.focusedId == row.id,
          )),
        ),
      );
      await tester.tap(rowOf(lib));
      // The row passed is the current one: already expanded by the click.
      expect(seen, [(lib, true, true, true)]);
    });

    testWidgets('a click gives the tree keyboard focus', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode(debugLabel: 'tree');
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, focusNode: focusNode),
      );
      expect(focusNode.hasFocus, isFalse);
      await tester.tap(rowOf(readme));
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
    });
  });

  group('activation', () {
    testWidgets(
      'a double-click on a directory toggles it once, then activates it',
      (tester) async {
        final controller = expandedController()..collapse(lib);
        addTearDown(controller.dispose);
        final tapped = <NodeId>[];
        final activated = <TreeRow<int>>[];
        await tester.pumpWidget(
          treeApp(
            controller: controller,
            onRowTap: (row) => tapped.add(row.id),
            onActivate: activated.add,
          ),
        );

        await tester.tap(rowOf(lib), kind: PointerDeviceKind.mouse);
        expect(controller.isExpanded(lib), isTrue);
        expect(activated, isEmpty);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(rowOf(lib), kind: PointerDeviceKind.mouse);
        // The first click expanded it; the second does not collapse it.
        expect(controller.isExpanded(lib), isTrue);
        expect(tapped, [lib, lib]);
        expect(activated.single.id, lib);
        expect(activated.single.isExpanded, isTrue);

        // A third click starts over: a plain click that toggles again.
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(rowOf(lib), kind: PointerDeviceKind.mouse);
        expect(controller.isExpanded(lib), isFalse);
        expect(activated, hasLength(1));
        await tester.pump();
      },
    );

    testWidgets('without expandOnTap a double-click toggles exactly once', (
      tester,
    ) async {
      final controller = expandedController()..collapse(lib);
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          expandOnTap: false,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      await tester.tap(rowOf(lib));
      expect(controller.isExpanded(lib), isFalse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(rowOf(lib));
      expect(controller.isExpanded(lib), isTrue);
      expect(activated, [lib]);
      await tester.pump();
    });

    testWidgets('a modified first click leaves the toggle to the activation', (
      tester,
    ) async {
      final controller = expandedController()..collapse(lib);
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      await _tapWith(tester, rowOf(lib), LogicalKeyboardKey.shiftLeft);
      expect(controller.isExpanded(lib), isFalse);
      await tester.tap(rowOf(lib), kind: PointerDeviceKind.mouse);
      expect(controller.isExpanded(lib), isTrue);
      expect(activated, [lib]);
      await tester.pump();
    });

    testWidgets('a double-click on a file activates it', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      await tester.tap(rowOf(readme));
      await tester.tap(rowOf(readme));
      expect(activated, [readme]);
      expect(controller.selection.selected, {readme});
      await tester.pump();
    });

    testWidgets('slow clicks and clicks on different rows do not activate', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      await tester.tap(rowOf(readme));
      await _waitPastDoubleClick(tester);
      await tester.tap(rowOf(readme));
      await tester.tap(rowOf(mainTest));
      await tester.tap(rowOf(readme));
      // A secondary click in between closes the double-click window too.
      await tester.tap(
        rowOf(readme),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.tap(rowOf(readme));
      expect(activated, isEmpty);
      await tester.pump();
    });

    testWidgets('a drag between the clicks cancels the second click', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      final tapped = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowTap: (row) => tapped.add(row.id),
          onActivate: (row) => activated.add(row.id),
        ),
      );
      await tester.tap(rowOf(mainTest));
      await tester.timedDrag(
        rowOf(mainTest),
        const Offset(0, 40),
        const Duration(milliseconds: 100),
      );
      expect(tapped, [mainTest]);
      expect(activated, isEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('secondary click', () {
    testWidgets('selects an unselected row, then calls onRowSecondaryTap', (
      tester,
    ) async {
      final controller = expandedController()..select(mainDart);
      addTearDown(controller.dispose);
      final calls = <(NodeId, Offset)>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowSecondaryTap: (row, position) => calls.add((row.id, position)),
        ),
      );
      final center = tester.getCenter(rowOf(readme));
      await tester.tapAt(
        center,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      expect(controller.selection.selected, {readme});
      expect(controller.focusedId, readme);
      expect(calls, [(readme, center)]);
    });

    testWidgets('keeps the selection when the row is selected', (tester) async {
      final controller = expandedController()
        ..select(mainDart)
        ..extendSelection(readme);
      addTearDown(controller.dispose);
      final calls = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowSecondaryTap: (row, _) => calls.add(row.id),
        ),
      );
      final selection = controller.selection;
      await tester.tap(
        rowOf(mainTest),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      expect(controller.selection, selection);
      expect(controller.focusedId, mainTest);
      expect(calls, [mainTest]);
    });

    testWidgets('only focuses without selectOnTap', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final calls = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          selectOnTap: false,
          onRowSecondaryTap: (row, _) => calls.add(row.id),
        ),
      );
      await tester.tap(
        rowOf(readme),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, readme);
      expect(calls, [readme]);
    });

    testWidgets('a touch long-press counts as a secondary tap', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final calls = <(NodeId, Offset)>[];
      final tapped = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowTap: (row) => tapped.add(row.id),
          onRowSecondaryTap: (row, position) => calls.add((row.id, position)),
        ),
      );
      final center = tester.getCenter(rowOf(readme));
      await tester.longPressAt(center);
      expect(calls, [(readme, center)]);
      expect(controller.selection.selected, {readme});
      expect(tapped, isEmpty);
    });

    testWidgets('no long-press secondary tap when turned off', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final calls = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          secondaryTapOnLongPress: false,
          onRowSecondaryTap: (row, _) => calls.add(row.id),
        ),
      );
      await tester.longPress(rowOf(readme));
      expect(calls, isEmpty);
      await tester.pump();
    });

    testWidgets('a mouse long-press is a plain click', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final calls = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowSecondaryTap: (row, _) => calls.add(row.id),
        ),
      );
      await tester.longPress(rowOf(readme), kind: PointerDeviceKind.mouse);
      expect(calls, isEmpty);
      expect(controller.selection.selected, {readme});
      await tester.pump();
    });

    testWidgets('a secondary click gives the tree keyboard focus', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode(debugLabel: 'tree');
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, focusNode: focusNode),
      );
      await tester.tap(
        rowOf(readme),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
    });
  });

  group('expander and checkbox hits', () {
    testWidgets('the expander toggles without selecting or activating', (
      tester,
    ) async {
      final controller = expandedController()..select(readme);
      addTearDown(controller.dispose);
      final tapped = <NodeId>[];
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowTap: (row) => tapped.add(row.id),
          onActivate: (row) => activated.add(row.id),
        ),
      );
      final chevron = find.descendant(
        of: rowOf(lib),
        matching: find.byIcon(Icons.chevron_right),
      );
      await tester.tap(chevron, kind: PointerDeviceKind.mouse);
      expect(controller.isExpanded(lib), isFalse);
      expect(controller.focusedId, lib);
      await tester.pump();
      // A quick second click on it toggles again and still activates
      // nothing.
      await tester.tap(chevron, kind: PointerDeviceKind.mouse);
      expect(controller.isExpanded(lib), isTrue);
      expect(controller.selection.selected, {readme});
      expect(tapped, isEmpty);
      expect(activated, isEmpty);
      await tester.pump();
    });

    testWidgets('a click on the row after the expander is a first click', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          expandOnTap: false,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      final chevron = find.descendant(
        of: rowOf(lib),
        matching: find.byIcon(Icons.chevron_right),
      );
      await tester.tap(find.text('lib'));
      await tester.tap(chevron);
      await tester.tap(find.text('lib'));
      expect(activated, isEmpty);
      await tester.pump();
    });

    testWidgets('the checkbox toggles without selecting or activating', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final tapped = <NodeId>[];
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
          onRowTap: (row) => tapped.add(row.id),
          onActivate: (row) => activated.add(row.id),
        ),
      );
      final checkbox = find.descendant(
        of: rowOf(readme),
        matching: find.byType(Checkbox),
      );
      await tester.tap(checkbox);
      await tester.pump();
      await tester.tap(checkbox);
      await tester.pump();
      await tester.tap(checkbox);
      expect(controller.checkStateOf(readme), CheckState.checked);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, readme);
      expect(tapped, isEmpty);
      expect(activated, isEmpty);
      await tester.pump();
    });
  });

  group('hover', () {
    testWidgets('follows mouse pointers and rebuilds only the hovered row', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final counter = BuildCounter<int>();
      await tester.pumpWidget(
        treeApp(controller: controller, rowBuilder: counter.build),
      );
      counter.take();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(tester.getCenter(rowOf(readme)));
      await tester.pump();
      expect(counter.counts, {readme: 1});
      expect(counter.details.single.isHovered, isTrue);
      counter.take();

      await mouse.moveTo(tester.getCenter(rowOf(mainTest)));
      await tester.pump();
      expect(counter.counts.keys.toSet(), {readme, mainTest});
      final hovered = {
        for (final details in counter.details) details.row.id: details,
      };
      expect(hovered[readme]!.isHovered, isFalse);
      expect(hovered[mainTest]!.isHovered, isTrue);
      counter.take();

      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();
      expect(counter.counts.keys.toSet(), {mainTest});
      expect(counter.details.single.isHovered, isFalse);
    });

    testWidgets('touch and stylus pointers never hover', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final counter = BuildCounter<int>();
      await tester.pumpWidget(
        treeApp(controller: controller, rowBuilder: counter.build),
      );
      counter.take();

      final stylus = await tester.createGesture(kind: PointerDeviceKind.stylus);
      addTearDown(stylus.removePointer);
      await stylus.addPointer(location: const Offset(700, 500));
      await stylus.moveTo(tester.getCenter(rowOf(readme)));
      await tester.pump();
      final touch = await tester.startGesture(
        tester.getCenter(rowOf(mainTest)),
      );
      await tester.pump();
      expect(counter.details.where((details) => details.isHovered), isEmpty);
      await touch.up();
      await tester.pump();
      expect(counter.details.where((details) => details.isHovered), isEmpty);
    });
  });
}
