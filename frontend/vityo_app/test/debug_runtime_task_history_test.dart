import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_runtime_task_history.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('debug runtime task history binder converts DAP snapshot to task', () {
    const launch = DebugLaunchConfiguration(
      readiness: DebugLaunchReadiness.ready,
      reason: 'ready',
      debuggerId: 'lldb-dap',
      debuggerLabel: 'LLDB DAP',
      debuggerExecutablePath: '/usr/bin/lldb-dap',
      adapterProtocol: 'dap',
      programPath: '/workspace/build/app',
      cwd: '/workspace',
    );
    const snapshot = DapSessionSnapshot(
      status: DapSessionStatus.paused,
      nextSeq: 4,
      pendingRequests: <DapPendingRequest>[],
      events: <DapObservedEvent>[
        DapObservedEvent(
          event: 'stopped',
          body: <String, Object?>{'reason': 'breakpoint'},
        ),
      ],
      threads: <DapThread>[DapThread(id: 1, name: 'main')],
      stackFrames: <DapStackFrame>[],
      scopes: <DapScope>[],
      variables: <DapVariable>[],
    );

    final task = const DebugRuntimeTaskHistoryBinder().toTaskSnapshot(
      launch: launch,
      adapterSnapshot: snapshot,
      taskId: 'debug.current',
      timestamp: DateTime.utc(2026, 5, 20),
    );

    expect(task.definition.id, 'debug.current');
    expect(task.status, RuntimeTaskStatus.running);
    expect(task.events.single.message, 'DAP event stopped.');
    expect(task.events.single.metadata['event'], 'stopped');
    expect(task.finishedAt, isNull);
  });

  test(
    'debug runtime task history binder persists terminal DAP task',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_debug_runtime_task_history_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final store = RuntimeTaskHistoryStore.fromDataStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
      );
      const launch = DebugLaunchConfiguration(
        readiness: DebugLaunchReadiness.ready,
        reason: 'ready',
        debuggerId: 'lldb-dap',
        debuggerLabel: 'LLDB DAP',
        debuggerExecutablePath: '/usr/bin/lldb-dap',
        adapterProtocol: 'dap',
        programPath: '/workspace/build/app',
        cwd: '/workspace',
      );
      const snapshot = DapSessionSnapshot(
        status: DapSessionStatus.terminated,
        nextSeq: 5,
        pendingRequests: <DapPendingRequest>[],
        events: <DapObservedEvent>[DapObservedEvent(event: 'terminated')],
        threads: <DapThread>[],
        stackFrames: <DapStackFrame>[],
        scopes: <DapScope>[],
        variables: <DapVariable>[],
      );

      final history = await const DebugRuntimeTaskHistoryBinder()
          .appendSnapshot(
            store: store,
            workspaceId: 'demo',
            launch: launch,
            adapterSnapshot: snapshot,
            taskId: 'debug.current',
            timestamp: DateTime.utc(2026, 5, 20),
          );

      expect(history.tasks.single.definition.id, 'debug.current');
      expect(history.tasks.single.status, RuntimeTaskStatus.succeeded);
      final restored = await store.readHistory(workspaceId: 'demo');
      expect(
        restored.tasks.single.events.single.metadata['event'],
        'terminated',
      );
    },
  );
}
