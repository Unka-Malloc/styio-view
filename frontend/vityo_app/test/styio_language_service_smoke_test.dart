import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';

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

  test('resolves definitions references and hover by function scope', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'scoped-definition-reference.styio',
      text: '''
value = 1

fn sample(input: f64) {
  value = input
  emit value
}

value -> @stdout
''',
      revision: 0,
    );

    final topDeclarationOffset = document.text.indexOf('value = 1');
    final localDeclarationOffset = document.text.indexOf('value = input');
    final localUseOffset = document.text.indexOf('emit value') + 'emit '.length;
    final topUseOffset = document.text.lastIndexOf('value -> @stdout');

    final localDefinition = service.definitionAt(document, localUseOffset);
    final topDefinition = service.definitionAt(document, topUseOffset);
    expect(localDefinition, isNotNull);
    expect(topDefinition, isNotNull);
    expect(localDefinition!.symbol.nameRange.start, localDeclarationOffset);
    expect(topDefinition!.symbol.nameRange.start, topDeclarationOffset);

    final localReferences = service.referencesAt(document, localUseOffset);
    final topReferences = service.referencesAt(document, topUseOffset);
    expect(localReferences.map((reference) => reference.range.start).toSet(), {
      localDeclarationOffset,
      localUseOffset,
    });
    expect(topReferences.map((reference) => reference.range.start).toSet(), {
      topDeclarationOffset,
      topUseOffset,
    });

    expect(service.hoverAt(document, localUseOffset), isNotNull);
    expect(service.hoverAt(document, topUseOffset), isNotNull);
  });

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

  test('surfaces TODO and FIXME comments as hint diagnostics', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'todo-comments.styio',
      text: '''
// TODO: hand this block to compiler-owned semantic parsing.
value = 42
/*
 * FIXME validate resource sink ownership after adapter handoff.
 */
value -> @stdout
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'todo-comment')
        .toList(growable: false);

    expect(diagnostics, hasLength(2));
    expect(
      diagnostics.every(
        (diagnostic) => diagnostic.severity == DiagnosticSeverity.hint,
      ),
      isTrue,
    );
    expect(diagnostics.first.message, contains('TODO comment'));
    expect(diagnostics.first.message, contains('compiler-owned'));
    expect(diagnostics.last.message, contains('FIXME comment'));
    expect(diagnostics.last.message, contains('adapter handoff'));
    expect(
      document.text.substring(
        diagnostics.first.range.start,
        diagnostics.first.range.end,
      ),
      contains('TODO: hand this block'),
    );
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

  test('offers negate-when-condition as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'negate-when-condition.styio',
      text: '''
ready = true
price = 12.5
when ready -> state ready
when !ready -> state blocked
when price > 0 -> state priced
''',
      revision: 0,
    );

    final readyAction = service
        .intentionsAt(document, document.text.indexOf('ready ->'))
        .singleWhere((item) => item.label == 'Negate when condition');
    final negatedAction = service
        .intentionsAt(document, document.text.indexOf('!ready') + 1)
        .singleWhere((item) => item.label == 'Negate when condition');
    final complexAction = service
        .intentionsAt(document, document.text.indexOf('price > 0') + 2)
        .singleWhere((item) => item.label == 'Negate when condition');

    expect(readyAction.detail, contains('guard'));
    expect(applyEdits(document.text, readyAction.edits), '''
ready = true
price = 12.5
when !ready -> state ready
when !ready -> state blocked
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, negatedAction.edits), '''
ready = true
price = 12.5
when ready -> state ready
when ready -> state blocked
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, complexAction.edits), '''
ready = true
price = 12.5
when ready -> state ready
when !ready -> state blocked
when !(price > 0) -> state priced
''');
  });

  test('offers flip-comparison-operands as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'flip-comparison-operands.styio',
      text: '''
price = 12.5
tax = 0.5
limit = 10.0
when price > limit -> state expensive
when price == limit -> state exact
when price + tax >= limit -> state taxed
''',
      revision: 0,
    );

    final greaterAction = service
        .intentionsAt(document, document.text.indexOf('price > limit') + 2)
        .singleWhere((item) => item.label == 'Flip comparison operands');
    final equalityAction = service
        .intentionsAt(document, document.text.indexOf('price == limit') + 8)
        .singleWhere((item) => item.label == 'Flip comparison operands');
    final arithmeticAction = service
        .intentionsAt(document, document.text.indexOf('price + tax') + 8)
        .singleWhere((item) => item.label == 'Flip comparison operands');

    expect(greaterAction.detail, contains('Swap'));
    expect(applyEdits(document.text, greaterAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
when limit < price -> state expensive
when price == limit -> state exact
when price + tax >= limit -> state taxed
''');
    expect(applyEdits(document.text, equalityAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
when price > limit -> state expensive
when limit == price -> state exact
when price + tax >= limit -> state taxed
''');
    expect(applyEdits(document.text, arithmeticAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
when price > limit -> state expensive
when price == limit -> state exact
when limit <= price + tax -> state taxed
''');
  });

  test('offers invert-comparison as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'invert-comparison.styio',
      text: '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when price > limit -> state expensive
when ready == blocked -> state same
when price + tax <= limit -> state affordable
when !(price > limit) -> state guarded
''',
      revision: 0,
    );

    final greaterAction = service
        .intentionsAt(document, document.text.indexOf('price > limit') + 2)
        .singleWhere((item) => item.label == 'Invert comparison');
    final equalityAction = service
        .intentionsAt(document, document.text.indexOf('ready == blocked') + 2)
        .singleWhere((item) => item.label == 'Invert comparison');
    final lessOrEqualAction = service
        .intentionsAt(document, document.text.indexOf('price + tax') + 8)
        .singleWhere((item) => item.label == 'Invert comparison');

    expect(greaterAction.detail, contains('logical opposite'));
    expect(applyEdits(document.text, greaterAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when price <= limit -> state expensive
when ready == blocked -> state same
when price + tax <= limit -> state affordable
when !(price > limit) -> state guarded
''');
    expect(applyEdits(document.text, equalityAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when price > limit -> state expensive
when ready != blocked -> state same
when price + tax <= limit -> state affordable
when !(price > limit) -> state guarded
''');
    expect(applyEdits(document.text, lessOrEqualAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when price > limit -> state expensive
when ready == blocked -> state same
when price + tax > limit -> state affordable
when !(price > limit) -> state guarded
''');
    final guardedIntentions = service.intentionsAt(
      document,
      document.text.lastIndexOf('price > limit') + 2,
    );
    expect(
      guardedIntentions,
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Invert comparison',
          ),
        ),
      ),
    );
    expect(
      guardedIntentions,
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Flip comparison operands',
          ),
        ),
      ),
    );
  });

  test('offers apply-demorgans-law as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'apply-demorgans-law.styio',
      text: '''
ready = true
priced = true
blocked = false
price = 12.5
when !(ready && priced) -> state active
when !(price > 0 || blocked) -> state safe
when !(!ready || blocked) -> state pending
when !(ready && priced || blocked) -> state mixed
''',
      revision: 0,
    );

    final conjunctionAction = service
        .intentionsAt(document, document.text.indexOf('ready && priced') + 2)
        .singleWhere((item) => item.label == "Apply De Morgan's law");
    final disjunctionAction = service
        .intentionsAt(document, document.text.indexOf('price > 0') + 2)
        .singleWhere((item) => item.label == "Apply De Morgan's law");
    final doubleNegationAction = service
        .intentionsAt(document, document.text.indexOf('!ready') + 1)
        .singleWhere((item) => item.label == "Apply De Morgan's law");

    expect(conjunctionAction.detail, contains('negation'));
    expect(applyEdits(document.text, conjunctionAction.edits), '''
ready = true
priced = true
blocked = false
price = 12.5
when !ready || !priced -> state active
when !(price > 0 || blocked) -> state safe
when !(!ready || blocked) -> state pending
when !(ready && priced || blocked) -> state mixed
''');
    expect(applyEdits(document.text, disjunctionAction.edits), '''
ready = true
priced = true
blocked = false
price = 12.5
when !(ready && priced) -> state active
when !(price > 0) && !blocked -> state safe
when !(!ready || blocked) -> state pending
when !(ready && priced || blocked) -> state mixed
''');
    expect(applyEdits(document.text, doubleNegationAction.edits), '''
ready = true
priced = true
blocked = false
price = 12.5
when !(ready && priced) -> state active
when !(price > 0 || blocked) -> state safe
when ready && !blocked -> state pending
when !(ready && priced || blocked) -> state mixed
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('ready =')),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == "Apply De Morgan's law",
          ),
        ),
      ),
    );
    expect(
      service.intentionsAt(
        document,
        document.text.indexOf('priced || blocked') + 2,
      ),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == "Apply De Morgan's law",
          ),
        ),
      ),
    );
  });

  test('reports and fixes De Morgan simplifications', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplifiable-demorgan-expression.styio',
      text: '''
ready = true
priced = false
blocked = false
when !(ready && priced) -> state active
when !(ready || blocked) -> state inactive
when !(ready && priced || blocked) -> state mixed
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final simplifiable = diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-demorgan-expression',
        )
        .toList(growable: false);

    expect(
      simplifiable
          .map(
            (diagnostic) => document.text.substring(
              diagnostic.range.start,
              diagnostic.range.end,
            ),
          )
          .toList(growable: false),
      ['!(ready && priced)', '!(ready || blocked)'],
    );

    final andFix = service
        .quickFixesForDiagnostic(document, simplifiable.first)
        .single;
    final orFix = service
        .quickFixesForDiagnostic(document, simplifiable.last)
        .single;

    expect(andFix.label, 'Apply De Morgan\'s law');
    expect(orFix.label, 'Apply De Morgan\'s law');
    expect(applyEdits(document.text, andFix.edits), '''
ready = true
priced = false
blocked = false
when !ready || !priced -> state active
when !(ready || blocked) -> state inactive
when !(ready && priced || blocked) -> state mixed
''');
    expect(applyEdits(document.text, orFix.edits), '''
ready = true
priced = false
blocked = false
when !(ready && priced) -> state active
when !ready && !blocked -> state inactive
when !(ready && priced || blocked) -> state mixed
''');
  });

  test('offers simplify-negated-boolean-literal as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplify-negated-boolean-literal.styio',
      text: '''
ready = true
when !true -> state never
when ! false -> state always
when !ready -> state toggled
''',
      revision: 0,
    );

    final trueAction = service
        .intentionsAt(document, document.text.indexOf('!true') + 1)
        .singleWhere(
          (item) => item.label == 'Simplify negated boolean literal',
        );
    final falseAction = service
        .intentionsAt(document, document.text.indexOf('! false') + 2)
        .singleWhere(
          (item) => item.label == 'Simplify negated boolean literal',
        );

    expect(trueAction.detail, contains('opposite value'));
    expect(applyEdits(document.text, trueAction.edits), '''
ready = true
when false -> state never
when ! false -> state always
when !ready -> state toggled
''');
    expect(applyEdits(document.text, falseAction.edits), '''
ready = true
when !true -> state never
when true -> state always
when !ready -> state toggled
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('!ready') + 1),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify negated boolean literal',
          ),
        ),
      ),
    );
  });

  test('offers simplify-double-negation as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplify-double-negation.styio',
      text: '''
ready = true
blocked = false
when !!ready -> state active
when !!(ready && !blocked) -> state complex
when ! !blocked -> state spaced
when !ready -> state negated
''',
      revision: 0,
    );

    final simpleAction = service
        .intentionsAt(document, document.text.indexOf('!!ready') + 2)
        .singleWhere((item) => item.label == 'Simplify double negation');
    final parenthesizedAction = service
        .intentionsAt(document, document.text.indexOf('ready && !blocked') + 2)
        .singleWhere((item) => item.label == 'Simplify double negation');
    final spacedAction = service
        .intentionsAt(document, document.text.indexOf('! !blocked') + 2)
        .singleWhere((item) => item.label == 'Simplify double negation');

    expect(simpleAction.detail, contains('double-negated'));
    expect(applyEdits(document.text, simpleAction.edits), '''
ready = true
blocked = false
when ready -> state active
when !!(ready && !blocked) -> state complex
when ! !blocked -> state spaced
when !ready -> state negated
''');
    expect(applyEdits(document.text, parenthesizedAction.edits), '''
ready = true
blocked = false
when !!ready -> state active
when (ready && !blocked) -> state complex
when ! !blocked -> state spaced
when !ready -> state negated
''');
    expect(applyEdits(document.text, spacedAction.edits), '''
ready = true
blocked = false
when !!ready -> state active
when !!(ready && !blocked) -> state complex
when blocked -> state spaced
when !ready -> state negated
''');
    expect(
      service.intentionsAt(document, document.text.lastIndexOf('!ready')),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify double negation',
          ),
        ),
      ),
    );
  });

  test('reports and fixes simplifiable boolean negations', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplifiable-boolean-negation.styio',
      text: '''
ready = true
blocked = false
when !true -> state never
when !!ready -> state active
when ! !blocked -> state spaced
when !ready -> state negated
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final simplifiable = diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-boolean-negation',
        )
        .toList(growable: false);

    expect(
      simplifiable
          .map(
            (diagnostic) => document.text.substring(
              diagnostic.range.start,
              diagnostic.range.end,
            ),
          )
          .toList(growable: false),
      ['!true', '!!ready', '! !blocked'],
    );

    final literalFix = service
        .quickFixesForDiagnostic(document, simplifiable.first)
        .single;
    final doubleFix = service
        .quickFixesForDiagnostic(document, simplifiable[1])
        .single;

    expect(literalFix.label, 'Simplify negated boolean literal');
    expect(doubleFix.label, 'Simplify double negation');
    expect(applyEdits(document.text, literalFix.edits), '''
ready = true
blocked = false
when false -> state never
when !!ready -> state active
when ! !blocked -> state spaced
when !ready -> state negated
''');
    expect(applyEdits(document.text, doubleFix.edits), '''
ready = true
blocked = false
when !true -> state never
when ready -> state active
when ! !blocked -> state spaced
when !ready -> state negated
''');
  });

  test('offers simplify-boolean-comparison as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplify-boolean-comparison.styio',
      text: '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''',
      revision: 0,
    );

    final equalsTrueAction = service
        .intentionsAt(document, document.text.indexOf('ready == true') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final equalsFalseAction = service
        .intentionsAt(document, document.text.indexOf('ready == false') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final notEqualsTrueAction = service
        .intentionsAt(document, document.text.indexOf('blocked != true') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final literalLeftAction = service
        .intentionsAt(document, document.text.indexOf('false != ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final sameTermAction = service
        .intentionsAt(document, document.text.indexOf('ready == ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final changedTermAction = service
        .intentionsAt(document, document.text.indexOf('ready != ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final complementEqualsAction = service
        .intentionsAt(document, document.text.indexOf('ready == !ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean comparison');
    final complementNotEqualsAction = service
        .intentionsAt(
          document,
          document.text.indexOf('!blocked != blocked') + 2,
        )
        .singleWhere((item) => item.label == 'Simplify boolean comparison');

    expect(equalsTrueAction.detail, contains('boolean literal'));
    expect(applyEdits(document.text, equalsTrueAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, equalsFalseAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when !ready -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, notEqualsTrueAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when !blocked -> state active
when false != ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, literalLeftAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(sameTermAction.detail, contains('truth value'));
    expect(applyEdits(document.text, sameTermAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when true -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, changedTermAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when ready == ready -> state same
when false -> state changed
when ready == !ready -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, complementEqualsAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when false -> state impossible
when !blocked != blocked -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, complementNotEqualsAction.edits), '''
ready = true
blocked = false
price = 12.5
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when false != ready -> state inverted
when ready == ready -> state same
when ready != ready -> state changed
when ready == !ready -> state impossible
when true -> state active_mirror
when check() == check() -> state effect
when price > 0 -> state priced
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('price > 0') + 2),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify boolean comparison',
          ),
        ),
      ),
    );
    expect(
      service.intentionsAt(document, document.text.indexOf('check() ==') + 2),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify boolean comparison',
          ),
        ),
      ),
    );
  });

  test('reports and fixes simplifiable boolean comparisons', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplifiable-boolean-comparison.styio',
      text: '''
ready = true
blocked = false
when ready == true -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when price > 0 -> state priced
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final simplifiable = diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-boolean-comparison',
        )
        .toList(growable: false);

    expect(
      simplifiable
          .map(
            (diagnostic) => document.text.substring(
              diagnostic.range.start,
              diagnostic.range.end,
            ),
          )
          .toList(growable: false),
      ['ready == true', 'ready == false', 'blocked != true'],
    );

    final positiveFix = service
        .quickFixesForDiagnostic(document, simplifiable.first)
        .single;
    final negativeFix = service
        .quickFixesForDiagnostic(document, simplifiable[1])
        .single;

    expect(positiveFix.label, 'Simplify boolean comparison');
    expect(negativeFix.label, 'Simplify boolean comparison');
    expect(applyEdits(document.text, positiveFix.edits), '''
ready = true
blocked = false
when ready -> state ready
when ready == false -> state stopped
when blocked != true -> state active
when price > 0 -> state priced
''');
    expect(applyEdits(document.text, negativeFix.edits), '''
ready = true
blocked = false
when ready == true -> state ready
when !ready -> state stopped
when blocked != true -> state active
when price > 0 -> state priced
''');
  });

  test('reports and fixes stable self comparisons', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'stable-self-comparison.styio',
      text: '''
price = 12.5
same = price == price
different = price != price
smaller = price < price
no_greater = price <= price
effect = check() == check()
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    diagnosticFor(String expression) => diagnostics.singleWhere(
      (diagnostic) =>
          document.text.substring(
            diagnostic.range.start,
            diagnostic.range.end,
          ) ==
          expression,
    );

    final equalDiagnostic = diagnosticFor('price == price');
    final notEqualDiagnostic = diagnosticFor('price != price');
    final lessDiagnostic = diagnosticFor('price < price');
    final lessOrEqualDiagnostic = diagnosticFor('price <= price');

    expect(equalDiagnostic.code, 'simplifiable-boolean-comparison');
    expect(notEqualDiagnostic.code, 'simplifiable-boolean-comparison');
    expect(lessDiagnostic.code, 'simplifiable-boolean-comparison');
    expect(lessOrEqualDiagnostic.code, 'simplifiable-boolean-comparison');
    expect(
      diagnostics.where(
        (diagnostic) =>
            diagnostic.code == 'simplifiable-boolean-comparison' &&
            document.text.substring(
                  diagnostic.range.start,
                  diagnostic.range.end,
                ) ==
                'check() == check()',
      ),
      isEmpty,
    );

    final equalFix = service
        .quickFixesForDiagnostic(document, equalDiagnostic)
        .single;
    final notEqualFix = service
        .quickFixesForDiagnostic(document, notEqualDiagnostic)
        .single;
    final lessFix = service
        .quickFixesForDiagnostic(document, lessDiagnostic)
        .single;
    final lessOrEqualFix = service
        .quickFixesForDiagnostic(document, lessOrEqualDiagnostic)
        .single;

    expect([
      equalFix.label,
      notEqualFix.label,
      lessFix.label,
      lessOrEqualFix.label,
    ], everyElement('Simplify boolean comparison'));
    expect(applyEdits(document.text, equalFix.edits), '''
price = 12.5
same = true
different = price != price
smaller = price < price
no_greater = price <= price
effect = check() == check()
''');
    expect(applyEdits(document.text, notEqualFix.edits), '''
price = 12.5
same = price == price
different = false
smaller = price < price
no_greater = price <= price
effect = check() == check()
''');
    expect(applyEdits(document.text, lessFix.edits), '''
price = 12.5
same = price == price
different = price != price
smaller = false
no_greater = price <= price
effect = check() == check()
''');
    expect(applyEdits(document.text, lessOrEqualFix.edits), '''
price = 12.5
same = price == price
different = price != price
smaller = price < price
no_greater = true
effect = check() == check()
''');
  });

  test('offers simplify-boolean-expression as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplify-boolean-expression.styio',
      text: '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''',
      revision: 0,
    );

    final andTrueAction = service
        .intentionsAt(document, document.text.indexOf('ready && true') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final falseOrAction = service
        .intentionsAt(document, document.text.indexOf('false || ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final orTrueAction = service
        .intentionsAt(document, document.text.indexOf('blocked || true') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final andFalseAction = service
        .intentionsAt(document, document.text.indexOf('ready && false') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final duplicateOrAction = service
        .intentionsAt(document, document.text.indexOf('ready || ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final duplicateNegatedAndAction = service
        .intentionsAt(document, document.text.indexOf('!blocked &&') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final complementOrAction = service
        .intentionsAt(document, document.text.indexOf('ready || !ready') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final complementAndAction = service
        .intentionsAt(
          document,
          document.text.indexOf('!blocked && blocked') + 2,
        )
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final absorbedOrAction = service
        .intentionsAt(
          document,
          document.text.indexOf('ready || (ready && blocked)') + 2,
        )
        .singleWhere((item) => item.label == 'Simplify boolean expression');
    final absorbedAndAction = service
        .intentionsAt(document, document.text.indexOf('ready) && !blocked') + 2)
        .singleWhere((item) => item.label == 'Simplify boolean expression');

    expect(andTrueAction.detail, contains('simplified value'));
    expect(applyEdits(document.text, andTrueAction.edits), '''
ready = true
blocked = false
when ready -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, falseOrAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, orTrueAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, andFalseAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, duplicateOrAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, duplicateNegatedAndAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, complementOrAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when true -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, complementAndAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when false -> state contradiction
when ready || (ready && blocked) -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, absorbedOrAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready -> state absorbed
when (!blocked || ready) && !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(applyEdits(document.text, absorbedAndAction.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when blocked || true -> state always
when ready && false -> state never
when ready || ready -> state repeated
when !blocked && !blocked -> state guarded
when ready || !ready -> state tautology
when !blocked && blocked -> state contradiction
when ready || (ready && blocked) -> state absorbed
when !blocked -> state absorbed_negated
when ready || (ready && check()) -> state effect_absorption
when true || ready && blocked -> state mixed
when check() || check() -> state effect
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('true || ready')),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify boolean expression',
          ),
        ),
      ),
    );
    expect(
      service.intentionsAt(document, document.text.indexOf('check() ||') + 2),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify boolean expression',
          ),
        ),
      ),
    );
    expect(
      service.intentionsAt(
        document,
        document.text.indexOf('ready && check()') + 2,
      ),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify boolean expression',
          ),
        ),
      ),
    );
  });

  test('reports and fixes simplifiable boolean expressions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplifiable-boolean-expression.styio',
      text: '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when ready || ready -> state repeated
when ready || (ready && blocked) -> state absorbed
when ready && false -> state never
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final simplifiable = diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-boolean-expression',
        )
        .toList(growable: false);

    expect(
      simplifiable
          .map(
            (diagnostic) => document.text.substring(
              diagnostic.range.start,
              diagnostic.range.end,
            ),
          )
          .toList(growable: false),
      [
        'ready && true',
        'false || ready',
        'ready || ready',
        'ready || (ready && blocked)',
      ],
    );

    final andTrueFix = service
        .quickFixesForDiagnostic(document, simplifiable.first)
        .single;
    final absorptionFix = service
        .quickFixesForDiagnostic(document, simplifiable.last)
        .single;

    expect(andTrueFix.label, 'Simplify boolean expression');
    expect(absorptionFix.label, 'Simplify boolean expression');
    expect(applyEdits(document.text, andTrueFix.edits), '''
ready = true
blocked = false
when ready -> state ready
when false || ready -> state active
when ready || ready -> state repeated
when ready || (ready && blocked) -> state absorbed
when ready && false -> state never
''');
    expect(applyEdits(document.text, absorptionFix.edits), '''
ready = true
blocked = false
when ready && true -> state ready
when false || ready -> state active
when ready || ready -> state repeated
when ready -> state absorbed
when ready && false -> state never
''');
  });

  test('reports and fixes constant Styio when conditions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'constant-condition.styio',
      text: '''
ready = true
when 1 < 2 -> state always
when ready && !ready -> state never
when ready -> state dynamic
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final constants = diagnostics
        .where((diagnostic) => diagnostic.code == 'constant-condition')
        .toList(growable: false);

    expect(constants.map((diagnostic) => diagnostic.message), [
      'Styio `when` condition is always true.',
      'Styio `when` condition is always false.',
    ]);

    final trueFix = service
        .quickFixesForDiagnostic(document, constants.first)
        .single;
    final falseFixes = service.quickFixesForDiagnostic(
      document,
      constants.last,
    );
    final falseFix = falseFixes.singleWhere(
      (fix) => fix.label == 'Replace condition with false',
    );
    final removeFalseBranchFix = falseFixes.singleWhere(
      (fix) => fix.label == 'Remove unreachable `when` branch',
    );

    expect(trueFix.label, 'Replace condition with true');
    expect(falseFix.label, 'Replace condition with false');
    expect(applyEdits(document.text, trueFix.edits), '''
ready = true
when true -> state always
when ready && !ready -> state never
when ready -> state dynamic
''');
    expect(applyEdits(document.text, falseFix.edits), '''
ready = true
when 1 < 2 -> state always
when false -> state never
when ready -> state dynamic
''');
    expect(applyEdits(document.text, removeFalseBranchFix.edits), '''
ready = true
when 1 < 2 -> state always
when ready -> state dynamic
''');
  });

  test('reports constant boolean equality and numeric comparison conditions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'constant-comparison-condition.styio',
      text: '''
when true == false -> state impossible
when 3 >= 2 -> state numeric
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'constant-condition')
        .toList(growable: false);

    expect(diagnostics.map((diagnostic) => diagnostic.message), [
      'Styio `when` condition is always false.',
      'Styio `when` condition is always true.',
    ]);
    expect(
      service.quickFixesForDiagnostic(document, diagnostics[1]).first.label,
      'Replace condition with true',
    );
  });

  test('reports constant division by zero in numeric expressions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'division-by-zero.styio',
      text: '''
total = 42
ratio = total / 0
scaled = total / 0.0
remainder = total % 0
folded = total / (1 - 1)
safe = total / 10
safe_remainder = total % 3
label = "total / 0"
// ignored = total / 0
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'division-by-zero')
        .toList();

    expect(diagnostics, hasLength(4));
    expect(
      diagnostics.map(
        (diagnostic) => document.text.substring(
          diagnostic.range.start,
          diagnostic.range.end,
        ),
      ),
      equals(['0', '0.0', '0', '(1 - 1)']),
    );
    expect(
      diagnostics.map((diagnostic) => diagnostic.message),
      equals([
        'Styio numeric expression divides by zero.',
        'Styio numeric expression divides by zero.',
        'Styio numeric expression takes remainder by zero.',
        'Styio numeric expression divides by zero.',
      ]),
    );
  });

  test('reports and fixes simplifiable numeric expressions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplifiable-numeric-expression.styio',
      text: '''
total = 42
a = total + 0
b = 0 + total
c = total - 0
d = total * 1
e = 1 * total
f = total / 1
g = check() + 0
h = total * 0
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-numeric-expression',
        )
        .toList();

    expect(diagnostics, hasLength(6));
    final firstFix = service
        .quickFixesForDiagnostic(document, diagnostics.first)
        .single;
    final lastFix = service
        .quickFixesForDiagnostic(document, diagnostics.last)
        .single;

    expect(firstFix.label, 'Simplify numeric expression');
    expect(applyEdits(document.text, firstFix.edits), '''
total = 42
a = total
b = 0 + total
c = total - 0
d = total * 1
e = 1 * total
f = total / 1
g = check() + 0
h = total * 0
''');
    expect(applyEdits(document.text, lastFix.edits), '''
total = 42
a = total + 0
b = 0 + total
c = total - 0
d = total * 1
e = 1 * total
f = total
g = check() + 0
h = total * 0
''');
  });

  test('offers simplify-negated-comparison as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplify-negated-comparison.styio',
      text: '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when !(price > limit) -> state affordable
when !(ready == blocked) -> state different
when !(price + tax <= limit) -> state over
when !(ready && blocked) -> state boolean
''',
      revision: 0,
    );

    final greaterAction = service
        .intentionsAt(document, document.text.indexOf('price > limit') + 2)
        .singleWhere((item) => item.label == 'Simplify negated comparison');
    final equalityAction = service
        .intentionsAt(document, document.text.indexOf('ready == blocked') + 2)
        .singleWhere((item) => item.label == 'Simplify negated comparison');
    final lessOrEqualAction = service
        .intentionsAt(document, document.text.indexOf('price + tax') + 8)
        .singleWhere((item) => item.label == 'Simplify negated comparison');

    expect(greaterAction.detail, contains('opposite operator'));
    expect(applyEdits(document.text, greaterAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when price <= limit -> state affordable
when !(ready == blocked) -> state different
when !(price + tax <= limit) -> state over
when !(ready && blocked) -> state boolean
''');
    expect(applyEdits(document.text, equalityAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when !(price > limit) -> state affordable
when ready != blocked -> state different
when !(price + tax <= limit) -> state over
when !(ready && blocked) -> state boolean
''');
    expect(applyEdits(document.text, lessOrEqualAction.edits), '''
price = 12.5
tax = 0.5
limit = 10.0
ready = true
blocked = false
when !(price > limit) -> state affordable
when !(ready == blocked) -> state different
when price + tax > limit -> state over
when !(ready && blocked) -> state boolean
''');
    expect(
      service.intentionsAt(document, document.text.indexOf('ready &&') + 2),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Simplify negated comparison',
          ),
        ),
      ),
    );
  });

  test('reports and fixes simplifiable negated comparisons', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'simplifiable-negated-comparison.styio',
      text: '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when !(price > limit) -> state affordable
when !(ready == blocked) -> state changed
when !(ready && blocked) -> state boolean
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final simplifiable = diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-negated-comparison',
        )
        .toList(growable: false);

    expect(
      simplifiable
          .map(
            (diagnostic) => document.text.substring(
              diagnostic.range.start,
              diagnostic.range.end,
            ),
          )
          .toList(growable: false),
      ['!(price > limit)', '!(ready == blocked)'],
    );

    final numericFix = service
        .quickFixesForDiagnostic(document, simplifiable.first)
        .single;
    final equalityFix = service
        .quickFixesForDiagnostic(document, simplifiable.last)
        .single;

    expect(numericFix.label, 'Simplify negated comparison');
    expect(equalityFix.label, 'Simplify negated comparison');
    expect(applyEdits(document.text, numericFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when price <= limit -> state affordable
when !(ready == blocked) -> state changed
when !(ready && blocked) -> state boolean
''');
    expect(applyEdits(document.text, equalityFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when !(price > limit) -> state affordable
when ready != blocked -> state changed
when !(ready && blocked) -> state boolean
''');
  });

  test('offers remove-redundant-parentheses as a context intention', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'remove-redundant-parentheses.styio',
      text: '''
ready = true
blocked = false
price = 12.5
limit = 10.0
label = (ready)
label -> @stdout
when (price > limit) -> state expensive
when ((ready && !blocked)) -> state active
when !(ready && blocked) -> state guarded
''',
      revision: 0,
    );

    final atomAction = service
        .intentionsAt(document, document.text.indexOf('(ready)') + 2)
        .singleWhere((item) => item.label == 'Remove redundant parentheses');
    final conditionAction = service
        .intentionsAt(document, document.text.indexOf('price > limit') + 2)
        .singleWhere((item) => item.label == 'Remove redundant parentheses');
    final nestedAction = service
        .intentionsAt(document, document.text.indexOf('ready && !blocked') + 2)
        .singleWhere((item) => item.label == 'Remove redundant parentheses');

    expect(atomAction.detail, contains('Unwrap parentheses'));
    expect(applyEdits(document.text, atomAction.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
label = ready
label -> @stdout
when (price > limit) -> state expensive
when ((ready && !blocked)) -> state active
when !(ready && blocked) -> state guarded
''');
    expect(applyEdits(document.text, conditionAction.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
label = (ready)
label -> @stdout
when price > limit -> state expensive
when ((ready && !blocked)) -> state active
when !(ready && blocked) -> state guarded
''');
    expect(applyEdits(document.text, nestedAction.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
label = (ready)
label -> @stdout
when (price > limit) -> state expensive
when (ready && !blocked) -> state active
when !(ready && blocked) -> state guarded
''');
    expect(
      service.intentionsAt(document, document.text.lastIndexOf('ready &&') + 2),
      isNot(
        contains(
          predicate<DiagnosticQuickFix>(
            (item) => item.label == 'Remove redundant parentheses',
          ),
        ),
      ),
    );
  });

  test('reports and fixes redundant parentheses as diagnostics', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'redundant-parentheses-diagnostic.styio',
      text: '''
ready = true
blocked = false
price = 12.5
limit = 10.0
label = (ready)
label -> @stdout
when (price > limit) -> state expensive
when ((ready && !blocked)) -> state active
when !(ready && blocked) -> state guarded
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final redundant = diagnostics
        .where((diagnostic) => diagnostic.code == 'redundant-parentheses')
        .toList(growable: false);

    expect(
      redundant
          .map(
            (diagnostic) => document.text.substring(
              diagnostic.range.start,
              diagnostic.range.end,
            ),
          )
          .toList(growable: false),
      ['(ready)', '(price > limit)', '((ready && !blocked))'],
    );

    final fix = service
        .quickFixesForDiagnostic(document, redundant.first)
        .single;
    expect(fix.label, 'Remove redundant parentheses');
    expect(applyEdits(document.text, fix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
label = ready
label -> @stdout
when (price > limit) -> state expensive
when ((ready && !blocked)) -> state active
when !(ready && blocked) -> state guarded
''');
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

  test('reports and fixes redundant explicit local type annotations', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'redundant-type-annotation.styio',
      text: '''
price: f64 = 12.5
count: i64 = 3
wide: f64 = 3
price -> @stdout
count -> @stdout
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final redundant = diagnostics
        .where((diagnostic) => diagnostic.code == 'redundant-type-annotation')
        .toList(growable: false);

    expect(redundant.map((diagnostic) => diagnostic.message), [
      'Explicit type `f64` on `price` is redundant.',
      'Explicit type `i64` on `count` is redundant.',
    ]);
    expect(
      diagnostics.where(
        (diagnostic) =>
            diagnostic.code == 'initializer-type-mismatch' &&
            document.text.substring(
                  diagnostic.range.start,
                  diagnostic.range.end,
                ) ==
                '3',
      ),
      hasLength(1),
    );

    final fix = service
        .quickFixesForDiagnostic(document, redundant.first)
        .single;
    expect(fix.label, 'Remove redundant type annotation');
    expect(applyEdits(document.text, fix.edits), '''
price = 12.5
count: i64 = 3
wide: f64 = 3
price -> @stdout
count -> @stdout
''');
  });

  test('reports function parameter initializer type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'function-initializer-type-mismatch.styio',
      text: '''
fn copy(value: f64): f64 {
  label: string = value
  emit value
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
        );

    expect(mismatch.message, contains('expects `string`, got `f64`'));
    expect(
      document.text.substring(mismatch.range.start, mismatch.range.end),
      'value',
    );
  });

  test('uses hash function return types in current-file diagnostics', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'hash-function-return-type.styio',
      text: '''
#answer := () => {
  value = 42
  <| value
}
label: string = answer()
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
        );

    expect(mismatch.message, contains('expects `string`, got `i64`'));
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

  test('reports function parameter assignment type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'function-assignment-type-mismatch.styio',
      text: '''
fn copy(value: f64): f64 {
  label: string = "ready"
  label = value
  emit value
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'assignment-type-mismatch',
        );

    expect(mismatch.message, contains('expects `string`, got `f64`'));
    expect(
      document.text.substring(mismatch.range.start, mismatch.range.end),
      'value',
    );
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

  test('reports binary operator operand type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'binary-operator-type-mismatch.styio',
      text: '''
price = 12.5
ready = true
bad = price && ready
fn broken(value: f64): bool {
  emit true || value + 1
}
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'binary-operator-type-mismatch',
        )
        .toList(growable: false);

    expect(diagnostics, hasLength(2));
    final logicalAndMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`&&`'),
    );
    final logicalOrMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`||`'),
    );
    final leftOperandFix = service
        .quickFixesForDiagnostic(document, logicalAndMismatch)
        .singleWhere((fix) => fix.label == 'Compare left operand with zero');
    final rightOperandFix = service
        .quickFixesForDiagnostic(document, logicalOrMismatch)
        .singleWhere((fix) => fix.label == 'Compare right operand with zero');

    expect(
      diagnostics.map((diagnostic) => diagnostic.message),
      containsAll([
        'Operator `&&` cannot be applied to `f64` and `bool`.',
        'Operator `||` cannot be applied to `bool` and `f64`.',
      ]),
    );
    expect(applyEdits(document.text, leftOperandFix.edits), '''
price = 12.5
ready = true
bad = price != 0.0 && ready
fn broken(value: f64): bool {
  emit true || value + 1
}
''');
    expect(applyEdits(document.text, rightOperandFix.edits), '''
price = 12.5
ready = true
bad = price && ready
fn broken(value: f64): bool {
  emit true || value + 1 != 0.0
}
''');
  });

  test('reports binary operator mismatches inside branch returns', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'branch-binary-operator-type-mismatch.styio',
      text: '''
fn broken(flag: bool): bool {
  when flag -> state branch {
    emit true || 1
  }
  emit true
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'binary-operator-type-mismatch',
        );

    expect(mismatch.message, contains('`bool` and `i64`'));
  });

  test('reports and fixes unary operator operand type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unary-operator-type-mismatch.styio',
      text: '''
price = 12.5
ready = true
bad = !price
also = -ready
fn broken(value: f64): bool {
  emit !value
}
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where(
          (diagnostic) => diagnostic.code == 'unary-operator-type-mismatch',
        )
        .toList(growable: false);
    final notPriceMismatch = diagnostics.singleWhere(
      (diagnostic) =>
          diagnostic.message == 'Operator `!` cannot be applied to `f64`.' &&
          diagnostic.range.start == document.text.indexOf('!price'),
    );
    final minusReadyMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`-`'),
    );
    final notValueMismatch = diagnostics.singleWhere(
      (diagnostic) =>
          diagnostic.message == 'Operator `!` cannot be applied to `f64`.' &&
          diagnostic.range.start == document.text.indexOf('!value'),
    );
    final priceFix = service
        .quickFixesForDiagnostic(document, notPriceMismatch)
        .singleWhere((fix) => fix.label == 'Compare operand with zero');
    final valueFix = service
        .quickFixesForDiagnostic(document, notValueMismatch)
        .singleWhere((fix) => fix.label == 'Compare operand with zero');

    expect(diagnostics, hasLength(3));
    expect(
      service.quickFixesForDiagnostic(document, minusReadyMismatch),
      isEmpty,
    );
    expect(applyEdits(document.text, priceFix.edits), '''
price = 12.5
ready = true
bad = price == 0.0
also = -ready
fn broken(value: f64): bool {
  emit !value
}
''');
    expect(applyEdits(document.text, valueFix.edits), '''
price = 12.5
ready = true
bad = !price
also = -ready
fn broken(value: f64): bool {
  emit value == 0.0
}
''');
  });

  test('reports unary operator mismatches inside branch returns', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'branch-unary-operator-type-mismatch.styio',
      text: '''
fn broken(value: f64): bool {
  when value > 0 -> state branch {
    emit !value
  }
  emit true
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'unary-operator-type-mismatch',
        );

    expect(mismatch.message, 'Operator `!` cannot be applied to `f64`.');
    expect(
      document.text.substring(mismatch.range.start, mismatch.range.end),
      '!',
    );
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

  test('reports function parameter when condition type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'function-condition-type-mismatch.styio',
      text: '''
fn priced(value: f64) {
  when value -> state active
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'condition-type-mismatch',
        );

    expect(mismatch.message, '`when` condition expects `bool`, got `f64`.');
    expect(
      document.text.substring(mismatch.range.start, mismatch.range.end),
      'value',
    );
  });

  test('reports and fixes task when condition type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'task-condition-type-mismatch.styio',
      text: '''
load = ||> {
  count = 1
  when count -> <| 1
}
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

    expect(mismatch.message, '`when` condition expects `bool`, got `i64`.');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  count = 1
  when count != 0 -> <| 1
}
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

  test('keeps one-line return expression ranges inside function braces', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'one-line-return-type-mismatch.styio',
      text: 'fn price(): f64 { emit 3 }\n',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'return-type-mismatch');
    final literalFix = service
        .quickFixesForDiagnostic(document, mismatch)
        .singleWhere(
          (fix) => fix.label == 'Change return expression to f64 literal',
        );

    expect(
      document.text.substring(mismatch.range.start, mismatch.range.end),
      '3',
    );
    expect(
      applyEdits(document.text, literalFix.edits),
      'fn price(): f64 { emit 3.0 }\n',
    );
  });

  test('reports branch return type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'branch-return-type-mismatch.styio',
      text: '''
fn ready(flag: bool): i64 {
  when flag -> state branch {
    emit true
  }
  emit 1
}
''',
      revision: 0,
    );

    final mismatches = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'return-type-mismatch')
        .toList(growable: false);

    expect(mismatches, hasLength(1));
    expect(mismatches.single.message, contains('expects `i64`, got `bool`'));
    expect(
      document.text.substring(
        mismatches.single.range.start,
        mismatches.single.range.end,
      ),
      'true',
    );

    final fixes = service.quickFixesForDiagnostic(document, mismatches.single);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change return expression to i64 literal',
    );

    expect(
      fixes.map((fix) => fix.label),
      isNot(contains('Change function `ready` return type to bool')),
    );
    expect(applyEdits(document.text, literalFix.edits), '''
fn ready(flag: bool): i64 {
  when flag -> state branch {
    emit 1
  }
  emit 1
}
''');
  });

  test('does not treat task value returns as function returns', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'task-return-isolated-from-function.styio',
      text: '''
fn outer(): i64 {
  job = ||> { <| "done" }
  emit 1
}
''',
      revision: 0,
    );

    final codes = service
        .analyzeDocument(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code);

    expect(codes, isNot(contains('return-type-mismatch')));
  });

  test('removes unreachable code through quick fix', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unreachable-code-quick-fix.styio',
      text: '''
fn stop(value: f64): f64 {
  emit value
  next = value + 1.0
}
''',
      revision: 0,
    );

    final unreachable = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'unreachable-code');
    final fix = service.quickFixesForDiagnostic(document, unreachable).single;

    expect(fix.label, 'Remove unreachable code');
    expect(applyEdits(document.text, fix.edits), '''
fn stop(value: f64): f64 {
  emit value
}
''');
  });

  test('inserts missing function return through quick fix', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'missing-function-return-quick-fix.styio',
      text: '''
fn price(): f64 {
  total = 1.0
}
''',
      revision: 0,
    );

    final missingReturn = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'missing-function-return',
        );
    final fix = service.quickFixesForDiagnostic(document, missingReturn).single;

    expect(fix.label, 'Insert return value');
    expect(applyEdits(document.text, fix.edits), '''
fn price(): f64 {
  total = 1.0
  emit 0.0
}
''');
  });

  test('inserts missing task return through quick fix', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'missing-task-return-quick-fix.styio',
      text: '''
load = ||> {
}
?| load -> result: i64 | 0
result -> @stdout
''',
      revision: 0,
    );

    final missingReturn = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'missing-task-return');
    final fix = service.quickFixesForDiagnostic(document, missingReturn).single;

    expect(fix.label, 'Insert task return value');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  <| 0
}
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('inserts conditional task return defaults through quick fix', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'conditional-task-return-quick-fix.styio',
      text: '''
load = ||> {
  ready = false
  when ready -> <| 1
}
?| load -> result: i64 | 0
result -> @stdout
''',
      revision: 0,
    );

    final conditionalReturn = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'conditional-task-return',
        );
    final fix = service
        .quickFixesForDiagnostic(document, conditionalReturn)
        .single;

    expect(fix.label, 'Insert task return value');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  ready = false
  when ready -> <| 1
  <| 0
}
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('inserts missing task return values through quick fix', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'missing-task-return-value-quick-fix.styio',
      text: '''
load = ||> {
  <|
}
?| load -> result: i64 | 0
result -> @stdout
''',
      revision: 0,
    );

    final missingReturnValue = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'missing-task-return-value',
        );
    final fix = service
        .quickFixesForDiagnostic(document, missingReturnValue)
        .single;

    expect(fix.label, 'Insert task return expression');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  <| 0
}
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('creates unresolved task return values through quick fix', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unresolved-task-return-value-quick-fix.styio',
      text: '''
load = ||> {
  <| value
}
?| load -> result: i64 | 0
result -> @stdout
''',
      revision: 0,
    );

    final unresolvedReturnValue = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'unresolved-task-return-value',
        );
    final fix = service
        .quickFixesForDiagnostic(document, unresolvedReturnValue)
        .single;

    expect(fix.label, 'Create task local binding `value`');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  value = 0
  <| value
}
?| load -> result: i64 | 0
result -> @stdout
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

  test('reports function parameter call argument type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'function-argument-type-mismatch.styio',
      text: '''
fn label(text: string) {
  emit text
}

fn caller(value: f64) {
  label(value)
}
''',
      revision: 0,
    );

    final mismatch = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'argument-type-mismatch',
        );

    expect(mismatch.message, contains('expects `string`, got `f64`'));
    expect(
      document.text.substring(mismatch.range.start, mismatch.range.end),
      'value',
    );
  });

  test('does not leak function locals into top-level call argument types', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'function-local-call-scope.styio',
      text: '''
fn leak() {
  local = "internal"
}

fn expectNumber(value: f64) {
  emit value
}

expectNumber(local)
''',
      revision: 0,
    );

    final codes = service
        .analyzeDocument(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code);

    expect(codes, isNot(contains('argument-type-mismatch')));
    expect(codes, contains('unresolved-reference'));
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

  test('reports and removes unused await result bindings', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unused-await-result-binding.styio',
      text: '''
load = ||> { <| "ready" }
?| load -> result: string
done = true
done -> @stdout
''',
      revision: 0,
    );

    final unused = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'unused-local-symbol');

    expect(
      document.text.substring(unused.range.start, unused.range.end),
      'result: string',
    );

    final quickFix = service.quickFixesForDiagnostic(document, unused).single;
    expect(quickFix.label, 'Remove unused await result binding');
    expect(applyEdits(document.text, quickFix.edits), '''
load = ||> { <| "ready" }
done = true
done -> @stdout
''');
  });

  test('reports and removes unused local task declarations', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unused-local-task.styio',
      text: '''
#outer := () => {
  job = ||> { <| 1 }
  <| 1
}

exported = ||> { <| 2 }
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'unused-local-symbol')
        .toList(growable: false);

    expect(diagnostics, hasLength(1));
    expect(
      document.text.substring(
        diagnostics.single.range.start,
        diagnostics.single.range.end,
      ),
      'job = ||> { <| 1 }',
    );

    final quickFix = service
        .quickFixesForDiagnostic(document, diagnostics.single)
        .single;
    expect(quickFix.label, 'Remove unused task declaration');
    expect(applyEdits(document.text, quickFix.edits), '''
#outer := () => {
  <| 1
}

exported = ||> { <| 2 }
''');
  });

  test('removes unused multiline local task declarations as a block', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unused-multiline-local-task.styio',
      text: '''
#outer := () => {
  job = ||> {
    <| 1
  }
  live = ||> { <| 2 }
  ?| live -> result: i64
  <| result
}

exported = ||> {
  <| 2
}
''',
      revision: 0,
    );

    final diagnostics = service
        .analyzeDocument(document)
        .diagnostics
        .where((diagnostic) => diagnostic.code == 'unused-local-symbol')
        .toList(growable: false);

    expect(diagnostics, hasLength(1));
    expect(diagnostics.single.message, contains('job'));

    final quickFix = service
        .quickFixesForDiagnostic(document, diagnostics.single)
        .single;
    expect(quickFix.label, 'Remove unused task declaration');
    expect(applyEdits(document.text, quickFix.edits), '''
#outer := () => {
  live = ||> { <| 2 }
  ?| live -> result: i64
  <| result
}

exported = ||> {
  <| 2
}
''');
  });

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

  test('prefers compiler duplicate diagnostics over generic duplicates', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'duplicate-function.styio',
      text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn blend(value: f64): f64 {
  emit value
}
''',
      revision: 0,
    );

    final codes = service
        .analyzeDocument(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code);

    expect(codes, contains('duplicate-function-declaration'));
    expect(codes, isNot(contains('duplicate-declaration')));
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

  test('reports and renames local declarations that shadow parameters', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'parameter-shadowing.styio',
      text: '''
fn normalize(value: f64): f64 {
  value = 1.0
  emit value
}
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'parameter-shadowing');
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(diagnostic.message, contains('shadows a function parameter'));
    expect(fix.label, 'Rename shadowing declaration to `value2`');
    expect(fix.edits.map((edit) => edit.newText), ['value2', 'value2']);
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
          (diagnostic) => diagnostic.code == 'duplicate-parameter-declaration',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Rename duplicate declaration to `value2`');
    expect(fix.edits.map((edit) => edit.newText), ['value2', 'value2']);
  });

  test('removes duplicate resource and task declarations safely', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'duplicate-runtime-symbols.styio',
      text: '''
@prices : f64|..2| := {}
@prices : string|..2| := {}
load = ||> { <| 1 }
load = ||> {
  <| 2
}
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final resource = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'duplicate-resource-declaration',
    );
    final task = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'duplicate-task-declaration',
    );
    final resourceFix = service
        .quickFixesForDiagnostic(document, resource)
        .single;
    final taskFix = service.quickFixesForDiagnostic(document, task).single;

    expect(resourceFix.label, 'Remove duplicate resource declaration');
    expect(taskFix.label, 'Remove duplicate task declaration');
    expect(applyEdits(document.text, resourceFix.edits), '''
@prices : f64|..2| := {}
load = ||> { <| 1 }
load = ||> {
  <| 2
}
''');
    expect(applyEdits(document.text, taskFix.edits), '''
@prices : f64|..2| := {}
@prices : string|..2| := {}
load = ||> { <| 1 }
''');
  });

  test('creates resources and tasks from unresolved Styio runtime usage', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'create-runtime-symbols.styio',
      text: '''
price = 1.0
price -> @prices
?| load -> result: string
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final resource = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'unresolved-resource',
    );
    final task = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'unresolved-task-await',
    );
    final resourceFix = service
        .quickFixesForDiagnostic(document, resource)
        .single;
    final taskFix = service.quickFixesForDiagnostic(document, task).single;

    expect(resourceFix.label, 'Create resource `@prices`');
    expect(taskFix.label, 'Create task `load`');
    expect(applyEdits(document.text, resourceFix.edits), '''
@prices : f64|..1| := {}
price = 1.0
price -> @prices
?| load -> result: string
''');
    expect(applyEdits(document.text, taskFix.edits), '''
load = ||> {
  <| ""
}

price = 1.0
price -> @prices
?| load -> result: string
''');
  });

  test('removes writes to read-only Styio resources', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'read-only-resource-write.styio',
      text: '''
price = 1
price -> @stdin
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'read-only-resource-write',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Remove read-only resource write');
    expect(applyEdits(document.text, fix.edits), '''
price = 1
''');
  });

  test('fixes current-file resource write and await result mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'runtime-type-mismatches.styio',
      text: '''
@prices : f64|..1| := {}
load = ||> { <| "ready" }
label = "bad"
label -> @prices
?| load -> result: i64
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final resource = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'resource-write-type-mismatch',
    );
    final await = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'await-result-type-mismatch',
    );
    final resourceFix = service
        .quickFixesForDiagnostic(document, resource)
        .single;
    final awaitFix = service.quickFixesForDiagnostic(document, await).single;

    expect(resourceFix.label, 'Change resource write value to f64 literal');
    expect(awaitFix.label, 'Change await binding type to string');
    expect(applyEdits(document.text, resourceFix.edits), '''
@prices : f64|..1| := {}
load = ||> { <| "ready" }
label = "bad"
0.0 -> @prices
?| load -> result: i64
''');
    expect(applyEdits(document.text, awaitFix.edits), '''
@prices : f64|..1| := {}
load = ||> { <| "ready" }
label = "bad"
label -> @prices
?| load -> result: string
''');
  });

  test('fixes await fallback type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'await-fallback-type-mismatch.styio',
      text: '''
load = ||> { <| 42 }
?| load -> result: i64 | "missing"
result -> @stdout
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'await-fallback-type-mismatch',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(
      document.text.substring(diagnostic.range.start, diagnostic.range.end),
      '"missing"',
    );
    expect(fix.label, 'Change await fallback to i64 literal');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> { <| 42 }
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('fixes task return type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'task-return-type-mismatch.styio',
      text: '''
load = ||> {
  <| 42
  <| "bad"
}
?| load -> result: i64 | 0
result -> @stdout
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'task-return-type-mismatch',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(
      document.text.substring(diagnostic.range.start, diagnostic.range.end),
      '"bad"',
    );
    expect(fix.label, 'Change task return expression to i64 literal');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  <| 42
  <| 0
}
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('fixes conditional task return type mismatches', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'conditional-task-return-type-mismatch.styio',
      text: '''
load = ||> {
  ready = false
  when ready -> <| "bad"
  <| 42
}
?| load -> result: i64 | 0
result -> @stdout
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'task-return-type-mismatch',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(
      document.text.substring(diagnostic.range.start, diagnostic.range.end),
      '"bad"',
    );
    expect(fix.label, 'Change task return expression to i64 literal');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  ready = false
  when ready -> <| 0
  <| 42
}
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('fixes invalid task return expressions from await context', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'invalid-task-return-expression.styio',
      text: '''
load = ||> {
  count = 1
  <| count && true
}
?| load -> result: bool | false
result -> @stdout
''',
      revision: 0,
    );

    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'invalid-task-return-expression',
        );
    final fix = service.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Change task return expression to bool literal');
    expect(applyEdits(document.text, fix.edits), '''
load = ||> {
  count = 1
  <| false
}
?| load -> result: bool | false
result -> @stdout
''');
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

  test('scopes current-file symbol completions by function body', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'scoped-completion.styio',
      text: '''
fn sample(price: f64) {
  localValue = price
  pr
  lo
}

lo
''',
      revision: 0,
    );

    final insideParameterLabels = service
        .completeAt(document, document.text.indexOf('  pr') + 4)
        .map((item) => item.label)
        .toSet();
    final insideLocalLabels = service
        .completeAt(document, document.text.indexOf('  lo') + 4)
        .map((item) => item.label)
        .toSet();
    final topLevelLabels = service
        .completeAt(document, document.text.lastIndexOf('lo') + 2)
        .map((item) => item.label)
        .toSet();

    expect(insideParameterLabels, contains('price'));
    expect(insideLocalLabels, contains('localValue'));
    expect(topLevelLabels, isNot(contains('price')));
    expect(topLevelLabels, isNot(contains('localValue')));
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

  test('offers expression negation and when postfix completions', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'postfix-control-completion.styio',
      text: '''
ready.no
(price > 0).wh
''',
      revision: 0,
    );

    final notCompletion = service
        .completeAt(document, document.text.indexOf('no') + 2)
        .singleWhere((item) => item.label == '.not');
    final whenCompletion = service
        .completeAt(document, document.text.indexOf('wh') + 2)
        .singleWhere((item) => item.label == '.when');

    expect(notCompletion.kind, CompletionItemKind.snippet);
    expect(notCompletion.insertText, '!ready');
    expect(
      document.text.substring(
        notCompletion.replacementRange!.start,
        notCompletion.replacementRange!.end,
      ),
      'ready.no',
    );
    expect(whenCompletion.insertText, 'when (price > 0) -> state next_state');
    expect(
      document.text.substring(
        whenCompletion.replacementRange!.start,
        whenCompletion.replacementRange!.end,
      ),
      '(price > 0).wh',
    );
  });

  test('postfix completions scan quoted and nested operands', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'postfix-nested-completion.styio',
      text: '''
"ready.value".no
call("a.b", nested(value)).no
''',
      revision: 0,
    );

    final stringNot = service
        .completeAt(document, document.text.indexOf('no') + 2)
        .singleWhere((item) => item.label == '.not');
    final callNot = service
        .completeAt(document, document.text.lastIndexOf('no') + 2)
        .singleWhere((item) => item.label == '.not');

    expect(stringNot.insertText, '!("ready.value")');
    expect(callNot.insertText, '!(call("a.b", nested(value)))');
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

  test('describes type names and standard resources in hover payloads', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'hover-type-resource.styio',
      text: 'price: f64 = 1\nstdout\n',
      revision: 0,
    );

    final typeHover = service.hoverAt(document, document.text.indexOf('f64'));
    final resourceHover = service.hoverAt(
      document,
      document.text.indexOf('stdout'),
    );

    expect(typeHover?.markdown, contains('Type `f64`'));
    expect(resourceHover?.markdown, contains('Resource identifier `stdout`'));
  });

  test('removes unreachable last-line and single-line ranges', () {
    const service = SimpleStyioLanguageService();
    const lastLineDocument = DocumentState(
      documentId: 'unreachable-last-line.styio',
      text: 'value = 1\nstale = 2',
      revision: 0,
    );
    const singleLineDocument = DocumentState(
      documentId: 'unreachable-single-line.styio',
      text: 'stale = 2',
      revision: 0,
    );
    final lastLineStart = lastLineDocument.text.indexOf('stale');

    final lastLineFix = service
        .quickFixesForDiagnostic(
          lastLineDocument,
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unreachable-code',
            message: 'Unreachable last line.',
            range: SourceRange(
              start: lastLineStart,
              end: lastLineDocument.length,
            ),
          ),
        )
        .single;
    final singleLineFix = service
        .quickFixesForDiagnostic(
          singleLineDocument,
          const Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unreachable-code',
            message: 'Unreachable only line.',
            range: SourceRange(start: 0, end: 9),
          ),
        )
        .single;

    expect(applyEdits(lastLineDocument.text, lastLineFix.edits), 'value = 1');
    expect(applyEdits(singleLineDocument.text, singleLineFix.edits), '');
  });
}
