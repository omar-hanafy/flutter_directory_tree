/// The flutter_directory_tree 2.0.0 benchmark subject.
library;

import 'package:fdt_bench_harness/harness.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// Creates the v2 subject.
BenchSubject createV2Subject(Workload workload) => V2Subject(workload);

/// The row extent of the measured view: 1.0.0's row height, so both
/// versions show the same rows in the benchmark viewport.
const double benchRowExtent = 28;

/// Measures the flutter_directory_tree 2.0.0 code in this repository through
/// its public API, the way an application calls it.
///
/// | operation | 2.0.0 calls |
/// |---|---|
/// | `build` | `DirectoryTree<Never>.build(entries)`, then `DirectoryTreeController<Never>(tree:, expansion: ExpansionState.withExpanded([rootId]))`: only the top folder expanded, nothing selected. |
/// | `expand_all` | `controller.expandAll()`, from `collapseAll()` and `expand(rootId)`. |
/// | `toggle` | `controller.toggleExpansion(targetId)` on the fully expanded tree: an incremental collapse that removes the target's block of rows. |
/// | `filter` | `controller.query = 'legacy'`. |
/// | `select_range` | `controller.extendSelection(targetId, focus: false)` after `select(anchorId, focus: false)`. |
/// | views | `DirectoryTreeView<Never>` (keyboard, scrollbar, and rows of the default `DirectoryTreeRow`) under a `DirectoryTreeTheme` pinned to [benchRowExtent]. |
///
/// `focus: false` matches 1.0.0, whose controller has no keyboard focus.
class V2Subject extends BenchSubject {
  /// Creates a subject for [workload].
  V2Subject(this.workload);

  /// The workload under test.
  final Workload workload;

  /// One file entry per path, created untimed. The nodes carry no data.
  late final List<TreeEntry<Never>> entries = [
    for (final path in workload.paths) TreeEntry<Never>.file(path),
  ];

  DirectoryTreeController<Never>? _built;
  DirectoryTreeController<Never>? _shared;

  /// The controller every operation after `build` works on: the last one
  /// `build` created, or a new one.
  DirectoryTreeController<Never> get controller =>
      _shared ??= _createController(entries);

  late final NodeId _rootId = _directoryId(workloadRoot);
  late final NodeId _toggleId = _directoryId(workload.toggleTarget);

  int _fullRows = 0;
  NodeId _anchorId = const NodeId('');
  NodeId _targetId = const NodeId('');

  /// The id of the directory at [path] in the shared controller's tree.
  NodeId _directoryId(String path) {
    final tree = controller.tree;
    final id = tree.idOf(path);
    if (id == null || tree[id] is! DirectoryNode<Never>) {
      throw StateError('$path is not a directory of the v2 tree');
    }
    return id;
  }

  /// The starting state of every operation after `expand_all`: every folder
  /// expanded, no search query, nothing selected.
  void _resetToFullTree() {
    controller
      ..query = ''
      ..expandAll()
      ..clearSelection();
  }

  @override
  void setUp(String operation) {
    switch (operation) {
      case 'build':
        entries;
      case 'expand_all':
        controller
          ..query = ''
          ..clearSelection();
        _rootId;
      case 'toggle':
        _resetToFullTree();
        _toggleId;
        _fullRows = controller.rows.length;
      case 'select_range':
        _resetToFullTree();
        final rows = controller.rows;
        _anchorId = rows[rows.length ~/ 4].id;
        _targetId = rows[rows.length * 3 ~/ 4].id;
      case 'filter' || 'first_frame' || 'jump_middle' || 'jump_end':
        _resetToFullTree();
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }

  @override
  void beforeRun(String operation) {
    switch (operation) {
      case 'build':
        _built?.dispose();
        _built = null;
      case 'expand_all':
        // What "Collapse all" and a click on the top folder leave.
        controller
          ..collapseAll()
          ..expand(_rootId);
      case 'toggle':
        if (!controller.isExpanded(_toggleId)) controller.expand(_toggleId);
      case 'filter':
        controller.query = '';
      case 'select_range':
        controller.select(_anchorId, focus: false);
    }
  }

  @override
  void run(String operation) {
    switch (operation) {
      case 'build':
        _built = _createController(entries);
      case 'expand_all':
        controller.expandAll();
      case 'toggle':
        controller.toggleExpansion(_toggleId);
      case 'filter':
        controller.query = workload.filterQuery;
      case 'select_range':
        controller.extendSelection(_targetId, focus: false);
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }

  @override
  Map<String, Object> counts(String operation) {
    switch (operation) {
      case 'build':
        final built = _built!;
        return {'rows': built.rows.length, 'nodes': built.tree.length};
      case 'toggle':
        final rows = controller.rows.length;
        return {'rows': rows, 'hidden_rows': _fullRows - rows};
      case 'select_range':
        return {'selected': controller.selection.length};
      default:
        return {'rows': controller.rows.length};
    }
  }

  @override
  void tearDown(String operation) {
    if (operation != 'build') return;
    final built = _built;
    _built = null;
    if (built == null) return;
    if (_shared == null) {
      _shared = built;
    } else {
      built.dispose();
    }
  }

  /// The 2.0.0 tree view an application would use, with every row counted
  /// by a [RowBuildProbe].
  ///
  /// The probe wraps the default row inside the row builder. 2.0.0 caches
  /// row widgets per id, so a remounted row may not call the builder again,
  /// but its probe still builds.
  @override
  Widget buildView({
    required ScrollController scrollController,
    required RowBuiltCallback onRowBuilt,
  }) => DirectoryTreeTheme(
    data: const DirectoryTreeThemeData(rowExtent: benchRowExtent),
    child: DirectoryTreeView<Never>(
      controller: controller,
      scrollController: scrollController,
      rowBuilder: (context, details) => RowBuildProbe(
        index: details.index,
        onBuilt: onRowBuilt,
        child: DirectoryTreeRow<Never>(details: details),
      ),
    ),
  );

  @override
  int get viewRowCount => controller.rows.length;

  @override
  void dispose() {
    _built?.dispose();
    _shared?.dispose();
    _built = null;
    _shared = null;
  }
}

/// A controller over a tree built from [entries], starting as 1.0.0's does
/// in the suite: only the top folder [workloadRoot] expanded, nothing
/// selected.
DirectoryTreeController<Never> _createController(
  List<TreeEntry<Never>> entries,
) {
  final tree = DirectoryTree<Never>.build(entries);
  return DirectoryTreeController<Never>(
    tree: tree,
    expansion: ExpansionState.withExpanded([tree.idOf(workloadRoot)!]),
  );
}
