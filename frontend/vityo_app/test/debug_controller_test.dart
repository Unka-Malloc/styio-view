import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_launcher.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_transport.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_runtime_task_history.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime_output_channels.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/debug_controller.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  DapSessionSnapshot snapshot({
    List<DapThread> threads = const <DapThread>[],
    List<DapStackFrame> frames = const <DapStackFrame>[],
    List<DapScope> scopes = const <DapScope>[],
    List<DapVariable> variables = const <DapVariable>[],
    int? activeThreadId,
  }) {
    return DapSessionSnapshot(
      status: DapSessionStatus.paused,
      nextSeq: 1,
      pendingRequests: const <DapPendingRequest>[],
      events: const <DapObservedEvent>[],
      threads: threads,
      stackFrames: frames,
      scopes: scopes,
      variables: variables,
      activeThreadId: activeThreadId,
    );
  }

  test(
    'configured debug controller owns command logging and runtime gate',
    () async {
      final logs = <String>[];
      final controller = DebugController.configured(
        toolchainManager: null,
        workspaceRoot: () => '/workspace/demo',
        launcher: null,
        runtimeOutputBuffer: RuntimeOutputLiveBuffer(),
        runtimeTaskHistoryBinder: const DebugRuntimeTaskHistoryBinder(),
        runtimeTaskHistoryStore: null,
        runtimeTaskHistoryWorkspaceId: 'demo',
        runtimeTaskHistoryMaxEntries: 10,
        log: logs.add,
      );
      addTearDown(controller.dispose);

      final breakpoint = controller.toggleBreakpointAt(
        filePath: '/workspace/demo/main.styio',
        line: 2,
      );
      final start = await controller.startConfiguredSession();

      expect(breakpoint.applied, isTrue);
      expect(controller.breakpoints.single.line, 2);
      expect(controller.agentContext.status, 'blocked');
      expect(controller.agentContext.breakpointCount, 1);
      expect(
        controller.agentContext.breakpoints.single.filePath,
        '/workspace/demo/main.styio',
      );
      expect(controller.agentContext.breakpoints.single.line, 2);
      expect(start.applied, isFalse);
      expect(start.message, contains('no toolchain manager'));
      expect(logs.first, contains('Added breakpoint'));
      expect(logs.last, start.message);
    },
  );

  test('debug controller requests paused DAP facts in dependency order', () {
    final controller = DebugController();
    var nextSeq = 10;
    int reserveSeq() => nextSeq++;

    final stackTrace = controller.nextInspectionRequest(
      snapshot(activeThreadId: 7),
      reserveSeq: reserveSeq,
    );
    final scopes = controller.nextInspectionRequest(
      snapshot(
        activeThreadId: 7,
        frames: const <DapStackFrame>[
          DapStackFrame(
            id: 11,
            name: 'main',
            sourcePath: 'src/main.styio',
            line: 3,
            column: 1,
          ),
        ],
      ),
      reserveSeq: reserveSeq,
    );
    final variables = controller.nextInspectionRequest(
      snapshot(
        activeThreadId: 7,
        frames: const <DapStackFrame>[
          DapStackFrame(
            id: 11,
            name: 'main',
            sourcePath: 'src/main.styio',
            line: 3,
            column: 1,
          ),
        ],
        scopes: const <DapScope>[
          DapScope(name: 'Locals', variablesReference: 23),
        ],
      ),
      reserveSeq: reserveSeq,
    );

    expect(stackTrace?.command, 'stackTrace');
    expect(stackTrace?.arguments['threadId'], 7);
    expect(scopes?.command, 'scopes');
    expect(scopes?.arguments['frameId'], 11);
    expect(variables?.command, 'variables');
    expect(variables?.arguments['variablesReference'], 23);
    expect(nextSeq, 13);
  });

  test('debug controller owns DAP snapshot projection', () {
    final controller = DebugController();
    controller.syncFromDapSnapshot(
      snapshot(
        activeThreadId: 7,
        threads: const <DapThread>[DapThread(id: 7, name: 'main')],
        frames: const <DapStackFrame>[
          DapStackFrame(
            id: 11,
            name: 'main',
            sourcePath: 'src/main.styio',
            line: 3,
            column: 1,
          ),
        ],
        variables: const <DapVariable>[
          DapVariable(name: 'value', value: '42', type: 'Int'),
        ],
      ),
      message: 'paused',
    );

    expect(controller.session.status, DebugSessionStatus.paused);
    expect(controller.session.threads.single.id, '7');
    expect(controller.session.stackFrames.single.filePath, 'src/main.styio');
    expect(controller.session.variables.single.value, '42');
  });

  test(
    'debug controller owns continue and step-over state transitions',
    () async {
      final controller = DebugController();

      final blocked = await controller.continueSession();
      expect(blocked.applied, isFalse);
      expect(controller.session.status, DebugSessionStatus.blocked);

      controller.replaceSession(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.paused,
          message: 'paused',
        ),
      );
      final continued = await controller.continueSession();
      expect(continued.applied, isTrue);
      expect(controller.session.status, DebugSessionStatus.running);

      controller.replaceSession(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.paused,
          message: 'paused again',
        ),
      );
      final stepped = await controller.stepOverSession();
      expect(stepped.applied, isTrue);
      expect(controller.session.status, DebugSessionStatus.paused);
    },
  );

  test(
    'debug controller rejects frame and thread selection without DAP',
    () async {
      final controller = DebugController();
      controller.replaceSession(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.paused,
          message: 'paused',
        ),
      );

      final frame = await controller.selectStackFrame('11');
      expect(frame.applied, isFalse);
      expect(frame.message, contains('no DAP session'));

      controller.replaceSession(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.paused,
          message: 'paused again',
        ),
      );
      final thread = await controller.selectThread('7');
      expect(thread.applied, isFalse);
      expect(thread.message, contains('no DAP session'));
    },
  );

  test('debug controller replaces and detaches owned DAP resources', () async {
    final transports = <_FakeDapByteTransport>[];
    final launcher = DapDebugAdapterLauncher(
      transportFactory: (_) async {
        final transport = _FakeDapByteTransport();
        transports.add(transport);
        return transport;
      },
    );
    final first = await launcher.launch(_readyLaunch());
    final second = await launcher.launch(_readyLaunch());
    final controller = DebugController();

    await controller.attachSession(first, onSnapshot: (_) {});
    expect(controller.sessionHandle, same(first));
    await controller.attachSession(second, onSnapshot: (_) {});
    await Future<void>.delayed(Duration.zero);

    expect(transports.first.closed, isTrue);
    expect(controller.sessionHandle, same(second));
    final detached = await controller.detachSession();
    expect(detached, same(second));
    expect(controller.sessionHandle, isNull);
    await detached?.close();
    controller.dispose();
  });

  test('debug controller stops and closes its attached DAP session', () async {
    late _FakeDapByteTransport transport;
    final launcher = DapDebugAdapterLauncher(
      transportFactory: (_) async {
        transport = _FakeDapByteTransport();
        return transport;
      },
    );
    final handle = await launcher.launch(_readyLaunch());
    final launchSendCount = transport.sentCount;
    final controller = DebugController();
    await controller.attachSession(handle, onSnapshot: (_) {});

    final result = await controller.stopSession();
    await Future<void>.delayed(Duration.zero);

    expect(result.applied, isTrue);
    expect(controller.session.status, DebugSessionStatus.stopped);
    expect(controller.sessionHandle, isNull);
    expect(transport.sentCount, launchSendCount + 1);
    expect(transport.closed, isTrue);
    controller.dispose();
  });

  test('debug controller fails closed without a toolchain manager', () async {
    final controller = DebugController();
    final output = RuntimeOutputLiveBuffer();

    final result = await controller.startSession(
      toolchainManager: null,
      workspaceRoot: '/workspace',
      launcher: null,
      runtimeOutputBuffer: output,
      onSnapshot: (_) {},
    );

    expect(result.applied, isFalse);
    expect(result.message, contains('no toolchain manager'));
    expect(controller.session.status, DebugSessionStatus.blocked);
    controller.dispose();
    await output.dispose();
  });
}

DebugLaunchConfiguration _readyLaunch() {
  return DebugLaunchConfiguration.fromToolchainDescriptor(
    debugger: const ToolchainDescriptor(
      id: 'lldb-dap',
      kind: ToolchainKind.debugger,
      displayName: 'LLDB DAP',
      executablePath: '/debug/lldb-dap',
      metadata: <String, Object?>{
        'adapterProtocol': 'dap',
        'programPath': 'build/app',
      },
    ),
    workspaceRoot: '/workspace',
  );
}

final class _FakeDapByteTransport implements DapByteTransport {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  bool closed = false;
  int sentCount = 0;

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Future<void> send(List<int> bytes) async {
    sentCount += 1;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}
