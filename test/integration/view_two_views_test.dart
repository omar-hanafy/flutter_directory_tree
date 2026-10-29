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

const a = ValueKey('A');
const b = ValueKey('B');

/// [build] (given A's or B's key) side by side, A on the left, each 300
/// wide, inside [wrap].
Widget twoViews(
  Widget Function(Key key) build, {
  Widget Function(Widget child)? wrap,
}) {
  final Widget row = Row(
    children: [
      SizedBox(width: 300, child: build(a)),
      SizedBox(width: 300, child: build(b)),
    ],
  );
  return MaterialApp(
    home: DirectoryTreeTheme(
      // Rows 30 high, so every row of the sample tree is on screen.
      data: testTheme,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(height: 300, child: wrap?.call(row) ?? row),
        ),
      ),
    ),
  );
}

/// The row of [id] in the tree with [key].
Finder rowIn(Key key, NodeId id) =>
    find.descendant(of: find.byKey(key), matching: rowOf(id));

List<Widget> oneItem(BuildContext context, Object? details) => [
  MenuItemButton(onPressed: () {}, child: const Text('Item')),
];

void main() {
  testWidgets('the fallback uses the row of the view with the keyboard', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final taps = <(Key?, Offset)>[];
    await tester.pumpWidget(
      twoViews(
        (key) => DirectoryTreeView<int>(
          key: key,
          controller: controller,
          onRowSecondaryTap: (row, position) => taps.add((key, position)),
        ),
      ),
    );
    await click(tester, tester.getCenter(rowIn(b, readme)));
    expect(await shiftF10(tester), isTrue);
    expect(taps.single.$1, b);
    expect(taps.single.$2, tester.getRect(rowIn(b, readme)).bottomLeft);
  });

  testWidgets('the menu opens at the row of the view with the keyboard', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final positions = <Offset>[];
    await tester.pumpWidget(
      twoViews(
        (key) => DirectoryTreeView<int>(
          key: key,
          controller: controller,
          contextMenuBuilder: (context, details) {
            positions.add(details.globalPosition);
            return oneItem(context, details);
          },
        ),
      ),
    );
    await click(tester, tester.getCenter(rowIn(b, readme)));
    expect(await shiftF10(tester), isTrue);
    await tester.pumpAndSettle();
    expect(positions.single, tester.getRect(rowIn(b, readme)).bottomLeft);
  });

  testWidgets('one menu host around two trees uses the tree with the '
      'keyboard', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final positions = <Offset>[];
    final nodes = {a: FocusNode(), b: FocusNode()};
    for (final node in nodes.values) {
      addTearDown(node.dispose);
    }
    await tester.pumpWidget(
      twoViews(
        (key) => KeyedSubtree(
          key: key,
          child: DirectoryTreeKeyboard<int>(
            controller: controller,
            focusNode: nodes[key],
            child: CustomScrollView(
              slivers: [SliverDirectoryTree<int>(controller: controller)],
            ),
          ),
        ),
        wrap: (child) => DirectoryTreeContextMenu<int>(
          controller: controller,
          builder: (context, details) {
            positions.add(details.globalPosition);
            return oneItem(context, details);
          },
          child: child,
        ),
      ),
    );
    controller.focus(readme);
    nodes[b]!.requestFocus();
    await tester.pump();
    expect(await shiftF10(tester), isTrue);
    await tester.pumpAndSettle();
    expect(positions.single, tester.getRect(rowIn(b, readme)).bottomLeft);
  });
}
