import 'package:flutter_directory_tree/flutter_directory_tree.dart';

// A subclass that forwards the renamed parameters to the super constructor.
class CompactTheme extends DirectoryTreeThemeData {
  const CompactTheme() : super(indent: 12, rowHeight: 22);
}

class TallTheme extends DirectoryTreeThemeData {
  TallTheme(double extent) : super(rowHeight: extent * 2);
}
