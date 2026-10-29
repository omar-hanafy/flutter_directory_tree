import 'package:flutter_directory_tree/flutter_directory_tree.dart'
    show DirectoryTreeThemeData;

const DirectoryTreeThemeData compact = DirectoryTreeThemeData(
  indent: 12,
  rowHeight: 22,
);

DirectoryTreeThemeData denser(DirectoryTreeThemeData base) =>
    base.copyWith(indent: 10, rowHeight: 24);
