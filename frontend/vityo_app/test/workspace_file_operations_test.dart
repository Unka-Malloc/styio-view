import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace file operations create and reveal files', () async {
    final store = InMemoryWorkspaceDocumentStore();
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['main.styio']),
    );
    final service = WorkspaceFileOperationService(
      workspaceController: controller,
      documentStore: store,
    );

    final created = await service.createFile(
      path: 'src/generated.styio',
      text: 'value := 1\n',
      open: true,
    );
    final document = await store.loadDocument('src/generated.styio');
    final revealed = service.revealFile('main.styio');

    expect(created.applied, isTrue);
    expect(created.kind, WorkspaceFileOperationKind.create);
    expect(document.text, 'value := 1\n');
    expect(controller.files, <String>['main.styio', 'src/generated.styio']);
    expect(controller.activeFilePath, 'main.styio');
    expect(revealed.applied, isTrue);
    expect(revealed.toJson()['kind'], 'reveal');
  });

  test('workspace file operations rename active file and preserve contents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'main := 1\n',
          revision: 2,
        ),
      },
    );
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['main.styio']),
    );
    final service = WorkspaceFileOperationService(
      workspaceController: controller,
      documentStore: store,
    );

    final renamed = await service.renameFile(
      path: 'main.styio',
      nextPath: 'src/main.styio',
    );
    final nextDocument = await store.loadDocument('src/main.styio');

    expect(renamed.applied, isTrue);
    expect(renamed.kind, WorkspaceFileOperationKind.rename);
    expect(renamed.nextPath, 'src/main.styio');
    expect(nextDocument.text, 'main := 1\n');
    expect(nextDocument.revision, 3);
    expect(await store.documentExists('main.styio'), isFalse);
    expect(controller.files, <String>['src/main.styio']);
    expect(controller.activeFilePath, 'src/main.styio');
  });

  test('workspace file operations delete inactive files', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'main := 1\n',
          revision: 1,
        ),
        'lib.styio': DocumentState(
          documentId: 'lib.styio',
          text: 'lib := 1\n',
          revision: 1,
        ),
      },
    );
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    )..openFile('lib.styio');
    final service = WorkspaceFileOperationService(
      workspaceController: controller,
      documentStore: store,
    );

    final deleted = await service.deleteFile('main.styio');

    expect(deleted.applied, isTrue);
    expect(await store.documentExists('main.styio'), isFalse);
    expect(controller.files, <String>['lib.styio']);
    expect(controller.activeFilePath, 'lib.styio');
  });

  test('workspace file operations block unsafe or conflicting paths', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'main := 1\n',
          revision: 1,
        ),
      },
    );
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['main.styio']),
    );
    final service = WorkspaceFileOperationService(
      workspaceController: controller,
      documentStore: store,
    );

    final unsafe = await service.createFile(path: '../escape.styio');
    final conflict = await service.renameFile(
      path: 'main.styio',
      nextPath: 'main.styio',
    );
    final missingReveal = service.revealFile('missing.styio');

    expect(unsafe.applied, isFalse);
    expect(unsafe.message, contains('inside the workspace'));
    expect(conflict.applied, isFalse);
    expect(conflict.message, contains('path did not change'));
    expect(missingReveal.applied, isFalse);
    expect(missingReveal.message, contains('not part of the project'));
  });
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
