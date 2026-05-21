import 'agent_coding_session_controller.dart';
import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_call_execution_plan.dart';

enum AgentCodingToolLoopRuntimeStatus {
  idle,
  waiting,
  blocked,
  failed,
  dispatched,
  complete,
  limitReached,
  stopped,
}

extension AgentCodingToolLoopRuntimeStatusX
    on AgentCodingToolLoopRuntimeStatus {
  String get wireValue => switch (this) {
    AgentCodingToolLoopRuntimeStatus.idle => 'idle',
    AgentCodingToolLoopRuntimeStatus.waiting => 'waiting',
    AgentCodingToolLoopRuntimeStatus.blocked => 'blocked',
    AgentCodingToolLoopRuntimeStatus.failed => 'failed',
    AgentCodingToolLoopRuntimeStatus.dispatched => 'dispatched',
    AgentCodingToolLoopRuntimeStatus.complete => 'complete',
    AgentCodingToolLoopRuntimeStatus.limitReached => 'limit_reached',
    AgentCodingToolLoopRuntimeStatus.stopped => 'stopped',
  };
}

class AgentCodingToolLoopRuntimeState {
  const AgentCodingToolLoopRuntimeState({
    required this.roundIndex,
    required this.executionPlan,
    this.dispatchReports = const <AgentToolCallDispatchReport>[],
  });

  final int roundIndex;
  final AgentToolCallExecutionPlan executionPlan;
  final List<AgentToolCallDispatchReport> dispatchReports;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'roundIndex': roundIndex,
      'executionPlan': executionPlan.toJson(),
      'dispatchReportCount': dispatchReports.length,
    };
  }
}

typedef AgentCodingToolLoopStopCondition =
    bool Function(AgentCodingToolLoopRuntimeState state);

class AgentCodingToolLoopRuntimeReport {
  const AgentCodingToolLoopRuntimeReport({
    required this.status,
    required this.maxDispatchRounds,
    required this.finalExecutionPlan,
    this.dispatchReports = const <AgentToolCallDispatchReport>[],
    this.stoppedByCondition = false,
  });

  final AgentCodingToolLoopRuntimeStatus status;
  final int maxDispatchRounds;
  final AgentToolCallExecutionPlan finalExecutionPlan;
  final List<AgentToolCallDispatchReport> dispatchReports;
  final bool stoppedByCondition;

  int get dispatchRoundCount => dispatchReports.length;
  bool get terminal =>
      status == AgentCodingToolLoopRuntimeStatus.blocked ||
      status == AgentCodingToolLoopRuntimeStatus.failed ||
      status == AgentCodingToolLoopRuntimeStatus.complete ||
      status == AgentCodingToolLoopRuntimeStatus.limitReached ||
      status == AgentCodingToolLoopRuntimeStatus.stopped;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'terminal': terminal,
      'maxDispatchRounds': maxDispatchRounds,
      'dispatchRoundCount': dispatchRoundCount,
      'stoppedByCondition': stoppedByCondition,
      'finalExecutionPlan': finalExecutionPlan.toJson(),
      'dispatchReports': dispatchReports
          .map((report) => report.toJson())
          .toList(growable: false),
    };
  }
}

class AgentCodingToolLoopRuntime {
  const AgentCodingToolLoopRuntime({this.maxDispatchRounds = 4, this.stopWhen});

  final int maxDispatchRounds;
  final AgentCodingToolLoopStopCondition? stopWhen;

  Future<AgentCodingToolLoopRuntimeReport> run({
    required AgentCodingSessionController controller,
    required AgentToolCallExecutor executor,
    AgentToolCallDispatcher dispatcher = const AgentToolCallDispatcher(),
  }) async {
    final dispatchReports = <AgentToolCallDispatchReport>[];
    if (maxDispatchRounds <= 0) {
      return _report(
        status: AgentCodingToolLoopRuntimeStatus.limitReached,
        controller: controller,
        dispatchReports: dispatchReports,
      );
    }

    while (dispatchReports.length < maxDispatchRounds) {
      final plan = controller.toolCallExecutionPlan;
      final state = AgentCodingToolLoopRuntimeState(
        roundIndex: dispatchReports.length,
        executionPlan: plan,
        dispatchReports: List<AgentToolCallDispatchReport>.unmodifiable(
          dispatchReports,
        ),
      );
      if (stopWhen?.call(state) ?? false) {
        return _report(
          status: AgentCodingToolLoopRuntimeStatus.stopped,
          controller: controller,
          dispatchReports: dispatchReports,
          stoppedByCondition: true,
        );
      }

      final terminalStatus = _statusForExecutionPlan(plan.status);
      if (terminalStatus != null) {
        return _report(
          status: terminalStatus,
          controller: controller,
          dispatchReports: dispatchReports,
        );
      }

      final dispatchReport = await controller.dispatchReadyToolCalls(
        executor,
        dispatcher: dispatcher,
      );
      dispatchReports.add(dispatchReport);

      final dispatchStatus = _statusForDispatchReport(dispatchReport.status);
      if (dispatchStatus != AgentCodingToolLoopRuntimeStatus.dispatched) {
        return _report(
          status: dispatchStatus,
          controller: controller,
          dispatchReports: dispatchReports,
        );
      }
      if (controller.toolCallExecutionPlan.status ==
          AgentToolCallExecutionPlanStatus.complete) {
        return _report(
          status: AgentCodingToolLoopRuntimeStatus.complete,
          controller: controller,
          dispatchReports: dispatchReports,
        );
      }
    }

    return _report(
      status: AgentCodingToolLoopRuntimeStatus.limitReached,
      controller: controller,
      dispatchReports: dispatchReports,
    );
  }

  AgentCodingToolLoopRuntimeReport _report({
    required AgentCodingToolLoopRuntimeStatus status,
    required AgentCodingSessionController controller,
    required List<AgentToolCallDispatchReport> dispatchReports,
    bool stoppedByCondition = false,
  }) {
    return AgentCodingToolLoopRuntimeReport(
      status: status,
      maxDispatchRounds: maxDispatchRounds,
      finalExecutionPlan: controller.toolCallExecutionPlan,
      dispatchReports: List<AgentToolCallDispatchReport>.unmodifiable(
        dispatchReports,
      ),
      stoppedByCondition: stoppedByCondition,
    );
  }
}

AgentCodingToolLoopRuntimeStatus? _statusForExecutionPlan(
  AgentToolCallExecutionPlanStatus status,
) {
  return switch (status) {
    AgentToolCallExecutionPlanStatus.idle =>
      AgentCodingToolLoopRuntimeStatus.idle,
    AgentToolCallExecutionPlanStatus.waiting ||
    AgentToolCallExecutionPlanStatus.reviewRequired =>
      AgentCodingToolLoopRuntimeStatus.waiting,
    AgentToolCallExecutionPlanStatus.blocked =>
      AgentCodingToolLoopRuntimeStatus.blocked,
    AgentToolCallExecutionPlanStatus.failed =>
      AgentCodingToolLoopRuntimeStatus.failed,
    AgentToolCallExecutionPlanStatus.complete =>
      AgentCodingToolLoopRuntimeStatus.complete,
    AgentToolCallExecutionPlanStatus.ready => null,
  };
}

AgentCodingToolLoopRuntimeStatus _statusForDispatchReport(
  AgentToolCallDispatchReportStatus status,
) {
  return switch (status) {
    AgentToolCallDispatchReportStatus.idle =>
      AgentCodingToolLoopRuntimeStatus.idle,
    AgentToolCallDispatchReportStatus.waiting =>
      AgentCodingToolLoopRuntimeStatus.waiting,
    AgentToolCallDispatchReportStatus.blocked =>
      AgentCodingToolLoopRuntimeStatus.blocked,
    AgentToolCallDispatchReportStatus.failed =>
      AgentCodingToolLoopRuntimeStatus.failed,
    AgentToolCallDispatchReportStatus.dispatched =>
      AgentCodingToolLoopRuntimeStatus.dispatched,
    AgentToolCallDispatchReportStatus.complete =>
      AgentCodingToolLoopRuntimeStatus.complete,
  };
}
