import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';

import 'coordinator.dart';

/// The implementations the report has columns for, in column order.
const List<String> knownImplementations = ['v1', 'v2'];

/// The modes, in report order, with their section titles.
const Map<String, String> knownModes = {
  'aot': 'AOT: macOS profile build',
  'jit': 'JIT: flutter test (debug mode)',
};

/// The key that identifies a measurement across runs.
String recordKey(BenchRecord r) =>
    '${r['implementation']}|${r['mode']}|${r['shape']}|${r['size']}|'
    '${r['operation']}';

/// Merges [fresh] into [existing]: a fresh record replaces an existing one
/// with the same [recordKey]. The result is sorted for stable output.
List<BenchRecord> mergeRecords(
  List<BenchRecord> existing,
  List<BenchRecord> fresh,
) {
  final byKey = {for (final r in existing) recordKey(r): r};
  for (final r in fresh) {
    byKey[recordKey(r)] = r;
  }
  return byKey.values.toList()..sort(_compareRecords);
}

int _indexOr(List<String> order, Object? value) {
  final i = order.indexOf('$value');
  return i == -1 ? order.length : i;
}

int _compareRecords(BenchRecord a, BenchRecord b) {
  final modes = knownModes.keys.toList();
  final shapes = [for (final s in WorkloadShape.values) s.name];
  final steps = [
    _indexOr(modes, a['mode']) - _indexOr(modes, b['mode']),
    _indexOr(shapes, a['shape']) - _indexOr(shapes, b['shape']),
    (a['size'] as int? ?? 0) - (b['size'] as int? ?? 0),
    _indexOr(standardOperations, a['operation']) -
        _indexOr(standardOperations, b['operation']),
    _indexOr(knownImplementations, a['implementation']) -
        _indexOr(knownImplementations, b['implementation']),
  ];
  for (final step in steps) {
    if (step != 0) return step;
  }
  return '${a['implementation']}|${a['mode']}'.compareTo(
    '${b['implementation']}|${b['mode']}',
  );
}

/// Formats milliseconds with precision that suits the magnitude.
String formatMs(num ms) {
  if (ms >= 100) return _thousands(ms.round());
  if (ms >= 1) return ms.toStringAsFixed(2);
  return ms.toStringAsFixed(3);
}

String _thousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// The table cell for one record's median.
String medianCell(BenchRecord? r) {
  if (r == null) return '';
  final median = r['median_ms'];
  if (median is num) return formatMs(median);
  final timeout = r['timeout_ms'];
  final blockedBy = r['blocked_by'];
  if (timeout is num) {
    return blockedBy != null
        ? 'timeout (blocked by $blockedBy)'
        : '> ${formatMs(timeout)} (timeout)';
  }
  if (r['error'] != null) {
    return blockedBy != null ? 'error (blocked by $blockedBy)' : 'error';
  }
  // The implementation cannot measure the operation yet; the details table
  // gives the reason.
  if (r['unavailable'] != null) return 'not available';
  return '';
}

/// The table cell for one record's fastest run.
String minCell(BenchRecord? r) {
  final min = r?['min_ms'];
  return min is num ? formatMs(min) : medianCell(r);
}

/// The speedup of [v2] over [v1] (v1 [field] / v2 [field], `median_ms` by
/// default).
///
/// When v1 itself exceeded the budget, the speedup is at least budget / v2.
/// An operation that was only blocked by a failed prerequisite never ran,
/// so it gets no speedup.
String speedupCell(
  BenchRecord? v1,
  BenchRecord? v2, {
  String field = 'median_ms',
}) {
  final v2Value = v2?[field];
  if (v1 == null || v2Value is! num || v2Value <= 0) return '';
  final v1Value = v1[field];
  if (v1Value is num) return '${_ratio(v1Value / v2Value)}x';
  final timeout = v1['timeout_ms'];
  if (timeout is num && v1['blocked_by'] == null) {
    return '> ${_ratio(timeout / v2Value)}x';
  }
  return '';
}

String _ratio(double r) =>
    r >= 100 ? _thousands(r.round()) : r.toStringAsFixed(r >= 10 ? 1 : 2);

/// The fields that describe the measurement rather than its result.
const Set<String> _known = {
  'implementation', 'mode', 'build_mode', 'shape', 'size', 'operation', //
  'runs', 'warmup', 'budget_ms', 'seed', 'fingerprint', 'median_ms', 'min_ms',
  'max_ms', 'machine', 'os', 'flutter', 'dart', 'timeout_ms', 'timeout_phase',
  'blocked_by', 'completed_runs', 'error', 'unavailable',
};

/// The problems with [records]' counts, checked against each workload's
/// [WorkloadExpectations] (one message per record that disagrees).
List<String> countProblems(
  List<BenchRecord> records,
  Map<String, WorkloadExpectations> expectations,
) {
  final problems = <String>[];
  for (final r in records) {
    if (r['median_ms'] is! num) continue;
    final expected = expectations['${r['shape']}|${r['size']}|${r['seed']}'];
    if (expected == null) continue;
    final found = expected.check('${r['operation']}', r);
    if (found.isNotEmpty) {
      problems.add(
        '${r['implementation']} ${r['mode']} ${r['operation']} '
        '${r['shape']} ${r['size']}: ${found.join('; ')}',
      );
    }
  }
  return problems;
}

/// Renders RESULTS.md from [records] (in any order), with one row per
/// workload of [workloads] in the workload table and the count checks
/// against [expectations] (keyed `shape|size|seed`).
String renderMarkdown(
  List<BenchRecord> unsorted, {
  required List<Workload> workloads,
  required Map<String, WorkloadExpectations> expectations,
  required DateTime generatedAt,
}) {
  final records = [...unsorted]..sort(_compareRecords);
  final b = StringBuffer()
    ..writeln('# Benchmark results')
    ..writeln()
    ..writeln(
      'Generated by `benchmark/runner` on '
      '${generatedAt.toIso8601String().substring(0, 10)}. '
      'See `benchmark/README.md` for what each operation measures. '
      'Raw records: `benchmark/results.jsonl`.',
    )
    ..writeln();

  String host(BenchRecord r) =>
      '${r['machine'] ?? 'unknown machine'}; ${r['os'] ?? 'unknown OS'}; '
      '${r['flutter'] ?? 'unknown Flutter SDK'}';
  // Records the runner wrote for a process that never started have no Dart
  // version; they only add a line when no other record shares their host.
  final hostsWithDart = {
    for (final r in records)
      if (r['dart'] != null) host(r),
  };
  final envs = <String>{
    for (final r in records)
      if (r['dart'] != null)
        '${host(r)}; Dart ${r['dart']}'
      else if (!hostsWithDart.contains(host(r)))
        '${host(r)}; Dart unknown',
  };
  b
    ..writeln('## Environment')
    ..writeln();
  for (final env in envs) {
    b.writeln('- $env');
  }
  if (envs.length > 1) {
    b
      ..writeln()
      ..writeln(
        '> Records come from more than one environment; compare columns '
        'only when they share one (see the details table).',
      );
  }
  final settings = {
    for (final r in records)
      'warm-up ${r['warmup']}, timed runs ${r['runs']}, budget '
          '${r['budget_ms'] is num ? formatMs(r['budget_ms']! as num) : '?'} '
          'ms per step',
  };
  b
    ..writeln()
    ..writeln('Settings: ${settings.join(' / ')}.')
    ..writeln()
    ..writeln(
      'Controller operations: wall time of the command. Frame operations '
      '(`first_frame`, `jump_middle`, `jump_end`): UI-thread time of the '
      'measured frame (build, layout, paint, composite; no raster time).',
    );

  for (final MapEntry(key: mode, value: title) in knownModes.entries) {
    final inMode = [
      for (final r in records)
        if (r['mode'] == mode) r,
    ];
    if (inMode.isEmpty) continue;
    final groups = <String, Map<String, BenchRecord>>{};
    for (final r in inMode) {
      final key = '${r['shape']}|${r['size']}|${r['operation']}';
      (groups[key] ??= {})['${r['implementation']}'] = r;
    }

    void table(String label, String Function(BenchRecord?) cell, String field) {
      b
        ..writeln(
          '| operation | shape | size | v1 $label (ms) | v2 $label (ms) '
          '| speedup |',
        )
        ..writeln('|---|---|---:|---:|---:|---:|');
      for (final group in groups.values) {
        final any = group.values.first;
        final v1 = group['v1'];
        final v2 = group['v2'];
        b.writeln(
          '| ${any['operation']} | ${any['shape']} '
          '| ${_thousands(any['size']! as int)} | ${cell(v1)} | ${cell(v2)} '
          '| ${speedupCell(v1, v2, field: field)} |',
        );
      }
    }

    b
      ..writeln()
      ..writeln('## $title')
      ..writeln()
      ..writeln(
        'Median per operation in milliseconds. Speedup = v1 median / v2 '
        'median.',
      )
      ..writeln();
    table('median', medianCell, 'median_ms');
    b
      ..writeln()
      ..writeln('### Fastest run ($mode)')
      ..writeln()
      ..writeln(
        'Minimum over the timed runs, less sensitive to garbage collection '
        'pauses on the large workloads. Speedup = v1 min / v2 min.',
      )
      ..writeln();
    table('min', minCell, 'min_ms');
  }

  final fingerprints = <String, Set<Object?>>{};
  for (final r in records) {
    if (r['fingerprint'] == null) continue;
    (fingerprints['${r['shape']} ${r['size']}'] ??= {}).add(r['fingerprint']);
  }
  final mismatched = [
    for (final e in fingerprints.entries)
      if (e.value.length > 1) e.key,
  ];
  if (mismatched.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        '> Warning: workload fingerprints differ between records for '
        '${mismatched.join(', ')}; those comparisons are not like for like.',
      );
  }

  b
    ..writeln()
    ..writeln('## Workloads')
    ..writeln()
    ..writeln(
      '| shape | size | folders | rows (all expanded) | max file depth '
      '| toggle target (rows below) | filter query (matching files, rows) '
      '| fingerprint |',
    )
    ..writeln('|---|---:|---:|---:|---:|---|---|---|');
  for (final w in workloads) {
    final e = expectations['${w.shape.name}|${w.size}|${w.seed}'];
    b.writeln(
      '| ${w.shape.name} | ${_thousands(w.size)} | ${_thousands(w.folderCount)} '
      '| ${e == null ? '' : _thousands(e.allRows)} | ${w.maxFileDepth} '
      '| `${w.toggleTarget}` '
      '(${e == null ? '' : _thousands(e.toggleHiddenRows)}) '
      '| `${w.filterQuery}` (${_thousands(w.filterMatchCount)}, '
      '${e == null ? '' : _thousands(e.filterRows)}) '
      '| `${w.fingerprint}` |',
    );
  }

  final problems = countProblems(records, expectations);
  b
    ..writeln()
    ..writeln('## Count checks')
    ..writeln();
  if (problems.isEmpty) {
    b.writeln(
      'Every measured record reports the counts `WorkloadExpectations` '
      'derives from the paths.',
    );
  } else {
    b.writeln('Records whose counts disagree with `WorkloadExpectations`:');
    b.writeln();
    for (final problem in problems) {
      b.writeln('- $problem');
    }
  }

  b
    ..writeln()
    ..writeln('## Details')
    ..writeln()
    ..writeln(
      '| implementation | mode | operation | shape | size | median | min '
      '| max | result counts / failure |',
    )
    ..writeln('|---|---|---|---|---:|---:|---:|---:|---|');
  for (final r in records) {
    String ms(String key) => r[key] is num ? formatMs(r[key]! as num) : '';
    final counts = [
      for (final e in r.entries)
        if (!_known.contains(e.key)) '${e.key} ${e.value}',
    ];
    final failure = [
      if (r['timeout_phase'] != null) 'timeout in ${r['timeout_phase']}',
      if (r['completed_runs'] != null) '${r['completed_runs']} runs done',
      if (r['blocked_by'] != null) 'blocked by ${r['blocked_by']}',
      if (r['error'] != null && r['blocked_by'] == null)
        'error: ${_escape('${r['error']}')}',
      if (r['unavailable'] != null)
        'not available: ${_escape('${r['unavailable']}')}',
    ];
    b.writeln(
      '| ${r['implementation']} | ${r['mode']} | ${r['operation']} '
      '| ${r['shape']} | ${_thousands(r['size']! as int)} | ${ms('median_ms')} '
      '| ${ms('min_ms')} | ${ms('max_ms')} | ${[...counts, ...failure].join(', ')} |',
    );
  }
  return b.toString();
}

String _escape(String s) {
  final oneLine = s.replaceAll('|', r'\|').replaceAll('\n', ' ');
  return oneLine.length > 200 ? '${oneLine.substring(0, 200)}...' : oneLine;
}
