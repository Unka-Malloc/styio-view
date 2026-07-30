import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';

void main() {
  test('Styio CLI JSONL protocol avoids plain AST output by default', () {
    const protocol = StyioCliJsonlProtocol();
    const document = StyioServiceDocument(
      documentId: 'fixture://protocol-arguments',
      text: 'value = 1\nvalue\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final arguments = protocol.analyzeArguments(document);

    expect(arguments, isNot(contains('--styio-ast')));
    expect(arguments, containsAllInOrder(<String>[
      '--parser-engine',
      'nightly',
      '--error-format',
      'jsonl',
      '--file',
      '/workspace/main.styio',
    ]));
  });

  test('Styio CLI JSONL protocol can request AST text explicitly', () {
    const protocol = StyioCliJsonlProtocol(emitAstText: true);
    const document = StyioServiceDocument(
      documentId: 'fixture://protocol-ast-arguments',
      text: 'value = 1\nvalue\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final arguments = protocol.analyzeArguments(document);

    expect(arguments, contains('--styio-ast'));
    expect(arguments, containsAllInOrder(<String>[
      '--parser-engine',
      'nightly',
      '--styio-ast',
      '--error-format',
      'jsonl',
    ]));
  });

  test('Styio CLI JSONL protocol treats plain AST stdout as clean syntax', () {
    const protocol = StyioCliJsonlProtocol(emitAstText: true);
    const document = StyioServiceDocument(
      documentId: 'fixture://plain-ast',
      text: 'value = 1\nvalue\n',
      revision: 1,
      filePath: '/workspace/main.styio',
    );

    final response = protocol.decode(
      document: document,
      stdout: 'AST -Original\nstyio.ast.main { value }\n',
      stderr: '',
      exitCode: 0,
      toolchainSucceeded: true,
    );

    expect(response.status, StyioServiceStatus.succeeded);
    expect(response.diagnostics, isEmpty);
    expect(response.hasPayload, isFalse);
  });
}
