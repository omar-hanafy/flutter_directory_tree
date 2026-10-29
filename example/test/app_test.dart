import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/app.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';
import 'package:flutter_directory_tree_example/widgets/name_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  group('shell', () {
    testWidgets('lists the demos in a navigation rail on wide windows', (
      tester,
    ) async {
      await pumpApp(tester);
      final rail = find.byType(NavigationRail);
      expect(rail, findsOneWidget);
      for (final title in [
        'Explorer',
        'Checkboxes',
        'Large tree',
        'Theming',
        'Picker',
      ]) {
        expect(
          find.descendant(of: rail, matching: find.text(title)),
          findsOneWidget,
        );
      }
      // The test platform is Android: no file system demo.
      expect(find.text('File system'), findsNothing);
    });

    testWidgets('uses a navigation bar on narrow windows', (tester) async {
      await pumpApp(tester, size: const Size(420, 800));
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byIcon(Icons.ads_click_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Pick a file'), findsOneWidget);
    });

    for (final size in const [Size(360, 640), Size(1280, 800)]) {
      testWidgets('every demo lays out without errors at $size', (
        tester,
      ) async {
        await pumpApp(tester, size: size);
        for (final demo in availableDemos()) {
          await tester.tap(find.byIcon(demo.icon).first);
          await tester.pump();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: demo.title);
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(demo.title),
            ),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('the theme toggle cycles system, light, and dark', (
      tester,
    ) async {
      await pumpApp(tester);
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(HomePage))).brightness;
      await tester.tap(find.byTooltip('Theme: system'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      await tester.tap(find.byTooltip('Theme: light'));
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      expect(find.byTooltip('Theme: dark'), findsOneWidget);
    });

    testWidgets('desktop platforms list the file system demo', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(availableDemos().map((demo) => demo.title), [
          'Explorer',
          'Checkboxes',
          'File system',
          'Large tree',
          'Theming',
          'Picker',
        ]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('explorer', () {
    testWidgets('a click selects a row and the details pane lists it', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Selection (0)'), findsOneWidget);
      await click(tester, rowLabel('README.md'));
      expect(find.text('Selection (1)'), findsOneWidget);
      expect(find.text('$sampleRoot/README.md'), findsOneWidget);
    });

    testWidgets('a double-click opens the file in the details pane', (
      tester,
    ) async {
      await pumpApp(tester);
      await doubleClick(tester, rowLabel('pubspec.yaml'));
      expect(find.textContaining('$sampleRoot/pubspec.yaml\n'), findsOneWidget);
    });

    testWidgets('Delete removes the row and Undo brings it back', (
      tester,
    ) async {
      await pumpApp(tester);
      await rightClick(tester, rowLabel('README.md'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(rowLabel('README.md'), findsNothing);
      expect(find.text('Deleted README.md'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(rowLabel('README.md'), findsOneWidget);
    });

    testWidgets('Rename asks for a name and renames the row', (tester) async {
      await pumpApp(tester);
      await rightClick(tester, rowLabel('CHANGELOG.md'));
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(nameFieldKey), 'HISTORY.md');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(rowLabel('CHANGELOG.md'), findsNothing);
      expect(rowLabel('HISTORY.md'), findsOneWidget);
      // The renamed node is selected under its new id.
      expect(find.text('$sampleRoot/HISTORY.md'), findsOneWidget);
    });

    testWidgets('New file creates a file inside the folder', (tester) async {
      await pumpApp(tester);
      await rightClick(tester, rowLabel('docs'));
      await tester.tap(find.text('New file'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(nameFieldKey), 'notes.md');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(rowLabel('notes.md'), findsOneWidget);
      expect(find.text('$sampleRoot/docs/notes.md'), findsOneWidget);
    });

    testWidgets('dragging a file onto a folder moves it there', (tester) async {
      await pumpApp(tester);
      await mouseDrag(tester, rowLabel('README.md'), rowLabel('docs'));
      expect(find.text('Moved README.md to docs'), findsOneWidget);
      // docs opened and shows the moved file, which stays selected.
      expect(rowLabel('README.md'), findsOneWidget);
      expect(find.text('$sampleRoot/docs/README.md'), findsOneWidget);
    });
  });

  group('checkboxes', () {
    testWidgets('check all and uncheck all update the live lists', (
      tester,
    ) async {
      await pumpApp(tester);
      await openDemo(tester, 'Checkboxes');
      final tree = sampleProjectTree();
      final leaves = tree.nodes
          .where(
            (node) => node is FileNode || !(node as DirectoryNode).hasChildren,
          )
          .length;
      expect(find.text('Checked leaves (0)'), findsOneWidget);
      await tester.tap(find.text('Check all'));
      await tester.pumpAndSettle();
      expect(find.text('Checked roots (1)'), findsOneWidget);
      expect(find.text('Checked leaves ($leaves)'), findsOneWidget);
      await tester.tap(find.text('Uncheck all'));
      await tester.pumpAndSettle();
      expect(find.text('Checked leaves (0)'), findsOneWidget);
    });

    testWidgets('a row checkbox checks that file', (tester) async {
      await pumpApp(tester);
      await openDemo(tester, 'Checkboxes');
      final row = find.ancestor(
        of: rowLabel('README.md'),
        matching: find.byType(DirectoryTreeRow<int>),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Checked leaves (1)'), findsOneWidget);
      expect(find.text('$sampleRoot/README.md'), findsNWidgets(2));
    });
  });

  group('large tree', () {
    testWidgets('builds 100,000 nodes, toggles, expands all, and searches', (
      tester,
    ) async {
      await pumpApp(tester);
      await openDemo(tester, 'Large tree');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('100,000 nodes built in'), findsOneWidget);
      expect(find.text('21 rows'), findsOneWidget);

      await tester.tap(find.text('Toggle folder'));
      await tester.pumpAndSettle();
      final timing = tester.widget<Text>(
        find.byKey(const ValueKey<String>('last-timing')),
      );
      expect(timing.data, startsWith('Toggle package_00: '));
      expect(timing.data, endsWith('(+24 rows)'));

      await tester.tap(find.byTooltip('Expand all'));
      await tester.pumpAndSettle();
      expect(find.text('100,000 rows'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'module_07/file_042');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      // The root, 20 packages, their module_07, and one file in each.
      expect(find.text('61 rows'), findsOneWidget);
    });
  });

  group('theming', () {
    testWidgets('the controls change the theme, direction, and rows', (
      tester,
    ) async {
      await pumpApp(tester);
      await openDemo(tester, 'Theming');
      Finder firstRow() => find.byType(DirectoryTreeRow<int>).first;
      DirectoryTreeThemeData rowTheme() =>
          DirectoryTreeTheme.of(tester.element(firstRow()));

      expect(rowTheme().guideStyle, DirectoryTreeGuideStyle.connectors);
      await tester.tap(find.text('Indent'));
      await tester.pumpAndSettle();
      expect(rowTheme().guideStyle, DirectoryTreeGuideStyle.indent);

      expect(find.textContaining(' items'), findsWidgets);
      await tester.tap(find.text('Size badges'));
      await tester.pumpAndSettle();
      expect(find.textContaining(' items'), findsNothing);

      expect(Directionality.of(tester.element(firstRow())), TextDirection.ltr);
      await tester.tap(find.text('Right to left'));
      await tester.pumpAndSettle();
      expect(Directionality.of(tester.element(firstRow())), TextDirection.rtl);

      expect(rowLabel('acme_app'), findsOneWidget);
      await tester.tap(find.text('Show roots'));
      await tester.pumpAndSettle();
      expect(rowLabel('acme_app'), findsNothing);
    });

    testWidgets('compact folders joins single-child folders', (tester) async {
      await pumpApp(tester);
      await openDemo(tester, 'Theming');
      // android holds only the folder app, so the two share one row.
      expect(rowLabel('android'), findsOneWidget);
      expect(rowLabel('android/app'), findsNothing);
      await tester.tap(find.text('Compact folders'));
      await tester.pumpAndSettle();
      expect(rowLabel('android'), findsNothing);
      expect(rowLabel('android/app'), findsOneWidget);
    });
  });

  group('picker', () {
    testWidgets('a picked file is shown as the result', (tester) async {
      await pumpApp(tester);
      await openDemo(tester, 'Picker');
      await tester.tap(find.text('Pick a file'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      // README.md is below the fold of the dialog; the search finds it.
      await searchInDialog(tester, 'README');
      await click(
        tester,
        find.descendant(of: dialog, matching: find.text('README.md')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();
      expect(find.text('file  $sampleRoot/README.md'), findsOneWidget);
    });

    testWidgets('several checked files come back in display order', (
      tester,
    ) async {
      await pumpApp(tester);
      await openDemo(tester, 'Picker');
      await tester.tap(find.text('Pick files'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      // Checks survive a search, so the second file can be found by name.
      for (final (query, name) in [
        ('pubspec', 'pubspec.yaml'),
        ('gitignore', '.gitignore'),
      ]) {
        await searchInDialog(tester, query);
        await click(
          tester,
          find.descendant(of: dialog, matching: find.text(name)),
        );
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Choose'));
      await tester.pumpAndSettle();
      final tree = sampleProjectTree();
      final expected = [
        for (final node in tree.nodes)
          if (node.name == '.gitignore' || node.name == 'pubspec.yaml')
            'file  ${node.path}',
      ];
      final lines = tester
          .widgetList<Text>(find.textContaining('file  $sampleRoot/'))
          .map((text) => text.data)
          .toList();
      expect(lines, expected);
    });

    testWidgets('Cancel shows cancelled', (tester) async {
      await pumpApp(tester);
      await openDemo(tester, 'Picker');
      await tester.tap(find.text('Pick folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('cancelled'), findsOneWidget);
    });
  });
}
