// Imported only so documentation references resolve.
import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/rendering/directory_tree_indent_guides.dart';
import 'package:flutter_directory_tree/src/rendering/directory_tree_label.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_checkbox.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_expander.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_directory_tree/src/widgets/row_scope.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

/// The default look of one tree row, drawn from its
/// [DirectoryTreeRowDetails].
///
/// From the start edge: the indentation with its guide lines
/// ([DirectoryTreeIndentGuides]), the [expander] (by default a
/// [DirectoryTreeExpander]), a [DirectoryTreeCheckbox] when
/// [DirectoryTreeRowDetails.checkboxMode] is not
/// [DirectoryTreeCheckboxMode.none], the [leading] icon (by default the
/// [DirectoryTreeThemeData.iconSet] icon of the node, open while the
/// directory is expanded), the [title] (by default a [DirectoryTreeLabel]
/// with the search matches highlighted), and the optional [trailing]
/// widget. Everything mirrors in right-to-left text.
///
/// Colors and styles come from [DirectoryTreeTheme.of]:
///
/// * Background: [DirectoryTreeThemeData.selectedColor] for a selected row
///   while the tree has keyboard focus, and
///   [DirectoryTreeThemeData.inactiveSelectedColor] while it does not;
///   [DirectoryTreeThemeData.hoverColor] for an unselected row under a
///   mouse pointer; nothing otherwise. Corners use
///   [DirectoryTreeThemeData.rowBorderRadius].
/// * Border: [DirectoryTreeThemeData.focusedBorderColor] around the focused
///   row (the keyboard cursor), only while the tree has keyboard focus.
/// * Label: [DirectoryTreeThemeData.selectedLabelStyle] when selected, else
///   [DirectoryTreeThemeData.dimmedLabelStyle] when the row is shown only
///   because a descendant matches the filter ([TreeRow.isMatch] is false),
///   else [DirectoryTreeThemeData.labelStyle].
///
/// Use it from a [DirectoryTreeRowBuilder] to change one part of a row and
/// keep the rest:
///
/// ```dart
/// // A tree whose entries carry file sizes in bytes as their data.
/// SliverDirectoryTree<int>(
///   controller: controller,
///   rowBuilder: (context, details) => DirectoryTreeRow(
///     details: details,
///     trailing: Text('${details.row.node.data ?? ''}'),
///   ),
/// )
/// ```
///
/// The row draws only; [SliverDirectoryTree] adds click, hover, and
/// semantics handling around it. Inside a [SliverDirectoryTree] the label
/// is left out of the semantics tree, because the row's semantics node
/// already carries it; elsewhere the label is read as usual.
class DirectoryTreeRow<T> extends StatelessWidget {
  /// Creates the row described by [details]; the optional widgets replace
  /// their default parts.
  const DirectoryTreeRow({
    super.key,
    required this.details,
    this.expander,
    this.leading,
    this.title,
    this.trailing,
  });

  /// The row to draw and its state.
  final DirectoryTreeRowDetails<T> details;

  /// Replaces the default [DirectoryTreeExpander]; null keeps it.
  ///
  /// Give it the theme's [DirectoryTreeThemeData.expanderSize] width so
  /// rows with and without an arrow line up.
  final Widget? expander;

  /// Replaces the default node icon; null keeps it.
  final Widget? leading;

  /// Replaces the default [DirectoryTreeLabel]; null keeps it.
  ///
  /// It gets the space left between [leading] and [trailing]; keep it to
  /// one line so it fits the fixed row height.
  final Widget? title;

  /// An extra widget at the end edge of the row, such as a size or a
  /// badge; null shows nothing.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = DirectoryTreeTheme.of(context);
    final details = this.details;
    final row = details.row;
    final node = row.node;
    final isMatch = row.isMatch;

    final Color? background;
    if (details.isSelected) {
      background = details.hasFocus
          ? theme.selectedColor
          : theme.inactiveSelectedColor;
    } else if (details.isHovered) {
      background = theme.hoverColor;
    } else {
      background = null;
    }
    final border = details.isFocused && details.hasFocus
        ? Border.all(
            color: theme.focusedBorderColor!,
            width: theme.focusedBorderWidth!,
          )
        : null;

    final TextStyle? labelStyle;
    if (details.isSelected) {
      labelStyle = theme.selectedLabelStyle;
    } else if (!isMatch) {
      labelStyle = theme.dimmedLabelStyle;
    } else {
      labelStyle = theme.labelStyle;
    }
    Widget label =
        title ??
        DirectoryTreeLabel(
          text: row.label,
          matchRanges: details.matchRanges,
          style: labelStyle,
        );
    if (RowSemanticsScope.isInside(context)) {
      label = ExcludeSemantics(child: label);
    }

    final icon =
        leading ??
        Icon(
          theme.iconSet!.iconFor(node, expanded: row.isExpanded),
          size: theme.iconSize,
          color: node.isDirectory ? theme.folderIconColor : theme.iconColor,
        );
    final spacing = SizedBox(width: theme.iconSpacing);
    final trailing = this.trailing;
    // Only the connector style reads the guides, which the core computes on
    // every read in O(depth).
    final guides = theme.guideStyle == DirectoryTreeGuideStyle.connectors
        ? row.guides
        : const <bool>[];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: theme.rowBorderRadius,
        border: border,
      ),
      child: Padding(
        padding: theme.rowPadding!,
        child: Row(
          children: <Widget>[
            DirectoryTreeIndentGuides(
              depth: row.depth,
              guides: guides,
              isLast: row.isLast,
            ),
            expander ?? DirectoryTreeExpander<T>(details: details),
            if (details.checkboxMode != DirectoryTreeCheckboxMode.none)
              DirectoryTreeCheckbox<T>(details: details),
            icon,
            spacing,
            Expanded(child: label),
            if (trailing != null) ...<Widget>[spacing, trailing],
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DirectoryTreeRowDetails<T>>('details', details))
      ..add(ObjectFlagProperty<Widget>.has('expander', expander))
      ..add(ObjectFlagProperty<Widget>.has('leading', leading))
      ..add(ObjectFlagProperty<Widget>.has('title', title))
      ..add(ObjectFlagProperty<Widget>.has('trailing', trailing));
  }
}
