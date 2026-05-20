import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('diagnostics interaction model exposes groups and actions', () {
    const snapshot = WorkspaceDiagnosticsSnapshot(
      providerId: 'workspace',
      diagnostics: <WorkspaceDiagnostic>[
        WorkspaceDiagnostic(
          documentId: 'src/main.styio',
          source: 'styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'syntax-error',
            message: 'Unexpected token.',
            range: SourceRange(start: 0, end: 1),
          ),
        ),
        WorkspaceDiagnostic(
          documentId: 'src/main.styio',
          source: 'toolchain',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'tool-warning',
            message: 'Tool warning.',
            range: SourceRange(start: 4, end: 8),
          ),
        ),
      ],
    );
    final view = WorkspaceDiagnosticsView.fromSnapshot(snapshot);
    const readyPlan = WorkspaceQuickFixConfirmationPlan(
      planId: 'fix-syntax',
      status: WorkspaceQuickFixConfirmationStatus.ready,
      message: 'Ready.',
      summary: 'Fix syntax',
      affectedDocumentIds: <String>['src/main.styio'],
    );
    const blockedPlan = WorkspaceQuickFixConfirmationPlan(
      planId: 'fix-missing',
      status: WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments,
      message: 'Missing document.',
      missingDocumentIds: <String>['src/missing.styio'],
    );

    final model = DiagnosticsInteractionModel.fromWorkspaceView(
      view,
      quickFixConfirmationPlans: const <WorkspaceQuickFixConfirmationPlan>[
        readyPlan,
        blockedPlan,
      ],
    );
    final json = model.toJson();
    final actions = model.actions;

    expect(model.totalCount, 2);
    expect(model.visibleCount, 2);
    expect(model.hasVisibleErrors, isTrue);
    expect(model.readyQuickFixCount, 1);
    expect(model.previewableQuickFixCount, 2);
    expect(model.view.sourceGroups, hasLength(2));
    expect(
      actions.where(
        (action) =>
            action.kind == DiagnosticsInteractionActionKind.openDocument,
      ),
      hasLength(1),
    );
    expect(
      actions.where(
        (action) =>
            action.kind == DiagnosticsInteractionActionKind.filterBySource,
      ),
      hasLength(2),
    );
    expect(
      actions.where(
        (action) =>
            action.kind == DiagnosticsInteractionActionKind.applyQuickFix,
      ),
      hasLength(2),
    );
    expect(
      actions.where(
        (action) =>
            action.kind == DiagnosticsInteractionActionKind.previewQuickFix,
      ),
      hasLength(2),
    );
    expect(
      actions
          .firstWhere(
            (action) =>
                action.kind == DiagnosticsInteractionActionKind.previewQuickFix,
          )
          .commandId,
      'previewQuickFix',
    );
    expect(
      actions
          .firstWhere(
            (action) =>
                action.kind == DiagnosticsInteractionActionKind.applyQuickFix,
          )
          .commandId,
      'applyQuickFix',
    );
    expect(actions.last.enabled, isFalse);
    expect(json['readyQuickFixCount'], 1);
    expect(json['previewableQuickFixCount'], 2);
    expect(json['actions'], isNotEmpty);
    expect(json['sourceGroups'], isNotEmpty);

    const routeDiagnostic = WorkspaceDiagnostic(
      documentId: 'src/main.styio',
      diagnostic: Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'syntax-error',
        message: 'Unexpected token.',
        range: SourceRange(start: 0, end: 1),
      ),
      quickFixes: <DiagnosticQuickFix>[
        DiagnosticQuickFix(
          label: 'Insert assignment',
          edits: <FormattingEdit>[
            FormattingEdit(range: SourceRange(start: 1, end: 1), newText: '='),
          ],
        ),
      ],
    );
    final applyRoute = DiagnosticsQuickFixCommandRoute.apply(
      diagnostic: routeDiagnostic,
      quickFixIndex: 0,
    );
    final missingRoute = DiagnosticsQuickFixCommandRoute.preview(
      diagnostic: routeDiagnostic,
      quickFixIndex: 4,
    );

    expect(applyRoute.commandId, 'applyQuickFix');
    expect(applyRoute.routeId, 'applyQuickFix:src/main.styio:syntax-error:0');
    expect(applyRoute.quickFix?.label, 'Insert assignment');
    expect(applyRoute.toJson()['quickFixIndex'], 0);
    expect(missingRoute.enabled, isFalse);
    expect(missingRoute.reason, contains('not available'));
  });

  test('diagnostics panel state persists selected problem context', () async {
    final store = DiagnosticsPanelStateStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    const diagnostic = WorkspaceDiagnostic(
      documentId: 'src/main.styio',
      source: 'styio',
      diagnostic: Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'unused-value',
        message: 'Unused value.',
        range: SourceRange(start: 12, end: 18),
      ),
    );
    final state = DiagnosticsPanelState.fromDiagnostic(
      workspaceId: 'demo',
      diagnostic: diagnostic,
      filterState: const WorkspaceDiagnosticsFilterState(
        severities: <DiagnosticSeverity>[DiagnosticSeverity.warning],
        sources: <String>['styio'],
      ),
      updatedAt: DateTime.utc(2026, 5, 20),
    );

    await store.saveState(state: state);
    final restored = await store.readState(workspaceId: 'demo');

    expect(restored.hasSelection, isTrue);
    expect(restored.selectedDocumentId, 'src/main.styio');
    expect(restored.selectedDiagnosticCode, 'unused-value');
    expect(restored.selectedRangeStart, 12);
    expect(restored.selectedRangeEnd, 18);
    expect(restored.filterState.summary, 'warning · source styio');
    expect(await store.deleteState(workspaceId: 'demo'), isTrue);
    expect((await store.readState(workspaceId: 'demo')).hasSelection, isFalse);
  });

  test('quick fix telemetry store persists review outcomes', () async {
    final store = WorkspaceQuickFixTelemetryStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    const diagnostic = WorkspaceDiagnostic(
      documentId: 'src/main.styio',
      providerId: 'styio-service',
      source: 'styio',
      diagnostic: Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'missing-assignment',
        message: 'Missing assignment.',
        range: SourceRange(start: 9, end: 9),
      ),
      quickFixes: <DiagnosticQuickFix>[
        DiagnosticQuickFix(
          label: 'Insert assignment',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 9, end: 9),
              newText: ' = value',
            ),
          ],
        ),
      ],
    );
    final review = WorkspaceQuickFixReviewPlan.fromDiagnostic(
      diagnostic: diagnostic,
      documents: const <DocumentState>[
        DocumentState(
          documentId: 'src/main.styio',
          text: 'let count\n',
          revision: 1,
        ),
      ],
    );
    final outcome = WorkspaceQuickFixReviewOutcome.fromReviewPlan(
      workspaceId: 'demo',
      reviewPlan: review,
      outcomeKind: WorkspaceQuickFixReviewOutcomeKind.previewed,
      message: 'User previewed quick fix.',
      timestamp: DateTime.utc(2026, 5, 20, 13),
    );

    await store.recordOutcome(outcome: outcome);

    final restored = await store.readSnapshot(workspaceId: 'demo');

    expect(restored.outcomes.single.producerId, 'styio-service');
    expect(restored.outcomes.single.documentId, 'src/main.styio');
    expect(restored.outcomes.single.diagnosticCode, 'missing-assignment');
    expect(restored.outcomes.single.ready, isTrue);
    expect(restored.toJson()['outcomeCount'], 1);
    expect(restored.outcomes.single.toJson()['outcomeKind'], 'previewed');
    expect(await store.clearSnapshot(workspaceId: 'demo'), isTrue);
    expect((await store.readSnapshot(workspaceId: 'demo')).outcomes, isEmpty);
  });

  test(
    'diagnostics runtime output binding emits diagnostics and quick fixes',
    () {
      const diagnostic = WorkspaceDiagnostic(
        documentId: 'src/main.styio',
        providerId: 'styio-service',
        source: 'styio',
        diagnostic: Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'missing-assignment',
          message: 'Missing assignment.',
          range: SourceRange(start: 9, end: 9),
        ),
        quickFixes: <DiagnosticQuickFix>[
          DiagnosticQuickFix(
            label: 'Insert assignment',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 9, end: 9),
                newText: ' = value',
              ),
            ],
          ),
        ],
      );
      final telemetry = WorkspaceQuickFixTelemetrySnapshot(
        workspaceId: 'demo',
        outcomes: <WorkspaceQuickFixReviewOutcome>[
          WorkspaceQuickFixReviewOutcome(
            workspaceId: 'demo',
            producerId: 'styio-service',
            documentId: 'src/main.styio',
            diagnosticCode: 'missing-assignment',
            quickFixIndex: 0,
            planId: 'quick-fix.src/main.styio.missing-assignment.0',
            outcomeKind: WorkspaceQuickFixReviewOutcomeKind.applied,
            confirmationStatus: WorkspaceQuickFixConfirmationStatus.ready,
            ready: true,
            message: 'Applied quick fix.',
            timestamp: DateTime.utc(2026, 5, 20, 14),
          ),
        ],
      );
      const snapshot = WorkspaceDiagnosticsSnapshot(
        providerId: 'styio-service',
        diagnostics: <WorkspaceDiagnostic>[diagnostic],
        message: 'Styio diagnostics updated.',
      );

      final binding = WorkspaceDiagnosticsRuntimeOutputBinding(
        snapshot: snapshot,
        quickFixTelemetry: telemetry,
      );
      final outputSnapshot = binding.outputPanelSnapshot(
        timestamp: DateTime.utc(2026, 5, 20, 14),
        channelId: 'diagnostics.styio-service',
      );

      expect(outputSnapshot.events, hasLength(3));
      expect(outputSnapshot.events[0].message, 'Styio diagnostics updated.');
      expect(outputSnapshot.events[0].metadata['quickFixReadyCount'], 1);
      expect(
        outputSnapshot.events[1].kind,
        RuntimeOutputChannelKind.languageService,
      );
      expect(
        outputSnapshot.events[1].message,
        'error src/main.styio: Missing assignment.',
      );
      expect(outputSnapshot.events[1].metadata['quickFixCount'], 1);
      expect(
        outputSnapshot.events[2].kind,
        RuntimeOutputChannelKind.runtimeEvents,
      );
      expect(outputSnapshot.events[2].metadata['outcomeKind'], 'applied');
      expect(binding.toJson()['outputEventCount'], 3);
    },
  );
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_diagnostics_panel_state_test_',
  );
  addTearDown(() => tempRoot.delete(recursive: true));
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}
