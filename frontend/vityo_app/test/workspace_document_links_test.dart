import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace document links resolve import targets', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
@import { styio/core }
@import { lib/missing }
''',
          revision: 0,
        ),
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '#blend := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentLinksService(documentStore: store);

    final result = await service.collectLinks(
      filePaths: const <String>['main.styio', 'lib/runtime.styio'],
      query: const WorkspaceDocumentLinksQuery(targetFilePath: 'main.styio'),
    );

    expect(result.status, WorkspaceDocumentLinksStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.linksIndexed, 3);
    expect(result.linkCount, 3);
    expect(result.workspaceLinkCount, 1);
    expect(result.externalLinkCount, 1);
    expect(result.unresolvedLinkCount, 1);

    final workspaceLink = result.links.firstWhere(
      (link) => link.kind == WorkspaceDocumentLinkKind.workspaceImport,
    );
    expect(workspaceLink.target, 'lib/runtime');
    expect(workspaceLink.resolvedFilePath, 'lib/runtime.styio');
    expect(workspaceLink.line, 0);
    expect(workspaceLink.previewText, '@import { lib/runtime }');

    final externalLink = result.links.firstWhere(
      (link) => link.kind == WorkspaceDocumentLinkKind.externalImport,
    );
    expect(externalLink.target, 'styio/core');
    expect(externalLink.canOpen, isFalse);
  });

  test('workspace document links use overlays, filters, and limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '@import { lib/saved }\n',
          revision: 0,
        ),
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '#blend := () => {}\n',
          revision: 0,
        ),
        'lib/extra.styio': DocumentState(
          documentId: 'lib/extra.styio',
          text: '#extra := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentLinksService(documentStore: store);

    final result = await service.collectLinks(
      filePaths: const <String>[
        'main.styio',
        'lib/runtime.styio',
        'lib/extra.styio',
      ],
      overlayDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { ./lib/runtime }
@import { lib/extra }
@import { lib/missing }
''',
          revision: 1,
        ),
      },
      query: const WorkspaceDocumentLinksQuery(
        targetFilePath: 'main.styio',
        includeUnresolved: false,
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceDocumentLinksStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.linksIndexed, 3);
    expect(result.linkCount, 1);
    expect(result.unresolvedLinkCount, 0);
    expect(result.links.single.target, './lib/runtime');
    expect(result.links.single.resolvedFilePath, 'lib/runtime.styio');

    final filtered = await service.collectLinks(
      filePaths: const <String>[
        'main.styio',
        'lib/runtime.styio',
        'lib/extra.styio',
      ],
      overlayDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '@import { lib/extra }\n',
          revision: 1,
        ),
      },
      query: const WorkspaceDocumentLinksQuery(
        targetFilePath: 'main.styio',
        pattern: 'extra',
      ),
    );

    expect(filtered.status, WorkspaceDocumentLinksStatus.completed);
    expect(filtered.links.single.target, 'lib/extra');
  });

  test('workspace document links reports empty workspace and no links', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: '@import { lib/runtime }\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentLinksService(documentStore: store);

    final emptyWorkspaceResult = await service.collectLinks(
      filePaths: const <String>['README.md'],
      query: const WorkspaceDocumentLinksQuery(targetFilePath: 'README.md'),
    );
    final noLinksResult = await service.collectLinks(
      filePaths: const <String>['main.styio'],
      query: const WorkspaceDocumentLinksQuery(targetFilePath: 'main.styio'),
    );

    expect(
      emptyWorkspaceResult.status,
      WorkspaceDocumentLinksStatus.emptyWorkspace,
    );
    expect(noLinksResult.status, WorkspaceDocumentLinksStatus.noLinks);
    expect(noLinksResult.message, 'No document links found in main.styio.');
  });

  test('workspace document links covers query helpers and glob edges', () async {
    const query = WorkspaceDocumentLinksQuery(targetFilePath: 'main.styio');
    final copied = query.copyWith(
      targetFilePath: 'src/main.styio',
      pattern: 'workspaceImport',
      includeExternal: false,
      includeUnresolved: false,
      includeGlobs: const <String>['src/**'],
      excludeGlobs: const <String>['src/generated/**'],
      maxResults: 0,
    );

    expect(copied.targetFilePath, 'src/main.styio');
    expect(copied.pattern, 'workspaceImport');
    expect(copied.includeExternal, isFalse);
    expect(copied.includeUnresolved, isFalse);
    expect(copied.maxResults, 0);
    expect(copied.copyWith().excludeGlobs, <String>['src/generated/**']);

    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
  @import src/lib/runtime
  @import { styio/core }
  @import { src/missing }
''',
          revision: 0,
        ),
        'src/lib/runtime.styio': DocumentState(
          documentId: 'src/lib/runtime.styio',
          text: '#runtime := () => {}\n',
          revision: 0,
        ),
        'src/generated/skip.styio': DocumentState(
          documentId: 'src/generated/skip.styio',
          text: '#skip := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentLinksService(documentStore: store);

    final result = await service.collectLinks(
      filePaths: const <String>[
        'src/main.styio',
        'src/main.styio',
        'src/lib/runtime.styio',
        'src/generated/skip.styio',
      ],
      query: copied,
    );

    expect(result.status, WorkspaceDocumentLinksStatus.completed);
    expect(result.linksIndexed, 3);
    expect(result.linkCount, 1);
    expect(result.links.single.kindLabel, 'workspace import');
    expect(result.links.single.targetLabel, 'src/lib/runtime.styio');
    expect(result.links.single.canOpen, isTrue);
    expect(result.links.single.column, 10);
    expect(result.message, isNull);

    final suffixGlobResult = await service.collectLinks(
      filePaths: const <String>['src/main.styio', 'src/lib/runtime.styio'],
      query: const WorkspaceDocumentLinksQuery(
        targetFilePath: 'src/main.styio',
        includeGlobs: <String>['**/main.styio'],
      ),
    );
    final wildcardGlobResult = await service.collectLinks(
      filePaths: const <String>['src/main.styio', 'src/lib/runtime.styio'],
      query: const WorkspaceDocumentLinksQuery(
        targetFilePath: 'src/main.styio',
        includeGlobs: <String>['src/*.styio'],
        excludeGlobs: <String>['**/generated/*.styio'],
      ),
    );
    final exactGlobResult = await service.collectLinks(
      filePaths: const <String>['src/main.styio', 'src/lib/runtime.styio'],
      query: const WorkspaceDocumentLinksQuery(
        targetFilePath: 'src/main.styio',
        includeGlobs: <String>['src/main.styio'],
      ),
    );

    expect(suffixGlobResult.status, WorkspaceDocumentLinksStatus.completed);
    expect(wildcardGlobResult.status, WorkspaceDocumentLinksStatus.completed);
    expect(exactGlobResult.status, WorkspaceDocumentLinksStatus.completed);
  });
}
