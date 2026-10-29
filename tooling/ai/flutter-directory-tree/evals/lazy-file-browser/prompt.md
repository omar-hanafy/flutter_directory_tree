---
description: A desktop folder browser uses the package's file system loader and loads folders lazily.
tags: [use, lazy-loading, io]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

Using flutter_directory_tree ^2.0.0 in a macOS app, write a Dart function `Future<DirectoryTreeController<FileSystemEntity>> openFolder(String path)` that shows a folder from disk, reads each subfolder only when the user opens it, and logs folders that cannot be read. Include the imports. Reply with only the code.
