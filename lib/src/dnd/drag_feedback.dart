part of 'directory_tree_drag_and_drop.dart';

/// How far the start edge of the feedback sits before the pointer.
const double _kFeedbackInset = 16;

/// The widest the default feedback grows before its label is truncated.
const double _kMaxFeedbackWidth = 320;

/// Places the drag feedback at the pointer: centered vertically, with its
/// start edge [_kFeedbackInset] before the pointer (mirrored in RTL).
class _DragFeedbackLayout extends SingleChildLayoutDelegate {
  _DragFeedbackLayout({required this.pointer, required this.textDirection});

  /// The pointer in the coordinates of the overlay.
  final Offset pointer;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final dx = textDirection == TextDirection.ltr
        ? pointer.dx - _kFeedbackInset
        : pointer.dx + _kFeedbackInset - childSize.width;
    return Offset(dx, pointer.dy - childSize.height / 2);
  }

  @override
  bool shouldRelayout(_DragFeedbackLayout oldDelegate) =>
      oldDelegate.pointer != pointer ||
      oldDelegate.textDirection != textDirection;
}

/// The default drag feedback: the icon and label of [node] on a raised
/// card of the theme's row height, with [count] when several nodes move.
class _DefaultDragFeedback extends StatelessWidget {
  const _DefaultDragFeedback({required this.node, required this.count});

  final TreeNode<Object?> node;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = DirectoryTreeTheme.of(context);
    final material = Theme.of(context);
    final colors = material.colorScheme;
    final extent = theme.rowExtent!;
    final countText =
        Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )?.formatDecimal(count) ??
        '$count';
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: _kMaxFeedbackWidth,
        minHeight: extent,
        maxHeight: extent,
      ),
      child: Material(
        elevation: 4,
        color: colors.surfaceContainerHigh,
        borderRadius: theme.rowBorderRadius,
        child: Padding(
          padding: theme.rowPadding!,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                theme.iconSet!.iconFor(node, expanded: false),
                size: theme.iconSize,
                color: node.isDirectory
                    ? theme.folderIconColor
                    : theme.iconColor,
              ),
              SizedBox(width: theme.iconSpacing),
              Flexible(
                child: Text(
                  node.label,
                  style: theme.labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count > 1) ...[
                SizedBox(width: theme.iconSpacing),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colors.primary,
                    shape: const StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      countText,
                      style: material.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
