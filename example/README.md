# flutter_directory_tree example

The showcase app for `package:flutter_directory_tree`. It is a Material 3 app
with light and dark themes and a theme-mode toggle in the app bar. Wide windows
get a navigation rail and narrow ones a navigation bar. Each demo lives in its
own file under `lib/demos/`.

| Demo | File | What it shows |
| --- | --- | --- |
| Explorer | `explorer_demo.dart` | A `DirectoryTreePanel` (toolbar, search, tree) over a generated Flutter project. It has multi-selection, `onActivate` opening a file in the details pane, and a context menu with New file, Rename, and Delete (with Undo). Rows drag and drop onto folders. Every edit rebuilds the tree from its entries and assigns `controller.tree`; the controller keeps expansion, selection, and focus by id. |
| Checkboxes | `checkboxes_demo.dart` | `DirectoryTreeCheckboxMode.checks` with tri-state folders, live lists of `checkedLeaves` and `checkedRoots`, and Check all and Uncheck all. |
| File system | `file_system_demo.dart` | Desktop only. `FileSystemTreeLoader` from `package:flutter_directory_tree/io.dart` starts at your home folder and loads each folder when it is expanded. It has a hidden-files toggle, a reload button, and load errors in a SnackBar through `onLoadError`. |
| Large tree | `large_tree_demo.dart` | A generated tree of exactly 100,000 nodes. It shows how long building took and times each toggle, expand all, and collapse all with a `Stopwatch` around the controller command. Search filters all 100,000 nodes. |
| Theming | `theming_demo.dart` | Live `DirectoryTreeTheme` and `DirectoryTreeThemeData` controls: guide style (none, indent, connectors), row extent, indent width, and folder color. It also toggles compact folders, top-level rows, and right-to-left text. A custom `rowBuilder` puts a size badge in the trailing slot of `DirectoryTreeRow`. |
| Picker | `picker_demo.dart` | `showDirectoryTreePicker` in every mode (files, folders, any), single and multiple. It shows the returned nodes or "cancelled". |

Shared sample data is in `lib/data/`. `tree_edits.dart` holds the entry edits
(add, rename, delete, move) that the explorer applies before it builds a new
tree.

## Run it

```sh
flutter run -d macos   # or windows, linux, chrome, an emulator, a phone
```

The File system demo needs `dart:io`, so it appears only on macOS, Windows,
and Linux. `lib/demos/file_system_demo.dart` picks the browser with a
conditional import. The web build compiles `file_system_browser_stub.dart`
and never compiles `package:flutter_directory_tree/io.dart`, so
`flutter build web` works.

On macOS the App Sandbox is turned off in `macos/Runner/*.entitlements`, so
the File system demo can read your real home folder. A sandboxed app sees only
its own container.

Icons come from the Material icon font, so `pubspec.yaml` keeps
`uses-material-design: true`. Apps that use the package need it too.

## Tests

```sh
flutter test                          # widget tests, every demo
flutter test integration_test -d macos  # the app on a real desktop window
```

- `test/app_test.dart` pumps the app, switches to each demo, and checks its key
  behavior. It covers selection and the details pane, opening a file, the
  context menu actions, drag and drop, the checkbox lists, building and timing
  the large tree, the theming controls, and picker results.
- `test/file_system_browser_test.dart` runs the file system browser on a
  temporary folder. It covers lazy loading, the hidden-files toggle, and an
  unreadable folder.
- `test/data_test.dart` checks the entry edits and the generated data.
- `integration_test/app_test.dart` runs on macOS. It drives the explorer with
  the mouse and keyboard (arrows, Shift selection, Cmd+F search, Enter) and the
  context menu. It also checks the picker dialog (search, Enter, Escape), the
  large tree, and the file system demo.
