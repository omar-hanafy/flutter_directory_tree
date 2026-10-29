import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/dnd/directory_tree_drag_and_drop.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_menu_details.dart';
import 'package:flutter_directory_tree/src/search/directory_tree_search_field.dart';
import 'package:flutter_directory_tree/src/search/directory_tree_toolbar.dart';
import 'package:flutter_directory_tree/src/view/directory_tree_view.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';

/// A ready-made explorer pane: a [DirectoryTreeToolbar], a
/// [DirectoryTreeSearchField], and a [DirectoryTreeView] below them, all
/// bound to one [controller].
///
/// The search field filters the rows as the user types, its down arrow
/// moves the keyboard focus into the tree, and Ctrl+F (Cmd+F on macOS)
/// moves it back to the search field from anywhere in the panel. The
/// toolbar shows [title], expand-all and collapse-all buttons, and
/// [actions].
///
/// ```dart
/// Expanded(
///   child: DirectoryTreePanel<void>(
///     controller: controller,
///     title: const Text('Explorer'),
///     onActivate: (row) => debugPrint('open ${row.node.path}'),
///   ),
/// )
/// ```
///
/// Every parameter from [rowBuilder] on is passed to the
/// [DirectoryTreeView] unchanged; see that class for their meaning. Use
/// [toolbar] to replace the toolbar, [showToolbar] and [showSearch] to hide
/// parts. Like the view, the panel needs a bounded height.
class DirectoryTreePanel<T> extends StatefulWidget {
  /// Creates an explorer pane for [controller].
  const DirectoryTreePanel({
    super.key,
    required this.controller,
    this.title,
    this.actions = const <Widget>[],
    this.toolbar,
    this.showToolbar = true,
    this.showSearch = true,
    this.searchHintText,
    this.autofocus = false,
    this.rowBuilder,
    this.checkboxMode = DirectoryTreeCheckboxMode.none,
    this.expandOnTap = true,
    this.selectOnTap = true,
    this.onRowTap,
    this.onActivate,
    this.onRowSecondaryTap,
    this.contextMenuBuilder,
    this.dragAndDrop,
    this.focusNode,
    this.shortcuts,
    this.typeAhead = true,
    this.scrollController,
    this.padding,
    this.physics,
    this.showScrollbar = true,
    this.semanticLabel,
    this.levelSemanticsHint,
    this.emptyBuilder,
  });

  /// The state every part of the panel shows and changes.
  ///
  /// The panel never disposes it.
  final DirectoryTreeController<T> controller;

  /// The leading widget of the default toolbar, usually a [Text]; none
  /// when `null`.
  ///
  /// Ignored when [toolbar] is given.
  final Widget? title;

  /// Widgets after the default toolbar's own buttons, such as an
  /// [IconButton] that creates a file.
  ///
  /// Ignored when [toolbar] is given.
  final List<Widget> actions;

  /// Replaces the default [DirectoryTreeToolbar] entirely; the default
  /// toolbar when `null`.
  final Widget? toolbar;

  /// Whether the toolbar (default or [toolbar]) is shown; true by default.
  final bool showToolbar;

  /// Whether the search field is shown; true by default.
  ///
  /// Without it, Ctrl+F does nothing and only the type-ahead of the tree
  /// searches.
  final bool showSearch;

  /// The hint of the search field;
  /// [MaterialLocalizations.searchFieldLabel] when `null`.
  final String? searchHintText;

  /// Whether the tree takes the keyboard focus when the panel first
  /// appears, if nothing else in its focus scope has it; false by default.
  final bool autofocus;

  /// See [DirectoryTreeView.rowBuilder].
  final DirectoryTreeRowBuilder<T>? rowBuilder;

  /// See [DirectoryTreeView.checkboxMode].
  final DirectoryTreeCheckboxMode checkboxMode;

  /// See [DirectoryTreeView.expandOnTap].
  final bool expandOnTap;

  /// See [DirectoryTreeView.selectOnTap].
  final bool selectOnTap;

  /// See [DirectoryTreeView.onRowTap].
  final ValueChanged<TreeRow<T>>? onRowTap;

  /// See [DirectoryTreeView.onActivate].
  final ValueChanged<TreeRow<T>>? onActivate;

  /// See [DirectoryTreeView.onRowSecondaryTap].
  final void Function(TreeRow<T> row, Offset globalPosition)? onRowSecondaryTap;

  /// See [DirectoryTreeView.contextMenuBuilder].
  final DirectoryTreeMenuBuilder<T>? contextMenuBuilder;

  /// See [DirectoryTreeView.dragAndDrop].
  final DirectoryTreeDragAndDrop<T>? dragAndDrop;

  /// The keyboard focus node of the tree; the panel creates and disposes
  /// its own when `null`.
  ///
  /// The search field's down arrow moves the focus to it.
  final FocusNode? focusNode;

  /// See [DirectoryTreeView.shortcuts].
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// See [DirectoryTreeView.typeAhead].
  final bool typeAhead;

  /// See [DirectoryTreeView.scrollController].
  final ScrollController? scrollController;

  /// See [DirectoryTreeView.padding].
  final EdgeInsetsGeometry? padding;

  /// See [DirectoryTreeView.physics].
  final ScrollPhysics? physics;

  /// See [DirectoryTreeView.showScrollbar].
  final bool showScrollbar;

  /// See [DirectoryTreeView.semanticLabel].
  final String? semanticLabel;

  /// See [DirectoryTreeView.levelSemanticsHint].
  final String Function(int level)? levelSemanticsHint;

  /// See [DirectoryTreeView.emptyBuilder].
  final WidgetBuilder? emptyBuilder;

  @override
  State<DirectoryTreePanel<T>> createState() => _DirectoryTreePanelState<T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<DirectoryTreeController<T>>(
          'controller',
          controller,
        ),
      )
      ..add(
        FlagProperty(
          'showToolbar',
          value: showToolbar,
          ifFalse: 'no toolbar',
          defaultValue: true,
        ),
      )
      ..add(
        FlagProperty(
          'showSearch',
          value: showSearch,
          ifFalse: 'no search',
          defaultValue: true,
        ),
      )
      ..add(
        FlagProperty(
          'autofocus',
          value: autofocus,
          ifTrue: 'autofocus',
          defaultValue: false,
        ),
      )
      ..add(
        EnumProperty<DirectoryTreeCheckboxMode>(
          'checkboxMode',
          checkboxMode,
          defaultValue: DirectoryTreeCheckboxMode.none,
        ),
      );
  }
}

class _DirectoryTreePanelState<T> extends State<DirectoryTreePanel<T>> {
  FocusNode? _ownedTreeFocusNode;
  final FocusNode _searchFocusNode = FocusNode(
    debugLabel: 'DirectoryTreePanel search',
  );

  FocusNode get _treeFocusNode =>
      widget.focusNode ??
      (_ownedTreeFocusNode ??= FocusNode(debugLabel: 'DirectoryTreePanel'));

  @override
  void didUpdateWidget(DirectoryTreePanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != null) {
      _ownedTreeFocusNode?.dispose();
      _ownedTreeFocusNode = null;
    }
  }

  @override
  void dispose() {
    _ownedTreeFocusNode?.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _focusSearch() => _searchFocusNode.requestFocus();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final treeFocusNode = _treeFocusNode;
    Widget result = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showToolbar)
          widget.toolbar ??
              DirectoryTreeToolbar(
                controller: controller,
                title: widget.title,
                actions: widget.actions,
              ),
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
            child: DirectoryTreeSearchField(
              controller: controller,
              focusNode: _searchFocusNode,
              treeFocusNode: treeFocusNode,
              hintText: widget.searchHintText,
            ),
          ),
        Expanded(
          child: DirectoryTreeView<T>(
            controller: controller,
            rowBuilder: widget.rowBuilder,
            checkboxMode: widget.checkboxMode,
            expandOnTap: widget.expandOnTap,
            selectOnTap: widget.selectOnTap,
            onRowTap: widget.onRowTap,
            onActivate: widget.onActivate,
            onRowSecondaryTap: widget.onRowSecondaryTap,
            contextMenuBuilder: widget.contextMenuBuilder,
            dragAndDrop: widget.dragAndDrop,
            focusNode: treeFocusNode,
            autofocus: widget.autofocus,
            shortcuts: widget.shortcuts,
            typeAhead: widget.typeAhead,
            scrollController: widget.scrollController,
            padding: widget.padding,
            physics: widget.physics,
            showScrollbar: widget.showScrollbar,
            semanticLabel: widget.semanticLabel,
            levelSemanticsHint: widget.levelSemanticsHint,
            emptyBuilder: widget.emptyBuilder,
          ),
        ),
      ],
    );
    if (widget.showSearch) {
      final apple =
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS;
      result = CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          SingleActivator(
            LogicalKeyboardKey.keyF,
            control: !apple,
            meta: apple,
          ): _focusSearch,
        },
        child: result,
      );
    }
    // The search field and the toolbar's buttons need a Material ancestor;
    // a transparent one keeps the panel usable outside a Scaffold.
    return Material(type: MaterialType.transparency, child: result);
  }
}
