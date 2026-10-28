import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_theme.dart';

/// The icons a directory tree shows for files and directories.
///
/// [iconFor] picks the icon of a node: [folder] or [folderOpen] for a
/// directory, and for a file the icon registered for its name in [names],
/// else for its extension in [extensions], else [file]. The theme's
/// [DirectoryTreeThemeData.iconSet] is the set the default rows use; it
/// defaults to [DirectoryTreeIconSet.material].
///
/// Extend the material set by copying its maps:
///
/// ```dart
/// final icons = DirectoryTreeIconSet.material.copyWith(
///   extensions: {
///     ...DirectoryTreeIconSet.material.extensions,
///     'proto': Icons.schema_outlined,
///   },
/// );
/// ```
@immutable
final class DirectoryTreeIconSet {
  /// Creates an icon set from its three base icons and optional lookups.
  ///
  /// Keys of [extensions] and [names] are matched without regard to case,
  /// and an extension key may start with a `.`; the canonical form is
  /// lowercase with no leading dot, as in [DirectoryTreeIconSet.material].
  const DirectoryTreeIconSet({
    required this.file,
    required this.folder,
    required this.folderOpen,
    this.extensions = const <String, IconData>{},
    this.names = const <String, IconData>{},
  });

  /// The icon of a file that neither [names] nor [extensions] covers.
  final IconData file;

  /// The icon of a collapsed directory.
  final IconData folder;

  /// The icon of an expanded directory.
  final IconData folderOpen;

  /// File icons by extension, such as `'dart'` or `'png'`.
  ///
  /// An extension is the part of a file name after any `.` that is not the
  /// first character, so a key may span several parts (`'tar.gz'`); when
  /// several keys match one name, the longest wins. Directories never use
  /// this map.
  final Map<String, IconData> extensions;

  /// File icons by whole file name, such as `'pubspec.yaml'` or
  /// `'dockerfile'`.
  ///
  /// Names take precedence over [extensions], and they are the only way to
  /// match a dotfile such as `.gitignore`, which has no extension.
  /// Directories never use this map.
  final Map<String, IconData> names;

  /// Material [Icons] for common files.
  ///
  /// Covers source code, shell scripts, images, documents, presentations,
  /// spreadsheets, data and configuration formats, archives and packages,
  /// audio, video, and fonts by extension, and well-known names such as
  /// `pubspec.yaml`, `package.json`, `README.md`, `LICENSE`, `CHANGELOG.md`,
  /// `Dockerfile`, `Makefile`, `.gitignore`, and `.env`. Files it does not
  /// cover use [Icons.insert_drive_file_outlined]; directories use
  /// [Icons.folder_outlined] and [Icons.folder_open_outlined].
  ///
  /// The icons come from the MaterialIcons font, so the app must declare
  /// `uses-material-design: true` in its `pubspec.yaml`.
  static const DirectoryTreeIconSet material = DirectoryTreeIconSet(
    file: Icons.insert_drive_file_outlined,
    folder: Icons.folder_outlined,
    folderOpen: Icons.folder_open_outlined,
    extensions: _materialExtensions,
    names: _materialNames,
  );

  /// The icon for [node].
  ///
  /// A directory gets [folderOpen] when [expanded] is true and [folder]
  /// otherwise. A file gets the [names] entry for its [TreeNode.name], else
  /// the [extensions] entry for the longest matching extension (`tar.gz` is
  /// tried before `gz`), else [file]. Matching ignores case. A `.` at the
  /// start of a name does not begin an extension, so dotfiles such as
  /// `.gitignore` and `.env` match only through [names]; `.eslintrc.json`
  /// still matches the `json` extension. [expanded] is ignored for files.
  ///
  /// Runs in O(name length) plus one map lookup per `.` in the name. The
  /// lookup tables are prepared on the first call for each set.
  IconData iconFor(TreeNode<Object?> node, {required bool expanded}) {
    if (node.isDirectory) return expanded ? folderOpen : folder;
    final lookup = _IconLookup.of(this);
    final name = node.name.toLowerCase();
    final byName = lookup.names[name];
    if (byName != null) return byName;
    final extensions = lookup.extensions;
    if (extensions.isEmpty) return file;
    // The suffixes after each '.' from left to right, so a longer registered
    // extension wins over a shorter one ('tar.gz' before 'gz'). Index 0 is
    // skipped because a leading '.' marks a dotfile, not an extension, and an
    // empty suffix after a trailing '.' ends the scan.
    var dot = name.length > 1 ? name.indexOf('.', 1) : -1;
    while (dot != -1 && dot < name.length - 1) {
      final icon = extensions[name.substring(dot + 1)];
      if (icon != null) return icon;
      dot = name.indexOf('.', dot + 1);
    }
    return file;
  }

  /// A copy of this set with the given fields replaced; null arguments keep
  /// the current values.
  ///
  /// The maps replace the current ones entirely; spread the current map into
  /// the new one to add entries.
  DirectoryTreeIconSet copyWith({
    IconData? file,
    IconData? folder,
    IconData? folderOpen,
    Map<String, IconData>? extensions,
    Map<String, IconData>? names,
  }) {
    return DirectoryTreeIconSet(
      file: file ?? this.file,
      folder: folder ?? this.folder,
      folderOpen: folderOpen ?? this.folderOpen,
      extensions: extensions ?? this.extensions,
      names: names ?? this.names,
    );
  }

  /// Whether [other] is a [DirectoryTreeIconSet] with the same three icons
  /// and maps with equal entries.
  ///
  /// Map order does not matter. Runs in O(entries) unless the sets are
  /// identical.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectoryTreeIconSet &&
          other.file == file &&
          other.folder == folder &&
          other.folderOpen == folderOpen &&
          mapEquals(other.extensions, extensions) &&
          mapEquals(other.names, names);

  /// A hash of the three icons and the map entries, independent of map
  /// order. Runs in O(entries).
  @override
  int get hashCode => Object.hash(
    file,
    folder,
    folderOpen,
    _hashEntries(extensions),
    _hashEntries(names),
  );

  static int _hashEntries(Map<String, IconData> map) => Object.hashAllUnordered(
    <int>[for (final entry in map.entries) Object.hash(entry.key, entry.value)],
  );

  /// `DirectoryTreeIconSet.material` for a set equal to [material],
  /// otherwise the three icons and the number of entries in each map.
  @override
  String toString() {
    if (this == material) return 'DirectoryTreeIconSet.material';
    return 'DirectoryTreeIconSet(file: $file, folder: $folder, '
        'folderOpen: $folderOpen, extensions: ${extensions.length}, '
        'names: ${names.length})';
  }
}

// The maps [DirectoryTreeIconSet.iconFor] searches: the public maps with
// lowercase keys and no leading '.' on extensions. Sets are immutable, so the
// tables are built once per set and kept in an Expando, which holds its keys
// weakly. Maps that are already canonical, such as the material ones, are
// used as they are.
final class _IconLookup {
  _IconLookup(DirectoryTreeIconSet icons)
    : names = _canonical(icons.names, extension: false),
      extensions = _canonical(icons.extensions, extension: true);

  static final Expando<_IconLookup> _cache = Expando<_IconLookup>(
    'DirectoryTreeIconSet',
  );

  static _IconLookup of(DirectoryTreeIconSet icons) =>
      _cache[icons] ??= _IconLookup(icons);

  final Map<String, IconData> names;
  final Map<String, IconData> extensions;

  static Map<String, IconData> _canonical(
    Map<String, IconData> map, {
    required bool extension,
  }) {
    String keyOf(String key) {
      final lower = key.toLowerCase();
      return extension && lower.startsWith('.') ? lower.substring(1) : lower;
    }

    if (map.keys.every((key) => keyOf(key) == key)) return map;
    return <String, IconData>{
      for (final entry in map.entries) keyOf(entry.key): entry.value,
    };
  }
}

const Map<String, IconData> _materialExtensions = <String, IconData>{
  // Source code.
  'c': Icons.code,
  'cc': Icons.code,
  'cpp': Icons.code,
  'cs': Icons.code,
  'cxx': Icons.code,
  'dart': Icons.code,
  'ex': Icons.code,
  'exs': Icons.code,
  'go': Icons.code,
  'gradle': Icons.code,
  'graphql': Icons.code,
  'groovy': Icons.code,
  'h': Icons.code,
  'hpp': Icons.code,
  'hs': Icons.code,
  'ipynb': Icons.code,
  'java': Icons.code,
  'jl': Icons.code,
  'jsx': Icons.code,
  'kt': Icons.code,
  'kts': Icons.code,
  'lua': Icons.code,
  'm': Icons.code,
  'mm': Icons.code,
  'pl': Icons.code,
  'proto': Icons.code,
  'py': Icons.code,
  'r': Icons.code,
  'rb': Icons.code,
  'rs': Icons.code,
  'scala': Icons.code,
  'svelte': Icons.code,
  'swift': Icons.code,
  'ts': Icons.code,
  'tsx': Icons.code,
  'vue': Icons.code,
  'xml': Icons.code,
  'zig': Icons.code,
  'cjs': Icons.javascript,
  'js': Icons.javascript,
  'mjs': Icons.javascript,
  'htm': Icons.html,
  'html': Icons.html,
  'css': Icons.css,
  'less': Icons.css,
  'sass': Icons.css,
  'scss': Icons.css,
  'php': Icons.php,
  // Shell scripts.
  'bash': Icons.terminal,
  'bat': Icons.terminal,
  'cmd': Icons.terminal,
  'command': Icons.terminal,
  'fish': Icons.terminal,
  'ps1': Icons.terminal,
  'sh': Icons.terminal,
  'zsh': Icons.terminal,
  // Images.
  'avif': Icons.image_outlined,
  'bmp': Icons.image_outlined,
  'gif': Icons.image_outlined,
  'heic': Icons.image_outlined,
  'heif': Icons.image_outlined,
  'icns': Icons.image_outlined,
  'ico': Icons.image_outlined,
  'jpeg': Icons.image_outlined,
  'jpg': Icons.image_outlined,
  'png': Icons.image_outlined,
  'psd': Icons.image_outlined,
  'svg': Icons.image_outlined,
  'tif': Icons.image_outlined,
  'tiff': Icons.image_outlined,
  'webp': Icons.image_outlined,
  // Documents.
  'pdf': Icons.picture_as_pdf_outlined,
  'doc': Icons.description_outlined,
  'docx': Icons.description_outlined,
  'odt': Icons.description_outlined,
  'pages': Icons.description_outlined,
  'rtf': Icons.description_outlined,
  'adoc': Icons.article_outlined,
  'markdown': Icons.article_outlined,
  'md': Icons.article_outlined,
  'mdx': Icons.article_outlined,
  'rst': Icons.article_outlined,
  'tex': Icons.article_outlined,
  'text': Icons.text_snippet_outlined,
  'txt': Icons.text_snippet_outlined,
  'log': Icons.receipt_long_outlined,
  // Presentations.
  'odp': Icons.slideshow_outlined,
  'ppt': Icons.slideshow_outlined,
  'pptx': Icons.slideshow_outlined,
  // Spreadsheets.
  'csv': Icons.table_chart_outlined,
  'numbers': Icons.table_chart_outlined,
  'ods': Icons.table_chart_outlined,
  'tsv': Icons.table_chart_outlined,
  'xls': Icons.table_chart_outlined,
  'xlsx': Icons.table_chart_outlined,
  // Data and configuration.
  'geojson': Icons.data_object,
  'json': Icons.data_object,
  'json5': Icons.data_object,
  'jsonc': Icons.data_object,
  'jsonl': Icons.data_object,
  'ndjson': Icons.data_object,
  'cfg': Icons.settings_outlined,
  'conf': Icons.settings_outlined,
  'config': Icons.settings_outlined,
  'ini': Icons.settings_outlined,
  'plist': Icons.settings_outlined,
  'properties': Icons.settings_outlined,
  'toml': Icons.settings_outlined,
  'xcconfig': Icons.settings_outlined,
  'yaml': Icons.settings_outlined,
  'yml': Icons.settings_outlined,
  'dockerfile': Icons.view_in_ar_outlined,
  'env': Icons.tune,
  'lock': Icons.lock_outline,
  'db': Icons.storage,
  'sql': Icons.storage,
  'sqlite': Icons.storage,
  'sqlite3': Icons.storage,
  'arb': Icons.translate,
  'po': Icons.translate,
  'pot': Icons.translate,
  'xlf': Icons.translate,
  'xliff': Icons.translate,
  'cer': Icons.key,
  'crt': Icons.key,
  'jks': Icons.key,
  'key': Icons.key,
  'keystore': Icons.key,
  'p12': Icons.key,
  'pem': Icons.key,
  'pfx': Icons.key,
  // Archives and packages.
  '7z': Icons.folder_zip_outlined,
  'bz2': Icons.folder_zip_outlined,
  'deb': Icons.folder_zip_outlined,
  'gz': Icons.folder_zip_outlined,
  'jar': Icons.folder_zip_outlined,
  'rar': Icons.folder_zip_outlined,
  'rpm': Icons.folder_zip_outlined,
  'tar': Icons.folder_zip_outlined,
  'tar.bz2': Icons.folder_zip_outlined,
  'tar.gz': Icons.folder_zip_outlined,
  'tar.xz': Icons.folder_zip_outlined,
  'tar.zst': Icons.folder_zip_outlined,
  'tgz': Icons.folder_zip_outlined,
  'xz': Icons.folder_zip_outlined,
  'zip': Icons.folder_zip_outlined,
  'zst': Icons.folder_zip_outlined,
  'aab': Icons.android,
  'apk': Icons.android,
  // Audio.
  'aac': Icons.audio_file_outlined,
  'aif': Icons.audio_file_outlined,
  'aiff': Icons.audio_file_outlined,
  'flac': Icons.audio_file_outlined,
  'm4a': Icons.audio_file_outlined,
  'mid': Icons.audio_file_outlined,
  'midi': Icons.audio_file_outlined,
  'mp3': Icons.audio_file_outlined,
  'oga': Icons.audio_file_outlined,
  'ogg': Icons.audio_file_outlined,
  'opus': Icons.audio_file_outlined,
  'wav': Icons.audio_file_outlined,
  'wma': Icons.audio_file_outlined,
  // Video.
  '3gp': Icons.video_file_outlined,
  'avi': Icons.video_file_outlined,
  'flv': Icons.video_file_outlined,
  'm4v': Icons.video_file_outlined,
  'mkv': Icons.video_file_outlined,
  'mov': Icons.video_file_outlined,
  'mp4': Icons.video_file_outlined,
  'mpeg': Icons.video_file_outlined,
  'mpg': Icons.video_file_outlined,
  'ogv': Icons.video_file_outlined,
  'webm': Icons.video_file_outlined,
  'wmv': Icons.video_file_outlined,
  // Fonts.
  'eot': Icons.font_download_outlined,
  'otf': Icons.font_download_outlined,
  'ttf': Icons.font_download_outlined,
  'woff': Icons.font_download_outlined,
  'woff2': Icons.font_download_outlined,
};

const Map<String, IconData> _materialNames = <String, IconData>{
  // Package manifests.
  'cargo.toml': Icons.inventory_2_outlined,
  'composer.json': Icons.inventory_2_outlined,
  'gemfile': Icons.inventory_2_outlined,
  'go.mod': Icons.inventory_2_outlined,
  'package.json': Icons.inventory_2_outlined,
  'podfile': Icons.inventory_2_outlined,
  'pom.xml': Icons.inventory_2_outlined,
  'pubspec.yaml': Icons.inventory_2_outlined,
  'pyproject.toml': Icons.inventory_2_outlined,
  'requirements.txt': Icons.inventory_2_outlined,
  // Lock files without a .lock extension.
  'go.sum': Icons.lock_outline,
  'package-lock.json': Icons.lock_outline,
  'pnpm-lock.yaml': Icons.lock_outline,
  // Project documents.
  'readme': Icons.info_outline,
  'readme.md': Icons.info_outline,
  'readme.rst': Icons.info_outline,
  'readme.txt': Icons.info_outline,
  'copying': Icons.gavel,
  'licence': Icons.gavel,
  'licence.md': Icons.gavel,
  'licence.txt': Icons.gavel,
  'license': Icons.gavel,
  'license.md': Icons.gavel,
  'license.txt': Icons.gavel,
  'changelog': Icons.history,
  'changelog.md': Icons.history,
  // Containers.
  '.dockerignore': Icons.view_in_ar_outlined,
  'compose.yaml': Icons.view_in_ar_outlined,
  'compose.yml': Icons.view_in_ar_outlined,
  'containerfile': Icons.view_in_ar_outlined,
  'docker-compose.yaml': Icons.view_in_ar_outlined,
  'docker-compose.yml': Icons.view_in_ar_outlined,
  'dockerfile': Icons.view_in_ar_outlined,
  // Build scripts.
  'cmakelists.txt': Icons.build_outlined,
  'gnumakefile': Icons.build_outlined,
  'justfile': Icons.build_outlined,
  'makefile': Icons.build_outlined,
  'rakefile': Icons.build_outlined,
  // Git.
  '.gitattributes': Icons.commit,
  '.gitignore': Icons.commit,
  '.gitkeep': Icons.commit,
  '.gitmodules': Icons.commit,
  // Environment files.
  '.env': Icons.tune,
  '.env.development': Icons.tune,
  '.env.example': Icons.tune,
  '.env.local': Icons.tune,
  '.env.production': Icons.tune,
  '.env.test': Icons.tune,
  // Tool configuration.
  '.editorconfig': Icons.settings_outlined,
  '.npmrc': Icons.settings_outlined,
  '.nvmrc': Icons.settings_outlined,
  '.prettierrc': Icons.settings_outlined,
  'analysis_options.yaml': Icons.settings_outlined,
  // Shell startup files.
  '.bash_profile': Icons.terminal,
  '.bashrc': Icons.terminal,
  '.profile': Icons.terminal,
  '.zprofile': Icons.terminal,
  '.zshrc': Icons.terminal,
};
