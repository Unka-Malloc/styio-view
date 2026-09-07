import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/input/editor_composition.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';

void main() {
  const documentId = 'document';

  EditorSelectionSet caret(int offset, int length) => EditorSelectionSet.single(
    SelectionState.collapsed(offset),
    documentLength: length,
  );

  group('EditorCompositionState', () {
    test('provisional updates preserve captured multi-selection anchors', () {
      const source = 'one two';
      final selections = EditorSelectionSet.normalized(
        selections: const <SelectionState>[
          SelectionState(baseOffset: 0, extentOffset: 3),
          SelectionState.collapsed(7),
        ],
        primaryIndex: 1,
        documentLength: source.length,
      );

      final composing = const EditorCompositionState.idle()
          .start(
            documentId: documentId,
            documentText: source,
            revision: 4,
            selectionSet: selections,
            connectionGeneration: 2,
            sequence: 0,
          )
          .nextState;
      final update = composing.update(
        revision: 4,
        selectionSet: selections,
        connectionGeneration: 2,
        sequence: 1,
        provisionalText: '語',
        provisionalSelection: const EditorInputRange(start: 1, end: 1),
        composingRange: const EditorInputRange(start: 0, end: 1),
      );

      expect(update.kind, EditorCompositionTransitionKind.provisional);
      expect(update.nextState.selectionSet, same(selections));
      expect(update.nextState.provisionalText, '語');
      expect(update.commitIntent, isNull);

      final commit = update.nextState.finalize(
        revision: 4,
        selectionSet: selections,
        connectionGeneration: 2,
        sequence: 2,
        reason: EditorCompositionTransitionReason.platformCommit,
      );
      expect(commit.nextState.phase, EditorCompositionPhase.idle);
      expect(commit.commitIntent!.selectionSet, same(selections));
      expect(commit.commitIntent!.text, '語');
      expect(commit.commitIntent!.expectedRevision, 4);
    });

    test('two-step finalization correlates and clears exactly once', () {
      const source = 'x';
      final selections = caret(1, source.length);
      final composing = const EditorCompositionState.idle()
          .start(
            documentId: documentId,
            documentText: source,
            revision: 1,
            selectionSet: selections,
            connectionGeneration: 5,
            sequence: 10,
          )
          .nextState
          .update(
            revision: 1,
            selectionSet: selections,
            connectionGeneration: 5,
            sequence: 11,
            provisionalText: 'é',
            provisionalSelection: const EditorInputRange(start: 1, end: 1),
            composingRange: const EditorInputRange(start: 0, end: 1),
          )
          .nextState;

      final begun = composing.beginFinalize(
        revision: 1,
        selectionSet: selections,
        connectionGeneration: 5,
        sequence: 12,
        reason: EditorCompositionTransitionReason.focusLoss,
      );
      expect(begun.nextState.phase, EditorCompositionPhase.finalizing);
      expect(begun.commitIntent!.sequence, 12);

      final wrongResult = begun.nextState.resolveFinalization(
        connectionGeneration: 5,
        sequence: 11,
        accepted: true,
      );
      expect(wrongResult.kind, EditorCompositionTransitionKind.ignored);
      expect(wrongResult.nextState.phase, EditorCompositionPhase.finalizing);

      final result = begun.nextState.resolveFinalization(
        connectionGeneration: 5,
        sequence: 12,
        accepted: true,
      );
      expect(result.kind, EditorCompositionTransitionKind.commit);
      expect(result.nextState.phase, EditorCompositionPhase.idle);
      expect(result.commitIntent, isNull);
    });

    test('revision and anchors reject while old callbacks are ignored', () {
      const source = 'seed';
      final selections = caret(4, source.length);
      final composing = const EditorCompositionState.idle()
          .start(
            documentId: documentId,
            documentText: source,
            revision: 3,
            selectionSet: selections,
            connectionGeneration: 8,
            sequence: 1,
          )
          .nextState;

      final old = composing.update(
        revision: 3,
        selectionSet: selections,
        connectionGeneration: 7,
        sequence: 99,
        provisionalText: 'old',
        provisionalSelection: const EditorInputRange(start: 0, end: 0),
        composingRange: const EditorInputRange(start: 0, end: 0),
      );
      expect(old.kind, EditorCompositionTransitionKind.ignored);
      expect(old.nextState, same(composing));

      final stale = composing.update(
        revision: 4,
        selectionSet: selections,
        connectionGeneration: 8,
        sequence: 2,
        provisionalText: 'new',
        provisionalSelection: const EditorInputRange(start: 0, end: 0),
        composingRange: const EditorInputRange(start: 0, end: 0),
      );
      expect(stale.kind, EditorCompositionTransitionKind.rejected);
      expect(stale.reason, EditorCompositionTransitionReason.staleRevision);
      expect(stale.nextState.phase, EditorCompositionPhase.idle);

      final changed = EditorSelectionSet.single(
        const SelectionState.collapsed(0),
        documentLength: source.length,
      );
      final anchorMismatch = composing.cancel(
        revision: 3,
        selectionSet: changed,
        connectionGeneration: 8,
        sequence: 2,
        reason: EditorCompositionTransitionReason.explicitCancel,
      );
      expect(anchorMismatch.kind, EditorCompositionTransitionKind.rejected);
      expect(
        anchorMismatch.reason,
        EditorCompositionTransitionReason.selectionChanged,
      );
    });

    test('duplicate terminal events cannot emit a second commit', () {
      const source = '';
      final selections = caret(0, 0);
      final composing = const EditorCompositionState.idle()
          .start(
            documentId: documentId,
            documentText: source,
            revision: 0,
            selectionSet: selections,
            connectionGeneration: 1,
            sequence: 0,
          )
          .nextState
          .update(
            revision: 0,
            selectionSet: selections,
            connectionGeneration: 1,
            sequence: 1,
            provisionalText: 'a',
            provisionalSelection: const EditorInputRange(start: 1, end: 1),
            composingRange: const EditorInputRange(start: 0, end: 1),
          )
          .nextState;
      final committed = composing.finalize(
        revision: 0,
        selectionSet: selections,
        connectionGeneration: 1,
        sequence: 2,
        reason: EditorCompositionTransitionReason.platformCommit,
      );
      final duplicate = committed.nextState.finalize(
        revision: 0,
        selectionSet: selections,
        connectionGeneration: 1,
        sequence: 2,
        reason: EditorCompositionTransitionReason.platformCommit,
      );
      expect(committed.commitIntent, isNotNull);
      expect(duplicate.kind, EditorCompositionTransitionKind.ignored);
      expect(duplicate.commitIntent, isNull);
    });

    test('oversized primary selection exposes an empty bounded window', () {
      final source = List<String>.filled(9000, 'a').join();
      final selections = EditorSelectionSet.single(
        SelectionState(baseOffset: 0, extentOffset: source.length),
        documentLength: source.length,
      );
      final started = const EditorCompositionState.idle().start(
        documentId: documentId,
        documentText: source,
        revision: 1,
        selectionSet: selections,
        connectionGeneration: 1,
        sequence: 0,
      );

      expect(started.nextState.window.text, isEmpty);
      expect(started.nextState.window.documentStart, 0);
      expect(started.nextState.window.completePrimaryRange.length, 9000);
    });

    test('platform ranges may split graphemes but not surrogate pairs', () {
      final selections = caret(0, 0);
      final composing = const EditorCompositionState.idle()
          .start(
            documentId: documentId,
            documentText: '',
            revision: 0,
            selectionSet: selections,
            connectionGeneration: 1,
            sequence: 0,
          )
          .nextState;
      final invalid = composing.update(
        revision: 0,
        selectionSet: selections,
        connectionGeneration: 1,
        sequence: 1,
        provisionalText: '😀',
        provisionalSelection: const EditorInputRange(start: 1, end: 1),
        composingRange: const EditorInputRange(start: 0, end: 2),
      );
      expect(invalid.kind, EditorCompositionTransitionKind.rejected);
      expect(
        invalid.reason,
        EditorCompositionTransitionReason.invalidPlatformRange,
      );
    });
  });
}
