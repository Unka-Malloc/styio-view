import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface renders external file conflict recovery', (
    tester,
  ) async {
    var acceptedExternalChange = false;
    const localDocument = DocumentState(
      documentId: 'fixture://file-conflict',
      text: 'value := 1\n',
      revision: 1,
    );
    const externalDocument = DocumentState(
      documentId: 'fixture://file-conflict',
      text: 'value := 2\n',
      revision: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: localDocument,
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              fileBindingSnapshot: const DocumentResourceBindingSnapshot(
                state: DocumentResourceBindingState.conflicted,
                resourceId: 'fixture://file-conflict',
                document: localDocument,
                externalDocument: externalDocument,
                failureKind: DocumentResourceBindingFailureKind.conflict,
                failureMessage: 'External changes conflict with local edits.',
              ),
              onAcceptExternalChange: () {
                acceptedExternalChange = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('editor-file-binding-status-banner')),
      findsOneWidget,
    );
    expect(find.text('External file conflict'), findsOneWidget);
    expect(find.text('Use external version'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('editor-file-binding-accept-external')),
    );

    expect(acceptedExternalChange, isTrue);
  });

  testWidgets('editor surface renders readonly and provider unavailable states', (
    tester,
  ) async {
    const document = DocumentState(
      documentId: 'fixture://readonly',
      text: 'value := 1\n',
      revision: 1,
    );

    Future<void> pumpStatus(DocumentResourceBindingSnapshot snapshot) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: EditorSurface(
                controller: EditorSessionController(
                  initialDocument: document,
                  languageService: const LocalStyioLanguageService(),
                ),
                viewportProfile: const ViewportProfile(
                  family: ViewportFamily.desktop,
                  width: 1200,
                  height: 800,
                ),
                fileBindingSnapshot: snapshot,
                onAcceptExternalChange: () {},
              ),
            ),
          ),
        ),
      );
    }

    await pumpStatus(
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.readonly,
        resourceId: 'fixture://readonly',
        document: document,
        failureKind: DocumentResourceBindingFailureKind.readonly,
        failureMessage: 'The backing resource is read-only.',
      ),
    );

    expect(find.text('Backing file is read-only'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('editor-file-binding-accept-external')),
          )
          .onPressed,
      isNull,
    );

    await pumpStatus(
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.providerUnavailable,
        resourceId: 'fixture://readonly',
        document: document,
        failureKind: DocumentResourceBindingFailureKind.providerUnavailable,
        failureMessage: 'The current file provider is unavailable.',
      ),
    );

    expect(find.text('File provider unavailable'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('editor-file-binding-accept-external')),
          )
          .onPressed,
      isNull,
    );
  });
}
