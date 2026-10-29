import 'dart:async';

import 'package:fdt_bench_workloads/protocol.dart';

/// A benchmark record (one JSON line of `results.jsonl`).
typedef BenchRecord = Map<String, Object?>;

/// A running benchmark process.
abstract class BenchProcess {
  /// Every output line, stdout and stderr merged. Ends when the process has
  /// exited and closed both streams.
  Stream<String> get lines;

  /// Completes with the exit code.
  Future<int> get exitCode;

  /// Kills the process and every process it started.
  Future<void> kill();
}

/// Starts a benchmark process that runs [operations] (in catalog order).
typedef BenchProcessStarter = Future<BenchProcess> Function(
  List<String> operations,
);

/// One implementation, mode, and workload to measure.
class WorkloadRun {
  /// Creates a run description.
  const WorkloadRun({
    required this.implementation,
    required this.mode,
    required this.shape,
    required this.size,
    this.seed = 20261028,
    this.runs = 5,
    this.warmup = 1,
    this.budget = const Duration(seconds: 60),
    this.startupBudget = const Duration(minutes: 5),
    required this.operations,
  });

  /// The implementation label, such as `v1`.
  final String implementation;

  /// `jit` or `aot`.
  final String mode;

  /// The workload shape name.
  final String shape;

  /// The workload size.
  final int size;

  /// The workload seed.
  final int seed;

  /// Timed runs per operation.
  final int runs;

  /// Warm-up runs per operation.
  final int warmup;

  /// The longest one step (workload generation, an operation's set-up, or
  /// one warm-up or timed run) may take before the process is killed.
  final Duration budget;

  /// The longest a process may take to report its first step (compiling the
  /// test or launching the app).
  final Duration startupBudget;

  /// The operations to measure, in catalog order.
  final List<String> operations;

  /// The fields of a record the runner writes itself (for timeouts, blocked
  /// operations, and processes that died).
  Map<String, Object?> baseRecord(String operation) => {
    'implementation': implementation,
    'mode': mode,
    'shape': shape,
    'size': size,
    'operation': operation,
    'runs': runs,
    'warmup': warmup,
    'seed': seed,
  };
}

enum _Failure { timeout, error }

/// Measures every operation of [run] in processes from [start] and returns
/// one record per operation, in the order they finished.
///
/// Every step must report its start (a `phase` line) within [run]'s budget
/// of the previous one, and the first within the startup budget. Otherwise
/// the process is killed, the step's operation is recorded with `timeout_ms`
/// and `timeout_phase`, and a new process continues with the remaining
/// operations. Operations whose prerequisites timed out or failed are
/// recorded as blocked (`blocked_by`) instead of being attempted. A process
/// that exits early fails the operation it was in. [onRecord] receives every
/// record as soon as it is known, with `budget_ms` added; [log] receives
/// progress messages and the output lines of failed processes.
Future<List<BenchRecord>> runWorkload(
  WorkloadRun run,
  BenchProcessStarter start, {
  void Function(BenchRecord record)? onRecord,
  void Function(String message)? log,
}) async {
  final records = <BenchRecord>[];
  final failures = <String, _Failure>{};
  final pending = [...run.operations];
  final budgetMs = run.budget.inMilliseconds;
  // What the last process said about itself in its start event; records the
  // runner writes (timeouts, blocked operations) carry it too.
  final processInfo = <String, Object?>{};

  void emit(BenchRecord record) {
    final complete = {...record, 'budget_ms': budgetMs};
    records.add(complete);
    pending.remove(record['operation']);
    onRecord?.call(complete);
  }

  void fail(String operation, _Failure failure, Map<String, Object?> data) {
    failures[operation] = failure;
    emit({...run.baseRecord(operation), ...data, ...processInfo});
  }

  while (pending.isNotEmpty) {
    for (final operation in [...pending]) {
      final blocker = operationNamed(operation).prerequisites
          .where(failures.containsKey)
          .firstOrNull;
      if (blocker == null) continue;
      final failure = failures[blocker]!;
      fail(operation, failure, {
        if (failure == _Failure.timeout) ...{
          'timeout_ms': budgetMs,
          'timeout_phase': 'blocked',
        } else
          'error': 'blocked: $blocker failed',
        'blocked_by': blocker,
      });
    }
    if (pending.isEmpty) break;

    final process = await start([...pending]);
    String? operation;
    var phase = 'startup';
    var completedRuns = 0;
    var done = false;
    var timedOut = false;
    final output = <String>[];
    Timer? timer;
    void arm(Duration duration) {
      timer?.cancel();
      timer = Timer(duration, () {
        timedOut = true;
        unawaited(process.kill());
      });
    }

    arm(run.startupBudget);
    // Completed by the subscription itself: the output can end before the
    // exit code arrives, and a done event that was already delivered never
    // reaches a later asFuture.
    final linesDone = Completer<void>();
    final lines = process.lines.listen(onDone: linesDone.complete, (line) {
      final event = decodeBenchLine(line);
      if (event == null) {
        output.add(line);
        if (output.length > 60) output.removeAt(0);
        return;
      }
      switch (event['event']) {
        case BenchEvent.start:
          for (final key in const ['build_mode', 'dart']) {
            if (event[key] != null) processInfo[key] = event[key];
          }
        case BenchEvent.phase:
          operation = event['operation'] as String?;
          phase = event['phase'] as String? ?? '?';
          completedRuns = event['completed_runs'] as int? ?? 0;
          arm(run.budget);
        case BenchEvent.record:
          final record = (event['record']! as Map).cast<String, Object?>();
          final name = record['operation'];
          if (name is! String || !pending.contains(name)) return;
          if (record['error'] != null) failures[name] = _Failure.error;
          emit(record);
        case BenchEvent.done:
          done = true;
          timer?.cancel();
        case BenchEvent.workload:
          break;
        default:
          output.add(line);
      }
    });
    final code = await process.exitCode;
    // The output can outlive the process when a child kept it open (the
    // kill on timeout closes it, and a crash leaves it closed).
    await linesDone.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => process.kill(),
    );
    await lines.cancel();
    timer?.cancel();

    final current = operation;
    if (timedOut) {
      final limit = phase == 'startup' ? run.startupBudget : run.budget;
      log?.call(
        '  timeout: ${current ?? 'all'} in $phase after '
        '${limit.inMilliseconds} ms',
      );
      if (current == null || !pending.contains(current)) {
        for (final remaining in [...pending]) {
          fail(remaining, _Failure.timeout, {
            'timeout_ms': budgetMs,
            'timeout_phase': phase,
          });
        }
      } else {
        fail(current, _Failure.timeout, {
          'timeout_ms': budgetMs,
          'timeout_phase': phase,
          'completed_runs': completedRuns,
        });
      }
    } else if (!done || pending.isNotEmpty) {
      final reason = done
          ? 'no record before the process finished (exit code $code)'
          : 'process exited with code $code during '
                '${current == null ? phase : '$current $phase'}';
      log?.call('  $reason; last output:\n    ${output.join('\n    ')}');
      if (current != null && pending.contains(current)) {
        fail(current, _Failure.error, {'error': reason});
      } else {
        for (final remaining in [...pending]) {
          fail(remaining, _Failure.error, {'error': reason});
        }
      }
    }
  }
  return records;
}
