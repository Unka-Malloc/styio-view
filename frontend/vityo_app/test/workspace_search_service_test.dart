import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_provider.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test(
    'workspace quick open ranks exact prefix contains and fuzzy matches',
    () {
      final result = const WorkspaceQuickOpenService().searchFiles(
        documentIds: const <String>[
          'docs/readme.md',
          'src/main.styio',
          'test/main_test.dart',
          'src/lib/math.styio',
        ],
        query: 'main',
      );
      final fuzzy = const WorkspaceQuickOpenService().searchFiles(
        documentIds: const <String>[
          'src/workspace_search_service.dart',
          'src/source_control_status.dart',
        ],
        query: 'wss',
      );

      expect(result.matches.map((match) => match.documentId), <String>[
        'src/main.styio',
        'test/main_test.dart',
      ]);
      expect(result.matches.first.label, 'main.styio');
      expect(result.truncated, isFalse);
      expect(
        fuzzy.matches.single.documentId,
        'src/workspace_search_service.dart',
      );
    },
  );

  test('workspace quick open preserves empty query order and truncates', () {
    final result = const WorkspaceQuickOpenService().searchFiles(
      documentIds: const <String>[
        'src/main.styio',
        'src/main.styio',
        'src/lib.styio',
        'test/main_test.dart',
      ],
      query: '',
      maxResults: 2,
    );

    expect(result.matches.map((match) => match.documentId), <String>[
      'src/main.styio',
      'src/lib.styio',
    ]);
    expect(result.truncated, isTrue);
  });

  test(
    'workspace symbol search scans semantic snapshots across documents',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': DocumentState(
            documentId: 'src/main.styio',
            text: '#main := (): string => {\n  value := 1\n  value\n}\n',
            revision: 1,
          ),
          'src/worker.styio': DocumentState(
            documentId: 'src/worker.styio',
            text: '#worker := (): string => {\n  workerValue := 1\n}\n',
            revision: 1,
          ),
        },
      );
      final service = WorkspaceSymbolSearchService(
        documentStore: store,
        semanticSnapshotProvider: const SemanticSnapshotProvider(
          languageService: LocalStyioLanguageService(),
        ),
      );

      final result = await service.searchSymbols(
        documentIds: const <String>['src/main.styio', 'src/worker.styio'],
        query: 'value',
      );

      expect(result.failures, isEmpty);
      expect(result.truncated, isFalse);
      expect(result.matches.first.documentId, 'src/main.styio');
      expect(result.matches.first.name, 'value');
      expect(result.matches.first.kind, ResolvedElementKind.variable);
      expect(result.matches.first.lineNumber, 2);
      expect(result.matches.first.lineText, '  value := 1');
    },
  );

  test(
    'workspace symbol search filters kinds and reports load failures',
    () async {
      final service = WorkspaceSymbolSearchService(
        documentStore: _FailingWorkspaceSearchStore(),
        semanticSnapshotProvider: const SemanticSnapshotProvider(
          languageService: LocalStyioLanguageService(),
        ),
      );

      final result = await service.searchSymbols(
        documentIds: const <String>['main.styio', 'missing.styio'],
        query: '',
        kinds: const <ResolvedElementKind>{ResolvedElementKind.variable},
        maxResults: 1,
      );
      final failure = await service.searchSymbols(
        documentIds: const <String>['missing.styio'],
        query: 'value',
      );

      expect(result.matches, hasLength(1));
      expect(result.matches.single.kind, ResolvedElementKind.variable);
      expect(result.truncated, isTrue);
      expect(result.failures, isEmpty);
      expect(failure.matches, isEmpty);
      expect(failure.failures.single.documentId, 'missing.styio');
    },
  );

  test(
    'workspace search scans supplied documents through document store',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value = 1\nemit value\n',
            revision: 1,
          ),
          'helper.styio': DocumentState(
            documentId: 'helper.styio',
            text: 'helperValue\nvalue\n',
            revision: 2,
          ),
        },
      );
      final service = WorkspaceSearchService(documentStore: store);

      final result = await service.search(
        documentIds: const <String>['main.styio', 'helper.styio'],
        query: 'value',
        wholeWord: true,
      );

      expect(result.failures, isEmpty);
      expect(result.truncated, isFalse);
      expect(
        result.matches.map(
          (match) => '${match.documentId}:${match.lineNumber}:${match.text}',
        ),
        <String>[
          'main.styio:1:value',
          'main.styio:2:value',
          'helper.styio:2:value',
        ],
      );
      expect(result.matches.first.lineText, 'value = 1');
    },
  );

  test(
    'workspace search records load failures and truncates matches',
    () async {
      final service = WorkspaceSearchService(
        documentStore: _FailingWorkspaceSearchStore(),
      );

      final result = await service.search(
        documentIds: const <String>['main.styio', 'missing.styio'],
        query: 'value',
        maxMatches: 1,
      );

      expect(result.matches, hasLength(1));
      expect(result.truncated, isTrue);
      expect(result.failures, isEmpty);

      final failureResult = await service.search(
        documentIds: const <String>['missing.styio'],
        query: 'value',
      );

      expect(failureResult.matches, isEmpty);
      expect(failureResult.failures.single.documentId, 'missing.styio');
      expect(failureResult.failures.single.message, contains('missing.styio'));
    },
  );

  test(
    'workspace search only marks truncated when results are omitted',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value\nvalue\n',
            revision: 1,
          ),
        },
      );
      final service = WorkspaceSearchService(documentStore: store);

      final exact = await service.search(
        documentIds: const <String>['main.styio'],
        query: 'value',
        maxMatches: 2,
      );
      final omitted = await service.search(
        documentIds: const <String>['main.styio'],
        query: 'value',
        maxMatches: 1,
      );

      expect(exact.matches, hasLength(2));
      expect(exact.truncated, isFalse);
      expect(omitted.matches, hasLength(1));
      expect(omitted.truncated, isTrue);
    },
  );

  test('workspace search supports regex queries safely', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value1\nvalue22\nvalue_count\n',
          revision: 1,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);

    final result = await service.search(
      documentIds: const <String>['main.styio'],
      query: r'value\d+',
      useRegex: true,
    );
    final invalid = await service.search(
      documentIds: const <String>['main.styio'],
      query: r'value[',
      useRegex: true,
    );

    expect(result.matches.map((match) => match.text), <String>[
      'value1',
      'value22',
    ]);
    expect(result.failures, isEmpty);
    expect(invalid.matches, isEmpty);
    expect(invalid.failures, isEmpty);
  });

  test('workspace search scans duplicate document ids once', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value\n',
          revision: 1,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);

    final result = await service.search(
      documentIds: const <String>['main.styio', 'main.styio'],
      query: 'value',
    );

    expect(result.matches, hasLength(1));
    expect(result.matches.single.documentId, 'main.styio');
  });

  test('workspace replace all updates matched documents through store', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\nemit value\n',
          revision: 1,
        ),
        'helper.styio': DocumentState(
          documentId: 'helper.styio',
          text: 'helperValue\nvalue\n',
          revision: 2,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);

    final result = await service.replaceAll(
      documentIds: const <String>['main.styio', 'helper.styio'],
      query: 'value',
      replacement: 'next',
      wholeWord: true,
    );
    final main = await store.loadDocument('main.styio');
    final helper = await store.loadDocument('helper.styio');

    expect(result.replacementCount, 3);
    expect(result.failures, isEmpty);
    expect(result.truncated, isFalse);
    expect(
      result.documents.map(
        (document) =>
            '${document.documentId}:${document.replacementCount}:${document.revision}',
      ),
      <String>['main.styio:2:2', 'helper.styio:1:3'],
    );
    expect(main.text, 'next = 1\nemit next\n');
    expect(helper.text, 'helperValue\nnext\n');
  });

  test('workspace replace preview does not save documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\nemit value\n',
          revision: 1,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);

    final preview = await service.previewReplaceAll(
      documentIds: const <String>['main.styio'],
      query: 'value',
      replacement: 'next',
    );
    final stored = await store.loadDocument('main.styio');

    expect(preview.replacementCount, 2);
    expect(preview.documents.single.documentId, 'main.styio');
    expect(preview.documents.single.revision, 1);
    expect(preview.documents.single.beforeText, 'value = 1\nemit value\n');
    expect(preview.documents.single.afterText, 'next = 1\nemit next\n');
    expect(preview.documents.single.changed, isTrue);
    expect(stored.text, 'value = 1\nemit value\n');
    expect(stored.revision, 1);
  });

  test('workspace replace preview applies after revision check', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);
    final preview = await service.previewReplaceAll(
      documentIds: const <String>['main.styio'],
      query: 'value',
      replacement: 'next',
    );

    final result = await service.applyReplacePreview(preview);
    final stored = await store.loadDocument('main.styio');

    expect(result.failures, isEmpty);
    expect(result.documents.single.revision, 2);
    expect(stored.text, 'next = 1\n');
    expect(stored.revision, 2);
  });

  test('workspace replace preview rejects stale documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);
    final preview = await service.previewReplaceAll(
      documentIds: const <String>['main.styio'],
      query: 'value',
      replacement: 'next',
    );
    await store.saveDocument(
      const DocumentState(
        documentId: 'main.styio',
        text: 'value = 2\n',
        revision: 2,
      ),
    );

    final result = await service.applyReplacePreview(preview);
    final stored = await store.loadDocument('main.styio');

    expect(result.documents, isEmpty);
    expect(result.failures.single.message, contains('document changed'));
    expect(stored.text, 'value = 2\n');
    expect(stored.revision, 2);
  });

  test('workspace replace all reports save failures and truncation', () async {
    final service = WorkspaceSearchService(
      documentStore: _FailingSaveWorkspaceSearchStore(),
    );

    final failure = await service.replaceAll(
      documentIds: const <String>['fail-save.styio'],
      query: 'value',
      replacement: 'next',
    );
    final truncated = await service.replaceAll(
      documentIds: const <String>['main.styio'],
      query: 'value',
      replacement: 'next',
      maxReplacements: 1,
    );

    expect(failure.documents, isEmpty);
    expect(failure.failures.single.documentId, 'fail-save.styio');
    expect(truncated.replacementCount, 1);
    expect(truncated.truncated, isTrue);
  });

  test('workspace replace all applies duplicate document ids once', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value value\n',
          revision: 1,
        ),
      },
    );
    final service = WorkspaceSearchService(documentStore: store);

    final result = await service.replaceAll(
      documentIds: const <String>['main.styio', 'main.styio'],
      query: 'value',
      replacement: 'next',
    );
    final document = await store.loadDocument('main.styio');

    expect(result.documents, hasLength(1));
    expect(result.replacementCount, 2);
    expect(document.text, 'next next\n');
    expect(document.revision, 2);
  });

  test('workspace search history appends latest unique records first', () {
    final first = WorkspaceSearchHistoryRecord(
      query: 'value',
      mode: WorkspaceSearchHistoryMode.text,
      createdAt: DateTime.utc(2026, 5, 20),
    );
    final second = WorkspaceSearchHistoryRecord(
      query: 'value',
      replacement: 'next',
      mode: WorkspaceSearchHistoryMode.replacePreview,
      createdAt: DateTime.utc(2026, 5, 20, 0, 1),
    );

    final history = const WorkspaceSearchHistory(
      workspaceId: 'demo',
    ).append(first).append(second).append(first, maxEntries: 2);

    expect(history.records.map((record) => record.mode), <Object>[
      WorkspaceSearchHistoryMode.text,
      WorkspaceSearchHistoryMode.replacePreview,
    ]);
    expect(
      history
          .recordsForMode(WorkspaceSearchHistoryMode.replacePreview)
          .single
          .replacement,
      'next',
    );
    expect(history.toJson()['recordCount'], 2);
  });

  test('workspace search history persists through DataStore', () async {
    final store = WorkspaceSearchHistoryStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    final record = WorkspaceSearchHistoryRecord(
      query: r'value\d+',
      mode: WorkspaceSearchHistoryMode.text,
      useRegex: true,
      createdAt: DateTime.utc(2026, 5, 20),
    );

    await store.appendRecord(workspaceId: 'demo', record: record);
    final restored = await store.readHistory(workspaceId: 'demo');

    expect(restored.workspaceId, 'demo');
    expect(restored.records.single.query, r'value\d+');
    expect(restored.records.single.useRegex, isTrue);
    expect(restored.records.single.mode, WorkspaceSearchHistoryMode.text);
    expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
    expect((await store.readHistory(workspaceId: 'demo')).records, isEmpty);
  });
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_workspace_search_history_test_',
  );
  addTearDown(() => tempRoot.delete(recursive: true));
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}

class _FailingWorkspaceSearchStore implements WorkspaceDocumentStore {
  @override
  Future<DocumentState> loadDocument(String path) async {
    if (path == 'missing.styio') {
      throw StateError('failed to load $path');
    }
    return DocumentState(
      documentId: path,
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
  }

  @override
  Future<void> saveDocument(DocumentState document) async {}

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => path != 'missing.styio';

  @override
  String? filePathForDocumentId(String documentId) => null;
}

class _FailingSaveWorkspaceSearchStore implements WorkspaceDocumentStore {
  final Map<String, DocumentState> _documents = <String, DocumentState>{
    'main.styio': const DocumentState(
      documentId: 'main.styio',
      text: 'value value\n',
      revision: 1,
    ),
    'fail-save.styio': const DocumentState(
      documentId: 'fail-save.styio',
      text: 'value\n',
      revision: 1,
    ),
  };

  @override
  Future<DocumentState> loadDocument(String path) async => _documents[path]!;

  @override
  Future<void> saveDocument(DocumentState document) async {
    if (document.documentId == 'fail-save.styio') {
      throw StateError('failed to save ${document.documentId}');
    }
    _documents[document.documentId] = document;
  }

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async =>
      _documents.containsKey(path);

  @override
  String? filePathForDocumentId(String documentId) => null;
}
