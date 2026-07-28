import 'package:test/test.dart';

import 'package:styio_ide/src/ide/execution/developer_loop_service.dart';
import 'package:styio_ide/src/ide/execution/developer_operation_adapter.dart';
import 'package:styio_ide/src/ide/execution/execution_receipt.dart';
import 'package:styio_ide/src/ide/language/dart_analyze_diagnostic_decoder.dart';
import 'package:styio_ide/src/ide/language/diagnostic_fact.dart';
import 'package:styio_ide/src/ide/workbench/capability_snapshot.dart';
import 'package:styio_ide/src/ide/workbench/ide_fact_provider.dart';

void main() {
  test('retains bounded revisioned receipts and filters facts', () async {
    var revision = 3;
    final adapter = _SuccessfulAdapter(_capability('ide.run'));
    final service = DeveloperLoopService(
      currentWorkspaceRevision: () => revision,
      adapters: <DeveloperOperationAdapter>[adapter],
      maxReceipts: 2,
      maxOutputCodeUnits: 4,
    );

    for (var index = 0; index < 3; index += 1) {
      await service.execute(
        operationId: 'run-$index',
        kind: DeveloperOperationKind.run,
        expectedWorkspaceRevision: revision,
      );
    }

    final facts = await service.read(
      const IdeFactQuery(capabilityIds: <String>['ide.run']),
      revision,
    );
    expect(facts.receipts.map((receipt) => receipt.operationId), <String>[
      'run-1',
      'run-2',
    ]);
    expect(facts.receipts.last.output.text, '0123');
    expect(facts.receipts.last.output.omittedCodeUnits, 6);
    expect(facts.capabilities.capabilities.keys, <String>['ide.run']);

    revision += 1;
    expect(
      () => service.read(const IdeFactQuery(), revision - 1),
      throwsA(isA<StaleIdeFactRevision>()),
    );
  });

  test('blocked capabilities never call their effect adapter', () async {
    final adapter = _CountingBlockedAdapter();
    final service = DeveloperLoopService(
      currentWorkspaceRevision: () => 1,
      adapters: <DeveloperOperationAdapter>[adapter],
    );

    final receipt = await service.execute(
      operationId: 'blocked',
      kind: DeveloperOperationKind.debug,
      expectedWorkspaceRevision: 1,
    );
    expect(receipt.status, ExecutionReceiptStatus.blocked);
    expect(receipt.exitCode, isNull);
    expect(adapter.callCount, 0);
  });

  test('machine diagnostics are typed, relative, and complete', () {
    final decoder = DartAnalyzeMachineDiagnosticDecoder(
      workspaceRoot: r'C:\workspace',
    );
    final batch = decoder.decode(
      output: BoundedText.from(
        r'ERROR|COMPILE_TIME_ERROR|UNDEFINED_NAME|C:\workspace\lib\main.dart|2|3|4|Undefined name',
        maxCodeUnits: 1024,
      ),
      errorOutput: BoundedText.empty,
      exitCode: 0,
    );

    expect(batch.state, IdeCapabilityState.available);
    expect(batch.diagnostics, hasLength(1));
    expect(batch.diagnostics.single.resourceId, 'lib/main.dart');
    expect(batch.diagnostics.single.severity, IdeDiagnosticSeverity.error);
    expect(batch.diagnostics.single.line, 2);
  });
}

IdeCapabilityFact _capability(String id) => IdeCapabilityFact(
  id: id,
  domain: IdeCapabilityDomain.run,
  state: IdeCapabilityState.available,
  provenance: 'test-adapter',
  message: 'Available for tests.',
);

final class _SuccessfulAdapter implements DeveloperOperationAdapter {
  _SuccessfulAdapter(IdeCapabilityFact capability)
    : capabilities = <IdeCapabilityFact>[capability];

  @override
  DeveloperOperationKind get kind => DeveloperOperationKind.run;

  @override
  final List<IdeCapabilityFact> capabilities;

  @override
  Future<DeveloperOperationResult> execute(
    DeveloperOperationContext context,
  ) async {
    return DeveloperOperationResult.succeeded(
      provenance: 'test-adapter',
      message: 'Completed.',
      output: BoundedText.from('0123456789', maxCodeUnits: 10),
    );
  }
}

final class _CountingBlockedAdapter implements DeveloperOperationAdapter {
  var callCount = 0;

  @override
  DeveloperOperationKind get kind => DeveloperOperationKind.debug;

  @override
  List<IdeCapabilityFact> get capabilities => <IdeCapabilityFact>[
    IdeCapabilityFact(
      id: 'ide.debug',
      domain: IdeCapabilityDomain.debug,
      state: IdeCapabilityState.blocked,
      provenance: 'test-adapter',
      message: 'Debug adapter is unavailable.',
    ),
  ];

  @override
  Future<DeveloperOperationResult> execute(
    DeveloperOperationContext context,
  ) async {
    callCount += 1;
    return const DeveloperOperationResult.succeeded(
      provenance: 'test-adapter',
      message: 'Should never run.',
    );
  }
}
