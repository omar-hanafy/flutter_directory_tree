import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// An [IconButton] whose [label] is both its semantics label and its
/// tooltip; the buttons of the search field and the toolbar use it.
///
/// [IconButton.tooltip] names a button only through a semantics tooltip.
/// This widget puts [label] in the button's semantics label instead and
/// shows the same text in a [Tooltip] that is excluded from semantics, so
/// assistive technologies find one name and announce it once.
///
/// With a non-null [isSelected] the button is a toggle. Material 3 icon
/// buttons draw and announce the selected state themselves; Material 2 ones
/// ignore [IconButton.isSelected], so under Material 2 this widget colors a
/// selected icon with [ColorScheme.primary] and adds the selected state to
/// the button's semantics.
///
/// Not exported: the package's public widgets build it internally.
@internal
class LabeledIconButton extends StatelessWidget {
  /// Creates a button that shows [icon] and calls [onPressed].
  const LabeledIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isSelected,
  });

  /// The name of the action: the semantics label and the tooltip text.
  final String label;

  /// The icon the button shows.
  final IconData icon;

  /// Called when the button is tapped or activated with the keyboard.
  final VoidCallback onPressed;

  /// Whether a toggle button is on, or `null` for a plain button.
  final bool? isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = isSelected;
    Widget icon = Icon(this.icon, semanticLabel: label);
    Color? color;
    if (selected != null && !theme.useMaterial3) {
      // The semantics go below the button so they mark the button's own
      // node, as Material 3 does for its selected state.
      icon = Semantics(selected: selected, child: icon);
      if (selected) color = theme.colorScheme.primary;
    }
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        isSelected: selected,
        color: color,
        icon: icon,
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(DiagnosticsProperty<bool>('isSelected', isSelected));
  }
}
