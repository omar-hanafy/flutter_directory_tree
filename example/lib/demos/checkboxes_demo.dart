import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';

/// Tri-state checkboxes ([DirectoryTreeCheckboxMode.checks]) with live
/// lists of [DirectoryTreeController.checkedLeaves] and
/// [DirectoryTreeController.checkedRoots].
///
/// Checking a folder checks everything below it; a folder with some checked
/// descendants shows a dash. Space toggles the focused row's check.
class CheckboxesDemo extends StatefulWidget {
  /// Creates the checkboxes demo.
  const CheckboxesDemo({super.key});

  @override
  State<CheckboxesDemo> createState() => _CheckboxesDemoState();
}

class _CheckboxesDemoState extends State<CheckboxesDemo> {
  late final DirectoryTreeController<int> _controller = () {
    final tree = sampleProjectTree();
    return DirectoryTreeController<int>(
      tree: tree,
      expansion: const ExpansionState.collapsed().expand(tree.roots.single),
    );
  }();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tree = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _controller.checkAll,
                icon: const Icon(Icons.done_all),
                label: const Text('Check all'),
              ),
              OutlinedButton.icon(
                onPressed: _controller.uncheckAll,
                icon: const Icon(Icons.remove_done),
                label: const Text('Uncheck all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: DirectoryTreeView<int>(
            controller: _controller,
            checkboxMode: DirectoryTreeCheckboxMode.checks,
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      ],
    );
    final lists = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _CheckedLists(
        leaves: _controller.checkedLeaves,
        roots: _controller.checkedRoots,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tree),
              const VerticalDivider(width: 1),
              SizedBox(width: 320, child: lists),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: tree),
            const Divider(height: 1),
            Expanded(flex: 2, child: lists),
          ],
        );
      },
    );
  }
}

class _CheckedLists extends StatelessWidget {
  const _CheckedLists({required this.leaves, required this.roots});

  final List<TreeNode<int>> leaves;
  final List<TreeNode<int>> roots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );
    Widget item(TreeNode<int> node) => Text(
      node.path.toString(),
      style: theme.textTheme.bodySmall,
      overflow: TextOverflow.ellipsis,
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          heading('Checked roots (${roots.length})'),
          Text(
            'The outermost checked nodes: a checked folder stands for '
            'everything below it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          for (final node in roots) item(node),
          heading('Checked leaves (${leaves.length})'),
          for (final node in leaves) item(node),
        ],
      ),
    );
  }
}
