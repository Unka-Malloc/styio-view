import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/search/search.dart';

void main() {
  testWidgets('workspace search surface submits query and opens matches', (
    tester,
  ) async {
    String? submittedQuery;
    String? openedDocumentId;
    final lastSearch = AgentWorkspaceSearchResultContext.fromDocuments(
      query: 'needle',
      documents: const <DocumentState>[
        DocumentState(
          documentId: 'src/main.styio',
          text: 'needle := 1\n',
          revision: 1,
        ),
        DocumentState(
          documentId: 'src/lib.styio',
          text: 'lib := needle\n',
          revision: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSearchSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            workspaceFileCount: 2,
            lastSearch: lastSearch,
            onSearch: (query) async {
              submittedQuery = query;
            },
            onOpenMatch: (documentId) async {
              openedDocumentId = documentId;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('workspace-search-surface')),
      findsOneWidget,
    );
    expect(find.text('Workspace Search'), findsOneWidget);
    expect(find.text('matches 2'), findsOneWidget);
    expect(find.text('src/main.styio'), findsOneWidget);
    expect(find.text('src/lib.styio'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-query-input')),
      'lib',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-search-submit')));
    await tester.pump();

    expect(submittedQuery, 'lib');

    await tester.tap(find.text('src/main.styio'));
    await tester.pump();

    expect(openedDocumentId, 'src/main.styio');
  });
}
