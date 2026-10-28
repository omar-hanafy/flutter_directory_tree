import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/src/theme/directory_tree_icon_set.dart';
import 'package:flutter_test/flutter_test.dart';

const IconData _file = IconData(0xe001);
const IconData _folder = IconData(0xe002);
const IconData _folderOpen = IconData(0xe003);
const IconData _gz = IconData(0xe004);
const IconData _tarGz = IconData(0xe005);
const IconData _json = IconData(0xe006);
const IconData _readme = IconData(0xe007);
const IconData _markdown = IconData(0xe008);
const IconData _hidden = IconData(0xe009);

const DirectoryTreeIconSet _custom = DirectoryTreeIconSet(
  file: _file,
  folder: _folder,
  folderOpen: _folderOpen,
  extensions: {
    'gz': _gz,
    'tar.gz': _tarGz,
    'json': _json,
    'md': _markdown,
    'gitignore': _hidden,
  },
  names: {'readme.md': _readme},
);

TreeNode<Object?> _fileNode(String name) =>
    DirectoryTree.fromPaths(['/repo/$name']).nodeAt('/repo/$name')!;

TreeNode<Object?> _directoryNode(String name) =>
    DirectoryTree.fromPaths(['/repo/$name/']).nodeAt('/repo/$name')!;

IconData _iconOf(
  DirectoryTreeIconSet icons,
  String name, {
  bool expanded = false,
}) => icons.iconFor(_fileNode(name), expanded: expanded);

void main() {
  group('iconFor', () {
    test('gives directories the folder icons by expansion', () {
      final lib = _directoryNode('lib');
      expect(lib.isDirectory, isTrue);
      expect(_custom.iconFor(lib, expanded: false), _folder);
      expect(_custom.iconFor(lib, expanded: true), _folderOpen);
      expect(
        DirectoryTreeIconSet.material.iconFor(lib, expanded: false),
        Icons.folder_outlined,
      );
      expect(
        DirectoryTreeIconSet.material.iconFor(lib, expanded: true),
        Icons.folder_open_outlined,
      );
    });

    test('ignores names and extensions for directories', () {
      for (final name in ['README.md', 'archive.tar.gz', '.gitignore']) {
        final directory = _directoryNode(name);
        expect(directory.isDirectory, isTrue, reason: name);
        expect(_custom.iconFor(directory, expanded: false), _folder);
        expect(_custom.iconFor(directory, expanded: true), _folderOpen);
      }
    });

    test('matches whole names before extensions', () {
      expect(_iconOf(_custom, 'readme.md'), _readme);
      expect(_iconOf(_custom, 'notes.md'), _markdown);
    });

    test('picks the longest matching extension', () {
      expect(_iconOf(_custom, 'archive.tar.gz'), _tarGz);
      expect(_iconOf(_custom, 'my.backup.tar.gz'), _tarGz);
      expect(_iconOf(_custom, 'archive.gz'), _gz);
      // "tar" is the base name here, not an extension.
      expect(_iconOf(_custom, 'tar.gz'), _gz);
      expect(_iconOf(_custom, 'archive.tar'), _file);
    });

    test('ignores case in names and extensions', () {
      expect(_iconOf(_custom, 'README.md'), _readme);
      expect(_iconOf(_custom, 'ReadMe.MD'), _readme);
      expect(_iconOf(_custom, 'ARCHIVE.TAR.GZ'), _tarGz);
      expect(_iconOf(_custom, 'Data.Json'), _json);
      expect(
        _iconOf(DirectoryTreeIconSet.material, 'PHOTO.JPG'),
        Icons.image_outlined,
      );
      expect(
        _iconOf(DirectoryTreeIconSet.material, 'Dockerfile'),
        Icons.view_in_ar_outlined,
      );
    });

    test('matches dotfiles by name only', () {
      // A leading dot does not start an extension.
      expect(_iconOf(_custom, '.gitignore'), _file);
      expect(
        _iconOf(_custom.copyWith(names: {'.gitignore': _hidden}), '.gitignore'),
        _hidden,
      );
      // Later dots still do.
      expect(_iconOf(_custom, '.eslintrc.json'), _json);
      expect(_iconOf(_custom, '.archive.tar.gz'), _tarGz);
    });

    test('falls back to the file icon', () {
      expect(_iconOf(_custom, 'Makefile'), _file);
      expect(_iconOf(_custom, 'notes.txt'), _file);
      expect(_iconOf(_custom, 'trailing.'), _file);
      expect(_iconOf(_custom, 'a'), _file);
      const bare = DirectoryTreeIconSet(
        file: _file,
        folder: _folder,
        folderOpen: _folderOpen,
      );
      expect(_iconOf(bare, 'main.dart'), _file);
      expect(_iconOf(bare, 'readme.md'), _file);
    });

    test('ignores expanded for files', () {
      expect(_iconOf(_custom, 'notes.md', expanded: true), _markdown);
      expect(_iconOf(_custom, 'x.bin', expanded: true), _file);
    });

    test('accepts keys in any case and extension keys with a dot', () {
      const loose = DirectoryTreeIconSet(
        file: _file,
        folder: _folder,
        folderOpen: _folderOpen,
        extensions: {'PNG': _json, '.Txt': _markdown, '.TAR.GZ': _tarGz},
        names: {'MAKEFILE': _readme, '.GitIgnore': _hidden},
      );
      expect(_iconOf(loose, 'logo.png'), _json);
      expect(_iconOf(loose, 'notes.TXT'), _markdown);
      expect(_iconOf(loose, 'backup.tar.gz'), _tarGz);
      expect(_iconOf(loose, 'Makefile'), _readme);
      expect(_iconOf(loose, '.gitignore'), _hidden);
      // The public maps keep the spelling they were given.
      expect(loose.extensions.keys, contains('PNG'));
    });
  });

  group('material', () {
    test('covers common files by extension', () {
      final expected = <String, IconData>{
        'main.dart': Icons.code,
        'App.kt': Icons.code,
        'server.go': Icons.code,
        'app.js': Icons.javascript,
        'index.html': Icons.html,
        'style.scss': Icons.css,
        'index.php': Icons.php,
        'build.sh': Icons.terminal,
        'setup.ps1': Icons.terminal,
        'logo.png': Icons.image_outlined,
        'icon.svg': Icons.image_outlined,
        'paper.pdf': Icons.picture_as_pdf_outlined,
        'letter.docx': Icons.description_outlined,
        'notes.md': Icons.article_outlined,
        'notes.txt': Icons.text_snippet_outlined,
        'server.log': Icons.receipt_long_outlined,
        'deck.pptx': Icons.slideshow_outlined,
        'table.csv': Icons.table_chart_outlined,
        'budget.xlsx': Icons.table_chart_outlined,
        'data.json': Icons.data_object,
        'config.yaml': Icons.settings_outlined,
        'settings.toml': Icons.settings_outlined,
        'yarn.lock': Icons.lock_outline,
        'schema.sql': Icons.storage,
        'app_en.arb': Icons.translate,
        'server.pem': Icons.key,
        'archive.zip': Icons.folder_zip_outlined,
        'backup.tar.gz': Icons.folder_zip_outlined,
        'app-release.apk': Icons.android,
        'song.mp3': Icons.audio_file_outlined,
        'clip.mp4': Icons.video_file_outlined,
        'Inter.ttf': Icons.font_download_outlined,
        'unknown.xyz': Icons.insert_drive_file_outlined,
      };
      for (final MapEntry(key: name, value: icon) in expected.entries) {
        expect(
          _iconOf(DirectoryTreeIconSet.material, name),
          icon,
          reason: name,
        );
      }
    });

    test('covers well-known file names', () {
      final expected = <String, IconData>{
        'pubspec.yaml': Icons.inventory_2_outlined,
        'package.json': Icons.inventory_2_outlined,
        'package-lock.json': Icons.lock_outline,
        'pubspec.lock': Icons.lock_outline,
        'README.md': Icons.info_outline,
        'README': Icons.info_outline,
        'LICENSE': Icons.gavel,
        'LICENSE.txt': Icons.gavel,
        'CHANGELOG.md': Icons.history,
        'Dockerfile': Icons.view_in_ar_outlined,
        'docker-compose.yml': Icons.view_in_ar_outlined,
        'Makefile': Icons.build_outlined,
        'CMakeLists.txt': Icons.build_outlined,
        '.gitignore': Icons.commit,
        '.gitattributes': Icons.commit,
        '.env': Icons.tune,
        '.env.local': Icons.tune,
        '.editorconfig': Icons.settings_outlined,
        'analysis_options.yaml': Icons.settings_outlined,
        '.bashrc': Icons.terminal,
        '.unknownrc': Icons.insert_drive_file_outlined,
      };
      for (final MapEntry(key: name, value: icon) in expected.entries) {
        expect(
          _iconOf(DirectoryTreeIconSet.material, name),
          icon,
          reason: name,
        );
      }
    });

    test('keys are canonical: lowercase, extensions without a leading dot', () {
      for (final key in DirectoryTreeIconSet.material.extensions.keys) {
        expect(key, key.toLowerCase());
        expect(key.startsWith('.'), isFalse, reason: key);
        expect(key, isNot(endsWith('.')));
      }
      for (final key in DirectoryTreeIconSet.material.names.keys) {
        expect(key, key.toLowerCase());
      }
    });
  });

  group('value semantics', () {
    test('copyWith replaces the given fields', () {
      expect(_custom.copyWith(), _custom);
      final changed = _custom.copyWith(
        file: _json,
        folder: _readme,
        folderOpen: _markdown,
        extensions: const {'x': _gz},
        names: const {'y': _gz},
      );
      expect(changed.file, _json);
      expect(changed.folder, _readme);
      expect(changed.folderOpen, _markdown);
      expect(changed.extensions, const {'x': _gz});
      expect(changed.names, const {'y': _gz});
      expect(_iconOf(changed, 'a.x'), _gz);
      expect(_iconOf(changed, 'a.json'), _json);
    });

    test('== and hashCode compare map entries regardless of order', () {
      final a = DirectoryTreeIconSet(
        file: _file,
        folder: _folder,
        folderOpen: _folderOpen,
        extensions: {'a': _gz, 'b': _json},
        names: {'c': _readme},
      );
      final b = DirectoryTreeIconSet(
        file: _file,
        folder: _folder,
        folderOpen: _folderOpen,
        extensions: {'b': _json, 'a': _gz},
        names: {'c': _readme},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.copyWith(file: _json)));
      expect(a, isNot(b.copyWith(folder: _json)));
      expect(a, isNot(b.copyWith(folderOpen: _json)));
      expect(a, isNot(b.copyWith(extensions: {'a': _gz})));
      expect(a, isNot(b.copyWith(extensions: {'a': _gz, 'b': _readme})));
      expect(a, isNot(b.copyWith(names: {})));
      expect(
        DirectoryTreeIconSet.material.copyWith(),
        DirectoryTreeIconSet.material,
      );
    });

    test('toString names the material set and summarizes others', () {
      expect(
        DirectoryTreeIconSet.material.toString(),
        'DirectoryTreeIconSet.material',
      );
      expect(
        _custom.toString(),
        allOf(
          startsWith('DirectoryTreeIconSet(file: IconData(U+0E001)'),
          endsWith('extensions: 5, names: 1)'),
        ),
      );
    });
  });
}
