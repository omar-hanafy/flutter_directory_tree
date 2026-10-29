import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';
import 'package:test/test.dart';

/// Every directory of [paths] (every proper prefix ending before a '/',
/// except the empty one), computed independently of the expectations.
Set<String> _folders(Iterable<String> paths) => {
  for (final path in paths)
    for (final (i, char) in path.split('').indexed)
      if (char == '/' && i > 0) path.substring(0, i),
};

void main() {
  group('operations', () {
    test('names are unique and prerequisites run earlier', () {
      final seen = <String>[];
      for (final operation in benchOperations) {
        expect(seen, isNot(contains(operation.name)));
        for (final prerequisite in operation.prerequisites) {
          expect(seen, contains(prerequisite), reason: operation.name);
        }
        seen.add(operation.name);
      }
      expect(standardOperations, seen);
    });

    test('frame operations come after the controller operations', () {
      final kinds = [for (final o in benchOperations) o.kind];
      final firstFrame = kinds.indexOf(OperationKind.frame);
      expect(kinds.skip(firstFrame), everyElement(OperationKind.frame));
      expect(kinds.take(firstFrame), everyElement(OperationKind.controller));
    });

    test('operationNamed rejects unknown names', () {
      expect(operationNamed('filter').kind, OperationKind.controller);
      expect(() => operationNamed('sort'), throwsFormatException);
    });
  });

  group('events', () {
    test('round-trip through a line, with any prefix', () {
      final line = encodeBenchLine({'event': 'phase', 'operation': 'build'});
      expect(line, startsWith(benchLineMarker));
      expect(decodeBenchLine('flutter: $line'), {
        'event': 'phase',
        'operation': 'build',
      });
    });

    test('ignore lines without a valid event', () {
      expect(decodeBenchLine('00:01 +1: All tests passed!'), isNull);
      expect(decodeBenchLine('${benchLineMarker}not json'), isNull);
      expect(decodeBenchLine('$benchLineMarker[1, 2]'), isNull);
      expect(decodeBenchLine('$benchLineMarker{"no_event": 1}'), isNull);
    });
  });

  group('WorkloadExpectations', () {
    // Row counts that directory_tree's v1 and v2 benchmarks both produced
    // for these workloads (flatten, toggle, and filter rows), so the
    // expectations are checked against two independent implementations.
    const reference = {
      WorkloadShape.deep: (all: 11545, hidden: 898, filter: 1080),
      WorkloadShape.wide: (all: 10009, hidden: 2123, filter: 332),
    };

    for (final shape in WorkloadShape.values) {
      group('${shape.name} 10000', () {
        final workload = Workload.generate(shape, 10000);
        final expected = WorkloadExpectations(workload);

        test('match directory_tree reference counts', () {
          final ref = reference[shape]!;
          expect(expected.allRows, ref.all);
          expect(expected.toggleHiddenRows, ref.hidden);
          expect(expected.filterRows, ref.filter);
        });

        test('match counts derived independently from the paths', () {
          final folders = _folders(workload.paths);
          expect(folders, contains(workloadRoot));
          expect(expected.allRows, workload.paths.length + folders.length);
          final children = {
            for (final path in [...workload.paths, ...folders])
              if (path.startsWith('$workloadRoot/') &&
                  !path.substring(workloadRoot.length + 1).contains('/'))
                path,
          };
          expect(expected.topLevelRows, 1 + children.length);
          final inside = [
            for (final path in [...workload.paths, ...folders])
              if (path.startsWith('${workload.toggleTarget}/')) path,
          ];
          expect(expected.toggleHiddenRows, inside.length);
          expect(expected.toggleRows, expected.allRows - inside.length);
          final range = expected.selectRangeCount;
          expect(range, closeTo(expected.allRows / 2, 2));
          expect(
            expected.selectRangeTarget - expected.selectRangeAnchor + 1,
            range,
          );
        });

        test('check accepts the expected counts', () {
          final rows = expected.allRows;
          final ok = <String, Map<String, Object?>>{
            'build': {'rows': expected.topLevelRows, 'nodes': 1},
            'expand_all': {'rows': rows},
            'toggle': {
              'rows': expected.toggleRows,
              'hidden_rows': expected.toggleHiddenRows,
            },
            'filter': {'rows': expected.filterRows},
            'select_range': {'selected': expected.selectRangeCount},
            'first_frame': {
              'rows': rows,
              'built_rows': 31,
              'first_index': 0,
              'last_index': 30,
            },
            'jump_middle': {
              'rows': rows,
              'built_rows': 31,
              'first_index': rows ~/ 2 - 15,
              'last_index': rows ~/ 2 + 15,
            },
            'jump_end': {
              'rows': rows,
              'built_rows': 31,
              'first_index': rows - 31,
              'last_index': rows - 1,
            },
          };
          expect(ok.keys, standardOperations);
          for (final MapEntry(key: operation, value: counts) in ok.entries) {
            expect(
              expected.check(operation, counts),
              isEmpty,
              reason: operation,
            );
          }
        });

        test('check reports wrong counts', () {
          final rows = expected.allRows;
          expect(expected.check('expand_all', {'rows': rows - 1}), [
            'rows is ${rows - 1}, expected $rows',
          ]);
          expect(expected.check('toggle', {'rows': 1}), hasLength(2));
          expect(expected.check('first_frame', {'rows': rows}), [
            'built_rows, first_index, or last_index is missing',
          ]);
          expect(
            expected.check('jump_end', {
              'rows': rows,
              'built_rows': 10,
              'first_index': 0,
              'last_index': 9,
            }),
            ['last_index is 9, expected ${rows - 1}'],
          );
          expect(
            expected.check('jump_middle', {
              'rows': rows,
              'built_rows': 5,
              'first_index': 0,
              'last_index': 9,
            }),
            hasLength(2),
          );
          expect(expected.check('sort', {}), ['unknown operation "sort"']);
        });
      });
    }
  });
}
