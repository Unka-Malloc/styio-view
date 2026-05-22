enum AgentCodingLoopGuardStatus { clear, attention, blocked }

extension AgentCodingLoopGuardStatusX on AgentCodingLoopGuardStatus {
  String get wireValue => switch (this) {
    AgentCodingLoopGuardStatus.clear => 'clear',
    AgentCodingLoopGuardStatus.attention => 'attention',
    AgentCodingLoopGuardStatus.blocked => 'blocked',
  };
}

class AgentCodingLoopGuard {
  const AgentCodingLoopGuard({
    required this.status,
    this.toolReplayReportCount = 0,
    this.failedToolResultCount = 0,
    this.agentStepCount = 0,
    this.maxAgentSteps,
    this.activeAgentId = '',
    this.hasProviderFailure = false,
    this.requiresUserReview = false,
    this.attentionReasons = const <String>[],
    this.blockingReasons = const <String>[],
    this.todoItems = const <String>[],
  });

  const AgentCodingLoopGuard.clear()
    : status = AgentCodingLoopGuardStatus.clear,
      toolReplayReportCount = 0,
      failedToolResultCount = 0,
      agentStepCount = 0,
      maxAgentSteps = null,
      activeAgentId = '',
      hasProviderFailure = false,
      requiresUserReview = false,
      attentionReasons = const <String>[],
      blockingReasons = const <String>[],
      todoItems = const <String>[];

  factory AgentCodingLoopGuard.fromSignals({
    required int toolReplayReportCount,
    required int failedToolResultCount,
    required bool hasProviderFailure,
    int agentStepCount = 0,
    int? maxAgentSteps,
    String activeAgentId = '',
    int maxToolReplayReports = 3,
    int maxFailedToolResults = 3,
  }) {
    final blockingReasons = <String>[];
    if (maxAgentSteps != null && agentStepCount >= maxAgentSteps) {
      final agentScope = activeAgentId.trim().isEmpty
          ? 'active-agent'
          : activeAgentId.trim();
      blockingReasons.add(
        'agent.loop.maxSteps:$agentScope:$agentStepCount/$maxAgentSteps',
      );
    }
    if (toolReplayReportCount >= maxToolReplayReports) {
      blockingReasons.add(
        'agent.loop.replayReportLimit:$toolReplayReportCount',
      );
    }
    if (failedToolResultCount >= maxFailedToolResults) {
      blockingReasons.add(
        'agent.loop.failedToolResultLimit:$failedToolResultCount',
      );
    }
    if (blockingReasons.isNotEmpty) {
      return AgentCodingLoopGuard(
        status: AgentCodingLoopGuardStatus.blocked,
        toolReplayReportCount: toolReplayReportCount,
        failedToolResultCount: failedToolResultCount,
        agentStepCount: agentStepCount,
        maxAgentSteps: maxAgentSteps,
        activeAgentId: activeAgentId,
        hasProviderFailure: hasProviderFailure,
        requiresUserReview: true,
        blockingReasons: List<String>.unmodifiable(blockingReasons),
      );
    }
    if (toolReplayReportCount > 0 ||
        failedToolResultCount > 0 ||
        hasProviderFailure) {
      final attentionReasons = <String>[];
      if (toolReplayReportCount > 0) {
        attentionReasons.add(
          'agent.loop.replayReportObserved:$toolReplayReportCount',
        );
      }
      if (failedToolResultCount > 0) {
        attentionReasons.add(
          'agent.loop.failedToolResultObserved:$failedToolResultCount',
        );
      }
      if (hasProviderFailure) {
        attentionReasons.add('agent.loop.providerFailureObserved');
      }
      return AgentCodingLoopGuard(
        status: AgentCodingLoopGuardStatus.attention,
        toolReplayReportCount: toolReplayReportCount,
        failedToolResultCount: failedToolResultCount,
        agentStepCount: agentStepCount,
        maxAgentSteps: maxAgentSteps,
        activeAgentId: activeAgentId,
        hasProviderFailure: hasProviderFailure,
        attentionReasons: List<String>.unmodifiable(attentionReasons),
      );
    }
    return const AgentCodingLoopGuard.clear();
  }

  final AgentCodingLoopGuardStatus status;
  final int toolReplayReportCount;
  final int failedToolResultCount;
  final int agentStepCount;
  final int? maxAgentSteps;
  final String activeAgentId;
  final bool hasProviderFailure;
  final bool requiresUserReview;
  final List<String> attentionReasons;
  final List<String> blockingReasons;
  final List<String> todoItems;

  bool get blocked => status == AgentCodingLoopGuardStatus.blocked;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'blocked': blocked,
      'toolReplayReportCount': toolReplayReportCount,
      'failedToolResultCount': failedToolResultCount,
      'agentStepCount': agentStepCount,
      if (maxAgentSteps != null) 'maxAgentSteps': maxAgentSteps,
      if (activeAgentId.isNotEmpty) 'activeAgentId': activeAgentId,
      'hasProviderFailure': hasProviderFailure,
      'requiresUserReview': requiresUserReview,
      if (attentionReasons.isNotEmpty) 'attentionReasons': attentionReasons,
      if (blockingReasons.isNotEmpty) 'blockingReasons': blockingReasons,
      if (todoItems.isNotEmpty) 'todoItems': todoItems,
    };
  }
}
