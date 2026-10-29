import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(Brightness brightness, {VisualDensity? density}) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF00796B),
    brightness: brightness,
  ),
  visualDensity: density ?? VisualDensity.standard,
  // Unpadded, so the row height follows the density alone; the touch
  // floor has its own tests.
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// [_theme] as `Theme.of` returns it in an app: with the English text
/// geometry merged into the text theme, which makes its styles complete.
ThemeData _localized(Brightness brightness) {
  final theme = _theme(brightness);
  return ThemeData.localize(
    theme,
    theme.typography.geometryThemeFor(ScriptCategory.englishLike),
  );
}

const DirectoryTreeIconSet _icons = DirectoryTreeIconSet(
  file: Icons.abc,
  folder: Icons.ac_unit,
  folderOpen: Icons.access_alarm,
  extensions: {'x': Icons.accessibility},
);

// Differs from every fallback value in every field.
const DirectoryTreeThemeData _custom = DirectoryTreeThemeData(
  rowExtent: 50,
  indentWidth: 30,
  rowPadding: EdgeInsets.all(2),
  rowBorderRadius: BorderRadius.all(Radius.circular(10)),
  expanderSize: 30,
  iconSize: 28,
  iconSpacing: 12,
  guideStyle: DirectoryTreeGuideStyle.connectors,
  guideColor: Color(0xFF000001),
  guideWidth: 3,
  hoverColor: Color(0xFF000002),
  selectedColor: Color(0xFF000003),
  inactiveSelectedColor: Color(0xFF000004),
  focusedBorderColor: Color(0xFF000005),
  focusedBorderWidth: 2,
  dropTargetColor: Color(0xFF000006),
  labelStyle: TextStyle(
    inherit: false,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: Color(0xFF000007),
  ),
  selectedLabelStyle: TextStyle(
    inherit: false,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: Color(0xFF000008),
  ),
  dimmedLabelStyle: TextStyle(
    inherit: false,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: Color(0xFF000009),
  ),
  matchHighlightStyle: TextStyle(
    fontWeight: FontWeight.w900,
    color: Color(0xFF00000A),
    backgroundColor: Color(0xFF00000B),
  ),
  iconColor: Color(0xFF00000C),
  folderIconColor: Color(0xFF00000D),
  iconSet: _icons,
  animationDuration: Duration(milliseconds: 400),
  animationCurve: Curves.linear,
);

const List<String> _fieldNames = [
  'rowExtent',
  'indentWidth',
  'rowPadding',
  'rowBorderRadius',
  'expanderSize',
  'iconSize',
  'iconSpacing',
  'guideStyle',
  'guideColor',
  'guideWidth',
  'hoverColor',
  'selectedColor',
  'inactiveSelectedColor',
  'focusedBorderColor',
  'focusedBorderWidth',
  'dropTargetColor',
  'labelStyle',
  'selectedLabelStyle',
  'dimmedLabelStyle',
  'matchHighlightStyle',
  'iconColor',
  'folderIconColor',
  'iconSet',
  'animationDuration',
  'animationCurve',
];

List<DiagnosticsNode> _properties(DirectoryTreeThemeData data) {
  final builder = DiagnosticPropertiesBuilder();
  data.debugFillProperties(builder);
  return builder.properties;
}

void _expectComplete(DirectoryTreeThemeData data) {
  final properties = _properties(data);
  expect(properties.map((p) => p.name), _fieldNames);
  for (final property in properties) {
    expect(property.value, isNotNull, reason: property.name);
  }
}

/// Pumps [child] under [theme] and returns the context of a widget below it.
Future<BuildContext> _contextUnder(
  WidgetTester tester, {
  ThemeData? theme,
  DirectoryTreeThemeData? local,
}) async {
  late BuildContext context;
  Widget child = Builder(
    builder: (c) {
      context = c;
      return const SizedBox();
    },
  );
  if (local != null) child = DirectoryTreeTheme(data: local, child: child);
  if (theme != null) child = Theme(data: theme, child: child);
  await tester.pumpWidget(child);
  return context;
}

void main() {
  group('DirectoryTreeThemeData.fallback', () {
    for (final brightness in Brightness.values) {
      test('derives every field from a ${brightness.name} Material 3 '
          'theme', () {
        final theme = _theme(brightness);
        final scheme = theme.colorScheme;
        final label = theme.textTheme.bodyMedium!;
        final data = DirectoryTreeThemeData.fallback(theme);

        expect(data.rowExtent, 36);
        expect(data.indentWidth, 16);
        expect(
          data.rowPadding,
          const EdgeInsetsDirectional.only(start: 4, end: 8),
        );
        expect(data.rowBorderRadius, BorderRadius.circular(4));
        expect(data.expanderSize, 20);
        expect(data.iconSize, 18);
        expect(data.iconSpacing, 6);
        expect(data.guideStyle, DirectoryTreeGuideStyle.indent);
        expect(data.guideColor, scheme.outlineVariant);
        expect(data.guideWidth, 1);
        expect(data.hoverColor, scheme.onSurface.withValues(alpha: 0.08));
        expect(data.selectedColor, scheme.secondaryContainer);
        expect(data.inactiveSelectedColor, scheme.surfaceContainerHighest);
        expect(data.focusedBorderColor, scheme.primary);
        expect(data.focusedBorderWidth, 1);
        expect(data.dropTargetColor, scheme.primary.withValues(alpha: 0.12));
        expect(data.labelStyle, label);
        expect(
          data.selectedLabelStyle,
          label.copyWith(color: scheme.onSecondaryContainer),
        );
        expect(
          data.dimmedLabelStyle,
          label.copyWith(color: scheme.onSurfaceVariant),
        );
        expect(
          data.matchHighlightStyle,
          TextStyle(
            fontWeight: FontWeight.w700,
            backgroundColor: scheme.tertiaryContainer,
            color: scheme.onTertiaryContainer,
          ),
        );
        expect(data.iconColor, scheme.onSurfaceVariant);
        expect(data.folderIconColor, scheme.primary);
        expect(data.iconSet, same(DirectoryTreeIconSet.material));
        expect(data.animationDuration, const Duration(milliseconds: 150));
        expect(data.animationCurve, Curves.easeOutCubic);
        _expectComplete(data);
      });
    }

    test('light and dark themes give different colors', () {
      final light = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      final dark = DirectoryTreeThemeData.fallback(_theme(Brightness.dark));
      expect(light.selectedColor, isNot(dark.selectedColor));
      expect(light.labelStyle!.color, isNot(dark.labelStyle!.color));
      expect(light.guideColor, isNot(dark.guideColor));
    });

    test('rowExtent is at least 48 while tap targets are padded', () {
      double extent(VisualDensity density) => DirectoryTreeThemeData.fallback(
        _theme(
          Brightness.light,
          density: density,
        ).copyWith(materialTapTargetSize: MaterialTapTargetSize.padded),
      ).rowExtent!;

      expect(extent(VisualDensity.standard), 48);
      expect(extent(VisualDensity.compact), 48);
      expect(
        extent(const VisualDensity(vertical: VisualDensity.maximumDensity)),
        52,
      );
    });

    test('rowExtent follows the vertical visual density, never below 20', () {
      double extent(VisualDensity density) => DirectoryTreeThemeData.fallback(
        _theme(Brightness.light, density: density),
      ).rowExtent!;

      expect(extent(VisualDensity.standard), 36);
      expect(extent(VisualDensity.comfortable), 32);
      expect(extent(VisualDensity.compact), 28);
      expect(
        extent(const VisualDensity(vertical: VisualDensity.minimumDensity)),
        20,
      );
      expect(
        extent(const VisualDensity(vertical: VisualDensity.maximumDensity)),
        52,
      );
      expect(
        extent(const VisualDensity(horizontal: VisualDensity.minimumDensity)),
        36,
      );
    });

    test('desktop platforms get compact rows by default', () {
      // ThemeData picks VisualDensity.defaultDensityForPlatform.
      expect(
        DirectoryTreeThemeData.fallback(
          ThemeData(platform: TargetPlatform.macOS),
        ).rowExtent,
        28,
      );
      expect(
        DirectoryTreeThemeData.fallback(
          ThemeData(platform: TargetPlatform.android),
        ).rowExtent,
        // Touch platforms pad tap targets to 48 px.
        48,
      );
    });

    test('asserts that an explicit rowExtent is positive and finite', () {
      // Not const: a const invocation would fail at compile time instead.
      for (final invalid in [0.0, -1.0, double.infinity, double.nan]) {
        expect(
          () => DirectoryTreeThemeData(rowExtent: invalid),
          throwsAssertionError,
          reason: '$invalid',
        );
        expect(
          () => const DirectoryTreeThemeData().copyWith(rowExtent: invalid),
          throwsAssertionError,
          reason: '$invalid',
        );
      }
      expect(DirectoryTreeThemeData(rowExtent: 0.5).rowExtent, 0.5);
      expect(DirectoryTreeThemeData(rowExtent: 16).rowExtent, 16);
    });

    test('is cached per ThemeData instance', () {
      final theme = _theme(Brightness.light);
      final first = DirectoryTreeThemeData.fallback(theme);
      expect(DirectoryTreeThemeData.fallback(theme), same(first));

      final copy = theme.copyWith();
      expect(DirectoryTreeThemeData.fallback(copy), isNot(same(first)));
      expect(DirectoryTreeThemeData.fallback(copy), first);
    });

    test('uses onSurface text when the text theme has no bodyMedium', () {
      final theme = _theme(Brightness.light)
          .copyWith(textTheme: const TextTheme());
      final scheme = theme.colorScheme;
      final data = DirectoryTreeThemeData.fallback(theme);

      expect(data.labelStyle, TextStyle(color: scheme.onSurface));
      expect(
        data.selectedLabelStyle,
        TextStyle(color: scheme.onSecondaryContainer),
      );
      expect(data.dimmedLabelStyle, TextStyle(color: scheme.onSurfaceVariant));
      _expectComplete(data);
    });
  });

  group('merge', () {
    test('returns the receiver for null', () {
      const data = DirectoryTreeThemeData(indentWidth: 10);
      expect(data.merge(null), same(data));
    });

    test('takes the non-null fields of the argument', () {
      final base = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      const override = DirectoryTreeThemeData(
        indentWidth: 24,
        guideStyle: DirectoryTreeGuideStyle.connectors,
        hoverColor: Color(0xFF123456),
        animationDuration: Duration.zero,
      );
      final merged = base.merge(override);

      expect(merged.indentWidth, 24);
      expect(merged.guideStyle, DirectoryTreeGuideStyle.connectors);
      expect(merged.hoverColor, const Color(0xFF123456));
      expect(merged.animationDuration, Duration.zero);
      // Everything else is the receiver's.
      expect(
        merged.copyWith(
          indentWidth: base.indentWidth,
          guideStyle: base.guideStyle,
          hoverColor: base.hoverColor,
          animationDuration: base.animationDuration,
        ),
        base,
      );
    });

    test('an argument that sets every field wins everywhere', () {
      final base = DirectoryTreeThemeData.fallback(_theme(Brightness.dark));
      final merged = base.merge(_custom);
      // The label styles of _custom do not inherit, so they replace; the
      // highlight style inherits and keeps nothing of the base because it
      // sets the same attributes.
      expect(merged, _custom);
    });

    test('an empty argument changes nothing', () {
      final base = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      expect(base.merge(const DirectoryTreeThemeData()), base);
      expect(const DirectoryTreeThemeData().merge(base), base);
    });

    test('text styles combine with TextStyle.merge', () {
      const base = DirectoryTreeThemeData(
        labelStyle: TextStyle(
          fontSize: 14,
          color: Color(0xFF000000),
          fontFamily: 'Roboto',
        ),
      );

      final partial = base.merge(
        const DirectoryTreeThemeData(labelStyle: TextStyle(fontSize: 20)),
      );
      expect(
        partial.labelStyle,
        const TextStyle(
          fontSize: 20,
          color: Color(0xFF000000),
          fontFamily: 'Roboto',
        ),
      );

      final complete = base.merge(
        const DirectoryTreeThemeData(
          labelStyle: TextStyle(inherit: false, fontSize: 12),
        ),
      );
      expect(
        complete.labelStyle,
        const TextStyle(inherit: false, fontSize: 12),
      );

      const highlight = TextStyle(fontSize: 3);
      expect(
        const DirectoryTreeThemeData()
            .merge(const DirectoryTreeThemeData(matchHighlightStyle: highlight))
            .matchHighlightStyle,
        highlight,
      );
    });
  });

  group('copyWith, ==, and hashCode', () {
    test('copyWith replaces each field and keeps the rest', () {
      final base = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      expect(base.copyWith(), base);

      final everything = base.copyWith(
        rowExtent: _custom.rowExtent,
        indentWidth: _custom.indentWidth,
        rowPadding: _custom.rowPadding,
        rowBorderRadius: _custom.rowBorderRadius,
        expanderSize: _custom.expanderSize,
        iconSize: _custom.iconSize,
        iconSpacing: _custom.iconSpacing,
        guideStyle: _custom.guideStyle,
        guideColor: _custom.guideColor,
        guideWidth: _custom.guideWidth,
        hoverColor: _custom.hoverColor,
        selectedColor: _custom.selectedColor,
        inactiveSelectedColor: _custom.inactiveSelectedColor,
        focusedBorderColor: _custom.focusedBorderColor,
        focusedBorderWidth: _custom.focusedBorderWidth,
        dropTargetColor: _custom.dropTargetColor,
        labelStyle: _custom.labelStyle,
        selectedLabelStyle: _custom.selectedLabelStyle,
        dimmedLabelStyle: _custom.dimmedLabelStyle,
        matchHighlightStyle: _custom.matchHighlightStyle,
        iconColor: _custom.iconColor,
        folderIconColor: _custom.folderIconColor,
        iconSet: _custom.iconSet,
        animationDuration: _custom.animationDuration,
        animationCurve: _custom.animationCurve,
      );
      expect(everything, _custom);
    });

    test('equal values are equal with equal hash codes', () {
      final a = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      final b = a.copyWith();
      expect(b, isNot(same(a)));
      expect(b, a);
      expect(b.hashCode, a.hashCode);
      expect(const DirectoryTreeThemeData(), const DirectoryTreeThemeData());
    });

    test('a difference in any one field breaks equality', () {
      final base = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      final variants = <String, DirectoryTreeThemeData>{
        'rowExtent': base.copyWith(rowExtent: _custom.rowExtent),
        'indentWidth': base.copyWith(indentWidth: _custom.indentWidth),
        'rowPadding': base.copyWith(rowPadding: _custom.rowPadding),
        'rowBorderRadius': base.copyWith(
          rowBorderRadius: _custom.rowBorderRadius,
        ),
        'expanderSize': base.copyWith(expanderSize: _custom.expanderSize),
        'iconSize': base.copyWith(iconSize: _custom.iconSize),
        'iconSpacing': base.copyWith(iconSpacing: _custom.iconSpacing),
        'guideStyle': base.copyWith(guideStyle: _custom.guideStyle),
        'guideColor': base.copyWith(guideColor: _custom.guideColor),
        'guideWidth': base.copyWith(guideWidth: _custom.guideWidth),
        'hoverColor': base.copyWith(hoverColor: _custom.hoverColor),
        'selectedColor': base.copyWith(selectedColor: _custom.selectedColor),
        'inactiveSelectedColor': base.copyWith(
          inactiveSelectedColor: _custom.inactiveSelectedColor,
        ),
        'focusedBorderColor': base.copyWith(
          focusedBorderColor: _custom.focusedBorderColor,
        ),
        'focusedBorderWidth': base.copyWith(
          focusedBorderWidth: _custom.focusedBorderWidth,
        ),
        'dropTargetColor': base.copyWith(
          dropTargetColor: _custom.dropTargetColor,
        ),
        'labelStyle': base.copyWith(labelStyle: _custom.labelStyle),
        'selectedLabelStyle': base.copyWith(
          selectedLabelStyle: _custom.selectedLabelStyle,
        ),
        'dimmedLabelStyle': base.copyWith(
          dimmedLabelStyle: _custom.dimmedLabelStyle,
        ),
        'matchHighlightStyle': base.copyWith(
          matchHighlightStyle: _custom.matchHighlightStyle,
        ),
        'iconColor': base.copyWith(iconColor: _custom.iconColor),
        'folderIconColor': base.copyWith(
          folderIconColor: _custom.folderIconColor,
        ),
        'iconSet': base.copyWith(iconSet: _custom.iconSet),
        'animationDuration': base.copyWith(
          animationDuration: _custom.animationDuration,
        ),
        'animationCurve': base.copyWith(animationCurve: _custom.animationCurve),
      };
      expect(variants.keys, _fieldNames);
      for (final MapEntry(key: field, value: variant) in variants.entries) {
        expect(variant, isNot(base), reason: field);
      }
    });

    test('debugFillProperties lists every field and hides unset ones', () {
      expect(_properties(_custom).map((p) => p.name), _fieldNames);
      final shown = _properties(const DirectoryTreeThemeData())
          .where((p) => !p.isFiltered(DiagnosticLevel.info));
      expect(shown, isEmpty);
    });
  });

  group('lerp', () {
    // Theme.of returns localized themes, whose text styles are complete
    // (inherit: false) like the label styles of _custom, so the two blend.
    final light = DirectoryTreeThemeData.fallback(_localized(Brightness.light));

    test('returns the receiver for null and for itself', () {
      expect(light.lerp(null, 0.5), same(light));
      expect(light.lerp(light, 0.5), same(light));
    });

    test('t = 0 and t = 1 give the endpoints exactly', () {
      expect(light.lerp(_custom, 0), same(light));
      expect(light.lerp(_custom, 1), same(_custom));
      final dark = DirectoryTreeThemeData.fallback(_localized(Brightness.dark));
      expect(light.lerp(dark, 0), same(light));
      expect(light.lerp(dark, 1), same(dark));

      // TextStyle.lerp alone would end with the raw label's decoration color
      // faded to transparent instead of the partial style.
      final raw = DirectoryTreeThemeData.fallback(_theme(Brightness.light));
      const partial = DirectoryTreeThemeData(
        labelStyle: TextStyle(fontSize: 20),
      );
      expect(raw.lerp(partial, 1), same(partial));
    });

    test('values close to the endpoints stay close to them', () {
      final dark = DirectoryTreeThemeData.fallback(_localized(Brightness.dark));
      final start = light.lerp(dark, 0.001);
      final end = light.lerp(dark, 0.999);
      expect(start.guideStyle, light.guideStyle);
      expect(end.guideStyle, dark.guideStyle);
      expect(start.labelStyle!.fontSize, light.labelStyle!.fontSize);
      expect(
        start.selectedColor!.r,
        moreOrLessEquals(light.selectedColor!.r, epsilon: 0.01),
      );
      expect(
        end.selectedColor!.r,
        moreOrLessEquals(dark.selectedColor!.r, epsilon: 0.01),
      );
    });

    test('the midpoint interpolates sizes, colors, styles, padding, and '
        'radius', () {
      final mid = light.lerp(_custom, 0.5);

      expect(mid.rowExtent, 43);
      expect(mid.indentWidth, 23);
      expect(mid.expanderSize, 25);
      expect(mid.iconSize, 23);
      expect(mid.iconSpacing, 9);
      expect(mid.guideWidth, 2);
      expect(mid.focusedBorderWidth, 1.5);
      expect(
        mid.rowPadding,
        EdgeInsetsGeometry.lerp(light.rowPadding, _custom.rowPadding, 0.5),
      );
      expect(
        mid.rowPadding!.resolve(TextDirection.ltr),
        const EdgeInsets.fromLTRB(3, 1, 5, 1),
      );
      expect(mid.rowBorderRadius, BorderRadius.circular(7));

      Color? half(Color? Function(DirectoryTreeThemeData) field) =>
          Color.lerp(field(light), field(_custom), 0.5);
      expect(mid.guideColor, half((d) => d.guideColor));
      expect(mid.hoverColor, half((d) => d.hoverColor));
      expect(mid.selectedColor, half((d) => d.selectedColor));
      expect(mid.inactiveSelectedColor, half((d) => d.inactiveSelectedColor));
      expect(mid.focusedBorderColor, half((d) => d.focusedBorderColor));
      expect(mid.dropTargetColor, half((d) => d.dropTargetColor));
      expect(mid.iconColor, half((d) => d.iconColor));
      expect(mid.folderIconColor, half((d) => d.folderIconColor));
      expect(mid.guideColor, isNot(light.guideColor));
      expect(mid.guideColor, isNot(_custom.guideColor));

      expect(
        mid.labelStyle,
        TextStyle.lerp(light.labelStyle, _custom.labelStyle, 0.5),
      );
      expect(mid.labelStyle!.fontSize, 17);
      expect(
        mid.selectedLabelStyle,
        TextStyle.lerp(
          light.selectedLabelStyle,
          _custom.selectedLabelStyle,
          0.5,
        ),
      );
      expect(
        mid.dimmedLabelStyle,
        TextStyle.lerp(light.dimmedLabelStyle, _custom.dimmedLabelStyle, 0.5),
      );
      expect(
        mid.matchHighlightStyle,
        TextStyle.lerp(
          light.matchHighlightStyle,
          _custom.matchHighlightStyle,
          0.5,
        ),
      );
    });

    test('the other fields switch at t = 0.5', () {
      final before = light.lerp(_custom, 0.49);
      final after = light.lerp(_custom, 0.5);

      expect(before.guideStyle, light.guideStyle);
      expect(after.guideStyle, _custom.guideStyle);
      expect(before.iconSet, light.iconSet);
      expect(after.iconSet, _custom.iconSet);
      expect(before.animationDuration, light.animationDuration);
      expect(after.animationDuration, _custom.animationDuration);
      expect(before.animationCurve, light.animationCurve);
      expect(after.animationCurve, _custom.animationCurve);
    });

    test('a field set on one side switches instead of fading', () {
      const set = DirectoryTreeThemeData(
        rowExtent: 40,
        rowPadding: EdgeInsets.all(3),
        rowBorderRadius: BorderRadius.zero,
        hoverColor: Color(0xFF112233),
        labelStyle: TextStyle(fontSize: 12),
      );
      const unset = DirectoryTreeThemeData();

      expect(set.lerp(unset, 0.25), set);
      expect(set.lerp(unset, 0.75), unset);
      expect(unset.lerp(set, 0.25), unset);
      expect(unset.lerp(set, 0.75), set);
    });

    test('text styles that TextStyle.lerp cannot blend switch at t = 0.5', () {
      const inheriting = DirectoryTreeThemeData(
        labelStyle: TextStyle(fontSize: 10),
      );
      const complete = DirectoryTreeThemeData(
        labelStyle: TextStyle(inherit: false, fontSize: 20),
      );
      expect(inheriting.lerp(complete, 0.25).labelStyle, inheriting.labelStyle);
      expect(inheriting.lerp(complete, 0.75).labelStyle, complete.labelStyle);

      final painted = DirectoryTreeThemeData(
        labelStyle: TextStyle(
          foreground: Paint()..color = const Color(0xFF00FF00),
        ),
        matchHighlightStyle: TextStyle(
          background: Paint()..color = const Color(0xFF0000FF),
        ),
      );
      // No color to build a Paint from: TextStyle.lerp would throw.
      const plain = DirectoryTreeThemeData(
        labelStyle: TextStyle(fontSize: 12),
        matchHighlightStyle: TextStyle(fontSize: 12),
      );
      expect(painted.lerp(plain, 0.25).labelStyle, painted.labelStyle);
      expect(painted.lerp(plain, 0.75).labelStyle, plain.labelStyle);
      expect(
        painted.lerp(plain, 0.25).matchHighlightStyle,
        painted.matchHighlightStyle,
      );
      expect(
        painted.lerp(plain, 0.75).matchHighlightStyle,
        plain.matchHighlightStyle,
      );
    });

    test('ThemeData.lerp interpolates the registered extension', () {
      final from = _theme(
        Brightness.light,
      ).copyWith(extensions: const [DirectoryTreeThemeData(indentWidth: 10)]);
      final to = _theme(
        Brightness.dark,
      ).copyWith(extensions: const [DirectoryTreeThemeData(indentWidth: 20)]);
      final mid = ThemeData.lerp(from, to, 0.5);
      expect(mid.extension<DirectoryTreeThemeData>()!.indentWidth, 15);
    });
  });

  group('DirectoryTreeTheme.of', () {
    testWidgets('is the fallback of the ambient theme without overrides', (
      tester,
    ) async {
      final context = await _contextUnder(
        tester,
        theme: _theme(Brightness.dark),
      );
      final resolved = DirectoryTreeTheme.of(context);
      expect(resolved, DirectoryTreeThemeData.fallback(Theme.of(context)));
      expect(
        resolved.selectedColor,
        _theme(Brightness.dark).colorScheme.secondaryContainer,
      );
      _expectComplete(resolved);
    });

    testWidgets('sets every field without a Theme ancestor', (tester) async {
      final context = await _contextUnder(tester);
      _expectComplete(DirectoryTreeTheme.of(context));
    });

    testWidgets('widget data beats the theme extension, which beats the '
        'fallback', (tester) async {
      final context = await _contextUnder(
        tester,
        theme: _theme(Brightness.light).copyWith(
          extensions: const [
            DirectoryTreeThemeData(
              indentWidth: 20,
              rowExtent: 40,
              guideColor: Color(0xFF00FF00),
              labelStyle: TextStyle(fontSize: 18),
            ),
          ],
        ),
        local: const DirectoryTreeThemeData(
          indentWidth: 24,
          hoverColor: Color(0xFF112233),
          guideColor: Color(0xFF0000FF),
          labelStyle: TextStyle(letterSpacing: 2),
        ),
      );
      final resolved = DirectoryTreeTheme.of(context);
      final fallback = DirectoryTreeThemeData.fallback(Theme.of(context));

      expect(resolved.indentWidth, 24);
      expect(resolved.guideColor, const Color(0xFF0000FF));
      expect(resolved.rowExtent, 40);
      expect(resolved.hoverColor, const Color(0xFF112233));
      expect(resolved.iconSize, fallback.iconSize);
      expect(resolved.selectedColor, fallback.selectedColor);
      expect(
        resolved.labelStyle,
        fallback.labelStyle!
            .merge(const TextStyle(fontSize: 18))
            .merge(const TextStyle(letterSpacing: 2)),
      );
      _expectComplete(resolved);
    });

    testWidgets('the extension alone applies over the fallback', (
      tester,
    ) async {
      final context = await _contextUnder(
        tester,
        theme: _theme(
          Brightness.light,
        ).copyWith(extensions: const [DirectoryTreeThemeData(indentWidth: 20)]),
      );
      final resolved = DirectoryTreeTheme.of(context);
      expect(resolved.indentWidth, 20);
      expect(
        resolved.copyWith(indentWidth: 16),
        DirectoryTreeThemeData.fallback(Theme.of(context)),
      );
    });

    testWidgets('an explicit rowExtent below the default floor is used as '
        'given', (tester) async {
      // The floor of 20 applies only to the density-derived default, so a
      // 1.x rowHeight of 16 carries over unchanged.
      final compact = _theme(Brightness.light, density: VisualDensity.compact);
      expect(DirectoryTreeThemeData.fallback(compact).rowExtent, 28);

      var context = await _contextUnder(
        tester,
        theme: compact.copyWith(
          extensions: const [DirectoryTreeThemeData(rowExtent: 16)],
        ),
      );
      expect(DirectoryTreeTheme.of(context).rowExtent, 16);

      context = await _contextUnder(
        tester,
        theme: compact,
        local: const DirectoryTreeThemeData(rowExtent: 16),
      );
      expect(DirectoryTreeTheme.of(context).rowExtent, 16);

      context = await _contextUnder(
        tester,
        theme: _theme(
          Brightness.light,
          density: const VisualDensity(vertical: VisualDensity.minimumDensity),
        ).copyWith(extensions: const [DirectoryTreeThemeData(rowExtent: 40)]),
        local: const DirectoryTreeThemeData(rowExtent: 12),
      );
      expect(DirectoryTreeTheme.of(context).rowExtent, 12);
    });

    testWidgets('only the nearest DirectoryTreeTheme applies', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        DirectoryTreeTheme(
          data: const DirectoryTreeThemeData(indentWidth: 10, iconSize: 30),
          child: DirectoryTreeTheme(
            data: const DirectoryTreeThemeData(indentWidth: 12),
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final resolved = DirectoryTreeTheme.of(context);
      expect(resolved.indentWidth, 12);
      expect(resolved.iconSize, 18);
    });

    testWidgets('a custom label style carries into the selected and dimmed '
        'styles', (tester) async {
      final context = await _contextUnder(
        tester,
        theme: _theme(Brightness.light),
        local: const DirectoryTreeThemeData(
          labelStyle: TextStyle(fontSize: 22, fontFamily: 'Mono'),
        ),
      );
      final scheme = Theme.of(context).colorScheme;
      final resolved = DirectoryTreeTheme.of(context);

      expect(resolved.labelStyle!.fontSize, 22);
      expect(resolved.labelStyle!.fontFamily, 'Mono');
      expect(resolved.labelStyle!.color, scheme.onSurface);
      expect(
        resolved.selectedLabelStyle,
        resolved.labelStyle!.copyWith(color: scheme.onSecondaryContainer),
      );
      expect(
        resolved.dimmedLabelStyle,
        resolved.labelStyle!.copyWith(color: scheme.onSurfaceVariant),
      );
    });

    testWidgets('explicit selected and dimmed styles apply over the derived '
        'ones', (tester) async {
      final context = await _contextUnder(
        tester,
        theme: _theme(Brightness.light).copyWith(
          extensions: const [
            DirectoryTreeThemeData(labelStyle: TextStyle(fontSize: 22)),
          ],
        ),
        local: const DirectoryTreeThemeData(
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
          dimmedLabelStyle: TextStyle(inherit: false, fontSize: 9),
        ),
      );
      final scheme = Theme.of(context).colorScheme;
      final resolved = DirectoryTreeTheme.of(context);

      expect(resolved.selectedLabelStyle!.fontSize, 22);
      expect(resolved.selectedLabelStyle!.fontWeight, FontWeight.w600);
      expect(resolved.selectedLabelStyle!.color, scheme.onSecondaryContainer);
      expect(
        resolved.dimmedLabelStyle,
        const TextStyle(inherit: false, fontSize: 9),
      );
    });

    testWidgets('without a custom label style, explicit selected and dimmed '
        'styles merge over the fallback ones', (tester) async {
      final context = await _contextUnder(
        tester,
        theme: _theme(Brightness.light),
        local: const DirectoryTreeThemeData(
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
        ),
      );
      final fallback = DirectoryTreeThemeData.fallback(Theme.of(context));
      final resolved = DirectoryTreeTheme.of(context);
      expect(
        resolved.selectedLabelStyle,
        fallback.selectedLabelStyle!.copyWith(fontWeight: FontWeight.w600),
      );
      expect(resolved.dimmedLabelStyle, fallback.dimmedLabelStyle);
    });

    testWidgets('returns the same instance until the theme or data changes', (
      tester,
    ) async {
      final theme = _theme(Brightness.light);
      var context = await _contextUnder(tester, theme: theme);
      final plain = DirectoryTreeTheme.of(context);
      expect(DirectoryTreeTheme.of(context), same(plain));

      const local = DirectoryTreeThemeData(indentWidth: 30);
      context = await _contextUnder(tester, theme: theme, local: local);
      final withLocal = DirectoryTreeTheme.of(context);
      expect(withLocal.indentWidth, 30);
      expect(DirectoryTreeTheme.of(context), same(withLocal));

      // The same local data under another theme resolves against that theme.
      context = await _contextUnder(
        tester,
        theme: _theme(Brightness.dark),
        local: local,
      );
      final dark = DirectoryTreeTheme.of(context);
      expect(dark, isNot(same(withLocal)));
      expect(dark.indentWidth, 30);
      expect(
        dark.selectedColor,
        _theme(Brightness.dark).colorScheme.secondaryContainer,
      );
    });

    testWidgets('dependents rebuild when the data changes, not when an equal '
        'value replaces it', (tester) async {
      var builds = 0;
      late DirectoryTreeThemeData seen;
      final child = Builder(
        builder: (context) {
          builds++;
          seen = DirectoryTreeTheme.of(context);
          return const SizedBox();
        },
      );

      await tester.pumpWidget(
        DirectoryTreeTheme(
          data: const DirectoryTreeThemeData(indentWidth: 10),
          child: child,
        ),
      );
      expect(builds, 1);

      await tester.pumpWidget(
        DirectoryTreeTheme(
          // Not const: an equal but distinct value.
          data: DirectoryTreeThemeData(indentWidth: 10),
          child: child,
        ),
      );
      expect(builds, 1);

      await tester.pumpWidget(
        DirectoryTreeTheme(
          data: const DirectoryTreeThemeData(indentWidth: 11),
          child: child,
        ),
      );
      expect(builds, 2);
      expect(seen.indentWidth, 11);
    });

    testWidgets('InheritedTheme.capture carries the theme to another '
        'subtree', (tester) async {
      late CapturedThemes captured;
      await tester.pumpWidget(
        DirectoryTreeTheme(
          data: const DirectoryTreeThemeData(indentWidth: 30),
          child: Builder(
            builder: (context) {
              captured = InheritedTheme.capture(from: context, to: null);
              return const SizedBox();
            },
          ),
        ),
      );

      late DirectoryTreeThemeData seen;
      await tester.pumpWidget(
        captured.wrap(
          Builder(
            builder: (context) {
              seen = DirectoryTreeTheme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen.indentWidth, 30);
    });

    testWidgets('describes its data', (tester) async {
      const theme = DirectoryTreeTheme(
        data: DirectoryTreeThemeData(indentWidth: 30),
        child: SizedBox(),
      );
      expect(theme.toStringDeep(), contains('indentWidth: 30.0'));
    });
  });

  group('default rowExtent for large text and touch', () {
    // The tallest label line in the rows of a default tree under [scaler].
    Future<({double row, double text})> measure(
      WidgetTester tester, {
      required TextScaler scaler,
      ThemeData? theme,
      DirectoryTreeThemeData data = const DirectoryTreeThemeData(),
    }) async {
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree<Object?>.build(const [
          TreeEntry<Object?>.file('/r/a.txt'),
          TreeEntry<Object?>.directory('/r/b'),
        ]),
        expansion: const ExpansionState.expanded(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view)
              .copyWith(textScaler: scaler),
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: DirectoryTreeTheme(
                data: data,
                child: CustomScrollView(
                  slivers: [
                    SliverDirectoryTree<Object?>(controller: controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final row = tester.getSize(find.byType(DirectoryTreeRow<Object?>).first);
      var text = 0.0;
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(
          of: find.byType(DirectoryTreeLabel),
          matching: find.byType(RichText),
        ),
      )) {
        text = math.max(text, paragraph.getMaxIntrinsicHeight(double.infinity));
      }
      return (row: row.height, text: text);
    }

    testWidgets('grows with the text scale so labels fit', (tester) async {
      for (final factor in [1.0, 1.5, 2.0, 3.0]) {
        final size = await measure(
          tester,
          scaler: TextScaler.linear(factor),
          theme: ThemeData(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
        expect(
          size.row,
          greaterThanOrEqualTo(size.text + 8),
          reason: '$factor',
        );
        if (factor == 1.0) expect(size.row, 36);
      }
      // Compact desktop rows too.
      final compact = await measure(
        tester,
        scaler: const TextScaler.linear(2),
        theme: ThemeData(visualDensity: VisualDensity.compact),
      );
      expect(compact.row, greaterThanOrEqualTo(compact.text + 4));
    });

    testWidgets('an explicit rowExtent stays as given', (tester) async {
      final size = await measure(
        tester,
        scaler: const TextScaler.linear(2),
        data: const DirectoryTreeThemeData(rowExtent: 30),
      );
      expect(size.row, 30);
    });

    testWidgets('of() resolves the scaled extent once per text scale', (
      tester,
    ) async {
      late BuildContext context;
      Widget app(double factor) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(factor)),
        child: Theme(
          data: ThemeData(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(app(1));
      final normal = DirectoryTreeTheme.of(context);
      await tester.pumpWidget(app(2));
      final large = DirectoryTreeTheme.of(context);
      expect(large.rowExtent, greaterThan(normal.rowExtent!));
      expect(DirectoryTreeTheme.of(context), same(large));
      expect(large.copyWith(rowExtent: normal.rowExtent), normal);
    });

    testWidgets('touch platforms get 48 px rows; desktops stay compact', (
      tester,
    ) async {
      final size = await measure(tester, scaler: TextScaler.noScaling);
      final touch =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.fuchsia;
      expect(size.row, touch ? 48 : 28);
    }, variant: TargetPlatformVariant.all());

    testWidgets(
      'a default tree meets the tap target and contrast guidelines',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final loader = PendingTestLoader();
        final controller = DirectoryTreeController<Object?>(
          tree: DirectoryTree<Object?>.build(const [
            TreeEntry<Object?>.directory('/r/lazy'),
            TreeEntry<Object?>.file('/r/a/b.txt'),
            TreeEntry<Object?>.file('/r/c.txt'),
          ]),
          expansion: const ExpansionState.expanded(),
          loadChildren: loader.call,
        )..select(const NodeId('/r/c.txt'));
        addTearDown(controller.dispose);
        for (final mode in DirectoryTreeCheckboxMode.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CustomScrollView(
                  slivers: [
                    // Rows that touch the edges of the scroll view are
                    // skipped by the tap target guidelines.
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverDirectoryTree<Object?>(
                        controller: controller,
                        checkboxMode: mode,
                        onActivate: (_) {},
                        onRowSecondaryTap: (_, _) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        semantics.dispose();
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  });
}

/// A loader whose loads never finish.
final class PendingTestLoader {
  Future<Iterable<TreeEntry<Object?>>> call(DirectoryNode<Object?> directory) =>
      Completer<Iterable<TreeEntry<Object?>>>().future;
}
