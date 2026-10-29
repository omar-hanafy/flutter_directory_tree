import 'dart:async';
import 'dart:math' as math;

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/dnd/directory_tree_drop_details.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';

part 'drag_and_drop_row.dart';
part 'drag_feedback.dart';
part 'drag_session.dart';
part 'row_drag_recognizer.dart';

/// What the user may drag in a directory tree view, where it may drop, and
/// what a drop does.
///
/// Give it to a [DirectoryTreeDragAndDropScope] (the composed tree view
/// takes it as its `dragAndDrop` argument). The user drags a row to move its
/// node, or the whole selection when the row is selected, and drops it on a
/// directory row (that directory receives the nodes) or on a file row (the
/// file's directory receives them). See [DirectoryTreeDragAndDropScope] for
/// the gestures and what the view shows while dragging.
///
/// The package never moves data. `onDrop` receives a
/// [DirectoryTreeDropDetails]; move the files (or whatever the nodes stand
/// for), then give the controller the new tree, and the view keeps its
/// expansion, selection, and focus by [NodeId]:
///
/// ```dart
/// DirectoryTreeDragAndDrop<FileInfo>(
///   canDrop: (details) => details.target.data?.isWritable ?? false,
///   onDrop: (details) async {
///     await storage.move(details.nodes, into: details.target);
///     controller.tree = await storage.scan();
///   },
/// )
/// ```
@immutable
final class DirectoryTreeDragAndDrop<T> {
  /// Creates a drag and drop configuration.
  ///
  /// * `onDrop` is called once for each drop that the target accepts, after
  ///   the pointer is released, with the dragged nodes and the target
  ///   directory.
  /// * `canDrag` decides whether a drag may start, given the nodes it would
  ///   move (see [DirectoryTreeDropDetails.nodes]); with `null`, every drag
  ///   may start. It is asked once per drag: for a mouse, trackpad, or
  ///   stylus when the pointer moves past the drag slop (a refused drag
  ///   leaves the gesture to the other recognizers of the row), and for
  ///   touch when the long press is recognized (a refused drag shows no
  ///   feedback, and a release without moving still reaches
  ///   [DirectoryTreeDragAndDropScope.onLongPressWithoutDrag]).
  /// * `canDrop` decides whether the target directory accepts the dragged
  ///   nodes. A target that is one of the dragged nodes, or lies inside one,
  ///   is always refused without asking, since moving a directory into
  ///   itself is never valid. With `null`, a target that is already the
  ///   parent of every dragged node is refused too, because the drop would
  ///   change nothing. It is asked when the pointer reaches a new target,
  ///   again when the tree or this configuration changes during the drag,
  ///   and on release, but not on every pointer move. It must not change the
  ///   tree.
  /// * [autoExpandDelay]: see the property; 700 milliseconds by default.
  /// * `feedbackBuilder` builds the widget that follows the pointer, given
  ///   the dragged nodes, once per drag. The default shows the dragged row's
  ///   icon and label on a raised card, with the number of nodes when there
  ///   are several. The widget appears in the nearest [Overlay], with the
  ///   themes of the tree around it (captured with
  ///   [InheritedTheme.captureAll]) but not its [Material]: wrap it in one
  ///   for text styles. It is centered vertically on the pointer, with its
  ///   start edge 16 logical pixels before the pointer, and ignores pointer
  ///   events and semantics.
  const DirectoryTreeDragAndDrop({
    required this._onDrop,
    this._canDrag,
    this._canDrop,
    this.autoExpandDelay = const Duration(milliseconds: 700),
    this._feedbackBuilder,
  });

  // The callbacks take T as a parameter, so a public field would throw a
  // TypeError when read through a DirectoryTreeDragAndDrop<Object?>
  // reference to a more specific instance. They stay private and are
  // called from this library only.
  final ValueChanged<DirectoryTreeDropDetails<T>> _onDrop;
  final bool Function(List<TreeNode<T>> nodes)? _canDrag;
  final bool Function(DirectoryTreeDropDetails<T> details)? _canDrop;
  final Widget Function(BuildContext context, List<TreeNode<T>> nodes)?
  _feedbackBuilder;

  /// How long the pointer must stay over a collapsed directory row during a
  /// drag before that directory expands, so the user can reach the folders
  /// inside it.
  ///
  /// The directory expands with [DirectoryTreeController.expand], so a
  /// lazily loaded directory starts loading. A directory that is dragged, or
  /// lies inside a dragged directory, never expands. Expanded directories
  /// stay expanded after the drag. `null` turns automatic expansion off, and
  /// [Duration.zero] expands as soon as the pointer reaches the row.
  final Duration? autoExpandDelay;

  /// Whether [other] has the same callbacks (compared with `==`, so the same
  /// function objects) and the same [autoExpandDelay].
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    // The runtime types match, so the private callbacks of [other] have the
    // static types used here and reading them cannot fail a type check.
    return other is DirectoryTreeDragAndDrop<T> &&
        other._onDrop == _onDrop &&
        other._canDrag == _canDrag &&
        other._canDrop == _canDrop &&
        other.autoExpandDelay == autoExpandDelay &&
        other._feedbackBuilder == _feedbackBuilder;
  }

  /// A hash consistent with [operator ==].
  @override
  int get hashCode => Object.hash(
    _onDrop,
    _canDrag,
    _canDrop,
    autoExpandDelay,
    _feedbackBuilder,
  );

  /// A description with [autoExpandDelay] and the optional callbacks that
  /// are set, such as
  /// `DirectoryTreeDragAndDrop(autoExpandDelay: 0:00:00.700000, canDrop)`.
  @override
  String toString() {
    final parts = [
      'autoExpandDelay: $autoExpandDelay',
      if (_canDrag != null) 'canDrag',
      if (_canDrop != null) 'canDrop',
      if (_feedbackBuilder != null) 'feedbackBuilder',
    ];
    return 'DirectoryTreeDragAndDrop(${parts.join(', ')})';
  }
}

/// Adds drag and drop, configured by a [DirectoryTreeDragAndDrop], to the
/// rows of a directory tree view below it.
///
/// The scope holds the state of the drag in progress: the dragged nodes, the
/// target under the pointer, the timer that expands a hovered folder, and
/// the auto-scroller. Each row takes part through [decorateRow], which a
/// sliver of tree rows applies around every row as its `rowDecorator`
/// (`SliverDirectoryTree.rowDecorator`). The composed tree view sets all of
/// this up when it gets a [DirectoryTreeDragAndDrop].
///
/// ```dart
/// DirectoryTreeDragAndDropScope<Object?>(
///   controller: controller,
///   dragAndDrop: DirectoryTreeDragAndDrop(onDrop: moveNodes),
///   onLongPressWithoutDrag: (row, position) => openMenu(row, position),
///   child: CustomScrollView(
///     slivers: [
///       SliverDirectoryTree(
///         controller: controller,
///         rowDecorator: DirectoryTreeDragAndDropScope.decorateRow,
///         // The scope turns a touch long press into a drag, or calls
///         // onLongPressWithoutDrag when the finger did not move.
///         secondaryTapOnLongPress: false,
///       ),
///     ],
///   ),
/// )
/// ```
///
/// ## Gestures
///
/// * Mouse and trackpad: a drag with the primary button starts once the
///   pointer is more than 4 logical pixels from where it was pressed, so a
///   click with a little jitter stays a click. Other buttons never drag.
/// * Stylus: like the mouse, after the touch slop of the device. A stylus
///   swipe over the rows therefore drags instead of scrolling.
/// * Touch (and pointers of unknown kind): a drag starts with a long press
///   ([kLongPressTimeout]) that has not moved past the touch slop; the
///   feedback appears under the finger with a haptic click. A swipe that
///   moves earlier scrolls the list as usual. A long press released without
///   moving past the touch slop is not a drag: nothing is dropped, and
///   [onLongPressWithoutDrag] is called instead, which tree views use to
///   open the context menu. A sliver whose rows react to a long press
///   themselves (such as `SliverDirectoryTree` with `secondaryTapOnLongPress`)
///   would take the long press first, so turn that off inside this scope.
///
/// One drag runs at a time; other pointers are ignored while it lasts.
///
/// ## While dragging
///
/// The row under the pointer decides the target: a directory row targets
/// that directory, a file row targets the file's parent directory, and a
/// top-level file row or the space outside the rows targets nothing. While
/// the target accepts the drop (see [DirectoryTreeDragAndDrop]), the target
/// row and the visible rows of its subtree are tinted with
/// [DirectoryTreeThemeData.dropTargetColor]. A collapsed directory row under
/// the pointer expands after [DirectoryTreeDragAndDrop.autoExpandDelay].
/// Within one row extent of the start or end edge of the [Scrollable] around
/// the rows, or past it, the list scrolls, faster the closer the pointer
/// gets to the edge, as long as the pointer stays within the width of the
/// list. Releasing the pointer drops on the row under it at that moment.
///
/// Data changes during a drag are safe. When [controller] gets a new tree,
/// the dragged nodes are looked up again by id (a drag whose nodes all
/// disappeared ends without a drop) and the target is checked again. The
/// pressed row may scroll out of view and be disposed without ending the
/// drag.
///
/// ## Requirements
///
/// The rows must be below this widget and inside a [Scrollable] for the
/// automatic scrolling, with an [Overlay] above them for the drag feedback
/// (a [MaterialApp] provides one; without an overlay, drags work without
/// feedback). Drag and drop has no keyboard or screen reader gesture; offer
/// moves through a context menu as well.
class DirectoryTreeDragAndDropScope<T> extends StatefulWidget {
  /// Creates a drag and drop scope for the rows of [controller] in [child].
  const DirectoryTreeDragAndDropScope({
    super.key,
    required this.controller,
    required this.dragAndDrop,
    required this.child,
    this.onLongPressWithoutDrag,
  });

  /// The controller whose rows this scope makes draggable.
  ///
  /// It must be the controller of the [DirectoryTreeRowDetails] that the
  /// rows are decorated with. Replacing it ends a drag in progress without a
  /// drop.
  final DirectoryTreeController<T> controller;

  /// What may be dragged and dropped, and what a drop does.
  ///
  /// A new value takes effect at once, also for a drag in progress: the
  /// current target is checked again with the new `canDrop`.
  final DirectoryTreeDragAndDrop<T> dragAndDrop;

  /// The subtree that holds the rows, usually a [CustomScrollView].
  final Widget child;

  /// Called when a touch long press on a row ends without the finger moving
  /// past the touch slop, so no drag happened.
  ///
  /// Receives the row as it is when the finger lifts and the global position
  /// where the press started. Tree views use it to open the context menu
  /// that a long press opens without drag and drop. It is called whether or
  /// not the row may be dragged, never for a mouse, trackpad, or stylus, and
  /// not when the row disappeared during the press.
  final void Function(TreeRow<T> row, Offset globalPosition)?
  onLongPressWithoutDrag;

  /// Makes the row of [details] draggable and a drop target of the nearest
  /// [DirectoryTreeDragAndDropScope]; returns [child] wrapped.
  ///
  /// Use it as the [DirectoryTreeRowDecorator] of a sliver of tree rows
  /// inside the scope (`SliverDirectoryTree.rowDecorator`). The wrapper
  /// keeps the size of [child], paints the drop-target tint over it while
  /// the row is in the target's block, and only listens for pointers going
  /// down, so the row's own gestures keep working. A tint change does not
  /// rebuild [child]. [context] is not used.
  ///
  /// In debug mode, building the result throws a [FlutterError] when no
  /// scope is above it or the scope belongs to another controller than
  /// [details]; in release mode such a row takes no part in drag and drop.
  static Widget decorateRow<T>(
    BuildContext context,
    DirectoryTreeRowDetails<T> details,
    Widget child,
  ) => _DragAndDropRow(
    rowId: details.row.id,
    controller: details.controller,
    child: child,
  );

  @override
  State<DirectoryTreeDragAndDropScope<T>> createState() =>
      _DirectoryTreeDragAndDropScopeState<T>();

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
        DiagnosticsProperty<DirectoryTreeDragAndDrop<T>>(
          'dragAndDrop',
          dragAndDrop,
        ),
      )
      ..add(
        ObjectFlagProperty<void Function(TreeRow<T>, Offset)>.has(
          'onLongPressWithoutDrag',
          onLongPressWithoutDrag,
        ),
      );
  }
}

/// The nodes a drag would move and whether `canDrag` allows it.
typedef _PreparedDrag<T> = ({List<TreeNode<T>> nodes, bool draggable});

class _DirectoryTreeDragAndDropScopeState<T>
    extends State<DirectoryTreeDragAndDropScope<T>>
    implements _DragAndDropScopeHandle {
  late final _RowDragGestureRecognizer _recognizer = _RowDragGestureRecognizer(
    debugOwner: this,
    canStartPreciseDrag: _canStartPreciseDrag,
    onStartDrag: _startSession,
  );

  // The target directory whose block is tinted, or null. Rows listen to it.
  final ValueNotifier<NodeId?> _dropTarget = ValueNotifier<NodeId?>(null);

  _DragSession<T>? _session;

  // What _canStartPreciseDrag found for a press, reused when the drag of the
  // same press starts right after the arena accepted it.
  _RowPress? _preparedPress;
  _PreparedDrag<T>? _prepared;

  @override
  DirectoryTreeController<Object?> get controller => widget.controller;

  @override
  ValueListenable<NodeId?> get dropTarget => _dropTarget;

  @override
  bool isInDropBlock(NodeId rowId) {
    final target = _dropTarget.value;
    if (target == null) return false;
    return rowId == target || widget.controller.tree.isAncestor(target, rowId);
  }

  @override
  void addPointer(PointerDownEvent event, _DragAndDropRowState row) {
    if (_session != null) return;
    _recognizer.addRowPointer(
      event,
      _RowPress(
        row: row,
        rowId: row.widget.rowId,
        kind: event.kind,
        position: event.position,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recognizer.gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  @override
  void didUpdateWidget(DirectoryTreeDragAndDropScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final session = _session;
    if (session == null) return;
    if (!identical(oldWidget.controller, widget.controller)) {
      // The drag belongs to the rows of the old controller.
      _finishSession(session);
    } else if (oldWidget.dragAndDrop != widget.dragAndDrop) {
      session.configurationChanged();
    }
  }

  @override
  void dispose() {
    final session = _session;
    if (session != null) _finishSession(session);
    _recognizer.dispose();
    _dropTarget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _DragAndDropScopeMarker(scope: this, child: widget.child);

  /// Whether a mouse, trackpad, or stylus press that moved past the slop
  /// may start a drag; remembers what it computed for [_startSession].
  bool _canStartPreciseDrag(_RowPress press) {
    _preparedPress = null;
    _prepared = null;
    if (_session != null || !mounted || !press.row.mounted) return false;
    final prepared = _prepare(press.rowId);
    _preparedPress = press;
    _prepared = prepared;
    return prepared != null && prepared.draggable;
  }

  /// Starts the drag of [press] once its gesture won, or returns `null` to
  /// let the press go.
  Drag? _startSession(_RowPress press) {
    final reused = identical(_preparedPress, press) ? _prepared : null;
    _preparedPress = null;
    _prepared = null;
    // A drag needs the pressed row on screen: its context finds the
    // scrollable, the overlay, and the view.
    if (_session != null || !mounted || !press.row.mounted) return null;
    final prepared = reused ?? _prepare(press.rowId);
    if (prepared == null) return null;
    // A long press always starts a session, so that a release without
    // movement can report the long press; a refused drag is inert.
    if (!prepared.draggable && !press.startsWithLongPress) return null;
    final session = _DragSession<T>(
      scope: this,
      press: press,
      nodes: prepared.nodes,
      draggable: prepared.draggable,
    );
    _session = session;
    try {
      session.begin();
    } on Object {
      // A half-started session must not block every later drag.
      _finishSession(session);
      rethrow;
    }
    return session;
  }

  /// The nodes a drag from the row [rowId] moves, and whether `canDrag`
  /// allows it; `null` when the row's node is gone.
  _PreparedDrag<T>? _prepare(NodeId rowId) {
    final controller = widget.controller;
    final tree = controller.tree;
    final node = tree[rowId];
    if (node == null) return null;
    final nodes = controller.isSelected(rowId)
        ? _outermostNodes(tree, controller.selectedNodes)
        : List<TreeNode<T>>.unmodifiable(<TreeNode<T>>[node]);
    if (nodes.isEmpty) return null;
    final canDrag = widget.dragAndDrop._canDrag;
    return (nodes: nodes, draggable: canDrag == null || canDrag(nodes));
  }

  /// Ends [session] without a drop: removes its feedback, timers, and
  /// listeners, and clears the tint.
  void _finishSession(_DragSession<T> session) {
    session.dispose();
    if (identical(_session, session)) _session = null;
    _dropTarget.value = null;
  }
}

/// The nodes of [nodes] (in pre-order of [tree]) that are not inside an
/// earlier node of the list, as an unmodifiable list.
///
/// Pre-order keeps every subtree contiguous, so a node lies inside the last
/// kept node exactly when its index is below the end of that node's
/// subtree. Nodes the tree does not contain are skipped. O(nodes).
List<TreeNode<T>> _outermostNodes<T>(
  DirectoryTree<T> tree,
  Iterable<TreeNode<T>> nodes,
) {
  final result = <TreeNode<T>>[];
  var end = -1;
  for (final node in nodes) {
    final index = tree.indexOf(node.id);
    if (index < 0 || index < end) continue;
    result.add(node);
    end = index + tree.subtreeSizeOf(node.id);
  }
  return List<TreeNode<T>>.unmodifiable(result);
}
