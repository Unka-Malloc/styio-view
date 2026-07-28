import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'agent_client_models.dart';

final class AgentSessionSnapshot {
  const AgentSessionSnapshot({
    required this.sessionId,
    required this.revision,
    required this.updates,
    this.bufferedUpdateBytes = 0,
    this.droppedUpdateCount = 0,
    this.droppedUpdateBytes = 0,
    this.queuedUpdateCount = 0,
  });

  final String sessionId;
  final int revision;
  final List<AgentSessionUpdate> updates;
  final int bufferedUpdateBytes;
  final int droppedUpdateCount;
  final int droppedUpdateBytes;
  final int queuedUpdateCount;

  int get acceptedUpdateCount => updates.length;
}

final class AgentSessionReducer {
  AgentSessionReducer({
    required this.sessionId,
    required int maxBufferedUpdates,
    AgentEventBackpressurePolicy? backpressurePolicy,
  }) : _policy =
           backpressurePolicy ??
           AgentEventBackpressurePolicy(
             maxQueuedEvents: maxBufferedUpdates,
             maxQueuedBytes: 1024 * 1024,
             maxHotHistoryEvents: maxBufferedUpdates,
             maxHotHistoryBytes: 1024 * 1024,
           );

  final String sessionId;
  final AgentEventBackpressurePolicy _policy;
  final ListQueue<_BufferedUpdate> _updates = ListQueue<_BufferedUpdate>();
  final ListQueue<_PendingUpdate> _pending = ListQueue<_PendingUpdate>();
  final StreamController<AgentSessionUpdate> _controller =
      StreamController<AgentSessionUpdate>.broadcast(sync: true);
  int _revision = 0;
  int _bufferedBytes = 0;
  int _queuedBytes = 0;
  int _droppedCount = 0;
  int _droppedBytes = 0;
  bool _drainScheduled = false;
  bool _closed = false;

  Stream<AgentSessionUpdate> get updates => _controller.stream;

  AgentSessionSnapshot get snapshot => AgentSessionSnapshot(
    sessionId: sessionId,
    revision: _revision,
    updates: List<AgentSessionUpdate>.unmodifiable(
      _updates.map((item) => item.update),
    ),
    bufferedUpdateBytes: _bufferedBytes,
    droppedUpdateCount: _droppedCount,
    droppedUpdateBytes: _droppedBytes,
    queuedUpdateCount: _pending.length,
  );

  Future<void> reduce(AgentSessionUpdate update) {
    if (_closed) {
      return Future<void>.value();
    }
    if (update.sessionId != sessionId) {
      return Future<void>.error(
        AgentClientFailure(
          'session_mismatch',
          'update belongs to a different session',
        ),
      );
    }
    final bytes = _encodedBytes(update);
    if (bytes > _policy.maxQueuedBytes ||
        _pending.length >= _policy.maxQueuedEvents ||
        _queuedBytes + bytes > _policy.maxQueuedBytes) {
      _recordDrop(bytes);
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _pending.addLast(
      _PendingUpdate(update: update, bytes: bytes, completer: completer),
    );
    _queuedBytes += bytes;
    if (!_drainScheduled) {
      _drainScheduled = true;
      scheduleMicrotask(_drain);
    }
    return completer.future;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _drain();
    await _controller.close();
  }

  void _drain() {
    _drainScheduled = false;
    while (_pending.isNotEmpty) {
      final pending = _pending.removeFirst();
      _queuedBytes -= pending.bytes;
      if (pending.bytes > _policy.maxHotHistoryBytes) {
        _recordDrop(pending.bytes);
        pending.completer.complete();
        continue;
      }
      _updates.addLast(
        _BufferedUpdate(update: pending.update, bytes: pending.bytes),
      );
      _bufferedBytes += pending.bytes;
      _revision += 1;
      _controller.add(pending.update);
      while (_updates.length > _policy.maxHotHistoryEvents ||
          _bufferedBytes > _policy.maxHotHistoryBytes) {
        final removed = _updates.removeFirst();
        _bufferedBytes -= removed.bytes;
        _recordDrop(removed.bytes);
      }
      pending.completer.complete();
    }
  }

  void _recordDrop(int bytes) {
    _droppedCount += 1;
    _droppedBytes += bytes;
  }
}

final class _PendingUpdate {
  const _PendingUpdate({
    required this.update,
    required this.bytes,
    required this.completer,
  });

  final AgentSessionUpdate update;
  final int bytes;
  final Completer<void> completer;
}

final class _BufferedUpdate {
  const _BufferedUpdate({required this.update, required this.bytes});

  final AgentSessionUpdate update;
  final int bytes;
}

int _encodedBytes(AgentSessionUpdate update) => utf8
    .encode(
      jsonEncode(<String, Object?>{
        'sessionId': update.sessionId,
        'kind': update.kind,
        if (update.text != null) 'text': update.text,
        'payload': update.payload,
      }),
    )
    .length;
