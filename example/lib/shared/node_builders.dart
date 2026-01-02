// example/lib/shared/node_builders.dart
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

import 'icon_providers.dart';

/// Animated chevron used in several demos.
Widget fancyExpander(
  BuildContext context,
  VisibleNode node,
  bool isExpanded,
  VoidCallback onPressed,
) {
  return IconButton(
    iconSize: 18,
    padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
    tooltip: isExpanded ? 'Collapse' : 'Expand',
    onPressed: onPressed,
    icon: AnimatedRotation(
      turns: isExpanded ? 0.25 : 0.0,
      duration: const Duration(milliseconds: 120),
      child: const Text('▸', textAlign: TextAlign.center),
    ),
  );
}

/// A reusable node builder showcasing icon providers, context menus, and the
/// stock [TreeNodeTile].
class DemoRowBuilder {
  DemoRowBuilder({required this.controller, IconProvider? icons})
    : iconProvider = icons ?? const FancyIconProvider() {
    _menu = MaterialContextMenuDelegate(_actionsFor);
  }

  final DirectoryTreeController controller;
  final IconProvider iconProvider;

  late final MaterialContextMenuDelegate _menu;

  List<NodeAction> _actionsFor(VisibleNode node) {
    return <NodeAction>[
      NodeAction(
        id: 'reveal',
        label: 'Reveal (select)',
        icon: const Icon(Icons.visibility, size: 18),
        onInvoke: (n) => controller.reveal(nodeId: n.id, select: true),
      ),
      NodeAction(
        id: 'toggle',
        label: 'Toggle expand',
        icon: const Icon(Icons.unfold_more, size: 18),
        onInvoke: (n) async => controller.toggle(n.id),
      ),
    ];
  }

  Widget build(
    BuildContext context,
    VisibleNode node,
    NodeVisualState visual, {
    VoidCallback? onActivated,
    VoidCallback? onTap,
  }) {
    final leading = iconProvider.leadingIcon(context, node);
    final trailing = iconProvider.trailingIcon(context, node);

    final tile = TreeNodeTile(
      node: node,
      state: visual,
      leading: leading == null
          ? null
          : Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
              child: leading,
            ),
      trailing: trailing,
      title: Text(node.name, overflow: TextOverflow.ellipsis),
      onTap: onTap ?? () => controller.selectOnly(node.id),
      onDoubleTap: node.hasChildren
          ? () => controller.toggle(node.id)
          : onActivated,
      onTertiaryTap: () => controller.toggleSelection(node.id),
    );

    return _menu.wrapWithMenu(context, tile, node);
  }
}
