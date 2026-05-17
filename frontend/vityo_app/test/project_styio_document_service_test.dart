import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  test('returns diagnostic quick fixes as intentions at cursor', () {
    final source = File(
      'test/fixtures/language_service/missing_assignment.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://missing_assignment',
      text: source,
      revision: 1,
    );
    const service = ProjectStyioDocumentService();
    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'missing-assignment');

    final intentions = service.intentionsAt(document, diagnostic.range.start);

    expect(
      intentions.map((fix) => fix.label),
      contains('Insert assignment'),
    );
  });
}
