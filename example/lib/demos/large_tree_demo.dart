import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/data/large_tree.dart';

/// A generated tree of 100,000 nodes with search, expand all, collapse
/// all, and timings of the controller commands.
///
/// Only the visible rows are built, and a toggle updates the rows
/// incrementally, so expanding one folder costs the same in a huge tree as
/// in a small one.
class LargeTreeDemo extends StatefulWidget {
  /// Creates the large tree demo with [nodeCount] nodes.
  const LargeTreeDemo({super.key, this.nodeCount = 100000});

  /// How many nodes the generated tree has.
  final int nodeCount;

  @override
  State<LargeTreeDemo> createState() => _LargeTreeDemoState();
}

class _LargeTreeDemoState extends State<LargeTreeDemo> {
  DirectoryTreeController<Object?>? _controller;
  Duration? _buildTime;
  String? _lastTiming;

  @override
  void initState() {
    super.initState();
    // Build after the first frame, so the page shows a progress indicator
    // instead of a frozen window while the tree is built.
    SchedulerBinding.instance.addPostFrameCallback((_) => _build());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _build() {
    if (!mounted) return;
    final stopwatch = Stopwatch()..start();
    final tree = DirectoryTree<Object?>.build(
      largeTreeEntries(nodeCount: widget.nodeCount),
    );
    final controller = DirectoryTreeController<Object?>(
      tree: tree,
      expansion: const ExpansionState.collapsed().expandAll(tree.roots),
    );
    stopwatch.stop();
    setState(() {
      _controller = controller;
      _buildTime = stopwatch.elapsed;
    });
  }

  /// Runs [command] under a [Stopwatch] and shows how long it took.
  void _time(String label, VoidCallback command) {
    final controller = _controller!;
    final before = controller.rows.length;
    final stopwatch = Stopwatch()..start();
    command();
    stopwatch.stop();
    final after = controller.rows.length;
    final delta = after - before;
    final sign = delta >= 0 ? '+' : '-';
    setState(() {
      _lastTiming =
          '$label: ${_milliseconds(stopwatch.elapsed)} '
          '($sign${formatCount(delta.abs())} rows)';
    });
  }

  static String _milliseconds(Duration duration) =>
      '${(duration.inMicroseconds / 1000).toStringAsFixed(2)} ms';

  /// The folder the toggle button opens or closes: the focused row's
  /// folder, or the first package.
  NodeId? _toggleTarget(DirectoryTreeController<Object?> controller) {
    final focused = controller.focusedRow?.node;
    if (focused is DirectoryNode<Object?>) return focused.id;
    if (focused?.parent case final parent?) return parent;
    final root = controller.tree.roots.firstOrNull;
    if (root == null) return null;
    return controller.tree.childrenOf(root).firstOrNull?.id;
  }

  void _toggle() {
    final controller = _controller!;
    final target = _toggleTarget(controller);
    if (target == null) return;
    final name = controller.tree[target]!.name;
    _time('Toggle $name', () => controller.toggleExpansion(target));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final buildTime = _buildTime;
    if (controller == null || buildTime == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Building ${formatCount(widget.nodeCount)} nodes...'),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Wrap(
                spacing: 24,
                runSpacing: 4,
                children: [
                  Text(
                    '${formatCount(controller.tree.length)} nodes built in '
                    '${_milliseconds(buildTime)}',
                  ),
                  Text('${formatCount(controller.rows.length)} rows'),
                  if (_lastTiming case final timing?)
                    Text(timing, key: const ValueKey<String>('last-timing')),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: DirectoryTreePanel<Object?>(
            controller: controller,
            toolbar: DirectoryTreeToolbar(
              controller: controller,
              title: const Text('monorepo'),
              showExpandAll: false,
              showCollapseAll: false,
              actions: [
                TextButton.icon(
                  onPressed: _toggle,
                  icon: const Icon(Icons.unfold_more),
                  label: const Text('Toggle folder'),
                ),
                IconButton(
                  tooltip: 'Expand all',
                  icon: const Icon(Icons.expand),
                  onPressed: () => _time('Expand all', controller.expandAll),
                ),
                IconButton(
                  tooltip: 'Collapse all',
                  icon: const Icon(Icons.compress),
                  onPressed: () =>
                      _time('Collapse all', controller.collapseAll),
                ),
              ],
            ),
            searchHintText: 'Search (try module_07/file_042)',
          ),
        ),
      ],
    );
  }
}
