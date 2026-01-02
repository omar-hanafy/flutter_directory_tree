// example/lib/pages/panel_and_toolbar_demo.dart
import 'package:directory_tree/directory_tree.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

import '../shared/node_builders.dart';

class PanelAndToolbarDemo extends StatefulWidget {
  const PanelAndToolbarDemo({super.key, required this.data});
  final core.TreeData data;

  @override
  State<PanelAndToolbarDemo> createState() => _PanelAndToolbarDemoState();
}

class _PanelAndToolbarDemoState extends State<PanelAndToolbarDemo> {
  late final DirectoryTreeController controller = DirectoryTreeController(
    data: widget.data,
    selection: SelectionController(mode: SelectionMode.multi),
    flattenStrategy: const DefaultFlattenStrategy(),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themed = DirectoryTreeDefaults.themed(context);

    return DirectoryTreeTheme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(title: const Text('DirectoryTreePanel + Toolbar')),
        body: DirectoryTreePanel(
          controller: controller,
          nodeBuilder: (ctx, node, state) =>
              DemoRowBuilder(controller: controller).build(ctx, node, state),
        ),
      ),
    );
  }
}
