import '../runtime/runtime.dart';
import 'debug_adapter_session.dart';
import 'debug_launch_contract.dart';

class DebugRuntimeTaskHistoryBinder {
  const DebugRuntimeTaskHistoryBinder({
    this.source = 'debug-runtime-task-history',
  });

  final String source;

  RuntimeTaskSnapshot toTaskSnapshot({
    required DebugLaunchConfiguration launch,
    required DapSessionSnapshot adapterSnapshot,
    String? taskId,
    DateTime? timestamp,
  }) {
    final id = taskId ?? 'debug.${launch.debuggerId}';
    final status = _runtimeStatusFromDap(adapterSnapshot.status);
    final eventTimestamp = timestamp ?? DateTime.now().toUtc();
    final events = <RuntimeTaskLifecycleEvent>[
      for (var index = 0; index < adapterSnapshot.events.length; index += 1)
        RuntimeTaskLifecycleEvent(
          taskId: id,
          sequence: index + 1,
          status: status,
          timestamp: eventTimestamp,
          message: 'DAP event ${adapterSnapshot.events[index].event}.',
          source: source,
          metadata: adapterSnapshot.events[index].toJson(),
        ),
    ];
    return RuntimeTaskSnapshot(
      definition: launch.toRuntimeTaskDefinition(taskId: id),
      status: status,
      statusMessage: _messageFromDap(adapterSnapshot),
      startedAt: status == RuntimeTaskStatus.queued ? null : eventTimestamp,
      finishedAt: _terminalStatus(status) ? eventTimestamp : null,
      exitCode: status == RuntimeTaskStatus.failed ? 1 : null,
      events: events,
    );
  }

  Future<RuntimeTaskHistorySnapshot> appendSnapshot({
    required RuntimeTaskHistoryStore store,
    required String workspaceId,
    required DebugLaunchConfiguration launch,
    required DapSessionSnapshot adapterSnapshot,
    String? taskId,
    int maxEntries = 50,
    DateTime? timestamp,
  }) {
    return store.appendTask(
      workspaceId: workspaceId,
      maxEntries: maxEntries,
      task: toTaskSnapshot(
        launch: launch,
        adapterSnapshot: adapterSnapshot,
        taskId: taskId,
        timestamp: timestamp,
      ),
    );
  }

  RuntimeTaskStatus _runtimeStatusFromDap(DapSessionStatus status) {
    return switch (status) {
      DapSessionStatus.idle => RuntimeTaskStatus.queued,
      DapSessionStatus.initializing ||
      DapSessionStatus.launching ||
      DapSessionStatus.running ||
      DapSessionStatus.paused => RuntimeTaskStatus.running,
      DapSessionStatus.terminated => RuntimeTaskStatus.succeeded,
      DapSessionStatus.failed => RuntimeTaskStatus.failed,
    };
  }

  String _messageFromDap(DapSessionSnapshot snapshot) {
    if (snapshot.failureMessage != null) {
      return snapshot.failureMessage!;
    }
    return 'DAP session ${snapshot.status.name}: '
        '${snapshot.events.length} events, '
        '${snapshot.pendingRequests.length} pending requests.';
  }

  bool _terminalStatus(RuntimeTaskStatus status) {
    return switch (status) {
      RuntimeTaskStatus.succeeded ||
      RuntimeTaskStatus.failed ||
      RuntimeTaskStatus.cancelled ||
      RuntimeTaskStatus.blocked => true,
      RuntimeTaskStatus.queued ||
      RuntimeTaskStatus.starting ||
      RuntimeTaskStatus.running => false,
    };
  }
}
