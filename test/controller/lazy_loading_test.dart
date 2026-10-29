import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

const r = NodeId('/r');
const lazy = NodeId('/r/lazy');
const other = NodeId('/r/other');
const fileTxt = NodeId('/r/file.txt');

/// `/r` with the empty directories `lazy` and `other` and a file.
DirectoryTree<String> lazyTree() => DirectoryTree<String>.build(const [
  TreeEntry.directory('/r/lazy'),
  TreeEntry.directory('/r/other'),
  TreeEntry.file('/r/file.txt'),
]);

final class LoadErrors {
  final List<(NodeId, Object, StackTrace)> calls = [];

  void call(NodeId directory, Object error, StackTrace stackTrace) =>
      calls.add((directory, error, stackTrace));
}

DirectoryTreeController<String> lazyController(
  FakeLoader<String> loader, {
  LoadErrors? errors,
  DirectoryTree<String>? tree,
  ExpansionState expansion = const ExpansionState.collapsed(),
  bool showRoots = true,
}) => DirectoryTreeController<String>(
  tree: tree ?? lazyTree(),
  expansion: expansion,
  showRoots: showRoots,
  loadChildren: loader.call,
  onLoadError: errors?.call,
);

void main() {
  group('statuses', () {
    test('follow the tree and the loader', () {
      final controller = lazyController(FakeLoader<String>());
      expect(controller.loadStatusOf(r), DirectoryLoadStatus.loaded);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.notLoaded);
      expect(controller.loadStatusOf(fileTxt), DirectoryLoadStatus.loaded);
      expect(controller.loadStatusOf(unknown), DirectoryLoadStatus.notLoaded);
      expect(controller.loadErrorOf(lazy), isNull);
      final plain = DirectoryTreeController<String>(tree: lazyTree());
      expect(plain.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      expect(plain.isExpandable(lazy), isFalse);
    });

    test('isExpandable covers lazy directories without a filter only', () {
      final controller = lazyController(
        FakeLoader<String>(),
        expansion: ExpansionState.withExpanded([r]),
      );
      expect(controller.isExpandable(r), isTrue);
      expect(controller.isExpandable(lazy), isTrue);
      expect(controller.isExpandable(fileTxt), isFalse);
      expect(controller.isExpandable(unknown), isFalse);
      controller.query = 'lazy';
      expect(controller.rows.rowOf(lazy), isNotNull);
      expect(controller.isExpandable(lazy), isFalse);
    });
  });

  group('loading', () {
    test('expand marks the directory, loads, and merges', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(
        loader,
        expansion: ExpansionState.withExpanded([r]),
      );
      final counter = NotificationCounter(controller);
      controller.expand(lazy);
      expect(counter.take(), 1);
      expect(controller.isExpanded(lazy), isTrue);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      expect(controller.isExpandable(lazy), isTrue);
      // The loader runs after the command, not inside it.
      expect(loader.calls, isEmpty);
      await settle();
      expect(loader.calls.single.directory.id, lazy);

      final before = controller.rows;
      expect(labelsOf(before), ['r', 'lazy', 'other', 'file.txt']);
      final recorder = RowsChangeRecorder(controller);
      loader.complete(lazy, const [
        TreeEntry.file('/r/lazy/b.txt', data: 'b'),
        TreeEntry.file('/r/lazy/a.txt', data: 'a'),
        TreeEntry.directory('/r/lazy/sub'),
      ]);
      await settle();
      expect(counter.take(), 1);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      expect(
        controller.loadStatusOf(const NodeId('/r/lazy/sub')),
        DirectoryLoadStatus.notLoaded,
      );
      expect(labelsOf(controller.rows), [
        'r',
        'lazy',
        'sub',
        'a.txt',
        'b.txt',
        'other',
        'file.txt',
      ]);
      expect(recorder.changes, [
        TreeRowsChange.splice(
          previous: before,
          index: 2,
          removed: 0,
          inserted: 3,
        ),
      ]);
      // The old tree is released once listeners ran; the splice stays.
      expect(
        controller.lastRowsChange,
        const TreeRowsChange.splice(
          previous: null,
          index: 2,
          removed: 0,
          inserted: 3,
        ),
      );
      expect(controller.tree.nodeAt('/r/lazy/a.txt')!.data, 'a');
      expectConsistentRows(controller);
    });

    test(
      'expand of a chain member without a row loads the chain end',
      () async {
        final loader = FakeLoader<String>();
        const p = NodeId('/r/p');
        const pa = NodeId('/r/p/a');
        const pab = NodeId('/r/p/a/b');
        final controller = DirectoryTreeController<String>(
          tree: DirectoryTree<String>.build(const [
            TreeEntry.directory('/r/p/a/b'),
            TreeEntry.file('/r/p/q.txt'),
            TreeEntry.file('/r/z.txt'),
          ]),
          expansion: ExpansionState.withExpanded([r]),
          compactFolders: true,
          loadChildren: loader.call,
        );
        // p is collapsed, so the chain a/b has no row.
        expect(controller.rows.indexOfNode(pa), -1);
        controller.expand(pa);
        expect(controller.expansion.isExpanded(pab), isTrue);
        expect(controller.loadStatusOf(pab), DirectoryLoadStatus.loading);
        await settle();
        expect(loader.callsFor(pab), hasLength(1));
        controller.expand(p);
        expect(labelsOf(controller.rows), ['r', 'p', 'a/b', 'q.txt', 'z.txt']);
        expectConsistentRows(controller);
      },
    );

    test(
      'a load that returns one folder keeps the compacted row open',
      () async {
        final loader = FakeLoader<String>();
        const sub = NodeId('/r/lazy/sub');
        final controller = DirectoryTreeController<String>(
          tree: lazyTree(),
          expansion: ExpansionState.withExpanded([r]),
          compactFolders: true,
          loadChildren: loader.call,
        );
        controller.expand(lazy);
        await settle();
        loader.complete(lazy, const [TreeEntry.directory('/r/lazy/sub')]);
        await settle();
        expect(labelsOf(controller.rows), [
          'r',
          'lazy/sub',
          'other',
          'file.txt',
        ]);
        expect(controller.rows[1].isExpanded, isTrue);
        expect(controller.expansion.isExpanded(sub), isTrue);
        expect(controller.loadStatusOf(sub), DirectoryLoadStatus.loading);
        await settle();
        loader.complete(sub, const [TreeEntry.file('/r/lazy/sub/f.txt')]);
        await settle();
        expect(labelsOf(controller.rows), [
          'r',
          'lazy/sub',
          'f.txt',
          'other',
          'file.txt',
        ]);
        expectConsistentRows(controller);
      },
    );

    test('a folder collapsed during its load keeps its row closed', () async {
      final loader = FakeLoader<String>();
      const sub = NodeId('/r/lazy/sub');
      final controller = DirectoryTreeController<String>(
        tree: lazyTree(),
        expansion: ExpansionState.withExpanded([r]),
        compactFolders: true,
        loadChildren: loader.call,
      )..expand(lazy);
      await settle();
      controller.collapse(lazy);
      loader.complete(lazy, const [TreeEntry.directory('/r/lazy/sub')]);
      await settle();
      expect(labelsOf(controller.rows), ['r', 'lazy/sub', 'other', 'file.txt']);
      expect(controller.rows[1].isExpanded, isFalse);
      expect(controller.loadStatusOf(sub), DirectoryLoadStatus.notLoaded);
      await settle();
      expect(loader.callsFor(sub), isEmpty);
    });

    test('one load per directory at a time', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      final first = controller.loadChildren(lazy);
      final second = controller.loadChildren(lazy);
      expect(identical(first, second), isTrue);
      expect(identical(controller.reloadChildren(lazy), first), isTrue);
      controller.expand(lazy);
      await settle();
      expect(loader.calls, hasLength(1));
      final completion = NotificationCounter(controller);
      loader.complete(lazy, const []);
      await first;
      expect(completion.count, 1);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      // A loaded directory, even an empty one, does not load again.
      expect(controller.isExpandable(lazy), isFalse);
      final counter = NotificationCounter(controller);
      await controller.loadChildren(lazy);
      expect(counter.count, 0);
      expect(loader.calls, hasLength(1));
    });

    test('a failure is stored, reported, and retried by expand', () async {
      final loader = FakeLoader<String>();
      final errors = LoadErrors();
      final controller = lazyController(
        loader,
        errors: errors,
        expansion: ExpansionState.withExpanded([r]),
      );
      final counter = NotificationCounter(controller);
      controller.expand(lazy);
      final load = controller.loadChildren(lazy);
      await settle();
      loader.fail(lazy, StateError('offline'));
      await expectLater(load, completes);
      expect(counter.take(), 2);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.failed);
      expect(controller.loadErrorOf(lazy), isA<StateError>());
      expect(errors.calls.single.$1, lazy);
      expect(errors.calls.single.$2, isA<StateError>());
      expect(controller.isExpanded(lazy), isTrue);
      expect(controller.isExpandable(lazy), isTrue);

      // Expanding the expanded directory retries.
      controller.expand(lazy);
      expect(counter.take(), 1);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      expect(controller.loadErrorOf(lazy), isNull);
      await settle();
      loader.complete(lazy, const [TreeEntry.file('/r/lazy/x.txt')]);
      await settle();
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      expect(labelsOf(controller.rows), contains('x.txt'));
    });

    test('a loader that throws synchronously fails like any other', () async {
      final errors = LoadErrors();
      final controller = DirectoryTreeController<String>(
        tree: lazyTree(),
        loadChildren: (directory) => throw ArgumentError('bad'),
        onLoadError: errors.call,
      );
      await expectLater(controller.loadChildren(lazy), completes);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.failed);
      expect(errors.calls.single.$2, isA<ArgumentError>());
    });

    test('an onLoadError that throws is reported to FlutterError', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final loader = FakeLoader<String>();
      final controller = DirectoryTreeController<String>(
        tree: lazyTree(),
        loadChildren: loader.call,
        onLoadError: (directory, error, stackTrace) =>
            throw StateError('in the callback'),
      );
      final load = controller.loadChildren(lazy);
      await settle();
      loader.fail(lazy, 'failure');
      await expectLater(load, completes);
      expect(reported.single.exception, isA<StateError>());
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.failed);
    });

    test('ignores entries that are not strictly inside', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      final load = controller.loadChildren(lazy);
      await settle();
      loader.complete(lazy, const [
        TreeEntry.file('/r/lazy/inside.txt'),
        TreeEntry.file('/r/lazy/deep/er/file.txt'),
        TreeEntry.directory('/r/lazy'),
        TreeEntry.file('/r/lazyx/near.txt'),
        TreeEntry.file('/r/other/sibling.txt'),
        TreeEntry.file('/elsewhere/far.txt'),
        TreeEntry.file(''),
        TreeEntry.file('/r/lazy/../escape.txt'),
      ]);
      await load;
      final paths = [
        for (final node in controller.tree.nodes) node.path.toString(),
      ];
      expect(paths, [
        '/r',
        '/r/lazy',
        '/r/lazy/deep',
        '/r/lazy/deep/er',
        '/r/lazy/deep/er/file.txt',
        '/r/lazy/inside.txt',
        '/r/other',
        '/r/file.txt',
      ]);
    });

    test(
      'compares ids, so any casing is inside a case-insensitive tree',
      () async {
        final loader = FakeLoader<String>();
        final tree = DirectoryTree<String>.build(const [
          TreeEntry.directory('/Repo/Lazy'),
          TreeEntry.file('/Repo/top.txt'),
        ], options: const TreeOptions(paths: PathPolicy.caseInsensitive));
        final controller = lazyController(loader, tree: tree);
        final id = tree.idOf('/repo/lazy')!;
        final load = controller.loadChildren(id);
        await settle();
        loader.complete(id, const [
          TreeEntry.file('/REPO/LAZY/Upper.txt'),
          TreeEntry.file('/repo/lazy/lower.txt'),
          TreeEntry.file('/REPO/LAZYX/no.txt'),
        ]);
        await load;
        expect(controller.tree.nodeAt('/repo/lazy/upper.txt'), isNotNull);
        expect(controller.tree.nodeAt('/repo/lazy/lower.txt'), isNotNull);
        expect(controller.tree.nodeAt('/repo/lazyx/no.txt'), isNull);
        expect(controller.loadStatusOf(id), DirectoryLoadStatus.loaded);
      },
    );

    test('a checked directory checks its loaded leaves', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader)..toggleChecked(lazy);
      expect(controller.checkStateOf(lazy), CheckState.checked);
      final load = controller.loadChildren(lazy);
      await settle();
      loader.complete(lazy, const [
        TreeEntry.file('/r/lazy/a.txt'),
        TreeEntry.file('/r/lazy/b.txt'),
      ]);
      await load;
      expect(controller.checkStateOf(lazy), CheckState.checked);
      expect(controller.checks.selected, {
        const NodeId('/r/lazy/a.txt'),
        const NodeId('/r/lazy/b.txt'),
      });
    });

    test('bulk expansion commands start no loads', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader)
        ..expandAll()
        ..collapseAll()
        ..expandSubtree(r)
        ..expansion = ExpansionState.withExpanded([r, lazy, other]);
      controller.reveal(lazy);
      await settle();
      expect(loader.calls, isEmpty);
      expect(controller.isExpanded(lazy), isTrue);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.notLoaded);
    });

    test('expand under a filter loads only a directory it shows', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(
        loader,
        expansion: ExpansionState.withExpanded([r]),
      )..query = 'lazy';
      controller.expand(other);
      await settle();
      expect(loader.calls, isEmpty);
      controller.expand(lazy);
      await settle();
      expect(loader.callsFor(lazy), hasLength(1));
    });

    test('loads of other directories survive a merge', () async {
      final loader = FakeLoader<String>();
      final controller =
          lazyController(loader, expansion: ExpansionState.withExpanded([r]))
            ..expand(lazy)
            ..expand(other);
      await settle();
      loader.complete(lazy, const [TreeEntry.file('/r/lazy/a.txt')]);
      await settle();
      expect(controller.loadStatusOf(other), DirectoryLoadStatus.loading);
      loader.complete(other, const [TreeEntry.file('/r/other/b.txt')]);
      await settle();
      expect(controller.loadStatusOf(other), DirectoryLoadStatus.loaded);
      expect(labelsOf(controller.rows), [
        'r',
        'lazy',
        'a.txt',
        'other',
        'b.txt',
        'file.txt',
      ]);
    });

    test('a reload drops the failures below the directory', () async {
      final loader = FakeLoader<String>();
      final tree = DirectoryTree<String>.build(const [
        TreeEntry.directory('/r/lazy/inner'),
        TreeEntry.file('/r/file.txt'),
      ]);
      final controller = lazyController(loader, tree: tree);
      const inner = NodeId('/r/lazy/inner');
      final failing = controller.loadChildren(inner);
      await settle();
      loader.fail(inner, 'nope');
      await failing;
      expect(controller.loadStatusOf(inner), DirectoryLoadStatus.failed);
      // Reload the parent, whose loader returns the inner contents too.
      final reload = controller.reloadChildren(lazy);
      expect(controller.tree.contains(inner), isFalse);
      expect(controller.loadErrorOf(inner), isNull);
      await settle();
      loader.complete(lazy, const [
        TreeEntry.directory('/r/lazy/inner'),
        TreeEntry.file('/r/lazy/inner/found.txt'),
      ]);
      await reload;
      expect(controller.loadStatusOf(inner), DirectoryLoadStatus.loaded);
      expect(controller.loadErrorOf(inner), isNull);
    });
  });

  group('reloadChildren', () {
    test('removes the contents at once and loads them again', () async {
      final loader = FakeLoader<String>();
      final tree = DirectoryTree<String>.build(const [
        TreeEntry.file('/r/dir/old.txt'),
        TreeEntry.file('/r/dir/sub/deep.txt'),
        TreeEntry.file('/r/file.txt'),
      ]);
      const dir = NodeId('/r/dir');
      const sub = NodeId('/r/dir/sub');
      final controller = lazyController(
        loader,
        tree: tree,
        expansion: ExpansionState.withExpanded([r, dir, sub]),
      )..focus(const NodeId('/r/dir/sub/deep.txt'));
      expect(tree[dir]!.isExplicit, isFalse);
      final before = controller.rows;
      final counter = NotificationCounter(controller);
      final recorder = RowsChangeRecorder(controller);
      final reload = controller.reloadChildren(dir);
      expect(counter.take(), 1);
      expect(controller.loadStatusOf(dir), DirectoryLoadStatus.loading);
      expect(controller.tree[dir]!.isExplicit, isTrue);
      expect(labelsOf(controller.rows), ['r', 'dir', 'file.txt']);
      expect(recorder.changes, [
        TreeRowsChange.splice(
          previous: before,
          index: 2,
          removed: 3,
          inserted: 0,
        ),
      ]);
      expect(controller.focusedId, dir);
      expect(controller.expansion, ExpansionState.withExpanded([r, dir]));
      expect(identical(controller.reloadChildren(dir), reload), isTrue);
      await settle();
      loader.complete(dir, const [TreeEntry.file('/r/dir/new.txt')]);
      await reload;
      expect(counter.take(), 1);
      expect(labelsOf(controller.rows), ['r', 'dir', 'new.txt', 'file.txt']);
      expect(controller.loadStatusOf(dir), DirectoryLoadStatus.loaded);
      expectConsistentRows(controller);
    });

    test('reopens the folders that were open as they load again', () async {
      final loader = FakeLoader<String>();
      const dir = NodeId('/r/dir');
      const sub = NodeId('/r/dir/sub');
      const deep = NodeId('/r/dir/sub/deep');
      const closed = NodeId('/r/dir/closed');
      final controller = lazyController(
        loader,
        tree: DirectoryTree<String>.build(const [
          TreeEntry.file('/r/dir/sub/deep/x.txt'),
          TreeEntry.file('/r/dir/closed/y.txt'),
          TreeEntry.file('/r/dir/a.txt'),
          TreeEntry.file('/r/file.txt'),
        ]),
        expansion: ExpansionState.withExpanded([r, dir, sub, deep]),
      );
      expect(labelsOf(controller.rows), [
        'r',
        'dir',
        'closed',
        'sub',
        'deep',
        'x.txt',
        'a.txt',
        'file.txt',
      ]);
      unawaited(controller.reloadChildren(dir));
      expect(labelsOf(controller.rows), ['r', 'dir', 'file.txt']);
      await settle();
      loader.complete(dir, const [
        TreeEntry.directory('/r/dir/sub'),
        TreeEntry.directory('/r/dir/closed'),
        TreeEntry.file('/r/dir/a.txt'),
      ]);
      await settle();
      expect(controller.isExpanded(sub), isTrue);
      expect(controller.loadStatusOf(sub), DirectoryLoadStatus.loading);
      expect(controller.isExpanded(closed), isFalse);
      expect(controller.loadStatusOf(closed), DirectoryLoadStatus.notLoaded);
      loader.complete(sub, const [TreeEntry.directory('/r/dir/sub/deep')]);
      await settle();
      expect(controller.loadStatusOf(deep), DirectoryLoadStatus.loading);
      loader.complete(deep, const [TreeEntry.file('/r/dir/sub/deep/x.txt')]);
      await settle();
      expect(labelsOf(controller.rows), [
        'r',
        'dir',
        'closed',
        'sub',
        'deep',
        'x.txt',
        'a.txt',
        'file.txt',
      ]);
      expect(
        controller.expansion,
        ExpansionState.withExpanded([r, dir, sub, deep]),
      );
      expect(loader.callsFor(closed), isEmpty);
      expectConsistentRows(controller);
    });

    test('a new tree ends the reopening', () async {
      final loader = FakeLoader<String>();
      const dir = NodeId('/r/dir');
      const sub = NodeId('/r/dir/sub');
      final controller = lazyController(
        loader,
        tree: DirectoryTree<String>.build(const [
          TreeEntry.file('/r/dir/sub/x.txt'),
          TreeEntry.file('/r/file.txt'),
        ]),
        expansion: ExpansionState.withExpanded([r, dir, sub]),
      );
      unawaited(controller.reloadChildren(dir));
      await settle();
      controller.tree = DirectoryTree<String>.build(const [
        TreeEntry.directory('/r/dir'),
        TreeEntry.file('/r/file.txt'),
      ]);
      // The expanded folder's discarded load starts again.
      await settle();
      expect(loader.callsFor(dir), hasLength(2));
      loader.complete(dir, const [TreeEntry.directory('/r/dir/sub')]);
      await settle();
      expect(controller.isExpanded(sub), isFalse);
      expect(loader.callsFor(sub), isEmpty);
    });

    test('keeps the check state of the directory', () async {
      final loader = FakeLoader<String>();
      final tree = DirectoryTree<String>.build(const [
        TreeEntry.file('/r/dir/a.txt'),
        TreeEntry.file('/r/dir/b.txt'),
        TreeEntry.file('/r/file.txt'),
      ]);
      const dir = NodeId('/r/dir');
      final controller = lazyController(loader, tree: tree)..toggleChecked(dir);
      final reload = controller.reloadChildren(dir);
      expect(controller.checkStateOf(dir), CheckState.checked);
      await settle();
      loader.complete(dir, const [
        TreeEntry.file('/r/dir/a.txt'),
        TreeEntry.file('/r/dir/c.txt'),
      ]);
      await reload;
      expect(controller.checkStateOf(dir), CheckState.checked);
      expect(controller.checks.selected, {
        const NodeId('/r/dir/a.txt'),
        const NodeId('/r/dir/c.txt'),
      });

      // A partially checked directory comes back unchecked.
      controller.setChecked(const NodeId('/r/dir/a.txt'), checked: false);
      final again = controller.reloadChildren(dir);
      expect(controller.checkStateOf(dir), CheckState.unchecked);
      await settle();
      loader.complete(dir, const [TreeEntry.file('/r/dir/a.txt')]);
      await again;
      expect(controller.checkStateOf(dir), CheckState.unchecked);
    });

    test('discards the loads below the directory', () async {
      final loader = FakeLoader<String>();
      final tree = DirectoryTree<String>.build(const [
        TreeEntry.directory('/r/dir/sub'),
        TreeEntry.file('/r/file.txt'),
      ]);
      const dir = NodeId('/r/dir');
      const sub = NodeId('/r/dir/sub');
      final controller = lazyController(loader, tree: tree);
      final inner = controller.loadChildren(sub);
      await settle();
      final reload = controller.reloadChildren(dir);
      await settle();
      loader.complete(sub, const [TreeEntry.file('/r/dir/sub/stale.txt')]);
      await inner;
      expect(controller.tree.nodeAt('/r/dir/sub/stale.txt'), isNull);
      loader.complete(dir, const [TreeEntry.directory('/r/dir/sub')]);
      await reload;
      expect(controller.loadStatusOf(sub), DirectoryLoadStatus.notLoaded);
      expect(controller.tree.nodeAt('/r/dir/sub/stale.txt'), isNull);
    });

    test('reloads an empty explicit directory like loadChildren', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      final first = controller.loadChildren(lazy);
      await settle();
      loader.complete(lazy, const []);
      await first;
      final again = controller.reloadChildren(lazy);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      await settle();
      expect(loader.callsFor(lazy), hasLength(2));
      loader.complete(lazy, const [TreeEntry.file('/r/lazy/z.txt')]);
      await again;
      expect(controller.tree.nodeAt('/r/lazy/z.txt'), isNotNull);
    });
  });

  group('discarding', () {
    test('a new tree resets statuses and drops running loads', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      final load = controller.loadChildren(lazy);
      final failed = controller.loadChildren(other);
      await settle();
      loader.fail(other, 'gone');
      await failed;
      controller.tree = lazyTree();
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.notLoaded);
      expect(controller.loadStatusOf(other), DirectoryLoadStatus.notLoaded);
      expect(controller.loadErrorOf(other), isNull);
      final counter = NotificationCounter(controller);
      loader.complete(lazy, const [TreeEntry.file('/r/lazy/late.txt')]);
      await expectLater(load, completes);
      expect(counter.count, 0);
      expect(controller.tree.nodeAt('/r/lazy/late.txt'), isNull);
      // A new load starts fresh.
      final fresh = controller.loadChildren(lazy);
      expect(identical(fresh, load), isFalse);
      await settle();
      expect(loader.callsFor(lazy), hasLength(2));
    });

    test('a new tree loads an expanded folder whose load it dropped', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(
        loader,
        expansion: ExpansionState.withExpanded([r]),
      )..expand(lazy);
      await settle();
      final stale = loader.callsFor(lazy).single;
      controller.updateTree((builder) => builder.addFile('/r/new.txt'));
      expect(controller.isExpanded(lazy), isTrue);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      await settle();
      expect(loader.callsFor(lazy), hasLength(2));
      stale.completer.complete(const [TreeEntry.file('/r/lazy/stale.txt')]);
      loader.complete(lazy, const [TreeEntry.file('/r/lazy/fresh.txt')]);
      await settle();
      expect(labelsOf(controller.rows), [
        'r',
        'lazy',
        'fresh.txt',
        'other',
        'file.txt',
        'new.txt',
      ]);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
    });

    test('finishing after dispose does nothing', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      final load = controller.loadChildren(lazy);
      final failing = controller.loadChildren(other);
      await settle();
      controller.dispose();
      loader
        ..complete(lazy, const [TreeEntry.file('/r/lazy/a.txt')])
        ..fail(other, 'late');
      await expectLater(load, completes);
      await expectLater(failing, completes);
      await expectLater(controller.loadChildren(lazy), completes);
      await expectLater(controller.reloadChildren(lazy), completes);
      expect(controller.tree.nodeAt('/r/lazy/a.txt'), isNull);
    });

    test('without a loader both methods complete at once', () async {
      final controller = DirectoryTreeController<String>(tree: lazyTree());
      final counter = NotificationCounter(controller);
      await controller.loadChildren(lazy);
      await controller.reloadChildren(r);
      expect(counter.count, 0);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      expect(controller.tree, lazyTree());
    });

    test('files and unknown ids complete at once', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      await controller.loadChildren(fileTxt);
      await controller.loadChildren(unknown);
      await controller.reloadChildren(fileTxt);
      await controller.reloadChildren(unknown);
      expect(loader.calls, isEmpty);
    });
  });

  group('hidden roots', () {
    test('load at construction', () async {
      final loader = FakeLoader<String>();
      final tree = DirectoryTree<String>.build(
        const [],
        options: const TreeOptions(roots: TreeRoots.fixed(['/project'])),
      );
      const project = NodeId('/project');
      final controller = lazyController(loader, tree: tree, showRoots: false);
      expect(controller.loadStatusOf(project), DirectoryLoadStatus.loading);
      await settle();
      expect(loader.callsFor(project), hasLength(1));
      loader.complete(project, const [
        TreeEntry.file('/project/a.txt'),
        TreeEntry.directory('/project/src'),
      ]);
      await settle();
      expect(labelsOf(controller.rows), ['src', 'a.txt']);
      expect(controller.focus(project), isFalse);
    });

    test('load when the tree is set and when showRoots turns false', () async {
      final loader = FakeLoader<String>();
      final controller = lazyController(loader);
      final counter = NotificationCounter(controller);
      controller.tree = DirectoryTree<String>.build(const [
        TreeEntry.directory('/one'),
        TreeEntry.directory('/two'),
      ]);
      expect(counter.take(), 1);
      await settle();
      expect(loader.calls, isEmpty);
      controller.showRoots = false;
      expect(counter.take(), 1);
      expect(
        controller.loadStatusOf(const NodeId('/one')),
        DirectoryLoadStatus.loading,
      );
      await settle();
      expect(loader.calls.map((call) => call.directory.id.value), [
        '/one',
        '/two',
      ]);
      loader.fail(const NodeId('/one'), 'no');
      loader.complete(const NodeId('/two'), const []);
      await settle();
      controller.tree = DirectoryTree<String>.build(const [
        TreeEntry.directory('/one'),
        TreeEntry.file('/two/t.txt'),
      ]);
      await settle();
      // The new tree starts over: /one loads again, /two has children.
      expect(loader.callsFor(const NodeId('/one')), hasLength(2));
      expect(loader.callsFor(const NodeId('/two')), hasLength(1));
    });
  });
}
