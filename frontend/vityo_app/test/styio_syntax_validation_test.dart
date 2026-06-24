import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';

void main() {
  StyioSyntaxContract contractFixture() {
    return StyioSyntaxContract.fromJson(
      jsonDecode(
            File(
              'test/fixtures/styio_syntax_contracts/ide_syntax_contract.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
  }

  List<Diagnostic> diagnosticsForFixture(String path) {
    final source = File('test/fixtures/styio_language/$path').readAsStringSync();
    const highlighter = StyioSyntaxHighlighter();
    final validator = StyioSyntaxValidator(contract: contractFixture());
    return validator.validate(
      source: source,
      tokens: highlighter.tokenize(source),
    );
  }

  test('loads IDE syntax contract from fixture config', () {
    final contract = contractFixture();

    expect(contract.id, 'vityo-ide-syntax');
    expect(contract.version, '2026.05.ide');
    expect(contract.delimiterPairs, containsPair('[', ']'));
    expect(contract.reportUnknownTokens, isTrue);
  });

  test('accepts true syntax fixtures through the IDE syntax validator', () {
    expect(diagnosticsForFixture('syntax_contract/value.true.styio'), isEmpty);
  });

  test('serializes IDE syntax validation reports with contract metadata', () {
    final source = File(
      'test/fixtures/styio_language/syntax_contract/unknown-token.false.styio',
    ).readAsStringSync();
    const highlighter = StyioSyntaxHighlighter();
    final report = StyioSyntaxValidator(
      contract: contractFixture(),
    ).validateWithReport(
      documentId: 'unknown-token.false.styio',
      source: source,
      tokens: highlighter.tokenize(source),
    );
    final json = report.toJson();

    expect(json['documentId'], 'unknown-token.false.styio');
    expect(json['contractId'], 'vityo-ide-syntax');
    expect(json['contractVersion'], '2026.05.ide');
    expect(json['source'], 'vityo-ide-syntax-contract');
    expect(json['fallback'], isTrue);
    expect(json['valid'], isFalse);
    expect(json['diagnosticCount'], greaterThan(0));
    expect(
      (json['diagnostics']! as List<Object?>).first,
      isA<Map<String, Object?>>(),
    );
  });

  test('reports false syntax fixtures through the IDE syntax validator', () {
    expect(
      diagnosticsForFixture('syntax_contract/unknown-token.false.styio')
          .map((diagnostic) => diagnostic.code),
      contains('unknown-token'),
    );
    expect(
      diagnosticsForFixture('syntax_contract/unclosed-bracket.false.styio')
          .map((diagnostic) => diagnostic.code),
      contains('unclosed-bracket'),
    );
  });

  test('compiler diagnostics delegates syntax checks to the extracted unit', () {
    final source = File(
      'test/fixtures/styio_language/syntax_contract/unknown-token.false.styio',
    ).readAsStringSync();
    const highlighter = StyioSyntaxHighlighter();
    final diagnostics = StyioCompilerDiagnostics(
      syntaxValidator: StyioSyntaxValidator(contract: contractFixture()),
    ).analyze(source: source, tokens: highlighter.tokenize(source));

    expect(
      diagnostics.map((diagnostic) => diagnostic.code),
      contains('unknown-token'),
    );
  });
}
