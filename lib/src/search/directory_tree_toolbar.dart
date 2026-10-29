import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/search/directory_tree_search_field.dart';
import 'package:flutter_directory_tree/src/search/labeled_icon_button.dart';

/// A header bar for a directory tree: a [title], the app's [actions], and
/// buttons that expand every folder, collapse every folder, and switch
/// compact folders on and off.
///
/// The built-in buttons call [DirectoryTreeController.expandAll] and
/// [DirectoryTreeController.collapseAll] and flip
/// [DirectoryTreeController.compactFolders]; the compact folders button
/// shows as selected while compact folders are on, also when the app
/// changes the setting. Each button names its action with a tooltip and a
/// semantics label. Their texts are English by default; pass translations
/// through [expandAllTooltip], [collapseAllTooltip], and
/// [compactFoldersTooltip].
///
/// ```dart
/// Column(
///   children: [
///     DirectoryTreeToolbar(
///       controller: controller,
///       title: const Text('Explorer'),
///       showCompactFolders: true,
///     ),
///     DirectoryTreeSearchField(controller: controller),
///     Expanded(child: DirectoryTreeView(controller: controller)),
///   ],
/// )
/// ```
///
/// The toolbar takes the full width it is given (the title fills the space
/// before the buttons), so it needs a bounded width, as in a [Column]. Its
/// height is at least [kMinInteractiveDimension] adjusted by the ambient
/// [ThemeData.visualDensity] (48 by default, 40 for
/// [VisualDensity.compact]), even without buttons. The title uses
/// [TextTheme.titleSmall] and the buttons follow the ambient
/// [IconButtonTheme]. It works without a [Material] ancestor. There is no
/// search field in it; pair it with a [DirectoryTreeSearchField].
///
/// The toolbar never rebuilds for the controller's focus, selection, or row
/// changes; only the compact folders button listens, and rebuilds when
/// [DirectoryTreeController.compactFolders] changes.
class DirectoryTreeToolbar extends StatelessWidget {
  /// Creates a toolbar for [controller].
  const DirectoryTreeToolbar({
    super.key,
    required this.controller,
    this.title,
    this.actions = const <Widget>[],
    this.showExpandAll = true,
    this.showCollapseAll = true,
    this.showCompactFolders = false,
    this.expandAllTooltip = 'Expand all',
    this.collapseAllTooltip = 'Collapse all',
    this.compactFoldersTooltip = 'Compact folders',
  });

  /// The controller the buttons act on.
  ///
  /// A controller of any data type works, since the buttons only expand,
  /// collapse, and switch compact folders.
  final DirectoryTreeController<Object?> controller;

  /// The widget at the start of the toolbar, typically a [Text].
  ///
  /// It is marked as a header for assistive technologies and gets
  /// [TextTheme.titleSmall] on one line, with an ellipsis when it does not
  /// fit. When `null`, the space stays empty and the buttons still sit at
  /// the end.
  final Widget? title;

  /// Widgets shown after the [title] and before the built-in buttons, such
  /// as a refresh or a new-file [IconButton].
  ///
  /// Empty by default.
  final List<Widget> actions;

  /// Whether to show the button that calls
  /// [DirectoryTreeController.expandAll]; true by default.
  final bool showExpandAll;

  /// Whether to show the button that calls
  /// [DirectoryTreeController.collapseAll]; true by default.
  final bool showCollapseAll;

  /// Whether to show the button that switches
  /// [DirectoryTreeController.compactFolders]; false by default.
  final bool showCompactFolders;

  /// The tooltip and semantics label of the expand all button.
  ///
  /// Defaults to 'Expand all'.
  final String expandAllTooltip;

  /// The tooltip and semantics label of the collapse all button.
  ///
  /// Defaults to 'Collapse all'.
  final String collapseAllTooltip;

  /// The tooltip and semantics label of the compact folders button.
  ///
  /// Defaults to 'Compact folders'.
  final String compactFoldersTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    // The transparent Material gives the buttons' ink a surface (and
    // Material 2 icon buttons the Material ancestor they require) wherever
    // the toolbar is placed.
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: theme.visualDensity.effectiveConstraints(
          const BoxConstraints(minHeight: kMinInteractiveDimension),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: title == null
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Semantics(
                          header: true,
                          child: DefaultTextStyle.merge(
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            child: title,
                          ),
                        ),
                      ),
              ),
              ...actions,
              if (showExpandAll)
                LabeledIconButton(
                  label: expandAllTooltip,
                  icon: Icons.unfold_more,
                  onPressed: controller.expandAll,
                ),
              if (showCollapseAll)
                LabeledIconButton(
                  label: collapseAllTooltip,
                  icon: Icons.unfold_less,
                  onPressed: controller.collapseAll,
                ),
              if (showCompactFolders)
                _CompactFoldersButton(
                  controller: controller,
                  label: compactFoldersTooltip,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<DirectoryTreeController<Object?>>(
          'controller',
          controller,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'showExpandAll',
          showExpandAll,
          defaultValue: true,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'showCollapseAll',
          showCollapseAll,
          defaultValue: true,
        ),
      )
      ..add(
        DiagnosticsProperty<bool>(
          'showCompactFolders',
          showCompactFolders,
          defaultValue: false,
        ),
      )
      ..add(
        StringProperty(
          'expandAllTooltip',
          expandAllTooltip,
          defaultValue: 'Expand all',
        ),
      )
      ..add(
        StringProperty(
          'collapseAllTooltip',
          collapseAllTooltip,
          defaultValue: 'Collapse all',
        ),
      )
      ..add(
        StringProperty(
          'compactFoldersTooltip',
          compactFoldersTooltip,
          defaultValue: 'Compact folders',
        ),
      );
  }
}

/// The compact folders toggle. It listens to the controller itself and
/// rebuilds only when [DirectoryTreeController.compactFolders] changes, so
/// focus, selection, and row notifications cost the toolbar nothing.
class _CompactFoldersButton extends StatefulWidget {
  const _CompactFoldersButton({required this.controller, required this.label});

  final DirectoryTreeController<Object?> controller;
  final String label;

  @override
  State<_CompactFoldersButton> createState() => _CompactFoldersButtonState();
}

class _CompactFoldersButtonState extends State<_CompactFoldersButton> {
  late bool _compact;

  @override
  void initState() {
    super.initState();
    _compact = widget.controller.compactFolders;
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(_CompactFoldersButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _compact = widget.controller.compactFolders;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final compact = widget.controller.compactFolders;
    if (compact != _compact) setState(() => _compact = compact);
  }

  void _toggle() {
    final controller = widget.controller;
    controller.compactFolders = !controller.compactFolders;
  }

  @override
  Widget build(BuildContext context) => LabeledIconButton(
    label: widget.label,
    icon: Icons.merge_type,
    isSelected: _compact,
    onPressed: _toggle,
  );
}
