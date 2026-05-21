import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_code_patch_applier.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_history_store.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/agent/agent_tool_call_execution_plan.dart';
import 'package:vityo_app/src/agent/agent_tool_call_lifecycle.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
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
        'TODO: bind ProviderRegistry route selection to the coding assistant UI.',
      ),
    );
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
    expect(
      controller.toolCallExecutionPlan.status,
      AgentToolCallExecutionPlanStatus.complete,
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

      final event = buffer.snapshot.events.single;
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
    expect(buffer.snapshot.events, hasLength(2));
    final event = buffer.snapshot.events.last;
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
    );
    final otherDocument = await workspaceStore.loadDocument('other.styio');

    expect(result?.applied, isTrue);
    expect(controller.pendingPatch, isNull);
    expect(editorController.document.text, 'value = 2\n');
    expect(otherDocument.text, 'name = new\n');
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
