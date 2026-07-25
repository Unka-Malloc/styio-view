import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_quick_fix_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/semantic_telemetry_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_quick_fix_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent quick-fix discovery fails closed when no fix exists', () async {
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'value := 1\n',
      revision: 1,
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{'main.styio': document},
    );
    final editor = EditorSessionController(
      initialDocument: document,
      languageService: const SimpleStyioLanguageService(),
    );
    final state = EditorWorkspaceStateController(documentCacheLimit: 4);
    final quickFix = WorkspaceQuickFixController(
      languageService: const ProjectStyioLanguageService(),
      loadDocuments: () async => const <DocumentState>[document],
      documentSamples: () => const <DocumentState>[document],
      documentStore: store,
      editorController: editor,
      editorWorkspaceState: state,
      cacheDocument: (_, _) {},
      log: (_) {},
    );
    final buffer = RuntimeOutputLiveBuffer();
    final telemetry = SemanticTelemetryController(
      panelStateController: SemanticSnapshotPanelEventStateController(),
      panelEventStore: null,
      panelWorkspaceId: 'workspace',
      quickFixTelemetryStore: null,
      quickFixWorkspaceId: 'workspace',
      runtimeOutputBuffer: buffer,
      activeDocumentPath: () => document.documentId,
      log: (_) {},
    );
    final agent = AgentController();
    final logs = <String>[];
    final controller = AgentQuickFixCommandController(
      editorController: editor,
      workspaceQuickFixController: quickFix,
      editorWorkspaceState: state,
      semanticTelemetry: telemetry,
      agentController: agent,
      activeDocumentPath: () => document.documentId,
      cacheDocument: (_, _) {},
      log: logs.add,
      notify: () {},
    );
    addTearDown(() async {
      agent.dispose();
      telemetry.dispose();
      await buffer.dispose();
      quickFix.dispose();
      editor.dispose();
    });

    final applied = await controller.apply(
      const AgentIdeCommandSuggestion(commandId: 'previewQuickFix'),
    );

    expect(applied, isFalse);
    expect(agent.lastCommandResult?.applied, isFalse);
    expect(agent.lastCommandResult?.message, contains('no quick fix'));
    expect(
      buffer.snapshot.events.single.metadata['action'],
      'agent.previewQuickFix',
    );
  });
}
