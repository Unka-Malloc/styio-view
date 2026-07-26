import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:styio_ide/src/view_ide/commands/commands.dart';
import 'package:styio_ide/src/ide/editor/document_state.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/workspace_file_command_controller.dart';
import 'package:styio_ide/src/ide/workspace/workspace.dart';

void main() {
  test('routes immediate create and reveal through owned callbacks', () async {
    const originalPath = 'src/main.styio';
    const createdPath = 'src/new.styio';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        originalPath: DocumentState(
          documentId: originalPath,
          text: 'main := 1\n',
          revision: 1,
        ),
      },
    );
    final workspace = WorkspaceController(
      projectSnapshot: _projectGraph(<String>[originalPath]),
    );
    addTearDown(workspace.dispose);
    var revealedPath = '';
    var reloadCount = 0;
    final controller = WorkspaceFileCommandController(
      workspaceController: workspace,
      documentStore: store,
      openWorkspaceFile: (path) async {
        revealedPath = path;
        workspace.openFile(path);
        return true;
      },
      reloadActiveDocument: () async {
        reloadCount += 1;
      },
    );

    final created = await controller.execute(
      commandId: AppCommandId.createWorkspaceFile,
      input: createdPath,
    );
    final revealed = await controller.execute(
      commandId: AppCommandId.revealWorkspaceFile,
      input: originalPath,
    );

    expect(created.applied, isTrue);
    expect(await store.documentExists(createdPath), isTrue);
    expect(workspace.files, contains(createdPath));
    expect(revealed.applied, isTrue);
    expect(revealedPath, originalPath);
    expect(reloadCount, 1);
  });

  test('destructive delete stays fail-closed until confirmed', () async {
    const path = 'src/main.styio';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        path: DocumentState(documentId: path, text: 'main := 1\n', revision: 1),
      },
    );
    final workspace = WorkspaceController(
      projectSnapshot: _projectGraph(<String>[path]),
    );
    addTearDown(workspace.dispose);
    final controller = WorkspaceFileCommandController(
      workspaceController: workspace,
      documentStore: store,
      openWorkspaceFile: (_) async => false,
      reloadActiveDocument: () async {},
    );

    final staged = await controller.execute(
      commandId: AppCommandId.deleteWorkspaceFile,
      input: path,
    );

    expect(staged.staged, isTrue);
    expect(controller.pendingConfirmation, same(staged));
    expect(await store.documentExists(path), isTrue);

    final cancelled = controller.cancel();
    expect(cancelled?.status, WorkspaceFileCommandRouteStatus.blocked);
    expect(controller.pendingConfirmation, isNull);
    expect(await store.documentExists(path), isTrue);

    await controller.execute(
      commandId: AppCommandId.deleteWorkspaceFile,
      input: path,
    );
    final confirmed = await controller.confirm();
    expect(confirmed?.applied, isTrue);
    expect(controller.pendingConfirmation, isNull);
    expect(await store.documentExists(path), isFalse);
    expect(workspace.files, isNot(contains(path)));
  });
}

ProjectGraphSnapshot _projectGraph(List<String> editorFiles) {
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
