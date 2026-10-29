/// The ordinary form of the Windows extended-length path [path]:
/// `\\?\C:\a` becomes `C:\a` and `\\?\UNC\server\share\a` becomes
/// `\\server\share\a`.
///
/// Every other string, including other device paths such as
/// `\\?\Volume{...}\` and paths without the prefix, is returned unchanged.
/// `DirectoryScanner` (from `package:directory_tree/io.dart`) retries a
/// listing that fails past `MAX_PATH` through the extended-length form and
/// reports the error of that retry, so the loader turns error paths into
/// this form before comparing them with the paths it listed. The same rule
/// as the core's own helper, which its `io.dart` does not export. Pure
/// string work.
String windowsOrdinaryPath(String path) {
  if (path.startsWith(r'\\?\UNC\')) return '\\\\${path.substring(8)}';
  if (path.startsWith(r'\\?\') && _isDriveRoot(path.substring(4))) {
    return path.substring(4);
  }
  return path;
}

/// Whether [path] starts with a drive letter, a colon, and a backslash.
bool _isDriveRoot(String path) {
  if (path.length < 3) return false;
  final letter = path.codeUnitAt(0) | 0x20; // Lowercases ASCII letters.
  return letter >= 0x61 && // a
      letter <= 0x7A && // z
      path.codeUnitAt(1) == 0x3A && // :
      path.codeUnitAt(2) == 0x5C; // \
}
