import 'dart:async';

import 'package:styio_coding_agent/styio_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  group('headless runtime', () {
    test('completes with a revisioned in-memory host snapshot', () async {
      final host = InMemoryHostWorkspace(
        roots: const <HostRoot>[
          HostRoot(id: 'workspace', uri: 'memory://workspace'),
        ],
        facts: const <String, Object?>{'language': 'dart'},
        revision: 7,
      );
      final runtime = AgentRuntime(
        sessionService: AgentSessionService(host: host),
      );

      final receipt = await runtime.run(
        const AgentRunRequest(
          sessionId: 'session-1',
          goal: 'Inspect',
          rootId: 'workspace',
        ),
      );

      expect(receipt.state, AgentSessionState.completed);
      expect(receipt.observedRevision, 7);
      expect(receipt.failure, isNull);
      expect(host.inspectionCount, 1);
    });

    test('cancels an active host request through its typed signal', () async {
      final host = _BlockingHost();
      final runtime = AgentRuntime(
        sessionService: AgentSessionService(host: host),
      );
      final pending = runtime.run(
        const AgentRunRequest(
          sessionId: 'session-1',
          goal: 'Inspect',
          rootId: 'workspace',
        ),
      );
      await host.started;

      expect(runtime.cancel('session-1'), isTrue);
      final receipt = await pending;

      expect(receipt.state, AgentSessionState.cancelled);
      expect(receipt.failure?.code, HostFailureCode.cancelled);
    });

    test('preserves typed host failures', () async {
      final runtime = AgentRuntime(
        sessionService: AgentSessionService(
          host: InMemoryHostWorkspace(
            roots: const <HostRoot>[
              HostRoot(id: 'workspace', uri: 'memory://workspace'),
            ],
            failure: const HostFailure(
              code: HostFailureCode.capabilityUnavailable,
              message: 'facts unavailable',
            ),
          ),
        ),
      );

      final receipt = await runtime.run(
        const AgentRunRequest(
          sessionId: 'session-1',
          goal: 'Inspect',
          rootId: 'workspace',
        ),
      );

      expect(receipt.state, AgentSessionState.failed);
      expect(receipt.failure?.code, HostFailureCode.capabilityUnavailable);
    });

    test('fails an expired request before calling the host', () async {
      final host = InMemoryHostWorkspace(
        roots: const <HostRoot>[
          HostRoot(id: 'workspace', uri: 'memory://workspace'),
        ],
      );
      final runtime = AgentRuntime(
        sessionService: AgentSessionService(
          host: host,
          clock: _FixedClock(DateTime.utc(2026, 7, 26, 12)),
        ),
      );

      final receipt = await runtime.run(
        AgentRunRequest(
          sessionId: 'session-1',
          goal: 'Inspect',
          rootId: 'workspace',
          deadline: DateTime.utc(2026, 7, 26, 11),
        ),
      );

      expect(receipt.state, AgentSessionState.failed);
      expect(receipt.failure?.code, HostFailureCode.deadlineExceeded);
      expect(host.inspectionCount, 0);
    });

    test('serializes duplicate commands for one session', () async {
      final host = _BlockingHost();
      final runtime = AgentRuntime(
        sessionService: AgentSessionService(host: host),
      );
      final first = runtime.run(
        const AgentRunRequest(
          sessionId: 'session-1',
          goal: 'First',
          rootId: 'workspace',
        ),
      );
      await host.started;
      final duplicate = runtime.run(
        const AgentRunRequest(
          sessionId: 'session-1',
          goal: 'Duplicate',
          rootId: 'workspace',
        ),
      );
      host.release();

      expect((await first).state, AgentSessionState.completed);
      final duplicateReceipt = await duplicate;
      expect(duplicateReceipt.state, AgentSessionState.failed);
      expect(duplicateReceipt.failure?.code, HostFailureCode.invalidRequest);
      expect(host.inspectionCount, 1);
    });
  });

  test('in-memory host rejects duplicate root ids', () {
    expect(
      () => InMemoryHostWorkspace(
        roots: const <HostRoot>[
          HostRoot(id: 'workspace', uri: 'memory://one'),
          HostRoot(id: 'workspace', uri: 'memory://two'),
        ],
      ),
      throwsArgumentError,
    );
  });
}

final class _FixedClock implements AgentClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _BlockingHost implements HostWorkspace {
  final Completer<void> _started = Completer<void>();
  final Completer<void> _released = Completer<void>();
  int inspectionCount = 0;

  Future<void> get started => _started.future;

  @override
  List<HostRoot> get roots => const <HostRoot>[
    HostRoot(id: 'workspace', uri: 'memory://workspace'),
  ];

  void release() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }

  @override
  Future<HostResult<HostWorkspaceSnapshot>> inspect(
    HostWorkspaceRequest request,
  ) async {
    inspectionCount += 1;
    if (!_started.isCompleted) {
      _started.complete();
    }
    await Future.any<void>(<Future<void>>[
      _released.future,
      request.context.cancellation.whenCancelled,
    ]);
    if (request.context.cancellation.isCancelled) {
      return const HostRejected<HostWorkspaceSnapshot>(
        HostFailure(code: HostFailureCode.cancelled, message: 'cancelled'),
      );
    }
    return HostSuccess<HostWorkspaceSnapshot>(
      HostWorkspaceSnapshot(
        rootId: request.rootId,
        revision: 0,
        facts: const <String, Object?>{},
      ),
    );
  }
}
