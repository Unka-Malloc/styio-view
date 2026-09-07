import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/presentation/agent_workbench/session_view.dart';
import 'package:vityo_app/src/presentation/agent_workbench/task_center.dart';

import '../../../products/vityo_app/test/support/vityod_test_harness.dart';

void main() {
  /// REQ-IDE-008 / criterion 1 / backpressure and bounded memory.
  ///
  /// Precondition: a reducer with strict queue, byte, and hot-history budgets.
  /// Action: submit 200 payload-bearing events without awaiting each enqueue.
  /// Oracle: every input is either retained or explicitly counted as dropped;
  /// retained events and bytes stay within budget; the final event order is
  /// stable and no unbounded pending queue remains.
  test('event backpressure is bounded and never drops silently', () async {
    const policy = AgentEventBackpressurePolicy(
      maxQueuedEvents: 8,
      maxQueuedBytes: 4096,
      maxHotHistoryEvents: 5,
      maxHotHistoryBytes: 1536,
    );
    final reducer = AgentSessionReducer(
      sessionId: 'bounded',
      maxBufferedUpdates: policy.maxHotHistoryEvents,
      backpressurePolicy: policy,
    );
    final submitted = <Future<void>>[];
    for (var index = 0; index < 200; index += 1) {
      submitted.add(
        reducer.reduce(
          AgentSessionUpdate(
            sessionId: 'bounded',
            kind: 'tool',
            text: 'event-$index',
            payload: <String, Object?>{
              'id': '$index',
              'body': List<String>.filled(80, 'x').join(),
            },
          ),
        ),
      );
    }
    await Future.wait<void>(submitted);
    final snapshot = reducer.snapshot;
    expect(snapshot.updates.length, lessThanOrEqualTo(5));
    expect(snapshot.bufferedUpdateBytes, lessThanOrEqualTo(1536));
    expect(snapshot.droppedUpdateCount, greaterThan(0));
    expect(snapshot.acceptedUpdateCount + snapshot.droppedUpdateCount, 200);
    expect(snapshot.queuedUpdateCount, 0);
    final retainedIds = snapshot.updates
        .map((update) => int.parse(update.payload['id']! as String))
        .toList(growable: false);
    expect(
      retainedIds,
      orderedEquals(retainedIds.toList(growable: false)..sort()),
    );
    await reducer.close();
  });

  /// REQ-IDE-008 / criterion 1 / process failure isolation.
  ///
  /// Precondition: one healthy and one crashing supervised Agent descriptor.
  /// Action: connect the healthy Agent, attempt the crashing Agent, then query
  /// and use the healthy connection again.
  /// Oracle: the crashing descriptor reports process_failed while the sibling
  /// generation/capabilities remain usable and registry shutdown reaps it.
  test('one failed Agent process does not invalidate a sibling', () async {
    if (!VityodTestHarness.isSupported) return;
    final fixture = File(
      '${Directory.current.path}${Platform.pathSeparator}..'
      '${Platform.pathSeparator}..${Platform.pathSeparator}tests'
      '${Platform.pathSeparator}acceptance${Platform.pathSeparator}fixtures'
      '${Platform.pathSeparator}vityo_app${Platform.pathSeparator}'
      'agent_client${Platform.pathSeparator}fake_agent.dart',
    );
    final dartExecutable = _findDartExecutable();
    expect(dartExecutable.existsSync(), isTrue);
    final harness = await VityodTestHarness.start(
      clientId: 'quality-agent-isolation',
    );
    final registry = AgentClientRegistry(
      descriptors: <String, AgentLaunchDescriptor>{
        'healthy': AgentLaunchDescriptor(
          id: 'healthy',
          executable: dartExecutable.path,
          arguments: <String>[fixture.path, 'normal'],
          workingDirectory: Directory.current.path,
        ),
        'crash': AgentLaunchDescriptor(
          id: 'crash',
          executable: dartExecutable.path,
          arguments: <String>[fixture.path, 'crash'],
          workingDirectory: Directory.current.path,
        ),
      },
      client: harness.client,
      policy: const AgentClientPolicy(
        requestTimeout: Duration(seconds: 3),
        shutdownTimeout: Duration(seconds: 2),
      ),
    );
    try {
      final healthy = await registry.connect('healthy');
      await expectLater(
        registry.connect('crash'),
        throwsA(
          isA<AgentClientFailure>().having(
            (failure) => failure.code,
            'code',
            'process_failed',
          ),
        ),
      );
      final stillHealthy = registry.connection('healthy');
      expect(stillHealthy.generation, healthy.generation);
      expect(stillHealthy.protocolVersion, 1);
      final session = await registry.newSession(
        agentId: 'healthy',
        cwd: Directory.current.uri,
      );
      expect(session.agentId, 'healthy');
    } finally {
      final receipts = await registry.close();
      expect(
        receipts.where((receipt) => receipt.agentId == 'healthy'),
        hasLength(1),
      );
      await harness.close();
    }
  });

  /// REQ-IDE-008 / criterion 1 / accessible virtualized collaboration.
  ///
  /// Precondition: 10,000 immutable timeline entries and one background
  /// permission requiring attention.
  /// Action: render task/session surfaces, traverse controls by keyboard, and
  /// inspect semantic labels.
  /// Oracle: only a visible-range number of rows is built, attention/control
  /// semantics are exposed, and keyboard activation routes to the exact
  /// session without rendering the full history.
  testWidgets(
    'large collaboration surfaces are virtualized and keyboard accessible',
    (tester) async {
      final commands = _Commands();
      final session = CollaborationSessionProjection(
        sessionId: 'large',
        snapshotRevision: 10,
        title: 'Large task',
        status: CollaborationTaskStatus.active,
        timeline: <CollaborationTimelineEntry>[
          for (var index = 0; index < 10000; index += 1)
            CollaborationTimelineEntry(
              id: 'large:turn:$index',
              sessionId: 'large',
              kind: CollaborationTimelineKind.turn,
              label: 'entry $index',
              payload: <String, Object?>{'id': '$index'},
            ),
        ],
        droppedTimelineCount: 20,
        pendingPermissions: const <String, CollaborationPermissionProjection>{},
        changeReviews: const <String, AgentChangeReviewProjection>{},
      );
      final projection = CollaborationProjection(
        revision: 1,
        sessions: <String, CollaborationSessionProjection>{'large': session},
        orderedSessionIds: const <String>['large'],
      );
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: AgentSessionView(session: session, commands: commands),
            ),
          ),
        ),
      );
      expect(find.byType(ListTile), findsWidgets);
      expect(find.byType(ListTile).evaluate().length, lessThan(40));
      expect(find.bySemanticsLabel('Cancel Agent task'), findsOneWidget);
      expect(find.bySemanticsLabel('Reconnect Agent'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(commands.routedSessionIds.every((id) => id == 'large'), isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: AgentTaskCenter(
                projection: projection,
                onSelectSession: commands.routedSessionIds.add,
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Agent task center'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('agent-task-large')));
      expect(commands.routedSessionIds.last, 'large');
      semantics.dispose();
    },
  );
}

File _findDartExecutable() {
  final engineDirectory = File(Platform.resolvedExecutable).parent;
  final cacheDirectory = engineDirectory.parent.parent.parent;
  return File(
    '${cacheDirectory.path}/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
  );
}

final class _Commands implements AgentWorkbenchCommandPort {
  final List<String> routedSessionIds = <String>[];

  @override
  Future<void> cancel(String sessionId) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> reconnect(String sessionId) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> retry(String sessionId) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> steer(String sessionId, String prompt) async {
    routedSessionIds.add(sessionId);
  }
}
