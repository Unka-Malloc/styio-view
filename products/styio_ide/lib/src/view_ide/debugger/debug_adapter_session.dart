import 'debug_adapter_protocol.dart';

enum DapSessionStatus {
  idle,
  initializing,
  launching,
  running,
  paused,
  terminated,
  failed,
}

class DapPendingRequest {
  const DapPendingRequest({required this.seq, required this.command});

  final int seq;
  final String command;

  Map<String, Object?> toJson() {
    return <String, Object?>{'seq': seq, 'command': command};
  }
}

class DapObservedEvent {
  const DapObservedEvent({required this.event, this.body});

  final String event;
  final Map<String, Object?>? body;

  Map<String, Object?> toJson() {
    return <String, Object?>{'event': event, if (body != null) 'body': body};
  }
}

class DapObservedResponse {
  const DapObservedResponse({
    required this.requestSeq,
    required this.command,
    required this.success,
    this.message,
    this.body,
  });

  final int requestSeq;
  final String command;
  final bool success;
  final String? message;
  final Map<String, Object?>? body;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestSeq': requestSeq,
      'command': command,
      'success': success,
      if (message != null) 'message': message,
      if (body != null) 'body': body,
    };
  }
}

class DapThread {
  const DapThread({required this.id, required this.name});

  final int id;
  final String name;

  Map<String, Object?> toJson() {
    return <String, Object?>{'id': id, 'name': name};
  }
}

class DapStackFrame {
  const DapStackFrame({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.line,
    required this.column,
  });

  final int id;
  final String name;
  final String sourcePath;
  final int line;
  final int column;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'sourcePath': sourcePath,
      'line': line,
      'column': column,
    };
  }
}

class DapScope {
  const DapScope({
    required this.name,
    required this.variablesReference,
    this.expensive = false,
  });

  final String name;
  final int variablesReference;
  final bool expensive;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'variablesReference': variablesReference,
      'expensive': expensive,
    };
  }
}

class DapVariable {
  const DapVariable({
    required this.name,
    required this.value,
    this.type,
    this.variablesReference = 0,
  });

  final String name;
  final String value;
  final String? type;
  final int variablesReference;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'value': value,
      if (type != null) 'type': type,
      'variablesReference': variablesReference,
    };
  }
}

class DapSessionSnapshot {
  const DapSessionSnapshot({
    required this.status,
    required this.nextSeq,
    required this.pendingRequests,
    required this.events,
    required this.threads,
    required this.stackFrames,
    required this.scopes,
    required this.variables,
    this.activeThreadId,
    this.lastResponse,
    this.failureMessage,
  });

  final DapSessionStatus status;
  final int nextSeq;
  final List<DapPendingRequest> pendingRequests;
  final List<DapObservedEvent> events;
  final List<DapThread> threads;
  final List<DapStackFrame> stackFrames;
  final List<DapScope> scopes;
  final List<DapVariable> variables;
  final int? activeThreadId;
  final DapObservedResponse? lastResponse;
  final String? failureMessage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'nextSeq': nextSeq,
      'pendingRequestCount': pendingRequests.length,
      'pendingRequests': pendingRequests
          .map((request) => request.toJson())
          .toList(growable: false),
      'eventCount': events.length,
      'events': events.map((event) => event.toJson()).toList(growable: false),
      'threadCount': threads.length,
      'threads': threads
          .map((thread) => thread.toJson())
          .toList(growable: false),
      'stackFrameCount': stackFrames.length,
      'stackFrames': stackFrames
          .map((frame) => frame.toJson())
          .toList(growable: false),
      'scopeCount': scopes.length,
      'scopes': scopes.map((scope) => scope.toJson()).toList(growable: false),
      'variableCount': variables.length,
      'variables': variables
          .map((variable) => variable.toJson())
          .toList(growable: false),
      if (activeThreadId != null) 'activeThreadId': activeThreadId,
      if (lastResponse != null) 'lastResponse': lastResponse!.toJson(),
      if (failureMessage != null) 'failureMessage': failureMessage,
    };
  }
}

class DapSessionController {
  DapSessionController({
    DapContentFrameCodec codec = const DapContentFrameCodec(),
  }) : _codec = codec;

  final DapContentFrameCodec _codec;
  final Map<int, DapPendingRequest> _pendingRequests =
      <int, DapPendingRequest>{};
  final List<DapObservedEvent> _events = <DapObservedEvent>[];
  final List<DapThread> _threads = <DapThread>[];
  final List<DapStackFrame> _stackFrames = <DapStackFrame>[];
  final List<DapScope> _scopes = <DapScope>[];
  final List<DapVariable> _variables = <DapVariable>[];
  int? _activeThreadId;
  int _nextSeq = 1;
  DapSessionStatus _status = DapSessionStatus.idle;
  DapObservedResponse? _lastResponse;
  String? _failureMessage;

  DapSessionSnapshot get snapshot {
    return DapSessionSnapshot(
      status: _status,
      nextSeq: _nextSeq,
      pendingRequests: List<DapPendingRequest>.unmodifiable(
        _pendingRequests.values,
      ),
      events: List<DapObservedEvent>.unmodifiable(_events),
      threads: List<DapThread>.unmodifiable(_threads),
      stackFrames: List<DapStackFrame>.unmodifiable(_stackFrames),
      scopes: List<DapScope>.unmodifiable(_scopes),
      variables: List<DapVariable>.unmodifiable(_variables),
      activeThreadId: _activeThreadId,
      lastResponse: _lastResponse,
      failureMessage: _failureMessage,
    );
  }

  int reserveSeq() {
    final seq = _nextSeq;
    _nextSeq += 1;
    return seq;
  }

  List<int> encodeRequest(DapRequest request) {
    recordOutboundRequest(request);
    return _codec.encode(request.toJson());
  }

  void recordOutboundRequest(DapRequest request) {
    _pendingRequests[request.seq] = DapPendingRequest(
      seq: request.seq,
      command: request.command,
    );
    if (request.seq >= _nextSeq) {
      _nextSeq = request.seq + 1;
    }
    switch (request.command) {
      case 'initialize':
        _status = DapSessionStatus.initializing;
        return;
      case 'launch':
      case 'configurationDone':
        _status = DapSessionStatus.launching;
        return;
      case 'continue':
      case 'next':
        _status = DapSessionStatus.running;
        return;
      case 'stackTrace':
        final threadId = request.arguments['threadId'];
        if (threadId is int) {
          _activeThreadId = threadId;
        }
        _stackFrames.clear();
        _scopes.clear();
        _variables.clear();
        return;
      case 'scopes':
        _scopes.clear();
        _variables.clear();
        return;
    }
  }

  void recordLaunchPlan(DapLaunchRequestPlan plan) {
    for (final request in plan.requests) {
      recordOutboundRequest(request);
    }
  }

  DapContentFrame? acceptFrameBytes(List<int> bytes) {
    final frame = _codec.decodeFirst(bytes);
    if (frame != null) {
      acceptMessage(frame.message);
    }
    return frame;
  }

  void acceptMessage(Map<String, Object?> message) {
    final type = message['type'];
    if (type == 'response') {
      _acceptResponse(message);
      return;
    }
    if (type == 'event') {
      _acceptEvent(message);
    }
  }

  void _acceptResponse(Map<String, Object?> message) {
    final requestSeq = message['request_seq'];
    if (requestSeq is! int) {
      throw const FormatException('DAP response is missing request_seq.');
    }
    final command = message['command'] as String? ?? '';
    final success = message['success'] as bool? ?? false;
    final body = _objectMap(message['body']);
    final observed = DapObservedResponse(
      requestSeq: requestSeq,
      command: command,
      success: success,
      message: message['message'] as String?,
      body: body,
    );
    _pendingRequests.remove(requestSeq);
    _lastResponse = observed;
    if (success) {
      _acceptSuccessfulResponseBody(command: command, body: body);
    }
    if (!success) {
      _status = DapSessionStatus.failed;
      _failureMessage =
          observed.message ??
          'DAP request $command failed for seq $requestSeq.';
      return;
    }
    _failureMessage = null;
    if (command == 'configurationDone') {
      _status = DapSessionStatus.running;
    } else if (_pendingRequests.isEmpty &&
        (_status == DapSessionStatus.initializing ||
            _status == DapSessionStatus.launching)) {
      _status = DapSessionStatus.running;
    }
  }

  void _acceptSuccessfulResponseBody({
    required String command,
    required Map<String, Object?>? body,
  }) {
    if (body == null) {
      return;
    }
    if (command == 'threads') {
      _threads
        ..clear()
        ..addAll(_threadsFromBody(body));
      if (_status == DapSessionStatus.paused &&
          _activeThreadId == null &&
          _threads.isNotEmpty) {
        _activeThreadId = _threads.first.id;
      }
      return;
    }
    if (command == 'stackTrace') {
      _stackFrames
        ..clear()
        ..addAll(_stackFramesFromBody(body));
      _scopes.clear();
      _variables.clear();
      return;
    }
    if (command == 'scopes') {
      _scopes
        ..clear()
        ..addAll(_scopesFromBody(body));
      _variables.clear();
      return;
    }
    if (command == 'variables') {
      _variables
        ..clear()
        ..addAll(_variablesFromBody(body));
    }
  }

  void _acceptEvent(Map<String, Object?> message) {
    final event = message['event'] as String? ?? '';
    final body = _objectMap(message['body']);
    final observed = DapObservedEvent(event: event, body: body);
    _events.add(observed);
    final threadId = body?['threadId'];
    if (threadId is int) {
      _activeThreadId = threadId;
    }
    switch (event) {
      case 'stopped':
        _status = DapSessionStatus.paused;
        return;
      case 'continued':
        _activeThreadId = null;
        _threads.clear();
        _stackFrames.clear();
        _scopes.clear();
        _variables.clear();
        _status = DapSessionStatus.running;
        return;
      case 'terminated':
      case 'exited':
        _activeThreadId = null;
        _threads.clear();
        _stackFrames.clear();
        _scopes.clear();
        _variables.clear();
        _status = DapSessionStatus.terminated;
        return;
    }
  }
}

List<DapStackFrame> _stackFramesFromBody(Map<String, Object?> body) {
  final values = body['stackFrames'];
  if (values is! List) {
    return const <DapStackFrame>[];
  }
  final frames = <DapStackFrame>[];
  for (final value in values) {
    final frame = _objectMap(value);
    if (frame == null) {
      continue;
    }
    final source = _objectMap(frame['source']);
    frames.add(
      DapStackFrame(
        id: frame['id'] as int? ?? 0,
        name: frame['name'] as String? ?? '',
        sourcePath: source?['path'] as String? ?? '',
        line: frame['line'] as int? ?? 0,
        column: frame['column'] as int? ?? 0,
      ),
    );
  }
  return frames;
}

List<DapThread> _threadsFromBody(Map<String, Object?> body) {
  final values = body['threads'];
  if (values is! List) {
    return const <DapThread>[];
  }
  final threads = <DapThread>[];
  for (final value in values) {
    final thread = _objectMap(value);
    if (thread == null) {
      continue;
    }
    threads.add(
      DapThread(
        id: thread['id'] as int? ?? 0,
        name: thread['name'] as String? ?? '',
      ),
    );
  }
  return threads;
}

List<DapScope> _scopesFromBody(Map<String, Object?> body) {
  final values = body['scopes'];
  if (values is! List) {
    return const <DapScope>[];
  }
  final scopes = <DapScope>[];
  for (final value in values) {
    final scope = _objectMap(value);
    if (scope == null) {
      continue;
    }
    scopes.add(
      DapScope(
        name: scope['name'] as String? ?? '',
        variablesReference: scope['variablesReference'] as int? ?? 0,
        expensive: scope['expensive'] as bool? ?? false,
      ),
    );
  }
  return scopes;
}

List<DapVariable> _variablesFromBody(Map<String, Object?> body) {
  final values = body['variables'];
  if (values is! List) {
    return const <DapVariable>[];
  }
  final variables = <DapVariable>[];
  for (final value in values) {
    final variable = _objectMap(value);
    if (variable == null) {
      continue;
    }
    variables.add(
      DapVariable(
        name: variable['name'] as String? ?? '',
        value: variable['value'] as String? ?? '',
        type: variable['type'] as String?,
        variablesReference: variable['variablesReference'] as int? ?? 0,
      ),
    );
  }
  return variables;
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }
  return null;
}
