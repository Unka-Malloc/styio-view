import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/controllers/history_controller.dart';
import 'package:vityo_app/src/ide/editor/controllers/selection_controller.dart';
import 'package:vityo_app/src/ide/editor/document/document_state.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';

void main() {
  group('EditorSelectionSet', () {
    test(
      'rejects empty input, invalid primary, and invalid document length',
      () {
        expect(
          () => EditorSelectionSet.normalized(
            selections: const <SelectionState>[],
            primaryIndex: 0,
            documentLength: 10,
          ),
          throwsArgumentError,
        );
        expect(
          () => EditorSelectionSet.normalized(
            selections: const <SelectionState>[SelectionState.collapsed(0)],
            primaryIndex: 1,
            documentLength: 10,
          ),
          throwsArgumentError,
        );
        expect(
          () => EditorSelectionSet.single(
            const SelectionState.collapsed(0),
            documentLength: -1,
          ),
          throwsArgumentError,
        );
      },
    );

    test('clamps, sorts, deduplicates, and merges touching selections', () {
      final set = EditorSelectionSet.normalized(
        selections: const <SelectionState>[
          SelectionState(baseOffset: 20, extentOffset: 17),
          SelectionState.collapsed(4),
          SelectionState(baseOffset: -3, extentOffset: 2),
          SelectionState(baseOffset: 7, extentOffset: 4),
          SelectionState.collapsed(4),
          SelectionState(baseOffset: 15, extentOffset: 12),
        ],
        primaryIndex: 3,
        documentLength: 18,
      );

      expect(set.selections, const <SelectionState>[
        SelectionState(baseOffset: 0, extentOffset: 2),
        SelectionState(baseOffset: 7, extentOffset: 4),
        SelectionState(baseOffset: 15, extentOffset: 12),
        SelectionState(baseOffset: 18, extentOffset: 17),
      ]);
      expect(set.primaryIndex, 1);
      expect(identical(set.primarySelection, set.selections[1]), isTrue);
    });

    test('primary member supplies direction for its merged cluster', () {
      final set = EditorSelectionSet.normalized(
        selections: const <SelectionState>[
          SelectionState(baseOffset: 2, extentOffset: 6),
          SelectionState(baseOffset: 9, extentOffset: 5),
          SelectionState(baseOffset: 8, extentOffset: 12),
        ],
        primaryIndex: 1,
        documentLength: 20,
      );

      expect(set.selections, const <SelectionState>[
        SelectionState(baseOffset: 12, extentOffset: 2),
      ]);
      expect(set.primaryIndex, 0);
    });

    test('normalization is independent of non-primary input order', () {
      final first = EditorSelectionSet.normalized(
        selections: const <SelectionState>[
          SelectionState(baseOffset: 18, extentOffset: 14),
          SelectionState(baseOffset: 2, extentOffset: 5),
          SelectionState.collapsed(9),
        ],
        primaryIndex: 2,
        documentLength: 20,
      );
      final second = EditorSelectionSet.normalized(
        selections: const <SelectionState>[
          SelectionState(baseOffset: 2, extentOffset: 5),
          SelectionState.collapsed(9),
          SelectionState(baseOffset: 18, extentOffset: 14),
        ],
        primaryIndex: 1,
        documentLength: 20,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('preserves primary membership when duplicate cursors collapse', () {
      final set = EditorSelectionSet.normalized(
        selections: const <SelectionState>[
          SelectionState.collapsed(8),
          SelectionState.collapsed(3),
          SelectionState.collapsed(8),
        ],
        primaryIndex: 2,
        documentLength: 10,
      );

      expect(set.selections, const <SelectionState>[
        SelectionState.collapsed(3),
        SelectionState.collapsed(8),
      ]);
      expect(set.primaryIndex, 1);
    });

    test('has structural value semantics and an unmodifiable collection', () {
      final source = <SelectionState>[
        const SelectionState.collapsed(1),
        const SelectionState(baseOffset: 4, extentOffset: 6),
      ];
      final first = EditorSelectionSet.normalized(
        selections: source,
        primaryIndex: 1,
        documentLength: 10,
      );
      final second = EditorSelectionSet.normalized(
        selections: List<SelectionState>.of(source),
        primaryIndex: 1,
        documentLength: 10,
      );

      source[0] = const SelectionState.collapsed(9);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        () => first.selections.add(const SelectionState.collapsed(8)),
        throwsUnsupportedError,
      );
      expect(first.selections.first, const SelectionState.collapsed(1));
    });
  });

  test('SelectionController stores one set and projects its primary', () {
    final controller = SelectionController(
      const SelectionState.collapsed(20),
      documentLength: 10,
    );

    expect(
      controller.selectionSet,
      EditorSelectionSet.single(
        const SelectionState.collapsed(10),
        documentLength: 10,
      ),
    );
    expect(
      identical(controller.selection, controller.selectionSet.primarySelection),
      isTrue,
    );

    controller.structuredSelectionStack.add(
      const SelectionState(baseOffset: 0, extentOffset: 10),
    );
    controller.selectSelections(
      const <SelectionState>[
        SelectionState.collapsed(8),
        SelectionState(baseOffset: 2, extentOffset: 4),
      ],
      primaryIndex: 0,
      documentLength: 10,
    );

    expect(controller.selectionSet.selections.length, 2);
    expect(controller.selection, const SelectionState.collapsed(8));
    expect(controller.structuredSelectionStack, isEmpty);

    controller.selectCollapsed(50, documentLength: 10);
    expect(controller.selectionSet.selections, const <SelectionState>[
      SelectionState.collapsed(10),
    ]);
    controller.dispose();
  });

  test('history exchanges complete immutable selection-set snapshots', () {
    const beforeDocument = DocumentState(
      documentId: 'sample.styio',
      text: 'abcdefghij',
      revision: 4,
    );
    const afterDocument = DocumentState(
      documentId: 'sample.styio',
      text: 'aXdefYghij',
      revision: 5,
    );
    final beforeSet = EditorSelectionSet.normalized(
      selections: const <SelectionState>[
        SelectionState(baseOffset: 1, extentOffset: 3),
        SelectionState.collapsed(6),
      ],
      primaryIndex: 1,
      documentLength: beforeDocument.length,
    );
    final afterSet = EditorSelectionSet.normalized(
      selections: const <SelectionState>[
        SelectionState.collapsed(2),
        SelectionState.collapsed(6),
      ],
      primaryIndex: 1,
      documentLength: afterDocument.length,
    );
    final history = HistoryController();
    final before = EditorHistorySnapshot(
      document: beforeDocument,
      selectionSet: beforeSet,
    );
    final after = EditorHistorySnapshot(
      document: afterDocument,
      selectionSet: afterSet,
    );

    history.pushUndo(before);
    history.pushRedo(after);

    final restoredBefore = history.popUndo()!;
    final restoredAfter = history.popRedo()!;
    expect(identical(restoredBefore.selectionSet, beforeSet), isTrue);
    expect(restoredBefore.selectionSet.selections, beforeSet.selections);
    expect(restoredBefore.selection, beforeSet.primarySelection);
    expect(restoredBefore.document, same(beforeDocument));
    expect(identical(restoredAfter.selectionSet, afterSet), isTrue);
    expect(restoredAfter.selectionSet.selections, afterSet.selections);
    expect(restoredAfter.document, same(afterDocument));
    history.dispose();
  });
}
