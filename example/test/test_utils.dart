import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree_example/app.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps the showcase app in a desktop-sized window (wide enough for the
/// navigation rail) and resets the window when the test ends.
Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ExampleApp());
  await tester.pumpAndSettle();
}

/// Switches to the demo titled [title] through the navigation rail.
Future<void> openDemo(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(title),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tree row labelled [label]; the label must be unique on screen.
Finder rowLabel(String label) => find.text(label);

/// Types [query] into the search field of the open dialog and waits for
/// the search debounce.
Future<void> searchInDialog(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// A mouse click on [finder], with frames for focus and menus to settle.
Future<void> click(
  WidgetTester tester,
  Finder finder, {
  int buttons = kPrimaryMouseButton,
}) async {
  final position = tester.getCenter(finder);
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

/// Two primary clicks on [finder] within the double-click timeout.
Future<void> doubleClick(WidgetTester tester, Finder finder) async {
  await click(tester, finder);
  await tester.pump(const Duration(milliseconds: 50));
  await click(tester, finder);
  await tester.pumpAndSettle();
}

/// A secondary click on [finder], which opens the context menu.
Future<void> rightClick(WidgetTester tester, Finder finder) async {
  await click(tester, finder, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

/// Drags [from] onto [to] with a mouse, in small steps so the drop target
/// registers.
Future<void> mouseDrag(WidgetTester tester, Finder from, Finder to) async {
  final start = tester.getCenter(from);
  final end = tester.getCenter(to);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(start + const Offset(0, 12));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.moveTo(end + const Offset(0, 2));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
