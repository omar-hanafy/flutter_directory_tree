/// Loads directory trees from the local file system into tree views, one
/// folder at a time.
///
/// This optional library adds [FileSystemTreeLoader]: its `loadTree` reads
/// a directory into a `DirectoryTree<FileSystemEntity>`, and its
/// `loadChildren` reads a folder's contents when a [DirectoryTreeController]
/// expands it. It also re-exports [DirectoryScanner] from
/// `package:directory_tree/io.dart`, which reads a whole directory at once.
///
/// It needs `dart:io`, so it works in apps for Android, iOS, Linux, macOS,
/// and Windows, but not on the web. The main library never imports it or
/// `dart:io`, so an app that also runs on the web keeps this import out of
/// its web build (for example behind a conditional import). Import it next
/// to the main library:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:flutter_directory_tree/flutter_directory_tree.dart';
/// import 'package:flutter_directory_tree/io.dart';
///
/// Future<DirectoryTreeController<FileSystemEntity>> openFolder(
///   String path,
/// ) async {
///   const loader = FileSystemTreeLoader();
///   return DirectoryTreeController<FileSystemEntity>(
///     tree: await loader.loadTree(path),
///     loadChildren: loader.loadChildren,
///   );
/// }
/// ```
library;

// Imported only so the references in the library documentation resolve.
import 'package:directory_tree/io.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/io/file_system_tree_loader.dart';

export 'package:directory_tree/io.dart' show DirectoryScanner;
export 'package:flutter_directory_tree/src/io/file_system_tree_loader.dart';
