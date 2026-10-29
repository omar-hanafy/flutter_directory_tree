import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

const r = NodeId('/r');
const a = NodeId('/r/a');
const b = NodeId('/r/a/b');
const c = NodeId('/r/a/b/c');

/// `/r` holding the chain `a/b/c` (each directory has one directory child,
/// `c` holds `m.txt`) and the file `z.txt`.
DirectoryTree<int> matchTree() => DirectoryTree<int>.build(const [
  TreeEntry.file('/r/a/b/c/m.txt'),
  TreeEntry.file('/r/z.txt'),
]);

/// `/r/a/b/c/file.txt` and `/r/other.txt`, compacted, with `r` expanded:
/// the rows are `r`, `a/b/c`, `other.txt`.
DirectoryTreeController<int> compactedController({ExpansionState? expansion}) =>
    DirectoryTreeController<int>(
      tree: DirectoryTree<int>.build(const [
        TreeEntry.file('/r/a/b/c/file.txt'),
        TreeEntry.file('/r/other.txt'),
      ]),
      expansion: expansion ?? ExpansionState.withExpanded([r]),
      compactFolders: true,
    );

const otherTxt = NodeId('/r/other.txt');

void main() {
  group('structure changes while filtering keep the matches visible', () {
    test('turning compaction off', () {
      final controller = DirectoryTreeController<int>(
        tree: matchTree(),
        compactFolders: true,
        query: 'm.txt',
      );
      expect(labelsOf(controller.rows), ['r', 'a/b/c', 'm.txt']);
      final requested = controller.expansion;
      controller.compactFolders = false;
      expect(labelsOf(controller.rows), ['r', 'a', 'b', 'c', 'm.txt']);
      // The search opened the row, so the requested state stays.
      expect(controller.expansion, requested);
      expectConsistentRows(controller);
      controller.query = '';
      expect(labelsOf(controller.rows), ['r']);
    });

    test('showing the roots', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/m.txt'),
          TreeEntry.file('/r/z.txt'),
        ]),
        showRoots: false,
        query: 'm.txt',
      );
      expect(labelsOf(controller.rows), ['a', 'm.txt']);
      controller.showRoots = true;
      expect(labelsOf(controller.rows), ['r', 'a', 'm.txt']);
      expectConsistentRows(controller);
    });

    test('a new tree that breaks up a compacted chain', () {
      final controller = DirectoryTreeController<int>(
        tree: matchTree(),
        compactFolders: true,
        query: 'm.txt',
      );
      final requested = controller.expansion;
      controller.updateTree((builder) => builder.addFile('/r/a/other.m.txt'));
      expect(labelsOf(controller.rows), [
        'r',
        'a',
        'b/c',
        'm.txt',
        'other.m.txt',
      ]);
      expect(controller.expansion, requested);
      expectConsistentRows(controller);
    });

    test('a new tree with matches in new folders', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'b.dart',
      );
      expect(labelsOf(controller.rows), ['repo', 'lib', 'src', 'b.dart']);
      controller.updateTree(
        (builder) => builder.addFile('/repo/docs/guide/b.dart.md'),
      );
      expect(labelsOf(controller.rows), [
        'repo',
        'docs',
        'guide',
        'b.dart.md',
        'lib',
        'src',
        'b.dart',
      ]);
      expectConsistentRows(controller);
    });

    test('a new tree keeps a folder the user collapsed during the search', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'dart',
      );
      controller.collapse(lib);
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'test',
        'main_test.dart',
      ]);
      controller.updateTree(
        (builder) => builder.addFile('/repo/lib/src/c.dart'),
      );
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'test',
        'main_test.dart',
      ]);
      expectConsistentRows(controller);
    });

    test('without revealMatches the effective state is kept as it is', () {
      final controller = DirectoryTreeController<int>(
        tree: matchTree(),
        expansion: ExpansionState.withExpanded([r, c]),
        compactFolders: true,
        query: 'm.txt',
        revealMatches: false,
      );
      expect(labelsOf(controller.rows), ['r', 'a/b/c', 'm.txt']);
      controller.updateTree((builder) => builder.addFile('/r/a/other.m.txt'));
      expect(labelsOf(controller.rows), ['r', 'a']);
      expectConsistentRows(controller);
    });
  });

  group('turning compaction off', () {
    test('expands the members of an open compacted row', () {
      final controller = compactedController(
        expansion: ExpansionState.withExpanded([r, c]),
      );
      expect(labelsOf(controller.rows), [
        'r',
        'a/b/c',
        'file.txt',
        'other.txt',
      ]);
      controller.compactFolders = false;
      expect(labelsOf(controller.rows), [
        'r',
        'a',
        'b',
        'c',
        'file.txt',
        'other.txt',
      ]);
      expect(controller.expansion, ExpansionState.withExpanded([r, a, b, c]));
      expectConsistentRows(controller);
    });

    test('shows the directories of a closed compacted row', () {
      final controller = compactedController();
      controller.compactFolders = false;
      expect(labelsOf(controller.rows), ['r', 'a', 'b', 'c', 'other.txt']);
      expect(controller.isExpanded(c), isFalse);
      expectConsistentRows(controller);
    });

    test('while filtering, only open rows reach the requested state', () {
      final controller = DirectoryTreeController<int>(
        tree: matchTree(),
        expansion: ExpansionState.withExpanded([c]),
        compactFolders: true,
        query: 'm.txt',
      );
      controller.compactFolders = false;
      expect(controller.expansion, ExpansionState.withExpanded([a, b, c]));
      expect(controller.rows.expansion.isExpanded(r), isTrue);
      expectConsistentRows(controller);
    });
  });

  test('showing the roots keeps them open', () {
    final controller = DirectoryTreeController<int>(
      tree: sampleTree(),
      showRoots: false,
    );
    expect(labelsOf(controller.rows), ['lib', 'test', 'README.md']);
    controller.showRoots = true;
    expect(labelsOf(controller.rows), ['repo', 'lib', 'test', 'README.md']);
    expect(controller.expansion, ExpansionState.withExpanded([repo]));
    expectConsistentRows(controller);
  });

  group('ids inside a compacted chain', () {
    test('selection commands select the row of a chain member', () {
      final controller = compactedController();
      controller.select(a);
      expect(controller.selection.selected, {c});
      expect(controller.selection.anchor, c);
      expect(controller.focusedId, c);
      expect(controller.isSelected(controller.focusedId!), isTrue);
      controller.toggleSelected(b);
      expect(controller.selection.selected, isEmpty);
      controller.toggleSelected(b);
      expect(controller.selection.selected, {c});
      controller.extendSelection(otherTxt);
      expect(controller.selection.selected, {c, otherTxt});
      controller
        ..select(otherTxt)
        ..extendSelection(a);
      expect(controller.selection.selected, {c, otherTxt});
      expect(controller.selection.anchor, otherTxt);
      expect(controller.reveal(b, select: true), isTrue);
      expect(controller.selection.selected, {c});
    });

    test('toggleExpansion without a row flips the chain end', () {
      // r is collapsed, so the chain a/b/c has no row.
      final controller = compactedController(
        expansion: ExpansionState.withExpanded([c]),
      );
      expect(controller.rows.indexOfNode(a), -1);
      controller.toggleExpansion(a);
      expect(controller.expansion.isExpanded(c), isFalse);
      controller.toggleExpansion(b);
      expect(controller.expansion.isExpanded(c), isTrue);
      controller.expand(r);
      expect(labelsOf(controller.rows), [
        'r',
        'a/b/c',
        'file.txt',
        'other.txt',
      ]);
    });
  });

  group('reveal', () {
    test('opens the ancestors incrementally with a splice', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        expansion: ExpansionState.withExpanded([repo]),
      );
      final before = controller.rows;
      expect(labelsOf(before), ['repo', 'lib', 'test', 'README.md']);
      expect(controller.reveal(aDart), isTrue);
      expect(
        controller.lastRowsChange,
        TreeRowsChange.splice(
          previous: before,
          index: 2,
          removed: 0,
          inserted: 4,
        ),
      );
      expect(controller.rows.first, same(before.first));
      expect(controller.rows.last, same(before.last));
      expect(
        controller.expansion,
        ExpansionState.withExpanded([repo, lib, src]),
      );
      expectConsistentRows(controller);
    });

    test('changes no state for a node the filter hides', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'a.dart',
      );
      final rows = controller.rows;
      final requested = controller.expansion;
      expect(controller.reveal(mainTest), isFalse);
      expect(controller.rows, same(rows));
      expect(controller.expansion, same(requested));
      controller.query = '';
      expect(labelsOf(controller.rows), ['repo']);
    });

    test('while filtering, opens the deciding ancestors in both states', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'b.dart',
      )..collapse(lib);
      expect(labelsOf(controller.rows), ['repo', 'lib']);
      expect(controller.reveal(bDart), isTrue);
      expect(labelsOf(controller.rows), ['repo', 'lib', 'src', 'b.dart']);
      expect(
        controller.expansion,
        ExpansionState.withExpanded([repo, lib, src]),
      );
      expectConsistentRows(controller);
      controller.query = '';
      expect(controller.rows.indexOfNode(bDart), isNot(-1));
    });

    test('never opens a hidden root or the members of a chain', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/b/c/file.txt'),
          TreeEntry.file('/r/other.txt'),
        ]),
        compactFolders: true,
        showRoots: false,
      );
      expect(labelsOf(controller.rows), ['a/b/c', 'other.txt']);
      expect(controller.reveal(const NodeId('/r/a/b/c/file.txt')), isTrue);
      expect(labelsOf(controller.rows), ['a/b/c', 'file.txt', 'other.txt']);
      expect(controller.expansion, ExpansionState.withExpanded([c]));
      expectConsistentRows(controller);
    });
  });
}
