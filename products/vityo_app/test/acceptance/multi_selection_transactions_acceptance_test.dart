import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/controllers/editor_session_facade.dart';
import 'package:vityo_app/src/ide/editor/document/document_state.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/ide/editor/transactions/transactions.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';

void main() {
  group('transactional multi-selection acceptance', () {
    test(
      'normalizes an immutable directed selection set independent of input order',
      () {
        final first = _session(text: '0123456789');
        _selectSelections(first, const <SelectionState>[
          SelectionState(baseOffset: 8, extentOffset: 4),
          SelectionState.collapsed(2),
          SelectionState.collapsed(2),
          SelectionState(baseOffset: 7, extentOffset: 10),
          SelectionState(baseOffset: -4, extentOffset: 1),
          SelectionState.collapsed(1),
        ], primaryIndex: 0);

        final second = _session(text: '0123456789');
        _selectSelections(second, const <SelectionState>[
          SelectionState.collapsed(1),
          SelectionState(baseOffset: 7, extentOffset: 10),
          SelectionState(baseOffset: -4, extentOffset: 1),
          SelectionState.collapsed(2),
          SelectionState(baseOffset: 8, extentOffset: 4),
          SelectionState.collapsed(2),
        ], primaryIndex: 4);

        expect(_selectionSetSignature(first), '0:1|2:2|10:4@2');
        expect(_selectionSetSignature(second), _selectionSetSignature(first));
        expect(_primarySelectionSignature(first), '10:4');
        expect(identical(first.selection, _primarySelection(first)), isTrue);

        final dynamic publicSelections = _selectionSet(first).selections;
        expect(
          () => publicSelections.add(const SelectionState.collapsed(9)),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'commits mixed insert and replace points as one mapped history intent',
      () {
        const originalText = 'alpha beta gamma';
        final controller = _session(text: originalText, revision: 9);
        _selectSelections(controller, const <SelectionState>[
          SelectionState.collapsed(6),
          SelectionState(baseOffset: 0, extentOffset: 5),
          SelectionState(baseOffset: 16, extentOffset: 11),
          SelectionState.collapsed(6),
        ], primaryIndex: 2);
        final beforeSelections = _selectionSetSignature(controller);

        controller.insertText('Z');

        expect(controller.document.text, 'Z Zbeta Z');
        expect(controller.document.revision, 10);
        expect(_selectionSetSignature(controller), '1:1|3:3|9:9@2');
        expect(controller.historyController.undoDepth, 1);
        expect(controller.historyController.redoDepth, 0);

        final afterSelections = _selectionSetSignature(controller);
        controller.undo();

        expect(controller.document.text, originalText);
        expect(controller.document.revision, 9);
        expect(_selectionSetSignature(controller), beforeSelections);
        expect(controller.canUndo, isFalse);
        expect(controller.canRedo, isTrue);

        controller.redo();

        expect(controller.document.text, 'Z Zbeta Z');
        expect(controller.document.revision, 10);
        expect(_selectionSetSignature(controller), afterSelections);
        expect(controller.canRedo, isFalse);
      },
    );

    test('canonicalizes duplicate edits and rejects ambiguous edit points', () {
      const document = DocumentState(
        documentId: 'sample.styio',
        text: 'ab',
        revision: 4,
      );
      const service = EditorTransactionService();
      final duplicate = WorkspaceEdit.singleDocument(
        document: document,
        source: WorkspaceEditSource.userInput,
        edits: const <WorkspaceTextEdit>[
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 1, end: 1),
            newText: 'X',
          ),
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 1, end: 1),
            newText: 'X',
          ),
        ],
      );

      final duplicateResult = service.applyToDocument(
        document: document,
        edit: duplicate,
      );

      expect(duplicateResult.isApplied, isTrue);
      expect(duplicateResult.appliedEditCount, 1);
      expect(duplicateResult.document.text, 'aXb');
      expect(duplicateResult.document.revision, 5);

      final ambiguous = WorkspaceEdit.singleDocument(
        document: document,
        source: WorkspaceEditSource.userInput,
        edits: const <WorkspaceTextEdit>[
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 1, end: 1),
            newText: 'X',
          ),
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 1, end: 1),
            newText: 'Y',
          ),
        ],
      );

      final ambiguousResult = service.applyToDocument(
        document: document,
        edit: ambiguous,
      );

      expect(ambiguousResult.isApplied, isFalse);
      expect(
        ambiguousResult.validation.code,
        WorkspaceEditValidationCode.overlappingRanges,
      );
      expect(ambiguousResult.appliedEditCount, 0);
      expect(identical(ambiguousResult.document, document), isTrue);
      expect(ambiguousResult.document.text, 'ab');
      expect(ambiguousResult.document.revision, 4);
    });

    test(
      'rejects overlap and stale revision without partial session state',
      () {
        final controller = _session(text: 'abcdef', revision: 3);
        final originalSelection = _selectionSetSignature(controller);
        final overlapping = controller.createCommandTransaction(
          commandId: 'editor.acceptance.overlap',
          edit: WorkspaceEdit.singleDocument(
            document: controller.document,
            source: WorkspaceEditSource.userInput,
            edits: const <WorkspaceTextEdit>[
              WorkspaceTextEdit(
                documentId: 'sample.styio',
                range: SourceRange(start: 0, end: 3),
                newText: 'A',
              ),
              WorkspaceTextEdit(
                documentId: 'sample.styio',
                range: SourceRange(start: 2, end: 5),
                newText: 'B',
              ),
            ],
          ),
        );

        final overlapResult = controller.applyCommandTransaction(overlapping);

        expect(overlapResult.isApplied, isFalse);
        expect(
          overlapResult.result.validation.code,
          WorkspaceEditValidationCode.overlappingRanges,
        );
        _expectUnchanged(controller, originalSelection);

        final stale = controller.createCommandTransaction(
          commandId: 'editor.acceptance.stale',
          edit: const WorkspaceEdit(
            source: WorkspaceEditSource.userInput,
            precondition: WorkspaceEditPrecondition(
              documentId: 'sample.styio',
              expectedRevision: 2,
            ),
            edits: <WorkspaceTextEdit>[
              WorkspaceTextEdit(
                documentId: 'sample.styio',
                range: SourceRange(start: 0, end: 1),
                newText: 'A',
              ),
            ],
          ),
        );

        final staleResult = controller.applyCommandTransaction(stale);

        expect(staleResult.isApplied, isFalse);
        expect(
          staleResult.result.validation.code,
          WorkspaceEditValidationCode.staleRevision,
        );
        _expectUnchanged(controller, originalSelection);
      },
    );

    test('single-selection editing is a one-element set projection', () {
      final controller = _session(
        text: 'abc',
        initialSelection: const SelectionState(baseOffset: 1, extentOffset: 2),
      );

      expect(_selectionSetSignature(controller), '1:2@0');
      expect(
        identical(controller.selection, _primarySelection(controller)),
        isTrue,
      );

      controller.insertText('X');

      expect(controller.document.text, 'aXc');
      expect(controller.document.revision, 1);
      expect(_selectionSetSignature(controller), '2:2@0');
      expect(controller.historyController.undoDepth, 1);

      controller.undo();

      expect(controller.document.text, 'abc');
      expect(controller.document.revision, 0);
      expect(_selectionSetSignature(controller), '1:2@0');
    });
  });
}

EditorSessionFacade _session({
  required String text,
  int revision = 0,
  SelectionState? initialSelection,
}) {
  return EditorSessionFacade(
    initialDocument: DocumentState(
      documentId: 'sample.styio',
      text: text,
      revision: revision,
    ),
    languageService: const SimpleStyioLanguageService(),
    initialSelection: initialSelection,
  );
}

void _selectSelections(
  EditorSessionFacade controller,
  List<SelectionState> selections, {
  required int primaryIndex,
}) {
  final dynamic contract = controller;
  contract.selectSelections(selections, primaryIndex: primaryIndex);
}

dynamic _selectionSet(EditorSessionFacade controller) {
  final dynamic contract = controller;
  return contract.selectionSet;
}

SelectionState _primarySelection(EditorSessionFacade controller) {
  final dynamic set = _selectionSet(controller);
  return set.primarySelection as SelectionState;
}

String _primarySelectionSignature(EditorSessionFacade controller) {
  final selection = _primarySelection(controller);
  return '${selection.baseOffset}:${selection.extentOffset}';
}

String _selectionSetSignature(EditorSessionFacade controller) {
  final dynamic set = _selectionSet(controller);
  final selections = (set.selections as Iterable<dynamic>)
      .cast<SelectionState>();
  final values = selections
      .map((selection) => '${selection.baseOffset}:${selection.extentOffset}')
      .join('|');
  return '$values@${set.primaryIndex as int}';
}

void _expectUnchanged(
  EditorSessionFacade controller,
  String selectionSignature,
) {
  expect(controller.document.text, 'abcdef');
  expect(controller.document.revision, 3);
  expect(_selectionSetSignature(controller), selectionSignature);
  expect(controller.historyController.undoDepth, 0);
  expect(controller.historyController.redoDepth, 0);
}
