import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_replace_controller.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';

void main() {
  test(
    'reviewed preview applies and synchronizes the active document',
    () async {
      const active = DocumentState(
        documentId: 'src/main.styio',
        text: 'needle main\n',
        revision: 1,
      );
      const inactive = DocumentState(
        documentId: 'src/helper.styio',
        text: 'needle helper\n',
        revision: 1,
      );
      final fixture = _fixture(<DocumentState>[active, inactive]);
      addTearDown(fixture.dispose);

      final preview = await fixture.controller.preview(
        query: 'needle',
        replacement: 'thread',
      );
      final result = await fixture.controller.apply(preview!);

      expect(result?.replacementCount, 2);
      expect(result?.failures, isEmpty);
      expect(fixture.controller.lastPreview, isNull);
      expect(fixture.editor.document.text, 'thread main\n');
      expect(
        (await fixture.store.loadDocument(inactive.documentId)).text,
        'thread helper\n',
      );
      expect(fixture.state.dirtyDocumentPaths.toSet(), <String>{
        active.documentId,
        inactive.documentId,
      });
    },
  );

  test(
    'stale preview fails closed without replacing active editor text',
    () async {
      const active = DocumentState(
        documentId: 'src/main.styio',
        text: 'needle main\n',
        revision: 1,
      );
      final fixture = _fixture(<DocumentState>[active]);
      addTearDown(fixture.dispose);
      final preview = await fixture.controller.preview(
        query: 'needle',
        replacement: 'thread',
      );
      await fixture.store.saveDocument(
        const DocumentState(
          documentId: 'src/main.styio',
          text: 'newer disk content\n',
          revision: 2,
        ),
      );

      final result = await fixture.controller.apply(preview!);

      expect(result?.documents, isEmpty);
      expect(result?.failures, hasLength(1));
      expect(result?.failures.single.message, contains('changed since'));
      expect(fixture.editor.document, active);
      expect(fixture.state.dirtyDocumentPaths, isEmpty);
      expect(fixture.controller.lastPreview, same(preview));
    },
  );

  test('daemon search preview commits every document atomically', () async {
    const active = DocumentState(
      documentId: 'src/main.styio',
      text: 'needle main\n',
      revision: 4,
    );
    const helper = DocumentState(
      documentId: 'src/helper.styio',
      text: 'helper needle\n',
      revision: 7,
    );
    final workspace = WorkspaceController(
      projectSnapshot: _projectGraph(<String>[
        active.documentId,
        helper.documentId,
      ]),
    );
    final store = _AtomicStore(<String, DocumentState>{
      active.documentId: active,
      helper.documentId: helper,
    });
    final editor = EditorSessionController(
      initialDocument: active,
      languageService: const SimpleStyioLanguageService(),
    );
    final state = EditorWorkspaceStateController(documentCacheLimit: 8);
    final controller = WorkspaceReplaceController(
      workspaceController: workspace,
      documentStore: store,
      editorController: editor,
      editorWorkspaceState: state,
      textSearchProvider: const _SearchProvider(),
      log: (_) {},
    );
    addTearDown(() {
      controller.dispose();
      editor.dispose();
      workspace.dispose();
    });

    final preview = await controller.preview(
      query: 'needle',
      replacement: 'thread',
    );
    final result = await controller.apply(preview!);

    expect(preview.replacementCount, 2);
    expect(result?.failures, isEmpty);
    expect(store.atomicCommitCount, 1);
    expect((await store.loadDocument(active.documentId)).text, 'thread main\n');
    expect(
      (await store.loadDocument(helper.documentId)).text,
      'helper thread\n',
    );
  });
}

final class _SearchProvider implements WorkspaceTextSearchProvider {
  const _SearchProvider();

  @override
  Future<WorkspaceSearchResult> search({
    required String workspaceId,
    required String query,
    int maxMatches = 1000,
  }) async {
    return const WorkspaceSearchResult(
      matches: <WorkspaceSearchMatch>[
        WorkspaceSearchMatch(
          documentId: 'src/main.styio',
          range: SourceRange(start: 0, end: 6),
          text: 'needle',
          lineNumber: 1,
          lineText: 'needle main',
        ),
        WorkspaceSearchMatch(
          documentId: 'src/helper.styio',
          range: SourceRange(start: 7, end: 13),
          text: 'needle',
          lineNumber: 1,
          lineText: 'helper needle',
        ),
      ],
    );
  }
}

final class _AtomicStore implements AtomicWorkspaceDocumentStore {
  _AtomicStore(Map<String, DocumentState> documents)
    : _documents = Map<String, DocumentState>.from(documents);

  final Map<String, DocumentState> _documents;
  int atomicCommitCount = 0;

  @override
  Future<Map<String, int>> saveDocumentsAtomically(
    Iterable<DocumentState> documents,
  ) async {
    atomicCommitCount += 1;
    final revisions = <String, int>{};
    for (final document in documents) {
      _documents[document.documentId] = document;
      revisions[document.documentId] = document.revision;
    }
    return revisions;
  }

  @override
  Future<DocumentState> loadDocument(String path) async => _documents[path]!;

  @override
  Future<void> saveDocument(DocumentState document) async {
    _documents[document.documentId] = document;
  }

  @override
  Future<bool> deleteDocument(String path) async =>
      _documents.remove(path) != null;

  @override
  Future<bool> documentExists(String path) async =>
      _documents.containsKey(path);

  @override
  String? filePathForDocumentId(String documentId) => null;
}

_ReplaceFixture _fixture(List<DocumentState> documents) {
  final active = documents.first;
  final workspace = WorkspaceController(
    projectSnapshot: _projectGraph(
      documents.map((document) => document.documentId).toList(),
    ),
  );
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: <String, DocumentState>{
      for (final document in documents) document.documentId: document,
    },
  );
  final editor = EditorSessionController(
    initialDocument: active,
    languageService: const SimpleStyioLanguageService(),
  );
  final state = EditorWorkspaceStateController(documentCacheLimit: 8);
  return _ReplaceFixture(
    workspace: workspace,
    store: store,
    editor: editor,
    state: state,
    controller: WorkspaceReplaceController(
      workspaceController: workspace,
      documentStore: store,
      editorController: editor,
      editorWorkspaceState: state,
      log: (_) {},
    ),
  );
}

final class _ReplaceFixture {
  const _ReplaceFixture({
    required this.workspace,
    required this.store,
    required this.editor,
    required this.state,
    required this.controller,
  });

  final WorkspaceController workspace;
  final InMemoryWorkspaceDocumentStore store;
  final EditorSessionController editor;
  final EditorWorkspaceStateController state;
  final WorkspaceReplaceController controller;

  void dispose() {
    controller.dispose();
    editor.dispose();
    workspace.dispose();
  }
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
      source: ToolchainResolutionSource.environment,
      detail: 'fixture',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.unknown,
    notes: const <String>[],
  );
}
