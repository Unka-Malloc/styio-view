import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/input/editor_composition.dart';
import 'package:vityo_app/src/ide/editor/input/unicode_boundary_index.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';

void main() {
  group('REQ-INPUT-002 composition and Unicode acceptance', () {
    test(
      'provisional multi-selection composition emits one anchored commit',
      () {
        const source = 'alpha beta';
        final anchors = EditorSelectionSet.normalized(
          selections: const <SelectionState>[
            SelectionState(baseOffset: 0, extentOffset: 5),
            SelectionState.collapsed(6),
          ],
          primaryIndex: 1,
          documentLength: source.length,
        );
        const idle = EditorCompositionState.idle();

        final started = idle.start(
          documentId: 'composition.styio',
          documentText: source,
          revision: 7,
          selectionSet: anchors,
          connectionGeneration: 3,
          sequence: 0,
        );
        expect(started.kind, EditorCompositionTransitionKind.started);
        expect(started.nextState.phase, EditorCompositionPhase.composing);
        expect(
          started.nextState.window.codeUnitLength,
          lessThanOrEqualTo(8192),
        );
        expect(started.nextState.selectionSet, anchors);
        expect(started.commitIntent, isNull);

        final updated = started.nextState.update(
          revision: 7,
          selectionSet: anchors,
          connectionGeneration: 3,
          sequence: 1,
          provisionalText: '日本',
          provisionalSelection: const EditorInputRange(start: 2, end: 2),
          composingRange: const EditorInputRange(start: 0, end: 2),
        );
        expect(updated.kind, EditorCompositionTransitionKind.provisional);
        expect(updated.nextState.provisionalText, '日本');
        expect(updated.commitIntent, isNull);
        // The pure model has no mutation route to committed source or history.
        expect(source, 'alpha beta');

        final committed = updated.nextState.finalize(
          revision: 7,
          selectionSet: anchors,
          connectionGeneration: 3,
          sequence: 2,
          reason: EditorCompositionTransitionReason.platformCommit,
        );
        expect(committed.kind, EditorCompositionTransitionKind.commit);
        expect(committed.nextState.phase, EditorCompositionPhase.idle);
        expect(committed.commitIntent, isNotNull);
        expect(committed.commitIntent!.text, '日本');
        expect(committed.commitIntent!.selectionSet, anchors);
        expect(committed.commitIntent!.expectedRevision, 7);
        expect(committed.commitIntent!.connectionGeneration, 3);

        final duplicate = committed.nextState.finalize(
          revision: 7,
          selectionSet: anchors,
          connectionGeneration: 3,
          sequence: 2,
          reason: EditorCompositionTransitionReason.platformCommit,
        );
        expect(duplicate.kind, EditorCompositionTransitionKind.ignored);
        expect(duplicate.commitIntent, isNull);
      },
    );

    test('cancel, focus loss, stale state, and reconnect are explicit', () {
      const source = 'seed';
      final anchors = EditorSelectionSet.single(
        const SelectionState.collapsed(4),
        documentLength: source.length,
      );

      final composing = const EditorCompositionState.idle()
          .start(
            documentId: 'composition.styio',
            documentText: source,
            revision: 4,
            selectionSet: anchors,
            connectionGeneration: 8,
            sequence: 0,
          )
          .nextState
          .update(
            revision: 4,
            selectionSet: anchors,
            connectionGeneration: 8,
            sequence: 1,
            provisionalText: 'é',
            provisionalSelection: const EditorInputRange(start: 1, end: 1),
            composingRange: const EditorInputRange(start: 0, end: 1),
          )
          .nextState;

      final canceled = composing.cancel(
        revision: 4,
        selectionSet: anchors,
        connectionGeneration: 8,
        sequence: 2,
        reason: EditorCompositionTransitionReason.explicitCancel,
      );
      expect(canceled.kind, EditorCompositionTransitionKind.canceled);
      expect(canceled.nextState.phase, EditorCompositionPhase.idle);
      expect(canceled.commitIntent, isNull);

      final focusLoss = composing.finalize(
        revision: 4,
        selectionSet: anchors,
        connectionGeneration: 8,
        sequence: 2,
        reason: EditorCompositionTransitionReason.focusLoss,
      );
      expect(focusLoss.kind, EditorCompositionTransitionKind.commit);
      expect(focusLoss.commitIntent!.text, 'é');

      final staleRevision = composing.update(
        revision: 5,
        selectionSet: anchors,
        connectionGeneration: 8,
        sequence: 2,
        provisionalText: 'ignored',
        provisionalSelection: const EditorInputRange(start: 7, end: 7),
        composingRange: const EditorInputRange(start: 0, end: 7),
      );
      expect(staleRevision.kind, EditorCompositionTransitionKind.rejected);
      expect(
        staleRevision.reason,
        EditorCompositionTransitionReason.staleRevision,
      );
      expect(staleRevision.nextState.phase, EditorCompositionPhase.idle);
      expect(staleRevision.commitIntent, isNull);

      final changedSelections = EditorSelectionSet.single(
        const SelectionState.collapsed(0),
        documentLength: source.length,
      );
      final changed = composing.update(
        revision: 4,
        selectionSet: changedSelections,
        connectionGeneration: 8,
        sequence: 2,
        provisionalText: 'ignored',
        provisionalSelection: const EditorInputRange(start: 7, end: 7),
        composingRange: const EditorInputRange(start: 0, end: 7),
      );
      expect(changed.kind, EditorCompositionTransitionKind.rejected);
      expect(
        changed.reason,
        EditorCompositionTransitionReason.selectionChanged,
      );
      expect(changed.commitIntent, isNull);

      final oldConnection = composing.update(
        revision: 4,
        selectionSet: anchors,
        connectionGeneration: 7,
        sequence: 2,
        provisionalText: 'ignored',
        provisionalSelection: const EditorInputRange(start: 7, end: 7),
        composingRange: const EditorInputRange(start: 0, end: 7),
      );
      expect(oldConnection.kind, EditorCompositionTransitionKind.ignored);
      expect(
        oldConnection.reason,
        EditorCompositionTransitionReason.staleGeneration,
      );

      final reconnected = focusLoss.nextState.start(
        documentId: 'composition.styio',
        documentText: '$sourceé',
        revision: 5,
        selectionSet: EditorSelectionSet.single(
          const SelectionState.collapsed(5),
          documentLength: 5,
        ),
        connectionGeneration: 9,
        sequence: 0,
      );
      expect(reconnected.kind, EditorCompositionTransitionKind.started);
      expect(reconnected.nextState.connectionGeneration, 9);
      expect(reconnected.nextState.provisionalText, isEmpty);
      expect(reconnected.nextState.expectedRevision, 5);
    });

    test('grapheme navigation and deletion never split UTF-16 text', () {
      const combined = 'e\u0301';
      const family = '👨‍👩‍👧‍👦';
      const text = 'A$combined$family אב';
      final combinedStart = 1;
      final familyStart = combinedStart + combined.length;
      final familyEnd = familyStart + family.length;
      final rtlStart = familyEnd + 1;
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: 'unicode.styio',
        revision: 12,
        text: text,
        anchorOffset: familyStart,
        maxCodeUnits: 8192,
      );

      expect(
        index.nextBoundary(combinedStart, documentRevision: 12),
        familyStart,
      );
      expect(index.nextBoundary(familyStart, documentRevision: 12), familyEnd);
      expect(
        index.previousBoundary(familyEnd, documentRevision: 12),
        familyStart,
      );
      expect(
        index.clampBoundary(
          familyStart + 1,
          bias: UnicodeBoundaryBias.backward,
          documentRevision: 12,
        ),
        familyStart,
      );
      expect(
        index.clampBoundary(
          familyStart + 1,
          bias: UnicodeBoundaryBias.forward,
          documentRevision: 12,
        ),
        familyEnd,
      );
      expect(
        index.deletionRange(familyEnd, forward: false, documentRevision: 12),
        EditorInputRange(start: familyStart, end: familyEnd),
      );
      expect(index.nextBoundary(rtlStart, documentRevision: 12), rtlStart + 1);
      expect(
        () => index.nextBoundary(familyStart, documentRevision: 13),
        throwsStateError,
      );
    });

    test('the boundary index scans only its bounded revision window', () {
      final text =
          '${List<String>.filled(12000, 'a').join()}👩🏽‍💻'
          '${List<String>.filled(12000, 'b').join()}';
      final emojiStart = text.indexOf('👩');
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: 'large-unicode.styio',
        revision: 2,
        text: text,
        anchorOffset: emojiStart,
        maxCodeUnits: 256,
      );

      expect(index.indexedCodeUnitCount, lessThanOrEqualTo(256));
      expect(index.windowStart, greaterThan(0));
      expect(index.windowEnd, lessThan(text.length));
      expect(index.isBoundary(emojiStart, documentRevision: 2), isTrue);
      expect(
        index.nextBoundary(emojiStart, documentRevision: 2),
        emojiStart + '👩🏽‍💻'.length,
      );
    });
  });
}
