import 'dart:async';

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_menu_details.dart';

/// Shows a Material context menu for the rows of a directory tree.
///
/// Wrap the tree with it: [child] is usually a scroll view with a
/// `SliverDirectoryTree` under a `DirectoryTreeKeyboard` (whose Shift+F10
/// and context menu key bindings invoke [OpenTreeContextMenuIntent]). Open
/// the menu of a row from the row's secondary tap with
/// [DirectoryTreeContextMenuState.open]; `DirectoryTreeView` does all of this
/// wiring when it is given a `contextMenuBuilder`.
///
/// [maybeOf] searches the ancestors of the context it is given, so call it
/// with a context below this widget, such as the one of a [Builder] inside
/// [child] (or keep a [GlobalKey] of the state):
///
/// ```dart
/// DirectoryTreeContextMenu<File>(
///   controller: controller,
///   builder: (context, details) => [
///     MenuItemButton(
///       onPressed: () => rename(details.row.node),
///       child: const Text('Rename'),
///     ),
///     MenuItemButton(
///       onPressed: () => delete(details.nodes),
///       child: const Text('Delete'),
///     ),
///   ],
///   // The Builder's context is below the menu host, so maybeOf finds it.
///   child: Builder(
///     builder: (context) => CustomScrollView(
///       slivers: [
///         SliverDirectoryTree<File>(
///           controller: controller,
///           onRowSecondaryTap: (row, globalPosition) =>
///               DirectoryTreeContextMenu.maybeOf<File>(
///                 context,
///               )?.open(row: row, globalPosition: globalPosition),
///         ),
///       ],
///     ),
///   ),
/// )
/// ```
///
/// ## Behavior
///
/// * With [selectOnOpen] (the default), opening selects the row when it is
///   not selected (with [DirectoryTreeController.select], which also
///   focuses it); without it, opening only focuses the row and leaves the
///   selection alone. Then [builder] runs with the
///   [DirectoryTreeMenuDetails]. An empty list opens no menu.
/// * The menu is a [MenuAnchor] menu styled by the ambient [MenuThemeData].
///   Its top-start corner is at the position (its top-left corner in
///   left-to-right text, its top-right corner in right-to-left text), and it
///   flips above the position when there is no room below.
/// * The menu takes keyboard focus on its first item, so the arrow keys move
///   between the items, Enter chooses one, and Escape closes the menu.
/// * Choosing an item, Escape, a tap outside the menu, and the user
///   scrolling [child] close the menu; keyboard focus then returns to the
///   widget that had it before the menu opened, unless the user has already
///   moved it elsewhere.
/// * One menu at a time: opening a menu while one is open replaces it.
/// * [OpenTreeContextMenuIntent], invoked from inside [child], opens the
///   menu of [DirectoryTreeController.focusedRow]. It selects (or focuses)
///   the row as [selectOnOpen] says, scrolls it into view, and opens the
///   menu after the next frame just below the row (see
///   [DirectoryTreeViewport.globalRowRect]), or at the center of this
///   widget when the row cannot be laid out. The action is enabled only
///   while the controller has a focused row, and an ancestor [Actions] can
///   override it.
///
/// The menu shows in the nearest [Overlay]. This widget sizes itself like
/// [child] and adds no semantics of its own.
///
/// ## On the web
///
/// Browsers show their own context menu for a right click, on top of this
/// menu, until the app calls `BrowserContextMenu.disableContextMenu()`
/// (from `package:flutter/services.dart`), for example in `main` when
/// `kIsWeb` is true. The package never calls it: the setting covers the
/// whole page, and while it is off, text fields show Flutter's own menu
/// instead of the browser's. `BrowserContextMenu.enableContextMenu()` turns
/// the browser menu back on.
class DirectoryTreeContextMenu<T> extends StatefulWidget {
  /// Creates a context menu host for the rows of [controller].
  const DirectoryTreeContextMenu({
    super.key,
    required this.controller,
    required this.builder,
    required this.child,
    this.selectOnOpen = true,
  });

  /// The controller whose rows the menus are for.
  ///
  /// Opening a menu selects through it, and the keyboard action opens the
  /// menu of its focused row. Replacing the controller closes an open menu.
  final DirectoryTreeController<T> controller;

  /// Builds the items of each menu; see [DirectoryTreeMenuBuilder].
  ///
  /// Called once per opened menu, with this widget's context.
  final DirectoryTreeMenuBuilder<T> builder;

  /// The tree the menus belong to, usually a scroll view that shows the rows
  /// of [controller].
  ///
  /// It gets the same constraints this widget gets, and this widget takes
  /// its size.
  final Widget child;

  /// Whether opening the menu of a row that is not selected selects it;
  /// true by default.
  ///
  /// When true, [DirectoryTreeContextMenuState.open] and the keyboard
  /// action select an unselected row with [DirectoryTreeController.select]
  /// first, so the menu acts on that row alone, as file managers do. When
  /// false, they only focus the row ([DirectoryTreeController.focus]) and
  /// never change the selection; the menu of an unselected row then acts
  /// on that row alone ([DirectoryTreeMenuDetails.nodes] is its node), and
  /// the menu of a selected row on the whole selection. Use false when
  /// clicks do not select either, such as a view with `selectOnTap: false`
  /// whose selection the user builds with checkboxes.
  final bool selectOnOpen;

  /// The state of the nearest [DirectoryTreeContextMenu] ancestor of
  /// [context] whose state is a `DirectoryTreeContextMenuState<T>`, or
  /// `null` when there is none.
  ///
  /// Use it from the tree's secondary tap handler, or from a menu item, to
  /// call [DirectoryTreeContextMenuState.open] or
  /// [DirectoryTreeContextMenuState.close]. A host for another node type is
  /// skipped (a `DirectoryTreeContextMenu<String>` is not found for `T` of
  /// `int`); `Object?` finds any host. Does not make [context] depend on the
  /// host, and walks up the ancestors in O(depth).
  static DirectoryTreeContextMenuState<T>? maybeOf<T>(BuildContext context) =>
      context.findAncestorStateOfType<DirectoryTreeContextMenuState<T>>();

  @override
  DirectoryTreeContextMenuState<T> createState() =>
      DirectoryTreeContextMenuState<T>();

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
        ObjectFlagProperty<DirectoryTreeMenuBuilder<T>>.has('builder', builder),
      )
      ..add(
        FlagProperty(
          'selectOnOpen',
          value: selectOnOpen,
          ifFalse: 'no select on open',
          defaultValue: true,
        ),
      );
  }
}

/// The state of a [DirectoryTreeContextMenu]: opens and closes its menu.
///
/// Get it with [DirectoryTreeContextMenu.maybeOf] (or a [GlobalKey]) and
/// call [open] from event handlers, such as the secondary tap of a row.
class DirectoryTreeContextMenuState<T>
    extends State<DirectoryTreeContextMenu<T>> {
  // The menu sits on a small anchor box over the child instead of wrapping
  // it. MenuAnchor flips a menu that does not fit below its anchor to above
  // the anchor's top edge, which must be the clicked point or the focused
  // row, not the top of the whole tree. Keeping the tree outside the anchor
  // also keeps it outside the menu's tap region group, so a click on the
  // tree is a tap outside the menu and closes it.
  final MenuController _menuController = MenuController();

  // The parent of every focus node of the menu; it finds the menu's focus
  // scope and tells whether keyboard focus is inside the menu.
  final FocusNode _menuFocus = FocusNode(
    debugLabel: 'DirectoryTreeContextMenu',
    canRequestFocus: false,
    skipTraversal: true,
  );

  late final Action<OpenTreeContextMenuIntent> _openAction =
      Action<OpenTreeContextMenuIntent>.overridable(
        defaultAction: _OpenFocusedRowMenuAction<T>(this),
        context: context,
      );

  // The menu that should be showing: null once it is closed or closing.
  _MenuRequest? _menu;

  // The menu the MenuAnchor shows, from its onOpen to its onClose.
  _MenuRequest? _showing;

  // Whether the MenuAnchor started closing and has not hidden yet. A
  // non-animated MenuAnchor hides in a microtask after a close request, so
  // a menu shown before that would be hidden by it; see _show.
  bool _anchorClosing = false;

  // A session runs from opening a menu while none is showing to the moment
  // the last menu closes; replacing a menu continues the session.
  bool _sessionActive = false;

  // The focus to restore when the session ends.
  FocusNode? _previousFocus;

  /// Whether a menu is open: true from an [open] call whose builder returned
  /// items until [close] or until the menu starts closing by itself (an item
  /// chosen, Escape, a tap outside).
  ///
  /// Already true in the moment between [open] and the frame that shows the
  /// menu, and already false while a closing menu is still on screen.
  bool get isOpen => _menu != null;

  /// Opens the context menu of [row] at [globalPosition], replacing a menu
  /// that is open.
  ///
  /// First selects [row] with [DirectoryTreeController.select] when it is
  /// not selected (which also focuses it and scrolls it into view), or,
  /// without [DirectoryTreeContextMenu.selectOnOpen], focuses it with
  /// [DirectoryTreeController.focus] when it is not focused. Then
  /// calls [DirectoryTreeContextMenu.builder] with the
  /// [DirectoryTreeMenuDetails]: the controller's current row for the node,
  /// [DirectoryTreeController.selectedNodes] as the nodes when the row is
  /// selected (else only the row's node), and [globalPosition]. When the
  /// builder returns items, the menu shows them with its top-start corner at
  /// [globalPosition] (above it when there is no room below) and moves
  /// keyboard focus to its first item. When it returns no items, no menu
  /// opens and an open menu closes.
  ///
  /// [globalPosition] is in global coordinates, such as
  /// `TapUpDetails.globalPosition`. Does nothing when [row]'s node is not in
  /// the controller's tree (a stale row) or this state is not mounted. The
  /// menu appears in the next frame. Call it from event handlers, never
  /// during a build.
  void open({required TreeRow<T> row, required Offset globalPosition}) {
    final anchor = Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0);
    _openAt(row, () => (position: globalPosition, anchor: anchor));
  }

  /// Closes the open menu, if any.
  ///
  /// Keyboard focus then returns to the widget that had it before the menu
  /// opened, unless focus has already left the menu or that widget is gone.
  /// [isOpen] is false right away; the menu disappears in the next frame.
  /// Does nothing when no menu is open.
  void close() {
    if (_menu == null) return;
    _menu = null;
    if (_showing != null) {
      // The MenuAnchor hides the menu soon; its onClose ends the session.
      _menuController.close();
    } else {
      // Nothing showed yet: the show that open scheduled finds no menu.
      _endSession();
    }
  }

  @override
  void didUpdateWidget(DirectoryTreeContextMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An open menu holds details of the old controller.
    if (!identical(oldWidget.controller, widget.controller)) close();
  }

  @override
  void dispose() {
    _menu = null;
    _showing = null;
    _previousFocus = null;
    _menuFocus.dispose();
    super.dispose();
  }

  /// Selects or focuses [row] as [DirectoryTreeContextMenu.selectOnOpen]
  /// says, builds the menu, and schedules showing it at the place [place]
  /// computes once the selection is updated.
  void _openAt(
    TreeRow<T> row,
    ({Offset position, Rect anchor}) Function() place,
  ) {
    if (!mounted) return;
    final controller = widget.controller;
    final id = row.id;
    if (!controller.tree.contains(id)) return;
    if (widget.selectOnOpen) {
      if (!controller.isSelected(id)) controller.select(id);
    } else if (controller.focusedId != id) {
      controller.focus(id);
    }
    final current = controller.rows.rowOf(id) ?? row;
    final nodes = controller.isSelected(id)
        ? controller.selectedNodes
        : List<TreeNode<T>>.unmodifiable(<TreeNode<T>>[current.node]);
    final placement = place();
    final details = DirectoryTreeMenuDetails<T>(
      controller: controller,
      row: current,
      nodes: nodes,
      globalPosition: placement.position,
    );
    final items = widget.builder(context, details);
    if (items.isEmpty) {
      close();
      return;
    }
    if (!_sessionActive) {
      // A click that opens the menu may have asked to focus the tree just
      // before; that focus belongs to the time before the menu.
      FocusManager.instance.applyFocusChangesIfNeeded();
      _previousFocus = FocusManager.instance.primaryFocus;
      _sessionActive = true;
    }
    final anchor = _globalToLocal(placement.anchor);
    setState(() {
      _menu = _MenuRequest(
        items: List<Widget>.unmodifiable(items),
        anchor: anchor,
      );
    });
    // A microtask runs after everything this event still does, such as the
    // menu's own outside-tap handling closing the previous menu.
    scheduleMicrotask(_show);
  }

  /// Opens the menu of the focused row below that row, or at the center of
  /// this widget when no viewport knows the row's bounds.
  ///
  /// Selecting or focusing the row (as [DirectoryTreeContextMenu.selectOnOpen]
  /// says) and showing it may scroll, and a row's bounds are known only
  /// once it is laid out, so the menu opens after the next frame.
  void _openForFocusedRow() {
    final controller = widget.controller;
    final row = controller.focusedRow;
    if (row == null) return;
    final id = row.id;
    if (widget.selectOnOpen && !controller.isSelected(id)) {
      controller.select(id);
    } else {
      unawaited(controller.ensureVisible(id));
    }
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        // Nothing when the host, its controller, or the focus changed in
        // the meantime.
        if (!mounted ||
            !identical(widget.controller, controller) ||
            controller.focusedId != id) {
          return;
        }
        final current = controller.rows.rowOf(id);
        if (current != null) _openAt(current, _focusedRowPlacement);
      }, debugLabel: 'DirectoryTreeContextMenu.openForFocusedRow')
      ..ensureVisualUpdate();
  }

  /// Just below the focused row, at its bottom-start corner, or at the
  /// center of this widget when no viewport has the row laid out.
  ({Offset position, Rect anchor}) _focusedRowPlacement() {
    final controller = widget.controller;
    final rect = controller.globalRowRect(controller.focusedIndex);
    if (rect == null || !rect.isFinite) return _centerPlacement();
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return (position: rtl ? rect.bottomRight : rect.bottomLeft, anchor: rect);
  }

  /// Shows the requested menu, unless it shows already or the previous menu
  /// is still closing (its onClose calls this again).
  void _show() {
    final menu = _menu;
    if (!mounted ||
        menu == null ||
        identical(menu, _showing) ||
        _anchorClosing) {
      return;
    }
    // Replaces a showing menu at once: its onClose comes first, then onOpen.
    _menuController.open();
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => _focusFirstItem(menu),
      debugLabel: 'DirectoryTreeContextMenu.focusFirstItem',
    );
  }

  /// Moves keyboard focus to the first focusable item of [menu] once it is
  /// laid out, or to the menu itself when no item can take focus, so the
  /// menu's arrow keys and Escape work.
  void _focusFirstItem(_MenuRequest menu) {
    if (!mounted || !identical(menu, _menu) || !identical(menu, _showing)) {
      return;
    }
    final scope = _findMenuScope();
    if (scope == null) return;
    final scopeContext = scope.context;
    final policy =
        (scopeContext == null
            ? null
            : FocusTraversalGroup.maybeOf(scopeContext)) ??
        ReadingOrderTraversalPolicy();
    (policy.findFirstFocus(scope, ignoreCurrentFocus: true) ?? scope)
        .requestFocus();
  }

  /// The focus scope of the menu panel: the outermost scope below
  /// [_menuFocus] (submenus have their own scopes further down).
  FocusScopeNode? _findMenuScope() {
    final pending = List<FocusNode>.of(_menuFocus.children);
    for (var i = 0; i < pending.length; i++) {
      final node = pending[i];
      if (node is FocusScopeNode) return node;
      pending.addAll(node.children);
    }
    return null;
  }

  void _handleMenuOpened() {
    _showing = _menu;
  }

  void _handleMenuStatusChanged(AnimationStatus status) {
    if (status.isForwardOrCompleted) return;
    // The MenuAnchor started closing: an item, Escape, a tap outside, a
    // scroll, a resize, or close().
    if (_menuController.isOpen) _anchorClosing = true;
    // When the menu that closes is the requested one, it is closed for
    // callers right away, though it stays on screen until it hides.
    if (_menu != null && identical(_menu, _showing)) _menu = null;
  }

  void _handleMenuClosed() {
    final closed = _showing;
    _showing = null;
    _anchorClosing = false;
    final pending = _menu;
    if (pending != null && !identical(pending, closed)) {
      // A newer menu replaces the one that closed; the session goes on.
      scheduleMicrotask(_show);
      return;
    }
    _menu = null;
    _endSession();
  }

  /// Ends the session: drops the menu's items and returns keyboard focus to
  /// the widget that had it before the first menu opened, when focus is
  /// still inside the menu (the user did not move it elsewhere).
  void _endSession() {
    final previous = _previousFocus;
    _previousFocus = null;
    _sessionActive = false;
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      // Rebuild without the closed menu's items, which hold its nodes.
      setState(() {});
    }
    // A node out of the focus tree would take focus whenever it is attached
    // again, so only a node that is still in the tree gets it back.
    if (previous == null ||
        previous.parent == null ||
        !(previous.context?.mounted ?? false) ||
        !previous.canRequestFocus) {
      return;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || _menuFocus.hasFocus) previous.requestFocus();
  }

  bool _handleUserScroll(UserScrollNotification notification) {
    // Like a MenuAnchor inside a scroll view: the anchored row moves away.
    if (notification.direction != ScrollDirection.idle && isOpen) close();
    return false;
  }

  /// The center of this widget, as a menu position and a zero-size anchor.
  ({Offset position, Rect anchor}) _centerPlacement() {
    final box = context.findRenderObject();
    final center = box is RenderBox && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset.zero;
    return (
      position: center,
      anchor: Rect.fromLTWH(center.dx, center.dy, 0, 0),
    );
  }

  /// [rect] in the coordinates of this widget's box; unchanged before the
  /// first layout.
  Rect _globalToLocal(Rect rect) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return rect;
    return MatrixUtils.inverseTransformRect(box.getTransformTo(null), rect);
  }

  @override
  Widget build(BuildContext context) {
    // A closing menu keeps its items and place until it hides.
    final shown = _menu ?? _showing;
    return Actions(
      actions: <Type, Action<Intent>>{OpenTreeContextMenuIntent: _openAction},
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: <Widget>[
          NotificationListener<UserScrollNotification>(
            onNotification: _handleUserScroll,
            child: widget.child,
          ),
          // The anchor box is never hit: taps go to the tree below it.
          Positioned.fromRect(
            rect: shown?.anchor ?? Rect.zero,
            child: Focus(
              focusNode: _menuFocus,
              canRequestFocus: false,
              skipTraversal: true,
              includeSemantics: false,
              child: MenuAnchor(
                controller: _menuController,
                style: _menuStyle,
                onOpen: _handleMenuOpened,
                onClose: _handleMenuClosed,
                onAnimationStatusChanged: _handleMenuStatusChanged,
                menuChildren: shown?.items ?? const <Widget>[],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Pins the placement of a context menu: the theme's alignment is meant for
  // menu bars and could move the menu away from the pointer.
  static const MenuStyle _menuStyle = MenuStyle(
    alignment: AlignmentDirectional.bottomStart,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('isOpen', value: isOpen, ifTrue: 'open'));
  }
}

/// One requested menu: its items and its anchor in the coordinates of the
/// host's box. Compared by identity to tell menus apart.
final class _MenuRequest {
  _MenuRequest({required this.items, required this.anchor});

  final List<Widget> items;
  final Rect anchor;
}

/// Opens the menu of the focused row; enabled while a row is focused.
class _OpenFocusedRowMenuAction<T> extends Action<OpenTreeContextMenuIntent> {
  _OpenFocusedRowMenuAction(this._host);

  final DirectoryTreeContextMenuState<T> _host;

  @override
  bool isEnabled(OpenTreeContextMenuIntent intent) =>
      _host.mounted && _host.widget.controller.focusedIndex >= 0;

  @override
  Object? invoke(OpenTreeContextMenuIntent intent) {
    _host._openForFocusedRow();
    return null;
  }
}
