/// Flutter widgets for directory trees built on `package:directory_tree`:
/// a virtualized, keyboard-first tree view with incremental expand and
/// collapse, multi-selection, tri-state checkboxes, search, and lazy
/// loading.
///
/// This library re-exports the whole `package:directory_tree` core, so one
/// import gives both the tree model ([DirectoryTree], [TreeRows],
/// [ExpansionState], [SelectionState], [TreeQuery]) and the Flutter layer
/// that displays it.
///
/// ## The controller
///
/// A [DirectoryTreeController] is the single source of truth for one tree
/// view. It holds the [DirectoryTree], the visible [TreeRows], two
/// expansion states (the requested one to persist, and the effective one on
/// screen that a search adds its matches to), the highlight selection, the
/// checkbox state, the keyboard focus, the search query and filters, and
/// the lazy-loading status of each directory. Widgets read these values and
/// call its commands; every command that changes something notifies the
/// listeners exactly once.
///
/// ```dart
/// final controller = DirectoryTreeController(
///   tree: DirectoryTree.fromPaths([
///     '/repo/lib/main.dart',
///     '/repo/lib/src/tree.dart',
///     '/repo/README.md',
///   ]),
/// );
///
/// controller.expand(controller.tree.roots.single); // repo opens
/// controller.moveFocus(TreeFocusMove.first); // focus and select repo
/// controller.query = 'tree'; // rows: repo, lib, src, tree.dart
/// controller.query = ''; // back to the expansion from before
/// ```
///
/// * Data: set [DirectoryTreeController.tree] (or call
///   [DirectoryTreeController.updateTree]) whenever the data changes; the
///   view state is kept by [NodeId].
/// * Rows: [DirectoryTreeController.rows] are the visible rows, and
///   [DirectoryTreeController.lastRowsChange] ([TreeRowsChange]) says which
///   block of them changed, so a list view can animate and keep its scroll
///   position.
/// * Expansion: [DirectoryTreeController.expand],
///   [DirectoryTreeController.collapse],
///   [DirectoryTreeController.toggleExpansion],
///   [DirectoryTreeController.expandAll],
///   [DirectoryTreeController.reveal], and friends.
/// * Selection and checkboxes: [DirectoryTreeController.select],
///   [DirectoryTreeController.extendSelection],
///   [DirectoryTreeController.toggleChecked],
///   [DirectoryTreeController.checkStateOf], and friends.
/// * Keyboard focus: [DirectoryTreeController.moveFocus] with a
///   [TreeFocusMove] and a [TreeSelectionUpdate].
/// * Search: [DirectoryTreeController.query] and
///   [DirectoryTreeController.filter].
/// * Lazy loading: pass a [DirectoryChildrenLoader] (and optionally a
///   [DirectoryLoadErrorCallback]); [DirectoryTreeController.loadStatusOf]
///   reports a [DirectoryLoadStatus] per directory.
/// * Scrolling: views implement [DirectoryTreeViewport] and attach
///   themselves, so [DirectoryTreeController.ensureVisible] and keyboard
///   paging work.
library;

// Imported only so the references in the library documentation resolve.
import 'package:directory_tree/directory_tree.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/controller/tree_rows_change.dart';

export 'package:directory_tree/directory_tree.dart';
export 'package:flutter_directory_tree/src/controller/directory_loading.dart';
export 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
export 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
export 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
export 'package:flutter_directory_tree/src/controller/tree_rows_change.dart';
export 'package:flutter_directory_tree/src/dnd/directory_tree_drag_and_drop.dart';
export 'package:flutter_directory_tree/src/dnd/directory_tree_drop_details.dart';
export 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
export 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
export 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
export 'package:flutter_directory_tree/src/menu/directory_tree_context_menu.dart';
export 'package:flutter_directory_tree/src/menu/directory_tree_menu_details.dart';
export 'package:flutter_directory_tree/src/rendering/directory_tree_indent_guides.dart';
export 'package:flutter_directory_tree/src/rendering/directory_tree_label.dart';
export 'package:flutter_directory_tree/src/search/directory_tree_search_field.dart';
export 'package:flutter_directory_tree/src/search/directory_tree_toolbar.dart';
export 'package:flutter_directory_tree/src/theme/directory_tree_icon_set.dart';
export 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';
export 'package:flutter_directory_tree/src/widgets/directory_tree_checkbox.dart';
export 'package:flutter_directory_tree/src/widgets/directory_tree_expander.dart';
export 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
export 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
export 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';
