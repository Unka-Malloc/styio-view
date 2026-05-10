import 'package:flutter_test/flutter_test.dart';
import 'package:styio_view_app/src/language/language_contract.dart';
import 'package:styio_view_app/src/language/styio_symbol_index.dart';
import 'package:styio_view_app/src/language/styio_syntax_highlighter.dart';

void main() {
  const source = '''
@import { styio/core }
@ma5 : f64|..2| := {
  @file("prices.txt") >> #(p) => {
    p[avg, 5] -> @ma5
  }
}
job = ||> { <| 42 }
?| job -> answer: i64 | 0
answer -> @stdout
''';

  test('indexes styio declarations and current-file references', () {
    const highlighter = StyioSyntaxHighlighter();
    const index = StyioSymbolIndex();

    final snapshot = index.build(highlighter.tokenize(source));
    final symbolKinds = {
      for (final symbol in snapshot.symbols) symbol.name: symbol.kind,
    };

    expect(symbolKinds['ma5'], SymbolKind.resource);
    expect(symbolKinds['p'], SymbolKind.parameter);
    expect(symbolKinds['job'], SymbolKind.variable);
    expect(symbolKinds['answer'], SymbolKind.variable);

    final ma5References = snapshot.references
        .where((reference) => reference.name == 'ma5')
        .toList(growable: false);
    expect(ma5References.length, 2);
    expect(ma5References.any((reference) => reference.isDeclaration), isTrue);
    expect(ma5References.any((reference) => !reference.isDeclaration), isTrue);
    expect(
      ma5References.any(
        (reference) => reference.access == ReferenceAccess.write,
      ),
      isTrue,
    );

    final jobReferences = snapshot.references
        .where((reference) => reference.name == 'job')
        .toList(growable: false);
    expect(
      jobReferences.any(
        (reference) => reference.access == ReferenceAccess.read,
      ),
      isTrue,
    );
  });

  test('resolves definitions and references from usage tokens', () {
    const index = StyioSymbolIndex();

    final parameterUseOffset = source.indexOf('p[avg');
    final parameterDefinition = index.definitionAt(source, parameterUseOffset);
    expect(parameterDefinition?.symbol.name, 'p');
    expect(parameterDefinition?.symbol.kind, SymbolKind.parameter);

    final resourceUseOffset = source.lastIndexOf('ma5');
    final resourceReferences = index.referencesAt(source, resourceUseOffset);
    expect(resourceReferences.length, 2);
    expect(
      resourceReferences.every(
        (reference) =>
            reference.targetRange.start ==
            resourceReferences.first.targetRange.start,
      ),
      isTrue,
    );
  });

  test('builds rename edits from resolved references', () {
    const index = StyioSymbolIndex();

    final resourceUseOffset = source.lastIndexOf('ma5');
    final plan = index.renameAt(source, resourceUseOffset, 'movingAverage');

    expect(plan?.target.name, 'ma5');
    expect(plan?.newName, 'movingAverage');
    expect(plan?.edits.length, 2);
    expect(plan?.hasConflicts, isFalse);
    expect(
      plan?.edits.every((edit) => edit.newText == 'movingAverage'),
      isTrue,
    );
    expect(index.renameAt(source, resourceUseOffset, 'f64'), isNull);
    expect(index.renameAt(source, resourceUseOffset, 'fn'), isNull);
    expect(index.renameAt(source, resourceUseOffset, 'not-valid'), isNull);
  });

  test('reports current-file rename conflicts before applying edits', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 1
total = price
total -> @stdout
''';

    final plan = index.renameAt(source, source.indexOf('price'), 'total');

    expect(plan?.target.name, 'price');
    expect(plan?.edits.length, 2);
    expect(plan?.hasConflicts, isTrue);
    expect(plan?.conflicts.single.message, contains('already declares'));
    expect(
      source.substring(
        plan!.conflicts.single.range.start,
        plan.conflicts.single.range.end,
      ),
      'total',
    );
  });

  test('builds safe delete edits only when a variable has no usages', () {
    const index = StyioSymbolIndex();
    const source = '''
used = 1
unused = 2
used -> @stdout
''';

    final unusedPlan = index.safeDeleteAt(source, source.indexOf('unused'));
    expect(unusedPlan?.target.name, 'unused');
    expect(unusedPlan?.hasConflicts, isFalse);
    expect(unusedPlan?.edits.single.newText, '');
    expect(
      source.substring(
        unusedPlan!.edits.single.range.start,
        unusedPlan.edits.single.range.end,
      ),
      'unused = 2\n',
    );

    final usedPlan = index.safeDeleteAt(source, source.indexOf('used'));
    expect(usedPlan?.hasConflicts, isTrue);
    expect(usedPlan?.edits, isEmpty);
    expect(usedPlan?.conflicts.single.message, contains('still used'));
  });

  test('builds inline variable edits from declaration initializers', () {
    const index = StyioSymbolIndex();
    const source = '''
seed = 40 + 2
value = seed
seed -> @stdout
''';

    final plan = index.inlineVariableAt(source, source.indexOf('seed'));

    expect(plan?.target.name, 'seed');
    expect(plan?.initializerText, '40 + 2');
    expect(plan?.references.length, 2);
    expect(plan?.hasConflicts, isFalse);
    expect(plan?.edits.length, 3);
    expect(
      source.substring(plan!.edits.last.range.start, plan.edits.last.range.end),
      'seed = 40 + 2\n',
    );
    expect(
      plan.edits.take(2).every((edit) => edit.newText == '40 + 2'),
      isTrue,
    );
  });

  test('blocks inline variable when no initializer is available', () {
    const index = StyioSymbolIndex();
    const source = '''
let pending
pending -> @stdout
''';

    final plan = index.inlineVariableAt(source, source.indexOf('pending'));

    expect(plan?.hasConflicts, isTrue);
    expect(plan?.edits, isEmpty);
    expect(plan?.conflicts.single.message, contains('initializer'));
  });

  test('builds introduce variable edits from a selected expression', () {
    const index = StyioSymbolIndex();
    const source = 'value = 40 + 2\n';
    final start = source.indexOf('40 + 2');
    final plan = index.introduceVariable(
      source,
      SourceRange(start: start, end: start + '40 + 2'.length),
      'answer',
    );

    expect(plan?.variableName, 'answer');
    expect(plan?.expressionText, '40 + 2');
    expect(plan?.hasConflicts, isFalse);
    expect(plan?.edits.length, 2);
    expect(plan?.edits.first.newText, 'answer = 40 + 2\n');
    expect(plan?.edits.last.newText, 'answer');
  });

  test('reports introduce variable conflicts before applying edits', () {
    const index = StyioSymbolIndex();
    const source = 'answer = 1\nvalue = 40 + 2\n';
    final start = source.indexOf('40 + 2');
    final plan = index.introduceVariable(
      source,
      SourceRange(start: start, end: start + '40 + 2'.length),
      'answer',
    );

    expect(plan?.hasConflicts, isTrue);
    expect(plan?.edits, isEmpty);
    expect(plan?.conflicts.single.message, contains('already declares'));
  });

  test('builds extract function edits from a selected expression', () {
    const index = StyioSymbolIndex();
    const source = 'fn main(user) {\n  value = user + 1\n}\n';
    final start = source.indexOf('user + 1');
    final plan = index.extractFunction(
      source,
      SourceRange(start: start, end: start + 'user + 1'.length),
      'computeValue',
    );

    expect(plan?.functionName, 'computeValue');
    expect(plan?.parameters, ['user']);
    expect(plan?.callText, 'computeValue(user)');
    expect(plan?.hasConflicts, isFalse);
    expect(plan?.edits.length, 2);
    expect(
      plan?.functionText,
      '#computeValue := (user) => {\n  <| user + 1\n}\n\n',
    );
    expect(plan?.edits.last.newText, 'computeValue(user)');
  });

  test('builds extract function duplicate occurrence replacements', () {
    const index = StyioSymbolIndex();
    const source = '''
fn main(user) {
  first = user + 1
  second = user + 1
}
''';
    final start = source.indexOf('user + 1');
    final plan = index.extractFunction(
      source,
      SourceRange(start: start, end: start + 'user + 1'.length),
      'computeValue',
    );

    expect(plan?.hasConflicts, isFalse);
    expect(plan?.duplicateOccurrences.length, 1);
    expect(
      source.substring(
        plan!.duplicateOccurrences.single.start,
        plan.duplicateOccurrences.single.end,
      ),
      'user + 1',
    );
    expect(plan.edits.length, 3);
    expect(
      plan.edits.skip(1).every((edit) => edit.newText == plan.callText),
      isTrue,
    );
  });

  test('builds extract function edits from selected statements', () {
    const index = StyioSymbolIndex();
    const source = 'fn main(user) {\n  value = user\n}\n';
    final start = source.indexOf('value = user');
    final plan = index.extractFunction(
      source,
      SourceRange(start: start, end: start + 'value = user'.length),
      'emitValue',
    );

    expect(plan?.parameters, ['user']);
    expect(plan?.hasConflicts, isFalse);
    expect(
      plan?.functionText,
      '#emitValue := (user) => {\n  value = user\n}\n\n',
    );
    expect(plan?.edits.last.newText, 'emitValue(user)');
  });

  test('reports extract function conflicts before applying edits', () {
    const index = StyioSymbolIndex();
    const source = 'fn computeValue() {}\nvalue = user + 1\n';
    final start = source.indexOf('user + 1');
    final plan = index.extractFunction(
      source,
      SourceRange(start: start, end: start + 'user + 1'.length),
      'computeValue',
    );

    expect(plan?.hasConflicts, isTrue);
    expect(plan?.edits, isEmpty);
    expect(plan?.conflicts.single.message, contains('already declares'));
  });

  test(
    'builds change signature edits for function rename and parameter reorder',
    () {
      const index = StyioSymbolIndex();
      const source = '''
fn blend(left: f64, right: f64) {
  result = left + right
}
value = blend(price, tax)
again = blend(total, fee)
''';

      final plan = index.changeSignature(
        source,
        source.indexOf('blend'),
        newName: 'combine',
        parameters: const [
          ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
          ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
        ],
      );

      expect(plan?.hasConflicts, isFalse);
      expect(plan?.originalName, 'blend');
      expect(plan?.originalParameters.map((parameter) => parameter.name), [
        'left',
        'right',
      ]);
      expect(plan?.edits.map((edit) => edit.newText), contains('combine'));
      expect(
        plan?.edits.map((edit) => edit.newText),
        contains('right: f64, left: f64'),
      );
      expect(plan?.edits.map((edit) => edit.newText), contains('tax, price'));
      expect(plan?.edits.map((edit) => edit.newText), contains('fee, total'));
    },
  );

  test('keeps named call arguments stable during parameter reorder', () {
    String applyEdits(String text, Iterable<FormattingEdit> edits) {
      var nextText = text;
      final ordered = edits.toList(growable: false)
        ..sort((left, right) => right.range.start.compareTo(left.range.start));
      for (final edit in ordered) {
        nextText = nextText.replaceRange(
          edit.range.start,
          edit.range.end,
          edit.newText,
        );
      }
      return nextText;
    }

    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64) {
  result = left + right
}
value = blend(right: tax, left: price)
again = blend(total, fee)
''';

    final plan = index.changeSignature(
      source,
      source.indexOf('blend'),
      newName: 'combine',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
      ],
    );

    expect(plan?.hasConflicts, isFalse);
    expect(applyEdits(source, plan!.edits), '''
fn combine(right: f64, left: f64) {
  result = left + right
}
value = combine(right: tax, left: price)
again = combine(fee, total)
''');
  });

  test(
    'builds change signature edits for parameter rename in function body',
    () {
      const index = StyioSymbolIndex();
      const source = '''
fn blend(left: f64, right: f64) {
  result = left + right
}
''';

      final plan = index.changeSignature(
        source,
        source.indexOf('blend'),
        newName: 'blend',
        parameters: const [
          ChangeSignatureParameterUpdate(originalName: 'left', name: 'lhs'),
          ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
        ],
      );

      expect(plan?.hasConflicts, isFalse);
      expect(
        plan?.edits.map((edit) => edit.newText),
        contains('lhs: f64, right: f64'),
      );
      expect(plan?.edits.map((edit) => edit.newText), contains('lhs'));
    },
  );

  test('renames named call argument labels during parameter rename', () {
    String applyEdits(String text, Iterable<FormattingEdit> edits) {
      var nextText = text;
      final ordered = edits.toList(growable: false)
        ..sort((left, right) => right.range.start.compareTo(left.range.start));
      for (final edit in ordered) {
        nextText = nextText.replaceRange(
          edit.range.start,
          edit.range.end,
          edit.newText,
        );
      }
      return nextText;
    }

    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64) {
  result = left + right
}
value = blend(left: price, right: tax)
''';

    final plan = index.changeSignature(
      source,
      source.indexOf('blend'),
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'lhs'),
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
      ],
    );

    expect(plan?.hasConflicts, isFalse);
    expect(applyEdits(source, plan!.edits), '''
fn blend(lhs: f64, right: f64) {
  result = lhs + right
}
value = blend(lhs: price, right: tax)
''');
  });

  test('reports change signature conflicts for call arity mismatch', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64) {
  result = left + right
}
value = blend(price)
''';

    final plan = index.changeSignature(
      source,
      source.indexOf('blend'),
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
      ],
    );

    expect(plan?.hasConflicts, isTrue);
    expect(plan?.edits, isEmpty);
    expect(plan?.conflicts.single.message, contains('expected 2'));
  });

  test('resolves parameter info from a function call argument list', () {
    const index = StyioSymbolIndex();
    const source = '''
/// Blends price and tax inputs.
/// @param left Base price before tax.
/// @param right Tax component to add.
fn blend(left: f64, right: f64 = 0.0) {
  emit left
}
value = blend(price, tax)
''';

    final info = index.parameterInfoAt(source, source.lastIndexOf('tax') + 1);

    expect(info?.callableName, 'blend');
    expect(info?.signature, 'fn blend(left: f64, right: f64 = 0.0)');
    expect(info?.documentation, 'Blends price and tax inputs.');
    expect(info?.activeParameterIndex, 1);
    expect(info?.activeParameter?.displayText, 'right: f64 = 0.0');
    expect(info?.activeParameter?.defaultValue, '0.0');
    expect(info?.activeParameter?.documentation, 'Tax component to add.');
    expect(info?.parameters.map((parameter) => parameter.name), [
      'left',
      'right',
    ]);
    expect(index.parameterInfoAt(source, source.indexOf('left:')), isNull);
  });

  test('uses default parameters for signature display and call arity', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64 = 0.0) {
  emit left + right
}
price = 1.0
value = blend(price)
''';

    final info = index.parameterInfoAt(
      source,
      source.lastIndexOf('price)') + 1,
    );
    final issues = index.callArgumentIssues(source);

    expect(info?.signature, 'fn blend(left: f64, right: f64 = 0.0)');
    expect(info?.parameters.last.displayText, 'right: f64 = 0.0');
    expect(info?.parameters.last.defaultValue, '0.0');
    expect(issues, isEmpty);
  });

  test('maps named call arguments to signature parameters', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
value = blend(right: tax, left: price)
''';

    final rightInfo = index.parameterInfoAt(
      source,
      source.lastIndexOf('tax') + 1,
    );
    final leftInfo = index.parameterInfoAt(
      source,
      source.lastIndexOf('price)') + 1,
    );

    expect(rightInfo?.activeParameterIndex, 1);
    expect(rightInfo?.activeParameter?.name, 'right');
    expect(leftInfo?.activeParameterIndex, 0);
    expect(leftInfo?.activeParameter?.name, 'left');
    expect(index.parameterNameHints(source), isEmpty);
    expect(index.callArgumentIssues(source), isEmpty);
  });

  test('offers named argument completions for current function calls', () {
    const index = StyioSymbolIndex();
    const source = '''
/// Blends price and tax inputs.
/// @param left Base price before tax.
/// @param right Tax component to add.
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
value = blend(le)
again = blend(left: price, ri)
empty = blend(price, )
''';

    final leftCompletion = index
        .namedArgumentCompletionsAt(source, source.indexOf('le)') + 2)
        .singleWhere((item) => item.label == 'left:');
    final rightLabels = index
        .namedArgumentCompletionsAt(source, source.indexOf('ri)') + 2)
        .map((item) => item.label)
        .toList(growable: false);
    final emptyLabels = index
        .namedArgumentCompletionsAt(
          source,
          source.indexOf('empty = blend(price, ') +
              'empty = blend(price, '.length,
        )
        .map((item) => item.label)
        .toList(growable: false);

    expect(leftCompletion.insertText, 'left: ');
    expect(leftCompletion.detail, contains('blend'));
    expect(leftCompletion.detail, contains('f64'));
    expect(leftCompletion.documentation, 'Base price before tax.');
    expect(
      source.substring(
        leftCompletion.replacementRange!.start,
        leftCompletion.replacementRange!.end,
      ),
      'le',
    );
    expect(rightLabels, ['right:']);
    expect(emptyLabels, ['right:']);
    expect(
      index.namedArgumentCompletionsAt(
        source,
        source.indexOf('left: price') + 'left:'.length,
      ),
      isEmpty,
    );
  });

  test('builds add-argument-names edits for current function calls', () {
    String applyEdits(String text, Iterable<FormattingEdit> edits) {
      var nextText = text;
      final ordered = edits.toList(growable: false)
        ..sort((left, right) => right.range.start.compareTo(left.range.start));
      for (final edit in ordered) {
        nextText = nextText.replaceRange(
          edit.range.start,
          edit.range.end,
          edit.newText,
        );
      }
      return nextText;
    }

    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, right: tax, factor)
already = blend(left: price, right: tax, scale: factor)
''';

    final plan = index.addArgumentNamesAt(
      source,
      source.indexOf('blend(price') + 'blend(price'.length,
    );

    expect(plan?.callableName, 'blend');
    expect(plan?.edits.length, 2);
    expect(applyEdits(source, plan!.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(left: price, right: tax, scale: factor)
already = blend(left: price, right: tax, scale: factor)
''');
    expect(
      index.addArgumentNamesAt(source, source.indexOf('already = blend(left:')),
      isNull,
    );
  });

  test('builds add-argument-name edit for the current argument', () {
    String applyEdits(String text, Iterable<FormattingEdit> edits) {
      var nextText = text;
      final ordered = edits.toList(growable: false)
        ..sort((left, right) => right.range.start.compareTo(left.range.start));
      for (final edit in ordered) {
        nextText = nextText.replaceRange(
          edit.range.start,
          edit.range.end,
          edit.newText,
        );
      }
      return nextText;
    }

    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, right: tax, factor)
duplicate = blend(price, left: tax)
''';

    final firstPlan = index.addArgumentNameAt(
      source,
      source.indexOf('price, right') + 1,
    );
    final factorPlan = index.addArgumentNameAt(
      source,
      source.indexOf('factor)') + 1,
    );

    expect(firstPlan?.callableName, 'blend');
    expect(firstPlan?.parameterName, 'left');
    expect(firstPlan?.edit.newText, 'left: price');
    expect(factorPlan?.parameterName, 'scale');
    expect(factorPlan?.edit.newText, 'scale: factor');
    expect(applyEdits(source, [firstPlan!.edit, factorPlan!.edit]), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(left: price, right: tax, scale: factor)
duplicate = blend(price, left: tax)
''');
    expect(
      index.addArgumentNameAt(source, source.indexOf('right: tax') + 1),
      isNull,
    );
    expect(
      index.addArgumentNameAt(source, source.indexOf('duplicate = blend') + 20),
      isNull,
    );
  });

  test('builds specify-type-explicitly edits for inferred local bindings', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
copy = price
explicit: f64 = 1
copy -> @stdout
explicit -> @stdout
''';

    final plan = index.specifyTypeExplicitlyAt(
      source,
      source.indexOf('copy ='),
    );
    final snapshot = index.build(
      const StyioSyntaxHighlighter().tokenize(source),
    );
    final explicitReferences = index.referencesAt(
      source,
      source.lastIndexOf('explicit ->'),
    );

    expect(plan?.variableName, 'copy');
    expect(plan?.typeName, 'f64');
    expect(plan?.edit.newText, ': f64');
    expect(
      source.replaceRange(
        plan!.edit.range.start,
        plan.edit.range.end,
        plan.edit.newText,
      ),
      '''
price = 12.5
copy: f64 = price
explicit: f64 = 1
copy -> @stdout
explicit -> @stdout
''',
    );
    expect(
      index.specifyTypeExplicitlyAt(source, source.indexOf('explicit:')),
      isNull,
    );
    expect(snapshot.symbols.map((symbol) => symbol.name), contains('explicit'));
    expect(explicitReferences.length, 2);
  });

  test('resolves KDoc-style block comments for parameter info', () {
    const index = StyioSymbolIndex();
    const source = '''
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
''';

    final snapshot = index.build(
      const StyioSyntaxHighlighter().tokenize(source),
    );
    final symbol = snapshot.symbols.singleWhere((item) => item.name == 'blend');
    final info = index.parameterInfoAt(source, source.lastIndexOf('tax') + 1);

    expect(symbol.documentation, contains('Blends price and tax inputs.'));
    expect(info?.documentation, 'Blends price and tax inputs.');
    expect(info?.parameters.first.documentation, 'Base price before tax.');
    expect(info?.activeParameter?.documentation, 'Tax component to add.');
  });

  test('reports call argument arity issues for current-file functions', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64) {
  emit left
}
price = 1
tax = 2
blend(price) -> @stdout
blend(price, tax, price) -> @stdout
''';

    final issues = index.callArgumentIssues(source);
    final missing = issues.singleWhere(
      (issue) => issue.diagnostic.code == 'missing-call-argument',
    );
    final extra = issues.singleWhere(
      (issue) => issue.diagnostic.code == 'too-many-call-arguments',
    );

    expect(missing.callableName, 'blend');
    expect(missing.actualArgumentCount, 1);
    expect(missing.expectedArgumentCount, 2);
    expect(missing.missingParameterNames, ['right']);
    expect(missing.replacementArgumentText, 'price, value');
    expect(missing.diagnostic.message, contains('right'));
    expect(
      source.substring(
        missing.diagnostic.range.start,
        missing.diagnostic.range.end,
      ),
      'blend(price)',
    );

    expect(extra.actualArgumentCount, 3);
    expect(extra.expectedArgumentCount, 2);
    expect(extra.extraArgumentCount, 1);
    expect(extra.replacementArgumentText, 'price, tax');
  });

  test('resolves parameter info from current hash function declarations', () {
    const index = StyioSymbolIndex();
    const source = '''
#blend := (left: f64, right: f64) => {
  <| left
}
value = blend(price, tax)
''';

    final info = index.parameterInfoAt(source, source.indexOf('tax') + 1);
    final snapshot = index.build(
      const StyioSyntaxHighlighter().tokenize(source),
    );

    expect(info?.callableName, 'blend');
    expect(info?.activeParameter?.displayText, 'right: f64');
    expect(
      snapshot.symbols
          .where((symbol) => symbol.kind == SymbolKind.parameter)
          .map((symbol) => symbol.name),
      containsAll(['left', 'right']),
    );
  });
}
