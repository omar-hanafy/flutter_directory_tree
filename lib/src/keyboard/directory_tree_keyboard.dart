import 'dart:async';

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';

/// Keyboard control of a directory tree view: arrow-key navigation,
/// selection and expansion keys, and type-ahead find, applied to a
/// [DirectoryTreeController].
///
/// Wrap the widget that shows the controller's rows (usually a scroll view
/// with a `SliverDirectoryTree`) in a [DirectoryTreeKeyboard]; the
/// `DirectoryTreeView` widget does this for you. The tree gets one keyboard
/// focus node, [focusNode]. The rows themselves are not focusable: the keys
/// act on the controller's keyboard cursor,
/// [DirectoryTreeController.focusedRow], which they also move.
///
/// ## Keys
///
/// [shortcuts] maps keys to intents. By default they come from
/// [DirectoryTreeShortcuts.defaults] for [defaultTargetPlatform] and the
/// ambient [Directionality] (left-to-right when there is none), so the left
/// and right arrows swap in right-to-left layouts. This widget registers a
/// default action for every intent of the package except
/// [OpenTreeContextMenuIntent], whose action belongs to the context menu
/// host above it:
///
/// * [MoveTreeFocusIntent]: [DirectoryTreeController.moveFocus].
/// * [ExpandTreeNodeIntent]: expand, or move into an expanded row.
/// * [CollapseTreeNodeIntent]: collapse, or move to the parent row.
///   With [selectionFollowsFocus] (the default) these focus moves select
///   the row they reach; without it they only move the focus.
/// * [ExpandTreeSubtreeIntent]: [DirectoryTreeController.expandSubtree].
/// * [ActivateTreeNodeIntent]: a directory toggles, then [onActivate] runs.
/// * [ToggleTreeSelectionIntent]: the focused row's check or selection
///   toggles, depending on [checkboxMode].
/// * [SelectAllTreeNodesIntent]: [DirectoryTreeController.selectAll].
/// * [ClearTreeSelectionIntent]: [DirectoryTreeController.clearSelection].
///
/// Each intent's documentation states its action's details and when the
/// action is enabled; a disabled action leaves its key to the widgets above
/// the tree (for example, Escape with an empty selection still closes a
/// dialog).
///
/// ## Overriding actions
///
/// Every action is created with [Action.overridable], with this widget's
/// context as the lookup context. An [Actions] widget above the keyboard
/// widget that maps one of these intent types therefore replaces the
/// default action, for its key bindings and for [Actions.invoke] calls from
/// inside [child] alike. The replacement may run the default through its
/// [Action.callingAction]:
///
/// ```dart
/// Actions(
///   actions: <Type, Action<Intent>>{
///     ActivateTreeNodeIntent: CallbackAction<ActivateTreeNodeIntent>(
///       onInvoke: (intent) => openInEditor(controller.focusedRow),
///     ),
///   },
///   child: DirectoryTreeKeyboard<Object?>(
///     controller: controller,
///     child: treeView,
///   ),
/// )
/// ```
///
/// ## Focus
///
/// Keys are handled only while [focusNode] itself has the primary focus.
/// When a widget elsewhere, or a focusable widget inside [child] (such as a
/// text field or a button in a custom row), has the focus, every key
/// reaches that widget untouched: no shortcut fires and no character goes
/// to the type-ahead search. Views request this node's focus when a row is
/// clicked.
///
/// When the tree gains the focus (by Tab, [autofocus], or
/// [FocusNode.requestFocus]) while the controller has no focused row, the
/// keyboard cursor goes to the first selected row of
/// [DirectoryTreeController.rows], or to the first row when no row is
/// selected, as the WAI-ARIA tree pattern describes. This only focuses the
/// row with [DirectoryTreeController.focus], which scrolls it into view;
/// the selection does not change. A click focuses its row before the tree
/// gains the focus, so a click never puts the cursor on another row first.
/// Finding the selected row costs O(min(s, r) x log rows) for s selected
/// ids and the index r of the row found.
///
/// ## Type-ahead
///
/// With [typeAhead] (the default), typing jumps to rows by name. A key
/// press joins the search when it types a printable character without a
/// shortcut modifier and no binding of [shortcuts] accepts it (so `*`
/// always expands a subtree). Meta (Cmd) is always a shortcut modifier,
/// and so are Ctrl and Alt, except where a platform types text with them:
/// Option (Alt) without Ctrl on macOS, iOS, and Android, and AltGr on
/// Windows, which reports Ctrl and Alt together. (Linux reports AltGr as a
/// key of its own, so its characters join as well.) Space joins only while a search is in
/// progress; otherwise it toggles the selection. The search text resets
/// [typeAheadTimeout] after the latest character, when another key (not a
/// modifier) is pressed, and when the tree loses the focus.
///
/// After each character the controller's [DirectoryTreeController.rows] are
/// searched for a [TreeRow.label] that starts with the search text,
/// ignoring case:
///
/// * When the text is one character, or one character typed repeatedly
///   (`a`, `aaa`), the search starts after the focused row and wraps
///   around, so repeating a letter cycles through the rows that start with
///   it.
/// * Otherwise the search starts at the focused row itself and wraps
///   around, so typing more of a name keeps the row once it matches.
///
/// The row found is focused and selected with
/// [DirectoryTreeController.select] (only focused, with
/// [DirectoryTreeController.focus], when [selectionFollowsFocus] is false),
/// which also scrolls it into view; when no row matches, nothing changes. A search reads each row's label at most
/// once per key press, so a key press with no match costs O(rows).
class DirectoryTreeKeyboard<T> extends StatefulWidget {
  /// Creates the keyboard handling for [controller]'s rows around [child].
  const DirectoryTreeKeyboard({
    super.key,
    required this.controller,
    required this.child,
    this.focusNode,
    this.autofocus = false,
    this.shortcuts,
    this.onActivate,
    this.checkboxMode = DirectoryTreeCheckboxMode.none,
    this.typeAhead = true,
    this.typeAheadTimeout = const Duration(seconds: 1),
    this.selectionFollowsFocus = true,
  });

  /// The controller whose rows the keys move through and act on.
  ///
  /// The actions read it when a key is pressed, so replacing it takes
  /// effect immediately; it also resets the type-ahead search.
  final DirectoryTreeController<T> controller;

  /// The widget that shows the rows, usually a scroll view with a
  /// `SliverDirectoryTree` of the same [controller].
  ///
  /// [focusNode] is its nearest [Focus] ancestor, so the rows can read
  /// whether the tree has the focus with [Focus.maybeOf].
  final Widget child;

  /// The keyboard focus node of the tree.
  ///
  /// Give one to move the focus to the tree from elsewhere (for example a
  /// search field's down arrow) or to listen to its focus. When `null`, the
  /// widget creates and disposes its own node. The keys work only while
  /// this node has the primary focus (see "Focus" above).
  final FocusNode? focusNode;

  /// Whether the tree takes the focus when it first appears, if nothing
  /// else in its focus scope has it; false by default.
  final bool autofocus;

  /// The key bindings, replacing the defaults entirely.
  ///
  /// When `null` (the default), the bindings are
  /// [DirectoryTreeShortcuts.defaults] for [defaultTargetPlatform] and the
  /// ambient [Directionality]. To add or change a few, spread the defaults
  /// into a new map. Characters that a binding accepts never join the
  /// type-ahead search, so binding a letter keeps it out of the search.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Called when the focused row is activated with Enter (or another key
  /// bound to [ActivateTreeNodeIntent]), after a directory row has toggled.
  ///
  /// It receives the row as it is after the toggle, for files and
  /// directories alike. When `null`, activating a file does nothing.
  final ValueChanged<TreeRow<T>>? onActivate;

  /// Which checkbox the rows show, which decides what Space does.
  ///
  /// With [DirectoryTreeCheckboxMode.checks], [ToggleTreeSelectionIntent]
  /// toggles the focused row's check; with the other modes it toggles (or,
  /// in single selection mode, sets) the highlight selection. Use the same
  /// value as the view that draws the rows.
  final DirectoryTreeCheckboxMode checkboxMode;

  /// Whether typing a row's name moves to it; true by default.
  ///
  /// See "Type-ahead" above. When false, characters that no binding accepts
  /// are left to the widgets above the tree.
  final bool typeAhead;

  /// How long the type-ahead search text lasts after the latest character;
  /// one second by default.
  ///
  /// A key press after this much time starts a new search. A zero duration
  /// keeps only the latest character.
  final Duration typeAheadTimeout;

  /// Whether moving the keyboard cursor also selects the row it reaches;
  /// true by default.
  ///
  /// When true, focus moves select as their intents say: a plain arrow
  /// replaces the selection, a Shift arrow extends it (see
  /// [MoveTreeFocusIntent.selection]), Left and Right select the parent or
  /// first child they move to, and type-ahead selects the row it finds.
  ///
  /// When false, every focus move of the default actions (the arrows with
  /// any modifier, Home, End, Page Up, Page Down, Left and Right when they
  /// move, and type-ahead) only moves [DirectoryTreeController.focusedId]
  /// and keeps the selection. The selection then changes only through
  /// [ToggleTreeSelectionIntent] (Space), [SelectAllTreeNodesIntent],
  /// [ClearTreeSelectionIntent], clicks, and code. Use it where the user
  /// builds the selection pick by pick, such as a multiple selection shown
  /// as checkboxes, so that moving through the rows never undoes a pick.
  /// An overriding action (see "Overriding actions") decides for itself.
  final bool selectionFollowsFocus;

  @override
  State<DirectoryTreeKeyboard<T>> createState() =>
      _DirectoryTreeKeyboardState<T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final shortcuts = this.shortcuts;
    properties
      ..add(
        DiagnosticsProperty<DirectoryTreeController<T>>(
          'controller',
          controller,
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
        // Hidden while the defaults apply.
        shortcuts == null
            ? DiagnosticsProperty<Map<ShortcutActivator, Intent>>(
                'shortcuts',
                null,
                defaultValue: null,
              )
            : ShortcutMapProperty('shortcuts', shortcuts),
      )
      ..add(
        ObjectFlagProperty<ValueChanged<TreeRow<T>>>.has(
          'onActivate',
          onActivate,
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
          'typeAhead',
          value: typeAhead,
          ifFalse: 'type-ahead off',
          defaultValue: true,
        ),
      )
      ..add(
        DiagnosticsProperty<Duration>(
          'typeAheadTimeout',
          typeAheadTimeout,
          defaultValue: const Duration(seconds: 1),
        ),
      )
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

class _DirectoryTreeKeyboardState<T> extends State<DirectoryTreeKeyboard<T>> {
  // Created on first use and kept until dispose, also while the widget uses
  // an external node, so a node is never disposed while a Focus widget
  // still holds it.
  FocusNode? _ownedFocusNode;

  late final _TreeShortcutManager _shortcutManager = _TreeShortcutManager(
    () => _focusNode.hasPrimaryFocus,
  );

  late final Map<Type, Action<Intent>> _actions;

  // The type-ahead search text and the timer that clears it.
  String _typeAhead = '';
  Timer? _typeAheadTimer;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'DirectoryTreeKeyboard'));

  DirectoryTreeController<T> get _controller => widget.controller;

  /// What a focus move of a default action does to the selection.
  TreeSelectionUpdate _selectionFor(TreeSelectionUpdate requested) =>
      widget.selectionFollowsFocus ? requested : TreeSelectionUpdate.keep;

  @override
  void initState() {
    super.initState();
    // The lookup context is this element, which is above the Actions widget
    // built below: overrides are searched among the ancestors of the
    // keyboard widget, never among its own actions.
    _actions = <Type, Action<Intent>>{
      MoveTreeFocusIntent: Action<MoveTreeFocusIntent>.overridable(
        defaultAction: _MoveTreeFocusAction<T>(this),
        context: context,
      ),
      ExpandTreeNodeIntent: Action<ExpandTreeNodeIntent>.overridable(
        defaultAction: _ExpandTreeNodeAction<T>(this),
        context: context,
      ),
      CollapseTreeNodeIntent: Action<CollapseTreeNodeIntent>.overridable(
        defaultAction: _CollapseTreeNodeAction<T>(this),
        context: context,
      ),
      ExpandTreeSubtreeIntent: Action<ExpandTreeSubtreeIntent>.overridable(
        defaultAction: _ExpandTreeSubtreeAction<T>(this),
        context: context,
      ),
      ActivateTreeNodeIntent: Action<ActivateTreeNodeIntent>.overridable(
        defaultAction: _ActivateTreeNodeAction<T>(this),
        context: context,
      ),
      ToggleTreeSelectionIntent: Action<ToggleTreeSelectionIntent>.overridable(
        defaultAction: _ToggleTreeSelectionAction<T>(this),
        context: context,
      ),
      SelectAllTreeNodesIntent: Action<SelectAllTreeNodesIntent>.overridable(
        defaultAction: _SelectAllTreeNodesAction<T>(this),
        context: context,
      ),
      ClearTreeSelectionIntent: Action<ClearTreeSelectionIntent>.overridable(
        defaultAction: _ClearTreeSelectionAction<T>(this),
        context: context,
      ),
    };
  }

  @override
  void didUpdateWidget(DirectoryTreeKeyboard<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.typeAhead ||
        !identical(widget.controller, oldWidget.controller)) {
      _resetTypeAhead();
    }
  }

  @override
  void dispose() {
    _typeAheadTimer?.cancel();
    _shortcutManager.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read on every build so a platform or direction change applies; the
    // defaults are constant maps, so an unchanged map is found identical.
    _shortcutManager.shortcuts =
        widget.shortcuts ??
        DirectoryTreeShortcuts.defaults(
          platform: defaultTargetPlatform,
          textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        );
    return Actions(
      actions: _actions,
      child: Shortcuts.manager(
        manager: _shortcutManager,
        debugLabel: 'DirectoryTreeKeyboard',
        // The type-ahead handler sits on the tree's own node, below the
        // shortcuts, so it sees each key first.
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onKeyEvent: _handleKeyEvent,
          onFocusChange: _handleFocusChange,
          child: widget.child,
        ),
      ),
    );
  }

  void _handleFocusChange(bool focused) {
    if (focused) {
      _focusInitialRow();
    } else {
      _resetTypeAhead();
    }
  }

  /// Gives the keyboard cursor a row when the tree gains the focus without
  /// one: the first selected row, else the first row. Never selects.
  void _focusInitialRow() {
    final controller = _controller;
    if (controller.focusedId != null) return;
    final rows = controller.rows;
    if (rows.isEmpty) return;
    final index = _firstSelectedRowIndex(controller);
    controller.focus(rows[index < 0 ? 0 : index].id);
  }

  /// The index of the first row whose id is selected (the rows the view
  /// paints as selected), or -1.
  ///
  /// Two scans run in lockstep, so the cost stays O(min(s, r) x log rows)
  /// for s selected ids and the answer r: one walks the selected ids and
  /// keeps the smallest row index, the other walks the rows from the top.
  /// The answer is final once the rows scan meets a selected row or the
  /// smallest index found so far, or once every id was seen.
  static int _firstSelectedRowIndex(
    DirectoryTreeController<Object?> controller,
  ) {
    final selection = controller.selection;
    if (selection.isEmpty) return -1;
    final rows = controller.rows;
    final ids = selection.selected.iterator;
    var best = -1;
    var next = 0;
    while (ids.moveNext()) {
      final id = ids.current;
      final index = rows.indexOfNode(id);
      if (index >= 0 && rows[index].id == id && (best < 0 || index < best)) {
        best = index;
      }
      if (best >= 0 && next >= best) return best;
      if (next < rows.length) {
        if (selection.isSelected(rows[next].id)) return next;
        next++;
      }
    }
    return best;
  }

  /// The type-ahead handler: takes the printable characters that no
  /// shortcut claims, and leaves every other key to the shortcuts.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.typeAhead || !node.hasPrimaryFocus || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character == null ||
        !_isPrintable(character) ||
        !_typesText(HardwareKeyboard.instance)) {
      // Modifiers alone (Shift for a capital letter) keep the search going;
      // any other key ends it.
      if (!_modifierKeys.contains(event.logicalKey)) _resetTypeAhead();
      return KeyEventResult.ignored;
    }
    final claimed = character == ' '
        ? _typeAhead.isEmpty
        : _isBoundToShortcut(event);
    if (claimed) {
      _resetTypeAhead();
      return KeyEventResult.ignored;
    }
    _typeAhead += character;
    _typeAheadTimer?.cancel();
    _typeAheadTimer = Timer(widget.typeAheadTimeout, _resetTypeAhead);
    _focusTypeAheadMatch();
    return KeyEventResult.handled;
  }

  /// Whether a binding of the active shortcut map accepts [event].
  ///
  /// A repeat is tested as a fresh press, so a character bound without
  /// repeats does not leak into the search while its key is held.
  bool _isBoundToShortcut(KeyEvent event) {
    final probe = event is KeyRepeatEvent
        ? KeyDownEvent(
            physicalKey: event.physicalKey,
            logicalKey: event.logicalKey,
            character: event.character,
            timeStamp: event.timeStamp,
            deviceType: event.deviceType,
          )
        : event;
    final keyboard = HardwareKeyboard.instance;
    for (final activator in _shortcutManager.shortcuts.keys) {
      if (activator.accepts(probe, keyboard)) return true;
    }
    return false;
  }

  /// Focuses and selects the next row whose label starts with the search
  /// text, as described under "Type-ahead" in [DirectoryTreeKeyboard].
  void _focusTypeAheadMatch() {
    final controller = _controller;
    final rows = controller.rows;
    final count = rows.length;
    if (count == 0) return;
    final runes = _typeAhead.runes.toList(growable: false);
    final first = String.fromCharCode(runes.first).toLowerCase();
    var cycling = true;
    for (var i = 1; i < runes.length && cycling; i++) {
      cycling = String.fromCharCode(runes[i]).toLowerCase() == first;
    }
    final prefix = cycling ? first : _typeAhead.toLowerCase();
    final focused = controller.focusedIndex;
    final start = focused < 0 ? 0 : (cycling ? focused + 1 : focused);
    for (var step = 0; step < count; step++) {
      final row = rows[(start + step) % count];
      // TreeRow.label is computed on each read, so it is read once here.
      if (row.label.toLowerCase().startsWith(prefix)) {
        if (widget.selectionFollowsFocus) {
          controller.select(row.id);
        } else {
          controller.focus(row.id);
        }
        return;
      }
    }
  }

  void _resetTypeAhead() {
    _typeAheadTimer?.cancel();
    _typeAheadTimer = null;
    _typeAhead = '';
  }
}

/// A [ShortcutManager] that handles keys only while [_isActive] is true:
/// while the tree's own focus node has the primary focus.
///
/// A [Shortcuts] widget sees the keys of every focused descendant. Without
/// this gate, a text field or a button inside the tree would lose its
/// arrows, Space, and Enter to the tree's bindings, since those sit between
/// it and the application's text editing and activation shortcuts.
final class _TreeShortcutManager extends ShortcutManager {
  _TreeShortcutManager(this._isActive);

  final bool Function() _isActive;

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (!_isActive()) return KeyEventResult.ignored;
    return super.handleKeypress(context, event);
  }
}

/// Whether the pressed modifiers still type text rather than form a
/// shortcut: none of Ctrl, Alt, and Meta; Option (Alt) without Ctrl on
/// Apple platforms and Android, whose layouts type characters with it; and
/// AltGr on Windows, which reports Ctrl and Alt together. Linux reports
/// AltGr as a key of its own, which is not a modifier here.
bool _typesText(HardwareKeyboard keyboard) {
  if (keyboard.isMetaPressed) return false;
  final control = keyboard.isControlPressed;
  final alt = keyboard.isAltPressed;
  if (!control && !alt) return true;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.iOS ||
    TargetPlatform.android => !control,
    TargetPlatform.windows => control && alt,
    TargetPlatform.linux || TargetPlatform.fuchsia => false,
  };
}

/// Whether [character] can be typed into a name: no control characters
/// (C0, DEL, C1) and no private-use characters, which some platforms report
/// for function and arrow keys.
bool _isPrintable(String character) {
  if (character.isEmpty) return false;
  for (var i = 0; i < character.length; i++) {
    final unit = character.codeUnitAt(i);
    if (unit < 0x20 ||
        (unit >= 0x7f && unit <= 0x9f) ||
        (unit >= 0xe000 && unit <= 0xf8ff)) {
      return false;
    }
  }
  return true;
}

/// Modifier and lock keys, whose presses do not end a type-ahead search.
final Set<LogicalKeyboardKey> _modifierKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.altGraph,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
  LogicalKeyboardKey.symbol,
  LogicalKeyboardKey.symbolLock,
  LogicalKeyboardKey.hyper,
  LogicalKeyboardKey.superKey,
};

// ---------------------------------------------------------------------------
// Default actions. Each reads the widget when it runs, so a new controller,
// checkbox mode, or onActivate applies at once.
// ---------------------------------------------------------------------------

/// [DirectoryTreeController.moveFocus] with the intent's move and selection
/// update; always enabled, so edge moves still consume their keys.
class _MoveTreeFocusAction<T> extends Action<MoveTreeFocusIntent> {
  _MoveTreeFocusAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  void invoke(MoveTreeFocusIntent intent) {
    _state._controller.moveFocus(
      intent.move,
      selection: _state._selectionFor(intent.selection),
    );
  }
}

class _ExpandTreeNodeAction<T> extends Action<ExpandTreeNodeIntent> {
  _ExpandTreeNodeAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  void invoke(ExpandTreeNodeIntent intent) {
    final controller = _state._controller;
    final row = controller.focusedRow;
    if (row == null) return;
    if (!row.isExpanded) {
      if (controller.isExpandable(row.id)) controller.expand(row.id);
      return;
    }
    final moved = controller.moveFocus(
      TreeFocusMove.firstChild,
      selection: _state._selectionFor(TreeSelectionUpdate.replace),
    );
    if (moved) return;
    // Expanded with no child rows: only a lazy directory whose load never
    // ran or failed is still expandable then, and expand starts that load
    // (it does nothing while a load runs).
    if (controller.isExpandable(row.id)) controller.expand(row.id);
  }
}

class _CollapseTreeNodeAction<T> extends Action<CollapseTreeNodeIntent> {
  _CollapseTreeNodeAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  void invoke(CollapseTreeNodeIntent intent) {
    final controller = _state._controller;
    final row = controller.focusedRow;
    if (row == null) return;
    if (row.isExpanded) {
      controller.collapse(row.id);
    } else {
      controller.moveFocus(
        TreeFocusMove.parent,
        selection: _state._selectionFor(TreeSelectionUpdate.replace),
      );
    }
  }
}

class _ExpandTreeSubtreeAction<T> extends Action<ExpandTreeSubtreeIntent> {
  _ExpandTreeSubtreeAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  bool isEnabled(ExpandTreeSubtreeIntent intent) =>
      _state._controller.focusedId != null;

  @override
  void invoke(ExpandTreeSubtreeIntent intent) {
    final id = _state._controller.focusedId;
    if (id != null) _state._controller.expandSubtree(id);
  }
}

class _ActivateTreeNodeAction<T> extends Action<ActivateTreeNodeIntent> {
  _ActivateTreeNodeAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  bool isEnabled(ActivateTreeNodeIntent intent) =>
      _state._controller.focusedId != null;

  @override
  void invoke(ActivateTreeNodeIntent intent) {
    final widget = _state.widget;
    final controller = widget.controller;
    var row = controller.focusedRow;
    if (row == null) return;
    if (row.node is DirectoryNode<T>) {
      final id = row.id;
      controller.toggleExpansion(id);
      // Toggling replaces the row object; hand out the current one.
      row = controller.rows.rowOf(id) ?? row;
    }
    widget.onActivate?.call(row);
  }
}

class _ToggleTreeSelectionAction<T> extends Action<ToggleTreeSelectionIntent> {
  _ToggleTreeSelectionAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  bool isEnabled(ToggleTreeSelectionIntent intent) =>
      _state._controller.focusedId != null;

  @override
  void invoke(ToggleTreeSelectionIntent intent) {
    final widget = _state.widget;
    final controller = widget.controller;
    final id = controller.focusedId;
    if (id == null) return;
    if (widget.checkboxMode == DirectoryTreeCheckboxMode.checks) {
      controller.toggleChecked(id);
    } else if (controller.selectionMode == SelectionMode.multiple) {
      controller.toggleSelected(id);
    } else {
      controller.select(id);
    }
  }
}

class _SelectAllTreeNodesAction<T> extends Action<SelectAllTreeNodesIntent> {
  _SelectAllTreeNodesAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  bool isEnabled(SelectAllTreeNodesIntent intent) =>
      _state._controller.selectionMode == SelectionMode.multiple;

  @override
  void invoke(SelectAllTreeNodesIntent intent) {
    _state._controller.selectAll();
  }
}

class _ClearTreeSelectionAction<T> extends Action<ClearTreeSelectionIntent> {
  _ClearTreeSelectionAction(this._state);

  final _DirectoryTreeKeyboardState<T> _state;

  @override
  bool isEnabled(ClearTreeSelectionIntent intent) =>
      !_state._controller.selection.isEmpty;

  @override
  void invoke(ClearTreeSelectionIntent intent) {
    _state._controller.clearSelection();
  }
}
