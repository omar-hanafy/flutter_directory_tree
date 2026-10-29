import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

/// Opens [showDirectoryTreePicker] over [sampleTree] from a button and
/// collects the result.
final class PickerHarness {
  bool done = false;
  List<TreeNode<int>>? result;

  List<NodeId>? get resultIds => result == null ? null : idsOf(result!);

  Future<void> open(
    WidgetTester tester, {
    DirectoryTreePickerMode mode = DirectoryTreePickerMode.files,
    bool multiple = false,
    Iterable<NodeId> initialSelection = const <NodeId>[],
    ExpansionState? initialExpansion,
    String? title,
    String? confirmLabel,
    bool showSearch = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDirectoryTreePicker<int>(
                  context: context,
                  tree: sampleTree(),
                  mode: mode,
                  multiple: multiple,
                  initialSelection: initialSelection,
                  initialExpansion: initialExpansion,
                  title: title,
                  confirmLabel: confirmLabel,
                  showSearch: showSearch,
                );
                done = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

/// The confirm button of the open picker dialog.
FilledButton confirmButton(WidgetTester tester, {String label = 'OK'}) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

/// The checkbox of the row of [id].
Finder checkboxOf(NodeId id) =>
    find.descendant(of: rowOf(id), matching: find.byType(Checkbox));

Future<void> confirm(WidgetTester tester, {String label = 'OK'}) async {
  await tester.tap(find.widgetWithText(FilledButton, label));
  await tester.pumpAndSettle();
}

void main() {
  group('single', () {
    testWidgets('files: only a file enables OK, which returns it', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(tester, title: 'Open file');
      expect(find.text('Open file'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
      // The top-level directory starts expanded; lib opens on a click but
      // cannot be picked.
      await click(tester, rowCenter(tester, lib));
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNull);
      expect(rowOf(mainDart), findsOneWidget);
      await click(tester, rowCenter(tester, mainDart));
      expect(confirmButton(tester).onPressed, isNotNull);
      await confirm(tester);
      expect(harness.done, isTrue);
      expect(harness.resultIds, [mainDart]);
    });

    testWidgets('files: a double-click on a file confirms at once', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(tester);
      await doubleClick(tester, rowCenter(tester, readme));
      await tester.pumpAndSettle();
      expect(harness.resultIds, [readme]);
    });

    testWidgets('files: Enter on the selected file confirms it', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(tester);
      await click(tester, rowCenter(tester, readme));
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(harness.resultIds, [readme]);
    });

    testWidgets('Cancel and Escape return null', (tester) async {
      final harness = PickerHarness();
      await harness.open(tester, initialSelection: [readme]);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(harness.done, isTrue);
      expect(harness.result, isNull);
      final again = PickerHarness();
      await again.open(tester, initialSelection: [readme]);
      // The tree has the keyboard and a selection; Escape still closes.
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(again.done, isTrue);
      expect(again.result, isNull);
    });

    testWidgets('directories: a double-click on a directory confirms it', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(tester, mode: DirectoryTreePickerMode.directories);
      await click(tester, rowCenter(tester, readme));
      expect(confirmButton(tester).onPressed, isNull);
      await doubleClick(tester, rowCenter(tester, testDir));
      await tester.pumpAndSettle();
      expect(harness.resultIds, [testDir]);
    });

    testWidgets('any: a directory or a file can be picked', (tester) async {
      final harness = PickerHarness();
      await harness.open(tester, mode: DirectoryTreePickerMode.any);
      await click(tester, rowCenter(tester, lib));
      expect(confirmButton(tester).onPressed, isNotNull);
      await confirm(tester);
      expect(harness.resultIds, [lib]);
    });

    testWidgets('an initial pick is revealed and can be confirmed at once', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(
        tester,
        initialSelection: [lib, const NodeId('/missing'), bDart, aDart],
        confirmLabel: 'Choose',
      );
      // lib is a directory and /missing is unknown; bDart is the first
      // valid id and the only one in single mode.
      expect(rowOf(bDart), findsOneWidget);
      expect(confirmButton(tester, label: 'Choose').onPressed, isNotNull);
      await confirm(tester, label: 'Choose');
      expect(harness.resultIds, [bDart]);
    });

    testWidgets('initialExpansion is used as given', (tester) async {
      final harness = PickerHarness();
      await harness.open(
        tester,
        initialExpansion: const ExpansionState.collapsed(),
      );
      expect(rowOf(repo), findsOneWidget);
      expect(rowOf(lib), findsNothing);
    });

    testWidgets('the search field filters the rows', (tester) async {
      final harness = PickerHarness();
      await harness.open(tester);
      await tester.enterText(find.byType(TextField), 'main_test');
      await tester.pumpAndSettle();
      expect(rowOf(mainTest), findsOneWidget);
      expect(rowOf(readme), findsNothing);
      await harness.open(tester, showSearch: false);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('multiple', () {
    testWidgets('files: checks pick files, directories check their files', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(tester, multiple: true);
      expect(confirmButton(tester).onPressed, isNull);
      // A click on a file row toggles its check.
      await click(tester, rowCenter(tester, readme));
      expect(confirmButton(tester).onPressed, isNotNull);
      // A directory's checkbox checks every file below it.
      await tester.tap(checkboxOf(testDir));
      await tester.pumpAndSettle();
      await confirm(tester);
      expect(harness.resultIds, [mainTest, readme]);
    });

    testWidgets('files: a second click unchecks, an empty pick disables OK', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(tester, multiple: true);
      await click(tester, rowCenter(tester, readme));
      await tester.pump(const Duration(seconds: 1));
      await click(tester, rowCenter(tester, readme));
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('any: a checked directory stands for its subtree', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(
        tester,
        mode: DirectoryTreePickerMode.any,
        multiple: true,
      );
      await tester.tap(checkboxOf(lib));
      await tester.pumpAndSettle();
      await click(tester, rowCenter(tester, readme));
      await confirm(tester);
      expect(harness.resultIds, [lib, readme]);
    });

    testWidgets('files: initial picks start checked, in display order', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(
        tester,
        multiple: true,
        initialSelection: [readme, aDart, src],
      );
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(tester.widget<Checkbox>(checkboxOf(aDart)).value, isTrue);
      // src is a directory: files mode ignores it.
      expect(tester.widget<Checkbox>(checkboxOf(src)).value, isNull);
      await confirm(tester);
      expect(harness.resultIds, [aDart, readme]);
    });

    testWidgets('directories: checkboxes pick, keys only move the focus', (
      tester,
    ) async {
      final harness = PickerHarness();
      await harness.open(
        tester,
        mode: DirectoryTreePickerMode.directories,
        multiple: true,
      );
      // Files cannot be picked: their boxes are disabled.
      expect(tester.widget<Checkbox>(checkboxOf(readme)).onChanged, isNull);
      await tester.tap(checkboxOf(testDir));
      await tester.pumpAndSettle();
      // A click on a row only focuses it and opens the directory.
      await click(tester, rowCenter(tester, lib));
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNotNull);
      // Moving with the arrows keeps the pick; Space adds the focused row.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.space);
      await confirm(tester);
      expect(harness.resultIds, [src, testDir]);
    });
  });

  group('embedded', () {
    testWidgets('reports the initial pick after the first frame', (
      tester,
    ) async {
      final changes = <List<NodeId>>[];
      await tester.pumpWidget(
        hostApp(
          DirectoryTreePicker<int>(
            tree: sampleTree(),
            multiple: true,
            initialSelection: const [readme, mainTest],
            onChanged: (pick) => changes.add(idsOf(pick)),
          ),
          height: 400,
        ),
      );
      await tester.pump();
      expect(changes, [
        [mainTest, readme],
      ]);
    });

    testWidgets('a new tree keeps the pick by id', (tester) async {
      final changes = <List<NodeId>>[];
      Widget picker(DirectoryTree<int> tree) => hostApp(
        DirectoryTreePicker<int>(
          tree: tree,
          initialSelection: const [readme],
          onChanged: (pick) => changes.add(idsOf(pick)),
        ),
        height: 400,
      );
      await tester.pumpWidget(picker(sampleTree()));
      await tester.pump();
      expect(changes, [
        [readme],
      ]);
      // The same paths in a new tree: the pick stays, nothing is reported.
      await tester.pumpWidget(picker(sampleTree()));
      await tester.pump();
      expect(changes, hasLength(1));
      // A tree without README.md drops the pick, reported after the frame.
      await tester.pumpWidget(
        picker(
          DirectoryTree<int>.build(const [
            TreeEntry.file('/repo/lib/main.dart'),
          ]),
        ),
      );
      await tester.pump();
      expect(changes.last, isEmpty);
    });

    testWidgets('a new mode starts over and keeps the expansion', (
      tester,
    ) async {
      final changes = <List<NodeId>>[];
      Widget picker(DirectoryTreePickerMode mode) => hostApp(
        DirectoryTreePicker<int>(
          tree: sampleTree(),
          mode: mode,
          onChanged: (pick) => changes.add(idsOf(pick)),
        ),
        height: 400,
      );
      await tester.pumpWidget(picker(DirectoryTreePickerMode.files));
      await click(tester, rowCenter(tester, lib));
      await tester.pumpAndSettle();
      expect(rowOf(mainDart), findsOneWidget);
      await tester.pumpWidget(picker(DirectoryTreePickerMode.directories));
      await tester.pumpAndSettle();
      expect(rowOf(mainDart), findsOneWidget);
      await click(tester, rowCenter(tester, src));
      expect(changes.last, [src]);
    });
  });
}
