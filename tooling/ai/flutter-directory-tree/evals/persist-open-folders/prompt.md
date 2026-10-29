---
description: Persisting open folders must save the requested expansion, not the effective one a search changes.
tags: [use, controller, persistence]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

My Flutter app shows a file tree with flutter_directory_tree ^2.0.0 and has a search box. Write two Dart functions: `Map<String, Object?> saveOpenFolders(DirectoryTreeController<Object?> controller)` that returns a JSON-encodable value describing which folders the user opened, and `DirectoryTreeController<Object?> restoreTree(DirectoryTree<Object?> tree, Map<String, Object?> saved)` that creates a controller with those folders open again. A search that is active while saving must not leak its auto-opened folders into the saved value. Reply with only the code.
