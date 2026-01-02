// example/lib/pages/splitter_demo.dart
import 'package:directory_tree/directory_tree.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:resizable_splitter/resizable_splitter.dart';

import '../shared/node_builders.dart';

class SplitterDemo extends StatefulWidget {
  const SplitterDemo({super.key, required this.data});

  final core.TreeData data;

  @override
  State<SplitterDemo> createState() => _SplitterDemoState();
}

class _SplitterDemoState extends State<SplitterDemo> {
  final SplitterController split = SplitterController(initialRatio: 0.4);
  late final DirectoryTreeController controller = DirectoryTreeController(
    data: widget.data,
    selection: SelectionController(mode: SelectionMode.single),
    flattenStrategy: const DefaultFlattenStrategy(),
  );

  String _details = 'Select a node…';

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    controller.dispose();
    split.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final ids = controller.selection.selectedIds;
    setState(() {
      if (ids.isEmpty) {
        _details = 'Select a node…';
      } else {
        final node = controller.data.nodes[ids.last]!;
        _details =
            'id: ${node.id}\nname: ${node.name}\nvirtual path: ${node.virtualPath}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themed = DirectoryTreeDefaults.themed(context);

    return DirectoryTreeTheme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(title: const Text('Resizable Splitter')),
        body: ResizableSplitter(
          controller: split,
          axis: Axis.horizontal,
          dividerThickness: 6,
          minPanelSize: 160,
          startPanel: Material(
            child: SelectionShortcuts(
              controller: controller,
              onActivate: (node) => controller.toggle(node.id),
              child: DirectoryTreeView(
                controller: controller,
                nodeBuilder: (ctx, node, state) =>
                    DemoRowBuilder(controller: controller).build(
                      ctx,
                      node,
                      state,
                      onTap: () {
                        controller.selectOnly(node.id);
                      },
                    ),
              ),
            ),
          ),
          endPanel: Material(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _details,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          semanticsLabel: 'Drag to resize panels',
        ),
      ),
    );
  }
}
