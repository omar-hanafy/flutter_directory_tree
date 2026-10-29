import 'package:flutter/animation.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

DirectoryTreeController<int> sampleController({
  ExpansionState expansion = const ExpansionState.collapsed(),
  String query = '',
  TreeFilter? filter,
  bool revealMatches = true,
  bool compactFolders = false,
  bool showRoots = true,
}) => DirectoryTreeController<int>(
  tree: sampleTree(),
  expansion: expansion,
  query: query,
  filter: filter,
  revealMatches: revealMatches,
  compactFolders: compactFolders,
  showRoots: showRoots,
);

/// `x` holding the chain `A/B/C` (each directory has one directory child,
/// `C` holds a file) and the file `other.txt`.
DirectoryTree<int> chainTree() => DirectoryTree<int>.build(const [
  TreeEntry.file('/x/A/B/C/file.txt', data: 1),
  TreeEntry.file('/x/other.txt', data: 2),
]);

const x = NodeId('/x');
const chainA = NodeId('/x/A');
const chainB = NodeId('/x/A/B');
const chainC = NodeId('/x/A/B/C');
const chainFile = NodeId('/x/A/B/C/file.txt');
const otherTxt = NodeId('/x/other.txt');

void main() {
  group('construction', () {
    test('defaults to an empty tree, collapsed, multiple selection', () {
      final controller = DirectoryTreeController<int>();
      expect(controller.tree.isEmpty, isTrue);
      expect(controller.rows, isEmpty);
      expect(controller.expansion, const ExpansionState.collapsed());
      expect(controller.selection.mode, SelectionMode.multiple);
      expect(controller.checks.mode, SelectionMode.multiple);
      expect(controller.focusedId, isNull);
      expect(controller.focusedIndex, -1);
      expect(controller.focusedRow, isNull);
      expect(controller.query, '');
      expect(controller.parsedQuery, isNull);
      expect(controller.filter, isNull);
      expect(controller.isFiltering, isFalse);
      expect(controller.revealMatches, isTrue);
      expect(controller.compactFolders, isFalse);
      expect(controller.showRoots, isTrue);
      expect(
        controller.lastRowsChange,
        const TreeRowsChange.reset(previous: null),
      );
    });

    test('shows the given expansion and drops unknown selection ids', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        expansion: ExpansionState.withExpanded([repo, lib]),
        selection: SelectionState(
          mode: SelectionMode.multiple,
          selected: [mainDart, unknown],
          anchor: unknown,
        ),
        checks: SelectionState(
          mode: SelectionMode.multiple,
          selected: [readme, unknown],
        ),
      );
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'src',
        'main.dart',
        'test',
        'README.md',
      ]);
      expect(controller.selection.selected, {mainDart});
      expect(controller.selection.anchor, isNull);
      expect(controller.checks.selected, {readme});
      expectConsistentRows(controller);
    });

    test('an initial query reveals matches on top of the expansion', () {
      final controller = sampleController(query: 'b.dart');
      expect(labelsOf(controller.rows), ['repo', 'lib', 'src', 'b.dart']);
      expect(controller.expansion, const ExpansionState.collapsed());
      expect(controller.isFiltering, isTrue);
      expectConsistentRows(controller);
    });

    test('an initial query without revealMatches keeps the expansion', () {
      final controller = sampleController(
        query: 'b.dart',
        revealMatches: false,
      );
      expect(labelsOf(controller.rows), ['repo']);
    });
  });

  group('tree setter', () {
    test('does nothing for the identical tree', () {
      final controller = sampleController();
      final rows = controller.rows;
      final same = controller.tree;
      expect(
        notificationsOf(controller, () {
          controller.tree = same;
        }),
        0,
      );
      expect(identical(controller.rows, rows), isTrue);
    });

    test('replaces an equal tree with one notification and a reset', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      final rows = controller.rows;
      final recorder = RowsChangeRecorder(controller);
      expect(
        notificationsOf(controller, () {
          controller.tree = sampleTree();
        }),
        1,
      );
      expect(recorder.changes, [TreeRowsChange.reset(previous: rows)]);
      expect(labelsOf(controller.rows), labelsOf(rows));
      expectConsistentRows(controller);
    });

    test('releases the replaced tree once listeners ran', () {
      final controller = sampleController();
      final recorder = RowsChangeRecorder(controller);
      final before = controller.rows;
      controller.tree = sampleTree();
      expect(recorder.changes.single.previous, same(before));
      expect(
        controller.lastRowsChange,
        const TreeRowsChange.reset(previous: null),
      );
      // A change that keeps the tree keeps its previous rows.
      final rows = controller.rows;
      controller.expand(repo);
      expect(controller.lastRowsChange.previous, same(rows));
    });

    test('prunes selection, checks, and both expansion states', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib, src, testDir]),
      )..query = 'main';
      controller
        ..selection = SelectionState(
          mode: SelectionMode.multiple,
          selected: [aDart, mainTest],
          anchor: aDart,
        )
        ..checks = SelectionState(
          mode: SelectionMode.multiple,
          selected: [aDart, readme],
        );
      controller.tree = controller.tree.rebuild(
        (builder) => builder
          ..remove('/repo/lib/src')
          ..remove('/repo/test'),
      );
      expect(controller.selection.selected, isEmpty);
      expect(controller.selection.anchor, isNull);
      expect(controller.checks.selected, {readme});
      expect(controller.expansion, ExpansionState.withExpanded([repo, lib]));
      expect(controller.rows.expansion.exceptions, {repo, lib});
      expectConsistentRows(controller);
      controller.query = '';
      expect(controller.expansion, ExpansionState.withExpanded([repo, lib]));
    });

    test('a checked empty directory that gains children checks them all', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.directory('/r/box'),
        TreeEntry.file('/r/keep.txt'),
      ]);
      final controller = DirectoryTreeController<int>(tree: tree)
        ..setChecked(const NodeId('/r/box'), checked: true);
      expect(
        controller.checkStateOf(const NodeId('/r/box')),
        CheckState.checked,
      );
      controller.updateTree(
        (builder) => builder
          ..addFile('/r/box/a.txt')
          ..addFile('/r/box/b.txt'),
      );
      expect(
        controller.checkStateOf(const NodeId('/r/box')),
        CheckState.checked,
      );
      expect(controller.checks.selected, {
        const NodeId('/r/box/a.txt'),
        const NodeId('/r/box/b.txt'),
      });
      // An uncheck of one leaf survives the next replacement.
      controller
        ..setChecked(const NodeId('/r/box/a.txt'), checked: false)
        ..tree = controller.tree.rebuild((builder) {});
      expect(
        controller.checkStateOf(const NodeId('/r/box')),
        CheckState.partial,
      );
      expect(controller.checks.selected, {const NodeId('/r/box/b.txt')});
    });

    test('a checked file that becomes a directory checks its leaves', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/thing'),
        TreeEntry.file('/r/other.txt'),
      ]);
      final controller = DirectoryTreeController<int>(tree: tree)
        ..setChecked(const NodeId('/r/thing'), checked: true);
      controller.tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/r/thing/inner.txt'),
        TreeEntry.file('/r/other.txt'),
      ]);
      expect(controller.checks.selected, {const NodeId('/r/thing/inner.txt')});
    });

    test('keeps the focus on a node that still exists', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib]),
      )..focus(mainDart);
      controller.updateTree((builder) => builder.addFile('/repo/new.txt'));
      expect(controller.focusedId, mainDart);
    });

    test('moves the focus to the nearest surviving ancestor', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib, src]),
      )..focus(aDart);
      controller.updateTree((builder) => builder.remove('/repo/lib/src'));
      expect(controller.focusedId, lib);
      expectConsistentRows(controller);
    });

    test('walks the old path when the ancestors are new nodes', () {
      // The focused file's directory is gone, but the tree rebuilt from
      // other entries still has its grandparent.
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib, src]),
      )..focus(bDart);
      controller.tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/repo/lib/other.dart'),
      ]);
      expect(controller.tree.contains(src), isFalse);
      // `lib` is now the root and has a row.
      expect(controller.focusedId, lib);
    });

    test('moves the focus to the parent of a removed node', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib, src]),
      )..focus(aDart);
      // Collapse `lib` in the new state while removing nothing above it.
      controller.tree = controller.tree.rebuild(
        (builder) => builder.remove('/repo/lib/src/a.dart'),
      );
      expect(controller.focusedId, src);
      controller.collapse(lib);
      expect(controller.focusedId, lib);
    });

    test('drops the focus when nothing of the old path survives', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..focus(readme);
      controller.tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/elsewhere/file.txt'),
      ]);
      expect(controller.focusedId, isNull);
    });

    test('updateTree rebuilds with the builder', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      expect(
        notificationsOf(controller, () {
          controller.updateTree((builder) => builder.addFile('/repo/z.txt'));
        }),
        1,
      );
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'test',
        'README.md',
        'z.txt',
      ]);
    });

    test('updateTree and lazy loads accept data on a fromPaths tree', () async {
      final loader = FakeLoader<Object?>();
      final controller = DirectoryTreeController(
        tree: DirectoryTree.fromPaths(['/r/a.txt', '/r/lazy/']),
        loadChildren: loader.call,
      );
      controller.updateTree((builder) => builder.addFile('/r/b.txt', data: 42));
      expect(controller.tree.nodeAt('/r/b.txt')!.data, 42);
      final lazy = controller.tree.idOf('/r/lazy')!;
      final load = controller.loadChildren(lazy);
      await settle();
      loader.complete(lazy, [
        const TreeEntry<Object?>.file('/r/lazy/c.txt', data: 'payload'),
      ]);
      await load;
      expect(controller.tree.nodeAt('/r/lazy/c.txt')!.data, 'payload');
    });
  });

  group('expansion commands', () {
    test('expand inserts the children incrementally', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      final before = controller.rows;
      expect(notificationsOf(controller, () => controller.expand(lib)), 1);
      final after = controller.rows;
      expect(labelsOf(after), [
        'repo',
        'lib',
        'src',
        'main.dart',
        'test',
        'README.md',
      ]);
      expect(
        controller.lastRowsChange,
        TreeRowsChange.splice(
          previous: before,
          index: 2,
          removed: 0,
          inserted: 2,
        ),
      );
      expect(identical(after[0], before[0]), isTrue);
      expect(identical(after[4], before[2]), isTrue);
      expect(identical(after[5], before[3]), isTrue);
      expect(controller.expansion.isExpanded(lib), isTrue);
      expect(controller.isExpanded(lib), isTrue);
      expectConsistentRows(controller);
    });

    test('collapse removes the descendant block and keeps their state', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib, src]),
      );
      final before = controller.rows;
      expect(notificationsOf(controller, () => controller.collapse(lib)), 1);
      expect(labelsOf(controller.rows), ['repo', 'lib', 'test', 'README.md']);
      expect(
        controller.lastRowsChange,
        TreeRowsChange.splice(
          previous: before,
          index: 2,
          removed: 4,
          inserted: 0,
        ),
      );
      expect(controller.expansion.isExpanded(src), isTrue);
      controller.expand(lib);
      expect(labelsOf(controller.rows), contains('a.dart'));
    });

    test('collapse moves a hidden focus to the collapsed row', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo, lib, src]),
      )..focus(bDart);
      controller.collapse(lib);
      expect(controller.focusedId, lib);
    });

    test('toggleExpansion flips the row state', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..toggleExpansion(lib);
      expect(controller.isExpanded(lib), isTrue);
      controller.toggleExpansion(lib);
      expect(controller.isExpanded(lib), isFalse);
      expectConsistentRows(controller);
    });

    test('a directory without a row only changes its state', () {
      final controller = sampleController();
      final before = controller.rows;
      expect(notificationsOf(controller, () => controller.expand(src)), 1);
      expect(controller.expansion.isExpanded(src), isTrue);
      expect(labelsOf(controller.rows), ['repo']);
      expect(controller.lastRowsChange, TreeRowsChange.reset(previous: before));
      controller
        ..expand(repo)
        ..expand(lib);
      expect(labelsOf(controller.rows), contains('a.dart'));
    });

    test('files, unknown ids, and repeated commands change nothing', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      final rows = controller.rows;
      final change = controller.lastRowsChange;
      for (final command in <void Function()>[
        () => controller.expand(readme),
        () => controller.collapse(readme),
        () => controller.toggleExpansion(readme),
        () => controller.expand(unknown),
        () => controller.collapse(unknown),
        () => controller.toggleExpansion(unknown),
        () => controller.expand(repo),
        () => controller.collapse(lib),
        () => controller.expandSubtree(readme),
        () => controller.collapseSubtree(unknown),
        () => controller.expansion = ExpansionState.withExpanded([repo]),
      ]) {
        expect(notificationsOf(controller, command), 0);
      }
      expect(identical(controller.rows, rows), isTrue);
      expect(identical(controller.lastRowsChange, change), isTrue);
    });

    test('expandAll and collapseAll set the constant states', () {
      final controller = sampleController()..focus(repo);
      final before = controller.rows;
      expect(notificationsOf(controller, controller.expandAll), 1);
      expect(controller.expansion, const ExpansionState.expanded());
      expect(controller.rows, hasLength(9));
      expect(controller.lastRowsChange, TreeRowsChange.reset(previous: before));
      controller.focus(aDart);
      expect(notificationsOf(controller, controller.collapseAll), 1);
      expect(controller.expansion, const ExpansionState.collapsed());
      expect(labelsOf(controller.rows), ['repo']);
      expect(controller.focusedId, repo);
      expect(notificationsOf(controller, controller.collapseAll), 0);
    });

    test('expandSubtree and collapseSubtree use the core transforms', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..expandSubtree(lib);
      expect(
        controller.expansion,
        ExpansionState.withExpanded([repo, lib, src]),
      );
      controller
        ..focus(aDart)
        ..collapseSubtree(lib);
      expect(controller.expansion, ExpansionState.withExpanded([repo]));
      expect(controller.focusedId, lib);
      expectConsistentRows(controller);
    });

    test('equal but not identical states change nothing', () {
      final controller = sampleController(
        expansion: ExpansionState.withCollapsed(const []),
      );
      final rows = controller.rows;
      expect(notificationsOf(controller, controller.expandAll), 0);
      expect(identical(controller.rows, rows), isTrue);
      controller.expansion = ExpansionState.withExpanded(const []);
      expect(notificationsOf(controller, controller.collapseAll), 0);
    });

    test('the expansion setter applies the state as given', () {
      final controller = sampleController();
      final state = ExpansionState.withExpanded([repo, testDir, unknown]);
      expect(
        notificationsOf(controller, () {
          controller.expansion = state;
        }),
        1,
      );
      expect(identical(controller.expansion, state), isTrue);
      expect(identical(controller.rows.expansion, state), isTrue);
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'test',
        'main_test.dart',
        'README.md',
      ]);
    });

    test('an id inside a compacted row toggles the row in both states', () {
      final controller = DirectoryTreeController<int>(
        tree: chainTree(),
        expansion: ExpansionState.withExpanded([x]),
        compactFolders: true,
      );
      expect(labelsOf(controller.rows), ['x', 'A/B/C', 'other.txt']);
      controller.expand(chainA);
      expect(labelsOf(controller.rows), [
        'x',
        'A/B/C',
        'file.txt',
        'other.txt',
      ]);
      expect(controller.expansion, ExpansionState.withExpanded([x, chainC]));
      controller.toggleExpansion(chainB);
      expect(labelsOf(controller.rows), ['x', 'A/B/C', 'other.txt']);
      expect(controller.expansion, ExpansionState.withExpanded([x]));
    });
  });

  group('two expansion states', () {
    test('a search reveals matches only in the effective state', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      final requested = controller.expansion;
      expect(
        notificationsOf(controller, () {
          controller.query = 'a.dart';
        }),
        1,
      );
      expect(labelsOf(controller.rows), ['repo', 'lib', 'src', 'a.dart']);
      expect(controller.expansion, requested);
      expect(controller.rows.expansion.exceptions, {repo, lib, src});
      expect(controller.isExpanded(src), isTrue);
      expect(controller.expansion.isExpanded(src), isFalse);
      expectConsistentRows(controller);
    });

    test('toggles while filtering change both states', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..query = 'a.dart';
      // `lib` is open only because of the search; collapsing it leaves the
      // requested state alone.
      controller.collapse(lib);
      expect(labelsOf(controller.rows), ['repo', 'lib']);
      expect(controller.expansion, ExpansionState.withExpanded([repo]));
      // Expanding it again is now a request of the user.
      controller.expand(lib);
      expect(controller.expansion, ExpansionState.withExpanded([repo, lib]));
      // A hidden directory changes its state in both.
      controller.expand(testDir);
      expect(
        controller.expansion,
        ExpansionState.withExpanded([repo, lib, testDir]),
      );
      controller.query = '';
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'src',
        'main.dart',
        'test',
        'main_test.dart',
        'README.md',
      ]);
      expect(
        identical(controller.rows.expansion, controller.expansion),
        isTrue,
      );
    });

    test('an id inside a compacted row maps to the row while filtering', () {
      final controller = DirectoryTreeController<int>(
        tree: chainTree(),
        expansion: ExpansionState.withExpanded([x]),
        compactFolders: true,
        query: 'other',
      );
      expect(labelsOf(controller.rows), ['x', 'other.txt']);
      controller.query = 'A';
      expect(labelsOf(controller.rows), ['x', 'A/B/C']);
      controller.expand(chainB);
      expect(labelsOf(controller.rows), ['x', 'A/B/C']);
      expect(controller.expansion, ExpansionState.withExpanded([x, chainC]));
      controller.query = '';
      expect(labelsOf(controller.rows), [
        'x',
        'A/B/C',
        'file.txt',
        'other.txt',
      ]);
    });

    test('a toggle on a revealed directory keeps it after the search', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..query = 'a.dart';
      // `src` is already expanded on screen; expanding it records the wish.
      expect(notificationsOf(controller, () => controller.expand(src)), 1);
      expect(controller.expansion, ExpansionState.withExpanded([repo, src]));
      controller.query = '';
      expect(controller.expansion, ExpansionState.withExpanded([repo, src]));
    });

    test('every filter change recomputes from the requested state', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..query = 'dart';
      controller.collapse(lib);
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'test',
        'main_test.dart',
      ]);
      controller.query = 'dart ';
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'src',
        'a.dart',
        'b.dart',
        'main.dart',
        'test',
        'main_test.dart',
      ]);
      final fresh = controller.tree.flatten(
        expansion: controller.expansion,
        filter: effectiveFilterOf(controller),
      );
      expect(controller.rows, fresh);
    });

    test('reveals of an earlier query do not carry over', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..query = 'a.dart';
      expect(controller.rows.expansion.isExpanded(src), isTrue);
      controller.query = 'main';
      expect(controller.rows.expansion.isExpanded(src), isFalse);
      expect(controller.rows.expansion.exceptions, {repo, lib, testDir});
    });

    test('clearing the filter restores the requested state', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      final before = controller.rows;
      controller
        ..query = 'main'
        ..query = '';
      expect(labelsOf(controller.rows), labelsOf(before));
      expect(controller.isFiltering, isFalse);
      expect(
        identical(controller.rows.expansion, controller.expansion),
        isTrue,
      );
    });

    test('clearing the filter reveals and scrolls to the focused node', () {
      final viewport = FakeViewport();
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..query = 'b.dart';
      controller
        ..attachViewport(viewport)
        ..focus(bDart, scroll: false);
      expect(
        notificationsOf(controller, () {
          controller.query = '';
        }),
        1,
      );
      expect(controller.focusedId, bDart);
      expect(
        controller.expansion,
        ExpansionState.withExpanded([repo, lib, src]),
      );
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'src',
        'a.dart',
        'b.dart',
        'main.dart',
        'test',
        'README.md',
      ]);
      expect(viewport.shown, hasLength(1));
      expect(viewport.shown.single.index, 4);
      expect(viewport.shown.single.alignment, isNull);
      expect(viewport.shown.single.duration, Duration.zero);
    });

    test('setting the expansion while filtering replaces both states', () {
      final controller = sampleController()..query = 'a.dart';
      controller.expansion = ExpansionState.withExpanded([repo, testDir]);
      expect(controller.rows.expansion, controller.expansion);
      expect(labelsOf(controller.rows), ['repo', 'lib']);
      controller.query = 'a.dar';
      expect(labelsOf(controller.rows), ['repo', 'lib', 'src', 'a.dart']);
      controller.query = '';
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'test',
        'main_test.dart',
        'README.md',
      ]);
    });

    test('expandAll and collapseAll while filtering change both states', () {
      final controller = sampleController()..query = 'main';
      controller.collapseAll();
      expect(controller.rows.expansion, const ExpansionState.collapsed());
      expect(labelsOf(controller.rows), ['repo']);
      controller.expandAll();
      expect(controller.expansion, const ExpansionState.expanded());
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'main.dart',
        'test',
        'main_test.dart',
      ]);
    });

    test('revealMatches false keeps matches in collapsed directories', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
        revealMatches: false,
      )..query = 'main';
      expect(labelsOf(controller.rows), ['repo', 'lib', 'test']);
      expect(
        notificationsOf(controller, () {
          controller.revealMatches = true;
        }),
        1,
      );
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'main.dart',
        'test',
        'main_test.dart',
      ]);
      controller
        ..query = ''
        ..revealMatches = false;
      expect(controller.revealMatches, isFalse);
    });
  });

  group('reveal', () {
    test('expands the ancestors, focuses, and scrolls', () {
      final viewport = FakeViewport();
      final controller = sampleController()..attachViewport(viewport);
      final before = controller.rows;
      late bool shown;
      expect(
        notificationsOf(controller, () {
          shown = controller.reveal(bDart);
        }),
        1,
      );
      expect(shown, isTrue);
      expect(controller.focusedId, bDart);
      expect(controller.selection.isEmpty, isTrue);
      expect(
        controller.expansion,
        ExpansionState.withExpanded([repo, lib, src]),
      );
      // The core's incremental reveal: the block after the opened root.
      expect(
        controller.lastRowsChange,
        TreeRowsChange.splice(
          previous: before,
          index: 1,
          removed: 0,
          inserted: 7,
        ),
      );
      expect(viewport.shown.single.index, controller.rows.indexOfNode(bDart));
      expect(viewport.shown.single.alignment, isNull);
    });

    test('forwards alignment, duration, and curve', () {
      final viewport = FakeViewport();
      final controller = sampleController()..attachViewport(viewport);
      controller.reveal(
        mainTest,
        alignment: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
      );
      expect(viewport.shown.single, (
        index: controller.rows.indexOfNode(mainTest),
        duration: const Duration(milliseconds: 300),
        curve: Curves.linear,
        alignment: 0.0,
      ));
      viewport.shown.clear();
      controller.revealPath(
        '/repo/README.md',
        alignment: 0.5,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeIn,
      );
      expect(viewport.shown.single, (
        index: controller.rows.indexOfNode(readme),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeIn,
        alignment: 0.5,
      ));
    });

    test('selects when asked, without scrolling when told not to', () {
      final viewport = FakeViewport();
      final controller = sampleController()..attachViewport(viewport);
      controller.reveal(aDart, select: true, focus: false, scroll: false);
      expect(controller.selection.selected, {aDart});
      expect(controller.selection.anchor, aDart);
      expect(controller.focusedId, isNull);
      expect(viewport.shown, isEmpty);
    });

    test('changes nothing for a node that already has a row', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..focus(lib);
      final rows = controller.rows;
      expect(
        notificationsOf(controller, () {
          expect(controller.reveal(lib), isTrue);
        }),
        0,
      );
      expect(identical(controller.rows, rows), isTrue);
    });

    test('never expands the chain end for an id inside a compacted row', () {
      final controller = DirectoryTreeController<int>(
        tree: chainTree(),
        expansion: ExpansionState.withExpanded([x]),
        compactFolders: true,
      );
      final rows = controller.rows;
      final expansion = controller.expansion;
      expect(controller.reveal(chainB), isTrue);
      expect(identical(controller.rows, rows), isTrue);
      expect(identical(controller.expansion, expansion), isTrue);
      expect(controller.isExpanded(chainC), isFalse);
      expect(controller.focusedId, chainC);
      expect(labelsOf(controller.rows), ['x', 'A/B/C', 'other.txt']);
      // A node below the chain still opens the chain's directory.
      expect(controller.reveal(chainFile), isTrue);
      expect(labelsOf(controller.rows), [
        'x',
        'A/B/C',
        'file.txt',
        'other.txt',
      ]);
    });

    test('returns false for unknown ids and nodes the filter hides', () {
      final controller = sampleController()..query = 'a.dart';
      expect(
        notificationsOf(controller, () {
          expect(controller.reveal(unknown), isFalse);
        }),
        0,
      );
      final rows = controller.rows;
      expect(controller.reveal(mainTest, select: true), isFalse);
      // No expansion can show it, so none changes; the selection applies.
      expect(controller.rows, same(rows));
      expect(controller.expansion, const ExpansionState.collapsed());
      expect(controller.selection.selected, {mainTest});
      expect(controller.focusedId, isNull);
    });

    test('revealPath resolves raw paths with the tree policy', () {
      final tree = DirectoryTree<int>.build(const [
        TreeEntry.file('/Repo/Lib/Main.dart'),
      ], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
      final controller = DirectoryTreeController<int>(tree: tree);
      final id = controller.revealPath('/REPO/lib/MAIN.DART');
      expect(id, tree.nodeAt('/repo/lib/main.dart')!.id);
      expect(controller.focusedId, id);
      expect(controller.revealPath('/repo/missing'), isNull);
      expect(controller.revealPath(''), isNull);
    });
  });

  group('search', () {
    test('a hidden chain directory toggles the state the core changed', () {
      final controller = DirectoryTreeController<int>(
        tree: chainTree(),
        expansion: ExpansionState.withExpanded([x]),
        compactFolders: true,
        query: 'other',
      );
      expect(controller.rows.indexOfNode(chainA), -1);
      controller.expand(chainA);
      // The requested state records the same directory as the rows' own
      // requested state, so clearing the search shows what was asked for.
      expect(controller.expansion, controller.rows.requestedExpansion);
      controller.query = '';
      expectConsistentRows(controller);
      expect(
        controller.rows.expansion.isExpanded(chainC),
        controller.expansion.isExpanded(chainC),
      );
    });

    test('query keeps the raw text and parses it', () {
      final controller = sampleController();
      expect(
        notificationsOf(controller, () {
          controller.query = '   ';
        }),
        1,
      );
      expect(controller.query, '   ');
      expect(controller.parsedQuery, isNull);
      expect(controller.isFiltering, isFalse);
      controller.query = ' main ';
      expect(controller.query, ' main ');
      expect(controller.parsedQuery, TreeQuery.parse(' main '));
      expect(
        notificationsOf(controller, () {
          controller.query = ' main ';
        }),
        0,
      );
    });

    test('combines the query and the filter', () {
      final dartFiles = TreeFilter.where<Object?>(
        (node) => node.isFile && node.name.endsWith('.dart'),
      );
      final controller = sampleController()..filter = dartFiles;
      expect(controller.isFiltering, isTrue);
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'src',
        'a.dart',
        'b.dart',
        'main.dart',
        'test',
        'main_test.dart',
      ]);
      controller.query = 'main';
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'main.dart',
        'test',
        'main_test.dart',
      ]);
      expect(controller.rows.filter, TreeQuery.parse('main').and(dartFiles));
      expectConsistentRows(controller);
      controller.filter = TreeFilter.all;
      expect(controller.rows.filter, TreeQuery.parse('main'));
      expect(
        notificationsOf(controller, () {
          controller.filter = TreeFilter.all;
        }),
        0,
      );
    });

    test('caseSensitiveQuery parses again', () {
      final controller = sampleController()..query = 'readme';
      expect(labelsOf(controller.rows), ['repo', 'README.md']);
      controller.caseSensitiveQuery = true;
      expect(controller.parsedQuery!.caseSensitive, isTrue);
      expect(controller.rows, isEmpty);
    });

    test('a query that matches nothing clears a hidden focus', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..focus(lib);
      controller.query = 'zzz';
      expect(controller.rows, isEmpty);
      expect(controller.focusedId, isNull);
    });

    test('a focused node the filter hides moves to the first match', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..focus(readme);
      controller.query = 'main';
      expect(controller.focusedId, mainDart);
    });

    test('match ranges come from the query for matching rows only', () {
      final controller = sampleController()..query = 'main';
      final rows = controller.rows;
      expect(controller.matchRangesOf(rows[0]), isEmpty);
      final mainRow = rows.rowOf(mainDart)!;
      expect(controller.matchRangesOf(mainRow), [(start: 0, end: 4)]);
      controller
        ..query = ''
        ..filter = TreeFilter.where<Object?>((node) => node.name == 'repo');
      expect(controller.matchRangesOf(controller.rows.first), isEmpty);
    });
  });

  group('compact folders and hidden roots', () {
    test('compactFolders recomputes and normalizes the focus', () {
      final controller = DirectoryTreeController<int>(
        tree: chainTree(),
        expansion: ExpansionState.withExpanded([x, chainA, chainB]),
      )..focus(chainB);
      final before = controller.rows;
      expect(
        notificationsOf(controller, () {
          controller.compactFolders = true;
        }),
        1,
      );
      expect(labelsOf(controller.rows), ['x', 'A/B/C', 'other.txt']);
      expect(controller.lastRowsChange, TreeRowsChange.reset(previous: before));
      expect(controller.focusedId, chainC);
      expect(controller.focusedRow!.label, 'A/B/C');
      expect(controller.focus(chainA), isTrue);
      expect(controller.focusedId, chainC);
    });

    test('showRoots false hides the roots', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      )..focus(repo);
      expect(
        notificationsOf(controller, () {
          controller.showRoots = false;
        }),
        1,
      );
      expect(labelsOf(controller.rows), ['lib', 'test', 'README.md']);
      expect(controller.focusedId, isNull);
      expect(controller.focus(repo), isFalse);
      expect(controller.reveal(repo), isFalse);
      expect(controller.isExpanded(repo), isTrue);
      expect(notificationsOf(controller, () => controller.collapse(repo)), 0);
      expect(notificationsOf(controller, () => controller.expand(repo)), 0);
      expect(controller.reveal(aDart), isTrue);
      expect(labelsOf(controller.rows), [
        'lib',
        'src',
        'a.dart',
        'b.dart',
        'main.dart',
        'test',
        'README.md',
      ]);
      controller.collapseAll();
      expect(labelsOf(controller.rows), ['lib', 'test', 'README.md']);
      expect(controller.focusedId, lib);
      // The root counted as expanded while hidden, so it shows open.
      controller.showRoots = true;
      expect(labelsOf(controller.rows), ['repo', 'lib', 'test', 'README.md']);
      expectConsistentRows(controller);
    });
  });

  group('viewports', () {
    test('ensureVisible shows the row on every attached viewport', () async {
      final first = FakeViewport();
      final second = FakeViewport();
      final controller =
          sampleController(expansion: ExpansionState.withExpanded([repo]))
            ..attachViewport(first)
            ..attachViewport(first)
            ..attachViewport(second);
      await controller.ensureVisible(
        readme,
        duration: const Duration(milliseconds: 50),
        curve: Curves.linear,
        alignment: 1,
      );
      const expected = (
        index: 3,
        duration: Duration(milliseconds: 50),
        curve: Curves.linear,
        alignment: 1.0,
      );
      expect(first.shown, [expected]);
      expect(second.shown, [expected]);
      controller.detachViewport(second);
      await controller.ensureVisible(lib);
      expect(first.shown, hasLength(2));
      expect(second.shown, hasLength(1));
    });

    test('ensureVisible does nothing without a row', () async {
      final viewport = FakeViewport();
      final controller = sampleController()..attachViewport(viewport);
      await controller.ensureVisible(aDart);
      await controller.ensureVisible(unknown);
      expect(viewport.shown, isEmpty);
    });

    test(
      'ensureVisible shows the compacted row of an inner directory',
      () async {
        final viewport = FakeViewport();
        final controller = DirectoryTreeController<int>(
          tree: chainTree(),
          expansion: ExpansionState.withExpanded([x]),
          compactFolders: true,
        )..attachViewport(viewport);
        await controller.ensureVisible(chainA);
        expect(viewport.shown.single.index, 1);
      },
    );

    test('globalRowRect asks the attached viewports in order', () {
      final controller = sampleController(
        expansion: ExpansionState.withExpanded([repo]),
      );
      expect(controller.globalRowRect(0), isNull);
      final first = FakeViewport();
      final second = FakeViewport()
        ..rects[1] = const Rect.fromLTWH(0, 20, 100, 20)
        ..rects[2] = const Rect.fromLTWH(0, 40, 100, 20);
      controller
        ..attachViewport(first)
        ..attachViewport(second);
      first.rects[2] = const Rect.fromLTWH(10, 40, 90, 20);
      expect(controller.globalRowRect(1), const Rect.fromLTWH(0, 20, 100, 20));
      expect(controller.globalRowRect(2), const Rect.fromLTWH(10, 40, 90, 20));
      expect(controller.globalRowRect(0), isNull);
      expect(controller.globalRowRect(-1), isNull);
      expect(controller.globalRowRect(controller.rows.length), isNull);
    });
  });

  test('dispose drops viewports', () async {
    final viewport = FakeViewport();
    final controller = sampleController()..attachViewport(viewport);
    controller.dispose();
    await controller.ensureVisible(repo);
    expect(viewport.shown, isEmpty);
  });
}
