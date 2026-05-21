import 'dart:async';

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

enum AgentCodingToolLoopContinuationStatus { dispatched, failed }

extension AgentCodingToolLoopContinuationStatusX
    on AgentCodingToolLoopContinuationStatus {
  String get wireValue => switch (this) {
    AgentCodingToolLoopContinuationStatus.dispatched => 'dispatched',
    AgentCodingToolLoopContinuationStatus.failed => 'failed',
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

class AgentCodingToolLoopContinuationRequest {
  const AgentCodingToolLoopContinuationRequest({
    required this.roundIndex,
    required this.dispatchReport,
    required this.executionPlan,
  });

  final int roundIndex;
  final AgentToolCallDispatchReport dispatchReport;
  final AgentToolCallExecutionPlan executionPlan;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'roundIndex': roundIndex,
      'dispatchReport': dispatchReport.toJson(),
      'executionPlan': executionPlan.toJson(),
    };
  }
}

class AgentCodingToolLoopContinuationResult {
  const AgentCodingToolLoopContinuationResult({
    required this.status,
    required this.message,
    this.metadata = const <String, Object?>{},
  });

  const AgentCodingToolLoopContinuationResult.dispatched({
    String message = 'Agent provider continuation dispatched.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: AgentCodingToolLoopContinuationStatus.dispatched,
         message: message,
         metadata: metadata,
       );

  const AgentCodingToolLoopContinuationResult.failure({
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: AgentCodingToolLoopContinuationStatus.failed,
         message: message,
         metadata: metadata,
       );

  final AgentCodingToolLoopContinuationStatus status;
  final String message;
  final Map<String, Object?> metadata;

  bool get failed => status == AgentCodingToolLoopContinuationStatus.failed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'failed': failed,
      'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

typedef AgentCodingToolLoopContinuation =
    FutureOr<AgentCodingToolLoopContinuationResult?> Function(
      AgentCodingToolLoopContinuationRequest request,
    );

class AgentCodingToolLoopRuntimeReport {
  const AgentCodingToolLoopRuntimeReport({
    required this.status,
    required this.maxDispatchRounds,
    required this.finalExecutionPlan,
    this.dispatchReports = const <AgentToolCallDispatchReport>[],
    this.continuationResults = const <AgentCodingToolLoopContinuationResult>[],
    this.stoppedByCondition = false,
  });

  final AgentCodingToolLoopRuntimeStatus status;
  final int maxDispatchRounds;
  final AgentToolCallExecutionPlan finalExecutionPlan;
  final List<AgentToolCallDispatchReport> dispatchReports;
  final List<AgentCodingToolLoopContinuationResult> continuationResults;
  final bool stoppedByCondition;

  int get dispatchRoundCount => dispatchReports.length;
  int get continuationCount => continuationResults.length;
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
      'continuationCount': continuationCount,
      'stoppedByCondition': stoppedByCondition,
      'finalExecutionPlan': finalExecutionPlan.toJson(),
      'dispatchReports': dispatchReports
          .map((report) => report.toJson())
          .toList(growable: false),
      'continuationResults': continuationResults
          .map((result) => result.toJson())
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
    AgentCodingToolLoopContinuation? continueAfterDispatch,
  }) async {
    final dispatchReports = <AgentToolCallDispatchReport>[];
    final continuationResults = <AgentCodingToolLoopContinuationResult>[];
    if (maxDispatchRounds <= 0) {
      return _report(
        status: AgentCodingToolLoopRuntimeStatus.limitReached,
        controller: controller,
        dispatchReports: dispatchReports,
        continuationResults: continuationResults,
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
          continuationResults: continuationResults,
          stoppedByCondition: true,
        );
      }

      final terminalStatus = _statusForExecutionPlan(plan.status);
      if (terminalStatus != null) {
        return _report(
          status: terminalStatus,
          controller: controller,
          dispatchReports: dispatchReports,
          continuationResults: continuationResults,
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
          continuationResults: continuationResults,
        );
      }
      final continuationFailed = await _continueAfterDispatch(
        continueAfterDispatch,
        roundIndex: dispatchReports.length - 1,
        dispatchReport: dispatchReport,
        executionPlan: controller.toolCallExecutionPlan,
        continuationResults: continuationResults,
      );
      if (continuationFailed) {
        return _report(
          status: AgentCodingToolLoopRuntimeStatus.failed,
          controller: controller,
          dispatchReports: dispatchReports,
          continuationResults: continuationResults,
        );
      }
      if (controller.toolCallExecutionPlan.status ==
          AgentToolCallExecutionPlanStatus.complete) {
        return _report(
          status: AgentCodingToolLoopRuntimeStatus.complete,
          controller: controller,
          dispatchReports: dispatchReports,
          continuationResults: continuationResults,
        );
      }
    }

    return _report(
      status: AgentCodingToolLoopRuntimeStatus.limitReached,
      controller: controller,
      dispatchReports: dispatchReports,
      continuationResults: continuationResults,
    );
  }

  Future<bool> _continueAfterDispatch(
    AgentCodingToolLoopContinuation? continueAfterDispatch, {
    required int roundIndex,
    required AgentToolCallDispatchReport dispatchReport,
    required AgentToolCallExecutionPlan executionPlan,
    required List<AgentCodingToolLoopContinuationResult> continuationResults,
  }) async {
    if (continueAfterDispatch == null) {
      return false;
    }
    try {
      final result = await Future<AgentCodingToolLoopContinuationResult?>.value(
        continueAfterDispatch(
          AgentCodingToolLoopContinuationRequest(
            roundIndex: roundIndex,
            dispatchReport: dispatchReport,
            executionPlan: executionPlan,
          ),
        ),
      );
      if (result == null) {
        return false;
      }
      continuationResults.add(result);
      return result.failed;
    } on Object catch (error) {
      continuationResults.add(
        AgentCodingToolLoopContinuationResult.failure(
          message: 'Agent provider continuation failed: $error',
        ),
      );
      return true;
    }
  }

  AgentCodingToolLoopRuntimeReport _report({
    required AgentCodingToolLoopRuntimeStatus status,
    required AgentCodingSessionController controller,
    required List<AgentToolCallDispatchReport> dispatchReports,
    required List<AgentCodingToolLoopContinuationResult> continuationResults,
    bool stoppedByCondition = false,
  }) {
    return AgentCodingToolLoopRuntimeReport(
      status: status,
      maxDispatchRounds: maxDispatchRounds,
      finalExecutionPlan: controller.toolCallExecutionPlan,
      dispatchReports: List<AgentToolCallDispatchReport>.unmodifiable(
        dispatchReports,
      ),
      continuationResults:
          List<AgentCodingToolLoopContinuationResult>.unmodifiable(
            continuationResults,
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
