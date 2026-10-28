import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
// Imported only so documentation references to the controller resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';

/// How [DirectoryTreeController.rows] changed in its latest update: one
/// contiguous block of rows replaced (a splice), or anything at all (a
/// reset).
///
/// Read it from [DirectoryTreeController.lastRowsChange] in a listener to
/// update a list view without rebuilding or re-anchoring every row: animate
/// the [inserted] rows, keep the scroll position of the rows before [index],
/// and shift the rows after the block by `inserted - removed`.
///
/// A splice is exact for row positions and ids: the rows of the new list
/// are the rows of [previous] before [index], then [inserted] new rows, then
/// the rows of [previous] from `index + removed` on, with the same
/// [TreeRow.id]s in the same order. The row objects outside the block may
/// still differ from those of [previous] (for example the row whose
/// expansion flipped, which sits just before the block, or every row after
/// a lazy load replaced the tree), so compare rows with `identical` before
/// reusing what was built for them.
///
/// Only trust a change whose [previous] is the rows object the view last
/// built: when a view skipped an update (several commands between two
/// frames), treat the change as a reset.
@immutable
final class TreeRowsChange {
  /// A change that may have moved, added, or removed any row, such as a new
  /// tree, a filter change, or a bulk expansion change.
  ///
  /// [isReset] is true and [index], [removed], and [inserted] are 0.
  const TreeRowsChange.reset({required this.previous})
    : isReset = true,
      index = 0,
      removed = 0,
      inserted = 0;

  /// A change that replaced [removed] rows at [index] with [inserted] rows
  /// and kept every other row id in place.
  ///
  /// All three numbers must not be negative.
  const TreeRowsChange.splice({
    required this.previous,
    required this.index,
    required this.removed,
    required this.inserted,
  }) : assert(index >= 0, 'index must not be negative'),
       assert(removed >= 0, 'removed must not be negative'),
       assert(inserted >= 0, 'inserted must not be negative'),
       isReset = false;

  /// The rows object this change replaced, or `null` for the first rows of
  /// a controller.
  ///
  /// Compared by identity in [operator ==]; it is the value that
  /// [DirectoryTreeController.rows] returned right before the change.
  final TreeRows<Object?>? previous;

  /// Whether this change says nothing about which rows stayed: rebuild the
  /// whole list and anchor the scroll position by row id.
  final bool isReset;

  /// The row index where the spliced block starts, the same in [previous]
  /// and in the new rows; 0 for a reset.
  ///
  /// For an expanded or collapsed row this is the index right after that
  /// row, whose own row object changed in place.
  final int index;

  /// How many rows of [previous] the block removed, starting at [index];
  /// 0 for a reset.
  final int removed;

  /// How many new rows the block inserted, starting at [index]; 0 for a
  /// reset.
  final int inserted;

  /// Whether [other] is a [TreeRowsChange] of the same kind with an
  /// identical [previous] and equal [index], [removed], and [inserted].
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreeRowsChange &&
          identical(other.previous, previous) &&
          other.isReset == isReset &&
          other.index == index &&
          other.removed == removed &&
          other.inserted == inserted;

  @override
  int get hashCode => Object.hash(
    identityHashCode(previous),
    isReset,
    index,
    removed,
    inserted,
  );

  /// A description such as `TreeRowsChange.reset()` or
  /// `TreeRowsChange.splice(index: 3, removed: 0, inserted: 2)`; [previous]
  /// is left out.
  @override
  String toString() => isReset
      ? 'TreeRowsChange.reset()'
      : 'TreeRowsChange.splice(index: $index, removed: $removed, '
            'inserted: $inserted)';
}
