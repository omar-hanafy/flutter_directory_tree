import 'package:flutter_directory_tree/flutter_directory_tree.dart' as tree;

int changeCount(tree.ListDiff diff) =>
    diff.removeIndicesDesc.length + diff.insertIndicesAsc.length;
