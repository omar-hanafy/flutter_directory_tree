# Migrating from flutter_directory_tree 1.x to 2.0.0

2.0.0 is a rewrite on top of directory_tree 2.0.0. In 1.x the app wired
most of the behavior itself: `nodeBuilder` handled clicks,
`SelectionShortcuts` handled keys, and the controller exposed two mutable
sub-controllers for expansion and selection, keyed by generated string ids.

In 2.0.0:

- One `DirectoryTreeController<T>` holds the tree and every kind of view
  state as immutable values: expansion, selection, checkboxes, keyboard
  focus, search, and lazy-loading status. Each command notifies once.
- Node ids are `NodeId`s, the canonical path of the node, so they survive
  rebuilds and can be stored.
- `DirectoryTreeView<T>` handles clicks, double-clicks, secondary taps,
  long presses, hover, the keyboard, type-ahead, checkboxes, context menus,
  and drag and drop. A row builder only draws.
- Opening and closing folders updates the rows incrementally, and focus or
  selection changes rebuild only the rows they touch.
- The theme is a `ThemeExtension` with Material 3 defaults.

What stayed the same, in concept: a controller you create and dispose, a
`DirectoryTreeView` and a `DirectoryTreePanel`, a toolbar, a picker
dialog, `DirectoryTreeTheme`, and state kept by id when the data changes.

The package still re-exports `package:directory_tree`, whose own API also
changed. Its [migration guide](https://github.com/omar-hanafy/directory_tree/blob/main/MIGRATION.md)
covers `TreeBuilder`, `TreeData`, `TreeEntry`, `ExpansionSet`,
`SelectionSet`, and the other core types in detail; the
[re-exported core symbols](#re-exported-core-symbols) section below
summarizes them.

## dart fix

`dart fix --apply` handles the renames whose meaning and type did not
change, seven transforms in all:

| 1.x | 2.0.0 |
| --- | --- |
| `DirectoryTreeThemeData(indent: ...)` and `copyWith(indent: ...)` | `indentWidth:` |
| `DirectoryTreeThemeData(rowHeight: ...)` and `copyWith(rowHeight: ...)` | `rowExtent:` |
| `ListDiff.removeIndicesDesc` | `ListDiff.removedIndices` |
| `ListDiff.insertIndicesAsc` | `ListDiff.insertedIndices` |
| `TreeEntry.fullPath` | `TreeEntry.path` |

The last three are directory_tree renames. directory_tree ships the same
fixes, but they only reach files that import `package:directory_tree`, so
this package repeats them for files that import only
`package:flutter_directory_tree`. A file that imports both gets one edit.

`dart fix` leaves these to you:

- Reads of the theme fields `indent` and `rowHeight`. In 2.0.0 every theme
  field is nullable, so a rename would not compile. Read the resolved
  value instead: `DirectoryTreeTheme.of(context).indentWidth!` and
  `DirectoryTreeTheme.of(context).rowExtent!`.
- Super parameters in a subclass of the theme (`super.indent`,
  `super.rowHeight`). The subclass's own parameter names are its public
  API, so rename them to `super.indentWidth` and `super.rowExtent` by hand.
- Code whose receiver type `dart fix` cannot resolve, such as
  `diffVisibleNodes(a, b).removeIndicesDesc`: `diffVisibleNodes` no longer
  exists. Replace the removed call first, then run `dart fix --apply`
  again.

Everything else needs a manual change. Most 1.x APIs took string ids and
mutable sub-controllers, and their replacements take `NodeId`s and
immutable values. A rename that compiled would often do nothing: for
example `controller.selection.clear()` compiles in 2.0.0 and discards the
cleared state (see [Behavior changes](#behavior-changes)).

## Before and after

Each pair shows the 1.x code first, then the 2.0.0 code.

### A controller and a view

```dart
// flutter_directory_tree 1.x
final controller = DirectoryTreeController(
  data: TreeBuilder().build(
    entries: const [
      TreeEntry(id: 'main', name: 'main.dart', fullPath: '/repo/lib/main.dart'),
      TreeEntry(id: 'readme', name: 'README.md', fullPath: '/repo/README.md'),
    ],
  ),
  selection: SelectionController(mode: SelectionMode.multi),
);

final view = SelectionShortcuts(
  controller: controller,
  onActivate: (node) => debugPrint('open ${node.sourcePath}'),
  child: DirectoryTreeView(
    controller: controller,
    nodeBuilder: (context, node, state) => TreeNodeTile(
      node: node,
      state: state,
      title: Text(node.name),
      onTap: () => controller.selectOnly(node.id),
    ),
  ),
);
```

```dart
final controller = DirectoryTreeController(
  tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/README.md']),
);

final view = DirectoryTreeView(
  controller: controller,
  onActivate: (row) => debugPrint('open ${row.node.path}'),
);
```

The 2.0.0 view selects on click, opens folders, and handles the keyboard
without a row builder or a shortcuts wrapper. 1.x started with every
folder open and every file selected (the `TreeBuilder` defaults); 2.0.0
starts collapsed with nothing selected. See
[Initial state from node flags](#initial-state-from-node-flags) to keep
the old start.

### Refreshing the data

```dart
// flutter_directory_tree 1.x
controller.rebuild(nextData); // keeps expansion and selection by id
controller.rebuild(nextData, tryPreserveState: false); // starts over
```

```dart
controller.tree = next; // keeps expansion, selection, checks, and focus

// Starting over takes three commands (three notifications).
controller
  ..tree = next
  ..expansion = const ExpansionState.collapsed()
  ..clearSelection();
```

### Selection

```dart
// flutter_directory_tree 1.x
controller.selectOnly(id);
controller.selectRange(anchorId: id, toId: otherId);
final ids = controller.selection.selectedIds;
controller.selection.clear();
```

```dart
controller.select(id); // also focuses the row and scrolls to it
controller.extendSelection(other); // from the anchor that select set
final ids = controller.selection.selected;
controller.clearSelection();
```

### Revealing a node

```dart
// flutter_directory_tree 1.x
await controller.revealAndScroll(
  nodeId: id,
  select: true,
  scrollController: scrollController,
  rowExtent: 28,
);
```

```dart
controller.reveal(
  id,
  select: true,
  alignment: 0, // the row at the top, as 1.x did; null scrolls minimally
  duration: const Duration(milliseconds: 220),
);
```

The view the controller is shown in scrolls; there is no scroll controller
or row extent to pass. `reveal` opens only the ancestors (1.x also opened
a target folder) and notifies once.

### The picker

```dart
// flutter_directory_tree 1.x
final ids = await showDirectoryTreePicker(
  context: context,
  controller: controller,
  allowMultiple: true,
  foldersOnly: true,
);
```

```dart
final nodes = await showDirectoryTreePicker(
  context: context,
  tree: controller.tree,
  mode: DirectoryTreePickerMode.directories,
  multiple: true,
  initialSelection: controller.selection.selected,
  initialExpansion: controller.expansion,
);
final ids = nodes?.map((node) => node.id).toSet() ?? const <NodeId>{};
```

The 1.x picker returned an empty set on cancel and changed the selection,
expansion, and search of the controller you passed. The 2.0.0 picker
returns `null` on cancel, returns nodes, and works on its own copy of the
state.

### The theme

```dart
// flutter_directory_tree 1.x
const theme = DirectoryTreeThemeData(
  rowHeight: 24,
  indent: 12,
  indentGuides: false,
  selectionColor: Color(0x332196F3),
  roundedCorners: false,
);
```

```dart
const theme = DirectoryTreeThemeData(
  rowExtent: 24, // dart fix
  indentWidth: 12, // dart fix
  guideStyle: DirectoryTreeGuideStyle.none,
  selectedColor: Color(0x332196F3),
  inactiveSelectedColor: Color(0x332196F3),
  rowBorderRadius: BorderRadius.zero,
);
```

## API mapping

Every public declaration of flutter_directory_tree 1.0.0 and its 2.0.0
replacement. "Removed" names the alternative. In 2.0.0, every method that
took a `String` id takes a `NodeId`: get one from `tree.idOf(path)`,
`node.id`, or `row.id`.

### DirectoryTreeController

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `DirectoryTreeController` | `DirectoryTreeController<T>` | `T` is the type of the tree's entry data. |
| `DirectoryTreeController(data: ...)` | `tree:` (`DirectoryTree<T>?`) | Optional; an empty tree by default. Build the tree with `DirectoryTree.build` or `DirectoryTree.fromPaths`. |
| `DirectoryTreeController(expansions: ...)` | `expansion:` (`ExpansionState`) | Default `ExpansionState.collapsed()`. `ExpansionController(initiallyExpanded: ids)` becomes `ExpansionState.withExpanded(ids)`. |
| `DirectoryTreeController(selection: ...)` | `selection:` (`SelectionState`) | Default: empty, `SelectionMode.multiple`. 1.x defaulted to single mode. |
| `DirectoryTreeController(flattenStrategy: ...)` | Removed | Sibling order is a tree option, `TreeOptions(order: ...)`; see [Sorting](#sorting-at-display-time). Filters go to `query` and `filter`. |
| `DirectoryTreeController(seedSelectionFromCore: ...)` | Removed | Nodes carry no selected flag. Pass `selection:` or `checks:`. |
| `autoExpandVisibleRoot` | Removed | There is no visible root. Pass `expansion: ExpansionState.withExpanded(tree.roots)` to open the top-level folders. |
| `data` | `tree` | Settable: assigning a new tree replaces `rebuild`. `data.nodes[id]` becomes `tree[id]`, `data.nodes.values` becomes `tree.nodes`. |
| `expansions` | `expansion`, plus the controller's expansion commands | Member by member below. |
| `selection` | `selection` (`SelectionState`), plus the controller's selection commands | Same name, different type. Member by member below. |
| `filterQuery` | `query` | Not trimmed, and the syntax grew: globs, quoted phrases, `type:`, `path:`, and `ext:` lists that match files only. A search can be collapsed by the user, and clearing it restores the folders that were open before. |
| `visibleNodes` | `rows` (`TreeRows<T>`, a `List<TreeRow<T>>`) | See `VisibleNode` below for the fields. |
| `rebuild(next, tryPreserveState: true)` | `tree = next`, `updateTree((builder) => ...)` | State is always kept by id. A checked leaf that became a folder with children stays checked as a whole, and the focus moves to the nearest surviving ancestor. |
| `rebuild(next, tryPreserveState: false)` | `tree = next`, then `expansion = const ExpansionState.collapsed()` and `clearSelection()` | |
| `rebuild(next, reseedFromCore: true)` | Removed | Compute the states and assign them; see [Initial state from node flags](#initial-state-from-node-flags). |
| `reveal(nodeId: ..., virtualPath: ..., select: ...)` | `reveal(id, {focus, select, scroll, alignment, duration, curve})`, `revealPath(path, ...)` | Synchronous, returns whether the node has a row. Focuses and scrolls by default; pass `focus: false, scroll: false` for the 1.x behavior. `virtualPath` (`/tree/...`) is not a 2.0.0 path: pass the real path to `revealPath`. |
| `revealAndScroll(...)` | `reveal(id, alignment: 0, duration: ...)` | See [Revealing a node](#revealing-a-node). |
| `expand(id)` | `expand(id)` | On a lazily loaded folder this starts loading its children. |
| `expand(id, recursive: true)` | `expandSubtree(id)` | |
| `collapse(id)` | `collapse(id)` | |
| `collapse(id, recursive: true)` | `collapseSubtree(id)` | |
| `toggle(id)` | `toggleExpansion(id)` | |
| `selectOnly(id)` | `select(id, {focus})` | Also focuses and scrolls to the row unless `focus: false`. Ignores ids that the `selectable` predicate rejects. |
| `toggleSelection(id)` | `toggleSelected(id, {focus})` | In single mode, toggling the selected id clears it; 1.x kept it selected. |
| `selectRange(anchorId: ..., toId: ...)` | `extendSelection(id, {focus})` | Uses the anchor that `select` and `toggleSelected` set. For an explicit anchor: `select(anchor, focus: false)` then `extendSelection(to)`. |
| `clearSelection()` | `clearSelection()` | Also clears the anchor. |
| `selectSubtree(id)` | `setChecked(id, checked: true)` | Checks live in `checks`, separate from the selection. See [Checkboxes](#checkboxes-on-the-selection). |
| `deselectSubtree(id)` | `setChecked(id, checked: false)` | |
| `nodeIdForEntryId(entryId)` | `tree.idOf(path)` | Ids come from paths. See [Looking up nodes by your own keys](#looking-up-nodes-by-your-own-keys). |
| `revealByEntryId(entryId, select: ...)` | `revealPath(path, select: ...)` | |
| `indexOfNode(id)` | `rows.indexOfNode(id)` | Also finds a folder inside a compacted row. |
| `dispose()` | `dispose()` | Also drops loads still running. |

New in 2.0.0: `focusedId`, `focusedRow`, `focus`, `moveFocus`,
`selectAll`, `selectionMode`, `checks` and the check commands,
`expandAll` and `collapseAll` on the controller, `caseSensitiveQuery`,
`filter`, `revealMatches`, `compactFolders`, `showRoots`,
`matchRangesOf`, lazy loading (`loadChildren`, `loadStatusOf`,
`reloadChildren`), `ensureVisible`, `globalRowRect`, and `lastRowsChange`.

### ExpansionController (removed)

The controller holds an immutable `ExpansionState` in `expansion`; listen
to the controller itself.

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `ExpansionController` | `DirectoryTreeController.expansion` (`ExpansionState`) | |
| `ExpansionController(initiallyExpanded: ids)` | `ExpansionState.withExpanded(ids)` | |
| `ExpansionController(state: set)` | `ExpansionState.withExpanded(ids)` | There is no shared live object. |
| `performBatch(updates)` | Compute a state and assign it once | `controller.expansion = controller.expansion.expandAll(ids).collapse(other);` |
| `isExpanded(id)` | `controller.isExpanded(id)` | The effective state on screen, including folders a search opened. `controller.expansion.isExpanded(id)` reads the requested state. |
| `setExpanded(id, true)` | `controller.expand(id)`, `controller.collapse(id)` | Or `expansion = expansion.setExpanded(id, expanded: true)`. |
| `toggle(id)` | `controller.toggleExpansion(id)` | |
| `expandAll(ids)` | `controller.expansion = controller.expansion.expandAll(ids)` | Not `controller.expandAll()`, which opens every folder. |
| `collapseAll()` | `controller.collapseAll()` | The top-level rows stay visible; 1.x also closed the visible root. |
| `expandedIds` | `expansion.exceptions` (collapsed by default), `expansion.toJson()` | A state can also be expanded by default with collapsed exceptions. |
| `retainWhere(test)` | Automatic when the tree changes; `ExpansionState.prune(tree)` | |
| `state` | `controller.expansion` | |

### SelectionController (removed)

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `SelectionController` | `DirectoryTreeController.selection` (`SelectionState`) | |
| `SelectionController(mode: ..., state: ...)` | `SelectionState.empty(mode: ...)`, `SelectionState(mode: ..., selected: ..., anchor: ...)` | |
| `mode` | `controller.selectionMode` | Setting it notifies. Switching to single keeps the anchor if it is selected, else the only selected id, else nothing. |
| `isSelected(id)` | `controller.isSelected(id)` | |
| `selectedIds` | `selection.selected` (`Set<NodeId>`), `controller.selectedNodes` (nodes in display order) | |
| `selectOnly(id)` | `controller.select(id)` | |
| `toggle(id)` | `controller.toggleSelected(id)` | |
| `clear()` | `controller.clearSelection()` | `controller.selection.clear()` compiles and does nothing. |
| `selectRange(order, anchor, to)` | `controller.extendSelection(to)` | Or `selection = selection.extendTo(to, order)`. |
| `addAll(ids)` | `controller.selection = controller.selection.addAll(ids)` | In single mode only the last id is kept. |
| `removeAll(ids)` | `controller.selection = controller.selection.removeAll(ids)` | |
| `retainWhere(test)` | Automatic when the tree changes; `SelectionState.prune(tree)` | |
| `performBatch(updates)` | Compute a state and assign it once | |
| `state` | `controller.selection` | |

### tree_diff.dart

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `schedulePreserveScrollOffset(...)` | Removed | `SliverDirectoryTree` keeps the first visible row in place on every change, in the same frame. A list of your own can read `controller.lastRowsChange` or use `ListDiff.compute`. |

### Context menus

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `NodeAction` | A `MenuItemButton` returned by a `DirectoryTreeMenuBuilder<T>` | `label` becomes `child: Text(...)`, `icon` becomes `leadingIcon`, `onInvoke(node)` becomes `onPressed`, reading `details.row` or `details.nodes`. |
| `ContextMenuDelegate` | `DirectoryTreeView(contextMenuBuilder: ...)`, or `onRowSecondaryTap` for another menu system | See [Menus from other design systems](#menus-from-other-design-systems). |
| `ContextMenuDelegate.actionsFor(node)` | The builder's return value | An empty list opens no menu, as in 1.x. |
| `ContextMenuDelegate.wrapWithMenu(...)` | Removed | The view wires the menu itself. |
| `MaterialContextMenuDelegate(provider)` | `contextMenuBuilder: (context, details) => [...]` | 2.0.0 uses `MenuAnchor` instead of `showMenu`, selects the row first if it was not selected (unless `selectOnTap` is false), passes the whole selection in `details.nodes` when the row was selected, opens from Shift+F10 and the context menu key, and returns focus to the tree when it closes. |

### Icons

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `IconProvider` | `DirectoryTreeThemeData(iconSet: DirectoryTreeIconSet(...))`, or `DirectoryTreeRow(leading: ..., trailing: ...)` in a `rowBuilder` | See [Icons from node data](#icons-from-node-data). |
| `IconProvider.leadingIcon` | `DirectoryTreeRow(leading: ...)` | Replaces the icon. |
| `IconProvider.trailingIcon` | `DirectoryTreeRow(trailing: ...)` | |
| `MaterialIconProvider` | `DirectoryTreeIconSet.material` (the default) | 2.0.0 shows an open folder icon for open folders, matches whole file names (`pubspec.yaml`) and multi-part extensions (`tar.gz`), and colors icons with `iconColor` and `folderIconColor`. There is no virtual-file or root icon. Size stays 18. The app needs `uses-material-design: true`. |

### Row rendering

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `NodeVisualState` | `DirectoryTreeRowDetails<T>` | `isExpanded` becomes `details.row.isExpanded`, `isSelected` becomes `details.isSelected`, `depth` becomes `details.row.depth`, `isHovered` becomes `details.isHovered` (always false in 1.x). 1.x `isFocused` meant "selected while the tree has focus": use `details.isSelected && details.hasFocus`; 2.0.0 `details.isFocused` is the keyboard cursor row. `contentIndent` is removed. |
| `NodeBuilder` | `DirectoryTreeRowBuilder<T>` | `(context, node, state)` becomes `(context, details)`. The builder draws the whole row: return `DirectoryTreeRow(details: details, title: ...)` to keep the indentation, guides, arrow, and icon. |
| `ExpanderBuilder` | `DirectoryTreeRow(expander: ...)` | See [A custom expander](#a-custom-expander). |
| `TreeNodeTile` | `DirectoryTreeRow<T>` | |
| `TreeNodeTile(node: ..., state: ...)` | `DirectoryTreeRow(details: ...)` | |
| `TreeNodeTile(leading:, title:, trailing:)` | `leading:`, `title:`, `trailing:` | |
| `TreeNodeTile(subtitle: ...)` | Removed | Rows are one line high; see [Subtitles](#subtitles). |
| `TreeNodeTile(onTap: ..., onDoubleTap: ...)` | The view's `onRowTap` and `onActivate` | The view selects on click and activates on the second click within `kDoubleTapTimeout`, on pointer up; 1.x fired `onTap` on pointer down when `onDoubleTap` was set. |
| `TreeNodeTile(onTertiaryTap: ...)` | Removed | See [Middle-click](#middle-click). |

### Intents and actions

2.0.0 intents act on the focused row (`controller.focusedRow`), not on an
id they carry. For any other node, call the controller.

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `ExpandNodeIntent(id)` | `ExpandTreeNodeIntent()`, or `controller.expand(id)` | |
| `ExpandNodeIntent(id, recursive: true)` | `ExpandTreeSubtreeIntent()`, or `controller.expandSubtree(id)` | |
| `CollapseNodeIntent(id)` | `CollapseTreeNodeIntent()`, or `controller.collapse(id)` | The intent collapses an open row, or moves to the parent of a closed one. |
| `CollapseNodeIntent(id, recursive: true)` | `controller.collapseSubtree(id)` | |
| `ToggleNodeIntent(id)` | `controller.toggleExpansion(id)` | `ActivateTreeNodeIntent()` toggles a focused folder, then calls `onActivate`. |
| `RevealNodeIntent(...)` | `controller.reveal(id, select: ...)`, `controller.revealPath(path, select: ...)` | |
| `SelectOnlyIntent(id)` | `controller.select(id)` | `MoveTreeFocusIntent` moves the focus and selects. |
| `ClearSelectionIntent()` | `ClearTreeSelectionIntent()` | Handled by the view (Escape); 1.x needed an app-registered action. |
| `DirectoryTreeAction<T>` | Removed | The view registers its own actions. To replace one, map the intent type in an `Actions` widget above the view. |

### Keyboard

`SelectionShortcuts` is gone: `DirectoryTreeView` contains a
`DirectoryTreeKeyboard`. Remove the wrapper; wrapping a 2.0.0 view in a
`DirectoryTreeKeyboard` adds a second keyboard layer with its own focus
node.

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `SelectionShortcuts(controller: ..., child: ...)` | `DirectoryTreeView(controller: ...)` | |
| `SelectionShortcuts(onActivate: ...)` | `DirectoryTreeView(onActivate: ...)` | Receives a `TreeRow<T>`. Called for files and folders, after a folder toggles; 1.x called it only for rows without children. |
| `SelectionShortcuts(autofocus: ...)` | `DirectoryTreeView(autofocus: ...)` | Default `false`; 1.x defaulted to `true`. |
| `SelectionShortcuts(pageJumpSize: ...)` | Removed | Pages are as tall as the viewport. See [A fixed page size](#a-fixed-page-size). |

The bindings changed too:

| Keys | 1.x | 2.0.0 |
| --- | --- | --- |
| Up, Down | Move and select | Move and select |
| Shift+Up, Shift+Down | Extend from the keyboard anchor (Shift+Up oscillated) | Extend from the anchor |
| Ctrl+Up, Ctrl+Down | Nothing | Move without selecting (not on macOS) |
| Left, Right | Close or go to the parent, open or go to the first child | The same, swapped in right-to-left layouts |
| Home, End, Page Up, Page Down | First, last, 10 rows; Shift extends | First, last, one viewport; Shift extends, Ctrl keeps the selection |
| Enter, Numpad Enter | A folder with children toggles; otherwise `onActivate`, or toggle the selection | A folder toggles, then `onActivate` runs for any row |
| Space | Toggle the selection | Toggle the selection, or the check in checks mode; Ctrl+Space too |
| Ctrl+A, Cmd+A | Both on every platform | Ctrl+A off Apple platforms, Cmd+A on them |
| Escape | Nothing | Clear the selection |
| `*`, Numpad *, Numpad +, Numpad - | Nothing | Open the subtree, open, close |
| Shift+F10, context menu key | Nothing | Open the context menu |
| Cmd+Down, Cmd+Up (macOS) | Nothing | Activate, go to the parent |
| Letters and digits | Nothing | Type-ahead find |

### Picker, services, theme, and widgets

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `showDirectoryTreePicker(...)` | `showDirectoryTreePicker<T>(...)` | Returns `Future<List<TreeNode<T>>?>`: `null` on cancel (1.x returned an empty set), nodes otherwise. |
| `showDirectoryTreePicker(controller: c)` | `tree: c.tree, initialSelection: c.selection.selected, initialExpansion: c.expansion` | The picker keeps its own state; 1.x changed the controller you passed. |
| `showDirectoryTreePicker(allowMultiple: ...)` | `multiple:` | With several picks, files mode returns the checked files and any mode the outermost checked nodes; 1.x returned exactly the selected ids. |
| `showDirectoryTreePicker(foldersOnly: true)` | `mode: DirectoryTreePickerMode.directories` | |
| `showDirectoryTreePicker(foldersOnly: false)` | `mode: DirectoryTreePickerMode.any` | The 2.0.0 default, `files`, rejects folders, which 1.x accepted. |
| `showDirectoryTreePicker(confirmLabel: ..., title: ...)` | `confirmLabel:`, `title:` | Both default to no title and the localized OK label; 1.x defaulted both to `'Select'`. |
| `revealAndSelect(controller, nodeId: ..., virtualPath: ...)` | `controller.reveal(id, select: true)`, `controller.revealPath(path, select: true)` | Also focuses and scrolls. |
| `folderSelection(controller, folderId)` | `controller.checkStateOf(id)` | Reads `checks`. Over the highlight selection: `controller.selection.checkStateOf(controller.tree, id)`. Empty folders count as leaves. |
| `DirectoryTreeDefaults.themed(context, base: ...)` | `DirectoryTreeTheme.of(context)` | Every field resolves from the Material 3 color scheme and text theme. |
| `DirectoryTreeThemeData` | `DirectoryTreeThemeData` | Now a `ThemeExtension` with nullable fields, value equality, `lerp`, `merge`, and `fallback`. |
| `DirectoryTreeThemeData(rowHeight: ...)` | `rowExtent:` | `dart fix`. The default is 36 adjusted by the visual density (28 for compact), not 28. |
| `DirectoryTreeThemeData.rowHeight` | `DirectoryTreeTheme.of(context).rowExtent!` | |
| `DirectoryTreeThemeData(indent: ...)` | `indentWidth:` | `dart fix`. Same default, 16. |
| `DirectoryTreeThemeData.indent` | `DirectoryTreeTheme.of(context).indentWidth!` | |
| `DirectoryTreeThemeData(indentGuides: ...)` | `guideStyle:` | 1.x drew no guides either way. 2.0.0 draws `DirectoryTreeGuideStyle.indent` lines by default; `DirectoryTreeGuideStyle.none` keeps the 1.x look. |
| `DirectoryTreeThemeData(hoverColor: ...)` | `hoverColor:` | Mouse only. |
| `DirectoryTreeThemeData(selectionColor: ...)` | `selectedColor:` and `inactiveSelectedColor:` | The first applies while the tree has keyboard focus, the second while it does not. Set both for one color. |
| `DirectoryTreeThemeData(focusColor: ...)` | `focusedBorderColor:` | 2.0.0 outlines the keyboard cursor row instead of filling selected rows. |
| `DirectoryTreeThemeData(guideColor: ...)` | `guideColor:` | 1.x ignored it. |
| `DirectoryTreeThemeData(animationDuration: ...)` | `animationDuration:` | Animates the arrows and the rows a folder reveals; default 150 ms; `Duration.zero` turns animations off. |
| `DirectoryTreeThemeData(roundedCorners: ...)` | `rowBorderRadius:` | `false` becomes `BorderRadius.zero`; `true` is the default radius of 4. |
| `DirectoryTreeThemeData.copyWith(...)` | `copyWith(...)` | With the new field names. |
| `DirectoryTreeTheme` | `DirectoryTreeTheme` | Same constructor. `of` merges the defaults, the theme extension, and the nearest `DirectoryTreeTheme`, so every field resolves. |
| `DirectoryTreePanel(controller: ..., nodeBuilder: ...)` | `DirectoryTreePanel<T>(controller: ..., rowBuilder: ...)` | Takes every parameter of `DirectoryTreeView` plus `title`, `actions`, `toolbar`, `showToolbar`, `showSearch`, and `searchHintText`. |
| `DirectoryTreePanel(toolbar: ...)` | `toolbar:` | |
| `DirectoryTreePanel(shortcutsAutofocus: ...)` | `autofocus:` | Default `false`; 1.x defaulted to `true`. |
| `DirectoryTreeToolbar(controller: ...)` | `DirectoryTreeToolbar(controller: ...)` and `DirectoryTreeSearchField(controller: ...)` | The 2.0.0 toolbar has no search field; put a `DirectoryTreeSearchField` below it, or use `DirectoryTreePanel`. |
| `DirectoryTreeToolbar(hintText: ...)` | `DirectoryTreeSearchField(hintText: ...)` | Defaults to the localized "Search". |
| `DirectoryTreeToolbar(showExpandCollapse: false)` | `DirectoryTreeToolbar(showExpandAll: false, showCollapseAll: false)` | |
| `DirectoryTreeView(controller: ...)` | `DirectoryTreeView<T>(controller: ...)` | |
| `DirectoryTreeView(nodeBuilder: ...)` | `rowBuilder:` | Optional; the default is `DirectoryTreeRow`. |
| `DirectoryTreeView(expanderBuilder: ...)` | `DirectoryTreeRow(expander: ...)` in a `rowBuilder` | See [A custom expander](#a-custom-expander). |
| `DirectoryTreeView(expanderSize: ...)` | `DirectoryTreeThemeData(expanderSize: ...)` | Default 20; 1.x used 24. |
| `DirectoryTreeView(expanderGap: ...)` | Removed | A custom `expander` can bring its own padding. |
| `DirectoryTreeView(contextMenuDelegate: ...)` | `contextMenuBuilder:`, `onRowSecondaryTap:` | |
| `DirectoryTreeView(scrollController: ...)` | `scrollController:` | |
| `DirectoryTreeView(padding: ...)` | `padding:` | Now an `EdgeInsetsGeometry?`. |
| `DirectoryTreeView(addAutomaticKeepAlives: ...)` | Removed | Rows hold no state worth keeping alive. |
| `DirectoryTreeView(showScrollbar: ...)` | `showScrollbar:` | A Material `Scrollbar` that shows while scrolling, or on hover on desktop, as the `ScrollbarTheme` says; 1.x always showed the thumb. Use `ScrollbarThemeData(thumbVisibility: ...)` for that. |
| `DirectoryTreeView(focusNode: ..., autofocus: ...)` | `focusNode:`, `autofocus:` | The node is the tree's keyboard focus node; in 1.x it only fed `isFocused`. |
| `DirectoryTreeView(preserveScrollOnChanges: ...)` | Removed | The first visible row always keeps its place. |
| `SelectionShortcuts` | Removed | See [Keyboard](#keyboard). |

New widgets: `SliverDirectoryTree`, `DirectoryTreeKeyboard`,
`DirectoryTreeContextMenu`, `DirectoryTreeDragAndDropScope`,
`DirectoryTreeSearchField`, `DirectoryTreePicker`, `DirectoryTreeExpander`,
`DirectoryTreeCheckbox`, `DirectoryTreeLabel`, and
`DirectoryTreeIndentGuides`, plus `FileSystemTreeLoader` in
`package:flutter_directory_tree/io.dart`.

### Re-exported core symbols

The core types changed with directory_tree 2.0.0. Its
[migration guide](https://github.com/omar-hanafy/directory_tree/blob/main/MIGRATION.md)
has the full mapping; these are the ones a Flutter app meets most.

| 1.x | 2.0.0 | Notes |
| --- | --- | --- |
| `TreeBuilder().build(entries: ...)` | `DirectoryTree.build(entries, options: TreeOptions(...))`, `DirectoryTree.fromPaths(paths)`, `DirectoryTreeBuilder` | 1.x was case-insensitive by default; pass `TreeOptions(paths: PathPolicy.caseInsensitive)` to keep that. `expandFoldersByDefault` and `selectNewFilesByDefault` become the controller's `expansion` and `selection`. |
| `TreeBuilder.rootId`, `TreeBuilder.treeRootId` | Removed | There is no synthetic root. |
| `TreeData` | `DirectoryTree<T>` | Immutable. |
| `TreeData.nodes` | `tree.nodes` (pre-order list), `tree[id]` | |
| `TreeData.rootId` | Removed | |
| `TreeData.visibleRootId` | `tree.roots`, `tree.rootNodes` | Any number of top-level nodes. |
| `TreeData.omitContainerRowAtRoot` | Removed | 2.0.0 has no container row; `showRoots: false` hides the top-level rows. |
| `TreeNode` | `TreeNode<T>` (`FileNode<T>` or `DirectoryNode<T>`) | `id` is a `NodeId`; `parentId` becomes `parent` (`null` at the top level); `childIds` becomes `DirectoryNode.children`; `type` becomes `kind`, `isFile`, `isDirectory`; `sourcePath` and `virtualPath` become `path`; `entryId` becomes `entry` and `data`; `origin` becomes `isExplicit`; `isExpanded` and `isSelected` move to the controller; `isVirtual` and `copyWith` are removed. |
| `NodeType` | `TreeNodeKind` | `folder` and `root` become `directory`. |
| `SelectionOrigin` | `TreeNode.isExplicit` | |
| `TreeEntry(id: ..., name: ..., fullPath: ..., isVirtual: ..., metadata: ...)` | `TreeEntry.file(path, data: ...)`, `TreeEntry.directory(path, data: ...)` | The path is the identity; `metadata` becomes typed `data`. |
| `TreeEntry.fullPath` | `TreeEntry.path` | `dart fix`. |
| `VisibleNode` | `TreeRow<T>` | `id`, `depth`, `hasChildren` (now false when a search hides every child); `name` becomes `label`; `type` becomes `node.kind`; `virtualPath` and `sourcePath` become `node.path`; `entryId` becomes `node.entry`; `origin` becomes `node.isExplicit`. New: `isExpanded`, `isLast`, `isMatch`, `guides`, `chain`. |
| `FlattenStrategy`, `DefaultFlattenStrategy`, `SortedFlattenStrategy` | `controller.rows`, `DirectoryTree.flatten` | |
| `SortDelegate`, `AlphaSortDelegate` | `TreeOptions(order: ...)`: `TreeOrder.directoriesFirst` (default), `TreeOrder.alphabetical`, `TreeOrder.by<T>` | Applied when the tree is built. |
| `compileFilter(query)`, `Predicate` | `TreeQuery.parse(query)`, `TreeFilter.where<T>(...)` | Pass a `TreeFilter` as the controller's `filter`. |
| `ExpansionSet` | `ExpansionState` | Immutable: keep the result of every call. |
| `SelectionSet` | `SelectionState` | Immutable: keep the result of every call. |
| `SelectionMode.multi` | `SelectionMode.multiple` | `dart fix` cannot rename enum values. |
| `SelectionMode.single` | `SelectionMode.single` | |
| `FolderSelection` | `CheckState` | `none`, `partial`, `all` become `unchecked`, `partial`, `checked`. |
| `ListDiff(removeIndicesDesc: ..., insertIndicesAsc: ...)` | `ListDiff.compute(before, after, keyOf: ...)` | |
| `ListDiff.removeIndicesDesc`, `ListDiff.insertIndicesAsc` | `removedIndices`, `insertedIndices` | `dart fix`. The lists are now unmodifiable. |
| `ListDiff.isNoop` | `diff.removedIndices.isEmpty && diff.insertedIndices.isEmpty` | `isEmpty` also requires `changedIndices` to be empty. |
| `diffVisibleNodes(before, after)` | `ListDiff.compute(before, after, keyOf: (row) => row.id)` | |
| `ancestorChain(data, id)` | `tree.ancestorsOf(id)` | Nearest first, without the node itself. |
| `findByVirtualPath(data, path)` | `tree.nodeAt(path)`, `tree.idOf(path)` | A real path, not `/tree/...`. |
| `basename`, `extensionLower`, `hasAnyExtension` | `TreePath.name`, `TreePath.extension` | `extensionLower(x)` becomes `node.path.extension.toLowerCase()`. |

## Behavior changes

These compile, or compile after `dart fix`, but do something different.

- Immutable state values. `controller.selection.clear()`,
  `controller.expansion.expand(id)`, and
  `controller.expansion.setExpanded(id, expanded: true)` compile and change
  nothing: they return a new value that is dropped. The analyzer only
  warns (`unused_result`). Call the controller's commands
  (`clearSelection()`, `expand(id)`) or assign the result.
- Old ids. `NodeId(oldStringId)` compiles and matches no node, because
  2.0.0 ids are canonical paths, and unknown ids are ignored without an
  error. Drop stored 1.x ids, or map them to paths.
- `DirectoryTreeToolbar(controller: c)` compiles but shows no search field
  and no row count. Add a `DirectoryTreeSearchField`, or use
  `DirectoryTreePanel`.
- `controller.expandAll()` opens every folder. It is not the 1.x
  `controller.expansions.expandAll(ids)`; for that, assign
  `controller.expansion = controller.expansion.expandAll(ids)`.
- The picker's default `mode` is `DirectoryTreePickerMode.files`, which
  rejects folders. A 1.x call without `foldersOnly` accepted any node: pass
  `mode: DirectoryTreePickerMode.any`.
- Defaults. A new controller starts with every folder closed and an empty
  selection in multiple mode; 1.x builder defaults opened every folder and
  selected every file. Paths are case-sensitive unless the tree uses
  `PathPolicy.caseInsensitive`, so names that differ only in case, which
  1.x merged, become separate nodes.
- Focus and scrolling. `select`, `toggleSelected`, `extendSelection`, and
  `reveal` move the keyboard focus to the row and scroll it into view by
  default. Pass `focus: false` (and `scroll: false` for `reveal`) for the
  1.x behavior.
- Clicks select. The view selects on click, toggles folders on click, and
  activates on double-click. Pass `selectOnTap: false` and
  `expandOnTap: false` to leave clicks to `onRowTap`.
- Single selection mode. `toggleSelected` on the selected row clears the
  selection; 1.x kept it selected.
- Theme values that compile. `guideColor`, `hoverColor`, and
  `animationDuration` keep their names, but guides are drawn by default,
  and the duration also animates rows that a folder reveals. A
  `rowExtent` you do not set is 36 at standard density, not 28.
- The theme getters `indent` and `rowHeight` and theme super parameters
  are not renamed by `dart fix` (see [dart fix](#dart-fix)).
- `ListDiff` index lists are unmodifiable. After the `dart fix` rename,
  `diff.removedIndices.sort()` compiles and throws an `UnsupportedError`.
  Copy the list first.
- A second keyboard layer. Wrapping a 2.0.0 `DirectoryTreeView` in a
  `DirectoryTreeKeyboard`, the literal replacement for
  `SelectionShortcuts`, adds a keyboard handler with its own focus node
  around the one the view already has. Remove the wrapper.
- `collapseAll()` keeps the top-level rows visible. 1.x collapsed the
  visible root to a single row.
- Enter on a file without `onActivate` does nothing; 1.x toggled its
  selection. See [Enter on a file](#enter-on-a-file).

## Recipes

### A custom expander

1.x `expanderBuilder`, `expanderSize`, and `expanderGap` changed the arrow
while the view kept the indentation. In 2.0.0, set the `expander` slot of
`DirectoryTreeRow`, and the row keeps its indentation, guides, icon, and
label:

```dart
Widget plusMinusRow(
  BuildContext context,
  DirectoryTreeRowDetails<Object?> details,
) {
  final row = details.row;
  return DirectoryTreeRow(
    details: details,
    expander: SizedBox(
      width: 20, // the theme's expanderSize, so rows line up
      child: details.isExpandable
          ? IconButton(
              iconSize: 14,
              padding: EdgeInsets.zero,
              icon: Icon(row.isExpanded ? Icons.remove : Icons.add),
              onPressed: () => details.controller.toggleExpansion(row.id),
            )
          : null,
    ),
  );
}
```

Pass it as `rowBuilder: plusMinusRow`. A custom row can also use
`DirectoryTreeExpander(details: details)`, the default arrow, which shows
progress while a folder loads and retries a failed load.

### Clicks the app handles

The 1.x view never selected on click; the `nodeBuilder` decided. Turn the
built-in click handling off and handle `onRowTap`:

```dart
final view = DirectoryTreeView(
  controller: controller,
  selectOnTap: false, // a click only focuses the row
  expandOnTap: false, // folders open with the arrow and the keyboard
  onRowTap: (row) => controller.toggleChecked(row.id),
);
```

### Menus from other design systems

`ContextMenuDelegate.wrapWithMenu` could show any menu. In 2.0.0, leave out
`contextMenuBuilder` and handle `onRowSecondaryTap`. The view selects the
row first (with the default `selectOnTap: true`), and Shift+F10 calls it at
the focused row's bottom start corner (bottom-left, or bottom-right in a
right-to-left layout):

```dart
Widget treeWithPopupMenu(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) {
  return DirectoryTreeView(
    controller: controller,
    onRowSecondaryTap: (row, position) => showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'rename', child: Text('Rename ${row.label}')),
      ],
    ),
  );
}
```

### Middle-click

1.x `TreeNodeTile.onTertiaryTap` handled the middle button. Wrap the row
in a `GestureDetector` in the `rowBuilder`; the view's own click handling
ignores the middle button:

```dart
final view = DirectoryTreeView(
  controller: controller,
  rowBuilder: (context, details) => GestureDetector(
    onTertiaryTapUp: (_) => debugPrint('open ${details.row.label} in a tab'),
    child: DirectoryTreeRow(details: details),
  ),
);
```

### The panel's toolbar and focus

1.x `DirectoryTreePanel` took `toolbar` and focused the tree on start
(`shortcutsAutofocus: true`). 2.0.0 does not take focus unless asked:

```dart
final panel = DirectoryTreePanel(
  controller: controller,
  autofocus: true,
  title: const Text('Files'),
);
```

Pass `toolbar:` to replace the toolbar, `showToolbar: false` or
`showSearch: false` to hide a part.

### The row count

The 1.x toolbar showed the number of visible rows. Add it to the actions:

```dart
final panel = DirectoryTreePanel(
  controller: controller,
  actions: [
    ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Text('${controller.rows.length} rows'),
    ),
  ],
);
```

### Looking up nodes by your own keys

1.x looked nodes up by `TreeEntry.id` (`nodeIdForEntryId`,
`revealByEntryId`). In 2.0.0 the path is the identity. Keep your key in the
entry's data and build a map once per tree:

```dart
final tree = DirectoryTree<String>.build([
  TreeEntry.file('/repo/lib/main.dart', data: 'main'),
  TreeEntry.file('/repo/README.md', data: 'readme'),
]);
final idsByKey = {for (final node in tree.nodes) ?node.data: node.id};
final keyed = DirectoryTreeController<String>(tree: tree);
keyed.reveal(idsByKey['main']!, select: true, scroll: false);
print(keyed.selectedNodes.single.name); // main.dart
```

### Initial state from node flags

1.x seeded the state from the builder's node flags: every folder open and
every file selected by default, and `seedSelectionFromCore`,
`autoExpandVisibleRoot`, and `rebuild(reseedFromCore: true)` used them.
Build the states yourself:

```dart
final paths = ['/repo/lib/main.dart', '/repo/README.md'];
final tree = DirectoryTree.fromPaths(
  paths,
  options: const TreeOptions(paths: PathPolicy.caseInsensitive),
);
final seeded = DirectoryTreeController(
  tree: tree,
  expansion: const ExpansionState.expanded(), // every folder open
  checks: const SelectionState.empty(mode: SelectionMode.multiple)
      .addAll(tree.files.map((file) => file.id)), // every file checked
);
print(seeded.rows.length); // 4
print(seeded.checkedLeaves.length); // 2
```

Use `selection:` instead of `checks:` to highlight the files rather than
check them. To open only the top-level folders, as
`autoExpandVisibleRoot` did, pass
`expansion: ExpansionState.withExpanded(tree.roots)`.

### Checkboxes on the selection

1.x checkbox trees used the highlight selection (`selectSubtree`,
`deselectSubtree`, `folderSelection`). 2.0.0 keeps checks apart, with
tri-state folders:

```dart
final files = DirectoryTreeController(
  tree: DirectoryTree.fromPaths([
    '/repo/lib/main.dart',
    '/repo/lib/src/tree.dart',
    '/repo/README.md',
  ]),
);
final lib = files.tree.idOf('/repo/lib')!;
files.setChecked(lib, checked: true); // was selectSubtree(libId)
print(files.checkStateOf(files.tree.roots.single)); // CheckState.partial
print(files.checkedLeaves.map((node) => node.name)); // (tree.dart, main.dart)
```

Show the boxes with `DirectoryTreeView(checkboxMode:
DirectoryTreeCheckboxMode.checks)`, and read `checkedLeaves` where 1.x read
`selectedIds`. `DirectoryTreeCheckboxMode.selection` draws two-state boxes
on the highlight selection, where a folder's box selects only that folder.

### Sorting at display time

1.x sorted when flattening (`flattenStrategy: SortedFlattenStrategy(...)`).
In 2.0.0 the order belongs to the tree. Rebuild it with another order; ids
do not change, so the view state carries over:

```dart
controller.tree = DirectoryTree.build(
  controller.tree.entries,
  options: controller.tree.options.copyWith(order: TreeOrder.alphabetical),
);
```

There is no input-order mode (1.x `sortChildrenByName: false`): the order
never depends on the input. `TreeOrder.by` sorts by your data.

### Enter on a file

1.x Enter on a file without `onActivate` toggled its selection. Do it in
`onActivate`:

```dart
final view = DirectoryTreeView(
  controller: controller,
  onActivate: (row) {
    if (row.node.isFile) controller.toggleSelected(row.id);
  },
);
```

`onActivate` also runs on a double-click.

### A fixed page size

1.x paged by `pageJumpSize` rows (10). 2.0.0 pages by the number of rows
that fit in the view. To page by a fixed count, replace the focus action:

```dart
final view = Actions(
  actions: {
    MoveTreeFocusIntent: CallbackAction<MoveTreeFocusIntent>(
      onInvoke: (intent) => controller.moveFocus(
        intent.move,
        selection: intent.selection,
        pageSize: 10,
      ),
    ),
  },
  child: DirectoryTreeView(controller: controller),
);
```

### Listening to one kind of change

1.x `expansions` and `selection` were listenables of their own, and could
be shared between controllers. In 2.0.0 the controller notifies for every
kind of change. Compare the value you care about; values that did not
change are the same object:

```dart
var lastSelection = controller.selection;
controller.addListener(() {
  if (identical(controller.selection, lastSelection)) return;
  lastSelection = controller.selection;
  debugPrint('${lastSelection.length} selected');
});
```

To keep two controllers in step, assign one's value to the other:
`other.selection = controller.selection`.

### Icons from node data

1.x `IconProvider` could pick an icon from any node field. 2.0.0 icon
sets map names and extensions; for anything else, set the `leading` slot:

```dart
final view = DirectoryTreeView(
  controller: cloud,
  rowBuilder: (context, details) => DirectoryTreeRow(
    details: details,
    leading: details.row.node.data == 'remote'
        ? const Icon(Icons.cloud_queue, size: 18)
        : null, // null keeps the default icon
  ),
);
```

Here `cloud` is a `DirectoryTreeController<String>` whose entries carry
`'remote'` as data. Virtual entries from 1.x become ordinary entries with
a flag like this in their data.

### Subtitles

`TreeNodeTile.subtitle` drew a second line. 2.0.0 rows have a fixed height
of one line, so show the extra text in the `trailing` slot, or compose it
into the `title`:

```dart
final view = DirectoryTreeView(
  controller: controller,
  rowBuilder: (context, details) => DirectoryTreeRow(
    details: details,
    trailing: Text(
      details.row.node.isDirectory ? 'folder' : 'file',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ),
);
```

### Without a recipe

- Scroll anchoring (`preserveScrollOnChanges: false`) is always on.
- Picker: in single mode a double-click or Enter on a valid row confirms
  it, as in 1.x. Pass `initialSelection` and `initialExpansion` to carry
  state in; the picker never writes back.
- Touch long press opens the context menu, as in 1.x. With drag and drop,
  a long press followed by a move starts a drag, and one released without
  moving opens the menu.
- The container row (`rootFolderLabel`), relative display paths
  (`stripPrefixes`), and bounded hoisting (`visibleRootMaxHoistLevels`)
  have no equivalent. Use `TreeRoots.fixed` for a known root,
  `showRoots: false` to hide it, `compactFolders: true` for chains of
  single folders, and relative paths for relative labels.

## Upgrade checklist

1. Set `flutter_directory_tree: ^2.0.0` and run `flutter pub get`.
2. Run `dart fix --apply` for the renames above.
3. Build trees with `DirectoryTree.build` or `DirectoryTree.fromPaths`
   instead of `TreeBuilder`, and decide on case sensitivity.
4. Replace `DirectoryTreeController(data: ...)` with `tree:`, string ids
   with `NodeId`s, and the `expansions` and `selection` sub-controller calls
   with controller commands.
5. Remove `SelectionShortcuts`, and move click handling from `nodeBuilder`
   to the view (`onRowTap`, `onActivate`, `selectOnTap`, `expandOnTap`).
   Turn `nodeBuilder` into a `rowBuilder` that returns `DirectoryTreeRow`,
   or drop it.
6. Move context menus to `contextMenuBuilder` and icons to the theme's
   `iconSet` or the row's `leading` slot.
7. Rename the theme fields that `dart fix` did not, and check the new
   defaults (row height, guides, colors).
8. Update picker calls: `tree:`, `mode:`, `multiple:`, and a nullable
   result.
9. Go through [Behavior changes](#behavior-changes), then run the analyzer
   and your tests. Fix every `unused_result` warning: each one is a state
   change that never happened.
