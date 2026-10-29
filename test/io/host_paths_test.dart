import 'package:flutter_directory_tree/src/io/host_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('windowsExtendedLengthPath', () {
    test('prefixes drive and UNC paths and normalizes their segments', () {
      expect(windowsExtendedLengthPath(r'C:\a\b'), r'\\?\C:\a\b');
      expect(windowsExtendedLengthPath('C:/a/./b//c/../d'), r'\\?\C:\a\b\d');
      expect(windowsExtendedLengthPath(r'c:\'), r'\\?\c:\');
      expect(windowsExtendedLengthPath(r'C:\a\..\..'), r'\\?\C:\');
      expect(
        windowsExtendedLengthPath(r'\\server\share\a'),
        r'\\?\UNC\server\share\a',
      );
      expect(
        windowsExtendedLengthPath('//server/share'),
        r'\\?\UNC\server\share\',
      );
    });

    test('has no form for relative, drive-relative, and device paths', () {
      for (final path in [
        r'a\b',
        'C:a',
        r'\a',
        r'\\server',
        r'\\server\',
        r'\\?\C:\a',
        r'\\.\C:\a',
        '',
      ]) {
        expect(windowsExtendedLengthPath(path), isNull, reason: path);
      }
    });
  });

  group('posixTreeSpelling', () {
    test('reads a leading // as / and a drive spec as a relative name', () {
      expect(posixTreeSpelling('//x/y'), '/x/y');
      expect(posixTreeSpelling('//'), '/');
      expect(posixTreeSpelling('C:'), './C:');
      expect(posixTreeSpelling('c:/x'), './c:/x');
    });

    test('keeps every other path', () {
      for (final path in [
        '/a/b',
        '///x',
        'C:x',
        r'C:\x',
        'a/c:',
        './c:',
        '',
        'c',
      ]) {
        expect(posixTreeSpelling(path), path, reason: path);
      }
    });
  });
}
