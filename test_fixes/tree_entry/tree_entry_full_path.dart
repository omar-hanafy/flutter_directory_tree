import 'package:flutter_directory_tree/flutter_directory_tree.dart';

// Reads through the flutter_directory_tree barrel, which re-exports
// TreeEntry from package:directory_tree.
String describe(TreeEntry entry) => 'entry at ${entry.fullPath}';

List<String> paths(Iterable<TreeEntry> entries) => [
  for (final entry in entries) entry.fullPath,
];

bool isUnder(TreeEntry entry, String prefix) =>
    entry.fullPath.startsWith(prefix);

String? firstPath(List<TreeEntry> entries) =>
    entries.isEmpty ? null : entries.first.fullPath;

// Control: an unrelated class with the same member name is untouched.
class Download {
  const Download(this.fullPath);

  final String fullPath;
}

String target(Download download) => download.fullPath;
