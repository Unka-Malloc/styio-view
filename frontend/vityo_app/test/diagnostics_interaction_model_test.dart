import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
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
    expect(actions.last.enabled, isFalse);
    expect(json['readyQuickFixCount'], 1);
    expect(json['actions'], isNotEmpty);
    expect(json['sourceGroups'], isNotEmpty);
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
