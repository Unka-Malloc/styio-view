import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/search/search.dart';

void main() {
  testWidgets('workspace search surface submits query and opens matches', (
    tester,
  ) async {
    String? submittedQuery;
    AgentWorkspaceSearchMatchContext? openedMatch;
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
            onOpenMatch: (match) async {
              openedMatch = match;
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

    expect(openedMatch?.documentId, 'src/main.styio');
    expect(openedMatch?.lineNumber, 1);
    expect(openedMatch?.start, 0);
  });

  testWidgets('workspace search surface filters and opens quick-open files', (
    tester,
  ) async {
    String? openedDocumentId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSearchSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            workspaceFileCount: 3,
            workspaceFiles: const <String>[
              'src/main.styio',
              'src/lib/math.styio',
              'docs/readme.md',
            ],
            onOpenFile: (documentId) async {
              openedDocumentId = documentId;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('workspace-quick-open-list')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('workspace-quick-open-input')),
      'math',
    );
    await tester.pump();

    expect(find.text('math.styio'), findsOneWidget);
    expect(find.text('main.styio'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('workspace-quick-open-src/lib/math.styio')),
    );
    await tester.pump();

    expect(openedDocumentId, 'src/lib/math.styio');
  });

  testWidgets('workspace search surface triggers and renders replace preview', (
    tester,
  ) async {
    String? previewQuery;
    String? previewReplacement;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkspaceSearchSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            workspaceFileCount: 1,
            lastReplacePreview: const WorkspaceReplacePreview(
              documents: <WorkspaceReplacePreviewDocument>[
                WorkspaceReplacePreviewDocument(
                  documentId: 'src/main.styio',
                  beforeText: 'needle := 1\n',
                  afterText: 'value := 1\n',
                  replacementCount: 1,
                  revision: 1,
                ),
              ],
            ),
            onPreviewReplace: (query, replacement) async {
              previewQuery = query;
              previewReplacement = replacement;
            },
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-query-input')),
      'needle',
    );
    await tester.enterText(
      find.byKey(const ValueKey('workspace-replace-input')),
      'value',
    );
    await tester.tap(
      find.byKey(const ValueKey('workspace-replace-preview-submit')),
    );
    await tester.pump();

    expect(previewQuery, 'needle');
    expect(previewReplacement, 'value');
    expect(
      find.byKey(const ValueKey('workspace-replace-preview')),
      findsOneWidget,
    );
    expect(find.text('replacements 1'), findsOneWidget);
    expect(find.text('src/main.styio'), findsOneWidget);
  });
}
