/// The flutter_directory_tree 1.0.0 benchmark subject.
library;

import 'package:fdt_bench_harness/harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// Creates the v1 subject.
BenchSubject createV1Subject(Workload workload) => V1Subject(workload);

/// Measures flutter_directory_tree 1.0.0 through its public API, the way an
/// application calls it.
///
/// | operation | 1.0.0 calls |
/// |---|---|
/// | `build` | `TreeBuilder().build(entries: ...)` (folders not expanded, files not selected), then `DirectoryTreeController(data:, selection: SelectionController(mode: SelectionMode.multi))`, whose `autoExpandVisibleRoot` expands the top folder. |
/// | `expand_all` | `controller.expand(visibleRootId, recursive: true)`. |
/// | `toggle` | `controller.toggle(targetId)` on the fully expanded tree. |
/// | `filter` | `controller.filterQuery = 'legacy'`. |
/// | `select_range` | `controller.selectRange(anchorId:, toId:)` after `selectOnly(anchorId)`. |
/// | views | `DirectoryTreeView` with a `TreeNodeTile` row (Material icon, label, tap selects). |
class V1Subject extends BenchSubject {
  /// Creates a subject for [workload].
  V1Subject(this.workload);

  /// The workload under test.
  final Workload workload;

  static const _icons = MaterialIconProvider();

  /// One non-virtual entry per path (id = path, name = basename), created
  /// untimed.
  late final List<TreeEntry> entries = [
    for (final path in workload.paths)
      TreeEntry(
        id: path,
        name: path.substring(path.lastIndexOf('/') + 1),
        fullPath: path,
      ),
  ];

  _Controllers? _built;
  _Controllers? _shared;

  /// The controller every operation after `build` works on: the last one
  /// `build` created, or a new one.
  DirectoryTreeController get controller =>
      (_shared ??= _Controllers.create(entries)).controller;

  late final String _toggleId = controller.data.nodes.values
      .firstWhere(
        (node) =>
            node.type == NodeType.folder &&
            node.sourcePath == workload.toggleTarget,
        orElse: () => throw StateError(
          'toggle target ${workload.toggleTarget} is not in the v1 tree',
        ),
      )
      .id;

  int _fullRows = 0;
  String _anchorId = '';
  String _targetId = '';

  void _expandAll() =>
      controller.expand(controller.data.visibleRootId, recursive: true);

  /// What "Collapse all" in 1.0.0's toolbar leaves: only the top folder open.
  void _collapseToTop() {
    final root = controller.data.visibleRootId;
    controller
      ..collapse(root, recursive: true)
      ..expand(root);
  }

  /// The starting state of every operation after `expand_all`.
  void _resetToFullTree() {
    controller.filterQuery = '';
    _expandAll();
    controller.clearSelection();
  }

  @override
  void setUp(String operation) {
    switch (operation) {
      case 'build':
        entries;
      case 'expand_all':
        controller
          ..filterQuery = ''
          ..clearSelection();
      case 'toggle':
        _resetToFullTree();
        _toggleId;
        _fullRows = controller.visibleNodes.length;
      case 'select_range':
        _resetToFullTree();
        final rows = controller.visibleNodes;
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
        _collapseToTop();
      case 'toggle':
        if (!controller.expansions.isExpanded(_toggleId)) {
          controller.expand(_toggleId);
        }
      case 'filter':
        controller.filterQuery = '';
      case 'select_range':
        controller.selectOnly(_anchorId);
    }
  }

  @override
  void run(String operation) {
    switch (operation) {
      case 'build':
        _built = _Controllers.create(entries);
      case 'expand_all':
        _expandAll();
      case 'toggle':
        controller.toggle(_toggleId);
      case 'filter':
        controller.filterQuery = workload.filterQuery;
      case 'select_range':
        controller.selectRange(anchorId: _anchorId, toId: _targetId);
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }

  @override
  Map<String, Object> counts(String operation) {
    switch (operation) {
      case 'build':
        final built = _built!.controller;
        return {
          'rows': built.visibleNodes.length,
          // 1.0.0 also stores its hidden root and the "tree" container.
          'nodes': built.data.nodes.length,
        };
      case 'toggle':
        final rows = controller.visibleNodes.length;
        return {'rows': rows, 'hidden_rows': _fullRows - rows};
      case 'select_range':
        return {'selected': controller.selection.selectedIds.length};
      default:
        return {'rows': controller.visibleNodes.length};
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

  @override
  Widget buildView({
    required ScrollController scrollController,
    required RowBuiltCallback onRowBuilt,
  }) {
    final controller = this.controller;
    return DirectoryTreeView(
      controller: controller,
      scrollController: scrollController,
      nodeBuilder: (context, node, state) {
        onRowBuilt(controller.indexOfNode(node.id));
        return TreeNodeTile(
          node: node,
          state: state,
          leading: _icons.leadingIcon(context, node),
          onTap: () => controller.selectOnly(node.id),
        );
      },
    );
  }

  @override
  int get viewRowCount => controller.visibleNodes.length;

  @override
  void dispose() {
    _built?.dispose();
    _shared?.dispose();
    _built = null;
    _shared = null;
  }
}

/// A controller and the selection controller it was given (which it does
/// not dispose itself).
class _Controllers {
  _Controllers(this.controller, this.selection);

  /// A controller over [entries]: the tree built with 1.0.0's builder, with
  /// default-on folder expansion and file selection turned off so the
  /// controller starts like v2's (only the top folder expanded, by the
  /// controller's `autoExpandVisibleRoot`, and nothing selected).
  factory _Controllers.create(List<TreeEntry> entries) {
    final data = TreeBuilder().build(
      entries: entries,
      expandFoldersByDefault: false,
      selectNewFilesByDefault: false,
    );
    final selection = SelectionController(mode: SelectionMode.multi);
    return _Controllers(
      DirectoryTreeController(data: data, selection: selection),
      selection,
    );
  }

  final DirectoryTreeController controller;
  final SelectionController selection;

  void dispose() {
    controller.dispose();
    selection.dispose();
  }
}
