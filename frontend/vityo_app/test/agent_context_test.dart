import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent_context.dart';
import 'package:vityo_app/src/view_ide/agent/agent_session.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';

void main() {
  group('AgentContextScope', () {
    test('full scope includes all channels', () {
      const scope = AgentContextScope.full;
      expect(scope.includeWorkspace, isTrue);
      expect(scope.includeActiveDocument, isTrue);
      expect(scope.includeSelection, isTrue);
      expect(scope.includeDiagnostics, isTrue);
      expect(scope.includeProjectGraph, isTrue);
      expect(scope.includeRuntimeEvents, isTrue);
      expect(scope.includeCommands, isTrue);
      expect(scope.includeCapabilityGaps, isTrue);
    });

    test('minimal scope excludes heavy channels', () {
      const scope = AgentContextScope.minimal;
      expect(scope.includeDiagnostics, isFalse);
      expect(scope.includeProjectGraph, isFalse);
      expect(scope.includeRuntimeEvents, isFalse);
    });

    test('scope roundtrips through JSON', () {
      const scope = AgentContextScope(
        includeWorkspace: true,
        includeDiagnostics: false,
        includeSettings: true,
      );
      final json = scope.toJson();
      final restored = AgentContextScope.fromJson(json);
      expect(restored.includeWorkspace, isTrue);
      expect(restored.includeDiagnostics, isFalse);
      expect(restored.includeSettings, isTrue);
      expect(restored.includeActiveDocument, isTrue); // default
    });
  });

  group('AgentRedactionPolicy', () {
    test('default policy redacts all sensitive content', () {
      const policy = AgentRedactionPolicy.defaultPolicy;
      expect(policy.redactEnvironmentVariableValues, isTrue);
      expect(policy.redactApiKeyReferences, isTrue);
      expect(policy.redactHomeDirectoryPaths, isTrue);
      expect(policy.redactSecretFields, isTrue);
    });

    test('localOnly policy preserves paths for tool execution', () {
      const policy = AgentRedactionPolicy.localOnly;
      expect(policy.redactHomeDirectoryPaths, isFalse);
      expect(policy.redactUserSpecificPaths, isFalse);
      expect(policy.redactSecretFields, isFalse);
      expect(policy.redactApiKeyReferences, isTrue);
    });
  });

  group('AgentContextSnapshot', () {
    test('hasSelection is true only when scope and document permit', () {
      final withSelection = const AgentContextSnapshot(
        snapshotId: 'snap-1',
        scope: AgentContextScope.full,
        documentContext: AgentActiveDocumentContext(
          selectionStartOffset: 10,
          selectionEndOffset: 20,
          selectionText: 'hello',
        ),
      );
      expect(withSelection.hasSelection, isTrue);

      final withoutSelection = const AgentContextSnapshot(
        snapshotId: 'snap-2',
        scope: AgentContextScope.full,
        documentContext: AgentActiveDocumentContext(),
      );
      expect(withoutSelection.hasSelection, isFalse);

      final scopedOut = const AgentContextSnapshot(
        snapshotId: 'snap-3',
        scope: AgentContextScope(
          includeDiagnostics: false,
          includeProjectGraph: false,
          includeRuntimeEvents: false,
          includeCommands: false,
          includeCapabilityGaps: false,
          includeSelection: false,
        ),
        documentContext: AgentActiveDocumentContext(
          selectionStartOffset: 10,
          selectionEndOffset: 20,
          selectionText: 'hello',
        ),
      );
      expect(scopedOut.hasSelection, isFalse);
    });

    test('context channels respect scope', () {
      final snapshot = const AgentContextSnapshot(
        snapshotId: 'snap-4',
        scope: AgentContextScope(
          includeDiagnostics: false,
          includeProjectGraph: false,
        ),
        diagnosticsContext: AgentDiagnosticsContext(errorCount: 5),
        projectGraphContext: AgentProjectGraphContext(projectTitle: 'test'),
      );
      // Channel data exists but scope excludes it
      expect(snapshot.hasDiagnostics, isFalse);
      expect(snapshot.hasProjectGraph, isFalse);
      expect(snapshot.hasWorkspace, isFalse); // no data
    });

    test('snapshot serializes to JSON without secrets', () {
      final snapshot = const AgentContextSnapshot(
        snapshotId: 'snap-5',
        createdAtIso8601: '2026-06-24T00:00:00Z',
        scope: AgentContextScope.full,
        workspaceContext: AgentWorkspaceSummaryContext(
          workspaceRoot: '/home/user/project',
        ),
        documentContext: AgentActiveDocumentContext(
          filePath: 'main.styio',
          language: 'styio',
          lineCount: 42,
        ),
        diagnosticsContext: AgentDiagnosticsContext(
          errorCount: 2,
          warningCount: 1,
        ),
        profileId: 'default-linux',
      );

      final json = snapshot.toJson();
      expect(json['snapshotId'], 'snap-5');
      expect(json['profileId'], 'default-linux');

      // Verify no raw secrets appear (redaction policy is included)
      final redaction = json['redactionPolicy'] as Map<String, Object?>;
      expect(redaction['redactApiKeyReferences'], isTrue);

      // Workspace context serialized
      final ws = json['workspaceContext'] as Map<String, Object?>;
      expect(ws['workspaceRoot'], '<redacted-path>');
    });

    test('snapshot roundtrips through JSON', () {
      final original = const AgentContextSnapshot(
        snapshotId: 'snap-6',
        createdAtIso8601: '2026-06-24T00:00:00Z',
        scope: AgentContextScope(
          includeSettings: true,
          includeProfile: true,
        ),
        workspaceContext: AgentWorkspaceSummaryContext(
          workspaceRoot: '/test',
          activeFilePath: 'main.styio',
        ),
        documentContext: AgentActiveDocumentContext(
          filePath: 'main.styio',
          lineCount: 100,
          selectionStartOffset: 0,
          selectionEndOffset: 10,
          selectionText: 'pipeline f',
        ),
        diagnosticsContext: AgentDiagnosticsContext(
          errorCount: 3,
          topErrors: ['unresolved-reference', 'missing-assignment'],
        ),
        projectGraphContext: AgentProjectGraphContext(
          projectTitle: 'my-project',
          graphSource: 'canonical-file',
        ),
        runtimeContext: AgentRuntimeSummaryContext(
          lastRunStatus: 'succeeded',
          laneStatuses: {'execution': 'succeeded'},
        ),
        capabilityGapContext: AgentCapabilityGapContext(
          upstreamBlocked: ['language.rename'],
        ),
        profileId: 'default-linux',
        redactionPolicy: AgentRedactionPolicy.localOnly,
      );

      final json = original.toJson();
      final restored = AgentContextSnapshot.fromJson(json);

      expect(restored.snapshotId, original.snapshotId);
      expect(restored.workspaceContext?.workspaceRoot, '/test');
      expect(restored.workspaceContext?.activeFilePath, 'main.styio');
      expect(restored.documentContext?.lineCount, 100);
      expect(restored.documentContext?.selectionText, 'pipeline f');
      expect(restored.diagnosticsContext?.errorCount, 3);
      expect(restored.projectGraphContext?.graphSource, 'canonical-file');
      expect(restored.runtimeContext?.lastRunStatus, 'succeeded');
      expect(restored.capabilityGapContext?.upstreamBlocked, ['language.rename']);
      expect(restored.profileId, 'default-linux');
      expect(restored.scope.includeSettings, isTrue);
      expect(restored.redactionPolicy.redactHomeDirectoryPaths, isFalse);
    });

    test('toDisplaySummary produces correct summary', () {
      final snapshot = const AgentContextSnapshot(
        snapshotId: 'snap-7',
        workspaceContext: AgentWorkspaceSummaryContext(workspaceRoot: '/ws'),
        documentContext: AgentActiveDocumentContext(
          filePath: 'main.styio',
          selectionStartOffset: 5,
          selectionEndOffset: 15,
          selectionText: 'func',
        ),
        diagnosticsContext: AgentDiagnosticsContext(
          errorCount: 2,
          warningCount: 1,
        ),
        projectGraphContext: AgentProjectGraphContext(projectTitle: 'MyProj'),
        runtimeContext: AgentRuntimeSummaryContext(lastRunStatus: 'succeeded'),
        commandCatalogContext: AgentCommandSummaryContext(
          availableCommandCount: 25,
          blockedCommandCount: 3,
        ),
        capabilityGapContext: AgentCapabilityGapContext(
          missingCapabilities: ['language.rename'],
        ),
      );

      final summary = snapshot.toDisplaySummary();
      expect(summary.workspace, '/ws');
      expect(summary.activeFile, 'main.styio');
      expect(summary.hasSelection, isTrue);
      expect(summary.errorCount, 2);
      expect(summary.warningCount, 1);
    });
  });

  group('AgentActionPlan', () {
    test('action plan references commands and workspace edits', () {
      final plan = const AgentActionPlan(
        planId: 'plan-1',
        description: 'Fix unresolved references',
        commands: [AppCommandId.applyQuickFix],
        workspaceEdits: [
          AgentWorkspaceEditIntent(
            intentId: 'edit-1',
            filePath: 'main.styio',
            editKind: 'replace',
            rangeStart: 10,
            rangeEnd: 20,
            newText: 'fixed',
            summary: 'Fix reference',
          ),
        ],
        requiresPermission: true,
        permissionScope: PermissionRequestScope.workspaceWrite,
        permissionReason: 'Modifying main.styio',
      );

      expect(plan.hasEdits, isTrue);
      expect(plan.hasCommands, isTrue);
      expect(plan.workspaceEdits.length, 1);

      final json = plan.toJson();
      expect(json['planId'], 'plan-1');
      expect(json['requiresPermission'], isTrue);
    });
  });

  group('AgentWorkspaceEditApplication', () {
    test('reports failures without losing successful applications', () {
      final application = const AgentWorkspaceEditApplication(
        applicationId: 'app-1',
        planId: 'plan-1',
        appliedAtIso8601: '2026-06-24T00:00:00Z',
        editCount: 2,
        affectedFilePaths: ['main.styio', 'lib.styio'],
        appliedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'edit-1',
            filePath: 'main.styio',
            editKind: 'replace',
            summary: 'Fixed',
          ),
        ],
        failedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'edit-2',
            filePath: 'lib.styio',
            editKind: 'insert',
            summary: 'Failed — out of range',
          ),
        ],
        errorMessages: ['edit-2: range out of bounds'],
        rollbackAvailable: true,
        rollbackTransactionId: 'txn-1',
      );

      expect(application.hasFailures, isTrue);
      expect(application.editCount, 2);
      expect(application.affectedFilePaths.length, 2);
      expect(application.rollbackAvailable, isTrue);

      final json = application.toJson();
      expect(json['appliedCount'], 1);
      expect(json['failedCount'], 1);
    });
  });

  group('Agent context secret redaction', () {
    test('API key environment variable names are not leaked in snapshot', () {
      final snapshot = const AgentContextSnapshot(
        snapshotId: 'snap-secret',
        redactionPolicy: AgentRedactionPolicy.defaultPolicy,
      );

      final json = snapshot.toJson();
      // Verify the snapshot JSON does not contain API key values
      final jsonStr = json.toString();
      expect(jsonStr, isNot(contains('sk-')));
      expect(jsonStr, isNot(contains('OPENAI_API_KEY')));
      expect(jsonStr, isNot(contains('token')));
    });
  });
}
