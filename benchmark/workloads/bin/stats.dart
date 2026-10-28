import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';

/// Prints a summary of every standard workload (shape x size), including the
/// counts each operation must report.
///
/// Usage: `dart run bin/stats.dart [size ...]`, for example
/// `dart run bin/stats.dart 10k 100k`.
void main(List<String> args) {
  final sizes = args.isEmpty ? standardSizes : args.map(_parseCount).toList();
  for (final shape in WorkloadShape.values) {
    for (final size in sizes) {
      final sw = Stopwatch()..start();
      final w = Workload.generate(shape, size);
      final generateMs = sw.elapsedMilliseconds;
      final expected = WorkloadExpectations(w);
      final entries = <String, int>{};
      final fileDepths = <int, int>{};
      for (final path in w.paths) {
        final dir = path.substring(0, path.lastIndexOf('/'));
        entries[dir] = (entries[dir] ?? 0) + 1;
        final depth = '/'.allMatches(path).length - 1;
        fileDepths[depth] = (fileDepths[depth] ?? 0) + 1;
      }
      final perDir = entries.values.toList()..sort();
      print({
        ...w.describe(),
        'generate_ms': generateMs,
        'rows_top_level': expected.topLevelRows,
        'rows_all': expected.allRows,
        'rows_after_toggle': expected.toggleRows,
        'rows_after_filter': expected.filterRows,
        'selected_by_range': expected.selectRangeCount,
        'dirs_with_files': perDir.length,
        'files_per_dir_p10_p50_p90_max': [
          perDir[perDir.length ~/ 10],
          perDir[perDir.length ~/ 2],
          perDir[perDir.length * 9 ~/ 10],
          perDir.last,
        ],
        'file_depths': (fileDepths.keys.toList()..sort())
            .map((d) => '$d:${fileDepths[d]}')
            .join(' '),
      });
    }
  }
}

int _parseCount(String raw) {
  final s = raw.trim().toLowerCase();
  final multiplier = s.endsWith('k')
      ? 1000
      : s.endsWith('m')
      ? 1000000
      : 1;
  final digits = multiplier == 1 ? s : s.substring(0, s.length - 1);
  return int.parse(digits) * multiplier;
}
