// Imported only so documentation references to the controller resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';

/// A keyboard-style move of the focused row, for
/// [DirectoryTreeController.moveFocus].
///
/// Moves work on the visible rows ([DirectoryTreeController.rows]). With no
/// row focused, [last] and [previous] go to the last row and every other
/// move goes to the first row.
enum TreeFocusMove {
  /// The next row (down arrow); stays on the last row.
  next,

  /// The previous row (up arrow); stays on the first row.
  previous,

  /// The first row (Home).
  first,

  /// The last row (End).
  last,

  /// The parent row (left arrow on a collapsed row); no move on a depth-0
  /// row.
  parent,

  /// The first child row (right arrow on an expanded row); no move when the
  /// row shows no child rows.
  firstChild,

  /// One page of rows down (Page Down), clamped to the last row.
  pageDown,

  /// One page of rows up (Page Up), clamped to the first row.
  pageUp,
}

/// What [DirectoryTreeController.moveFocus] does to the selection after the
/// focus moves.
enum TreeSelectionUpdate {
  /// Selects the newly focused row alone, as
  /// [DirectoryTreeController.select] does (plain arrow keys).
  replace,

  /// Extends the selection from the anchor to the newly focused row, as
  /// [DirectoryTreeController.extendSelection] does (Shift with arrow
  /// keys).
  extend,

  /// Leaves the selection as it is, so only the focus moves (Ctrl with
  /// arrow keys on Windows and Linux).
  keep,
}
