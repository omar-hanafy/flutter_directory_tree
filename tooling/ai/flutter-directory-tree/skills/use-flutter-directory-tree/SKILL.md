---
name: use-flutter-directory-tree
description: Use when writing or reviewing Flutter code in a project that depends on the flutter_directory_tree package (2.x) - DirectoryTreeController commands (expand, select, toggleChecked, moveFocus, reveal, query, updateTree, loadChildren), DirectoryTreeView and DirectoryTreePanel, SliverDirectoryTree with DirectoryTreeKeyboard, custom rows with rowBuilder and DirectoryTreeRow, checkboxes and showDirectoryTreePicker, context menus, drag and drop, lazy loading with FileSystemTreeLoader, search query syntax, keyboard bindings, DirectoryTreeThemeData theming, persisting the expansion, and keeping trees of 100k+ nodes fast.
---

# Use flutter_directory_tree correctly

flutter_directory_tree 2.x is a ground-up rewrite. Code written from the
1.x API (`TreeBuilder`, `nodeBuilder`, `SelectionShortcuts`, `ExpansionController`)
or with its string ids does not compile, or worse, compiles and does
nothing. Use the exact names below.

## Step 0: inspect the project

1. Resolved version:
   `flutter pub deps --style=compact | grep '^- flutter_directory_tree '`.
   This skill documents 2.x. For 1.x, use the
   migrate-flutter-directory-tree-v1-to-v2 skill first.
2. Existing style: `grep -rn "DirectoryTree" lib/ | head`.
3. One import gives everything:
   `import 'package:flutter_directory_tree/flutter_directory_tree.dart';`.
   It re-exports all of `package:directory_tree` (`DirectoryTree`,
   `TreeEntry`, `NodeId`, `ExpansionState`, `SelectionState`, `TreeQuery`,
   `TreeFilter`), so never add a `package:directory_tree` import beside it.
4. `package:flutter_directory_tree/io.dart` is a second library with
   `FileSystemTreeLoader` (and the core's `DirectoryScanner`). It needs
   `dart:io`: never import it from code that is compiled for the web; put
   it behind a conditional import.
5. The default icons come from the Material icon font: the app's
   pubspec needs `uses-material-design: true` under `flutter:`.

## The model

1. One `DirectoryTreeController<T>` per view (`T` is the type of each
   entry's `data`). Create it in `initState`, dispose it in `dispose`.
   Views and panels never dispose it.
2. State values are immutable. `controller.expansion` is an
   `ExpansionState`, `controller.selection` and `controller.checks` are
   `SelectionState`s. `controller.selection.clear()` returns a new value
   and changes nothing (the analyzer only warns `unused_result`). Call a
   controller command, or compute a value and assign it once:
   `controller.expansion = controller.expansion.expandAll(ids)`.
3. A `NodeId` is the canonical path of a node, so it survives rebuilds
   and can be stored. Get one from `node.id`, `row.id`,
   `controller.tree.nodeAt('/repo/lib')?.id` (`null` when the tree has no
   such node), or `controller.tree.idOf('/repo/lib')`, which returns the
   id of any parseable path whether or not the tree contains it. Unknown
   ids never throw: commands ignore them, queries answer `null`, `false`,
   -1, or an empty result. So a wrong path (or wrong case: paths are
   case-sensitive unless the tree uses `PathPolicy.caseInsensitive`)
   fails silently; check `controller.tree.contains(id)` when in doubt.
4. Every command that changes something notifies listeners exactly once;
   a command that changes nothing does not notify.
5. To change the data, assign `controller.tree = next` or call
   `controller.updateTree((builder) => ...)`. Expansion, selection, checks,
   and focus carry over by id; the focus moves to the nearest surviving
   ancestor; the first visible row keeps its place on screen.

```dart
class FilesPane extends StatefulWidget {
  const FilesPane({super.key, required this.paths, this.savedExpansion});

  final List<String> paths;
  final Map<String, Object?>? savedExpansion;

  @override
  State<FilesPane> createState() => _FilesPaneState();
}

class _FilesPaneState extends State<FilesPane> {
  late final DirectoryTreeController<Object?> _controller;

  @override
  void initState() {
    super.initState();
    final tree = DirectoryTree.fromPaths(widget.paths);
    final saved = widget.savedExpansion;
    _controller = DirectoryTreeController(
      tree: tree,
      expansion: saved == null
          ? ExpansionState.withExpanded(tree.roots)
          : ExpansionState.fromJson(saved),
    );
  }

  @override
  void didUpdateWidget(FilesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.paths, widget.paths)) {
      _controller.tree = DirectoryTree.fromPaths(widget.paths); // keeps state
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The value to persist: the requested expansion, not `rows.expansion`.
  Map<String, Object?> saveExpansion() => _controller.expansion.toJson();

  @override
  Widget build(BuildContext context) {
    return DirectoryTreePanel(
      controller: _controller,
      title: const Text('Files'),
      onActivate: (row) {
        if (row.node.isFile) debugPrint('open ${row.node.path}');
      },
      contextMenuBuilder: (context, details) => [
        MenuItemButton(
          onPressed: () => _controller.updateTree((builder) {
            for (final node in details.nodes) {
              builder.remove(node.path.toString());
            }
          }),
          child: Text('Delete ${details.nodes.length}'),
        ),
      ],
    );
  }
}
```

## Exact names agents get wrong

| Task | Wrong guess (mostly 1.x) | 2.x API |
|---|---|---|
| Build a tree | `TreeBuilder().build(entries: ...)` | `DirectoryTree.fromPaths(paths)`, or `DirectoryTree<T>.build([TreeEntry.file(path, data: x), TreeEntry.directory(path)])` |
| One folder on top | assuming `fromPaths` keeps the shared parent | The default `TreeRoots.minimal()` makes the outermost folders that hold entries the top-level rows (`/repo/lib/a.dart` and `/repo/docs/` give `docs` and `lib`); pass `options: const TreeOptions(roots: TreeRoots.commonAncestor())` or `TreeRoots.fixed(['/repo'])` for one `repo` row |
| Controller data | `data:`, `rebuild(next)` | `tree:`, `controller.tree = next`, `updateTree(...)` |
| Open the top level at start | `autoExpandVisibleRoot` | `expansion: ExpansionState.withExpanded(tree.roots)` |
| Toggle a folder | `toggle(id)` | `toggleExpansion(id)` |
| Open or close a subtree | `expand(id, recursive: true)` | `expandSubtree(id)`, `collapseSubtree(id)` |
| Plain click | `selectOnly(id)` | `select(id)` (also focuses and scrolls; `focus: false` to not) |
| Ctrl-click | `toggleSelection(id)` | `toggleSelected(id)` |
| Shift-click | `selectRange(anchorId: ..., toId: ...)` | `extendSelection(id)` (from the anchor `select` set) |
| Clear | `selection.clear()` | `clearSelection()` |
| Selected ids | `selectedIds` | `selection.selected` (`Set<NodeId>`), `selectedNodes` (display order) |
| Check a folder | `selectSubtree(id)` | `setChecked(id, checked: true)`, `toggleChecked(id)` |
| Search text | `filterQuery` | `query` |
| Visible rows | `visibleNodes`, `node.name` | `rows` (a `List<TreeRow<T>>`), `row.label` |
| Row widget | `nodeBuilder`, `TreeNodeTile` | `rowBuilder` returning `DirectoryTreeRow(details: details, ...)` |
| Keyboard | `SelectionShortcuts(child: ...)` | built into `DirectoryTreeView`; never wrap it |
| Reveal and scroll | `revealAndScroll(...)` | `reveal(id, select: true, alignment: 0)`, `revealPath(path)` |
| Theme | `rowHeight`, `indent`, `selectionColor` | `rowExtent`, `indentWidth`, `selectedColor` plus `inactiveSelectedColor` |
| Picker options | `allowMultiple`, `foldersOnly` | `multiple:`, `mode: DirectoryTreePickerMode.directories` |
| Many-select mode | `SelectionMode.multi` | `SelectionMode.multiple` |

## The controller

Constructor: `DirectoryTreeController<T>({tree, expansion, selection,
checks, selectable, query, caseSensitiveQuery, filter, revealMatches,
compactFolders, showRoots, loadChildren, onLoadError})`. Every argument is
optional. The controller's `selection` and `checks` default to
`SelectionMode.multiple`, but a bare `SelectionState.empty()` is
`SelectionMode.single`: pass
`const SelectionState.empty(mode: SelectionMode.multiple)` when you build
one. `selectable` (a node predicate) keeps nodes out of the selection, for
example folders in a file picker; it must be cheap, because `selectAll` and
`extendSelection` call it per row.

Four independent kinds of state:

- Expansion: `expand`, `collapse`, `toggleExpansion`, `expandAll`,
  `collapseAll`, `expandSubtree`, `collapseSubtree`, `reveal(id, {focus,
  select, scroll, alignment, duration, curve})` (returns whether the node
  has a row), and `revealPath(path, ...)` (returns the id or `null`).
  `expandAll()` opens every folder and starts no loads; it is not the 1.x
  `expansions.expandAll(ids)`. `collapseAll()` keeps the top-level rows.
- Selection (the highlight): `select`, `toggleSelected`, `extendSelection`,
  `selectAll` (multiple mode only), `clearSelection`, `isSelected`,
  `isSelectable`, `selectedNodes`, and the `selectionMode` setter.
- Checks (the checkboxes): `toggleChecked`, `setChecked(id, checked:)`,
  `checkAll`, `uncheckAll`, `checkStateOf(id)` (`CheckState.unchecked`,
  `partial`, or `checked`), `checkedLeaves` (files and empty folders) and
  `checkedRoots` (a fully checked folder stands for its subtree). Checks
  never touch the selection.
- Focus (the keyboard cursor): `focusedId`, `focusedRow`, `focusedIndex`,
  `focus(id)`, and `moveFocus(TreeFocusMove.next, selection:
  TreeSelectionUpdate.extend)`. `TreeSelectionUpdate.keep` moves without
  selecting.

Requested versus effective expansion: a search opens the folders that lead
to its matches, but keeps them out of `controller.expansion`, the requested
state. The rows show the effective state, `controller.rows.expansion`, and
`controller.isExpanded(id)` reads it. Persist
`controller.expansion.toJson()` and restore it with
`ExpansionState.fromJson(saved)`. Clearing the query (`query = ''`) closes
the folders the search opened, except the ones leading to the focused row:
the focused node stays revealed, and those folders join the requested
`controller.expansion` (so a saved expansion can include them).

```dart
void controllerBasics(DirectoryTreeController<Object?> controller) {
  final lib = controller.tree.nodeAt('/repo/lib')?.id;
  if (lib == null) return; // not in the tree (idOf would still return an id)
  controller.expand(lib);
  controller.select(lib); // a click: selects, focuses, and scrolls to it
  controller.setChecked(lib, checked: true); // checks every leaf below lib
  final files = controller.checkedLeaves.map((node) => node.path).toList();
  debugPrint('$files, focused: ${controller.focusedRow?.label}');
}
```

Other members: `rows` (`TreeRows<T>`), `lastRowsChange`, `isExpandable`,
`isFiltering`, `parsedQuery`, `matchRangesOf(row)`, `compactFolders`
(VS Code style `lib/src` rows), `showRoots` (false hides the top-level
rows), `ensureVisible(id)`, and `globalRowRect(index)`.

`lastRowsChange` (`TreeRowsChange`: `isReset`, `index`, `removed`,
`inserted`, `previous`) says which block of `rows` the last update
replaced. Read it inside a listener: when the change replaced the tree,
`previous` becomes `null` after the listeners ran (the API reference
has a `watchRows` example).

## Search

`controller.query = text` (or a `DirectoryTreeSearchField`, which
`DirectoryTreePanel` contains, debounced by 120 ms). The text goes through
`TreeQuery.parse`, which never throws. A node matches when it matches
every term; matches show with their ancestors, and `matchRangesOf(row)`
gives the highlight ranges.

| Term | Matches |
|---|---|
| `main` | names containing `main`, ignoring case |
| `"my notes"` | the quoted phrase, literally |
| `!test` | nodes that do not match `test` (any term) |
| `*.dart`, `test_?.md` | whole names matching the glob |
| `ext:dart,md` | files ending with one of the extensions |
| `type:file`, `type:dir` | files, or directories |
| `path:lib/src` | nodes whose path contains `lib/src` |
| `lib/` | the direct children of a folder whose path ends with `lib` |

`caseSensitiveQuery: true` matches exact case. `filter` adds your own
`TreeFilter.where<T>((node) => ...)`, combined with the query.
`revealMatches: false` leaves matches inside closed folders hidden.

## Lazy loading

Pass `loadChildren` (a `DirectoryChildrenLoader<T>`: it takes the
`DirectoryNode<T>` and returns a `Future` of `TreeEntry<T>`s whose paths
lie inside it). A folder without children loads the first time it opens.
`loadStatusOf(id)` is `DirectoryLoadStatus.notLoaded`, `loading`, `loaded`,
or `failed`; a failed load calls `onLoadError(directory, error,
stackTrace)`, shows an error icon, and opening the folder again (or
clicking the icon) retries. `await controller.loadChildren(id)` waits for
a load. `reloadChildren(id)` is a refresh button: the folder keeps its
rows, and the loads below it keep running, until its listing arrives;
then the listing replaces its contents in one change, and expansion,
selection, checks, and focus stay with every node that still exists. A
failed reload changes nothing below it (status `failed`; expanding
retries). A new tree keeps unfinished refreshes: such folders are listed
on their next expand, and an open one starts again. A compacted row shows
the load status of every folder in it. The API reference has the full
reload rules.

```dart
Future<DirectoryTreeController<FileSystemEntity>> openLocalFolder(
  String path,
) async {
  const loader = FileSystemTreeLoader(); // includeHidden: false by default
  final tree = await loader.loadTree(path); // the folder and its children
  return DirectoryTreeController(
    tree: tree,
    expansion: ExpansionState.withExpanded(tree.roots),
    loadChildren: loader.loadChildren,
    onLoadError: (directory, error, stackTrace) =>
        debugPrint('Cannot open $directory: $error'),
  );
}
```

Each node's `data` is its `File`, `Directory`, or `Link`.
`FileSystemTreeLoader(includeHidden:, followLinks:, skip:)` configures it.

## Views and input

- `DirectoryTreeView<T>(controller: ...)`: the tree with clicks, hover,
  keyboard, type-ahead, checkboxes, menus, and drag and drop built in.
  `DirectoryTreePanel<T>` adds a toolbar (title, `actions`, expand all,
  collapse all) and a search field (Ctrl+F, or Cmd+F on macOS, focuses
  it). Both scroll and need a bounded height (`Expanded`, `SizedBox`,
  a `Scaffold` body).
- Click: focuses and selects the row and toggles a folder. Shift-click
  extends from the anchor; Ctrl-click (Cmd-click on macOS) toggles.
  Double-click and Enter activate: a folder toggles, then `onActivate`
  runs, for files and folders. Clicks act on pointer up, never delayed.
- `selectOnTap: false`: clicks only focus (the app or the checkboxes own
  the selection; the context menu then opens without selecting).
  `expandOnTap: false`: folders open with the arrow, keys, and
  double-click. `onRowTap` runs after the built-in handling.
- `selectionFollowsFocus: false`: arrows, Home, End, page keys, and
  type-ahead move the focus without selecting; Space toggles.
- `autofocus` defaults to false. The keys act only while the tree has
  keyboard focus; a click on a row gives it focus.
- Rows are a fixed height (`rowExtent`), so a row widget must fit in it.

Default keys (from `DirectoryTreeShortcuts.defaults(platform:,
textDirection:)`): arrows move and select; Shift extends; Ctrl+arrows move
without selecting (not on macOS); Right/Left open or enter, close or go to
parent (swapped in right-to-left layouts); `*` opens the subtree; Enter
activates; Space toggles the selection (the check in checks mode); Ctrl+A
(Cmd+A on macOS and iOS) selects all; Escape clears; Shift+F10 and the
menu key open the context menu; Cmd+Up and Cmd+Down go to the parent and
activate on macOS. Change bindings by spreading the defaults into
`shortcuts`; change what a key does by mapping its intent type (such as
`ActivateTreeNodeIntent` or `MoveTreeFocusIntent`) in an `Actions` widget
above the view.

```dart
Widget treeWithBackspace(
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
      const SingleActivator(LogicalKeyboardKey.backspace):
          const MoveTreeFocusIntent(TreeFocusMove.parent),
    },
  );
}
```

## Menus, drag and drop, checkboxes, picker

- `contextMenuBuilder: (context, details) => [MenuItemButton(...)]`.
  `details.nodes` is the whole selection when the menu opened on a
  selected row, else just that row's node; `details.row` is the row.
  Return `[]` for no menu. It opens on secondary click, touch long press,
  Shift+F10, and the menu key. For another design system, leave it out
  and use `onRowSecondaryTap: (row, globalPosition) => ...`. On the web,
  call `BrowserContextMenu.disableContextMenu()` (from
  `package:flutter/services.dart`) while a tree with a menu is on screen
  and `BrowserContextMenu.enableContextMenu()` when it leaves; the package
  never calls them because the setting is page-wide.
- `dragAndDrop: DirectoryTreeDragAndDrop(onDrop: (details) => ...)`. The
  package never moves data: `onDrop` gets `details.nodes` and
  `details.target` (a `DirectoryNode`), moves the data, then assigns the
  new tree (or uses `updateTree`). `canDrag`, `canDrop`, `autoExpandDelay`
  (700 ms), and `feedbackBuilder` are optional. Drag and drop has no
  keyboard gesture, so also offer moves in the context menu.
- `checkboxMode: DirectoryTreeCheckboxMode.checks` shows tri-state boxes
  bound to `controller.checks` (pair it with `selectOnTap: false`);
  `DirectoryTreeCheckboxMode.selection` mirrors the highlight selection.
- `showDirectoryTreePicker(context:, tree:, mode:, multiple:,
  initialSelection:, initialExpansion:, title:, confirmLabel:)` returns
  `null` on cancel, otherwise a non-empty `List<TreeNode<T>>` in display
  order. `mode` defaults to `DirectoryTreePickerMode.files`, which never
  picks folders; use `directories` or `any`. With `multiple: true`: files
  mode returns the checked files, directories mode the folders whose own
  box is checked, any mode the outermost checked nodes. The picker keeps
  its own state and never changes your controller. `DirectoryTreePicker`
  is the same body without the dialog (`onChanged`, `onConfirm`).

```dart
Future<List<NodeId>?> pickFolders(
  BuildContext context,
  DirectoryTree<Object?> tree,
) async {
  final picked = await showDirectoryTreePicker(
    context: context,
    tree: tree,
    mode: DirectoryTreePickerMode.directories,
    multiple: true,
    title: 'Choose folders',
  );
  return picked?.map((node) => node.id).toList(); // null: cancelled
}
```

## Theming and custom rows

- App-wide: `ThemeData(extensions: const [DirectoryTreeThemeData(...)])`.
  One subtree: `DirectoryTreeTheme(data: ..., child: ...)`.
  `DirectoryTreeTheme.of(context)` resolves every field (Material 3
  defaults, then the extension, then the nearest `DirectoryTreeTheme`).
- `rowExtent` default: 36 adjusted by visual density (28 with
  `VisualDensity.compact`, the desktop default), at least 48 where
  Material pads tap targets (Android, iOS, Fuchsia), and taller under a
  larger text scale. A `rowExtent` you set is used as given.
- `selectedColor` applies while the tree has keyboard focus and
  `inactiveSelectedColor` otherwise: set both for one color. `guideStyle`
  is `DirectoryTreeGuideStyle.indent` (default), `connectors`, or `none`.
  `animationDuration: Duration.zero` turns animations off.
  `iconSet: DirectoryTreeIconSet.material.copyWith(extensions: {...})` maps
  more extensions or file names to icons.
- `rowBuilder: (context, details) => DirectoryTreeRow(details: details,
  trailing: ...)` replaces one slot (`expander`, `leading`, `title`,
  `trailing`) and keeps the rest. For a fully custom row use
  `DirectoryTreeExpander(details: details)`,
  `DirectoryTreeCheckbox(details: details)`, `DirectoryTreeLabel`, and
  `DirectoryTreeIndentGuides`. Build only from `details` (`row`,
  `isSelected`, `isFocused`, `hasFocus`, `isHovered`, `checkState`,
  `loadStatus`, `isExpandable`, `matchRanges`, `controller`): the builder
  runs only when a row's details change. The row's semantics node already
  carries the label, so wrap your own label text in `ExcludeSemantics`.
- Slivers: build what `DirectoryTreeView` builds, outermost first: an
  optional `DirectoryTreeDragAndDropScope`, the `DirectoryTreeContextMenu`,
  the `DirectoryTreeKeyboard`, and a `CustomScrollView` holding a
  `SliverDirectoryTree`. Keep the menu host above the keyboard widget:
  Shift+F10 and the menu key reach it only from there, and a host inside
  the keyboard opens only from secondary taps. The sliver opens no menu by
  itself: call `open(row: row, globalPosition: globalPosition)` on the
  host's state from its `onRowSecondaryTap`, through
  `DirectoryTreeContextMenu.maybeOf<T>(context)` with a context below the
  host (a `Builder`) or a `GlobalKey<DirectoryTreeContextMenuState<T>>` kept
  in a `State`. With drag and drop, set the sliver's
  `rowDecorator: DirectoryTreeDragAndDropScope.decorateRow` and
  `secondaryTapOnLongPress: false`, and open the menu from the scope's
  `onLongPressWithoutDrag` through the key, as `DirectoryTreeView` does:
  the scope sits above the host, so `maybeOf` finds nothing there and the
  touch menu silently never opens. Give the keyboard and the sliver the
  same `onActivate`. The API reference shows both stacks
  (`composedExplorer`, and `DraggableExplorer` with drag and drop).

## Accessibility

Each row is one semantics node with its label, states, level hint, and
actions; the API reference lists the labels to translate.

## Performance rules for large trees

- Focus moves and `select` cost O(log rows), `toggleSelected`
  O(selection size + log rows), and `extendSelection` O(range size + log
  rows); the view rebuilds only the rows whose details changed.
- Opening or closing one folder costs O(log rows + the rows that appear or
  disappear) without calling the filter, plus copying the row list, which
  grows with the visible rows, and the expansion state, which grows with
  its exceptions (every folder whose state differs from the default,
  visible or not).
- Full passes happen only for a new tree, a query or filter change,
  `compactFolders`/`showRoots` changes, and bulk commands (`expandAll`,
  `selectAll`, `checkAll`).
- Do not rebuild the `DirectoryTree` or assign `query` per frame; debounce
  typing (the search field does). Do not call `expandAll()` on a huge
  tree in response to input.
- `row.label`, `row.guides`, and `row.chain` are computed on every read:
  read each once per build into a local, never in a loop.
- Never search `controller.rows` linearly per row in a build; use
  `rows.indexOfNode(id)` or `rows.rowOf(id)`.
- For derived UI (a row count, a status bar), use a `ListenableBuilder`
  on the controller and compare the value you need
  (`identical(controller.selection, last)`) to skip work.

## Verification

After edits: `flutter analyze` and `flutter test`. Treat every
`unused_result` warning on `ExpansionState` or `SelectionState` as a bug: a
state change that never happened. Widget tests must give the view a
bounded size and tap a row (or pass `autofocus: true`) before sending keys.

## Failure handling

- A command does nothing: the id is not in the tree (check
  `controller.tree.contains(id)` and the path's case), or a new state
  value was computed and dropped.
- "Vertical viewport was given unbounded height": put the view or panel in
  an `Expanded` or a `SizedBox`.
- Icons render as boxes: add `uses-material-design: true`.
- The web build fails on `dart:io`: `io.dart` is imported in web code.
- Keys do nothing: the tree lacks keyboard focus, a text field has it, or
  a `DirectoryTreeKeyboard` wraps a `DirectoryTreeView` (two keyboard
  layers; remove the wrapper).
- Two menus on a right click in a browser: see `BrowserContextMenu` above.

## Full API tables

Every constructor parameter, theme field, intent, and callback signature
is in [references/api-quick-reference.md](references/api-quick-reference.md).
