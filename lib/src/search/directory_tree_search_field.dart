import 'dart:async';

// Imported only so documentation references resolve.
import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/search/labeled_icon_button.dart';

/// A text field that edits the search query of a [DirectoryTreeController].
///
/// Typing sets [DirectoryTreeController.query] once the user pauses for
/// [debounce], so a large tree is filtered once per pause instead of once
/// per keystroke; the controller then filters the rows, reveals the
/// matches, and highlights them. The binding goes both ways: when the app
/// changes the query, the field shows the new text.
///
/// Place it above a tree view and pass the view's focus node as
/// [treeFocusNode], so the keyboard flows from the search to the results:
///
/// ```dart
/// Column(
///   children: [
///     DirectoryTreeSearchField(
///       controller: controller,
///       treeFocusNode: treeFocusNode,
///     ),
///     Expanded(
///       child: DirectoryTreeView(
///         controller: controller,
///         focusNode: treeFocusNode,
///       ),
///     ),
///   ],
/// )
/// ```
///
/// ## Keyboard
///
/// * Escape clears a non-empty query and the text at once. When both are
///   empty, the field ignores Escape, so an ancestor can still use it, for
///   example to close a dialog.
/// * Arrow Down applies text that is still waiting for the [debounce],
///   focuses the first row whose [TreeRow.isMatch] is true (the first row
///   when none is) with [DirectoryTreeController.focus], and moves keyboard
///   focus to [treeFocusNode]. When no rows are left, the key is left to
///   the text field. With a modifier (Shift+Down, for example) it keeps its
///   text editing meaning.
/// * Enter, or the search key of a soft keyboard, applies text that is
///   still waiting for the [debounce] at once; the field then loses focus
///   as any [TextField] does.
///
/// While an input method is composing text (the provisional, underlined
/// text of many Asian keyboards), Escape and Arrow Down belong to the input
/// method and the field leaves them alone.
///
/// ## Appearance
///
/// A clear button shows at the end of the field while it has text. The
/// field needs [MaterialLocalizations], which a [MaterialApp] provides, for
/// the default hint and the clear button's tooltip, and it works without a
/// [Material] ancestor. Typed text is not autocorrected and quotes and
/// dashes are not made "smart", because file names and the query syntax of
/// [TreeQuery] need them as typed.
class DirectoryTreeSearchField extends StatefulWidget {
  /// Creates a search field bound to [controller].
  const DirectoryTreeSearchField({
    super.key,
    required this.controller,
    this.focusNode,
    this.treeFocusNode,
    this.autofocus = false,
    this.hintText,
    this.decoration,
    this.debounce = const Duration(milliseconds: 120),
  });

  /// The controller whose [DirectoryTreeController.query] this field edits.
  ///
  /// A controller of any data type works, since the field reads only the
  /// query and the rows and moves the focus. When this changes to another
  /// controller, the field shows that controller's query, and text still
  /// waiting for the [debounce] is dropped.
  final DirectoryTreeController<Object?> controller;

  /// The focus node of the text field.
  ///
  /// When `null`, the field creates and disposes a node of its own.
  final FocusNode? focusNode;

  /// The focus node of the tree view that shows the [controller]'s rows,
  /// which receives keyboard focus when the user presses Arrow Down.
  ///
  /// When `null`, Arrow Down still focuses the first matching row in the
  /// [controller] (and scrolls the attached views to it), but keyboard
  /// focus stays in the field.
  final FocusNode? treeFocusNode;

  /// Whether the field takes keyboard focus when it first appears.
  ///
  /// Defaults to false. See [TextField.autofocus].
  final bool autofocus;

  /// The hint shown while the field is empty.
  ///
  /// When `null`, the hint is [MaterialLocalizations.searchFieldLabel]
  /// ("Search" in English), in the app's language. A hint that [decoration]
  /// sets itself, with [InputDecoration.hint] or [InputDecoration.hintText],
  /// takes precedence over both.
  final String? hintText;

  /// The decoration around the text.
  ///
  /// When `null`, the field uses a dense [InputDecoration] with a search
  /// icon at the start, styled by the ambient [InputDecorationTheme]. A
  /// given decoration is used as it is, with two additions when it leaves
  /// them unset: the hint (see [hintText]), and the clear button as the
  /// [InputDecoration.suffixIcon] while the field has text. A decoration
  /// with a suffix icon of its own therefore has no clear button.
  final InputDecoration? decoration;

  /// How long typing must pause before the text becomes the query.
  ///
  /// Every edit of the text starts the wait again; moving the caret does
  /// not. [Duration.zero] (or a negative duration) applies every edit
  /// immediately, which suits small trees. Clearing, with Escape or the
  /// clear button, is always immediate, and a change of
  /// [DirectoryTreeController.query] made elsewhere drops text that is
  /// still waiting. Defaults to 120 milliseconds.
  final Duration debounce;

  @override
  State<DirectoryTreeSearchField> createState() =>
      _DirectoryTreeSearchFieldState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(
        DiagnosticsProperty<DirectoryTreeController<Object?>>(
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
        DiagnosticsProperty<FocusNode>(
          'treeFocusNode',
          treeFocusNode,
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
      ..add(StringProperty('hintText', hintText, defaultValue: null))
      ..add(
        DiagnosticsProperty<InputDecoration>(
          'decoration',
          decoration,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<Duration>(
          'debounce',
          debounce,
          defaultValue: const Duration(milliseconds: 120),
        ),
      );
  }
}

class _DirectoryTreeSearchFieldState extends State<DirectoryTreeSearchField> {
  static const InputDecoration _defaultDecoration = InputDecoration(
    prefixIcon: Icon(Icons.search),
    isDense: true,
  );

  // Only the bare keys: Shift+Down and the other modified arrows keep their
  // text editing meaning.
  static const SingleActivator _clearKey = SingleActivator(
    LogicalKeyboardKey.escape,
  );
  static const SingleActivator _treeKey = SingleActivator(
    LogicalKeyboardKey.arrowDown,
  );

  late final TextEditingController _text;
  FocusNode? _ownedFocusNode;
  Timer? _debounceTimer;

  // The text as of its last change, which tells edits apart from the
  // notifications the text controller sends for caret and composing moves.
  late String _lastText;

  // The controller's query as of the last time the field looked, which
  // tells query changes apart from the controller's other notifications
  // (focus, selection, rows). It is set before the field applies a query
  // itself, so the notification that follows is not taken for an outside
  // change.
  late String _lastQuery;

  FocusNode get _focusNode =>
      widget.focusNode ??
      (_ownedFocusNode ??= FocusNode(debugLabel: 'DirectoryTreeSearchField'));

  @override
  void initState() {
    super.initState();
    final query = widget.controller.query;
    _lastQuery = query;
    _lastText = query;
    _text = TextEditingController.fromValue(_valueAtEnd(query))
      ..addListener(_handleTextChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(DirectoryTreeSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _cancelDebounce();
      _lastQuery = widget.controller.query;
      _showQuery(_lastQuery);
    } else if (widget.debounce != oldWidget.debounce &&
        _debounceTimer != null) {
      // Wait the new duration instead. A zero or negative one still goes
      // through a timer: applying the query here would notify the
      // controller's listeners in the middle of a build.
      _debounceTimer!.cancel();
      _debounceTimer = Timer(widget.debounce, _applyWaitingText);
    }
  }

  @override
  void dispose() {
    _cancelDebounce();
    widget.controller.removeListener(_handleControllerChanged);
    _text.dispose();
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  static TextEditingValue _valueAtEnd(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  bool get _isComposing {
    final composing = _text.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _handleTextChanged() {
    final text = _text.text;
    if (text == _lastText) return;
    final hadText = _lastText.isNotEmpty;
    _lastText = text;
    // The clear button comes or goes.
    if (text.isNotEmpty != hadText) setState(() {});
    if (text == widget.controller.query) {
      _cancelDebounce();
      return;
    }
    final debounce = widget.debounce;
    if (debounce <= Duration.zero) {
      _applyQuery(text);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _applyWaitingText);
  }

  void _handleControllerChanged() {
    final query = widget.controller.query;
    if (query == _lastQuery) return;
    _lastQuery = query;
    // The query changed elsewhere: it replaces text still waiting.
    _cancelDebounce();
    _showQuery(query);
  }

  /// Shows [query] in the field. Equal text is left alone, which keeps the
  /// caret and the selection; other text gets the caret at its end.
  void _showQuery(String query) {
    if (_text.text == query) return;
    _text.value = _valueAtEnd(query);
  }

  void _applyWaitingText() {
    _debounceTimer = null;
    _applyQuery(_text.text);
  }

  void _applyQuery(String query) {
    _cancelDebounce();
    _lastQuery = query;
    widget.controller.query = query;
  }

  /// Applies text that is still waiting for the debounce.
  void _flush() {
    if (_text.text != widget.controller.query) {
      _applyQuery(_text.text);
    } else {
      _cancelDebounce();
    }
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Clears the text and the query and keeps keyboard focus in the field
  /// (the clear button that may hold it disappears); returns false when
  /// both were empty already.
  bool _clear() {
    if (_text.text.isEmpty && widget.controller.query.isEmpty) return false;
    _applyQuery('');
    _text.clear();
    _focusNode.requestFocus();
    return true;
  }

  /// Focuses the first matching row and hands keyboard focus to the tree;
  /// returns false when there is no row.
  bool _focusTree() {
    _flush();
    final controller = widget.controller;
    final rows = controller.rows;
    if (rows.isEmpty) return false;
    final index = rows.indexWhere((row) => row.isMatch);
    controller.focus(rows[index < 0 ? 0 : index].id);
    widget.treeFocusNode?.requestFocus();
    return true;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_isComposing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final bool handled;
    if (_clearKey.accepts(event, keyboard)) {
      handled = _clear();
    } else if (_treeKey.accepts(event, keyboard)) {
      handled = _focusTree();
    } else {
      handled = false;
    }
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    var decoration = widget.decoration ?? _defaultDecoration;
    if (decoration.hint == null && decoration.hintText == null) {
      decoration = decoration.copyWith(
        hintText: widget.hintText ?? localizations.searchFieldLabel,
      );
    }
    if (_text.text.isNotEmpty && decoration.suffixIcon == null) {
      decoration = decoration.copyWith(
        suffixIcon: LabeledIconButton(
          label: localizations.clearButtonTooltip,
          icon: Icons.clear,
          onPressed: _clear,
        ),
      );
    }
    // The transparent Material lets the field and its clear button work in
    // places without one, such as a bare route or a desktop side panel.
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: _handleKeyEvent,
        child: TextField(
          controller: _text,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          decoration: decoration,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          onSubmitted: (_) => _flush(),
        ),
      ),
    );
  }
}
