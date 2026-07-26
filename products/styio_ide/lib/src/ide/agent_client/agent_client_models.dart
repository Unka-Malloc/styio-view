import 'dart:async';
import 'dart:collection';

final class AgentClientFailure implements Exception {
  AgentClientFailure(this.code, String message)
    : message = message.length <= 1024 ? message : message.substring(0, 1024);

  final String code;
  final String message;

  @override
  String toString() => 'AgentClientFailure($code, $message)';
}

final class AgentClientPolicy {
  const AgentClientPolicy({
    this.maxMessageBytes = 1024 * 1024,
    this.maxBufferedUpdatesPerSession = 128,
    this.maxBufferedUpdateBytesPerSession = 1024 * 1024,
    this.maxQueuedUpdatesPerSession = 64,
    this.maxQueuedUpdateBytesPerSession = 512 * 1024,
    this.maxPendingRequests = 128,
    this.requestTimeout = const Duration(seconds: 30),
    this.shutdownTimeout = const Duration(seconds: 3),
    this.allowedExtensions = const <String>{},
  }) : assert(maxMessageBytes > 0),
       assert(maxBufferedUpdatesPerSession > 0),
       assert(maxBufferedUpdateBytesPerSession > 0),
       assert(maxQueuedUpdatesPerSession > 0),
       assert(maxQueuedUpdateBytesPerSession > 0),
       assert(maxPendingRequests > 0);

  final int maxMessageBytes;
  final int maxBufferedUpdatesPerSession;
  final int maxBufferedUpdateBytesPerSession;
  final int maxQueuedUpdatesPerSession;
  final int maxQueuedUpdateBytesPerSession;
  final int maxPendingRequests;
  final Duration requestTimeout;
  final Duration shutdownTimeout;
  final Set<String> allowedExtensions;
}

final class AgentEventBackpressurePolicy {
  const AgentEventBackpressurePolicy({
    required this.maxQueuedEvents,
    required this.maxQueuedBytes,
    required this.maxHotHistoryEvents,
    required this.maxHotHistoryBytes,
  }) : assert(maxQueuedEvents > 0),
       assert(maxQueuedBytes > 0),
       assert(maxHotHistoryEvents > 0),
       assert(maxHotHistoryBytes > 0);

  final int maxQueuedEvents;
  final int maxQueuedBytes;
  final int maxHotHistoryEvents;
  final int maxHotHistoryBytes;
}

final class AgentConnectionSnapshot {
  const AgentConnectionSnapshot({
    required this.agentId,
    required this.protocolVersion,
    required this.generation,
    required this.capabilities,
    required this.metadata,
  });

  final String agentId;
  final int protocolVersion;
  final int generation;
  final Set<String> capabilities;
  final Map<String, Object?> metadata;
}

enum AgentPermissionDecision { allowOnce, rejectOnce }

final class AgentPermissionRequest {
  const AgentPermissionRequest({
    required this.id,
    required this.agentId,
    required this.sessionId,
    required this.options,
  });

  final String id;
  final String agentId;
  final String sessionId;
  final Set<String> options;
}

final class AgentSessionUpdate {
  const AgentSessionUpdate({
    required this.sessionId,
    required this.kind,
    required this.payload,
    this.text,
  });

  final String sessionId;
  final String kind;
  final String? text;
  final Map<String, Object?> payload;
}

final class PermissionRequestQueue {
  final ListQueue<AgentPermissionRequest> _items =
      ListQueue<AgentPermissionRequest>();
  final ListQueue<Completer<AgentPermissionRequest>> _waiters =
      ListQueue<Completer<AgentPermissionRequest>>();
  bool _closed = false;

  void add(AgentPermissionRequest request) {
    if (_closed) {
      return;
    }
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(request);
    } else {
      _items.add(request);
    }
  }

  Stream<AgentPermissionRequest> stream() async* {
    while (!_closed) {
      if (_items.isNotEmpty) {
        yield _items.removeFirst();
        continue;
      }
      final waiter = Completer<AgentPermissionRequest>();
      _waiters.add(waiter);
      try {
        yield await waiter.future;
      } on StateError {
        return;
      }
    }
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _items.clear();
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('permission queue closed'));
      }
    }
    _waiters.clear();
  }
}
