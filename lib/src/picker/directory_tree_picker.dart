import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_directory_tree/src/picker/initial_pick.dart';
import 'package:flutter_directory_tree/src/search/directory_tree_search_field.dart';
import 'package:flutter_directory_tree/src/view/directory_tree_view.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';

/// Which nodes a [DirectoryTreePicker] lets the user pick.
enum DirectoryTreePickerMode {
  /// Files only; directories open and close but are never picked.
  files,

  /// Directories only; files are shown but cannot be picked.
  directories,

  /// Files and directories.
  any,
}

/// Shows a dialog in which the user picks nodes of [tree], and returns
/// them, or `null` when the dialog is dismissed or cancelled.
///
/// The dialog is a [DirectoryTreePicker] (see there for how each [mode]
/// and [multiple] combination picks) with a Cancel button and a confirm
/// button labeled [confirmLabel]
/// ([MaterialLocalizations.okButtonLabel] when `null`). The confirm button
/// is enabled only while the pick is valid and not empty. In single mode,
/// activating a valid row (a double-click, or Enter) confirms it right
/// away. Escape, a tap outside the dialog, and the back button cancel.
///
/// The picker works on its own state, built from [tree],
/// [initialSelection], and [initialExpansion]; nothing in the app changes
/// until the result is used. [title] is shown above the tree when given.
///
/// ```dart
/// final picked = await showDirectoryTreePicker<void>(
///   context: context,
///   tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/README.md']),
///   title: 'Open file',
/// );
/// if (picked != null) debugPrint('open ${picked.single.path}');
/// ```
///
/// The returned list is in display order (pre-order) and holds no node
/// twice. It is never empty: an empty pick cannot be confirmed.
Future<List<TreeNode<T>>?> showDirectoryTreePicker<T>({
  required BuildContext context,
  required DirectoryTree<T> tree,
  DirectoryTreePickerMode mode = DirectoryTreePickerMode.files,
  bool multiple = false,
  Iterable<NodeId> initialSelection = const <NodeId>[],
  ExpansionState? initialExpansion,
  String? title,
  String? confirmLabel,
  bool showSearch = true,
  DirectoryTreeRowBuilder<T>? rowBuilder,
}) => showDialog<List<TreeNode<T>>>(
  context: context,
  builder: (context) => _DirectoryTreePickerDialog<T>(
    tree: tree,
    mode: mode,
    multiple: multiple,
    initialSelection: initialSelection,
    initialExpansion: initialExpansion,
    title: title,
    confirmLabel: confirmLabel,
    showSearch: showSearch,
    rowBuilder: rowBuilder,
  ),
);

/// A tree in which the user picks files, directories, or both: the body of
/// [showDirectoryTreePicker], for embedding in a page or a custom dialog.
///
/// How the user picks depends on [mode] and [multiple]:
///
/// * Single (`multiple: false`): a click or the arrow keys select one
///   row, and only rows that [mode] accepts can be selected. Activating
///   such a row (a double-click, or Enter) calls [onConfirm].
/// * Multiple files or any nodes: every row has a tri-state checkbox
///   ([DirectoryTreeCheckboxMode.checks]); checking a directory checks
///   everything below it. A click on a file row toggles its check. The
///   pick is the checked files ([DirectoryTreePickerMode.files]) or the
///   outermost checked nodes, where a checked directory stands for its
///   whole subtree ([DirectoryTreePickerMode.any]).
/// * Multiple directories: every row has a checkbox that picks that one
///   directory, without its children. Clicks on rows only focus them and
///   open or close directories, and every key that moves the focus (the
///   arrows with or without Shift, Home, End, the page keys, Left and
///   Right, type-ahead) only moves it
///   ([DirectoryTreeView.selectionFollowsFocus] is false), so moving never
///   undoes a pick; Space and the checkboxes toggle.
///
/// The picker owns its state, built from [tree], [initialSelection], and
/// [initialExpansion] when it is created; later changes of those two
/// initial values are ignored, while a new [tree] keeps the state by id.
/// Building the initial state costs O(n + k log k) for n nodes and k
/// initial picks.
/// Escape is left to the widgets around the picker (in a dialog, it
/// closes the dialog).
///
/// The picker fills the space its parent gives it, so it needs a bounded
/// size.
class DirectoryTreePicker<T> extends StatefulWidget {
  /// Creates a picker for the nodes of [tree].
  const DirectoryTreePicker({
    super.key,
    required this.tree,
    this.mode = DirectoryTreePickerMode.files,
    this.multiple = false,
    this.initialSelection = const <NodeId>[],
    this.initialExpansion,
    this.showSearch = true,
    this.searchHintText,
    this.rowBuilder,
    this.autofocus = false,
    this.onChanged,
    this.onConfirm,
  });

  /// The nodes to pick from.
  ///
  /// A new tree keeps the current pick, expansion, and focus by [NodeId]
  /// and drops the ids it no longer contains. The pick is then computed
  /// from the new tree (a checked directory that gained a file, for
  /// example, now stands for its checked files only), and [onChanged]
  /// reports it when it differs from the previous pick by [TreeNode.==],
  /// which also compares the nodes' data.
  final DirectoryTree<T> tree;

  /// Which nodes can be picked; [DirectoryTreePickerMode.files] by default.
  final DirectoryTreePickerMode mode;

  /// Whether more than one node can be picked; false by default.
  final bool multiple;

  /// The nodes picked when the picker appears.
  ///
  /// Ids that [tree] does not contain and nodes that [mode] does not
  /// accept are ignored; in single mode only the first remaining id
  /// counts. Every picked node starts visible: its ancestors are expanded,
  /// and the first one is focused and scrolled into view.
  final Iterable<NodeId> initialSelection;

  /// Which directories start expanded, before the picked nodes are
  /// revealed; when `null`, the top-level directories.
  final ExpansionState? initialExpansion;

  /// Whether a [DirectoryTreeSearchField] is shown above the tree; true by
  /// default.
  final bool showSearch;

  /// The hint of the search field;
  /// [MaterialLocalizations.searchFieldLabel] when `null`.
  final String? searchHintText;

  /// Builds each row; the default row when `null`.
  ///
  /// See [DirectoryTreeView.rowBuilder]. The details carry the checkbox
  /// state, so a custom row can draw the picker's checkboxes.
  final DirectoryTreeRowBuilder<T>? rowBuilder;

  /// Whether the tree takes the keyboard focus when the picker first
  /// appears; false by default ([showDirectoryTreePicker] sets it).
  final bool autofocus;

  /// Called with the pick whenever it changes, and once after the first
  /// frame when the initial pick is not empty, so the latest value it
  /// received is always the current pick.
  ///
  /// The list is unmodifiable, in display order (pre-order), and empty when
  /// nothing valid is picked. The pick is computed once per change of the
  /// selection, the checks, or [tree], in O(k log k) for k picked nodes;
  /// focus moves and scrolling never compute it. It may call `setState`:
  /// changes that happen while the widgets build (a new [tree] or [mode])
  /// are reported after the frame.
  final ValueChanged<List<TreeNode<T>>>? onChanged;

  /// Called in single mode when the user activates a row that [mode]
  /// accepts, with a list holding that node, which is also the new pick.
  ///
  /// [showDirectoryTreePicker] closes its dialog with it.
  final ValueChanged<List<TreeNode<T>>>? onConfirm;

  @override
  State<DirectoryTreePicker<T>> createState() => _DirectoryTreePickerState<T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<DirectoryTreePickerMode>('mode', mode))
      ..add(
        FlagProperty(
          'multiple',
          value: multiple,
          ifTrue: 'multiple',
          defaultValue: false,
        ),
      )
      ..add(
        FlagProperty(
          'showSearch',
          value: showSearch,
          ifFalse: 'no search',
          defaultValue: true,
        ),
      );
  }
}

/// How a picker records the pick.
enum _PickStyle {
  /// The highlight selection in single mode.
  single,

  /// Tri-state checks (multiple files or any nodes).
  checks,

  /// The highlight selection in multiple mode, shown as checkboxes
  /// (multiple directories).
  selectionBoxes,
}

bool _accepts(DirectoryTreePickerMode mode, TreeNode<Object?> node) =>
    switch (mode) {
      DirectoryTreePickerMode.files => node.isFile,
      DirectoryTreePickerMode.directories => node.isDirectory,
      DirectoryTreePickerMode.any => true,
    };

class _DirectoryTreePickerState<T> extends State<DirectoryTreePicker<T>> {
  late DirectoryTreeController<T> _controller;
  late _PickStyle _style;
  final FocusNode _treeFocusNode = FocusNode(debugLabel: 'DirectoryTreePicker');

  // The pick and the state it was computed from (the selection or checks,
  // and the tree): the pick is computed again only when that state
  // changes, not on every focus move.
  List<TreeNode<T>> _pick = const [];
  SelectionState? _pickSource;
  DirectoryTree<T>? _pickTree;
  bool _reportScheduled = false;

  // The key bindings of the last build and what they were made for.
  Map<ShortcutActivator, Intent>? _shortcuts;
  (TargetPlatform, TextDirection)? _shortcutsKey;

  @override
  void initState() {
    super.initState();
    _style = _styleOf(widget);
    _controller = _createController();
    _pickSource = _currentPickSource;
    _pickTree = _controller.tree;
    _pick = _computePick();
    _controller.addListener(_handleControllerChanged);
    if (_pick.isNotEmpty) {
      _scheduleReport();
      final first = _pick.first.id;
      // The view attaches its viewport during the first build, so the
      // first pick can be focused and scrolled to only after it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.reveal(first);
      });
    }
  }

  @override
  void didUpdateWidget(DirectoryTreePicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode != oldWidget.mode ||
        widget.multiple != oldWidget.multiple) {
      // Another way of picking: start over from the initial values, and
      // keep what the user opened.
      final expansion = _controller.expansion;
      _controller
        ..removeListener(_handleControllerChanged)
        ..dispose();
      _style = _styleOf(widget);
      _controller = _createController(expansion: expansion)
        ..addListener(_handleControllerChanged);
      _handleControllerChanged();
    } else if (!identical(widget.tree, oldWidget.tree)) {
      _controller.tree = widget.tree;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _treeFocusNode.dispose();
    super.dispose();
  }

  static _PickStyle _styleOf(DirectoryTreePicker<Object?> widget) {
    if (!widget.multiple) return _PickStyle.single;
    return widget.mode == DirectoryTreePickerMode.directories
        ? _PickStyle.selectionBoxes
        : _PickStyle.checks;
  }

  /// A controller with the initial pick, its nodes revealed, built in one
  /// pass (see [revealPicks] and [checkPicks]).
  DirectoryTreeController<T> _createController({ExpansionState? expansion}) {
    final tree = widget.tree;
    final mode = widget.mode;
    final picks = <NodeId>[];
    for (final id in widget.initialSelection) {
      final node = tree[id];
      if (node == null || !_accepts(mode, node)) continue;
      picks.add(id);
      if (_style == _PickStyle.single) break;
    }
    final startExpansion = revealPicks(
      tree,
      picks,
      expansion ??
          widget.initialExpansion ??
          ExpansionState.withExpanded(tree.roots),
    );
    switch (_style) {
      case _PickStyle.single:
      case _PickStyle.selectionBoxes:
        return DirectoryTreeController<T>(
          tree: tree,
          expansion: startExpansion,
          selection: SelectionState(
            mode: _style == _PickStyle.single
                ? SelectionMode.single
                : SelectionMode.multiple,
            selected: picks,
            anchor: picks.isEmpty ? null : picks.first,
          ),
          selectable: (node) => _accepts(mode, node),
        );
      case _PickStyle.checks:
        // The checks are the pick, so nothing is ever highlighted: clicks
        // and arrow keys only move the focus.
        return DirectoryTreeController<T>(
          tree: tree,
          expansion: startExpansion,
          checks: checkPicks(tree, picks),
          selectable: (_) => false,
        );
    }
  }

  SelectionState get _currentPickSource =>
      _style == _PickStyle.checks ? _controller.checks : _controller.selection;

  List<TreeNode<T>> _computePick() {
    final mode = widget.mode;
    final Iterable<TreeNode<T>> nodes = switch (_style) {
      _PickStyle.checks =>
        mode == DirectoryTreePickerMode.files
            ? _controller.checkedLeaves.where((node) => node.isFile)
            : _controller.checkedRoots,
      _PickStyle.single || _PickStyle.selectionBoxes =>
        _controller.selectedNodes.where((node) => _accepts(mode, node)),
    };
    return List<TreeNode<T>>.unmodifiable(nodes);
  }

  void _handleControllerChanged() {
    final source = _currentPickSource;
    final tree = _controller.tree;
    // The pick depends on the tree too: a new tree may keep the selection
    // object but hold other nodes for its ids.
    if (identical(source, _pickSource) && identical(tree, _pickTree)) return;
    _pickSource = source;
    _pickTree = tree;
    final pick = _computePick();
    final same = _samePick(pick, _pick);
    // Equal nodes of a new tree still replace the old ones, which the
    // confirm button returns.
    _pick = pick;
    if (same) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // A change made while the widgets build (a new tree or mode from
      // didUpdateWidget): onChanged usually calls setState on an ancestor,
      // which is not allowed during a build.
      _scheduleReport();
    } else {
      widget.onChanged?.call(pick);
    }
  }

  void _scheduleReport() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (mounted) widget.onChanged?.call(_pick);
    });
  }

  /// Whether [a] and [b] hold equal nodes ([TreeNode.==], which compares
  /// the data and the child ids too) in the same order.
  static bool _samePick(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleActivate(TreeRow<T> row) {
    final node = row.node;
    if (!_accepts(widget.mode, node)) return;
    _controller.select(row.id, focus: false);
    widget.onConfirm?.call(List<TreeNode<T>>.unmodifiable([node]));
  }

  void _handleRowTap(TreeRow<T> row) {
    final node = row.node;
    if (node.isFile && _accepts(widget.mode, node)) {
      _controller.toggleChecked(row.id);
    }
  }

  /// The tree's key bindings: the defaults without Escape, so it reaches
  /// the dialog.
  Map<ShortcutActivator, Intent> _shortcutsFor(BuildContext context) {
    final key = (defaultTargetPlatform, Directionality.of(context));
    final cached = _shortcuts;
    if (cached != null && key == _shortcutsKey) return cached;
    final defaults = DirectoryTreeShortcuts.defaults(
      platform: key.$1,
      textDirection: key.$2,
    );
    final shortcuts = <ShortcutActivator, Intent>{
      for (final MapEntry(:key, :value) in defaults.entries)
        if (value is! ClearTreeSelectionIntent) key: value,
    };
    _shortcutsKey = key;
    return _shortcuts = shortcuts;
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    final treeFocusNode = _treeFocusNode;
    final view = DirectoryTreeView<T>(
      controller: _controller,
      rowBuilder: widget.rowBuilder,
      checkboxMode: switch (style) {
        _PickStyle.single => DirectoryTreeCheckboxMode.none,
        _PickStyle.checks => DirectoryTreeCheckboxMode.checks,
        _PickStyle.selectionBoxes => DirectoryTreeCheckboxMode.selection,
      },
      selectOnTap: style == _PickStyle.single,
      onRowTap: style == _PickStyle.checks ? _handleRowTap : null,
      onActivate: style == _PickStyle.single ? _handleActivate : null,
      focusNode: treeFocusNode,
      autofocus: widget.autofocus,
      shortcuts: _shortcutsFor(context),
      // Selection checkboxes are picks: moving must never undo one.
      selectionFollowsFocus: style != _PickStyle.selectionBoxes,
    );
    // The same structure with or without the search field, so that showing
    // or hiding it keeps the view's state (scroll position, focus).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DirectoryTreeSearchField(
              controller: _controller,
              treeFocusNode: treeFocusNode,
              hintText: widget.searchHintText,
            ),
          ),
        Expanded(child: view),
      ],
    );
  }
}

class _DirectoryTreePickerDialog<T> extends StatefulWidget {
  const _DirectoryTreePickerDialog({
    required this.tree,
    required this.mode,
    required this.multiple,
    required this.initialSelection,
    required this.initialExpansion,
    required this.title,
    required this.confirmLabel,
    required this.showSearch,
    required this.rowBuilder,
  });

  final DirectoryTree<T> tree;
  final DirectoryTreePickerMode mode;
  final bool multiple;
  final Iterable<NodeId> initialSelection;
  final ExpansionState? initialExpansion;
  final String? title;
  final String? confirmLabel;
  final bool showSearch;
  final DirectoryTreeRowBuilder<T>? rowBuilder;

  @override
  State<_DirectoryTreePickerDialog<T>> createState() =>
      _DirectoryTreePickerDialogState<T>();
}

class _DirectoryTreePickerDialogState<T>
    extends State<_DirectoryTreePickerDialog<T>> {
  final GlobalKey<_DirectoryTreePickerState<T>> _pickerKey =
      GlobalKey<_DirectoryTreePickerState<T>>();

  // Whether the pick is not empty, for the confirm button. The picker
  // reports its initial pick only after the first frame, so the first
  // frame decides from the initial selection: any id of the tree that the
  // mode accepts is picked. O(initial selection) at most, once.
  late bool _hasPick = widget.initialSelection.any((id) {
    final node = widget.tree[id];
    return node != null && _accepts(widget.mode, node);
  });

  /// The picker's current pick, which exists from its first build on.
  List<TreeNode<T>> get _pick =>
      _pickerKey.currentState?._pick ?? const <Never>[];

  void _handleChanged(List<TreeNode<T>> pick) {
    setState(() => _hasPick = pick.isNotEmpty);
  }

  void _confirm(List<TreeNode<T>> pick) {
    if (pick.isEmpty) return;
    Navigator.of(context).pop(pick);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final title = widget.title;
    return AlertDialog(
      title: title == null ? null : Text(title),
      content: SizedBox(
        width: 520,
        height: 440,
        child: DirectoryTreePicker<T>(
          key: _pickerKey,
          tree: widget.tree,
          mode: widget.mode,
          multiple: widget.multiple,
          initialSelection: widget.initialSelection,
          initialExpansion: widget.initialExpansion,
          showSearch: widget.showSearch,
          rowBuilder: widget.rowBuilder,
          autofocus: true,
          onChanged: _handleChanged,
          onConfirm: _confirm,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: _hasPick ? () => _confirm(_pick) : null,
          child: Text(widget.confirmLabel ?? localizations.okButtonLabel),
        ),
      ],
    );
  }
}
