import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface clears provider banner after reconnect', (
    tester,
  ) async {
    const document = DocumentState(
      documentId: 'fixture://reconnect',
      text: 'value := 1\n',
      revision: 1,
    );
    final controller = EditorSessionController(
      initialDocument: document,
      languageService: const LocalStyioLanguageService(),
    );

    Future<void> pumpStatus(DocumentResourceBindingSnapshot snapshot) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: EditorSurface(
                controller: controller,
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
        state: DocumentResourceBindingState.providerUnavailable,
        resourceId: 'fixture://reconnect',
        document: document,
        failureKind: DocumentResourceBindingFailureKind.providerUnavailable,
        failureMessage: 'The current file provider is unavailable.',
      ),
    );

    expect(find.text('File provider unavailable'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-file-binding-status-banner')),
      findsOneWidget,
    );

    await pumpStatus(
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.boundClean,
        resourceId: 'fixture://reconnect',
        document: document,
      ),
    );

    expect(find.text('File provider unavailable'), findsNothing);
    expect(
      find.byKey(const ValueKey('editor-file-binding-status-banner')),
      findsNothing,
    );
    expect(controller.document.documentId, 'fixture://reconnect');
  });
}
