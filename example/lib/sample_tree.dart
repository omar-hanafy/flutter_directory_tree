// example/lib/sample_tree.dart
//
// Demo data for the example application. Swap this out for your own
// TreeData builder when wiring the widget to a real project.

import 'package:directory_tree/directory_tree.dart' as core;

Future<core.TreeData> buildDemoTreeData() async {
  // Simulate async work (e.g., reading from disk or a service).
  await Future<void>.delayed(const Duration(milliseconds: 200));

  final entries = <core.TreeEntry>[
    // Application sources
    const core.TreeEntry(
      id: 'app-main',
      name: 'main.dart',
      fullPath: '/workspace/app/lib/main.dart',
    ),
    const core.TreeEntry(
      id: 'app-shell',
      name: 'app_shell.dart',
      fullPath: '/workspace/app/lib/src/app_shell.dart',
    ),
    const core.TreeEntry(
      id: 'app-controller',
      name: 'directory_tree_controller.dart',
      fullPath:
          '/workspace/app/lib/src/controller/directory_tree_controller.dart',
    ),
    const core.TreeEntry(
      id: 'app-theme',
      name: 'directory_tree_theme.dart',
      fullPath: '/workspace/app/lib/src/theme/directory_tree_theme.dart',
    ),
    const core.TreeEntry(
      id: 'app-widget',
      name: 'directory_tree_view.dart',
      fullPath: '/workspace/app/lib/src/widgets/directory_tree_view.dart',
    ),
    const core.TreeEntry(
      id: 'app-test',
      name: 'directory_tree_controller_test.dart',
      fullPath: '/workspace/app/test/directory_tree_controller_test.dart',
    ),

    // Shared utilities package
    const core.TreeEntry(
      id: 'utils-path',
      name: 'path_utils.dart',
      fullPath: '/workspace/packages/utils/lib/path_utils.dart',
    ),
    const core.TreeEntry(
      id: 'utils-reveal',
      name: 'reveal_path.dart',
      fullPath: '/workspace/packages/utils/lib/reveal_path.dart',
    ),
    const core.TreeEntry(
      id: 'utils-search',
      name: 'search_filter.dart',
      fullPath: '/workspace/packages/utils/lib/search_filter.dart',
    ),

    // Design tokens (another root)
    const core.TreeEntry(
      id: 'design-theme',
      name: 'theme.tokens.json',
      fullPath: '/workspace/packages/design/tokens/theme.tokens.json',
    ),
    const core.TreeEntry(
      id: 'design-spacing',
      name: 'spacing.tokens.json',
      fullPath: '/workspace/packages/design/tokens/spacing.tokens.json',
    ),

    // Documentation & assets (mix of real + virtual entries)
    const core.TreeEntry(
      id: 'docs-index',
      name: 'index.md',
      fullPath: '/workspace/app/docs/index.md',
    ),
    const core.TreeEntry(
      id: 'docs-release',
      name: 'Release Notes.md',
      fullPath: '/workspace/app/docs/Release Notes.md',
      isVirtual: true,
      metadata: {'virtualParent': '/workspace/app/docs'},
    ),
    const core.TreeEntry(
      id: 'docs-migration',
      name: 'Migration Guide.md',
      fullPath: '/workspace/app/docs/Migration Guide.md',
      isVirtual: true,
      metadata: {'virtualParent': '/workspace/app/docs'},
    ),
    const core.TreeEntry(
      id: 'asset-logo',
      name: 'logo.png',
      fullPath: '/workspace/app/assets/logo.png',
    ),
    const core.TreeEntry(
      id: 'asset-preview',
      name: 'preview.webp',
      fullPath: '/workspace/app/assets/preview.webp',
      isVirtual: true,
      metadata: {'virtualParent': '/workspace/app/assets'},
    ),
  ];

  final data = core.TreeBuilder().build(
    entries: entries,
    sourceRoots: const [
      '/workspace/app',
      '/workspace/packages/utils',
      '/workspace/packages/design',
    ],
    stripPrefixes: const ['/workspace'],
    rootFolderLabel: 'workspace',
    expandFoldersByDefault: true,
    selectNewFilesByDefault: false,
  );

  return data;
}
