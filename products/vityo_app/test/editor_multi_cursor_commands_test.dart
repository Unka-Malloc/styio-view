import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/controllers/selection_controller.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_interaction.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';

void main() {
  group('EditorSelectionInteraction', () {
    test('toggle is primary preserving and retains caret affinity', () {
      const interaction = EditorSelectionInteraction();
      final initial = EditorSelectionSet.single(
        const SelectionState.collapsed(2),
        documentLength: 20,
      );

      final added = interaction.addOrToggleCursor(
        current: initial,
        position: const EditorCaretPosition(
          offset: 12,
          affinity: EditorCaretAffinity.upstream,
          desiredVisualX: 32,
        ),
        documentLength: 20,
      );
      expect(added.primarySelection.extentOffset, 12);
      expect(
        added.primarySelection.extentAffinity,
        EditorCaretAffinity.upstream,
      );
      expect(added.primarySelection.desiredVisualX, 32);

      final secondary = interaction.addOrToggleCursor(
        current: added,
        position: const EditorCaretPosition(offset: 7),
        documentLength: 20,
        makePrimary: false,
      );
      final removed = interaction.addOrToggleCursor(
        current: secondary,
        position: const EditorCaretPosition(offset: 7),
        documentLength: 20,
      );
      expect(removed.primarySelection, added.primarySelection);
      expect(removed.selections, added.selections);
      expect(
        interaction.addOrToggleCursor(
          current: removed,
          position: const EditorCaretPosition(offset: 12),
          documentLength: 20,
        ),
        same(removed),
      );
    });

    test(
      'resolved movement transforms every selection and normalizes once',
      () {
        const interaction = EditorSelectionInteraction();
        final current = EditorSelectionSet.normalized(
          selections: const <SelectionState>[
            SelectionState.collapsed(2),
            SelectionState.collapsed(8),
            SelectionState.collapsed(14),
          ],
          primaryIndex: 1,
          documentLength: 20,
        );
        final extended = interaction.moveOrExtend(
          current: current,
          positions: const <EditorCaretPosition>[
            EditorCaretPosition(offset: 5),
            EditorCaretPosition(offset: 10, desiredVisualX: 48),
            EditorCaretPosition(offset: 10),
          ],
          extend: true,
          documentLength: 20,
        );

        expect(extended.selections, const <SelectionState>[
          SelectionState(baseOffset: 2, extentOffset: 5),
          SelectionState(baseOffset: 8, extentOffset: 14, desiredVisualX: 48),
        ]);
        expect(extended.primaryIndex, 1);
      },
    );

    test('rectangle uses ordered layout facts and directed source edges', () {
      const interaction = EditorSelectionInteraction();
      final selectionSet = interaction.projectRectangle(
        lines: const <EditorRectangularLineProjection>[
          EditorRectangularLineProjection(
            lineIndex: 2,
            left: EditorCaretPosition(offset: 7),
            right: EditorCaretPosition(offset: 7),
          ),
          EditorRectangularLineProjection(
            lineIndex: 4,
            left: EditorCaretPosition(
              offset: 15,
              affinity: EditorCaretAffinity.upstream,
            ),
            right: EditorCaretPosition(offset: 11),
          ),
        ],
        primaryLineIndex: 4,
        horizontalDirection: EditorRectangleHorizontalDirection.leftToRight,
        documentLength: 18,
      );

      expect(selectionSet.selections[0], const SelectionState.collapsed(7));
      expect(selectionSet.primarySelection.baseOffset, 15);
      expect(selectionSet.primarySelection.extentOffset, 11);
      expect(
        selectionSet.primarySelection.baseAffinity,
        EditorCaretAffinity.upstream,
      );
    });
  });

  test('SelectionController owns command intent and rejects stale facts', () {
    final controller = SelectionController(
      const SelectionState.collapsed(3),
      documentLength: 12,
    );
    addTearDown(controller.dispose);

    controller.requestInteractionCommand(
      EditorSelectionCommand.moveCursorsDown,
    );
    final firstSequence = controller.pendingInteractionCommand!.sequence;
    controller.requestInteractionCommand(
      EditorSelectionCommand.extendSelectionsDown,
    );
    final currentSequence = controller.pendingInteractionCommand!.sequence;
    expect(
      controller.applyResolvedMovementCommand(
        sequence: firstSequence,
        positions: const <EditorCaretPosition>[EditorCaretPosition(offset: 6)],
        documentLength: 12,
      ),
      isFalse,
    );
    expect(
      controller.applyResolvedMovementCommand(
        sequence: currentSequence,
        positions: const <EditorCaretPosition>[
          EditorCaretPosition(offset: 6, desiredVisualX: 24),
        ],
        documentLength: 12,
      ),
      isTrue,
    );
    expect(
      controller.selection,
      const SelectionState(baseOffset: 3, extentOffset: 6, desiredVisualX: 24),
    );
  });

  test('selection commands publish editor-safe metadata and bindings', () {
    const ids = <AppCommandId>[
      AppCommandId.addCursorAbove,
      AppCommandId.addCursorBelow,
      AppCommandId.removeSecondaryCursors,
      AppCommandId.moveCursorsLeft,
      AppCommandId.moveCursorsRight,
      AppCommandId.moveCursorsUp,
      AppCommandId.moveCursorsDown,
      AppCommandId.extendSelectionsLeft,
      AppCommandId.extendSelectionsRight,
      AppCommandId.extendSelectionsUp,
      AppCommandId.extendSelectionsDown,
      AppCommandId.extendColumnSelectionLeft,
      AppCommandId.extendColumnSelectionRight,
      AppCommandId.extendColumnSelectionUp,
      AppCommandId.extendColumnSelectionDown,
    ];

    for (final id in ids) {
      final descriptor = VityoCommandRegistry.descriptorFor(id);
      expect(descriptor.telemetryTargetSurface, AppCommandTargetSurface.editor);
      expect(
        descriptor.permissionRequirement,
        AppCommandPermissionRequirement.none,
      );
      expect(descriptor.telemetrySideEffect, AppCommandSideEffect.none);
      expect(descriptor.shortcuts, isNotEmpty);
    }
  });
}
