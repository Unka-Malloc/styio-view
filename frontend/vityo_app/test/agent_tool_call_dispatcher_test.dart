import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
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
          output: 'command executed',
        );
      });

      expect(report.status, AgentToolCallDispatchReportStatus.dispatched);
      expect(
        controller.toolCallTimeline.status,
        AgentToolCallTimelineStatus.complete,
      );
      expect(
        controller.toolCallTimeline.callFor('call-command')?.resultSample,
        'command executed',
      );
      expect(
        controller.toolCallExecutionPlan.status,
        AgentToolCallExecutionPlanStatus.complete,
      );
    },
  );

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
