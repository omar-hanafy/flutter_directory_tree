import 'package:flutter/material.dart';

/// The file system browser on platforms without `dart:io` (the web): a
/// message instead of a tree.
///
/// Has the same constructor as the `dart:io` version, so the conditional
/// import in `file_system_demo.dart` can pick either.
class FileSystemBrowser extends StatelessWidget {
  /// Creates the placeholder; [rootPath] is ignored.
  const FileSystemBrowser({super.key, this.rootPath});

  /// Ignored on this platform.
  final String? rootPath;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('The file system demo needs a desktop platform.'),
  );
}
