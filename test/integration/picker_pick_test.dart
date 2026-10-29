import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/picker/initial_pick.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

/// Opens [showDirectoryTreePicker] over [sampleTree], fully expanded, from
/// a button; [result] is what it returned.
final class Dialog {
  bool done = false;
  List<TreeNode<int>>? result;

  List<NodeId>? get resultIds => result == null ? null : idsOf(result!);

  Future<void> open(
    WidgetTester tester, {
    DirectoryTreePickerMode mode = DirectoryTreePickerMode.files,
    bool multiple = false,
    List<NodeId> initialSelection = const [],
    bool settle = true,
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
                  initialExpansion: const ExpansionState.expanded(),
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }
}

FilledButton okButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'OK'));

Future<void> pressOk(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'OK'));
  await tester.pumpAndSettle();
}

/// An embedded picker of [tree], fully expanded, reporting to [changes].
Widget embeddedPicker(
  DirectoryTree<int> tree,
  List<List<TreeNode<int>>> changes, {
  DirectoryTreePickerMode mode = DirectoryTreePickerMode.files,
  bool multiple = false,
  List<NodeId> initialSelection = const [],
}) => hostApp(
  DirectoryTreePicker<int>(
    tree: tree,
    mode: mode,
    multiple: multiple,
    initialSelection: initialSelection,
    initialExpansion: const ExpansionState.expanded(),
    onChanged: changes.add,
  ),
  height: 400,
);

void main() {
  group('multiple directories: focus moves never change the pick', () {
    Future<Dialog> openPicked(WidgetTester tester) async {
      final dialog = Dialog();
      await dialog.open(
        tester,
        mode: DirectoryTreePickerMode.directories,
        multiple: true,
        initialSelection: [testDir, lib],
      );
      await click(tester, rowCenter(tester, aDart));
      return dialog;
    }

    testWidgets('Left and Right', (tester) async {
      final dialog = await openPicked(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await pressOk(tester);
      expect(dialog.resultIds, [lib, testDir]);
    });

    testWidgets('type-ahead', (tester) async {
      final dialog = await openPicked(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.pump();
      await pressOk(tester);
      expect(dialog.resultIds, [lib, testDir]);
    });

    testWidgets('Shift+arrows', (tester) async {
      final dialog = await openPicked(tester);
      await pressWith(
        tester,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.arrowUp,
      );
      await pressWith(
        tester,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.arrowDown,
      );
      await pressOk(tester);
      expect(dialog.resultIds, [lib, testDir]);
    });

    testWidgets('Space still adds the focused directory', (tester) async {
      final dialog = await openPicked(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.space);
      await pressOk(tester);
      expect(dialog.resultIds, [lib, src, testDir]);
    });
  });

  group('a new tree computes the pick again', () {
    testWidgets('a checked directory that gained a file', (tester) async {
      final changes = <List<TreeNode<int>>>[];
      await tester.pumpWidget(
        embeddedPicker(
          sampleTree(),
          changes,
          mode: DirectoryTreePickerMode.any,
          multiple: true,
          initialSelection: const [src],
        ),
      );
      await tester.pump();
      expect(idsOf(changes.last), [src]);
      await tester.pumpWidget(
        embeddedPicker(
          DirectoryTree<int>.build(const [
            TreeEntry.file('/repo/lib/src/a.dart', data: 1),
            TreeEntry.file('/repo/lib/src/b.dart', data: 2),
            TreeEntry.file('/repo/lib/src/c.dart', data: 6),
            TreeEntry.file('/repo/lib/main.dart', data: 3),
          ]),
          changes,
          mode: DirectoryTreePickerMode.any,
          multiple: true,
          initialSelection: const [src],
        ),
      );
      await tester.pump();
      expect(idsOf(changes.last), [aDart, bDart]);
    });

    testWidgets('a directory whose only unchecked file is gone', (
      tester,
    ) async {
      final changes = <List<TreeNode<int>>>[];
      await tester.pumpWidget(
        embeddedPicker(
          sampleTree(),
          changes,
          mode: DirectoryTreePickerMode.any,
          multiple: true,
          initialSelection: const [aDart],
        ),
      );
      await tester.pump();
      expect(idsOf(changes.last), [aDart]);
      await tester.pumpWidget(
        embeddedPicker(
          DirectoryTree<int>.build(const [
            TreeEntry.file('/repo/lib/src/a.dart', data: 1),
            TreeEntry.file('/repo/lib/main.dart', data: 3),
          ]),
          changes,
          mode: DirectoryTreePickerMode.any,
          multiple: true,
          initialSelection: const [aDart],
        ),
      );
      await tester.pump();
      expect(idsOf(changes.last), [src]);
    });

    testWidgets('a picked node with new data', (tester) async {
      final changes = <List<TreeNode<int>>>[];
      await tester.pumpWidget(
        embeddedPicker(sampleTree(), changes, initialSelection: const [readme]),
      );
      await tester.pump();
      expect(changes.last.single.data, 5);
      await tester.pumpWidget(
        embeddedPicker(
          DirectoryTree<int>.build(const [
            TreeEntry.file('/repo/lib/main.dart', data: 3),
            TreeEntry.file('/repo/README.md', data: 500),
          ]),
          changes,
          initialSelection: const [readme],
        ),
      );
      await tester.pump();
      expect(changes, hasLength(2));
      expect(changes.last.single.data, 500);
    });

    testWidgets('equal nodes in a new tree report nothing', (tester) async {
      final changes = <List<TreeNode<int>>>[];
      await tester.pumpWidget(
        embeddedPicker(
          sampleTree(),
          changes,
          multiple: true,
          initialSelection: const [readme, aDart],
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        embeddedPicker(
          sampleTree(),
          changes,
          multiple: true,
          initialSelection: const [readme, aDart],
        ),
      );
      await tester.pump();
      expect(changes, hasLength(1));
    });
  });

  testWidgets('the dialog enables OK on its first frame for an initial pick', (
    tester,
  ) async {
    final dialog = Dialog();
    await dialog.open(tester, initialSelection: const [readme], settle: false);
    expect(find.byType(DirectoryTreePicker<int>), findsOneWidget);
    expect(okButton(tester).onPressed, isNotNull);
    okButton(tester).onPressed!();
    await tester.pumpAndSettle();
    expect(dialog.resultIds, [readme]);
  });

  group('the initial pick is built in one pass', () {
    // 40 folders of 50 files, every file picked.
    DirectoryTree<int> bigTree() => DirectoryTree<int>.build([
      for (var d = 0; d < 40; d++)
        for (var f = 0; f < 50; f++) TreeEntry<int>.file('/big/d$d/f$f.txt'),
    ]);
    List<NodeId> allFiles(DirectoryTree<int> tree) => [
      for (final node in tree.nodes)
        if (node.isFile) node.id,
    ];

    for (final (mode, multiple) in [
      (DirectoryTreePickerMode.files, true),
      (DirectoryTreePickerMode.any, true),
      (DirectoryTreePickerMode.files, false),
    ]) {
      testWidgets('$mode, multiple: $multiple', (tester) async {
        final tree = bigTree();
        final picks = allFiles(tree);
        final changes = <List<TreeNode<int>>>[];
        debugInitialPickStateBuilds = 0;
        await tester.pumpWidget(
          hostApp(
            DirectoryTreePicker<int>(
              tree: tree,
              mode: mode,
              multiple: multiple,
              initialSelection: picks,
              initialExpansion: const ExpansionState.collapsed(),
              onChanged: changes.add,
            ),
            height: 400,
          ),
        );
        await tester.pump();
        // One expansion state for every revealed ancestor, and one check
        // state for every pick: never one per pick.
        expect(debugInitialPickStateBuilds, multiple ? 2 : 1);
        final expected = !multiple
            ? [picks.first]
            : mode == DirectoryTreePickerMode.files
            ? picks
            : [...tree.roots];
        expect(idsOf(changes.single), expected);
      });
    }

    test('match checking and revealing one pick at a time', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a/a1.txt'),
        TreeEntry.file('/r/a/b/b1.txt'),
        TreeEntry.file('/r/a/b/b2.txt'),
        TreeEntry.directory('/r/empty'),
        TreeEntry.file('/r/c/c1.txt'),
        TreeEntry.file('/r/top.txt'),
      ]);
      NodeId id(String path) => tree.idOf(path)!;
      // Overlapping picks (a directory and a file inside it), an empty
      // directory, a file, and an unknown id.
      final picks = [
        id('/r/a/b/b1.txt'),
        id('/r/a'),
        id('/r/empty'),
        id('/r/c/c1.txt'),
        const NodeId('/missing'),
      ];
      var checks = const SelectionState.empty(mode: SelectionMode.multiple);
      var expansion = const ExpansionState.collapsed();
      for (final pick in picks) {
        checks = checks.check(tree, pick);
        expansion = expansion.reveal(tree, pick);
      }
      expect(checkPicks(tree, picks).selected, checks.selected);
      expect(
        revealPicks(tree, picks, const ExpansionState.collapsed()),
        expansion,
      );
    });
  });
}
