import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface renders open file tabs and selects inactive tab', (
    tester,
  ) async {
    String? selectedDocumentId;
    String? closedDocumentId;

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
              openDocumentIds: const <String>[
                'src/main.styio',
                'src/lib.styio',
              ],
              dirtyDocumentIds: const <String>['src/lib.styio'],
              activeDocumentId: 'src/main.styio',
              onSelectDocument: (documentId) {
                selectedDocumentId = documentId;
              },
              onCloseDocument: (documentId) {
                closedDocumentId = documentId;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('editor-open-file-tab-strip')),
      findsOneWidget,
    );
    expect(find.text('main.styio'), findsOneWidget);
    expect(find.text('lib.styio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-open-file-tab-dirty-src/lib.styio')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('editor-open-file-tab-src/lib.styio')),
    );
    expect(selectedDocumentId, 'src/lib.styio');

    await tester.tap(
      find.byKey(const ValueKey('editor-open-file-tab-close-src/main.styio')),
    );
    expect(closedDocumentId, 'src/main.styio');
  });

  testWidgets('editor surface falls back to current document tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: const DocumentState(
                  documentId: 'scratch.styio',
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
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('editor-open-file-tab-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-open-file-tab-scratch.styio')),
      findsOneWidget,
    );
  });
}
