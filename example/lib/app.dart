import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree_example/demos/checkboxes_demo.dart';
import 'package:flutter_directory_tree_example/demos/explorer_demo.dart';
import 'package:flutter_directory_tree_example/demos/file_system_demo.dart';
import 'package:flutter_directory_tree_example/demos/large_tree_demo.dart';
import 'package:flutter_directory_tree_example/demos/picker_demo.dart';
import 'package:flutter_directory_tree_example/demos/theming_demo.dart';

/// The showcase app: one page per demo, light and dark Material 3 themes,
/// and a theme-mode toggle.
class ExampleApp extends StatefulWidget {
  /// Creates the showcase app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  ThemeMode _themeMode = ThemeMode.system;

  static const Color _seed = Color(0xFF3F6FD8);

  void _cycleThemeMode() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_directory_tree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed),
      darkTheme: ThemeData(colorSchemeSeed: _seed, brightness: Brightness.dark),
      themeMode: _themeMode,
      home: HomePage(themeMode: _themeMode, onCycleThemeMode: _cycleThemeMode),
    );
  }
}

/// One entry of the navigation.
class Demo {
  /// Creates a navigation entry.
  const Demo({
    required this.title,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  /// The label in the navigation and the app bar.
  final String title;

  /// The navigation icon.
  final IconData icon;

  /// The navigation icon while the demo is shown.
  final IconData selectedIcon;

  /// Builds the demo page.
  final WidgetBuilder builder;
}

/// Whether the file system demo can run here: desktop platforms only, since
/// the web has no file system and mobile apps only see their own sandbox.
bool get fileSystemDemoAvailable =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => false,
    };

/// The demos available on this platform, in navigation order.
List<Demo> availableDemos() => [
  Demo(
    title: 'Explorer',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    builder: (context) => const ExplorerDemo(),
  ),
  Demo(
    title: 'Checkboxes',
    icon: Icons.check_box_outlined,
    selectedIcon: Icons.check_box,
    builder: (context) => const CheckboxesDemo(),
  ),
  if (fileSystemDemoAvailable)
    Demo(
      title: 'File system',
      icon: Icons.storage_outlined,
      selectedIcon: Icons.storage,
      builder: (context) => const FileSystemDemo(),
    ),
  Demo(
    title: 'Large tree',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    builder: (context) => const LargeTreeDemo(),
  ),
  Demo(
    title: 'Theming',
    icon: Icons.palette_outlined,
    selectedIcon: Icons.palette,
    builder: (context) => const ThemingDemo(),
  ),
  Demo(
    title: 'Picker',
    icon: Icons.ads_click_outlined,
    selectedIcon: Icons.ads_click,
    builder: (context) => const PickerDemo(),
  ),
];

/// The page that hosts the demos: a [NavigationRail] on wide windows and a
/// [NavigationBar] on narrow ones.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({
    super.key,
    required this.themeMode,
    required this.onCycleThemeMode,
  });

  /// The current theme mode, shown by the toggle.
  final ThemeMode themeMode;

  /// Switches to the next theme mode.
  final VoidCallback onCycleThemeMode;

  /// Windows at least this wide get the navigation rail.
  static const double railBreakpoint = 720;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Demo> _demos = availableDemos();
  int _index = 0;

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final demo = _demos[_index];
    final (IconData icon, String label) = switch (widget.themeMode) {
      ThemeMode.system => (Icons.brightness_auto, 'Theme: system'),
      ThemeMode.light => (Icons.light_mode, 'Theme: light'),
      ThemeMode.dark => (Icons.dark_mode, 'Theme: dark'),
    };
    final appBar = AppBar(
      title: Text(demo.title),
      actions: [
        IconButton(
          tooltip: label,
          icon: Icon(icon),
          onPressed: widget.onCycleThemeMode,
        ),
        const SizedBox(width: 8),
      ],
    );
    // A new key per demo gives every demo a fresh state when it is shown.
    final page = KeyedSubtree(
      key: ValueKey<String>(demo.title),
      child: demo.builder(context),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= HomePage.railBreakpoint) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final demo in _demos)
                      NavigationRailDestination(
                        icon: Icon(demo.icon),
                        selectedIcon: Icon(demo.selectedIcon),
                        label: Text(demo.title),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: appBar,
          body: page,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: [
              for (final demo in _demos)
                NavigationDestination(
                  icon: Icon(demo.icon),
                  selectedIcon: Icon(demo.selectedIcon),
                  label: demo.title,
                ),
            ],
          ),
        );
      },
    );
  }
}
