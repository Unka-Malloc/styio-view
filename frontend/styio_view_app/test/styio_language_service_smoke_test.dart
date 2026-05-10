import 'package:flutter_test/flutter_test.dart';
import 'package:styio_view_app/src/editor/document_state.dart';
import 'package:styio_view_app/src/language/language_contract.dart';
import 'package:styio_view_app/src/language/simple_styio_language_service.dart';

void main() {
  String applyEdits(String text, Iterable<FormattingEdit> edits) {
    var nextText = text;
    final editsDescending = edits.toList(growable: false)
      ..sort((left, right) => right.range.start.compareTo(left.range.start));
    for (final edit in editsDescending) {
      nextText = nextText.replaceRange(
        edit.range.start,
        edit.range.end,
        edit.newText,
      );
    }
    return nextText;
  }

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
/// Blends price and tax inputs.
/// @param left Base price before tax.
/// @param right Tax component to add.
fn blend(left: f64, right: f64 = 0.0) {
  emit left
}
value = blend(price, tax)
''',
      revision: 0,
    );

    final info = service.parameterInfoAt(
      document,
      document.text.lastIndexOf('tax') + 1,
    );

    expect(info?.callableName, 'blend');
    expect(info?.signature, 'fn blend(left: f64, right: f64 = 0.0)');
    expect(info?.documentation, 'Blends price and tax inputs.');
    expect(info?.activeParameterIndex, 1);
    expect(info?.activeParameter?.name, 'right');
    expect(info?.activeParameter?.defaultValue, '0.0');
    expect(info?.activeParameter?.documentation, 'Tax component to add.');
  });

  test('does not require defaulted call arguments', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'default-arguments.styio',
      text: '''
fn blend(left: f64, right: f64 = 0.0) {
  emit left + right
}
price = 1.0
value = blend(price)
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final info = service.parameterInfoAt(
      document,
      document.text.lastIndexOf('price)') + 1,
    );

    expect(
      diagnostics.where(
        (diagnostic) => diagnostic.code == 'missing-call-argument',
      ),
      isEmpty,
    );
    expect(info?.signature, 'fn blend(left: f64, right: f64 = 0.0)');
    expect(info?.parameters.last.displayText, 'right: f64 = 0.0');
  });

  test('maps named call arguments for parameter info and quick fixes', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'named-arguments.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
value = blend(right: tax, left: price)
missing = blend(right: tax)
''',
      revision: 0,
    );

    final info = service.parameterInfoAt(
      document,
      document.text.indexOf('right: tax') + 'right: tax'.length,
    );
    final analysis = service.analyzeDocument(document);
    final missing = analysis.diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'missing-call-argument',
    );
    final quickFix = service.quickFixesForDiagnostic(document, missing).single;

    expect(info?.activeParameterIndex, 1);
    expect(info?.activeParameter?.name, 'right');
    expect(
      service
          .inlayHints(document)
          .where((hint) => hint.kind == InlayHintKind.parameter),
      isEmpty,
    );
    expect(missing.message, contains('left'));
    expect(quickFix.edits.single.newText, 'right: tax, left: value');
  });

  test('attaches block documentation comments to function assistance', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'kdoc-style-docs.styio',
      text: '''
/**
 * Blends price and tax inputs.
 *
 * @param[left] Base price before tax.
 * @param right Tax component to add.
 */
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
''',
      revision: 0,
    );

    final analysis = service.analyzeDocument(document);
    final symbol = analysis.documentSymbols.singleWhere(
      (item) => item.name == 'blend',
    );
    final hover = service.hoverAt(document, document.text.lastIndexOf('blend'));
    final info = service.parameterInfoAt(
      document,
      document.text.lastIndexOf('tax') + 1,
    );
    final completion = service
        .completeAt(document, document.text.lastIndexOf('blend') + 2)
        .singleWhere((item) => item.label == 'blend');

    expect(symbol.documentation, contains('Blends price and tax inputs.'));
    expect(hover?.markdown, contains('Blends price and tax inputs.'));
    expect(info?.documentation, 'Blends price and tax inputs.');
    expect(info?.activeParameter?.documentation, 'Tax component to add.');
    expect(completion.documentation, contains('Blends price and tax inputs.'));
  });

  test('returns symbol-aware hover documentation for current-file symbols', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'symbol-hover.styio',
      text: 'value = value\nvalue -> @stdout\n',
      revision: 0,
    );

    final hover = service.hoverAt(
      document,
      document.text.indexOf('= value') + 3,
    );

    expect(hover?.markdown, contains('Styio variable `value`'));
    expect(hover?.markdown, contains('Styio value binding'));
    expect(hover?.markdown, contains('Declared at 1:1'));
    expect(hover?.markdown, contains('3 current-file usages'));
  });

  test('attaches leading doc comments to symbol quick documentation', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'doc-comment-hover.styio',
      text: '''
/// Normalizes prices before sink writes.
/// Keeps source units unchanged.
fn normalize(price: f64) {
  emit price
}
value = normalize(total)
''',
      revision: 0,
    );

    final symbol = service
        .analyzeDocument(document)
        .documentSymbols
        .singleWhere((item) => item.name == 'normalize');
    final hover = service.hoverAt(
      document,
      document.text.lastIndexOf('normalize'),
    );

    expect(
      symbol.documentation,
      'Normalizes prices before sink writes.\nKeeps source units unchanged.',
    );
    expect(hover?.markdown, contains('Normalizes prices before sink writes.'));
    expect(hover?.markdown, contains('Keeps source units unchanged.'));
  });

  test('returns parameter name inlay hints for current-file calls', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'parameter-inlays.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
same = blend(left, right)
''',
      revision: 0,
    );

    final hints = service.inlayHints(document);

    expect(hints.map((hint) => hint.label), ['left:', 'right:']);
    expect(hints.map((hint) => hint.kind).toSet(), {InlayHintKind.parameter});
    expect(hints.first.position, document.text.indexOf('price'));
    expect(hints.last.position, document.text.indexOf('tax'));
    expect(service.analyzeDocument(document).inlayHintCount, 2);
  });

  test('returns inferred type inlay hints for local bindings', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'type-inlays.styio',
      text: '''
fn blend(left: f64, right: f64): f64 {
  emit left
}
price = 12.5
count = 3
enabled = true
label = "close"
value = blend(price, count)
copy = price
explicit: f64 = 1
''',
      revision: 0,
    );

    final hints = service.inlayHints(document);
    final typeHints = hints.where((hint) => hint.kind == InlayHintKind.type);

    expect(typeHints.map((hint) => hint.label), [
      ': f64',
      ': i64',
      ': bool',
      ': string',
      ': f64',
      ': f64',
    ]);
    expect(typeHints.map((hint) => hint.position), [
      document.text.indexOf('price') + 'price'.length,
      document.text.indexOf('count') + 'count'.length,
      document.text.indexOf('enabled') + 'enabled'.length,
      document.text.indexOf('label') + 'label'.length,
      document.text.indexOf('value') + 'value'.length,
      document.text.indexOf('copy') + 'copy'.length,
    ]);
    expect(
      typeHints.any(
        (hint) => hint.range.start == document.text.indexOf('explicit'),
      ),
      isFalse,
    );
  });

  test('removes unused parameters through change signature', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'change-signature-remove-parameter.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
again = blend(total, fee)
''',
      revision: 0,
    );

    final plan = service.changeSignatureAt(
      document,
      document.text.indexOf('blend') + 1,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
      ],
    );

    expect(plan, isNotNull);
    expect(plan!.hasConflicts, isFalse);
    expect(applyEdits(document.text, plan.edits), '''
fn blend(left: f64) {
  emit left
}
value = blend(price)
again = blend(total)
''');
  });

  test('blocks parameter removal while body references remain', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'change-signature-remove-used-parameter.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left + right
}
value = blend(price, tax)
''',
      revision: 0,
    );

    final plan = service.changeSignatureAt(
      document,
      document.text.indexOf('blend') + 1,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
      ],
    );

    expect(plan, isNotNull);
    expect(plan!.hasConflicts, isTrue);
    expect(plan.conflicts.single.message, contains('Cannot remove parameter'));
    expect(plan.edits, isEmpty);
  });

  test('reports and fixes unused parameters through change signature', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unused-parameter.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
again = blend(total, fee)
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((item) => item.code == 'unused-parameter');

    expect(
      document.text.substring(diagnostic.range.start, diagnostic.range.end),
      'right',
    );
    final quickFix = service
        .quickFixesForDiagnostic(document, diagnostic)
        .single;
    expect(quickFix.label, 'Remove unused parameter');
    expect(applyEdits(document.text, quickFix.edits), '''
fn blend(left: f64) {
  emit left
}
value = blend(price)
again = blend(total)
''');
  });

  test('reports and fixes call argument arity mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'call-arity.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left
}
price = 1
tax = 2
blend(price) -> @stdout
blend(price, tax, price) -> @stdout
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final missing = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'missing-call-argument',
    );
    final extra = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'too-many-call-arguments',
    );

    expect(missing.message, contains('right'));
    expect(extra.message, contains('expected 2'));

    final missingFix = service
        .quickFixesForDiagnostic(document, missing)
        .single;
    final extraFix = service.quickFixesForDiagnostic(document, extra).single;

    expect(missingFix.label, 'Insert missing argument');
    expect(missingFix.edits.single.newText, 'price, value');
    expect(extraFix.label, 'Remove extra argument');
    expect(extraFix.edits.single.newText, 'price, tax');
  });

  test('reports and optimizes duplicate or unsorted imports', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'imports.styio',
      text: '''
@import { styio/io }
@import { styio/core }
@import { styio/io }
value = 1
''',
      revision: 0,
    );

    final duplicate = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'duplicate-import');
    final fixes = service.quickFixesForDiagnostic(document, duplicate);

    expect(duplicate.message, contains('styio/io'));
    expect(fixes.single.label, 'Optimize imports');
    expect(fixes.single.edits.map((edit) => edit.newText), [
      '@import { styio/core }\n@import { styio/io }\n',
      '',
      '',
    ]);
  });

  test('reports non-canonical import blocks for optimization', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unsorted-imports.styio',
      text: '''
@import { styio/io }
@import { styio/core }
value = 1
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'import-block-not-optimized',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(diagnostic.severity, DiagnosticSeverity.hint);
    expect(fix.label, 'Optimize imports');
    expect(
      fix.edits.first.newText,
      '@import { styio/core }\n@import { styio/io }\n',
    );
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

  test('offers change-to quick fix for similar unresolved symbols', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'typo-local.styio',
      text: '''
movingAverage = 42
movingAverge -> @stdout
''',
      revision: 0,
    );

    final unresolved = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'unresolved-reference');
    final fixes = service.quickFixesForDiagnostic(document, unresolved);

    expect(fixes.first.label, 'Change to `movingAverage`');
    expect(fixes.first.edits.single.newText, 'movingAverage');
    expect(
      fixes.map((fix) => fix.label),
      contains('Create local binding `movingAverge`'),
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

  test('reports and renames duplicate declarations in the same scope', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'duplicate-declaration.styio',
      text: '''
value = 1
value = 2
value -> @stdout
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'duplicate-declaration',
        );
    final fixes = service.quickFixesForDiagnostic(document, diagnostic);

    expect(diagnostic.message, contains('value'));
    expect(fixes.single.label, 'Rename duplicate declaration to `value2`');
    expect(fixes.single.edits.map((edit) => edit.newText), [
      'value2',
      'value2',
    ]);
  });

  test('does not report matching parameter names in separate functions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'scoped-parameters.styio',
      text: '''
#first := (value) => {
  <| value
}
#second := (value) => {
  <| value
}
''',
      revision: 0,
    );

    final duplicateDiagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'duplicate-declaration');

    expect(duplicateDiagnostics, isEmpty);
  });

  test('reports duplicate parameters in the same signature scope', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'duplicate-parameters.styio',
      text: '''
#sum := (value, value) => {
  <| value
}
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'duplicate-declaration',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Rename duplicate declaration to `value2`');
    expect(fix.edits.map((edit) => edit.newText), ['value2', 'value2']);
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

  test('offers current-file symbols as completion items', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'completion.styio',
      text: '''
/// Runs async price work.
job = ||> { <| 42 }
jo''',
      revision: 0,
    );

    final jobCompletion = service
        .completeAt(document, document.text.length)
        .singleWhere((item) => item.label == 'job');

    expect(jobCompletion.kind, CompletionItemKind.variable);
    expect(jobCompletion.insertText, 'job');
    expect(jobCompletion.documentation, 'Runs async price work.');
  });

  test('offers postfix completions that replace the target expression', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'postfix-completion.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left
}
blend(price, tax).em
''',
      revision: 0,
    );

    final completion = service
        .completeAt(document, document.text.lastIndexOf('em') + 2)
        .firstWhere((item) => item.label == '.emit');
    final range = completion.replacementRange;

    expect(completion.kind, CompletionItemKind.snippet);
    expect(completion.insertText, 'emit blend(price, tax)');
    expect(range, isNotNull);
    expect(
      document.text.substring(range!.start, range.end),
      'blend(price, tax).em',
    );
    expect(
      applyEdits(document.text, [
        FormattingEdit(range: range, newText: completion.insertText),
      ]),
      '''
fn blend(left: f64, right: f64) {
  emit left
}
emit blend(price, tax)
''',
    );
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
