import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';

void main() {
  test('execution session exposes stable result contract', () {
    const session = ExecutionSession(
      sessionId: 'run-1',
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage: 'Run finished.',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[ExecutionLogEvent(message: 'ok')],
      stderrEvents: <ExecutionLogEvent>[],
      unitRange: SourceRange(start: 1, end: 5),
    );

    final contract = session.toResultContract(
      metadata: const <String, Object?>{'route': 'local'},
    );
    final json = session.toJson();

    expect(contract.source, 'execution-session');
    expect(contract.succeeded, isTrue);
    expect(contract.toJson()['stdoutCount'], 1);
    expect(contract.toJson()['metadata'], <String, Object?>{'route': 'local'});
    expect(json['unitRange'], <String, int>{'start': 1, 'end': 5});
  });

  test('native tool result maps onto execution result contract', () {
    final record = NativeToolResultRecord(
      command: AppCommandId.runBuild,
      label: 'Run Build',
      applied: false,
      message: 'Build failed.',
      metadata: const <String, Object?>{
        'buildResult': <String, Object?>{'status': 'failed'},
      },
      diagnostics: const <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'build.failed',
          message: 'Build failed.',
          range: SourceRange(start: 0, end: 1),
        ),
      ],
      completedAt: DateTime.utc(2026, 5, 20),
    );

    final contract = record.toResultContract();
    final json = record.toJson();

    expect(contract.source, 'native-tool');
    expect(contract.kind, 'runBuild');
    expect(contract.failed, isTrue);
    expect(contract.diagnosticCount, 1);
    expect(json['executionResult'], isA<Map<String, Object?>>());
  });

  test('runtime event envelope serializes event contract', () {
    final event = RuntimeEventEnvelope(
      schemaVersion: 1,
      sessionId: 'run-1',
      sequence: 3,
      timestamp: DateTime.utc(2026, 5, 20, 1, 2, 3),
      eventKind: 'run.finished',
      origin: 'styio.runtime',
      payload: const <String, Object?>{'success': true},
    );

    final json = event.toJson();

    expect(json['sessionId'], 'run-1');
    expect(json['eventKind'], 'run.finished');
    expect(json['timestamp'], '2026-05-20T01:02:03.000Z');
    expect(json['payload'], <String, Object?>{'success': true});
  });
}
