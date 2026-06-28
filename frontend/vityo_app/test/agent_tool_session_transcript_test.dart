import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('tool session transcript projects completed tool results', () async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: '{"path":"main.styio"}',
      ),
    );
    controller.approveToolCallExecution('call-read');

    await controller.dispatchReadyToolCalls((request) {
      return AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output:
            '{"source":"test-tool","document":{"path":"main.styio","text":"value = 1"}}',
        metadata: const <String, Object?>{'source': 'test-tool'},
      );
    });

    final transcript = controller.toolSessionTranscript;

    expect(transcript.status, AgentToolCallTimelineStatus.complete);
    expect(transcript.hasTerminalParts, isTrue);
    expect(transcript.parts, hasLength(1));
    expect(transcript.parts.single.callId, 'call-read');
    expect(transcript.parts.single.toolId, 'readWorkspaceFile');
    expect(
      transcript.parts.single.status,
      AgentToolSessionPartStatus.completed,
    );
    expect(transcript.parts.single.inputText, '{"path":"main.styio"}');
    expect(
      transcript.parts.single.output,
      '{"source":"test-tool","document":{"path":"main.styio","text":"value = 1"}}',
    );
    expect(
      transcript.parts.single.metadata['toolResult'],
      isA<Map<String, Object?>>(),
    );
    expect(transcript.toJson()['status'], 'complete');
  });

  test('tool session transcript preserves orphan result contexts', () {
    final transcript = AgentToolSessionTranscript.fromToolState(
      timeline: AgentToolCallTimeline.empty(),
      executionPlan: const AgentToolCallExecutionPlan(
        status: AgentToolCallExecutionPlanStatus.idle,
        executions: <AgentToolCallExecution>[],
      ),
      resultContexts: <AgentToolCallResultContext>[
        AgentToolCallResultContext(
          callId: 'call-orphan',
          toolId: 'collectExtensionContext',
          status: AgentToolCallResultContextStatus.failure,
          message: 'extension host unavailable',
          output: '',
          createdAt: DateTime.utc(2026),
        ),
      ],
    );

    expect(transcript.status, AgentToolCallTimelineStatus.failed);
    expect(transcript.parts, hasLength(1));
    expect(transcript.parts.single.callId, 'call-orphan');
    expect(transcript.parts.single.status, AgentToolSessionPartStatus.failed);
    expect(transcript.parts.single.message, 'extension host unavailable');
  });
}

AgentSessionContext _context() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}
