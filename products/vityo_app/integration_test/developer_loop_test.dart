import 'dart:io';

import 'package:vityo_app/src/ide/execution/developer_loop_service.dart';
import 'package:vityo_app/src/ide/execution/developer_operation_adapter.dart';
import 'package:vityo_app/src/ide/execution/execution_receipt.dart';
import 'package:vityo_app/src/ide/execution/process_developer_operation_adapter.dart';
import 'package:vityo_app/src/ide/workbench/capability_snapshot.dart';
import 'package:vityo_app/src/ide/workbench/ide_fact_provider.dart';

Future<void> main() async {
  const revision = 7;
  final runCapability = IdeCapabilityFact(
    id: 'ide.run',
    domain: IdeCapabilityDomain.run,
    state: IdeCapabilityState.available,
    provenance: 'dart-sdk',
    message: 'Dart process execution is available.',
  );
  final debugCapability = IdeCapabilityFact(
    id: 'ide.debug',
    domain: IdeCapabilityDomain.debug,
    state: IdeCapabilityState.blocked,
    provenance: 'vityo',
    message: 'No debug adapter is configured.',
  );
  final service = DeveloperLoopService(
    currentWorkspaceRevision: () => revision,
    adapters: <DeveloperOperationAdapter>[
      ProcessDeveloperOperationAdapter(
        kind: DeveloperOperationKind.run,
        capabilities: <IdeCapabilityFact>[runCapability],
        executable: Platform.resolvedExecutable,
        arguments: const <String>['--version'],
        workingDirectory: Directory.current.path,
      ),
      UnavailableDeveloperOperationAdapter(
        kind: DeveloperOperationKind.debug,
        capability: debugCapability,
      ),
    ],
  );

  final runReceipt = await service.execute(
    operationId: 'dart-version',
    kind: DeveloperOperationKind.run,
    expectedWorkspaceRevision: revision,
  );
  if (runReceipt.status != ExecutionReceiptStatus.succeeded ||
      runReceipt.exitCode != 0 ||
      runReceipt.workspaceRevision != revision) {
    throw StateError('process receipt did not report truthful success');
  }

  final blockedReceipt = await service.execute(
    operationId: 'debug-unavailable',
    kind: DeveloperOperationKind.debug,
    expectedWorkspaceRevision: revision,
  );
  if (blockedReceipt.status != ExecutionReceiptStatus.blocked ||
      blockedReceipt.exitCode != null) {
    throw StateError('unavailable capability did not fail closed');
  }

  final facts = await service.read(const IdeFactQuery(), revision);
  if (facts.receipts.length != 2 ||
      facts.capabilities.capabilities['ide.debug']?.state !=
          IdeCapabilityState.blocked) {
    throw StateError('fact provider did not expose the shared receipt source');
  }
}
