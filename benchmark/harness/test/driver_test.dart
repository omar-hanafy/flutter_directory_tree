import 'package:fdt_bench_harness/jit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A naive implementation of every operation on plain lists of paths, used
/// to check the harness and the expectations independently of any tree
/// package.
class _ReferenceSubject extends BenchSubject {
  _ReferenceSubject(this.workload, {this.failIn, this.failInRun});

  final Workload workload;
  final String? failIn;
  final String? failInRun;

  late final List<String> _all = () {
    final folders = <String>{
      for (final path in workload.paths)
        for (
          var i = path.indexOf('/', 1);
          i != -1;
          i = path.indexOf('/', i + 1)
        )
          path.substring(0, i),
    };
    // Pre-order: comparing segment lists puts every folder before its
    // contents.
    return [...folders, ...workload.paths]..sort(
      (a, b) =>
          a.split('/').join('\u0000').compareTo(b.split('/').join('\u0000')),
    );
  }();

  List<String> _rows = const [];
  Set<String> _selected = const {};
  int disposeCalls = 0;

  List<String> _topLevel() => [
    for (final path in _all)
      if (path == workloadRoot ||
          (path.startsWith('$workloadRoot/') &&
              !path.substring(workloadRoot.length + 1).contains('/')))
        path,
  ];

  @override
  void setUp(String operation) {
    if (operation == failIn) throw StateError('set-up of $operation broke');
    _rows = operation == 'expand_all' ? _topLevel() : [..._all];
    _selected = {};
  }

  @override
  void beforeRun(String operation) {
    switch (operation) {
      case 'expand_all':
        _rows = _topLevel();
      case 'toggle' || 'filter':
        _rows = [..._all];
      case 'select_range':
        _selected = {_rows[_rows.length ~/ 4]};
    }
  }

  @override
  void run(String operation) {
    if (operation == failInRun) throw StateError('run of $operation broke');
    final target = '${workload.toggleTarget}/';
    switch (operation) {
      case 'build':
        _rows = _topLevel();
      case 'expand_all':
        _rows = [..._all];
      case 'toggle':
        _rows = [
          for (final path in _all)
            if (!path.startsWith(target)) path,
        ];
      case 'filter':
        final matches = [
          for (final path in workload.paths)
            if (path.split('/').last.contains(workload.filterQuery)) path,
        ];
        final keep = <String>{
          ...matches,
          for (final path in matches)
            for (
              var i = path.indexOf('/', 1);
              i != -1;
              i = path.indexOf('/', i + 1)
            )
              path.substring(0, i),
        };
        _rows = [
          for (final path in _all)
            if (keep.contains(path)) path,
        ];
      case 'select_range':
        _selected = _rows
            .sublist(_rows.length ~/ 4, _rows.length * 3 ~/ 4 + 1)
            .toSet();
    }
  }

  @override
  Map<String, Object> counts(String operation) => switch (operation) {
    'toggle' => {
      'rows': _rows.length,
      'hidden_rows': _all.length - _rows.length,
    },
    'select_range' => {'selected': _selected.length},
    _ => {'rows': _rows.length},
  };

  @override
  Widget buildView({
    required ScrollController scrollController,
    required RowBuiltCallback onRowBuilt,
  }) {
    return ListView.builder(
      controller: scrollController,
      itemExtent: 28,
      itemCount: _all.length,
      itemBuilder: (context, index) {
        onRowBuilt(index);
        return Text(_all[index]);
      },
    );
  }

  @override
  int get viewRowCount => _all.length;

  @override
  void dispose() => disposeCalls++;
}

Future<
  ({List<Map<String, Object?>> records, List<Map<String, Object?>> events})
>
_run(
  WidgetTester tester,
  BenchSubject Function(Workload workload) create, {
  List<String>? operations,
  int runs = 2,
}) async {
  final slot = ValueNotifier<Widget?>(null);
  addTearDown(slot.dispose);
  await tester.pumpWidget(BenchHost(slot: slot));
  final events = <Map<String, Object?>>[];
  final records = await runBenchmark(
    BenchConfig(
      implementation: 'reference',
      size: 300,
      runs: runs,
      operations: operations,
    ),
    create,
    frames: TesterFrameDriver(tester, slot),
    emit: (line) => events.add(decodeBenchLine(line)!),
  );
  return (records: records, events: events);
}

void main() {
  testWidgets('every operation produces the expected counts', (tester) async {
    late _ReferenceSubject subject;
    final (:records, :events) = await _run(
      tester,
      (workload) => subject = _ReferenceSubject(workload),
    );

    final expected = WorkloadExpectations(
      Workload.generate(WorkloadShape.deep, 300),
    );
    expect(records.map((r) => r['operation']), standardOperations);
    for (final record in records) {
      final operation = record['operation']! as String;
      expect(record, isNot(contains('error')), reason: operation);
      expect(record['implementation'], 'reference');
      expect(record['mode'], 'jit');
      expect(record['build_mode'], 'debug');
      expect(record['size'], 300);
      expect(record['runs'], 2);
      expect(record['dart'], isA<String>());
      final median = record['median_ms']! as double;
      expect(record['min_ms']! as double, lessThanOrEqualTo(median));
      expect(record['max_ms']! as double, greaterThanOrEqualTo(median));
      expect(expected.check(operation, record), isEmpty, reason: operation);
    }
    // A 600 px viewport of 28 px rows shows 22 rows, plus the cache extent.
    final firstFrame = records.firstWhere(
      (r) => r['operation'] == 'first_frame',
    );
    expect(firstFrame['built_rows'], inInclusiveRange(22, 40));
    expect(subject.disposeCalls, 1);
    expect(tester.takeException(), isNull);

    // Events: start, workload phase, workload, then per operation a set-up
    // phase, one phase per warm-up and run, and the record; then done.
    expect(events.first['event'], BenchEvent.start);
    expect(events.first['operations'], standardOperations);
    expect(events[1], {
      'event': BenchEvent.phase,
      'operation': null,
      'phase': 'workload',
      'completed_runs': 0,
    });
    expect(events[2]['event'], BenchEvent.workload);
    expect(events.last['event'], BenchEvent.done);
    final perOperation = [
      for (final e in events.skip(3).take(events.length - 4))
        e['event'] == BenchEvent.phase
            ? '${e['phase']}${e['completed_runs']}'
            : '${e['event']}',
    ];
    expect(perOperation, [
      for (final _ in standardOperations) ...[
        'setup0',
        'warmup0',
        'run0',
        'run1',
        'record',
      ],
    ]);
  });

  testWidgets('runs a subset of operations, each from a fresh start', (
    tester,
  ) async {
    final (:records, events: _) = await _run(
      tester,
      _ReferenceSubject.new,
      operations: ['jump_end', 'toggle'],
    );
    expect(records.map((r) => r['operation']), ['toggle', 'jump_end']);
    final expected = WorkloadExpectations(
      Workload.generate(WorkloadShape.deep, 300),
    );
    for (final record in records) {
      expect(expected.check(record['operation']! as String, record), isEmpty);
    }
  });

  testWidgets('reports failures and blocks dependent operations', (
    tester,
  ) async {
    final (:records, events: _) = await _run(
      tester,
      (w) => _ReferenceSubject(w, failIn: 'expand_all', failInRun: 'filter'),
    );
    final byOperation = {for (final r in records) r['operation']: r};
    expect(byOperation['build'], contains('median_ms'));
    expect(
      byOperation['expand_all']!['error'],
      contains('set-up of expand_all'),
    );
    expect(byOperation['expand_all'], isNot(contains('median_ms')));
    for (final blocked in [
      'toggle',
      'filter',
      'select_range',
      'first_frame',
      'jump_middle',
      'jump_end',
    ]) {
      expect(byOperation[blocked]!['blocked_by'], 'expand_all');
      expect(byOperation[blocked]!['error'], contains('blocked'));
    }
  });

  testWidgets('an operation failing in a run does not stop the others', (
    tester,
  ) async {
    final (:records, events: _) = await _run(
      tester,
      (w) => _ReferenceSubject(w, failInRun: 'filter'),
    );
    final byOperation = {for (final r in records) r['operation']: r};
    expect(byOperation['filter']!['error'], contains('run of filter broke'));
    expect(byOperation['select_range'], contains('median_ms'));
    expect(byOperation['jump_end'], contains('median_ms'));
  });

  testWidgets('measureFrame times one frame and fails when none runs', (
    tester,
  ) async {
    final slot = ValueNotifier<Widget?>(null);
    addTearDown(slot.dispose);
    await tester.pumpWidget(BenchHost(slot: slot));
    final frames = TesterFrameDriver(tester, slot);
    var builds = 0;
    final ms = await measureFrame(frames, () {
      slot.value = Builder(
        builder: (context) {
          builds++;
          return const Text('row');
        },
      );
    });
    expect(builds, 1);
    expect(ms, greaterThan(0));
    expect(find.text('row'), findsOneWidget);

    await expectLater(
      measureFrame(_NoFrames(slot), () {}),
      throwsA(isA<StateError>()),
    );
    // Runs the frame the failed measurement scheduled.
    await tester.pump();
  });

  testWidgets('RowBuildProbe counts mounts of reused row widgets', (
    tester,
  ) async {
    final probe = RowProbe();
    // One widget instance per row, reused like a row cache does, so the
    // "row builder" runs once per row however often a row is mounted.
    final rows = [
      for (var i = 0; i < 1000; i++)
        RowBuildProbe(index: i, onBuilt: probe.add, child: Text('row $i')),
    ];
    var builderCalls = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final list = Directionality(
      textDirection: TextDirection.ltr,
      child: ListView.builder(
        controller: scroll,
        itemExtent: 28,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          builderCalls++;
          return rows[index];
        },
      ),
    );
    await tester.pumpWidget(list);
    final mounted = probe.toCounts()['built_rows']! as int;
    expect(mounted, greaterThan(0));
    expect(builderCalls, mounted);

    // Pumping the identical widget again builds nothing.
    probe.reset();
    await tester.pumpWidget(list);
    expect(probe.toCounts()['built_rows'], 0);

    // Scrolling away and back mounts the rows again: the probes count them
    // whether or not a row builder ran for them.
    scroll.jumpTo(10000);
    await tester.pump();
    probe.reset();
    scroll.jumpTo(0);
    await tester.pump();
    expect(probe.toCounts(), {
      'built_rows': mounted,
      'first_index': 0,
      'last_index': mounted - 1,
    });
  });
}

/// A driver whose pump never runs a frame.
class _NoFrames implements FrameDriver {
  _NoFrames(this.slot);

  @override
  final ValueNotifier<Widget?> slot;

  @override
  Future<void> pump() async {}
}
