part of 'directory_tree_drag_and_drop.dart';

/// How far a mouse or trackpad pointer moves before a press becomes a drag,
/// in logical pixels.
///
/// The hit slop Flutter uses for these pointers is 1 pixel, which turns a
/// click with the slightest jitter into a drag (and a drag cancels the
/// click). 4 pixels is the drag threshold of desktop platforms (Windows
/// `SM_CXDRAG`) and still well below the touch slop that a tap tolerates.
const double _kPreciseDragSlop = 4;

/// Whether presses of [kind] start a drag with a long press (touch-like
/// pointers, whose swipes scroll) rather than after moving past a slop.
bool _startsWithLongPress(PointerDeviceKind kind) =>
    kind == PointerDeviceKind.touch || kind == PointerDeviceKind.unknown;

/// A pointer that went down on a decorated row.
final class _RowPress {
  _RowPress({
    required this.row,
    required this.rowId,
    required this.kind,
    required this.position,
  });

  /// The state of the pressed row; its context is used when the drag starts.
  final _DragAndDropRowState row;

  /// The id of the pressed row.
  final NodeId rowId;

  final PointerDeviceKind kind;

  /// The global position where the pointer went down.
  final Offset position;

  bool get startsWithLongPress => _startsWithLongPress(kind);
}

/// Recognizes the drags of one scope's rows, one pointer state per pressed
/// pointer.
///
/// The scope owns this recognizer and the [Drag] it starts, so the drag
/// keeps receiving the pointer's movement when the pressed row scrolls out
/// of view and is disposed. Unlike [ImmediateMultiDragGestureRecognizer],
/// it never starts a mouse drag before the pointer moved past the slop, even
/// when no other recognizer wants the pointer and the arena hands it over at
/// pointer down: a plain click must not drop anything.
final class _RowDragGestureRecognizer extends MultiDragGestureRecognizer {
  _RowDragGestureRecognizer({
    required super.debugOwner,
    required this.canStartPreciseDrag,
    required this.onStartDrag,
  }) {
    onStart = _handleStart;
  }

  /// Asked when a mouse, trackpad, or stylus press moved past the slop;
  /// false leaves the pointer to the other recognizers.
  final bool Function(_RowPress press) canStartPreciseDrag;

  /// Starts the drag of an accepted press, or returns `null` to drop it.
  final Drag? Function(_RowPress press) onStartDrag;

  // The press of the pointer being added, read by createNewPointerState.
  _RowPress? _pendingPress;

  // The pointer state whose drag is starting, read by _handleStart (the
  // start callback of the base class only receives a position).
  _RowPointerState? _starting;

  /// Tracks [event], a pointer that went down on the row of [press].
  ///
  /// Pointers whose buttons are not the primary button alone are ignored.
  void addRowPointer(PointerDownEvent event, _RowPress press) {
    _pendingPress = press;
    try {
      addPointer(event);
    } finally {
      _pendingPress = null;
    }
  }

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    final press = _pendingPress;
    assert(press != null, 'Row pointers are added with addRowPointer.');
    return press!.startsWithLongPress
        ? _LongPressPointerState(this, press, event, gestureSettings)
        : _SlopPointerState(this, press, event, gestureSettings);
  }

  Drag? _handleStart(Offset position) {
    final state = _starting;
    return state == null ? null : onStartDrag(state.press);
  }

  @override
  String get debugDescription => 'directory tree row drag';
}

/// The state of one pressed pointer.
abstract class _RowPointerState extends MultiDragPointerState {
  _RowPointerState(
    this.recognizer,
    this.press,
    PointerDownEvent event,
    DeviceGestureSettings? gestureSettings,
  ) : super(event.position, event.kind, gestureSettings);

  final _RowDragGestureRecognizer recognizer;
  final _RowPress press;

  /// Runs [starter], the base class's start callback for this pointer,
  /// letting the recognizer know which press is starting.
  void startWith(GestureMultiDragStartCallback starter) {
    recognizer._starting = this;
    try {
      starter(initialPosition);
    } finally {
      recognizer._starting = null;
    }
  }
}

/// A mouse, trackpad, or stylus press: becomes a drag once it moved past the
/// slop, if the scope allows it.
final class _SlopPointerState extends _RowPointerState {
  _SlopPointerState(
    super.recognizer,
    super.press,
    super.event,
    super.gestureSettings,
  );

  // The start callback when the arena accepted this pointer before it moved
  // past the slop.
  GestureMultiDragStartCallback? _starter;
  bool _passedSlop = false;

  double get _slop =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad
      ? _kPreciseDragSlop
      : computeHitSlop(kind, gestureSettings);

  @override
  void checkForResolutionAfterMove() {
    if (_passedSlop || pendingDelta!.distance <= _slop) return;
    _passedSlop = true;
    final starter = _starter;
    if (starter != null) {
      // The arena accepted this pointer already (nothing else wanted it).
      _starter = null;
      if (recognizer.canStartPreciseDrag(press)) startWith(starter);
      return;
    }
    resolve(
      recognizer.canStartPreciseDrag(press)
          ? GestureDisposition.accepted
          : GestureDisposition.rejected,
    );
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_passedSlop) {
      startWith(starter);
    } else {
      _starter = starter;
    }
  }
}

/// A touch press: becomes a drag session after a long press that stayed
/// within the touch slop; moving earlier gives the pointer up, so the list
/// scrolls.
final class _LongPressPointerState extends _RowPointerState {
  _LongPressPointerState(
    super.recognizer,
    super.press,
    super.event,
    super.gestureSettings,
  ) {
    _timer = Timer(kLongPressTimeout, _handleLongPress);
  }

  Timer? _timer;

  // The start callback when the arena accepted this pointer before the long
  // press timer fired.
  GestureMultiDragStartCallback? _starter;

  void _handleLongPress() {
    _timer = null;
    final starter = _starter;
    if (starter != null) {
      _starter = null;
      startWith(starter);
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      startWith(starter);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    final timer = _timer;
    if (timer == null) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      timer.cancel();
      _timer = null;
      _starter = null;
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
