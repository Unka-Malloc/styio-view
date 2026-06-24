import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/problems/problems.dart';

void main() {
  testWidgets('problems surface renders diagnostics and selects entries', (
    tester,
  ) async {
    Diagnostic? selectedDiagnostic;
    const diagnostics = <Diagnostic>[
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'syntax-error',
        message: 'Unexpected token.',
        range: SourceRange(start: 0, end: 5),
      ),
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'unused-value',
        message: 'Unused value.',
        range: SourceRange(start: 6, end: 11),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: diagnostics,
            onSelectDiagnostic: (diagnostic) {
              selectedDiagnostic = diagnostic;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('problems-surface')), findsOneWidget);
    expect(find.text('Problems'), findsOneWidget);
    expect(find.text('document src/main.styio'), findsOneWidget);
    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('visible 2'), findsOneWidget);
    expect(find.text('groups 1'), findsOneWidget);
    expect(find.text('selected syntax-error'), findsOneWidget);
    expect(find.text('error 1'), findsOneWidget);
    expect(find.text('warning 1'), findsOneWidget);
    expect(find.text('Unexpected token.'), findsOneWidget);
    expect(find.text('Unused value.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('problems-diagnostic-syntax-error')),
    );
    await tester.pump();

    expect(selectedDiagnostic?.code, 'syntax-error');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('selected unused-value'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selectedDiagnostic?.code, 'unused-value');
  });

  testWidgets('problems surface renders workspace diagnostics snapshot', (
    tester,
  ) async {
    WorkspaceDiagnostic? selectedWorkspaceDiagnostic;
    DiagnosticsPanelState? changedPanelState;
    var refreshCount = 0;
    var previewCount = 0;
    var applyCount = 0;
    var workspaceEditApplyCount = 0;
    var workspaceEditCancelCount = 0;
    DiagnosticsQuickFixCommandRoute? previewFixRoute;
    DiagnosticsQuickFixCommandRoute? applyFixRoute;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            workspaceDiagnostics: const WorkspaceDiagnosticsSnapshot(
              providerId: 'workspace',
              diagnostics: <WorkspaceDiagnostic>[
                WorkspaceDiagnostic(
                  documentId: 'src/main.styio',
                  diagnostic: Diagnostic(
                    severity: DiagnosticSeverity.error,
                    code: 'syntax-error',
                    message: 'Unexpected token.',
                    range: SourceRange(start: 0, end: 5),
                  ),
                ),
                WorkspaceDiagnostic(
                  documentId: 'src/lib.styio',
                  diagnostic: Diagnostic(
                    severity: DiagnosticSeverity.hint,
                    code: 'style',
                    message: 'Prefer explicit name.',
                    range: SourceRange(start: 1, end: 4),
                  ),
                  quickFixes: <DiagnosticQuickFix>[
                    DiagnosticQuickFix(
                      label: 'Use explicit name',
                      edits: <FormattingEdit>[
                        FormattingEdit(
                          range: SourceRange(start: 1, end: 4),
                          newText: 'value',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            workspaceEditPreview: const WorkspaceEditPreview(
              planId: 'workspace-fix-1',
              summary: 'Remove duplicate imports across workspace',
              source: WorkspaceEditSource.codeAction,
              missingDocumentIds: <String>['src/missing.styio'],
              documents: <WorkspaceEditDocumentPreview>[
                WorkspaceEditDocumentPreview(
                  documentId: 'src/lib.styio',
                  revision: 3,
                  beforeText: '@import a\n@import a\n',
                  afterText: '@import a\n',
                  edits: <FormattingEdit>[
                    FormattingEdit(
                      range: SourceRange(start: 10, end: 20),
                      newText: '',
                    ),
                  ],
                ),
              ],
            ),
            onSelectWorkspaceDiagnostic: (diagnostic) {
              selectedWorkspaceDiagnostic = diagnostic;
            },
            diagnosticsPanelState: const DiagnosticsPanelState(
              workspaceId: 'demo',
              selectedDocumentId: 'src/lib.styio',
              selectedDiagnosticCode: 'style',
              selectedRangeStart: 1,
              selectedRangeEnd: 4,
            ),
            onDiagnosticsPanelStateChanged: (state) {
              changedPanelState = state;
            },
            onRefreshWorkspaceDiagnostics: () async {
              refreshCount += 1;
            },
            onPreviewWorkspaceQuickFix: () async {
              previewCount += 1;
            },
            onApplyWorkspaceQuickFix: () async {
              applyCount += 1;
            },
            onPreviewDiagnosticQuickFix: (route) async {
              previewFixRoute = route;
            },
            onApplyDiagnosticQuickFix: (route) async {
              applyFixRoute = route;
            },
            onApplyWorkspaceEdit: (controls) async {
              workspaceEditApplyCount += 1;
            },
            onCancelWorkspaceEdit: (controls) async {
              workspaceEditCancelCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.text('workspace-documents 2'), findsOneWidget);
    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('visible 2'), findsOneWidget);
    expect(find.text('groups 2'), findsOneWidget);
    expect(find.text('restored style'), findsOneWidget);
    expect(find.text('error 1'), findsOneWidget);
    expect(find.text('hint 1'), findsOneWidget);
    expect(find.text('Prefer explicit name.'), findsOneWidget);
    expect(find.textContaining('src/lib.styio · hint · style'), findsOneWidget);
    expect(find.text('fixes 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('problems-workspace-edit-preview')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Remove duplicate imports across workspace'),
      findsOneWidget,
    );
    expect(
      find.text('Preview blocked until missing documents are loaded.'),
      findsOneWidget,
    );
    expect(find.textContaining('blocked-missing-documents'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('problems-workspace-edit-apply')),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('problems-workspace-edit-cancel')),
      findsOneWidget,
    );
    expect(find.text('Before: @import a / @import a'), findsOneWidget);
    expect(find.text('After: @import a'), findsOneWidget);
    expect(find.textContaining('src/missing.styio'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('problems-diagnostic-style')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('problems-diagnostic-style')));
    await tester.pump();

    expect(selectedWorkspaceDiagnostic?.documentId, 'src/lib.styio');
    expect(changedPanelState?.selectedDiagnosticCode, 'style');
    expect(changedPanelState?.workspaceId, 'demo');
    expect(find.text('selected-fixes 1'), findsOneWidget);
    expect(find.text('Quick Fixes: style'), findsOneWidget);
    expect(find.text('Use explicit name · edits 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('problems-preview-fix-style-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('problems-apply-fix-style-0')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('problems-preview-fix-style-0')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('problems-apply-fix-style-0')));
    await tester.pump();

    expect(previewFixRoute?.commandId, 'previewQuickFix');
    expect(previewFixRoute?.quickFixIndex, 0);
    expect(previewFixRoute?.diagnostic.documentId, 'src/lib.styio');
    expect(applyFixRoute?.commandId, 'applyQuickFix');
    expect(applyFixRoute?.routeId, 'applyQuickFix:src/lib.styio:style:0');

    await tester.ensureVisible(
      find.byKey(const ValueKey('problems-refresh-workspace')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('problems-refresh-workspace')));
    await tester.pump();

    expect(refreshCount, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('problems-preview-workspace-quick-fix')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('problems-preview-workspace-quick-fix')),
    );
    await tester.pump();

    expect(previewCount, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('problems-apply-workspace-quick-fix')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('problems-apply-workspace-quick-fix')),
    );
    await tester.pump();

    expect(applyCount, 1);

    await tester.ensureVisible(
      find.byKey(const ValueKey('problems-workspace-edit-cancel')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('problems-workspace-edit-cancel')),
    );
    await tester.pump();

    expect(workspaceEditApplyCount, 0);
    expect(workspaceEditCancelCount, 1);
  });

  testWidgets('problems surface renders diagnostics producer lifecycle', (
    tester,
  ) async {
    final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
      providerId: 'styio-project-diagnostics',
      request: const WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio', 'src/lib.styio'],
        activeDocumentId: 'src/main.styio',
      ),
      command: 'styio',
      arguments: const <String>['check', '.'],
      workingDirectory: '/workspace/vityo',
    );
    final controller = WorkspaceDiagnosticsProducerLifecycleController();
    controller.start(plan, message: 'Styio diagnostics started.');
    final lifecycle = controller.reportProgress(
      plan,
      progress: 0.25,
      message: 'Scanned 1 of 4 documents.',
    );
    WorkspaceDiagnosticsProducerLifecycleSnapshot? canceledSnapshot;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            diagnosticsProducerLifecycles:
                <WorkspaceDiagnosticsProducerLifecycleSnapshot>[lifecycle],
            onCancelDiagnosticsProducer: (snapshot) async {
              canceledSnapshot = snapshot;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(
        const ValueKey('problems-diagnostics-producer-lifecycle-panel'),
      ),
      findsOneWidget,
    );
    expect(find.text('Diagnostics producers'), findsOneWidget);
    expect(find.text('styio-project-diagnostics · running'), findsOneWidget);
    expect(find.text('Scanned 1 of 4 documents.'), findsOneWidget);
    expect(find.text('progress 25%'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey(
          'problems-diagnostics-producer-cancel-styio-project-diagnostics',
        ),
      ),
    );
    await tester.pump();

    expect(canceledSnapshot?.providerId, 'styio-project-diagnostics');
    expect(canceledSnapshot?.canCancel, isTrue);
  });

  testWidgets('problems surface renders semantic snapshot panel events', (
    tester,
  ) async {
    final viewModel = SemanticSnapshotPanelViewModel.fromState(
      SemanticSnapshotPanelEventState.empty(
        SemanticSnapshotPanelEventTarget.problems,
      ).record(
        SemanticSnapshotPanelEvent(
          target: SemanticSnapshotPanelEventTarget.problems,
          kind: SemanticSnapshotTelemetryEventKind.codeActionApply,
          documentId: 'src/main.styio',
          message: 'Applied quick fix.',
          payload: const <String, Object?>{
            'status': 'applied',
            'label': 'Insert assignment',
          },
          timestamp: DateTime.utc(2026, 5, 20, 15),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            semanticSnapshotPanelViewModel: viewModel,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('problems-semantic-snapshot-panel')),
      findsOneWidget,
    );
    expect(find.text('Semantic Problems'), findsOneWidget);
    expect(find.text('items 1'), findsOneWidget);
    expect(find.text('code-actions 1'), findsOneWidget);
    expect(find.text('Insert assignment'), findsOneWidget);
    expect(
      find.textContaining('src/main.styio · code-action-apply'),
      findsOneWidget,
    );
  });

  testWidgets('problems surface applies ready workspace edit review controls', (
    tester,
  ) async {
    WorkspaceEditReviewControls? appliedControls;
    WorkspaceEditReviewControls? canceledControls;
    const readyPreview = WorkspaceEditPreview(
      planId: 'ready-fix',
      summary: 'Rename symbol in workspace',
      source: WorkspaceEditSource.rename,
      documents: <WorkspaceEditDocumentPreview>[
        WorkspaceEditDocumentPreview(
          documentId: 'src/main.styio',
          revision: 7,
          beforeText: 'old',
          afterText: 'new',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 3),
              newText: 'new',
            ),
          ],
        ),
        WorkspaceEditDocumentPreview(
          documentId: 'src/lib.styio',
          revision: 2,
          beforeText: 'old lib',
          afterText: 'new lib',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 3),
              newText: 'new',
            ),
          ],
        ),
        WorkspaceEditDocumentPreview(
          documentId: 'src/hidden.styio',
          revision: 1,
          beforeText: 'old hidden',
          afterText: 'new hidden',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 3),
              newText: 'new',
            ),
          ],
        ),
      ],
      fileOperations: <WorkspaceFileOperationPreview>[
        WorkspaceFileOperationPreview(
          operation: WorkspaceFileOperation.create(
            documentId: 'src/new.styio',
            text: 'value = 1',
          ),
          status: WorkspaceFileOperationPreviewStatus.ready,
          message: 'Document src/new.styio will be created.',
          afterText: 'value = 1',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            workspaceEditPreview: readyPreview,
            workspaceEditDiffWindow: readyPreview.diffWindow(
              documentLimit: 2,
              fileOperationLimit: 1,
            ),
            onApplyWorkspaceEdit: (controls) async {
              appliedControls = controls;
            },
            onCancelWorkspaceEdit: (controls) async {
              canceledControls = controls;
            },
          ),
        ),
      ),
    );

    expect(
      find.textContaining('ready · Workspace edit preview is ready'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('problems-workspace-edit-diff-window')),
      findsOneWidget,
    );
    expect(find.textContaining('documents 0+2/3'), findsOneWidget);
    expect(find.text('+1 more document(s)'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('problems-workspace-edit-file-operation-src/new.styio'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('problems-workspace-edit-apply')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('problems-workspace-edit-cancel')),
    );
    await tester.pump();

    expect(appliedControls?.confirmationPlan.planId, 'ready-fix');
    expect(appliedControls?.canApply, isTrue);
    expect(canceledControls?.confirmationPlan.planId, 'ready-fix');
  });

  testWidgets('problems surface renders workspace edit apply result', (
    tester,
  ) async {
    const preview = WorkspaceEditPreview(
      planId: 'applied-fix',
      summary: 'Apply project fix',
      source: WorkspaceEditSource.codeAction,
      documents: <WorkspaceEditDocumentPreview>[
        WorkspaceEditDocumentPreview(
          documentId: 'src/main.styio',
          revision: 1,
          beforeText: 'old',
          afterText: 'new',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 3),
              newText: 'new',
            ),
          ],
        ),
      ],
    );
    final confirmation = WorkspaceEditConfirmationPlan.fromPreview(preview);
    final result = WorkspaceEditApplyResultViewModel.fromTelemetry(
      confirmationPlan: confirmation,
      telemetry: WorkspaceEditReviewResultTelemetry.fromApplicationResult(
        confirmationPlan: confirmation,
        result: const WorkspaceEditApplicationResult(
          applied: true,
          message: 'Applied project fix.',
          appliedEditCount: 1,
          appliedDocumentIds: <String>['src/main.styio'],
        ),
        recordedAt: DateTime.utc(2026, 5, 20),
      ),
      diffWindow: preview.diffWindow(),
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
          message: 'Applied assignment fix.',
          affectedDocumentIds: <String>['src/main.styio'],
          timestamp: DateTime.utc(2026, 5, 20),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            workspaceEditApplyResult: result,
            quickFixTelemetry: telemetry,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('problems-workspace-edit-apply-result')),
      findsOneWidget,
    );
    expect(find.text('Workspace edit applied'), findsOneWidget);
    expect(find.textContaining('applied · code-action'), findsOneWidget);
    expect(find.textContaining('1 affected document'), findsOneWidget);
    expect(find.text('Applied project fix.'), findsOneWidget);
    expect(find.text('applied src/main.styio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('problems-quick-fix-telemetry')),
      findsOneWidget,
    );
    expect(find.text('Quick-fix outcomes'), findsOneWidget);
    expect(find.text('applied missing-assignment #0'), findsOneWidget);
    expect(find.textContaining('Applied assignment fix.'), findsOneWidget);
  });

  testWidgets('problems surface binds quick-fix review diff apply controls', (
    tester,
  ) async {
    WorkspaceQuickFixReviewPlan? appliedPlan;
    WorkspaceQuickFixReviewPlan? canceledPlan;
    const diagnostic = WorkspaceDiagnostic(
      documentId: 'src/main.styio',
      diagnostic: Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'missing-assignment',
        message: 'Missing assignment.',
        range: SourceRange(start: 0, end: 9),
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
    final reviewPlan = WorkspaceQuickFixReviewPlan.fromDiagnostic(
      diagnostic: diagnostic,
      documents: const <DocumentState>[
        DocumentState(
          documentId: 'src/main.styio',
          text: 'let count\n',
          revision: 3,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            quickFixReviewPlan: reviewPlan,
            onApplyQuickFixReviewPlan: (plan) async {
              appliedPlan = plan;
            },
            onCancelQuickFixReviewPlan: (plan) async {
              canceledPlan = plan;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('problems-quick-fix-review')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('problems-quick-fix-review-preview')),
      findsOneWidget,
    );
    expect(find.text('Quick-fix diff preview'), findsOneWidget);
    expect(find.text('Before: let count'), findsOneWidget);
    expect(find.text('After: let count = value'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('problems-quick-fix-review-apply')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('problems-quick-fix-review-cancel')),
    );
    await tester.pump();

    expect(appliedPlan?.diagnostic.diagnostic.code, 'missing-assignment');
    expect(appliedPlan?.ready, isTrue);
    expect(canceledPlan?.quickFixIndex, 0);
  });

  testWidgets('problems surface filters workspace diagnostics by severity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProblemsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            documentId: 'src/main.styio',
            diagnostics: const <Diagnostic>[],
            severityFilter: const <DiagnosticSeverity>[
              DiagnosticSeverity.error,
            ],
            workspaceDiagnostics: const WorkspaceDiagnosticsSnapshot(
              providerId: 'workspace',
              diagnostics: <WorkspaceDiagnostic>[
                WorkspaceDiagnostic(
                  documentId: 'src/main.styio',
                  diagnostic: Diagnostic(
                    severity: DiagnosticSeverity.error,
                    code: 'syntax-error',
                    message: 'Unexpected token.',
                    range: SourceRange(start: 0, end: 5),
                  ),
                ),
                WorkspaceDiagnostic(
                  documentId: 'src/lib.styio',
                  diagnostic: Diagnostic(
                    severity: DiagnosticSeverity.warning,
                    code: 'unused-value',
                    message: 'Unused value.',
                    range: SourceRange(start: 6, end: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('visible 1'), findsOneWidget);
    expect(find.text('groups 1'), findsOneWidget);
    expect(find.text('filter error'), findsOneWidget);
    expect(find.text('Unexpected token.'), findsOneWidget);
    expect(find.text('Unused value.'), findsNothing);
  });
}
