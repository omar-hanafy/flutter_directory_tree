import 'dart:async';

import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/widgets/row_scope.dart';
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

    test('a new tree keeps folders collapsed inside a collapsed parent', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'dart',
      );
      controller
        ..collapse(src)
        ..collapse(lib)
        ..updateTree((builder) => builder.addFile('/repo/test/x.dart'))
        ..expand(lib);
      expect(controller.isExpanded(src), isFalse);
      expect(labelsOf(controller.rows), [
        'repo',
        'lib',
        'src',
        'main.dart',
        'test',
        'main_test.dart',
        'x.dart',
      ]);
      expectConsistentRows(controller);
    });

    test('collapseSubtree and collapseAll survive tree swaps', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'dart',
      )..collapseSubtree(lib);
      controller
        ..tree = controller.tree.rebuild((builder) {})
        ..expand(lib);
      expect(controller.isExpanded(src), isFalse);
      controller
        ..collapseAll()
        ..updateTree((builder) => builder.addFile('/repo/lib/src/c.dart'))
        ..expand(repo)
        ..expand(lib);
      expect(controller.isExpanded(src), isFalse);
      expect(controller.isExpanded(testDir), isFalse);
      expectConsistentRows(controller);
    });

    test('a match in a folder that held none opens it', () {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        query: 'c.dart',
      );
      expect(controller.rows, isEmpty);
      controller.updateTree(
        (builder) => builder.addFile('/repo/lib/src/c.dart'),
      );
      expect(labelsOf(controller.rows), ['repo', 'lib', 'src', 'c.dart']);
      expectConsistentRows(controller);
    });

    test('a folder shown only for its own name opens for a new match', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/src/readme.txt'),
          TreeEntry.file('/r/other.txt'),
        ]),
        query: 'src',
      );
      // src matches, but nothing inside it does, so the search left it
      // closed.
      expect(labelsOf(controller.rows), ['r', 'src']);
      controller.updateTree(
        (builder) => builder.addFile('/r/src/src_util.dart'),
      );
      expect(labelsOf(controller.rows), ['r', 'src', 'src_util.dart']);
      expectConsistentRows(controller);
    });

    test('without revealMatches the effective state is kept as it is', () {
      // The row a/b/c is closed, so breaking its chain opens nothing.
      final controller = DirectoryTreeController<int>(
        tree: matchTree(),
        expansion: ExpansionState.withExpanded([r]),
        compactFolders: true,
        query: 'm.txt',
        revealMatches: false,
      );
      expect(labelsOf(controller.rows), ['r', 'a/b/c']);
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

    test('a selected folder that joins a chain selects the chain end', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/b/c/file.txt'),
          TreeEntry.file('/r/other.txt'),
        ]),
        expansion: ExpansionState.withExpanded([r]),
      )..select(a);
      expect(controller.selection.selected, {a});
      controller.compactFolders = true;
      expect(controller.selection.selected, {c});
      expect(controller.selection.anchor, c);
      expect(controller.isSelected(controller.rows[1].id), isTrue);
    });

    test('a selection that maps back to the current one does not notify', () {
      final controller = compactedController()..select(c);
      final selection = controller.selection;
      final notifications = notificationsOf(
        controller,
        () => controller.selection = SelectionState(
          mode: SelectionMode.multiple,
          selected: const [a],
          anchor: a,
        ),
      );
      expect(notifications, 0);
      expect(controller.selection, selection);
    });

    test('reloading a chain member keeps the chain row as it was', () async {
      final loader = FakeLoader<int>();
      const d = NodeId('/r/d');
      const sDir = NodeId('/r/d/s');
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/d/s/m.dart'),
          TreeEntry.file('/r/d/s/n.txt'),
          TreeEntry.file('/r/z.txt'),
        ]),
        expansion: const ExpansionState.expanded(),
        compactFolders: true,
        loadChildren: loader.call,
      )..toggleExpansion(sDir);
      expect(labelsOf(controller.rows), ['r', 'd/s', 'z.txt']);
      unawaited(controller.reloadChildren(d));
      await settle();
      loader.complete(d, const [
        TreeEntry.file('/r/d/s/m.dart'),
        TreeEntry.file('/r/d/s/n.txt'),
      ]);
      await settle();
      expect(labelsOf(controller.rows), ['r', 'd/s', 'z.txt']);
      expectConsistentRows(controller);
    });

    group('refreshing a compacted row', () {
      const aDir = NodeId('/r/a');
      const bDir = NodeId('/r/a/b');

      DirectoryTreeController<int> chained(
        FakeLoader<int> loader, {
        required List<NodeId> expanded,
        String query = '',
      }) => DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/b/x.txt'),
          TreeEntry.file('/r/f.txt'),
        ]),
        expansion: ExpansionState.withExpanded(expanded),
        compactFolders: true,
        query: query,
        loadChildren: loader.call,
        onLoadError: (_, _, _) {},
      );

      // A loader that lists one level returns a without its contents.
      Future<void> refreshRoot(
        DirectoryTreeController<int> controller,
        FakeLoader<int> loader,
      ) async {
        unawaited(controller.reloadChildren(r));
        await settle();
        loader.complete(r, const [
          TreeEntry.directory('/r/a'),
          TreeEntry.file('/r/f.txt'),
        ]);
        await settle();
      }

      test('a closed row lists its first folder when it opens', () async {
        final loader = FakeLoader<int>();
        final controller = chained(loader, expanded: [r]);
        expect(labelsOf(controller.rows), ['r', 'a/b', 'f.txt']);
        await refreshRoot(controller, loader);
        expect(loader.callsFor(aDir), isEmpty);
        controller.toggleExpansion(bDir);
        await settle();
        expect(loader.callsFor(aDir), hasLength(1));
      });

      test(
        'an open row shows and retries the load of its first folder',
        () async {
          final loader = FakeLoader<int>();
          final controller = chained(loader, expanded: [r, bDir]);
          expect(labelsOf(controller.rows), ['r', 'a/b', 'x.txt', 'f.txt']);
          await refreshRoot(controller, loader);
          TreeRow<int> row() => controller.rows[1];
          expect(row().id, bDir);
          expect(rowLoadStatus(controller, row()), DirectoryLoadStatus.loading);
          loader.fail(aDir, 'offline');
          await settle();
          expect(rowLoadStatus(controller, row()), DirectoryLoadStatus.failed);
          controller.expand(bDir);
          await settle();
          expect(loader.callsFor(aDir), hasLength(2));
          expect(rowLoadStatus(controller, row()), DirectoryLoadStatus.loading);
        },
      );

      test('a chain that breaks keeps its open row open', () {
        final controller = chained(FakeLoader<int>(), expanded: [r, bDir]);
        controller.updateTree((builder) => builder.addFile('/r/a/new.txt'));
        expect(labelsOf(controller.rows), [
          'r',
          'a',
          'b',
          'x.txt',
          'new.txt',
          'f.txt',
        ]);
        expect(controller.expansion.isExpanded(aDir), isTrue);
        expectConsistentRows(controller);
      });

      test('a chain that breaks out of sight keeps its open row open', () {
        const p = NodeId('/r/p');
        const pa = NodeId('/r/p/a');
        const pc = NodeId('/r/p/a/b/c');
        final controller = DirectoryTreeController<int>(
          tree: DirectoryTree<int>.build(const [
            TreeEntry.file('/r/p/a/b/c/x.txt'),
            TreeEntry.file('/r/p/f.txt'),
            TreeEntry.file('/r/z.txt'),
          ]),
          expansion: ExpansionState.withExpanded([r, p, pc]),
          compactFolders: true,
        );
        expect(labelsOf(controller.rows), [
          'r',
          'p',
          'a/b/c',
          'x.txt',
          'f.txt',
          'z.txt',
        ]);
        controller
          ..collapse(p)
          ..updateTree((builder) => builder.addFile('/r/p/a/new.txt'))
          ..expand(p);
        expect(labelsOf(controller.rows), [
          'r',
          'p',
          'a',
          'b/c',
          'x.txt',
          'new.txt',
          'f.txt',
          'z.txt',
        ]);
        expect(controller.isExpanded(pa), isTrue);
        expectConsistentRows(controller);
      });

      test('a chain that breaks keeps its closed row closed', () {
        final controller = DirectoryTreeController<int>(
          tree: DirectoryTree<int>.build(const [
            TreeEntry.file('/r/a/b/x.txt'),
            TreeEntry.file('/r/a/f.txt'),
            TreeEntry.file('/r/q.txt'),
          ]),
          expansion: ExpansionState.withExpanded([r, aDir]),
          compactFolders: true,
        );
        expect(labelsOf(controller.rows), ['r', 'a', 'b', 'f.txt', 'q.txt']);
        // An atomic save seen as a removal and an addition: the chain forms
        // with its row closed, then breaks again.
        controller.updateTree((builder) => builder.remove('/r/a/f.txt'));
        expect(labelsOf(controller.rows), ['r', 'a/b', 'q.txt']);
        controller.updateTree((builder) => builder.addFile('/r/a/f.txt'));
        expect(labelsOf(controller.rows), ['r', 'a', 'q.txt']);
        expect(controller.isExpanded(aDir), isFalse);
        expectConsistentRows(controller);
      });

      test('a chain that breaks in a state expanded by default', () {
        final controller = DirectoryTreeController<int>(
          tree: DirectoryTree<int>.build(const [
            TreeEntry.file('/r/a/b/x.txt'),
            TreeEntry.file('/r/q.txt'),
          ]),
          // Everything expanded except a, which the row a/b never consults.
          expansion: ExpansionState.withCollapsed([aDir]),
          compactFolders: true,
        );
        expect(labelsOf(controller.rows), ['r', 'a/b', 'x.txt', 'q.txt']);
        controller.updateTree((builder) => builder.addFile('/r/a/f.txt'));
        expect(labelsOf(controller.rows), [
          'r',
          'a',
          'b',
          'x.txt',
          'f.txt',
          'q.txt',
        ]);
        expectConsistentRows(controller);
      });

      test('a new tree restarts only the outermost load of a row', () async {
        final loader = FakeLoader<int>();
        const cDir = NodeId('/r/a/b/c');
        final controller = DirectoryTreeController<int>(
          tree: DirectoryTree<int>.build(const [
            TreeEntry.directory('/r/a/b/c'),
            TreeEntry.file('/r/z.txt'),
          ]),
          expansion: ExpansionState.withExpanded([r]),
          compactFolders: true,
          loadChildren: loader.call,
        );
        expect(labelsOf(controller.rows), ['r', 'a/b/c', 'z.txt']);
        controller.expand(cDir);
        final reloads = [
          controller.reloadChildren(aDir),
          controller.reloadChildren(bDir),
        ];
        await settle();
        expect(loader.calls, hasLength(3));
        controller.updateTree((builder) => builder.addFile('/r/y.txt'));
        await settle();
        expect(loader.callsFor(aDir), hasLength(2));
        expect(loader.callsFor(bDir), hasLength(1));
        expect(loader.callsFor(cDir), hasLength(1));
        expect(
          rowLoadStatus(controller, controller.rows[1]),
          DirectoryLoadStatus.loading,
        );
        // The futures of the discarded reloads follow the restart.
        var done = 0;
        for (final reload in reloads) {
          unawaited(reload.then((_) => done++));
        }
        for (final call in loader.calls.take(3)) {
          call.completer.complete(const <TreeEntry<int>>[]);
        }
        await settle();
        expect(done, 0);
        loader.complete(aDir, const [TreeEntry.directory('/r/a/b/c')]);
        await settle();
        expect(done, 2);
        expectConsistentRows(controller);
      });

      test('a new chain end loads while filtering', () async {
        final loader = FakeLoader<int>();
        const d = NodeId('/r/d');
        const e = NodeId('/r/d/e');
        final controller = DirectoryTreeController<int>(
          tree: DirectoryTree<int>.build(const [
            TreeEntry.directory('/r/d'),
            TreeEntry.file('/r/z.txt'),
          ]),
          compactFolders: true,
          query: 'd',
          loadChildren: loader.call,
        );
        expect(labelsOf(controller.rows), ['r', 'd']);
        controller.expand(d);
        await settle();
        loader.complete(d, const [TreeEntry.directory('/r/d/e')]);
        await settle();
        // The row d/e shows because d matches; e itself does not.
        expect(labelsOf(controller.rows), ['r', 'd/e']);
        expect(loader.callsFor(e), hasLength(1));
      });
    });

    test('an anchor that outlived the selection moves to the chain end', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/b/c/file.txt'),
          TreeEntry.file('/r/other.txt'),
        ]),
        expansion: ExpansionState.withExpanded([r]),
      )..toggleSelected(a);
      // Toggling the only selected folder again keeps it as the anchor.
      controller.toggleSelected(a);
      expect(controller.selection.selected, isEmpty);
      expect(controller.selection.anchor, a);
      controller.compactFolders = true;
      expect(controller.selection.anchor, c);
    });

    test('a tree swap that puts a selected folder in a chain', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/b/c/file.txt'),
          TreeEntry.file('/r/a/x.txt'),
          TreeEntry.file('/r/other.txt'),
        ]),
        expansion: ExpansionState.withExpanded([r]),
        compactFolders: true,
      )..select(a);
      expect(controller.selection.selected, {a});
      controller.updateTree((builder) => builder.remove('/r/a/x.txt'));
      expect(labelsOf(controller.rows), ['r', 'a/b/c', 'other.txt']);
      expect(controller.selection.selected, {c});
    });

    test('a chain member selected without a row selects the chain end', () {
      final controller = compactedController(
        expansion: const ExpansionState.collapsed(),
      )..select(a);
      expect(controller.selection.selected, {c});
      expect(controller.reveal(a), isTrue);
      expect(controller.isSelected(controller.focusedId!), isTrue);
    });

    test('reveal selects the chain end of a member the filter hides', () {
      final controller = compactedController()..query = 'other';
      expect(labelsOf(controller.rows), ['r', 'other.txt']);
      expect(controller.reveal(a, select: true), isFalse);
      expect(controller.selection.selected, {c});
      controller.query = '';
      expect(labelsOf(controller.rows), ['r', 'a/b/c', 'other.txt']);
      expect(controller.isSelected(controller.rows[1].id), isTrue);
    });

    test('a selection given to the constructor selects chain ends', () {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry.file('/r/a/b/c/file.txt'),
          TreeEntry.file('/r/other.txt'),
        ]),
        expansion: ExpansionState.withExpanded([r]),
        compactFolders: true,
        selection: SelectionState(
          mode: SelectionMode.multiple,
          selected: const [a, otherTxt],
          anchor: a,
        ),
      );
      expect(controller.selection.selected, {c, otherTxt});
      expect(controller.selection.anchor, c);
      expect(controller.isSelected(controller.rows[1].id), isTrue);
      // A refresh that changes nothing about the chain keeps the selection.
      final selection = controller.selection;
      controller.updateTree((builder) => builder.addFile('/r/new.txt'));
      expect(controller.selection, selection);
    });

    test('setting the selection selects chain ends', () {
      final controller = compactedController();
      var notifications = 0;
      controller
        ..addListener(() => notifications++)
        ..selection = SelectionState(
          mode: SelectionMode.multiple,
          selected: const [b],
          anchor: b,
        );
      expect(controller.selection.selected, {c});
      expect(controller.selection.anchor, c);
      expect(notifications, 1);
      expect(controller.isSelected(controller.rows[1].id), isTrue);
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
