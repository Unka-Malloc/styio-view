import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/controller/editor_controller.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/simple_styio_language_service.dart';

void main() {
  test('selection diagnostics include collapsed external diagnostics', () {
    const text = 'let value = 1\n';
    final offset = text.indexOf('value');
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'range-index.styio',
        text: text,
        revision: 3,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(offset),
    );

    controller.applyExternalDiagnostics(
      <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'collapsed',
          message: 'Collapsed diagnostic.',
          range: SourceRange(start: offset, end: offset),
        ),
      ],
    );

    expect(
      controller.diagnosticsAtSelection.map((diagnostic) => diagnostic.code),
      contains('collapsed'),
    );
  });
}
