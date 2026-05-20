import 'package:flutter_test/flutter_test.dart';
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
}
