import 'dart:async';
import 'dart:math' as math;

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/controller/tree_rows_change.dart';

/// The state of one directory tree view: the [tree], the visible [rows],
/// expansion, selection, checkboxes, keyboard focus, search, and lazy
/// loading, with the commands that change them.
///
/// A controller holds immutable values from `package:directory_tree`
/// ([DirectoryTree], [TreeRows], [ExpansionState], [SelectionState],
/// [TreeQuery]) and swaps them on every command. Widgets read the current
/// values and listen for changes; they never mutate anything themselves.
/// Create one in `State.initState`, pass it to the tree widgets, and
/// [dispose] it in `State.dispose`.
///
/// ```dart
/// final controller = DirectoryTreeController(
///   tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/README.md']),
/// );
/// controller.expand(controller.tree.roots.single);
/// print(controller.rows.map((row) => row.label)); // (repo, lib, README.md)
/// controller.query = 'main'; // rows: repo, lib, main.dart
/// ```
///
/// ## Notifications
///
/// Every command that changes observable state calls [notifyListeners]
/// exactly once, after all of its changes are applied; a command that
/// changes nothing does not notify. Setters compare the new value with `==`
/// ([tree] compares by identity). Lazy loads finishing later notify on
/// their own. Unknown [NodeId]s are never an error: commands ignore them
/// and queries answer `null`, `false`, -1, or an empty result.
///
/// ## Rows and expansion
///
/// [rows] always equal what [DirectoryTree.flatten] returns for
/// `rows.expansion`, the effective filter, `expandMatches: false`, and the
/// current [compactFolders] and [showRoots]. Expanding or collapsing one
/// directory updates the rows incrementally, so only the rows that appear
/// or disappear are built and every other [TreeRow] stays the identical
/// object; [lastRowsChange] tells a list view which block of rows changed.
///
/// There are two expansion states. [expansion] is the requested one: what
/// the user and the app asked for, which never contains the directories a
/// search opened, so it is the one to persist. `rows.expansion` is the
/// effective one on screen: the same as [expansion] when nothing is
/// filtered, and [expansion] plus the ancestors of the matches after a
/// filter change. Every expansion command changes both states the same way.
///
/// ## Search
///
/// [query] (parsed as a [TreeQuery]) and [filter] together form the
/// effective filter. Each change of it shows the matches on top of
/// [expansion] (see [revealMatches]); clearing it shows [expansion] again
/// with the focused node revealed.
///
/// ## Lazy loading
///
/// With a `loadChildren` loader, directories without children load their
/// children when they are expanded (see [loadStatusOf]). Loads never throw:
/// failures are reported through `onLoadError` and [loadErrorOf].
///
/// ## Complexity
///
/// Focus moves and single selection changes cost O(log rows). Single
/// expansion toggles cost O(log rows + rows that appear or disappear) and
/// never call the filter. Full passes over the tree happen only on a new
/// [tree], filter changes, [compactFolders] and [showRoots] changes, and
/// bulk commands such as [expandAll], [selectAll], and [checkAll].
class DirectoryTreeController<T> extends ChangeNotifier {
  /// Creates a controller for [tree] (an empty tree when `null`).
  ///
  /// * [expansion] is the initial requested expansion; every directory
  ///   starts collapsed by default. With an active [query] or [filter], the
  ///   rows show it plus the ancestors of the matches.
  /// * [selection] and [checks] are the initial highlight selection and
  ///   checkbox state, both in [SelectionMode.multiple] by default. Ids that
  ///   [tree] does not contain are dropped.
  /// * `selectable` decides which nodes the selection commands may select;
  ///   every node by default. It does not affect [checks]. It must be pure
  ///   and cheap, since [selectAll] and [extendSelection] call it per row.
  /// * [query], [caseSensitiveQuery], [filter], and [revealMatches]: see the
  ///   properties of the same names.
  /// * [compactFolders] and [showRoots]: see the properties of the same
  ///   names.
  /// * [loadChildren] makes directories without children lazily loadable;
  ///   see [DirectoryChildrenLoader]. `onLoadError` is told about failed
  ///   loads (see [DirectoryLoadErrorCallback]).
  ///
  /// With a loader and [showRoots] false, every top-level directory without
  /// children starts loading right away.
  DirectoryTreeController({
    DirectoryTree<T>? tree,
    ExpansionState expansion = const ExpansionState.collapsed(),
    SelectionState selection = const SelectionState.empty(
      mode: SelectionMode.multiple,
    ),
    SelectionState checks = const SelectionState.empty(
      mode: SelectionMode.multiple,
    ),
    this._selectable,
    String query = '',
    bool caseSensitiveQuery = false,
    TreeFilter? filter,
    bool revealMatches = true,
    this._compactFolders = false,
    this._showRoots = true,
    DirectoryChildrenLoader<T>? loadChildren,
    this._onLoadError,
  }) : _tree = tree ?? DirectoryTree<T>.empty(),
       _requested = expansion,
       _query = query,
       _caseSensitiveQuery = caseSensitiveQuery,
       _filter = filter,
       _revealMatches = revealMatches,
       _loader = loadChildren {
    if (kFlutterMemoryAllocationsEnabled) {
      ChangeNotifier.maybeDispatchObjectCreation(this);
    }
    _selection = selection.prune(_tree);
    _checks = checks.prune(_tree);
    _parsedQuery = _parseQuery(query, caseSensitive: caseSensitiveQuery);
    _effectiveFilter = _combineFilters(_parsedQuery, filter);
    _rows = _flatten(
      expansion,
      expandMatches: _effectiveFilter != null && revealMatches,
    );
    _lastRowsChange = const TreeRowsChange.reset(previous: null);
    _loadHiddenRoots();
    // Nobody listens yet, so the statuses set above need no notification.
    _dirty = false;
  }

  DirectoryTree<T> _tree;
  late TreeRows<T> _rows;
  late TreeRowsChange _lastRowsChange;

  // The requested expansion. While nothing is filtered it equals
  // _rows.expansion (usually as the same object); while filtering,
  // _rows.expansion adds the directories the search revealed.
  ExpansionState _requested;

  late SelectionState _selection;
  late SelectionState _checks;
  final bool Function(TreeNode<T> node)? _selectable;

  String _query;
  bool _caseSensitiveQuery;
  late TreeQuery? _parsedQuery;
  TreeFilter? _filter;
  late TreeFilter? _effectiveFilter;
  bool _revealMatches;
  bool _compactFolders;
  bool _showRoots;

  // Always the id of a row (rows[focusedIndex].id) or null.
  NodeId? _focusedId;

  final DirectoryChildrenLoader<T>? _loader;
  final DirectoryLoadErrorCallback? _onLoadError;

  // Statuses that differ from what the tree implies (see loadStatusOf):
  // loading, failed, and loaded directories that stayed empty.
  final Map<NodeId, DirectoryLoadStatus> _statusOverrides =
      <NodeId, DirectoryLoadStatus>{};
  final Map<NodeId, Object> _loadErrors = <NodeId, Object>{};

  // The in-flight load per directory. A finishing load applies its result
  // only while it is still the entry here; replacing the tree, reloading an
  // ancestor, and dispose drop entries, which discards those loads.
  final Map<NodeId, _PendingLoad> _loads = <NodeId, _PendingLoad>{};

  // Leaf and checked-leaf counts per pre-order index, built on the first
  // checkStateOf after the tree or the checks changed.
  _CheckCounts? _checkCounts;

  final List<DirectoryTreeViewport> _viewports = <DirectoryTreeViewport>[];

  bool _disposed = false;

  // Set by every private mutation that changes observable state; a command
  // notifies once in _commit when it is set.
  bool _dirty = false;

  // The scroll a command asked for, run once it has notified.
  _Scroll? _pendingScroll;

  // ---------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------

  /// The tree this controller shows.
  ///
  /// Setting a tree that is not identical to the current one replaces it
  /// and keeps the view state by [NodeId], which makes it safe to refresh
  /// the data at any time (a file watcher, a finished drag and drop move):
  ///
  /// * [selection] and [checks] drop the ids the new tree does not contain.
  ///   A checked leaf (a file or an empty directory) that is now a
  ///   directory with children becomes checked as a whole: all of its
  ///   leaves are checked.
  /// * Both expansion states drop ids that are not directories of the new
  ///   tree.
  /// * The focus stays on its node when the node still exists, otherwise it
  ///   moves to the nearest ancestor of the old path that does, and then to
  ///   the nearest row that shows it (see [focusedId]).
  /// * Load statuses start over from the new tree (see [loadStatusOf]) and
  ///   loads still in flight are discarded when they finish. With a loader
  ///   and [showRoots] false, top-level directories without children start
  ///   loading.
  /// * [rows] are flattened again and [lastRowsChange] is a reset.
  ///
  /// Listeners are notified once. Runs in O(rows) plus the size of the
  /// selection, checks, and expansion; with a filter, O(n) for n nodes.
  DirectoryTree<T> get tree => _tree;

  set tree(DirectoryTree<T> value) {
    if (identical(value, _tree)) return;
    _applyTree(value, discardLoads: true);
    _loadHiddenRoots();
    _commit();
  }

  /// Replaces [tree] with `tree.rebuild(update)`, applying the rules of the
  /// [tree] setter.
  ///
  /// Use it for small edits, such as adding a created file or removing a
  /// deleted folder:
  ///
  /// ```dart
  /// controller.updateTree((builder) => builder.addFile('/repo/lib/new.dart'));
  /// ```
  void updateTree(void Function(DirectoryTreeBuilder<T> builder) update) {
    tree = _tree.rebuild(update);
  }

  // ---------------------------------------------------------------------
  // Rows
  // ---------------------------------------------------------------------

  /// The visible rows, in display order.
  ///
  /// Whenever listeners run, these equal what [DirectoryTree.flatten]
  /// returns for `rows.expansion` (the effective expansion state), the
  /// effective filter, `expandMatches: false`, and the current
  /// [compactFolders] and [showRoots]. A new object after every change that
  /// affects rows; unchanged rows of an expansion toggle are the identical
  /// [TreeRow] objects as before.
  TreeRows<T> get rows => _rows;

  /// How [rows] changed in their latest update.
  ///
  /// A splice when one directory expanded or collapsed incrementally
  /// (`index` is the row after it) and after a lazy load (the block of the
  /// loaded directory); a reset for every other change. It changes exactly
  /// when [rows] changes and its [TreeRowsChange.previous] is the rows
  /// object that was replaced. Before the first change it is a reset whose
  /// `previous` is `null`.
  TreeRowsChange get lastRowsChange => _lastRowsChange;

  /// Whether the directory [id] can show children, so a view should draw an
  /// expand arrow for it.
  ///
  /// True for a directory whose row has children ([TreeRow.hasChildren],
  /// which honors the filter and compacted rows), and, with a loader and no
  /// effective filter, for a directory without children whose
  /// [loadStatusOf] is [DirectoryLoadStatus.notLoaded],
  /// [DirectoryLoadStatus.loading], or [DirectoryLoadStatus.failed]. For a
  /// directory without a row, the tree decides when nothing is filtered (it
  /// has children) and the answer is false while filtering, apart from the
  /// lazy-loading rule. False for files and unknown ids. O(log rows).
  bool isExpandable(NodeId id) {
    final node = _tree[id];
    if (node is! DirectoryNode<T>) return false;
    final row = _rows.rowOf(id);
    if (row != null) {
      if (row.hasChildren) return true;
    } else if (_effectiveFilter == null && node.hasChildren) {
      return true;
    }
    return _loader != null &&
        _effectiveFilter == null &&
        !node.hasChildren &&
        loadStatusOf(id) != DirectoryLoadStatus.loaded;
  }

  // ---------------------------------------------------------------------
  // Expansion
  // ---------------------------------------------------------------------

  /// The requested expansion state: the directories the user and the app
  /// asked to expand, without the ones a search revealed.
  ///
  /// Persist this value (for example with [ExpansionState.toJson]) to
  /// restore the view later. While nothing is filtered it equals
  /// `rows.expansion`; while filtering, `rows.expansion` also holds the
  /// ancestors of the matches. Ids are not checked against the tree.
  ///
  /// Setting it replaces both states with the value as given (while
  /// filtering, the search reveals disappear until the next filter change)
  /// and recomputes [rows] (a reset). It starts no loads.
  ExpansionState get expansion => _requested;

  set expansion(ExpansionState value) {
    if (value == _requested) return;
    _transformExpansion((_) => value);
    _commit();
  }

  /// Whether the directory [id] is expanded in the effective state
  /// (`rows.expansion`), so its children show when its row is visible.
  ///
  /// Top-level directories count as expanded while [showRoots] is false,
  /// whatever the state says. False for files and unknown ids. O(1).
  bool isExpanded(NodeId id) {
    final node = _tree[id];
    if (node is! DirectoryNode<T>) return false;
    if (!_showRoots && node.isRoot) return true;
    return _rows.expansion.isExpanded(id);
  }

  /// Expands the directory [id] in both expansion states, inserting its
  /// visible descendants after its row.
  ///
  /// For an id inside a compacted row the row's directory (its deepest)
  /// expands, as [TreeRows.expandNode] does. A directory without a row only
  /// changes its state. When that directory has no children, a loader, and
  /// the status [DirectoryLoadStatus.notLoaded] or
  /// [DirectoryLoadStatus.failed], this also starts [loadChildren] for it
  /// unless the effective filter hides it; this happens even when it is
  /// already expanded, which retries a failed load.
  ///
  /// Does nothing for files, unknown ids, and top-level directories while
  /// [showRoots] is false. [lastRowsChange] becomes a splice after the row
  /// (a reset when the directory has no row). O(log rows + new rows).
  void expand(NodeId id) {
    final node = _tree[id];
    if (node is! DirectoryNode<T>) return;
    final target = _rows.rowOf(id)?.node ?? node;
    _toggle(node, expand: true);
    if (target is DirectoryNode<T> && _loadsOnExpand(target)) {
      unawaited(_startLoad(target));
    }
    _commit();
  }

  /// Collapses the directory [id] in both expansion states, removing its
  /// visible descendants.
  ///
  /// Descendants keep their own state, so expanding again restores them. A
  /// focused row that disappears moves the focus to the collapsed row. For
  /// an id inside a compacted row the whole row collapses. Does nothing for
  /// files, unknown ids, and top-level directories while [showRoots] is
  /// false. [lastRowsChange] becomes a splice after the row (a reset when
  /// the directory has no row). O(log rows).
  void collapse(NodeId id) {
    final node = _tree[id];
    if (node is! DirectoryNode<T>) return;
    _toggle(node, expand: false);
    _commit();
  }

  /// Collapses the directory [id] when it is expanded on screen (its row's
  /// state, or the effective state without a row), otherwise [expand]s it,
  /// which may start a load.
  ///
  /// This is what a click on an expand arrow does. For a compacted row, the
  /// state that flips is the state of the row's directory.
  void toggleExpansion(NodeId id) {
    final node = _tree[id];
    if (node is! DirectoryNode<T>) return;
    final row = _rows.rowOf(id);
    final expanded = row != null ? row.isExpanded : isExpanded(id);
    if (expanded) {
      collapse(id);
    } else {
      expand(id);
    }
  }

  /// Expands every directory: both expansion states become
  /// `const ExpansionState.expanded()`.
  ///
  /// Starts no loads, so lazily loaded directories show as expanded with no
  /// children until they load. Full recompute of [rows] (a reset), O(rows).
  void expandAll() {
    _transformExpansion((_) => const ExpansionState.expanded());
    _commit();
  }

  /// Collapses every directory: both expansion states become
  /// `const ExpansionState.collapsed()`.
  ///
  /// The focus moves to the depth-0 row that contains the focused node.
  /// Starts no loads. Full recompute of [rows] (a reset), O(rows).
  void collapseAll() {
    _transformExpansion((_) => const ExpansionState.collapsed());
    _commit();
  }

  /// Expands the directory [id] and every directory below it in both
  /// expansion states, with [ExpansionState.expandSubtree].
  ///
  /// Starts no loads. Does nothing for files and unknown ids. Full
  /// recompute of [rows] (a reset), O(rows + subtree size).
  void expandSubtree(NodeId id) {
    _transformExpansion((state) => state.expandSubtree(_tree, id));
    _commit();
  }

  /// Collapses the directory [id] and every directory below it in both
  /// expansion states, with [ExpansionState.collapseSubtree].
  ///
  /// A focused row that disappears moves the focus to the nearest row that
  /// contains it. Starts no loads. Does nothing for files and unknown ids.
  /// Full recompute of [rows] (a reset), O(rows + subtree size).
  void collapseSubtree(NodeId id) {
    _transformExpansion((state) => state.collapseSubtree(_tree, id));
    _commit();
  }

  /// Makes the node [id] visible by expanding its ancestors in both
  /// expansion states, then focuses, selects, and scrolls to it as asked.
  ///
  /// Use it to show a search result or a file opened elsewhere. A node that
  /// already has a row, including a directory inside a compacted row,
  /// changes no expansion at all. Returns whether the node has a row
  /// afterwards: false for unknown ids, for nodes the effective filter
  /// hides, and for top-level nodes while [showRoots] is false. With
  /// [focus] (the default) and a row, the row is focused. With [select],
  /// the node becomes the selection, as [DirectoryTreeController.select]
  /// does, when it is selectable, even without a row. With [scroll] (the
  /// default) and a row, [ensureVisible]
  /// runs after listeners are notified with [alignment], [duration], and
  /// [curve]: the default `null` alignment scrolls minimally and instantly,
  /// while for example `alignment: 0` with a duration puts the row at the
  /// top with an animation. Starts no loads.
  ///
  /// Notifies at most once. O(rows) when ancestors had to expand,
  /// O(log rows) otherwise.
  bool reveal(
    NodeId id, {
    bool focus = true,
    bool select = false,
    bool scroll = true,
    double? alignment,
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
  }) {
    if (!_tree.contains(id)) return false;
    if (_rows.indexOfNode(id) < 0) {
      _transformExpansion((state) => state.reveal(_tree, id));
    }
    final index = _rows.indexOfNode(id);
    if (select && isSelectable(id)) _setSelection(_selection.select(id));
    if (index >= 0) {
      if (focus) _setFocus(_rows[index].id);
      if (scroll) {
        _pendingScroll = (
          id: id,
          duration: duration,
          curve: curve,
          alignment: alignment,
        );
      }
    }
    _commit();
    return index >= 0;
  }

  /// Resolves the raw [path] with [DirectoryTree.idOf] and [reveal]s that
  /// node.
  ///
  /// Returns the node's id, or `null` when [path] cannot be parsed or the
  /// tree has no node there (and then changes nothing). The id is returned
  /// even when the filter hides the node. Under
  /// [PathPolicy.caseInsensitive] any casing of the path finds the node.
  /// The other arguments work as in [reveal].
  NodeId? revealPath(
    String path, {
    bool focus = true,
    bool select = false,
    bool scroll = true,
    double? alignment,
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
  }) {
    final id = _tree.idOf(path);
    if (id == null || !_tree.contains(id)) return null;
    reveal(
      id,
      focus: focus,
      select: select,
      scroll: scroll,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
    return id;
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  /// The highlight selection: the rows a user clicked, shift-clicked, or
  /// moved to with the keyboard.
  ///
  /// It may hold nodes that have no row (inside collapsed directories or
  /// hidden by the filter); they stay selected. Setting it drops the ids
  /// the tree does not contain (see [SelectionState.prune]) and notifies
  /// when the result differs. The constructor's `selectable` predicate is
  /// not applied to a set value.
  SelectionState get selection => _selection;

  set selection(SelectionState value) {
    _setSelection(value.prune(_tree));
    _commit();
  }

  /// Whether [selection] holds at most one id or any number.
  ///
  /// Setting it converts the selection with [SelectionState.withMode]:
  /// switching to [SelectionMode.single] keeps the anchor when it is
  /// selected, else the only selected id, else nothing.
  SelectionMode get selectionMode => _selection.mode;

  set selectionMode(SelectionMode value) {
    _setSelection(_selection.withMode(value));
    _commit();
  }

  /// Whether the node [id] is in [selection]. O(1).
  bool isSelected(NodeId id) => _selection.isSelected(id);

  /// Whether the selection commands may select the node [id]: it is in the
  /// tree and the constructor's `selectable` predicate (if any) accepts
  /// it.
  ///
  /// False for unknown ids. Never affects [checks].
  bool isSelectable(NodeId id) {
    final node = _tree[id];
    if (node == null) return false;
    final selectable = _selectable;
    return selectable == null || selectable(node);
  }

  /// The selected nodes in pre-order (display order), as an unmodifiable
  /// list.
  ///
  /// Includes selected nodes without a row. Runs in O(k log k) for k
  /// selected ids.
  List<TreeNode<T>> get selectedNodes =>
      _nodesInPreOrder(_selection.selected, leavesOnly: false);

  /// Replaces the selection with the node [id] and makes it the anchor (a
  /// plain click).
  ///
  /// The selection changes only when [isSelectable] is true for [id]. With
  /// [focus] (the default) the row of [id] is focused even when it is not
  /// selectable, and [ensureVisible] runs after listeners are notified.
  /// Does nothing for unknown ids. O(log rows).
  void select(NodeId id, {bool focus = true}) {
    if (isSelectable(id)) _setSelection(_selection.select(id));
    if (focus) _focusRowOf(id, scroll: true);
    _commit();
  }

  /// Adds the node [id] to the selection or removes it (a Ctrl or Cmd
  /// click), with [SelectionState.toggle].
  ///
  /// In [SelectionMode.multiple] the node becomes the anchor; in
  /// [SelectionMode.single] it replaces the selection or clears it. Changes
  /// the selection only when [isSelectable] is true. [focus] works as in
  /// [select]. O(selection size + log rows).
  void toggleSelected(NodeId id, {bool focus = true}) {
    if (isSelectable(id)) _setSelection(_selection.toggle(id));
    if (focus) _focusRowOf(id, scroll: true);
    _commit();
  }

  /// Selects the range of visible selectable rows from the anchor to the
  /// node [id] (a Shift click), with [SelectionState.extendTo].
  ///
  /// The range runs over the ids of the visible rows that are selectable,
  /// in display order, and replaces the selection; the anchor stays. Falls
  /// back to [select] in [SelectionMode.single], without an anchor, and
  /// when the anchor or [id] has no row. Changes the selection only when
  /// [isSelectable] is true. [focus] works as in [select]. O(range size +
  /// log rows).
  void extendSelection(NodeId id, {bool focus = true}) {
    if (isSelectable(id)) _setSelection(_extendedSelection(id));
    if (focus) _focusRowOf(id, scroll: true);
    _commit();
  }

  /// Selects every visible selectable row, in [SelectionMode.multiple]
  /// only.
  ///
  /// The selection becomes exactly those rows' ids (nodes without a row
  /// are deselected). The anchor is kept when it is one of them, else it
  /// moves to the first. Does nothing in [SelectionMode.single]. O(rows).
  void selectAll() {
    if (_selection.mode != SelectionMode.multiple) return;
    final ids = <NodeId>[
      for (final row in _rows)
        if (_isRowSelectable(row)) row.id,
    ];
    NodeId? anchor;
    if (ids.isNotEmpty) {
      final current = _selection.anchor;
      final index = current == null ? -1 : _rows.indexOfNode(current);
      final keep =
          index >= 0 &&
          _rows[index].id == current &&
          _isRowSelectable(_rows[index]);
      anchor = keep ? current : ids.first;
    }
    _setSelection(
      SelectionState(
        mode: SelectionMode.multiple,
        selected: ids,
        anchor: anchor,
      ),
    );
    _commit();
  }

  /// Deselects everything and removes the anchor, keeping the mode.
  void clearSelection() {
    _setSelection(_selection.clear());
    _commit();
  }

  // ---------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------

  /// The checkbox state, with the tri-state semantics of [SelectionState]:
  /// leaves (files and directories without children) are checked or not,
  /// and a directory with children is checked, partial, or unchecked from
  /// its leaves.
  ///
  /// Independent of [selection] and of the `selectable` predicate. Setting
  /// it drops the ids the tree does not contain and notifies when the
  /// result differs.
  SelectionState get checks => _checks;

  set checks(SelectionState value) {
    _setChecks(value.prune(_tree));
    _commit();
  }

  /// The checkbox state of the node [id]: [CheckState.unchecked] for
  /// unknown ids.
  ///
  /// The first call after [tree] or [checks] changed counts the checked
  /// leaves of the whole tree once, in O(n); every other call is O(1).
  /// [toggleChecked] and [setChecked] update those counts in
  /// O(subtree size + depth) instead of starting over.
  CheckState checkStateOf(NodeId id) {
    final index = _tree.indexOf(id);
    if (index < 0) return CheckState.unchecked;
    return _counts().stateAt(index);
  }

  /// Unchecks the node [id] when it is checked, otherwise checks it (a
  /// click on its checkbox), so a partial directory becomes checked.
  ///
  /// Checking a node checks every leaf below it; unchecking unchecks them.
  /// In [SelectionMode.single] a node with more than one leaf cannot be
  /// checked ([SelectionState.canCheck] is false), so the call does nothing
  /// for it. Does nothing for unknown ids. O(checks size + subtree size).
  void toggleChecked(NodeId id) {
    final index = _tree.indexOf(id);
    if (index < 0) return;
    final checked = _checkStateAt(id, index) == CheckState.checked;
    _setCheckedAt(id, index, checked: !checked);
    _commit();
  }

  /// Checks the node [id] and every leaf below it when [checked] is true,
  /// otherwise unchecks them.
  ///
  /// Same rules and cost as [toggleChecked].
  void setChecked(NodeId id, {required bool checked}) {
    final index = _tree.indexOf(id);
    if (index < 0) return;
    _setCheckedAt(id, index, checked: checked);
    _commit();
  }

  /// Checks every leaf of the tree (every top-level node), in
  /// [SelectionMode.multiple] only.
  ///
  /// Does nothing in [SelectionMode.single]. O(n).
  void checkAll() {
    if (_checks.mode != SelectionMode.multiple) return;
    _setChecks(
      _checks.addAll(<NodeId>[
        for (final node in _tree.nodes)
          if (_isLeaf(node)) node.id,
      ]),
    );
    _commit();
  }

  /// Unchecks everything, with [SelectionState.clear].
  void uncheckAll() {
    _setChecks(_checks.clear());
    _commit();
  }

  /// The checked leaves (files and directories without children) in
  /// pre-order, as an unmodifiable list.
  ///
  /// Use it for a file picker's result. Runs in O(k log k) for k checked
  /// ids.
  List<TreeNode<T>> get checkedLeaves =>
      _nodesInPreOrder(_checks.selected, leavesOnly: true);

  /// The outermost checked nodes in pre-order, as an unmodifiable list: a
  /// checked directory stands for everything below it.
  ///
  /// Use it to act on whole folders, such as a "folders to back up" picker.
  /// The walk skips checked and unchecked subtrees, so once the counts of
  /// [checkStateOf] exist it visits only the checked nodes it returns and
  /// the partial directories with their children.
  List<TreeNode<T>> get checkedRoots {
    final nodes = _tree.nodes;
    final result = <TreeNode<T>>[];
    if (!_checks.isEmpty) {
      final counts = _counts();
      var index = 0;
      while (index < nodes.length) {
        final state = counts.stateAt(index);
        if (state == CheckState.partial) {
          index++;
          continue;
        }
        final node = nodes[index];
        if (state == CheckState.checked) result.add(node);
        index += _tree.subtreeSizeOf(node.id);
      }
    }
    return List<TreeNode<T>>.unmodifiable(result);
  }

  // ---------------------------------------------------------------------
  // Focus
  // ---------------------------------------------------------------------

  /// The id of the focused row (the keyboard cursor), or `null`.
  ///
  /// Always the [TreeRow.id] of a row of [rows] when not `null`: focusing a
  /// node inside a compacted row focuses that row. When the rows change
  /// and the focused node loses its row, the focus moves to the row that
  /// contains it (its nearest visible ancestor), or to `null` when there
  /// is none. After a filter change it moves to the first row that matches
  /// instead.
  NodeId? get focusedId => _focusedId;

  /// The focused row, or `null`. O(log rows).
  TreeRow<T>? get focusedRow {
    final index = focusedIndex;
    return index < 0 ? null : _rows[index];
  }

  /// The index of the focused row in [rows], or -1 when nothing is
  /// focused. O(log rows).
  int get focusedIndex {
    final id = _focusedId;
    return id == null ? -1 : _rows.indexOfNode(id);
  }

  /// Focuses the row that shows the node [id], or clears the focus when
  /// [id] is `null`.
  ///
  /// Returns false and changes nothing when [id] has no row (unknown,
  /// inside a collapsed directory, hidden by the filter, or a top-level
  /// node while [showRoots] is false). For a node inside a compacted row,
  /// that row is focused and [focusedId] becomes its id. With [scroll] (the
  /// default) [ensureVisible] runs after listeners are notified, also when
  /// the row was focused already. Does not change the selection.
  bool focus(NodeId? id, {bool scroll = true}) {
    if (id == null) {
      _setFocus(null);
      _commit();
      return true;
    }
    if (!_focusRowOf(id, scroll: scroll)) return false;
    _commit();
    return true;
  }

  /// Moves the focus like an arrow, Home, End, or Page key, then updates
  /// the selection as [selection] says.
  ///
  /// With nothing focused, [TreeFocusMove.last] and
  /// [TreeFocusMove.previous] go to the last row and every other move to
  /// the first row. Otherwise the moves clamp to the rows;
  /// [TreeFocusMove.parent] and [TreeFocusMove.firstChild] use
  /// [TreeRows.parentIndexOf] and [TreeRows.firstChildIndexOf] and do not
  /// move when those are `null`. The page moves go [pageSize] rows (at
  /// least 1), or by default the largest
  /// [DirectoryTreeViewport.pageRowCount] of the attached viewports, or 10
  /// without one.
  ///
  /// When the focus moved, [TreeSelectionUpdate.replace] selects the new
  /// row as [select] does, [TreeSelectionUpdate.extend] extends to it as
  /// [extendSelection] does, and [TreeSelectionUpdate.keep] leaves the
  /// selection alone; listeners are notified once and [ensureVisible] then
  /// scrolls the row into view. Returns false, and changes nothing, when
  /// the focus did not move (no rows, or already at the edge). O(log rows)
  /// plus the cost of the selection update.
  bool moveFocus(
    TreeFocusMove move, {
    TreeSelectionUpdate selection = TreeSelectionUpdate.replace,
    int? pageSize,
  }) {
    final rows = _rows;
    if (rows.isEmpty) return false;
    final current = focusedIndex;
    final last = rows.length - 1;
    final int target;
    if (current < 0) {
      target = move == TreeFocusMove.last || move == TreeFocusMove.previous
          ? last
          : 0;
    } else {
      target = switch (move) {
        TreeFocusMove.next => math.min(current + 1, last),
        TreeFocusMove.previous => math.max(current - 1, 0),
        TreeFocusMove.first => 0,
        TreeFocusMove.last => last,
        TreeFocusMove.pageDown => math.min(current + _pageSize(pageSize), last),
        TreeFocusMove.pageUp => math.max(current - _pageSize(pageSize), 0),
        TreeFocusMove.parent => rows.parentIndexOf(current) ?? current,
        TreeFocusMove.firstChild => rows.firstChildIndexOf(current) ?? current,
      };
    }
    if (target == current) return false;
    final id = rows[target].id;
    _setFocus(id);
    if (isSelectable(id)) {
      switch (selection) {
        case TreeSelectionUpdate.replace:
          _setSelection(_selection.select(id));
        case TreeSelectionUpdate.extend:
          _setSelection(_extendedSelection(id));
        case TreeSelectionUpdate.keep:
          break;
      }
    }
    _pendingScroll = _minimalScroll(id);
    _commit();
    return true;
  }

  // ---------------------------------------------------------------------
  // Search and filters
  // ---------------------------------------------------------------------

  /// The search text, exactly as set (no trimming), parsed with
  /// [TreeQuery.parse] into [parsedQuery].
  ///
  /// Setting it notifies when the text differs. When the parsed query
  /// differs too, the rows are filtered again: see [filter] for what a
  /// filter change does. An empty or whitespace-only query filters nothing.
  String get query => _query;

  set query(String value) {
    if (value == _query) return;
    _query = value;
    _dirty = true;
    _parsedQuery = _parseQuery(value, caseSensitive: _caseSensitiveQuery);
    _applyFilterChange();
    _commit();
  }

  /// Whether [query] compares names, globs, and `path:` terms with exact
  /// case; false by default.
  ///
  /// Setting it parses [query] again and filters again when the query has
  /// terms.
  bool get caseSensitiveQuery => _caseSensitiveQuery;

  set caseSensitiveQuery(bool value) {
    if (value == _caseSensitiveQuery) return;
    _caseSensitiveQuery = value;
    _dirty = true;
    _parsedQuery = _parseQuery(_query, caseSensitive: value);
    _applyFilterChange();
    _commit();
  }

  /// [query] parsed with [TreeQuery.parse], or `null` when it has no terms
  /// (it would match every node).
  TreeQuery? get parsedQuery => _parsedQuery;

  /// An extra filter combined with [parsedQuery]; `null` by default.
  ///
  /// The effective filter is [parsedQuery], this filter, or both joined
  /// with [TreeFilter.and]; a `null` filter or one whose
  /// [TreeFilter.matchesAll] is true counts as none. Every change of the
  /// effective filter recomputes the rows from the requested [expansion],
  /// adding the ancestors of every match to the effective state when
  /// [revealMatches] is true; [expansion] itself never gets those. When the
  /// effective filter goes away, the rows show [expansion] again, and a
  /// focused node that would be hidden is revealed (which expands its
  /// ancestors in [expansion] too) and scrolled to. After a change of the
  /// effective filter, a focused node without a row moves the focus to the
  /// first matching row (or clears it).
  ///
  /// Setting a value `==` to the current one does nothing. Each change of
  /// the effective filter is a full recompute, O(n), with a reset.
  TreeFilter? get filter => _filter;

  set filter(TreeFilter? value) {
    if (value == _filter) return;
    _filter = value;
    _dirty = true;
    _applyFilterChange();
    _commit();
  }

  /// Whether a filter change expands the ancestors of every match in the
  /// effective state, so all matches show; true by default.
  ///
  /// When false, matches inside collapsed directories stay hidden until
  /// the user expands them. Setting it while filtering filters again from
  /// the requested [expansion].
  bool get revealMatches => _revealMatches;

  set revealMatches(bool value) {
    if (value == _revealMatches) return;
    _revealMatches = value;
    _dirty = true;
    if (_effectiveFilter != null) _refilter();
    _commit();
  }

  /// Whether an effective filter is active (a [query] with terms, a
  /// [filter], or both).
  bool get isFiltering => _effectiveFilter != null;

  /// Whether a directory whose only child is a directory shares one row
  /// with it (`lib/src/utils`), as the compact folders of VS Code do;
  /// false by default.
  ///
  /// Such a row expands and collapses as its deepest directory. Setting it
  /// keeps both expansion states and recomputes [rows] (a reset, O(rows),
  /// O(n) with a filter); a focused directory that joins a compacted row
  /// focuses that row.
  bool get compactFolders => _compactFolders;

  set compactFolders(bool value) {
    if (value == _compactFolders) return;
    _compactFolders = value;
    _dirty = true;
    _setRows(
      _flatten(_rows.expansion, expandMatches: false),
      TreeRowsChange.reset(previous: _rows),
    );
    _maintainFocus();
    _commit();
  }

  /// Whether the top-level nodes are rows; true by default.
  ///
  /// Set it to false to show the contents of one folder whose name is a
  /// title rather than a row. Top-level nodes then have no row (so [focus]
  /// and [reveal] return false for them), count as expanded, and their
  /// children are the depth-0 rows. With a loader, every top-level
  /// directory whose status is [DirectoryLoadStatus.notLoaded] starts
  /// loading at construction, when [tree] is set, and when this becomes
  /// false. Setting it keeps both expansion states and recomputes [rows] (a
  /// reset, O(rows), O(n) with a filter); a focused top-level node loses
  /// the focus.
  bool get showRoots => _showRoots;

  set showRoots(bool value) {
    if (value == _showRoots) return;
    _showRoots = value;
    _dirty = true;
    _setRows(
      _flatten(_rows.expansion, expandMatches: false),
      TreeRowsChange.reset(previous: _rows),
    );
    _maintainFocus();
    _loadHiddenRoots();
    _commit();
  }

  /// The ranges of `row.label` that [parsedQuery] highlights, for a
  /// highlighted label widget.
  ///
  /// [TreeQuery.matchRanges] of the label when [parsedQuery] is not `null`
  /// and the row matched the effective filter itself ([TreeRow.isMatch]);
  /// otherwise an empty constant list. Ancestors shown only because a
  /// descendant matched get no highlight. Runs in O(terms x label length).
  List<({int start, int end})> matchRangesOf(TreeRow<T> row) {
    final query = _parsedQuery;
    if (query == null || !row.isMatch) {
      return const <({int start, int end})>[];
    }
    return query.matchRanges(row.label);
  }

  // ---------------------------------------------------------------------
  // Lazy loading
  // ---------------------------------------------------------------------

  /// The lazy-loading status of the directory [id].
  ///
  /// [DirectoryLoadStatus.loading] while a load runs and
  /// [DirectoryLoadStatus.failed] after a failed one. Otherwise a directory
  /// with children is [DirectoryLoadStatus.loaded], and one without
  /// children is [DirectoryLoadStatus.notLoaded] when the controller has a
  /// loader and nothing loaded it since the tree was set (else
  /// [DirectoryLoadStatus.loaded]). Files are loaded; unknown ids are not
  /// loaded. O(1).
  DirectoryLoadStatus loadStatusOf(NodeId id) {
    final node = _tree[id];
    if (node == null) return DirectoryLoadStatus.notLoaded;
    if (node is! DirectoryNode<T>) return DirectoryLoadStatus.loaded;
    final override = _statusOverrides[id];
    if (override != null) return override;
    return node.hasChildren || _loader == null
        ? DirectoryLoadStatus.loaded
        : DirectoryLoadStatus.notLoaded;
  }

  /// The error of the latest failed load of [id], or `null` when its
  /// status is not [DirectoryLoadStatus.failed].
  Object? loadErrorOf(NodeId id) => _loadErrors[id];

  /// Loads the children of the directory [id] with the controller's
  /// loader, unless they are loaded already.
  ///
  /// Starts a load for a directory whose status is
  /// [DirectoryLoadStatus.notLoaded] or [DirectoryLoadStatus.failed]: the
  /// status becomes [DirectoryLoadStatus.loading] (listeners are notified),
  /// and the loader runs in a later microtask. When it succeeds, the
  /// entries strictly inside the directory are merged into [tree]
  /// (`tree.rebuild((b) => b.addAll(entries))`, with the rules of the
  /// [tree] setter except that the load statuses of other directories are
  /// kept), a checked directory gets its new leaves checked, the directory
  /// becomes [DirectoryLoadStatus.loaded] even when nothing was added, and
  /// [lastRowsChange] is a splice at the directory's rows. When it fails,
  /// the status becomes [DirectoryLoadStatus.failed], [loadErrorOf] holds
  /// the error, the directory keeps its expansion, and the constructor's
  /// `onLoadError` is called. Each outcome notifies once.
  ///
  /// While a load of [id] runs, every call returns that load's future.
  /// The future completes when the result is applied, and never with an
  /// error. It completes right away without a loader, for files, unknown
  /// ids, loaded directories, and after [dispose]. A load is discarded,
  /// without a notification, when [tree] is set or an ancestor is reloaded
  /// before it finishes, and after [dispose].
  Future<void> loadChildren(NodeId id) {
    if (_loader == null || _disposed) return Future<void>.value();
    final pending = _loads[id];
    if (pending != null) return pending.future;
    final node = _tree[id];
    if (node is! DirectoryNode<T> ||
        loadStatusOf(id) == DirectoryLoadStatus.loaded) {
      return Future<void>.value();
    }
    final future = _startLoad(node);
    _commit();
    return future;
  }

  /// Removes the loaded contents of the directory [id] and loads them
  /// again, as a refresh button does.
  ///
  /// Every entry below the directory is removed from [tree] right away
  /// (the directory itself stays, as an explicit directory entry when it
  /// was inferred), with the rules of the [tree] setter except that the
  /// load statuses of other directories are kept and loads below the
  /// directory are discarded. A directory that was checked stays checked,
  /// so its reloaded leaves come back checked. Then a load starts as in
  /// [loadChildren], in the same notification. Returns the running load's
  /// future when a load of [id] is in progress already. Completes right
  /// away without a loader, for files, unknown ids, and after [dispose].
  Future<void> reloadChildren(NodeId id) {
    if (_loader == null || _disposed) return Future<void>.value();
    final pending = _loads[id];
    if (pending != null) return pending.future;
    final node = _tree[id];
    if (node is! DirectoryNode<T>) return Future<void>.value();
    if (node.hasChildren || !node.isExplicit) {
      final previousTree = _tree;
      final wasChecked =
          _checkStateAt(id, previousTree.indexOf(id)) == CheckState.checked;
      _loads.removeWhere((other, _) => previousTree.isAncestor(id, other));
      final path = node.path.toString();
      final entry = node.entry ?? TreeEntry<T>.directory(path);
      _applyTree(
        previousTree.rebuild(
          (builder) => builder
            ..remove(path)
            ..add(entry),
        ),
        discardLoads: false,
      );
      // The directory is a leaf now, so its own id carries its check state
      // until the reloaded entries arrive and inherit it.
      final ids = <NodeId>[id];
      _setChecks(wasChecked ? _checks.addAll(ids) : _checks.removeAll(ids));
    }
    final directory = _tree[id];
    if (directory is! DirectoryNode<T>) {
      _commit();
      return Future<void>.value();
    }
    final future = _startLoad(directory);
    _commit();
    return future;
  }

  // ---------------------------------------------------------------------
  // Viewports
  // ---------------------------------------------------------------------

  /// Registers [viewport] so [ensureVisible] scrolls it and [moveFocus]
  /// pages by its [DirectoryTreeViewport.pageRowCount].
  ///
  /// Views call it when they start showing this controller. Attaching a
  /// viewport twice has no effect. Does not notify.
  void attachViewport(DirectoryTreeViewport viewport) {
    if (_disposed || _viewports.contains(viewport)) return;
    _viewports.add(viewport);
  }

  /// Unregisters a viewport registered with [attachViewport].
  ///
  /// Views call it before they stop showing this controller. Does nothing
  /// for a viewport that is not attached. Does not notify.
  void detachViewport(DirectoryTreeViewport viewport) {
    _viewports.remove(viewport);
  }

  /// Scrolls every attached viewport to the row of the node [id], with
  /// [DirectoryTreeViewport.showRow] and the given [duration], [curve], and
  /// [alignment].
  ///
  /// With the default `null` [alignment] the scroll is minimal (nothing
  /// happens when the row is fully visible); 0 puts the row at the top, 1
  /// at the bottom, 0.5 in the middle. For a node inside a compacted row,
  /// that row is shown. Does nothing when the node has no row or no
  /// viewport is attached. The future completes when every viewport
  /// finished scrolling. Commands that move the focus call it for you, with
  /// a minimal, instant scroll.
  Future<void> ensureVisible(
    NodeId id, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  }) async {
    final index = _rows.indexOfNode(id);
    if (index < 0 || _viewports.isEmpty) return;
    await Future.wait<void>(<Future<void>>[
      for (final viewport in List<DirectoryTreeViewport>.of(_viewports))
        viewport.showRow(
          index,
          duration: duration,
          curve: curve,
          alignment: alignment,
        ),
    ]);
  }

  /// Discards the controller: loads still running are ignored when they
  /// finish, and viewports are released.
  ///
  /// The controller must not be used afterwards.
  @override
  void dispose() {
    _disposed = true;
    _loads.clear();
    _viewports.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Private: change tracking
  // ---------------------------------------------------------------------

  /// Ends a command: notifies once when something changed, then scrolls to
  /// the node the command asked for.
  void _commit() {
    final scroll = _pendingScroll;
    _pendingScroll = null;
    if (_disposed) {
      _dirty = false;
      return;
    }
    if (_dirty) {
      _dirty = false;
      notifyListeners();
    }
    if (scroll != null && _viewports.isNotEmpty) {
      unawaited(
        ensureVisible(
          scroll.id,
          duration: scroll.duration,
          curve: scroll.curve,
          alignment: scroll.alignment,
        ),
      );
    }
  }

  void _setRows(TreeRows<T> next, TreeRowsChange change) {
    if (identical(next, _rows)) return;
    _rows = next;
    _lastRowsChange = change;
    _dirty = true;
  }

  void _setRequested(ExpansionState next) {
    if (identical(next, _requested)) return;
    if (next != _requested) _dirty = true;
    _requested = next;
  }

  void _setSelection(SelectionState next) {
    if (identical(next, _selection) || next == _selection) return;
    _selection = next;
    _dirty = true;
  }

  void _setChecks(SelectionState next) {
    if (identical(next, _checks) || next == _checks) return;
    _checks = next;
    _checkCounts = null;
    _dirty = true;
  }

  void _setFocus(NodeId? id) {
    if (id == _focusedId) return;
    _focusedId = id;
    _dirty = true;
  }

  // ---------------------------------------------------------------------
  // Private: rows and expansion
  // ---------------------------------------------------------------------

  TreeRows<T> _flatten(
    ExpansionState expansion, {
    required bool expandMatches,
  }) => _tree.flatten(
    expansion: expansion,
    filter: _effectiveFilter,
    expandMatches: expandMatches,
    compactFolders: _compactFolders,
    showRoots: _showRoots,
  );

  /// Expands ([expand] true) or collapses [directory] in both states: the
  /// rows incrementally, with a splice right after its row, and the
  /// requested state for the same directory the rows changed.
  void _toggle(DirectoryNode<T> directory, {required bool expand}) {
    // Hidden roots always count as expanded; the core ignores them too.
    if (!_showRoots && directory.isRoot) return;
    final id = directory.id;
    final previous = _rows;
    final index = previous.indexOfNode(id);
    final next = expand ? previous.expandNode(id) : previous.collapseNode(id);
    if (!identical(next, previous)) {
      final TreeRowsChange change;
      if (index < 0) {
        // Only the state of a directory without a row changed.
        change = TreeRowsChange.reset(previous: previous);
      } else {
        // The core replaces the row itself and inserts or removes exactly
        // the block of its visible descendants right after it.
        final delta = next.length - previous.length;
        change = TreeRowsChange.splice(
          previous: previous,
          index: index + 1,
          removed: delta < 0 ? -delta : 0,
          inserted: delta > 0 ? delta : 0,
        );
      }
      _setRows(next, change);
      _maintainFocus();
    }
    if (_effectiveFilter == null) {
      _setRequested(_rows.expansion);
    } else {
      // An id inside a compacted row stands for the row's directory, which
      // is what the core expanded in the effective state.
      final target = index < 0 ? id : previous[index].id;
      _setRequested(_requested.setExpanded(target, expanded: expand));
    }
  }

  /// Applies [transform] to both expansion states and recomputes the rows
  /// from the effective one (no new filter calls, no new reveals).
  void _transformExpansion(
    ExpansionState Function(ExpansionState state) transform,
  ) {
    final requested = transform(_requested);
    final effective = _effectiveFilter == null
        ? requested
        : transform(_rows.expansion);
    _setRequested(requested);
    final previous = _rows;
    final next = previous.withExpansion(effective);
    if (identical(next, previous)) return;
    _setRows(next, TreeRowsChange.reset(previous: previous));
    _maintainFocus();
  }

  /// Moves the focus to a row after the rows changed: the focused node's
  /// own row, else (after a filter change) the first matching row, else
  /// the row of its nearest visible ancestor, else nothing.
  void _maintainFocus({bool afterFilterChange = false}) {
    final id = _focusedId;
    if (id == null) return;
    final rows = _rows;
    var index = rows.indexOfNode(id);
    if (index < 0) {
      if (afterFilterChange) {
        index = rows.indexWhere((row) => row.isMatch);
      } else {
        for (final ancestor in _tree.ancestorsOf(id)) {
          index = rows.indexOfNode(ancestor.id);
          if (index >= 0) break;
        }
      }
    }
    _setFocus(index < 0 ? null : rows[index].id);
  }

  /// Focuses the row of [id], asking [_commit] to scroll to it when
  /// [scroll]; returns whether [id] has a row.
  bool _focusRowOf(NodeId id, {required bool scroll}) {
    final index = _rows.indexOfNode(id);
    if (index < 0) return false;
    _setFocus(_rows[index].id);
    if (scroll) _pendingScroll = _minimalScroll(id);
    return true;
  }

  int _pageSize(int? pageSize) {
    if (pageSize != null) return math.max(1, pageSize);
    var largest = 0;
    for (final viewport in _viewports) {
      largest = math.max(largest, viewport.pageRowCount);
    }
    return largest > 0 ? largest : 10;
  }

  bool _isRowSelectable(TreeRow<T> row) {
    final selectable = _selectable;
    return selectable == null || selectable(row.node);
  }

  /// The selection after extending it to [id] over the visible selectable
  /// rows.
  SelectionState _extendedSelection(NodeId id) {
    final current = _selection;
    if (current.mode == SelectionMode.single) return current.select(id);
    // The range lies between the rows of the anchor and of id, so the walk
    // can start at the first of them instead of at row 0.
    final anchor = current.anchor;
    final anchorIndex = anchor == null ? -1 : _rows.indexOfNode(anchor);
    final idIndex = _rows.indexOfNode(id);
    final start = anchorIndex >= 0 && idIndex >= 0
        ? math.min(anchorIndex, idIndex)
        : 0;
    return current.extendTo(
      id,
      _rows.skip(start).where(_isRowSelectable).map((row) => row.id),
    );
  }

  // ---------------------------------------------------------------------
  // Private: filters
  // ---------------------------------------------------------------------

  static TreeQuery? _parseQuery(String query, {required bool caseSensitive}) {
    final parsed = TreeQuery.parse(query, caseSensitive: caseSensitive);
    return parsed.matchesAll ? null : parsed;
  }

  static TreeFilter? _combineFilters(TreeQuery? query, TreeFilter? filter) {
    final extra = filter == null || filter.matchesAll ? null : filter;
    if (query == null) return extra;
    if (extra == null) return query;
    return query.and(extra);
  }

  /// Recomputes the effective filter after [query], [caseSensitiveQuery],
  /// or [filter] changed, and filters the rows again when it differs.
  void _applyFilterChange() {
    final next = _combineFilters(_parsedQuery, _filter);
    if (next == _effectiveFilter) return;
    _effectiveFilter = next;
    _refilter();
  }

  /// Recomputes the rows from the requested state for the current
  /// effective filter: with the matches revealed while filtering, else with
  /// the focused node revealed.
  void _refilter() {
    final previous = _rows;
    if (_effectiveFilter != null) {
      _setRows(
        _flatten(_requested, expandMatches: _revealMatches),
        TreeRowsChange.reset(previous: previous),
      );
      _maintainFocus(afterFilterChange: true);
      return;
    }
    var rows = _flatten(_requested, expandMatches: false);
    final focused = _focusedId;
    if (focused != null && rows.indexOfNode(focused) < 0) {
      // The focused row may have been visible only through the search.
      _setRequested(_requested.reveal(_tree, focused));
      rows = rows.withExpansion(_requested);
    }
    _setRows(rows, TreeRowsChange.reset(previous: previous));
    _maintainFocus();
    final shown = _focusedId;
    if (shown != null) _pendingScroll = _minimalScroll(shown);
  }

  // ---------------------------------------------------------------------
  // Private: tree replacement
  // ---------------------------------------------------------------------

  /// Swaps in [next] with the rules of the [tree] setter. With
  /// [discardLoads] (the setter) load statuses start over and every
  /// running load is discarded, and the change is a reset; otherwise (a
  /// lazy merge or a reload) the statuses of directories that still exist
  /// are kept and the change is the splice between the old and new rows.
  void _applyTree(DirectoryTree<T> next, {required bool discardLoads}) {
    final previousTree = _tree;
    final previousRows = _rows;
    final focused = _focusedId == null
        ? null
        : _survivingId(previousTree, next, _focusedId!);
    _tree = next;
    _dirty = true;
    _checkCounts = null;
    _setSelection(_selection.prune(next));
    _setChecks(_adoptCheckedLeaves(previousTree, next, _checks.prune(next)));
    final requested = _requested.prune(next);
    final effective = _effectiveFilter == null
        ? requested
        : previousRows.expansion.prune(next);
    _setRequested(requested);
    if (discardLoads) {
      _statusOverrides.clear();
      _loadErrors.clear();
      _loads.clear();
    } else {
      _statusOverrides.removeWhere((id, _) => !next.contains(id));
      _loadErrors.removeWhere((id, _) => !next.contains(id));
      _loads.removeWhere((id, _) => !next.contains(id));
    }
    final rows = _flatten(effective, expandMatches: false);
    _setRows(
      rows,
      discardLoads
          ? TreeRowsChange.reset(previous: previousRows)
          : _spliceBetween(previousRows, rows),
    );
    _focusedId = focused;
    _maintainFocus();
  }

  /// [id] when [next] contains it, else the id of the nearest ancestor of
  /// its path in [previous] that [next] contains, else `null`.
  static NodeId? _survivingId(
    DirectoryTree<Object?> previous,
    DirectoryTree<Object?> next,
    NodeId id,
  ) {
    if (next.contains(id)) return id;
    final node = previous[id];
    if (node == null) return null;
    final policy = next.options.paths;
    for (var path = node.path.parent; path != null; path = path.parent) {
      final candidate = policy.idOf(path);
      if (next.contains(candidate)) return candidate;
    }
    return null;
  }

  /// [checks] with every checked leaf of [previous] that is a directory
  /// with children in [next] checked as a whole.
  ///
  /// The directory's own id is replaced by its leaves, as if it had been
  /// checked after its children appeared; a later uncheck of one of them
  /// then survives further tree replacements. In single mode, where one
  /// leaf fits, a directory with several leaves is unchecked instead.
  static SelectionState _adoptCheckedLeaves(
    DirectoryTree<Object?> previous,
    DirectoryTree<Object?> next,
    SelectionState checks,
  ) {
    if (checks.isEmpty) return checks;
    List<NodeId>? grown;
    for (final id in checks.selected) {
      final node = next[id];
      if (node is! DirectoryNode<Object?> || !node.hasChildren) continue;
      final before = previous[id];
      if (before != null && !_isLeaf(before)) continue;
      (grown ??= <NodeId>[]).add(id);
    }
    if (grown == null) return checks;
    if (checks.mode == SelectionMode.single) {
      // A single selection holds one id, so at most one directory grew.
      final id = grown.single;
      return checks.canCheck(next, id)
          ? checks.check(next, id)
          : checks.removeAll(grown);
    }
    final leaves = <NodeId>[for (final id in grown) ..._leavesOf(next, id)];
    return checks.addAll(leaves).removeAll(grown);
  }

  /// The splice that turns the row ids of [previous] into those of [next]:
  /// the longest common prefix and suffix stay, the middle is replaced.
  static TreeRowsChange _spliceBetween(
    TreeRows<Object?> previous,
    TreeRows<Object?> next,
  ) {
    final oldLength = previous.length;
    final newLength = next.length;
    final shorter = math.min(oldLength, newLength);
    var prefix = 0;
    while (prefix < shorter && previous[prefix].id == next[prefix].id) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        previous[oldLength - 1 - suffix].id ==
            next[newLength - 1 - suffix].id) {
      suffix++;
    }
    return TreeRowsChange.splice(
      previous: previous,
      index: prefix,
      removed: oldLength - prefix - suffix,
      inserted: newLength - prefix - suffix,
    );
  }

  // ---------------------------------------------------------------------
  // Private: checks
  // ---------------------------------------------------------------------

  _CheckCounts _counts() => _checkCounts ??= _CheckCounts.build(_tree, _checks);

  /// The check state of [id] at pre-order [index], from the counts when
  /// they exist (without building them), else from the subtree.
  CheckState _checkStateAt(NodeId id, int index) =>
      _checkCounts?.stateAt(index) ?? _checks.checkStateOf(_tree, id);

  void _setCheckedAt(NodeId id, int index, {required bool checked}) {
    final current = _checks;
    final SelectionState next;
    if (checked) {
      // A single selection cannot hold several leaves; the core would
      // throw, and a click must never throw.
      if (!current.canCheck(_tree, id)) return;
      next = current.check(_tree, id);
    } else {
      next = current.uncheck(_tree, id);
    }
    if (identical(next, current)) return;
    _checks = next;
    _dirty = true;
    final counts = _checkCounts;
    if (counts != null && current.mode == SelectionMode.multiple) {
      // In multiple mode only leaves inside the subtree changed.
      counts.updateSubtree(_tree, next, index);
    } else {
      _checkCounts = null;
    }
  }

  List<TreeNode<T>> _nodesInPreOrder(
    Iterable<NodeId> ids, {
    required bool leavesOnly,
  }) {
    final tree = _tree;
    final nodes = tree.nodes;
    final indexes = <int>[];
    for (final id in ids) {
      final index = tree.indexOf(id);
      if (index < 0 || (leavesOnly && !_isLeaf(nodes[index]))) continue;
      indexes.add(index);
    }
    indexes.sort();
    return List<TreeNode<T>>.unmodifiable(<TreeNode<T>>[
      for (final index in indexes) nodes[index],
    ]);
  }

  // ---------------------------------------------------------------------
  // Private: loading
  // ---------------------------------------------------------------------

  /// Whether [expand] on [directory] should start a load: a lazy directory
  /// that never loaded or failed, and is not filtered out.
  bool _loadsOnExpand(DirectoryNode<T> directory) {
    if (_loader == null || directory.hasChildren) return false;
    if (_loads.containsKey(directory.id)) return false;
    final status = loadStatusOf(directory.id);
    if (status != DirectoryLoadStatus.notLoaded &&
        status != DirectoryLoadStatus.failed) {
      return false;
    }
    // A lazy directory has no children, so the filter shows it exactly when
    // it matches itself.
    final filter = _effectiveFilter;
    return filter == null || filter.matches(directory);
  }

  /// Starts loading the top-level directories that are not loaded while
  /// they are hidden, since no row could expand them.
  void _loadHiddenRoots() {
    if (_showRoots || _loader == null || _disposed) return;
    for (final root in _tree.rootNodes) {
      if (root is DirectoryNode<T> &&
          !_loads.containsKey(root.id) &&
          loadStatusOf(root.id) == DirectoryLoadStatus.notLoaded) {
        unawaited(_startLoad(root));
      }
    }
  }

  /// Marks [directory] as loading and schedules its loader; the caller
  /// commits.
  Future<void> _startLoad(DirectoryNode<T> directory) {
    final id = directory.id;
    final load = _PendingLoad();
    _loads[id] = load;
    _statusOverrides[id] = DirectoryLoadStatus.loading;
    _loadErrors.remove(id);
    _dirty = true;
    return load.future = _runLoad(directory, load);
  }

  Future<void> _runLoad(DirectoryNode<T> directory, _PendingLoad load) async {
    final loader = _loader!;
    final List<TreeEntry<T>> entries;
    try {
      // A microtask keeps loader code out of the command that started the
      // load (which notifies first), and turns a synchronous throw into an
      // ordinary failure.
      final result = await Future<Iterable<TreeEntry<T>>>.microtask(
        () => loader(directory),
      );
      entries = List<TreeEntry<T>>.of(result);
    } on Object catch (error, stackTrace) {
      if (_isCurrent(directory.id, load)) {
        _failLoad(directory.id, error, stackTrace);
      }
      return;
    }
    if (_isCurrent(directory.id, load)) _finishLoad(directory.id, entries);
  }

  bool _isCurrent(NodeId id, _PendingLoad load) =>
      !_disposed && identical(_loads[id], load);

  void _finishLoad(NodeId id, List<TreeEntry<T>> entries) {
    _loads.remove(id);
    final tree = _tree;
    final directory = tree[id];
    if (directory is DirectoryNode<T>) {
      final accepted = _entriesInside(directory, entries, tree.options.paths);
      // The directory had no children when its load started, so these
      // entries cannot change the status of any other existing directory.
      if (accepted.isNotEmpty) {
        _applyTree(
          tree.rebuild((builder) => builder.addAll(accepted)),
          discardLoads: false,
        );
      }
      _statusOverrides[id] = DirectoryLoadStatus.loaded;
    } else {
      _statusOverrides.remove(id);
    }
    _loadErrors.remove(id);
    _dirty = true;
    _commit();
  }

  void _failLoad(NodeId id, Object error, StackTrace stackTrace) {
    _loads.remove(id);
    _statusOverrides[id] = DirectoryLoadStatus.failed;
    _loadErrors[id] = error;
    _dirty = true;
    _commit();
    final callback = _onLoadError;
    if (callback == null) return;
    try {
      callback(id, error, stackTrace);
    } on Object catch (callbackError, callbackStack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: callbackError,
          stack: callbackStack,
          library: 'flutter_directory_tree',
          context: ErrorDescription('while reporting a failed directory load'),
        ),
      );
    }
  }

  /// The entries strictly inside [directory] under [policy], comparing ids
  /// so that a case-insensitive policy accepts any casing.
  static List<TreeEntry<T>> _entriesInside<T>(
    DirectoryNode<T> directory,
    List<TreeEntry<T>> entries,
    PathPolicy policy,
  ) {
    final depth = directory.path.segments.length;
    final accepted = <TreeEntry<T>>[];
    for (final entry in entries) {
      final path = policy.tryParse(entry.path);
      if (path == null || path.segments.length <= depth) continue;
      // Climb to the ancestor at the directory's depth and compare ids.
      var ancestor = path;
      for (var level = path.segments.length; level > depth; level--) {
        ancestor = ancestor.parent!;
      }
      if (policy.idOf(ancestor) == directory.id) accepted.add(entry);
    }
    return accepted;
  }
}

/// A file, or a directory without children: what check states count.
bool _isLeaf(TreeNode<Object?> node) => switch (node) {
  FileNode<Object?>() => true,
  DirectoryNode<Object?>(:final hasChildren) => !hasChildren,
};

/// The leaves in the subtree of [id], in pre-order.
List<NodeId> _leavesOf(DirectoryTree<Object?> tree, NodeId id) {
  final index = tree.indexOf(id);
  if (index < 0) return const <NodeId>[];
  final nodes = tree.nodes;
  final end = index + tree.subtreeSizeOf(id);
  return <NodeId>[
    for (var i = index; i < end; i++)
      if (_isLeaf(nodes[i])) nodes[i].id,
  ];
}

/// A scroll request: the node and the [DirectoryTreeViewport.showRow]
/// arguments.
typedef _Scroll = ({
  NodeId id,
  Duration duration,
  Curve curve,
  double? alignment,
});

/// The minimal, instant scroll to [id] that focus changes use.
_Scroll _minimalScroll(NodeId id) => (
  id: id,
  duration: Duration.zero,
  curve: Curves.easeOutCubic,
  alignment: null,
);

/// One running load; the controller applies its result only while it is
/// the directory's entry in the controller's load map.
final class _PendingLoad {
  late final Future<void> future;
}

/// Leaf and checked-leaf counts per pre-order index of one tree, from which
/// every check state follows in O(1).
final class _CheckCounts {
  _CheckCounts._(this.leaves, this.checked);

  /// Counts every node of [tree] for [checks] in one reverse pre-order
  /// pass: a node's descendants come after it, so they are complete before
  /// they are added to their parent.
  factory _CheckCounts.build(
    DirectoryTree<Object?> tree,
    SelectionState checks,
  ) {
    final nodes = tree.nodes;
    final count = nodes.length;
    final leaves = Int32List(count);
    final checked = Int32List(count);
    for (var i = count - 1; i >= 0; i--) {
      final node = nodes[i];
      if (_isLeaf(node)) {
        leaves[i] = 1;
        if (checks.isSelected(node.id)) checked[i] = 1;
      }
      final parent = node.parent;
      if (parent != null) {
        final parentIndex = tree.indexOf(parent);
        leaves[parentIndex] += leaves[i];
        checked[parentIndex] += checked[i];
      }
    }
    return _CheckCounts._(leaves, checked);
  }

  final Int32List leaves;
  final Int32List checked;

  CheckState stateAt(int index) {
    final count = checked[index];
    if (count == 0) return CheckState.unchecked;
    return count == leaves[index] ? CheckState.checked : CheckState.partial;
  }

  /// Recounts the subtree at [index] for [checks] and adds the difference
  /// to its ancestors, after a change confined to that subtree.
  void updateSubtree(
    DirectoryTree<Object?> tree,
    SelectionState checks,
    int index,
  ) {
    final nodes = tree.nodes;
    final root = nodes[index];
    final end = index + tree.subtreeSizeOf(root.id);
    final before = checked[index];
    checked.fillRange(index, end, 0);
    for (var i = end - 1; i >= index; i--) {
      final node = nodes[i];
      if (_isLeaf(node) && checks.isSelected(node.id)) checked[i] += 1;
      if (i > index) checked[tree.indexOf(node.parent!)] += checked[i];
    }
    final delta = checked[index] - before;
    if (delta == 0) return;
    for (final ancestor in tree.ancestorsOf(root.id)) {
      checked[tree.indexOf(ancestor.id)] += delta;
    }
  }
}
