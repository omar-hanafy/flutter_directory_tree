import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// The root folder of the generated sample project.
const String sampleRoot = '/acme_app';

/// The entries of a generated Flutter project under [sampleRoot].
///
/// Files carry a made-up size in bytes as their data; directories carry no
/// data. The output is the same on every call, so tests can rely on it.
List<TreeEntry<int>> sampleProjectEntries() {
  final entries = <TreeEntry<int>>[];
  var seed = 7;
  int nextSize() {
    // A small linear congruential generator keeps the sizes stable.
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return 200 + seed % 48000;
  }

  void file(String path) =>
      entries.add(TreeEntry<int>.file('$sampleRoot/$path', data: nextSize()));
  void directory(String path) =>
      entries.add(TreeEntry<int>.directory('$sampleRoot/$path'));

  for (final name in const [
    'README.md',
    'CHANGELOG.md',
    'pubspec.yaml',
    'analysis_options.yaml',
    '.gitignore',
  ]) {
    file(name);
  }
  file('lib/main.dart');
  file('lib/app.dart');
  for (final feature in const ['auth', 'catalog', 'checkout', 'profile']) {
    for (final layer in const ['data', 'domain', 'presentation']) {
      for (final part in const ['repository', 'model', 'controller']) {
        file('lib/src/features/$feature/$layer/${feature}_$part.dart');
      }
    }
  }
  for (final name in const ['colors', 'spacing', 'typography', 'theme']) {
    file('lib/src/design/$name.dart');
  }
  file('lib/src/utils/formatters.dart');
  file('lib/src/utils/validators.dart');
  for (final feature in const ['auth', 'catalog', 'checkout']) {
    file('test/features/${feature}_test.dart');
  }
  file('test/widget_test.dart');
  file('integration_test/app_test.dart');
  for (final image in const ['logo.png', 'hero.jpg', 'empty_state.svg']) {
    file('assets/images/$image');
  }
  file('assets/fonts/Inter-Regular.ttf');
  file('assets/l10n/app_en.arb');
  file('assets/l10n/app_ar.arb');
  file('android/app/build.gradle.kts');
  file('android/app/src/main/AndroidManifest.xml');
  file('ios/Runner/Info.plist');
  file('ios/Runner/AppDelegate.swift');
  file('web/index.html');
  file('web/manifest.json');
  directory('docs');
  directory('build');
  return entries;
}

/// The sample project as a tree.
DirectoryTree<int> sampleProjectTree() =>
    DirectoryTree<int>.build(sampleProjectEntries());

/// [bytes] as a short human-readable size, such as `12.4 KB`.
String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}
