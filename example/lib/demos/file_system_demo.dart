import 'package:flutter/material.dart';
// The browser needs dart:io. The web build gets a stub instead, so that
// `flutter build web` never compiles package:flutter_directory_tree/io.dart.
import 'package:flutter_directory_tree_example/demos/file_system/file_system_browser_stub.dart'
    if (dart.library.io) 'package:flutter_directory_tree_example/demos/file_system/file_system_browser_io.dart';

/// A lazy file system browser that starts at the user's home folder.
///
/// Shown on desktop platforms only (see `fileSystemDemoAvailable` in
/// `app.dart`).
class FileSystemDemo extends StatelessWidget {
  /// Creates the file system demo.
  const FileSystemDemo({super.key});

  @override
  Widget build(BuildContext context) => const FileSystemBrowser();
}
