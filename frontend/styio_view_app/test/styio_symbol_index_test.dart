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

  test('resolves parameter info from a function call argument list', () {
    const index = StyioSymbolIndex();
    const source = '''
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
''';

    final info = index.parameterInfoAt(source, source.indexOf('tax') + 1);

    expect(info?.callableName, 'blend');
    expect(info?.signature, 'fn blend(left: f64, right: f64)');
    expect(info?.activeParameterIndex, 1);
    expect(info?.activeParameter?.displayText, 'right: f64');
    expect(info?.parameters.map((parameter) => parameter.name), [
      'left',
      'right',
    ]);
    expect(index.parameterInfoAt(source, source.indexOf('left:')), isNull);
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
