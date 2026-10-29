import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/io.dart';

/// Browses the local file system with a [FileSystemTreeLoader]: the root
/// folder is read one level deep, and every other folder loads its
/// contents the first time it is expanded.
///
/// Folders that cannot be read (no permission, removed meanwhile) report
/// the failure through the controller's `onLoadError`, which shows it in a
/// [SnackBar]; expanding the folder again retries.
class FileSystemBrowser extends StatefulWidget {
  /// Creates a browser rooted at [rootPath], or at the user's home folder
  /// when it is `null`.
  const FileSystemBrowser({super.key, this.rootPath});

  /// The folder to show; the home folder when `null`.
  final String? rootPath;

  @override
  State<FileSystemBrowser> createState() => _FileSystemBrowserState();
}

/// The user's home folder, or the current directory when the environment
/// does not name one.
String homeDirectory() {
  final environment = Platform.environment;
  return environment['HOME'] ??
      environment['USERPROFILE'] ??
      Directory.current.path;
}

class _FileSystemBrowserState extends State<FileSystemBrowser> {
  late final String _rootPath = widget.rootPath ?? homeDirectory();
  bool _includeHidden = false;
  late FileSystemTreeLoader _loader = FileSystemTreeLoader(
    includeHidden: _includeHidden,
  );
  DirectoryTreeController<FileSystemEntity>? _controller;
  Object? _rootError;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final tree = await _loader.loadTree(_rootPath);
      if (!mounted) return;
      setState(() {
        _controller = DirectoryTreeController<FileSystemEntity>(
          tree: tree,
          expansion: const ExpansionState.collapsed().expandAll(tree.roots),
          // A closure rather than the tear-off, so the hidden-files toggle
          // can swap the loader without a new controller.
          loadChildren: (directory) => _loader.loadChildren(directory),
          onLoadError: _handleLoadError,
        );
      });
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _rootError = error);
    }
  }

  void _handleLoadError(NodeId directory, Object error, StackTrace stack) {
    if (!mounted) return;
    final name = _controller?.tree[directory]?.name ?? directory.value;
    final reason = error is FileSystemException
        ? (error.osError?.message ?? error.message)
        : '$error';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not open $name: $reason')));
  }

  void _toggleHidden() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _includeHidden = !_includeHidden;
      _loader = FileSystemTreeLoader(includeHidden: _includeHidden);
    });
    // Reading the root again with the new loader shows or hides the dot
    // files; the folders below it load again when they are expanded.
    for (final root in controller.tree.roots) {
      unawaited(controller.reloadChildren(root));
    }
  }

  void _refresh() {
    final controller = _controller;
    if (controller == null) return;
    final focused = controller.focusedRow?.node;
    final directory = switch (focused) {
      DirectoryNode<FileSystemEntity>() => focused,
      FileNode<FileSystemEntity>(:final parent?) => controller.tree[parent],
      _ => controller.tree.rootNodes.firstOrNull,
    };
    if (directory != null) unawaited(controller.reloadChildren(directory.id));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      final error = _rootError;
      return Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not read $_rootPath: $error'),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DirectoryTreePanel<FileSystemEntity>(
            controller: controller,
            title: Text(_rootPath, overflow: TextOverflow.ellipsis),
            searchHintText: 'Search loaded files',
            actions: [
              IconButton(
                tooltip: _includeHidden
                    ? 'Hide hidden files'
                    : 'Show hidden files',
                isSelected: _includeHidden,
                icon: const Icon(Icons.visibility_off_outlined),
                selectedIcon: const Icon(Icons.visibility),
                onPressed: _toggleHidden,
              ),
              IconButton(
                tooltip: 'Reload folder',
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              controller.focusedRow?.node.data?.path ??
                  'Expand a folder to load it. Its contents are read only '
                      'when you open it.',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
