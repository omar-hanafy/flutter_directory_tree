import 'dart:async';

import 'package:fdt_bench_runner/runner.dart';
import 'package:fdt_bench_workloads/protocol.dart';
import 'package:test/test.dart';

/// Where a scripted process stops: it hangs (until killed) or exits with
/// [exitCode] right after reporting [phase] of [operation].
typedef _Stop = ({String? operation, String phase, int? exitCode});

/// A benchmark process that prints the line protocol for [operations] like
/// the harness does, with one warm-up and two runs per operation.
class _ScriptedProcess implements BenchProcess {
  _ScriptedProcess(
    this.operations, {
    this.stop,
    this.errorIn,
    this.unavailableIn = const {},
    this.silent = false,
  }) {
    scheduleMicrotask(_play);
  }

  final List<String> operations;
  final _Stop? stop;
  final String? errorIn;

  /// Operations the subject cannot measure: like the harness, the process
  /// reports no steps for them, only a record with `unavailable`.
  final Set<String> unavailableIn;
  final bool silent;
  final _lines = StreamController<String>();
  final _exit = Completer<int>();
  bool killed = false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Future<void> kill() async {
    killed = true;
    _finish(-9);
  }

  void _finish(int code) {
    if (_exit.isCompleted) return;
    unawaited(_lines.close());
    _exit.complete(code);
  }

  void _send(Map<String, Object?> event) {
    if (!_exit.isCompleted) _lines.add(encodeBenchLine(event));
  }

  /// Reports [phase]; returns false when the script stops there.
  bool _phase(String? operation, String phase, [int runs = 0]) {
    _send({
      'event': 'phase',
      'operation': operation,
      'phase': phase,
      'completed_runs': runs,
    });
    final stop = this.stop;
    if (stop == null || stop.operation != operation || stop.phase != phase) {
      return true;
    }
    final code = stop.exitCode;
    if (code != null) _finish(code);
    return false;
  }

  Future<void> _play() async {
    if (silent) return;
    _lines.add('00:00 +0: loading bench/jit_bench_test.dart');
    _send({'event': 'start', 'build_mode': 'debug', 'dart': '3.x (stable)'});
    if (!_phase(null, 'workload')) return;
    _send({
      'event': 'workload',
      'description': {'fingerprint': 'f00d'},
    });
    for (final operation in operations) {
      if (unavailableIn.contains(operation)) {
        _send({
          'event': 'record',
          'record': {
            'implementation': 'v2',
            'mode': 'jit',
            'operation': operation,
            'unavailable': 'no view yet',
          },
        });
        continue;
      }
      for (final (phase, runs) in [
        ('setup', 0),
        ('warmup', 0),
        ('run', 0),
        ('run', 1),
      ]) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (!_phase(operation, phase, runs)) return;
      }
      _send({
        'event': 'record',
        'record': {
          'implementation': 'v1',
          'mode': 'jit',
          'operation': operation,
          if (operation == errorIn)
            'error': 'boom'
          else ...{
            'median_ms': 1.5,
            'min_ms': 1.0,
            'max_ms': 2.0,
          },
        },
      });
    }
    _send({'event': 'done'});
    _finish(0);
  }
}

const _run = WorkloadRun(
  implementation: 'v1',
  mode: 'jit',
  shape: 'deep',
  size: 10000,
  runs: 2,
  budget: Duration(milliseconds: 300),
  startupBudget: Duration(milliseconds: 600),
  operations: [
    'build',
    'expand_all',
    'toggle',
    'filter',
    'select_range',
    'first_frame',
    'jump_middle',
    'jump_end',
  ],
);

/// Runs [_run] with scripted processes: the n-th started process uses
/// `scripts[n]` (the last one repeats).
Future<
  ({
    Map<String, BenchRecord> records,
    List<List<String>> starts,
    List<_ScriptedProcess> processes,
  })
>
_coordinate(
  List<_ScriptedProcess Function(List<String> operations)> scripts,
) async {
  final starts = <List<String>>[];
  final processes = <_ScriptedProcess>[];
  final streamed = <BenchRecord>[];
  final records = await runWorkload(_run, (operations) async {
    starts.add(operations);
    final script = scripts[(starts.length - 1).clamp(0, scripts.length - 1)];
    final process = script(operations);
    processes.add(process);
    return process;
  }, onRecord: streamed.add);
  expect(streamed, records);
  return (
    records: {for (final r in records) r['operation']! as String: r},
    starts: starts,
    processes: processes,
  );
}

void main() {
  test('one process measures every operation', () async {
    final (:records, :starts, :processes) = await _coordinate([
      _ScriptedProcess.new,
    ]);
    expect(starts, [_run.operations]);
    expect(records.keys, _run.operations);
    for (final r in records.values) {
      expect(r['median_ms'], 1.5);
      expect(r['budget_ms'], 300);
    }
    expect(processes.single.killed, isFalse);
  });

  test('a step over budget is killed, and a new process continues', () async {
    // The hung process only ends when the coordinator kills it, so reaching
    // the expectations at all proves the watchdog fired.
    final (:records, :starts, :processes) = await _coordinate([
      (ops) => _ScriptedProcess(
        ops,
        stop: (operation: 'toggle', phase: 'run', exitCode: null),
      ),
      _ScriptedProcess.new,
    ]);
    expect(processes.first.killed, isTrue);
    expect(processes.last.killed, isFalse);
    // The runner writes this record itself, with what the process reported
    // about itself in its start event.
    expect(records['toggle'], {
      ..._run.baseRecord('toggle'),
      'timeout_ms': 300,
      'timeout_phase': 'run',
      'completed_runs': 0,
      'build_mode': 'debug',
      'dart': '3.x (stable)',
      'budget_ms': 300,
    });
    expect(starts, [
      _run.operations,
      ['filter', 'select_range', 'first_frame', 'jump_middle', 'jump_end'],
    ]);
    expect(records['build']!['median_ms'], 1.5);
    expect(records['jump_end']!['median_ms'], 1.5);
  });

  test('operations that depend on a timeout are blocked, not run', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess(
        ops,
        stop: (operation: 'expand_all', phase: 'setup', exitCode: null),
      ),
    ]);
    expect(starts, hasLength(1));
    expect(records['build']!['median_ms'], 1.5);
    expect(records['expand_all']!['timeout_phase'], 'setup');
    for (final blocked in _run.operations.skip(2)) {
      expect(records[blocked]!['timeout_phase'], 'blocked');
      expect(records[blocked]!['blocked_by'], 'expand_all');
      expect(records[blocked]!['timeout_ms'], 300);
    }
  });

  test('a hang while generating the workload times out everything', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess(
        ops,
        stop: (operation: null, phase: 'workload', exitCode: null),
      ),
    ]);
    expect(starts, hasLength(1));
    expect(records.keys, _run.operations);
    for (final r in records.values) {
      expect(r['timeout_phase'], 'workload');
    }
  });

  test('a process that never starts reports a startup timeout', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess(ops, silent: true),
    ]);
    expect(starts, hasLength(1));
    for (final r in records.values) {
      expect(r['timeout_phase'], 'startup');
    }
  });

  test('a crash fails the current operation and continues', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess(
        ops,
        stop: (operation: 'filter', phase: 'warmup', exitCode: 3),
      ),
      _ScriptedProcess.new,
    ]);
    expect(
      records['filter']!['error'],
      'process exited with code 3 during filter warmup',
    );
    expect(records['filter'], isNot(contains('timeout_ms')));
    expect(starts.last, [
      'select_range',
      'first_frame',
      'jump_middle',
      'jump_end',
    ]);
    expect(records['jump_end']!['median_ms'], 1.5);
  });

  test('a process that dies before any step fails every operation', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess(
        ops,
        stop: (operation: null, phase: 'workload', exitCode: 1),
      ),
    ]);
    expect(starts, hasLength(1));
    for (final r in records.values) {
      expect(
        r['error'],
        'process exited with code 1 during workload',
        reason: '${r['operation']}',
      );
    }
  });

  test('an error record blocks dependent operations after a restart', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess(
        ops,
        errorIn: 'expand_all',
        stop: (operation: 'toggle', phase: 'setup', exitCode: 3),
      ),
      _ScriptedProcess.new,
    ]);
    expect(records['build']!['median_ms'], 1.5);
    expect(records['expand_all']!['error'], 'boom');
    expect(records['toggle']!['error'], contains('during toggle setup'));
    // Everything left needs expand_all, so no second process starts.
    expect(starts, hasLength(1));
    for (final blocked in _run.operations.skip(3)) {
      expect(records[blocked]!['error'], 'blocked: expand_all failed');
      expect(records[blocked]!['blocked_by'], 'expand_all');
      expect(records[blocked], isNot(contains('timeout_ms')));
    }
  });

  test('an unavailable operation is recorded and blocks nothing', () async {
    final (:records, :starts, :processes) = await _coordinate([
      (ops) => _ScriptedProcess(ops, unavailableIn: const {'first_frame'}),
    ]);
    expect(starts, [_run.operations]);
    expect(records.keys, _run.operations);
    expect(records['first_frame']!['unavailable'], 'no view yet');
    expect(records['first_frame'], isNot(contains('error')));
    expect(records['first_frame']!['budget_ms'], 300);
    // Both list first_frame as a prerequisite: an operation the subject
    // cannot measure is not a failure, so they still run.
    for (final dependent in ['jump_middle', 'jump_end']) {
      expect(records[dependent]!['median_ms'], 1.5);
      expect(records[dependent], isNot(contains('blocked_by')));
    }
    expect(processes.single.killed, isFalse);
  });

  test('records the process repeats or never asked for are ignored', () async {
    final (:records, :starts, processes: _) = await _coordinate([
      (ops) => _ScriptedProcess([...ops, 'build']),
    ]);
    expect(starts, hasLength(1));
    expect(records.keys, _run.operations);
  });
}
