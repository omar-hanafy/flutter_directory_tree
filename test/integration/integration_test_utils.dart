import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widgets/widget_test_utils.dart';

export '../widgets/widget_test_utils.dart';

/// A test app showing [child] at the top left of the screen, sized
/// [viewportWidth] x [height], under the fixed-extent test theme.
Widget hostApp(
  Widget child, {
  double height = viewportHeight,
  TextDirection textDirection = TextDirection.ltr,
  bool scaffold = true,
}) {
  final sized = Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: viewportWidth, height: height, child: child),
  );
  return MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: DirectoryTreeTheme(
        data: testTheme,
        child: scaffold ? Scaffold(body: sized) : sized,
      ),
    ),
  );
}

/// The center of the row of [id].
Offset rowCenter(WidgetTester tester, NodeId id) => tester.getCenter(rowOf(id));

/// A mouse click at [position] with [buttons], with frames for menus and
/// focus to settle.
Future<void> click(
  WidgetTester tester,
  Offset position, {
  int buttons = kPrimaryMouseButton,
}) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await gesture.addPointer(location: position);
  await gesture.down(position);
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
  await tester.pump();
  await tester.pump();
}

/// Two primary clicks at [position] within the double-click timeout.
Future<void> doubleClick(WidgetTester tester, Offset position) async {
  await click(tester, position);
  await tester.pump(const Duration(milliseconds: 50));
  await click(tester, position);
}

/// A secondary mouse click at [position].
Future<void> rightClick(WidgetTester tester, Offset position) =>
    click(tester, position, buttons: kSecondaryMouseButton);

/// Sends [key] and lets the result settle.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

/// Presses [key] while [modifier] is held.
Future<void> pressWith(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
  await tester.pump();
}

/// The ids of [nodes], in order.
List<NodeId> idsOf(Iterable<TreeNode<Object?>> nodes) => [
  for (final node in nodes) node.id,
];
