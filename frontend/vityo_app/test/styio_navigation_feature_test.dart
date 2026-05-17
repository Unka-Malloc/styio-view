import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_navigation_feature.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';

void main() {
  test(
    'builds definition references and rename from semantic snapshot fixture',
    () {
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
      const feature = StyioNavigationFeature();

      final definition = feature.definitionAt(
        document: document,
        snapshot: snapshot,
        offset: offset,
      );
      final references = feature.referencesAt(
        document: document,
        snapshot: snapshot,
        offset: offset,
      );
      final rename = feature.renameAt(
        document: document,
        snapshot: snapshot,
        offset: offset,
        newName: 'nextValue',
      );

      expect(definition?.symbol.name, 'value');
      expect(references, hasLength(2));
      expect(rename, isNotNull);
      expect(rename!.hasConflicts, isFalse);
      expect(rename.edits, hasLength(2));
      expect(rename.edits.every((edit) => edit.newText == 'nextValue'), isTrue);
    },
  );

  test('builds navigation from declaration-only analysis facts', () {
    const document = DocumentState(
      documentId: 'fixture://analysis-declaration',
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
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 11, end: 16),
          targetRange: SourceRange(start: 0, end: 5),
          access: ReferenceAccess.read,
        ),
      ],
    );
    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );
    const feature = StyioNavigationFeature();

    final definition = feature.definitionAt(
      document: document,
      snapshot: snapshot,
      offset: 2,
    );
    final references = feature.referencesAt(
      document: document,
      snapshot: snapshot,
      offset: 2,
    );
    final rename = feature.renameAt(
      document: document,
      snapshot: snapshot,
      offset: 2,
      newName: 'nextValue',
    );

    expect(definition?.symbol.name, 'value');
    expect(definition?.originRange.start, 0);
    expect(references.map((reference) => reference.isDeclaration), <bool>[
      true,
      false,
    ]);
    expect(rename, isNotNull);
    expect(rename!.edits, hasLength(2));
    expect(rename.edits.first.range.start, 0);
  });

  test('treats rename to the same name as a no-op', () {
    const document = DocumentState(
      documentId: 'fixture://rename-no-op',
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
    const feature = StyioNavigationFeature();

    final rename = feature.renameAt(
      document: document,
      snapshot: snapshot,
      offset: 12,
      newName: 'value',
    );

    expect(rename, isNotNull);
    expect(rename!.references, hasLength(2));
    expect(rename.hasConflicts, isFalse);
    expect(rename.edits, isEmpty);
  });

  test('preserves type symbol kind in definition and references', () {
    const document = DocumentState(
      documentId: 'fixture://type-symbol-kind',
      text: 'schema User\nUser\n',
      revision: 1,
    );
    const target = ResolvedElement(
      name: 'User',
      kind: ResolvedElementKind.type,
      nameRange: SourceRange(start: 7, end: 11),
      declarationRange: SourceRange(start: 0, end: 11),
    );
    const snapshot = SemanticSnapshot(
      documentId: 'fixture://type-symbol-kind',
      revision: 1,
      tokens: <TokenSpan>[],
      elements: <ResolvedElement>[target],
      references: <ResolvedReference>[
        ResolvedReference(
          name: 'User',
          range: SourceRange(start: 7, end: 11),
          target: target,
          access: ResolvedReferenceAccess.declaration,
          isDeclaration: true,
        ),
        ResolvedReference(
          name: 'User',
          range: SourceRange(start: 12, end: 16),
          target: target,
          access: ResolvedReferenceAccess.read,
          isDeclaration: false,
        ),
      ],
    );
    const feature = StyioNavigationFeature();

    final definition = feature.definitionAt(
      document: document,
      snapshot: snapshot,
      offset: 13,
    );
    final references = feature.referencesAt(
      document: document,
      snapshot: snapshot,
      offset: 13,
    );

    expect(definition?.symbol.kind, SymbolKind.state);
    expect(references.map((reference) => reference.kind).toSet(), {
      SymbolKind.state,
    });
  });
}
