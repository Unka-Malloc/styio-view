import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_workspace_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_file_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_search_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent workspace file command reports its input contract', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'createWorkspaceFile'),
    );

    expect(applied, isFalse);
    final result = fixture.agent.lastCommandResult!;
    expect(result.message, contains('input is required'));
    expect(result.metadata['reason'], 'missing-input');
    expect(result.metadata['inputContract'], isNotEmpty);
  });

  test(
    'agent workspace create routes through authoritative file service',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      final applied = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(
          commandId: 'createWorkspaceFile',
          input: 'src/new.styio',
        ),
      );

      expect(applied, isTrue);
      expect(await fixture.store.documentExists('src/new.styio'), isTrue);
      expect((await fixture.store.loadDocument('src/new.styio')).text, isEmpty);
      expect(fixture.agent.lastCommandResult?.metadata['applied'], isTrue);
      expect(fixture.notifications, 1);
    },
  );

  test('agent rename routes validated input to project rename', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(
        commandId: 'renameSymbol',
        input: '  renamedValue  ',
      ),
    );

    expect(applied, isTrue);
    expect(fixture.renamedTo, 'renamedValue');
    expect(fixture.agent.lastCommandResult?.applied, isTrue);
  });

  test(
    'agent definition navigation uses project fallback and then fails closed',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);
      fixture.projectDefinitionAvailable = true;

      final definition = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'goToDefinition'),
      );
      fixture.projectDefinitionAvailable = false;
      final unavailable = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'goToDefinition'),
      );

      expect(definition, isTrue);
      expect(unavailable, isFalse);
      expect(
        fixture.agent.lastCommandResult?.message,
        contains('no resolved definition'),
      );
    },
  );
}

_Fixture _fixture() {
  const document = DocumentState(
    documentId: 'src/main.styio',
    text: 'value := 0\n',
    revision: 1,
  );
  final workspace = WorkspaceController(
    projectSnapshot: ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/fixture',
      activeFilePath: document.documentId,
      title: 'fixture',
      notes: const <String>[],
    ),
  );
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: const <String, DocumentState>{'src/main.styio': document},
  );
  final agent = AgentController();
  final editor = EditorSessionController(
    initialDocument: document,
    languageService: const SimpleStyioLanguageService(),
  );
  var notifications = 0;
  final fileCommands = WorkspaceFileCommandController(
    workspaceController: workspace,
    documentStore: store,
    openWorkspaceFile: (_) async => true,
    reloadActiveDocument: () async {},
  );
  final search = WorkspaceSearchController(
    workspaceController: workspace,
    documentStore: store,
    languageService: const ProjectStyioLanguageService(),
    documentSamples: () => const <DocumentState>[document],
    publishResults: (_, _) {},
    log: (_) {},
  );
  late final _Fixture fixture;
  fixture = _Fixture(
    workspace: workspace,
    store: store,
    agent: agent,
    editor: editor,
    commands: AgentWorkspaceCommandController(
      agentController: agent,
      fileCommands: fileCommands,
      searchController: search,
      openWorkspaceFile: (_) async => true,
      renameSymbol: (newName) async {
        fixture.renamedTo = newName;
        return true;
      },
      editorController: editor,
      goToProjectDefinition: () async => fixture.projectDefinitionAvailable,
      selectProjectReference: ({required forward}) async {
        fixture.lastReferenceDirection = forward;
        return fixture.projectReferenceAvailable;
      },
      log: (_) {},
      notify: () {
        notifications += 1;
        fixture.notifications = notifications;
      },
    ),
  );
  return fixture;
}

final class _Fixture {
  _Fixture({
    required this.workspace,
    required this.store,
    required this.agent,
    required this.editor,
    required this.commands,
  });

  final WorkspaceController workspace;
  final InMemoryWorkspaceDocumentStore store;
  final AgentController agent;
  final EditorSessionController editor;
  final AgentWorkspaceCommandController commands;
  int notifications = 0;
  String? renamedTo;
  bool projectDefinitionAvailable = false;
  bool projectReferenceAvailable = false;
  bool? lastReferenceDirection;

  void dispose() {
    agent.dispose();
    editor.dispose();
    workspace.dispose();
  }
}
