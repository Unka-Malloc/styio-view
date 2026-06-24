import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_provider.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_search_service.dart';

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

  test('workspace replace preview exposes virtualized document windows', () {
    const preview = WorkspaceReplacePreview(
      documents: <WorkspaceReplacePreviewDocument>[
        WorkspaceReplacePreviewDocument(
          documentId: 'src/a.styio',
          beforeText: 'needle\n',
          afterText: 'value\n',
          replacementCount: 1,
          revision: 1,
        ),
        WorkspaceReplacePreviewDocument(
          documentId: 'src/b.styio',
          beforeText: 'needle\n',
          afterText: 'value\n',
          replacementCount: 1,
          revision: 2,
        ),
        WorkspaceReplacePreviewDocument(
          documentId: 'src/c.styio',
          beforeText: 'needle\n',
          afterText: 'value\n',
          replacementCount: 1,
          revision: 3,
        ),
      ],
    );

    final window = preview.window(documentOffset: 1, documentLimit: 1);
    final json = window.toJson();

    expect(window.documents.single.documentId, 'src/b.styio');
    expect(window.hasPreviousDocuments, isTrue);
    expect(window.hasMoreDocuments, isTrue);
    expect(json['documentOffset'], 1);
    expect(json['windowDocumentCount'], 1);
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
    'workspace symbol search exposes fallback semantic confidence',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': DocumentState(
            documentId: 'src/main.styio',
            text: '#main := (): string => {\n  value := 1\n  value\n}\n',
            revision: 1,
          ),
        },
      );
      final service = WorkspaceSymbolSearchService(
        documentStore: store,
        semanticSnapshotProvider: SemanticSnapshotProvider(
          languageService: CachedStyioLanguageService(
            cache: StyioServiceResultCache(),
            allowLocalFallback: false,
          ),
        ),
      );

      final result = await service.searchSymbols(
        documentIds: const <String>['src/main.styio'],
        query: 'value',
      );

      expect(result.matches.single.name, 'value');
      expect(result.matches.single.usedFallback, isTrue);
      expect(
        result.matches.single.snapshotSource,
        SemanticSnapshotProviderSource.localBuilderFallback,
      );
      expect(
        result.matches.single.snapshotConfidence,
        SemanticSnapshotFeatureConfidence.localFallback,
      );
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
    'workspace search index searches loaded snapshot without store reads',
    () async {
      final store = _CountingWorkspaceSearchStore(
        documents: const <String, DocumentState>{
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

      final build = await service.buildIndex(
        documentIds: const <String>['main.styio', 'helper.styio', 'main.styio'],
      );
      final indexed = build.index.search(query: 'value', wholeWord: true);
      final loadCountAfterIndexedSearch = store.loadCount;
      final direct = await service.search(
        documentIds: const <String>['main.styio', 'helper.styio'],
        query: 'value',
        wholeWord: true,
      );

      expect(build.failures, isEmpty);
      expect(build.index.documentIds, <String>['main.styio', 'helper.styio']);
      expect(build.index.documentCount, 2);
      expect(build.index.totalLineCount, 4);
      expect(build.index.totalByteLength, 39);
      expect(loadCountAfterIndexedSearch, 2);
      expect(store.loadCount, 4);
      expect(
        indexed.matches.map(
          (match) => '${match.documentId}:${match.lineNumber}:${match.text}',
        ),
        direct.matches.map(
          (match) => '${match.documentId}:${match.lineNumber}:${match.text}',
        ),
      );
      expect(indexed.failures, isEmpty);
      expect(indexed.truncated, isFalse);
      expect(build.index.toJson()['documents'], isA<List<Object?>>());
    },
  );

  test('workspace search index reports load failures and truncation', () async {
    final service = WorkspaceSearchService(
      documentStore: _FailingWorkspaceSearchStore(),
    );

    final failure = await service.buildIndex(
      documentIds: const <String>['missing.styio', 'main.styio'],
    );
    final truncated = await service.buildIndex(
      documentIds: const <String>['main.styio', 'helper.styio'],
      maxDocuments: 1,
    );
    final empty = await service.buildIndex(
      documentIds: const <String>['main.styio'],
      maxDocuments: 0,
    );

    expect(failure.index.documentIds, <String>['main.styio']);
    expect(failure.failures.single.documentId, 'missing.styio');
    expect(failure.index.truncated, isFalse);
    expect(truncated.index.documentIds, <String>['main.styio']);
    expect(truncated.index.truncated, isTrue);
    expect(empty.index.documents, isEmpty);
    expect(empty.index.truncated, isTrue);
  });

  test(
    'workspace search index controller refreshes only stale revisions',
    () async {
      final store = _CountingWorkspaceSearchStore(
        documents: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value := 1\n',
            revision: 1,
          ),
          'helper.styio': DocumentState(
            documentId: 'helper.styio',
            text: 'helper := value\n',
            revision: 1,
          ),
        },
      );
      final controller = WorkspaceSearchIndexController(
        service: WorkspaceSearchService(documentStore: store),
      );

      final first = await controller.refreshIfStale(
        currentDocuments: const <DocumentState>[
          DocumentState(
            documentId: 'main.styio',
            text: 'value := 1\n',
            revision: 1,
          ),
          DocumentState(
            documentId: 'helper.styio',
            text: 'helper := value\n',
            revision: 1,
          ),
        ],
      );
      final cached = await controller.refreshIfStale(
        currentDocuments: const <DocumentState>[
          DocumentState(
            documentId: 'main.styio',
            text: 'value := 1\n',
            revision: 1,
          ),
          DocumentState(
            documentId: 'helper.styio',
            text: 'helper := value\n',
            revision: 1,
          ),
        ],
      );
      await store.saveDocument(
        const DocumentState(
          documentId: 'main.styio',
          text: 'next := value\n',
          revision: 2,
        ),
      );
      final refreshed = await controller.refreshIfStale(
        currentDocuments: const <DocumentState>[
          DocumentState(
            documentId: 'main.styio',
            text: 'next := value\n',
            revision: 2,
          ),
          DocumentState(
            documentId: 'helper.styio',
            text: 'helper := value\n',
            revision: 1,
          ),
        ],
      );
      final cachedSearch = controller.searchCached(query: 'next');

      expect(first.status, WorkspaceSearchIndexRefreshStatus.ready);
      expect(first.staleDocumentIds, <String>['helper.styio', 'main.styio']);
      expect(first.generation, 1);
      expect(cached.generation, 1);
      expect(store.loadCount, 4);
      expect(refreshed.generation, 2);
      expect(refreshed.staleDocumentIds, <String>['main.styio']);
      expect(cachedSearch.matches.single.documentId, 'main.styio');
      expect(refreshed.toJson()['status'], 'ready');
    },
  );

  test(
    'workspace search index watcher refreshes from file system events',
    () async {
      final store = _CountingWorkspaceSearchStore(
        documents: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value := 1\n',
            revision: 1,
          ),
        },
      );
      final controller = WorkspaceSearchIndexController(
        service: WorkspaceSearchService(documentStore: store),
      );
      var documents = const <DocumentState>[
        DocumentState(
          documentId: 'main.styio',
          text: 'value := 1\n',
          revision: 1,
        ),
      ];
      final events = StreamController<FileSystemManagerEvent>();
      final fileSystemManager = _FakeWorkspaceSearchFileSystemManager(
        events.stream,
      );
      final binding = WorkspaceSearchIndexFileSystemWatcherBinding(
        controller: controller,
        fileSystemManager: fileSystemManager,
        workspaceRoot: '/workspace/vityo',
        currentDocuments: () => documents,
      );
      final snapshots = <WorkspaceSearchIndexWatcherSnapshot>[];
      final completed = Completer<void>();
      final subscription = binding.watchAndRefresh().listen(
        snapshots.add,
        onDone: completed.complete,
      );
      addTearDown(subscription.cancel);
      addTearDown(events.close);

      await Future<void>.delayed(Duration.zero);
      await store.saveDocument(
        const DocumentState(
          documentId: 'main.styio',
          text: 'next := value\n',
          revision: 2,
        ),
      );
      documents = const <DocumentState>[
        DocumentState(
          documentId: 'main.styio',
          text: 'next := value\n',
          revision: 2,
        ),
      ];
      events.add(
        const FileSystemManagerEvent(
          kind: FileSystemManagerEventKind.modified,
          path: '/workspace/vityo/main.styio',
          normalizedPath: '/workspace/vityo/main.styio',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await events.close();
      await completed.future;

      expect(fileSystemManager.watchedPath, '/workspace/vityo');
      expect(fileSystemManager.watchedRecursive, isTrue);
      expect(
        snapshots.first.status,
        WorkspaceSearchIndexWatcherStatus.listening,
      );
      expect(snapshots.any((snapshot) => snapshot.ready), isTrue);
      expect(controller.snapshot.generation, 1);
      expect(
        controller.searchCached(query: 'next').matches.single.documentId,
        'main.styio',
      );
      expect(
        snapshots
            .where((snapshot) => snapshot.ready)
            .single
            .refreshPlan
            ?.eventCount,
        1,
      );
      expect(snapshots.last.status, WorkspaceSearchIndexWatcherStatus.stopped);
      expect(snapshots.last.toJson()['status'], 'stopped');
    },
  );

  test(
    'workspace search watcher stream batcher flushes on debounce timer',
    () async {
      final events = StreamController<FileSystemManagerEvent>();
      final batches = <WorkspaceSearchWatcherEventBatch>[];
      final subscription = const WorkspaceSearchWatcherStreamBatcher(
        policy: WorkspaceSearchWatcherPolicy(
          debounceWindow: Duration(milliseconds: 5),
          maxEventsPerBatch: 10,
        ),
      ).bind(events.stream).listen(batches.add);
      addTearDown(subscription.cancel);
      addTearDown(events.close);

      events
        ..add(
          const FileSystemManagerEvent(
            kind: FileSystemManagerEventKind.modified,
            path: '/workspace/vityo/src/a.styio',
            normalizedPath: '/workspace/vityo/src/a.styio',
          ),
        )
        ..add(
          const FileSystemManagerEvent(
            kind: FileSystemManagerEventKind.modified,
            path: '/workspace/vityo/src/b.styio',
            normalizedPath: '/workspace/vityo/src/b.styio',
          ),
        );
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(batches, hasLength(1));
      expect(batches.single.eventCount, 2);
      expect(batches.single.shouldRefresh, isTrue);
      expect(batches.single.refreshPlan.refreshEventCount, 2);
      expect(batches.single.toJson()['eventCount'], 2);
    },
  );

  test(
    'workspace search watcher safeguards expose refresh and recovery plans',
    () {
      const policy = WorkspaceSearchWatcherPolicy(
        debounceWindow: Duration(milliseconds: 75),
        maxEventsPerBatch: 1,
        maxQueuedEvents: 3,
        ignoredPathPrefixes: <String>['/workspace/vityo/.git/'],
        ignoredPathSuffixes: <String>['.tmp'],
      );
      final plan = WorkspaceSearchWatcherRefreshPlan.fromEvents(
        policy: policy,
        events: const <FileSystemManagerEvent>[
          FileSystemManagerEvent(
            kind: FileSystemManagerEventKind.modified,
            path: '/workspace/vityo/src/main.styio',
            normalizedPath: '/workspace/vityo/src/main.styio',
          ),
          FileSystemManagerEvent(
            kind: FileSystemManagerEventKind.modified,
            path: '/workspace/vityo/.git/index',
            normalizedPath: '/workspace/vityo/.git/index',
          ),
          FileSystemManagerEvent(
            kind: FileSystemManagerEventKind.unknown,
            path: '/workspace/vityo/src/unknown',
            normalizedPath: '/workspace/vityo/src/unknown',
          ),
          FileSystemManagerEvent(
            kind: FileSystemManagerEventKind.deleted,
            path: '/workspace/vityo/src/extra.styio',
            normalizedPath: '/workspace/vityo/src/extra.styio',
          ),
        ],
      );
      const batchPolicy = WorkspaceSearchWatcherPolicy(
        debounceWindow: Duration(milliseconds: 75),
        maxEventsPerBatch: 2,
      );
      final batcher = WorkspaceSearchWatcherEventBatchController(
        policy: batchPolicy,
      );
      final firstBatch = batcher.add(
        const FileSystemManagerEvent(
          kind: FileSystemManagerEventKind.modified,
          path: '/workspace/vityo/src/a.styio',
          normalizedPath: '/workspace/vityo/src/a.styio',
        ),
        receivedAt: DateTime.utc(2026, 5, 20, 10),
      );
      final flushedBatch = batcher.add(
        const FileSystemManagerEvent(
          kind: FileSystemManagerEventKind.modified,
          path: '/workspace/vityo/src/b.styio',
          normalizedPath: '/workspace/vityo/src/b.styio',
        ),
        receivedAt: DateTime.utc(2026, 5, 20, 10, 0, 0, 80),
      );
      const failedSnapshot = WorkspaceSearchIndexWatcherSnapshot(
        status: WorkspaceSearchIndexWatcherStatus.failed,
        workspaceRoot: '/workspace/vityo',
        recursive: true,
        message: 'watch failed',
      );
      final retryPlan = WorkspaceSearchWatcherRecoveryPlan.fromSnapshot(
        failedSnapshot,
        failureCount: 1,
      );
      final disablePlan = WorkspaceSearchWatcherRecoveryPlan.fromSnapshot(
        failedSnapshot,
        failureCount: 3,
      );

      expect(plan.shouldRefresh, isTrue);
      expect(plan.eventCount, 3);
      expect(plan.refreshEventCount, 1);
      expect(plan.ignoredEventCount, 1);
      expect(plan.nonRefreshableEventCount, 1);
      expect(plan.truncated, isTrue);
      expect(
        (plan.toJson()['policy']! as Map<String, Object?>)['debounceMillis'],
        75,
      );
      expect(firstBatch, isNull);
      expect(flushedBatch?.eventCount, 2);
      expect(flushedBatch?.shouldRefresh, isTrue);
      expect(flushedBatch?.toJson()['shouldRefresh'], isTrue);
      expect(
        retryPlan.action,
        WorkspaceSearchWatcherRecoveryAction.restartWatcher,
      );
      expect(retryPlan.canRetry, isTrue);
      expect(
        disablePlan.action,
        WorkspaceSearchWatcherRecoveryAction.disableWatcher,
      );
      expect(disablePlan.canRetry, isFalse);
    },
  );

  test(
    'workspace search watcher recovery persists through DataStore',
    () async {
      final store = WorkspaceSearchWatcherRecoveryStore.fromDataStore(
        dataStore: await _createDataStore(),
      );
      const failedSnapshot = WorkspaceSearchIndexWatcherSnapshot(
        status: WorkspaceSearchIndexWatcherStatus.failed,
        workspaceRoot: '/workspace/vityo',
        recursive: true,
        message: 'watch failed',
      );
      final retryPlan = WorkspaceSearchWatcherRecoveryPlan.fromSnapshot(
        failedSnapshot,
        failureCount: 1,
      );
      final disablePlan = WorkspaceSearchWatcherRecoveryPlan.fromSnapshot(
        failedSnapshot,
        failureCount: 3,
      );

      final first = await store.recordPlan(
        workspaceId: 'demo',
        plan: retryPlan,
      );
      final second = await store.recordPlan(
        workspaceId: 'demo',
        plan: disablePlan,
      );
      final restored = await store.readState(workspaceId: 'demo');

      expect(first.failureCount, 1);
      expect(second.failureCount, 2);
      expect(
        restored.lastPlan?.action,
        WorkspaceSearchWatcherRecoveryAction.disableWatcher,
      );
      expect(restored.recoveryDisabled, isTrue);
      expect(restored.toJson()['recoveryDisabled'], isTrue);
      expect(await store.deleteState(workspaceId: 'demo'), isTrue);
      expect((await store.readState(workspaceId: 'demo')).failureCount, 0);
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

// DELETED-MERGE:   test('workspace search history appends latest unique records first', () {
// DELETED-MERGE:     final first = WorkspaceSearchHistoryRecord(
// DELETED-MERGE:       query: 'value',
// DELETED-MERGE:       mode: WorkspaceSearchHistoryMode.text,
// DELETED-MERGE:       createdAt: DateTime.utc(2026, 5, 20),
// DELETED-MERGE:     );
// DELETED-MERGE:     final second = WorkspaceSearchHistoryRecord(
// DELETED-MERGE:       query: 'value',
// DELETED-MERGE:       replacement: 'next',
// DELETED-MERGE:       mode: WorkspaceSearchHistoryMode.replacePreview,
// DELETED-MERGE:       createdAt: DateTime.utc(2026, 5, 20, 0, 1),
// DELETED-MERGE:     );
// DELETED-MERGE: 
// DELETED-MERGE:     final history = const WorkspaceSearchHistory(
// DELETED-MERGE:       workspaceId: 'demo',
// DELETED-MERGE:     ).append(first).append(second).append(first, maxEntries: 2);
// DELETED-MERGE: 
// DELETED-MERGE:     expect(history.records.map((record) => record.mode), <Object>[
// DELETED-MERGE:       WorkspaceSearchHistoryMode.text,
// DELETED-MERGE:       WorkspaceSearchHistoryMode.replacePreview,
// DELETED-MERGE:     ]);
// DELETED-MERGE:     expect(
// DELETED-MERGE:       history
// DELETED-MERGE:           .recordsForMode(WorkspaceSearchHistoryMode.replacePreview)
// DELETED-MERGE:           .single
// DELETED-MERGE:           .replacement,
// DELETED-MERGE:       'next',
// DELETED-MERGE:     );
// DELETED-MERGE:     expect(history.toJson()['recordCount'], 2);
// DELETED-MERGE:   });
// DELETED-MERGE: 
// DELETED-MERGE:   test('workspace search index exposes invalidation keys', () {
// DELETED-MERGE:     final index = WorkspaceSearchIndex(
// DELETED-MERGE:       documents: <WorkspaceSearchIndexDocument>[
// DELETED-MERGE:         WorkspaceSearchIndexDocument.fromDocument(
// DELETED-MERGE:           const DocumentState(
// DELETED-MERGE:             documentId: 'main.styio',
// DELETED-MERGE:             text: 'value := 1\n',
// DELETED-MERGE:             revision: 1,
// DELETED-MERGE:           ),
// DELETED-MERGE:         ),
// DELETED-MERGE:         WorkspaceSearchIndexDocument.fromDocument(
// DELETED-MERGE:           const DocumentState(
// DELETED-MERGE:             documentId: 'lib.styio',
// DELETED-MERGE:             text: 'lib := value\n',
// DELETED-MERGE:             revision: 4,
// DELETED-MERGE:           ),
// DELETED-MERGE:         ),
// DELETED-MERGE:       ],
// DELETED-MERGE:       createdAt: DateTime.utc(2026, 5, 20),
// DELETED-MERGE:     );
// DELETED-MERGE:     final current = WorkspaceSearchIndexInvalidationKey.fromDocumentStates(
// DELETED-MERGE:       const <DocumentState>[
// DELETED-MERGE:         DocumentState(
// DELETED-MERGE:           documentId: 'main.styio',
// DELETED-MERGE:           text: 'value := 2\n',
// DELETED-MERGE:           revision: 2,
// DELETED-MERGE:         ),
// DELETED-MERGE:         DocumentState(documentId: 'new.styio', text: 'new := 1\n', revision: 1),
// DELETED-MERGE:       ],
// DELETED-MERGE:     );
// DELETED-MERGE:     final restored = WorkspaceSearchIndexInvalidationKey.fromJson(
// DELETED-MERGE:       index.invalidationKey.toJson(),
// DELETED-MERGE:     );
// DELETED-MERGE: 
// DELETED-MERGE:     expect(restored.matches(index.invalidationKey), isTrue);
// DELETED-MERGE:     expect(index.invalidationKey.matches(current), isFalse);
// DELETED-MERGE:     expect(index.invalidationKey.staleDocumentIds(current), <String>[
// DELETED-MERGE:       'lib.styio',
// DELETED-MERGE:       'main.styio',
// DELETED-MERGE:       'new.styio',
// DELETED-MERGE:     ]);
// DELETED-MERGE:     expect(
// DELETED-MERGE:       (index.toJson()['invalidationKey']!
// DELETED-MERGE:           as Map<String, Object?>)['documentCount'],
// DELETED-MERGE:       2,
// DELETED-MERGE:     );
// DELETED-MERGE:   });
// DELETED-MERGE: 
// DELETED-MERGE:   test('workspace search history persists through DataStore', () async {
// DELETED-MERGE:     final store = WorkspaceSearchHistoryStore.fromDataStore(
// DELETED-MERGE:       dataStore: await _createDataStore(),
// DELETED-MERGE:     );
// DELETED-MERGE:     final record = WorkspaceSearchHistoryRecord(
// DELETED-MERGE:       query: r'value\d+',
// DELETED-MERGE:       mode: WorkspaceSearchHistoryMode.text,
// DELETED-MERGE:       useRegex: true,
// DELETED-MERGE:       createdAt: DateTime.utc(2026, 5, 20),
// DELETED-MERGE:     );
// DELETED-MERGE: 
// DELETED-MERGE:     await store.appendRecord(workspaceId: 'demo', record: record);
// DELETED-MERGE:     final restored = await store.readHistory(workspaceId: 'demo');
// DELETED-MERGE: 
// DELETED-MERGE:     expect(restored.workspaceId, 'demo');
// DELETED-MERGE:     expect(restored.records.single.query, r'value\d+');
// DELETED-MERGE:     expect(restored.records.single.useRegex, isTrue);
// DELETED-MERGE:     expect(restored.records.single.mode, WorkspaceSearchHistoryMode.text);
// DELETED-MERGE:     expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
// DELETED-MERGE:     expect((await store.readHistory(workspaceId: 'demo')).records, isEmpty);
// DELETED-MERGE:   });
// DELETED-MERGE: 
// DELETED-MERGE:   test('workspace search filters persist through DataStore', () async {
// DELETED-MERGE:     final store = WorkspaceSearchFilterStore.fromDataStore(
// DELETED-MERGE:       dataStore: await _createDataStore(),
// DELETED-MERGE:     );
// DELETED-MERGE: 
// DELETED-MERGE:     final saved = await store.saveFilters(
// DELETED-MERGE:       const WorkspaceSearchFilterState(
// DELETED-MERGE:         workspaceId: 'demo',
// DELETED-MERGE:         caseSensitive: true,
// DELETED-MERGE:         wholeWord: true,
// DELETED-MERGE:         useRegex: true,
// DELETED-MERGE:         includeGlob: 'src/**',
// DELETED-MERGE:         excludeGlob: 'build/**',
// DELETED-MERGE:       ),
// DELETED-MERGE:     );
// DELETED-MERGE:     final restored = await store.readFilters(workspaceId: 'demo');
// DELETED-MERGE: 
// DELETED-MERGE:     expect(saved.active, isTrue);
// DELETED-MERGE:     expect(restored.workspaceId, 'demo');
// DELETED-MERGE:     expect(restored.caseSensitive, isTrue);
// DELETED-MERGE:     expect(restored.wholeWord, isTrue);
// DELETED-MERGE:     expect(restored.useRegex, isTrue);
// DELETED-MERGE:     expect(restored.includeGlob, 'src/**');
// DELETED-MERGE:     expect(restored.excludeGlob, 'build/**');
// DELETED-MERGE:     expect(restored.toJson()['active'], isTrue);
// DELETED-MERGE:     expect(await store.deleteFilters(workspaceId: 'demo'), isTrue);
// DELETED-MERGE:     expect((await store.readFilters(workspaceId: 'demo')).active, isFalse);
// DELETED-MERGE:   });
// DELETED-MERGE: 
// DELETED-MERGE:   test(
// DELETED-MERGE:     'workspace replace preview expansion state persists through DataStore',
// DELETED-MERGE:     () async {
// DELETED-MERGE:       final store = WorkspaceReplacePreviewExpansionStore.fromDataStore(
// DELETED-MERGE:         dataStore: await _createDataStore(),
// DELETED-MERGE:       );
// DELETED-MERGE: 
// DELETED-MERGE:       final expanded = await store.toggleDocument(
// DELETED-MERGE:         workspaceId: 'demo',
// DELETED-MERGE:         documentId: 'src/main.styio',
// DELETED-MERGE:       );
// DELETED-MERGE:       final collapsed = await store.toggleDocument(
// DELETED-MERGE:         workspaceId: 'demo',
// DELETED-MERGE:         documentId: 'src/main.styio',
// DELETED-MERGE:       );
// DELETED-MERGE:       await store.saveState(
// DELETED-MERGE:         state: const WorkspaceReplacePreviewExpansionState(
// DELETED-MERGE:           workspaceId: 'demo',
// DELETED-MERGE:           expandedDocumentIds: <String>['src/lib.styio', 'src/main.styio'],
// DELETED-MERGE:         ),
// DELETED-MERGE:       );
// DELETED-MERGE:       final restored = await store.readState(workspaceId: 'demo');
// DELETED-MERGE: 
// DELETED-MERGE:       expect(expanded.expandedDocumentIds, <String>['src/main.styio']);
// DELETED-MERGE:       expect(collapsed.expandedDocumentIds, isEmpty);
// DELETED-MERGE:       expect(restored.workspaceId, 'demo');
// DELETED-MERGE:       expect(restored.expandedDocumentIds, <String>[
// DELETED-MERGE:         'src/lib.styio',
// DELETED-MERGE:         'src/main.styio',
// DELETED-MERGE:       ]);
// DELETED-MERGE:       expect(restored.isExpanded('src/main.styio'), isTrue);
// DELETED-MERGE:       expect(restored.toJson()['expandedCount'], 2);
// DELETED-MERGE:       expect(await store.deleteState(workspaceId: 'demo'), isTrue);
// DELETED-MERGE:       expect(
// DELETED-MERGE:         (await store.readState(workspaceId: 'demo')).expandedDocumentIds,
// DELETED-MERGE:         isEmpty,
// DELETED-MERGE:       );
// DELETED-MERGE:     },
// DELETED-MERGE:   );
// DELETED-MERGE: }
// DELETED-MERGE: 
// DELETED-MERGE: Future<FoundationDataStore> _createDataStore() async {
// DELETED-MERGE:   final tempRoot = await Directory.systemTemp.createTemp(
// DELETED-MERGE:     'vityo_workspace_search_history_test_',
// DELETED-MERGE:   );
// DELETED-MERGE:   addTearDown(() => tempRoot.delete(recursive: true));
// DELETED-MERGE:   final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
// DELETED-MERGE:   final resourceManager = LocalResourceManager(
// DELETED-MERGE:     facts: ResourceFacts.linuxDebianArm(
// DELETED-MERGE:       systemTempPath: tempRoot.path,
// DELETED-MERGE:       homePath: tempRoot.path,
// DELETED-MERGE:     ),
// DELETED-MERGE:   );
// DELETED-MERGE:   return FoundationDataStore(
// DELETED-MERGE:     resourceCoordinator: FoundationResourceCoordinator(
// DELETED-MERGE:       resourceManager: resourceManager,
// DELETED-MERGE:       fileSystemManager: fileSystemManager,
// DELETED-MERGE:     ),
// DELETED-MERGE:     fileSystemManager: fileSystemManager,
// DELETED-MERGE:   );
// DELETED-MERGE: }
// DELETED-MERGE: 
// DELETED-MERGE: class _FailingWorkspaceSearchStore implements WorkspaceDocumentStore {
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<DocumentState> loadDocument(String path) async {
// DELETED-MERGE:     if (path == 'missing.styio') {
// DELETED-MERGE:       throw StateError('failed to load $path');
// DELETED-MERGE:     }
// DELETED-MERGE:     return DocumentState(
// DELETED-MERGE:       documentId: path,
// DELETED-MERGE:       text: 'value := 1\nvalue\n',
// DELETED-MERGE:       revision: 1,
// DELETED-MERGE:     );
// DELETED-MERGE:   }
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<void> saveDocument(DocumentState document) async {}
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<bool> deleteDocument(String path) async => false;
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<bool> documentExists(String path) async => path != 'missing.styio';
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   String? filePathForDocumentId(String documentId) => null;
// DELETED-MERGE: }
// DELETED-MERGE: 
// DELETED-MERGE: class _FailingSaveWorkspaceSearchStore implements WorkspaceDocumentStore {
// DELETED-MERGE:   final Map<String, DocumentState> _documents = <String, DocumentState>{
// DELETED-MERGE:     'main.styio': const DocumentState(
// DELETED-MERGE:       documentId: 'main.styio',
// DELETED-MERGE:       text: 'value value\n',
// DELETED-MERGE:       revision: 1,
// DELETED-MERGE:     ),
// DELETED-MERGE:     'fail-save.styio': const DocumentState(
// DELETED-MERGE:       documentId: 'fail-save.styio',
// DELETED-MERGE:       text: 'value\n',
// DELETED-MERGE:       revision: 1,
// DELETED-MERGE:     ),
// DELETED-MERGE:   };
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<DocumentState> loadDocument(String path) async => _documents[path]!;
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<void> saveDocument(DocumentState document) async {
// DELETED-MERGE:     if (document.documentId == 'fail-save.styio') {
// DELETED-MERGE:       throw StateError('failed to save ${document.documentId}');
// DELETED-MERGE:     }
// DELETED-MERGE:     _documents[document.documentId] = document;
// DELETED-MERGE:   }
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<bool> deleteDocument(String path) async => false;
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<bool> documentExists(String path) async =>
// DELETED-MERGE:       _documents.containsKey(path);
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   String? filePathForDocumentId(String documentId) => null;
// DELETED-MERGE: }
// DELETED-MERGE: 
// DELETED-MERGE: class _FakeWorkspaceSearchFileSystemManager
// DELETED-MERGE:     extends UnsupportedFileSystemManager {
// DELETED-MERGE:   _FakeWorkspaceSearchFileSystemManager(this.events)
// DELETED-MERGE:     : super(facts: FileSystemFacts.linuxDebianArm());
// DELETED-MERGE: 
// DELETED-MERGE:   final Stream<FileSystemManagerEvent> events;
// DELETED-MERGE:   String watchedPath = '';
// DELETED-MERGE:   bool watchedRecursive = false;
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Stream<FileSystemManagerEvent> watch(String path, {bool recursive = false}) {
// DELETED-MERGE:     watchedPath = path;
// DELETED-MERGE:     watchedRecursive = recursive;
// DELETED-MERGE:     return events;
// DELETED-MERGE:   }
// DELETED-MERGE: }
// DELETED-MERGE: 
// DELETED-MERGE: class _CountingWorkspaceSearchStore implements WorkspaceDocumentStore {
// DELETED-MERGE:   _CountingWorkspaceSearchStore({required Map<String, DocumentState> documents})
// DELETED-MERGE:     : _documents = Map<String, DocumentState>.of(documents);
// DELETED-MERGE: 
// DELETED-MERGE:   final Map<String, DocumentState> _documents;
// DELETED-MERGE:   int loadCount = 0;
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<DocumentState> loadDocument(String path) async {
// DELETED-MERGE:     loadCount += 1;
// DELETED-MERGE:     final document = _documents[path];
// DELETED-MERGE:     if (document == null) {
// DELETED-MERGE:       throw StateError('missing $path');
// DELETED-MERGE:     }
// DELETED-MERGE:     return document;
// DELETED-MERGE:   }
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<void> saveDocument(DocumentState document) async {
// DELETED-MERGE:     _documents[document.documentId] = document;
// DELETED-MERGE:   }
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<bool> deleteDocument(String path) async =>
// DELETED-MERGE:       _documents.remove(path) != null;
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   Future<bool> documentExists(String path) async =>
// DELETED-MERGE:       _documents.containsKey(path);
// DELETED-MERGE: 
// DELETED-MERGE:   @override
// DELETED-MERGE:   String? filePathForDocumentId(String documentId) => null;
// DELETED-MERGE: }
