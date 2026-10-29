import 'package:flutter_directory_tree/src/io/windows_ordinary_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips the extended-length prefix of drive and UNC paths', () {
    expect(windowsOrdinaryPath(r'\\?\C:\a\b'), r'C:\a\b');
    expect(windowsOrdinaryPath(r'\\?\c:\'), r'c:\');
    expect(windowsOrdinaryPath(r'\\?\UNC\server\share\a'), r'\\server\share\a');
  });

  test('keeps every other path as it is', () {
    for (final path in [
      r'C:\a\b',
      r'\\server\share\a',
      r'\\?\Volume{1234}\a',
      r'\\?\C:',
      r'\\.\C:\a',
      '/home/me/a',
      '',
    ]) {
      expect(windowsOrdinaryPath(path), path, reason: path);
    }
  });
}
