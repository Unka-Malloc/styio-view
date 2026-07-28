import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('toolchain runtime propagates process identity metadata', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-fixture',
          kind: ToolchainKind.runner,
          displayName: 'Styio Fixture',
          executablePath: '/usr/bin/styio',
        ),
        activate: true,
      );
    final runtime = ToolchainRuntime(
      catalog: catalog,
      processManager: _IdentityProcessManager(),
    );

    final result = await runtime.run(
      kind: ToolchainKind.runner,
      arguments: const <String>['check', '.'],
    );

    expect(result.succeeded, isTrue);
    expect(result.metadata['processHandleId'], 'toolchain-proc-1');
    expect(result.metadata['pid'], 6161);
    expect(result.toJson()['metadata'], isA<Map<String, Object?>>());
  });

  test('toolchain manager runtime result exposes typed process identity', () {
    const definition = RuntimeTaskDefinition(
      id: 'styio-check',
      label: 'Styio Check',
      kind: RuntimeTaskKind.test,
      command: 'styio',
    );
    final binding = const RuntimeExecutionPlanner()
        .plan(definition: definition)
        .createHandoff(target: RuntimeExecutionHandoffTarget.toolchainManager)
        .bind();
    const runtimeResult = ToolchainRuntimeResult(
      status: ToolchainRuntimeStatus.succeeded,
      toolchainId: 'styio-fixture',
      stdout: 'ok',
      stderr: '',
      exitCode: 0,
      metadata: <String, Object?>{
        'processHandleId': 'toolchain-proc-1',
        'pid': 6161,
        'processHandleSource': 'toolchain-runtime',
      },
    );

    final result = ToolchainManagerRuntimeExecutionResult(
      binding: binding,
      status: ToolchainManagerRuntimeExecutionStatus.executed,
      outputEvents: <RuntimeOutputEvent>[],
      runtimeResult: runtimeResult,
    );

    expect(result.processHandle?.processHandleId, 'toolchain-proc-1');
    expect(result.processHandle?.pid, 6161);
    expect(result.processHandle?.source, 'toolchain-runtime');
    expect(result.toJson()['processHandle'], isA<Map<String, Object?>>());
  });
}

class _IdentityProcessManager implements ProcessManager {
  @override
  final ProcessFacts facts = ProcessFacts.linuxDebianArm();

  @override
  final ProcessCompatibility compatibility = ProcessAdapter(
    ProcessFacts.linuxDebianArm(),
  ).adapt();

  @override
  Future<ProcessCommandResult> run(ProcessCommandRequest request) async {
    return ProcessCommandResult(
      status: ProcessCommandStatus.succeeded,
      executablePath: request.executablePath,
      arguments: request.arguments,
      exitCode: 0,
      stdout: 'ok',
      stderr: '',
      duration: const Duration(milliseconds: 12),
      metadata: const <String, Object?>{
        'processHandleId': 'toolchain-proc-1',
        'pid': 6161,
        'processHandleSource': 'toolchain-runtime',
      },
    );
  }

  @override
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    return null;
  }
}
