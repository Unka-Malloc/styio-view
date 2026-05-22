import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent tool call dispatcher dispatches approved ready calls', () async {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-patch',
            toolId: 'applyWorkspacePatch',
            input: '{"patch":"diff --git a/main.styio b/main.styio"}',
          ),
        ]);
    final executionPlan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
      reviewDecisions: const <AgentToolCallReviewDecision>[
        AgentToolCallReviewDecision.approved(
          callId: 'call-patch',
          toolId: 'applyWorkspacePatch',
        ),
      ],
    );
    final requests = <AgentToolCallDispatchRequest>[];

    final report = await const AgentToolCallDispatcher().dispatchReady(
      executionPlan: executionPlan,
      timeline: timeline,
      executor: (request) {
        requests.add(request);
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: 'patch preview dispatched',
        );
      },
    );

    expect(report.status, AgentToolCallDispatchReportStatus.dispatched);
    expect(report.dispatched, isTrue);
    expect(report.plan.status, AgentToolCallDispatchPlanStatus.ready);
    expect(requests.single.toolId, 'applyWorkspacePatch');
    expect(requests.single.inputText, contains('diff --git'));
    expect(report.events.single.kind, AgentToolCallEventKind.result);
    expect(report.toJson()['status'], 'dispatched');
  });

  test(
    'agent tool call dispatcher validates result schema when available',
    () async {
      final profile = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      );
      final selection = AgentToolRegistry().selectForProfile(
        profile: profile,
        providerKind: AgentProviderKind.cloudOpenAICompatible,
      );
      final permissions = AgentToolPermissionPlan.fromSelection(selection);
      final timeline = const AgentToolCallLifecycleTracker()
          .track(<AgentToolCallEvent>[
            const AgentToolCallEvent.callStarted(
              callId: 'call-read',
              toolId: 'readWorkspaceFile',
              input: '{"path":"main.styio"}',
            ),
          ]);
      final executionPlan = AgentToolCallExecutionPlan.fromTimeline(
        toolSelection: selection,
        permissionPlan: permissions,
        timeline: timeline,
      );

      final report = await const AgentToolCallDispatcher().dispatchReady(
        executionPlan: executionPlan,
        timeline: timeline,
        toolSelection: selection,
        executor: (request) {
          return AgentToolCallDispatchResult.success(
            callId: request.callId,
            toolId: request.toolId,
            output: '{"document":{"text":"value = 1"}}',
          );
        },
      );

      expect(report.status, AgentToolCallDispatchReportStatus.failed);
      expect(report.results.single.success, isFalse);
      expect(
        report.results.single.message,
        contains('does not satisfy its result schema'),
      );
      expect(
        report.results.single.metadata['source'],
        'agent-tool-result-validation',
      );
      expect(report.events.single.kind, AgentToolCallEventKind.error);
    },
  );

  test('agent tool call dispatcher waits for review-gated calls', () async {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-patch',
            toolId: 'applyWorkspacePatch',
            input: '{"patch":"diff --git a/main.styio b/main.styio"}',
          ),
        ]);
    final executionPlan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );
    var executed = false;

    final report = await const AgentToolCallDispatcher().dispatchReady(
      executionPlan: executionPlan,
      timeline: timeline,
      executor: (_) {
        executed = true;
        return const AgentToolCallDispatchResult.success(
          callId: 'call-patch',
          toolId: 'applyWorkspacePatch',
          output: 'unexpected',
        );
      },
    );

    expect(report.status, AgentToolCallDispatchReportStatus.waiting);
    expect(report.plan.status, AgentToolCallDispatchPlanStatus.waitingReview);
    expect(report.results, isEmpty);
    expect(report.events, isEmpty);
    expect(executed, isFalse);
  });

  test(
    'agent coding session dispatches approved tool calls into lifecycle',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      controller.recordToolCallEvent(
        const AgentToolCallEvent.callStarted(
          callId: 'call-command',
          toolId: 'runIdeCommand',
          input: '{"commandId":"runTests"}',
        ),
      );
      expect(
        controller.toolCallExecutionPlan.status,
        AgentToolCallExecutionPlanStatus.reviewRequired,
      );

      controller.approveToolCallExecution('call-command');
      final report = await controller.dispatchReadyToolCalls((request) {
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: '{"source":"ide-command-runner","result":{"applied":true}}',
        );
      });

      expect(report.status, AgentToolCallDispatchReportStatus.dispatched);
      expect(
        controller.toolCallTimeline.status,
        AgentToolCallTimelineStatus.complete,
      );
      expect(
        controller.toolCallTimeline.callFor('call-command')?.resultSample,
        '{"source":"ide-command-runner","result":{"applied":true}}',
      );
      expect(
        controller.toolCallExecutionPlan.status,
        AgentToolCallExecutionPlanStatus.complete,
      );
    },
  );

  test(
    'agent coding session records replayable tool execution journal',
    () async {
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
          input: '{"path":"missing.styio"}',
        ),
      );

      final report = await controller.dispatchReadyToolCalls((request) {
        return AgentToolCallDispatchResult.failure(
          callId: request.callId,
          toolId: request.toolId,
          message: 'file missing',
        );
      });
      final journal = controller.toolCallExecutionJournal;

      expect(report.status, AgentToolCallDispatchReportStatus.failed);
      expect(journal.status, AgentToolCallExecutionJournalStatus.failed);
      expect(journal.replayCandidates.single.toolId, 'readWorkspaceFile');
      expect(
        journal.replayRequests().single.inputText,
        '{"path":"missing.styio"}',
      );
    },
  );

  test('agent coding session replays tool execution journal', () async {
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
        input: '{"path":"missing.styio"}',
      ),
    );
    await controller.dispatchReadyToolCalls((request) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'file missing',
      );
    });

    final report = await controller.replayToolCallJournal((request) {
      return AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output:
            '{"source":"agent-session-context","document":{"text":"restored"}}',
      );
    });

    expect(report.status, AgentToolCallReplayReportStatus.replayed);
    expect(report.replayed, isTrue);
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(
      controller.toolCallExecutionPlan.executionFor('call-read')?.status,
      AgentToolCallExecutionStatus.completed,
    );
    expect(
      controller.toolCallReplayPlan.status,
      AgentToolCallReplayPlanStatus.blocked,
    );
    expect(
      controller.recentToolCallResultContexts.any(
        (result) => result.metadata['replayedFromJournal'] == true,
      ),
      isTrue,
    );
  });

  test('agent builtin executor reads sampled workspace files', () async {
    final context = _context(
      workspaceFiles: const <String>['helper.styio'],
      workspaceDocuments: const <DocumentState>[
        DocumentState(
          documentId: 'helper.styio',
          text: 'helper = 1\n',
          revision: 3,
        ),
      ],
    );
    final report = await _dispatchBuiltinRead(context, 'helper.styio');
    final output = jsonDecode(report.results.single.output);

    expect(report.status, AgentToolCallDispatchReportStatus.dispatched);
    expect(output['source'], 'agent-session-context');
    expect(output['document']['documentId'], 'helper.styio');
    expect(output['document']['text'], 'helper = 1\n');
  });

  test('agent builtin executor reads workspace store files', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'stored.styio': DocumentState(
          documentId: 'stored.styio',
          text: 'stored = true\n',
          revision: 4,
        ),
      },
    );
    final report = await _dispatchBuiltinRead(
      _context(workspaceFiles: const <String>['stored.styio']),
      'stored.styio',
      documentStore: store,
    );
    final output = jsonDecode(report.results.single.output);

    expect(report.status, AgentToolCallDispatchReportStatus.dispatched);
    expect(output['source'], 'workspace-document-store');
    expect(output['document']['revision'], 4);
    expect(output['document']['text'], 'stored = true\n');
  });

  test('agent builtin executor collects coding checkpoint', () async {
    final executor = AgentBuiltinToolExecutor(context: _context());
    final result = await executor.execute(
      const AgentToolCallDispatchRequest(
        callId: 'call-checkpoint',
        toolId: 'collectAgentCodingCheckpoint',
        inputText: '{}',
      ),
    );
    final output = jsonDecode(result.output);

    expect(result.success, isTrue);
    expect(output['source'], 'agent-session-context');
    expect(output['checkpoint']['schemaVersion'], isA<int>());
    expect(output['checkpoint']['workspace'], isA<Map<Object?, Object?>>());
  });

  test('agent builtin executor collects Styio language context', () async {
    final executor = AgentBuiltinToolExecutor(context: _context());
    final result = await executor.execute(
      const AgentToolCallDispatchRequest(
        callId: 'call-language',
        toolId: 'collectStyioLanguageContext',
        inputText: '{}',
      ),
    );
    final output = jsonDecode(result.output);

    expect(result.success, isTrue);
    expect(output['source'], 'agent-session-context');
    expect(output['language'], isA<Map<Object?, Object?>>());
    expect(output['language']['completionCount'], isA<int>());
    expect(result.metadata['semanticSpanCount'], isA<int>());
  });

  test('agent builtin executor collects validation context', () async {
    final executor = AgentBuiltinToolExecutor(
      context: _context(),
      validationContextProvider: () =>
          AgentCodingValidationToolContext.fromSessionContext(
            _context(),
            validationPlan: const AgentCodingValidationPlan(
              status: AgentCodingValidationPlanStatus.ready,
              shouldRun: true,
              reason: 'Generated code was applied and needs validation.',
              registeredCommandIds: <String>['runTests'],
              commandPlans: <AgentCodingValidationCommandPlan>[
                AgentCodingValidationCommandPlan(
                  commandId: 'runTests',
                  phase: 'testing',
                  required: true,
                  requiresInput: false,
                ),
              ],
            ),
            validationResult: const AgentCodingValidationResult(
              status: AgentCodingValidationResultStatus.notStarted,
              summary: 'Agent coding validation has not started.',
              requiredCommandIds: <String>['runTests'],
              missingCommandIds: <String>['runTests'],
            ),
            validationPipeline: const AgentCodingValidationPipeline(
              status: AgentCodingValidationPipelineStatus.ready,
              summary: 'Agent coding validation is ready to run.',
              nextCommandId: 'runTests',
              remainingCommandIds: <String>['runTests'],
              runnableCommandIds: <String>['runTests'],
              progressDenominator: 1,
            ),
          ),
    );
    final result = await executor.execute(
      const AgentToolCallDispatchRequest(
        callId: 'call-validation',
        toolId: 'collectAgentValidationContext',
        inputText: '{}',
      ),
    );
    final output = jsonDecode(result.output);

    expect(result.success, isTrue);
    expect(output['source'], 'agent-validation-context');
    expect(output['validation']['validationPlan']['status'], 'ready');
    expect(
      output['validation']['validationPipeline']['nextCommandId'],
      'runTests',
    );
    expect(result.metadata['nextCommandId'], 'runTests');
    expect(result.metadata['runnableCommandCount'], 1);
  });

  test(
    'agent builtin executor reports recovery context fallback facts',
    () async {
      final executor = AgentBuiltinToolExecutor(context: _context());
      final result = await executor.execute(
        const AgentToolCallDispatchRequest(
          callId: 'call-recovery-fallback',
          toolId: 'collectAgentRecoveryContext',
          inputText: '{}',
        ),
      );
      final output = jsonDecode(result.output);
      final recovery = output['recovery'] as Map<String, Object?>;

      expect(result.success, isTrue);
      expect(output['source'], 'agent-session-context');
      expect(recovery['fallbackMode'], 'agentSessionContextOnly');
      expect(recovery['fullHistoryUnavailable'], isTrue);
      expect(recovery.containsKey('TODO'), isFalse);
      expect(result.metadata['fullHistoryUnavailable'], isTrue);
    },
  );

  test('agent builtin executor collects recovery context', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.linux);
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord.failure(
          requestId: 'agent-recovery',
          profile: profile,
          providerKind: AgentProviderKind.cloudOpenAICompatible,
          prompt: 'Recover the agent session.',
          errorMessage: 'Provider stream failed.',
          createdAt: DateTime.utc(2026, 5, 22),
          completedAt: DateTime.utc(2026, 5, 22, 0, 1),
        ),
      ],
    );
    final executor = AgentBuiltinToolExecutor(
      context: _context(),
      recoveryContextProvider: () =>
          history.toRecoveryContext(targetProviderProfileKey: 'backup'),
    );
    final result = await executor.execute(
      const AgentToolCallDispatchRequest(
        callId: 'call-recovery',
        toolId: 'collectAgentRecoveryContext',
        inputText: '{}',
      ),
    );
    final output = jsonDecode(result.output);

    expect(result.success, isTrue);
    expect(output['source'], 'agent-recovery-context');
    expect(output['recovery']['hasRecoverableSession'], isTrue);
    expect(output['recovery']['hasReplayDraft'], isTrue);
    expect(result.metadata['hasReplayDraft'], isTrue);
    expect(result.metadata['requestDraftCount'], 3);
  });

  test('agent builtin executor delegates extension tools', () async {
    AgentToolCallDispatchRequest? receivedRequest;
    final executor = AgentBuiltinToolExecutor(
      context: _context(),
      extensionToolRunner: (request) async {
        receivedRequest = request;
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: '{"extension":"ok"}',
          metadata: const <String, Object?>{'source': 'extension-host'},
        );
      },
    );
    final result = await executor.execute(
      const AgentToolCallDispatchRequest(
        callId: 'call-extension',
        toolId: 'collectExtensionContext',
        inputText: '{"extensionId":"demo"}',
      ),
    );

    expect(result.success, isTrue);
    expect(receivedRequest?.toolId, 'collectExtensionContext');
    expect(result.output, '{"extension":"ok"}');
    expect(result.metadata['source'], 'extension-host');
  });

  test('agent builtin executor requires extension tool runner', () async {
    final executor = AgentBuiltinToolExecutor(context: _context());
    final result = await executor.execute(
      const AgentToolCallDispatchRequest(
        callId: 'call-extension',
        toolId: 'collectExtensionContext',
        inputText: '{"extensionId":"demo"}',
      ),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('no AgentExtensionToolRunner'));
  });

  test('agent builtin executor previews workspace edits', () async {
    final executor = AgentBuiltinToolExecutor(context: _context());
    final result = await executor.execute(
      AgentToolCallDispatchRequest(
        callId: 'call-preview',
        toolId: 'previewWorkspaceEdit',
        inputText: jsonEncode(<String, Object?>{
          'edits': <Object?>[
            <String, Object?>{
              'documentId': 'main.styio',
              'start': 8,
              'end': 9,
              'replacementText': '2',
            },
          ],
        }),
      ),
    );
    final output = jsonDecode(result.output);

    expect(result.success, isTrue);
    expect(output['source'], 'agent-workspace-edit-preview');
    expect(output['patch']['patchId'], 'agent-tool-call-preview');
    expect(output['conversion']['converted'], isTrue);
    expect(output['conversion']['plan']['id'], 'agent-tool-call-preview');
  });

  test('agent builtin executor requires workspace patch runner', () async {
    final executor = AgentBuiltinToolExecutor(context: _context());
    final result = await executor.execute(
      AgentToolCallDispatchRequest(
        callId: 'call-apply',
        toolId: 'applyWorkspacePatch',
        inputText: jsonEncode(<String, Object?>{
          'edits': <Object?>[
            <String, Object?>{
              'documentId': 'main.styio',
              'start': 8,
              'end': 9,
              'replacementText': '2',
            },
          ],
        }),
      ),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('no AgentWorkspacePatchToolRunner'));
  });

  test(
    'agent builtin executor applies workspace patches through runner',
    () async {
      AgentCodePatch? receivedPatch;
      final executor = AgentBuiltinToolExecutor(
        context: _context(),
        workspacePatchRunner: (patch) async {
          receivedPatch = patch;
          return const AgentCodePatchApplicationResult(
            applied: true,
            message: 'patch applied through review gate',
            appliedEditCount: 1,
            appliedOperationCounts: <String, int>{'replace': 1},
            appliedDocumentIds: <String>['main.styio'],
          );
        },
      );
      final result = await executor.execute(
        AgentToolCallDispatchRequest(
          callId: 'call-apply',
          toolId: 'applyWorkspacePatch',
          inputText: jsonEncode(<String, Object?>{
            'patch': <String, Object?>{
              'patchId': 'patch-from-tool',
              'summary': 'Change value.',
              'edits': <Object?>[
                <String, Object?>{
                  'documentId': 'main.styio',
                  'start': 8,
                  'end': 9,
                  'replacementText': '2',
                },
              ],
            },
          }),
        ),
      );
      final output = jsonDecode(result.output);

      expect(result.success, isTrue);
      expect(receivedPatch?.patchId, 'patch-from-tool');
      expect(output['source'], 'agent-workspace-patch-runner');
      expect(output['result']['applied'], isTrue);
      expect(output['result']['appliedDocumentIds'], <String>['main.styio']);
    },
  );

  test(
    'agent builtin executor captures snapshot before applying workspace patch',
    () async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      AgentCodePatch? receivedPatch;
      final executor = AgentBuiltinToolExecutor(
        context: _context(),
        workspaceSnapshotService: AgentWorkspaceSnapshotService(
          editorController: editorController,
        ),
        workspacePatchRunner: (patch) async {
          receivedPatch = patch;
          return const AgentCodePatchApplicationResult(
            applied: true,
            message: 'patch applied after snapshot capture',
            appliedEditCount: 1,
            appliedOperationCounts: <String, int>{'replace': 1},
            appliedDocumentIds: <String>['main.styio'],
          );
        },
      );

      final result = await executor.execute(
        AgentToolCallDispatchRequest(
          callId: 'call-apply-snapshot',
          toolId: 'applyWorkspacePatch',
          inputText: jsonEncode(<String, Object?>{
            'patch': <String, Object?>{
              'patchId': 'patch-from-tool',
              'summary': 'Change value.',
              'edits': <Object?>[
                <String, Object?>{
                  'documentId': 'main.styio',
                  'start': 8,
                  'end': 9,
                  'replacementText': '2',
                },
              ],
            },
          }),
        ),
      );

      final output = jsonDecode(result.output) as Map<String, Object?>;
      final workspaceSnapshot =
          output['workspaceSnapshot']! as Map<String, Object?>;
      final snapshot = workspaceSnapshot['snapshot']! as Map<String, Object?>;

      expect(result.success, isTrue);
      expect(receivedPatch?.patchId, 'patch-from-tool');
      expect(workspaceSnapshot['status'], 'captured');
      expect(
        snapshot['snapshotId'],
        'agent-tool-snapshot-call-apply-snapshot-patch-from-tool',
      );
      expect(snapshot['documentIds'], <String>['main.styio']);
      expect(result.metadata['workspaceSnapshotCaptured'], isTrue);
      expect(result.metadata['workspaceSnapshotStatus'], 'captured');
      expect(
        result.metadata['workspaceSnapshotId'],
        'agent-tool-snapshot-call-apply-snapshot-patch-from-tool',
      );
      expect(result.metadata['workspaceSnapshotDocumentCount'], 1);
    },
  );

  test('agent builtin executor runs registered IDE commands', () async {
    AgentIdeCommandSuggestion? suggestion;
    final executor = AgentBuiltinToolExecutor(
      context: _context(),
      ideCommandRunner: (incoming) async {
        suggestion = incoming;
        return AgentCommandResultContext(
          commandId: incoming.commandId,
          input: incoming.input,
          applied: true,
          message: 'runTests completed',
          completedAt: DateTime.utc(2026, 5, 22),
        );
      },
    );
    final result = await executor.execute(
      AgentToolCallDispatchRequest(
        callId: 'call-command',
        toolId: 'runIdeCommand',
        inputText: jsonEncode(<String, Object?>{'commandId': 'runTests'}),
      ),
    );
    final output = jsonDecode(result.output);

    expect(result.success, isTrue);
    expect(suggestion?.commandId, 'runTests');
    expect(output['source'], 'ide-command-runner');
    expect(output['result']['commandId'], 'runTests');
    expect(output['result']['message'], 'runTests completed');
  });

  test('agent builtin executor rejects unregistered IDE commands', () async {
    final executor = AgentBuiltinToolExecutor(
      context: _context(),
      ideCommandRunner: (_) async {
        throw StateError('should not run');
      },
    );
    final result = await executor.execute(
      AgentToolCallDispatchRequest(
        callId: 'call-command',
        toolId: 'runIdeCommand',
        inputText: jsonEncode(<String, Object?>{'commandId': 'missingCommand'}),
      ),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('not registered'));
  });

  test('agent builtin executor requires IDE command runner', () async {
    final executor = AgentBuiltinToolExecutor(context: _context());
    final result = await executor.execute(
      AgentToolCallDispatchRequest(
        callId: 'call-command',
        toolId: 'runIdeCommand',
        inputText: jsonEncode(<String, Object?>{'commandId': 'runTests'}),
      ),
    );

    expect(result.success, isFalse);
    expect(result.message, contains('no AgentIdeCommandToolRunner'));
  });
}

Future<AgentToolCallDispatchReport> _dispatchBuiltinRead(
  AgentSessionContext context,
  String path, {
  WorkspaceDocumentStore? documentStore,
}) {
  final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
  final selection = AgentToolRegistry().selectForProfile(
    profile: profile,
    providerKind: AgentProviderKind.localOnlyFallback,
  );
  final permissions = AgentToolPermissionPlan.fromSelection(selection);
  final timeline = const AgentToolCallLifecycleTracker().track(
    <AgentToolCallEvent>[
      AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: jsonEncode(<String, Object?>{'path': path}),
      ),
    ],
  );
  final executionPlan = AgentToolCallExecutionPlan.fromTimeline(
    toolSelection: selection,
    permissionPlan: permissions,
    timeline: timeline,
  );
  return const AgentToolCallDispatcher().dispatchReady(
    executionPlan: executionPlan,
    timeline: timeline,
    executor: AgentBuiltinToolExecutor(
      context: context,
      documentStore: documentStore,
    ).execute,
  );
}

AgentSessionContext _context({
  Iterable<String> workspaceFiles = const <String>[],
  Iterable<DocumentState> workspaceDocuments = const <DocumentState>[],
}) {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    workspaceFiles: workspaceFiles,
    workspaceDocuments: workspaceDocuments,
  );
}
