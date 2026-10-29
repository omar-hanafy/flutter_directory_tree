# Changelog

All notable changes to this project will be documented in this file.

## 2.0.0

Breaking: a ground-up rewrite on directory_tree 2.0.0. Code written for 1.x
needs changes. [MIGRATION.md](MIGRATION.md) maps every 1.x declaration to
its replacement, lists the changes that compile but behave differently,
and has recipes for 1.x features that moved. `dart fix --apply` renames
the theme parameters `indent` and `rowHeight` and the re-exported
`ListDiff.removeIndicesDesc`, `ListDiff.insertIndicesAsc`, and
`TreeEntry.fullPath`; every other change is manual.

### Added
- `DirectoryTreeController<T>` keeps all view state as immutable values:
  expansion, selection, tri-state checks, keyboard focus, search, and the
  lazy-loading status of each folder. Each command notifies once.
  Expanding and collapsing a folder updates the rows incrementally, and
  `lastRowsChange` says which block of rows changed.
- Search through `query` (parsed with `TreeQuery`) and `filter`, with
  matches revealed and highlighted. The requested `expansion` leaves out
  the folders a search opened, so clearing the search restores the view,
  except that the folders leading to the focused row stay open.
- Lazy loading with `loadChildren`, `loadStatusOf`, `loadChildren(id)`,
  and `reloadChildren(id)`, and `FileSystemTreeLoader` in the new
  `package:flutter_directory_tree/io.dart` library, which also re-exports
  `DirectoryScanner`. A reload reopens the folders that were open below
  it as their contents come back.
- `SliverDirectoryTree`, a virtualized sliver with fixed-height rows that
  rebuilds only the rows whose state changed, keeps the first visible row
  in place when the rows change, and animates the rows a folder reveals.
- Mouse and touch handling: click, Shift-click, Ctrl-click (Cmd-click on
  macOS), double-click activation, secondary click, touch long press, and
  hover.
- `DirectoryTreeKeyboard`, `DirectoryTreeShortcuts.defaults`, and the
  tree intents: platform-specific bindings, right-to-left layouts, and
  type-ahead find (also with Option and AltGr). Tabbing into a tree
  focuses its first selected row, or its first row.
  `selectionFollowsFocus: false` moves the focus without selecting.
- Context menus with `DirectoryTreeContextMenu` and
  `DirectoryTreeMenuDetails`, opened by secondary click, long press,
  Shift+F10, and the context menu key. `selectOnOpen` decides whether
  opening the menu selects the row.
- Drag and drop with `DirectoryTreeDragAndDrop`,
  `DirectoryTreeDragAndDropScope`, and `DirectoryTreeDropDetails`.
- `DirectoryTreeSearchField`, `DirectoryTreePicker`, and
  `DirectoryTreePickerMode`.
- `DirectoryTreeRow`, `DirectoryTreeRowDetails`, `DirectoryTreeExpander`,
  `DirectoryTreeCheckbox`, `DirectoryTreeLabel`,
  `DirectoryTreeIndentGuides`, and `DirectoryTreeIconSet` for custom rows
  and icons.
- `compactFolders` and `showRoots` on the controller.
- Row semantics: label, level hint (`levelSemanticsHint`), selected,
  expanded, and checked states, the keyboard focus, loading and failed
  states, and expand, collapse, retry, and Open (`onActivate`) actions,
  with localizable labels; `semanticLabel` for the whole tree.
- Support for the web, compiled to JavaScript and to WebAssembly.
- `lib/fix_data.yaml` with the `dart fix` renames.

### Changed
- `DirectoryTreeController` is generic over the entry data type, takes a
  `DirectoryTree<T>` as `tree`, and identifies nodes by `NodeId` (the
  canonical path) instead of generated string ids. It starts with every
  folder closed and an empty selection in multiple mode.
- `DirectoryTreeView` handles clicks, keys, checkboxes, context menus, and
  drag and drop itself. `rowBuilder` replaces `nodeBuilder` and is
  optional.
- `DirectoryTreePanel` takes every parameter of `DirectoryTreeView`, plus
  `title`, `actions`, `toolbar`, `showToolbar`, `showSearch`, and
  `searchHintText`. It no longer takes the keyboard focus by default.
- `DirectoryTreeToolbar` shows a title, actions, and expand all, collapse
  all, and compact folders buttons. The search field is now
  `DirectoryTreeSearchField`.
- `showDirectoryTreePicker` takes a `tree`, a `mode`, and `multiple`,
  returns the picked nodes or `null` on cancel, and no longer changes the
  caller's controller.
- `DirectoryTreeThemeData` is a `ThemeExtension` with nullable fields and
  Material 3 defaults. `indent` is now `indentWidth`, `rowHeight` is
  `rowExtent` (default 36, adjusted by the visual density, at least 48
  on touch platforms, and taller with large text),
  `selectionColor` is `selectedColor` plus `inactiveSelectedColor`,
  `indentGuides` is `guideStyle`, `roundedCorners` is `rowBorderRadius`,
  and `focusColor` is `focusedBorderColor`.
- The package requires Dart 3.13.5 and Flutter 3.47.7, and depends only on
  `directory_tree` 2.0.0 and Flutter. The `path` dependency is gone.

### Removed
- `ExpansionController` and `SelectionController`: use the controller's
  `expansion` and `selection` values and commands.
- `SelectionShortcuts`, the 1.x intents (`ExpandNodeIntent`,
  `CollapseNodeIntent`, `ToggleNodeIntent`, `RevealNodeIntent`,
  `SelectOnlyIntent`, `ClearSelectionIntent`), and `DirectoryTreeAction`.
- `TreeNodeTile`, `NodeVisualState`, `NodeBuilder`, and `ExpanderBuilder`.
- `ContextMenuDelegate`, `MaterialContextMenuDelegate`, and `NodeAction`.
- `IconProvider` and `MaterialIconProvider`.
- `DirectoryTreeDefaults`, `revealAndSelect`, `folderSelection`, and
  `schedulePreserveScrollOffset`.
- `DirectoryTreeView` parameters `expanderBuilder`, `expanderSize`,
  `expanderGap`, `contextMenuDelegate`, `addAutomaticKeepAlives`, and
  `preserveScrollOnChanges`.

### Fixed
These 1.0.0 defects are gone in 2.0.0:
- Repeated Shift+Up oscillated between a two-row and a three-row
  selection, and Shift+Page Up extended only once.
- The picker's confirm button kept the enabled state it had when the
  dialog opened, so it stayed disabled after selecting something in a
  dialog that opened with nothing selected. The picker also changed the
  selection, expansion, and search of the controller passed to it.
- In `DirectoryTreePanel` and the picker, selected rows drew as if the
  tree had no focus: `NodeVisualState.isFocused` stayed false until the
  focus moved into the view's own focus node.
- With the `TreeBuilder` defaults, a new controller opened every folder
  and selected every file, even in single selection mode.
- Keyboard moves did not scroll the focused row into view.
- Documentation that did not match the code: the README's theming example
  passed a `folderIconColor` that did not exist, the README advertised
  Shift-click and Ctrl-click selection that no widget implemented, and
  `selectRange` was documented as adding to the selection while it
  replaced it.

## [1.0.0] - 2026-01-02

### Added
- Virtualized tree view widget with desktop-friendly keyboard navigation.
- `TreeController` for managing selection, expansion, focus, and active entry state.
- `TreeBuilder` utilities to compose trees from arbitrary source roots.
- Tri-state folder selection with bulk select/deselect helpers.
- Example application showcasing customization and status reporting.
- Unit tests covering tree building, selection logic, and focus traversal.
