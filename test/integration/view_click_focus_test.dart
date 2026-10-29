import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

/// The details the default row of [id] was last built with.
DirectoryTreeRowDetails<int> detailsOf(WidgetTester tester, NodeId id) => tester
    .widget<DirectoryTreeRow<int>>(
      find.descendant(
        of: rowOf(id),
        matching: find.byType(DirectoryTreeRow<int>),
      ),
    )
    .details;

void main() {
  late FocusNode treeFocus;
  late FocusNode inner;

  setUp(() {
    treeFocus = FocusNode(debugLabel: 'tree');
    inner = FocusNode(debugLabel: 'inside main.dart');
  });
  tearDown(() {
    treeFocus.dispose();
    inner.dispose();
  });

  /// A view whose main.dart row has [trailing] built with the [inner]
  /// focus node.
  Widget view(
    DirectoryTreeController<int> controller,
    Widget Function(FocusNode node) trailing, {
    DirectoryTreeDragAndDrop<int>? dragAndDrop,
    void Function(TreeRow<int>, Offset)? onRowSecondaryTap,
  }) => hostApp(
    DirectoryTreeView<int>(
      controller: controller,
      focusNode: treeFocus,
      dragAndDrop: dragAndDrop,
      onRowSecondaryTap: onRowSecondaryTap,
      rowBuilder: (context, details) => DirectoryTreeRow<int>(
        details: details,
        trailing: details.row.id == mainDart ? trailing(inner) : null,
      ),
    ),
  );

  Widget iconButton(FocusNode node) => IconButton(
    focusNode: node,
    onPressed: () {},
    icon: const Icon(Icons.more_vert),
  );

  Widget textField(FocusNode node) =>
      SizedBox(width: 120, child: TextField(focusNode: node));

  void expectTreeHasKeys(WidgetTester tester, NodeId focused) {
    expect(treeFocus.hasPrimaryFocus, isTrue);
    expect(inner.hasFocus, isFalse);
    expect(detailsOf(tester, focused).isFocused, isTrue);
    expect(detailsOf(tester, focused).hasFocus, isTrue);
  }

  testWidgets('a click on a row takes the keys from a focused button in '
      'another row', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(view(controller, iconButton));
    inner.requestFocus();
    await tester.pump();
    expect(inner.hasPrimaryFocus, isTrue);
    await click(tester, rowCenter(tester, readme));
    expectTreeHasKeys(tester, readme);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(controller.focusedId, mainTest);
  });

  testWidgets('a click and a touch tap take the keys from a text field in '
      'another row', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(view(controller, textField));
    inner.requestFocus();
    await tester.pump();
    await click(tester, rowCenter(tester, readme));
    expectTreeHasKeys(tester, readme);
    inner.requestFocus();
    await tester.pump();
    // A touch outside a text field does not unfocus it on mobile.
    await tester.tapAt(rowCenter(tester, testDir));
    await tester.pump();
    expectTreeHasKeys(tester, testDir);
  });

  testWidgets('a secondary click takes the keys from a focused button', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      view(controller, iconButton, onRowSecondaryTap: (_, _) {}),
    );
    inner.requestFocus();
    await tester.pump();
    await rightClick(tester, rowCenter(tester, readme));
    expectTreeHasKeys(tester, readme);
  });

  testWidgets('an expander click takes the keys from a focused button', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(view(controller, iconButton));
    inner.requestFocus();
    await tester.pump();
    await click(
      tester,
      tester.getCenter(
        find.descendant(
          of: rowOf(testDir),
          matching: find.byType(DirectoryTreeExpander<int>),
        ),
      ),
    );
    expect(controller.isExpanded(testDir), isFalse);
    expect(treeFocus.hasPrimaryFocus, isTrue);
  });

  testWidgets('a touch long-press without a drag takes the keys from a text '
      'field in another row', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final taps = <NodeId>[];
    await tester.pumpWidget(
      view(
        controller,
        textField,
        dragAndDrop: DirectoryTreeDragAndDrop<int>(onDrop: (_) {}),
        onRowSecondaryTap: (row, _) => taps.add(row.id),
      ),
    );
    inner.requestFocus();
    await tester.pump();
    final gesture = await tester.startGesture(
      rowCenter(tester, readme),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    expect(taps, [readme]);
    expectTreeHasKeys(tester, readme);
  });
}
