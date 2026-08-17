import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/controllers/editor_session_facade.dart';
import 'package:vityo_app/src/ide/editor/document/document_state.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_interaction.dart';
import 'package:vityo_app/src/ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';

void main() {
  group('REQ-INPUT-001 multi-cursor interaction acceptance', () {
    test('publishes the frozen editor-selection command IDs', () {
      const requiredNames = <String>{
        'addCursorAbove',
        'addCursorBelow',
        'removeSecondaryCursors',
        'moveCursorsLeft',
        'moveCursorsRight',
        'moveCursorsUp',
        'moveCursorsDown',
        'extendSelectionsLeft',
        'extendSelectionsRight',
        'extendSelectionsUp',
        'extendSelectionsDown',
        'extendColumnSelectionLeft',
        'extendColumnSelectionRight',
        'extendColumnSelectionUp',
        'extendColumnSelectionDown',
      };

      final registeredNames = AppCommandId.values
          .map((command) => command.name)
          .toSet();
      expect(registeredNames, containsAll(requiredNames));

      for (final name in requiredNames) {
        final descriptor = VityoCommandRegistry.descriptorForName(name);
        expect(descriptor, isNotNull, reason: '$name must be registered');
        expect(
          descriptor!.telemetryTargetSurface,
          AppCommandTargetSurface.editor,
        );
        expect(
          descriptor.permissionRequirement,
          AppCommandPermissionRequirement.none,
        );
        expect(descriptor.telemetrySideEffect, AppCommandSideEffect.none);
      }
    });

    test(
      'adds, toggles, and removes cursors without losing primary identity',
      () {
        const interaction = EditorSelectionInteraction();
        final initial = EditorSelectionSet.single(
          const SelectionState.collapsed(1),
          documentLength: 12,
        );

        final added = interaction.addOrToggleCursor(
          current: initial,
          position: const EditorCaretPosition(
            offset: 8,
            affinity: EditorCaretAffinity.upstream,
          ),
          documentLength: 12,
          makePrimary: true,
        );
        expect(_signature(added), '1:1|8:8@1');
        expect(
          added.primarySelection.extentAffinity,
          EditorCaretAffinity.upstream,
        );

        final withThird = interaction.addOrToggleCursor(
          current: added,
          position: const EditorCaretPosition(offset: 4),
          documentLength: 12,
          makePrimary: false,
        );
        expect(_signature(withThird), '1:1|4:4|8:8@2');

        final toggledOff = interaction.addOrToggleCursor(
          current: withThird,
          position: const EditorCaretPosition(offset: 4),
          documentLength: 12,
          makePrimary: true,
        );
        expect(_signature(toggledOff), '1:1|8:8@1');

        final primaryNoOp = interaction.addOrToggleCursor(
          current: toggledOff,
          position: const EditorCaretPosition(
            offset: 8,
            affinity: EditorCaretAffinity.upstream,
          ),
          documentLength: 12,
          makePrimary: true,
        );
        expect(primaryNoOp, toggledOff);

        final primaryOnly = interaction.removeSecondaryCursors(
          current: primaryNoOp,
          documentLength: 12,
        );
        expect(_signature(primaryOnly), '8:8@0');
        expect(
          primaryOnly.primarySelection.extentAffinity,
          EditorCaretAffinity.upstream,
        );
      },
    );

    test(
      'projects tab, short, empty, and mixed-direction lines deterministically',
      () {
        const source = '\tab\nx\n\nאבג\n';
        const interaction = EditorSelectionInteraction();

        final rectangle = interaction.projectRectangle(
          lines: const <EditorRectangularLineProjection>[
            EditorRectangularLineProjection(
              lineIndex: 0,
              left: EditorCaretPosition(offset: 1),
              right: EditorCaretPosition(offset: 3),
            ),
            EditorRectangularLineProjection(
              lineIndex: 1,
              left: EditorCaretPosition(offset: 5),
              right: EditorCaretPosition(offset: 5),
            ),
            EditorRectangularLineProjection(
              lineIndex: 2,
              left: EditorCaretPosition(offset: 6),
              right: EditorCaretPosition(offset: 6),
            ),
            // The visually-left edge of this RTL run is logically after the
            // visually-right edge. Source direction must remain explicit.
            EditorRectangularLineProjection(
              lineIndex: 3,
              left: EditorCaretPosition(
                offset: 10,
                affinity: EditorCaretAffinity.upstream,
              ),
              right: EditorCaretPosition(offset: 7),
            ),
          ],
          primaryLineIndex: 3,
          horizontalDirection: EditorRectangleHorizontalDirection.leftToRight,
          documentLength: source.length,
        );

        expect(_signature(rectangle), '1:3|5:5|6:6|10:7@3');
        expect(rectangle.primarySelection.baseOffset, 10);
        expect(rectangle.primarySelection.extentOffset, 7);
        expect(
          rectangle.primarySelection.baseAffinity,
          EditorCaretAffinity.upstream,
        );

        final reverse = interaction.projectRectangle(
          lines: const <EditorRectangularLineProjection>[
            EditorRectangularLineProjection(
              lineIndex: 0,
              left: EditorCaretPosition(offset: 1),
              right: EditorCaretPosition(offset: 3),
            ),
          ],
          primaryLineIndex: 0,
          horizontalDirection: EditorRectangleHorizontalDirection.rightToLeft,
          documentLength: source.length,
        );
        expect(_signature(reverse), '3:1@0');
      },
    );

    test('a projected rectangle edits and undoes as one user intent', () {
      const source = '\tab\nx\n\nאבג\n';
      const interaction = EditorSelectionInteraction();
      final rectangle = interaction.projectRectangle(
        lines: const <EditorRectangularLineProjection>[
          EditorRectangularLineProjection(
            lineIndex: 0,
            left: EditorCaretPosition(offset: 1),
            right: EditorCaretPosition(offset: 3),
          ),
          EditorRectangularLineProjection(
            lineIndex: 1,
            left: EditorCaretPosition(offset: 5),
            right: EditorCaretPosition(offset: 5),
          ),
          EditorRectangularLineProjection(
            lineIndex: 2,
            left: EditorCaretPosition(offset: 6),
            right: EditorCaretPosition(offset: 6),
          ),
          EditorRectangularLineProjection(
            lineIndex: 3,
            left: EditorCaretPosition(offset: 10),
            right: EditorCaretPosition(offset: 7),
          ),
        ],
        primaryLineIndex: 3,
        horizontalDirection: EditorRectangleHorizontalDirection.leftToRight,
        documentLength: source.length,
      );
      final session = EditorSessionFacade(
        initialDocument: const DocumentState(
          documentId: 'rectangle.styio',
          text: source,
          revision: 0,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      addTearDown(session.dispose);
      session.selectionController.selectSelectionSet(rectangle);

      session.insertText('#');

      expect(session.document.text, '\t#\nx#\n#\n#\n');
      expect(session.document.revision, 1);
      expect(session.historyController.undoDepth, 1);
      expect(session.selectionSet.selections, hasLength(4));

      session.undo();
      expect(session.document.text, source);
      expect(session.document.revision, 0);
      expect(session.selectionSet, rectangle);
      expect(session.historyController.redoDepth, 1);
    });
  });
}

String _signature(EditorSelectionSet set) {
  final selections = set.selections
      .map((selection) => '${selection.baseOffset}:${selection.extentOffset}')
      .join('|');
  return '$selections@${set.primaryIndex}';
}
