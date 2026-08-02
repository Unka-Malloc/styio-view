import 'dart:io';

import '../../../products/vityo_app/lib/src/ide/execution/developer_loop_service.dart';
import '../../../products/vityo_app/lib/src/ide/execution/developer_operation_adapter.dart';
import '../../../products/vityo_app/lib/src/ide/execution/execution_receipt.dart';
import '../../../products/vityo_app/lib/src/ide/execution/process_developer_operation_adapter.dart';
import '../../../products/vityo_app/lib/src/ide/agent_client/tools/context_export_service.dart';
import '../../../products/vityo_app/lib/src/ide/agent_client/tools/ide_tool_catalog.dart';
import '../../../products/vityo_app/lib/src/ide/agent_client/tools/tool_security_policy.dart';
import '../../../products/vityo_app/lib/src/ide/language/dart_analyze_diagnostic_decoder.dart';
import '../../../products/vityo_app/lib/src/ide/workbench/capability_snapshot.dart';
import '../../../products/vityo_app/lib/src/ide/workbench/ide_fact_consumers.dart';
import '../../../products/vityo_app/lib/src/ide/workbench/ide_fact_provider.dart';
import '../../../products/vityo_app/lib/src/ide/workspace/workspace_change_set.dart';
import '../../../products/vityo_app/lib/src/ide/workspace/workspace_revision_service.dart';
import '../../../products/vityo_app/lib/src/ide/workspace/workspace_transaction_service.dart';

Future<void> main() async {
  final fixtureRoot = Directory.fromUri(
    Platform.script.resolve('../fixtures/vityo_app/developer_loop/'),
  );
  final temporaryRoot = await Directory.systemTemp.createTemp(
    'styio-developer-loop-',
  );
  try {
    await _copyFixture(fixtureRoot, temporaryRoot);
    final mainFile = File(
      '${temporaryRoot.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}main.dart',
    );
    final initialText = await mainFile.readAsString();

    final revisions = InMemoryWorkspaceRevisionService();
    final transactions = RevisionedWorkspaceTransactionService(revisions);
    final workspace = StandaloneIdeWorkspace(
      revisions: revisions,
      transactions: transactions,
    );
    await workspace.open(<String, String>{'lib/main.dart': initialText});

    final before = revisions.snapshot();
    final markerStart = initialText.indexOf("'before'");
    _expect(markerStart >= 0, 'fixture must contain the editable marker');
    final preview = await workspace.edit(
      WorkspaceChangeSet(
        id: 'developer-loop-edit',
        baseWorkspaceRevision: before.workspaceRevision,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'lib/main.dart',
            baseDocumentRevision: before.document('lib/main.dart').revision,
            edits: <WorkspaceTextChange>[
              WorkspaceTextChange(
                start: markerStart,
                end: markerStart + "'before'".length,
                replacement: "'after'",
              ),
            ],
          ),
        ],
      ),
    );
    final editReceipt = await transactions.commit(preview.id);
    _expect(
      editReceipt.outcome == WorkspaceTransactionOutcome.committed,
      'fixture edit must commit through the workspace transaction owner',
    );
    final editedRevision = editReceipt.workspaceRevision;

    final capabilities = _capabilities();
    final saveAdapter = _SaveAdapter(
      capability: capabilities['ide.save']!,
      target: mainFile,
      readText: () => revisions.snapshot().document('lib/main.dart').text,
    );
    final service = DeveloperLoopService(
      currentWorkspaceRevision: () => revisions.snapshot().workspaceRevision,
      adapters: <DeveloperOperationAdapter>[
        saveAdapter,
        ProcessDeveloperOperationAdapter(
          kind: DeveloperOperationKind.analyze,
          capabilities: <IdeCapabilityFact>[
            capabilities['ide.language.analyze']!,
            capabilities['ide.diagnostics']!,
          ],
          executable: Platform.resolvedExecutable,
          arguments: const <String>[
            'analyze',
            '--format=machine',
            'lib',
            'test',
          ],
          workingDirectory: temporaryRoot.path,
          diagnosticDecoder: DartAnalyzeMachineDiagnosticDecoder(
            workspaceRoot: temporaryRoot.path,
          ),
        ),
        ProcessDeveloperOperationAdapter(
          kind: DeveloperOperationKind.test,
          capabilities: <IdeCapabilityFact>[capabilities['ide.test']!],
          executable: Platform.resolvedExecutable,
          arguments: const <String>['run', 'test/smoke.dart'],
          workingDirectory: temporaryRoot.path,
        ),
        ProcessDeveloperOperationAdapter(
          kind: DeveloperOperationKind.run,
          capabilities: <IdeCapabilityFact>[capabilities['ide.run']!],
          executable: Platform.resolvedExecutable,
          arguments: const <String>['run', 'lib/main.dart'],
          workingDirectory: temporaryRoot.path,
        ),
        for (final kind in <DeveloperOperationKind>[
          DeveloperOperationKind.format,
          DeveloperOperationKind.build,
          DeveloperOperationKind.debug,
          DeveloperOperationKind.sourceControl,
          DeveloperOperationKind.terminal,
          DeveloperOperationKind.toolchain,
          DeveloperOperationKind.packageManagement,
        ])
          UnavailableDeveloperOperationAdapter(
            kind: kind,
            capability: capabilities[_capabilityId(kind)]!,
          ),
      ],
      maxReceipts: 16,
    );

    final receipts = <ExecutionReceipt>[
      await service.execute(
        operationId: 'save-1',
        kind: DeveloperOperationKind.save,
        expectedWorkspaceRevision: editedRevision,
      ),
      await service.execute(
        operationId: 'analyze-1',
        kind: DeveloperOperationKind.analyze,
        expectedWorkspaceRevision: editedRevision,
      ),
      await service.execute(
        operationId: 'test-1',
        kind: DeveloperOperationKind.test,
        expectedWorkspaceRevision: editedRevision,
      ),
      await service.execute(
        operationId: 'run-1',
        kind: DeveloperOperationKind.run,
        expectedWorkspaceRevision: editedRevision,
      ),
    ];
    _expect(
      receipts.every(
        (receipt) =>
            receipt.status == ExecutionReceiptStatus.succeeded &&
            receipt.workspaceRevision == editedRevision &&
            receipt.exitCode == 0 &&
            receipt.provenance.isNotEmpty,
      ),
      'save, analyze, test, and run must emit successful revisioned receipts',
    );
    _expect(
      await mainFile.readAsString() ==
          revisions.snapshot().document('lib/main.dart').text,
      'save must persist the authoritative edited document',
    );
    _expect(
      receipts.last.output.text.trim() == 'after',
      'run must observe the saved edit instead of a visual substitute',
    );

    final blocked = await service.execute(
      operationId: 'debug-unavailable',
      kind: DeveloperOperationKind.debug,
      expectedWorkspaceRevision: editedRevision,
    );
    _expect(
      blocked.status == ExecutionReceiptStatus.blocked &&
          blocked.exitCode == null &&
          blocked.message.isNotEmpty,
      'an unavailable route must be an explicit blocked receipt',
    );
    final degraded = await service.execute(
      operationId: 'format-heuristic',
      kind: DeveloperOperationKind.format,
      expectedWorkspaceRevision: editedRevision,
    );
    _expect(
      degraded.status == ExecutionReceiptStatus.degraded &&
          degraded.exitCode == null &&
          degraded.message.isNotEmpty,
      'a heuristic route must remain explicitly degraded',
    );

    final provider = service as IdeFactProvider;
    final userReader = UserFacingIdeFactReader(provider);
    final userFacts = await userReader.read(
      const IdeFactQuery(),
      editedRevision,
    );
    final agentPage =
        await RevisionedIdeContextExportService(
          provider: provider,
          currentWorkspaceRevision: () =>
              revisions.snapshot().workspaceRevision,
          sanitizer: const McpPayloadSanitizer(),
        ).read(
          ContextQuery(expectedWorkspaceRevision: editedRevision),
          const ContextBudget(
            maxItems: 256,
            maxUtf8Bytes: 1024 * 1024,
            maxCodeUnitsPerItem: 256 * 1024,
          ),
        );
    _expect(
      userFacts.workspaceRevision == editedRevision &&
          userFacts.capabilities.capabilities.length == capabilities.length &&
          agentPage.workspaceRevision == editedRevision &&
          !agentPage.truncated &&
          agentPage.items.length ==
              capabilities.length + userFacts.receipts.length + 1 &&
          agentPage.items.every(
            (item) => item.sensitivity == ContextSensitivity.internal,
          ),
      'Agent context must use the bounded, sanitized, revision-bound export',
    );
    _expect(
      userFacts.diagnostics.workspaceRevision == editedRevision &&
          userFacts.diagnostics.state == IdeCapabilityState.available &&
          userFacts.diagnostics.diagnostics.isEmpty &&
          userFacts.diagnostics.provenance == 'dart-analyze-machine',
      'clean analyzer diagnostics must be structured and revision-bound',
    );
    _expect(
      IdeCapabilityDomain.values.every(
        (domain) => userFacts.capabilities.capabilities.values.any(
          (fact) => fact.domain == domain,
        ),
      ),
      'every developer domain must expose an explicit capability fact',
    );

    final next = revisions.snapshot();
    final stalePreview = await transactions.preview(
      WorkspaceChangeSet(
        id: 'make-facts-stale',
        baseWorkspaceRevision: next.workspaceRevision,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'lib/main.dart',
            baseDocumentRevision: next.document('lib/main.dart').revision,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(
                start: 0,
                end: 0,
                replacement: '// changed\n',
              ),
            ],
          ),
        ],
      ),
    );
    await transactions.commit(stalePreview.id);
    await _expectThrows<StaleIdeFactRevision>(
      () => provider.read(const IdeFactQuery(), editedRevision),
      'stale facts must fail closed rather than replaying cached success',
    );
  } finally {
    await temporaryRoot.delete(recursive: true);
  }
}

Map<String, IdeCapabilityFact> _capabilities() {
  IdeCapabilityFact fact(
    String id,
    IdeCapabilityDomain domain,
    IdeCapabilityState state,
    String message,
  ) {
    return IdeCapabilityFact(
      id: id,
      domain: domain,
      state: state,
      provenance: 'vityo',
      message: message,
    );
  }

  return <String, IdeCapabilityFact>{
    'ide.save': fact(
      'ide.save',
      IdeCapabilityDomain.save,
      IdeCapabilityState.available,
      'Workspace save is available.',
    ),
    'ide.language.analyze': fact(
      'ide.language.analyze',
      IdeCapabilityDomain.language,
      IdeCapabilityState.available,
      'Dart analyzer adapter is available.',
    ),
    'ide.diagnostics': fact(
      'ide.diagnostics',
      IdeCapabilityDomain.diagnostics,
      IdeCapabilityState.available,
      'Analyzer diagnostics are available.',
    ),
    'ide.format': fact(
      'ide.format',
      IdeCapabilityDomain.formatting,
      IdeCapabilityState.degraded,
      'Only heuristic formatting is configured.',
    ),
    'ide.build': fact(
      'ide.build',
      IdeCapabilityDomain.build,
      IdeCapabilityState.blocked,
      'No build adapter is configured.',
    ),
    'ide.run': fact(
      'ide.run',
      IdeCapabilityDomain.run,
      IdeCapabilityState.available,
      'Dart run adapter is available.',
    ),
    'ide.test': fact(
      'ide.test',
      IdeCapabilityDomain.test,
      IdeCapabilityState.available,
      'Fixture test adapter is available.',
    ),
    'ide.debug': fact(
      'ide.debug',
      IdeCapabilityDomain.debug,
      IdeCapabilityState.blocked,
      'No debug adapter is configured.',
    ),
    'ide.source-control': fact(
      'ide.source-control',
      IdeCapabilityDomain.sourceControl,
      IdeCapabilityState.blocked,
      'No source-control adapter is configured.',
    ),
    'ide.terminal': fact(
      'ide.terminal',
      IdeCapabilityDomain.terminal,
      IdeCapabilityState.blocked,
      'No terminal adapter is configured.',
    ),
    'ide.toolchain': fact(
      'ide.toolchain',
      IdeCapabilityDomain.toolchain,
      IdeCapabilityState.blocked,
      'No toolchain adapter is configured.',
    ),
    'ide.package': fact(
      'ide.package',
      IdeCapabilityDomain.packageManagement,
      IdeCapabilityState.blocked,
      'No package adapter is configured.',
    ),
  };
}

String _capabilityId(DeveloperOperationKind kind) => switch (kind) {
  DeveloperOperationKind.format => 'ide.format',
  DeveloperOperationKind.build => 'ide.build',
  DeveloperOperationKind.debug => 'ide.debug',
  DeveloperOperationKind.sourceControl => 'ide.source-control',
  DeveloperOperationKind.terminal => 'ide.terminal',
  DeveloperOperationKind.toolchain => 'ide.toolchain',
  DeveloperOperationKind.packageManagement => 'ide.package',
  _ => throw StateError('No unavailable capability for ${kind.name}.'),
};

final class _SaveAdapter implements DeveloperOperationAdapter {
  const _SaveAdapter({
    required this.capability,
    required this.target,
    required this.readText,
  });

  final IdeCapabilityFact capability;
  final File target;
  final String Function() readText;

  @override
  DeveloperOperationKind get kind => DeveloperOperationKind.save;

  @override
  List<IdeCapabilityFact> get capabilities => <IdeCapabilityFact>[capability];

  @override
  Future<DeveloperOperationResult> execute(
    DeveloperOperationContext context,
  ) async {
    await target.writeAsString(readText(), flush: true);
    return const DeveloperOperationResult.succeeded(
      provenance: 'workspace-save-adapter',
      message: 'Document persisted.',
    );
  }
}

Future<void> _copyFixture(Directory source, Directory target) async {
  final sourcePrefix = source.path.endsWith(Platform.pathSeparator)
      ? source.path
      : '${source.path}${Platform.pathSeparator}';
  for (final entity in source.listSync(recursive: true)) {
    final relative = entity.path.substring(sourcePrefix.length);
    final destination = '${target.path}${Platform.pathSeparator}$relative';
    if (entity is Directory) {
      await Directory(destination).create(recursive: true);
    } else if (entity is File) {
      await File(destination).parent.create(recursive: true);
      await entity.copy(destination);
    }
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

Future<void> _expectThrows<T extends Object>(
  Future<void> Function() action,
  String message,
) async {
  try {
    await action();
  } on T {
    return;
  }
  throw StateError(message);
}
