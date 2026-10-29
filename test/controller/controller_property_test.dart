import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'controller_test_utils.dart';

const _prefixes = ['/r', '/s', '/t/u', 'C:/w', '/'];
const _names = ['a', 'b', 'B', 'lib', 'src', 'x.txt', 'y.md', 'Main.dart'];
const _queries = [
  '',
  '  ',
  'a',
  'A',
  'x',
  'lib',
  'zzz',
  'ext:md',
  '*.txt',
  '!a',
  'type:d',
  'path:src',
  'b src',
];

final List<TreeFilter?> _filters = [
  null,
  TreeFilter.all,
  TreeFilter.where<Object?>((node) => node.isDirectory),
  TreeFilter.where<Object?>((node) => !node.name.contains('b')),
  TreeFilter.where<Object?>((node) => false),
  TreeFilter.where<Object?>((node) => node.path.extension == '.md'),
];

String _randomPath(Random random) {
  final prefix = _prefixes[random.nextInt(_prefixes.length)];
  final depth = random.nextInt(5);
  final segments = [
    for (var i = 0; i < depth; i++) _names[random.nextInt(_names.length)],
  ];
  if (segments.isEmpty) return prefix;
  final joined = segments.join('/');
  return prefix.endsWith('/') ? '$prefix$joined' : '$prefix/$joined';
}

TreeEntry<int> _randomEntry(Random random, int data) {
  final path = _randomPath(random);
  return random.nextInt(4) == 0
      ? TreeEntry<int>.directory(path, data: data)
      : TreeEntry<int>.file(path, data: data);
}

/// Up to 30 entries under several path roots, with repeated names (so
/// single-child chains, conflicts, and merges are common), explicit empty
/// directories, and a random root strategy.
DirectoryTree<int> _randomTree(Random random, PathPolicy policy) {
  final count = 1 + random.nextInt(30);
  const strategies = [
    TreeRoots.minimal(),
    TreeRoots.commonAncestor(),
    TreeRoots.filesystem(),
  ];
  return DirectoryTree<int>.build(
    [for (var i = 0; i < count; i++) _randomEntry(random, i)],
    options: TreeOptions(
      paths: policy,
      roots: strategies[random.nextInt(strategies.length)],
    ),
  );
}

ExpansionState _randomExpansion(Random random, DirectoryTree<Object?> tree) {
  final ids = [
    for (final node in tree.nodes)
      if (random.nextInt(3) == 0) node.id,
    if (random.nextBool()) unknown,
  ];
  return random.nextBool()
      ? ExpansionState.withExpanded(ids)
      : ExpansionState.withCollapsed(ids);
}

/// How often the runs reached the situations the invariants are about, so
/// a generator change cannot silently stop exercising them.
final Map<String, int> _coverage = <String, int>{};

void _cover(String situation) =>
    _coverage[situation] = (_coverage[situation] ?? 0) + 1;

/// Runs every pending microtask chain: loader calls and load completions
/// take a few microtask hops each. Unlike a zero timer, this costs no time
/// on the web, where timers are clamped.
Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

/// What the controller exposes, to tell whether a command changed anything.
final class _Snapshot {
  _Snapshot(DirectoryTreeController<int> controller)
    : tree = controller.tree,
      rows = controller.rows,
      change = controller.lastRowsChange,
      expansion = controller.expansion,
      selection = controller.selection,
      checks = controller.checks,
      focusedId = controller.focusedId,
      query = controller.query,
      caseSensitiveQuery = controller.caseSensitiveQuery,
      filter = controller.filter,
      revealMatches = controller.revealMatches,
      compactFolders = controller.compactFolders,
      showRoots = controller.showRoots,
      statuses = {
        for (final node in controller.tree.nodes)
          node.id: controller.loadStatusOf(node.id),
      },
      errors = {
        for (final node in controller.tree.nodes)
          node.id: controller.loadErrorOf(node.id),
      };

  final DirectoryTree<int> tree;
  final TreeRows<int> rows;
  final TreeRowsChange change;
  final ExpansionState expansion;
  final SelectionState selection;
  final SelectionState checks;
  final NodeId? focusedId;
  final String query;
  final bool caseSensitiveQuery;
  final TreeFilter? filter;
  final bool revealMatches;
  final bool compactFolders;
  final bool showRoots;
  final Map<NodeId, DirectoryLoadStatus> statuses;
  final Map<NodeId, Object?> errors;

  bool sameAs(_Snapshot other) =>
      identical(tree, other.tree) &&
      identical(rows, other.rows) &&
      expansion == other.expansion &&
      selection == other.selection &&
      checks == other.checks &&
      focusedId == other.focusedId &&
      query == other.query &&
      caseSensitiveQuery == other.caseSensitiveQuery &&
      identical(filter, other.filter) &&
      revealMatches == other.revealMatches &&
      compactFolders == other.compactFolders &&
      showRoots == other.showRoots &&
      mapEquals(statuses, other.statuses) &&
      mapEquals(errors, other.errors);
}

/// One random command sequence over one controller.
final class _Run {
  _Run(this.seed) : random = Random(seed) {
    policy = random.nextInt(4) == 0
        ? PathPolicy.caseInsensitive
        : const PathPolicy();
    final tree = _randomTree(random, policy);
    loader = random.nextBool() ? FakeLoader<int>() : null;
    if (random.nextInt(3) == 0) {
      // Selectability must not depend on spelling, which a rebuild under a
      // case-insensitive policy may change.
      selectable = (node) => !node.id.value.contains('/b');
    }
    controller = DirectoryTreeController<int>(
      tree: tree,
      expansion: _randomExpansion(random, tree),
      query: random.nextInt(4) == 0
          ? _queries[random.nextInt(_queries.length)]
          : '',
      filter: random.nextInt(6) == 0
          ? _filters[random.nextInt(_filters.length)]
          : null,
      revealMatches: random.nextInt(4) != 0,
      compactFolders: random.nextBool(),
      showRoots: random.nextInt(4) != 0,
      selectable: selectable,
      loadChildren: loader?.call,
    );
    model = controller.expansion;
    counter = NotificationCounter(controller);
    controller.addListener(() => seenChange = controller.lastRowsChange);
  }

  /// The [DirectoryTreeController.lastRowsChange] the latest notification
  /// showed, while its `previous` was still set.
  TreeRowsChange? seenChange;

  /// Directories that were open below a reloaded directory, with whether
  /// the requested state expanded them: they open again when a load brings
  /// them back.
  final Map<NodeId, bool> reopen = {};

  void modelReload(_Snapshot before, NodeId id) {
    final node = before.tree[id];
    if (loader == null ||
        node is! DirectoryNode<int> ||
        before.statuses[id] == DirectoryLoadStatus.loading ||
        (!node.hasChildren && node.isExplicit)) {
      return;
    }
    final start = before.tree.indexOf(id);
    final end = start + before.tree.subtreeSizeOf(id);
    for (var i = start + 1; i < end; i++) {
      final below = before.tree.nodes[i];
      if (below is! DirectoryNode<int>) continue;
      final requested = model.isExpanded(below.id);
      if (requested || before.rows.expansion.isExpanded(below.id)) {
        reopen[below.id] = requested;
      }
    }
  }

  void modelReopen(_Snapshot before, NodeId id) {
    final tree = controller.tree;
    if (identical(tree, before.tree) || !tree.contains(id)) return;
    final start = tree.indexOf(id);
    final end = start + tree.subtreeSizeOf(id);
    for (var i = start + 1; i < end; i++) {
      final below = tree.nodes[i].id;
      if (reopen.remove(below) ?? false) {
        model = model.expand(below);
        _cover('reopened');
      }
    }
  }

  final int seed;
  final Random random;
  late final PathPolicy policy;
  late final FakeLoader<int>? loader;
  bool Function(TreeNode<int> node)? selectable;
  late final DirectoryTreeController<int> controller;
  late final NotificationCounter counter;
  final FakeViewport viewport = FakeViewport(pageRowCount: 4);
  bool viewportAttached = false;
  bool selectionSetterUsed = false;
  int nextData = 1000;

  /// The requested expansion as the contract defines it, maintained
  /// independently of the controller.
  late ExpansionState model;

  final List<String> log = [];

  String get reason => 'seed $seed: ${log.join(' | ')}';

  NodeId pickId() {
    final tree = controller.tree;
    final rows = controller.rows;
    final roll = random.nextInt(20);
    if (roll == 0 || tree.isEmpty) return unknown;
    if (roll < 3) return tree.roots[random.nextInt(tree.roots.length)];
    if (roll < 6) {
      final chained = [
        for (final row in rows)
          if (row.chain.length > 1) row,
      ];
      if (chained.isNotEmpty) {
        final row = chained[random.nextInt(chained.length)];
        return row.chain[random.nextInt(row.chain.length)].id;
      }
    }
    if (roll < 14 && rows.isNotEmpty) {
      return rows[random.nextInt(rows.length)].id;
    }
    return tree.nodes[random.nextInt(tree.length)].id;
  }

  /// Updates [model] for an expand or collapse of [id] as the contract
  /// says: the row's directory for an id with a row; otherwise, with compact
  /// folders, the deepest directory of the chain [id] belongs to (whose
  /// state the chain's row reads), else the id itself.
  /// Whether [id] shows as expanded, which a toggle flips: its row's state,
  /// else the effective state of its chain's deepest directory (hidden
  /// roots count as expanded).
  bool shownExpanded(_Snapshot before, NodeId id) {
    final row = before.rows.rowOf(id);
    if (row != null) return row.isExpanded;
    final node = before.tree[id];
    if (node is! DirectoryNode<int>) return false;
    if (!before.showRoots && node.isRoot) return true;
    return before.rows.expansion.isExpanded(chainEndOf(before, node));
  }

  void modelToggle(_Snapshot before, NodeId id, {required bool expand}) {
    final node = before.tree[id];
    if (node is! DirectoryNode<int>) return;
    if (!before.showRoots && node.isRoot) return;
    final index = before.rows.indexOfNode(id);
    var target = id;
    if (index >= 0) {
      target = before.rows[index].id;
    } else if (before.compactFolders) {
      var current = node;
      while (current.children.length == 1) {
        final child = before.tree[current.children.first];
        if (child is! DirectoryNode<int>) break;
        current = child;
      }
      target = current.id;
    }
    model = model.setExpanded(target, expanded: expand);
  }

  /// The deepest directory of the compacted chain [directory] belongs to
  /// in [before], walking down from it; itself without compact folders and
  /// for hidden roots.
  NodeId chainEndOf(_Snapshot before, DirectoryNode<int> directory) {
    if (!before.compactFolders || (!before.showRoots && directory.isRoot)) {
      return directory.id;
    }
    var current = directory;
    while (current.children.length == 1) {
      final child = before.tree[current.children.first];
      if (child is! DirectoryNode<int>) break;
      current = child;
    }
    return current.id;
  }

  /// The ancestors of [id] whose own state decides whether it shows: not
  /// hidden roots, not directories that continue a compacted chain.
  List<NodeId> decidingAncestors(_Snapshot before, NodeId id) => [
    for (final ancestor in before.tree.ancestorsOf(id))
      if (!(ancestor.isRoot && !before.showRoots) &&
          !(before.compactFolders &&
              ancestor is DirectoryNode<int> &&
              ancestor.children.length == 1 &&
              before.tree[ancestor.children.first] is DirectoryNode<int>))
        ancestor.id,
  ];

  /// A reveal expands the deciding ancestors in the requested state, unless
  /// no expansion can show the node (the core's reveal changes nothing).
  void modelReveal(_Snapshot before, NodeId id) {
    if (!before.tree.contains(id) || before.rows.indexOfNode(id) >= 0) return;
    if (identical(before.rows.reveal(id), before.rows)) return;
    model = model.expandAll(decidingAncestors(before, id));
  }

  /// Turning compaction off expands the members of the visible compacted
  /// rows: in the requested state all of them without a filter, else only
  /// those of rows whose deepest directory it expands.
  void modelCompactionOff(_Snapshot before, {required bool wasFiltering}) {
    for (final row in before.rows) {
      final members = [
        for (final node in row.chain)
          if (node.id != row.id) node.id,
      ];
      if (members.isEmpty) continue;
      if (!wasFiltering || model.isExpanded(row.id)) {
        model = model.expandAll(members);
      }
    }
  }

  /// A load that leaves an expanded directory with one child directory
  /// expands the deepest directory of the new chain.
  void modelLoadedChain(_Snapshot before, NodeId id) {
    final tree = controller.tree;
    if (identical(tree, before.tree) || !before.compactFolders) return;
    final directory = tree[id];
    if (directory is! DirectoryNode<int>) return;
    if (!before.showRoots && directory.isRoot) return;
    if (!model.isExpanded(id)) return;
    var current = directory;
    while (current.children.length == 1) {
      final child = tree[current.children.first];
      if (child is! DirectoryNode<int>) break;
      current = child;
    }
    if (!identical(current, directory)) {
      model = model.expand(current.id);
      _cover('loaded chain');
    }
  }

  /// After a filter input changed: clearing the filter reveals the focused
  /// node in the requested state when it would be hidden.
  void modelFilterChange(_Snapshot before, {required bool wasFiltering}) {
    final focused = before.focusedId;
    if (!wasFiltering || controller.isFiltering || focused == null) return;
    final plain = before.tree.flatten(
      expansion: model,
      expandMatches: false,
      compactFolders: before.compactFolders,
      showRoots: before.showRoots,
    );
    if (plain.indexOfNode(focused) < 0) {
      model = plain.reveal(focused).expansion;
    }
  }

  void modelTreeChange(_Snapshot before) {
    if (!identical(controller.tree, before.tree)) {
      model = model.prune(controller.tree);
    }
  }

  /// A new tree from the setter: the requested state is pruned and the
  /// reopening ends.
  void modelNewTree(_Snapshot before) {
    modelTreeChange(before);
    if (!identical(controller.tree, before.tree)) reopen.clear();
  }

  /// The children of directories at the moment they were reloaded, so a
  /// load can bring them back (and reopen the open ones).
  final Map<NodeId, List<TreeEntry<int>>> reloaded = {};

  List<TreeEntry<int>> entriesFor(DirectoryNode<Object?> directory) {
    final previous = reloaded.remove(directory.id);
    if (previous != null && random.nextBool()) return previous;
    final base = directory.path.toString();
    final separator = base.endsWith('/') ? '' : '/';
    if (random.nextInt(6) == 0) {
      // A single child directory: with compact folders the loaded
      // directory then continues a chain.
      return [
        TreeEntry<int>.directory(
          '$base$separator${_names[random.nextInt(_names.length)]}',
          data: nextData++,
        ),
      ];
    }
    final count = random.nextInt(4);
    return [
      for (var i = 0; i < count; i++)
        switch (random.nextInt(6)) {
          0 => TreeEntry<int>.file('/elsewhere/${_names[i]}', data: nextData++),
          1 => TreeEntry<int>.directory(
            '$base$separator${_names[random.nextInt(_names.length)]}',
            data: nextData++,
          ),
          2 => TreeEntry<int>.file(
            '${policy.caseSensitive ? base : base.toUpperCase()}'
            '$separator${_names[random.nextInt(_names.length)]}.new',
            data: nextData++,
          ),
          3 => TreeEntry<int>.file(
            '$base${separator}deep/${_names[random.nextInt(_names.length)]}',
            data: nextData++,
          ),
          _ => TreeEntry<int>.file(
            '$base$separator${_names[random.nextInt(_names.length)]}.txt',
            data: nextData++,
          ),
        },
    ];
  }

  Future<void> step() async {
    final before = _Snapshot(controller);
    final wasFiltering = controller.isFiltering;
    counter.take();
    seenChange = null;
    var filterCommand = false;
    final command = random.nextInt(40);
    switch (command) {
      case 0:
        final id = pickId();
        log.add('expand($id)');
        modelToggle(before, id, expand: true);
        controller.expand(id);
      case 1:
        final id = pickId();
        log.add('collapse($id)');
        modelToggle(before, id, expand: false);
        controller.collapse(id);
      case 2:
        final id = pickId();
        log.add('toggleExpansion($id)');
        modelToggle(before, id, expand: !shownExpanded(before, id));
        controller.toggleExpansion(id);
      case 3:
        log.add('expandAll');
        model = const ExpansionState.expanded();
        controller.expandAll();
      case 4:
        log.add('collapseAll');
        model = const ExpansionState.collapsed();
        controller.collapseAll();
      case 5:
        final id = pickId();
        log.add('expandSubtree($id)');
        model = model.expandSubtree(before.tree, id);
        controller.expandSubtree(id);
      case 6:
        final id = pickId();
        log.add('collapseSubtree($id)');
        model = model.collapseSubtree(before.tree, id);
        controller.collapseSubtree(id);
      case 7:
        final value = random.nextInt(4) == 0
            ? controller.expansion
            : _randomExpansion(random, controller.tree);
        log.add('expansion = $value');
        if (value != model) model = value;
        controller.expansion = value;
      case 8:
        // Half of the edits clear the query, so unfiltered states stay
        // common.
        final value = random.nextBool()
            ? ''
            : _queries[random.nextInt(_queries.length)];
        log.add("query = '$value'");
        filterCommand = true;
        controller.query = value;
        modelFilterChange(before, wasFiltering: wasFiltering);
      case 9:
        log.add('caseSensitiveQuery = ${!controller.caseSensitiveQuery}');
        filterCommand = true;
        controller.caseSensitiveQuery = !controller.caseSensitiveQuery;
        modelFilterChange(before, wasFiltering: wasFiltering);
      case 10:
        final value = random.nextBool()
            ? null
            : _filters[random.nextInt(_filters.length)];
        log.add('filter = $value');
        filterCommand = true;
        controller.filter = value;
        modelFilterChange(before, wasFiltering: wasFiltering);
      case 11:
        log.add('revealMatches = ${!controller.revealMatches}');
        filterCommand = true;
        controller.revealMatches = !controller.revealMatches;
      case 12:
        log.add('compactFolders = ${!controller.compactFolders}');
        if (controller.compactFolders) {
          modelCompactionOff(before, wasFiltering: wasFiltering);
          _cover('compaction off');
        }
        controller.compactFolders = !controller.compactFolders;
      case 13:
        log.add('showRoots = ${!controller.showRoots}');
        if (!controller.showRoots) {
          // Hidden roots counted as expanded, so showing them keeps them so.
          model = model.expandAll([
            for (final root in before.tree.rootNodes)
              if (root is DirectoryNode<int>) root.id,
          ]);
        }
        controller.showRoots = !controller.showRoots;
      case 14:
        final tree = controller.tree;
        final next = tree.rebuild((builder) {
          for (var i = random.nextInt(3); i > 0 && tree.isNotEmpty; i--) {
            builder.remove(
              tree.nodes[random.nextInt(tree.length)].path.toString(),
            );
          }
          for (var i = random.nextInt(4); i > 0; i--) {
            builder.add(_randomEntry(random, nextData++));
          }
        });
        log.add('tree = edited (${next.length} nodes)');
        controller.tree = next;
        modelNewTree(before);
      case 15:
        final roll = random.nextInt(3);
        final current = controller.tree;
        final next = roll == 0
            ? current
            : roll == 1
            ? current.rebuild((builder) {})
            : _randomTree(random, policy);
        log.add('tree = ${['same', 'equal', 'new'][roll]}');
        controller.tree = next;
        modelNewTree(before);
      case 16:
        final id = pickId();
        final focus = random.nextBool();
        final select = random.nextBool();
        log.add('reveal($id, focus: $focus, select: $select)');
        modelReveal(before, id);
        controller.reveal(
          id,
          focus: focus,
          select: select,
          scroll: random.nextBool(),
          alignment: random.nextBool() ? null : random.nextDouble(),
        );
      case 17:
        final path = random.nextInt(4) == 0
            ? _randomPath(random)
            : controller.tree.isEmpty
            ? ''
            : controller.tree.nodes[random.nextInt(controller.tree.length)].path
                  .toString();
        log.add("revealPath('$path')");
        final id = before.tree.idOf(path);
        if (id != null) modelReveal(before, id);
        controller.revealPath(path, select: random.nextBool());
      case 18:
        final id = pickId();
        log.add('select($id)');
        controller.select(id, focus: random.nextBool());
      case 19:
        final id = pickId();
        log.add('toggleSelected($id)');
        controller.toggleSelected(id, focus: random.nextBool());
      case 20:
        final id = pickId();
        log.add('extendSelection($id)');
        controller.extendSelection(id, focus: random.nextBool());
      case 21:
        log.add('selectAll');
        controller.selectAll();
      case 22:
        log.add('clearSelection');
        controller.clearSelection();
      case 23:
        final mode = SelectionMode.values[random.nextInt(2)];
        log.add('selectionMode = $mode');
        controller.selectionMode = mode;
      case 24:
        final ids = [pickId(), if (random.nextBool()) pickId()];
        final mode = ids.toSet().length > 1
            ? SelectionMode.multiple
            : SelectionMode.values[random.nextInt(2)];
        log.add('selection = $ids');
        selectionSetterUsed = true;
        controller.selection = SelectionState(
          mode: mode,
          selected: ids,
          anchor: random.nextBool() ? ids.first : null,
        );
      case 25:
        final id = pickId();
        log.add('toggleChecked($id)');
        controller.toggleChecked(id);
      case 26:
        final id = pickId();
        final checked = random.nextBool();
        log.add('setChecked($id, $checked)');
        controller.setChecked(id, checked: checked);
      case 27:
        if (random.nextBool()) {
          log.add('checkAll');
          controller.checkAll();
        } else {
          log.add('uncheckAll');
          controller.uncheckAll();
        }
      case 28:
        final ids = [pickId(), if (random.nextBool()) pickId()];
        final mode = ids.toSet().length > 1 || random.nextInt(4) != 0
            ? SelectionMode.multiple
            : SelectionMode.single;
        log.add('checks = $ids ($mode)');
        controller.checks = SelectionState(mode: mode, selected: ids);
      case 29:
        final id = random.nextInt(5) == 0 ? null : pickId();
        log.add('focus($id)');
        controller.focus(id, scroll: random.nextBool());
      case 30:
        final move = TreeFocusMove.values[random.nextInt(8)];
        final update = TreeSelectionUpdate.values[random.nextInt(3)];
        log.add('moveFocus($move, $update)');
        controller.moveFocus(
          move,
          selection: update,
          pageSize: random.nextBool() ? null : random.nextInt(5),
        );
      case 31:
        final id = pickId();
        log.add('loadChildren($id)');
        unawaited(controller.loadChildren(id));
      case 32:
        final id = pickId();
        log.add('reloadChildren($id)');
        final node = before.tree[id];
        if (node is DirectoryNode<int> && node.hasChildren) {
          reloaded[id] = [
            for (final child in node.children)
              if (before.tree[child] case final childNode?)
                childNode is DirectoryNode<int>
                    ? TreeEntry<int>.directory(
                        childNode.path.toString(),
                        data: nextData++,
                      )
                    : TreeEntry<int>.file(
                        childNode.path.toString(),
                        data: nextData++,
                      ),
          ];
        }
        modelReload(before, id);
        unawaited(controller.reloadChildren(id));
        modelTreeChange(before);
      case 33:
        final pending = loader?.pending ?? const [];
        if (pending.isEmpty) {
          log.add('complete (none pending)');
          break;
        }
        final call = pending[random.nextInt(pending.length)];
        final entries = entriesFor(call.directory);
        log.add('complete(${call.directory.id}, ${entries.length} entries)');
        call.completer.complete(entries);
        await _flush();
        modelTreeChange(before);
        modelReopen(before, call.directory.id);
        modelLoadedChain(before, call.directory.id);
      case 34:
        final pending = loader?.pending ?? const [];
        if (pending.isEmpty) {
          log.add('fail (none pending)');
          break;
        }
        final call = pending[random.nextInt(pending.length)];
        log.add('fail(${call.directory.id})');
        call.completer.completeError('boom $seed');
        await _flush();
      case 35:
        if (viewportAttached) {
          log.add('detachViewport');
          controller.detachViewport(viewport);
        } else {
          log.add('attachViewport');
          controller.attachViewport(viewport);
        }
        viewportAttached = !viewportAttached;
      default:
        // Extra toggles of visible rows, the incremental path.
        final rows = controller.rows;
        final id = rows.isEmpty
            ? unknown
            : rows[random.nextInt(rows.length)].id;
        log.add('toggleExpansion(row $id)');
        modelToggle(before, id, expand: !shownExpanded(before, id));
        controller.toggleExpansion(id);
    }
    await _flush();
    final after = _Snapshot(controller);
    expectInvariants(before, after, filterCommand: filterCommand);
  }

  void expectInvariants(
    _Snapshot before,
    _Snapshot after, {
    required bool filterCommand,
  }) {
    final notifications = counter.take();
    final changed = !before.sameAs(after);
    if (changed) _cover('changed');
    if (!changed) _cover('unchanged');
    if (controller.isFiltering) _cover('filtering');
    if (!controller.showRoots) _cover('hidden roots');
    if (controller.rows.any((row) => row.chain.length > 1)) {
      _cover('compacted row');
    }
    if (controller.focusedId != null) _cover('focused');
    if (controller.selection.length > 1) _cover('multi selection');
    if (!identical(after.tree, before.tree)) _cover('tree changed');
    if (policy == PathPolicy.caseInsensitive) _cover('case-insensitive');
    if (!identical(after.rows, before.rows)) {
      final change = controller.lastRowsChange;
      if (change.isReset) {
        _cover('reset');
      } else if (identical(after.rows.tree, before.rows.tree)) {
        _cover(
          change.inserted > 0
              ? 'toggle splice (insert)'
              : change.removed > 0
              ? 'toggle splice (remove)'
              : 'toggle splice (in place)',
        );
      } else {
        _cover('load splice');
      }
    }
    for (final status in after.statuses.values) {
      if (status == DirectoryLoadStatus.loading) _cover('loading');
      if (status == DirectoryLoadStatus.failed) _cover('failed');
    }
    if (controller.checkedRoots.isNotEmpty) _cover('checked');
    expect(notifications, changed ? 1 : 0, reason: '$reason (notifications)');

    expectConsistentRows(controller, reason: reason);
    final tree = controller.tree;
    final rows = controller.rows;

    // The requested state follows the contract's transforms.
    expect(controller.expansion, model, reason: '$reason (requested state)');
    if (!controller.isFiltering) {
      expect(
        rows.expansion,
        controller.expansion,
        reason: '$reason (equal states)',
      );
    } else if (filterCommand && !identical(rows, before.rows)) {
      // A filter change recomputes the effective state from the requested
      // one.
      final fresh = tree.flatten(
        expansion: model,
        filter: effectiveFilterOf(controller),
        expandMatches: controller.revealMatches,
        compactFolders: controller.compactFolders,
        showRoots: controller.showRoots,
      );
      expect(rows.expansion, fresh.expansion, reason: '$reason (refilter)');
      // A focused node that lost its row moves to the first match.
      final previous = before.focusedId;
      if (previous != null && rows.indexOfNode(previous) < 0) {
        final first = rows.indexWhere((row) => row.isMatch);
        expect(
          controller.focusedId,
          first < 0 ? null : rows[first].id,
          reason: '$reason (focus after a filter change)',
        );
      }
    }

    // Focus is a row id or null.
    final focused = controller.focusedId;
    if (focused != null) {
      final index = rows.indexOfNode(focused);
      expect(index, greaterThanOrEqualTo(0), reason: '$reason (focus row)');
      expect(rows[index].id, focused, reason: '$reason (focus row id)');
      expect(controller.focusedIndex, index, reason: reason);
      expect(controller.focusedRow, same(rows[index]), reason: reason);
    } else {
      expect(controller.focusedIndex, -1, reason: reason);
    }

    // Selection and checks only name nodes of the tree.
    for (final state in [controller.selection, controller.checks]) {
      for (final id in state.selected) {
        expect(tree.contains(id), isTrue, reason: '$reason (pruned $id)');
      }
      final anchor = state.anchor;
      if (anchor != null) {
        expect(tree.contains(anchor), isTrue, reason: '$reason (anchor)');
      }
    }
    final predicate = selectable;
    if (predicate != null && !selectionSetterUsed) {
      for (final id in controller.selection.selected) {
        expect(predicate(tree[id]!), isTrue, reason: '$reason (selectable)');
      }
    }
    // With compact folders a selected directory is the id of its row: never
    // one that continues a chain, unless its chain's deepest directory is
    // not selectable.
    if (controller.compactFolders) {
      final selection = controller.selection;
      for (final id in [...selection.selected, ?selection.anchor]) {
        final node = tree[id];
        if (node is! DirectoryNode<int>) continue;
        if (!controller.showRoots && node.isRoot) continue;
        var end = node;
        while (end.children.length == 1) {
          final child = tree[end.children.first];
          if (child is! DirectoryNode<int>) break;
          end = child;
        }
        if (identical(end, node)) continue;
        expect(
          controller.isSelectable(end.id),
          isFalse,
          reason: '$reason (chain member $id selected)',
        );
      }
    }

    // lastRowsChange describes the actual difference.
    if (identical(rows, before.rows)) {
      expect(
        identical(controller.lastRowsChange, before.change),
        isTrue,
        reason: '$reason (change kept)',
      );
    } else {
      final change = seenChange!;
      expect(
        identical(change.previous, before.rows),
        isTrue,
        reason: '$reason (change.previous)',
      );
      // Once listeners ran, a replaced tree is released; the rest stays.
      final kept = controller.lastRowsChange;
      expect(
        kept.previous,
        identical(rows.tree, before.rows.tree) ? same(before.rows) : isNull,
        reason: '$reason (previous after the listeners)',
      );
      expect(
        (kept.isReset, kept.index, kept.removed, kept.inserted),
        (change.isReset, change.index, change.removed, change.inserted),
        reason: '$reason (change kept after the listeners)',
      );
      if (!change.isReset) {
        final oldIds = idsOf(before.rows);
        final newIds = idsOf(rows);
        expect(
          change.index + change.removed,
          lessThanOrEqualTo(oldIds.length),
          reason: '$reason (splice range)',
        );
        expect(
          oldIds.length - change.removed + change.inserted,
          newIds.length,
          reason: '$reason (splice length)',
        );
        final spliced = [
          ...oldIds.sublist(0, change.index),
          ...newIds.sublist(change.index, change.index + change.inserted),
          ...oldIds.sublist(change.index + change.removed),
        ];
        expect(newIds, spliced, reason: '$reason (splice ids)');
        if (identical(rows.tree, before.rows.tree)) {
          // An incremental toggle: only the toggled row (right before the
          // block) and the block itself are new objects.
          for (var i = 0; i < change.index - 1; i++) {
            expect(
              rows[i],
              same(before.rows[i]),
              reason: '$reason (prefix $i)',
            );
          }
          final suffix = oldIds.length - change.index - change.removed;
          for (var i = 1; i <= suffix; i++) {
            expect(
              rows[rows.length - i],
              same(before.rows[before.rows.length - i]),
              reason: '$reason (suffix $i)',
            );
          }
        }
      }
    }

    // Check states match the core, through incremental count updates.
    for (final node in tree.nodes) {
      expect(
        controller.checkStateOf(node.id),
        controller.checks.checkStateOf(tree, node.id),
        reason: '$reason (check state of ${node.id})',
      );
    }
    final leaves = [
      for (final node in tree.nodes)
        if (controller.checks.isSelected(node.id) &&
            (node is FileNode<int> ||
                !(node as DirectoryNode<int>).hasChildren))
          node.id,
    ];
    expect(
      controller.checkedLeaves.map((node) => node.id),
      leaves,
      reason: '$reason (checkedLeaves)',
    );
    final roots = <NodeId>[];
    for (var i = 0; i < tree.length;) {
      final node = tree.nodes[i];
      if (controller.checks.checkStateOf(tree, node.id) == CheckState.checked) {
        roots.add(node.id);
        i += tree.subtreeSizeOf(node.id);
      } else {
        i++;
      }
    }
    expect(
      controller.checkedRoots.map((node) => node.id),
      roots,
      reason: '$reason (checkedRoots)',
    );
    expect(controller.selectedNodes.map((node) => node.id), [
      for (final node in tree.nodes)
        if (controller.selection.isSelected(node.id)) node.id,
    ], reason: '$reason (selectedNodes)');

    // Expand arrows and load statuses.
    final hasLoader = loader != null;
    for (final row in rows) {
      final node = row.node;
      final lazy =
          hasLoader &&
          !controller.isFiltering &&
          node is DirectoryNode<int> &&
          !node.hasChildren &&
          controller.loadStatusOf(node.id) != DirectoryLoadStatus.loaded;
      expect(
        controller.isExpandable(row.id),
        row.hasChildren || lazy,
        reason: '$reason (isExpandable ${row.id})',
      );
    }
    for (final node in tree.nodes) {
      final status = controller.loadStatusOf(node.id);
      if (status == DirectoryLoadStatus.loading) {
        expect(
          loader!.callsFor(node.id).any((call) => call.isPending),
          isTrue,
          reason: '$reason (loading ${node.id} has a pending call)',
        );
      }
      expect(
        controller.loadErrorOf(node.id) != null,
        status == DirectoryLoadStatus.failed,
        reason: '$reason (error of ${node.id})',
      );
    }
  }

  Future<void> finish() async {
    controller.dispose();
    for (final call in loader?.pending ?? const <LoaderCall<int>>[]) {
      call.completer.complete(const []);
    }
    await _flush();
  }
}

void main() {
  test('random command sequences keep every invariant', () async {
    const runs = 320;
    const steps = 40;
    var commands = 0;
    for (var seed = 0; seed < runs; seed++) {
      final run = _Run(seed);
      // Let loads started at construction reach the loader.
      await _flush();
      // The initial state already satisfies the invariants.
      run.expectInvariants(
        _Snapshot(run.controller),
        _Snapshot(run.controller),
        filterCommand: false,
      );
      for (var step = 0; step < steps; step++) {
        await run.step();
        commands++;
      }
      await run.finish();
    }
    expect(commands, runs * steps);
    for (final situation in [
      'changed',
      'unchanged',
      'filtering',
      'hidden roots',
      'compacted row',
      'focused',
      'multi selection',
      'tree changed',
      'case-insensitive',
      'reset',
      'toggle splice (insert)',
      'toggle splice (remove)',
      'toggle splice (in place)',
      'load splice',
      'loading',
      'failed',
      'checked',
      'compaction off',
    ]) {
      expect(
        _coverage[situation] ?? 0,
        greaterThan(20),
        reason: 'the runs should reach "$situation"; coverage: $_coverage',
      );
    }
  });
}
