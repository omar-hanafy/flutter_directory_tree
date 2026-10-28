// manual-migration: super_formal_parameter_without_associated_named -- rename super.indent to super.indentWidth and super.rowHeight to super.rowExtent by hand
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

// dart fix cannot rename super parameters: the subclass's own parameter
// names are its public API, so the user renames them by hand.
class SizedTheme extends DirectoryTreeThemeData {
  const SizedTheme({super.indent, super.rowHeight});
}
