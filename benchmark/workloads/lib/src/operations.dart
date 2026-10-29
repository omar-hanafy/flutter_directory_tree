/// How the harness times an operation.
enum OperationKind {
  /// A controller command, timed with a `Stopwatch` around the call.
  controller,

  /// One frame of the tree view, timed on the UI thread from the start of
  /// the frame to its post-frame callbacks.
  frame,
}

/// One benchmark operation.
class BenchOperation {
  /// Creates an operation.
  const BenchOperation(
    this.name,
    this.kind, {
    this.prerequisites = const [],
    required this.summary,
  });

  /// The operation name used in records and on the command line.
  final String name;

  /// How the harness times it.
  final OperationKind kind;

  /// Operations whose prepared state this one needs. When one of them timed
  /// out or failed, this operation is reported as blocked instead of being
  /// attempted (its set-up would repeat the same work).
  final List<String> prerequisites;

  /// One line for reports.
  final String summary;
}

/// Every operation, in execution order.
///
/// The controller operations work on one shared controller: `build` leaves
/// the top folder expanded, `expand_all` expands every folder, and every
/// later operation starts from that fully expanded tree with no filter and no
/// selection (restored, untimed, by its set-up).
const List<BenchOperation> benchOperations = [
  BenchOperation(
    'build',
    OperationKind.controller,
    summary:
        'Paths to a ready controller: build the tree and create the '
        'controller with only the top folder expanded.',
  ),
  BenchOperation(
    'expand_all',
    OperationKind.controller,
    prerequisites: ['build'],
    summary: 'Expand every folder, starting with only the top folder open.',
  ),
  BenchOperation(
    'toggle',
    OperationKind.controller,
    prerequisites: ['build', 'expand_all'],
    summary:
        'Collapse the toggle target in the fully expanded tree and update '
        'the rows.',
  ),
  BenchOperation(
    'filter',
    OperationKind.controller,
    prerequisites: ['build', 'expand_all'],
    summary: 'Apply the search query to the fully expanded tree.',
  ),
  BenchOperation(
    'select_range',
    OperationKind.controller,
    prerequisites: ['build', 'expand_all'],
    summary:
        'Extend the selection from the row at 1/4 to the row at 3/4 of the '
        'fully expanded tree (half of all rows).',
  ),
  BenchOperation(
    'first_frame',
    OperationKind.frame,
    prerequisites: ['build', 'expand_all'],
    summary: 'First frame of a tree view over the fully expanded tree.',
  ),
  BenchOperation(
    'jump_middle',
    OperationKind.frame,
    prerequisites: ['build', 'expand_all', 'first_frame'],
    summary: 'The frame after jumping from the top to the middle of the list.',
  ),
  BenchOperation(
    'jump_end',
    OperationKind.frame,
    prerequisites: ['build', 'expand_all', 'first_frame'],
    summary: 'The frame after jumping from the top to the end of the list.',
  ),
];

/// The operation names, in execution order.
final List<String> standardOperations = List.unmodifiable([
  for (final operation in benchOperations) operation.name,
]);

/// Returns the operation called [name].
///
/// Throws a [FormatException] for an unknown name.
BenchOperation operationNamed(String name) {
  for (final operation in benchOperations) {
    if (operation.name == name) return operation;
  }
  throw FormatException('Unknown operation "$name"');
}
