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
    this.hasProviderFailure = false,
    this.attentionReasons = const <String>[],
    this.blockingReasons = const <String>[],
    this.todoItems = const <String>[],
  });

  const AgentCodingLoopGuard.clear()
    : status = AgentCodingLoopGuardStatus.clear,
      toolReplayReportCount = 0,
      failedToolResultCount = 0,
      hasProviderFailure = false,
      attentionReasons = const <String>[],
      blockingReasons = const <String>[],
      todoItems = const <String>[];

  factory AgentCodingLoopGuard.fromSignals({
    required int toolReplayReportCount,
    required int failedToolResultCount,
    required bool hasProviderFailure,
    int maxToolReplayReports = 3,
    int maxFailedToolResults = 3,
  }) {
    final blockingReasons = <String>[];
    final todoItems = <String>[];
    if (toolReplayReportCount >= maxToolReplayReports) {
      blockingReasons.add(
        'agent.loop.replayReportLimit:$toolReplayReportCount',
      );
      todoItems.add(
        'TODO: require user review before continuing after repeated agent tool replay attempts.',
      );
    }
    if (failedToolResultCount >= maxFailedToolResults) {
      blockingReasons.add(
        'agent.loop.failedToolResultLimit:$failedToolResultCount',
      );
      todoItems.add(
        'TODO: require user review before continuing after repeated failed agent tool results.',
      );
    }
    if (blockingReasons.isNotEmpty) {
      return AgentCodingLoopGuard(
        status: AgentCodingLoopGuardStatus.blocked,
        toolReplayReportCount: toolReplayReportCount,
        failedToolResultCount: failedToolResultCount,
        hasProviderFailure: hasProviderFailure,
        blockingReasons: List<String>.unmodifiable(blockingReasons),
        todoItems: List<String>.unmodifiable(todoItems),
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
        hasProviderFailure: hasProviderFailure,
        attentionReasons: List<String>.unmodifiable(attentionReasons),
      );
    }
    return const AgentCodingLoopGuard.clear();
  }

  final AgentCodingLoopGuardStatus status;
  final int toolReplayReportCount;
  final int failedToolResultCount;
  final bool hasProviderFailure;
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
      'hasProviderFailure': hasProviderFailure,
      if (attentionReasons.isNotEmpty) 'attentionReasons': attentionReasons,
      if (blockingReasons.isNotEmpty) 'blockingReasons': blockingReasons,
      if (todoItems.isNotEmpty) 'todoItems': todoItems,
    };
  }
}
