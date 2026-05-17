import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_semantic_token_feature.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';

void main() {
  test('builds declaration and reference semantic spans from snapshot', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);

    final spans = const StyioSemanticTokenFeature().semanticSpans(
      snapshot: snapshot,
    );

    expect(
      spans
          .where(
            (span) =>
                span.kind == SemanticKind.variable &&
                span.modifiers.contains('declaration'),
          )
          .map((span) => source.substring(span.range.start, span.range.end)),
      contains('value'),
    );
    expect(
      spans
          .where(
            (span) =>
                span.kind == SemanticKind.variable &&
                !span.modifiers.contains('declaration'),
          )
          .map((span) => source.substring(span.range.start, span.range.end)),
      contains('value'),
    );
  });

  test('maps resolved element kinds to semantic token kinds', () {
    const snapshot = SemanticSnapshot(
      documentId: 'fixture://semantic-token-kinds',
      revision: 1,
      tokens: <TokenSpan>[],
      elements: <ResolvedElement>[
        ResolvedElement(
          name: 'Thing',
          kind: ResolvedElementKind.type,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 5),
        ),
        ResolvedElement(
          name: 'source',
          kind: ResolvedElementKind.resource,
          nameRange: SourceRange(start: 6, end: 12),
          declarationRange: SourceRange(start: 6, end: 12),
        ),
        ResolvedElement(
          name: 'input',
          kind: ResolvedElementKind.parameter,
          nameRange: SourceRange(start: 18, end: 23),
          declarationRange: SourceRange(start: 18, end: 23),
        ),
      ],
      references: <ResolvedReference>[],
    );

    final spans = const StyioSemanticTokenFeature().semanticSpans(
      snapshot: snapshot,
    );

    expect(spans.map((span) => span.kind), <SemanticKind>[
      SemanticKind.typeName,
      SemanticKind.resource,
      SemanticKind.parameter,
    ]);
  });
}
