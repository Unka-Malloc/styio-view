import 'package:flutter_test/flutter_test.dart';
import 'package:styio_view_app/src/editor/document_state.dart';
import 'package:styio_view_app/src/language/language_contract.dart';
import 'package:styio_view_app/src/language/simple_styio_language_service.dart';

void main() {
  test('analyzes token, semantic, diagnostic, and formatting layers', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'sample.styio',
      text: 'fn main() {\n  let stream = source |> normalize -> sink\n',
      revision: 0,
    );

    final analysis = service.analyzeDocument(document);

    expect(analysis.tokenSpans.any((span) => span.lexeme == 'fn'), isTrue);
    expect(analysis.semanticSpans.isNotEmpty, isTrue);
    expect(analysis.diagnostics.isNotEmpty, isTrue);
    expect(analysis.formattingEdits, isEmpty);
  });

  test('returns diagnostic quick fixes for core linter findings', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'sample.styio',
      text: 'fn main() {\n  let stream\n',
      revision: 0,
    );

    final analysis = service.analyzeDocument(document);
    final missingAssignment = analysis.diagnostics.singleWhere(
      (item) => item.code == 'missing-assignment',
    );
    final unclosedBlock = analysis.diagnostics.singleWhere(
      (item) => item.code == 'unclosed-block',
    );

    final assignmentFixes = service.quickFixesForDiagnostic(
      document,
      missingAssignment,
    );
    final blockFixes = service.quickFixesForDiagnostic(document, unclosedBlock);

    expect(assignmentFixes.single.label, 'Insert assignment');
    expect(assignmentFixes.single.edits.single.newText, ' = value');
    expect(blockFixes.single.label, 'Append closing brace');
  });

  test('recognizes current styio target syntax before compiler handoff', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'topology_v2.styio',
      text: '''
@import { styio/core }
@ma5 : f64|..2| := {
  @file("prices.txt") >> #(p) => {
    p[avg, 5] -> @ma5
  }
}
job = ||> { <| 42 }
?| job -> answer: i64 | 0
answer -> @stdout
''',
      revision: 0,
    );

    final analysis = service.analyzeDocument(document);
    final lexemes = analysis.tokenSpans.map((span) => span.lexeme).toSet();
    String semanticText(SemanticSpan span) =>
        document.text.substring(span.range.start, span.range.end);

    expect(lexemes, containsAll(['@', ':=', '..', '>>', '#', '||>', '?|']));
    expect(analysis.diagnostics, isEmpty);
    expect(
      analysis.semanticSpans
          .where((span) => span.kind == SemanticKind.resource)
          .map(semanticText),
      containsAll(['ma5', 'file', 'stdout']),
    );
    expect(
      analysis.semanticSpans
          .where((span) => span.kind == SemanticKind.typeName)
          .map(semanticText),
      containsAll(['f64', 'i64']),
    );

    final taskHover = service.hoverAt(document, document.text.indexOf('||>'));
    expect(taskHover?.markdown, contains('task'));
  });

  test('offers resource and task completions for target syntax', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'sample.styio',
      text: '@',
      revision: 0,
    );

    final labels = service
        .completeAt(document, 0)
        .map((item) => item.label)
        .toSet();

    expect(labels, containsAll(['@import', '@resource', '@stdout', '@stdin']));
  });
}
