import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';

/// Which checkbox, if any, each row shows in front of its icon.
///
/// The default row draws the checkbox; a custom row reads
/// [DirectoryTreeRowDetails.checkboxMode] and
/// [DirectoryTreeRowDetails.checkState] to draw its own.
enum DirectoryTreeCheckboxMode {
  /// No checkbox; [DirectoryTreeRowDetails.checkState] is null.
  none,

  /// A tri-state checkbox bound to [DirectoryTreeController.checks].
  ///
  /// A directory shows [CheckState.partial] when only some of its leaves are
  /// checked, and toggling it checks or unchecks its whole subtree.
  checks,

  /// A two-state checkbox that mirrors the highlight selection.
  ///
  /// It is checked while the row is selected, and toggling it toggles only
  /// that row's selection: a directory never selects its children.
  selection,
}

/// Builds the widget for one row of a tree view.
///
/// Return the default row with some parts replaced, or any widget that fits
/// the theme's fixed row extent. The view wraps the result with the
/// built-in click, hover, and semantics handling, so the builder only
/// draws. It runs again only for rows whose [DirectoryTreeRowDetails]
/// changed.
typedef DirectoryTreeRowBuilder<T> = Widget Function(
  BuildContext context,
  DirectoryTreeRowDetails<T> details,
);

/// Wraps the widget of one row, for example to make it draggable.
///
/// The view applies a decorator around the built and interactive row; drag
/// and drop installs one. A decorator must keep the row's size.
typedef DirectoryTreeRowDecorator<T> = Widget Function(
  BuildContext context,
  DirectoryTreeRowDetails<T> details,
  Widget child,
);

/// Everything a row widget needs to draw one visible row of a tree view.
///
/// A tree view creates new details whenever a row or its state changes and
/// reuses the previous row widget while the details stay equal, so a
/// [DirectoryTreeRowBuilder] only runs for rows that changed.
///
/// Equality compares [controller] and [row] by identity (the core keeps
/// unchanged [TreeRow] objects identical across incremental updates, so
/// identity is the cheap and exact test) and every other field by value.
@immutable
final class DirectoryTreeRowDetails<T> {
  /// Creates the details of one row.
  ///
  /// Tree views create these; tests and custom slivers may create them too.
  const DirectoryTreeRowDetails({
    required this.controller,
    required this.row,
    required this.index,
    required this.isSelected,
    required this.isFocused,
    required this.hasFocus,
    required this.isHovered,
    required this.checkboxMode,
    required this.checkState,
    required this.loadStatus,
    required this.isExpandable,
    required this.matchRanges,
  });

  /// The controller that owns the row.
  ///
  /// Custom rows call its commands, for example
  /// [DirectoryTreeController.toggleExpansion] from their own expander.
  final DirectoryTreeController<T> controller;

  /// The visible row: its node, depth, guides, label, expansion, and match
  /// flags.
  final TreeRow<T> row;

  /// The index of [row] in [DirectoryTreeController.rows].
  final int index;

  /// Whether the row's node is in [DirectoryTreeController.selection].
  final bool isSelected;

  /// Whether this row is [DirectoryTreeController.focusedRow], the keyboard
  /// cursor.
  final bool isFocused;

  /// Whether the tree view has keyboard focus.
  ///
  /// When false, draw the selection with the inactive color and no focus
  /// border, so the user can tell which part of the screen keys go to.
  final bool hasFocus;

  /// Whether a mouse pointer is over the row; always false for touch.
  final bool isHovered;

  /// Which checkbox the view shows in front of the icon.
  final DirectoryTreeCheckboxMode checkboxMode;

  /// The state of the row's checkbox.
  ///
  /// Null for [DirectoryTreeCheckboxMode.none]. For
  /// [DirectoryTreeCheckboxMode.checks], the value of
  /// [DirectoryTreeController.checkStateOf]. For
  /// [DirectoryTreeCheckboxMode.selection], [CheckState.checked] when
  /// [isSelected] and [CheckState.unchecked] otherwise.
  final CheckState? checkState;

  /// The lazy-loading status of the row's node.
  ///
  /// [DirectoryLoadStatus.loaded] for files and for every node of a
  /// controller without a loader.
  final DirectoryLoadStatus loadStatus;

  /// Whether the row shows an expander, from
  /// [DirectoryTreeController.isExpandable].
  ///
  /// True for directories with visible children and for lazy directories
  /// that are not loaded yet.
  final bool isExpandable;

  /// The ranges of [TreeRow.label] to highlight for the search query, from
  /// [DirectoryTreeController.matchRangesOf].
  ///
  /// Sorted, non-overlapping `[start, end)` UTF-16 ranges; empty when there
  /// is nothing to highlight.
  final List<({int start, int end})> matchRanges;

  /// Returns a copy with the given fields replaced.
  ///
  /// The view uses it to apply hover changes without recomputing the rest.
  DirectoryTreeRowDetails<T> copyWith({
    TreeRow<T>? row,
    int? index,
    bool? isSelected,
    bool? isFocused,
    bool? hasFocus,
    bool? isHovered,
    DirectoryTreeCheckboxMode? checkboxMode,
    CheckState? checkState,
    DirectoryLoadStatus? loadStatus,
    bool? isExpandable,
    List<({int start, int end})>? matchRanges,
  }) => DirectoryTreeRowDetails<T>(
    controller: controller,
    row: row ?? this.row,
    index: index ?? this.index,
    isSelected: isSelected ?? this.isSelected,
    isFocused: isFocused ?? this.isFocused,
    hasFocus: hasFocus ?? this.hasFocus,
    isHovered: isHovered ?? this.isHovered,
    checkboxMode: checkboxMode ?? this.checkboxMode,
    checkState: checkState ?? this.checkState,
    loadStatus: loadStatus ?? this.loadStatus,
    isExpandable: isExpandable ?? this.isExpandable,
    matchRanges: matchRanges ?? this.matchRanges,
  );

  /// Whether [other] describes the same row in the same state.
  ///
  /// [controller] and [row] compare by identity, everything else by value.
  /// O(number of match ranges).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryTreeRowDetails<T> &&
          identical(other.controller, controller) &&
          identical(other.row, row) &&
          other.index == index &&
          other.isSelected == isSelected &&
          other.isFocused == isFocused &&
          other.hasFocus == hasFocus &&
          other.isHovered == isHovered &&
          other.checkboxMode == checkboxMode &&
          other.checkState == checkState &&
          other.loadStatus == loadStatus &&
          other.isExpandable == isExpandable &&
          listEquals(other.matchRanges, matchRanges);

  /// A hash consistent with [operator ==].
  @override
  int get hashCode => Object.hash(
    identityHashCode(controller),
    identityHashCode(row),
    index,
    isSelected,
    isFocused,
    hasFocus,
    isHovered,
    checkboxMode,
    checkState,
    loadStatus,
    isExpandable,
    Object.hashAll(matchRanges),
  );

  /// A description with the row label, index, and the flags that are set,
  /// such as `DirectoryTreeRowDetails(lib, index: 1, selected, focused)`.
  @override
  String toString() {
    final flags = [
      if (isSelected) 'selected',
      if (isFocused) 'focused',
      if (hasFocus) 'tree focused',
      if (isHovered) 'hovered',
      if (isExpandable) 'expandable',
      if (checkState != null) 'check: ${checkState!.name}',
      if (loadStatus != DirectoryLoadStatus.loaded) 'load: ${loadStatus.name}',
      if (matchRanges.isNotEmpty) 'matches: ${matchRanges.length}',
    ];
    final flagText = flags.isEmpty ? '' : ', ${flags.join(', ')}';
    return 'DirectoryTreeRowDetails(${row.label}, index: $index$flagText)';
  }
}
