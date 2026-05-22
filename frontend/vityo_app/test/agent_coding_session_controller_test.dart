import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_code_patch_applier.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_history_store.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/view_ide/agent/agent_registry.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/agent/agent_tool_call_dispatcher.dart';
import 'package:vityo_app/src/agent/agent_tool_call_execution_plan.dart';
import 'package:vityo_app/src/agent/agent_tool_registry.dart';
import 'package:vityo_app/src/agent/agent_tool_permission_policy_store.dart';
import 'package:vityo_app/src/agent/agent_workspace_snapshot.dart';
import 'package:vityo_app/src/agent/agent_workspace_snapshot_store.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_tool_session_transcript.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent coding session sends prompt with current IDE context', () async {
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.text,
            text: 'Context received.',
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );

    controller.updatePrompt('Explain this file.');
    final response = await controller.sendPrompt();

    expect(response, isNotNull);
    expect(adapter.requests.single.userPrompt, 'Explain this file.');
    expect(adapter.requests.single.context.document.documentId, 'main.styio');
    expect(
      adapter.requests.single.context.agent.toolPermissionPlan?.reviewToolIds,
      contains('previewWorkspaceEdit'),
    );
    expect(
      adapter.requests.single.context.agent.toolCatalog?.toolIds,
      contains('readWorkspaceFile'),
    );
    expect(
      adapter.requests.single.context.agent.agentRegistry.activeAgentId,
      defaultAgentRuntimeAgentId,
    );
    expect(controller.draftPrompt, '');
    expect(
      controller.lastResponse?.contentParts.single.text,
      'Context received.',
    );
    expect(controller.conversationTurns.map((turn) => turn.role), [
      AgentConversationRole.user,
      AgentConversationRole.assistant,
    ]);
    expect(controller.lastError, isNull);
  });

  test('agent coding session selects active agent runtime', () async {
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-runtime',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(kind: AgentContentPartKind.text, text: 'Selected.'),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    expect(controller.activeAgentId, defaultAgentRuntimeAgentId);
    expect(controller.selectAgentRuntime('vityo-review-agent'), isTrue);
    expect(controller.activeAgentId, 'vityo-review-agent');
    expect(controller.selectAgentRuntime('vityo-recovery-agent'), isFalse);

    controller.updatePrompt('Review this file.');
    await controller.sendPrompt();

    expect(
      adapter.requests.single.context.agent.agentRegistry.activeAgentId,
      'vityo-review-agent',
    );
    expect(
      adapter.requests.single.context.agent.agentRegistry.activeAgent?.mode,
      AgentRuntimeMode.subagent,
    );
  });

  test('agent coding session applies active agent permission rules', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      adapter: _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-review-permission',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[],
        ),
      ),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    expect(controller.selectAgentRuntime('vityo-review-agent'), isTrue);

    final permission = controller.toolPermissionPlan.decisions.firstWhere(
      (decision) => decision.toolId == 'applyWorkspacePatch',
    );
    expect(permission.status, AgentToolPermissionDecisionStatus.denied);
    expect(permission.ruleId, 'review-agent-deny-patch-apply');

    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-apply-patch-review-agent',
        toolId: 'applyWorkspacePatch',
        input: '{"patch":{}}',
      ),
    );

    final execution = controller.toolCallExecutionPlan.executionFor(
      'call-apply-patch-review-agent',
    )!;
    final journalEntry = controller.toolCallExecutionJournal.entries.single;
    expect(execution.status, AgentToolCallExecutionStatus.blocked);
    expect(
      execution.issueCodes,
      contains('agent.tool.permission.denied.applyWorkspacePatch'),
    );
    expect(journalEntry.executionStatus, 'blocked');
    expect(journalEntry.permissionStatus, 'denied');
    expect(
      journalEntry.executionIssueCodes,
      contains('agent.tool.permission.denied.applyWorkspacePatch'),
    );
  });

  test('agent coding session blocks active agent after max steps', () async {
    final adapter = _FakeAgentProviderAdapter(
      kind: AgentProviderKind.cloudOpenAICompatible,
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-step-limit',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(kind: AgentContentPartKind.text, text: 'Step done.'),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      adapter: adapter,
      contextProvider: _context,
      agentRegistry: AgentRegistry(
        defaultAgentId: 'single-step-agent',
        agents: const <AgentRuntimeDefinition>[
          AgentRuntimeDefinition(
            agentId: 'single-step-agent',
            displayName: 'Single Step Agent',
            mode: AgentRuntimeMode.primary,
            maxSteps: 1,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Run the first step.');
    final first = await controller.sendPrompt();

    expect(first, isNotNull);
    expect(controller.codingLoopGuard.blocked, isTrue);
    expect(
      controller.codingLoopGuard.blockingReasons,
      contains('agent.loop.maxSteps:single-step-agent:1/1'),
    );

    controller.updatePrompt('Run another step.');
    expect(controller.canSend, isFalse);
    final second = await controller.sendPrompt();

    expect(second, isNull);
    expect(adapter.requests, hasLength(1));
    expect(controller.lastError, contains('agent.loop.guard.blocked'));
  });

  test(
    'agent runtime permission rules take precedence over session approvals',
    () {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: _FakeAgentProviderAdapter(
          kind: AgentProviderKind.cloudOpenAICompatible,
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-review-permission-approval',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[],
          ),
        ),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      controller.selectAgentRuntime('vityo-review-agent');
      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-apply-patch-review-agent-approval',
          toolId: 'applyWorkspacePatch',
          input: '{"patch":{}}',
        ),
      );

      expect(
        controller.approveToolCallExecution(
          'call-apply-patch-review-agent-approval',
          rememberForSession: true,
          reason: 'Allow patch application for this session.',
        ),
        isTrue,
      );

      final permission = controller.toolPermissionPlan.decisions.firstWhere(
        (decision) => decision.toolId == 'applyWorkspacePatch',
      );
      final execution = controller.toolCallExecutionPlan.executionFor(
        'call-apply-patch-review-agent-approval',
      )!;

      expect(permission.status, AgentToolPermissionDecisionStatus.denied);
      expect(permission.ruleId, 'review-agent-deny-patch-apply');
      expect(execution.status, AgentToolCallExecutionStatus.blocked);
    },
  );

  test('agent coding session exposes coding execution readiness gate', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );

    final emptyReadiness = controller.codingExecutionReadiness;
    expect(emptyReadiness.hasIssue('agent.prompt.empty'), isTrue);
    expect(emptyReadiness.canDispatchProviderRequest, isFalse);

    controller.updatePrompt('Refactor this Styio file.');
    final readyToSend = controller.codingExecutionReadiness;
    expect(readyToSend.hasIssue('agent.prompt.empty'), isFalse);
    expect(readyToSend.canDispatchProviderRequest, isTrue);
    expect(readyToSend.readyForAutonomousWorkspaceEdits, isFalse);
    expect(
      readyToSend.todoItems,
      contains(
        'Attach provider execution resolution so Agent Surface can report endpoint health before autonomous provider requests.',
      ),
    );
    expect(readyToSend.todoItems.join('\n'), isNot(contains('TODO:')));
    expect(readyToSend.toJson()['status'], 'needsAttention');
  });

  test('agent coding session exposes tool call execution plan', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );

    controller.recordToolCallEvents(const <AgentToolCallEvent>[
      AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: '{"path":"main.styio"}',
      ),
      AgentToolCallEvent.result(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        result: 'value = 1',
      ),
    ]);
    final timeline = controller.toolCallTimeline;
    final executionPlan = controller.toolCallExecutionPlan;

    expect(timeline.status, AgentToolCallTimelineStatus.complete);
    expect(timeline.callIds, <String>['call-read']);
    expect(executionPlan.status, AgentToolCallExecutionPlanStatus.complete);
    expect(
      executionPlan.executionFor('call-read')!.status,
      AgentToolCallExecutionStatus.completed,
    );
    expect(executionPlan.blockingIssueCodes, isEmpty);
  });

  test(
    'agent coding session remembers tool permission approval for session',
    () {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: _FakeAgentProviderAdapter(
          kind: AgentProviderKind.cloudOpenAICompatible,
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-permission',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[],
          ),
        ),
        contextProvider: _context,
      );

      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-preview-1',
          toolId: 'previewWorkspaceEdit',
          input: '{}',
        ),
      );
      expect(
        controller.toolCallExecutionPlan.executionFor('call-preview-1')?.status,
        AgentToolCallExecutionStatus.reviewRequired,
      );

      final approved = controller.approveToolCallExecution(
        'call-preview-1',
        rememberForSession: true,
        reason: 'Allow preview edits for this session.',
      );
      controller.clearToolCallTimeline();
      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-preview-2',
          toolId: 'previewWorkspaceEdit',
          input: '{}',
        ),
      );

      final permission = controller.toolPermissionPlan.decisions.firstWhere(
        (decision) => decision.toolId == 'previewWorkspaceEdit',
      );
      expect(approved, isTrue);
      expect(permission.status, AgentToolPermissionDecisionStatus.allowed);
      expect(permission.ruleId, 'session-tool-permission-previewWorkspaceEdit');
      expect(
        controller.toolCallExecutionPlan.executionFor('call-preview-2')?.status,
        AgentToolCallExecutionStatus.ready,
      );
      expect(
        controller.sessionToolPermissionRules.single.action,
        AgentToolPermissionAction.allow,
      );
    },
  );

  test('agent coding session remembers tool permission denial for session', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      adapter: _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-permission',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[],
        ),
      ),
      contextProvider: _context,
    );

    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-command-1',
        toolId: 'runIdeCommand',
        input: '{"commandId":"saveAll"}',
      ),
    );
    final denied = controller.denyToolCallExecution(
      'call-command-1',
      rememberForSession: true,
      reason: 'Do not run IDE commands in this session.',
    );
    controller.clearToolCallTimeline();
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-command-2',
        toolId: 'runIdeCommand',
        input: '{"commandId":"saveAll"}',
      ),
    );

    final execution = controller.toolCallExecutionPlan.executionFor(
      'call-command-2',
    )!;
    expect(denied, isTrue);
    expect(
      controller.previewDispatchPlan().toolPermissionPlan.blocksDispatch,
      isTrue,
    );
    expect(execution.status, AgentToolCallExecutionStatus.blocked);
    expect(
      execution.issueCodes,
      contains('agent.tool.permission.denied.runIdeCommand'),
    );

    expect(controller.clearSessionToolPermissionRule('runIdeCommand'), isTrue);
    expect(
      controller.toolCallExecutionPlan.executionFor('call-command-2')?.status,
      AgentToolCallExecutionStatus.reviewRequired,
    );
  });

  test(
    'agent coding session persists project tool permission policy',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_tool_permission_policy_controller_test_',
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
      final policyStore = AgentToolPermissionPolicyStore.fromDataStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
      );
      final first = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
        sessionHistoryWorkspaceId: 'demo',
        toolPermissionPolicyStore: policyStore,
      );
      addTearDown(first.dispose);
      first.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-project-deny-1',
          toolId: 'runIdeCommand',
          input: '{"commandId":"runTests"}',
        ),
      );

      final persisted = await first.denyToolCallExecutionForProject(
        'call-project-deny-1',
        reason: 'Project policy blocks IDE command tools.',
      );

      final second = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
        sessionHistoryWorkspaceId: 'demo',
        toolPermissionPolicyStore: policyStore,
      );
      addTearDown(second.dispose);
      await second.loadToolPermissionPolicy();
      second.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-project-deny-2',
          toolId: 'runIdeCommand',
          input: '{"commandId":"runTests"}',
        ),
      );

      final execution = second.toolCallExecutionPlan.executionFor(
        'call-project-deny-2',
      )!;
      expect(persisted, isTrue);
      expect(
        second.projectToolPermissionRules.single.action,
        AgentToolPermissionAction.deny,
      );
      expect(execution.status, AgentToolCallExecutionStatus.blocked);
      expect(
        execution.issueCodes,
        contains('agent.tool.permission.denied.runIdeCommand'),
      );
    },
  );

  test(
    'agent coding session forwards denied tool feedback to next request',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-denied-tool-feedback',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-command-feedback',
          toolId: 'runIdeCommand',
          input: '{"commandId":"runTests"}',
        ),
      );
      final denied = controller.denyToolCallExecution(
        'call-command-feedback',
        reason: 'Use the validation context before running tests.',
      );
      controller.updatePrompt('Continue after tool review.');
      await controller.sendPrompt();

      final result = adapter.requests.single.toolCallResults.single;
      expect(denied, isTrue);
      expect(result.success, isFalse);
      expect(result.callId, 'call-command-feedback');
      expect(result.toolId, 'runIdeCommand');
      expect(result.output, contains('correctiveFeedback'));
      expect(
        result.output,
        contains('Use the validation context before running tests.'),
      );
      expect(result.metadata['source'], 'agent-tool-review');
      expect(result.metadata['reviewDecision'], 'denied');
      expect(result.output, contains('recoveryAction: reviseToolRequest'));
      expect(
        result.metadata['correctiveFeedback'],
        'Use the validation context before running tests.',
      );
      expect(result.metadata['recoveryAction'], 'reviseToolRequest');
    },
  );

  test('agent coding session clears tool call timeline with conversation', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );

    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: '{"path":"main.styio"}',
      ),
    );
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.running,
    );

    controller.clearConversation();

    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.idle,
    );
    expect(
      controller.toolCallExecutionPlan.status,
      AgentToolCallExecutionPlanStatus.idle,
    );
  });

  test('agent coding session records streamed tool call metadata', () async {
    final adapter = _ToolCallStreamingAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );

    controller.updatePrompt('Read the current file.');
    final response = await controller.sendPrompt();

    expect(response, isNotNull);
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(controller.toolCallTimeline.callIds, <String>['call-read']);
    expect(controller.toolCallExecutionJournal.sourceEventCount, 2);
    expect(
      controller.toolCallExecutionPlan.status,
      AgentToolCallExecutionPlanStatus.complete,
    );
  });

  test('agent coding session dispatches streamed provider tool calls', () async {
    final adapter = _StreamingToolCallOnlyAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );

    controller.updatePrompt('Read the current file through streaming tools.');
    final response = await controller.sendPrompt();

    expect(response?.finishReason, 'tool_calls');
    expect(controller.toolCallTimeline.callIds, <String>['call-read']);
    expect(controller.toolCallExecutionJournal.sourceEventCount, 4);
    expect(
      controller.toolCallExecutionPlan.status,
      AgentToolCallExecutionPlanStatus.ready,
    );

    await controller.dispatchReadyToolCalls(
      (request) => AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output:
            '{"source":"agent-session-context","document":{"text":"value := 1"}}',
      ),
    );

    expect(controller.recentToolCallResultContexts.single.callId, 'call-read');
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(controller.toolCallExecutionJournal.sourceEventCount, 5);
  });

  test(
    'agent coding session forwards dispatched tool results to next request',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-tool-result',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'Done.'),
          ],
        ),
      );
      final historyStore = _MemoryAgentCodingSessionHistoryStore(
        AgentCodingSessionHistory(workspaceId: 'demo'),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        sessionHistoryStore: historyStore,
        sessionHistoryWorkspaceId: 'demo',
      );

      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-read',
          toolId: 'readWorkspaceFile',
          input: '{"path":"main.styio"}',
        ),
      );
      controller.approveToolCallExecution('call-read');
      await controller.dispatchReadyToolCalls(
        (request) => AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output:
              '{"source":"agent-session-context","document":{"text":"value = 1"}}',
          metadata: const <String, Object?>{'source': 'test'},
        ),
      );

      expect(
        controller.recentToolCallResultContexts.single.callId,
        'call-read',
      );
      expect(controller.restoreToolResultContinuationDraft(), isTrue);
      expect(
        controller.draftPrompt,
        contains('Continue after 1 agent tool result(s).'),
      );
      expect(await controller.dispatchToolResultContinuation(), isNull);
      expect(
        controller.lastError,
        contains('explicit user confirmation is required'),
      );
      await controller.dispatchToolResultContinuation(confirmed: true);

      final request = adapter.requests.single;
      expect(request.toolCallResults.single.callId, 'call-read');
      expect(request.toolCallResults.single.toolId, 'readWorkspaceFile');
      expect(request.toolCallResults.single.success, isTrue);
      expect(
        request.toolCallResults.single.output,
        '{"source":"agent-session-context","document":{"text":"value = 1"}}',
      );
      expect(
        request.context.agent.toolCallTimeline?.status,
        AgentToolCallTimelineStatus.complete,
      );
      expect(
        request.context.agent.toolCallExecutionJournal?.entries.single.callId,
        'call-read',
      );
      expect(
        request.context.agent.toolReplayPlan?.status,
        AgentToolCallReplayPlanStatus.blocked,
      );
      expect(
        request.toolSessionTranscript?.parts.single.inputText,
        '{"path":"main.styio"}',
      );
      expect(
        request.toolSessionTranscript?.parts.single.status,
        AgentToolSessionPartStatus.completed,
      );
      expect(request.toJson()['toolCallResults'], isA<List<Object?>>());
      expect(
        request.toJson()['toolSessionTranscript'],
        isA<Map<String, Object?>>(),
      );
      final metadata = historyStore.history.records.single.metadata;
      final transcript =
          metadata['toolSessionTranscript'] as Map<String, Object?>;
      expect(metadata['toolResultContinuation'], isTrue);
      expect(metadata['toolResultContinuationCount'], 1);
      expect(metadata['toolResultContinuationFailedCount'], 0);
      expect(metadata['toolResultContinuationCallIds'], <String>['call-read']);
      expect(transcript['status'], 'complete');
      expect(transcript['partCount'], 1);
      expect(controller.recentToolCallResultContexts, isEmpty);
      expect(controller.restoreToolResultContinuationDraft(), isFalse);
      expect(
        await controller.dispatchToolResultContinuation(confirmed: true),
        isNull,
      );
      expect(controller.lastError, contains('no tool results are available'));
    },
  );

  test(
    'agent coding session applies provider-specific tool output budgets',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
        toolRegistry: AgentToolRegistry(
          tools: const <AgentToolDefinition>[
            AgentToolDefinition(
              toolId: 'readWorkspaceFile',
              displayName: 'Read Workspace File',
              description: 'Read a workspace file.',
              permissionMode: AgentToolPermissionMode.never,
              providerOutputLimits: <AgentProviderKind, int>{
                AgentProviderKind.localOnlyFallback: 10,
              },
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);

      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-budgeted-read',
          toolId: 'readWorkspaceFile',
          input: '{"path":"main.styio"}',
        ),
      );
      await controller.dispatchReadyToolCalls(
        (request) => AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: '0123456789abcdef',
        ),
      );

      final result = controller.recentToolCallResultContexts.single;
      expect(result.outputTruncated, isTrue);
      expect(result.outputLimit, 10);
      expect(result.outputOmittedLength, 6);
      expect(
        result.output,
        contains('[tool output truncated: 6 char(s) omitted]'),
      );
    },
  );

  test(
    'agent coding session persists tool execution journal in history metadata',
    () async {
      final historyStore = _MemoryAgentCodingSessionHistoryStore(
        AgentCodingSessionHistory(workspaceId: 'demo'),
      );
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-tool-journal',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'Done.'),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        sessionHistoryStore: historyStore,
        sessionHistoryWorkspaceId: 'demo',
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Create history before tool dispatch.');
      await controller.sendPrompt();
      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-read',
          toolId: 'readWorkspaceFile',
          input: '{"path":"main.styio"}',
        ),
      );
      await controller.dispatchReadyToolCalls(
        (request) => AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output:
              '{"source":"agent-session-context","document":{"text":"value = 1"}}',
        ),
      );

      final history = await historyStore.readHistory(workspaceId: 'demo');
      final metadata = history.records.single.metadata;
      final journal =
          metadata['toolCallExecutionJournal'] as Map<String, Object?>;
      final transcript =
          metadata['toolSessionTranscript'] as Map<String, Object?>;
      final recoveryPayload = history.toRecoveryContext().toJson();

      expect(journal['status'], 'complete');
      expect(journal['entryCount'], 1);
      expect(journal['replayCandidateCount'], 0);
      expect(transcript['status'], 'complete');
      expect(transcript['partCount'], 1);
      expect(recoveryPayload['toolCallExecutionJournal'], journal);
      expect(recoveryPayload['toolSessionTranscript'], transcript);
      final auditSummary =
          recoveryPayload['auditSummary']! as Map<String, Object?>;
      expect(auditSummary['toolJournalStatus'], 'complete');
      expect(auditSummary['toolJournalEntryCount'], 1);
      expect(auditSummary['hasToolExecutionEvidence'], isTrue);
      expect(auditSummary['requiresUserReview'], isFalse);
    },
  );

  test(
    'agent coding session persists tool replay reports in history metadata',
    () async {
      final historyStore = _MemoryAgentCodingSessionHistoryStore(
        AgentCodingSessionHistory(workspaceId: 'demo'),
      );
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-replay-history',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'Ready.'),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        sessionHistoryStore: historyStore,
        sessionHistoryWorkspaceId: 'demo',
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Create history before replay.');
      await controller.sendPrompt();
      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-read',
          toolId: 'readWorkspaceFile',
          input: '{"path":"main.styio"}',
        ),
      );
      await controller.dispatchReadyToolCalls((request) {
        return AgentToolCallDispatchResult.failure(
          callId: request.callId,
          toolId: request.toolId,
          message: 'temporary read failure',
        );
      });
      await controller.replayToolCallJournal((request) {
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output:
              '{"source":"agent-session-context","document":{"text":"value = 1"}}',
        );
      });

      final history = await historyStore.readHistory(workspaceId: 'demo');
      final metadata = history.records.single.metadata;
      final report =
          metadata['lastToolCallReplayReport'] as Map<String, Object?>;

      expect(report['status'], 'replayed');
      expect(metadata['toolCallReplayReportCount'], 1);
      expect(metadata['toolCallReplayReports'], isA<List<Object?>>());
      expect(
        controller
            .sessionHistorySnapshot
            .records
            .single
            .metadata['lastToolCallReplayReport'],
        isA<Map<String, Object?>>(),
      );
    },
  );

  test(
    'agent coding session forwards replay metadata to provider follow-up',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-replay-follow-up',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.text,
              text: 'Followed.',
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
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
      await controller.dispatchReadyToolCalls((request) {
        return AgentToolCallDispatchResult.failure(
          callId: request.callId,
          toolId: request.toolId,
          message: 'temporary read failure',
        );
      });
      await controller.replayToolCallJournal((request) {
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output:
              '{"source":"agent-session-context","document":{"text":"value = 1"}}',
        );
      });
      controller.updatePrompt('Continue after replay.');
      await controller.sendPrompt();

      final replayedResult = adapter.requests.single.toolCallResults.firstWhere(
        (result) => result.metadata['replayedFromJournal'] == true,
      );

      expect(replayedResult.callId, 'call-read');
      expect(replayedResult.metadata['replayToolId'], 'readWorkspaceFile');
      expect(replayedResult.success, isTrue);
    },
  );

  test(
    'agent coding session feeds blocked tool input errors back to provider',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      var executed = false;

      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-read',
          toolId: 'readWorkspaceFile',
          input: '{"path":123}',
        ),
      );
      final report = await controller.dispatchReadyToolCalls((request) {
        executed = true;
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: 'unexpected',
        );
      });

      expect(executed, isFalse);
      expect(report.status, AgentToolCallDispatchReportStatus.failed);
      expect(report.results.single.success, isFalse);
      expect(
        report.results.single.metadata['source'],
        'agent-tool-input-validation',
      );
      expect(report.results.single.output, contains('invalid arguments'));
      expect(
        report.results.single.output,
        contains('Please rewrite the input'),
      );
      expect(controller.recentToolCallResultContexts.single.success, isFalse);
      expect(
        controller.toolCallTimeline.status,
        AgentToolCallTimelineStatus.failed,
      );
    },
  );

  test('agent coding session records provider executable tool calls', () async {
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-provider-tool-call',
        role: 'assistant',
        finishReason: 'tool_calls',
        contentParts: <AgentContentPart>[
          AgentContentPart(kind: AgentContentPartKind.text, text: ''),
        ],
        toolCallEvents: <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{"path":"main.styio"}',
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );

    controller.updatePrompt('Read current file.');
    await controller.sendPrompt();

    expect(controller.toolCallTimeline.callIds, <String>['call-read']);
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.running,
    );
    expect(
      controller.toolCallExecutionPlan.status,
      AgentToolCallExecutionPlanStatus.ready,
    );
  });

  test(
    'agent coding session blocks provider dispatch when route is blocked',
    () async {
      const resolution = AgentProviderExecutionResolution(
        profileId: 'blocked-provider',
        status: AgentProviderExecutionResolutionStatus.blocked,
        endpoints: <AgentProviderEndpointReadiness>[],
      );
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-blocked',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'blocked'),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        providerExecutionResolution: resolution,
        runtimeOutputBuffer: buffer,
      );

      controller.updatePrompt('Try to dispatch.');

      expect(controller.canSend, isFalse);
      expect(
        controller.codingExecutionReadiness.hasIssue(
          'agent.provider.route.blocked',
        ),
        isTrue,
      );

      final response = await controller.sendPrompt();

      expect(response, isNull);
      expect(adapter.requests, isEmpty);
      expect(controller.lastError, contains('Agent request blocked'));
      expect(controller.lastError, contains('agent.provider.route.blocked'));
      final event = buffer.snapshot.events.single;
      expect(event.channelId, 'agent.activity');
      expect(event.metadata['outcome'], 'failed');
      expect(event.message, contains('agent.provider.route.blocked'));
    },
  );

  test(
    'agent coding session publishes runtime output activity event',
    () async {
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-output',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.text,
              text: 'Patch plan ready.',
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        runtimeOutputBuffer: buffer,
      );

      controller.updatePrompt('Plan a fix.');
      await controller.sendPrompt();

      final streamEvents = buffer.snapshot.events
          .where((event) => event.metadata['streamEventKind'] != null)
          .toList(growable: false);
      expect(
        streamEvents.map((event) => event.metadata['streamEventKind']),
        <String>['started', 'contentPart', 'completed'],
      );
      expect(streamEvents.first.metadata['synthetic'], isTrue);
      final event = buffer.snapshot.events.singleWhere(
        (event) => event.metadata['outcome'] == 'succeeded',
      );
      expect(event.channelId, 'agent.activity');
      expect(event.kind, RuntimeOutputChannelKind.agent);
      expect(event.message, 'Patch plan ready.');
      expect(event.metadata['requestId'], 'agent-request-output');
      expect(event.metadata['outcome'], 'succeeded');
      expect(event.metadata['contentPartCount'], 1);
    },
  );

  test('agent coding session consumes streaming provider events', () async {
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    final adapter = _StreamingAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
      runtimeOutputBuffer: buffer,
    );

    controller.updatePrompt('Stream a response.');
    final response = await controller.sendPrompt();

    expect(response?.contentParts.single.text, 'streamed answer');
    expect(adapter.sendCalled, isFalse);
    expect(adapter.streamedRequestIds, <String>['agent-request-1']);
    final streamEvents = buffer.snapshot.events
        .where((event) => event.metadata['streamEventKind'] != null)
        .toList(growable: false);
    expect(
      streamEvents.map((event) => event.metadata['streamEventKind']),
      <String>['started', 'contentDelta', 'completed'],
    );
    expect(buffer.snapshot.events.last.metadata['outcome'], 'succeeded');
  });

  test('agent coding session publishes history restore failures', () async {
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
      sessionHistoryStore: const _ThrowingAgentCodingSessionHistoryStore(
        readMessage: 'history backend unavailable',
      ),
      sessionHistoryWorkspaceId: 'demo',
      runtimeOutputBuffer: buffer,
    );

    await controller.loadSessionHistory();

    final event = buffer.snapshot.events.single;
    expect(controller.sessionHistorySnapshot.workspaceId, 'demo');
    expect(event.channelId, 'agent.activity');
    expect(event.kind, RuntimeOutputChannelKind.agent);
    expect(event.message, contains('Agent history restore failed'));
    expect(event.message, contains('history backend unavailable'));
    expect(event.metadata['operation'], 'agent.history.restore');
    expect(event.metadata['outcome'], 'failed');
  });

  test('agent coding session publishes history persistence failures', () async {
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-persist-failure',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.text,
            text: 'History persistence is non-blocking.',
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
      sessionHistoryStore: const _ThrowingAgentCodingSessionHistoryStore(
        appendMessage: 'disk write denied',
      ),
      sessionHistoryWorkspaceId: 'demo',
      runtimeOutputBuffer: buffer,
    );

    controller.updatePrompt('Persist this request.');
    final response = await controller.sendPrompt();

    expect(response, isNotNull);
    final streamEvents = buffer.snapshot.events
        .where((event) => event.metadata['streamEventKind'] != null)
        .toList(growable: false);
    expect(streamEvents, hasLength(3));
    final event = buffer.snapshot.events.singleWhere(
      (event) => event.metadata['operation'] == 'agent.history.persist',
    );
    expect(event.message, contains('Agent history persistence failed'));
    expect(event.message, contains('disk write denied'));
    expect(event.metadata['operation'], 'agent.history.persist');
    expect(event.metadata['outcome'], 'failed');
  });

  test('agent coding session persists successful prompt history', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_controller_history_test_',
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
    final historyStore = AgentCodingSessionHistoryStore.fromDataStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
    );
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.text,
            text: 'History recorded.',
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
      sessionHistoryStore: historyStore,
      sessionHistoryWorkspaceId: 'demo',
    );

    controller.updatePrompt('Record this request.');
    await controller.sendPrompt();
    final history = await historyStore.readHistory(workspaceId: 'demo');

    expect(history.records.single.requestId, 'agent-request-1');
    expect(
      controller.sessionHistorySnapshot.records.single.requestId,
      'agent-request-1',
    );
    expect(history.records.single.prompt, 'Record this request.');
    expect(history.records.single.succeeded, isTrue);
    expect(
      history.records.single.responseTextSample,
      contains('History recorded'),
    );
    expect(
      controller.sessionCheckpoint.status,
      AgentCodingSessionCheckpointStatus.ready,
    );
    expect(controller.sessionCheckpoint.latestRequestId, 'agent-request-1');
    expect(
      controller.sessionRecoveryPlan.status,
      AgentCodingSessionRecoveryStatus.notNeeded,
    );
  });

  test(
    'controller records validation summary in session history metadata',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-validated',
        summary: 'Validated change.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
        ],
      );
      final historyStore = _MemoryAgentCodingSessionHistoryStore(
        AgentCodingSessionHistory(workspaceId: 'demo'),
      );
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-validation-history',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        sessionHistoryStore: historyStore,
        sessionHistoryWorkspaceId: 'demo',
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Apply validated patch.');
      await controller.sendPrompt();
      final applied = controller.applyPendingPatch(
        AgentCodePatchApplier(editorController: editorController),
      );
      expect(applied?.applied, isTrue);
      for (final commandId in <String>[
        'saveAll',
        'refreshLanguageService',
        'refreshWorkspaceDiagnostics',
        'collectProjectLanguageContext',
      ]) {
        controller.recordIdeCommandResult(
          AgentCommandResultContext(
            commandId: commandId,
            applied: true,
            message: '$commandId completed.',
          ),
        );
      }
      controller.recordIdeCommandResult(
        const AgentCommandResultContext(
          commandId: 'runTests',
          applied: false,
          message: 'runTests failed.',
          metadata: <String, Object?>{
            'testResult': <String, Object?>{
              'status': 'failed',
              'failedCount': 1,
            },
          },
        ),
      );

      await Future<void>.delayed(Duration.zero);
      final immediateMetadata = historyStore.history.records.first.metadata;
      final immediateLastPatchApplication =
          immediateMetadata['lastPatchApplication']! as Map<String, Object?>;
      final immediateValidationSnapshot =
          immediateLastPatchApplication['validationSnapshot']!
              as Map<String, Object?>;

      expect(
        controller
            .lastPatchApplicationContext
            ?.validationSnapshot
            ?.resultStatus,
        'failed',
      );
      expect(immediateValidationSnapshot['resultStatus'], 'failed');
      expect(
        immediateValidationSnapshot['failedCommandIds'],
        contains('runTests'),
      );

      controller.updatePrompt('Continue after validation.');
      await controller.sendPrompt();

      final metadata = historyStore.history.records.first.metadata;
      final validationResult =
          metadata['validationResult']! as Map<String, Object?>;
      final validationPipeline =
          metadata['validationPipeline']! as Map<String, Object?>;
      final validationCommandResults =
          metadata['validationCommandResults']! as List<Object?>;
      final failedCommandResults =
          metadata['validationFailedCommandResults']! as List<Object?>;
      final lastPatchApplication =
          metadata['lastPatchApplication']! as Map<String, Object?>;
      final patchValidationSnapshot =
          lastPatchApplication['validationSnapshot']! as Map<String, Object?>;

      expect(lastPatchApplication['patchId'], 'patch-validated');
      expect(patchValidationSnapshot['resultStatus'], 'failed');
      expect(patchValidationSnapshot['pipelineStatus'], 'failed');
      expect(patchValidationSnapshot['failedCommandIds'], contains('runTests'));
      expect(validationResult['status'], 'failed');
      expect(validationResult['failedCommandIds'], contains('runTests'));
      expect(validationPipeline['status'], 'failed');
      expect(validationPipeline['progressNumerator'], 4);
      expect(validationPipeline['progressDenominator'], 5);
      expect(validationCommandResults, hasLength(5));
      expect(
        validationCommandResults
            .whereType<Map<String, Object?>>()
            .map((result) => result['commandId'])
            .toList(),
        containsAll(<String>[
          'saveAll',
          'refreshLanguageService',
          'refreshWorkspaceDiagnostics',
          'collectProjectLanguageContext',
          'runTests',
        ]),
      );
      final failedRun = failedCommandResults.single! as Map<String, Object?>;
      expect(failedRun['commandId'], 'runTests');
      expect(failedRun['message'], 'runTests failed.');
    },
  );

  test('agent coding session restores recovery request draft', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord.failure(
          requestId: 'agent-failed',
          profile: profile,
          providerKind: AgentProviderKind.cloudOpenAICompatible,
          prompt: 'Retry the failed coding task.',
          errorMessage: 'Provider timed out.',
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
        ),
      ],
      updatedAt: DateTime.utc(2026, 5, 20, 0, 2),
    );
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-retry',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: profile,
      adapter: adapter,
      contextProvider: _context,
      sessionHistoryStore: _MemoryAgentCodingSessionHistoryStore(history),
      sessionHistoryWorkspaceId: 'demo',
    );

    await controller.loadSessionHistory();
    final draft = controller.recoveryRequestDraftFor(
      AgentCodingSessionRecoveryAction.retrySameProvider,
    );

    expect(draft?.prompt, 'Retry the failed coding task.');
    expect(draft?.readyToDispatch, isTrue);
    expect(
      controller.restoreRecoveryDraft(
        AgentCodingSessionRecoveryAction.retrySameProvider,
      ),
      isTrue,
    );
    expect(controller.draftPrompt, 'Retry the failed coding task.');
    final blocked = await controller.dispatchRecoveryRequestDraft(
      AgentCodingSessionRecoveryAction.retrySameProvider,
    );
    expect(blocked.status, AgentCodingSessionRecoveryDispatchStatus.blocked);
    expect(adapter.requests, isEmpty);
    final dispatched = await controller.dispatchRecoveryRequestDraft(
      AgentCodingSessionRecoveryAction.retrySameProvider,
      confirmed: true,
    );
    expect(
      dispatched.status,
      AgentCodingSessionRecoveryDispatchStatus.dispatched,
    );
    expect(dispatched.responseRequestId, 'agent-retry');
    expect(adapter.requests.single.userPrompt, 'Retry the failed coding task.');
    expect(controller.draftPrompt, isEmpty);
  });

  test('agent coding session sends previous turns with next prompt', () async {
    final adapter = _FakeAgentProviderAdapter(
      response: const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(kind: AgentContentPartKind.text, text: 'ok'),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );

    controller.updatePrompt('Explain this file.');
    await controller.sendPrompt();
    controller.updatePrompt('Refactor it.');
    await controller.sendPrompt();

    expect(adapter.requests.first.conversationTurns, isEmpty);
    expect(adapter.requests.last.conversationTurns.length, 2);
    expect(
      adapter.requests.last.conversationTurns.first.text,
      'Explain this file.',
    );
    expect(controller.conversationTurns.length, 4);
    controller.clearConversation();
    expect(controller.conversationTurns, isEmpty);
    expect(controller.lastResponse, isNull);
  });

  test(
    'agent coding session sends recent coding plans with next prompt',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.plan,
              text: 'Plan before patch.',
              plan: AgentCodingPlan(
                summary: 'Update active document safely.',
                steps: <String>['Inspect IDE facts.', 'Prepare patch.'],
                acceptanceCriteria: <String>['Patch preview is shown.'],
                risks: <String>['Dirty inactive files.'],
              ),
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.updatePrompt('Plan this edit.');
      await controller.sendPrompt();
      controller.updatePrompt('Continue from the plan.');
      await controller.sendPrompt();

      expect(adapter.requests.first.context.agent.recentCodingPlans, isEmpty);
      final plan = adapter.requests.last.context.agent.recentCodingPlans.single;
      expect(plan.summary, 'Update active document safely.');
      expect(plan.steps, <String>['Inspect IDE facts.', 'Prepare patch.']);
      expect(plan.acceptanceCriteria, <String>['Patch preview is shown.']);
      expect(plan.risks, <String>['Dirty inactive files.']);
      expect(plan.text, 'Plan before patch.');
    },
  );

  test(
    'agent coding session sends recent diagnostic summaries with next prompt',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.diagnosticSummary,
              text: 'Diagnostics summarized.',
              diagnosticSummary: AgentDiagnosticSummary(
                title: 'Build failed.',
                summary: 'Parser target failed with one error.',
                severity: 'error',
                diagnosticCount: 1,
                affectedDocuments: <String>['src/parser.cc'],
                suggestedCommandIds: <String>['runBuild'],
              ),
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.updatePrompt('Summarize diagnostics.');
      await controller.sendPrompt();
      controller.updatePrompt('Continue from diagnostics.');
      await controller.sendPrompt();

      expect(
        adapter.requests.first.context.agent.recentDiagnosticSummaries,
        isEmpty,
      );
      final summary =
          adapter.requests.last.context.agent.recentDiagnosticSummaries.single;
      expect(summary.title, 'Build failed.');
      expect(summary.summary, 'Parser target failed with one error.');
      expect(summary.severity, 'error');
      expect(summary.diagnosticCount, 1);
      expect(summary.affectedDocuments, <String>['src/parser.cc']);
      expect(summary.suggestedCommandIds, <String>['runBuild']);
      expect(summary.text, 'Diagnostics summarized.');
    },
  );

  test(
    'agent coding session feeds IDE command result into next prompt context',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.ideCommand,
              text: 'Run the registered build command.',
              ideCommand: AgentIdeCommandSuggestion(
                commandId: 'runBuild',
                input: 'target=all',
                reason: 'Validate the native patch.',
              ),
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );
      final completedAt = DateTime.utc(2026, 5, 19, 12, 30);

      controller.updatePrompt('Suggest validation.');
      await controller.sendPrompt();
      controller.recordIdeCommandResult(
        AgentCommandResultContext(
          commandId: 'runBuild',
          input: 'target=all',
          applied: true,
          message: 'Build completed.',
          metadata: const <String, Object?>{
            'agentContextSchemaVersion': 45,
            'workspaceRoot': '/workspace/demo',
            'buildResult': <String, Object?>{'success': true},
            'requiredCommand': 'selectClangCppVersion',
            'recoveryForCommandId': 'runBuild',
            'settingsRoute': 'settings',
            'settingsSection': 'toolchain',
            'toolchainSelectionStatus': 'missing',
            'toolchainId': 'clang-cpp',
            'clangCppSelection': 'clang++ 18.1.0',
            'cppStandard': 'c++20',
            'preferredBuildEngineHandoff': 'ninja',
            'backendRouteSelection': <String, Object?>{
              'routeKind': 'hosted',
              'allowed': false,
              'blockedReason': 'native route disabled',
            },
            'sourceControlContext': <String, Object?>{
              'providerKind': 'git',
              'branchName': 'ai-dev',
              'changeCount': 1,
              'stagedPaths': <String>[],
              'unstagedPaths': <String>['src/main.styio'],
              'conflictedPaths': <String>[],
            },
            'languageServiceStatus': <String, Object?>{
              'severity': 'ready',
              'syntaxValidationReady': true,
              'semanticFactsReady': false,
              'capabilityHealth': 'degraded',
              'missingCapabilityCount': 3,
              'blockedCapabilityCount': 1,
              'cacheLookupCount': 4,
              'cacheLookupHitRate': 0.75,
            },
            'testing': <String, Object?>{
              'hasLastRun': true,
              'hasFailingTests': true,
              'rerunFailed': <String, Object?>{'filter': 'syntax'},
            },
            'largeIgnored': <String, Object?>{'token': 'secret'},
          },
          completedAt: completedAt,
        ),
      );
      controller.updatePrompt('Continue after validation.');
      await controller.sendPrompt();

      final nextContext = adapter.requests.last.context;
      expect(nextContext.agent.pendingIdeCommands, isEmpty);
      expect(nextContext.commands.lastResult?.commandId, 'runBuild');
      expect(nextContext.commands.lastResult?.input, 'target=all');
      expect(nextContext.commands.lastResult?.applied, isTrue);
      expect(nextContext.commands.lastResult?.message, 'Build completed.');
      expect(nextContext.commands.recentResults.single.commandId, 'runBuild');
      expect(
        nextContext.commands.lastResult?.metadata['buildResult'],
        isA<Map<String, Object?>>(),
      );
      expect(
        controller.conversationTurns.map((turn) => turn.text).join('\n'),
        contains('IDE command result:'),
      );
      final commandResultTurn = controller.conversationTurns.firstWhere(
        (turn) => turn.text.contains('IDE command result:'),
      );
      expect(commandResultTurn.text, contains('agentContextSchemaVersion: 45'));
      expect(
        commandResultTurn.text,
        contains('workspaceRoot: /workspace/demo'),
      );
      expect(
        commandResultTurn.text,
        contains('requiredCommand: selectClangCppVersion'),
      );
      expect(
        commandResultTurn.text,
        contains('recoveryForCommandId: runBuild'),
      );
      expect(commandResultTurn.text, contains('settingsRoute: settings'));
      expect(commandResultTurn.text, contains('settingsSection: toolchain'));
      expect(
        commandResultTurn.text,
        contains('toolchainSelectionStatus: missing'),
      );
      expect(commandResultTurn.text, contains('toolchainId: clang-cpp'));
      expect(commandResultTurn.text, contains('clangCppSelection: clang++'));
      expect(commandResultTurn.text, contains('cppStandard: c++20'));
      expect(
        commandResultTurn.text,
        contains('preferredBuildEngineHandoff: ninja'),
      );
      expect(
        commandResultTurn.text,
        contains(
          'backendRouteSelection: routeKind=hosted, allowed=false, '
          'blockedReason=native route disabled',
        ),
      );
      expect(
        commandResultTurn.text,
        contains(
          'sourceControlContext: provider=git, branch=ai-dev, changes=1, '
          'staged=0, unstaged=1, conflicts=0',
        ),
      );
      expect(
        commandResultTurn.text,
        contains(
          'languageServiceStatus: severity=ready, syntaxReady=true, '
          'semanticReady=false, health=degraded, missing=3, blocked=1, '
          'cacheLookups=4, cacheHitRate=0.75',
        ),
      );
      expect(
        commandResultTurn.text,
        contains(
          'testing: hasLastRun=true, hasFailingTests=true, rerunFilter=syntax',
        ),
      );
      expect(commandResultTurn.text, isNot(contains('token: secret')));
    },
  );

  test('agent coding session gates prompt send while IDE command applies', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Continue after command.');
    expect(controller.canSend, isTrue);
    expect(controller.beginIdeCommandApplication(), isTrue);
    expect(controller.applyingIdeCommand, isTrue);
    expect(controller.canSend, isFalse);
    expect(controller.beginIdeCommandApplication(), isFalse);

    controller.endIdeCommandApplication();

    expect(controller.applyingIdeCommand, isFalse);
    expect(controller.canSend, isTrue);
  });

  test(
    'agent coding session clear conversation resets stale error state',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FailingSecondAgentProviderAdapter(),
        contextProvider: _context,
      );

      controller.updatePrompt('First request.');
      await controller.sendPrompt();
      controller.updatePrompt('Second request.');
      await controller.sendPrompt();

      expect(controller.conversationTurns, isNotEmpty);
      expect(controller.lastError, contains('provider unavailable'));

      controller.clearConversation();

      expect(controller.conversationTurns, isEmpty);
      expect(controller.lastError, isNull);
    },
  );

  test(
    'agent coding session sends and clears prompt attachments on success',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'ok'),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.addAttachment(
        const AgentRequestAttachment(
          attachmentId: 'note-1',
          kind: 'text',
          name: 'note.txt',
          content: 'prefer simple edits',
        ),
      );
      controller.updatePrompt('Use attachment.');
      await controller.sendPrompt();

      expect(adapter.requests.single.attachments.single.name, 'note.txt');
      expect(controller.attachments, isEmpty);
    },
  );

  test('agent coding session caps prompt attachments', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _ThrowingAgentProviderAdapter(),
      contextProvider: _context,
      maxAttachments: 2,
    );

    controller.addAttachment(
      const AgentRequestAttachment(
        attachmentId: 'note-1',
        kind: 'text',
        name: 'one.txt',
        content: 'one',
      ),
    );
    controller.addAttachment(
      const AgentRequestAttachment(
        attachmentId: 'note-2',
        kind: 'text',
        name: 'two.txt',
        content: 'two',
      ),
    );
    controller.addAttachment(
      const AgentRequestAttachment(
        attachmentId: 'note-3',
        kind: 'text',
        name: 'three.txt',
        content: 'three',
      ),
    );

    expect(
      controller.attachments.map((attachment) => attachment.attachmentId),
      <String>['note-2', 'note-3'],
    );
  });

  test('agent coding session rejects invalid prompt attachments', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _ThrowingAgentProviderAdapter(),
      contextProvider: _context,
    );

    for (final attachment in const <AgentRequestAttachment>[
      AgentRequestAttachment(
        attachmentId: '',
        kind: 'text',
        name: 'empty-id.txt',
        content: 'content',
      ),
      AgentRequestAttachment(
        attachmentId: 'empty-kind',
        kind: '',
        name: 'empty-kind.txt',
        content: 'content',
      ),
      AgentRequestAttachment(
        attachmentId: 'empty-name',
        kind: 'text',
        name: '',
        content: 'content',
      ),
      AgentRequestAttachment(
        attachmentId: 'empty-content',
        kind: 'text',
        name: 'empty-content.txt',
        content: '   ',
      ),
    ]) {
      controller.addAttachment(attachment);
    }

    expect(controller.attachments, isEmpty);
  });

  test(
    'agent coding session retains prompt attachments on provider failure',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _ThrowingAgentProviderAdapter(),
        contextProvider: _context,
      );

      controller.addAttachment(
        const AgentRequestAttachment(
          attachmentId: 'note-1',
          kind: 'text',
          name: 'note.txt',
          content: 'prefer simple edits',
        ),
      );
      controller.updatePrompt('Use attachment.');
      await controller.sendPrompt();

      expect(controller.attachments.single.name, 'note.txt');
      controller.removeAttachment('note-1');
      expect(controller.attachments, isEmpty);
    },
  );

  test(
    'agent coding session caps conversation turns sent to provider',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'ok'),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        maxConversationTurns: 2,
      );

      controller.updatePrompt('one');
      await controller.sendPrompt();
      controller.updatePrompt('two');
      await controller.sendPrompt();
      controller.updatePrompt('three');
      await controller.sendPrompt();

      expect(controller.conversationTurns.length, 2);
      expect(controller.conversationTurns.first.text, 'three');
      expect(adapter.requests.last.conversationTurns.length, 2);
      expect(adapter.requests.last.conversationTurns.first.text, 'two');
      final compaction =
          adapter.requests.last.context.agent.conversationCompaction!;
      expect(compaction.status, AgentConversationCompactionStatus.windowed);
      expect(compaction.omittedTurnCount, 2);
      expect(compaction.hasSummary, isTrue);
      expect(compaction.summaryTurnCount, 2);
      expect(compaction.summaryStrategy, 'deterministic-extractive');
      expect(compaction.providerAssisted, isFalse);
      expect(compaction.summary, contains('- user: one'));
      expect(compaction.summary, contains('- assistant: ok'));
    },
  );

  test(
    'agent coding session supports zero retained conversation turns',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-zero-window',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'ok'),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        maxConversationTurns: 0,
      );

      controller.updatePrompt('one');
      await controller.sendPrompt();
      controller.updatePrompt('two');
      await controller.sendPrompt();

      expect(controller.conversationTurns, isEmpty);
      expect(adapter.requests.last.conversationTurns, isEmpty);
      final compaction =
          adapter.requests.last.context.agent.conversationCompaction!;
      expect(compaction.status, AgentConversationCompactionStatus.windowed);
      expect(compaction.omittedTurnCount, 2);
      expect(compaction.hasSummary, isTrue);
      expect(compaction.summaryTurnCount, 2);
      expect(compaction.summaryStrategy, 'deterministic-extractive');
      expect(compaction.providerAssisted, isFalse);
      expect(compaction.summary, contains('- user: one'));
      expect(compaction.summary, contains('- assistant: ok'));
    },
  );

  test(
    'agent coding session truncates oversized conversation turn text',
    () async {
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.text,
              text: 'assistant response is also too long',
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        maxConversationTurnTextLength: 10,
      );

      controller.updatePrompt('0123456789abcdef');
      await controller.sendPrompt();
      controller.updatePrompt('next');
      await controller.sendPrompt();

      expect(
        controller.conversationTurns.first.text,
        '0123456789\n[truncated 6 char(s)]',
      );
      expect(
        controller.conversationTurns[1].text,
        'assistant \n[truncated 25 char(s)]',
      );
      expect(
        adapter.requests.last.conversationTurns.first.text,
        '0123456789\n[truncated 6 char(s)]',
      );
      final compaction =
          adapter.requests.last.context.agent.conversationCompaction!;
      expect(compaction.status, AgentConversationCompactionStatus.truncated);
      expect(compaction.truncatedRetainedTurnCount, 2);
      expect(compaction.hasSummary, isFalse);
      expect(compaction.summary, isEmpty);
    },
  );

  test('agent coding session keeps pending code patch for preview', () async {
    const patch = AgentCodePatch(
      patchId: 'patch-1',
      summary: 'Update value.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      ),
      contextProvider: _context,
    );

    controller.updatePrompt('Change value.');
    await controller.sendPrompt();

    expect(controller.pendingPatch?.patchId, 'patch-1');
    controller.clearPendingPatch();
    expect(controller.pendingPatch, isNull);
  });

  test(
    'agent coding session exposes change review gate for pending patch',
    () async {
      const patch = AgentCodePatch(
        patchId: 'patch-review-1',
        summary: 'Update value.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FakeAgentProviderAdapter(
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-review',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: _context,
      );

      expect(
        controller.codingChangeReviewGate.status,
        AgentCodingChangeReviewGateStatus.idle,
      );

      controller.updatePrompt('Change value.');
      await controller.sendPrompt();
      final gate = controller.codingChangeReviewGate;

      expect(gate.status, AgentCodingChangeReviewGateStatus.needsReview);
      expect(gate.requiresUserReview, isTrue);
      expect(gate.canApplyPreview, isTrue);
      expect(gate.hasIssue('agent.change.requires-review'), isTrue);
      expect(
        gate.requiredReviewSteps,
        containsAll(<String>[
          'reviewWorkspaceEditPreview',
          'confirmGeneratedPatchScope',
          'capturePostApplyResult',
        ]),
      );
      expect(
        gate.reviewSurfaceActionIds,
        containsAll(<String>[
          'reviewWorkspaceEditPreview',
          'applyPendingPatch',
          'dismissPendingPatch',
          'collectAgentCodingCheckpoint',
        ]),
      );
      expect(
        gate.todoItems,
        isNot(
          contains(
            'TODO: bind this gate to the concrete diff review and apply controls.',
          ),
        ),
      );
      expect(gate.todoItems.join('\n'), isNot(contains('TODO:')));
      expect(gate.toJson()['status'], 'needsReview');
    },
  );

  test('agent coding session applies pending code patch to editor', () async {
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    const patch = AgentCodePatch(
      patchId: 'patch-1',
      summary: 'Update value.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      ),
      contextProvider: _context,
      runtimeOutputBuffer: buffer,
    );

    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    final result = controller.applyPendingPatch(
      AgentCodePatchApplier(editorController: editorController),
    );

    expect(result?.applied, isTrue);
    expect(controller.pendingPatch, isNull);
    expect(controller.lastPatchApplicationResult?.appliedEditCount, 1);
    expect(editorController.document.text, 'value = 2\n');
    final patchEvent = buffer.snapshot.events.singleWhere(
      (event) => event.metadata['operation'] == 'agent.patch.apply',
    );
    expect(patchEvent.channelId, 'agent.activity');
    expect(patchEvent.metadata['patchId'], 'patch-1');
    expect(patchEvent.metadata['outcome'], 'succeeded');
    expect(patchEvent.metadata['appliedEditCount'], 1);
  });

  test('agent coding session records skipped no-op patch documents', () async {
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 4,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    const patch = AgentCodePatch(
      patchId: 'patch-noop',
      summary: 'No-op value edit.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 0,
          end: 5,
          replacementText: 'value',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-noop',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      ),
      contextProvider: _context,
    );

    controller.updatePrompt('Apply no-op.');
    await controller.sendPrompt();
    final result = controller.applyPendingPatch(
      AgentCodePatchApplier(editorController: editorController),
    );

    expect(result?.applied, isFalse);
    expect(controller.pendingPatch, isNotNull);
    expect(controller.lastPatchApplicationContext?.skippedNoOpDocumentIds, [
      'main.styio',
    ]);
    expect(editorController.document.revision, 4);
    expect(editorController.canUndo, isFalse);
  });

  test(
    'agent coding session applies pending code patch with snapshot revert plan',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-snapshot-active',
        summary: 'Update value.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
        ],
      );
      final adapter = _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-snapshot',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.updatePrompt('Change value with snapshot.');
      await controller.sendPrompt();
      final result = await controller.applyPendingPatchWithSnapshot(
        applier: AgentCodePatchApplier(editorController: editorController),
        snapshotService: AgentWorkspaceSnapshotService(
          editorController: editorController,
        ),
      );
      final revertEdit = controller.lastWorkspaceRevertPlan!.patch.edits.single;

      expect(result?.applied, isTrue);
      expect(
        controller.lastWorkspaceSnapshotCaptureResult?.status,
        AgentWorkspaceSnapshotCaptureStatus.captured,
      );
      expect(
        controller.lastWorkspaceSnapshot?.documentFor('main.styio')?.text,
        'value = 1\n',
      );
      expect(
        controller.lastWorkspaceRevertPlan?.status,
        AgentWorkspaceRevertPlanStatus.ready,
      );
      final workspaceCheckpoint = controller.workspaceCheckpointContext!;
      expect(workspaceCheckpoint.captureStatus, 'captured');
      expect(workspaceCheckpoint.snapshotId, startsWith('agent-snapshot-'));
      expect(workspaceCheckpoint.patchId, 'patch-snapshot-active');
      expect(workspaceCheckpoint.capturedDocumentCount, 1);
      expect(workspaceCheckpoint.revertPlanStatus, 'ready');
      expect(workspaceCheckpoint.revertReady, isTrue);
      expect(workspaceCheckpoint.revertChangedDocumentCount, 1);
      expect(revertEdit.documentId, 'main.styio');
      expect(revertEdit.replacementText, 'value = 1\n');
      expect(editorController.document.text, 'value = 2\n');

      final revertResult = controller.applyLastWorkspaceRevertPlan(
        AgentCodePatchApplier(editorController: editorController),
      );

      expect(revertResult?.applied, isTrue);
      expect(editorController.document.text, 'value = 1\n');
      expect(controller.lastWorkspaceRevertPlan, isNull);
      expect(controller.lastWorkspaceSnapshot, isNull);
    },
  );

  test('agent coding session restores persisted workspace snapshot', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_workspace_snapshot_controller_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final store = AgentWorkspaceSnapshotStore.fromDataStore(
      dataStore: _foundationDataStore(tempRoot),
    );
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    const patch = AgentCodePatch(
      patchId: 'patch-persisted-snapshot',
      summary: 'Update value.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
      ],
    );
    final first = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-persisted-snapshot',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      ),
      contextProvider: _context,
      workspaceSnapshotStore: store,
      workspaceSnapshotWorkspaceId: 'demo',
    );
    addTearDown(first.dispose);

    first.updatePrompt('Capture a snapshot.');
    await first.sendPrompt();
    await first.capturePendingPatchSnapshot(
      AgentWorkspaceSnapshotService(editorController: editorController),
    );
    AgentCodePatchApplier(editorController: editorController).apply(patch);

    final second = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
      workspaceSnapshotStore: store,
      workspaceSnapshotWorkspaceId: 'demo',
    );
    addTearDown(second.dispose);
    await second.loadWorkspaceSnapshot(
      snapshotService: AgentWorkspaceSnapshotService(
        editorController: editorController,
      ),
    );

    expect(
      second.lastWorkspaceSnapshotCaptureResult?.message,
      contains('Restored workspace snapshot'),
    );
    expect(second.lastWorkspaceSnapshotCaptureResult?.restored, isTrue);
    expect(second.lastWorkspaceSnapshot?.patchId, 'patch-persisted-snapshot');
    expect(
      second.lastWorkspaceSnapshot?.documentFor('main.styio')?.text,
      'value = 1\n',
    );
    expect(
      second.lastWorkspaceRevertPlan?.status,
      AgentWorkspaceRevertPlanStatus.ready,
    );
    expect(
      second.lastWorkspaceRevertPlan?.patch.edits.single.replacementText,
      'value = 1\n',
    );
  });

  test(
    'agent coding session clears patch result when pending patch is dismissed',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-other-file',
        summary: 'Update other file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'other.styio',
            start: 0,
            end: 0,
            replacementText: 'value = 2\n',
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FakeAgentProviderAdapter(
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: _context,
      );

      controller.updatePrompt('Change other file.');
      await controller.sendPrompt();
      controller.applyPendingPatch(
        AgentCodePatchApplier(editorController: editorController),
      );

      expect(controller.pendingPatch, isNotNull);
      expect(controller.lastPatchApplicationResult?.applied, isFalse);

      controller.clearPendingPatch();

      expect(controller.pendingPatch, isNull);
      expect(controller.lastPatchApplicationResult, isNull);
    },
  );

  test('agent coding session applies pending workspace patch', () async {
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final workspaceStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'other.styio': DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 1,
        ),
      },
    );
    const patch = AgentCodePatch(
      patchId: 'patch-workspace',
      summary: 'Update workspace.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          baseRevision: 1,
          start: 8,
          end: 9,
          replacementText: '2',
        ),
        AgentCodePatchEdit(
          documentId: 'other.styio',
          baseRevision: 1,
          start: 7,
          end: 10,
          replacementText: 'new',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _FakeAgentProviderAdapter(
        response: const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      ),
      contextProvider: _context,
    );

    controller.updatePrompt('Change workspace.');
    await controller.sendPrompt();
    final result = await controller.applyPendingWorkspacePatch(
      AgentWorkspaceCodePatchApplier(
        editorController: editorController,
        workspaceDocumentStore: workspaceStore,
      ),
      snapshotService: AgentWorkspaceSnapshotService(
        editorController: editorController,
        workspaceDocumentStore: workspaceStore,
      ),
    );
    final otherDocument = await workspaceStore.loadDocument('other.styio');

    expect(result?.applied, isTrue);
    expect(controller.pendingPatch, isNull);
    expect(
      controller.lastWorkspaceSnapshotCaptureResult?.status,
      AgentWorkspaceSnapshotCaptureStatus.captured,
    );
    expect(
      controller.lastWorkspaceRevertPlan?.diffSummary.modifiedDocumentIds,
      containsAll(<String>['main.styio', 'other.styio']),
    );
    expect(editorController.document.text, 'value = 2\n');
    expect(otherDocument.text, 'name = new\n');

    final revertResult = await controller
        .applyLastWorkspaceRevertPlanToWorkspace(
          AgentWorkspaceCodePatchApplier(
            editorController: editorController,
            workspaceDocumentStore: workspaceStore,
          ),
        );
    final revertedOtherDocument = await workspaceStore.loadDocument(
      'other.styio',
    );

    expect(revertResult?.applied, isTrue);
    expect(editorController.document.text, 'value = 1\n');
    expect(revertedOtherDocument.text, 'name = old\n');
    expect(controller.lastWorkspaceRevertPlan, isNull);
  });

  test(
    'agent coding session rejects concurrent workspace patch application',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final workspaceStore = _DelayedWorkspaceDocumentStore(
        const DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 1,
        ),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-workspace-concurrent',
        summary: 'Update workspace.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'other.styio',
            baseRevision: 1,
            start: 7,
            end: 10,
            replacementText: 'new',
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FakeAgentProviderAdapter(
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: _context,
      );

      controller.updatePrompt('Change workspace.');
      await controller.sendPrompt();
      final firstResult = controller.applyPendingWorkspacePatch(
        AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ),
      );
      await workspaceStore.loadStarted.future;
      controller.updatePrompt('Do not send while applying.');
      expect(controller.canSend, isFalse);
      expect(await controller.sendPrompt(), isNull);

      final secondResult = await controller.applyPendingWorkspacePatch(
        AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ),
      );
      workspaceStore.releaseLoad();
      final appliedFirstResult = await firstResult;

      expect(secondResult?.applied, isFalse);
      expect(secondResult?.message, contains('already in progress'));
      expect(appliedFirstResult?.applied, isTrue);
      expect(controller.applyingPatch, isFalse);
    },
  );

  test(
    'agent coding session ignores patch result after provider remount',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final workspaceStore = _DelayedWorkspaceDocumentStore(
        const DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 1,
        ),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-workspace-remount',
        summary: 'Update workspace.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'other.styio',
            baseRevision: 1,
            start: 7,
            end: 10,
            replacementText: 'new',
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FakeAgentProviderAdapter(
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: _context,
      );

      controller.updatePrompt('Change workspace.');
      await controller.sendPrompt();
      final result = controller.applyPendingWorkspacePatch(
        AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ),
      );
      await workspaceStore.loadStarted.future;
      controller.mountProvider(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _ThrowingAgentProviderAdapter(),
      );
      workspaceStore.releaseLoad();

      expect(await result, isNull);
      expect(controller.applyingPatch, isFalse);
      expect(controller.pendingPatch, isNull);
      expect(controller.lastPatchApplicationResult, isNull);
    },
  );

  test(
    'agent coding session ignores patch result after pending patch is cleared',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final workspaceStore = _DelayedWorkspaceDocumentStore(
        const DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 1,
        ),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-workspace-clear',
        summary: 'Update workspace.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'other.styio',
            baseRevision: 1,
            start: 7,
            end: 10,
            replacementText: 'new',
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FakeAgentProviderAdapter(
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: _context,
      );

      controller.updatePrompt('Change workspace.');
      await controller.sendPrompt();
      final result = controller.applyPendingWorkspacePatch(
        AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ),
      );
      await workspaceStore.loadStarted.future;
      controller.clearPendingPatch();
      workspaceStore.releaseLoad();

      expect(await result, isNull);
      expect(controller.applyingPatch, isFalse);
      expect(controller.pendingPatch, isNull);
      expect(controller.lastPatchApplicationResult, isNull);
    },
  );

  test(
    'agent coding session ignores patch result after conversation is cleared',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final workspaceStore = _DelayedWorkspaceDocumentStore(
        const DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 1,
        ),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-workspace-clear-conversation',
        summary: 'Update workspace.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'other.styio',
            baseRevision: 1,
            start: 7,
            end: 10,
            replacementText: 'new',
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FakeAgentProviderAdapter(
          response: const AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: _context,
      );

      controller.updatePrompt('Change workspace.');
      await controller.sendPrompt();
      final result = controller.applyPendingWorkspacePatch(
        AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ),
      );
      await workspaceStore.loadStarted.future;
      controller.clearConversation();
      workspaceStore.releaseLoad();

      expect(await result, isNull);
      expect(controller.applyingPatch, isFalse);
      expect(controller.conversationTurns, isEmpty);
      expect(controller.pendingPatch, isNull);
      expect(controller.lastPatchApplicationResult, isNull);
    },
  );

  test('agent coding session records provider failure', () async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _ThrowingAgentProviderAdapter(),
      contextProvider: _context,
    );

    controller.updatePrompt('Explain this file.');
    final response = await controller.sendPrompt();

    expect(response, isNull);
    expect(controller.sending, isFalse);
    expect(controller.lastError, contains('provider unavailable'));
    expect(controller.lastProviderFailure, isNull);
    expect(controller.pendingPatch, isNull);
  });

  test('agent coding session preserves structured provider failure', () async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _StructuredFailureAgentProviderAdapter(),
      contextProvider: _context,
    );

    controller.updatePrompt('Explain this file.');
    final response = await controller.sendPrompt();

    expect(response, isNull);
    expect(controller.sending, isFalse);
    expect(controller.lastError, contains('kind=timeout'));
    expect(controller.lastError, contains('provider timed out'));
    expect(
      controller.lastProviderFailure?.kind,
      AgentProviderTransportFailureKind.timeout,
    );
    expect(
      controller.lastProviderFailure?.target,
      'https://agent.example.test',
    );
    expect(
      controller.lastProviderFailure?.recoveryHint,
      'Check the provider endpoint.',
    );

    controller.clearConversation();

    expect(controller.lastError, isNull);
    expect(controller.lastProviderFailure, isNull);
  });

  test(
    'agent coding session redacts sensitive provider error tokens',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _SensitiveThrowingAgentProviderAdapter(),
        contextProvider: _context,
      );

      controller.updatePrompt('Explain this file.');
      await controller.sendPrompt();

      expect(controller.lastError, contains('Bearer [redacted]'));
      expect(controller.lastError, contains('token=[redacted]'));
      expect(controller.lastError, isNot(contains('secret-token')));
      expect(controller.lastError, isNot(contains('abc123')));
    },
  );

  test(
    'agent coding session clears stale response before failed request',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _FailingSecondAgentProviderAdapter(),
        contextProvider: _context,
      );

      controller.updatePrompt('First request.');
      await controller.sendPrompt();
      expect(
        controller.lastResponse?.contentParts.single.text,
        'first response',
      );

      controller.updatePrompt('Second request.');
      final response = await controller.sendPrompt();

      expect(response, isNull);
      expect(controller.lastResponse, isNull);
      expect(controller.lastError, contains('provider unavailable'));
    },
  );

  test(
    'agent coding session can mount a configured provider at runtime',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      const profile = AgentPromptProfile(
        profileId: 'cloud',
        displayName: 'Cloud Agent',
        systemPrompt: 'Use IDE context.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-test',
        ),
      );
      final adapter = _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
        response: const AgentProviderResponseEnvelope(
          requestId: 'request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[],
        ),
      );

      controller.mountProvider(
        profile: profile,
        adapter: adapter,
        message: 'Configured provider mounted.',
        executionResolution: const AgentProviderExecutionResolution(
          profileId: 'cloud',
          status: AgentProviderExecutionResolutionStatus.ready,
          selectedEndpointIndex: 0,
          endpoints: <AgentProviderEndpointReadiness>[
            AgentProviderEndpointReadiness(
              endpointIndex: 0,
              fallback: false,
              endpoint: AgentProviderEndpoint(
                route: AgentProviderRoute.webHosted,
                baseUrl: 'https://agent.example.test/v1',
                model: 'gpt-test',
              ),
              plan: AgentProviderExecutionPlan(
                routeKind: AgentProviderExecutionRouteKind.cloud,
                providerKind: AgentProviderKind.cloudOpenAICompatible,
                route: AgentProviderRoute.webHosted,
                endpointBaseUrl: 'https://agent.example.test/v1',
              ),
              credentialReadiness: AgentProviderCredentialReadiness.available,
            ),
          ],
        ),
      );

      expect(controller.profile.profileId, 'cloud');
      expect(controller.adapter, same(adapter));
      expect(controller.providerKind, AgentProviderKind.cloudOpenAICompatible);
      expect(controller.providerSupportsCodePatch, isTrue);
      expect(controller.providerMountMessage, 'Configured provider mounted.');
      expect(controller.lastResponse, isNull);
      expect(controller.pendingPatch, isNull);

      controller.updatePrompt('Use provider.');
      final response = await controller.sendPrompt();
      final providerExecution =
          adapter.requests.single.context.agent.providerExecution!;
      final recoveryPlan = adapter.requests.single.context.agent.recoveryPlan!;

      expect(response, isNotNull);
      expect(providerExecution.status, 'ready');
      expect(providerExecution.selectedEndpoint?.routeKind, 'cloud');
      expect(
        providerExecution.selectedEndpoint?.credentialReadiness,
        'available',
      );
      expect(recoveryPlan.status, AgentCodingSessionRecoveryStatus.blocked);
      expect(recoveryPlan.canFailoverProvider, isFalse);
    },
  );

  test('agent coding session redacts provider mount message', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );

    controller.mountProvider(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      message: 'mounted Bearer secret-token',
    );

    expect(controller.providerMountMessage, contains('Bearer [redacted]'));
    expect(controller.providerMountMessage, isNot(contains('secret-token')));
  });

  test(
    'agent coding session ignores stale response after provider switch',
    () async {
      final adapter = _CompletingAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.updatePrompt('Explain this file.');
      final pendingResponse = controller.sendPrompt();
      expect(controller.sending, isTrue);

      controller.mountProvider(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        message: 'Provider switched.',
      );
      expect(controller.sending, isFalse);

      adapter.complete(
        const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.text,
              text: 'stale response',
            ),
          ],
        ),
      );

      expect(await pendingResponse, isNull);
      expect(controller.lastResponse, isNull);
      expect(controller.conversationTurns, isEmpty);
      expect(controller.providerMountMessage, 'Provider switched.');
    },
  );

  test('agent coding session can cancel active request', () async {
    final adapter = _CompletingAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );

    controller.updatePrompt('Explain this file.');
    final pendingResponse = controller.sendPrompt();
    expect(controller.sending, isTrue);

    controller.cancelActiveRequest();
    expect(controller.sending, isFalse);
    expect(controller.lastError, 'Agent request cancelled.');

    adapter.complete(
      const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.text,
            text: 'late response',
          ),
        ],
      ),
    );

    expect(await pendingResponse, isNull);
    expect(controller.lastResponse, isNull);
    expect(controller.conversationTurns, isEmpty);
  });

  test(
    'agent coding session forwards active provider request cancellation',
    () {
      final adapter = _CancellableCompletingAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );

      controller.updatePrompt('Explain this file.');
      final pendingResponse = controller.sendPrompt();
      expect(controller.sending, isTrue);
      expect(adapter.activeRequestId, 'agent-request-1');

      controller.cancelActiveRequest();

      expect(adapter.cancelledRequestIds, <String>['agent-request-1']);
      expect(controller.sending, isFalse);
      expect(controller.lastError, 'Agent request cancelled.');

      adapter.complete(
        const AgentProviderResponseEnvelope(
          requestId: 'agent-request-1',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: 'late'),
          ],
        ),
      );

      expect(pendingResponse, completion(isNull));
    },
  );

  test(
    'agent coding session cancels streaming provider requests with telemetry',
    () async {
      final adapter = _CancellableStreamingAgentProviderAdapter();
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
        runtimeOutputBuffer: buffer,
      );

      controller.updatePrompt('Explain this file.');
      final pendingResponse = controller.sendPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(controller.sending, isTrue);
      expect(adapter.streamedRequestIds, <String>['agent-request-1']);

      controller.cancelActiveRequest();

      expect(adapter.cancelledRequestIds, <String>['agent-request-1']);
      expect(controller.sending, isFalse);
      expect(controller.lastError, 'Agent request cancelled.');
      expect(
        buffer.snapshot.events.any(
          (event) =>
              event.channelId == 'agent.activity' &&
              event.metadata['outcome'] == 'cancelled',
        ),
        isTrue,
      );

      adapter.complete();

      expect(await pendingResponse, isNull);
    },
  );
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

class _FakeAgentProviderAdapter implements AgentProviderAdapter {
  _FakeAgentProviderAdapter({
    required this.response,
    this.kind = AgentProviderKind.localOnlyFallback,
  });

  final AgentProviderResponseEnvelope response;
  @override
  final AgentProviderKind kind;
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'fake';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    return response;
  }
}

class _StreamingAgentProviderAdapter implements StreamingAgentProviderAdapter {
  final List<String> streamedRequestIds = <String>[];
  var sendCalled = false;

  @override
  String get adapterId => 'streaming';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    sendCalled = true;
    throw StateError('streaming adapter send should not be used');
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    streamedRequestIds.add(request.requestId);
    yield AgentProviderStreamEvent.started(request.requestId);
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: 'streamed answer',
    );
    yield AgentProviderStreamEvent.completed(requestId: request.requestId);
  }
}

class _ToolCallStreamingAgentProviderAdapter
    implements StreamingAgentProviderAdapter {
  @override
  String get adapterId => 'tool-call-streaming';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw StateError('tool-call streaming adapter send should not be used');
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    yield AgentProviderStreamEvent.started(request.requestId);
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: '',
      metadata: const <String, Object?>{
        'toolCallEventKind': 'tool-call',
        'toolCallId': 'call-read',
        'toolId': 'readWorkspaceFile',
        'toolInput': '{"path":"main.styio"}',
      },
    );
    yield AgentProviderStreamEvent.completed(
      requestId: request.requestId,
      metadata: const <String, Object?>{
        'toolCallEventKind': 'tool-result',
        'toolCallId': 'call-read',
        'toolId': 'readWorkspaceFile',
        'toolResult': 'value = 1',
        'finishReason': 'stop',
      },
    );
  }
}

class _CancellableStreamingAgentProviderAdapter
    implements StreamingAgentProviderAdapter, CancellableAgentProviderAdapter {
  final List<String> streamedRequestIds = <String>[];
  final List<String> cancelledRequestIds = <String>[];
  final Completer<void> _completion = Completer<void>();

  @override
  String get adapterId => 'cancellable-streaming';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw StateError('cancellable streaming adapter send should not be used');
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    streamedRequestIds.add(request.requestId);
    yield AgentProviderStreamEvent.started(request.requestId);
    await _completion.future;
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: 'late streamed answer',
    );
    yield AgentProviderStreamEvent.completed(requestId: request.requestId);
  }

  @override
  void cancelRequest(String requestId) {
    cancelledRequestIds.add(requestId);
  }

  void complete() {
    if (!_completion.isCompleted) {
      _completion.complete();
    }
  }
}

class _ThrowingAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'throwing';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw StateError('provider unavailable');
  }
}

class _SensitiveThrowingAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'sensitive-throwing';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw StateError('provider unavailable Bearer secret-token token=abc123');
  }
}

class _StructuredFailureAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'structured-failure';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw const AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.timeout,
      message: 'provider timed out',
      target: 'https://agent.example.test',
      recoveryHint: 'Check the provider endpoint.',
    );
  }
}

class _StreamingToolCallOnlyAgentProviderAdapter
    implements StreamingAgentProviderAdapter {
  @override
  String get adapterId => 'streaming-tool-call-only';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw StateError(
      'streaming tool-call-only adapter send should not be used',
    );
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    yield AgentProviderStreamEvent.started(request.requestId);
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: '',
      metadata: const <String, Object?>{
        'toolCallEventKind': 'tool-input-start',
        'toolCallId': 'call-read',
        'toolId': 'readWorkspaceFile',
      },
    );
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: '',
      metadata: const <String, Object?>{
        'toolCallEventKind': 'tool-input-delta',
        'toolCallId': 'call-read',
        'toolId': 'readWorkspaceFile',
        'toolInputDelta': '{"path":"main.styio"}',
      },
    );
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: '',
      metadata: const <String, Object?>{
        'toolCallEventKind': 'tool-input-end',
        'toolCallId': 'call-read',
        'toolId': 'readWorkspaceFile',
        'toolInput': '{"path":"main.styio"}',
      },
    );
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: '',
      metadata: const <String, Object?>{
        'toolCallEventKind': 'tool-call',
        'toolCallId': 'call-read',
        'toolId': 'readWorkspaceFile',
        'toolInput': '{"path":"main.styio"}',
      },
    );
    yield AgentProviderStreamEvent.completed(
      requestId: request.requestId,
      metadata: const <String, Object?>{'finishReason': 'tool_calls'},
    );
  }
}

class _ThrowingAgentCodingSessionHistoryStore
    implements AgentCodingSessionHistoryStore {
  const _ThrowingAgentCodingSessionHistoryStore({
    this.readMessage = 'read failed',
    this.appendMessage = 'append failed',
  });

  final String readMessage;
  final String appendMessage;

  @override
  Future<AgentCodingSessionHistory> readHistory({
    required String workspaceId,
  }) async {
    throw StateError(readMessage);
  }

  @override
  Future<AgentCodingSessionHistory> appendRecord({
    required String workspaceId,
    required AgentCodingSessionHistoryRecord record,
    int maxEntries = 50,
  }) async {
    throw StateError(appendMessage);
  }

  @override
  Future<AgentCodingSessionCheckpoint> readCheckpoint({
    required String workspaceId,
  }) async {
    throw StateError(readMessage);
  }

  @override
  Future<AgentCodingSessionRecoveryPlan> readRecoveryPlan({
    required String workspaceId,
  }) async {
    throw StateError(readMessage);
  }

  @override
  Future<AgentCodingSessionRecoveryContext> readRecoveryContext({
    required String workspaceId,
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
  }) async {
    throw StateError(readMessage);
  }

  @override
  Future<void> saveHistory(AgentCodingSessionHistory history) async {
    throw StateError('save failed');
  }
}

class _MemoryAgentCodingSessionHistoryStore
    implements AgentCodingSessionHistoryStore {
  _MemoryAgentCodingSessionHistoryStore(this.history);

  AgentCodingSessionHistory history;

  @override
  Future<AgentCodingSessionHistory> readHistory({
    required String workspaceId,
  }) async {
    return history.workspaceId == workspaceId
        ? history
        : AgentCodingSessionHistory(workspaceId: workspaceId);
  }

  @override
  Future<AgentCodingSessionHistory> appendRecord({
    required String workspaceId,
    required AgentCodingSessionHistoryRecord record,
    int maxEntries = 50,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    history = current.append(record, maxEntries: maxEntries);
    return history;
  }

  @override
  Future<AgentCodingSessionCheckpoint> readCheckpoint({
    required String workspaceId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toCheckpoint();
  }

  @override
  Future<AgentCodingSessionRecoveryPlan> readRecoveryPlan({
    required String workspaceId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toRecoveryPlan();
  }

  @override
  Future<AgentCodingSessionRecoveryContext> readRecoveryContext({
    required String workspaceId,
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toRecoveryContext(
      targetProviderProfileKey:
          targetProviderProfileKey ?? targetProviderProfileId,
    );
  }

  @override
  Future<void> saveHistory(AgentCodingSessionHistory history) async {
    this.history = history;
  }
}

class _FailingSecondAgentProviderAdapter implements AgentProviderAdapter {
  var _sendCount = 0;

  @override
  String get adapterId => 'failing-second';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    _sendCount += 1;
    if (_sendCount == 2) {
      throw StateError('provider unavailable');
    }
    return const AgentProviderResponseEnvelope(
      requestId: 'agent-request-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.text,
          text: 'first response',
        ),
      ],
    );
  }
}

class _DelayedWorkspaceDocumentStore implements WorkspaceDocumentStore {
  _DelayedWorkspaceDocumentStore(this._document);

  DocumentState _document;
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> _releaseLoad = Completer<void>();

  @override
  Future<DocumentState> loadDocument(String path) async {
    if (!loadStarted.isCompleted) {
      loadStarted.complete();
    }
    await _releaseLoad.future;
    return _document;
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _document = document;
  }

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => true;

  @override
  String? filePathForDocumentId(String documentId) => documentId;

  void releaseLoad() {
    if (!_releaseLoad.isCompleted) {
      _releaseLoad.complete();
    }
  }
}

class _CompletingAgentProviderAdapter implements AgentProviderAdapter {
  final Completer<AgentProviderResponseEnvelope> _completer =
      Completer<AgentProviderResponseEnvelope>();

  @override
  String get adapterId => 'completing';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    return _completer.future;
  }

  void complete(AgentProviderResponseEnvelope response) {
    _completer.complete(response);
  }
}

FoundationDataStore _foundationDataStore(Directory root) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}

class _CancellableCompletingAgentProviderAdapter
    implements AgentProviderAdapter, CancellableAgentProviderAdapter {
  Completer<AgentProviderResponseEnvelope>? _completer;
  String? activeRequestId;
  final List<String> cancelledRequestIds = <String>[];

  @override
  String get adapterId => 'cancellable-completing';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    activeRequestId = request.requestId;
    _completer = Completer<AgentProviderResponseEnvelope>();
    return _completer!.future;
  }

  @override
  void cancelRequest(String requestId) {
    cancelledRequestIds.add(requestId);
  }

  void complete(AgentProviderResponseEnvelope response) {
    _completer?.complete(response);
  }
}
