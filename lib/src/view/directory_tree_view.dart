import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/dnd/directory_tree_drag_and_drop.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_context_menu.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_menu_details.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/panel/directory_tree_panel.dart';
import 'package:flutter_directory_tree/src/search/directory_tree_search_field.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

/// A scrollable directory tree with mouse, touch, and keyboard handling:
/// the rows of a [DirectoryTreeController] in one widget, with optional
/// context menus and drag and drop.
///
/// This is the widget most apps need. It stacks the building blocks of the
/// package and wires them to each other:
///
/// * a [SliverDirectoryTree] in a [CustomScrollView] draws the visible rows
///   and handles clicks, taps, and hover;
/// * a [DirectoryTreeKeyboard] maps keys to controller commands and runs
///   the type-ahead search;
/// * with a [contextMenuBuilder], a [DirectoryTreeContextMenu] opens a menu
///   for secondary clicks, touch long-presses, and Shift+F10 or the context
///   menu key;
/// * with [dragAndDrop], a [DirectoryTreeDragAndDropScope] lets the user
///   drag rows onto directories.
///
/// Compose those widgets directly for another arrangement, such as more
/// slivers in the same scroll view. [DirectoryTreePanel] puts a toolbar and
/// a search field on top of this view.
///
/// ```dart
/// DirectoryTreeView<void>(
///   controller: controller,
///   onActivate: (row) => debugPrint('open ${row.node.path}'),
///   contextMenuBuilder: (context, details) => [
///     MenuItemButton(
///       onPressed: () => debugPrint('delete ${details.nodes.length}'),
///       child: const Text('Delete'),
///     ),
///   ],
/// )
/// ```
///
/// ## Pointer and keyboard
///
/// A click focuses its row and, with [selectOnTap], selects it (Ctrl, or
/// Cmd on macOS, toggles; Shift extends); with [expandOnTap] a plain click
/// also opens or closes a directory. A double-click or Enter activates a
/// row: a directory toggles once, then [onActivate] runs for files and
/// directories alike. The keys are [DirectoryTreeShortcuts.defaults] unless
/// [shortcuts] replaces them.
///
/// ## Secondary taps and context menus
///
/// A secondary click (or a touch long-press) on a row selects the row when
/// it is not selected (with [selectOnTap]; otherwise it only focuses it),
/// calls [onRowSecondaryTap], and then opens the menu of
/// [contextMenuBuilder]. With [dragAndDrop], a touch long-press starts a
/// drag once the finger moves; a long-press released without moving counts
/// as a secondary tap. Shift+F10 and the context menu key open the menu for
/// the focused row; without a [contextMenuBuilder] they call
/// [onRowSecondaryTap] for the focused row instead (see there), so a menu
/// of another design system is reachable from the keyboard as well.
///
/// On the web, browsers show their own context menu for a right click on
/// top of the tree's menu until the app calls
/// `BrowserContextMenu.disableContextMenu()`; see
/// [DirectoryTreeContextMenu] for why the package leaves that to the app.
///
/// ## Changing the configuration
///
/// Every parameter may change between builds. The scroll position, the
/// keyboard focus, and the type-ahead search survive changes that add or
/// remove parts of the view, such as [contextMenuBuilder], [dragAndDrop],
/// [showScrollbar], [padding], or [semanticLabel].
///
/// ## Layout
///
/// The view fills the space its parent gives it and scrolls when the rows
/// need more, so it needs a bounded height, for example inside [Expanded]
/// or a [SizedBox]. Each row is [DirectoryTreeThemeData.rowExtent] high.
class DirectoryTreeView<T> extends StatefulWidget {
  /// Creates a view of [controller]'s rows.
  const DirectoryTreeView({
    super.key,
    required this.controller,
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
    this.autofocus = false,
    this.shortcuts,
    this.typeAhead = true,
    this.scrollController,
    this.padding,
    this.physics,
    this.showScrollbar = true,
    this.semanticLabel,
    this.levelSemanticsHint,
    this.emptyBuilder,
    this.selectionFollowsFocus = true,
  });

  /// The state the view shows and changes.
  ///
  /// The view listens to it but never disposes it; the widget that created
  /// it does. A different controller takes effect immediately.
  final DirectoryTreeController<T> controller;

  /// Builds the widget of each row; [DirectoryTreeRow] when `null`.
  ///
  /// The view wraps the result with the click, hover, and semantics
  /// handling, so the builder only draws. It runs again only for rows whose
  /// [DirectoryTreeRowDetails] changed.
  final DirectoryTreeRowBuilder<T>? rowBuilder;

  /// Which checkbox each row shows in front of its icon; none by default.
  ///
  /// Also decides what Space does: with [DirectoryTreeCheckboxMode.checks]
  /// it toggles the focused row's check, otherwise its selection.
  final DirectoryTreeCheckboxMode checkboxMode;

  /// Whether a plain click on a directory row opens or closes it; true by
  /// default.
  ///
  /// The expander in front of the icon toggles either way.
  final bool expandOnTap;

  /// Whether clicks select rows; true by default.
  ///
  /// When false, a click only focuses its row, and the selection changes
  /// only through the keyboard, selection checkboxes, and code.
  final bool selectOnTap;

  /// Called after the built-in handling of a primary click on a row.
  final ValueChanged<TreeRow<T>>? onRowTap;

  /// Called when a row is activated with a double-click or Enter, after a
  /// directory row has toggled; for files and directories alike.
  final ValueChanged<TreeRow<T>>? onActivate;

  /// Called for a secondary click or touch long-press on a row, with the
  /// global position of the pointer, after the row was selected (with
  /// [selectOnTap]; otherwise focused) and before the context menu opens.
  ///
  /// Without a [contextMenuBuilder], Shift+F10 and the context menu key call
  /// it too, for the focused row, the same way: with [selectOnTap] the row
  /// is selected first when it is not selected. The position is the
  /// bottom-start corner of the row (bottom-left in left-to-right text,
  /// bottom-right in right-to-left text), or the center of the view when
  /// the row is not laid out (scrolled out of view). The keys reach the
  /// widgets above the view while no row is focused, and an ancestor
  /// [Actions] that maps [OpenTreeContextMenuIntent] replaces this
  /// behavior.
  ///
  /// On the web, see [DirectoryTreeContextMenu] for the browser's own menu.
  final void Function(TreeRow<T> row, Offset globalPosition)? onRowSecondaryTap;

  /// Builds the items of the context menu of a row; no menu when `null`.
  ///
  /// Return an empty list to open no menu for a row. See
  /// [DirectoryTreeContextMenu]; the view creates it with
  /// [DirectoryTreeContextMenu.selectOnOpen] set to [selectOnTap], so with
  /// `selectOnTap: false` opening a menu never changes the selection. On the
  /// web, browsers show their own context menu on top of this one until the
  /// app calls `BrowserContextMenu.disableContextMenu()` (see
  /// [DirectoryTreeContextMenu]).
  final DirectoryTreeMenuBuilder<T>? contextMenuBuilder;

  /// How rows are dragged and dropped onto directories; no drag and drop
  /// when `null`.
  ///
  /// The package never moves data: the `onDrop` callback of
  /// [DirectoryTreeDragAndDrop] tells the app, which builds a new tree and
  /// assigns it to the controller.
  final DirectoryTreeDragAndDrop<T>? dragAndDrop;

  /// The keyboard focus node of the tree; the view creates and disposes its
  /// own when `null`.
  ///
  /// Give one to move the focus to the tree from elsewhere, such as the
  /// down arrow of a [DirectoryTreeSearchField].
  final FocusNode? focusNode;

  /// Whether the tree takes the keyboard focus when it first appears, if
  /// nothing else in its focus scope has it; false by default.
  final bool autofocus;

  /// The key bindings, replacing [DirectoryTreeShortcuts.defaults]
  /// entirely; the defaults when `null`.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Whether typing the start of a row's name moves to that row; true by
  /// default.
  final bool typeAhead;

  /// Whether moving the keyboard cursor (arrow keys, Home, End, the page
  /// keys, type-ahead) also selects the row it reaches; true by default.
  ///
  /// Set it to false where the user builds the selection pick by pick, for
  /// example with [DirectoryTreeCheckboxMode.selection] and
  /// `selectOnTap: false`, so that moving through the rows never undoes a
  /// pick; Space still toggles the focused row. See
  /// [DirectoryTreeKeyboard.selectionFollowsFocus].
  final bool selectionFollowsFocus;

  /// Controls the scroll position; the view creates and disposes its own
  /// when `null`.
  final ScrollController? scrollController;

  /// Empty space around the rows, inside the scroll view; none when `null`.
  final EdgeInsetsGeometry? padding;

  /// How the scroll view responds to input; the platform default when
  /// `null`.
  final ScrollPhysics? physics;

  /// Whether a [Scrollbar] is shown; true by default.
  ///
  /// When true the view adds a Material [Scrollbar] on every platform
  /// (visible while scrolling, or on hover on desktop, as the
  /// [ScrollbarTheme] says); when false there is none, not even the one
  /// that desktop platforms add by default.
  final bool showScrollbar;

  /// A label for the whole tree, read by screen readers before the rows;
  /// none when `null`.
  final String? semanticLabel;

  /// Builds the semantics hint of each row from its level ([TreeRow.depth]
  /// plus 1); the English `Level 2` when `null`.
  ///
  /// Pass a function to localize it. See
  /// [SliverDirectoryTree.levelSemanticsHint].
  final String Function(int level)? levelSemanticsHint;

  /// Builds what the view shows while there are no rows: an empty tree, or
  /// a search with no matches.
  ///
  /// The widget fills the visible area below the padding; wrap it in a
  /// [Center] to center it. When `null`, an empty view shows nothing.
  final WidgetBuilder? emptyBuilder;

  @override
  State<DirectoryTreeView<T>> createState() => _DirectoryTreeViewState<T>();

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
        EnumProperty<DirectoryTreeCheckboxMode>(
          'checkboxMode',
          checkboxMode,
          defaultValue: DirectoryTreeCheckboxMode.none,
        ),
      )
      ..add(
        FlagProperty(
          'expandOnTap',
          value: expandOnTap,
          ifFalse: 'no expand on tap',
          defaultValue: true,
        ),
      )
      ..add(
        FlagProperty(
          'selectOnTap',
          value: selectOnTap,
          ifFalse: 'no select on tap',
          defaultValue: true,
        ),
      )
      ..add(
        ObjectFlagProperty<DirectoryTreeMenuBuilder<T>>.has(
          'contextMenuBuilder',
          contextMenuBuilder,
        ),
      )
      ..add(
        DiagnosticsProperty<DirectoryTreeDragAndDrop<T>>(
          'dragAndDrop',
          dragAndDrop,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<FocusNode>(
          'focusNode',
          focusNode,
          defaultValue: null,
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
        DiagnosticsProperty<EdgeInsetsGeometry>(
          'padding',
          padding,
          defaultValue: null,
        ),
      )
      ..add(
        FlagProperty(
          'showScrollbar',
          value: showScrollbar,
          ifFalse: 'no scrollbar',
          defaultValue: true,
        ),
      )
      ..add(StringProperty('semanticLabel', semanticLabel, defaultValue: null))
      ..add(
        FlagProperty(
          'selectionFollowsFocus',
          value: selectionFollowsFocus,
          ifFalse: 'selection does not follow focus',
          defaultValue: true,
        ),
      );
  }
}

class _DirectoryTreeViewState<T> extends State<DirectoryTreeView<T>> {
  final GlobalKey<DirectoryTreeContextMenuState<T>> _menuKey =
      GlobalKey<DirectoryTreeContextMenuState<T>>();

  // The wrappers around the keyboard and the scroll view come and go with
  // the parameters; these keys move both subtrees (the scroll position,
  // the focus, the type-ahead search) to their new place instead of
  // building them anew.
  final GlobalKey _keyboardKey = GlobalKey(debugLabel: 'keyboard');
  final GlobalKey _scrollViewKey = GlobalKey(debugLabel: 'scroll view');

  late final Action<OpenTreeContextMenuIntent> _keyboardSecondaryTap =
      Action<OpenTreeContextMenuIntent>.overridable(
        defaultAction: _KeyboardSecondaryTapAction<T>(this),
        context: context,
      );

  ScrollController? _ownedScrollController;
  FocusNode? _ownedFocusNode;

  // Whether the controller has no rows; the view rebuilds only when this
  // flips, never for the row changes the sliver handles itself.
  late bool _isEmpty;

  ScrollController get _scrollController =>
      widget.scrollController ??
      (_ownedScrollController ??= ScrollController(
        debugLabel: 'DirectoryTreeView',
      ));

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'DirectoryTreeView'));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _isEmpty = widget.controller.rows.isEmpty;
  }

  @override
  void didUpdateWidget(DirectoryTreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _isEmpty = widget.controller.rows.isEmpty;
    }
    if (widget.scrollController != null) {
      // The scroll view moves its position to the new controller in this
      // build, so the one the view owned can go now.
      _ownedScrollController?.dispose();
      _ownedScrollController = null;
    }
    if (widget.focusNode != null) {
      _ownedFocusNode?.dispose();
      _ownedFocusNode = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _ownedScrollController?.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final isEmpty = widget.controller.rows.isEmpty;
    if (isEmpty != _isEmpty) setState(() => _isEmpty = isEmpty);
  }

  void _handleSecondaryTap(TreeRow<T> row, Offset globalPosition) {
    widget.onRowSecondaryTap?.call(row, globalPosition);
    if (widget.contextMenuBuilder != null) {
      _menuKey.currentState?.open(row: row, globalPosition: globalPosition);
    }
  }

  void _handleLongPressWithoutDrag(TreeRow<T> row, Offset globalPosition) {
    // What the sliver does for a secondary tap: focus the tree, act on the
    // selection when the row is part of it, otherwise select the row (or
    // only focus it without selectOnTap).
    final controller = widget.controller;
    final id = row.id;
    final focusNode = _focusNode;
    if (!focusNode.hasFocus && focusNode.canRequestFocus) {
      focusNode.requestFocus();
    }
    if (widget.selectOnTap && !controller.isSelected(id)) {
      controller.select(id);
    } else {
      controller.focus(id);
    }
    _handleSecondaryTap(controller.rows.rowOf(id) ?? row, globalPosition);
  }

  /// Shift+F10 without a menu builder: [DirectoryTreeView.onRowSecondaryTap]
  /// for the focused row, selected first as a secondary click would, at the
  /// row's bottom-start corner or the center of the view.
  void _secondaryTapFromKeyboard() {
    final callback = widget.onRowSecondaryTap;
    final controller = widget.controller;
    final row = controller.focusedRow;
    if (callback == null || row == null) return;
    final id = row.id;
    if (widget.selectOnTap && !controller.isSelected(id)) controller.select(id);
    final rows = controller.rows;
    final current = rows.rowOf(id) ?? row;
    final rect = controller.globalRowRect(rows.indexOfNode(id));
    final Offset position;
    if (rect != null && rect.isFinite) {
      final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
      position = rtl ? rect.bottomRight : rect.bottomLeft;
    } else {
      final box = context.findRenderObject();
      position = box is RenderBox && box.hasSize
          ? box.localToGlobal(box.size.center(Offset.zero))
          : Offset.zero;
    }
    callback(current, position);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final dragAndDrop = widget.dragAndDrop;
    final contextMenuBuilder = widget.contextMenuBuilder;
    final handlesSecondaryTap =
        widget.onRowSecondaryTap != null || contextMenuBuilder != null;

    Widget sliver = SliverDirectoryTree<T>(
      controller: controller,
      rowBuilder: widget.rowBuilder,
      rowDecorator: dragAndDrop == null
          ? null
          : DirectoryTreeDragAndDropScope.decorateRow<T>,
      checkboxMode: widget.checkboxMode,
      expandOnTap: widget.expandOnTap,
      selectOnTap: widget.selectOnTap,
      onRowTap: widget.onRowTap,
      onActivate: widget.onActivate,
      onRowSecondaryTap: handlesSecondaryTap ? _handleSecondaryTap : null,
      // With drag and drop a touch long-press belongs to the drag; the
      // scope reports a long-press that never moved instead.
      secondaryTapOnLongPress: dragAndDrop == null,
      levelSemanticsHint: widget.levelSemanticsHint,
    );
    // Always padded, so that a padding change keeps the sliver's state.
    sliver = SliverPadding(
      padding: widget.padding ?? EdgeInsets.zero,
      sliver: sliver,
    );
    final emptyBuilder = widget.emptyBuilder;
    final scrollController = _scrollController;
    Widget result = CustomScrollView(
      key: _scrollViewKey,
      controller: scrollController,
      physics: widget.physics,
      // The view adds its own scrollbar (or none), so the one desktop
      // platforms add by default must not appear as well.
      scrollBehavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false),
      slivers: <Widget>[
        sliver,
        if (_isEmpty && emptyBuilder != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Builder(builder: emptyBuilder),
          ),
      ],
    );
    if (widget.showScrollbar) {
      result = Scrollbar(controller: scrollController, child: result);
    }
    result = DirectoryTreeKeyboard<T>(
      key: _keyboardKey,
      controller: controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      shortcuts: widget.shortcuts,
      onActivate: widget.onActivate,
      checkboxMode: widget.checkboxMode,
      typeAhead: widget.typeAhead,
      selectionFollowsFocus: widget.selectionFollowsFocus,
      child: result,
    );
    if (contextMenuBuilder != null) {
      result = DirectoryTreeContextMenu<T>(
        key: _menuKey,
        controller: controller,
        builder: contextMenuBuilder,
        selectOnOpen: widget.selectOnTap,
        child: result,
      );
    } else if (widget.onRowSecondaryTap != null) {
      result = Actions(
        actions: <Type, Action<Intent>>{
          OpenTreeContextMenuIntent: _keyboardSecondaryTap,
        },
        child: result,
      );
    }
    if (dragAndDrop != null) {
      result = DirectoryTreeDragAndDropScope<T>(
        controller: controller,
        dragAndDrop: dragAndDrop,
        onLongPressWithoutDrag: handlesSecondaryTap
            ? _handleLongPressWithoutDrag
            : null,
        child: result,
      );
    }
    final semanticLabel = widget.semanticLabel;
    if (semanticLabel != null) {
      result = Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticLabel,
        child: result,
      );
    }
    return result;
  }
}

/// Calls [DirectoryTreeView.onRowSecondaryTap] for the focused row; enabled
/// while a row is focused, so the keys reach the widgets above otherwise.
class _KeyboardSecondaryTapAction<T> extends Action<OpenTreeContextMenuIntent> {
  _KeyboardSecondaryTapAction(this._view);

  final _DirectoryTreeViewState<T> _view;

  @override
  bool isEnabled(OpenTreeContextMenuIntent intent) =>
      _view.mounted &&
      _view.widget.onRowSecondaryTap != null &&
      _view.widget.controller.focusedIndex >= 0;

  @override
  Object? invoke(OpenTreeContextMenuIntent intent) {
    _view._secondaryTapFromKeyboard();
    return null;
  }
}
