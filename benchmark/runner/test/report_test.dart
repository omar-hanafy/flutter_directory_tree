import 'package:fdt_bench_runner/runner.dart';
import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';
import 'package:test/test.dart';

BenchRecord _record(
  String impl,
  String op, {
  String mode = 'aot',
  String shape = 'deep',
  int size = 10000,
  Map<String, Object?> fields = const {},
}) => {
  'implementation': impl,
  'mode': mode,
  'shape': shape,
  'size': size,
  'operation': op,
  'runs': 5,
  'warmup': 1,
  'budget_ms': 60000,
  'seed': Workload.defaultSeed,
  'fingerprint': '131893f6',
  'machine': 'Test CPU (arm64), 8 logical cores, 16 GB',
  'os': 'testOS 1',
  'flutter': 'Flutter 3.x (stable, framework abc, engine def)',
  'dart': '3.x (stable)',
  ...fields,
};

void main() {
  final workload = Workload.generate(WorkloadShape.deep, 10000);
  final expected = WorkloadExpectations(workload);
  final expectations = {'deep|10000|${Workload.defaultSeed}': expected};

  test('mergeRecords replaces by key, including the mode, and sorts', () {
    final merged = mergeRecords(
      [
        _record('v1', 'filter', mode: 'jit', fields: {'median_ms': 9.0}),
        _record('v1', 'filter', fields: {'median_ms': 8.0}),
        _record('v1', 'build', size: 100000, fields: {'median_ms': 1.0}),
      ],
      [
        _record('v2', 'build', fields: {'median_ms': 2.0}),
        _record('v1', 'filter', mode: 'jit', fields: {'median_ms': 3.0}),
        _record('v1', 'build', shape: 'wide', fields: {'median_ms': 4.0}),
      ],
    );
    expect(
      merged.map(
        (r) =>
            '${r['mode']} ${r['shape']} ${r['size']} ${r['operation']} '
            '${r['implementation']} ${r['median_ms']}',
      ),
      [
        'aot deep 10000 build v2 2.0',
        'aot deep 10000 filter v1 8.0',
        'aot deep 100000 build v1 1.0',
        'aot wide 10000 build v1 4.0',
        'jit deep 10000 filter v1 3.0',
      ],
    );
  });

  test('cells format numbers, timeouts, blocked operations, and speedups', () {
    final fast = _record('v2', 'build', fields: {'median_ms': 2.5});
    final slow = _record('v1', 'build', fields: {'median_ms': 1250.0});
    final timeout = _record(
      'v1',
      'build',
      fields: {'timeout_ms': 60000, 'timeout_phase': 'run'},
    );
    final blocked = _record(
      'v1',
      'toggle',
      fields: {
        'timeout_ms': 60000,
        'timeout_phase': 'blocked',
        'blocked_by': 'build',
      },
    );
    expect(medianCell(slow), '1,250');
    expect(medianCell(fast), '2.50');
    expect(
      medianCell(_record('v1', 'x', fields: {'median_ms': 0.1234})),
      '0.123',
    );
    expect(medianCell(timeout), '> 60,000 (timeout)');
    expect(medianCell(blocked), 'timeout (blocked by build)');
    expect(medianCell(_record('v1', 'x', fields: {'error': 'boom'})), 'error');
    expect(
      medianCell(
        _record('v1', 'x', fields: {'error': 'blocked', 'blocked_by': 'build'}),
      ),
      'error (blocked by build)',
    );
    expect(medianCell(null), '');
    expect(speedupCell(slow, fast), '500x');
    expect(speedupCell(fast, slow), '0.00x');
    expect(speedupCell(timeout, fast), '> 24,000x');
    expect(speedupCell(blocked, fast), '');
    expect(
      speedupCell(
        _record('v1', 'build', fields: {'median_ms': 9.0, 'min_ms': 4.0}),
        _record('v2', 'build', fields: {'median_ms': 3.0, 'min_ms': 2.0}),
        field: 'min_ms',
      ),
      '2.00x',
    );
    expect(minCell(_record('v1', 'x', fields: {'min_ms': 1250})), '1,250');
    expect(minCell(blocked), 'timeout (blocked by build)');
    expect(speedupCell(slow, null), '');
    expect(speedupCell(slow, timeout), '');
  });

  test('countProblems flags records whose counts disagree', () {
    final good = _record(
      'v1',
      'expand_all',
      fields: {'median_ms': 1.0, 'rows': expected.allRows},
    );
    final bad = _record('v1', 'filter', fields: {'median_ms': 1.0, 'rows': 3});
    final unmeasured = _record('v1', 'toggle', fields: {'error': 'boom'});
    expect(countProblems([good, unmeasured], expectations), isEmpty);
    expect(countProblems([good, bad], expectations), [
      'v1 aot filter deep 10000: rows is 3, expected ${expected.filterRows}',
    ]);
  });

  test('renderMarkdown has a section per mode with empty v2 columns', () {
    final md = renderMarkdown(
      [
        _record(
          'v1',
          'build',
          fields: {
            'median_ms': 12.0,
            'min_ms': 11.0,
            'max_ms': 13.0,
            'rows': expected.topLevelRows,
            'nodes': 7,
          },
        ),
        _record(
          'v1',
          'expand_all',
          fields: {'timeout_ms': 60000, 'timeout_phase': 'warmup'},
        ),
        _record(
          'v1',
          'build',
          mode: 'jit',
          fields: {
            'median_ms': 30.0,
            'min_ms': 29.0,
            'max_ms': 31.0,
            'rows': expected.topLevelRows,
          },
        ),
      ],
      workloads: [workload],
      expectations: expectations,
      generatedAt: DateTime.utc(2026, 10, 29),
    );
    expect(md, contains('on 2026-10-29.'));
    expect(
      md,
      contains(
        '- Test CPU (arm64), 8 logical cores, 16 GB; testOS 1; Flutter 3.x '
        '(stable, framework abc, engine def); Dart 3.x (stable)',
      ),
    );
    final aot = md.indexOf('## AOT: macOS profile build');
    final jit = md.indexOf('## JIT: flutter test (debug mode)');
    expect(aot, greaterThan(0));
    expect(jit, greaterThan(aot));
    expect(
      md,
      contains(
        '| operation | shape | size | v1 median (ms) | v2 median (ms) '
        '| speedup |',
      ),
    );
    expect(
      md.substring(aot, jit),
      contains('| build | deep | 10,000 | 12.00 |  |  |'),
    );
    expect(
      md.substring(aot, jit),
      contains('| expand_all | deep | 10,000 | > 60,000 (timeout) |  |  |'),
    );
    expect(
      md.substring(jit),
      contains('| build | deep | 10,000 | 30.00 |  |  |'),
    );
    expect(md, contains('### Fastest run (aot)'));
    expect(md, contains('| build | deep | 10,000 | 11.00 |  |  |'));
    expect(
      md,
      contains(
        '| v1 | aot | build | deep | 10,000 | 12.00 | 11.00 | 13.00 '
        '| rows ${expected.topLevelRows}, nodes 7 |',
      ),
    );
    expect(md, contains('timeout in warmup'));
    expect(md, contains('`/repo/data` (898)'));
    expect(md, contains('`legacy` (313, 1,080)'));
    expect(md, contains('Every measured record reports the counts'));
    expect(md, isNot(contains(String.fromCharCode(0x2014))));
  });

  test('an unavailable operation shows "not available" and its reason', () {
    final v1 = _record(
      'v1',
      'first_frame',
      fields: {
        'median_ms': 2.0,
        'min_ms': 1.5,
        'max_ms': 3.0,
        'rows': expected.allRows,
        'built_rows': 31,
        'first_index': 0,
        'last_index': 30,
      },
    );
    final v2 = _record(
      'v2',
      'first_frame',
      fields: {'unavailable': 'the view is not merged yet'},
    );
    expect(medianCell(v2), 'not available');
    expect(minCell(v2), 'not available');
    expect(speedupCell(v1, v2), '');
    expect(countProblems([v1, v2], expectations), isEmpty);

    final md = renderMarkdown(
      [v1, v2],
      workloads: [workload],
      expectations: expectations,
      generatedAt: DateTime.utc(2026),
    );
    expect(
      md,
      contains('| first_frame | deep | 10,000 | 2.00 | not available |  |'),
    );
    expect(
      md,
      contains('| first_frame | deep | 10,000 | 1.50 | not available |  |'),
    );
    expect(
      md,
      contains(
        '| v2 | aot | first_frame | deep | 10,000 |  |  |  '
        '| not available: the view is not merged yet |',
      ),
    );
    expect(md, contains('Every measured record reports the counts'));
  });

  test('renderMarkdown warns about mismatched workloads and counts', () {
    final md = renderMarkdown(
      [
        _record('v1', 'expand_all', fields: {'median_ms': 1.0, 'rows': 1}),
        _record(
          'v2',
          'expand_all',
          fields: {'median_ms': 1.0, 'fingerprint': 'x'},
        ),
      ],
      workloads: const [],
      expectations: expectations,
      generatedAt: DateTime.utc(2026),
    );
    expect(md, contains('fingerprints differ'));
    expect(
      md,
      contains('- v1 aot expand_all deep 10000: rows is 1, expected 11545'),
    );
  });

  test('records without a Dart version do not add an environment', () {
    String environmentOf(List<BenchRecord> records) {
      final md = renderMarkdown(
        records,
        workloads: const [],
        expectations: const {},
        generatedAt: DateTime.utc(2026),
      );
      final start = md.indexOf('## Environment');
      return md.substring(start, md.indexOf('Settings:', start));
    }

    final measured = _record('v1', 'build', fields: {'median_ms': 1.0});
    final timedOut = {
      ..._record('v1', 'expand_all', fields: {'timeout_ms': 60000}),
    }..remove('dart');
    expect('- '.allMatches(environmentOf([measured, timedOut])), hasLength(1));
    final elsewhere = {...timedOut, 'machine': 'Other CPU'};
    final both = environmentOf([measured, elsewhere]);
    expect(both, contains('Other CPU'));
    expect(both, contains('Dart unknown'));
    expect(both, contains('more than one environment'));
  });

  test('the report lists every operation of the catalog in order', () {
    final md = renderMarkdown(
      [
        for (final op in standardOperations.reversed)
          _record('v1', op, fields: {'median_ms': 1.0}),
      ],
      workloads: const [],
      expectations: const {},
      generatedAt: DateTime.utc(2026),
    );
    final positions = [
      for (final op in standardOperations) md.indexOf('| $op | deep |'),
    ];
    expect(positions, everyElement(greaterThan(0)));
    expect(positions, orderedEquals([...positions]..sort()));
  });
}
