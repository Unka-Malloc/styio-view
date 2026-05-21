import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_call_lifecycle.dart';

enum AgentToolCallExecutionJournalStatus {
  idle,
  running,
  blocked,
  failed,
  complete,
}

extension AgentToolCallExecutionJournalStatusX
    on AgentToolCallExecutionJournalStatus {
  String get wireValue => switch (this) {
    AgentToolCallExecutionJournalStatus.idle => 'idle',
    AgentToolCallExecutionJournalStatus.running => 'running',
    AgentToolCallExecutionJournalStatus.blocked => 'blocked',
    AgentToolCallExecutionJournalStatus.failed => 'failed',
    AgentToolCallExecutionJournalStatus.complete => 'complete',
  };
}

class AgentToolCallExecutionJournalEntry {
  const AgentToolCallExecutionJournalEntry({
    required this.callId,
    required this.toolId,
    required this.status,
    required this.inputComplete,
    this.inputText = '',
    this.resultSample = '',
    this.errorMessage = '',
    this.permissionReason = '',
    this.eventCount = 0,
    this.metadata = const <String, Object?>{},
  });

  factory AgentToolCallExecutionJournalEntry.fromState({
    required AgentToolCallState state,
    AgentToolCallDispatchResult? dispatchResult,
  }) {
    final successResult = dispatchResult?.success == true;
    return AgentToolCallExecutionJournalEntry(
      callId: state.callId,
      toolId: state.toolId,
      status: state.status,
      inputComplete: state.inputComplete,
      inputText: state.inputText,
      resultSample: dispatchResult == null || !successResult
          ? state.resultSample
          : _sample(dispatchResult.output.isEmpty
                ? dispatchResult.message
                : dispatchResult.output),
      errorMessage: dispatchResult == null || successResult
          ? state.errorMessage
          : dispatchResult.message,
      permissionReason: state.permissionReason,
      eventCount: state.eventCount,
      metadata: <String, Object?>{
        ...state.metadata,
        if (dispatchResult != null) 'dispatchResult': dispatchResult.toJson(),
      },
    );
  }

  final String callId;
  final String toolId;
  final AgentToolCallStatus status;
  final bool inputComplete;
  final String inputText;
  final String resultSample;
  final String errorMessage;
  final String permissionReason;
  final int eventCount;
  final Map<String, Object?> metadata;

  bool get hasDispatchInput => toolId.trim().isNotEmpty && inputComplete;
  bool get terminal =>
      status == AgentToolCallStatus.completed ||
      status == AgentToolCallStatus.failed ||
      status == AgentToolCallStatus.permissionBlocked;
  bool get replayCandidate =>
      hasDispatchInput &&
      status != AgentToolCallStatus.completed &&
      status != AgentToolCallStatus.permissionBlocked;

  AgentToolCallDispatchRequest toReplayRequest() {
    return AgentToolCallDispatchRequest(
      callId: callId,
      toolId: toolId,
      inputText: inputText.isEmpty ? '{}' : inputText,
      metadata: <String, Object?>{
        ...metadata,
        'replayedFromJournal': true,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      'terminal': terminal,
      'inputComplete': inputComplete,
      'hasDispatchInput': hasDispatchInput,
      'replayCandidate': replayCandidate,
      'inputLength': inputText.length,
      if (inputText.isNotEmpty) 'inputText': inputText,
      if (resultSample.isNotEmpty) 'resultSample': resultSample,
      if (errorMessage.isNotEmpty) 'errorMessage': errorMessage,
      if (permissionReason.isNotEmpty) 'permissionReason': permissionReason,
      'eventCount': eventCount,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'TODO':
          'Redact sensitive tool input fields before this journal is persisted beyond the workspace recovery store.',
    };
  }
}

class AgentToolCallExecutionJournal {
  const AgentToolCallExecutionJournal({
    required this.status,
    required this.entries,
    this.sourceEventCount = 0,
    this.todoItems = const <String>[
      'TODO: persist this journal through AgentCodingSessionHistoryStore so interrupted tool chains can be resumed after reload.',
    ],
  });

  factory AgentToolCallExecutionJournal.fromTimeline({
    required AgentToolCallTimeline timeline,
    AgentToolCallDispatchReport? dispatchReport,
    int? sourceEventCount,
  }) {
    final resultByCallId = <String, AgentToolCallDispatchResult>{
      for (final result
          in dispatchReport?.results ?? const <AgentToolCallDispatchResult>[])
        result.callId: result,
    };
    final entries = <AgentToolCallExecutionJournalEntry>[
      for (final call in timeline.calls)
        AgentToolCallExecutionJournalEntry.fromState(
          state: call,
          dispatchResult: resultByCallId[call.callId],
        ),
    ];
    return AgentToolCallExecutionJournal(
      status: _journalStatus(timeline.status),
      entries: List<AgentToolCallExecutionJournalEntry>.unmodifiable(entries),
      sourceEventCount:
          sourceEventCount ??
          entries.fold<int>(0, (sum, entry) => sum + entry.eventCount),
    );
  }

  final AgentToolCallExecutionJournalStatus status;
  final List<AgentToolCallExecutionJournalEntry> entries;
  final int sourceEventCount;
  final List<String> todoItems;

  List<AgentToolCallExecutionJournalEntry> get replayCandidates {
    return entries
        .where((entry) => entry.replayCandidate)
        .toList(growable: false);
  }

  List<AgentToolCallDispatchRequest> replayRequests({
    bool includeCompleted = false,
  }) {
    return entries
        .where(
          (entry) =>
              entry.hasDispatchInput &&
              (includeCompleted || entry.replayCandidate),
        )
        .map((entry) => entry.toReplayRequest())
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'entryCount': entries.length,
      'sourceEventCount': sourceEventCount,
      'replayCandidateCount': replayCandidates.length,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'todoItems': todoItems,
    };
  }
}

AgentToolCallExecutionJournalStatus _journalStatus(
  AgentToolCallTimelineStatus status,
) {
  return switch (status) {
    AgentToolCallTimelineStatus.idle => AgentToolCallExecutionJournalStatus.idle,
    AgentToolCallTimelineStatus.running =>
      AgentToolCallExecutionJournalStatus.running,
    AgentToolCallTimelineStatus.blocked =>
      AgentToolCallExecutionJournalStatus.blocked,
    AgentToolCallTimelineStatus.failed =>
      AgentToolCallExecutionJournalStatus.failed,
    AgentToolCallTimelineStatus.complete =>
      AgentToolCallExecutionJournalStatus.complete,
  };
}

String _sample(String value, {int maxLength = 20000}) {
  if (value.length <= maxLength) {
    return value;
  }
  return value.substring(0, maxLength);
}
