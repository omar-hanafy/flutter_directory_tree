---
description: A multi-folder pick uses the directories mode and handles cancel as null.
tags: [use, picker]
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
---

With flutter_directory_tree ^2.0.0, write a Dart function `Future<List<String>> chooseBackupFolders(BuildContext context, DirectoryTree<Object?> tree)` that opens a dialog where the user picks several folders (never files) and returns their paths, or an empty list when the user cancels. Reply with only the code.
