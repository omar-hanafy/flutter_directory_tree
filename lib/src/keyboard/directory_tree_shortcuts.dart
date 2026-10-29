import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';

/// The default key bindings of a tree view, for [DirectoryTreeKeyboard].
///
/// [defaults] returns the bindings for one platform and text direction.
/// Start from them to add, change, or remove a binding, then pass the
/// result as [DirectoryTreeKeyboard.shortcuts]:
///
/// ```dart
/// DirectoryTreeKeyboard<Object?>(
///   controller: controller,
///   shortcuts: <ShortcutActivator, Intent>{
///     ...DirectoryTreeShortcuts.defaults(
///       platform: defaultTargetPlatform,
///       textDirection: Directionality.of(context),
///     ),
///     const SingleActivator(LogicalKeyboardKey.f2): const RenameIntent(),
///   },
///   child: treeView,
/// )
/// ```
///
/// To change what a key does instead of which key does it, keep the
/// bindings and override the intent's action with an [Actions] widget above
/// the keyboard widget (see [DirectoryTreeKeyboard]).
abstract final class DirectoryTreeShortcuts {
  /// The default bindings for [platform] and [textDirection], as an
  /// unmodifiable map.
  ///
  /// On every platform:
  ///
  /// * Up and Down: [MoveTreeFocusIntent] with [TreeFocusMove.previous] and
  ///   [TreeFocusMove.next]; Home, End, PageUp, and PageDown: the
  ///   [TreeFocusMove.first], [TreeFocusMove.last], [TreeFocusMove.pageUp],
  ///   and [TreeFocusMove.pageDown] moves. With Shift these moves extend the
  ///   selection ([TreeSelectionUpdate.extend]); otherwise they replace it.
  /// * Right and Left: [ExpandTreeNodeIntent] and [CollapseTreeNodeIntent],
  ///   swapped when [textDirection] is [TextDirection.rtl], so the arrow
  ///   that points into the row's indentation always collapses.
  /// * NumpadAdd and NumpadSubtract: [ExpandTreeNodeIntent] and
  ///   [CollapseTreeNodeIntent] (in every direction).
  /// * The `*` character (from any key that types it) and NumpadMultiply:
  ///   [ExpandTreeSubtreeIntent].
  /// * Enter and NumpadEnter: [ActivateTreeNodeIntent].
  /// * Space and Ctrl+Space: [ToggleTreeSelectionIntent].
  /// * Escape: [ClearTreeSelectionIntent].
  /// * Shift+F10 and the context menu key: [OpenTreeContextMenuIntent].
  ///
  /// On macOS and iOS (Apple keyboards), also:
  ///
  /// * Cmd+A: [SelectAllTreeNodesIntent].
  /// * Cmd+Down: [ActivateTreeNodeIntent], and Cmd+Up: [MoveTreeFocusIntent]
  ///   with [TreeFocusMove.parent], as in Finder.
  ///
  /// On every other platform, also:
  ///
  /// * Ctrl+A: [SelectAllTreeNodesIntent].
  /// * Ctrl with Up, Down, Home, End, PageUp, or PageDown: the same moves
  ///   with [TreeSelectionUpdate.keep], so the focus moves without touching
  ///   the selection (then Ctrl+Space toggles the focused row).
  ///
  /// Bindings require exactly the modifiers listed (for example, Ctrl+Shift+
  /// Down is not bound) and fire on key repeats too. Each combination of a
  /// platform family and a direction returns the same constant map, so
  /// passing the result to a widget on every build costs nothing. To change
  /// it, copy it into a new map, as the [DirectoryTreeShortcuts] example
  /// shows.
  static Map<ShortcutActivator, Intent> defaults({
    required TargetPlatform platform,
    required TextDirection textDirection,
  }) {
    final apple =
        platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;
    final rtl = textDirection == TextDirection.rtl;
    if (apple) return rtl ? _appleRtl : _appleLtr;
    return rtl ? _otherRtl : _otherLtr;
  }

  // Shared by every platform and direction.
  static const Map<ShortcutActivator, Intent>
  _common = <ShortcutActivator, Intent>{
    // Focus moves that replace the selection.
    SingleActivator(LogicalKeyboardKey.arrowUp): MoveTreeFocusIntent(
      TreeFocusMove.previous,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): MoveTreeFocusIntent(
      TreeFocusMove.next,
    ),
    SingleActivator(LogicalKeyboardKey.home): MoveTreeFocusIntent(
      TreeFocusMove.first,
    ),
    SingleActivator(LogicalKeyboardKey.end): MoveTreeFocusIntent(
      TreeFocusMove.last,
    ),
    SingleActivator(LogicalKeyboardKey.pageUp): MoveTreeFocusIntent(
      TreeFocusMove.pageUp,
    ),
    SingleActivator(LogicalKeyboardKey.pageDown): MoveTreeFocusIntent(
      TreeFocusMove.pageDown,
    ),
    // Focus moves that extend the selection.
    SingleActivator(
      LogicalKeyboardKey.arrowUp,
      shift: true,
    ): MoveTreeFocusIntent(
      TreeFocusMove.previous,
      selection: TreeSelectionUpdate.extend,
    ),
    SingleActivator(
      LogicalKeyboardKey.arrowDown,
      shift: true,
    ): MoveTreeFocusIntent(
      TreeFocusMove.next,
      selection: TreeSelectionUpdate.extend,
    ),
    SingleActivator(LogicalKeyboardKey.home, shift: true): MoveTreeFocusIntent(
      TreeFocusMove.first,
      selection: TreeSelectionUpdate.extend,
    ),
    SingleActivator(LogicalKeyboardKey.end, shift: true): MoveTreeFocusIntent(
      TreeFocusMove.last,
      selection: TreeSelectionUpdate.extend,
    ),
    SingleActivator(
      LogicalKeyboardKey.pageUp,
      shift: true,
    ): MoveTreeFocusIntent(
      TreeFocusMove.pageUp,
      selection: TreeSelectionUpdate.extend,
    ),
    SingleActivator(
      LogicalKeyboardKey.pageDown,
      shift: true,
    ): MoveTreeFocusIntent(
      TreeFocusMove.pageDown,
      selection: TreeSelectionUpdate.extend,
    ),
    // Expansion.
    SingleActivator(LogicalKeyboardKey.numpadAdd): ExpandTreeNodeIntent(),
    SingleActivator(LogicalKeyboardKey.numpadSubtract):
        CollapseTreeNodeIntent(),
    CharacterActivator('*'): ExpandTreeSubtreeIntent(),
    SingleActivator(LogicalKeyboardKey.numpadMultiply):
        ExpandTreeSubtreeIntent(),
    // Activation, selection, and the context menu.
    SingleActivator(LogicalKeyboardKey.enter): ActivateTreeNodeIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateTreeNodeIntent(),
    SingleActivator(LogicalKeyboardKey.space): ToggleTreeSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.space, control: true):
        ToggleTreeSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.escape): ClearTreeSelectionIntent(),
    SingleActivator(LogicalKeyboardKey.f10, shift: true):
        OpenTreeContextMenuIntent(),
    SingleActivator(LogicalKeyboardKey.contextMenu):
        OpenTreeContextMenuIntent(),
  };

  static const Map<ShortcutActivator, Intent> _ltrArrows =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowRight): ExpandTreeNodeIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): CollapseTreeNodeIntent(),
      };

  static const Map<ShortcutActivator, Intent> _rtlArrows =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft): ExpandTreeNodeIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            CollapseTreeNodeIntent(),
      };

  // macOS and iOS: Cmd instead of Ctrl, and Finder's Cmd+Up and Cmd+Down.
  // Ctrl+arrows belong to the system there (Mission Control), so there is
  // no binding that moves the focus without selecting.
  static const Map<ShortcutActivator, Intent> _apple =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            SelectAllTreeNodesIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
            ActivateTreeNodeIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp, meta: true):
            MoveTreeFocusIntent(TreeFocusMove.parent),
      };

  // Windows, Linux, Android, and Fuchsia: Ctrl+A, and Ctrl with the focus
  // moves keeps the selection.
  static const Map<ShortcutActivator, Intent> _other =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyA, control: true):
            SelectAllTreeNodesIntent(),
        SingleActivator(
          LogicalKeyboardKey.arrowUp,
          control: true,
        ): MoveTreeFocusIntent(
          TreeFocusMove.previous,
          selection: TreeSelectionUpdate.keep,
        ),
        SingleActivator(
          LogicalKeyboardKey.arrowDown,
          control: true,
        ): MoveTreeFocusIntent(
          TreeFocusMove.next,
          selection: TreeSelectionUpdate.keep,
        ),
        SingleActivator(
          LogicalKeyboardKey.home,
          control: true,
        ): MoveTreeFocusIntent(
          TreeFocusMove.first,
          selection: TreeSelectionUpdate.keep,
        ),
        SingleActivator(
          LogicalKeyboardKey.end,
          control: true,
        ): MoveTreeFocusIntent(
          TreeFocusMove.last,
          selection: TreeSelectionUpdate.keep,
        ),
        SingleActivator(
          LogicalKeyboardKey.pageUp,
          control: true,
        ): MoveTreeFocusIntent(
          TreeFocusMove.pageUp,
          selection: TreeSelectionUpdate.keep,
        ),
        SingleActivator(
          LogicalKeyboardKey.pageDown,
          control: true,
        ): MoveTreeFocusIntent(
          TreeFocusMove.pageDown,
          selection: TreeSelectionUpdate.keep,
        ),
      };

  static const Map<ShortcutActivator, Intent> _appleLtr =
      <ShortcutActivator, Intent>{..._common, ..._ltrArrows, ..._apple};

  static const Map<ShortcutActivator, Intent> _appleRtl =
      <ShortcutActivator, Intent>{..._common, ..._rtlArrows, ..._apple};

  static const Map<ShortcutActivator, Intent> _otherLtr =
      <ShortcutActivator, Intent>{..._common, ..._ltrArrows, ..._other};

  static const Map<ShortcutActivator, Intent> _otherRtl =
      <ShortcutActivator, Intent>{..._common, ..._rtlArrows, ..._other};
}
