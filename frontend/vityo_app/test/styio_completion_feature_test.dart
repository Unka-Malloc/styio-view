import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_completion_feature.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';

void main() {
  test('builds completion items from semantic snapshot fixture', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);
    final offset = source.length;

    final completions = const StyioCompletionFeature().completeAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );

    expect(
      completions.map((item) => item.label),
      containsAll(<String>['schema', 'i64', 'value']),
    );
    final valueCompletion = completions.singleWhere(
      (item) => item.label == 'value',
    );
    expect(valueCompletion.replacementRange?.start, source.length);
    expect(valueCompletion.replacementRange?.end, source.length);
  });

  test('filters completion items by current identifier prefix', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);
    final offset = source.lastIndexOf('value') + 2;

    final completions = const StyioCompletionFeature().completeAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );

    expect(completions.map((item) => item.label), <String>['value']);
    final valueCompletion = completions.single;
    expect(
      valueCompletion.replacementRange?.start,
      source.lastIndexOf('value'),
    );
    expect(
      valueCompletion.replacementRange?.end,
      source.lastIndexOf('value') + 5,
    );
  });

  test('treats token end as an exclusive completion boundary', () {
    const source = 'value ';
    const document = DocumentState(
      documentId: 'fixture://completion-boundary',
      text: source,
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);

    final completions = const StyioCompletionFeature().completeAt(
      document: document,
      snapshot: snapshot,
      offset: 5,
    );

    expect(completions.map((item) => item.label), contains('schema'));
    final schemaCompletion = completions.singleWhere(
      (item) => item.label == 'schema',
    );
    expect(schemaCompletion.replacementRange?.start, 5);
    expect(schemaCompletion.replacementRange?.end, 5);
  });
}
