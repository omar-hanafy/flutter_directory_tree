part of 'directory_tree_drag_and_drop.dart';

/// The auto-scroll speed per pixel of overlap with the edge zone, as in
/// [SliverReorderableList]: up to 20 pixels per 20 milliseconds.
const double _kAutoScrollVelocityScalar = 50;

/// The depth of the auto-scroll edge zone when the pressed row has no size.
const double _kDefaultEdgeZone = 36;

/// One drag of rows, from the moment its gesture won to the drop or the
/// cancellation.
///
/// The scope's recognizer sends the pointer's movement here directly, so a
/// session keeps working when the pressed row scrolls out of view and its
/// widget is disposed. The session finds the row under the pointer by hit
/// testing on every pointer move and, after the rows moved under a still
/// pointer (scrolling, expansion, a new tree), once after the next frame.
///
/// While the list scrolls, [Scrollable] ignores pointers over its content,
/// so a hit test of the whole view passes over the rows; the session then
/// hit tests the list's viewport directly (see [_rowIdAt]) and tests again
/// when the scrolling stops.
final class _DragSession<T> implements Drag {
  _DragSession({
    required this.scope,
    required this.press,
    required List<TreeNode<T>> nodes,
    required this.draggable,
  }) : controller = scope.widget.controller,
       _position = press.position,
       _moved = !press.startsWithLongPress {
    _tree = controller.tree;
    _setNodes(nodes);
  }

  final _DirectoryTreeDragAndDropScopeState<T> scope;
  final _RowPress press;
  final DirectoryTreeController<T> controller;

  /// Whether `canDrag` allowed the drag. A touch session that it refused
  /// shows nothing and drops nothing; it only waits to report a long press
  /// released without movement.
  final bool draggable;

  // The tree that _nodes come from.
  late DirectoryTree<T> _tree;
  late List<TreeNode<T>> _nodes;
  late Set<NodeId> _draggedIds;
  // The parent of every dragged node when they share one, for the default
  // canDrop.
  NodeId? _commonParent;

  Offset _position;
  // Whether the pointer moved past the touch slop since it went down; a
  // touch session only targets, scrolls, and drops once it has.
  bool _moved;
  bool _ended = false;

  int? _viewId;
  TextDirection _textDirection = TextDirection.ltr;
  OverlayState? _overlay;
  OverlayEntry? _feedbackEntry;
  Widget? _feedback;

  ScrollableState? _scrollable;
  ScrollPosition? _scrollPosition;
  // The viewport around the rows, below the IgnorePointer of the Scrollable.
  RenderBox? _viewport;
  EdgeDraggingAutoScroller? _autoScroller;
  double _edgeZone = _kDefaultEdgeZone;

  NodeId? _targetId;
  bool _targetAccepted = false;
  // Set when the tree or the configuration changed, so the next target
  // update asks canDrop again even for the same target.
  bool _targetStale = true;
  NodeId? _expandId;
  Timer? _expandTimer;
  bool _refreshScheduled = false;

  DirectoryTreeDragAndDrop<T> get _config => scope.widget.dragAndDrop;

  /// Shows the feedback and prepares hit testing and auto-scrolling, from
  /// the pressed row's context.
  void begin() {
    controller.addListener(_handleControllerChanged);
    if (!draggable) return;
    final context = press.row.context;
    _viewId = View.of(context).viewId;
    _textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      _scrollable = scrollable;
      // Rows move under a still pointer while the list scrolls, whoever
      // scrolls it (the auto-scroller, a mouse wheel, the app), and the
      // hit test changes when the scrolling stops.
      final position = scrollable.position
        ..addListener(_scheduleRefresh)
        ..isScrollingNotifier.addListener(_scheduleRefresh);
      _scrollPosition = position;
      _autoScroller = EdgeDraggingAutoScroller(
        scrollable,
        onScrollViewScrolled: _handleAutoScrolled,
        velocityScalar: _kAutoScrollVelocityScalar,
      );
      final box = context.findRenderObject();
      if (RenderAbstractViewport.maybeOf(box) case final RenderBox viewport) {
        _viewport = viewport;
      }
      if (box is RenderBox && box.hasSize) {
        final extent = position.axis == Axis.vertical
            ? box.size.height
            : box.size.width;
        if (extent > 0) _edgeZone = extent;
      }
    }
    _showFeedback(context);
    if (press.startsWithLongPress) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  /// Asks canDrop again for the current target, after the scope got a new
  /// configuration.
  void configurationChanged() {
    _targetStale = true;
    _scheduleRefresh();
  }

  @override
  void update(DragUpdateDetails details) {
    if (_ended) return;
    // The first update carries the movement since the pointer went down,
    // with the position where it went down, so positions are accumulated
    // from the deltas (as Draggable does).
    _position += details.delta;
    if (!_moved) {
      final slop = computeHitSlop(
        press.kind,
        scope._recognizer.gestureSettings,
      );
      _moved = (_position - press.position).distance > slop;
    }
    if (!draggable) return;
    _feedbackEntry?.markNeedsBuild();
    if (!_moved) return;
    _updateTarget();
    _autoScroll();
  }

  @override
  void end(DragEndDetails details) {
    if (_ended) return;
    if (!_moved) {
      // A long press without a drag: report it, drop nothing.
      final callback = scope.widget.onLongPressWithoutDrag;
      final row = controller.rows.rowOf(press.rowId);
      scope._finishSession(this);
      if (callback != null && row != null) callback(row, press.position);
      return;
    }
    final drop = draggable ? _dropAt(_position) : null;
    final onDrop = _config._onDrop;
    // Clean up first: the handler usually replaces the tree, and it may
    // throw.
    scope._finishSession(this);
    if (drop != null) onDrop(drop);
  }

  @override
  void cancel() {
    if (!_ended) scope._finishSession(this);
  }

  /// Removes the feedback, timers, and listeners. Idempotent; the scope
  /// calls it through [_DirectoryTreeDragAndDropScopeState._finishSession].
  void dispose() {
    if (_ended) return;
    _ended = true;
    controller.removeListener(_handleControllerChanged);
    final position = _scrollPosition;
    if (position != null) {
      position
        ..removeListener(_scheduleRefresh)
        ..isScrollingNotifier.removeListener(_scheduleRefresh);
    }
    _autoScroller?.stopAutoScroll();
    _expandTimer?.cancel();
    _expandTimer = null;
    final entry = _feedbackEntry;
    _feedbackEntry = null;
    if (entry != null) {
      entry
        ..remove()
        ..dispose();
    }
  }

  // -------------------------------------------------------------------
  // Nodes
  // -------------------------------------------------------------------

  void _setNodes(List<TreeNode<T>> nodes) {
    _nodes = nodes;
    _draggedIds = <NodeId>{for (final node in nodes) node.id};
    var parent = nodes.isEmpty ? null : nodes.first.parent;
    for (final node in nodes) {
      if (node.parent != parent) {
        parent = null;
        break;
      }
    }
    _commonParent = parent;
  }

  void _handleControllerChanged() {
    if (_ended) return;
    final tree = controller.tree;
    if (!identical(tree, _tree)) {
      _tree = tree;
      // Look the dragged nodes up again by id: a refresh replaces every node
      // object, and a node may be gone.
      final nodes = <TreeNode<T>>[for (final node in _nodes) ?tree[node.id]]
        ..sort((a, b) => tree.indexOf(a.id).compareTo(tree.indexOf(b.id)));
      if (nodes.isEmpty) {
        scope._finishSession(this);
        return;
      }
      _setNodes(_outermostNodes(tree, nodes));
      _targetStale = true;
    }
    _scheduleRefresh();
  }

  /// Whether [id] is a dragged node or inside one. O(depth).
  bool _isDraggedOrInside(DirectoryTree<T> tree, NodeId id) {
    if (_draggedIds.contains(id)) return true;
    for (final ancestor in tree.ancestorsOf(id)) {
      if (_draggedIds.contains(ancestor.id)) return true;
    }
    return false;
  }

  /// The drop of the dragged nodes on [target], or `null` when the target
  /// refuses them.
  DirectoryTreeDropDetails<T>? _acceptedDrop(
    DirectoryTree<T> tree,
    DirectoryNode<T> target,
  ) {
    if (_nodes.isEmpty || _isDraggedOrInside(tree, target.id)) return null;
    final canDrop = _config._canDrop;
    if (canDrop == null && target.id == _commonParent) return null;
    final details = DirectoryTreeDropDetails<T>(nodes: _nodes, target: target);
    return canDrop == null || canDrop(details) ? details : null;
  }

  // -------------------------------------------------------------------
  // Targets
  // -------------------------------------------------------------------

  /// The id of the decorated row of this scope under [position], or `null`.
  ///
  /// A hit test of the whole view respects everything painted over the rows
  /// (pinned headers, overlays, outer scroll views). While the list scrolls,
  /// its [Scrollable] ignores pointers over the rows, so that test finds
  /// none; the viewport is then hit tested on its own, which still respects
  /// the slivers inside it.
  NodeId? _rowIdAt(Offset position) {
    final viewId = _viewId;
    if (viewId == null) return null;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    final hit = _rowIdIn(result.path);
    if (hit != null) return hit;
    final viewport = _viewport;
    final scrolling = _scrollPosition?.isScrollingNotifier.value ?? false;
    if (!scrolling || viewport == null || !viewport.attached) return null;
    if (!viewport.hasSize) return null;
    final viewportResult = BoxHitTestResult();
    viewport.hitTest(
      viewportResult,
      position: viewport.globalToLocal(position),
    );
    return _rowIdIn(viewportResult.path);
  }

  /// The id of the first decorated row of this scope in [path].
  NodeId? _rowIdIn(Iterable<HitTestEntry> path) {
    for (final entry in path) {
      final target = entry.target;
      if (target is! RenderMetaData) continue;
      final row = target.metaData;
      if (row is _DragAndDropRowState &&
          row.mounted &&
          identical(row._scope, scope) &&
          row._attached) {
        return row.widget.rowId;
      }
    }
    return null;
  }

  /// The directory a drop on the row of [node] goes to: the node itself
  /// for a directory, the parent for a file.
  static NodeId? _targetIdOf<T>(TreeNode<T>? node) => switch (node) {
    DirectoryNode<T>(:final id) => id,
    FileNode<T>(:final parent) => parent,
    null => null,
  };

  /// Hit tests the pointer position and updates the tint and the
  /// auto-expand timer.
  void _updateTarget() {
    final tree = controller.tree;
    final rowId = _rowIdAt(_position);
    final node = rowId == null ? null : tree[rowId];
    final targetId = _targetIdOf(node);
    if (_targetStale || targetId != _targetId) {
      _targetStale = false;
      _targetId = targetId;
      final target = targetId == null ? null : tree[targetId];
      _targetAccepted =
          target is DirectoryNode<T> && _acceptedDrop(tree, target) != null;
    }
    scope._dropTarget.value = _targetAccepted ? _targetId : null;
    _updateAutoExpand(tree, node);
  }

  void _updateAutoExpand(DirectoryTree<T> tree, TreeNode<T>? node) {
    final expandId =
        node is DirectoryNode<T> &&
            !controller.isExpanded(node.id) &&
            controller.isExpandable(node.id) &&
            !_isDraggedOrInside(tree, node.id)
        ? node.id
        : null;
    if (expandId == _expandId) return;
    _expandTimer?.cancel();
    _expandTimer = null;
    _expandId = expandId;
    final delay = _config.autoExpandDelay;
    if (expandId != null && delay != null) {
      _expandTimer = Timer(delay, _autoExpand);
    }
  }

  void _autoExpand() {
    _expandTimer = null;
    final id = _expandId;
    if (_ended || id == null || controller.isExpanded(id)) return;
    // The controller notifies, which schedules a new hit test once the new
    // rows are laid out.
    controller.expand(id);
  }

  /// Hit tests again after the next frame, when the rows under a still
  /// pointer may have moved.
  void _scheduleRefresh() {
    if (_ended || !_moved || !draggable || _refreshScheduled) return;
    _refreshScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _refreshScheduled = false;
        if (!_ended) _updateTarget();
      }, debugLabel: 'DirectoryTreeDragAndDropScope.refreshTarget')
      ..ensureVisualUpdate();
  }

  /// The accepted drop at [position], checked afresh, or `null`.
  DirectoryTreeDropDetails<T>? _dropAt(Offset position) {
    final tree = controller.tree;
    final rowId = _rowIdAt(position);
    final targetId = _targetIdOf(rowId == null ? null : tree[rowId]);
    final target = targetId == null ? null : tree[targetId];
    if (target is! DirectoryNode<T>) return null;
    return _acceptedDrop(tree, target);
  }

  // -------------------------------------------------------------------
  // Auto-scroll
  // -------------------------------------------------------------------

  /// Scrolls when the pointer is within one row extent of the start or end
  /// edge of the list (or past it) and within the list's cross extent.
  void _autoScroll() {
    final scroller = _autoScroller;
    final scrollable = _scrollable;
    if (scroller == null || scrollable == null) return;
    if (!scrollable.mounted) {
      scroller.stopAutoScroll();
      return;
    }
    final box = scrollable.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final vertical = scrollable.position.axis == Axis.vertical;
    final cross = vertical ? _position.dx : _position.dy;
    final crossStart = vertical ? rect.left : rect.top;
    final crossEnd = vertical ? rect.right : rect.bottom;
    if (cross < crossStart || cross > crossEnd) {
      scroller.stopAutoScroll();
      return;
    }
    // EdgeDraggingAutoScroller scrolls by how far this box reaches past an
    // edge; centering it on the pointer makes the zone one box half (one
    // row extent) deep. It must fit in the list, so it stays at most half
    // of the list's extent.
    final extent = vertical ? rect.height : rect.width;
    final zone = math.min(_edgeZone, extent / 4);
    scroller.startAutoScrollIfNecessary(
      Rect.fromCenter(
        center: _position,
        width: vertical ? 0 : zone * 2,
        height: vertical ? zone * 2 : 0,
      ),
    );
  }

  void _handleAutoScrolled() {
    if (_ended) {
      _autoScroller?.stopAutoScroll();
      return;
    }
    // The scroller keeps the pointer box relative to the content; give it
    // the box at the current scroll offset before its next step.
    _autoScroll();
  }

  // -------------------------------------------------------------------
  // Feedback
  // -------------------------------------------------------------------

  void _showFeedback(BuildContext context) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final nodes = _nodes;
    final builder = _config._feedbackBuilder;
    final feedback = builder == null
        ? _DefaultDragFeedback(node: _primaryNode(), count: nodes.length)
        : Builder(builder: (context) => builder(context, nodes));
    _overlay = overlay;
    _feedback = InheritedTheme.captureAll(
      context,
      Directionality(
        textDirection: _textDirection,
        child: ExcludeSemantics(child: feedback),
      ),
      to: overlay.context,
    );
    final entry = OverlayEntry(builder: _buildFeedback);
    _feedbackEntry = entry;
    overlay.insert(entry);
  }

  /// The dragged node that holds the pressed row, which the default
  /// feedback shows.
  TreeNode<T> _primaryNode() {
    final tree = controller.tree;
    for (final node in _nodes) {
      if (node.id == press.rowId || tree.isAncestor(node.id, press.rowId)) {
        return node;
      }
    }
    return _nodes.first;
  }

  Widget _buildFeedback(BuildContext context) {
    final box = _overlay?.context.findRenderObject();
    final pointer = box is RenderBox && box.hasSize
        ? box.globalToLocal(_position)
        : _position;
    return IgnorePointer(
      child: CustomSingleChildLayout(
        delegate: _DragFeedbackLayout(
          pointer: pointer,
          textDirection: _textDirection,
        ),
        child: _feedback,
      ),
    );
  }
}
