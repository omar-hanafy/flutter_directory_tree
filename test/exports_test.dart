import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('re-exports the directory_tree core', () {
    final tree = DirectoryTree.fromPaths(['/repo/lib/main.dart']);
    expect(tree.fileCount, 1);
  });
}
