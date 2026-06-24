import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface renders close confirmation actions', (
    tester,
  ) async {
    var saved = false;
    var discarded = false;
    var savedAndClosed = false;
    var discardedAndClosed = false;
    var canceled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: const DocumentState(
                  documentId: 'src/main.styio',
                  text: 'value := 1\n',
                  revision: 1,
                ),
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              closeRequestSurface: const EditorCloseRequestSurface(
                status: EditorCloseRequestSurfaceStatus.blockedUnsavedChanges,
                filePath: 'src/main.styio',
                message: 'Close blocked for src/main.styio.',
                canSave: true,
                canDiscard: true,
              ),
              onSaveLocalChanges: () {
                saved = true;
              },
              onDiscardLocalChanges: () {
                discarded = true;
              },
              onSaveAndCloseRequest: () {
                savedAndClosed = true;
              },
              onDiscardAndCloseRequest: () {
                discardedAndClosed = true;
              },
              onCancelCloseRequest: () {
                canceled = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('editor-close-request-banner')),
      findsOneWidget,
    );
    expect(find.text('Close blocked'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-close-request-save')));
    expect(saved, isFalse);
    expect(savedAndClosed, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('editor-close-request-discard')),
    );
    expect(discarded, isFalse);
    expect(discardedAndClosed, isTrue);

    await tester.tap(find.byKey(const ValueKey('editor-close-request-cancel')));
    expect(canceled, isTrue);
  });

  testWidgets('editor surface renders switch action for inactive dirty close', (
    tester,
  ) async {
    var switched = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: const DocumentState(
                  documentId: 'src/lib.styio',
                  text: 'lib := 1\n',
                  revision: 1,
                ),
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              closeRequestSurface: const EditorCloseRequestSurface(
                status: EditorCloseRequestSurfaceStatus.blockedUnsavedChanges,
                filePath: 'src/main.styio',
                message: 'Close blocked for src/main.styio.',
                canSwitchToFile: true,
              ),
              onSwitchToCloseRequestFile: () {
                switched = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Switch to file'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('editor-close-request-switch')));

    expect(switched, isTrue);
  });
}
