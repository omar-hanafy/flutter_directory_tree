/// Enforces repository rules that neither lints nor tests can express.
///
/// Repository checks run with `dart run tool/check_repo.dart`. They are
/// deterministic and need no network:
/// - no em-dash character (U+2014) in text files Git tracks or would track
///   (tracked plus untracked files that `.gitignore` does not exclude);
/// - CHANGELOG.md has a section for the pubspec version, and its first
///   section is either that version or `Unreleased` (`## 2.0.0`,
///   `## [2.0.0] - 2026-10-29`, and `## [Unreleased]` are all recognized);
/// - nothing under `lib/` imports a platform-specific `dart:` library, so
///   the main library runs on every platform, including the web and Wasm.
///   The file system library (`lib/io.dart` and `lib/src/io/`) may import
///   `dart:io` and `package:directory_tree/io.dart`; no other file under
///   `lib/` imports either of them or the file system library itself;
/// - every `@Deprecated` under `lib/` names its removal version as
///   "removed in X.0.0", and none survives into that major version.
///
/// Release checks run with `dart tool/check_repo.dart --release`, before
/// dependencies are resolved: plain `dart` (unlike `dart run`) does not
/// resolve them, and a development override points at a directory that
/// exists only on the developer's machine. They require that the package
/// resolves from pub.dev exactly as its users resolve it:
/// - no `pubspec_overrides.yaml` exists anywhere in the repository;
/// - `pubspec.yaml` has no `path` or `git` dependency and no
///   `dependency_overrides` section.
///
/// Both modes check the repository that contains this script, whatever the
/// current directory is. They print every failure and exit non-zero when any
/// check fails.
library;

import 'dart:io';

/// Every failure found so far, printed together at the end.
final List<String> _errors = <String>[];

const String _usage = 'Usage: dart run tool/check_repo.dart [--release]';

/// Libraries that only some platforms provide: native platforms (`dart:io`,
/// `dart:ffi`, `dart:isolate`, ...) or the web (`dart:html`, `dart:ui_web`,
/// ...). Every `dart:js` library is web-only too; see [_isPlatformLibrary].
const Set<String> _platformLibraries = <String>{
  'dart:cli',
  'dart:ffi',
  'dart:html',
  'dart:indexed_db',
  'dart:io',
  'dart:isolate',
  'dart:mirrors',
  'dart:nativewrappers',
  'dart:svg',
  'dart:ui_web',
  'dart:web_audio',
  'dart:web_gl',
};

/// The file system library and its implementation files, the only files
/// under `lib/` that may use `dart:io`.
const String _ioLibrary = 'lib/io.dart';
const String _ioDirectory = 'lib/src/io/';
const String _packageUriPrefix = 'package:flutter_directory_tree/';

/// The `pubspec.yaml` sections whose entries name dependencies.
const Set<String> _dependencySections = <String>{
  'dependencies',
  'dev_dependencies',
};

/// Runs the repository checks, or the release checks with `--release`.
void main(List<String> arguments) {
  if (arguments.contains('-h') || arguments.contains('--help')) {
    stdout.writeln(_usage);
    return;
  }
  final unknown = arguments.where((argument) => argument != '--release');
  if (unknown.isNotEmpty) {
    stderr
      ..writeln('Unknown argument: ${unknown.first}')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }

  final script = Platform.script;
  if (script.isScheme('file')) {
    Directory.current = File.fromUri(script).parent.parent;
  }

  final String title;
  if (arguments.contains('--release')) {
    title = 'Release checks';
    _checkReleaseDependencies();
  } else {
    title = 'Repository checks';
    final version = _pubspecVersion();
    _checkEmDashes();
    if (version != null) {
      _checkChangelog(version);
      _checkDeprecations(version);
    }
    _checkPlatformImports();
  }

  if (_errors.isEmpty) {
    stdout.writeln('$title passed.');
    return;
  }
  stderr.writeln('$title failed:');
  for (final error in _errors) {
    stderr.writeln('  - $error');
  }
  exitCode = 1;
}

String? _pubspecVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _errors.add('pubspec.yaml is missing.');
    return null;
  }
  final match = RegExp(
    r'''^version:[ \t]*['"]?([^'"\s#]+)['"]?[ \t]*(?:#.*)?$''',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  if (match == null) _errors.add('pubspec.yaml has no version line.');
  return match?.group(1);
}

/// Tracked files plus untracked files that are not ignored, so a new file
/// fails locally before it is committed, exactly as it will in CI.
List<String> _repositoryFiles() {
  final ProcessResult result;
  try {
    result = Process.runSync('git', <String>[
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
  } on ProcessException catch (error) {
    _errors.add('git is not available: ${error.message}');
    return const <String>[];
  }
  if (result.exitCode != 0) {
    _errors.add('git ls-files failed: ${result.stderr}');
    return const <String>[];
  }
  final output = result.stdout;
  if (output is! String) return const <String>[];
  return output
      .split('\u0000')
      .where((path) => path.isNotEmpty && File(path).existsSync())
      .toSet()
      .toList();
}

void _checkEmDashes() {
  for (final path in _repositoryFiles()) {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on FileSystemException {
      continue; // Unreadable, or not valid UTF-8 (a binary file).
    } on FormatException {
      continue;
    }
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('\u2014')) {
        _errors.add("$path:${i + 1}: em-dash character; use '-' instead.");
      }
    }
  }
}

void _checkChangelog(String version) {
  final changelog = File('CHANGELOG.md');
  if (!changelog.existsSync()) {
    _errors.add('CHANGELOG.md is missing.');
    return;
  }
  final sections = _changelogSections(changelog.readAsLinesSync());
  if (!sections.contains(version)) {
    _errors.add('CHANGELOG.md has no "## $version" section.');
  }
  if (sections.isNotEmpty &&
      sections.first != version &&
      sections.first != 'Unreleased') {
    _errors.add(
      'CHANGELOG.md starts with the "${sections.first}" section; the first '
      'section must be "## $version" or "## Unreleased".',
    );
  }
}

/// The version, or `Unreleased`, that each level-2 heading outside fenced
/// code blocks names, in order. `## 2.0.0`, `## [2.0.0] - 2026-10-29`, and
/// `## v2.0.0 (2026-10-29)` all name `2.0.0`.
List<String> _changelogSections(List<String> lines) {
  final heading = RegExp(r'^##[ \t]+\[?v?([^\]\s]+)');
  final sections = <String>[];
  var inFence = false;
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final match = heading.firstMatch(line);
    if (match != null) sections.add(match.group(1)!);
  }
  return sections;
}

bool _isPlatformLibrary(String uri) =>
    _platformLibraries.contains(uri) ||
    uri == 'dart:js' ||
    uri.startsWith('dart:js_');

/// Whether [uri] is the core package's `dart:io` scanner library or one of
/// its implementation files.
bool _isCoreIoLibrary(String uri) =>
    uri == 'package:directory_tree/io.dart' ||
    uri.startsWith('package:directory_tree/src/io/');

void _checkPlatformImports() {
  // One directive, possibly spread over several lines, up to its `;`.
  // Conditional imports carry extra URIs after `if (...)`.
  final directive = RegExp(
    r'^[ \t]*(?:import|export|part)\b[^;]*;',
    multiLine: true,
  );
  final quotedUri = RegExp('''['"]([^'"]+)['"]''');
  for (final file in _dartFilesUnder('lib')) {
    final path = _posix(file.path);
    final inIoLibrary = path == _ioLibrary || path.startsWith(_ioDirectory);
    final text = file.readAsStringSync();
    for (final match in directive.allMatches(text)) {
      final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
      final where = '$path:$line';
      for (final uriMatch in quotedUri.allMatches(match.group(0)!)) {
        final uri = uriMatch.group(1)!;
        if (inIoLibrary) {
          if (_isPlatformLibrary(uri) && uri != 'dart:io') {
            _errors.add(
              '$where: $uri is platform-specific; the file system library '
              'may import dart:io only.',
            );
          }
        } else if (uri == 'dart:io' || _isCoreIoLibrary(uri)) {
          final what = uri == 'dart:io' ? 'dart:io' : '$uri (it uses dart:io)';
          _errors.add(
            '$where: imports $what; only $_ioLibrary and $_ioDirectory may, '
            'so the main library runs on the web.',
          );
        } else if (_isPlatformLibrary(uri)) {
          _errors.add(
            '$where: $uri is platform-specific; lib/ must run on every '
            'platform.',
          );
        } else if (_isIoLibraryFile(path, uri)) {
          _errors.add(
            '$where: imports or exports the file system library ($uri); '
            'the main library must not depend on dart:io.',
          );
        }
      }
    }
  }
}

/// Whether [uri], written in the file at [fromPath], refers to the file
/// system library or one of its implementation files.
bool _isIoLibraryFile(String fromPath, String uri) {
  final String target;
  if (uri.startsWith(_packageUriPrefix)) {
    target = 'lib/${uri.substring(_packageUriPrefix.length)}';
  } else if (uri.contains(':')) {
    return false; // Another package or a dart: library.
  } else {
    target = Uri.parse(fromPath).resolve(uri).path;
  }
  return target == _ioLibrary || target.startsWith(_ioDirectory);
}

void _checkDeprecations(String version) {
  final major = int.tryParse(version.split('.').first);
  final annotation = RegExp(r'@Deprecated\(');
  final bareAnnotation = RegExp(r'@deprecated\b');
  final removal = RegExp(r'removed in (\d+)\.0\.0');
  for (final file in _dartFilesUnder('lib')) {
    final path = _posix(file.path);
    final text = file.readAsStringSync();
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (_isComment(lines[i])) continue;
      if (bareAnnotation.hasMatch(lines[i])) {
        _errors.add(
          '$path:${i + 1}: use @Deprecated("... removed in X.0.0") instead '
          'of @deprecated, so the removal version is stated.',
        );
      }
    }
    for (final match in annotation.allMatches(text)) {
      final lineStart = text.lastIndexOf('\n', match.start) + 1;
      if (_isComment(text.substring(lineStart, match.start))) continue;
      final line = '\n'.allMatches(text.substring(0, lineStart)).length + 1;
      final where = '$path:$line';
      // Only this annotation's own message counts, even when it wraps onto
      // later lines or is split into adjacent string literals.
      final target = removal.firstMatch(_annotationMessage(text, match.end));
      if (target == null) {
        _errors.add('$where: @Deprecated must say "removed in X.0.0".');
      } else if (major != null && int.parse(target.group(1)!) <= major) {
        _errors.add(
          '$where: deprecated for removal in ${target.group(1)}.0.0, but '
          'the package is at $version. Delete it and its dart fix shim test.',
        );
      }
    }
  }
}

bool _isComment(String line) => line.trimLeft().startsWith('//');

/// The concatenated string literals of an annotation's arguments, which
/// start at [start] (just after the opening parenthesis) and end at the
/// matching closing parenthesis. Parentheses inside string literals do not
/// end the arguments.
String _annotationMessage(String text, int start) {
  final message = StringBuffer();
  var depth = 1;
  var i = start;
  while (i < text.length && depth > 0) {
    final char = text[i];
    if (char == "'" || char == '"') {
      var close = i + 1;
      while (close < text.length && text[close] != char) {
        if (text[close] == r'\') close++;
        close++;
      }
      message.write(text.substring(i + 1, close.clamp(i + 1, text.length)));
      i = close + 1;
      continue;
    }
    if (char == '(') depth++;
    if (char == ')') depth--;
    i++;
  }
  return message.toString();
}

void _checkReleaseDependencies() {
  for (final path in _filesNamed('pubspec_overrides.yaml')) {
    _errors.add(
      '$path: development override; delete every pubspec_overrides.yaml '
      'before releasing, so dependencies resolve from pub.dev.',
    );
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    _errors.add('pubspec.yaml is missing.');
    return;
  }
  final lines = pubspec.readAsLinesSync();
  final reported = <String>{};
  String? section;
  String? dependency;
  int? entryIndent;
  for (var i = 0; i < lines.length; i++) {
    final line = _withoutYamlComment(lines[i]);
    if (line.trim().isEmpty) continue;
    final where = 'pubspec.yaml:${i + 1}';
    final indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      section = _yamlKey(line);
      dependency = null;
      entryIndent = null;
      if (section == 'dependency_overrides') {
        _errors.add(
          '$where: dependency_overrides; remove them before releasing, so '
          'tests run against the versions users resolve.',
        );
      }
      continue;
    }
    if (!_dependencySections.contains(section)) continue;
    entryIndent ??= indent;
    final String? source;
    if (indent <= entryIndent) {
      // A dependency entry; its source may be an inline map:
      // `name: {path: ../name}`.
      dependency = _yamlKey(line);
      source = RegExp(r'[{,][ \t]*(path|git)[ \t]*:').firstMatch(line)?[1];
    } else {
      source = RegExp(r'^[ \t]*(path|git)[ \t]*:').firstMatch(line)?[1];
    }
    if (source != null && dependency != null && reported.add(dependency)) {
      _errors.add(
        '$where: $dependency is a $source dependency in $section; depend on '
        'a pub.dev version before releasing.',
      );
    }
  }
}

/// The key of a YAML mapping line (`name` for `  name: value`), or null.
String? _yamlKey(String line) =>
    RegExp(r'^[ \t]*([^\s:#{}\[\],]+)[ \t]*:').firstMatch(line)?[1];

/// [line] without its YAML comment: a `#` that starts the line or follows
/// whitespace starts a comment.
String _withoutYamlComment(String line) {
  final match = RegExp(r'(?:^|[ \t])#').firstMatch(line);
  return match == null ? line : line.substring(0, match.start);
}

/// The repository-relative paths of all files called [name], sorted.
///
/// Hidden directories (`.git`, `.dart_tool`, agent worktrees under
/// `.claude/`) and `build` directories hold no sources and are skipped.
List<String> _filesNamed(String name) {
  final found = <String>[];
  final pending = <Directory>[Directory('.')];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    for (final entity in directory.listSync(followLinks: false)) {
      final path = _posix(entity.path);
      final base = path.substring(path.lastIndexOf('/') + 1);
      if (entity is Directory) {
        if (!base.startsWith('.') && base != 'build') pending.add(entity);
      } else if (base == name) {
        found.add(path.startsWith('./') ? path.substring(2) : path);
      }
    }
  }
  return found..sort();
}

Iterable<File> _dartFilesUnder(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const <File>[];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}

String _posix(String path) => path.replaceAll(r'\', '/');
