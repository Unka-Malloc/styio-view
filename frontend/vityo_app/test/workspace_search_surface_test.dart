import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_provider.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/search/search.dart';

void main() {
  testWidgets('workspace search surface submits query and opens matches', (
    tester,
  ) async {
    String? submittedQuery;
    AgentWorkspaceSearchMatchContext? openedMatch;
    AgentWorkspaceSymbolMatchContext? openedSymbolMatch;
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
    const symbolResult = WorkspaceSymbolSearchResult(
      matches: <WorkspaceSymbolMatch>[
        WorkspaceSymbolMatch(
          documentId: 'src/main.styio',
          name: 'needle',
          kind: ResolvedElementKind.variable,
          nameRange: SourceRange(start: 0, end: 6),
          declarationRange: SourceRange(start: 0, end: 11),
          lineNumber: 1,
          lineText: 'needle := 1',
          score: 1000,
          snapshotSource: SemanticSnapshotProviderSource.localBuilderFallback,
          snapshotConfidence: SemanticSnapshotFeatureConfidence.localFallback,
          detail: 'Styio binding',
        ),
      ],
    );
    final lastSymbolSearch =
        AgentWorkspaceSymbolSearchResultContext.fromWorkspaceResult(
          query: 'needle',
          scannedDocumentCount: 2,
          result: symbolResult,
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
            searchIndex: WorkspaceSearchIndex(
              documents: <WorkspaceSearchIndexDocument>[
                WorkspaceSearchIndexDocument.fromDocument(
                  const DocumentState(
                    documentId: 'src/main.styio',
                    text: 'needle := 1\n',
                    revision: 1,
                  ),
                ),
                WorkspaceSearchIndexDocument.fromDocument(
                  const DocumentState(
                    documentId: 'src/lib.styio',
                    text: 'lib := needle\n',
                    revision: 2,
                  ),
                ),
              ],
              createdAt: DateTime.utc(2026, 5, 20),
            ),
            searchHistory: WorkspaceSearchHistory(
              workspaceId: 'demo',
              records: <WorkspaceSearchHistoryRecord>[
                WorkspaceSearchHistoryRecord(
                  query: 'needle',
                  mode: WorkspaceSearchHistoryMode.text,
                  createdAt: DateTime.utc(2026, 5, 20),
                ),
              ],
            ),
            searchFilters: const WorkspaceSearchFilterState(
              workspaceId: 'demo',
              caseSensitive: true,
              wholeWord: true,
              includeGlob: 'src/**',
            ),
            lastSearch: lastSearch,
            lastSymbolSearch: lastSymbolSearch,
            onSearch: (query) async {
              submittedQuery = query;
            },
            onOpenMatch: (match) async {
              openedMatch = match;
            },
            onOpenSymbolMatch: (match) async {
              openedSymbolMatch = match;
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
    expect(find.text('files 2'), findsOneWidget);
    expect(find.text('index-docs 2'), findsOneWidget);
    expect(find.text('index-key 2'), findsOneWidget);
    expect(find.text('history 1'), findsOneWidget);
    expect(find.text('filters active'), findsOneWidget);
    expect(find.text('case-sensitive'), findsOneWidget);
    expect(find.text('whole-word'), findsOneWidget);
    expect(find.text('include src/**'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workspace-search-history')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('workspace-search-query-input')),
      'lib',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-search-submit')));
    await tester.pump();

    expect(submittedQuery, 'lib');

    await tester.drag(
      find.byKey(const ValueKey('workspace-search-surface')),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();

    expect(find.text('matches 2'), findsOneWidget);
    expect(find.text('src/main.styio'), findsOneWidget);
    expect(find.text('src/lib.styio'), findsOneWidget);

    await tester.tap(find.text('src/main.styio'));
    await tester.pump();

    expect(openedMatch?.documentId, 'src/main.styio');
    expect(openedMatch?.lineNumber, 1);
    expect(openedMatch?.start, 0);

    const symbolKey = ValueKey(
      'workspace-symbol-search-match-src/main.styio-needle-0',
    );
    await tester.drag(
      find.byKey(const ValueKey('workspace-search-surface')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    expect(find.text('symbols 1'), findsOneWidget);
    expect(find.text('needle · variable'), findsOneWidget);
    expect(find.textContaining('semantic local-fallback'), findsOneWidget);
    await tester.tap(find.byKey(symbolKey));
    await tester.pump();

    expect(openedSymbolMatch?.documentId, 'src/main.styio');
    expect(openedSymbolMatch?.name, 'needle');
    expect(openedSymbolMatch?.snapshotConfidence, 'local-fallback');
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
    String? toggledDocumentId;
    WorkspaceReplacePreview? appliedPreview;
    const replacePreview = WorkspaceReplacePreview(
      documents: <WorkspaceReplacePreviewDocument>[
        WorkspaceReplacePreviewDocument(
          documentId: 'src/main.styio',
          beforeText: 'needle := 1\n',
          afterText: 'value := 1\n',
          replacementCount: 1,
          revision: 1,
        ),
        WorkspaceReplacePreviewDocument(
          documentId: 'src/lib.styio',
          beforeText: 'needle := 2\n',
          afterText: 'value := 2\n',
          replacementCount: 1,
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
            workspaceFileCount: 1,
            lastReplacePreview: replacePreview,
            lastReplacePreviewWindow: replacePreview.window(documentLimit: 1),
            replaceExpansionState: const WorkspaceReplacePreviewExpansionState(
              workspaceId: 'demo',
              expandedDocumentIds: <String>['src/main.styio'],
            ),
            onPreviewReplace: (query, replacement) async {
              previewQuery = query;
              previewReplacement = replacement;
            },
            onApplyReplacePreview: (preview) async {
              appliedPreview = preview;
            },
            onToggleReplaceDocumentExpansion: (documentId) async {
              toggledDocumentId = documentId;
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
    expect(find.text('replacements 2'), findsOneWidget);
    expect(find.text('documents 2'), findsOneWidget);
    expect(find.text('replace-window 0-1/2'), findsOneWidget);
    expect(find.text('has more documents'), findsOneWidget);
    expect(find.text('expanded 1'), findsWidgets);
    expect(find.text('src/main.styio'), findsOneWidget);
    expect(find.text('src/lib.styio'), findsNothing);
    expect(find.text('Before full: needle := 1'), findsOneWidget);
    expect(find.text('After full: value := 1'), findsOneWidget);

    final toggleButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('workspace-replace-toggle-src/main.styio')),
    );
    toggleButton.onPressed!();
    await tester.pump();

    expect(toggledDocumentId, 'src/main.styio');

    await tester.tap(
      find.byKey(const ValueKey('workspace-replace-apply-submit')),
    );
    await tester.pump();

    expect(appliedPreview?.replacementCount, 2);
    expect(appliedPreview?.documents.first.documentId, 'src/main.styio');
  });
}
