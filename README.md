# flutter_directory_tree

[![pub package](https://img.shields.io/pub/v/flutter_directory_tree.svg)](https://pub.dev/packages/flutter_directory_tree)

A tree view of files and folders for Flutter: the explorer pane of an
editor, a file or folder picker, a repository browser. It shows a
`DirectoryTree` from
[`package:directory_tree`](https://pub.dev/packages/directory_tree) as a
virtualized list of fixed-height rows, and it handles the mouse, touch, and
the keyboard the way desktop file explorers do.

One `DirectoryTreeController` holds the state of a view: which folders are
open, the selection, the checkboxes, the keyboard focus, the search, and
which folders are still loading. The widgets read it and call its commands.
You can replace the data at any time, for example after a file watcher
event, and the view keeps what the user had open, selected, and focused.

- Virtualized rows: only the rows on screen are built. Opening a folder
  builds only the rows that appear, and a selection or focus change
  rebuilds only the rows whose state changed.
- Keyboard navigation with Windows and Linux bindings, macOS bindings,
  right-to-left layouts, and type-ahead find.
- Selection with click, Shift-click, and Ctrl-click (Cmd-click on macOS),
  plus tri-state checkboxes kept separately from the selection.
- Search with globs, quoted phrases, and `ext:`, `type:`, and `path:`
  terms. Matches are revealed and highlighted, and clearing the search
  closes the folders it opened.
- Lazy loading of folder contents, with a loader for the local file system.
- Context menus, drag and drop onto folders, and a picker dialog.
- Material 3 defaults, file-type icons, indent guides, a `ThemeExtension`,
  custom row builders, and slivers you can combine with your own.
- Screen reader support: each row reports its label, level, and selected,
  expanded, and checked states.

| Platform | `flutter_directory_tree.dart` | `io.dart` (file system loader) |
| --- | --- | --- |
| Android, iOS | yes | yes |
| Linux, macOS, Windows | yes | yes |
| Web, compiled to JavaScript or WebAssembly | yes | no |

The test suite runs on the Dart VM and in Chrome, both as JavaScript and
as WebAssembly.

## Install

```sh
flutter pub add flutter_directory_tree
```

The default file and folder icons come from the Material icon font, so the
app's `pubspec.yaml` must declare it (new Flutter projects already do):

```yaml
flutter:
  uses-material-design: true
```

Import one library:

```dart
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
```

It re-exports all of `package:directory_tree`, so `DirectoryTree`,
`TreeQuery`, `ExpansionState`, and `SelectionState` need no extra import.

## Quick start

Create the controller in `initState`, dispose it in `dispose`, and give it
to a view:

```dart
class ExplorerPane extends StatefulWidget {
  const ExplorerPane({super.key});

  @override
  State<ExplorerPane> createState() => _ExplorerPaneState();
}

class _ExplorerPaneState extends State<ExplorerPane> {
  late final DirectoryTreeController<Object?> _controller;

  @override
  void initState() {
    super.initState();
    final tree = DirectoryTree.fromPaths([
      '/repo/lib/main.dart',
      '/repo/lib/src/tree.dart',
      '/repo/test/tree_test.dart',
      '/repo/README.md',
    ]);
    _controller = DirectoryTreeController(
      tree: tree,
      expansion: ExpansionState.withExpanded(tree.roots),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DirectoryTreePanel(
      controller: _controller,
      title: const Text('Explorer'),
      onActivate: (row) => debugPrint('open ${row.node.path}'),
    );
  }
}
```

`DirectoryTreePanel` puts a toolbar (expand all, collapse all) and a search
field above a `DirectoryTreeView`. Use `DirectoryTreeView` alone when you
want only the tree. Both fill the space their parent gives them and scroll,
so they need a bounded height, such as the body of a `Scaffold` or an
`Expanded` in a `Column`.

`onActivate` runs on a double-click and on Enter, for files and folders.
A folder opens or closes first.

## The controller

### Expansion, selection, checkboxes, and focus

```dart
final controller = DirectoryTreeController(
  tree: DirectoryTree.fromPaths([
    '/repo/lib/main.dart',
    '/repo/lib/src/tree.dart',
    '/repo/test/tree_test.dart',
    '/repo/README.md',
  ]),
);
List<String> labels() => [for (final row in controller.rows) row.label];
final repo = controller.tree.roots.single;
final lib = controller.tree.idOf('/repo/lib')!;

controller.expand(repo);
print(labels()); // [repo, lib, test, README.md]

controller.select(lib); // a plain click: selects and focuses the row
controller.moveFocus(
  TreeFocusMove.next, // the down arrow
  selection: TreeSelectionUpdate.extend, // with Shift
);
print(controller.focusedRow!.label); // test
print(controller.selectedNodes.map((node) => node.name)); // (lib, test)

controller.toggleChecked(lib); // a click on lib's checkbox
print(controller.checkStateOf(repo)); // CheckState.partial
final checked = controller.checkedLeaves.map((node) => node.name);
print(checked); // (tree.dart, main.dart)
```

Nodes are identified by `NodeId`, the canonical path of the node, so an id
stays valid when the tree is rebuilt. `controller.tree.idOf(path)` finds
one. Commands ignore ids the tree does not contain, and queries answer
`null`, `false`, -1, or an empty result for them.

The four kinds of state are independent:

- Expansion: `expand`, `collapse`, `toggleExpansion`, `expandAll`,
  `collapseAll`, `expandSubtree`, `collapseSubtree`, and `reveal` (or
  `revealPath`), which opens the ancestors of a node and focuses, selects,
  and scrolls to it.
- Selection, the highlighted rows: `select` (a click), `toggleSelected`
  (Ctrl-click), `extendSelection` (Shift-click), `selectAll`, and
  `clearSelection`. It starts in `SelectionMode.multiple`; set
  `selectionMode` to `SelectionMode.single` for one row at a time. The
  constructor's `selectable` predicate keeps nodes out of the selection,
  for example directories in a file picker.
- Checks, the checkboxes: `toggleChecked`, `setChecked`, `checkAll`, and
  `uncheckAll`. Checking a folder checks every file and empty folder below
  it, and a folder with only some of them checked is `CheckState.partial`.
  Read the result with `checkedLeaves` (files and empty folders) or
  `checkedRoots` (a fully checked folder stands for its whole subtree).
- Focus, the keyboard cursor: `focusedId`, `focusedRow`, `focus`, and
  `moveFocus`. The focus is on a visible row or on nothing. When its row
  disappears, it moves to the nearest row that contains the node.

Every command that changes something notifies the listeners once, and a
command that changes nothing does not notify.

### Requested and effective expansion

A search opens the folders that lead to its matches. The controller keeps
those folders out of `controller.expansion`, the requested state, which
holds only what the user and the app opened. The rows show the effective
state, `controller.rows.expansion`, and `controller.isExpanded(id)` reads
it:

```dart
controller.query = 'tree';
print(labels()); // [repo, lib, src, tree.dart, test, tree_test.dart]
print(controller.isExpanded(lib)); // true
print(controller.expansion.isExpanded(lib)); // false

final saved = controller.expansion.toJson();
print(saved); // {default: collapsed, exceptions: [/repo]}

controller.query = '';
print(labels()); // [repo, lib, test, README.md]
print(ExpansionState.fromJson(saved) == controller.expansion); // true
```

Persist `controller.expansion.toJson()` and pass
`ExpansionState.fromJson(saved)` as the `expansion` of a new controller to
restore the view. While a search is active, the user can still close the
folders it opened.

### Replacing the data

Assign a new tree, or edit the current one with `updateTree`:

```dart
controller.updateTree(
  (builder) => builder.addFile('/repo/lib/src/rows.dart'),
);
print(controller.isSelected(lib)); // true
print(controller.checkStateOf(lib)); // CheckState.partial
```

The controller keeps expansion, selection, checks, and focus by id, so
`lib` stays selected, and the new file is unchecked, which makes `lib`
partial. Ids that no longer exist are dropped, and the focus moves to the
nearest surviving ancestor. On screen, the first visible row keeps its
position.

## Search

Set `controller.query` to the text of a search box, or put a
`DirectoryTreeSearchField` above the view (`DirectoryTreePanel` has one).
The query is parsed with `TreeQuery.parse`, which never throws: text it
does not understand is searched for literally. A node matches when it
matches every term.

| Term | Matches |
| --- | --- |
| `main` | names that contain `main`, ignoring case |
| `tree test` | names that contain `tree` and `test` |
| `"my notes"` | names that contain the phrase; quoted text is literal |
| `!test` | nodes that do not match `test`; works with any term |
| `*.dart`, `test_?.md` | whole names that match the glob |
| `ext:dart`, `ext:dart,md`, `ext:tar.gz` | files whose name ends with one of the extensions |
| `type:file`, `type:dir` | files, or directories (`type:f` and `type:d` work too) |
| `path:lib/src` | nodes whose path contains `lib/src` |
| `lib/src` | the node `src` in a path that contains `lib/src`, so the text of a compacted row can be typed |
| `lib/` | the direct children of a folder whose path ends with `lib` |

The full rules are on `TreeQuery`. The view shows the matches with their
ancestors, dims the ancestors, and highlights the matched part of each
label:

```dart
controller.query = 'ext:dart !test';
final matches = controller.rows.where((row) => row.isMatch);
print(matches.map((row) => row.label)); // (rows.dart, tree.dart, main.dart)
print(labels().first); // repo

controller.query = 'MAIN';
final main = controller.rows.singleWhere((row) => row.isMatch);
print(controller.matchRangesOf(main)); // [(end: 4, start: 0)]
controller.query = '';
```

- `caseSensitiveQuery: true` compares names, globs, and `path:` terms with
  exact case.
- `filter` adds a filter of your own, such as
  `TreeFilter.where<Object?>((node) => !node.name.startsWith('.'))`; it is
  combined with the query.
- `revealMatches: false` leaves matches inside closed folders hidden until
  the user opens them.

Each change of the query or filter runs the filter once over the whole
tree. Opening and closing folders during a search reuses those results.

## Lazy loading

Give the controller a `loadChildren` function, and a folder without
children loads them the first time it is opened:

```dart
// Stands in for a network or database call.
Future<List<String>> listFolder(String path) async => switch (path) {
  '/bucket' => ['photos/', 'notes.txt'],
  '/bucket/photos' => ['cat.jpg'],
  _ => [],
};

final controller = DirectoryTreeController<Object?>(
  tree: DirectoryTree.fromPaths(['/bucket/']),
  loadChildren: (directory) async {
    final path = directory.path.toString();
    return [
      for (final name in await listFolder(path))
        name.endsWith('/')
            ? TreeEntry.directory('$path/$name')
            : TreeEntry.file('$path/$name'),
    ];
  },
  onLoadError: (directory, error, stackTrace) =>
      debugPrint('Cannot open $directory: $error'),
);
final bucket = controller.tree.roots.single;
print(controller.loadStatusOf(bucket)); // DirectoryLoadStatus.notLoaded

controller.expand(bucket); // starts the load
print(controller.loadStatusOf(bucket)); // DirectoryLoadStatus.loading
await controller.loadChildren(bucket); // waits for the running load
print(controller.rows.map((row) => row.label)); // (bucket, photos, notes.txt)
```

The row of a loading folder shows a progress indicator in place of its
arrow. A load that throws marks the folder `DirectoryLoadStatus.failed`,
calls `onLoadError`, and shows an error icon in place of the arrow.
Clicking the icon, or opening the folder again, retries the load.

`reloadChildren(id)` drops a folder's contents and loads them again, as a
refresh button would; the folders that were open below it open again as
their contents come back. Loads still running when the tree is replaced
are discarded, and an open folder whose load was discarded loads again.

### The local file system

`package:flutter_directory_tree/io.dart` adds `FileSystemTreeLoader`, which
reads one folder at a time with `dart:io`:

```dart
import 'package:flutter_directory_tree/io.dart';
```

```dart
Future<DirectoryTreeController<FileSystemEntity>> openFolder(
  String path,
) async {
  const loader = FileSystemTreeLoader();
  final tree = await loader.loadTree(path); // the folder and its children
  return DirectoryTreeController(
    tree: tree,
    expansion: ExpansionState.withExpanded(tree.roots),
    loadChildren: loader.loadChildren,
  );
}
```

Each node's `data` is its `File`, `Directory`, or `Link`. Hidden entries
are left out unless `includeHidden` is true, `skip` leaves out what you
choose, and links are not followed unless `followLinks` is true.

`io.dart` needs `dart:io`, so it works on Android, iOS, Linux, macOS, and
Windows, but not on the web. The main library never imports it. An app
that also runs on the web must keep this import out of its web build, for
example behind a conditional import. To read a whole folder at once, use
the re-exported `DirectoryScanner` from the same library.

## Keyboard

`DirectoryTreeView` and `DirectoryTreePanel` include a
`DirectoryTreeKeyboard`. Its default bindings come from
`DirectoryTreeShortcuts.defaults` and depend on the platform:

| Action | Windows and Linux | macOS |
| --- | --- | --- |
| Move the focus and select that row | Up, Down, Home, End, Page Up, Page Down | Up, Down, Home, End, Page Up, Page Down |
| Move the focus and extend the selection from the anchor | Shift+Up, Shift+Down, Shift+Home, Shift+End, Shift+Page Up, Shift+Page Down | Shift+Up, Shift+Down, Shift+Home, Shift+End, Shift+Page Up, Shift+Page Down |
| Move the focus without changing the selection | Ctrl+Up, Ctrl+Down, Ctrl+Home, Ctrl+End, Ctrl+Page Up, Ctrl+Page Down | none |
| Move to the parent row and select it | none | Cmd+Up |
| Open the folder, or move into an open folder | Numpad +, Right | Numpad +, Right |
| Close the folder, or move to the parent row | Numpad -, Left | Numpad -, Left |
| Open the folder and every folder below it | `*`, Numpad * | `*`, Numpad * |
| Activate the row: a folder opens or closes, then `onActivate` runs | Enter, Numpad Enter | Enter, Numpad Enter, Cmd+Down |
| Toggle the focused row's selection (its check in checks mode) | Space, Ctrl+Space | Space, Ctrl+Space |
| Select every visible row (multiple selection mode only) | Ctrl+A | Cmd+A |
| Clear the selection | Escape | Escape |
| Open the context menu of the focused row | Shift+F10, Menu | Shift+F10, Menu |

iOS uses the macOS bindings, and Android uses the Windows and Linux ones.
In a right-to-left layout, Left and Right swap, so the arrow that points
into the indentation always closes. Page Up and Page Down move by the
number of rows that fit on screen.

Typing the start of a name jumps to a row whose label starts with
it, ignoring case; repeating one letter cycles through the rows that start
with it. Space joins the search only while one is in progress. Letters
typed with Option on macOS or AltGr on Windows count as typing.

The keys act only while the tree itself has keyboard focus. A click on a
row gives it focus. When the tree gets the focus without a focused row,
by Tab or `autofocus`, the focus goes to the first selected row, or to the
first row. When a text field or a button, even one inside a custom row,
has focus, every key goes to that widget instead.

With `selectionFollowsFocus: false`, the arrows, Home, End, the page keys,
and type-ahead move the focus without changing the selection, and Space
toggles the focused row; the picker works this way for a multiple
selection without checkboxes.

To change a binding, spread the defaults into a new map and pass it as
`shortcuts` (`defaultTargetPlatform` comes from
`package:flutter/foundation.dart`, `LogicalKeyboardKey` from
`package:flutter/services.dart`):

```dart
Widget buildTree(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) {
  return DirectoryTreeView(
    controller: controller,
    shortcuts: {
      ...DirectoryTreeShortcuts.defaults(
        platform: defaultTargetPlatform,
        textDirection: Directionality.of(context),
      ),
      // Backspace goes to the parent folder, as in some file managers.
      const SingleActivator(LogicalKeyboardKey.backspace):
          const MoveTreeFocusIntent(TreeFocusMove.parent),
    },
  );
}
```

To change what a key does, keep the binding and map its intent type (such
as `ActivateTreeNodeIntent`) to your own action in an `Actions` widget
above the view. `DirectoryTreeKeyboard` documents every intent.

## Mouse and touch

| Input | What happens |
| --- | --- |
| Click | Focuses the row, gives the tree keyboard focus, and selects the row. A click on a folder also opens or closes it. |
| Shift-click | Selects the range from the anchor (the row of the last click without Shift) to this row. |
| Ctrl-click, or Cmd-click on macOS | Adds the row to the selection or removes it. |
| Double-click | Activates the row: a folder opens or closes once, then `onActivate` runs. |
| Click on the arrow or the checkbox | Toggles it, without selecting or activating the row. |
| Secondary click, Ctrl-click on macOS, or a touch long press | Selects the row unless it is already selected (only focuses it with `selectOnTap: false`), then calls `onRowSecondaryTap` and opens the context menu. |
| Mouse hover | Highlights the row with the theme's `hoverColor`. Touch never hovers. |

Clicks act when the pointer goes up, and a single click is never delayed
to wait for a double-click. `selectOnTap: false` makes clicks only focus
rows, for views where checkboxes or the app decide the selection.
`expandOnTap: false` leaves opening folders to the arrow, the keyboard, and
double-clicks. `onRowTap` runs after the built-in handling of each click.

With drag and drop, a touch long press followed by a move starts a drag,
and a long press released without moving opens the context menu.

## Context menus

```dart
final view = DirectoryTreeView(
  controller: controller,
  contextMenuBuilder: (context, details) => [
    MenuItemButton(
      onPressed: () => controller.expandSubtree(details.row.id),
      child: const Text('Expand all below'),
    ),
    MenuItemButton(
      onPressed: () => controller.updateTree((builder) {
        for (final node in details.nodes) {
          builder.remove(node.path.toString());
        }
      }),
      child: Text('Delete ${details.nodes.length}'),
    ),
  ],
);
```

The menu opens on a secondary click, a touch long press, Shift+F10, and the
context menu key, at the pointer or below the focused row. Before it
opens, the row is selected if it was not, unless the view has
`selectOnTap: false`, which leaves the selection to the app.
`details.nodes` is the whole selection when the user opened the menu on a
selected row, and only that row's node otherwise, so "Delete" deletes what
the user selected. Return an empty list to open no menu for a row.

The menu is a Material `MenuAnchor` menu. To show a menu from another
design system, leave `contextMenuBuilder` out and handle
`onRowSecondaryTap`, which receives the row and the global pointer
position; Shift+F10 then calls it at the bottom start corner of the
focused row (bottom right in a right-to-left layout).

On the web, a right click also opens the browser's own context menu over
the tree's menu. Call `BrowserContextMenu.disableContextMenu()` (from
`package:flutter/services.dart`) while a tree with a menu is on screen,
and `BrowserContextMenu.enableContextMenu()` when it goes away: the
setting is page-wide, and text fields use the browser's menu.

## Drag and drop

The package never moves your data. It tells you what the user dropped
where, and your handler moves the data and gives the controller the new
tree:

```dart
void moveInto(
  DirectoryTreeController<Object?> controller,
  DirectoryTreeDropDetails<Object?> details,
) {
  final tree = controller.tree;
  final target = details.target.path.toString();
  controller.updateTree((builder) {
    for (final node in details.nodes) {
      final from = node.path.toString();
      final parent = from.substring(0, from.lastIndexOf('/'));
      for (final moved in [node, ...tree.descendantsOf(node.id)]) {
        final to = '$target${moved.path.toString().substring(parent.length)}';
        if (moved.isFile) {
          builder.addFile(to);
        } else {
          builder.addDirectory(to);
        }
      }
      builder.remove(from);
    }
  });
}
```

```dart
final view = DirectoryTreeView(
  controller: controller,
  dragAndDrop: DirectoryTreeDragAndDrop(
    onDrop: (details) => moveInto(controller, details),
  ),
);
```

A real file browser moves the files on disk in `onDrop`, then assigns the
re-read tree to `controller.tree`. Expansion, selection, and focus carry
over by id.

The user drags a row (or the whole selection, when the row is selected)
and drops it on a folder row, or on a file row to drop into that file's
folder. A mouse drag starts after the pointer moves 4 logical pixels; a
touch drag starts with a long press. While dragging, the target folder and
its visible rows are tinted, a closed folder opens after the pointer rests
on it for `autoExpandDelay` (700 milliseconds by default), and the list
scrolls near its edges.

`canDrag` and `canDrop` limit what may be dragged and where it may land.
A folder is never dropped into itself or into a folder inside it.
Without `canDrop`, a drop that would change nothing is refused too. Drag
and drop has no keyboard or screen reader gesture, so offer moves in a
context menu as well.

## Checkboxes and the picker

`checkboxMode: DirectoryTreeCheckboxMode.checks` puts a tri-state checkbox
in front of each row, bound to `controller.checks`. Space toggles the
focused row's check. `DirectoryTreeCheckboxMode.selection` shows a
two-state box that mirrors the highlight selection instead.

```dart
final view = DirectoryTreeView(
  controller: controller,
  checkboxMode: DirectoryTreeCheckboxMode.checks,
  selectOnTap: false,
);
```

`showDirectoryTreePicker` opens a dialog with its own state, so nothing in
your app changes until you use the result:

```dart
final picked = await showDirectoryTreePicker(
  context: context,
  tree: controller.tree,
  mode: DirectoryTreePickerMode.directories,
  title: 'Choose a folder',
);
if (picked != null) debugPrint('chosen: ${picked.single.path}');
```

What it returns depends on `mode` and `multiple`:

| `mode` | `multiple: false` (default) | `multiple: true` |
| --- | --- | --- |
| `files` (default) | the one file the user picked | the checked files; checking a folder checks every file below it |
| `directories` | the one folder the user picked | every folder whose own box is checked; a folder's box does not check its children |
| `any` | the one file or folder the user picked | the outermost checked nodes: a fully checked folder stands for everything below it |

The result is `null` when the user cancels (Cancel, Escape, a tap outside
the dialog, or the back button). Otherwise it is a non-empty list in
display order: OK stays disabled until the pick is valid. In single mode a
double-click or Enter on a valid row confirms it at once. Pass
`initialSelection` and `initialExpansion` to start from the state of an
existing controller. `DirectoryTreePicker` is the same picker without the
dialog, for a page or a dialog of your own.

## Theming

Every size, color, text style, icon, and animation setting is a field of
`DirectoryTreeThemeData`, and every field is optional. The defaults come
from the app's Material 3 `ColorScheme`, `TextTheme`, and `VisualDensity`.
Register app-wide values as a theme extension, so they animate when the app
theme changes:

```dart
final app = MaterialApp(
  theme: ThemeData(
    extensions: const [
      DirectoryTreeThemeData(
        rowExtent: 28,
        indentWidth: 12,
        guideStyle: DirectoryTreeGuideStyle.connectors,
      ),
    ],
  ),
  home: const Scaffold(body: ExplorerPane()),
);
```

Override values for one subtree with `DirectoryTreeTheme`:

```dart
final view = DirectoryTreeTheme(
  data: DirectoryTreeThemeData(
    folderIconColor: Colors.amber,
    iconSet: DirectoryTreeIconSet.material.copyWith(
      extensions: {
        ...DirectoryTreeIconSet.material.extensions,
        'proto': Icons.schema_outlined,
      },
    ),
  ),
  child: DirectoryTreeView(controller: controller),
);
```

`DirectoryTreeTheme.of(context)` resolves the theme in that order: the
Material defaults, then the extension, then the nearest
`DirectoryTreeTheme`. A few fields to know:

- `rowExtent` is the height of every row: 36 by default, adjusted by the
  visual density (28 for `VisualDensity.compact`, the desktop default),
  at least 48 where Material pads tap targets (Android, iOS, Fuchsia), and
  taller when the text scale makes a label line taller. A `rowExtent` you
  set is used as given.
- `selectedColor` is the selection background while the tree has keyboard
  focus, and `inactiveSelectedColor` while it does not. Set both to the
  same color for one selection color.
- `guideStyle` draws vertical `indent` lines (the default), `connectors`
  like the `tree` command, or `none`.
- `animationDuration` animates the arrows and the rows a folder reveals;
  `Duration.zero` turns animations off. They are also off while the
  platform asks for reduced motion.

## Custom rows

A `rowBuilder` builds each row from its `DirectoryTreeRowDetails`: the
`TreeRow`, whether it is selected, focused, or hovered, whether the tree has
focus, its check state, its load status, and the search highlight ranges.
It runs only for rows whose details changed. The view adds the click,
hover, and semantics handling around what it returns.

To change one part of the default row, return a `DirectoryTreeRow` and set
its `expander`, `leading`, `title`, or `trailing` slot:

```dart
final sizes = DirectoryTreeController<int>(
  tree: DirectoryTree<int>.build([
    TreeEntry.file('/repo/README.md', data: 1200),
    TreeEntry.file('/repo/lib/main.dart', data: 640),
  ]),
);
final view = DirectoryTreeView(
  controller: sizes,
  rowBuilder: (context, details) => DirectoryTreeRow(
    details: details,
    trailing: Text('${details.row.node.data ?? ''}'),
  ),
);
```

To draw the whole row yourself, reuse `DirectoryTreeExpander` and
`DirectoryTreeCheckbox`, which keep the standard behavior: the arrow
toggles the folder, shows progress while it loads, and retries a failed
load, and the checkbox follows `checkboxMode`:

```dart
Widget buildRow(
  BuildContext context,
  DirectoryTreeRowDetails<Object?> details,
) {
  final row = details.row;
  return Padding(
    padding: EdgeInsetsDirectional.only(start: 16.0 * row.depth),
    child: Row(
      children: [
        DirectoryTreeExpander(details: details),
        DirectoryTreeCheckbox(details: details),
        Expanded(
          // The row's semantics node already carries the label.
          child: ExcludeSemantics(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (details.isSelected) const Icon(Icons.check, size: 16),
      ],
    ),
  );
}
```

Pass it as `rowBuilder: buildRow`. Keep a row within the theme's
`rowExtent`: every row has that fixed height. `DirectoryTreeLabel` draws a
label with search highlights, and `DirectoryTreeIndentGuides` draws the
guide lines, if your row needs them.

## Composing with slivers

`DirectoryTreeView` is a `CustomScrollView` with one
`SliverDirectoryTree`, wrapped in a `DirectoryTreeKeyboard`. Build that
stack yourself to put other slivers in the same scroll view:

```dart
final explorer = DirectoryTreeKeyboard(
  controller: controller,
  onActivate: (row) => debugPrint('open ${row.node.path}'),
  child: CustomScrollView(
    slivers: [
      const SliverToBoxAdapter(child: ListTile(title: Text('Open editors'))),
      SliverDirectoryTree(
        controller: controller,
        onActivate: (row) => debugPrint('open ${row.node.path}'),
      ),
    ],
  ),
);
```

The keyboard widget handles Enter and the sliver handles double-clicks,
so give both the same `onActivate`. The sliver registers itself with the
controller, so `ensureVisible`, `reveal`, and Page Up and Page Down scroll
the right list even with slivers before it. Add a context menu with
`DirectoryTreeContextMenu` and drag and drop with
`DirectoryTreeDragAndDropScope` around the scroll view; their
documentation shows the wiring that `DirectoryTreeView` does for you.

The controller also works without any of these widgets: `rows` is a
`List<TreeRow>`, and `lastRowsChange` says which block of rows the last
update replaced, for a list view of your own.

## Performance

The controller's commands have these costs, for n nodes in the tree:

- Moving the focus and changing the selection of one row: O(log rows).
  The view then rebuilds only the rows whose details changed.
- Opening or closing one folder: O(log rows + the rows that appear or
  disappear). The other rows stay the same objects, and the filter is not
  called again.
- `checkStateOf`: O(n) once after the tree or the checks change, then O(1)
  per row. `toggleChecked` and `setChecked` update those counts for the
  node's subtree and ancestors only.
- Full passes over the tree happen only for a new tree, a change of the
  query or filter, a change of `compactFolders` or `showRoots`, and bulk
  commands such as `expandAll`, `selectAll`, and `checkAll`.

Scrolling builds only the rows in the viewport, at a fixed height, so the
cost of a frame does not grow with the tree. The type-ahead search reads
each row label at most once per key press.

<!-- benchmark numbers: filled in after the final run -->

## Accessibility

Each row is one semantics node. It carries the row label, the selected
state, the expanded state of folders, the checked or mixed state when the
view shows checkboxes, a tap action, expand and collapse actions, a
long-press action when the view has a context menu or
`onRowSecondaryTap`, and a hint with the row's level (`Level 2` for a row
at depth 1). With `onActivate`, rows also offer an "Open" action, so touch
screen reader users, who have no double-click and no Enter key, can
activate them. A folder that is loading or failed to load says so, and a
failed one offers an action that retries the load.

While the tree has the keyboard focus, the focused row is the focused
semantics node, so screen readers follow the arrow keys. Rows grow with
the text scale, and on touch platforms they are at least 48 pixels tall.

```dart
final view = DirectoryTreeView(
  controller: controller,
  semanticLabel: 'Project files',
  levelSemanticsHint: (level) => 'Ebene $level',
);
```

`semanticLabel` names the whole tree, and `levelSemanticsHint` translates
the level hint; `activateSemanticsLabel`, `loadingSemanticsLabel`, and
`loadFailedSemanticsLabel` translate the other English defaults. A custom row should not repeat the label in its own
semantics; wrap such text in `ExcludeSemantics`, as the custom row above
does.

## Migrating from 1.x

2.0.0 is a rewrite on directory_tree 2.0.0, and code written for 1.x needs
changes. `dart fix --apply` handles seven renames. [MIGRATION.md](MIGRATION.md)
maps every 1.x declaration to its replacement, lists the changes that
compile but behave differently, and has recipes for 1.x features that
moved.

## Development

Run these from the package root before sending a change:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_repo.dart
flutter test
flutter test --platform chrome
flutter test --platform chrome --wasm
dart fix test_fixes --compare-to-golden
```

[AGENTS.md](https://github.com/omar-hanafy/flutter_directory_tree/blob/main/AGENTS.md)
in the repository describes the conventions and the release process.

## License

MIT. See [LICENSE](LICENSE).
