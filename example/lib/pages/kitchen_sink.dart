// example/lib/pages/kitchen_sink.dart
import 'package:directory_tree/directory_tree.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

import '../shared/node_builders.dart';

class KitchenSinkPage extends StatefulWidget {
  const KitchenSinkPage({super.key, required this.data});
  final core.TreeData data;

  @override
  State<KitchenSinkPage> createState() => _KitchenSinkPageState();
}

class _KitchenSinkPageState extends State<KitchenSinkPage> {
  late DirectoryTreeController controller;
  late TextEditingController _filter;

  bool _useSorted = true;
  bool _allowMulti = true;

  double _rowHeight = 28;
  double _indent = 16;
  bool _rounded = true;

  @override
  void initState() {
    super.initState();
    controller = _buildController();
    _filter = TextEditingController(text: controller.filterQuery);
  }

  @override
  void dispose() {
    controller.dispose();
    _filter.dispose();
    super.dispose();
  }

  DirectoryTreeController _buildController() {
    return DirectoryTreeController(
      data: widget.data,
      selection: SelectionController(
        mode: _allowMulti ? SelectionMode.multi : SelectionMode.single,
      ),
      flattenStrategy: _useSorted
          ? SortedFlattenStrategy(const AlphaSortDelegate())
          : const DefaultFlattenStrategy(),
    );
  }

  void _rebuildController() {
    final old = controller;
    final prevFilter = old.filterQuery;
    final prevSelected = old.selection.selectedIds.toList(growable: false);
    final prevExpanded = old.expansions.expandedIds.toSet();

    final newController = DirectoryTreeController(
      data: old.data,
      expansions: ExpansionController(initiallyExpanded: prevExpanded),
      selection: SelectionController(
        mode: _allowMulti ? SelectionMode.multi : SelectionMode.single,
      ),
      flattenStrategy: _useSorted
          ? SortedFlattenStrategy(const AlphaSortDelegate())
          : const DefaultFlattenStrategy(),
    );

    newController.filterQuery = prevFilter;

    old.dispose();

    setState(() {
      controller = newController;
      _filter.text = controller.filterQuery;
    });

    if (prevSelected.isNotEmpty) {
      if (_allowMulti) {
        controller.selectOnly(prevSelected.first);
        for (final id in prevSelected.skip(1)) {
          controller.toggleSelection(id);
        }
      } else {
        controller.selectOnly(prevSelected.first);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = DirectoryTreeDefaults.themed(
      context,
      base: DirectoryTreeThemeData(
        rowHeight: _rowHeight,
        indent: _indent,
        roundedCorners: _rounded,
        animationDuration: const Duration(milliseconds: 120),
      ),
    );

    final rowBuilder = DemoRowBuilder(controller: controller);

    return DirectoryTreeTheme(
      data: themeData,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kitchen Sink'),
          actions: [
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: () {
                final nodes = controller.visibleNodes;
                if (nodes.isEmpty) return;
                controller.selectRange(
                  anchorId: nodes.first.id,
                  toId: nodes.last.id,
                );
              },
            ),
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.deselect),
              onPressed: controller.clearSelection,
            ),
          ],
        ),
        body: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(width: 320),
              child: _buildSidebarOptions(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _buildToolbar(),
                  const Divider(height: 1),
                  Expanded(
                    child: SelectionShortcuts(
                      controller: controller,
                      onActivate: (node) => controller.toggle(node.id),
                      child: DirectoryTreeView(
                        controller: controller,
                        nodeBuilder: (ctx, node, state) => rowBuilder.build(
                          ctx,
                          node,
                          state,
                          onActivated: () => controller.toggle(node.id),
                        ),
                        expanderBuilder: fancyExpander,
                        showScrollbar: true,
                        preserveScrollOnChanges: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                  _buildStatusBar(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarOptions() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        const Text(
          'List & Behavior',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SwitchListTile(
          title: const Text('SortedFlattenStrategy (AlphaSortDelegate)'),
          value: _useSorted,
          onChanged: (value) {
            setState(() => _useSorted = value);
            _rebuildController();
          },
        ),
        SwitchListTile(
          title: const Text('Multi-selection mode'),
          value: _allowMulti,
          onChanged: (value) {
            setState(() => _allowMulti = value);
            _rebuildController();
          },
        ),
        const SizedBox(height: 16),
        const Text('Theme', style: TextStyle(fontWeight: FontWeight.w600)),
        _slider(
          label: 'Row height',
          value: _rowHeight,
          min: 20,
          max: 40,
          onChanged: (value) => setState(() => _rowHeight = value),
        ),
        _slider(
          label: 'Indent',
          value: _indent,
          min: 8,
          max: 24,
          onChanged: (value) => setState(() => _indent = value),
        ),
        SwitchListTile(
          title: const Text('Rounded row corners'),
          value: _rounded,
          onChanged: (value) => setState(() => _rounded = value),
        ),
        const SizedBox(height: 16),
        const Text(
          'Filter & reveal',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const Text(
          'Use the toolbar search field above the tree. Syntax supports `ext:dart` and `!token`.',
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Reveal by virtual path (e.g. /src/utils.dart)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (path) => revealAndSelect(controller, virtualPath: path),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.assistant_navigation),
          label: const Text('Reveal current selection'),
          onPressed: () async {
            final id = controller.selection.selectedIds.isEmpty
                ? null
                : controller.selection.selectedIds.last;
            if (id != null) {
              await controller.reveal(nodeId: id, select: true);
            }
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Commands & Shortcuts',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tree supports arrows, Space, Enter, Home/End, PageUp/PageDown, '
          'and Cmd/Ctrl+A via SelectionShortcuts.',
        ),
        const SizedBox(height: 12),
        _CommandsPreview(controller: controller),
      ],
    );
  }

  Widget _buildToolbar() {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _filter,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Filter tree…',
                ),
                onChanged: (value) => controller.filterQuery = value,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Expand all folders',
              child: IconButton(
                icon: const Icon(Icons.unfold_more),
                onPressed: () {
                  final folders = controller.data.nodes.values
                      .where(
                        (node) =>
                            node.type == core.NodeType.folder ||
                            node.type == core.NodeType.root,
                      )
                      .map((node) => node.id);
                  controller.expansions.expandAll(folders);
                },
              ),
            ),
            Tooltip(
              message: 'Collapse all',
              child: IconButton(
                icon: const Icon(Icons.unfold_less),
                onPressed: controller.expansions.collapseAll,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible = controller.visibleNodes;
        final selected = controller.selection.selectedIds;
        final currentId = selected.isEmpty ? null : selected.last;

        String details;
        if (currentId != null) {
          final node = controller.data.nodes[currentId]!;
          final extensions = extensionLower(node.name);
          final predicate = compileFilter(controller.filterQuery);
          final matchesFilter = predicate(node.name, extensions);
          final dartLike = hasAnyExtension(node.name, ['.dart']);
          final chain = ancestorChain(controller.data, currentId).join(' → ');
          details =
              'Selected: ${node.name} | ext=$extensions | matches=$matchesFilter '
              '| dart? $dartLike | chain: $chain';
        } else {
          details = 'No selection';
        }

        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Visible: ${visible.length} | Selected: ${selected.length} | $details',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        );
      },
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 160, child: Text(label)),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: (max - min).round(),
            value: value,
            label: value.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _CommandsPreview extends StatelessWidget {
  const _CommandsPreview({required this.controller});

  final DirectoryTreeController controller;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ExpandNodeIntent: DirectoryTreeAction<ExpandNodeIntent>(controller),
        CollapseNodeIntent: DirectoryTreeAction<CollapseNodeIntent>(controller),
        ToggleNodeIntent: DirectoryTreeAction<ToggleNodeIntent>(controller),
        RevealNodeIntent: DirectoryTreeAction<RevealNodeIntent>(controller),
        SelectOnlyIntent: DirectoryTreeAction<SelectOnlyIntent>(controller),
        ClearSelectionIntent: DirectoryTreeAction<ClearSelectionIntent>(
          controller,
        ),
      },
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ElevatedButton(
            onPressed: () {
              final id = _currentId();
              if (id != null) {
                Actions.invoke(context, ExpandNodeIntent(id));
              }
            },
            child: const Text('Action: Expand node'),
          ),
          ElevatedButton(
            onPressed: () {
              final id = _currentId();
              if (id != null) {
                Actions.invoke(context, CollapseNodeIntent(id));
              }
            },
            child: const Text('Action: Collapse node'),
          ),
          ElevatedButton(
            onPressed: () {
              final id = _currentId();
              if (id != null) {
                Actions.invoke(context, ToggleNodeIntent(id));
              }
            },
            child: const Text('Action: Toggle node'),
          ),
          ElevatedButton(
            onPressed: () {
              final id = _currentId();
              if (id != null) {
                Actions.invoke(
                  context,
                  RevealNodeIntent(nodeId: id, select: true),
                );
              }
            },
            child: const Text('Action: Reveal + select'),
          ),
          OutlinedButton(
            onPressed: () =>
                Actions.invoke(context, const ClearSelectionIntent()),
            child: const Text('Action: Clear selection'),
          ),
        ],
      ),
    );
  }

  String? _currentId() {
    final ids = controller.selection.selectedIds;
    return ids.isEmpty ? null : ids.last;
  }
}
