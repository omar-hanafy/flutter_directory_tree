import 'dart:async';
import 'dart:math' as math;

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show DefaultMaterialLocalizations, MaterialLocalizations;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/controller/tree_rows_change.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_checkbox.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_expander.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_directory_tree/src/widgets/row_scope.dart';

/// The visible rows of a [DirectoryTreeController] as a sliver, for a
/// [CustomScrollView].
///
/// Rows are virtualized: only the rows in the viewport (plus the scroll
/// view's cache extent) are built, at the fixed height
/// [DirectoryTreeThemeData.rowExtent], so a tree of a million rows scrolls
/// like a short list. The sliver listens to the controller and rebuilds
/// only the rows whose [DirectoryTreeRowDetails] changed: selecting,
/// focusing, checking, or hovering a row rebuilds that row and nothing
/// else.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     SliverDirectoryTree<Object?>(
///       controller: controller,
///       onActivate: (row) => openFile(row.node),
///     ),
///   ],
/// )
/// ```
///
/// ## Mouse, touch, and keyboard focus
///
/// Clicks act when the pointer goes up, with no double-click delay. A
/// primary click gives the tree keyboard focus (the nearest [Focus] above
/// the sliver, normally the tree's keyboard handling) and focuses the row
/// (the controller's keyboard cursor). With [selectOnTap] it also selects:
/// a plain click selects the row, Shift extends the selection to it, and
/// Command (macOS and iOS) or Control (other platforms) toggles it. With
/// [expandOnTap] a plain click (no modifier) also expands or collapses a
/// directory. [onRowTap] runs last.
///
/// A second primary click on the same row within [kDoubleTapTimeout]
/// activates it: a directory expands or collapses exactly once per
/// activation (the second click of a double-click does not toggle it again
/// when the first one did through [expandOnTap]), then [onActivate] runs
/// for files and directories alike, after that click's [onRowTap].
///
/// A secondary click (and on macOS a Control-click), or a touch long-press
/// while [secondaryTapOnLongPress] is true, selects the row unless it is
/// already selected (with [selectOnTap]; otherwise it only focuses it),
/// then calls [onRowSecondaryTap] with the pointer's global position. Use
/// it to open a context menu for the selection.
///
/// Clicks on a row's [DirectoryTreeExpander] or [DirectoryTreeCheckbox]
/// toggle them and never select or activate the row. Hover is tracked for
/// mouse pointers only.
///
/// ## Scrolling and animation
///
/// The sliver implements [DirectoryTreeViewport] and attaches itself to the
/// controller, so [DirectoryTreeController.ensureVisible], focus moves, and
/// [TreeFocusMove.pageDown] scroll it; it works with any slivers before it
/// and inside a [SliverPadding].
///
/// When the rows change, the first visible row keeps its position on
/// screen in the same frame (no frame shows a jump), so data refreshes,
/// lazy loads, and expansions above the viewport do not move what the user
/// is looking at. When that row is gone, the next visible row that still
/// exists keeps its place instead, and when none does, the scroll offset is
/// only clamped to the new content. When the whole tree is scrolled past,
/// the content after it stays in place. The same holds when the row height
/// changes, for example with the text scale.
///
/// While the view scrolls: a fling continues from the corrected position
/// with its momentum, and an animated
/// [DirectoryTreeController.ensureVisible] is aimed again at its row's new
/// place for the time it has left (when the row is already where it was
/// asked to be, the scroll stops there). An animation the app started
/// with [ScrollPosition.animateTo] keeps its absolute target, so
/// `animateTo(0)` still ends at the top; the content then moves when it
/// gets there. A correction does not notify scroll listeners itself (as
/// a layout correction does not); the next scroll offset they see is the
/// corrected one.
///
/// Rows inserted by an incremental expand or a lazy load (a
/// [TreeRowsChange] splice) fade and slide in over
/// [DirectoryTreeThemeData.animationDuration]; rows that appear by
/// scrolling or after any other change do not animate, and nothing
/// animates while [MediaQuery.disableAnimationsOf] is true.
///
/// ## Semantics
///
/// Each row is one semantics node, as large as the row, so screen readers
/// stop once per row. It is labeled with [TreeRow.label] and reports:
///
/// * the selected state, the expanded state of expandable rows, and the
///   checked or mixed state when [checkboxMode] shows checkboxes;
/// * the load state of a lazy directory as its value:
///   [loadingSemanticsLabel] while its children load and
///   [loadFailedSemanticsLabel] after the load failed;
/// * a hint with the row's level from [levelSemanticsHint];
/// * the keyboard focus: while the tree has keyboard focus, the row of
///   [DirectoryTreeController.focusedId] is the focused node, so screen
///   readers on the web and on desktops follow the arrow keys.
///
/// Its actions:
///
/// * tap: with checkboxes, toggles the row's box as a click on it does;
///   otherwise (and for a box that cannot change) a plain click;
/// * expand and collapse for expandable rows (as a click on the expander
///   does); on iOS and macOS, whose screen readers lack those actions,
///   also custom actions labeled with
///   [MaterialLocalizations.collapsedIconTapHint] and
///   [MaterialLocalizations.expandedIconTapHint];
/// * a custom action labeled with
///   [MaterialLocalizations.refreshIndicatorSemanticLabel] that retries the
///   failed load of a lazy directory;
/// * a custom action labeled [activateSemanticsLabel] that activates the
///   row (as Enter or a double-click does) when [onActivate] is set, so
///   touch screen reader users can open files;
/// * long press: the secondary tap, when [onRowSecondaryTap] is set.
///
/// The default [DirectoryTreeExpander] and [DirectoryTreeCheckbox] add no
/// node of their own inside the sliver. A custom [rowBuilder] should not
/// repeat the label in its own semantics; wrap such text in
/// [ExcludeSemantics].
class SliverDirectoryTree<T> extends StatefulWidget {
  /// Creates the sliver of [controller]'s rows.
  const SliverDirectoryTree({
    super.key,
    required this.controller,
    this.rowBuilder,
    this.rowDecorator,
    this.checkboxMode = DirectoryTreeCheckboxMode.none,
    this.expandOnTap = true,
    this.selectOnTap = true,
    this.onRowTap,
    this.onActivate,
    this.onRowSecondaryTap,
    this.secondaryTapOnLongPress = true,
    this.levelSemanticsHint,
    this.activateSemanticsLabel = 'Open',
    this.loadingSemanticsLabel = 'Loading',
    this.loadFailedSemanticsLabel = 'Failed to load',
  });

  /// The controller whose [DirectoryTreeController.rows] this sliver shows.
  ///
  /// The sliver listens to it and attaches itself as a
  /// [DirectoryTreeViewport] while it is mounted; replacing the controller
  /// moves both to the new one.
  final DirectoryTreeController<T> controller;

  /// Builds the widget of one row; null draws a [DirectoryTreeRow].
  ///
  /// It runs only for rows whose [DirectoryTreeRowDetails] changed, and the
  /// result must fit [DirectoryTreeThemeData.rowExtent]. The sliver adds
  /// the click, hover, and semantics handling around it.
  final DirectoryTreeRowBuilder<T>? rowBuilder;

  /// Wraps each built row, after the sliver added its click and hover
  /// handling; null wraps nothing.
  ///
  /// Drag and drop installs one; see [DirectoryTreeRowDecorator].
  final DirectoryTreeRowDecorator<T>? rowDecorator;

  /// Which checkbox each row shows; [DirectoryTreeCheckboxMode.none] by
  /// default.
  ///
  /// It decides [DirectoryTreeRowDetails.checkState] and the semantics
  /// checked state of each row.
  final DirectoryTreeCheckboxMode checkboxMode;

  /// Whether a plain primary click on a directory row expands or collapses
  /// it; true by default.
  ///
  /// Clicks with Shift, Command, or Control never toggle. When false, a
  /// double-click still toggles a directory once.
  final bool expandOnTap;

  /// Whether clicks change the selection; true by default.
  ///
  /// When false, primary and secondary clicks only focus the row (and
  /// [expandOnTap] still applies), which suits views where the checkboxes
  /// or the app decide what is selected.
  final bool selectOnTap;

  /// Called after the built-in handling of every primary click on a row
  /// (including each click of a double-click), with the row as it is after
  /// that handling.
  final ValueChanged<TreeRow<T>>? onRowTap;

  /// Called when a row is activated by a double-click, after the click's
  /// own handling, for files and directories alike.
  ///
  /// Keyboard activation (Enter) is handled by the tree's keyboard widget.
  final ValueChanged<TreeRow<T>>? onActivate;

  /// Called after a secondary click, or a touch long-press while
  /// [secondaryTapOnLongPress] is true, has selected (or focused) the row;
  /// receives the row and the pointer's global position.
  final void Function(TreeRow<T> row, Offset globalPosition)? onRowSecondaryTap;

  /// Whether a touch long-press counts as a secondary tap; true by default.
  ///
  /// Set it to false when touch long-presses start drags instead, as drag
  /// and drop does. Mouse and stylus long-presses never count.
  final bool secondaryTapOnLongPress;

  /// Builds the semantics hint of a row from its level, which is
  /// [TreeRow.depth] plus 1.
  ///
  /// Null uses the English `Level 2`; pass a function to localize it.
  final String Function(int level)? levelSemanticsHint;

  /// The label of the custom semantics action that activates a row, as a
  /// double-click or Enter does; `'Open'` by default.
  ///
  /// Rows offer the action only while [onActivate] is set. It is how touch
  /// screen reader users, who have no double-click and no Enter key, reach
  /// [onActivate]; pass a localized verb that says what activation does in
  /// the app, such as "Open".
  final String activateSemanticsLabel;

  /// The semantics value of a lazy directory row while its children load;
  /// `'Loading'` by default.
  ///
  /// Screen readers read it after the row's label. Pass a localized
  /// string.
  final String loadingSemanticsLabel;

  /// The semantics value of a lazy directory row whose children failed to
  /// load; `'Failed to load'` by default.
  ///
  /// Screen readers read it after the row's label; the row also offers an
  /// action that retries the load. Pass a localized string.
  final String loadFailedSemanticsLabel;

  @override
  State<SliverDirectoryTree<T>> createState() => _SliverDirectoryTreeState<T>();

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
        ),
      )
      ..add(
        FlagProperty(
          'selectOnTap',
          value: selectOnTap,
          ifFalse: 'no select on tap',
        ),
      )
      ..add(
        FlagProperty(
          'secondaryTapOnLongPress',
          value: secondaryTapOnLongPress,
          ifFalse: 'no secondary tap on long press',
        ),
      )
      ..add(
        ObjectFlagProperty<DirectoryTreeRowBuilder<T>>.has(
          'rowBuilder',
          rowBuilder,
        ),
      )
      ..add(
        ObjectFlagProperty<DirectoryTreeRowDecorator<T>>.has(
          'rowDecorator',
          rowDecorator,
        ),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<TreeRow<T>>>.has('onRowTap', onRowTap),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<TreeRow<T>>>.has(
          'onActivate',
          onActivate,
        ),
      )
      ..add(
        ObjectFlagProperty<void Function(TreeRow<T>, Offset)>.has(
          'onRowSecondaryTap',
          onRowSecondaryTap,
        ),
      )
      ..add(
        ObjectFlagProperty<String Function(int)>.has(
          'levelSemanticsHint',
          levelSemanticsHint,
        ),
      )
      ..add(
        StringProperty(
          'activateSemanticsLabel',
          activateSemanticsLabel,
          defaultValue: 'Open',
        ),
      )
      ..add(
        StringProperty(
          'loadingSemanticsLabel',
          loadingSemanticsLabel,
          defaultValue: 'Loading',
        ),
      )
      ..add(
        StringProperty(
          'loadFailedSemanticsLabel',
          loadFailedSemanticsLabel,
          defaultValue: 'Failed to load',
        ),
      );
  }
}

/// What one build of the sliver shows. The item builder of that build reads
/// it, so rows created later during layout stay consistent with the item
/// count of the same build.
final class _Snapshot<T> {
  _Snapshot({
    required this.rows,
    required this.focusedId,
    required this.hasFocus,
    required this.query,
    required this.checkboxMode,
  });

  final TreeRows<T> rows;
  final NodeId? focusedId;
  final bool hasFocus;
  final TreeQuery? query;
  final DirectoryTreeCheckboxMode checkboxMode;
}

/// A row widget and the details it was built for. [query] is the parsed
/// query its match ranges were computed with.
final class _CachedRow<T> {
  _CachedRow(this.details, this.widget, this.query);

  final DirectoryTreeRowDetails<T> details;
  final _RowItem<T> widget;
  final TreeQuery? query;
}

/// The rows a splice inserted: indexes [start] (inclusive) to [end]
/// (exclusive) of [rows].
final class _InsertedBlock {
  _InsertedBlock(this.rows, this.start, this.end);

  final TreeRows<Object?> rows;
  final int start;
  final int end;
}

class _SliverDirectoryTreeState<T> extends State<SliverDirectoryTree<T>>
    implements DirectoryTreeViewport {
  // The rows of the controller's latest notification.
  late TreeRows<T> _rows;

  // What the latest build shows, and the base of scroll anchoring: the
  // render sliver was last laid out with these rows.
  _Snapshot<T>? _snapshot;

  // The scroll correction applied since the latest build (see
  // _anchorScrollOffset).
  double _appliedAnchorCorrection = 0;

  // After showRow jumped, the row it showed is the anchor until the next
  // build (the latest layout no longer describes the screen): its id, its
  // index in the rows of that moment, those rows, and the correction
  // applied since.
  ({NodeId id, int index, TreeRows<T> rows, double applied})? _shownAnchor;

  // The animation of the latest animated showRow while it runs.
  _RowAnimation? _rowAnimation;

  _InsertedBlock? _insertedBlock;

  // The tree and checks mode the cached rows' checkboxes were built for:
  // whether a box is enabled depends on both (SelectionState.canCheck).
  DirectoryTree<T>? _checksTree;
  SelectionMode? _checksMode;

  final Map<NodeId, _CachedRow<T>> _cache = <NodeId, _CachedRow<T>>{};
  final Map<NodeId, _RowItemState<T>> _items = <NodeId, _RowItemState<T>>{};

  ScrollableState? _scrollable;
  Duration _insertDuration = Duration.zero;
  Curve _insertCurve = Curves.linear;

  // Double-click tracking: the row of the latest primary click while the
  // double-click window is open, whether that click toggled the row's
  // directory, and the row a press armed as the second click.
  NodeId? _lastClickId;
  bool _lastClickToggled = false;
  Timer? _clickWindow;
  NodeId? _armedId;

  DirectoryTreeController<T> get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _rows = _controller.rows;
    _controller
      ..addListener(_handleControllerChanged)
      ..attachViewport(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context);
  }

  @override
  void didUpdateWidget(SliverDirectoryTree<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller
        ..removeListener(_handleControllerChanged)
        ..detachViewport(this);
      widget.controller
        ..addListener(_handleControllerChanged)
        ..attachViewport(this);
      _resetClicks();
      _cache.clear();
      _adoptRows(widget.controller.rows, splice: null);
      return;
    }
    // The row widgets read these when they build, so cached widgets would
    // keep the old ones.
    if (oldWidget.rowBuilder != widget.rowBuilder ||
        oldWidget.rowDecorator != widget.rowDecorator ||
        oldWidget.secondaryTapOnLongPress != widget.secondaryTapOnLongPress ||
        (oldWidget.onRowSecondaryTap == null) !=
            (widget.onRowSecondaryTap == null) ||
        (oldWidget.onActivate == null) != (widget.onActivate == null) ||
        oldWidget.levelSemanticsHint != widget.levelSemanticsHint ||
        oldWidget.activateSemanticsLabel != widget.activateSemanticsLabel ||
        oldWidget.loadingSemanticsLabel != widget.loadingSemanticsLabel ||
        oldWidget.loadFailedSemanticsLabel != widget.loadFailedSemanticsLabel) {
      _cache.clear();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..detachViewport(this);
    _clickWindow?.cancel();
    _rowAnimation?.complete();
    _rowAnimation = null;
    super.dispose();
  }

  void _handleControllerChanged() {
    final rows = _controller.rows;
    if (!identical(rows, _rows)) {
      final change = _controller.lastRowsChange;
      // A splice is only trusted when it starts from the rows this sliver
      // has; otherwise some change in between was missed.
      final splice = !change.isReset && identical(change.previous, _rows)
          ? change
          : null;
      _adoptRows(rows, splice: splice);
    }
    setState(() {
      // The details of the visible rows are recomputed in build.
    });
  }

  /// Makes [rows] the rows to show: records the block [splice] inserted
  /// for the insert animation, keeps the first visible row in place, and
  /// schedules a layout.
  void _adoptRows(TreeRows<T> rows, {required TreeRowsChange? splice}) {
    if (splice != null && splice.inserted > 0) {
      final block = _InsertedBlock(
        rows,
        splice.index,
        splice.index + splice.inserted,
      );
      _insertedBlock = block;
      // Only rows built for the frame right after the splice animate; rows
      // built later appear because of scrolling.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (identical(_insertedBlock, block)) _insertedBlock = null;
      });
    } else {
      _insertedBlock = null;
    }
    _rows = rows;
    _anchorScrollOffset();
    _retargetRowAnimation();
    // The visible children may all stay the same while the row count
    // changes, which alone would not lay the sliver out again.
    _renderSliver()?.markNeedsLayout();
  }

  // ---------------------------------------------------------------------
  // Building
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = DirectoryTreeTheme.of(context);
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _insertDuration = disableAnimations
        ? Duration.zero
        : theme.animationDuration!;
    _insertCurve = theme.animationCurve!;
    final controller = _controller;
    if (widget.checkboxMode == DirectoryTreeCheckboxMode.checks) {
      final tree = controller.tree;
      final mode = controller.checks.mode;
      if (!identical(tree, _checksTree) || mode != _checksMode) {
        _cache.clear();
        _checksTree = tree;
        _checksMode = mode;
      }
    }
    // A new row height (a theme or text scale change) keeps the first
    // visible row in place, as a rows change does.
    final extent = theme.rowExtent!;
    final render = _renderSliver();
    if (render != null && render.itemExtent != extent) {
      _anchorScrollOffset(extent: extent);
    }
    final snapshot = _Snapshot<T>(
      rows: _rows,
      focusedId: controller.focusedId,
      hasFocus: Focus.maybeOf(context)?.hasFocus ?? false,
      query: controller.parsedQuery,
      checkboxMode: widget.checkboxMode,
    );
    _snapshot = snapshot;
    _appliedAnchorCorrection = 0;
    _shownAnchor = null;
    return SliverFixedExtentList.builder(
      itemExtent: extent,
      itemCount: snapshot.rows.length,
      itemBuilder: (context, index) => _buildRow(snapshot, index),
      findChildIndexCallback: (key) => _indexOfKey(snapshot.rows, key),
      // Rows keep no state worth keeping off screen, and keep-alive would
      // hold rows of huge trees in memory.
      addAutomaticKeepAlives: false,
    );
  }

  static int? _indexOfKey(TreeRows<Object?> rows, Key key) {
    if (key is! ValueKey<NodeId>) return null;
    final id = key.value;
    final index = rows.indexOfNode(id);
    // indexOfNode also finds a node inside a compacted row; only the row
    // keyed by exactly this id moves there.
    return index >= 0 && rows[index].id == id ? index : null;
  }

  Widget? _buildRow(_Snapshot<T> snapshot, int index) {
    final rows = snapshot.rows;
    if (index < 0 || index >= rows.length) return null;
    final row = rows[index];
    final id = row.id;
    final controller = _controller;
    final isSelected = controller.isSelected(id);
    final cached = _cache[id];
    // Match ranges only change with the row object or the query, and
    // computing them reads the label, which the core derives on each read.
    final matchRanges =
        cached != null &&
            identical(cached.details.row, row) &&
            identical(cached.query, snapshot.query)
        ? cached.details.matchRanges
        : controller.matchRangesOf(row);
    final details = DirectoryTreeRowDetails<T>(
      controller: controller,
      row: row,
      index: index,
      isSelected: isSelected,
      isFocused: id == snapshot.focusedId,
      hasFocus: snapshot.hasFocus,
      isHovered: false,
      checkboxMode: snapshot.checkboxMode,
      checkState: switch (snapshot.checkboxMode) {
        DirectoryTreeCheckboxMode.none => null,
        DirectoryTreeCheckboxMode.checks => controller.checkStateOf(id),
        DirectoryTreeCheckboxMode.selection =>
          isSelected ? CheckState.checked : CheckState.unchecked,
      },
      loadStatus: controller.loadStatusOf(id),
      isExpandable: controller.isExpandable(id),
      matchRanges: matchRanges,
    );
    // The identical widget makes the framework skip the row entirely.
    if (cached != null && cached.details == details) return cached.widget;
    final item = _RowItem<T>(
      key: ValueKey<NodeId>(id),
      host: this,
      details: details,
    );
    _cache[id] = _CachedRow<T>(details, item, snapshot.query);
    return item;
  }

  /// Whether the row at [index] of the latest build was inserted by the
  /// latest splice and should animate in.
  bool _animatesIn(int index) {
    final block = _insertedBlock;
    if (block == null || _insertDuration == Duration.zero) return false;
    final snapshot = _snapshot;
    return snapshot != null &&
        identical(block.rows, snapshot.rows) &&
        index >= block.start &&
        index < block.end;
  }

  String _levelHint(int level) =>
      widget.levelSemanticsHint?.call(level) ?? 'Level $level';

  void _registerItem(NodeId id, _RowItemState<T> item) => _items[id] = item;

  void _unregisterItem(NodeId id, _RowItemState<T> item) {
    if (identical(_items[id], item)) _items.remove(id);
    // A row that left the screen is rebuilt from scratch when it comes
    // back, so its cache entry only costs memory.
    if (identical(_cache[id]?.widget, item.widget)) _cache.remove(id);
  }

  // ---------------------------------------------------------------------
  // Clicks
  // ---------------------------------------------------------------------

  /// A pointer went down on the row [id]: a primary press there while the
  /// double-click window of a click on the same row is open arms an
  /// activation. Every press closes the window.
  void _handlePointerDown(NodeId id, PointerDownEvent event) {
    final open = _clickWindow?.isActive ?? false;
    _armedId = open && _lastClickId == id && event.buttons == kPrimaryButton
        ? id
        : null;
    _clickWindow?.cancel();
    _clickWindow = null;
  }

  void _resetClicks() {
    _clickWindow?.cancel();
    _clickWindow = null;
    _lastClickId = null;
    _lastClickToggled = false;
    _armedId = null;
  }

  void _handlePrimaryTap(
    TreeRow<T> row,
    TapUpDetails details,
    BuildContext itemContext,
  ) {
    final id = row.id;
    final activation = _armedId == id;
    _armedId = null;
    final keyboard = HardwareKeyboard.instance;
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.macOS && keyboard.isControlPressed) {
      // On macOS a Control-click is the secondary click of one-button
      // mice and trackpads.
      _handleSecondaryTap(row, details.globalPosition, itemContext);
      return;
    }
    final commandKey =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    _click(
      row,
      itemContext,
      extend: keyboard.isShiftPressed,
      toggle: commandKey ? keyboard.isMetaPressed : keyboard.isControlPressed,
      activation: activation,
      opensDoubleClickWindow: true,
    );
  }

  /// The built-in handling of a primary click on [row], then the
  /// callbacks.
  ///
  /// With [activation] this is the second click of a double-click. With
  /// [opensDoubleClickWindow] a following click on the same row within
  /// [kDoubleTapTimeout] activates it.
  void _click(
    TreeRow<T> row,
    BuildContext itemContext, {
    required bool extend,
    required bool toggle,
    required bool activation,
    required bool opensDoubleClickWindow,
  }) {
    final controller = _controller;
    final id = row.id;
    requestTreeFocus(itemContext);
    if (widget.selectOnTap) {
      if (extend) {
        controller.extendSelection(id);
      } else if (toggle) {
        controller.toggleSelected(id);
      } else {
        controller.select(id);
      }
    } else {
      controller.focus(id);
    }
    final isDirectory = row.node is DirectoryNode<T>;
    final onRowTap = widget.onRowTap;
    if (activation) {
      // A directory toggles once per activation: the first click of this
      // double-click may have done it already.
      final toggled = _lastClickToggled;
      _resetClicks();
      if (isDirectory && !toggled) controller.toggleExpansion(id);
      final onActivate = widget.onActivate;
      onRowTap?.call(_currentRow(row));
      onActivate?.call(_currentRow(row));
      return;
    }
    final plain = !extend && !toggle;
    final toggles = widget.expandOnTap && plain && isDirectory;
    if (toggles) controller.toggleExpansion(id);
    _resetClicks();
    if (opensDoubleClickWindow) {
      _lastClickId = id;
      _lastClickToggled = toggles;
      _clickWindow = Timer(kDoubleTapTimeout, _resetClicks);
    }
    onRowTap?.call(_currentRow(row));
  }

  void _handleSecondaryTap(
    TreeRow<T> row,
    Offset globalPosition,
    BuildContext itemContext,
  ) {
    _resetClicks();
    final controller = _controller;
    final id = row.id;
    requestTreeFocus(itemContext);
    if (widget.selectOnTap && !controller.isSelected(id)) {
      controller.select(id);
    } else {
      controller.focus(id);
    }
    widget.onRowSecondaryTap?.call(_currentRow(row), globalPosition);
  }

  /// The semantics tap action: with checkboxes, what a click on the row's
  /// box does; otherwise (or when the box cannot change) a plain click
  /// that never activates.
  void _handleSemanticTap(
    DirectoryTreeRowDetails<T> details,
    BuildContext itemContext,
  ) {
    _resetClicks();
    // The row's node is the checkbox for screen readers.
    if (canToggleCheckbox(details)) {
      toggleCheckbox(itemContext, details);
      return;
    }
    final row = details.row;
    _click(
      row,
      itemContext,
      extend: false,
      toggle: false,
      activation: false,
      opensDoubleClickWindow: false,
    );
  }

  /// The semantics expand and collapse actions, and the retry of a failed
  /// load: what a click on the row's expander does.
  void _handleSemanticExpansion(
    TreeRow<T> row,
    BuildContext itemContext, {
    required bool expand,
  }) {
    _resetClicks();
    requestTreeFocus(itemContext);
    final controller = _controller;
    final id = row.id;
    if (expand) {
      // Also starts a failed load again.
      controller.expand(id);
    } else {
      controller.collapse(id);
    }
    controller.focus(id);
  }

  /// The semantics activate action: what Enter does on the row, after it
  /// is focused (and selected, with [SliverDirectoryTree.selectOnTap]).
  void _handleSemanticActivate(TreeRow<T> row, BuildContext itemContext) {
    _resetClicks();
    requestTreeFocus(itemContext);
    final controller = _controller;
    final id = row.id;
    if (widget.selectOnTap) {
      controller.select(id);
    } else {
      controller.focus(id);
    }
    if (row.node is DirectoryNode<T>) controller.toggleExpansion(id);
    widget.onActivate?.call(_currentRow(row));
  }

  /// The row of [row]'s node in the controller's current rows, which a
  /// click may have just replaced (an expanded directory is a new row
  /// object); [row] itself when it is gone.
  TreeRow<T> _currentRow(TreeRow<T> row) {
    final rows = _controller.rows;
    final index = rows.indexOfNode(row.id);
    if (index >= 0) {
      final current = rows[index];
      if (current.id == row.id) return current;
    }
    return row;
  }

  // ---------------------------------------------------------------------
  // Scroll anchoring
  // ---------------------------------------------------------------------

  RenderSliverFixedExtentList? _renderSliver() {
    if (!mounted) return null;
    final render = context.findRenderObject();
    return render is RenderSliverFixedExtentList ? render : null;
  }

  ScrollPosition? get _position {
    final scrollable = _scrollable;
    if (scrollable == null || !scrollable.mounted) return null;
    return scrollable.position;
  }

  /// Keeps the first visible row where it is on screen after the rows or
  /// the row height ([extent], the render sliver's by default) changed, by
  /// correcting the scroll offset before the next layout.
  ///
  /// The correction is computed against the rows of the latest build, which
  /// are the rows the render sliver was last laid out with, and the part
  /// already applied since then is subtracted, so several changes before
  /// one frame add up to the right total.
  void _anchorScrollOffset({double? extent}) {
    final base = _snapshot?.rows;
    final render = _renderSliver();
    final position = _position;
    if (base == null ||
        render == null ||
        position == null ||
        !_hasLayout(render) ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return;
    }
    final oldExtent = render.itemExtent;
    final newExtent = extent ?? oldExtent;
    final shown = _shownAnchor;
    final double desired;
    if (shown != null) {
      final moved = _shownRowMove(shown, render, oldExtent);
      final offset = moved == null
          ? 0.0
          : moved.to * newExtent - moved.from * oldExtent;
      desired = render.constraints.growthDirection == GrowthDirection.reverse
          ? -offset
          : offset;
    } else {
      desired = _anchorCorrection(
        base,
        _rows,
        render.constraints,
        oldExtent,
        newExtent,
      );
    }
    final applied = shown?.applied ?? _appliedAnchorCorrection;
    final delta = desired - applied;
    if (delta == 0) return;
    // The scroll physics keep a corrected offset as it is, so it must land
    // inside the scroll range of the new rows here.
    final range = _predictedScrollRange(
      render,
      position,
      _rows.length * newExtent - render.geometry!.scrollExtent,
    );
    final pixels = position.pixels;
    final target = clampDouble(pixels + delta, range.min, range.max);
    final correction = target - pixels;
    if (correction != 0) {
      position.correctBy(correction);
      _keepCorrection(position, correction);
    }
    if (shown != null) {
      _shownAnchor = (
        id: shown.id,
        index: shown.index,
        rows: shown.rows,
        applied: shown.applied + correction,
      );
    } else {
      _appliedAnchorCorrection += correction;
    }
  }

  /// Where the row that showRow jumped to moved since (its index then and
  /// now); when it is gone, where the next surviving row of the screen
  /// moved; null when none of them survives.
  ({int from, int to})? _shownRowMove(
    ({NodeId id, int index, TreeRows<T> rows, double applied}) shown,
    RenderSliver render,
    double extent,
  ) {
    final index = _rows.indexOfNode(shown.id);
    if (index >= 0) return (from: shown.index, to: index);
    // The rows that can be on screen below the shown row.
    final visible = extent <= 0
        ? 0
        : (render.constraints.viewportMainAxisExtent / extent).ceil();
    final end = math.min(shown.rows.length, shown.index + 1 + visible);
    for (var i = shown.index + 1; i < end; i++) {
      final next = _rows.indexOfNode(shown.rows[i].id);
      if (next >= 0) return (from: i, to: next);
    }
    return null;
  }

  /// Keeps [correction], just applied to [position], from being undone by
  /// a running scroll activity that sets absolute offsets.
  ///
  /// * A fling ([BallisticScrollActivity]) starts again from the corrected
  ///   offset with its current velocity, so it keeps its momentum.
  /// * An animated showRow is aimed again by [_retargetRowAnimation], from
  ///   the corrected offset.
  /// * An animation the app started ([ScrollPosition.animateTo]) keeps its
  ///   absolute target: `animateTo(0)` still ends at the top.
  ///
  /// The correction itself does not notify, and every later offset comes
  /// from an activity that starts at the corrected one, so scroll
  /// listeners only ever see real offsets.
  void _keepCorrection(ScrollPosition position, double correction) {
    final activity = _activityOf(position);
    if (activity is BallisticScrollActivity) {
      activity.delegate.goBallistic(activity.velocity);
    } else if (activity != null &&
        identical(activity, _rowAnimation?.activity)) {
      _rowAnimation!.correction += correction;
    }
  }

  /// The running activity of [position].
  ///
  /// [ScrollPosition.activity] is meant for subclasses, but only the
  /// activity tells a fling, or the sliver's own animation, from the other
  /// activities, and the sliver does not own the position to subclass it.
  static ScrollActivity? _activityOf(ScrollPosition position) =>
      // Read only, to compare identities and types; see above.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      position.activity;

  /// The change of the scroll offset that keeps the first visible row of
  /// [base] at its place in [rows], for a sliver laid out with
  /// [constraints] and rows of [oldExtent] that are now [newExtent] high;
  /// 0 when nothing needs to move.
  static double _anchorCorrection(
    TreeRows<Object?> base,
    TreeRows<Object?> rows,
    SliverConstraints constraints,
    double oldExtent,
    double newExtent,
  ) {
    if ((identical(base, rows) && oldExtent == newExtent) || oldExtent <= 0) {
      return 0;
    }
    final scrollOffset = constraints.scrollOffset;
    // The first pixel of the sliver that is not under a pinned header.
    final leading = scrollOffset + math.max(0.0, constraints.overlap);
    // The start of the tree is on screen: rows flow from there.
    if (leading <= 0) return 0;
    final oldCount = base.length;
    double offset = 0;
    if (leading >= oldCount * oldExtent) {
      // The tree is scrolled past: keep what follows it in place.
      offset = rows.length * newExtent - oldCount * oldExtent;
    } else {
      final first = leading ~/ oldExtent;
      final end = math.min(
        oldCount,
        ((scrollOffset + constraints.remainingPaintExtent) / oldExtent).ceil(),
      );
      // The first visible row that still has a row keeps its place.
      for (var i = first; i < end; i++) {
        final index = rows.indexOfNode(base[i].id);
        if (index >= 0) {
          offset = index * newExtent - i * oldExtent;
          break;
        }
      }
    }
    // Slivers that grow backwards (before a scroll view's center) move the
    // other way when the scroll offset grows.
    return constraints.growthDirection == GrowthDirection.reverse
        ? -offset
        : offset;
  }

  /// Whether [render] and every sliver around it have been laid out, so
  /// their geometry describes the screen.
  static bool _hasLayout(RenderSliver render) {
    if (!render.attached || render.geometry == null) return false;
    RenderObject? node = render.parent;
    while (node is RenderSliver) {
      if (node.geometry == null) return false;
      node = node.parent;
    }
    if (node is RenderViewport) {
      for (
        var child = node.firstChild;
        child != null;
        child = node.childAfter(child)
      ) {
        if (child.geometry == null) return false;
      }
      return true;
    }
    if (node is RenderShrinkWrappingViewport) {
      for (
        var child = node.firstChild;
        child != null;
        child = node.childAfter(child)
      ) {
        if (child.geometry == null) return false;
      }
      return true;
    }
    return node is RenderAbstractViewport;
  }

  /// The scroll range the viewport will report once the tree's scroll
  /// extent changed by [delta], from the extents of its latest layout.
  static ({double min, double max}) _predictedScrollRange(
    RenderSliver render,
    ScrollPosition position,
    double delta,
  ) {
    final current = (
      min: position.minScrollExtent,
      max: position.maxScrollExtent,
    );
    if (delta == 0) return current;
    final constraints = render.constraints;
    final mainAxisExtent = constraints.viewportMainAxisExtent;
    final backwards = constraints.growthDirection == GrowthDirection.reverse;
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport is RenderViewport) {
      var forward = 0.0;
      var reverse = 0.0;
      for (
        var child = viewport.firstChild;
        child != null;
        child = viewport.childAfter(child)
      ) {
        final extent = child.geometry!.scrollExtent;
        if (child.constraints.growthDirection == GrowthDirection.reverse) {
          reverse += extent;
        } else {
          forward += extent;
        }
      }
      if (backwards) {
        reverse += delta;
      } else {
        forward += delta;
      }
      final anchor = viewport.anchor;
      return (
        min: math.min(0.0, -reverse + mainAxisExtent * anchor),
        max: math.max(0.0, forward - mainAxisExtent * (1.0 - anchor)),
      );
    }
    if (viewport is RenderShrinkWrappingViewport) {
      var total = delta;
      for (
        var child = viewport.firstChild;
        child != null;
        child = viewport.childAfter(child)
      ) {
        total += child.geometry!.scrollExtent;
      }
      return (min: 0.0, max: math.max(0.0, total - mainAxisExtent));
    }
    // An unknown viewport: the old range, widened by any growth.
    return (
      min: backwards ? current.min - math.max(0.0, delta) : current.min,
      max: backwards ? current.max : current.max + math.max(0.0, delta),
    );
  }

  // ---------------------------------------------------------------------
  // DirectoryTreeViewport
  // ---------------------------------------------------------------------

  @override
  int get pageRowCount {
    final render = _renderSliver();
    if (render == null || !_hasLayout(render)) return 1;
    final extent = render.itemExtent;
    if (extent <= 0) return 1;
    final constraints = render.constraints;
    // The part of the viewport the tree can paint in, below the slivers
    // before it and any pinned header that overlaps it.
    final visible =
        constraints.remainingPaintExtent - math.max(0.0, constraints.overlap);
    return math.max(1, (visible / extent).floor());
  }

  @override
  Future<void> showRow(
    int index, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  }) {
    final rows = _controller.rows;
    if (!mounted || index < 0 || index >= rows.length) {
      return Future<void>.value();
    }
    final render = _renderSliver();
    final position = _position;
    if (render == null ||
        position == null ||
        !_hasLayout(render) ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      // Nothing is on screen yet: scroll once the first layout is done.
      return _showRowAfterLayout(
        rows[index].id,
        duration: duration,
        curve: curve,
        alignment: alignment,
      );
    }
    final target = _offsetToShow(render, position, rows, index, alignment);
    if (target == null) return Future<void>.value();
    final id = rows[index].id;
    if (duration == Duration.zero) {
      _shownAnchor = (id: id, index: index, rows: rows, applied: 0);
      position.jumpTo(target);
      return Future<void>.value();
    }
    _rowAnimation?.complete();
    final animation = _RowAnimation(
      id: id,
      alignment: alignment,
      curve: curve,
      duration: duration,
    );
    _rowAnimation = animation;
    // The animation's clock starts with its first frame and reads the
    // time stamps the scroll animation runs on (scaled by timeDilation),
    // not the time it was asked for: an app idle for a while has no
    // recent frame.
    void track(Duration timeStamp) {
      if (animation.done.isCompleted) return;
      animation
        ..start ??= timeStamp
        ..lastFrame = timeStamp;
      SchedulerBinding.instance.scheduleFrameCallback(
        track,
        rescheduling: true,
      );
    }

    SchedulerBinding.instance.scheduleFrameCallback(track);
    _animateLeg(animation, position, target, duration);
    return animation.done.future;
  }

  /// The scroll offset that shows the row at [index] of [rows] as showRow
  /// documents it, inside the scroll range those rows will have; null when
  /// the scroll offset need not change.
  double? _offsetToShow(
    RenderSliverFixedExtentList render,
    ScrollPosition position,
    TreeRows<T> rows,
    int index,
    double? alignment,
  ) {
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport == null) return null;
    final extent = render.itemExtent;
    // The rows may have changed since the latest layout (the controller
    // notifies before it scrolls), so the row's place comes from its index
    // and the fixed extent, never from built children.
    final rect = _rowRect(render, index, extent);
    final pixels = position.pixels;
    final double target;
    if (alignment == null) {
      final leading = viewport.getOffsetToReveal(render, 0, rect: rect);
      final trailing = viewport.getOffsetToReveal(render, 1, rect: rect);
      final revealed = RevealedOffset.clampOffset(
        leadingEdgeOffset: leading,
        trailingEdgeOffset: trailing,
        currentOffset: pixels,
      );
      if (revealed == null) return null;
      target = revealed.offset;
    } else {
      target = viewport.getOffsetToReveal(render, alignment, rect: rect).offset;
    }
    if (!target.isFinite) return null;
    final range = _predictedScrollRange(
      render,
      position,
      rows.length * extent - render.geometry!.scrollExtent,
    );
    final clamped = clampDouble(target, range.min, range.max);
    if ((clamped - pixels).abs() < precisionErrorTolerance) return null;
    return clamped;
  }

  /// What is left of [animation]'s duration, on the frame clock.
  static Duration _timeLeft(_RowAnimation animation) {
    final start = animation.start;
    final lastFrame = animation.lastFrame;
    if (start == null || lastFrame == null) return animation.duration;
    return animation.duration - (lastFrame - start);
  }

  /// Animates [position] to [target] over [duration] as the current leg of
  /// [animation], which completes when this leg ends, unless a later leg
  /// replaced it.
  void _animateLeg(
    _RowAnimation animation,
    ScrollPosition position,
    double target,
    Duration duration,
  ) {
    final leg = position.animateTo(
      target,
      duration: duration,
      curve: animation.curve,
    );
    final activity = _activityOf(position);
    animation
      ..activity = activity
      ..target = target
      ..correction = 0;
    unawaited(
      leg.whenComplete(() {
        if (!identical(animation.activity, activity)) return;
        animation.complete();
        if (identical(_rowAnimation, animation)) _rowAnimation = null;
      }),
    );
  }

  /// After the rows changed while showRow animates, aims the animation at
  /// the row's new place, from the corrected offset, in the time left.
  ///
  /// The animation targets an absolute offset, which no longer shows the
  /// row once rows were added or removed above it, and its next frame
  /// would undo the anchor correction.
  void _retargetRowAnimation() {
    final animation = _rowAnimation;
    if (animation == null) return;
    final position = _position;
    final render = _renderSliver();
    if (position == null ||
        render == null ||
        !identical(_activityOf(position), animation.activity)) {
      // The animation ended or was interrupted, for example by a drag.
      animation.complete();
      _rowAnimation = null;
      return;
    }
    final index = _rows.indexOfNode(animation.id);
    final double? target;
    if (index < 0) {
      // A row that is gone has no new place: keep heading for the content
      // the animation was heading to.
      if (animation.correction == 0) return;
      target = animation.target + animation.correction;
    } else {
      if (!_hasLayout(render) || !position.hasContentDimensions) return;
      target = _offsetToShow(
        render,
        position,
        _rows,
        index,
        animation.alignment,
      );
      if (target == null) {
        // The row is already where it was asked to be: stop here.
        _endRowAnimation(animation, position, null);
        return;
      }
      if (animation.correction == 0 &&
          (target - animation.target).abs() < precisionErrorTolerance) {
        // Nothing moved for this animation.
        return;
      }
    }
    final left = _timeLeft(animation);
    if (left <= Duration.zero) {
      _endRowAnimation(animation, position, target);
      return;
    }
    _animateLeg(animation, position, target, left);
  }

  /// Ends [animation] now: at [target], or where the scroll is when null.
  void _endRowAnimation(
    _RowAnimation animation,
    ScrollPosition position,
    double? target,
  ) {
    animation.activity = null;
    // A jump replaces the animation's activity, which would otherwise keep
    // heading for its old offset.
    position.jumpTo(target ?? position.pixels);
    animation.complete();
    if (identical(_rowAnimation, animation)) _rowAnimation = null;
  }

  /// The bounds of the row at [index] in the coordinates
  /// [RenderAbstractViewport.getOffsetToReveal] expects for a sliver
  /// target.
  static Rect _rowRect(RenderSliver render, int index, double extent) {
    final constraints = render.constraints;
    final start = index * extent;
    final reversed = axisDirectionIsReversed(
      applyGrowthDirectionToAxisDirection(
        constraints.axisDirection,
        constraints.growthDirection,
      ),
    );
    // For reversed axes the viewport measures from the end of the sliver's
    // latest scroll extent; placing the rect from that same value keeps the
    // result exact even when the rows changed since.
    final mainStart = reversed
        ? render.geometry!.scrollExtent - start - extent
        : start;
    final cross = constraints.crossAxisExtent;
    return switch (constraints.axis) {
      Axis.vertical => Rect.fromLTWH(0, mainStart, cross, extent),
      Axis.horizontal => Rect.fromLTWH(mainStart, 0, extent, cross),
    };
  }

  /// Shows the row of [id] once a frame has laid the sliver out, trying for
  /// at most [frames] frames; the row index is looked up again then, since
  /// the rows may have changed.
  Future<void> _showRowAfterLayout(
    NodeId id, {
    required Duration duration,
    required Curve curve,
    required double? alignment,
    int frames = 3,
  }) {
    final completer = Completer<void>();
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        final index = mounted ? _controller.rows.indexOfNode(id) : -1;
        if (index < 0) {
          completer.complete();
          return;
        }
        final render = _renderSliver();
        final position = _position;
        final laidOut =
            render != null &&
            position != null &&
            _hasLayout(render) &&
            position.hasPixels &&
            position.hasContentDimensions;
        final Future<void> next;
        if (laidOut) {
          next = showRow(
            index,
            duration: duration,
            curve: curve,
            alignment: alignment,
          );
        } else if (frames > 1) {
          next = _showRowAfterLayout(
            id,
            duration: duration,
            curve: curve,
            alignment: alignment,
            frames: frames - 1,
          );
        } else {
          next = Future<void>.value();
        }
        completer.complete(next);
      })
      ..ensureVisualUpdate();
    return completer.future;
  }

  @override
  Rect? globalRowRect(int index) {
    final rows = _controller.rows;
    if (!mounted || index < 0 || index >= rows.length) return null;
    final item = _items[rows[index].id];
    if (item == null || !item.mounted) return null;
    final box = item.context.findRenderObject();
    final render = _renderSliver();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        render == null ||
        !_hasLayout(render)) {
      return null;
    }
    // The child of the sliver that holds the row: its layout offset is the
    // row's place in the sliver's latest layout.
    RenderObject child = box;
    while (child.parent != null && !identical(child.parent, render)) {
      child = child.parent!;
    }
    if (child is! RenderBox || !identical(child.parent, render)) return null;
    final start = render.childScrollOffset(child);
    if (start == null) return null;
    // Rows built for the cache extent, or hidden under a pinned header,
    // are not on screen.
    final constraints = render.constraints;
    final visibleStart =
        constraints.scrollOffset + math.max(0.0, constraints.overlap);
    final visibleEnd =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    if (start + render.itemExtent <= visibleStart || start >= visibleEnd) {
      return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }
}

/// An animated showRow: the row it shows, where in the viewport, its curve,
/// and its duration from [start], the time stamp of its first frame
/// ([lastFrame] is that of its latest one).
/// [activity] and [target] belong to its current leg; [correction] is the
/// anchor correction applied since that leg started.
final class _RowAnimation {
  _RowAnimation({
    required this.id,
    required this.alignment,
    required this.curve,
    required this.duration,
  });

  final NodeId id;
  final double? alignment;
  final Curve curve;
  final Duration duration;
  Duration? start;
  Duration? lastFrame;
  ScrollActivity? activity;
  double target = 0;
  double correction = 0;
  final Completer<void> done = Completer<void>();

  void complete() {
    if (!done.isCompleted) done.complete();
  }
}

/// One row: the built row widget with click, hover, and semantics handling.
class _RowItem<T> extends StatefulWidget {
  const _RowItem({super.key, required this.host, required this.details});

  final _SliverDirectoryTreeState<T> host;
  final DirectoryTreeRowDetails<T> details;

  @override
  State<_RowItem<T>> createState() => _RowItemState<T>();
}

class _RowItemState<T> extends State<_RowItem<T>> {
  bool _hovered = false;

  // Decided once: an element that animated in keeps its transition so the
  // row below it is never rebuilt from scratch.
  late final bool _animatesIn;

  _SliverDirectoryTreeState<T> get _host => widget.host;

  @override
  void initState() {
    super.initState();
    _animatesIn = _host._animatesIn(widget.details.index);
    _host._registerItem(widget.details.row.id, this);
  }

  @override
  void dispose() {
    _host._unregisterItem(widget.details.row.id, this);
    super.dispose();
  }

  void _handleEnter(PointerEnterEvent event) {
    if (event.kind != PointerDeviceKind.mouse || _hovered) return;
    setState(() => _hovered = true);
  }

  void _handleExit(PointerExitEvent event) {
    if (!_hovered) return;
    setState(() => _hovered = false);
  }

  void _handlePointerDown(PointerDownEvent event) =>
      _host._handlePointerDown(widget.details.row.id, event);

  void _handleTapUp(TapUpDetails details) =>
      _host._handlePrimaryTap(widget.details.row, details, context);

  void _handleSecondaryTapUp(TapUpDetails details) => _host._handleSecondaryTap(
    widget.details.row,
    details.globalPosition,
    context,
  );

  void _handleLongPressStart(LongPressStartDetails details) => _host
      ._handleSecondaryTap(widget.details.row, details.globalPosition, context);

  void _handleSemanticTap() =>
      _host._handleSemanticTap(widget.details, context);

  void _handleSemanticExpand() =>
      _host._handleSemanticExpansion(widget.details.row, context, expand: true);

  void _handleSemanticCollapse() => _host._handleSemanticExpansion(
    widget.details.row,
    context,
    expand: false,
  );

  void _handleSemanticActivate() =>
      _host._handleSemanticActivate(widget.details.row, context);

  void _handleSemanticLongPress() {
    final box = context.findRenderObject();
    final position = box is RenderBox && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset.zero;
    _host._handleSecondaryTap(widget.details.row, position, context);
  }

  Map<Type, GestureRecognizerFactory> _gestures({
    required bool longPress,
    required DeviceGestureSettings? gestureSettings,
  }) {
    // Like GestureDetector, the recognizers use the device's touch slop.
    return <Type, GestureRecognizerFactory>{
      TapGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onTapUp = _handleTapUp
              ..onSecondaryTapUp = _handleSecondaryTapUp
              ..gestureSettings = gestureSettings,
          ),
      if (longPress)
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                debugOwner: this,
                supportedDevices: const <PointerDeviceKind>{
                  PointerDeviceKind.touch,
                },
              ),
              (recognizer) => recognizer
                ..onLongPressStart = _handleLongPressStart
                ..gestureSettings = gestureSettings,
            ),
    };
  }

  /// The custom semantics actions of the row [details] describes, or null
  /// when it has none.
  Map<CustomSemanticsAction, VoidCallback>? _customActions(
    BuildContext context,
    SliverDirectoryTree<T> config,
    DirectoryTreeRowDetails<T> details,
  ) {
    final failed = details.loadStatus == DirectoryLoadStatus.failed;
    // VoiceOver has no expand and collapse actions.
    final platform = defaultTargetPlatform;
    final expansionActions =
        details.isExpandable &&
        !kIsWeb &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS);
    final activates = config.onActivate != null;
    if (!failed && !expansionActions && !activates) return null;
    final localizations =
        Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) ??
        const DefaultMaterialLocalizations();
    final expanded = details.row.isExpanded;
    return <CustomSemanticsAction, VoidCallback>{
      if (activates)
        CustomSemanticsAction(label: config.activateSemanticsLabel):
            _handleSemanticActivate,
      if (failed)
        CustomSemanticsAction(
          label: localizations.refreshIndicatorSemanticLabel,
        ): _handleSemanticExpand,
      if (expansionActions && expanded)
        CustomSemanticsAction(label: localizations.expandedIconTapHint):
            _handleSemanticCollapse,
      if (expansionActions && !expanded)
        CustomSemanticsAction(label: localizations.collapsedIconTapHint):
            _handleSemanticExpand,
    };
  }

  @override
  Widget build(BuildContext context) {
    final config = _host.widget;
    var details = widget.details;
    if (_hovered) details = details.copyWith(isHovered: true);
    final row = details.row;
    final checkState = details.checkState;

    Widget child = RowSemanticsScope(
      child:
          config.rowBuilder?.call(context, details) ??
          DirectoryTreeRow<T>(details: details),
    );
    child = MouseRegion(
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: Listener(
        onPointerDown: _handlePointerDown,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: _gestures(
            longPress: config.secondaryTapOnLongPress,
            gestureSettings: MediaQuery.maybeGestureSettingsOf(context),
          ),
          excludeFromSemantics: true,
          child: child,
        ),
      ),
    );
    final decorator = config.rowDecorator;
    if (decorator != null) child = decorator(context, details, child);
    child = Semantics(
      container: true,
      label: row.label,
      value: switch (details.loadStatus) {
        DirectoryLoadStatus.loading => config.loadingSemanticsLabel,
        DirectoryLoadStatus.failed => config.loadFailedSemanticsLabel,
        DirectoryLoadStatus.notLoaded || DirectoryLoadStatus.loaded => null,
      },
      hint: _host._levelHint(row.depth + 1),
      selected: details.isSelected,
      expanded: details.isExpandable ? row.isExpanded : null,
      checked: checkState == null ? null : checkState == CheckState.checked,
      mixed: checkState == null ? null : checkState == CheckState.partial,
      // The keyboard cursor, while the tree has keyboard focus. Only that
      // row changes on a focus move.
      focusable: details.isFocused && details.hasFocus ? true : null,
      focused: details.isFocused && details.hasFocus ? true : null,
      onTap: _handleSemanticTap,
      onLongPress: config.onRowSecondaryTap == null
          ? null
          : _handleSemanticLongPress,
      onExpand: details.isExpandable && !row.isExpanded
          ? _handleSemanticExpand
          : null,
      onCollapse: details.isExpandable && row.isExpanded
          ? _handleSemanticCollapse
          : null,
      customSemanticsActions: _customActions(context, config, details),
      child: child,
    );
    if (_animatesIn) {
      child = _InsertTransition(
        duration: _host._insertDuration,
        curve: _host._insertCurve,
        child: child,
      );
    }
    return child;
  }
}

/// Fades and slides in a row that an expansion or a lazy load inserted.
class _InsertTransition extends StatefulWidget {
  const _InsertTransition({
    required this.duration,
    required this.curve,
    required this.child,
  });

  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_InsertTransition> createState() => _InsertTransitionState();
}

class _InsertTransitionState extends State<_InsertTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  // Rows slide down from a quarter of their height above their place.
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -0.25),
    end: Offset.zero,
  ).animate(_progress);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
