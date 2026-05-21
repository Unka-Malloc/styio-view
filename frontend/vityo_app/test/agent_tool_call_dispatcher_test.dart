import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

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
