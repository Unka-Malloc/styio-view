import 'agent_tool_call_execution_plan.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_call_result_context.dart';

enum AgentToolSessionPartStatus {
  waitingInput,
  reviewRequired,
  ready,
  running,
  blocked,
  completed,
  failed,
}

extension AgentToolSessionPartStatusX on AgentToolSessionPartStatus {
  String get wireValue => switch (this) {
    AgentToolSessionPartStatus.waitingInput => 'waiting_input',
    AgentToolSessionPartStatus.reviewRequired => 'review_required',
    AgentToolSessionPartStatus.ready => 'ready',
    AgentToolSessionPartStatus.running => 'running',
    AgentToolSessionPartStatus.blocked => 'blocked',
    AgentToolSessionPartStatus.completed => 'completed',
    AgentToolSessionPartStatus.failed => 'failed',
  };
}

class AgentToolSessionPart {
  const AgentToolSessionPart({
    required this.callId,
    required this.toolId,
    required this.status,
    this.inputText = '',
    this.output = '',
    this.message = '',
    this.issueCodes = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String callId;
  final String toolId;
  final AgentToolSessionPartStatus status;
  final String inputText;
  final String output;
  final String message;
  final List<String> issueCodes;
  final Map<String, Object?> metadata;

  bool get terminal =>
      status == AgentToolSessionPartStatus.completed ||
      status == AgentToolSessionPartStatus.failed ||
      status == AgentToolSessionPartStatus.blocked;

  bool get success => status == AgentToolSessionPartStatus.completed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      'terminal': terminal,
      'success': success,
      if (inputText.isNotEmpty) 'inputText': inputText,
      if (output.isNotEmpty) 'output': output,
      if (message.isNotEmpty) 'message': message,
      if (issueCodes.isNotEmpty) 'issueCodes': issueCodes,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentToolSessionTranscript {
  const AgentToolSessionTranscript({required this.status, required this.parts});

  factory AgentToolSessionTranscript.fromToolState({
    required AgentToolCallTimeline timeline,
    required AgentToolCallExecutionPlan executionPlan,
    Iterable<AgentToolCallResultContext> resultContexts =
        const <AgentToolCallResultContext>[],
  }) {
    final resultByCallId = <String, AgentToolCallResultContext>{};
    for (final result in resultContexts) {
      resultByCallId[result.callId] = result;
    }

    final parts = <AgentToolSessionPart>[];
    final seenCallIds = <String>{};
    for (final call in timeline.calls) {
      final result = resultByCallId[call.callId];
      final execution = executionPlan.executionFor(call.callId);
      parts.add(
        AgentToolSessionPart(
          callId: call.callId,
          toolId: call.toolId,
          status: _sessionPartStatus(
            call: call,
            execution: execution,
            result: result,
          ),
          inputText: call.inputText,
          output: result?.output ?? call.resultSample,
          message: _sessionPartMessage(call: call, result: result),
          issueCodes: execution?.issueCodes ?? const <String>[],
          metadata: <String, Object?>{
            ...call.metadata,
            if (result != null) 'toolResult': result.toJson(),
          },
        ),
      );
      seenCallIds.add(call.callId);
    }

    for (final result in resultContexts) {
      if (seenCallIds.contains(result.callId)) {
        continue;
      }
      parts.add(
        AgentToolSessionPart(
          callId: result.callId,
          toolId: result.toolId,
          status: result.success
              ? AgentToolSessionPartStatus.completed
              : AgentToolSessionPartStatus.failed,
          output: result.output,
          message: result.message,
          metadata: <String, Object?>{'toolResult': result.toJson()},
        ),
      );
    }

    return AgentToolSessionTranscript(
      status: _transcriptStatus(timeline, parts),
      parts: List<AgentToolSessionPart>.unmodifiable(parts),
    );
  }

  final AgentToolCallTimelineStatus status;
  final List<AgentToolSessionPart> parts;

  bool get hasTerminalParts {
    return parts.any((part) => part.terminal);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'partCount': parts.length,
      'hasTerminalParts': hasTerminalParts,
      'parts': parts.map((part) => part.toJson()).toList(growable: false),
    };
  }
}

AgentToolSessionPartStatus _sessionPartStatus({
  required AgentToolCallState call,
  required AgentToolCallExecution? execution,
  required AgentToolCallResultContext? result,
}) {
  if (result != null) {
    return result.success
        ? AgentToolSessionPartStatus.completed
        : AgentToolSessionPartStatus.failed;
  }
  final executionStatus = execution?.status;
  if (executionStatus == AgentToolCallExecutionStatus.reviewRequired) {
    return AgentToolSessionPartStatus.reviewRequired;
  }
  if (executionStatus == AgentToolCallExecutionStatus.blocked) {
    return AgentToolSessionPartStatus.blocked;
  }
  if (executionStatus == AgentToolCallExecutionStatus.failed) {
    return AgentToolSessionPartStatus.failed;
  }
  if (executionStatus == AgentToolCallExecutionStatus.ready) {
    return AgentToolSessionPartStatus.ready;
  }
  if (executionStatus == AgentToolCallExecutionStatus.waitingInput) {
    return AgentToolSessionPartStatus.waitingInput;
  }
  if (executionStatus == AgentToolCallExecutionStatus.completed) {
    return AgentToolSessionPartStatus.completed;
  }
  return switch (call.status) {
    AgentToolCallStatus.inputStreaming =>
      AgentToolSessionPartStatus.waitingInput,
    AgentToolCallStatus.inputReady => AgentToolSessionPartStatus.ready,
    AgentToolCallStatus.running => AgentToolSessionPartStatus.running,
    AgentToolCallStatus.permissionBlocked => AgentToolSessionPartStatus.blocked,
    AgentToolCallStatus.completed => AgentToolSessionPartStatus.completed,
    AgentToolCallStatus.failed => AgentToolSessionPartStatus.failed,
  };
}

String _sessionPartMessage({
  required AgentToolCallState call,
  required AgentToolCallResultContext? result,
}) {
  if (result != null) {
    return result.message;
  }
  if (call.errorMessage.isNotEmpty) {
    return call.errorMessage;
  }
  if (call.permissionReason.isNotEmpty) {
    return call.permissionReason;
  }
  return '';
}

AgentToolCallTimelineStatus _transcriptStatus(
  AgentToolCallTimeline timeline,
  List<AgentToolSessionPart> parts,
) {
  if (timeline.status != AgentToolCallTimelineStatus.idle || parts.isEmpty) {
    return timeline.status;
  }
  if (parts.every(
    (part) => part.status == AgentToolSessionPartStatus.completed,
  )) {
    return AgentToolCallTimelineStatus.complete;
  }
  if (parts.any((part) => part.status == AgentToolSessionPartStatus.failed)) {
    return AgentToolCallTimelineStatus.failed;
  }
  if (parts.any((part) => part.status == AgentToolSessionPartStatus.blocked)) {
    return AgentToolCallTimelineStatus.blocked;
  }
  if (parts.any((part) => !part.terminal)) {
    return AgentToolCallTimelineStatus.running;
  }
  return AgentToolCallTimelineStatus.idle;
}
