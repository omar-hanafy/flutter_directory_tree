import 'package:flutter_directory_tree/flutter_directory_tree.dart' as tree;

const tree.DirectoryTreeThemeData compact = tree.DirectoryTreeThemeData(
  indent: 12,
  rowHeight: 22,
);

tree.DirectoryTreeThemeData denser(tree.DirectoryTreeThemeData base) =>
    base.copyWith(indent: 10, rowHeight: 24);
