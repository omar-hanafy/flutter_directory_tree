import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_directory_tree/src/widgets/row_scope.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

/// The expand arrow of a row: a chevron that toggles the directory, a
/// progress indicator while its children load, or an error icon that
/// retries a failed load.
///
/// [DirectoryTreeRow] shows one in front of the icon; use it in a custom
/// row to keep the standard behavior. What it shows follows [details]:
///
/// * [DirectoryLoadStatus.loading]: a small [CircularProgressIndicator].
/// * [DirectoryLoadStatus.failed]: an [Icons.error_outline] in the theme's
///   error color. A click calls [DirectoryTreeController.expand], which
///   starts the load again (and expands the directory if it was
///   collapsed).
/// * Otherwise, when [DirectoryTreeRowDetails.isExpandable]: a chevron that
///   points to the end edge (mirrored in right-to-left text) and rotates
///   to point down while the row is expanded, over the theme's
///   [DirectoryTreeThemeData.animationDuration] (instant when
///   [MediaQuery.disableAnimationsOf] is true). A click calls
///   [DirectoryTreeController.toggleExpansion].
/// * Otherwise an empty box, so rows with and without an arrow line up.
///
/// The widget is [DirectoryTreeThemeData.expanderSize] wide and as tall as
/// its parent allows (that size when the height is unbounded), so the whole
/// height of a row is the hit area. A click also moves the controller's
/// focus to the row and gives the tree keyboard focus, but never selects
/// the row or activates it: the click does not reach the row's own click
/// handling.
///
/// Inside a [SliverDirectoryTree] the expander adds nothing to the
/// semantics tree: the row's node reports the expanded state and the load
/// state, and offers the expand, collapse, and retry actions, so screen
/// readers get one node per row with a touch target as large as the row.
/// Elsewhere the chevron is a button labeled with
/// [MaterialLocalizations.collapsedIconTapHint] ("Expand") or
/// [MaterialLocalizations.expandedIconTapHint] ("Collapse"), and the error
/// icon a button labeled with
/// [MaterialLocalizations.refreshIndicatorSemanticLabel] ("Refresh") that
/// retries the load.
class DirectoryTreeExpander<T> extends StatelessWidget {
  /// Creates the expander of the row described by [details].
  const DirectoryTreeExpander({super.key, required this.details});

  /// The row this expander belongs to.
  final DirectoryTreeRowDetails<T> details;

  @override
  Widget build(BuildContext context) {
    final theme = DirectoryTreeTheme.of(context);
    final size = math.max(0.0, theme.expanderSize!);
    final glyphSize = math.max(0.0, math.min(size, theme.iconSize!));
    final row = details.row;
    final localizations =
        Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) ??
        const DefaultMaterialLocalizations();

    Widget? glyph;
    VoidCallback? onTap;
    String? semanticsLabel;
    switch (details.loadStatus) {
      case DirectoryLoadStatus.loading:
        final spinner = math.max(0.0, glyphSize - 4);
        glyph = SizedBox.square(
          dimension: spinner,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.iconColor,
          ),
        );
      case DirectoryLoadStatus.failed:
        glyph = Icon(
          Icons.error_outline,
          size: glyphSize,
          color: Theme.of(context).colorScheme.error,
        );
        onTap = () => _retry(context);
        semanticsLabel = localizations.refreshIndicatorSemanticLabel;
      case DirectoryLoadStatus.notLoaded:
      case DirectoryLoadStatus.loaded:
        if (details.isExpandable) {
          final expanded = row.isExpanded;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final animate =
              !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
          // Icons.chevron_right mirrors itself in right-to-left text, so it
          // points to the end edge in both directions; turning it a quarter
          // toward the bottom is clockwise in LTR and counterclockwise in
          // RTL.
          glyph = AnimatedRotation(
            turns: expanded ? (rtl ? -0.25 : 0.25) : 0,
            duration: animate ? theme.animationDuration! : Duration.zero,
            curve: theme.animationCurve!,
            child: Icon(
              Icons.chevron_right,
              size: glyphSize,
              color: theme.iconColor,
            ),
          );
          onTap = () => _toggle(context);
          semanticsLabel = expanded
              ? localizations.expandedIconTapHint
              : localizations.collapsedIconTapHint;
        }
    }

    final box = LimitedBox(
      maxHeight: size,
      child: SizedBox(
        width: size,
        height: double.infinity,
        child: glyph == null ? null : Center(child: glyph),
      ),
    );
    if (onTap == null) return ExcludeSemantics(child: box);
    final Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: MouseRegion(cursor: SystemMouseCursors.click, child: box),
    );
    // In a sliver row the row's node carries the state and the actions.
    if (RowSemanticsScope.isInside(context)) {
      return ExcludeSemantics(child: button);
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: button,
    );
  }

  void _toggle(BuildContext context) {
    final controller = details.controller;
    final id = details.row.id;
    requestTreeFocus(context);
    controller
      ..toggleExpansion(id)
      ..focus(id);
  }

  void _retry(BuildContext context) {
    final controller = details.controller;
    final id = details.row.id;
    requestTreeFocus(context);
    controller
      ..expand(id)
      ..focus(id);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<DirectoryTreeRowDetails<T>>('details', details),
    );
  }
}
