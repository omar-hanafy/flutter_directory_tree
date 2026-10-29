import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';
import 'package:flutter_directory_tree_example/data/tree_edits.dart';
import 'package:flutter_directory_tree_example/widgets/name_dialog.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

/// An IDE-style explorer: a [DirectoryTreePanel] with multi-selection, a
/// context menu (new file, rename, delete), drag and drop, and a details
/// pane.
///
/// Every edit works like a real app's would: it changes the list of
/// entries, builds a new [DirectoryTree] from it, and assigns it to
/// [DirectoryTreeController.tree]. The controller keeps the expansion,
/// selection, and focus by [NodeId].
class ExplorerDemo extends StatefulWidget {
  /// Creates the explorer demo.
  const ExplorerDemo({super.key});

  @override
  State<ExplorerDemo> createState() => _ExplorerDemoState();
}

class _ExplorerDemoState extends State<ExplorerDemo> {
  late final DirectoryTreeController<int> _controller = _createController();

  /// The file the user opened last (double-click or Enter).
  NodeId? _openedId;

  late final DirectoryTreeDragAndDrop<int> _dragAndDrop =
      DirectoryTreeDragAndDrop<int>(onDrop: _move, canDrop: _canDrop);

  static DirectoryTreeController<int> _createController() {
    final tree = sampleProjectTree();
    final root = tree.roots.single;
    return DirectoryTreeController<int>(
      tree: tree,
      expansion: const ExpansionState.collapsed().expand(root),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  DirectoryTree<int> get _tree => _controller.tree;

  void _setEntries(List<TreeEntry<int>> entries) {
    _controller.tree = DirectoryTree<int>.build(
      entries,
      options: _tree.options,
    );
  }

  void _showMessage(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  /// The directory that new files go into for a click on [node].
  DirectoryNode<int>? _directoryFor(TreeNode<int>? node) => switch (node) {
    DirectoryNode<int>() => node,
    FileNode<int>(:final parent?) => _tree[parent] as DirectoryNode<int>?,
    _ => null,
  };

  Future<void> _newFile(TreeNode<int>? near) async {
    final directory =
        _directoryFor(near) ??
        _directoryFor(_tree.rootNodes.isEmpty ? null : _tree.rootNodes.first);
    if (directory == null) return;
    final name = await showNameDialog(
      context,
      title: 'New file in ${directory.name}',
      confirmLabel: 'Create',
      initialName: 'untitled.dart',
    );
    if (name == null || !mounted) return;
    final path = directory.path.child(name).toString();
    if (_tree.nodeAt(path) != null) {
      _showMessage('$name already exists in ${directory.name}');
      return;
    }
    _setEntries(TreeEdits.addFile(_tree.entries, path, data: 0));
    final id = _tree.idOf(path);
    if (id != null) _controller.reveal(id, select: true);
  }

  Future<void> _rename(TreeNode<int> node) async {
    final name = await showNameDialog(
      context,
      title: 'Rename ${node.name}',
      confirmLabel: 'Rename',
      initialName: node.name,
    );
    if (name == null || name == node.name || !mounted) return;
    final parent = node.path.parent;
    if (parent == null) return;
    final path = parent.child(name).toString();
    if (_tree.nodeAt(path) != null) {
      _showMessage('$name already exists');
      return;
    }
    final wasOpened = _openedId == node.id;
    _setEntries(TreeEdits.rename(_tree.entries, node.path.toString(), path));
    final id = _tree.idOf(path);
    if (id == null) return;
    _controller.reveal(id, select: true);
    if (wasOpened) setState(() => _openedId = id);
  }

  void _delete(List<TreeNode<int>> nodes) {
    final previous = _tree;
    _setEntries(
      TreeEdits.delete(
        _tree.entries,
        [for (final node in nodes) node.path.toString()],
        keepParents: [
          for (final node in nodes)
            if (node.parent case final parent?) _tree[parent]!.path.toString(),
        ],
      ),
    );
    final noun = nodes.length == 1
        ? nodes.single.name
        : '${nodes.length} items';
    _showMessage(
      'Deleted $noun',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => _controller.tree = previous,
      ),
    );
  }

  bool _canDrop(DirectoryTreeDropDetails<int> details) {
    final target = details.target.path;
    return details.nodes.every(
      (node) => _tree.nodeAt(target.child(node.name).toString()) == null,
    );
  }

  void _move(DirectoryTreeDropDetails<int> details) {
    final target = details.target;
    final paths = [for (final node in details.nodes) node.path];
    _setEntries(TreeEdits.move(_tree.entries, paths, target.path));
    final moved = [
      for (final path in paths)
        ?_tree.idOf(target.path.child(path.name).toString()),
    ];
    _controller
      ..expand(target.id)
      ..selection = SelectionState(
        mode: SelectionMode.multiple,
        selected: moved,
        anchor: moved.isEmpty ? null : moved.first,
      );
    if (moved.isNotEmpty) _controller.reveal(moved.first);
    final dragged = details.nodes;
    final noun = dragged.length == 1
        ? dragged.single.name
        : '${dragged.length} items';
    _showMessage('Moved $noun to ${target.name}');
  }

  List<Widget> _menu(
    BuildContext context,
    DirectoryTreeMenuDetails<int> details,
  ) {
    final nodes = details.nodes;
    return [
      MenuItemButton(
        leadingIcon: const Icon(Icons.note_add_outlined),
        onPressed: () => unawaited(_newFile(details.row.node)),
        child: const Text('New file'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.drive_file_rename_outline),
        onPressed: nodes.length == 1
            ? () => unawaited(_rename(nodes.single))
            : null,
        child: const Text('Rename'),
      ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.delete_outline),
        onPressed: () => _delete(nodes),
        child: Text(
          nodes.length == 1 ? 'Delete' : 'Delete ${nodes.length} items',
        ),
      ),
    ];
  }

  void _restore() {
    final fresh = sampleProjectTree();
    _controller
      ..tree = fresh
      ..expand(fresh.roots.single);
  }

  @override
  Widget build(BuildContext context) {
    final panel = DirectoryTreePanel<int>(
      controller: _controller,
      title: const Text('Project'),
      actions: [
        IconButton(
          tooltip: 'New file',
          icon: const Icon(Icons.note_add_outlined),
          onPressed: () => unawaited(_newFile(_controller.focusedRow?.node)),
        ),
      ],
      onActivate: (row) {
        if (row.node.isFile) setState(() => _openedId = row.id);
      },
      contextMenuBuilder: _menu,
      dragAndDrop: _dragAndDrop,
      emptyBuilder: (context) => _EmptyProject(onRestore: _restore),
    );
    final details = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _DetailsPane(
        controller: _controller,
        opened: _openedId == null ? null : _tree[_openedId!],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        return ResizableSplitter(
          axis: wide ? Axis.horizontal : Axis.vertical,
          initialPosition: SplitterPosition.fraction(wide ? 0.6 : 0.65),
          startConstraints: const SplitterPaneConstraints(minExtent: 160),
          endConstraints: const SplitterPaneConstraints(minExtent: 120),
          start: panel,
          end: details,
        );
      },
    );
  }
}

class _EmptyProject extends StatelessWidget {
  const _EmptyProject({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Nothing to show'),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRestore,
            child: const Text('Restore the sample project'),
          ),
        ],
      ),
    );
  }
}

class _DetailsPane extends StatelessWidget {
  const _DetailsPane({required this.controller, required this.opened});

  final DirectoryTreeController<int> controller;
  final TreeNode<int>? opened;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selectedNodes;
    final opened = this.opened;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Opened file', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (opened == null)
            Text(
              'Double-click a file or press Enter to open it.',
              style: theme.textTheme.bodySmall,
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(opened.name),
                subtitle: Text(
                  '${opened.path}\n${formatSize(opened.data ?? 0)}',
                ),
                isThreeLine: true,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Selection (${selected.length})',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (selected.isEmpty)
            Text(
              'Click a row; Ctrl or Cmd adds to the selection, Shift selects '
              'a range. Right-click for the menu, drag rows onto folders.',
              style: theme.textTheme.bodySmall,
            ),
          for (final node in selected)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                node.isDirectory
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: 18,
              ),
              title: Text(node.path.toString()),
            ),
        ],
      ),
    );
  }
}
