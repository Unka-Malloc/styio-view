import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('native tool result maps diagnostics into workspace snapshot', () {
    final completedAt = DateTime.utc(2026, 5, 20, 12);
    final record = NativeToolResultRecord(
      command: AppCommandId.runStaticAnalysis,
      label: 'Static Analysis',
      applied: false,
      message: 'clang-tidy produced diagnostics.',
      metadata: const <String, Object?>{
        'documentId': 'src/main.styio',
        'staticAnalysisResult': <String, Object?>{
          'status': 'failed',
          'diagnosticCount': 1,
        },
      },
      diagnostics: const <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'native-unused',
          message: 'Native tool reported an unused value.',
          range: SourceRange(start: 8, end: 12),
        ),
      ],
      completedAt: completedAt,
    );

    final snapshot = record.toWorkspaceDiagnosticsSnapshot();
    final streamSnapshot = snapshot.streamSnapshot;

    expect(snapshot.providerId, 'native-tool.runStaticAnalysis');
    expect(snapshot.message, 'clang-tidy produced diagnostics.');
    expect(snapshot.diagnostics.single.documentId, 'src/main.styio');
    expect(snapshot.diagnostics.single.source, 'native-tool');
    expect(snapshot.diagnostics.single.providerId, snapshot.providerId);
    expect(snapshot.severityCounts['warning'], 1);
    expect(streamSnapshot.sourceKindCounts['native-tool'], 1);
    expect(
      streamSnapshot.entries.single.sourceKind,
      WorkspaceDiagnosticStreamSourceKind.nativeTool,
    );
  });
}
