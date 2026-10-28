import 'dart:math';

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_directory_tree/src/rendering/directory_tree_label.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Range = ({int start, int end});

/// A span of the built label: its text and whether it is highlighted.
typedef _Span = (String text, bool highlighted);

const TextStyle _base = TextStyle(fontSize: 13);
const TextStyle _highlight = TextStyle(fontWeight: FontWeight.w900);

Widget _host(Widget child, {ThemeData? theme}) => Theme(
  data: theme ?? ThemeData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Finder get _richText => find.descendant(
  of: find.byType(DirectoryTreeLabel),
  matching: find.byType(RichText),
);

/// The span that DirectoryTreeLabel passed to Text.rich.
TextSpan _labelSpan(WidgetTester tester) {
  // Text.rich wraps the given span in a root span that holds the style.
  final root = tester.widget<RichText>(_richText).text as TextSpan;
  return root.children!.single as TextSpan;
}

List<_Span> _spans(WidgetTester tester, {TextStyle highlight = _highlight}) {
  final spans = <_Span>[];
  _labelSpan(tester).visitChildren((span) {
    final text = span as TextSpan;
    if (text.style != null) expect(text.style, highlight);
    spans.add((text.text!, text.style != null));
    return true;
  });
  return spans;
}

Future<List<_Span>> _label(
  WidgetTester tester,
  String text,
  List<_Range> ranges, {
  EnginePhase phase = EnginePhase.sendSemanticsUpdate,
}) async {
  await tester.pumpWidget(
    _host(
      DirectoryTreeLabel(
        text: text,
        matchRanges: ranges,
        style: _base,
        highlightStyle: _highlight,
      ),
    ),
    phase: phase,
  );
  return _spans(tester);
}

bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

/// Which code units of [text] [ranges] highlight, computed one unit at a
/// time: units inside a valid range after clamping, widened to whole
/// surrogate pairs.
List<bool> _expectedHighlight(String text, List<_Range> ranges) {
  final marks = List<bool>.filled(text.length, false);
  for (final range in ranges) {
    if (range.start >= range.end) continue;
    final end = min(text.length, range.end);
    for (var i = max(0, range.start); i < end; i++) {
      marks[i] = true;
    }
  }
  for (var i = 0; i + 1 < text.length; i++) {
    final pair = _isHigh(text.codeUnitAt(i)) && _isLow(text.codeUnitAt(i + 1));
    if (pair && (marks[i] || marks[i + 1])) {
      marks[i] = true;
      marks[i + 1] = true;
    }
  }
  return marks;
}

void main() {
  group('spans', () {
    testWidgets('without ranges the text is one plain span', (tester) async {
      expect(await _label(tester, 'main.dart', []), [('main.dart', false)]);
    });

    testWidgets('one range splits the text around it', (tester) async {
      expect(await _label(tester, 'main.dart', [(start: 0, end: 4)]), [
        ('main', true),
        ('.dart', false),
      ]);
      expect(await _label(tester, 'main.dart', [(start: 5, end: 9)]), [
        ('main.', false),
        ('dart', true),
      ]);
      expect(await _label(tester, 'main.dart', [(start: 0, end: 9)]), [
        ('main.dart', true),
      ]);
    });

    testWidgets('overlapping ranges merge', (tester) async {
      expect(
        await _label(tester, 'abcdef', [
          (start: 1, end: 3),
          (start: 2, end: 5),
        ]),
        [('a', false), ('bcde', true), ('f', false)],
      );
      expect(
        await _label(tester, 'abcdef', [
          (start: 0, end: 6),
          (start: 2, end: 3),
        ]),
        [('abcdef', true)],
      );
    });

    testWidgets('touching ranges merge', (tester) async {
      expect(
        await _label(tester, 'abcdef', [
          (start: 0, end: 2),
          (start: 2, end: 4),
        ]),
        [('abcd', true), ('ef', false)],
      );
    });

    testWidgets('unsorted ranges are sorted', (tester) async {
      expect(
        await _label(tester, 'abcdef', [
          (start: 4, end: 5),
          (start: 0, end: 1),
          (start: 2, end: 3),
        ]),
        [
          ('a', true),
          ('b', false),
          ('c', true),
          ('d', false),
          ('e', true),
          ('f', false),
        ],
      );
    });

    testWidgets('out-of-range ranges are clamped to the text', (tester) async {
      expect(
        await _label(tester, 'abcdef', [
          (start: -3, end: 2),
          (start: 4, end: 99),
        ]),
        [('ab', true), ('cd', false), ('ef', true)],
      );
      expect(
        await _label(tester, 'abcdef', [
          (start: 10, end: 20),
          (start: -5, end: -1),
          (start: 6, end: 7),
        ]),
        [('abcdef', false)],
      );
    });

    testWidgets('empty and reversed ranges are ignored', (tester) async {
      expect(
        await _label(tester, 'abcdef', [
          (start: 2, end: 2),
          (start: 4, end: 1),
        ]),
        [('abcdef', false)],
      );
      expect(
        await _label(tester, 'abcdef', [
          (start: 3, end: 3),
          (start: 1, end: 2),
          (start: 5, end: 0),
        ]),
        [('a', false), ('b', true), ('cdef', false)],
      );
    });

    testWidgets('empty text gives one empty span', (tester) async {
      expect(await _label(tester, '', [(start: 0, end: 1)]), [('', false)]);
    });

    testWidgets('a range never splits a surrogate pair', (tester) async {
      // 'a', U+1F600 as two code units (1 and 2), 'b'.
      const text = 'a\u{1F600}b';
      expect(text.length, 4);
      // Starts inside the pair.
      expect(await _label(tester, text, [(start: 2, end: 4)]), [
        ('a', false),
        ('\u{1F600}b', true),
      ]);
      // Ends inside the pair.
      expect(await _label(tester, text, [(start: 0, end: 2)]), [
        ('a\u{1F600}', true),
        ('b', false),
      ]);
      // Covers only the high or only the low half.
      for (final range in [(start: 1, end: 2), (start: 2, end: 3)]) {
        expect(await _label(tester, text, [range]), [
          ('a', false),
          ('\u{1F600}', true),
          ('b', false),
        ]);
      }
      // Starts and ends inside two neighboring pairs.
      expect(await _label(tester, '\u{1F600}\u{1F600}', [(start: 1, end: 3)]), [
        ('\u{1F600}\u{1F600}', true),
      ]);
    });

    testWidgets('highlights what TreeQuery.matchRanges finds', (tester) async {
      const text = 'Main_Test.dart';
      final ranges = TreeQuery.parse('ma t').matchRanges(text);
      expect(ranges, isNotEmpty);
      final spans = await _label(tester, text, ranges);
      expect(spans.map((span) => span.$1).join(), text);
      expect(
        [
          for (final (part, highlighted) in spans)
            if (highlighted) part,
        ],
        [for (final range in ranges) text.substring(range.start, range.end)],
      );
    });

    testWidgets('any ranges cover the text in order, alternate, and keep '
        'surrogate pairs whole', (tester) async {
      final random = Random(20261028);
      // Includes surrogate pairs and lone surrogates.
      const pieces = ['a', 'B', '.', '_', 'é', '\u{1F600}', '\u{10437}'];
      const lone = ['\uD800', '\uDC00'];
      for (var iteration = 0; iteration < 300; iteration++) {
        final buffer = StringBuffer();
        final count = random.nextInt(9);
        for (var i = 0; i < count; i++) {
          buffer.write(
            random.nextInt(8) == 0
                ? lone[random.nextInt(lone.length)]
                : pieces[random.nextInt(pieces.length)],
          );
        }
        final text = buffer.toString();
        final ranges = [
          for (var i = random.nextInt(5); i > 0; i--)
            (
              start: random.nextInt(text.length + 7) - 3,
              end: random.nextInt(text.length + 7) - 3,
            ),
        ];
        final reason = 'text ${text.codeUnits}, ranges $ranges';

        // Stop after building: lone surrogates never reach text shaping.
        final spans = await _label(
          tester,
          text,
          ranges,
          phase: EnginePhase.build,
        );

        expect(spans.map((span) => span.$1).join(), text, reason: reason);
        if (text.isEmpty) {
          expect(spans, [('', false)], reason: reason);
          continue;
        }
        final highlighted = <bool>[];
        var boundary = 0;
        for (var i = 0; i < spans.length; i++) {
          final (part, isHighlighted) = spans[i];
          expect(part, isNotEmpty, reason: reason);
          if (i > 0) {
            // Merged ranges leave no two neighboring spans alike.
            expect(isHighlighted, isNot(spans[i - 1].$2), reason: reason);
            final splitsPair =
                _isHigh(text.codeUnitAt(boundary - 1)) &&
                _isLow(text.codeUnitAt(boundary));
            expect(splitsPair, isFalse, reason: reason);
          }
          highlighted.addAll(List<bool>.filled(part.length, isHighlighted));
          boundary += part.length;
        }
        expect(highlighted, _expectedHighlight(text, ranges), reason: reason);
      }
    });
  });

  group('styles and layout', () {
    testWidgets('uses the theme label and highlight styles by default', (
      tester,
    ) async {
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B)),
      );
      await tester.pumpWidget(
        _host(
          const DirectoryTreeLabel(
            text: 'main.dart',
            matchRanges: [(start: 0, end: 4)],
          ),
          theme: theme,
        ),
      );
      final resolved = DirectoryTreeTheme.of(
        tester.element(find.byType(DirectoryTreeLabel)),
      );
      final root = tester.widget<RichText>(_richText).text as TextSpan;
      expect(root.style, resolved.labelStyle);
      expect(_spans(tester, highlight: resolved.matchHighlightStyle!), [
        ('main', true),
        ('.dart', false),
      ]);
    });

    testWidgets('follows a DirectoryTreeTheme', (tester) async {
      const highlight = TextStyle(color: Color(0xFFFF0000));
      await tester.pumpWidget(
        _host(
          const DirectoryTreeTheme(
            data: DirectoryTreeThemeData(
              labelStyle: TextStyle(inherit: false, fontSize: 21),
              matchHighlightStyle: highlight,
            ),
            child: DirectoryTreeLabel(
              text: 'main.dart',
              matchRanges: [(start: 0, end: 4)],
            ),
          ),
        ),
      );
      final root = tester.widget<RichText>(_richText).text as TextSpan;
      expect(root.style!.fontSize, 21);
      final resolved = DirectoryTreeTheme.of(
        tester.element(find.byType(DirectoryTreeLabel)),
      );
      expect(_spans(tester, highlight: resolved.matchHighlightStyle!), [
        ('main', true),
        ('.dart', false),
      ]);
      expect(resolved.matchHighlightStyle!.color, const Color(0xFFFF0000));
    });

    testWidgets('explicit styles win over the theme', (tester) async {
      await tester.pumpWidget(
        _host(
          const DirectoryTreeTheme(
            data: DirectoryTreeThemeData(
              labelStyle: TextStyle(inherit: false, fontSize: 21),
              matchHighlightStyle: TextStyle(color: Color(0xFFFF0000)),
            ),
            child: DirectoryTreeLabel(
              text: 'main.dart',
              matchRanges: [(start: 0, end: 4)],
              style: _base,
              highlightStyle: _highlight,
            ),
          ),
        ),
      );
      final root = tester.widget<RichText>(_richText).text as TextSpan;
      expect(root.style, _base);
      expect(_spans(tester), [('main', true), ('.dart', false)]);
    });

    testWidgets('defaults to one line with an ellipsis', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 60,
                child: DirectoryTreeLabel(
                  text: 'a_really_long_file_name_that_does_not_fit.dart',
                  style: TextStyle(fontSize: 10),
                ),
              ),
              // A one-line reference, so the check does not depend on font
              // metrics.
              DirectoryTreeLabel(text: 'a', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
      final rich = tester.widget<RichText>(_richText.first);
      expect(rich.maxLines, 1);
      expect(rich.overflow, TextOverflow.ellipsis);
      final long = tester.renderObject<RenderParagraph>(_richText.first);
      final short = tester.renderObject<RenderParagraph>(_richText.last);
      expect(long.didExceedMaxLines, isTrue);
      expect(short.didExceedMaxLines, isFalse);
      expect(long.size.height, short.size.height);
    });

    testWidgets('passes maxLines and overflow through', (tester) async {
      await tester.pumpWidget(
        _host(
          const DirectoryTreeLabel(
            text: 'main.dart',
            maxLines: 2,
            overflow: TextOverflow.fade,
          ),
        ),
      );
      var rich = tester.widget<RichText>(_richText);
      expect(rich.maxLines, 2);
      expect(rich.overflow, TextOverflow.fade);

      await tester.pumpWidget(
        _host(const DirectoryTreeLabel(text: 'main.dart', maxLines: null)),
      );
      rich = tester.widget<RichText>(_richText);
      expect(rich.maxLines, isNull);
    });

    testWidgets('reads as its whole text to accessibility', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const DirectoryTreeLabel(
            text: 'main.dart',
            matchRanges: [(start: 1, end: 3)],
          ),
        ),
      );
      expect(find.bySemanticsLabel('main.dart'), findsOneWidget);
      semantics.dispose();
    });

    test('describes its properties', () {
      final builder = DiagnosticPropertiesBuilder();
      const DirectoryTreeLabel(
        text: 'main.dart',
        matchRanges: [(start: 0, end: 4)],
        maxLines: 2,
      ).debugFillProperties(builder);
      final description = builder.properties
          .where((p) => !p.isFiltered(DiagnosticLevel.info))
          .map((p) => p.toString())
          .toList();
      expect(description, contains('text: "main.dart"'));
      expect(description, contains('maxLines: 2'));
      expect(
        description.any((line) => line.startsWith('matchRanges: ')),
        isTrue,
      );
    });
  });
}
