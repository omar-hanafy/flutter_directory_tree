// example/lib/pages/tree_diff_demo.dart
import 'package:directory_tree/directory_tree.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

class TreeDiffDemo extends StatefulWidget {
  const TreeDiffDemo({super.key, required this.data});
  final core.TreeData data;

  @override
  State<TreeDiffDemo> createState() => _TreeDiffDemoState();
}

class _TreeDiffDemoState extends State<TreeDiffDemo> {
  late final DirectoryTreeController controller = DirectoryTreeController(
    data: widget.data,
    flattenStrategy: const DefaultFlattenStrategy(),
  );

  final ScrollController mirrorScroll = ScrollController();
  List<VisibleNode> _mirror = const <VisibleNode>[];

  @override
  void initState() {
    super.initState();
    _mirror = List<VisibleNode>.from(controller.visibleNodes);
    controller.addListener(_syncMirror);
  }

  @override
  void dispose() {
    controller.removeListener(_syncMirror);
    controller.dispose();
    mirrorScroll.dispose();
    super.dispose();
  }

  void _syncMirror() {
    final next = List<VisibleNode>.from(controller.visibleNodes);
    schedulePreserveScrollOffset(
      controller: mirrorScroll,
      before: _mirror,
      after: next,
      rowExtent: DirectoryTreeTheme.of(context).rowHeight,
    );

    final diff = diffVisibleNodes(_mirror, next);
    if (!diff.isNoop) {
      debugPrint(
        'ListDiff remove(desc)=${diff.removeIndicesDesc} insert(asc)=${diff.insertIndicesAsc}',
      );
    }

    setState(() => _mirror = next);
  }

  @override
  Widget build(BuildContext context) {
    final themed = DirectoryTreeDefaults.themed(context);

    return DirectoryTreeTheme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(title: const Text('Tree Diff + Preserve Scroll')),
        body: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _FilterBar(controller: controller),
                  const Divider(height: 1),
                  Expanded(
                    child: DirectoryTreeView(
                      controller: controller,
                      nodeBuilder: (ctx, node, state) => ListTile(
                        dense: true,
                        title: Text(node.name),
                        onTap: () => controller.selectOnly(node.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  const ListTile(
                    dense: true,
                    title: Text('Plain ListView mirror'),
                    subtitle: Text(
                      'schedulePreserveScrollOffset keeps anchor in view',
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: mirrorScroll,
                      itemExtent: themed.rowHeight,
                      itemCount: _mirror.length,
                      itemBuilder: (context, index) {
                        final node = _mirror[index];
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: themed.indent * node.depth + 8,
                            ),
                            child: Text(node.name),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatefulWidget {
  const _FilterBar({required this.controller});
  final DirectoryTreeController controller;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.filterQuery,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Filter…',
              ),
              onChanged: (value) => widget.controller.filterQuery = value,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.unfold_more),
            tooltip: 'Expand all',
            onPressed: () {
              final folders = widget.controller.data.nodes.values
                  .where(
                    (node) =>
                        node.type == core.NodeType.folder ||
                        node.type == core.NodeType.root,
                  )
                  .map((node) => node.id);
              widget.controller.expansions.expandAll(folders);
            },
          ),
          IconButton(
            icon: const Icon(Icons.unfold_less),
            tooltip: 'Collapse all',
            onPressed: widget.controller.expansions.collapseAll,
          ),
        ],
      ),
    );
  }
}
