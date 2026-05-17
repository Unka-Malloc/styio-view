import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_refactor_feature.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';

void main() {
  test('builds local refactor plans from semantic snapshot fixture', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);
    final valueUse = source.lastIndexOf('value') + 2;
    const feature = StyioRefactorFeature();

    final safeDelete = feature.safeDeleteAt(
      document: document,
      snapshot: snapshot,
      offset: valueUse,
    );
    final inline = feature.inlineVariableAt(
      document: document,
      snapshot: snapshot,
      offset: valueUse,
    );
    final changeSignature = feature.changeSignatureAt(
      document: document,
      snapshot: snapshot,
      offset: valueUse,
      newName: 'nextValue',
      parameters: const <ChangeSignatureParameterUpdate>[],
    );

    expect(safeDelete, isNotNull);
    expect(safeDelete!.hasConflicts, isTrue);
    expect(inline, isNotNull);
    expect(inline!.initializerText, '1');
    expect(inline.edits, hasLength(2));
    expect(changeSignature, isNotNull);
    expect(changeSignature!.edits, hasLength(2));
  });

  test('builds introduce and extract plans from selected fixture ranges', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
    const feature = StyioRefactorFeature();
    final literalStart = source.indexOf('1');
    final valueUseStart = source.lastIndexOf('value');

    final introduce = feature.introduceVariable(
      document: document,
      range: SourceRange(start: literalStart, end: literalStart + 1),
      name: 'one',
    );
    final extract = feature.extractFunction(
      document: document,
      range: SourceRange(start: valueUseStart, end: valueUseStart + 5),
      name: 'readValue',
    );

    expect(introduce, isNotNull);
    expect(introduce!.expressionText, '1');
    expect(introduce.edits, hasLength(2));
    expect(extract, isNotNull);
    expect(extract!.callText, 'readValue()');
    expect(extract.functionText, contains('#readValue'));
  });

  test('preserves type symbol kind in safe delete plans', () {
    const document = DocumentState(
      documentId: 'fixture://type-safe-delete',
      text: 'schema User\n',
      revision: 1,
    );
    const target = ResolvedElement(
      name: 'User',
      kind: ResolvedElementKind.type,
      nameRange: SourceRange(start: 7, end: 11),
      declarationRange: SourceRange(start: 0, end: 11),
    );
    const snapshot = SemanticSnapshot(
      documentId: 'fixture://type-safe-delete',
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
      ],
    );
    const feature = StyioRefactorFeature();

    final plan = feature.safeDeleteAt(
      document: document,
      snapshot: snapshot,
      offset: 8,
    );

    expect(plan?.target.kind, SymbolKind.state);
    expect(plan?.references.single.kind, SymbolKind.state);
  });
}
