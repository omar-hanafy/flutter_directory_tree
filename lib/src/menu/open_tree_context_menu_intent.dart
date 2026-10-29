import 'package:flutter/widgets.dart';

/// An intent to open the context menu of the focused row of a directory
/// tree, as Shift+F10 and the context menu key do.
///
/// A `DirectoryTreeContextMenu` above the focused widget handles it by
/// opening the menu of the controller's focused row; without one, nothing
/// handles it and the key goes on to the enclosing widgets.
///
/// Temporary copy, private to the menu module: the keyboard module declares
/// this intent in `lib/src/keyboard/directory_tree_intents.dart`, and this
/// file is deleted when both modules are merged.
class OpenTreeContextMenuIntent extends Intent {
  /// Creates an intent to open the context menu of the focused row.
  const OpenTreeContextMenuIntent();
}
