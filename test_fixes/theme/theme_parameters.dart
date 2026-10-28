import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

// Constructor: const, non-const, one argument, both arguments, any order.
const DirectoryTreeThemeData compact = DirectoryTreeThemeData(
  rowHeight: 22,
  indent: 12,
);

const DirectoryTreeThemeData indentOnly = DirectoryTreeThemeData(indent: 20);

const DirectoryTreeThemeData rowOnly = DirectoryTreeThemeData(rowHeight: 32);

const List<DirectoryTreeThemeData> presets = [
  DirectoryTreeThemeData(indent: 8),
  DirectoryTreeThemeData(rowHeight: 40, hoverColor: Color(0x11000000)),
];

DirectoryTreeThemeData build(double width, double height) {
  return DirectoryTreeThemeData(
    hoverColor: const Color(0x22000000),
    indent: width,
    rowHeight: height,
  );
}

// copyWith: one argument, both arguments, chained.
DirectoryTreeThemeData denser(DirectoryTreeThemeData base) {
  return base.copyWith(rowHeight: 24, indent: 10);
}

DirectoryTreeThemeData wider(DirectoryTreeThemeData base) =>
    base.copyWith(indent: 24).copyWith(rowHeight: 30);

// Tear-off of copyWith, then a call through it.
DirectoryTreeThemeData viaTearOff(DirectoryTreeThemeData base) {
  final copy = base.copyWith;
  return copy(hoverColor: const Color(0x33000000));
}

// Inside a widget: unchanged arguments stay as they are.
Widget themed(Widget child) {
  return DirectoryTreeTheme(
    data: const DirectoryTreeThemeData(
      indent: 18,
      hoverColor: Color(0x44000000),
    ),
    child: child,
  );
}

// Control: an unrelated method with the same parameter names is untouched.
class Spacing {
  const Spacing({this.indent = 0, this.rowHeight = 0});

  final double indent;
  final double rowHeight;

  Spacing copyWith({double? indent, double? rowHeight}) => Spacing(
    indent: indent ?? this.indent,
    rowHeight: rowHeight ?? this.rowHeight,
  );
}

Spacing spacing = const Spacing(indent: 4, rowHeight: 6).copyWith(indent: 5);
