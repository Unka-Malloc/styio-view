import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_workspace_replace_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_replace_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent workspace replace requires preview before apply', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'applyWorkspaceReplace'),
    );

    expect(applied, isFalse);
    expect(fixture.agent.lastCommandResult?.applied, isFalse);
    expect(
      fixture.agent.lastCommandResult?.metadata['requiredCommand'],
      'previewWorkspaceReplace',
    );
    expect(fixture.logs.single, contains('no workspace replace preview'));
  });

  test(
    'agent workspace replace previews then applies reviewed edits',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      final previewed = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(
          commandId: 'previewWorkspaceReplace',
          input: 'needle -> thread',
        ),
      );
      final applied = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'applyWorkspaceReplace'),
      );

      expect(previewed, isTrue);
      expect(applied, isTrue);
      expect(fixture.editor.document.text, 'thread main\n');
      expect(fixture.agent.recentCommandResults, hasLength(2));
      final result = fixture.agent.lastCommandResult!;
      expect(result.commandId, 'applyWorkspaceReplace');
      expect(result.applied, isTrue);
      final metadata =
          result.metadata['workspaceReplaceResult']! as Map<String, Object?>;
      expect(metadata['replacementCount'], 1);
      expect(metadata['failureCount'], 0);
    },
  );
}

_Fixture _fixture() {
  const document = DocumentState(
    documentId: 'src/main.styio',
    text: 'needle main\n',
    revision: 1,
  );
  final workspace = WorkspaceController(
    projectSnapshot: const ProjectGraphSnapshot(
      id: 'fixture://project',
      title: 'fixture',
      kind: ProjectKind.package,
      workspaceRoot: '/workspace/fixture',
      workspaceMembers: <String>[],
      packages: <ProjectPackageSnapshot>[],
      dependencies: <ProjectDependencySnapshot>[],
      targets: <ProjectTargetDescriptor>[],
      editorFiles: <String>['src/main.styio'],
      toolchain: ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.projectPin,
        detail: 'fixture',
      ),
      lockState: ProjectLockState.unknown,
      vendorState: ProjectVendorState.unknown,
      notes: <String>[],
    ),
  );
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: const <String, DocumentState>{'src/main.styio': document},
  );
  final editor = EditorSessionController(
    initialDocument: document,
    languageService: const SimpleStyioLanguageService(),
  );
  final state = EditorWorkspaceStateController(documentCacheLimit: 4);
  final replace = WorkspaceReplaceController(
    workspaceController: workspace,
    documentStore: store,
    editorController: editor,
    editorWorkspaceState: state,
    log: (_) {},
  );
  final agent = AgentController();
  final logs = <String>[];
  return _Fixture(
    workspace: workspace,
    editor: editor,
    state: state,
    replace: replace,
    agent: agent,
    logs: logs,
    commands: AgentWorkspaceReplaceCommandController(
      workspaceReplaceController: replace,
      agentController: agent,
      log: logs.add,
    ),
  );
}

final class _Fixture {
  const _Fixture({
    required this.workspace,
    required this.editor,
    required this.state,
    required this.replace,
    required this.agent,
    required this.logs,
    required this.commands,
  });

  final WorkspaceController workspace;
  final EditorSessionController editor;
  final EditorWorkspaceStateController state;
  final WorkspaceReplaceController replace;
  final AgentController agent;
  final List<String> logs;
  final AgentWorkspaceReplaceCommandController commands;

  void dispose() {
    replace.dispose();
    agent.dispose();
    editor.dispose();
    workspace.dispose();
  }
}
