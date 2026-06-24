import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace file explorer state toggles and round trips', () {
    final state = const WorkspaceFileExplorerState(workspaceId: 'demo')
        .toggleExpanded('src')
        .toggleExpanded('test')
        .selectPath('src/main.styio')
        .withSortMode(WorkspaceFileExplorerSortMode.alphabetical);
    final restored = WorkspaceFileExplorerState.fromJson(state.toJson());

    expect(restored.expandedPaths, <String>['src', 'test']);
    expect(restored.selectedPath, 'src/main.styio');
    expect(restored.sortMode, WorkspaceFileExplorerSortMode.alphabetical);
    expect(restored.toggleExpanded('src').expandedPaths, <String>['test']);
  });

  test(
    'workspace file explorer state persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_workspace_file_explorer_state_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final store = WorkspaceFileExplorerStateStore.fromDataStore(
        dataStore: dataStore,
      );

      await store.saveState(
        const WorkspaceFileExplorerState(
          workspaceId: 'demo',
          expandedPaths: <String>['src'],
          selectedPath: 'src/main.styio',
        ),
      );
      final restored = await store.readState(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.expandedPaths, <String>['src']);
      expect(restored.selectedPath, 'src/main.styio');
      expect(await store.deleteState(workspaceId: 'demo'), isTrue);
      expect(
        (await store.readState(workspaceId: 'demo')).expandedPaths,
        isEmpty,
      );
    },
  );

  test(
    'workspace file explorer controller restores and updates state',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_workspace_file_explorer_controller_state_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final stateStore = WorkspaceFileExplorerStateStore.fromDataStore(
        dataStore: dataStore,
      );
      await stateStore.saveState(
        const WorkspaceFileExplorerState(
          workspaceId: 'demo',
          expandedPaths: <String>['src'],
        ),
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: _projectGraph(
          editorFiles: const <String>['main.styio', 'src/lib.styio'],
        ),
      );
      final documentStore = InMemoryWorkspaceDocumentStore();
      await documentStore.saveDocument(
        const DocumentState(
          documentId: 'main.styio',
          text: 'main := 1\n',
          revision: 1,
        ),
      );
      final controller = WorkspaceFileExplorerController(
        workspaceController: workspaceController,
        operationService: WorkspaceFileOperationService(
          workspaceController: workspaceController,
          documentStore: documentStore,
        ),
        stateStore: stateStore,
        stateWorkspaceId: 'demo',
      );
      addTearDown(controller.dispose);

      await controller.restoreState();
      await controller.run(
        const WorkspaceFileExplorerActionRequest(
          kind: WorkspaceFileOperationKind.reveal,
          path: 'main.styio',
        ),
      );
      final persisted = await stateStore.readState(workspaceId: 'demo');

      expect(controller.state.expandedPaths, <String>['src']);
      expect(
        controller.snapshot.toJson()['state'],
        isA<Map<String, Object?>>(),
      );
      expect(persisted.revealedPath, 'main.styio');
      expect(persisted.selectedPath, 'main.styio');
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
