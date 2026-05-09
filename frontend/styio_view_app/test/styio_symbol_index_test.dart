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
}
