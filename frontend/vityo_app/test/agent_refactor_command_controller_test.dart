import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_refactor_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';

void main() {
  test('safe delete mutates and dirties the authoritative source buffer', () {
    const text = 'used = 1\nunused = 2\nused -> @stdout\n';
    final fixture = _fixture(text, text.indexOf('unused'));
    addTearDown(fixture.dispose);

    final applied = fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'safeDelete'),
    );

    expect(applied, isTrue);
    expect(fixture.editor.document.text, 'used = 1\nused -> @stdout\n');
    expect(fixture.state.isDirty('sample.styio'), isTrue);
    expect(fixture.cached?.text, fixture.editor.document.text);
  });

  test('unsafe delete fails closed without dirtying the document', () {
    const text = 'used = 1\nused -> @stdout\n';
    final fixture = _fixture(text, text.indexOf('used'));
    addTearDown(fixture.dispose);

    final applied = fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'safeDelete'),
    );

    expect(applied, isFalse);
    expect(fixture.editor.document.text, text);
    expect(fixture.state.isDirty('sample.styio'), isFalse);
    expect(
      fixture.agent.lastCommandResult?.message,
      contains('no safe delete'),
    );
  });

  test('ordinary inline command shares authoritative mutation ownership', () {
    const text = 'value = 1\nvalue -> @stdout\n';
    final fixture = _fixture(text, text.lastIndexOf('value'));
    addTearDown(fixture.dispose);

    final applied = fixture.commands.executeEditorCommand(
      AppCommandId.inlineVariable,
    );

    expect(applied, isTrue);
    expect(fixture.editor.document.text, '1 -> @stdout\n');
    expect(fixture.state.isDirty('sample.styio'), isTrue);
    expect(fixture.agent.lastCommandResult, isNull);
  });
}

_Fixture _fixture(String text, int offset) {
  final editor = EditorSessionController(
    initialDocument: DocumentState(
      documentId: 'sample.styio',
      text: text,
      revision: 0,
    ),
    languageService: const SimpleStyioLanguageService(),
    initialSelection: SelectionState.collapsed(offset),
  );
  final state = EditorWorkspaceStateController(documentCacheLimit: 4);
  final agent = AgentController();
  late final _Fixture fixture;
  fixture = _Fixture(editor: editor, state: state, agent: agent);
  fixture.commands = AgentRefactorCommandController(
    editorController: editor,
    editorWorkspaceState: state,
    agentController: agent,
    activeDocumentPath: () => 'sample.styio',
    cacheDocument: (_, document) => fixture.cached = document,
    log: (_) {},
    notify: () {},
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.editor, required this.state, required this.agent});

  final EditorSessionController editor;
  final EditorWorkspaceStateController state;
  final AgentController agent;
  late AgentRefactorCommandController commands;
  DocumentState? cached;

  void dispose() {
    editor.dispose();
    agent.dispose();
  }
}
