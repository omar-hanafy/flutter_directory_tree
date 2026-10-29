import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';

/// Opens [showDirectoryTreePicker] in every mode, single and multiple, and
/// shows what it returned.
///
/// The picker works on its own copy of the state, so cancelling changes
/// nothing; it returns `null` then.
class PickerDemo extends StatefulWidget {
  /// Creates the picker demo.
  const PickerDemo({super.key});

  @override
  State<PickerDemo> createState() => _PickerDemoState();
}

class _PickerDemoState extends State<PickerDemo> {
  final DirectoryTree<int> _tree = sampleProjectTree();
  String? _request;
  List<TreeNode<int>>? _result;
  bool _cancelled = false;

  static String _modeName(DirectoryTreePickerMode mode) => switch (mode) {
    DirectoryTreePickerMode.files => 'files',
    DirectoryTreePickerMode.directories => 'folders',
    DirectoryTreePickerMode.any => 'files or folders',
  };

  static String _title(DirectoryTreePickerMode mode, {required bool multiple}) {
    final what = switch (mode) {
      DirectoryTreePickerMode.files => multiple ? 'files' : 'a file',
      DirectoryTreePickerMode.directories => multiple ? 'folders' : 'a folder',
      DirectoryTreePickerMode.any =>
        multiple ? 'files or folders' : 'a file or folder',
    };
    return 'Pick $what';
  }

  Future<void> _open(
    DirectoryTreePickerMode mode, {
    required bool multiple,
  }) async {
    final title = _title(mode, multiple: multiple);
    final picked = await showDirectoryTreePicker<int>(
      context: context,
      tree: _tree,
      mode: mode,
      multiple: multiple,
      initialExpansion: const ExpansionState.collapsed().expandAll(_tree.roots),
      title: title,
      confirmLabel: multiple ? 'Choose' : 'Open',
    );
    if (!mounted) return;
    setState(() {
      _request = title;
      _result = picked;
      _cancelled = picked == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Each button opens the picker dialog in one mode. Single pickers '
          'confirm on a double-click or Enter; multiple pickers use '
          'checkboxes.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final mode in DirectoryTreePickerMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    _modeName(mode),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => unawaited(_open(mode, multiple: false)),
                  child: Text(_title(mode, multiple: false)),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(_open(mode, multiple: true)),
                  child: Text(_title(mode, multiple: true)),
                ),
              ],
            ),
          ),
        const Divider(height: 32),
        Text('Result', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_request == null)
          Text('Nothing picked yet.', style: theme.textTheme.bodySmall)
        else ...[
          Text(_request!, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (_cancelled)
            const Text('cancelled', key: ValueKey<String>('picker-cancelled'))
          else
            for (final node in result!)
              Text(
                '${node.isDirectory ? 'folder' : 'file'}  ${node.path}',
                style: theme.textTheme.bodyMedium,
              ),
        ],
      ],
    );
  }
}
