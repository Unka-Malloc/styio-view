import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace file command router maps command input to action plans', () {
    const router = WorkspaceFileCommandRouter();

    final create = router.route(
      commandId: AppCommandId.createWorkspaceFile,
      input: 'src/new.styio',
      context: const WorkspaceFileCommandRouteContext(
        defaultText: 'value := 1',
      ),
    );
    final rename = router.route(
      commandId: AppCommandId.renameWorkspaceFile,
      input: 'src/old.styio -> src/current.styio',
    );
    final reveal = router.route(
      commandId: AppCommandId.openWorkspaceFile,
      context: const WorkspaceFileCommandRouteContext(
        selectedFilePath: 'README.md',
      ),
    );
    final blocked = router.route(commandId: AppCommandId.deleteWorkspaceFile);
    final unsupported = router.route(commandId: AppCommandId.run);

    expect(create.routed, isTrue);
    expect(create.request?.kind, WorkspaceFileOperationKind.create);
    expect(create.request?.path, 'src/new.styio');
    expect(create.request?.text, 'value := 1');
    expect(create.confirmationPlan?.requiresConfirmation, isTrue);
    expect(rename.request?.path, 'src/old.styio');
    expect(rename.request?.nextPath, 'src/current.styio');
    expect(reveal.request?.kind, WorkspaceFileOperationKind.reveal);
    expect(reveal.request?.path, 'README.md');
    expect(reveal.confirmationPlan?.canRunWithoutDialog, isTrue);
    expect(blocked.status, WorkspaceFileCommandRouteStatus.blocked);
    expect(unsupported.status, WorkspaceFileCommandRouteStatus.unsupported);
    expect(create.toJson()['confirmationPlan'], isA<Map<String, Object?>>());
  });

  test(
    'workspace file command palette adapter stages and runs file commands',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'README.md': DocumentState(
            documentId: 'README.md',
            text: '# Demo\n',
            revision: 1,
          ),
          'src/old.styio': DocumentState(
            documentId: 'src/old.styio',
            text: 'old := 1\n',
            revision: 1,
          ),
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: _projectGraph(
          editorFiles: const <String>['README.md', 'src/old.styio'],
        ),
      );
      final explorerController = WorkspaceFileExplorerController(
        workspaceController: workspaceController,
        operationService: WorkspaceFileOperationService(
          workspaceController: workspaceController,
          documentStore: store,
        ),
      );
      addTearDown(explorerController.dispose);
      final adapter = WorkspaceFileCommandPaletteAdapter(
        controller: explorerController,
      );

      final reveal = await adapter.execute(
        commandId: AppCommandId.openWorkspaceFile,
        input: 'README.md',
      );
      final delete = await adapter.execute(
        commandId: AppCommandId.deleteWorkspaceFile,
        input: 'src/old.styio',
      );
      expect(explorerController.pendingConfirmationPlan, isNotNull);
      final deleted = await explorerController.runPendingAction(
        confirmed: true,
      );

      expect(reveal.applied, isTrue);
      expect(reveal.operationResult?.kind, WorkspaceFileOperationKind.reveal);
      expect(workspaceController.activeFilePath, 'README.md');
      expect(delete.staged, isTrue);
      expect(delete.confirmationPlan?.destructive, isTrue);
      expect(deleted?.applied, isTrue);
      expect(await store.documentExists('src/old.styio'), isFalse);
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
