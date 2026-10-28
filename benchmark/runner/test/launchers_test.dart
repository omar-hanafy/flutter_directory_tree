import 'dart:io';

import 'package:fdt_bench_runner/runner.dart';
import 'package:test/test.dart';

/// Whether process [pid] still exists.
Future<bool> _alive(int pid) async {
  final result = await Process.run('kill', ['-0', '$pid']);
  return result.exitCode == 0;
}

void main() {
  test('benchArguments passes the workload and the operations', () {
    const run = WorkloadRun(
      implementation: 'v1',
      mode: 'jit',
      shape: 'wide',
      size: 100000,
      runs: 3,
      warmup: 0,
      operations: ['build'],
    );
    expect(
      benchArguments(run, ['toggle', 'filter']),
      '--shape wide --size 100000 --seed 20261028 --runs 3 --warmup 0 '
      '--operations toggle,filter',
    );
  });

  test('describeFlutterVersion summarizes flutter --version --machine', () {
    expect(
      describeFlutterVersion(
        'Waiting for lock\n{"frameworkVersion": "3.47.7", "channel": '
        '"stable", "frameworkRevision": "abaf9c523780a608bd46", '
        '"engineRevision": "deb287481e3ce9468f34", "flutterVersion": '
        '"3.47.7"}',
      ),
      'Flutter 3.47.7 (stable, framework abaf9c5237, engine deb287481e)',
    );
    expect(describeFlutterVersion(null), 'unknown Flutter SDK');
    expect(describeFlutterVersion('not json'), 'unknown Flutter SDK');
  });

  test('killProcessTree kills a process and its children', () async {
    // A shell whose child sleeps: killing only the shell would leave the
    // sleep running, like flutter_tester under a killed flutter tool.
    final process = await LocalBenchProcess.start('sh', [
      '-c',
      r'sleep 30 & echo "child $!"; wait',
    ]);
    final childLine = await process.lines.firstWhere(
      (line) => line.startsWith('child '),
    );
    final child = int.parse(childLine.substring('child '.length));
    expect(await _alive(child), isTrue);

    await process.kill();
    expect(await process.exitCode, isNot(0));
    // SIGKILL is asynchronous; give the OS a moment to reap the child.
    for (var i = 0; i < 50 && await _alive(child); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(await _alive(child), isFalse);
  }, testOn: '!windows');
}
