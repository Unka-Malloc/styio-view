import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/styio_symbol_index.dart';
import 'package:vityo_app/src/language/styio_syntax_highlighter.dart';

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

  test('builds remove-argument-name edits when the position stays safe', () {
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
value = blend(price, right: tax, scale: factor)
wrongSlot = blend(price, scale: factor)
outOfOrder = blend(scale: factor, price, right: tax)
''';

    final rightPlan = index.removeArgumentNameAt(
      source,
      source.indexOf('right: tax') + 1,
    );
    final scalePlan = index.removeArgumentNameAt(
      source,
      source.indexOf('scale: factor') + 1,
    );

    expect(rightPlan?.callableName, 'blend');
    expect(rightPlan?.parameterName, 'right');
    expect(rightPlan?.edit.newText, 'tax');
    expect(scalePlan?.parameterName, 'scale');
    expect(scalePlan?.edit.newText, 'factor');
    expect(applyEdits(source, [rightPlan!.edit, scalePlan!.edit]), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, tax, factor)
wrongSlot = blend(price, scale: factor)
outOfOrder = blend(scale: factor, price, right: tax)
''');
    expect(
      index.removeArgumentNameAt(
        source,
        source.indexOf('wrongSlot = blend(price, scale:') +
            'wrongSlot = blend(price, '.length,
      ),
      isNull,
    );
    expect(
      index.removeArgumentNameAt(
        source,
        source.indexOf('outOfOrder = blend(scale:') +
            'outOfOrder = blend('.length,
      ),
      isNull,
    );
  });

  test('builds remove-all-argument-names edits for ordered named calls', () {
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
value = blend(left: price, right: tax, scale: factor)
mixed = blend(price, right: tax, scale: factor)
singleNamed = blend(price, right: tax, factor)
unsafe = blend(scale: factor, right: tax)
''';

    final orderedPlan = index.removeArgumentNamesAt(
      source,
      source.indexOf('value = blend') + 'value = blend('.length,
    );
    final mixedPlan = index.removeArgumentNamesAt(
      source,
      source.indexOf('mixed = blend') + 'mixed = blend(price, '.length,
    );

    expect(orderedPlan?.callableName, 'blend');
    expect(orderedPlan?.edits.length, 3);
    expect(mixedPlan?.edits.length, 2);
    expect(applyEdits(source, orderedPlan!.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(price, tax, factor)
mixed = blend(price, right: tax, scale: factor)
singleNamed = blend(price, right: tax, factor)
unsafe = blend(scale: factor, right: tax)
''');
    expect(applyEdits(source, mixedPlan!.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
factor = 2.0
value = blend(left: price, right: tax, scale: factor)
mixed = blend(price, tax, factor)
singleNamed = blend(price, right: tax, factor)
unsafe = blend(scale: factor, right: tax)
''');
    expect(
      index.removeArgumentNamesAt(
        source,
        source.indexOf('singleNamed = blend') +
            'singleNamed = blend(price, '.length,
      ),
      isNull,
    );
    expect(
      index.removeArgumentNamesAt(
        source,
        source.indexOf('unsafe = blend') + 'unsafe = blend('.length,
      ),
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

  test(
    'builds remove-explicit-type edits when inference preserves the type',
    () {
      const index = StyioSymbolIndex();
      const source = '''
price = 12.5
copy: f64 = price
count: i64 = 3
wide: f64 = 3
again = copy
later = count
''';

      final copyPlan = index.removeExplicitTypeAt(
        source,
        source.indexOf('copy:'),
      );
      final countPlan = index.removeExplicitTypeAt(
        source,
        source.indexOf('i64'),
      );
      final hints = index.typeNameHints(source);

      expect(copyPlan?.variableName, 'copy');
      expect(copyPlan?.typeName, 'f64');
      expect(copyPlan?.edit.newText, '');
      expect(
        source.replaceRange(
          copyPlan!.edit.range.start,
          copyPlan.edit.range.end,
          copyPlan.edit.newText,
        ),
        '''
price = 12.5
copy = price
count: i64 = 3
wide: f64 = 3
again = copy
later = count
''',
      );
      expect(countPlan?.typeName, 'i64');
      expect(
        index.removeExplicitTypeAt(source, source.indexOf('wide:')),
        isNull,
      );
      expect(
        hints.singleWhere(
          (hint) => hint.range.start == source.indexOf('again'),
        ),
        isA<InlayHint>().having((hint) => hint.label, 'label', ': f64'),
      );
      expect(
        hints.singleWhere(
          (hint) => hint.range.start == source.indexOf('later'),
        ),
        isA<InlayHint>().having((hint) => hint.label, 'label', ': i64'),
      );
    },
  );

  test('infers simple binary expression types', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
tax = 2
total = price + tax
spread = total > 10.0
ready = spread && true
''';

    final hints = index.typeNameHints(source);

    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('total')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': f64'),
    );
    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('spread')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': bool'),
    );
    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('ready')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': bool'),
    );
  });

  test('respects binary operator precedence for expression types', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
tax = 2
threshold = 10.0
ready = true || price + tax > threshold
spread = price + tax * 2 > threshold && true
total = price + tax * 2
''';

    final hints = index.typeNameHints(source);

    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('ready')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': bool'),
    );
    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('spread')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': bool'),
    );
    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('total')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': f64'),
    );
  });

  test('reports binary operator operand type mismatches', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
ready = true
bad = price && ready
also = ready + 1
ok = true || price > 0
fn broken(value: f64): bool {
  emit true || value + 1
}
''';

    final issues = index.binaryOperatorTypeIssues(source);

    expect(issues.map((issue) => issue.operatorLexeme), ['&&', '+', '||']);
    expect(issues.map((issue) => issue.leftTypeName), ['f64', 'bool', 'bool']);
    expect(issues.map((issue) => issue.rightTypeName), ['bool', 'i64', 'f64']);
    expect(
      issues.map(
        (issue) => source.substring(
          issue.operatorRange.start,
          issue.operatorRange.end,
        ),
      ),
      ['&&', '+', '||'],
    );
    expect(
      issues.map(
        (issue) => source.substring(
          issue.leftOperandRange.start,
          issue.leftOperandRange.end,
        ),
      ),
      ['price', 'ready', 'true'],
    );
    expect(
      issues.map(
        (issue) => source.substring(
          issue.rightOperandRange.start,
          issue.rightOperandRange.end,
        ),
      ),
      ['ready', '1', 'value + 1'],
    );
    expect(issues.map((issue) => issue.diagnostic.code).toSet(), {
      'binary-operator-type-mismatch',
    });
  });

  test('reports unary operator operand type mismatches', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
ready = true
bad = !price
also = -ready
fn broken(value: f64): bool {
  emit !value
}
''';

    final issues = index.unaryOperatorTypeIssues(source);

    expect(issues.map((issue) => issue.operatorLexeme), ['!', '-', '!']);
    expect(issues.map((issue) => issue.operandTypeName), [
      'f64',
      'bool',
      'f64',
    ]);
    expect(
      issues.map(
        (issue) => source.substring(
          issue.operatorRange.start,
          issue.operatorRange.end,
        ),
      ),
      ['!', '-', '!'],
    );
    expect(
      issues.map(
        (issue) =>
            source.substring(issue.operandRange.start, issue.operandRange.end),
      ),
      ['price', 'ready', 'value'],
    );
    expect(issues.map((issue) => issue.diagnostic.code).toSet(), {
      'unary-operator-type-mismatch',
    });
  });

  test('infers parenthesized and unary expression types', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
tax = 2
ready = price > 0
total = (price + tax)
negative = -(price + tax)
blocked = !ready
''';

    final hints = index.typeNameHints(source);

    expect(
      hints.singleWhere((hint) => hint.range.start == source.indexOf('total')),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': f64'),
    );
    expect(
      hints.singleWhere(
        (hint) => hint.range.start == source.indexOf('negative'),
      ),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': f64'),
    );
    expect(
      hints.singleWhere(
        (hint) => hint.range.start == source.indexOf('blocked'),
      ),
      isA<InlayHint>().having((hint) => hint.label, 'label', ': bool'),
    );
  });

  test('reports when condition type mismatches', () {
    const index = StyioSymbolIndex();
    const source = '''
price = 12.5
ready = price > 0
when price -> state priced
when ready -> state ready
when !ready -> state blocked
when price + 1 -> state wide
when -(price + 1) -> state negative
when "open" -> state text
''';

    final issues = index.conditionTypeMismatchIssues(source);

    expect(issues.map((issue) => issue.actualTypeName), [
      'f64',
      'f64',
      'f64',
      'string',
    ]);
    expect(
      issues.map(
        (issue) => source.substring(
          issue.diagnostic.range.start,
          issue.diagnostic.range.end,
        ),
      ),
      ['price', 'price + 1', '-(price + 1)', '"open"'],
    );
    expect(issues.first.replacementConditionText, 'price != 0.0');
    expect(issues[1].replacementConditionText, 'price + 1 != 0.0');
    expect(issues[2].replacementConditionText, '-(price + 1) != 0.0');
    expect(issues[3].replacementConditionText, isEmpty);
  });

  test('reports typed local initializer type mismatches', () {
    const index = StyioSymbolIndex();
    const source = '''
fn amount(): i64 {
  emit 1
}
price = 12.5
wide: f64 = 3
count: i64 = price
fromCall: f64 = amount()
ok: f64 = price
flag: i64 = price > 1
blocked: i64 = !true
condition: i64 = true || price > 0
''';

    final issues = index.typedLocalInitializerIssues(source);

    expect(issues.map((issue) => issue.variableName), [
      'wide',
      'count',
      'fromCall',
      'flag',
      'blocked',
      'condition',
    ]);
    expect(issues.map((issue) => issue.expectedTypeName), [
      'f64',
      'i64',
      'f64',
      'i64',
      'i64',
      'i64',
    ]);
    expect(issues.map((issue) => issue.actualTypeName), [
      'i64',
      'f64',
      'i64',
      'bool',
      'bool',
      'bool',
    ]);
    expect(
      issues.map(
        (issue) => source.substring(
          issue.diagnostic.range.start,
          issue.diagnostic.range.end,
        ),
      ),
      ['3', 'price', 'amount()', 'price > 1', '!true', 'true || price > 0'],
    );
    expect(issues.first.replacementInitializerText, '3.0');
    expect(
      issues.map(
        (issue) => source.substring(issue.typeRange.start, issue.typeRange.end),
      ),
      ['f64', 'i64', 'f64', 'i64', 'i64', 'i64'],
    );
  });

  test('reports typed local assignment type mismatches', () {
    const index = StyioSymbolIndex();
    const source = '''
rate: f64 = 0.0
rate = 1
count: i64 = 0
count = 1.5
label: string = "ok"
label = 2
ok: f64 = 1.0
ok = rate + 1
flag: bool = true
flag = rate + 1
''';

    final issues = index.assignmentTypeMismatchIssues(source);

    expect(issues.map((issue) => issue.variableName), [
      'rate',
      'count',
      'label',
      'flag',
    ]);
    expect(issues.map((issue) => issue.expectedTypeName), [
      'f64',
      'i64',
      'string',
      'bool',
    ]);
    expect(issues.map((issue) => issue.actualTypeName), [
      'i64',
      'f64',
      'i64',
      'f64',
    ]);
    expect(
      issues.map(
        (issue) => source.substring(
          issue.diagnostic.range.start,
          issue.diagnostic.range.end,
        ),
      ),
      ['1', '1.5', '2', 'rate + 1'],
    );
    expect(issues.first.replacementAssignmentText, '1.0');
    expect(issues[1].replacementInitializerTextForActualType, '0.0');
    expect(issues[1].canChangeDeclaredType, isTrue);
    expect(issues[2].canChangeDeclaredType, isFalse);
    expect(
      issues.map(
        (issue) => source.substring(issue.typeRange.start, issue.typeRange.end),
      ),
      ['f64', 'i64', 'string', 'bool'],
    );
  });

  test('reports function return type mismatches', () {
    const index = StyioSymbolIndex();
    const source = '''
fn price(): f64 {
  emit 3
}
fn amount(): i64 {
  emit 1.5
}
#label := (): string => {
  <| 1
}
fn ok(left: f64): f64 {
  emit left
}
fn ready(left: f64): i64 {
  emit left > 0
}
''';

    final issues = index.functionReturnTypeIssues(source);

    expect(issues.map((issue) => issue.functionName), [
      'price',
      'amount',
      'label',
      'ready',
    ]);
    expect(issues.map((issue) => issue.expectedTypeName), [
      'f64',
      'i64',
      'string',
      'i64',
    ]);
    expect(issues.map((issue) => issue.actualTypeName), [
      'i64',
      'f64',
      'i64',
      'bool',
    ]);
    expect(
      issues.map(
        (issue) => source.substring(
          issue.diagnostic.range.start,
          issue.diagnostic.range.end,
        ),
      ),
      ['3', '1.5', '1', 'left > 0'],
    );
    expect(issues.first.replacementReturnExpressionText, '3.0');
    expect(
      issues.map(
        (issue) => source.substring(
          issue.returnTypeRange.start,
          issue.returnTypeRange.end,
        ),
      ),
      ['f64', 'i64', 'string', 'i64'],
    );
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

  test('reports named call argument issues for current-file functions', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left
}
price = 1
tax = 2
factor = 3
blend(left: price, rigth: tax, scale: factor) -> @stdout
blend(left: price, left: tax, scale: factor) -> @stdout
''';

    final issues = index.callArgumentIssues(source);
    final unknown = issues.singleWhere(
      (issue) => issue.diagnostic.code == 'unknown-named-argument',
    );
    final duplicate = issues.singleWhere(
      (issue) => issue.diagnostic.code == 'duplicate-named-argument',
    );

    expect(unknown.callableName, 'blend');
    expect(unknown.namedArgumentName, 'rigth');
    expect(unknown.suggestedParameterName, 'right');
    expect(
      source.substring(
        unknown.diagnostic.range.start,
        unknown.diagnostic.range.end,
      ),
      'rigth',
    );
    expect(duplicate.namedArgumentName, 'left');
    expect(
      source.substring(
        duplicate.diagnostic.range.start,
        duplicate.diagnostic.range.end,
      ),
      'left',
    );
    expect(duplicate.replacementArgumentText, 'left: price, scale: factor');
  });

  test('reports call argument type mismatches for current-file functions', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, count: i64) {
  emit left
}
price = 1.5
count = 3
blend(count, price) -> @stdout
blend(left: count, count: price) -> @stdout
''';

    final issues = index.callArgumentIssues(source);
    final mismatches = issues
        .where((issue) => issue.diagnostic.code == 'argument-type-mismatch')
        .toList(growable: false);

    expect(mismatches.map((issue) => issue.parameterName), [
      'left',
      'count',
      'left',
      'count',
    ]);
    expect(mismatches.map((issue) => issue.expectedTypeName), [
      'f64',
      'i64',
      'f64',
      'i64',
    ]);
    expect(mismatches.map((issue) => issue.actualTypeName), [
      'i64',
      'f64',
      'i64',
      'f64',
    ]);
    expect(
      mismatches.map(
        (issue) => source.substring(
          issue.diagnostic.range.start,
          issue.diagnostic.range.end,
        ),
      ),
      ['count', 'price', 'count', 'price'],
    );
    expect(
      mismatches.map(
        (issue) => source.substring(
          issue.parameterTypeRange!.start,
          issue.parameterTypeRange!.end,
        ),
      ),
      ['f64', 'i64', 'f64', 'i64'],
    );
    expect(mismatches.first.diagnostic.message, contains('expects `f64`'));
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

  test('reports refactor conflicts for unsupported symbols and usages', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64) {
  emit left
}
unused = 1
self = self + 1
value = self
''';

    final safeDeleteFunction = index.safeDeleteAt(
      source,
      source.indexOf('blend'),
    );
    final inlineFunction = index.inlineVariableAt(
      source,
      source.indexOf('blend'),
    );
    final inlineUnused = index.inlineVariableAt(
      source,
      source.indexOf('unused'),
    );
    final inlineSelf = index.inlineVariableAt(source, source.indexOf('self'));

    expect(safeDeleteFunction?.hasConflicts, isTrue);
    expect(safeDeleteFunction?.conflicts.single.message, contains('variable'));
    expect(inlineFunction?.hasConflicts, isTrue);
    expect(inlineFunction?.conflicts.single.message, contains('variable'));
    expect(inlineUnused?.hasConflicts, isTrue);
    expect(inlineUnused?.conflicts.single.message, contains('never used'));
    expect(inlineSelf?.hasConflicts, isTrue);
    expect(
      inlineSelf?.conflicts.map((conflict) => conflict.message).join('\n'),
      contains('initializer'),
    );
  });

  test('reports introduce variable validation conflicts', () {
    const index = StyioSymbolIndex();
    const expressionSource = 'value = 40 + 2\n';
    final expressionStart = expressionSource.indexOf('40 + 2');
    final invalidName = index.introduceVariable(
      expressionSource,
      SourceRange(start: expressionStart, end: expressionStart + 6),
      'not-valid',
    );

    const multilineSource = 'value = 1 +\n  2\n';
    final multiline = index.introduceVariable(
      multilineSource,
      SourceRange(
        start: multilineSource.indexOf('1 +'),
        end: multilineSource.indexOf('2') + 1,
      ),
      'result',
    );

    const commentSource = 'value = 1 // note\n';
    final comment = index.introduceVariable(
      commentSource,
      SourceRange(
        start: commentSource.indexOf('//'),
        end: commentSource.indexOf('note') + 4,
      ),
      'note',
    );

    const targetSource = 'value = 1\n';
    final assignmentTarget = index.introduceVariable(
      targetSource,
      const SourceRange(start: 0, end: 'value'.length),
      'renamed',
    );

    const pipelineSource = 'value -> @stdout\n';
    final pipeline = index.introduceVariable(
      pipelineSource,
      SourceRange(start: 0, end: pipelineSource.trimRight().length),
      'output',
    );

    expect(
      invalidName?.conflicts.map((conflict) => conflict.message),
      contains('Enter a valid Styio identifier.'),
    );
    expect(
      multiline?.conflicts.map((conflict) => conflict.message),
      contains('Introduce Variable currently requires one expression line.'),
    );
    expect(
      comment?.conflicts.map((conflict) => conflict.message),
      contains('Cannot introduce a variable from a comment range.'),
    );
    expect(
      assignmentTarget?.conflicts.map((conflict) => conflict.message),
      contains('Cannot introduce a variable from an assignment target.'),
    );
    expect(
      pipeline?.conflicts.map((conflict) => conflict.message),
      contains('Select an expression, not a binding or pipeline statement.'),
    );
  });

  test('reports extract function validation conflicts', () {
    const index = StyioSymbolIndex();
    const expressionSource = 'value = user + 1\n';
    final expressionStart = expressionSource.indexOf('user + 1');
    final invalidName = index.extractFunction(
      expressionSource,
      SourceRange(start: expressionStart, end: expressionStart + 8),
      'not-valid',
    );
    final partialToken = index.extractFunction(
      expressionSource,
      SourceRange(start: expressionStart + 1, end: expressionStart + 3),
      'compute',
    );
    final assignmentTarget = index.extractFunction(
      expressionSource,
      const SourceRange(start: 0, end: 'value'.length),
      'compute',
    );

    const multilineSource = 'value = price +\n  tax\n';
    final multiline = index.extractFunction(
      multilineSource,
      SourceRange(
        start: multilineSource.indexOf('price'),
        end: multilineSource.indexOf('tax') + 3,
      ),
      'compute',
    );

    const declarationSource = 'fn main() {\n  emit 1\n}\n';
    final declaration = index.extractFunction(
      declarationSource,
      SourceRange(start: 0, end: declarationSource.indexOf('{')),
      'compute',
    );

    const braceSource = 'value = { price\n';
    final brace = index.extractFunction(
      braceSource,
      SourceRange(start: braceSource.indexOf('{'), end: braceSource.length),
      'compute',
    );

    Iterable<String> messages(ExtractFunctionPlan? plan) {
      return plan?.conflicts.map((conflict) => conflict.message) ??
          const <String>[];
    }

    expect(
      messages(invalidName),
      contains('Enter a valid Styio function identifier.'),
    );
    expect(
      messages(partialToken),
      contains('Extract Function requires complete selected tokens.'),
    );
    expect(
      messages(assignmentTarget),
      contains('Cannot extract a function from an assignment target.'),
    );
    expect(
      messages(multiline),
      contains(
        'Extract Function currently requires full-line selections for multi-line code.',
      ),
    );
    expect(
      messages(declaration).join('\n'),
      contains('not declarations'),
    );
    expect(messages(brace).join('\n'), contains('unmatched opening brace'));
  });

  test('reports change signature validation conflicts', () {
    const index = StyioSymbolIndex();
    const source = '''
fn taken() {
}

fn blend(left: f64, right: f64) {
  result = left + right
}

alias = blend
value = blend(1.0, 2.0)
''';
    final offset = source.indexOf('blend');

    Iterable<String> messages(ChangeSignaturePlan? plan) {
      return plan?.conflicts.map((conflict) => conflict.message) ??
          const <String>[];
    }

    final invalidName = index.changeSignature(
      source,
      offset,
      newName: 'not-valid',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
      ],
    );
    final duplicateName = index.changeSignature(
      source,
      offset,
      newName: 'taken',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
      ],
    );
    final missingOriginal = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'missing', name: 'missing'),
      ],
    );
    final duplicateOriginal = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'leftAgain'),
      ],
    );
    final invalidParameter = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'not-valid'),
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
      ],
    );
    final duplicateParameter = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'value'),
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'value'),
      ],
    );
    final removeUsed = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
      ],
    );
    final renameAndReorder = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'lhs'),
      ],
    );
    final reorderWithNonCallUsage = index.changeSignature(
      source,
      offset,
      newName: 'blend',
      parameters: const [
        ChangeSignatureParameterUpdate(originalName: 'right', name: 'right'),
        ChangeSignatureParameterUpdate(originalName: 'left', name: 'left'),
      ],
    );

    expect(
      messages(invalidName),
      contains('Enter a valid Styio function identifier.'),
    );
    expect(messages(duplicateName).join('\n'), contains('already declares'));
    expect(
      messages(missingOriginal).join('\n'),
      contains('not in the current function signature'),
    );
    expect(
      messages(duplicateOriginal).join('\n'),
      contains('appears more than once'),
    );
    expect(
      messages(invalidParameter),
      contains('Enter valid Styio parameter identifiers.'),
    );
    expect(
      messages(duplicateParameter).join('\n'),
      contains('Parameter `value` appears more than once'),
    );
    expect(
      messages(removeUsed).join('\n'),
      contains('Cannot remove parameter `right`'),
    );
    expect(
      messages(renameAndReorder).join('\n'),
      contains('separate safe steps'),
    );
    expect(
      messages(reorderWithNonCallUsage).join('\n'),
      contains('non-call usage'),
    );
  });

  test('resolves nested calls, zero-argument info, and typed local scopes', () {
    const index = StyioSymbolIndex();
    const source = '''
value = ping()

fn ping(): i64 {
  emit 1
}

fn takes(value: f64): f64 {
  emit value
}

fn caller(input: i64): i64 {
  local: i64 = input
  bad = local && true
  takes(local)
  emit local
}

#hash := (): f64 => {
  local: i64 = 1
  <| local
}

result = takes((ping() + 1))
''';

    final emptyInfo = index.parameterInfoAt(
      source,
      source.indexOf('ping()') + 'ping('.length,
    );
    final nestedInfo = index.parameterInfoAt(
      source,
      source.lastIndexOf('ping()') + 'ping('.length,
    );
    final binaryIssues = index.binaryOperatorTypeIssues(source);
    final argumentIssues = index.callArgumentIssues(source);
    final returnIssues = index.functionReturnTypeIssues(source);

    expect(emptyInfo?.callableName, 'ping');
    expect(emptyInfo?.activeParameterIndex, -1);
    expect(emptyInfo?.parameters, isEmpty);
    expect(nestedInfo?.callableName, 'ping');
    expect(
      binaryIssues.map((issue) => issue.operatorLexeme),
      contains('&&'),
    );
    expect(
      argumentIssues.map((issue) => issue.diagnostic.code),
      contains('argument-type-mismatch'),
    );
    expect(
      returnIssues.map((issue) => issue.functionName),
      contains('hash'),
    );
  });
}
