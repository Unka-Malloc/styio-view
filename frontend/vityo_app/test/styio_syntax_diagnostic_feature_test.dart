import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_syntax_diagnostic_feature.dart';
import 'package:vityo_app/src/view_ide/language/syntax/styio_syntax_highlighter.dart';

void main() {
  test('reports local delimiter diagnostics from false fixture', () {
    final source = File(
      'test/fixtures/language_service/unclosed_delimiter.false.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://unclosed_delimiter',
      text: source,
      revision: 1,
    );
    final tokens = const StyioSyntaxHighlighter().tokenize(source);

    final diagnostics = const StyioSyntaxDiagnosticFeature().diagnosticsFor(
      document: document,
      tokens: tokens,
    );

    expect(
      diagnostics.map((diagnostic) => diagnostic.code),
      contains('local.unclosed-delimiter'),
    );
  });

  test('builds quick fix for unclosed delimiter diagnostic', () {
    final source = File(
      'test/fixtures/language_service/unclosed_delimiter.false.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://unclosed_delimiter',
      text: source,
      revision: 1,
    );
    final feature = const StyioSyntaxDiagnosticFeature();
    final tokens = const StyioSyntaxHighlighter().tokenize(source);
    final diagnostic = feature
        .diagnosticsFor(document: document, tokens: tokens)
        .singleWhere(
          (diagnostic) => diagnostic.code == 'local.unclosed-delimiter',
        );

    final fixes = feature.quickFixesForDiagnostic(
      document: document,
      diagnostic: diagnostic,
    );

    expect(fixes.single.label, startsWith('Insert matching'));
    expect(fixes.single.edits.single.range.start, document.length);
    expect(fixes.single.edits.single.newText, isNotEmpty);
  });
}
