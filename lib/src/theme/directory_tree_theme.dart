import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/rendering/directory_tree_indent_guides.dart';
import 'package:flutter_directory_tree/src/rendering/directory_tree_label.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_icon_set.dart';

/// How [DirectoryTreeIndentGuides] marks the depth of a row.
enum DirectoryTreeGuideStyle {
  /// No lines.
  ///
  /// Rows keep their indentation of `depth * indentWidth`; only the lines are
  /// gone.
  none,

  /// A vertical line through every indentation level of a row, like the
  /// indent guides of a code editor.
  indent,

  /// The connectors that [DirectoryTree.render] prints, drawn as lines: an
  /// elbow from the parent's line into each row, and a vertical line in every
  /// level whose ancestor has a later sibling.
  connectors,
}

/// The sizes, colors, text styles, icons, and motion of directory tree views.
///
/// Every field is optional. Widgets read the resolved theme from
/// [DirectoryTreeTheme.of], which starts from [DirectoryTreeThemeData.fallback]
/// (defaults derived from the ambient Material 3 [ThemeData]) and applies, in
/// order, this class registered as a theme extension and the data of the
/// nearest [DirectoryTreeTheme]. A null field therefore means "inherit".
///
/// Register app-wide values as a theme extension, so they animate with
/// [ThemeData.lerp] when the app theme changes:
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     extensions: const [DirectoryTreeThemeData(indentWidth: 20)],
///   ),
///   home: const MyExplorer(),
/// );
/// ```
///
/// Use a [DirectoryTreeTheme] to change values for one subtree.
@immutable
class DirectoryTreeThemeData extends ThemeExtension<DirectoryTreeThemeData>
    with Diagnosticable {
  /// Creates a theme; each null field is filled from the themes underneath
  /// it when [DirectoryTreeTheme.of] resolves it.
  ///
  /// In debug mode, asserts that [rowExtent], when given, is positive and
  /// finite. The other sizes and widths are logical pixels, expected to be
  /// non-negative, and not validated.
  const DirectoryTreeThemeData({
    this.rowExtent,
    this.indentWidth,
    this.rowPadding,
    this.rowBorderRadius,
    this.expanderSize,
    this.iconSize,
    this.iconSpacing,
    this.guideStyle,
    this.guideColor,
    this.guideWidth,
    this.hoverColor,
    this.selectedColor,
    this.inactiveSelectedColor,
    this.focusedBorderColor,
    this.focusedBorderWidth,
    this.dropTargetColor,
    this.labelStyle,
    this.selectedLabelStyle,
    this.dimmedLabelStyle,
    this.matchHighlightStyle,
    this.iconColor,
    this.folderIconColor,
    this.iconSet,
    this.animationDuration,
    this.animationCurve,
  }) : assert(
         rowExtent == null || (rowExtent > 0 && rowExtent < double.infinity),
         'rowExtent must be positive and finite',
       );

  /// The defaults for [theme], with every field set.
  ///
  /// Colors come from the Material 3 roles of [ThemeData.colorScheme], the
  /// label style from [ThemeData.textTheme], and the row height from
  /// [ThemeData.visualDensity] and [ThemeData.materialTapTargetSize]; each
  /// field's documentation names its default. The row height here ignores
  /// the text scale, which only [DirectoryTreeTheme.of] knows.
  /// [DirectoryTreeTheme.of] starts from this value, so use it directly only
  /// when building a complete theme by hand.
  ///
  /// The result is cached per [ThemeData] instance: calling this again with
  /// the same theme returns the same object.
  factory DirectoryTreeThemeData.fallback(ThemeData theme) =>
      _fallbacks[theme] ??= _createFallback(theme);

  // ThemeData is immutable and Theme.of returns the same instance while the
  // app theme is unchanged, so the defaults are computed once per theme. The
  // Expando holds its keys weakly: dropping a theme drops its defaults.
  static final Expando<DirectoryTreeThemeData> _fallbacks =
      Expando<DirectoryTreeThemeData>('DirectoryTreeThemeData.fallback');

  static const double _baseRowExtent = 36;
  static const double _minRowExtent = 20;

  /// The row height from the visual density alone: 36 adjusted by
  /// [ThemeData.visualDensity], never below 20.
  static double _densityRowExtent(ThemeData theme) => math.max(
    _minRowExtent,
    _baseRowExtent + theme.visualDensity.baseSizeAdjustment.dy,
  );

  static DirectoryTreeThemeData _createFallback(ThemeData theme) {
    final scheme = theme.colorScheme;
    final label =
        theme.textTheme.bodyMedium ?? TextStyle(color: scheme.onSurface);
    return DirectoryTreeThemeData(
      rowExtent: math.max(
        _densityRowExtent(theme),
        // Material pads tap targets to 48 px on touch platforms.
        theme.materialTapTargetSize == MaterialTapTargetSize.padded
            ? kMinInteractiveDimension
            : 0.0,
      ),
      indentWidth: 16,
      rowPadding: const EdgeInsetsDirectional.only(start: 4, end: 8),
      rowBorderRadius: const BorderRadius.all(Radius.circular(4)),
      expanderSize: 20,
      iconSize: 18,
      iconSpacing: 6,
      guideStyle: DirectoryTreeGuideStyle.indent,
      guideColor: scheme.outlineVariant,
      guideWidth: 1,
      hoverColor: scheme.onSurface.withValues(alpha: 0.08),
      selectedColor: scheme.secondaryContainer,
      inactiveSelectedColor: scheme.surfaceContainerHighest,
      focusedBorderColor: scheme.primary,
      focusedBorderWidth: 1,
      dropTargetColor: scheme.primary.withValues(alpha: 0.12),
      labelStyle: label,
      selectedLabelStyle: _selectedLabel(label, scheme),
      dimmedLabelStyle: _dimmedLabel(label, scheme),
      matchHighlightStyle: TextStyle(
        fontWeight: FontWeight.w700,
        backgroundColor: scheme.tertiaryContainer,
        color: scheme.onTertiaryContainer,
      ),
      iconColor: scheme.onSurfaceVariant,
      folderIconColor: scheme.primary,
      iconSet: DirectoryTreeIconSet.material,
      animationDuration: const Duration(milliseconds: 150),
      animationCurve: Curves.easeOutCubic,
    );
  }

  // The default selected and dimmed label styles: the label style recolored
  // for the selection background and for search context rows.
  static TextStyle _selectedLabel(TextStyle label, ColorScheme scheme) =>
      label.copyWith(color: scheme.onSecondaryContainer);

  static TextStyle _dimmedLabel(TextStyle label, ColorScheme scheme) =>
      label.copyWith(color: scheme.onSurfaceVariant);

  /// The height of every row, in logical pixels.
  ///
  /// The tree view lays its rows out at this fixed extent. The default is
  /// 36 adjusted by [ThemeData.visualDensity]
  /// (`36 + VisualDensity.baseSizeAdjustment.dy`, so 28 for
  /// [VisualDensity.compact], the default density of desktop platforms),
  /// never less than 20, and at least [kMinInteractiveDimension] (48)
  /// while [ThemeData.materialTapTargetSize] is
  /// [MaterialTapTargetSize.padded] (the default on Android, iOS, and
  /// Fuchsia), so rows are comfortable touch targets.
  ///
  /// [DirectoryTreeTheme.of] also grows the default with the text scale
  /// ([MediaQuery.textScalerOf]): the row gains the height the scaled label
  /// line adds, so large text is never clipped. The height still stays
  /// fixed for a given text scale, which keeps scrolling O(1).
  ///
  /// The floors and the text scaling apply only to the default: an
  /// explicit value, from a theme extension or a [DirectoryTreeTheme], is
  /// used as given and must be positive and finite. Choose one that fits
  /// the label at the text scales the app supports.
  final double? rowExtent;

  /// The horizontal space each depth level adds, in logical pixels.
  ///
  /// A row at depth `d` is indented by `d * indentWidth`, and each level is
  /// one slot of [DirectoryTreeIndentGuides]. Defaults to 16.
  final double? indentWidth;

  /// The padding inside each row, around its indentation and content.
  ///
  /// Defaults to `EdgeInsetsDirectional.only(start: 4, end: 8)`, which
  /// mirrors in right-to-left text.
  final EdgeInsetsGeometry? rowPadding;

  /// The corner radius of row backgrounds (hover, selection, drop target)
  /// and of the focused row's border.
  ///
  /// Defaults to a circular radius of 4.
  final BorderRadiusGeometry? rowBorderRadius;

  /// The width and height of the expander area of a row, which shows the
  /// chevron, a progress indicator while children load, or an error icon
  /// after a failed load.
  ///
  /// Defaults to 20.
  final double? expanderSize;

  /// The size of row icons, in logical pixels. Defaults to 18.
  final double? iconSize;

  /// The gap between a row's icon and its label, in logical pixels.
  /// Defaults to 6.
  final double? iconSpacing;

  /// How [DirectoryTreeIndentGuides] draws the indentation.
  ///
  /// Defaults to [DirectoryTreeGuideStyle.indent].
  final DirectoryTreeGuideStyle? guideStyle;

  /// The color of indentation guide lines.
  ///
  /// Defaults to [ColorScheme.outlineVariant].
  final Color? guideColor;

  /// The stroke width of indentation guide lines, in logical pixels.
  ///
  /// 0 draws hairlines one physical pixel wide, as [Paint.strokeWidth] does.
  /// Defaults to 1.
  final double? guideWidth;

  /// The background of a row under a mouse pointer.
  ///
  /// Defaults to [ColorScheme.onSurface] at 8% opacity, the Material 3 hover
  /// state layer.
  final Color? hoverColor;

  /// The background of a selected row while the tree has keyboard focus.
  ///
  /// Defaults to [ColorScheme.secondaryContainer].
  final Color? selectedColor;

  /// The background of a selected row while the tree does not have keyboard
  /// focus, so the selection stays visible but recedes, as in desktop file
  /// explorers.
  ///
  /// Defaults to [ColorScheme.surfaceContainerHighest].
  final Color? inactiveSelectedColor;

  /// The color of the border around the focused row (the keyboard cursor)
  /// while the tree has keyboard focus.
  ///
  /// Defaults to [ColorScheme.primary].
  final Color? focusedBorderColor;

  /// The width of the focused row's border, in logical pixels. Defaults to 1.
  final double? focusedBorderWidth;

  /// The background of a row that would receive the current drag-and-drop.
  ///
  /// Defaults to [ColorScheme.primary] at 12% opacity.
  final Color? dropTargetColor;

  /// The text style of row labels.
  ///
  /// Defaults to [TextTheme.bodyMedium], or to plain
  /// [ColorScheme.onSurface] text when the text theme has none. When a theme
  /// sets this field, [DirectoryTreeTheme.of] also derives the default
  /// [selectedLabelStyle] and [dimmedLabelStyle] from it, so a new font size
  /// or family reaches every row state.
  final TextStyle? labelStyle;

  /// The text style of a selected row's label.
  ///
  /// Defaults to [labelStyle] in [ColorScheme.onSecondaryContainer], which
  /// reads on [selectedColor].
  final TextStyle? selectedLabelStyle;

  /// The text style of a label that is shown only because a descendant
  /// matches the search (its `TreeRow.isMatch` is false).
  ///
  /// Defaults to [labelStyle] in [ColorScheme.onSurfaceVariant].
  final TextStyle? dimmedLabelStyle;

  /// The style of the parts of a label that match the search.
  ///
  /// [DirectoryTreeLabel] applies it over the label style as a child span, so
  /// a style with `inherit: true` changes only what it sets. Defaults to bold
  /// (w700) [ColorScheme.onTertiaryContainer] text on
  /// [ColorScheme.tertiaryContainer].
  final TextStyle? matchHighlightStyle;

  /// The color of file icons. Defaults to [ColorScheme.onSurfaceVariant].
  final Color? iconColor;

  /// The color of directory icons. Defaults to [ColorScheme.primary].
  final Color? folderIconColor;

  /// The icons for files and directories; see [DirectoryTreeIconSet.iconFor].
  ///
  /// Defaults to [DirectoryTreeIconSet.material].
  final DirectoryTreeIconSet? iconSet;

  /// The duration of row animations: rows revealed by an expand fade and
  /// slide in, and chevrons rotate.
  ///
  /// [Duration.zero] turns the animations off. Defaults to 150 milliseconds.
  final Duration? animationDuration;

  /// The easing curve of row animations. Defaults to [Curves.easeOutCubic].
  final Curve? animationCurve;

  /// A copy of this theme in which the non-null fields of [other] replace
  /// these.
  ///
  /// Text styles combine with [TextStyle.merge]: a style of [other] with
  /// `inherit: true` overrides only the attributes it sets, and one with
  /// `inherit: false` replaces the style. Returns this theme when [other] is
  /// null.
  DirectoryTreeThemeData merge(DirectoryTreeThemeData? other) {
    if (other == null || identical(other, this)) return this;
    return copyWith(
      rowExtent: other.rowExtent,
      indentWidth: other.indentWidth,
      rowPadding: other.rowPadding,
      rowBorderRadius: other.rowBorderRadius,
      expanderSize: other.expanderSize,
      iconSize: other.iconSize,
      iconSpacing: other.iconSpacing,
      guideStyle: other.guideStyle,
      guideColor: other.guideColor,
      guideWidth: other.guideWidth,
      hoverColor: other.hoverColor,
      selectedColor: other.selectedColor,
      inactiveSelectedColor: other.inactiveSelectedColor,
      focusedBorderColor: other.focusedBorderColor,
      focusedBorderWidth: other.focusedBorderWidth,
      dropTargetColor: other.dropTargetColor,
      labelStyle: _mergeStyles(labelStyle, other.labelStyle),
      selectedLabelStyle: _mergeStyles(
        selectedLabelStyle,
        other.selectedLabelStyle,
      ),
      dimmedLabelStyle: _mergeStyles(dimmedLabelStyle, other.dimmedLabelStyle),
      matchHighlightStyle: _mergeStyles(
        matchHighlightStyle,
        other.matchHighlightStyle,
      ),
      iconColor: other.iconColor,
      folderIconColor: other.folderIconColor,
      iconSet: other.iconSet,
      animationDuration: other.animationDuration,
      animationCurve: other.animationCurve,
    );
  }

  static TextStyle? _mergeStyles(TextStyle? base, TextStyle? override) =>
      base == null ? override : base.merge(override);

  /// A copy of this theme with the given fields replaced.
  ///
  /// A null argument keeps the current value, so a field cannot be reset to
  /// null here; build a new [DirectoryTreeThemeData] for that.
  @override
  DirectoryTreeThemeData copyWith({
    double? rowExtent,
    double? indentWidth,
    EdgeInsetsGeometry? rowPadding,
    BorderRadiusGeometry? rowBorderRadius,
    double? expanderSize,
    double? iconSize,
    double? iconSpacing,
    DirectoryTreeGuideStyle? guideStyle,
    Color? guideColor,
    double? guideWidth,
    Color? hoverColor,
    Color? selectedColor,
    Color? inactiveSelectedColor,
    Color? focusedBorderColor,
    double? focusedBorderWidth,
    Color? dropTargetColor,
    TextStyle? labelStyle,
    TextStyle? selectedLabelStyle,
    TextStyle? dimmedLabelStyle,
    TextStyle? matchHighlightStyle,
    Color? iconColor,
    Color? folderIconColor,
    DirectoryTreeIconSet? iconSet,
    Duration? animationDuration,
    Curve? animationCurve,
  }) {
    return DirectoryTreeThemeData(
      rowExtent: rowExtent ?? this.rowExtent,
      indentWidth: indentWidth ?? this.indentWidth,
      rowPadding: rowPadding ?? this.rowPadding,
      rowBorderRadius: rowBorderRadius ?? this.rowBorderRadius,
      expanderSize: expanderSize ?? this.expanderSize,
      iconSize: iconSize ?? this.iconSize,
      iconSpacing: iconSpacing ?? this.iconSpacing,
      guideStyle: guideStyle ?? this.guideStyle,
      guideColor: guideColor ?? this.guideColor,
      guideWidth: guideWidth ?? this.guideWidth,
      hoverColor: hoverColor ?? this.hoverColor,
      selectedColor: selectedColor ?? this.selectedColor,
      inactiveSelectedColor:
          inactiveSelectedColor ?? this.inactiveSelectedColor,
      focusedBorderColor: focusedBorderColor ?? this.focusedBorderColor,
      focusedBorderWidth: focusedBorderWidth ?? this.focusedBorderWidth,
      dropTargetColor: dropTargetColor ?? this.dropTargetColor,
      labelStyle: labelStyle ?? this.labelStyle,
      selectedLabelStyle: selectedLabelStyle ?? this.selectedLabelStyle,
      dimmedLabelStyle: dimmedLabelStyle ?? this.dimmedLabelStyle,
      matchHighlightStyle: matchHighlightStyle ?? this.matchHighlightStyle,
      iconColor: iconColor ?? this.iconColor,
      folderIconColor: folderIconColor ?? this.folderIconColor,
      iconSet: iconSet ?? this.iconSet,
      animationDuration: animationDuration ?? this.animationDuration,
      animationCurve: animationCurve ?? this.animationCurve,
    );
  }

  /// The theme a fraction [t] of the way from this theme to [other].
  ///
  /// [ThemeData.lerp] calls this while the app theme animates. Sizes,
  /// colors, text styles, [rowPadding], and [rowBorderRadius] interpolate
  /// when both themes set them. Everything else switches from this theme's
  /// value to [other]'s at `t == 0.5`: [guideStyle], [iconSet],
  /// [animationDuration], [animationCurve], any field that only one theme
  /// sets (interpolating against a missing value would fade toward
  /// transparent or zero instead of toward the inherited default), and text
  /// styles that [TextStyle.lerp] cannot blend because their
  /// [TextStyle.inherit] values or their foreground or background paints
  /// differ. Returns this theme when [other] is null or `t == 0`, and [other]
  /// when `t == 1`, so the endpoints are exact even for text styles that set
  /// different attributes (which [TextStyle.lerp] alone would fade).
  @override
  DirectoryTreeThemeData lerp(DirectoryTreeThemeData? other, double t) {
    if (other == null || identical(other, this) || t == 0) return this;
    if (t == 1) return other;
    return DirectoryTreeThemeData(
      rowExtent: _lerpDouble(rowExtent, other.rowExtent, t),
      indentWidth: _lerpDouble(indentWidth, other.indentWidth, t),
      rowPadding: _lerpPadding(rowPadding, other.rowPadding, t),
      rowBorderRadius: _lerpRadius(rowBorderRadius, other.rowBorderRadius, t),
      expanderSize: _lerpDouble(expanderSize, other.expanderSize, t),
      iconSize: _lerpDouble(iconSize, other.iconSize, t),
      iconSpacing: _lerpDouble(iconSpacing, other.iconSpacing, t),
      guideStyle: t < 0.5 ? guideStyle : other.guideStyle,
      guideColor: _lerpColor(guideColor, other.guideColor, t),
      guideWidth: _lerpDouble(guideWidth, other.guideWidth, t),
      hoverColor: _lerpColor(hoverColor, other.hoverColor, t),
      selectedColor: _lerpColor(selectedColor, other.selectedColor, t),
      inactiveSelectedColor: _lerpColor(
        inactiveSelectedColor,
        other.inactiveSelectedColor,
        t,
      ),
      focusedBorderColor: _lerpColor(
        focusedBorderColor,
        other.focusedBorderColor,
        t,
      ),
      focusedBorderWidth: _lerpDouble(
        focusedBorderWidth,
        other.focusedBorderWidth,
        t,
      ),
      dropTargetColor: _lerpColor(dropTargetColor, other.dropTargetColor, t),
      labelStyle: _lerpStyle(labelStyle, other.labelStyle, t),
      selectedLabelStyle: _lerpStyle(
        selectedLabelStyle,
        other.selectedLabelStyle,
        t,
      ),
      dimmedLabelStyle: _lerpStyle(dimmedLabelStyle, other.dimmedLabelStyle, t),
      matchHighlightStyle: _lerpStyle(
        matchHighlightStyle,
        other.matchHighlightStyle,
        t,
      ),
      iconColor: _lerpColor(iconColor, other.iconColor, t),
      folderIconColor: _lerpColor(folderIconColor, other.folderIconColor, t),
      iconSet: t < 0.5 ? iconSet : other.iconSet,
      animationDuration: t < 0.5 ? animationDuration : other.animationDuration,
      animationCurve: t < 0.5 ? animationCurve : other.animationCurve,
    );
  }

  // Each helper interpolates only when both values exist. With one side
  // missing, Flutter's lerps would start from transparent or zero, which is
  // not what a missing field means here (it means "inherit the default"), so
  // the value switches at the midpoint instead.
  static double? _lerpDouble(double? a, double? b, double t) =>
      a == null || b == null ? (t < 0.5 ? a : b) : lerpDouble(a, b, t);

  static Color? _lerpColor(Color? a, Color? b, double t) =>
      a == null || b == null ? (t < 0.5 ? a : b) : Color.lerp(a, b, t);

  static EdgeInsetsGeometry? _lerpPadding(
    EdgeInsetsGeometry? a,
    EdgeInsetsGeometry? b,
    double t,
  ) => a == null || b == null
      ? (t < 0.5 ? a : b)
      : EdgeInsetsGeometry.lerp(a, b, t);

  static BorderRadiusGeometry? _lerpRadius(
    BorderRadiusGeometry? a,
    BorderRadiusGeometry? b,
    double t,
  ) => a == null || b == null
      ? (t < 0.5 ? a : b)
      : BorderRadiusGeometry.lerp(a, b, t);

  // TextStyle.lerp asserts when the inherit flags differ, and dereferences a
  // missing color when only one side paints with a Paint, so those pairs
  // switch instead of blending.
  static TextStyle? _lerpStyle(TextStyle? a, TextStyle? b, double t) {
    if (a == null ||
        b == null ||
        a.inherit != b.inherit ||
        (a.foreground == null) != (b.foreground == null) ||
        (a.background == null) != (b.background == null)) {
      return t < 0.5 ? a : b;
    }
    return TextStyle.lerp(a, b, t);
  }

  /// Whether [other] is a [DirectoryTreeThemeData] with equal values in
  /// every field.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is DirectoryTreeThemeData &&
        other.rowExtent == rowExtent &&
        other.indentWidth == indentWidth &&
        other.rowPadding == rowPadding &&
        other.rowBorderRadius == rowBorderRadius &&
        other.expanderSize == expanderSize &&
        other.iconSize == iconSize &&
        other.iconSpacing == iconSpacing &&
        other.guideStyle == guideStyle &&
        other.guideColor == guideColor &&
        other.guideWidth == guideWidth &&
        other.hoverColor == hoverColor &&
        other.selectedColor == selectedColor &&
        other.inactiveSelectedColor == inactiveSelectedColor &&
        other.focusedBorderColor == focusedBorderColor &&
        other.focusedBorderWidth == focusedBorderWidth &&
        other.dropTargetColor == dropTargetColor &&
        other.labelStyle == labelStyle &&
        other.selectedLabelStyle == selectedLabelStyle &&
        other.dimmedLabelStyle == dimmedLabelStyle &&
        other.matchHighlightStyle == matchHighlightStyle &&
        other.iconColor == iconColor &&
        other.folderIconColor == folderIconColor &&
        other.iconSet == iconSet &&
        other.animationDuration == animationDuration &&
        other.animationCurve == animationCurve;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    rowExtent,
    indentWidth,
    rowPadding,
    rowBorderRadius,
    expanderSize,
    iconSize,
    iconSpacing,
    guideStyle,
    guideColor,
    guideWidth,
    hoverColor,
    selectedColor,
    inactiveSelectedColor,
    focusedBorderColor,
    focusedBorderWidth,
    dropTargetColor,
    labelStyle,
    selectedLabelStyle,
    dimmedLabelStyle,
    matchHighlightStyle,
    iconColor,
    folderIconColor,
    iconSet,
    animationDuration,
    animationCurve,
  ]);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('rowExtent', rowExtent, defaultValue: null))
      ..add(DoubleProperty('indentWidth', indentWidth, defaultValue: null))
      ..add(
        DiagnosticsProperty<EdgeInsetsGeometry>(
          'rowPadding',
          rowPadding,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<BorderRadiusGeometry>(
          'rowBorderRadius',
          rowBorderRadius,
          defaultValue: null,
        ),
      )
      ..add(DoubleProperty('expanderSize', expanderSize, defaultValue: null))
      ..add(DoubleProperty('iconSize', iconSize, defaultValue: null))
      ..add(DoubleProperty('iconSpacing', iconSpacing, defaultValue: null))
      ..add(
        EnumProperty<DirectoryTreeGuideStyle>(
          'guideStyle',
          guideStyle,
          defaultValue: null,
        ),
      )
      ..add(ColorProperty('guideColor', guideColor, defaultValue: null))
      ..add(DoubleProperty('guideWidth', guideWidth, defaultValue: null))
      ..add(ColorProperty('hoverColor', hoverColor, defaultValue: null))
      ..add(ColorProperty('selectedColor', selectedColor, defaultValue: null))
      ..add(
        ColorProperty(
          'inactiveSelectedColor',
          inactiveSelectedColor,
          defaultValue: null,
        ),
      )
      ..add(
        ColorProperty(
          'focusedBorderColor',
          focusedBorderColor,
          defaultValue: null,
        ),
      )
      ..add(
        DoubleProperty(
          'focusedBorderWidth',
          focusedBorderWidth,
          defaultValue: null,
        ),
      )
      ..add(
        ColorProperty('dropTargetColor', dropTargetColor, defaultValue: null),
      )
      ..add(
        DiagnosticsProperty<TextStyle>(
          'labelStyle',
          labelStyle,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<TextStyle>(
          'selectedLabelStyle',
          selectedLabelStyle,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<TextStyle>(
          'dimmedLabelStyle',
          dimmedLabelStyle,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<TextStyle>(
          'matchHighlightStyle',
          matchHighlightStyle,
          defaultValue: null,
        ),
      )
      ..add(ColorProperty('iconColor', iconColor, defaultValue: null))
      ..add(
        ColorProperty('folderIconColor', folderIconColor, defaultValue: null),
      )
      ..add(
        DiagnosticsProperty<DirectoryTreeIconSet>(
          'iconSet',
          iconSet,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<Duration>(
          'animationDuration',
          animationDuration,
          defaultValue: null,
        ),
      )
      ..add(
        DiagnosticsProperty<Curve>(
          'animationCurve',
          animationCurve,
          defaultValue: null,
        ),
      );
  }
}

/// Overrides the [DirectoryTreeThemeData] of the directory tree widgets
/// below it.
///
/// The [data] applies on top of the app theme's [DirectoryTreeThemeData]
/// extension and of [DirectoryTreeThemeData.fallback]; only its non-null
/// fields change anything. Only the nearest [DirectoryTreeTheme] applies: an
/// outer one is not merged in. To build on an outer theme, merge into it,
/// for example `DirectoryTreeTheme.of(context).merge(...)`.
///
/// Widgets read the resolved values with [DirectoryTreeTheme.of].
class DirectoryTreeTheme extends InheritedTheme {
  /// Creates a theme override for [child] and its descendants.
  const DirectoryTreeTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// The values to apply below this widget; null fields inherit.
  final DirectoryTreeThemeData data;

  /// The resolved theme for widgets at [context], with every field set.
  ///
  /// Starts from [DirectoryTreeThemeData.fallback] for the ambient [Theme]
  /// (or the default [ThemeData] when there is none), then applies the
  /// theme's [DirectoryTreeThemeData] extension, then the [data] of the
  /// nearest [DirectoryTreeTheme], each with [DirectoryTreeThemeData.merge].
  /// When [DirectoryTreeThemeData.labelStyle] is set at either level, the
  /// selected and dimmed label styles that are not set explicitly derive
  /// from the resolved label style, so a custom label font applies to every
  /// row state.
  ///
  /// When neither level sets [DirectoryTreeThemeData.rowExtent], the
  /// default row height grows with the text scale of [MediaQuery]: the row
  /// gains what the scaled label line adds to the unscaled one (see
  /// [DirectoryTreeThemeData.rowExtent]).
  ///
  /// Registers a dependency on the [Theme], on the nearest
  /// [DirectoryTreeTheme], and (without an explicit row height) on the text
  /// scale of the nearest [MediaQuery], so the calling widget rebuilds when
  /// any of them changes. The result is cached: repeated calls under the
  /// same theme, data, and text scale return the same instance without
  /// allocating.
  static DirectoryTreeThemeData of(BuildContext context) {
    final theme = Theme.of(context);
    final local = context
        .dependOnInheritedWidgetOfExactType<DirectoryTreeTheme>()
        ?.data;
    final extension = theme.extension<DirectoryTreeThemeData>();
    final DirectoryTreeThemeData resolved;
    if (local == null) {
      resolved = _resolvedByTheme[theme] ??= _resolve(theme, extension);
    } else {
      final cached = _resolvedByData[local];
      if (cached != null && identical(cached.theme, theme)) {
        resolved = cached.data;
      } else {
        resolved = _resolve(theme, extension?.merge(local) ?? local);
        _resolvedByData[local] = (theme: theme, data: resolved);
      }
    }
    if (local?.rowExtent != null || extension?.rowExtent != null) {
      return resolved;
    }
    final scaler = MediaQuery.maybeTextScalerOf(context);
    if (scaler == null || scaler == TextScaler.noScaling) return resolved;
    return _scaled(theme, resolved, scaler);
  }

  // The default row height for a text scale, per resolved theme (one text
  // scale each: the common case is one per app). The Expando holds its keys
  // weakly.
  static final Expando<({TextScaler scaler, DirectoryTreeThemeData data})>
  _scaledByData = Expando<({TextScaler scaler, DirectoryTreeThemeData data})>(
    'DirectoryTreeTheme.of',
  );

  static DirectoryTreeThemeData _scaled(
    ThemeData theme,
    DirectoryTreeThemeData resolved,
    TextScaler scaler,
  ) {
    final cached = _scaledByData[resolved];
    if (cached != null && cached.scaler == scaler) return cached.data;
    // What the largest label line grows by; selected and dimmed labels may
    // use their own fonts.
    var growth = 0.0;
    for (final style in <TextStyle?>[
      resolved.labelStyle,
      resolved.selectedLabelStyle,
      resolved.dimmedLabelStyle,
    ]) {
      if (style == null) continue;
      growth = math.max(
        growth,
        _lineHeight(style, scaler) - _lineHeight(style, TextScaler.noScaling),
      );
    }
    final extent = math.max(
      resolved.rowExtent!,
      (DirectoryTreeThemeData._densityRowExtent(theme) + growth).ceilToDouble(),
    );
    final data = extent == resolved.rowExtent
        ? resolved
        : resolved.copyWith(rowExtent: extent);
    _scaledByData[resolved] = (scaler: scaler, data: data);
    return data;
  }

  /// The height of one line of [style] under [scaler].
  static double _lineHeight(TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    );
    final height = painter.preferredLineHeight;
    painter.dispose();
    return height;
  }

  // Rows call [of] on every build, so the resolved themes are cached by the
  // identity of the immutable inputs: per ThemeData without a local theme,
  // and per local data object (remembering the ThemeData it was resolved
  // against) otherwise. The Expandos hold their keys weakly.
  static final Expando<DirectoryTreeThemeData> _resolvedByTheme =
      Expando<DirectoryTreeThemeData>('DirectoryTreeTheme.of');
  static final Expando<({ThemeData theme, DirectoryTreeThemeData data})>
  _resolvedByData = Expando<({ThemeData theme, DirectoryTreeThemeData data})>(
    'DirectoryTreeTheme.of',
  );

  static DirectoryTreeThemeData _resolve(
    ThemeData theme,
    DirectoryTreeThemeData? overrides,
  ) {
    final fallback = DirectoryTreeThemeData.fallback(theme);
    if (overrides == null) return fallback;
    final merged = fallback.merge(overrides);
    if (overrides.labelStyle == null) return merged;
    // The default selected and dimmed styles were derived from the default
    // label style; derive them again from the customized one so a new font
    // size or family does not stop at unselected rows. Explicit selected and
    // dimmed styles still merge on top.
    final label = merged.labelStyle!;
    final scheme = theme.colorScheme;
    return merged.copyWith(
      selectedLabelStyle: DirectoryTreeThemeData._selectedLabel(
        label,
        scheme,
      ).merge(overrides.selectedLabelStyle),
      dimmedLabelStyle: DirectoryTreeThemeData._dimmedLabel(
        label,
        scheme,
      ).merge(overrides.dimmedLabelStyle),
    );
  }

  @override
  Widget wrap(BuildContext context, Widget child) =>
      DirectoryTreeTheme(data: data, child: child);

  @override
  bool updateShouldNotify(DirectoryTreeTheme oldWidget) =>
      data != oldWidget.data;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<DirectoryTreeThemeData>(
        'data',
        data,
        showName: false,
      ),
    );
  }
}
