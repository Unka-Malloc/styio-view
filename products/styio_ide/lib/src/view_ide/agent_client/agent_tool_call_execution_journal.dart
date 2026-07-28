import 'dart:convert';

import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_call_execution_plan.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_permission.dart';

enum AgentToolCallExecutionJournalStatus {
  idle,
  running,
  blocked,
  failed,
  complete,
}

enum AgentToolCallReplayPlanStatus { empty, ready, blocked }

extension AgentToolCallReplayPlanStatusX on AgentToolCallReplayPlanStatus {
  String get wireValue => switch (this) {
    AgentToolCallReplayPlanStatus.empty => 'empty',
    AgentToolCallReplayPlanStatus.ready => 'ready',
    AgentToolCallReplayPlanStatus.blocked => 'blocked',
  };
}

enum AgentToolCallReplayReportStatus { blocked, replayed, failed }

extension AgentToolCallReplayReportStatusX on AgentToolCallReplayReportStatus {
  String get wireValue => switch (this) {
    AgentToolCallReplayReportStatus.blocked => 'blocked',
    AgentToolCallReplayReportStatus.replayed => 'replayed',
    AgentToolCallReplayReportStatus.failed => 'failed',
  };
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
    this.executionStatus = '',
    this.permissionStatus = '',
    this.reviewDecisionStatus = '',
    this.executionIssueCodes = const <String>[],
    this.blockingIssueCodes = const <String>[],
    this.eventCount = 0,
    this.metadata = const <String, Object?>{},
  });

  factory AgentToolCallExecutionJournalEntry.fromState({
    required AgentToolCallState state,
    AgentToolCallDispatchResult? dispatchResult,
    AgentToolCallExecution? execution,
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
          : _sample(
              dispatchResult.output.isEmpty
                  ? dispatchResult.message
                  : dispatchResult.output,
            ),
      errorMessage: dispatchResult == null || successResult
          ? state.errorMessage
          : dispatchResult.message,
      permissionReason: state.permissionReason,
      executionStatus: execution?.status.wireValue ?? '',
      permissionStatus: execution?.permissionStatus?.wireValue ?? '',
      reviewDecisionStatus: execution?.reviewDecisionStatus?.wireValue ?? '',
      executionIssueCodes: execution?.issueCodes ?? const <String>[],
      blockingIssueCodes:
          execution?.issues
              .where((issue) => issue.blocking)
              .map((issue) => issue.code)
              .toList(growable: false) ??
          const <String>[],
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
  final String executionStatus;
  final String permissionStatus;
  final String reviewDecisionStatus;
  final List<String> executionIssueCodes;
  final List<String> blockingIssueCodes;
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
        ..._executionEvidenceMetadata(),
        'replayedFromJournal': true,
      },
    );
  }

  Map<String, Object?> toJson() {
    final redactedInputText = _redactAgentToolJournalText(inputText);
    final redactedResultSample = _redactAgentToolJournalText(resultSample);
    final redactedMetadata = _redactAgentToolJournalData(metadata);
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      'terminal': terminal,
      'inputComplete': inputComplete,
      'hasDispatchInput': hasDispatchInput,
      'replayCandidate': replayCandidate,
      'inputLength': inputText.length,
      if (inputText.isNotEmpty) 'inputText': redactedInputText,
      if (resultSample.isNotEmpty) 'resultSample': redactedResultSample,
      if (errorMessage.isNotEmpty)
        'errorMessage': _redactAgentToolJournalText(errorMessage),
      if (permissionReason.isNotEmpty)
        'permissionReason': _redactAgentToolJournalText(permissionReason),
      if (executionStatus.isNotEmpty) 'executionStatus': executionStatus,
      if (permissionStatus.isNotEmpty) 'permissionStatus': permissionStatus,
      if (reviewDecisionStatus.isNotEmpty)
        'reviewDecisionStatus': reviewDecisionStatus,
      if (executionIssueCodes.isNotEmpty)
        'executionIssueCodes': executionIssueCodes,
      if (blockingIssueCodes.isNotEmpty)
        'blockingIssueCodes': blockingIssueCodes,
      'eventCount': eventCount,
      if (redactedMetadata.isNotEmpty) 'metadata': redactedMetadata,
    };
  }

  Map<String, Object?> _executionEvidenceMetadata() {
    return <String, Object?>{
      if (executionStatus.isNotEmpty) 'journalExecutionStatus': executionStatus,
      if (permissionStatus.isNotEmpty)
        'journalPermissionStatus': permissionStatus,
      if (reviewDecisionStatus.isNotEmpty)
        'journalReviewDecisionStatus': reviewDecisionStatus,
      if (executionIssueCodes.isNotEmpty)
        'journalExecutionIssueCodes': executionIssueCodes,
      if (blockingIssueCodes.isNotEmpty)
        'journalBlockingIssueCodes': blockingIssueCodes,
    };
  }
}

class AgentToolCallExecutionJournal {
  const AgentToolCallExecutionJournal({
    required this.status,
    required this.entries,
    this.sourceEventCount = 0,
    this.todoItems = const <String>[],
  });

  factory AgentToolCallExecutionJournal.fromTimeline({
    required AgentToolCallTimeline timeline,
    AgentToolCallDispatchReport? dispatchReport,
    AgentToolCallExecutionPlan? executionPlan,
    int? sourceEventCount,
  }) {
    final resultByCallId = <String, AgentToolCallDispatchResult>{
      for (final result
          in dispatchReport?.results ?? const <AgentToolCallDispatchResult>[])
        result.callId: result,
    };
    final executionByCallId = <String, AgentToolCallExecution>{
      for (final execution
          in executionPlan?.executions ?? const <AgentToolCallExecution>[])
        execution.callId: execution,
    };
    final entries = <AgentToolCallExecutionJournalEntry>[
      for (final call in timeline.calls)
        AgentToolCallExecutionJournalEntry.fromState(
          state: call,
          dispatchResult: resultByCallId[call.callId],
          execution: executionByCallId[call.callId],
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

class AgentToolCallReplayIssue {
  const AgentToolCallReplayIssue({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{'code': code, 'message': message};
  }
}

class AgentToolCallReplayPlan {
  const AgentToolCallReplayPlan({
    required this.status,
    required this.requests,
    this.includeCompleted = false,
    this.requiresUserConfirmation = true,
    this.issues = const <AgentToolCallReplayIssue>[],
    this.todoItems = const <String>[],
  });

  factory AgentToolCallReplayPlan.fromJournal(
    AgentToolCallExecutionJournal journal, {
    bool includeCompleted = false,
  }) {
    if (journal.entries.isEmpty) {
      return const AgentToolCallReplayPlan(
        status: AgentToolCallReplayPlanStatus.empty,
        requests: <AgentToolCallDispatchRequest>[],
        requiresUserConfirmation: false,
        issues: <AgentToolCallReplayIssue>[
          AgentToolCallReplayIssue(
            code: 'agent.tool.replay.emptyJournal',
            message: 'No tool execution journal entries are available.',
          ),
        ],
      );
    }
    final requests = journal.replayRequests(includeCompleted: includeCompleted);
    if (requests.isEmpty) {
      return AgentToolCallReplayPlan(
        status: AgentToolCallReplayPlanStatus.blocked,
        requests: const <AgentToolCallDispatchRequest>[],
        includeCompleted: includeCompleted,
        requiresUserConfirmation: false,
        issues: const <AgentToolCallReplayIssue>[
          AgentToolCallReplayIssue(
            code: 'agent.tool.replay.noReplayableInputs',
            message:
                'No journal entries have dispatch input eligible for replay.',
          ),
        ],
      );
    }
    return AgentToolCallReplayPlan(
      status: AgentToolCallReplayPlanStatus.ready,
      requests: List<AgentToolCallDispatchRequest>.unmodifiable(requests),
      includeCompleted: includeCompleted,
    );
  }

  final AgentToolCallReplayPlanStatus status;
  final List<AgentToolCallDispatchRequest> requests;
  final bool includeCompleted;
  final bool requiresUserConfirmation;
  final List<AgentToolCallReplayIssue> issues;
  final List<String> todoItems;

  bool get ready =>
      status == AgentToolCallReplayPlanStatus.ready && requests.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'includeCompleted': includeCompleted,
      'requiresUserConfirmation': requiresUserConfirmation,
      'requestCount': requests.length,
      'requests': requests
          .map((request) => request.toJson())
          .toList(growable: false),
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
      if (todoItems.isNotEmpty) 'todoItems': todoItems,
    };
  }
}

class AgentToolCallReplayReport {
  const AgentToolCallReplayReport({
    required this.status,
    required this.plan,
    this.results = const <AgentToolCallDispatchResult>[],
    this.events = const <AgentToolCallEvent>[],
  });

  factory AgentToolCallReplayReport.fromResults({
    required AgentToolCallReplayPlan plan,
    required List<AgentToolCallDispatchResult> results,
    required List<AgentToolCallEvent> events,
  }) {
    return AgentToolCallReplayReport(
      status: results.every((result) => result.success)
          ? AgentToolCallReplayReportStatus.replayed
          : AgentToolCallReplayReportStatus.failed,
      plan: plan,
      results: List<AgentToolCallDispatchResult>.unmodifiable(results),
      events: List<AgentToolCallEvent>.unmodifiable(events),
    );
  }

  final AgentToolCallReplayReportStatus status;
  final AgentToolCallReplayPlan plan;
  final List<AgentToolCallDispatchResult> results;
  final List<AgentToolCallEvent> events;

  bool get replayed => status == AgentToolCallReplayReportStatus.replayed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'replayed': replayed,
      'plan': plan.toJson(),
      'results': results.map((result) => result.toJson()).toList(),
      'eventCount': events.length,
    };
  }
}

AgentToolCallExecutionJournalStatus _journalStatus(
  AgentToolCallTimelineStatus status,
) {
  return switch (status) {
    AgentToolCallTimelineStatus.idle =>
      AgentToolCallExecutionJournalStatus.idle,
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

const _agentToolJournalRedacted = '[redacted]';

final _sensitiveJournalKeyWords = <String>{
  'authorization',
  'bearer',
  'credential',
  'credentials',
  'password',
  'passwd',
  'token',
  'apikey',
  'secret',
  'privatekey',
  'accesskey',
  'refreshtoken',
};

bool _isSensitiveAgentToolJournalKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (_sensitiveJournalKeyWords.contains(normalized)) {
    return true;
  }
  return _sensitiveJournalKeyWords.any(
    (word) =>
        normalized.endsWith(word) ||
        (word == 'secret' && normalized.contains(word)),
  );
}

Map<String, Object?> _redactAgentToolJournalData(
  Map<String, Object?> metadata,
) {
  return <String, Object?>{
    for (final entry in metadata.entries)
      entry.key: _redactAgentToolJournalValue(
        entry.value,
        parentKey: entry.key,
      ),
  };
}

Object? _redactAgentToolJournalValue(Object? value, {String? parentKey}) {
  if (parentKey != null && _isSensitiveAgentToolJournalKey(parentKey)) {
    return _agentToolJournalRedacted;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _redactAgentToolJournalValue(
          entry.value,
          parentKey: entry.key.toString(),
        ),
    };
  }
  if (value is Iterable) {
    return value
        .map((item) => _redactAgentToolJournalValue(item))
        .toList(growable: false);
  }
  if (value is String) {
    return _redactAgentToolJournalText(value);
  }
  return value;
}

String _redactAgentToolJournalText(String value) {
  if (value.isEmpty) {
    return value;
  }
  try {
    final decoded = jsonDecode(value);
    return jsonEncode(_redactAgentToolJournalValue(decoded));
  } on FormatException {
    return _redactAgentToolJournalFreeText(value);
  }
}

String _redactAgentToolJournalFreeText(String value) {
  var redacted = value.replaceAllMapped(
    RegExp(r'(Authorization\s*:\s*Bearer\s+)[^\r\n,;]+', caseSensitive: false),
    (match) => '${match.group(1)}$_agentToolJournalRedacted',
  );
  redacted = redacted.replaceAll(
    RegExp(r'Bearer\s+[^\s,;}\]]+', caseSensitive: false),
    'Bearer $_agentToolJournalRedacted',
  );
  redacted = redacted.replaceAllMapped(
    RegExp(
      r'\b((?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|password|passwd|secret|credential|private[_-]?key|access[_-]?key)\b\s*[:=]\s*)("[^"]*"|[^\s,;}\]]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$_agentToolJournalRedacted',
  );
  return redacted;
}
