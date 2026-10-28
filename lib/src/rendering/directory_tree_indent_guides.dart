import 'dart:math' as math;

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';

/// The indentation of one row, with guide lines that show its place in the
/// tree.
///
/// The widget is `depth * indentWidth` wide and fills the height its parent
/// allows, so in a row it spans the row's full height; when the height is
/// unbounded, as in a [Row] inside a [ListView] without a fixed item extent,
/// it is [DirectoryTreeThemeData.rowExtent] tall. Each depth level is a slot
/// `indentWidth` wide, numbered from the start edge, so slot 0 belongs to the
/// top-level ancestor. Lines are centered in their slots, and [style] decides
/// which slots get one:
///
/// * [DirectoryTreeGuideStyle.indent]: a full-height vertical line in every
///   slot.
/// * [DirectoryTreeGuideStyle.connectors]: the connectors [DirectoryTree.render]
///   prints, as lines. Each slot `j` before the last (`j` up to `depth - 2`)
///   has a full-height vertical line when `guides[j + 1]` is true, that is,
///   when the ancestor at depth `j + 1` has a later sibling. The last slot
///   (`depth - 1`) has an elbow: a vertical line from the top to the middle
///   that continues to the bottom unless [isLast], and a horizontal line from
///   the middle of the slot to its end edge, toward the row's content.
/// * [DirectoryTreeGuideStyle.none]: no lines; the indentation remains.
///
/// Under [TextDirection.rtl] everything is mirrored: slot 0 is at the right
/// edge and elbows point left. Top-level rows (depth 0) take no width.
///
/// Parameters left null come from [DirectoryTreeTheme.of]. Pass
/// [TreeRow.depth], [TreeRow.guides], and [TreeRow.isLast] of the row being
/// built. Painting uses a [CustomPainter] that asks for a repaint only when
/// one of these inputs (or the text direction) changes, so rebuilding a row
/// with equal values does not mark its guides for painting.
class DirectoryTreeIndentGuides extends StatelessWidget {
  /// Creates the guides of a row at [depth].
  ///
  /// [depth], [indentWidth], and [width] must not be negative.
  const DirectoryTreeIndentGuides({
    super.key,
    required this.depth,
    required this.guides,
    required this.isLast,
    this.style,
    this.indentWidth,
    this.color,
    this.width,
  }) : assert(depth >= 0, 'depth must not be negative'),
       assert(
         indentWidth == null || indentWidth >= 0,
         'indentWidth must not be negative',
       ),
       assert(width == null || width >= 0, 'width must not be negative');

  /// The row's indentation level: 0 for top-level rows, as in
  /// [TreeRow.depth].
  final int depth;

  /// For each ancestor level, whether a vertical line continues through it,
  /// as in [TreeRow.guides]: `guides[i]` is true when the row's ancestor at
  /// depth `i` has a later visible sibling.
  ///
  /// Only [DirectoryTreeGuideStyle.connectors] reads it, at indexes 1 to
  /// `depth - 1`. Missing entries count as false and extra entries are
  /// ignored.
  final List<bool> guides;

  /// Whether the row is the last of its siblings, as in [TreeRow.isLast].
  ///
  /// Under [DirectoryTreeGuideStyle.connectors] the elbow of the last row
  /// stops at the middle of the row instead of continuing down.
  final bool isLast;

  /// Which lines to draw; null uses [DirectoryTreeThemeData.guideStyle].
  final DirectoryTreeGuideStyle? style;

  /// The width of each depth level in logical pixels; null uses
  /// [DirectoryTreeThemeData.indentWidth].
  final double? indentWidth;

  /// The line color; null uses [DirectoryTreeThemeData.guideColor].
  final Color? color;

  /// The line stroke width in logical pixels, 0 for hairlines; null uses
  /// [DirectoryTreeThemeData.guideWidth].
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = DirectoryTreeTheme.of(context);
    // Theme values are not validated, so negative sizes are clamped here.
    final slotWidth = math.max(0.0, indentWidth ?? theme.indentWidth!);
    return LimitedBox(
      maxHeight: math.max(0.0, theme.rowExtent!),
      child: SizedBox(
        width: depth * slotWidth,
        height: double.infinity,
        child: CustomPaint(
          painter: _IndentGuidesPainter(
            depth: depth,
            guides: guides,
            isLast: isLast,
            style: style ?? theme.guideStyle!,
            slotWidth: slotWidth,
            color: color ?? theme.guideColor!,
            strokeWidth: math.max(0.0, width ?? theme.guideWidth!),
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('depth', depth))
      ..add(IterableProperty<bool>('guides', guides))
      ..add(FlagProperty('isLast', value: isLast, ifTrue: 'last'))
      ..add(
        EnumProperty<DirectoryTreeGuideStyle>(
          'style',
          style,
          defaultValue: null,
        ),
      )
      ..add(DoubleProperty('indentWidth', indentWidth, defaultValue: null))
      ..add(ColorProperty('color', color, defaultValue: null))
      ..add(DoubleProperty('width', width, defaultValue: null));
  }
}

final class _IndentGuidesPainter extends CustomPainter {
  _IndentGuidesPainter({
    required this.depth,
    required this.guides,
    required this.isLast,
    required this.style,
    required this.slotWidth,
    required this.color,
    required this.strokeWidth,
    required this.textDirection,
  });

  final int depth;
  final List<bool> guides;
  final bool isLast;
  final DirectoryTreeGuideStyle style;
  final double slotWidth;
  final Color color;
  final double strokeWidth;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth == 0 || slotWidth == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rtl = textDirection == TextDirection.rtl;
    final height = size.height;

    // Horizontal positions are measured from the start edge and mirrored
    // against the right edge of the box in right-to-left text.
    double xAt(double fromStart) => rtl ? size.width - fromStart : fromStart;
    double centerOf(int slot) => xAt((slot + 0.5) * slotWidth);

    switch (style) {
      case DirectoryTreeGuideStyle.none:
        return;
      case DirectoryTreeGuideStyle.indent:
        for (var slot = 0; slot < depth; slot++) {
          final x = centerOf(slot);
          canvas.drawLine(Offset(x, 0), Offset(x, height), paint);
        }
      case DirectoryTreeGuideStyle.connectors:
        final last = depth - 1;
        for (var slot = 0; slot < last; slot++) {
          if (slot + 1 < guides.length && guides[slot + 1]) {
            final x = centerOf(slot);
            canvas.drawLine(Offset(x, 0), Offset(x, height), paint);
          }
        }
        final x = centerOf(last);
        final middle = height / 2;
        // The horizontal line starts at the far edge of the vertical stroke
        // so the corner of a last row's elbow is filled.
        final halfStroke = strokeWidth / 2;
        canvas
          ..drawLine(Offset(x, 0), Offset(x, isLast ? middle : height), paint)
          ..drawLine(
            Offset(rtl ? x + halfStroke : x - halfStroke, middle),
            Offset(xAt(depth * slotWidth), middle),
            paint,
          );
    }
  }

  @override
  bool shouldRepaint(_IndentGuidesPainter oldDelegate) =>
      oldDelegate.depth != depth ||
      oldDelegate.isLast != isLast ||
      oldDelegate.style != style ||
      oldDelegate.slotWidth != slotWidth ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.textDirection != textDirection ||
      !listEquals(oldDelegate.guides, guides);
}
