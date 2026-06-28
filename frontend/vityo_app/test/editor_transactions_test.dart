import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/editor/transactions.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';

void main() {
  test('workspace edit applies non-overlapping edits as one revision', () {
    const service = EditorTransactionService();
    const document = DocumentState(
      documentId: 'sample.styio',
      text: 'alpha beta gamma',
      revision: 7,
    );
    final edit = WorkspaceEdit.singleDocument(
      document: document,
      source: WorkspaceEditSource.rename,
      edits: <WorkspaceTextEdit>[
        const WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 0, end: 5),
          newText: 'one',
        ),
        const WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 11, end: 16),
          newText: 'three',
        ),
      ],
    );

    final result = service.applyToDocument(document: document, edit: edit);

    expect(result.isApplied, isTrue);
    expect(result.appliedEditCount, 2);
    expect(result.document.text, 'one beta three');
    expect(result.document.revision, 8);
  });

  test('workspace edit rejects stale revision and overlapping ranges', () {
    const service = EditorTransactionService();
    const document = DocumentState(
      documentId: 'sample.styio',
      text: 'abcdef',
      revision: 2,
    );
    final staleEdit = const WorkspaceEdit(
      source: WorkspaceEditSource.agentPatch,
      precondition: WorkspaceEditPrecondition(
        documentId: 'sample.styio',
        expectedRevision: 1,
      ),
      edits: <WorkspaceTextEdit>[
        WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 0, end: 1),
          newText: 'A',
        ),
      ],
    );
    final overlappingEdit = WorkspaceEdit.singleDocument(
      document: document,
      source: WorkspaceEditSource.searchReplace,
      edits: const <WorkspaceTextEdit>[
        WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 0, end: 3),
          newText: 'abc',
        ),
        WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 2, end: 4),
          newText: 'cd',
        ),
      ],
    );

    expect(
      service
          .applyToDocument(document: document, edit: staleEdit)
          .validation
          .code,
      WorkspaceEditValidationCode.staleRevision,
    );
    expect(
      service
          .applyToDocument(document: document, edit: overlappingEdit)
          .validation
          .code,
      WorkspaceEditValidationCode.overlappingRanges,
    );
  });

  test('editor formatting edits route through transaction service', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'alpha beta gamma',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(6),
    );

    controller.applyFormattingEdits(
      const <FormattingEdit>[
        FormattingEdit(
          range: SourceRange(start: 0, end: 5),
          newText: 'one',
        ),
        FormattingEdit(
          range: SourceRange(start: 11, end: 16),
          newText: 'three',
        ),
      ],
      source: WorkspaceEditSource.rename,
      label: 'test rename',
    );

    expect(controller.document.text, 'one beta three');
    expect(controller.document.revision, 1);
    expect(controller.selection.end, 4);
    expect(controller.canUndo, isTrue);
  });
}
