import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
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
    expect(find.text('error 1'), findsOneWidget);
    expect(find.text('warning 1'), findsOneWidget);
    expect(find.text('Unexpected token.'), findsOneWidget);
    expect(find.text('Unused value.'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('problems-diagnostic-syntax-error')),
    );
    await tester.pump();

    expect(selectedDiagnostic?.code, 'syntax-error');
  });

  testWidgets('problems surface renders workspace diagnostics snapshot', (
    tester,
  ) async {
    WorkspaceDiagnostic? selectedWorkspaceDiagnostic;
    var refreshCount = 0;
    var previewCount = 0;
    var applyCount = 0;

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
                ),
              ],
            ),
            workspaceEditPreview: const WorkspaceEditPreview(
              planId: 'workspace-fix-1',
              summary: 'Remove duplicate imports across workspace',
              source: WorkspaceEditSource.codeAction,
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
            onRefreshWorkspaceDiagnostics: () async {
              refreshCount += 1;
            },
            onPreviewWorkspaceQuickFix: () async {
              previewCount += 1;
            },
            onApplyWorkspaceQuickFix: () async {
              applyCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.text('workspace-documents 2'), findsOneWidget);
    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('error 1'), findsOneWidget);
    expect(find.text('hint 1'), findsOneWidget);
    expect(find.text('Prefer explicit name.'), findsOneWidget);
    expect(find.textContaining('src/lib.styio · hint · style'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('problems-workspace-edit-preview')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Remove duplicate imports across workspace'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('problems-diagnostic-style')));
    await tester.pump();

    expect(selectedWorkspaceDiagnostic?.documentId, 'src/lib.styio');

    await tester.tap(
      find.byKey(const ValueKey('problems-refresh-workspace')),
    );
    await tester.pump();

    expect(refreshCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('problems-preview-workspace-quick-fix')),
    );
    await tester.pump();

    expect(previewCount, 1);

    await tester.tap(
      find.byKey(const ValueKey('problems-apply-workspace-quick-fix')),
    );
    await tester.pump();

    expect(applyCount, 1);
  });
}
