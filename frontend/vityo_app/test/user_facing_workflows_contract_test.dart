import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/app_bootstrap.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/commands/command_palette_model.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/transactions/transactions.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/workspace/hosted_workspace_lifecycle.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_diagnostics.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Workflow 1: Editor Transaction -- document edit lifecycle
  // ---------------------------------------------------------------------------
  group('editor transaction workflow', () {
    test('success: single valid text edit applies and bumps revision', () {
      const doc = DocumentState(
        documentId: 'test.dart',
        text: 'hello world',
        revision: 1,
      );
      final edit = WorkspaceEdit.singleDocument(
        document: doc,
        source: WorkspaceEditSource.userInput,
        edits: <WorkspaceTextEdit>[
          const WorkspaceTextEdit(
            documentId: 'test.dart',
            range: SourceRange(start: 6, end: 11),
            newText: 'vityo',
          ),
        ],
      );

      const service = EditorTransactionService();
      final validation = service.validateForDocument(document: doc, edit: edit);

      expect(validation.isValid, isTrue);
      expect(validation.code, WorkspaceEditValidationCode.ok);

      final result = service.applyToDocument(document: doc, edit: edit);

      expect(result.isApplied, isTrue);
      expect(result.appliedEditCount, 1);
      expect(result.document.revision, 2);
      expect(result.document.text, 'hello vityo');
      expect(
        result.contentHash,
        sha256.convert(utf8.encode('hello vityo')).toString(),
      );
    });

    test('blocked: stale revision precondition rejects edit', () {
      const doc = DocumentState(
        documentId: 'test.dart',
        text: 'hello world',
        revision: 1,
      );
      const stalePrecondition = WorkspaceEditPrecondition(
        documentId: 'test.dart',
        expectedRevision: 42,
        expectedContentHash: null,
      );
      const edit = WorkspaceEdit(
        source: WorkspaceEditSource.userInput,
        edits: <WorkspaceTextEdit>[
          WorkspaceTextEdit(
            documentId: 'test.dart',
            range: SourceRange(start: 0, end: 5),
            newText: 'hi',
          ),
        ],
        precondition: stalePrecondition,
      );

      const service = EditorTransactionService();
      final validation = service.validateForDocument(document: doc, edit: edit);

      expect(validation.isValid, isFalse);
      expect(validation.code, WorkspaceEditValidationCode.staleRevision);
      expect(validation.message, contains('42'));
    });

    test('recovery: empty edits report as empty and document unchanged', () {
      const doc = DocumentState(
        documentId: 'test.dart',
        text: 'unchanged',
        revision: 5,
      );
      final edit = WorkspaceEdit(
        source: WorkspaceEditSource.codeAction,
        edits: <WorkspaceTextEdit>[],
        precondition: WorkspaceEditPrecondition.forDocument(doc),
      );

      const service = EditorTransactionService();
      final validation = service.validateForDocument(document: doc, edit: edit);

      expect(validation.isValid, isFalse);
      expect(validation.code, WorkspaceEditValidationCode.empty);

      final result = service.applyToDocument(document: doc, edit: edit);

      expect(result.isApplied, isFalse);
      expect(result.appliedEditCount, 0);
      expect(result.document.revision, 5);
      expect(result.document.text, 'unchanged');
    });
  });

  // ---------------------------------------------------------------------------
  // Workflow 2: Command Palette -- query, filter, select
  // ---------------------------------------------------------------------------
  group('command palette workflow', () {
    final allCommands = StyioCommandRegistry.commands.toList(growable: false);

    test('success: empty query returns all commands with score >= 1', () {
      final model = CommandPaletteModel(commands: allCommands);
      final state = const CommandPaletteQueryState();
      final entries = model.entriesFor(state);

      expect(entries.length, allCommands.length);
      for (final entry in entries) {
        expect(entry.score, greaterThanOrEqualTo(1));
      }
    });

    test('blocked: query with no match returns empty overlay', () {
      final model = CommandPaletteModel(commands: allCommands);
      final state = const CommandPaletteQueryState(
        query: 'zzz_nonexistent_zzz_top_level_42',
      );
      final entries = model.entriesFor(state);

      expect(entries, isEmpty);

      final overlay = model.overlayStateFor(state);
      expect(overlay.empty, isTrue);
      expect(overlay.visibleCount, 0);
      expect(overlay.selectedEntry, isNull);
    });

    test('recovery: narrowing query reduces entries and re-ranks', () {
      final model = CommandPaletteModel(commands: allCommands);
      final broadState = const CommandPaletteQueryState(query: 'run');
      final broadEntries = model.entriesFor(broadState);

      expect(broadEntries.length, greaterThanOrEqualTo(3));

      final narrowState = const CommandPaletteQueryState(query: 'run test');
      final narrowEntries = model.entriesFor(narrowState);

      expect(narrowEntries.length, lessThan(broadEntries.length));

      final recoveredState = const CommandPaletteQueryState(query: '');
      final recoveredEntries = model.entriesFor(recoveredState);

      expect(recoveredEntries.length, allCommands.length);

      for (final e in recoveredEntries) {
        expect(e.score, greaterThanOrEqualTo(1));
      }
    });

    test('recovery: recent command boost lifts matching entries', () {
      final model = CommandPaletteModel(commands: allCommands);
      const state = CommandPaletteQueryState(
        query: 'save',
        recentCommandIds: <AppCommandId>[AppCommandId.saveAll],
      );
      final entries = model.entriesFor(state);

      expect(entries, isNotEmpty);
      final save = entries.firstWhere(
        (e) => e.command.id == AppCommandId.save,
        orElse: () => fail('save command not found'),
      );
      final saveAll = entries.firstWhere(
        (e) => e.command.id == AppCommandId.saveAll,
        orElse: () => fail('saveAll command not found'),
      );

      expect(saveAll.recent, isTrue);
      expect(saveAll.recentRank, 0);
      expect(saveAll.score, greaterThan(save.score));
    });
  });

  // ---------------------------------------------------------------------------
  // Workflow 3: Hosted Workspace Lifecycle -- close, connector parity, expiry
  // ---------------------------------------------------------------------------
  group('hosted workspace lifecycle workflow', () {
    final baseTime = DateTime.utc(2026, 6, 15, 12, 0, 0);

    ProjectGraphSnapshot projectWithWorkspace({
      required HostedWorkspaceStatus status,
      HostedWorkspaceExportState exportState =
          HostedWorkspaceExportState.notRequested,
      String entryUrl = 'https://hosted.example.com/ws/demo',
      int retentionDays = 7,
      DateTime? closedAt,
    }) {
      return ProjectGraphSnapshot(
        id: 'demo',
        title: 'Demo Project',
        kind: ProjectKind.hosted,
        workspaceRoot: '/workspace/demo',
        workspaceMembers: <String>['/workspace/demo'],
        manifestPath: '/workspace/demo/vityo.yaml',
        packages: <ProjectPackageSnapshot>[],
        dependencies: <ProjectDependencySnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>[],
        toolchain: const ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.unavailable,
          detail: 'No toolchain configured.',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.unknown,
        notes: const <String>[],
        hostedWorkspace: HostedWorkspaceRecordSnapshot(
          workspaceId: 'ws-demo',
          schemaVersion: '1',
          ownerRef: 'user-abc',
          status: status,
          entryUrl: entryUrl,
          createdAt: baseTime.subtract(const Duration(days: 30)),
          lastActiveAt: baseTime.subtract(const Duration(days: 2)),
          retentionDays: retentionDays,
          exportState: exportState,
          closedAt: closedAt,
        ),
      );
    }

    test('success: active workspace close plan requires confirmation', () {
      final lifecycle = const HostedWorkspaceLifecycle();
      final project = projectWithWorkspace(
        status: HostedWorkspaceStatus.active,
      );

      final plan = lifecycle.closePlanFor(project, now: baseTime);

      expect(plan, isNotNull);
      expect(plan!.workspaceId, 'ws-demo');
      expect(plan.status, HostedWorkspaceStatus.active);
      expect(plan.requiresClearConfirmation, isTrue);
      expect(plan.pendingDeletionPlan, isNull);
    });

    test('success: ready connector parity report', () {
      final lifecycle = const HostedWorkspaceLifecycle();
      final project = projectWithWorkspace(
        status: HostedWorkspaceStatus.active,
      );

      final report = lifecycle.connectorParityReportFor(
        project,
        controlPlaneAvailable: true,
        documentStoreAvailable: true,
        backendReachable: true,
      );

      expect(report.ready, isTrue);
      expect(report.status, HostedBackendConnectorStatus.ready);
      expect(report.checks.length, 4);
      for (final check in report.checks) {
        expect(check.available, isTrue);
      }
    });

    test('blocked: missing hosted workspace record is unavailable', () {
      final lifecycle = const HostedWorkspaceLifecycle();
      const project = ProjectGraphSnapshot(
        id: 'local',
        title: 'Local Project',
        kind: ProjectKind.workspace,
        workspaceRoot: '/workspace/local',
        workspaceMembers: <String>['/workspace/local'],
        manifestPath: '/workspace/local/vityo.yaml',
        packages: <ProjectPackageSnapshot>[],
        dependencies: <ProjectDependencySnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>[],
        toolchain: ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.unavailable,
          detail: 'No toolchain configured.',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.unknown,
        notes: <String>[],
        hostedWorkspace: null,
      );

      final plan = lifecycle.closePlanFor(project);
      expect(plan, isNull);

      final report = lifecycle.connectorParityReportFor(project);

      expect(report.ready, isFalse);
      expect(report.status, HostedBackendConnectorStatus.unavailable);
      expect(report.message, contains('No hosted workspace record'));
    });

    test(
      'recovery: retry actions surfaced when document store unavailable',
      () {
        final lifecycle = const HostedWorkspaceLifecycle();
        final project = projectWithWorkspace(
          status: HostedWorkspaceStatus.active,
        );

        final report = lifecycle.connectorParityReportFor(
          project,
          controlPlaneAvailable: true,
          documentStoreAvailable: false,
          backendReachable: false,
          failureMessage: 'Connection refused',
        );

        expect(report.ready, isFalse);

        final retryConnect = report.actionFor(
          HostedBackendRetryActionKind.retryConnect,
        );
        expect(retryConnect, isNotNull);
        expect(retryConnect!.kind, HostedBackendRetryActionKind.retryConnect);
        expect(retryConnect.enabled, isTrue);

        final openSettings = report.actionFor(
          HostedBackendRetryActionKind.openSettings,
        );
        expect(openSettings, isNotNull);
        expect(openSettings!.kind, HostedBackendRetryActionKind.openSettings);
        expect(openSettings.endpointPlan, isNotNull);
      },
    );

    test('recovery: pending deletion plan computed from retention days', () {
      final lifecycle = const HostedWorkspaceLifecycle();
      final closedAt = baseTime.subtract(const Duration(days: 3));
      final project = projectWithWorkspace(
        status: HostedWorkspaceStatus.pendingDeletion,
        retentionDays: 7,
        closedAt: closedAt,
      );

      final plan = lifecycle.closePlanFor(project, now: baseTime);

      expect(plan, isNotNull);
      expect(plan!.status, HostedWorkspaceStatus.pendingDeletion);
      expect(plan.requiresClearConfirmation, isTrue);

      final deletionPlan = plan.pendingDeletionPlan;
      expect(deletionPlan, isNotNull);
      expect(deletionPlan!.retentionDays, 7);
      expect(deletionPlan.closedAt, closedAt);
      expect(deletionPlan.expired, isFalse);
      expect(deletionPlan.remaining.inDays, 4);
    });

    test('blocked: expired deletion plan signals deadline passed', () {
      final lifecycle = const HostedWorkspaceLifecycle();
      final closedAt = baseTime.subtract(const Duration(days: 10));
      final project = projectWithWorkspace(
        status: HostedWorkspaceStatus.pendingDeletion,
        retentionDays: 7,
        closedAt: closedAt,
      );

      final plan = lifecycle.closePlanFor(project, now: baseTime);

      final deletionPlan = plan!.pendingDeletionPlan!;
      expect(deletionPlan.expired, isTrue);
      expect(deletionPlan.remaining, Duration.zero);
    });
  });

  // ---------------------------------------------------------------------------
  // Workflow 4: App Bootstrap Service Wiring -- absent/injected contract
  // ---------------------------------------------------------------------------
  group('app bootstrap service wiring contract', () {
    test('success: injected service descriptor reports ready wiring', () {
      const entry = AppBootstrapServiceWiringEntry(
        descriptor: AppBootstrapServiceDescriptor(
          serviceId: 'agent.provider.registry',
          ownerLayer: 'agent',
          requiredInjection: false,
        ),
        state: AppBootstrapServiceWiringState.injected,
      );

      expect(entry.state, AppBootstrapServiceWiringState.injected);
      expect(entry.descriptor.hasAbsentStateContract, isFalse);
      expect(entry.descriptor.serviceId, 'agent.provider.registry');
    });

    test('blocked: absent required service has capability gap', () {
      final descriptor = const AppBootstrapServiceDescriptor(
        serviceId: 'styio.language.service',
        ownerLayer: 'language-service',
        requiredInjection: true,
        capabilityGapCode: 'STYIO_LS_UNAVAILABLE',
        recoveryAction: 'bootstrapStyioToolchain',
      );

      expect(descriptor.hasAbsentStateContract, isTrue);
      expect(descriptor.capabilityGapCode, 'STYIO_LS_UNAVAILABLE');
      expect(descriptor.recoveryAction, 'bootstrapStyioToolchain');
    });

    test('recovery: absent gap provides actionable recovery hint', () {
      final descriptor = const AppBootstrapServiceDescriptor(
        serviceId: 'native.toolchain.catalog',
        ownerLayer: 'toolchain',
        requiredInjection: true,
        capabilityGapCode: 'NO_DEFAULT_TOOLCHAIN',
        recoveryAction: 'executeToolchainInstallPlan',
      );

      expect(descriptor.hasAbsentStateContract, isTrue);
      expect(descriptor.recoveryAction, 'executeToolchainInstallPlan');
      expect(descriptor.capabilityGapCode, 'NO_DEFAULT_TOOLCHAIN');

      final entry = AppBootstrapServiceWiringEntry(
        descriptor: descriptor,
        state: AppBootstrapServiceWiringState.absent,
      );
      expect(entry.accountedFor, isTrue);
      expect(entry.injected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Workflow 5: Workspace Diagnostics Producer Execution Plan
  // ---------------------------------------------------------------------------
  group('workspace diagnostics producer contract', () {
    test('success: native tool producer builds runnable execution plan', () {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['main.cc'],
        activeDocumentId: 'main.cc',
      );

      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'clang-tidy',
        request: request,
        command: '/usr/bin/clang-tidy',
        arguments: <String>['--checks=*'],
        workingDirectory: '/workspace/demo',
      );

      expect(plan.providerId, 'clang-tidy');
      expect(plan.definition.id, 'diagnostics.clang-tidy');
      expect(plan.definition.command, '/usr/bin/clang-tidy');
      expect(plan.executionPlan.ready, isTrue);
      expect(plan.executionPlan.status, RuntimeExecutionPlanStatus.ready);
      expect(plan.handoff.ready, isTrue);
      expect(plan.handoff.status, RuntimeExecutionHandoffStatus.ready);
      expect(plan.binding.ready, isTrue);
      expect(plan.binding.status, RuntimeExecutionHandoffBindingStatus.ready);
      expect(
        plan.binding.outputChannel.kind,
        RuntimeOutputChannelKind.nativeTools,
      );
    });

    test('blocked: empty command blocks execution plan', () {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['main.cc'],
        activeDocumentId: 'main.cc',
      );

      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'missing-analyzer',
        request: request,
        command: '',
        arguments: <String>[],
      );

      expect(plan.definition.command, isEmpty);
      expect(
        plan.executionPlan.status,
        RuntimeExecutionPlanStatus.blockedUnrunnable,
      );
      expect(plan.executionPlan.ready, isFalse);
    });

    test('recovery: handoff bind produces ready binding for ready plan', () {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['lib.dart'],
        activeDocumentId: 'lib.dart',
      );

      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'dart-analyzer',
        request: request,
        command: '/opt/dart-sdk/bin/dart',
        arguments: <String>['analyze'],
      );

      expect(plan.handoff.ready, isTrue);

      final rebound = plan.handoff.bind(
        outputKind: RuntimeOutputChannelKind.nativeTools,
        metadata: <String, Object?>{
          'diagnosticsProducer': true,
          'diagnosticsProviderId': 'dart-analyzer',
        },
      );
      expect(rebound.ready, isTrue);
      expect(rebound.status, RuntimeExecutionHandoffBindingStatus.ready);
      expect(rebound.outputChannel.kind, RuntimeOutputChannelKind.nativeTools);
    });
  });
}
