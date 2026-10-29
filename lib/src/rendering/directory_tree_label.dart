import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';

/// A row label with the parts that match a search highlighted.
///
/// Builds a [Text.rich] in [style] whose matched parts are child spans in
/// [highlightStyle]. A child span's style applies over its parent's, so a
/// highlight style with `inherit: true` changes only what it sets, such as
/// the weight and background.
///
/// [matchRanges] are what [TreeQuery.matchRanges] returns for [text]
/// (`DirectoryTreeController.matchRangesOf` gives them for a row), but any
/// list is safe: before building, ranges are clamped to the text, empty
/// ranges and ranges whose start is after their end are ignored, a range
/// that starts or ends inside a surrogate pair grows to include the whole
/// character, and the rest are sorted and merged where they overlap or
/// touch. Building takes O(r log r) for r ranges plus the text length.
class DirectoryTreeLabel extends StatelessWidget {
  /// Creates a label that shows [text] with [matchRanges] highlighted.
  const DirectoryTreeLabel({
    super.key,
    required this.text,
    this.matchRanges = const <({int start, int end})>[],
    this.style,
    this.highlightStyle,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  /// The text to show, such as `TreeRow.label`.
  final String text;

  /// The parts of [text] to highlight, as UTF-16 code unit offsets with an
  /// exclusive end, the form [TreeQuery.matchRanges] returns.
  ///
  /// Defaults to none, which shows [text] in [style] alone.
  final List<({int start, int end})> matchRanges;

  /// The style of the whole label; null uses
  /// [DirectoryTreeThemeData.labelStyle].
  ///
  /// Like [Text.style], it is merged with the ambient [DefaultTextStyle]
  /// when its [TextStyle.inherit] is true.
  final TextStyle? style;

  /// The style of the highlighted parts, applied over [style]; null uses
  /// [DirectoryTreeThemeData.matchHighlightStyle].
  final TextStyle? highlightStyle;

  /// The maximum number of lines, as in [Text.maxLines]; null means no
  /// limit. Defaults to 1, the usual for tree rows.
  final int? maxLines;

  /// How text that does not fit is cut, as in [Text.overflow]. Defaults to
  /// [TextOverflow.ellipsis].
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final theme = style == null || highlightStyle == null
        ? DirectoryTreeTheme.of(context)
        : null;
    final ranges = _normalizeRanges(text, matchRanges);
    final InlineSpan span;
    if (ranges.isEmpty) {
      span = TextSpan(text: text);
    } else {
      final highlight = highlightStyle ?? theme!.matchHighlightStyle;
      final children = <InlineSpan>[];
      var cursor = 0;
      for (final range in ranges) {
        if (range.start > cursor) {
          children.add(TextSpan(text: text.substring(cursor, range.start)));
        }
        children.add(
          TextSpan(
            text: text.substring(range.start, range.end),
            style: highlight,
          ),
        );
        cursor = range.end;
      }
      if (cursor < text.length) {
        children.add(TextSpan(text: text.substring(cursor)));
      }
      span = TextSpan(children: children);
    }
    return Text.rich(
      span,
      style: style ?? theme!.labelStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text))
      ..add(
        IterableProperty<({int start, int end})>(
          'matchRanges',
          matchRanges,
          defaultValue: const <({int start, int end})>[],
        ),
      )
      ..add(DiagnosticsProperty<TextStyle>('style', style, defaultValue: null))
      ..add(
        DiagnosticsProperty<TextStyle>(
          'highlightStyle',
          highlightStyle,
          defaultValue: null,
        ),
      )
      ..add(IntProperty('maxLines', maxLines, defaultValue: 1))
      ..add(
        EnumProperty<TextOverflow>(
          'overflow',
          overflow,
          defaultValue: TextOverflow.ellipsis,
        ),
      );
  }
}

/// The valid parts of [ranges] for [text]: clamped, grown to whole
/// characters at surrogate pairs, sorted, and merged where they overlap or
/// touch, so the result splits [text] into well-formed substrings.
List<({int start, int end})> _normalizeRanges(
  String text,
  List<({int start, int end})> ranges,
) {
  final length = text.length;
  if (ranges.isEmpty || length == 0) return const <({int start, int end})>[];
  final valid = <({int start, int end})>[];
  for (final range in ranges) {
    var start = range.start;
    var end = range.end;
    // Reversed and empty ranges select nothing; out-of-range parts are cut
    // off, which can leave nothing.
    if (start >= end) continue;
    if (start < 0) start = 0;
    if (end > length) end = length;
    if (start >= end) continue;
    // A boundary between the two halves of a surrogate pair would leave an
    // unpaired surrogate in each span, which renders as a replacement
    // character, so the range grows to cover the whole character.
    if (start > 0 && _splitsPair(text, start)) start--;
    if (end < length && _splitsPair(text, end)) end++;
    valid.add((start: start, end: end));
  }
  if (valid.length < 2) return valid;
  valid.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  var current = valid.first;
  for (var i = 1; i < valid.length; i++) {
    final next = valid[i];
    if (next.start <= current.end) {
      if (next.end > current.end) {
        current = (start: current.start, end: next.end);
      }
    } else {
      merged.add(current);
      current = next;
    }
  }
  merged.add(current);
  return merged;
}

/// Whether [index] (with `0 < index < text.length`) falls between a high and
/// a low surrogate.
bool _splitsPair(String text, int index) =>
    _isLowSurrogate(text.codeUnitAt(index)) &&
    _isHighSurrogate(text.codeUnitAt(index - 1));

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
