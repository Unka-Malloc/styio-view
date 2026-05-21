import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace file explorer builds stable directory tree', () {
    final tree = buildWorkspaceFileExplorerTree(const <String>[
      'README.md',
      'src/main.styio',
      'src/lib/math.styio',
      'test/parser_test.styio',
    ]);

    expect(tree.map((node) => node.name), <String>['src', 'test', 'README.md']);
    expect(tree.first.kind, WorkspaceFileExplorerNodeKind.directory);
    expect(tree.first.fileCount, 2);
    expect(tree.first.children.map((node) => node.path), <String>[
      'src/lib',
      'src/main.styio',
    ]);
    expect(tree.first.toJson()['fileCount'], 2);
  });

  test('workspace file explorer discovery normalizes file system paths', () {
    final discovery = WorkspaceFileExplorerDiscoveryResult.fromPaths(
      seedPaths: const <String>['README.md'],
      discoveredPaths: const <String>[
        'src\\main.styio',
        'src/main.styio',
        'src/lib/math.styio',
        '../secret.styio',
        '/tmp/outside.styio',
        '',
      ],
      source: 'fixture-fs',
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['README.md']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: InMemoryWorkspaceDocumentStore(),
      ),
    );
    addTearDown(controller.dispose);

    final snapshot = controller.snapshotFromDiscovery(discovery);

    expect(discovery.source, 'fixture-fs');
    expect(discovery.filePaths, <String>[
      'README.md',
      'src/lib/math.styio',
      'src/main.styio',
    ]);
    expect(discovery.ignoredPathCount, 3);
    expect(discovery.truncated, isFalse);
    expect(snapshot.fileCount, 3);
    expect(snapshot.discovery, same(discovery));
    expect(snapshot.roots.map((node) => node.name), <String>[
      'src',
      'README.md',
    ]);
    expect(snapshot.toJson()['discovery'], isA<Map<String, Object?>>());
  });

  test('workspace file explorer watch snapshot applies file system events', () {
    final plan = const WorkspaceFileExplorerWatchPlan(
      rootPath: '/workspace/fixture',
    ).activate(message: 'watcher attached');
    final watch = WorkspaceFileExplorerWatchSnapshot(
      plan: plan,
      baseFilePaths: const <String>[
        'README.md',
        'build/generated.styio',
        'src/old.styio',
        'src/stale.styio',
      ],
      events: <WorkspaceFileExplorerWatchEvent>[
        WorkspaceFileExplorerWatchEvent(
          kind: WorkspaceFileExplorerWatchEventKind.created,
          path: 'src/new.styio',
          timestamp: DateTime.utc(2026, 5, 20, 12),
        ),
        WorkspaceFileExplorerWatchEvent(
          kind: WorkspaceFileExplorerWatchEventKind.renamed,
          path: 'src/old.styio',
          nextPath: 'src/current.styio',
          timestamp: DateTime.utc(2026, 5, 20, 12, 1),
        ),
        WorkspaceFileExplorerWatchEvent(
          kind: WorkspaceFileExplorerWatchEventKind.deleted,
          path: 'src/stale.styio',
          timestamp: DateTime.utc(2026, 5, 20, 12, 2),
        ),
        WorkspaceFileExplorerWatchEvent(
          kind: WorkspaceFileExplorerWatchEventKind.created,
          path: '../outside.styio',
          timestamp: DateTime.utc(2026, 5, 20, 12, 3),
        ),
        WorkspaceFileExplorerWatchEvent(
          kind: WorkspaceFileExplorerWatchEventKind.created,
          path: '.git/config',
          timestamp: DateTime.utc(2026, 5, 20, 12, 4),
        ),
      ],
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['README.md']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: InMemoryWorkspaceDocumentStore(),
      ),
    );
    addTearDown(controller.dispose);

    final snapshot = controller.snapshotFromWatch(watch);

    expect(plan.active, isTrue);
    expect(watch.filePaths, <String>[
      'README.md',
      'src/current.styio',
      'src/new.styio',
    ]);
    expect(watch.toJson()['eventCount'], 5);
    expect(watch.toDiscoveryResult().source, 'file-system-manager.watch');
    expect(snapshot.watch, same(watch));
    expect(snapshot.discovery?.fileCount, 3);
    expect(snapshot.fileCount, 3);
    expect(snapshot.toJson()['watch'], isA<Map<String, Object?>>());
  });

  test('workspace file explorer watcher debounce batches events', () {
    const policy = WorkspaceFileExplorerWatchDebouncePolicy(
      window: Duration(milliseconds: 100),
      maxBatchEvents: 3,
    );
    final batcher = WorkspaceFileExplorerWatchEventBatcher(policy: policy);

    final first = batcher.add(
      WorkspaceFileExplorerWatchEvent(
        kind: WorkspaceFileExplorerWatchEventKind.created,
        path: 'src/a.styio',
        timestamp: DateTime.utc(2026, 5, 20, 14),
      ),
    );
    final second = batcher.add(
      WorkspaceFileExplorerWatchEvent(
        kind: WorkspaceFileExplorerWatchEventKind.modified,
        path: 'src/a.styio',
        timestamp: DateTime.utc(2026, 5, 20, 14, 0, 0, 50),
      ),
    );
    final third = batcher.add(
      WorkspaceFileExplorerWatchEvent(
        kind: WorkspaceFileExplorerWatchEventKind.created,
        path: 'src/b.styio',
        timestamp: DateTime.utc(2026, 5, 20, 14, 0, 0, 90),
      ),
    );

    expect(first, isNull);
    expect(second, isNull);
    expect(third?.eventCount, 3);
    expect(batcher.pendingEventCount, 0);
    expect(policy.toJson()['maxBatchEvents'], 3);
    expect(third?.toJson()['eventCount'], 3);
  });

  test(
    'workspace file explorer watcher stream batcher flushes by timer',
    () async {
      final events = StreamController<WorkspaceFileExplorerWatchEvent>();
      final batches = <WorkspaceFileExplorerWatchEventBatch>[];
      final subscription = const WorkspaceFileExplorerWatchStreamBatcher(
        policy: WorkspaceFileExplorerWatchDebouncePolicy(
          window: Duration(milliseconds: 5),
          maxBatchEvents: 10,
        ),
      ).bind(events.stream).listen(batches.add);
      addTearDown(subscription.cancel);
      addTearDown(events.close);

      events
        ..add(
          WorkspaceFileExplorerWatchEvent(
            kind: WorkspaceFileExplorerWatchEventKind.created,
            path: 'src/a.styio',
            timestamp: DateTime.utc(2026, 5, 20, 14),
          ),
        )
        ..add(
          WorkspaceFileExplorerWatchEvent(
            kind: WorkspaceFileExplorerWatchEventKind.modified,
            path: 'src/b.styio',
            timestamp: DateTime.utc(2026, 5, 20, 14, 0, 0, 1),
          ),
        );
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(batches, hasLength(1));
      expect(batches.single.eventCount, 2);
      expect(batches.single.events.map((event) => event.path), <String>[
        'src/a.styio',
        'src/b.styio',
      ]);
      expect(batches.single.toJson()['eventCount'], 2);
    },
  );

  test(
    'workspace file explorer watcher binding consumes file system manager events',
    () async {
      final events = StreamController<FileSystemManagerEvent>();
      final fileSystemManager = _FakeWorkspaceFileExplorerFileSystemManager(
        events.stream,
      );
      final binding = WorkspaceFileExplorerFileSystemWatcherBinding(
        fileSystemManager: fileSystemManager,
        plan: const WorkspaceFileExplorerWatchPlan(
          rootPath: '/workspace/fixture',
        ),
        baseFilePaths: const <String>['README.md'],
        clock: () => DateTime.utc(2026, 5, 20, 13),
      );
      final snapshots = <WorkspaceFileExplorerWatchSnapshot>[];
      final completed = Completer<void>();
      final subscription = binding.watch().listen(
        snapshots.add,
        onDone: completed.complete,
      );
      addTearDown(subscription.cancel);
      addTearDown(events.close);

      await Future<void>.delayed(Duration.zero);
      events.add(
        const FileSystemManagerEvent(
          kind: FileSystemManagerEventKind.created,
          path: '/workspace/fixture/src/new.styio',
          normalizedPath: '/workspace/fixture/src/new.styio',
        ),
      );
      events.add(
        const FileSystemManagerEvent(
          kind: FileSystemManagerEventKind.deleted,
          path: '/workspace/fixture/README.md',
          normalizedPath: '/workspace/fixture/README.md',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await events.close();
      await completed.future;

      expect(fileSystemManager.watchedPath, '/workspace/fixture');
      expect(fileSystemManager.watchedRecursive, isTrue);
      expect(snapshots.first.plan.active, isTrue);
      expect(snapshots.last.filePaths, <String>['src/new.styio']);
      expect(snapshots.last.eventCount, 2);
      expect(snapshots.last.events.map((event) => event.source).toSet(), {
        'file-system-manager.watch',
      });
      expect(snapshots.last.toDiscoveryResult().filePaths, <String>[
        'src/new.styio',
      ]);
    },
  );

  test('workspace file explorer builds confirmation plans for actions', () {
    const deleteRequest = WorkspaceFileExplorerActionRequest(
      kind: WorkspaceFileOperationKind.delete,
      path: 'src/old.styio',
    );
    const revealRequest = WorkspaceFileExplorerActionRequest(
      kind: WorkspaceFileOperationKind.reveal,
      path: 'src/main.styio',
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['README.md']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: InMemoryWorkspaceDocumentStore(),
      ),
    );
    addTearDown(controller.dispose);

    final deletePlan = controller.confirmationPlanFor(deleteRequest);
    final revealPlan = controller.confirmationPlanFor(revealRequest);

    expect(deletePlan.title, 'Delete workspace file');
    expect(deletePlan.destructive, isTrue);
    expect(deletePlan.risk, WorkspaceFileExplorerActionRisk.destructive);
    expect(deletePlan.requiresConfirmation, isTrue);
    expect(deletePlan.toJson()['canRunWithoutDialog'], isFalse);
    expect(revealPlan.requiresConfirmation, isFalse);
    expect(revealPlan.canRunWithoutDialog, isTrue);
    expect(revealPlan.toJson()['request'], isA<Map<String, Object?>>());
  });

  test('workspace file explorer controller runs file operations', () async {
    final store = InMemoryWorkspaceDocumentStore();
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['main.styio']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: store,
      ),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    final created = await controller.run(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.create,
        path: 'src/new.styio',
        text: 'value := 1\n',
        open: true,
      ),
    );
    final renamed = await controller.run(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.rename,
        path: 'src/new.styio',
        nextPath: 'src/renamed.styio',
      ),
    );
    final revealed = await controller.run(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.reveal,
        path: 'main.styio',
      ),
    );
    final snapshot = controller.snapshot;

    expect(created.applied, isTrue);
    expect(renamed.applied, isTrue);
    expect(revealed.applied, isTrue);
    expect(controller.lastResult, same(revealed));
    expect(snapshot.fileCount, 2);
    expect(snapshot.activeFilePath, 'main.styio');
    expect(snapshot.toJson()['fileCount'], 2);
    expect(workspaceController.files, <String>[
      'main.styio',
      'src/renamed.styio',
    ]);
    expect(await store.documentExists('src/new.styio'), isFalse);
    expect(await store.documentExists('src/renamed.styio'), isTrue);
    expect(notifications, greaterThanOrEqualTo(3));
  });

  test('workspace file explorer stages pending dialog actions', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'main := 1\n',
          revision: 1,
        ),
      },
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['main.styio']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: store,
      ),
    );
    addTearDown(controller.dispose);

    final plan = controller.stageAction(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.delete,
        path: 'main.styio',
      ),
    );
    final blocked = await controller.runPendingAction(confirmed: false);
    final applied = await controller.runPendingAction(confirmed: true);

    expect(plan.requiresConfirmation, isTrue);
    expect(controller.pendingConfirmationPlan, isNull);
    expect(blocked, isNull);
    expect(applied?.applied, isTrue);
    expect(applied?.kind, WorkspaceFileOperationKind.delete);
    expect(await store.documentExists('main.styio'), isFalse);

    controller.stageAction(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.reveal,
        path: 'missing.styio',
      ),
    );
    final reveal = await controller.runPendingAction(confirmed: false);

    expect(reveal?.applied, isFalse);
    expect(reveal?.message, contains('not part of the project'));
  });

  test(
    'workspace file explorer stages batch action confirmation plans',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'main := 1\n',
            revision: 1,
          ),
          'old.styio': DocumentState(
            documentId: 'old.styio',
            text: 'old := 1\n',
            revision: 1,
          ),
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: _projectGraph(
          editorFiles: const <String>['main.styio', 'old.styio'],
        ),
      );
      final controller = WorkspaceFileExplorerController(
        workspaceController: workspaceController,
        operationService: WorkspaceFileOperationService(
          workspaceController: workspaceController,
          documentStore: store,
        ),
      );
      addTearDown(controller.dispose);

      final plan = controller
          .stageBatchActions(const <WorkspaceFileExplorerActionRequest>[
            WorkspaceFileExplorerActionRequest(
              kind: WorkspaceFileOperationKind.rename,
              path: 'old.styio',
              nextPath: 'src/old.styio',
            ),
            WorkspaceFileExplorerActionRequest(
              kind: WorkspaceFileOperationKind.delete,
              path: 'main.styio',
            ),
          ]);
      final skipped = await controller.runPendingBatchAction(confirmed: false);
      final results = await controller.runPendingBatchAction(confirmed: true);

      expect(plan.actionCount, 2);
      expect(plan.requiresConfirmation, isTrue);
      expect(plan.destructiveActionCount, 1);
      expect(plan.summary, contains('2 action'));
      expect(controller.pendingBatchActionPlan, isNull);
      expect(skipped, isEmpty);
      expect(results.map((result) => result.kind), <WorkspaceFileOperationKind>[
        WorkspaceFileOperationKind.rename,
        WorkspaceFileOperationKind.delete,
      ]);
      expect(await store.documentExists('old.styio'), isFalse);
      expect(await store.documentExists('src/old.styio'), isTrue);
      expect(await store.documentExists('main.styio'), isFalse);
    },
  );
}

ProjectGraphSnapshot _projectGraph({required List<String> editorFiles}) {
  return ProjectGraphSnapshot(
    id: 'fixture://project',
    title: 'fixture',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/fixture',
    workspaceMembers: const <String>[],
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: editorFiles,
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'fixture',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.unknown,
    notes: const <String>[],
  );
}

class _FakeWorkspaceFileExplorerFileSystemManager
    extends UnsupportedFileSystemManager {
  _FakeWorkspaceFileExplorerFileSystemManager(this.events)
    : super(facts: FileSystemFacts.linuxDebianArm());

  final Stream<FileSystemManagerEvent> events;
  String watchedPath = '';
  bool watchedRecursive = false;

  @override
  Stream<FileSystemManagerEvent> watch(String path, {bool recursive = false}) {
    watchedPath = path;
    watchedRecursive = recursive;
    return events;
  }
}
