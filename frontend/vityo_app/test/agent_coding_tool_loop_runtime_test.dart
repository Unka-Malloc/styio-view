import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent coding tool loop runtime dispatches ready tool calls', () async {
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
    controller.approveToolCallExecution('call-command');

    final report = await const AgentCodingToolLoopRuntime().run(
      controller: controller,
      executor: (request) {
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: _commandOutput(),
        );
      },
    );

    expect(report.status, AgentCodingToolLoopRuntimeStatus.complete);
    expect(report.dispatchRoundCount, 1);
    expect(report.terminal, isTrue);
    expect(
      report.finalExecutionPlan.status,
      AgentToolCallExecutionPlanStatus.complete,
    );
    expect(report.toJson()['status'], 'complete');
  });

  test('agent coding tool loop runtime waits for review-gated calls', () async {
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
    var executed = false;

    final report = await const AgentCodingToolLoopRuntime().run(
      controller: controller,
      executor: (_) {
        executed = true;
        return const AgentToolCallDispatchResult.success(
          callId: 'call-command',
          toolId: 'runIdeCommand',
          output: 'unexpected',
        );
      },
    );

    expect(report.status, AgentCodingToolLoopRuntimeStatus.waiting);
    expect(report.dispatchRoundCount, 0);
    expect(executed, isFalse);
  });

  test('agent coding tool loop runtime honors stop condition', () async {
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
    controller.approveToolCallExecution('call-command');
    var executed = false;

    final report =
        await AgentCodingToolLoopRuntime(
          stopWhen: (state) =>
              state.executionPlan.status ==
              AgentToolCallExecutionPlanStatus.ready,
        ).run(
          controller: controller,
          executor: (_) {
            executed = true;
            return const AgentToolCallDispatchResult.success(
              callId: 'call-command',
              toolId: 'runIdeCommand',
              output: 'unexpected',
            );
          },
        );

    expect(report.status, AgentCodingToolLoopRuntimeStatus.stopped);
    expect(report.stoppedByCondition, isTrue);
    expect(report.dispatchRoundCount, 0);
    expect(executed, isFalse);
  });

  test(
    'agent coding tool loop runtime respects zero dispatch budget',
    () async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.openAICodexSparkForPlatform(
          PlatformTarget.linux,
        ),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      final report =
          await const AgentCodingToolLoopRuntime(maxDispatchRounds: 0).run(
            controller: controller,
            executor: (_) {
              return const AgentToolCallDispatchResult.success(
                callId: 'unused',
                toolId: 'unused',
                output: 'unused',
              );
            },
          );

      expect(report.status, AgentCodingToolLoopRuntimeStatus.limitReached);
      expect(report.dispatchRoundCount, 0);
    },
  );

  test('agent coding tool loop runtime continues after dispatch', () async {
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
    controller.approveToolCallExecution('call-command');
    AgentCodingToolLoopContinuationRequest? continuationRequest;

    final report = await const AgentCodingToolLoopRuntime().run(
      controller: controller,
      executor: (request) {
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: _commandOutput(),
        );
      },
      continueAfterDispatch: (request) {
        continuationRequest = request;
        return const AgentCodingToolLoopContinuationResult.dispatched(
          message: 'Provider follow-up queued.',
          metadata: <String, Object?>{'source': 'test-continuation'},
        );
      },
    );

    expect(report.status, AgentCodingToolLoopRuntimeStatus.complete);
    expect(report.continuationCount, 1);
    expect(continuationRequest?.roundIndex, 0);
    expect(
      continuationRequest?.dispatchReport.status,
      AgentToolCallDispatchReportStatus.dispatched,
    );
    expect(
      report.continuationResults.single.message,
      'Provider follow-up queued.',
    );
    expect(report.toJson()['continuationCount'], 1);
  });

  test('agent coding tool loop runtime fails on continuation errors', () async {
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
    controller.approveToolCallExecution('call-command');

    final report = await const AgentCodingToolLoopRuntime().run(
      controller: controller,
      executor: (request) {
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: _commandOutput(),
        );
      },
      continueAfterDispatch: (_) {
        throw StateError('provider unavailable');
      },
    );

    expect(report.status, AgentCodingToolLoopRuntimeStatus.failed);
    expect(report.continuationCount, 1);
    expect(report.continuationResults.single.failed, isTrue);
    expect(
      report.continuationResults.single.message,
      contains('provider unavailable'),
    );
  });
}

String _commandOutput() {
  return '{"source":"test-command-runner","result":{"applied":true}}';
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
