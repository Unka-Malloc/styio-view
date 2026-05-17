import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_formatting_feature.dart';

void main() {
  test('builds whitespace formatting edits from fixture', () {
    final source = File(
      'test/fixtures/language_service/formatting_trailing_whitespace.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://formatting_trailing_whitespace',
      text: source,
      revision: 1,
    );

    final edits = const StyioFormattingFeature().formatDocument(document);

    expect(edits, hasLength(2));
    expect(edits.first.newText, '');
    expect(edits.last.newText, '\n');
  });

  test('builds formatting code action when whitespace edits exist', () {
    const document = DocumentState(
      documentId: 'fixture://formatting_action',
      text: 'value := 1  ',
      revision: 1,
    );

    final action = const StyioFormattingFeature().formatDocumentAction(
      document,
    );

    expect(action, isNotNull);
    expect(action!.label, 'Format document whitespace');
    expect(action.edits.map((edit) => edit.newText), <String>['', '\n']);
  });

  test('does not build formatting code action for clean document', () {
    const document = DocumentState(
      documentId: 'fixture://formatting_clean',
      text: 'value := 1\n',
      revision: 1,
    );

    final action = const StyioFormattingFeature().formatDocumentAction(
      document,
    );

    expect(action, isNull);
  });
}
