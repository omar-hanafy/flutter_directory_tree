// example/lib/pages/picker_dialog_demo.dart
import 'package:directory_tree/directory_tree.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

import '../shared/node_builders.dart';

class PickerDialogDemo extends StatefulWidget {
  const PickerDialogDemo({super.key, required this.data});
  final core.TreeData data;

  @override
  State<PickerDialogDemo> createState() => _PickerDialogDemoState();
}

class _PickerDialogDemoState extends State<PickerDialogDemo> {
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

  bool _multi = false;
  bool _foldersOnly = false;
  Set<String> _picked = const <String>{};

  @override
  Widget build(BuildContext context) {
    final themed = DirectoryTreeDefaults.themed(context);

    return DirectoryTreeTheme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(title: const Text('Picker Dialog')),
        body: Column(
          children: [
            SwitchListTile(
              title: const Text('Allow multiple'),
              value: _multi,
              onChanged: (value) => setState(() => _multi = value),
            ),
            SwitchListTile(
              title: const Text('Folders only'),
              value: _foldersOnly,
              onChanged: (value) => setState(() => _foldersOnly = value),
            ),
            const Divider(),
            Expanded(
              child: DirectoryTreeView(
                controller: controller,
                nodeBuilder: (ctx, node, state) => DemoRowBuilder(
                  controller: controller,
                ).build(ctx, node, state),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open picker…'),
                    onPressed: () async {
                      final picked = await showDirectoryTreePicker(
                        context: context,
                        controller: controller,
                        allowMultiple: _multi,
                        foldersOnly: _foldersOnly,
                        confirmLabel: 'Choose',
                        title: 'Pick ${_foldersOnly ? "folder(s)" : "item(s)"}',
                      );
                      setState(() => _picked = picked);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _picked.isEmpty
                          ? 'Picked: (none)'
                          : 'Picked: ${_picked.join(', ')}',
                      overflow: TextOverflow.ellipsis,
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
