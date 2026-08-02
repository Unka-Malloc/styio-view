import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/controllers/editor_session_facade.dart';
import 'package:vityo_app/src/ide/editor/document/document_state.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/ide/editor/transactions/transactions.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';

void main() {
  group('editor position mapping', () {
    test('requires explicit left or right association at insertion', () {
      final edits = <WorkspaceTextEdit>[
        const WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 2, end: 2),
          newText: 'XYZ',
        ),
      ];

      expect(
        mapEditorPositionThroughEdits(
          position: 2,
          editsAscending: edits,
          association: EditorPositionAssociation.left,
        ),
        2,
      );
      expect(
        mapEditorPositionThroughEdits(
          position: 2,
          editsAscending: edits,
          association: EditorPositionAssociation.right,
        ),
        5,
      );
    });

    test('maps replacement start, interior, and end explicitly', () {
      final edits = <WorkspaceTextEdit>[
        const WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 2, end: 5),
          newText: 'XY',
        ),
      ];

      for (final position in <int>[2, 3]) {
        expect(
          mapEditorPositionThroughEdits(
            position: position,
            editsAscending: edits,
            association: EditorPositionAssociation.left,
          ),
          2,
        );
        expect(
          mapEditorPositionThroughEdits(
            position: position,
            editsAscending: edits,
            association: EditorPositionAssociation.right,
          ),
          4,
        );
      }
      for (final association in EditorPositionAssociation.values) {
        expect(
          mapEditorPositionThroughEdits(
            position: 5,
            editsAscending: edits,
            association: association,
          ),
          4,
        );
      }
    });

    test('associates adjacent replacement boundary on either side', () {
      final edits = <WorkspaceTextEdit>[
        const WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 1, end: 3),
          newText: 'X',
        ),
        const WorkspaceTextEdit(
          documentId: 'sample.styio',
          range: SourceRange(start: 3, end: 5),
          newText: 'YY',
        ),
      ];

      expect(
        mapEditorPositionThroughEdits(
          position: 3,
          editsAscending: edits,
          association: EditorPositionAssociation.left,
        ),
        2,
      );
      expect(
        mapEditorPositionThroughEdits(
          position: 3,
          editsAscending: edits,
          association: EditorPositionAssociation.right,
        ),
        4,
      );
    });

    test(
      'right association crosses an insertion into an adjacent replacement',
      () {
        final edits = <WorkspaceTextEdit>[
          const WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 2, end: 2),
            newText: 'X',
          ),
          const WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 2, end: 4),
            newText: 'YZ',
          ),
        ];

        expect(
          mapEditorPositionThroughEdits(
            position: 2,
            editsAscending: edits,
            association: EditorPositionAssociation.left,
          ),
          2,
        );
        expect(
          mapEditorPositionThroughEdits(
            position: 2,
            editsAscending: edits,
            association: EditorPositionAssociation.right,
          ),
          5,
        );
      },
    );
  });

  group('normalized edit batches', () {
    const document = DocumentState(
      documentId: 'sample.styio',
      text: 'abcdef',
      revision: 4,
    );
    const service = EditorTransactionService();

    test(
      'collapses exact duplicates and applies descending in one revision',
      () {
        final edit = WorkspaceEdit.singleDocument(
          document: document,
          source: WorkspaceEditSource.userInput,
          edits: const <WorkspaceTextEdit>[
            WorkspaceTextEdit(
              documentId: 'sample.styio',
              range: SourceRange(start: 4, end: 6),
              newText: 'Z',
            ),
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

        final result = service.applyToDocument(document: document, edit: edit);

        expect(result.isApplied, isTrue);
        expect(result.document.text, 'aXbcdZ');
        expect(result.document.revision, 5);
        expect(result.appliedEditCount, 2);
        expect(result.normalizedEdits.map((value) => value.range.start), <int>[
          1,
          4,
        ]);
      },
    );

    test('rejects conflicting insertions and intersections atomically', () {
      for (final edits in <List<WorkspaceTextEdit>>[
        const <WorkspaceTextEdit>[
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 2, end: 2),
            newText: 'X',
          ),
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 2, end: 2),
            newText: 'Y',
          ),
        ],
        const <WorkspaceTextEdit>[
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 0, end: 3),
            newText: 'X',
          ),
          WorkspaceTextEdit(
            documentId: 'sample.styio',
            range: SourceRange(start: 2, end: 5),
            newText: 'Y',
          ),
        ],
      ]) {
        final result = service.applyToDocument(
          document: document,
          edit: WorkspaceEdit.singleDocument(
            document: document,
            source: WorkspaceEditSource.userInput,
            edits: edits,
          ),
        );

        expect(
          result.validation.code,
          WorkspaceEditValidationCode.overlappingRanges,
        );
        expect(result.appliedEditCount, 0);
        expect(identical(result.document, document), isTrue);
      }
    });
  });

  test('multi-selection text input commits and restores one full intent', () {
    final controller = EditorSessionFacade(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'alpha beta gamma',
        revision: 9,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    controller.selectSelections(const <SelectionState>[
      SelectionState.collapsed(6),
      SelectionState(baseOffset: 0, extentOffset: 5),
      SelectionState(baseOffset: 16, extentOffset: 11),
      SelectionState.collapsed(6),
    ], primaryIndex: 2);
    final before = controller.selectionSet;

    controller.insertText('Z');

    expect(controller.document.text, 'Z Zbeta Z');
    expect(controller.document.revision, 10);
    expect(_signature(controller.selectionSet), '1:1|3:3|9:9@2');
    expect(controller.historyController.undoDepth, 1);

    controller.undo();
    expect(controller.document.text, 'alpha beta gamma');
    expect(controller.document.revision, 9);
    expect(controller.selectionSet, before);

    controller.redo();
    expect(controller.document.text, 'Z Zbeta Z');
    expect(_signature(controller.selectionSet), '1:1|3:3|9:9@2');
  });

  test('stale command leaves document, set, and history untouched', () {
    final controller = EditorSessionFacade(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'abc',
        revision: 3,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    controller.selectSelections(const <SelectionState>[
      SelectionState.collapsed(0),
      SelectionState.collapsed(3),
    ], primaryIndex: 1);
    final before = controller.selectionSet;
    final transaction = controller.createCommandTransaction(
      commandId: 'stale',
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
            newText: 'X',
          ),
        ],
      ),
    );

    final result = controller.applyCommandTransaction(transaction);

    expect(result.isApplied, isFalse);
    expect(controller.document.text, 'abc');
    expect(controller.document.revision, 3);
    expect(controller.selectionSet, before);
    expect(controller.historyController.undoDepth, 0);
    expect(controller.historyController.redoDepth, 0);
  });
}

String _signature(EditorSelectionSet set) {
  final values = set.selections
      .map((selection) => '${selection.baseOffset}:${selection.extentOffset}')
      .join('|');
  return '$values@${set.primaryIndex}';
}
