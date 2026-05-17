import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_hover_feature.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';

void main() {
  test('builds hover payload from semantic snapshot fixture', () {
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

    final hover = const StyioHoverFeature().hoverAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );

    expect(hover, isNotNull);
    expect(hover!.markdown, contains('**value**'));
    expect(hover.range.start, source.lastIndexOf('value'));
  });

  test('builds hover payload from analysis documentation facts', () {
    const document = DocumentState(
      documentId: 'fixture://analysis-hover',
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 10),
          detail: 'Styio binding',
          documentation: 'Base value used by the document.',
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 11, end: 16),
          targetRange: SourceRange(start: 0, end: 5),
        ),
      ],
    );
    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    final hover = const StyioHoverFeature().hoverAt(
      document: document,
      snapshot: snapshot,
      offset: 12,
    );

    expect(hover?.range.start, 11);
    expect(hover?.markdown, contains('Styio binding'));
    expect(hover?.markdown, contains('Base value used by the document.'));
  });
}
