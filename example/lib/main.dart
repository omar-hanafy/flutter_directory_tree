// example/lib/main.dart
import 'package:directory_tree/directory_tree.dart' as core;
import 'package:flutter/material.dart';

import 'pages/kitchen_sink.dart';
import 'pages/panel_and_toolbar_demo.dart';
import 'pages/picker_dialog_demo.dart';
import 'pages/splitter_demo.dart';
import 'pages/tree_diff_demo.dart';
import 'sample_tree.dart';

void main() {
  runApp(const DirectoryTreeExamplesApp());
}

class DirectoryTreeExamplesApp extends StatelessWidget {
  const DirectoryTreeExamplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_directory_tree — Examples',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  core.TreeData? _data;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDemoTree();
  }

  Future<void> _loadDemoTree() async {
    try {
      final data = await buildDemoTreeData();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (err) {
      if (!mounted) return;
      setState(() => _loadError = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loadError != null) {
      body = _ErrorHint(error: _loadError!);
    } else if (_data == null) {
      body = const _LoadingHint();
    } else {
      body = _ExamplesList(data: _data!);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('flutter_directory_tree — Examples')),
      body: body,
    );
  }
}

class _ExamplesList extends StatelessWidget {
  const _ExamplesList({required this.data});

  final core.TreeData data;

  @override
  Widget build(BuildContext context) {
    final items = <_ExampleItem>[
      _ExampleItem(
        title: 'Kitchen Sink (most APIs)',
        subtitle:
            'Controllers, flatten/sort, theme defaults, context menu, icon provider, '
            'custom node builder, search filter, reveal helpers, selection shortcuts, '
            'indent & connector guides, commands.',
        builder: (_) => KitchenSinkPage(data: data),
      ),
      _ExampleItem(
        title: 'Panel + Toolbar',
        subtitle:
            'DirectoryTreePanel + DirectoryTreeToolbar with default theming and multi-select.',
        builder: (_) => PanelAndToolbarDemo(data: data),
      ),
      _ExampleItem(
        title: 'Picker Dialog',
        subtitle:
            'showDirectoryTreePicker — single/multiple, folders-only toggle.',
        builder: (_) => PickerDialogDemo(data: data),
      ),
      _ExampleItem(
        title: 'Resizable Splitter',
        subtitle: 'ResizableSplitter + SplitterController (drag and keyboard).',
        builder: (_) => SplitterDemo(data: data),
      ),
      _ExampleItem(
        title: 'Tree Diff + Preserve Scroll',
        subtitle:
            'diffVisibleNodes, ListDiff, schedulePreserveScrollOffset with a mirrored ListView.',
        builder: (_) => TreeDiffDemo(data: data),
      ),
    ];

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: items.length,
      separatorBuilder: (context, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          title: Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(item.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: item.builder)),
        );
      },
    );
  }
}

class _ExampleItem {
  const _ExampleItem({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final WidgetBuilder builder;
}

class _LoadingHint extends StatelessWidget {
  const _LoadingHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Loading demo tree…\n\n'
          'Open example/lib/sample_tree.dart and return a directory_tree.TreeData.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _ErrorHint extends StatelessWidget {
  const _ErrorHint({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not build demo TreeData.\n\n$error\n\n'
          'Edit example/lib/sample_tree.dart to match your directory_tree data.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: Colors.red),
        ),
      ),
    );
  }
}
