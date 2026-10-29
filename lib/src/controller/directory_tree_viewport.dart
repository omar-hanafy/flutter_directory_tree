import 'package:flutter/animation.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';

/// A widget that shows the rows of a [DirectoryTreeController] and can
/// scroll them into view.
///
/// The controller has no widgets of its own. A view that displays
/// [DirectoryTreeController.rows] implements this interface and registers
/// itself with [DirectoryTreeController.attachViewport] while it is mounted
/// (and [DirectoryTreeController.detachViewport] when it goes away), so that
/// [DirectoryTreeController.ensureVisible] can scroll it and
/// [DirectoryTreeController.moveFocus] can page by what fits on screen.
///
/// Row indexes are indexes into [DirectoryTreeController.rows] at the time
/// of the call. The controller notifies its listeners before it asks a
/// viewport to show a row that a command just created, so a viewport may be
/// asked about rows it has not built yet; it should compute positions from
/// the index rather than from built children.
abstract interface class DirectoryTreeViewport {
  /// The number of rows that fit fully inside the visible area, at least 1.
  ///
  /// [DirectoryTreeController.moveFocus] uses the largest value among the
  /// attached viewports as the page size of [TreeFocusMove.pageDown] and
  /// [TreeFocusMove.pageUp] when the caller gives none.
  int get pageRowCount;

  /// Scrolls so the row at [index] is visible, animating over [duration]
  /// with [curve] (jumping when [duration] is [Duration.zero]).
  ///
  /// With [alignment] `null` (the default) the scroll is minimal: the least
  /// distance that makes the row fully visible, and nothing at all when it
  /// already is. Otherwise [alignment] places the row in the viewport: 0 at
  /// the top, 1 at the bottom, 0.5 in the middle, with the offset clamped to
  /// the scroll range. The returned future completes when the scroll ends.
  /// [index] is in the range of [DirectoryTreeController.rows].
  Future<void> showRow(
    int index, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  });

  /// The bounds of the row at [index] in global coordinates, or `null` when
  /// no part of that row is on screen.
  ///
  /// The result is the whole row, also when only part of it is visible. It
  /// is `null` when the row is not laid out yet, when it is scrolled out of
  /// the visible area (even if the scroll view built it ahead, in its cache
  /// extent), and when a pinned header covers it.
  ///
  /// Use it to anchor a menu or a tooltip to a row, for example the context
  /// menu of the focused row.
  Rect? globalRowRect(int index);
}
