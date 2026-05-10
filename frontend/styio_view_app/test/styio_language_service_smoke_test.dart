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
    final symbols = {
      for (final symbol in analysis.documentSymbols) symbol.name: symbol.kind,
    };

    expect(lexemes, containsAll(['@', ':=', '..', '>>', '#', '||>', '?|']));
    expect(analysis.diagnostics, isEmpty);
    expect(symbols['ma5'], SymbolKind.resource);
    expect(symbols['job'], SymbolKind.variable);
    expect(symbols['answer'], SymbolKind.variable);
    expect(symbols['p'], SymbolKind.parameter);
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

    final answerDefinition = service.definitionAt(
      document,
      document.text.lastIndexOf('answer'),
    );
    expect(answerDefinition?.symbol.name, 'answer');
    expect(answerDefinition?.symbol.kind, SymbolKind.variable);

    final resourceReferences = service.referencesAt(
      document,
      document.text.lastIndexOf('ma5'),
    );
    expect(resourceReferences.length, 2);

    final renamePlan = service.renameAt(
      document,
      document.text.lastIndexOf('ma5'),
      'movingAverage',
    );
    expect(renamePlan?.edits.length, 2);
    expect(renamePlan?.target.kind, SymbolKind.resource);
  });

  test('returns parameter info for current-file function calls', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'parameter-info.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
''',
      revision: 0,
    );

    final info = service.parameterInfoAt(
      document,
      document.text.indexOf('tax') + 1,
    );

    expect(info?.callableName, 'blend');
    expect(info?.signature, 'fn blend(left: f64, right: f64)');
    expect(info?.activeParameterIndex, 1);
    expect(info?.activeParameter?.name, 'right');
  });

  test('reports unresolved identifiers from the local symbol index', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unresolved.styio',
      text: '''
@import { styio/core }
known = 1
known -> @stdout
missingPrice -> @stdout
''',
      revision: 0,
    );

    final analysis = service.analyzeDocument(document);
    final unresolved = analysis.diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'unresolved-reference',
    );

    expect(
      document.text.substring(unresolved.range.start, unresolved.range.end),
      'missingPrice',
    );
  });

  test('offers create-from-usage quick fixes for unresolved locals', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unresolved-local.styio',
      text: 'fn main() {\n  emit stream\n}\n',
      revision: 0,
    );

    final unresolved = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'unresolved-reference');
    final fixes = service.quickFixesForDiagnostic(document, unresolved);

    expect(fixes.map((fix) => fix.label), ['Create local binding `stream`']);
    expect(fixes.single.detail, contains('local Styio binding'));
    expect(fixes.single.edits.single.newText, '  stream = value\n');
    expect(
      fixes.single.edits.single.range.start,
      document.text.indexOf('  emit'),
    );
  });

  test('offers create function quick fix from unresolved calls', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unresolved-call.styio',
      text: '''
@import { styio/core }
price = 1
tax = 2
total = calculate(price, tax)
''',
      revision: 0,
    );

    final unresolved = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'unresolved-reference');
    final fixes = service.quickFixesForDiagnostic(document, unresolved);

    expect(fixes.map((fix) => fix.label), [
      'Create function `calculate`',
      'Create local binding `calculate`',
    ]);
    expect(
      fixes.first.edits.single.newText,
      '#calculate := (price, tax) => {\n  <| value\n}\n\n',
    );
    expect(
      fixes.first.edits.single.range.start,
      document.text.indexOf('price = 1'),
    );
  });

  test(
    'reports and fixes unused local symbols from the current file index',
    () {
      const service = SimpleStyioLanguageService();
      const document = DocumentState(
        documentId: 'unused-local.styio',
        text: '''
used = 1
unused = 2
_ignored = 3
used -> @stdout
''',
        revision: 0,
      );

      final analysis = service.analyzeDocument(document);
      final unused = analysis.diagnostics.singleWhere(
        (diagnostic) => diagnostic.code == 'unused-local-symbol',
      );

      expect(
        document.text.substring(unused.range.start, unused.range.end),
        'unused = 2',
      );

      final quickFix = service.quickFixesForDiagnostic(document, unused).single;
      expect(quickFix.label, 'Remove unused declaration');
      expect(
        document.text.substring(
          quickFix.edits.single.range.start,
          quickFix.edits.single.range.end,
        ),
        'unused = 2\n',
      );
    },
  );

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

  test('offers current-file symbols as completion items', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'completion.styio',
      text: 'job = ||> { <| 42 }\njo',
      revision: 0,
    );

    final jobCompletion = service
        .completeAt(document, document.text.length)
        .singleWhere((item) => item.label == 'job');

    expect(jobCompletion.kind, CompletionItemKind.variable);
    expect(jobCompletion.insertText, 'job');
  });

  test('matches completion items by contained text and symbol initials', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'completion-matching.styio',
      text: '''
movingAverage = source |> normalize
resource_sink = movingAverage
av
''',
      revision: 0,
    );

    final containedLabels = service
        .completeAt(document, document.text.lastIndexOf('av') + 2)
        .map((item) => item.label)
        .toSet();

    expect(containedLabels, contains('movingAverage'));

    const initialsDocument = DocumentState(
      documentId: 'completion-initials.styio',
      text: '''
movingAverage = source |> normalize
resource_sink = movingAverage
rs
''',
      revision: 0,
    );

    final initialsLabels = service
        .completeAt(
          initialsDocument,
          initialsDocument.text.lastIndexOf('rs') + 2,
        )
        .map((item) => item.label)
        .toSet();

    expect(initialsLabels, contains('resource_sink'));
  });
}
