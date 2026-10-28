import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_directory_tree/src/rendering/directory_tree_indent_guides.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_test/flutter_test.dart';

const Color _color = Color(0xFF336699);
const double _rowHeight = 30;

/// [guides] at the start of a row of height [_rowHeight], as a row lays them
/// out.
Widget _row(
  Widget guides, {
  TextDirection direction = TextDirection.ltr,
  DirectoryTreeThemeData? theme,
}) {
  Widget child = Directionality(
    textDirection: direction,
    child: Align(
      alignment: AlignmentDirectional.topStart,
      child: SizedBox(
        height: _rowHeight,
        child: Row(mainAxisSize: MainAxisSize.min, children: [guides]),
      ),
    ),
  );
  if (theme != null) child = DirectoryTreeTheme(data: theme, child: child);
  return child;
}

DirectoryTreeIndentGuides _guides({
  int depth = 3,
  List<bool> guides = const [true, true, false],
  bool isLast = false,
  DirectoryTreeGuideStyle? style = DirectoryTreeGuideStyle.connectors,
  double? indentWidth = 16,
  Color? color = _color,
  double? width = 1,
}) => DirectoryTreeIndentGuides(
  depth: depth,
  guides: guides,
  isLast: isLast,
  style: style,
  indentWidth: indentWidth,
  color: color,
  width: width,
);

Finder get _found => find.byType(DirectoryTreeIndentGuides);

CustomPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(
      find.descendant(of: _found, matching: find.byType(CustomPaint)),
    )
    .painter!;

void main() {
  group('indent style', () {
    testWidgets('draws a full-height line centered in every slot', (
      tester,
    ) async {
      await tester.pumpWidget(
        _row(_guides(style: DirectoryTreeGuideStyle.indent)),
      );
      expect(tester.getSize(_found), const Size(48, _rowHeight));
      expect(
        _found,
        paints
          ..line(
            p1: const Offset(8, 0),
            p2: const Offset(8, _rowHeight),
            color: _color,
            strokeWidth: 1,
          )
          ..line(p1: const Offset(24, 0), p2: const Offset(24, _rowHeight))
          ..line(p1: const Offset(40, 0), p2: const Offset(40, _rowHeight)),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 3));
    });

    testWidgets('ignores guides and isLast', (tester) async {
      await tester.pumpWidget(
        _row(
          _guides(
            style: DirectoryTreeGuideStyle.indent,
            guides: const [false, false, false],
            isLast: true,
          ),
        ),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 3));
    });

    testWidgets('mirrors in right-to-left text', (tester) async {
      await tester.pumpWidget(
        _row(
          _guides(style: DirectoryTreeGuideStyle.indent),
          direction: TextDirection.rtl,
        ),
      );
      expect(
        _found,
        paints
          ..line(p1: const Offset(40, 0), p2: const Offset(40, _rowHeight))
          ..line(p1: const Offset(24, 0), p2: const Offset(24, _rowHeight))
          ..line(p1: const Offset(8, 0), p2: const Offset(8, _rowHeight)),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 3));
    });
  });

  group('connectors style', () {
    testWidgets('draws ancestor lines from guides and an elbow into the row', (
      tester,
    ) async {
      await tester.pumpWidget(_row(_guides()));
      // Slot 0 continues (guides[1]); slot 1 does not (guides[2]); slot 2 is
      // the elbow of a row with later siblings.
      expect(
        _found,
        paints
          ..line(
            p1: const Offset(8, 0),
            p2: const Offset(8, _rowHeight),
            color: _color,
            strokeWidth: 1,
          )
          ..line(p1: const Offset(40, 0), p2: const Offset(40, _rowHeight))
          ..line(p1: const Offset(39.5, 15), p2: const Offset(48, 15)),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 3));
    });

    testWidgets('stops the elbow at the middle for the last sibling', (
      tester,
    ) async {
      await tester.pumpWidget(_row(_guides(isLast: true)));
      expect(
        _found,
        paints
          ..line(p1: const Offset(8, 0), p2: const Offset(8, _rowHeight))
          ..line(p1: const Offset(40, 0), p2: const Offset(40, 15))
          ..line(p1: const Offset(39.5, 15), p2: const Offset(48, 15)),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 3));
    });

    testWidgets('mirrors in right-to-left text', (tester) async {
      await tester.pumpWidget(
        _row(_guides(isLast: true), direction: TextDirection.rtl),
      );
      expect(
        _found,
        paints
          ..line(p1: const Offset(40, 0), p2: const Offset(40, _rowHeight))
          ..line(p1: const Offset(8, 0), p2: const Offset(8, 15))
          ..line(p1: const Offset(8.5, 15), p2: const Offset(0, 15)),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 3));

      await tester.pumpWidget(_row(_guides(), direction: TextDirection.rtl));
      expect(
        _found,
        paints
          ..line(p1: const Offset(40, 0), p2: const Offset(40, _rowHeight))
          ..line(p1: const Offset(8, 0), p2: const Offset(8, _rowHeight))
          ..line(p1: const Offset(8.5, 15), p2: const Offset(0, 15)),
      );
    });

    testWidgets('a top-level child has only its elbow', (tester) async {
      await tester.pumpWidget(_row(_guides(depth: 1, guides: const [true])));
      expect(tester.getSize(_found), const Size(16, _rowHeight));
      expect(
        _found,
        paints
          ..line(p1: const Offset(8, 0), p2: const Offset(8, _rowHeight))
          ..line(p1: const Offset(7.5, 15), p2: const Offset(16, 15)),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 2));
    });

    testWidgets('draws the connectors DirectoryTree.render prints', (
      tester,
    ) async {
      final tree = DirectoryTree.fromPaths([
        '/r/a/b/c/x.txt',
        '/r/a/b/c/y.txt',
        '/r/a/b/z.txt',
        '/r/a/q.txt',
        '/r/d/e/f.txt',
        '/r/d/e/g/h.txt',
        '/r/i.txt',
      ]);
      final rows = tree.flatten();
      final lines = tree.render().split('\n');
      expect(lines, hasLength(rows.length));
      const style = TreeStyle.unicode;
      var pipes = 0;
      var gaps = 0;

      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final line = lines[index];
        if (row.depth == 0) continue;
        await tester.pumpWidget(
          _row(
            _guides(depth: row.depth, guides: row.guides, isLast: row.isLast),
          ),
        );

        // Each 4-character column of the text prefix is one 16-pixel slot.
        final pattern = paints;
        var lineCount = 2;
        for (var slot = 0; slot < row.depth - 1; slot++) {
          final column = line.substring(slot * 4, slot * 4 + 4);
          if (column == style.pipe) {
            pipes++;
            lineCount++;
            final x = slot * 16 + 8.0;
            pattern.line(p1: Offset(x, 0), p2: Offset(x, _rowHeight));
          } else {
            gaps++;
            expect(column, style.gap, reason: line);
          }
        }
        final branch = line.substring((row.depth - 1) * 4, row.depth * 4);
        final x = (row.depth - 1) * 16 + 8.0;
        pattern
          ..line(
            p1: Offset(x, 0),
            p2: Offset(x, branch == style.lastBranch ? 15 : _rowHeight),
          )
          ..line(p1: Offset(x - 0.5, 15), p2: Offset(row.depth * 16.0, 15));
        expect(_found, pattern, reason: line);
        expect(
          _found,
          paintsExactlyCountTimes(#drawLine, lineCount),
          reason: line,
        );
      }
      // The tree exercises both continuing and ended ancestor lines.
      expect(pipes, greaterThan(0));
      expect(gaps, greaterThan(0));
    });

    testWidgets('treats missing guides as false and ignores extra ones', (
      tester,
    ) async {
      await tester.pumpWidget(_row(_guides(guides: const [])));
      expect(_found, paintsExactlyCountTimes(#drawLine, 2));

      await tester.pumpWidget(
        _row(_guides(depth: 1, guides: const [true, true, true, true])),
      );
      expect(_found, paintsExactlyCountTimes(#drawLine, 2));
    });
  });

  group('none style and depth 0', () {
    testWidgets('none keeps the indentation and draws nothing', (tester) async {
      await tester.pumpWidget(
        _row(_guides(style: DirectoryTreeGuideStyle.none)),
      );
      expect(tester.getSize(_found), const Size(48, _rowHeight));
      expect(_found, paintsNothing);
    });

    testWidgets('a top-level row takes no width and draws nothing', (
      tester,
    ) async {
      for (final style in DirectoryTreeGuideStyle.values) {
        await tester.pumpWidget(
          _row(_guides(depth: 0, guides: const [], style: style)),
        );
        expect(tester.getSize(_found), const Size(0, _rowHeight));
        expect(_found, paintsNothing);
      }
    });
  });

  group('theme', () {
    testWidgets('fills missing parameters from DirectoryTreeTheme.of', (
      tester,
    ) async {
      await tester.pumpWidget(
        _row(
          const DirectoryTreeIndentGuides(
            depth: 2,
            guides: [false, true],
            isLast: true,
          ),
          theme: const DirectoryTreeThemeData(
            guideStyle: DirectoryTreeGuideStyle.connectors,
            indentWidth: 20,
            guideColor: Color(0xFFFF0000),
            guideWidth: 2,
          ),
        ),
      );
      expect(tester.getSize(_found), const Size(40, _rowHeight));
      expect(
        _found,
        paints
          ..line(
            p1: const Offset(10, 0),
            p2: const Offset(10, _rowHeight),
            color: const Color(0xFFFF0000),
            strokeWidth: 2,
          )
          ..line(p1: const Offset(30, 0), p2: const Offset(30, 15))
          ..line(p1: const Offset(29, 15), p2: const Offset(40, 15)),
      );
    });

    testWidgets('defaults to indent guides in outlineVariant', (tester) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B)),
      );
      await tester.pumpWidget(
        Theme(
          data: theme,
          child: _row(
            const DirectoryTreeIndentGuides(
              depth: 2,
              guides: [false, false],
              isLast: true,
            ),
          ),
        ),
      );
      expect(tester.getSize(_found), const Size(32, _rowHeight));
      expect(
        _found,
        paints
          ..line(
            p1: const Offset(8, 0),
            p2: const Offset(8, _rowHeight),
            color: theme.colorScheme.outlineVariant,
            strokeWidth: 1,
          )
          ..line(p1: const Offset(24, 0), p2: const Offset(24, _rowHeight)),
      );
    });

    testWidgets('explicit parameters win over the theme', (tester) async {
      await tester.pumpWidget(
        _row(
          _guides(style: DirectoryTreeGuideStyle.indent, depth: 1),
          theme: const DirectoryTreeThemeData(
            guideStyle: DirectoryTreeGuideStyle.none,
            indentWidth: 40,
            guideColor: Color(0xFFFF0000),
            guideWidth: 5,
          ),
        ),
      );
      expect(tester.getSize(_found), const Size(16, _rowHeight));
      expect(
        _found,
        paints..line(
          p1: const Offset(8, 0),
          p2: const Offset(8, _rowHeight),
          color: _color,
          strokeWidth: 1,
        ),
      );
    });

    testWidgets('clamps negative theme sizes instead of failing', (
      tester,
    ) async {
      // The theme does not validate these (only rowExtent is asserted).
      await tester.pumpWidget(
        _row(
          const DirectoryTreeIndentGuides(
            depth: 2,
            guides: [true, true],
            isLast: false,
          ),
          theme: const DirectoryTreeThemeData(indentWidth: -4, guideWidth: -1),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_found), const Size(0, _rowHeight));
      expect(_found, paintsNothing);
    });
  });

  group('layout', () {
    testWidgets('uses the theme row extent when the height is unbounded', (
      tester,
    ) async {
      Widget unbounded(DirectoryTreeThemeData? theme) {
        Widget child = Directionality(
          textDirection: TextDirection.ltr,
          child: ListView(
            children: [
              Row(children: [_guides()]),
            ],
          ),
        );
        if (theme != null) {
          child = DirectoryTreeTheme(data: theme, child: child);
        }
        return child;
      }

      await tester.pumpWidget(unbounded(null));
      expect(tester.getSize(_found), const Size(48, 36));

      await tester.pumpWidget(
        unbounded(const DirectoryTreeThemeData(rowExtent: 44)),
      );
      expect(tester.getSize(_found), const Size(48, 44));
      expect(
        _found,
        paints..line(p1: const Offset(8, 0), p2: const Offset(8, 44)),
      );
    });

    testWidgets('fills a taller row', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 100,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [_guides(isLast: true)],
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(_found), const Size(48, 100));
      expect(
        _found,
        paints
          ..line(p1: const Offset(8, 0), p2: const Offset(8, 100))
          ..line(p1: const Offset(40, 0), p2: const Offset(40, 50))
          ..line(p1: const Offset(39.5, 50), p2: const Offset(48, 50)),
      );
    });

    test('rejects negative sizes in debug mode', () {
      expect(
        () => DirectoryTreeIndentGuides(
          depth: -1,
          guides: const [],
          isLast: false,
        ),
        throwsAssertionError,
      );
      expect(
        () => DirectoryTreeIndentGuides(
          depth: 1,
          guides: const [],
          isLast: false,
          indentWidth: -1,
        ),
        throwsAssertionError,
      );
      expect(
        () => DirectoryTreeIndentGuides(
          depth: 1,
          guides: const [],
          isLast: false,
          width: -1,
        ),
        throwsAssertionError,
      );
    });
  });

  group('repainting', () {
    testWidgets('an equal rebuild does not repaint', (tester) async {
      await tester.pumpWidget(_row(_guides()));
      final render = tester.renderObject<RenderCustomPaint>(
        find.descendant(of: _found, matching: find.byType(CustomPaint)),
      );
      expect(render.debugNeedsPaint, isFalse);

      // A new but equal guides list, as a rebuilt row passes.
      await tester.pumpWidget(
        _row(_guides(guides: [true, true, false])),
        phase: EnginePhase.layout,
      );
      expect(render.debugNeedsPaint, isFalse);
      await tester.pump();

      await tester.pumpWidget(
        _row(_guides(color: const Color(0xFF000000))),
        phase: EnginePhase.layout,
      );
      expect(render.debugNeedsPaint, isTrue);
      await tester.pump();
    });

    testWidgets('every input change asks for a repaint', (tester) async {
      await tester.pumpWidget(_row(_guides()));
      final base = _painter(tester);

      await tester.pumpWidget(_row(_guides(guides: [true, true, false])));
      expect(_painter(tester).shouldRepaint(base), isFalse);

      final variants = <String, Widget>{
        'depth': _row(_guides(depth: 2)),
        'guides': _row(_guides(guides: const [true, false, false])),
        'isLast': _row(_guides(isLast: true)),
        'style': _row(_guides(style: DirectoryTreeGuideStyle.indent)),
        'indentWidth': _row(_guides(indentWidth: 12)),
        'color': _row(_guides(color: const Color(0xFF000000))),
        'width': _row(_guides(width: 2)),
        'textDirection': _row(_guides(), direction: TextDirection.rtl),
        'theme value': _row(
          _guides(color: null),
          theme: const DirectoryTreeThemeData(guideColor: Color(0xFF000000)),
        ),
      };
      for (final MapEntry(key: input, value: widget) in variants.entries) {
        await tester.pumpWidget(widget);
        expect(_painter(tester).shouldRepaint(base), isTrue, reason: input);
      }
    });
  });

  testWidgets('describes its properties', (tester) async {
    final builder = DiagnosticPropertiesBuilder();
    _guides(isLast: true).debugFillProperties(builder);
    final description = builder.properties
        .where((p) => !p.isFiltered(DiagnosticLevel.info))
        .map((p) => p.toString())
        .toList();
    expect(
      description,
      containsAll(<String>[
        'depth: 3',
        'guides: true, true, false',
        'last',
        'style: connectors',
        'indentWidth: 16.0',
        'width: 1.0',
      ]),
    );
  });
}
