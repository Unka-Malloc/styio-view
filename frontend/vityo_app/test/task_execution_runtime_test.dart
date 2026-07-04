import 'package:vityo_app/src/view_ide/environment/configuration/environment_variable_configuration.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/process/process_manager.dart';
import 'package:vityo_app/src/view_ide/runtime/task_execution_runtime.dart';

Future<void> main() async {
  var tick = 0;
  final runtime = TaskExecutionRuntime(
    redactionPolicy: const EnvironmentVariableRedactionPolicy(),
    stdoutCapBytes: 16,
    stderrCapBytes: 16,
    stdoutCapDeltas: 2,
    stderrCapDeltas: 2,
    clock: () => DateTime.utc(2026, 6, 29, 12, 0, tick++),
  );

  runtime.startFromProcessRequest(
    operationId: 'task.run',
    request: const ProcessCommandRequest(
      executablePath: 'dart',
      arguments: <String>['run', 'tool.dart'],
      environment: <String, String>{
        'TOKEN': 'secret-value',
        'PATH': '/usr/bin',
      },
      workingDirectory: '/workspace',
    ),
  );
  runtime.stdout('hello\n');
  runtime.stderr('warning\n');
  runtime.diagnostic(
    'lint',
    'Trailing whitespace.',
    severity: TaskExecutionDiagnosticSeverity.warning,
    source: 'analysis',
  );
  runtime.runtimeEvent('Runtime hook fired.');
  runtime.cancel(reason: 'User cancelled the task.');
  runtime.cleanup(message: 'Released temporary files.');

  final record = runtime.snapshot();
  final restored = TaskExecutionRuntimeRecord.fromJson(record.toJson());

  _expect(record.operationId == 'task.run', 'operationId');
  _expect(
    record.argv.length == 3 &&
        record.argv[0] == 'dart' &&
        record.argv[1] == 'run' &&
        record.argv[2] == 'tool.dart',
    'argv',
  );
  _expect(record.cwd == '/workspace', 'cwd');
  _expect(
    record.redactedEnvironment['TOKEN'] == '<redacted>',
    'redacted TOKEN',
  );
  _expect(record.redactedEnvironment['PATH'] == '/usr/bin', 'PATH');
  _expect(record.stdoutDeltas.length == 1, 'stdout count');
  _expect(record.stderrDeltas.length == 1, 'stderr count');
  _expect(record.stdoutDeltas.single.text == 'hello\n', 'stdout text');
  _expect(record.stderrDeltas.single.text == 'warning\n', 'stderr text');
  _expect(record.diagnostics.single.code == 'lint', 'diagnostic code');
  _expect(
    record.runtimeEvents.first.kind == TaskExecutionEventKind.started,
    'started event',
  );
  _expect(
    record.runtimeEvents.any(
      (event) => event.kind == TaskExecutionEventKind.cancelled,
    ),
    'cancel event',
  );
  _expect(
    record.cancellation?.reason == 'User cancelled the task.',
    'cancellation',
  );
  _expect(
    record.cleanup?.message == 'Released temporary files.',
    'cleanup message',
  );
  _expect(record.completed, 'completed');
  _expect(record.cleanedUp, 'cleaned up');
  _expect(
    restored.runtimeEvents.length == record.runtimeEvents.length,
    'round-trip runtime events',
  );
  _expect(
    restored.cancellation?.reason == 'User cancelled the task.',
    'round-trip cancellation',
  );
  _expect(
    restored.cleanup?.message == 'Released temporary files.',
    'round-trip cleanup',
  );

  // ignore: avoid_print
  print('task_execution_runtime_test passed');
}

void _expect(bool condition, String label) {
  if (!condition) {
    throw StateError('task_execution_runtime_test failed: $label');
  }
}
