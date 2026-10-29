/// Host path spellings the loader needs to read paths as `dart:io` and
/// `DirectoryScanner` do. The same rules as the core's own helpers, which
/// `package:directory_tree/io.dart` does not export. Pure string work.
library;

/// The extended-length form of the absolute Windows path [path], or `null`
/// when [path] has none.
///
/// Forward slashes become backslashes, empty and `.` segments are dropped,
/// and `..` removes the previous segment (never the drive or the share),
/// because Windows applies none of these rules to a `\\?\` path. A drive
/// path `C:\a\b` becomes `\\?\C:\a\b` and a UNC path `\\server\share\a`
/// becomes `\\?\UNC\server\share\a`. `null` for relative paths,
/// drive-relative paths (`C:a`, `\a`), UNC paths without a share, and
/// paths that already use a device prefix (`\\?\` or `\\.\`).
///
/// `DirectoryScanner` retries a listing or a link that fails past
/// `MAX_PATH` through this form of the absolute path, and reports the
/// error of that retry with it.
String? windowsExtendedLengthPath(String path) {
  final normalized = path.replaceAll('/', r'\');
  if (normalized.startsWith(r'\\?\') || normalized.startsWith(r'\\.\')) {
    return null;
  }
  final String root;
  final Iterable<String> rest;
  if (_isDriveRoot(normalized)) {
    root = '\\\\?\\${normalized.substring(0, 3)}';
    rest = normalized.substring(3).split(r'\');
  } else if (normalized.startsWith(r'\\')) {
    final parts = normalized.substring(2).split(r'\');
    if (parts.length < 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    root = '\\\\?\\UNC\\${parts[0]}\\${parts[1]}';
    rest = parts.skip(2);
  } else {
    return null;
  }
  final segments = <String>[];
  for (final segment in rest) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  if (segments.isEmpty) return root.endsWith(r'\') ? root : '$root\\';
  final separator = root.endsWith(r'\') ? '' : r'\';
  return '$root$separator${segments.join(r'\')}';
}

/// [path], a Linux or macOS path, respelled so that path parsing reads it
/// as the location the host does.
///
/// Parsing applies Windows rules to two spellings that are ordinary paths
/// on these hosts: a leading `//` reads as a UNC root, where the host reads
/// `/`, and a relative first segment such as `C:` reads as a drive, where
/// the host reads a file name. So `//x` becomes `/x` (and `//` becomes
/// `/`), and a relative path whose first segment is a drive spec, such as
/// `C:` or `c:/x`, gets the prefix `./`. Every other path is returned
/// unchanged, including `///x`, which parsing already reads as `/x`, and
/// `C:x` or `C:\x`, which parsing already reads as relative names.
String posixTreeSpelling(String path) {
  if (path.startsWith('//') && !path.startsWith('///')) {
    return path.substring(1);
  }
  if (path.length >= 2 &&
      _isAsciiLetter(path.codeUnitAt(0)) &&
      path.codeUnitAt(1) == 0x3A && // :
      (path.length == 2 || path.codeUnitAt(2) == 0x2F)) {
    return './$path';
  }
  return path;
}

/// Whether [path] starts with a drive letter, a colon, and a backslash.
bool _isDriveRoot(String path) =>
    path.length >= 3 &&
    _isAsciiLetter(path.codeUnitAt(0)) &&
    path.codeUnitAt(1) == 0x3A && // :
    path.codeUnitAt(2) == 0x5C; // \

bool _isAsciiLetter(int unit) {
  final lower = unit | 0x20; // Lowercases ASCII letters.
  return lower >= 0x61 && lower <= 0x7A; // a to z
}
