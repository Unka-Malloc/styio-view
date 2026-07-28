library;

import 'dart:async';

import '../cancellation.dart';
import '../hosts/host_workspace.dart';

enum AgentSessionState { idle, running, completed, cancelled, failed }

abstract interface class AgentClock {
  DateTime now();
}

final class SystemAgentClock implements AgentClock {
  const SystemAgentClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

final class AgentRunRequest {
  const AgentRunRequest({
    required this.sessionId,
    required this.goal,
    required this.rootId,
    this.cancellation,
    this.deadline,
  });

  final String sessionId;
  final String goal;
  final String rootId;
  final AgentCancellationToken? cancellation;
  final DateTime? deadline;
}

final class AgentRunReceipt {
  const AgentRunReceipt({
    required this.sessionId,
    required this.state,
    required this.eventCount,
    this.observedRevision,
    this.failure,
  });

  final String sessionId;
  final AgentSessionState state;
  final int eventCount;
  final int? observedRevision;
  final HostFailure? failure;

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'state': state.name,
    'eventCount': eventCount,
    if (observedRevision != null) 'observedRevision': observedRevision,
    if (failure != null) 'failure': failure!.toJson(),
  };
}

final class AgentSessionService {
  AgentSessionService({
    required HostWorkspace host,
    AgentClock clock = const SystemAgentClock(),
  }) : _host = host,
       _clock = clock;

  final HostWorkspace _host;
  final AgentClock _clock;
  final Map<String, _SessionActor> _sessions = <String, _SessionActor>{};

  Future<AgentRunReceipt> run(AgentRunRequest request) {
    if (request.sessionId.trim().isEmpty) {
      return Future<AgentRunReceipt>.value(
        _failed(
          request.sessionId,
          HostFailureCode.invalidRequest,
          'sessionId must not be empty',
        ),
      );
    }
    final actor = _sessions.putIfAbsent(request.sessionId, _SessionActor.new);
    return actor.enqueue(() => _run(actor, request));
  }

  bool cancel(String sessionId) {
    final actor = _sessions[sessionId];
    if (actor == null || actor.state.isTerminal) {
      return false;
    }
    actor.cancellation.cancel();
    return true;
  }

  AgentSessionState? stateOf(String sessionId) => _sessions[sessionId]?.state;

  void dispose() => _sessions.clear();

  Future<AgentRunReceipt> _run(
    _SessionActor actor,
    AgentRunRequest request,
  ) async {
    if (actor.state != AgentSessionState.idle) {
      return _failed(
        request.sessionId,
        HostFailureCode.invalidRequest,
        'session has already started',
      );
    }
    if (request.goal.trim().isEmpty || request.rootId.trim().isEmpty) {
      actor.state = AgentSessionState.failed;
      return _failed(
        request.sessionId,
        HostFailureCode.invalidRequest,
        'goal and rootId must not be empty',
      );
    }

    final cancellation = _CombinedCancellationSignal(
      actor.cancellation.token,
      request.cancellation,
    );
    if (cancellation.isCancelled) {
      actor.state = AgentSessionState.cancelled;
      return _cancelled(request.sessionId);
    }

    var now = _clock.now();
    if (_deadlineReached(now, request.deadline)) {
      actor.state = AgentSessionState.failed;
      return _failed(
        request.sessionId,
        HostFailureCode.deadlineExceeded,
        'session deadline exceeded before host execution',
      );
    }

    actor.state = AgentSessionState.running;
    HostResult<HostWorkspaceSnapshot> result;
    try {
      result = await _host.inspect(
        HostWorkspaceRequest(
          context: HostRequestContext(
            sessionId: request.sessionId,
            observedAt: now,
            cancellation: cancellation,
            deadline: request.deadline,
          ),
          goal: request.goal,
          rootId: request.rootId,
        ),
      );
    } on Object {
      actor.state = AgentSessionState.failed;
      return _failed(
        request.sessionId,
        HostFailureCode.capabilityUnavailable,
        'host request failed without a typed result',
      );
    }

    if (cancellation.isCancelled) {
      actor.state = AgentSessionState.cancelled;
      return _cancelled(request.sessionId, eventCount: 2);
    }
    now = _clock.now();
    if (_deadlineReached(now, request.deadline)) {
      actor.state = AgentSessionState.failed;
      return _failed(
        request.sessionId,
        HostFailureCode.deadlineExceeded,
        'session deadline exceeded during host execution',
        eventCount: 2,
      );
    }

    return switch (result) {
      HostSuccess<HostWorkspaceSnapshot>(:final value) => _complete(
        actor,
        request.sessionId,
        value.revision,
      ),
      HostRejected<HostWorkspaceSnapshot>(:final failure) => _reject(
        actor,
        request.sessionId,
        failure,
      ),
    };
  }

  static AgentRunReceipt _complete(
    _SessionActor actor,
    String sessionId,
    int revision,
  ) {
    actor.state = AgentSessionState.completed;
    return AgentRunReceipt(
      sessionId: sessionId,
      state: AgentSessionState.completed,
      eventCount: 3,
      observedRevision: revision,
    );
  }

  static AgentRunReceipt _reject(
    _SessionActor actor,
    String sessionId,
    HostFailure failure,
  ) {
    if (failure.code == HostFailureCode.cancelled) {
      actor.state = AgentSessionState.cancelled;
      return AgentRunReceipt(
        sessionId: sessionId,
        state: AgentSessionState.cancelled,
        eventCount: 2,
        failure: failure,
      );
    }
    actor.state = AgentSessionState.failed;
    return AgentRunReceipt(
      sessionId: sessionId,
      state: AgentSessionState.failed,
      eventCount: 2,
      failure: failure,
    );
  }

  static AgentRunReceipt _cancelled(String sessionId, {int eventCount = 1}) =>
      AgentRunReceipt(
        sessionId: sessionId,
        state: AgentSessionState.cancelled,
        eventCount: eventCount,
        failure: const HostFailure(
          code: HostFailureCode.cancelled,
          message: 'session cancelled',
        ),
      );

  static AgentRunReceipt _failed(
    String sessionId,
    HostFailureCode code,
    String message, {
    int eventCount = 1,
  }) => AgentRunReceipt(
    sessionId: sessionId,
    state: AgentSessionState.failed,
    eventCount: eventCount,
    failure: HostFailure(code: code, message: message),
  );

  static bool _deadlineReached(DateTime now, DateTime? deadline) =>
      deadline != null && !now.isBefore(deadline);
}

extension on AgentSessionState {
  bool get isTerminal =>
      this == AgentSessionState.completed ||
      this == AgentSessionState.cancelled ||
      this == AgentSessionState.failed;
}

final class _CombinedCancellationSignal implements HostCancellationSignal {
  _CombinedCancellationSignal(this.local, this.external);

  final AgentCancellationToken local;
  final AgentCancellationToken? external;

  @override
  bool get isCancelled => local.isCancelled || (external?.isCancelled ?? false);

  @override
  Future<void> get whenCancelled {
    final externalSignal = external;
    if (externalSignal == null) {
      return local.whenCancelled;
    }
    return Future.any<void>(<Future<void>>[
      local.whenCancelled,
      externalSignal.whenCancelled,
    ]);
  }
}

final class _SessionActor {
  Future<void> _tail = Future<void>.value();
  final AgentCancellationController cancellation =
      AgentCancellationController();
  AgentSessionState state = AgentSessionState.idle;

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}
