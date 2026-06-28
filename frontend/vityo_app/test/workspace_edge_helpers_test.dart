import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace quick open covers helper branches and empty projects', () {
    const service = WorkspaceQuickOpenService();

    final empty = service.searchFiles(
      documentIds: const <String>[],
      query: 'main',
    );
    expect(empty.matches, isEmpty);
    expect(empty.truncated, isFalse);

    final exact = service.searchFiles(
      documentIds: const <String>[
        r'lib\src\main.styio',
        'lib/src/main_extra.styio',
        'lib/src/domain.styio',
        'README.md',
      ],
      query: 'main.styio',
    );
    expect(exact.matches.first.label, 'main.styio');
    expect(exact.matches.first.documentId, r'lib\src\main.styio');

    final prefix = service.searchFiles(
      documentIds: const <String>[
        'lib/mainland.styio',
        'lib/main.styio',
        'lib/amain.styio',
      ],
      query: 'main',
    );
    expect(
      prefix.matches.map((item) => item.documentId),
      contains('lib/main.styio'),
    );

    final ordered = service.searchFiles(
      documentIds: const <String>[
        'src/workspace_quick_open.dart',
        'src/workspace_search.dart',
      ],
      query: 'wqo',
    );
    expect(ordered.matches.single.documentId, 'src/workspace_quick_open.dart');
  });

  test(
    'workspace document link helpers cover labels, filters, and globs',
    () async {
      final copied =
          const WorkspaceDocumentLinksQuery(
            targetFilePath: 'main.styio',
          ).copyWith(
            targetFilePath: 'src/main.styio',
            pattern: 'runtime',
            includeExternal: false,
            includeUnresolved: false,
            includeGlobs: const <String>['src/**'],
            excludeGlobs: const <String>['**/skip.styio'],
            maxResults: 2,
          );
      expect(copied.targetFilePath, 'src/main.styio');
      expect(copied.pattern, 'runtime');
      expect(copied.includeExternal, isFalse);
      expect(copied.includeUnresolved, isFalse);
      expect(copied.includeGlobs, const <String>['src/**']);
      expect(copied.excludeGlobs, const <String>['**/skip.styio']);
      expect(copied.maxResults, 2);

      const external = WorkspaceDocumentLinkItem(
        sourceFilePath: 'src/main.styio',
        target: 'styio/core',
        kind: WorkspaceDocumentLinkKind.externalImport,
        range: SourceRange(start: 0, end: 10),
        line: 0,
        column: 0,
        previewText: '@import styio/core',
      );
      const workspace = WorkspaceDocumentLinkItem(
        sourceFilePath: 'src/main.styio',
        target: 'lib/runtime',
        kind: WorkspaceDocumentLinkKind.workspaceImport,
        range: SourceRange(start: 0, end: 11),
        line: 0,
        column: 0,
        previewText: '@import { lib/runtime }',
        resolvedFilePath: 'src/lib/runtime.styio',
      );
      const unresolved = WorkspaceDocumentLinkItem(
        sourceFilePath: 'src/main.styio',
        target: 'lib/missing',
        kind: WorkspaceDocumentLinkKind.unresolvedImport,
        range: SourceRange(start: 0, end: 11),
        line: 0,
        column: 0,
        previewText: '@import { lib/missing }',
      );
      expect(external.kindLabel, 'external import');
      expect(workspace.kindLabel, 'workspace import');
      expect(unresolved.kindLabel, 'unresolved import');
      expect(workspace.targetLabel, 'src/lib/runtime.styio');
      expect(external.targetLabel, 'styio/core');
      expect(workspace.canOpen, isTrue);
      expect(external.canOpen, isFalse);

      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': DocumentState(
            documentId: 'src/main.styio',
            text: '''
@import src/lib/runtime
@import { styio/core }
@import { generated/skip }
''',
            revision: 0,
          ),
          'src/lib/runtime.styio': DocumentState(
            documentId: 'src/lib/runtime.styio',
            text: '#runtime := () => {}\n',
            revision: 0,
          ),
          'generated/skip.styio': DocumentState(
            documentId: 'generated/skip.styio',
            text: '#skip := () => {}\n',
            revision: 0,
          ),
        },
      );
      final service = WorkspaceDocumentLinksService(documentStore: store);

      final result = await service.collectLinks(
        filePaths: const <String>[
          'src/main.styio',
          'src/lib/runtime.styio',
          'generated/skip.styio',
        ],
        query: const WorkspaceDocumentLinksQuery(
          targetFilePath: 'src/main.styio',
          pattern: 'workspaceImport',
          includeGlobs: <String>['**/*.styio'],
          excludeGlobs: <String>['generated/**'],
        ),
      );

      expect(result.status, WorkspaceDocumentLinksStatus.completed);
      expect(
        result.links.single.kind,
        WorkspaceDocumentLinkKind.workspaceImport,
      );
      expect(result.links.single.resolvedFilePath, 'src/lib/runtime.styio');
    },
  );

  test(
    'workspace code actions expose helper getters and empty states',
    () async {
      final query = const WorkspaceCodeActionsQuery().copyWith(
        pattern: 'unused',
        includeGlobs: const <String>['src/**'],
        excludeGlobs: const <String>['**/skip.styio'],
        maxResults: 4,
      );
      expect(query.pattern, 'unused');
      expect(query.includeGlobs, const <String>['src/**']);
      expect(query.excludeGlobs, const <String>['**/skip.styio']);
      expect(query.maxResults, 4);

      const item = WorkspaceCodeActionItem(
        id: 'fix',
        label: 'Fix',
        detail: 'Fix detail',
        documents: <WorkspaceCodeActionDocumentPreview>[
          WorkspaceCodeActionDocumentPreview(
            filePath: 'src/a.styio',
            editCount: 2,
            firstEditRange: SourceRange(start: 3, end: 5),
            line: 0,
            column: 3,
            previewText: 'alpha',
          ),
          WorkspaceCodeActionDocumentPreview(
            filePath: 'src/b.styio',
            editCount: 1,
            firstEditRange: SourceRange(start: 0, end: 1),
            line: 0,
            column: 0,
            previewText: 'beta',
          ),
        ],
      );
      expect(item.editCount, 3);
      expect(item.changedFileCount, 2);
      expect(item.filePaths, const <String>['src/a.styio', 'src/b.styio']);

      final service = WorkspaceCodeActionsService(
        documentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'README.md': DocumentState(
              documentId: 'README.md',
              text: '@import { lib/missing }\n',
              revision: 0,
            ),
          },
        ),
      );
      final empty = await service.collectCodeActions(
        filePaths: const <String>['README.md'],
        query: const WorkspaceCodeActionsQuery(),
      );
      expect(empty.status, WorkspaceCodeActionsStatus.emptyWorkspace);
      expect(empty.message, contains('Styio workspace file'));
    },
  );

  test(
    'workspace search helpers cover empty replace and replacement escapes',
    () async {
      final searchQuery = const WorkspaceTextSearchQuery(pattern: 'ready')
          .copyWith(
            pattern: 'emit',
            literal: false,
            caseSensitive: true,
            includeGlobs: const <String>['src/**'],
            excludeGlobs: const <String>['**/*_test.styio'],
            maxResults: 5,
          );
      expect(searchQuery.pattern, 'emit');
      expect(searchQuery.literal, isFalse);
      expect(searchQuery.caseSensitive, isTrue);
      expect(searchQuery.includeGlobs, const <String>['src/**']);
      expect(searchQuery.excludeGlobs, const <String>['**/*_test.styio']);
      expect(searchQuery.maxResults, 5);

      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': DocumentState(
            documentId: 'src/main.styio',
            text: 'emit("alpha")\nemit("beta")\n',
            revision: 0,
          ),
        },
      );
      final service = WorkspaceTextSearchService(documentStore: store);

      final emptySearch = await service.searchFiles(
        filePaths: const <String>['src/main.styio'],
        query: const WorkspaceTextSearchQuery(pattern: ''),
      );
      expect(emptySearch.status, WorkspaceTextSearchStatus.emptyPattern);
      expect(emptySearch.message, contains('non-empty pattern'));

      final emptyReplace = await service.previewReplaceFiles(
        filePaths: const <String>['src/main.styio'],
        query: const WorkspaceTextReplaceQuery(pattern: '', replacement: 'x'),
      );
      expect(emptyReplace.status, WorkspaceTextSearchStatus.emptyPattern);
      expect(emptyReplace.canApply, isFalse);

      final preview = await service.previewReplaceFiles(
        filePaths: const <String>['src/main.styio'],
        query: const WorkspaceTextReplaceQuery(
          pattern: r'emit\("(\w+)"\)',
          replacement: r'log("\$ $0 $1 $99")',
          literal: false,
        ),
      );
      expect(preview.status, WorkspaceTextSearchStatus.completed);
      expect(preview.hitLimit, isFalse);
      expect(preview.replacementCount, 2);
      expect(preview.matchedFileCount, 1);
      expect(preview.searchResult.matchCount, 2);
      expect(preview.matches.first.replacementText, contains(r'$'));
      expect(preview.matches.first.replacementText, contains('emit("alpha")'));
      expect(preview.matches.first.replacementText, contains('alpha'));

      final apply = WorkspaceTextReplaceApplyResult(
        preview: preview,
        applied: false,
        changedDocuments: const <String, DocumentState>{},
        message: 'not applied',
      );
      expect(apply.documentsChanged, 0);
      expect(apply.replacementsApplied, 0);
    },
  );
}
