part of 'directory_tree_drag_and_drop.dart';

/// What a decorated row needs from its scope, without the scope's type
/// argument: rows pass and receive only ids, so a row never calls a method
/// whose parameters mention `T`.
abstract interface class _DragAndDropScopeHandle {
  /// The controller of the scope, compared by identity with the row's.
  DirectoryTreeController<Object?> get controller;

  /// The accepted target directory of the drag in progress, or `null`.
  ValueListenable<NodeId?> get dropTarget;

  /// Whether the row [rowId] is the drop target or inside it. O(1).
  bool isInDropBlock(NodeId rowId);

  /// Routes a pointer that went down on [row] to the drag recognizer.
  void addPointer(PointerDownEvent event, _DragAndDropRowState row);
}

/// Makes the scope reachable from the rows below it.
class _DragAndDropScopeMarker extends InheritedWidget {
  const _DragAndDropScopeMarker({required this.scope, required super.child});

  final _DragAndDropScopeHandle scope;

  @override
  bool updateShouldNotify(_DragAndDropScopeMarker oldWidget) =>
      !identical(oldWidget.scope, scope);
}

/// The widget that [DirectoryTreeDragAndDropScope.decorateRow] puts around
/// a row: a hit-test marker for drop targets, a pointer listener that starts
/// drags, and the drop-target tint.
class _DragAndDropRow extends StatefulWidget {
  const _DragAndDropRow({
    required this.rowId,
    required this.controller,
    required this.child,
  });

  final NodeId rowId;
  final DirectoryTreeController<Object?> controller;
  final Widget child;

  @override
  State<_DragAndDropRow> createState() => _DragAndDropRowState();
}

class _DragAndDropRowState extends State<_DragAndDropRow> {
  _DragAndDropScopeHandle? _scope;
  bool _inDropBlock = false;

  /// Whether this row belongs to its scope: there is one, for the same
  /// controller.
  bool get _attached {
    final scope = _scope;
    return scope != null && identical(scope.controller, widget.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DragAndDropScopeMarker>()
        ?.scope;
    if (!identical(scope, _scope)) {
      _scope?.dropTarget.removeListener(_handleDropTargetChanged);
      _scope = scope;
      scope?.dropTarget.addListener(_handleDropTargetChanged);
    }
    _inDropBlock = _computeInDropBlock();
  }

  @override
  void didUpdateWidget(_DragAndDropRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _inDropBlock = _computeInDropBlock();
  }

  @override
  void dispose() {
    _scope?.dropTarget.removeListener(_handleDropTargetChanged);
    super.dispose();
  }

  bool _computeInDropBlock() =>
      _attached && _scope!.isInDropBlock(widget.rowId);

  // Every mounted row listens, so a target change costs one O(1) check per
  // built row and rebuilds only the rows whose tint changed.
  void _handleDropTargetChanged() {
    final inDropBlock = _computeInDropBlock();
    if (inDropBlock != _inDropBlock) {
      setState(() => _inDropBlock = inDropBlock);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_attached) _scope!.addPointer(event, this);
  }

  @override
  Widget build(BuildContext context) {
    assert(_debugCheckScope(), 'decorateRow needs a matching scope');
    final color = _inDropBlock
        ? DirectoryTreeTheme.of(context).dropTargetColor
        : null;
    // The structure never changes with the tint, so the row's own subtree
    // keeps its state; translucent hit testing lets a drag start, and a drop
    // land, on parts of the row that its child does not paint.
    return MetaData(
      metaData: this,
      behavior: HitTestBehavior.translucent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: color == null
              ? const BoxDecoration()
              : BoxDecoration(color: color),
          child: widget.child,
        ),
      ),
    );
  }

  bool _debugCheckScope() {
    final scope = _scope;
    if (scope == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          'DirectoryTreeDragAndDropScope.decorateRow was used without a '
          'DirectoryTreeDragAndDropScope above the row.',
        ),
        ErrorHint(
          'Wrap the scroll view that shows the rows in a '
          'DirectoryTreeDragAndDropScope for the same controller.',
        ),
      ]);
    }
    if (!identical(scope.controller, widget.controller)) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          'A row decorated by DirectoryTreeDragAndDropScope.decorateRow '
          'belongs to another controller than its scope.',
        ),
        ErrorHint(
          'Give the DirectoryTreeDragAndDropScope the controller of the '
          'rows it wraps.',
        ),
      ]);
    }
    return true;
  }
}
