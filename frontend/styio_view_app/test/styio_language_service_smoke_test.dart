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

  test('offers specify-type-explicitly as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'specify-type-explicitly.styio',
      text: '''
price = 12.5
copy = price
explicit: f64 = 1
''',
      revision: 0,
    );

    final action = service
        .intentionsAt(document, document.text.indexOf('copy =') + 1)
        .singleWhere((item) => item.label == 'Specify type explicitly');

    expect(action.detail, contains('f64'));
    expect(applyEdits(document.text, action.edits), '''
price = 12.5
copy: f64 = price
explicit: f64 = 1
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('explicit:') + 1),
      isEmpty,
    );
  });

  test('offers remove-explicit-type as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'remove-explicit-type.styio',
      text: '''
price = 12.5
copy: f64 = price
wide: f64 = 3
copy -> @stdout
''',
      revision: 0,
    );

    final action = service
        .intentionsAt(document, document.text.indexOf('copy:') + 1)
        .singleWhere((item) => item.label == 'Remove explicit type');

    expect(action.detail, contains('f64'));
    expect(applyEdits(document.text, action.edits), '''
price = 12.5
copy = price
wide: f64 = 3
copy -> @stdout
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('wide:') + 1),
      isEmpty,
    );
  });

  test('reports and fixes typed local initializer type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'initializer-type-mismatch.styio',
      text: '''
wide: f64 = 3
wide -> @stdout
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
        );
    final fixes = service.quickFixesForDiagnostic(document, mismatch);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change initializer to f64 literal',
    );
    final localTypeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change local `wide` type to i64',
    );

    expect(mismatch.message, contains('expects `f64`, got `i64`'));
    expect(applyEdits(document.text, literalFix.edits), '''
wide: f64 = 3.0
wide -> @stdout
''');
    expect(applyEdits(document.text, localTypeFix.edits), '''
wide: i64 = 3
wide -> @stdout
''');
  });

  test('reports and fixes typed local assignment type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'assignment-type-mismatch.styio',
      text: '''
rate: f64 = 0.0
rate = 1
count: i64 = 0
count = 1.5
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'assignment-type-mismatch');
    final rateMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`rate`'),
    );
    final countMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`count`'),
    );
    final rateFixes = service.quickFixesForDiagnostic(document, rateMismatch);
    final literalFix = rateFixes.singleWhere(
      (fix) => fix.label == 'Change assignment to f64 literal',
    );
    final countTypeFix = service
        .quickFixesForDiagnostic(document, countMismatch)
        .singleWhere((fix) => fix.label == 'Change local `count` type to f64');

    expect(rateMismatch.message, contains('expects `f64`, got `i64`'));
    expect(applyEdits(document.text, literalFix.edits), '''
rate: f64 = 0.0
rate = 1.0
count: i64 = 0
count = 1.5
''');
    expect(applyEdits(document.text, countTypeFix.edits), '''
rate: f64 = 0.0
rate = 1
count: f64 = 0.0
count = 1.5
''');
  });

  test('reports binary expression type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'binary-expression-type-mismatch.styio',
      text: '''
price = 12.5
flag: i64 = price > 1
fn ready(value: f64): i64 {
  emit value > 0
}
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final initializerMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
    );
    final returnMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'return-type-mismatch',
    );
    final returnTypeFix = service
        .quickFixesForDiagnostic(document, returnMismatch)
        .singleWhere(
          (fix) => fix.label == 'Change function `ready` return type to bool',
        );

    expect(initializerMismatch.message, contains('expects `i64`, got `bool`'));
    expect(returnMismatch.message, contains('expects `i64`, got `bool`'));
    expect(applyEdits(document.text, returnTypeFix.edits), '''
price = 12.5
flag: i64 = price > 1
fn ready(value: f64): bool {
  emit value > 0
}
''');
  });

  test('reports precedence-aware expression type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'precedence-expression-type-mismatch.styio',
      text: '''
price = 12.5
flag: i64 = true || price > 0
fn ready(value: f64): i64 {
  emit true || value + 1 > 0
}
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final initializerMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
    );
    final returnMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'return-type-mismatch',
    );
    final returnTypeFix = service
        .quickFixesForDiagnostic(document, returnMismatch)
        .singleWhere(
          (fix) => fix.label == 'Change function `ready` return type to bool',
        );

    expect(initializerMismatch.message, contains('expects `i64`, got `bool`'));
    expect(returnMismatch.message, contains('expects `i64`, got `bool`'));
    expect(applyEdits(document.text, returnTypeFix.edits), '''
price = 12.5
flag: i64 = true || price > 0
fn ready(value: f64): bool {
  emit true || value + 1 > 0
}
''');
  });

  test('reports unary and parenthesized expression type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unary-expression-type-mismatch.styio',
      text: '''
price = 12.5
ready = price > 0
flag: i64 = !ready
fn negative(value: f64): i64 {
  emit -(value + 1)
}
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final initializerMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
    );
    final returnMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'return-type-mismatch',
    );
    final returnTypeFix = service
        .quickFixesForDiagnostic(document, returnMismatch)
        .singleWhere(
          (fix) => fix.label == 'Change function `negative` return type to f64',
        );

    expect(initializerMismatch.message, contains('expects `i64`, got `bool`'));
    expect(returnMismatch.message, contains('expects `i64`, got `f64`'));
    expect(applyEdits(document.text, returnTypeFix.edits), '''
price = 12.5
ready = price > 0
flag: i64 = !ready
fn negative(value: f64): f64 {
  emit -(value + 1)
}
''');
  });

  test('reports and fixes when condition type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'condition-type-mismatch.styio',
      text: '''
price = 12.5
ready = price > 0
when price -> state priced
when ready -> state ready
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'condition-type-mismatch',
        );
    final fix = service
        .quickFixesForDiagnostic(document, mismatch)
        .singleWhere((item) => item.label == 'Compare condition with zero');

    expect(mismatch.message, contains('expects `bool`, got `f64`'));
    expect(applyEdits(document.text, fix.edits), '''
price = 12.5
ready = price > 0
when price != 0.0 -> state priced
when ready -> state ready
''');
  });

  test('reports and fixes function return type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'return-type-mismatch.styio',
      text: '''
fn price(): f64 {
  emit 3
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'return-type-mismatch');
    final fixes = service.quickFixesForDiagnostic(document, mismatch);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change return expression to f64 literal',
    );
    final returnTypeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change function `price` return type to i64',
    );

    expect(mismatch.message, contains('expects `f64`, got `i64`'));
    expect(applyEdits(document.text, literalFix.edits), '''
fn price(): f64 {
  emit 3.0
}
''');
    expect(applyEdits(document.text, returnTypeFix.edits), '''
fn price(): i64 {
  emit 3
}
''');
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

  test('reports and fixes named call argument issues', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'named-argument-issues.styio',
      text: '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left
}
price = 1
tax = 2
factor = 3
typo = blend(left: price, rigth: tax, scale: factor)
duplicate = blend(left: price, left: tax, scale: factor)
''',
      revision: 0,
    );
    final diagnostics = service.analyzeDocument(document).diagnostics;
    final unknown = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'unknown-named-argument',
    );
    final duplicate = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'duplicate-named-argument',
    );

    final unknownFix = service
        .quickFixesForDiagnostic(document, unknown)
        .single;
    final duplicateFix = service
        .quickFixesForDiagnostic(document, duplicate)
        .single;

    expect(unknown.message, contains('rigth'));
    expect(unknownFix.label, 'Change argument name to `right`');
    expect(applyEdits(document.text, unknownFix.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left
}
price = 1
tax = 2
factor = 3
typo = blend(left: price, right: tax, scale: factor)
duplicate = blend(left: price, left: tax, scale: factor)
''');
    expect(duplicate.message, contains('left'));
    expect(duplicateFix.label, 'Remove duplicate `left` argument');
    expect(applyEdits(document.text, duplicateFix.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left
}
price = 1
tax = 2
factor = 3
typo = blend(left: price, rigth: tax, scale: factor)
duplicate = blend(left: price, scale: factor)
''');
  });

  test('reports and fixes literal call argument type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'argument-type-mismatch.styio',
      text: '''
fn emitPrice(value: f64) {
  emit value
}
emitPrice(3) -> @stdout
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'argument-type-mismatch',
        );
    final fixes = service.quickFixesForDiagnostic(document, mismatch);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change argument to f64 literal',
    );
    final parameterTypeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change parameter `value` type to i64',
    );

    expect(mismatch.message, contains('expects `f64`, got `i64`'));
    expect(applyEdits(document.text, literalFix.edits), '''
fn emitPrice(value: f64) {
  emit value
}
emitPrice(3.0) -> @stdout
''');
    expect(applyEdits(document.text, parameterTypeFix.edits), '''
fn emitPrice(value: i64) {
  emit value
}
emitPrice(3) -> @stdout
''');
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

  test('offers named argument completions inside function calls', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'named-argument-completion.styio',
      text: '''
/// Blends price and tax inputs.
/// @param left Base price before tax.
/// @param right Tax component to add.
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
value = blend(le)
again = blend(left: price, ri)
''',
      revision: 0,
    );

    final leftCompletion = service
        .completeAt(document, document.text.indexOf('le)') + 2)
        .singleWhere((item) => item.label == 'left:');
    final rightLabels = service
        .completeAt(document, document.text.indexOf('ri)') + 2)
        .map((item) => item.label)
        .toList(growable: false);
    final rightNamedArgumentLabels = rightLabels
        .where((label) => label.endsWith(':'))
        .toList(growable: false);

    expect(leftCompletion.kind, CompletionItemKind.snippet);
    expect(leftCompletion.insertText, 'left: ');
    expect(leftCompletion.detail, contains('f64'));
    expect(leftCompletion.documentation, 'Base price before tax.');
    expect(
      applyEdits(document.text, [
        FormattingEdit(
          range: leftCompletion.replacementRange!,
          newText: leftCompletion.insertText,
        ),
      ]),
      '''
/// Blends price and tax inputs.
/// @param left Base price before tax.
/// @param right Tax component to add.
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
value = blend(left: )
again = blend(left: price, ri)
''',
    );
    expect(rightLabels.first, 'right:');
    expect(rightNamedArgumentLabels, ['right:']);
  });

  test('offers add-argument-names as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'add-argument-names.styio',
      text: '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
value = blend(price, tax)
''',
      revision: 0,
    );

    final actions = service.intentionsAt(
      document,
      document.text.lastIndexOf('price, tax') + 1,
    );
    final action = actions.singleWhere(
      (item) => item.label == 'Add argument names',
    );
    final singleArgumentAction = actions.singleWhere(
      (item) => item.label == 'Add left: to argument',
    );

    expect(action.label, 'Add argument names');
    expect(action.detail, contains('blend'));
    expect(applyEdits(document.text, action.edits), '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
value = blend(left: price, right: tax)
''');
    expect(singleArgumentAction.detail, contains('current `blend` argument'));
    expect(applyEdits(document.text, singleArgumentAction.edits), '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
value = blend(left: price, tax)
''');
  });

  test('offers remove-argument-name as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'remove-argument-name.styio',
      text: '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, right: tax, scale: factor)
wrongSlot = blend(price, scale: factor)
''',
      revision: 0,
    );

    final action = service
        .intentionsAt(document, document.text.indexOf('right: tax') + 1)
        .singleWhere((item) => item.label == 'Remove right: from argument');

    expect(action.detail, contains('positionally'));
    expect(applyEdits(document.text, action.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, tax, scale: factor)
wrongSlot = blend(price, scale: factor)
''');
    expect(
      service.intentionsAt(
        document,
        document.text.indexOf('wrongSlot = blend(price, scale:') +
            'wrongSlot = blend(price, '.length,
      ),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Remove scale: from argument',
          ),
        ),
      ),
    );
  });

  test('offers remove-all-argument-names as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'remove-all-argument-names.styio',
      text: '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(left: price, right: tax, scale: factor)
unsafe = blend(scale: factor, right: tax)
''',
      revision: 0,
    );

    final action = service
        .intentionsAt(document, document.text.indexOf('right: tax') + 1)
        .singleWhere((item) => item.label == 'Remove all argument names');

    expect(action.detail, contains('signature order'));
    expect(applyEdits(document.text, action.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, tax, factor)
unsafe = blend(scale: factor, right: tax)
''');
    expect(
      service.intentionsAt(
        document,
        document.text.indexOf('unsafe = blend') + 'unsafe = blend('.length,
      ),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Remove all argument names',
          ),
        ),
      ),
    );
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
