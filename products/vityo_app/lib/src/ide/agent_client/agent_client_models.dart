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
    this.maxSessions = 64,
    this.maxPendingRequests = 128,
    this.requestTimeout = const Duration(seconds: 30),
    this.shutdownTimeout = const Duration(seconds: 3),
    this.allowedExtensions = const <String>{},
  }) : assert(maxMessageBytes > 0),
       assert(maxBufferedUpdatesPerSession > 0),
       assert(maxBufferedUpdateBytesPerSession > 0),
       assert(maxQueuedUpdatesPerSession > 0),
       assert(maxQueuedUpdateBytesPerSession > 0),
       assert(maxSessions > 0),
       assert(maxPendingRequests > 0);

  final int maxMessageBytes;
  final int maxBufferedUpdatesPerSession;
  final int maxBufferedUpdateBytesPerSession;
  final int maxQueuedUpdatesPerSession;
  final int maxQueuedUpdateBytesPerSession;
  final int maxSessions;
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
    required this.toolCallId,
    required this.options,
    this.toolCallTitle,
    this.toolCallKind,
  });

  final String id;
  final String agentId;
  final String sessionId;
  final String toolCallId;
  final String? toolCallTitle;
  final String? toolCallKind;

  /// Supported ACP permission option kinds, never opaque wire option IDs.
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
  PermissionRequestQueue({required this.maxItems}) {
    if (maxItems <= 0) {
      throw ArgumentError.value(maxItems, 'maxItems', 'must be positive');
    }
  }

  final int maxItems;
  final ListQueue<AgentPermissionRequest> _items =
      ListQueue<AgentPermissionRequest>();
  final ListQueue<_PermissionWaiter> _waiters = ListQueue<_PermissionWaiter>();
  bool _closed = false;

  bool add(AgentPermissionRequest request) {
    if (_closed) {
      return false;
    }
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      if (waiter.cancelled) {
        continue;
      }
      waiter.completer.complete(request);
      return true;
    }
    if (_items.length >= maxItems) {
      return false;
    }
    _items.add(request);
    return true;
  }

  void removeWhere(bool Function(AgentPermissionRequest request) predicate) {
    final retained = _items
        .where((request) => !predicate(request))
        .toList(growable: false);
    _items
      ..clear()
      ..addAll(retained);
  }

  Stream<AgentPermissionRequest> stream() =>
      Stream<AgentPermissionRequest>.multi((controller) {
        _PermissionWaiter? activeWaiter;
        var cancelled = false;

        Future<void> pump() async {
          while (!cancelled && !_closed) {
            if (_items.isNotEmpty) {
              controller.add(_items.removeFirst());
              await Future<void>.delayed(Duration.zero);
              continue;
            }
            if (_waiters.length >= maxItems) {
              controller.addError(
                StateError('permission consumer limit exceeded'),
              );
              controller.close();
              return;
            }
            final waiter = _PermissionWaiter();
            activeWaiter = waiter;
            _waiters.add(waiter);
            try {
              final request = await waiter.completer.future;
              if (!cancelled) {
                controller.add(request);
              }
            } on StateError {
              if (!cancelled) {
                controller.close();
              }
              return;
            } finally {
              _waiters.remove(waiter);
              if (identical(activeWaiter, waiter)) {
                activeWaiter = null;
              }
            }
          }
          if (!cancelled) {
            controller.close();
          }
        }

        controller.onCancel = () {
          cancelled = true;
          final waiter = activeWaiter;
          if (waiter != null && !waiter.completer.isCompleted) {
            waiter.cancelled = true;
            _waiters.remove(waiter);
            waiter.completer.completeError(
              StateError('permission consumer cancelled'),
            );
          }
        };
        unawaited(pump());
      });

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _items.clear();
    for (final waiter in _waiters) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(StateError('permission queue closed'));
      }
    }
    _waiters.clear();
  }
}

final class _PermissionWaiter {
  final Completer<AgentPermissionRequest> completer =
      Completer<AgentPermissionRequest>();
  bool cancelled = false;
}
