import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';

/// Live theming: guide lines, row extent, indent width, compact folders,
/// top-level rows, right-to-left text, folder colors, and a custom
/// `rowBuilder` that adds a size badge to [DirectoryTreeRow]'s trailing
/// slot.
///
/// The look comes from a [DirectoryTreeTheme] around the view; every field
/// left `null` falls back to the app's Material 3 theme.
class ThemingDemo extends StatefulWidget {
  /// Creates the theming demo.
  const ThemingDemo({super.key});

  @override
  State<ThemingDemo> createState() => _ThemingDemoState();
}

class _ThemingDemoState extends State<ThemingDemo> {
  late final DirectoryTreeController<int> _controller = () {
    final tree = sampleProjectTree();
    final root = tree.roots.single;
    final lib = tree.nodeAt('$sampleRoot/lib')!.id;
    final features = tree.nodeAt('$sampleRoot/lib/src/features')!.id;
    return DirectoryTreeController<int>(
      tree: tree,
      expansion: const ExpansionState.collapsed()
          .expand(root)
          .expand(lib)
          .expand(features),
    );
  }();

  DirectoryTreeGuideStyle _guideStyle = DirectoryTreeGuideStyle.connectors;
  double _rowExtent = 30;
  double _indentWidth = 18;
  bool _rightToLeft = false;
  bool _sizeBadges = true;
  Color? _folderColor;

  static const Map<String, Color?> _folderColors = {
    'Theme': null,
    'Amber': Color(0xFFF2A900),
    'Teal': Color(0xFF00897B),
    'Pink': Color(0xFFD81B60),
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildRow(BuildContext context, DirectoryTreeRowDetails<int> details) {
    final node = details.row.node;
    final String badge = switch (node) {
      FileNode<int>(:final data) => formatSize(data ?? 0),
      DirectoryNode<int>() =>
        '${_controller.tree.childrenOf(node.id).length} items',
    };
    return DirectoryTreeRow<int>(
      details: details,
      trailing: _SizeBadge(text: badge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = Directionality(
      textDirection: _rightToLeft ? TextDirection.rtl : TextDirection.ltr,
      child: DirectoryTreeTheme(
        data: DirectoryTreeThemeData(
          guideStyle: _guideStyle,
          rowExtent: _rowExtent,
          indentWidth: _indentWidth,
          folderIconColor: _folderColor,
        ),
        child: DirectoryTreeView<int>(
          controller: _controller,
          rowBuilder: _sizeBadges ? _buildRow : null,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
    final controls = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _controlList(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: controls),
              const VerticalDivider(width: 1),
              Expanded(child: view),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: view),
            const Divider(height: 1),
            Expanded(child: controls),
          ],
        );
      },
    );
  }

  Widget _controlList(BuildContext context) {
    final theme = Theme.of(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          label('Guide lines'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<DirectoryTreeGuideStyle>(
              segments: const [
                ButtonSegment(
                  value: DirectoryTreeGuideStyle.none,
                  label: Text('None'),
                ),
                ButtonSegment(
                  value: DirectoryTreeGuideStyle.indent,
                  label: Text('Indent'),
                ),
                ButtonSegment(
                  value: DirectoryTreeGuideStyle.connectors,
                  label: Text('Connectors'),
                ),
              ],
              selected: {_guideStyle},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _guideStyle = value.single),
            ),
          ),
          label('Row extent: ${_rowExtent.round()} px'),
          Slider(
            value: _rowExtent,
            min: 20,
            max: 48,
            divisions: 28,
            label: '${_rowExtent.round()}',
            onChanged: (value) => setState(() => _rowExtent = value),
          ),
          label('Indent width: ${_indentWidth.round()} px'),
          Slider(
            value: _indentWidth,
            min: 8,
            max: 40,
            divisions: 32,
            label: '${_indentWidth.round()}',
            onChanged: (value) => setState(() => _indentWidth = value),
          ),
          label('Folder color'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final MapEntry(:key, :value) in _folderColors.entries)
                  ChoiceChip(
                    label: Text(key),
                    avatar: value == null
                        ? null
                        : CircleAvatar(backgroundColor: value),
                    selected: _folderColor == value,
                    onSelected: (_) => setState(() => _folderColor = value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Compact folders'),
            subtitle: const Text('Join single-child folders into one row'),
            value: _controller.compactFolders,
            onChanged: (value) => _controller.compactFolders = value,
          ),
          SwitchListTile(
            title: const Text('Show roots'),
            subtitle: const Text('Show the top-level folder as a row'),
            value: _controller.showRoots,
            onChanged: (value) => _controller.showRoots = value,
          ),
          SwitchListTile(
            title: const Text('Right to left'),
            value: _rightToLeft,
            onChanged: (value) => setState(() => _rightToLeft = value),
          ),
          SwitchListTile(
            title: const Text('Size badges'),
            subtitle: const Text('A rowBuilder with a trailing widget'),
            value: _sizeBadges,
            onChanged: (value) => setState(() => _sizeBadges = value),
          ),
        ],
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsetsDirectional.only(start: 8, end: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: scheme.onSecondaryContainer),
      ),
    );
  }
}
