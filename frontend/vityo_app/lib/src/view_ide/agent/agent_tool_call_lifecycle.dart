import 'dart:convert';

enum AgentToolCallEventKind {
  inputStart,
  inputDelta,
  inputEnd,
  callStarted,
  permissionBlocked,
  result,
  error,
}

extension AgentToolCallEventKindX on AgentToolCallEventKind {
  String get wireValue => switch (this) {
    AgentToolCallEventKind.inputStart => 'input_start',
    AgentToolCallEventKind.inputDelta => 'input_delta',
    AgentToolCallEventKind.inputEnd => 'input_end',
    AgentToolCallEventKind.callStarted => 'call_started',
    AgentToolCallEventKind.permissionBlocked => 'permission_blocked',
    AgentToolCallEventKind.result => 'result',
    AgentToolCallEventKind.error => 'error',
  };
}

enum AgentToolCallStatus {
  inputStreaming,
  inputReady,
  running,
  permissionBlocked,
  completed,
  failed,
}

extension AgentToolCallStatusX on AgentToolCallStatus {
  String get wireValue => switch (this) {
    AgentToolCallStatus.inputStreaming => 'input_streaming',
    AgentToolCallStatus.inputReady => 'input_ready',
    AgentToolCallStatus.running => 'running',
    AgentToolCallStatus.permissionBlocked => 'permission_blocked',
    AgentToolCallStatus.completed => 'completed',
    AgentToolCallStatus.failed => 'failed',
  };
}

enum AgentToolCallTimelineStatus { idle, running, blocked, failed, complete }

extension AgentToolCallTimelineStatusX on AgentToolCallTimelineStatus {
  String get wireValue => switch (this) {
    AgentToolCallTimelineStatus.idle => 'idle',
    AgentToolCallTimelineStatus.running => 'running',
    AgentToolCallTimelineStatus.blocked => 'blocked',
    AgentToolCallTimelineStatus.failed => 'failed',
    AgentToolCallTimelineStatus.complete => 'complete',
  };
}

class AgentToolCallEvent {
  const AgentToolCallEvent({
    required this.kind,
    required this.callId,
    this.toolId = '',
    this.inputDelta = '',
    this.input = '',
    this.result = '',
    this.errorMessage = '',
    this.permissionReason = '',
    this.emittedAt,
    this.metadata = const <String, Object?>{},
  });

  const AgentToolCallEvent.inputStart({
    required String callId,
    required String toolId,
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.inputStart,
         callId: callId,
         toolId: toolId,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  const AgentToolCallEvent.inputDelta({
    required String callId,
    required String inputDelta,
    String toolId = '',
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.inputDelta,
         callId: callId,
         toolId: toolId,
         inputDelta: inputDelta,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  const AgentToolCallEvent.inputEnd({
    required String callId,
    String toolId = '',
    String input = '',
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.inputEnd,
         callId: callId,
         toolId: toolId,
         input: input,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  const AgentToolCallEvent.callStarted({
    required String callId,
    required String toolId,
    String input = '',
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.callStarted,
         callId: callId,
         toolId: toolId,
         input: input,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  const AgentToolCallEvent.permissionBlocked({
    required String callId,
    required String toolId,
    required String permissionReason,
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.permissionBlocked,
         callId: callId,
         toolId: toolId,
         permissionReason: permissionReason,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  const AgentToolCallEvent.result({
    required String callId,
    required String toolId,
    required String result,
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.result,
         callId: callId,
         toolId: toolId,
         result: result,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  const AgentToolCallEvent.error({
    required String callId,
    required String toolId,
    required String errorMessage,
    DateTime? emittedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         kind: AgentToolCallEventKind.error,
         callId: callId,
         toolId: toolId,
         errorMessage: errorMessage,
         emittedAt: emittedAt,
         metadata: metadata,
       );

  final AgentToolCallEventKind kind;
  final String callId;
  final String toolId;
  final String inputDelta;
  final String input;
  final String result;
  final String errorMessage;
  final String permissionReason;
  final DateTime? emittedAt;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'callId': callId,
      if (toolId.isNotEmpty) 'toolId': toolId,
      if (inputDelta.isNotEmpty) 'inputDeltaLength': inputDelta.length,
      if (input.isNotEmpty) 'inputLength': input.length,
      if (result.isNotEmpty) 'resultLength': result.length,
      if (errorMessage.isNotEmpty) 'errorMessage': errorMessage,
      if (permissionReason.isNotEmpty) 'permissionReason': permissionReason,
      if (emittedAt != null) 'emittedAt': emittedAt!.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentToolCallState {
  const AgentToolCallState({
    required this.callId,
    required this.toolId,
    required this.status,
    this.inputText = '',
    this.inputComplete = false,
    this.resultSample = '',
    this.errorMessage = '',
    this.permissionReason = '',
    this.startedAt,
    this.updatedAt,
    this.eventCount = 0,
    this.metadata = const <String, Object?>{},
  });

  final String callId;
  final String toolId;
  final AgentToolCallStatus status;
  final String inputText;
  final bool inputComplete;
  final String resultSample;
  final String errorMessage;
  final String permissionReason;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final int eventCount;
  final Map<String, Object?> metadata;

  bool get terminal =>
      status == AgentToolCallStatus.completed ||
      status == AgentToolCallStatus.failed ||
      status == AgentToolCallStatus.permissionBlocked;

  bool get blocked => status == AgentToolCallStatus.permissionBlocked;

  String get progressLabel {
    return _metadataString(metadata, const <String>[
      'progressLabel',
      'toolProgressLabel',
      'progress.label',
    ]);
  }

  num? get progressCurrent {
    return _metadataNumber(metadata, const <String>[
      'progressCurrent',
      'toolProgressCurrent',
      'progress.current',
    ]);
  }

  num? get progressTotal {
    return _metadataNumber(metadata, const <String>[
      'progressTotal',
      'toolProgressTotal',
      'progress.total',
    ]);
  }

  String get progressUnit {
    return _metadataString(metadata, const <String>[
      'progressUnit',
      'toolProgressUnit',
      'progress.unit',
    ]);
  }

  String get progressSummary {
    final label = progressLabel;
    final current = progressCurrent;
    final total = progressTotal;
    final unit = progressUnit;
    final parts = <String>[];
    if (label.isNotEmpty) {
      parts.add(label);
    }
    if (current != null && total != null) {
      parts.add(
        '${_formatNumber(current)}/${_formatNumber(total)}'
        '${unit.isEmpty ? '' : ' $unit'}',
      );
    } else if (current != null) {
      parts.add('${_formatNumber(current)}${unit.isEmpty ? '' : ' $unit'}');
    }
    return parts.join(' · ');
  }

  String get richErrorDetails {
    return _metadataText(metadata, const <String>[
      'richErrorDetails',
      'errorDetails',
      'error.details',
      'error.detail',
    ]);
  }

  AgentToolCallState copyWith({
    String? toolId,
    AgentToolCallStatus? status,
    String? inputText,
    bool? inputComplete,
    String? resultSample,
    String? errorMessage,
    String? permissionReason,
    DateTime? startedAt,
    DateTime? updatedAt,
    int? eventCount,
    Map<String, Object?>? metadata,
  }) {
    return AgentToolCallState(
      callId: callId,
      toolId: toolId ?? this.toolId,
      status: status ?? this.status,
      inputText: inputText ?? this.inputText,
      inputComplete: inputComplete ?? this.inputComplete,
      resultSample: resultSample ?? this.resultSample,
      errorMessage: errorMessage ?? this.errorMessage,
      permissionReason: permissionReason ?? this.permissionReason,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      eventCount: eventCount ?? this.eventCount,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      'terminal': terminal,
      'inputComplete': inputComplete,
      'inputLength': inputText.length,
      'eventCount': eventCount,
      if (resultSample.isNotEmpty) 'resultSample': resultSample,
      if (errorMessage.isNotEmpty) 'errorMessage': errorMessage,
      if (progressSummary.isNotEmpty) 'progressSummary': progressSummary,
      if (richErrorDetails.isNotEmpty) 'richErrorDetails': richErrorDetails,
      if (permissionReason.isNotEmpty) 'permissionReason': permissionReason,
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentToolCallTimeline {
  const AgentToolCallTimeline({
    required this.status,
    required this.calls,
    this.todoItems = const <String>[],
  });

  factory AgentToolCallTimeline.empty() {
    return const AgentToolCallTimeline(
      status: AgentToolCallTimelineStatus.idle,
      calls: <AgentToolCallState>[],
      todoItems: <String>[],
    );
  }

  final AgentToolCallTimelineStatus status;
  final List<AgentToolCallState> calls;
  final List<String> todoItems;

  List<String> get callIds {
    return calls.map((call) => call.callId).toList(growable: false);
  }

  List<String> get blockedCallIds {
    return calls
        .where((call) => call.blocked)
        .map((call) => call.callId)
        .toList(growable: false);
  }

  AgentToolCallState? callFor(String callId) {
    for (final call in calls) {
      if (call.callId == callId) {
        return call;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'callCount': calls.length,
      'callIds': callIds,
      'blockedCallIds': blockedCallIds,
      'calls': calls.map((call) => call.toJson()).toList(growable: false),
      if (todoItems.isNotEmpty) 'todoItems': todoItems,
    };
  }
}

class AgentToolCallLifecycleTracker {
  const AgentToolCallLifecycleTracker({
    this.maxInputLength = 20000,
    this.maxResultSampleLength = 20000,
  });

  final int maxInputLength;
  final int maxResultSampleLength;

  AgentToolCallTimeline track(Iterable<AgentToolCallEvent> events) {
    var timeline = AgentToolCallTimeline.empty();
    for (final event in events) {
      timeline = apply(timeline, event);
    }
    return timeline;
  }

  AgentToolCallTimeline apply(
    AgentToolCallTimeline timeline,
    AgentToolCallEvent event,
  ) {
    if (event.callId.trim().isEmpty) {
      return timeline;
    }
    final callsById = <String, AgentToolCallState>{
      for (final call in timeline.calls) call.callId: call,
    };
    final previous = callsById[event.callId];
    callsById[event.callId] = _nextState(previous, event);
    final previousOrder = timeline.callIds;
    final calls = <AgentToolCallState>[
      for (final callId in previousOrder)
        if (callsById.containsKey(callId)) callsById[callId]!,
      for (final entry in callsById.entries)
        if (!previousOrder.contains(entry.key)) entry.value,
    ];
    return AgentToolCallTimeline(
      status: _timelineStatus(calls),
      calls: List<AgentToolCallState>.unmodifiable(calls),
      todoItems: const <String>[],
    );
  }

  AgentToolCallState _nextState(
    AgentToolCallState? previous,
    AgentToolCallEvent event,
  ) {
    final timestamp = event.emittedAt;
    final toolId = event.toolId.isNotEmpty
        ? event.toolId
        : previous?.toolId ?? '';
    final eventCount = (previous?.eventCount ?? 0) + 1;
    final startedAt = previous?.startedAt ?? timestamp;
    final metadata = <String, Object?>{
      ...?previous?.metadata,
      ...event.metadata,
    };

    switch (event.kind) {
      case AgentToolCallEventKind.inputStart:
        return AgentToolCallState(
          callId: event.callId,
          toolId: toolId,
          status: AgentToolCallStatus.inputStreaming,
          startedAt: startedAt,
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
      case AgentToolCallEventKind.inputDelta:
        return (previous ?? _seedState(event, toolId)).copyWith(
          toolId: toolId,
          status: AgentToolCallStatus.inputStreaming,
          inputText: _appendTruncated(
            previous?.inputText ?? '',
            event.inputDelta,
            maxInputLength,
          ),
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
      case AgentToolCallEventKind.inputEnd:
        return (previous ?? _seedState(event, toolId)).copyWith(
          toolId: toolId,
          status: AgentToolCallStatus.inputReady,
          inputText: event.input.isNotEmpty
              ? _truncate(event.input, maxInputLength)
              : previous?.inputText,
          inputComplete: true,
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
      case AgentToolCallEventKind.callStarted:
        return (previous ?? _seedState(event, toolId)).copyWith(
          toolId: toolId,
          status: AgentToolCallStatus.running,
          inputText: event.input.isNotEmpty
              ? _truncate(event.input, maxInputLength)
              : previous?.inputText,
          inputComplete:
              event.input.isNotEmpty || (previous?.inputComplete ?? false),
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
      case AgentToolCallEventKind.permissionBlocked:
        return (previous ?? _seedState(event, toolId)).copyWith(
          toolId: toolId,
          status: AgentToolCallStatus.permissionBlocked,
          permissionReason: event.permissionReason,
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
      case AgentToolCallEventKind.result:
        return (previous ?? _seedState(event, toolId)).copyWith(
          toolId: toolId,
          status: AgentToolCallStatus.completed,
          resultSample: _truncate(event.result, maxResultSampleLength),
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
      case AgentToolCallEventKind.error:
        return (previous ?? _seedState(event, toolId)).copyWith(
          toolId: toolId,
          status: AgentToolCallStatus.failed,
          errorMessage: event.errorMessage,
          updatedAt: timestamp,
          eventCount: eventCount,
          metadata: metadata,
        );
    }
  }
}

String _metadataString(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = _metadataLookup(metadata, key);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

num? _metadataNumber(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = _metadataLookup(metadata, key);
    if (value is num) {
      return value;
    }
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

String _metadataText(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = _metadataLookup(metadata, key);
    if (value == null) {
      continue;
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is Map || value is List) {
      try {
        return jsonEncode(value);
      } on Object {
        return value.toString();
      }
    }
  }
  return '';
}

Object? _metadataLookup(Map<String, Object?> metadata, String key) {
  if (metadata.containsKey(key)) {
    return metadata[key];
  }
  Object? current = metadata;
  for (final segment in key.split('.')) {
    if (current is Map) {
      current = current[segment];
    } else {
      return null;
    }
  }
  return current;
}

String _formatNumber(num value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

AgentToolCallState _seedState(AgentToolCallEvent event, String toolId) {
  return AgentToolCallState(
    callId: event.callId,
    toolId: toolId,
    status: AgentToolCallStatus.inputStreaming,
    startedAt: event.emittedAt,
    updatedAt: event.emittedAt,
  );
}

AgentToolCallTimelineStatus _timelineStatus(List<AgentToolCallState> calls) {
  if (calls.isEmpty) {
    return AgentToolCallTimelineStatus.idle;
  }
  if (calls.any(
    (call) => call.status == AgentToolCallStatus.permissionBlocked,
  )) {
    return AgentToolCallTimelineStatus.blocked;
  }
  if (calls.any((call) => call.status == AgentToolCallStatus.failed)) {
    return AgentToolCallTimelineStatus.failed;
  }
  if (calls.any((call) => !call.terminal)) {
    return AgentToolCallTimelineStatus.running;
  }
  return AgentToolCallTimelineStatus.complete;
}

String _appendTruncated(String current, String delta, int maxLength) {
  return _truncate('$current$delta', maxLength);
}

String _truncate(String value, int maxLength) {
  if (maxLength <= 0) {
    return '';
  }
  if (value.length <= maxLength) {
    return value;
  }
  return value.substring(0, maxLength);
}
