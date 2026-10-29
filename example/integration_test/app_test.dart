import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/app.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';
import 'package:flutter_directory_tree_example/demos/file_system/file_system_browser_io.dart';
import 'package:flutter_directory_tree_example/widgets/name_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a desktop device: `flutter test integration_test -d macos`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> startApp(WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
  }

  Future<void> openDemo(WidgetTester tester, String title) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text(title),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The label of the tree row [label] (not a text field showing it).
  Finder row(String label) => find.descendant(
    of: find.byType(DirectoryTreeRow<int>),
    matching: find.text(label),
  );

  Future<void> click(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(finder));
    await gesture.down(tester.getCenter(finder));
    await tester.pump();
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Cmd+F on Apple platforms, Ctrl+F elsewhere.
  Future<void> pressFind(WidgetTester tester) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finder, findsWidgets);
  }

  testWidgets('explorer: click, keyboard navigation, and selection', (
    tester,
  ) async {
    await startApp(tester);
    expect(find.text('Selection (0)'), findsOneWidget);

    await click(tester, row('README.md'));
    expect(find.text('Selection (1)'), findsOneWidget);
    expect(find.text('$sampleRoot/README.md'), findsOneWidget);

    // Home goes to the first row, Down to android, Right opens it, Down
    // moves into it.
    await press(tester, LogicalKeyboardKey.home);
    expect(find.text(sampleRoot), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('$sampleRoot/android'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.text('app'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.text('$sampleRoot/android/app'), findsOneWidget);

    // Shift+Down extends the selection to the next row.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Selection (2)'), findsOneWidget);
  });

  testWidgets('explorer: search, then Enter opens the match', (tester) async {
    await startApp(tester);
    await click(tester, row('README.md'));
    await pressFind(tester);
    await tester.enterText(find.byType(TextField), 'main.dart');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(row('README.md'), findsNothing);
    expect(find.text('main.dart'), findsWidgets);

    // Down moves from the search field into the tree, Enter activates.
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.textContaining('$sampleRoot/lib/main.dart\n'), findsOneWidget);
  });

  testWidgets('explorer: the context menu renames a file', (tester) async {
    await startApp(tester);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    final position = tester.getCenter(row('CHANGELOG.md'));
    await gesture.addPointer(location: position);
    await gesture.down(position);
    await tester.pump();
    await gesture.up();
    await gesture.removePointer();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.byKey(nameFieldKey), findsOneWidget);
    await tester.enterText(find.byKey(nameFieldKey), 'HISTORY.md');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(row('HISTORY.md'), findsOneWidget);
    expect(row('CHANGELOG.md'), findsNothing);
  });

  testWidgets('picker: search and Enter confirm a single file', (tester) async {
    await startApp(tester);
    await openDemo(tester, 'Picker');
    await tester.tap(find.text('Pick a file'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);

    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'README',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.enter);

    expect(dialog, findsNothing);
    expect(find.text('file  $sampleRoot/README.md'), findsOneWidget);
  });

  testWidgets('picker: Escape cancels', (tester) async {
    await startApp(tester);
    await openDemo(tester, 'Picker');
    await tester.tap(find.text('Pick folders'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('cancelled'), findsOneWidget);
  });

  testWidgets('large tree: builds and toggles', (tester) async {
    await startApp(tester);
    await openDemo(tester, 'Large tree');
    await waitFor(tester, find.textContaining('100,000 nodes built in'));
    await tester.tap(find.text('Toggle folder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Toggle package_00: '), findsOneWidget);
  });

  testWidgets('file system: opens the home folder', (tester) async {
    await startApp(tester);
    await openDemo(tester, 'File system');
    final home = homeDirectory();
    await waitFor(tester, find.text(home));
    // The home folder's own row is the first row of the tree.
    final name = home.split(RegExp(r'[/\\]')).lastWhere((part) => part != '');
    expect(find.text(name), findsWidgets);
  }, skip: !fileSystemDemoAvailable);
}
