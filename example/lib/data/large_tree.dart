import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// The root folder of the generated large tree.
const String largeRoot = '/monorepo';

/// File entries for a monorepo whose tree has exactly [nodeCount] nodes:
/// [largeRoot], [packages] packages with [modulesPerPackage] modules each,
/// and the files spread evenly over the modules.
///
/// Besides the root, only files are listed; the tree infers the folders
/// between them. [nodeCount] must
/// leave at least one file per module.
List<TreeEntry<Object?>> largeTreeEntries({
  int nodeCount = 100000,
  int packages = 20,
  int modulesPerPackage = 24,
}) {
  final modules = packages * modulesPerPackage;
  final directories = 1 + packages + modules;
  final files = nodeCount - directories;
  assert(files >= modules, 'nodeCount leaves fewer files than modules');
  final perModule = files ~/ modules;
  var extra = files % modules;
  // The explicit root entry makes the monorepo folder the top-level node.
  // Without it the default TreeRoots.minimal would start the tree at the
  // module folders, the outermost folders that directly hold files.
  final entries = <TreeEntry<Object?>>[
    const TreeEntry<Object?>.directory(largeRoot),
  ];
  for (var p = 0; p < packages; p++) {
    final package = 'package_${_pad(p, 2)}';
    for (var m = 0; m < modulesPerPackage; m++) {
      final module = '$largeRoot/$package/module_${_pad(m, 2)}';
      var count = perModule;
      if (extra > 0) {
        count++;
        extra--;
      }
      for (var f = 0; f < count; f++) {
        entries.add(TreeEntry<Object?>.file('$module/file_${_pad(f, 3)}.dart'));
      }
    }
  }
  return entries;
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');

/// [value] with thousands separators, such as `100,000`.
String formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
