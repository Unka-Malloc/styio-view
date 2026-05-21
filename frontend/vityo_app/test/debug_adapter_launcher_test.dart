import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_launcher.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_transport.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_telemetry_store.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test(
    'DAP debug adapter launcher sends launch plan through transport',
    () async {
      late _FakeDapByteTransport fakeTransport;
      final launcher = DapDebugAdapterLauncher(
        transportFactory: (launch) async {
          fakeTransport = _FakeDapByteTransport();
          return fakeTransport;
        },
      );

      final handle = await launcher.launch(_readyLaunch());

      expect(handle.launchPlan.requests, hasLength(4));
      expect(fakeTransport.sentBytes, hasLength(4));
      expect(_decodedCommand(fakeTransport.sentBytes[0]), 'initialize');
      expect(_decodedCommand(fakeTransport.sentBytes[1]), 'setBreakpoints');
      expect(_decodedCommand(fakeTransport.sentBytes[2]), 'launch');
      expect(_decodedCommand(fakeTransport.sentBytes[3]), 'configurationDone');
      expect(handle.snapshot.status, DapSessionStatus.launching);
      expect(handle.snapshot.pendingRequests, hasLength(4));
      await handle.close();
    },
  );

  test(
    'DAP debug adapter execution plan launches through adapter launcher',
    () async {
      late _FakeDapByteTransport fakeTransport;
      final launcher = DapDebugAdapterLauncher(
        transportFactory: (launch) async {
          fakeTransport = _FakeDapByteTransport();
          return fakeTransport;
        },
      );
      final plan = DapDebugAdapterExecutionPlan.fromConfiguration(
        profileId: 'debug-styio',
        launchConfiguration: _readyLaunch(),
      );

      final handle = await launcher.launchExecutionPlan(plan);

      expect(plan.ready, isTrue);
      expect(plan.outputBinding.outputChannel.toJson()['kind'], 'debug');
      expect(plan.outputSubscriptionPlan().toJson()['status'], 'pending');
      expect(plan.toJson()['status'], 'ready');
      expect(fakeTransport.sentBytes, hasLength(4));
      expect(handle.launchConfiguration.debuggerId, 'lldb-dap');
      await handle.close();
    },
  );

  test(
    'DAP debug session termination plan chooses graceful and forced routes',
    () async {
      final launcher = DapDebugAdapterLauncher(
        transportFactory: (launch) async => _FakeDapByteTransport(),
      );
      final handle = await launcher.launch(_readyLaunch());

      final graceful = handle.terminationPlan();
      final forced = handle.terminationPlan(
        force: true,
        processHandleAvailable: true,
      );
      final finished = DebugSessionTerminationPlan.fromSnapshot(
        debuggerId: 'lldb-dap',
        snapshot: const DapSessionSnapshot(
          status: DapSessionStatus.terminated,
          nextSeq: 1,
          pendingRequests: <DapPendingRequest>[],
          events: <DapObservedEvent>[],
          threads: <DapThread>[],
          stackFrames: <DapStackFrame>[],
          scopes: <DapScope>[],
          variables: <DapVariable>[],
        ),
      );

      expect(graceful.action, DebugSessionTerminationAction.dapDisconnect);
      expect(graceful.requiresConfirmation, isFalse);
      expect(forced.action, DebugSessionTerminationAction.killProcess);
      expect(forced.requiresConfirmation, isTrue);
      expect(forced.toJson()['processHandleAvailable'], isTrue);
      expect(finished.canTerminate, isFalse);
      await handle.close();
    },
  );

  test('DAP debug session termination executor sends disconnect', () async {
    late _FakeDapByteTransport fakeTransport;
    final launcher = DapDebugAdapterLauncher(
      transportFactory: (launch) async {
        fakeTransport = _FakeDapByteTransport();
        return fakeTransport;
      },
    );
    final handle = await launcher.launch(_readyLaunch());

    final result = await const DebugSessionTerminationExecutor().execute(
      handle: handle,
      plan: handle.terminationPlan(),
      reason: 'User stopped debugging.',
    );

    expect(result.status, DebugSessionTerminationExecutionStatus.executed);
    expect(result.requestCommand, 'disconnect');
    expect(result.toJson()['status'], 'executed');
    expect(_decodedCommand(fakeTransport.sentBytes.last), 'disconnect');
  });

  test('DAP debug session termination executor binds process killer', () async {
    late _FakeDapByteTransport fakeTransport;
    final launcher = DapDebugAdapterLauncher(
      transportFactory: (launch) async {
        fakeTransport = _FakeDapByteTransport();
        return fakeTransport;
      },
    );
    final killedDebuggers = <String>[];
    final handle = await launcher.launch(_readyLaunch());
    final executor = DebugSessionTerminationExecutor(
      processTerminationHandler:
          ({required handle, required plan, required reason}) async {
            killedDebuggers.add(plan.debuggerId);
            return const DebugProcessTerminationResult.accepted(
              message: 'Killed debug adapter process.',
              metadata: <String, Object?>{'pid': 9001},
            );
          },
    );

    final result = await executor.execute(
      handle: handle,
      plan: handle.terminationPlan(force: true, processHandleAvailable: true),
      reason: 'Force stop.',
    );

    expect(result.status, DebugSessionTerminationExecutionStatus.executed);
    expect(result.plan.action, DebugSessionTerminationAction.killProcess);
    expect(result.processResult?.processTerminated, isTrue);
    expect(killedDebuggers, <String>['lldb-dap']);
    expect(_decodedCommand(fakeTransport.sentBytes.last), isNot('disconnect'));
  });

  test('DAP debug launch telemetry store persists execution records', () async {
    final store = DebugLaunchTelemetryStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    final plan = DapDebugAdapterExecutionPlan.fromConfiguration(
      profileId: 'debug-styio',
      launchConfiguration: _readyLaunch(),
    );
    final record = DebugLaunchTelemetryRecord.fromExecutionPlan(
      workspaceId: 'demo',
      plan: plan,
      status: DebugLaunchTelemetryStatus.planned,
      timestamp: DateTime.utc(2026, 5, 20, 15),
    );

    await store.record(record: record);

    final restored = await store.readSnapshot(workspaceId: 'demo');

    expect(restored.records.single.profileId, 'debug-styio');
    expect(restored.records.single.debuggerId, 'lldb-dap');
    expect(restored.records.single.planStatus, 'ready');
    expect(restored.records.single.ready, isTrue);
    expect(restored.records.single.metadata['outputChannelId'], isNotEmpty);
    expect(restored.toJson()['recordCount'], 1);
    expect(await store.clearSnapshot(workspaceId: 'demo'), isTrue);
    expect((await store.readSnapshot(workspaceId: 'demo')).records, isEmpty);
  });

  test('DAP debug launch telemetry binds to runtime output events', () {
    final plan = DapDebugAdapterExecutionPlan.fromConfiguration(
      profileId: 'debug-styio',
      launchConfiguration: _readyLaunch(),
    );
    final telemetry = DebugLaunchTelemetrySnapshot(
      workspaceId: 'demo',
      records: <DebugLaunchTelemetryRecord>[
        DebugLaunchTelemetryRecord.fromExecutionPlan(
          workspaceId: 'demo',
          plan: plan,
          status: DebugLaunchTelemetryStatus.launched,
          message: 'Debug launched.',
          timestamp: DateTime.utc(2026, 5, 20, 16),
        ),
      ],
    );

    final binding = DebugLaunchRuntimeOutputBinding(
      telemetry: telemetry,
      plan: plan,
    );
    final outputSnapshot = binding.outputPanelSnapshot(
      timestamp: DateTime.utc(2026, 5, 20, 16),
      channelId: 'debug.demo',
    );

    expect(outputSnapshot.events, hasLength(3));
    expect(outputSnapshot.events.first.kind, RuntimeOutputChannelKind.debug);
    expect(outputSnapshot.events.first.metadata['planStatus'], 'ready');
    expect(
      outputSnapshot.events[1].kind,
      RuntimeOutputChannelKind.runtimeEvents,
    );
    expect(outputSnapshot.events[1].metadata['recordCount'], 1);
    expect(
      outputSnapshot.events.last.message,
      'launched debug-styio: Debug launched.',
    );
    expect(outputSnapshot.events.last.metadata['successful'], isTrue);
    expect(binding.toJson()['outputEventCount'], 3);
  });

  test(
    'DAP debug runtime execution adapter launches and emits telemetry',
    () async {
      late _FakeDapByteTransport fakeTransport;
      final launcher = DapDebugAdapterLauncher(
        transportFactory: (launch) async {
          fakeTransport = _FakeDapByteTransport();
          return fakeTransport;
        },
      );
      final plan = DapDebugAdapterExecutionPlan.fromConfiguration(
        profileId: 'debug-styio',
        launchConfiguration: _readyLaunch(),
      );
      final buffer = RuntimeOutputLiveBuffer();
      final adapter = DebugRuntimeExecutionAdapter(
        launcher: launcher,
        workspaceId: 'demo',
        clock: () => DateTime.utc(2026, 5, 20, 17),
      );

      final result = await adapter.executePlan(plan: plan, buffer: buffer);

      expect(result.launched, isTrue);
      expect(
        result.dispatchResult.status,
        RuntimeExecutionDispatchStatus.dispatched,
      );
      expect(result.handle, isNotNull);
      expect(
        result.telemetry.records.single.status,
        DebugLaunchTelemetryStatus.launched,
      );
      expect(fakeTransport.sentBytes, hasLength(4));
      expect(
        buffer.snapshot.visibleEvents
            .map((event) => event.metadata['debugRuntimeExecution'])
            .whereType<String>(),
        contains('dap-launcher'),
      );
      expect(
        result.outputEvents.map((event) => event.message),
        contains(
          'launched debug-styio: Debug adapter launched through runtime execution route.',
        ),
      );
      final cancelled = await adapter.cancelExecution(
        execution: result,
        buffer: buffer,
        reason: 'User cancelled debug session.',
      );

      expect(cancelled.status, DebugRuntimeExecutionStatus.cancelled);
      expect(
        cancelled.telemetry.records.single.status,
        DebugLaunchTelemetryStatus.cancelled,
      );
      expect(
        cancelled.outputEvents.map((event) => event.message),
        contains('cancelled debug-styio: User cancelled debug session.'),
      );
      expect(
        cancelled.terminationExecution?.status,
        DebugSessionTerminationExecutionStatus.executed,
      );
      expect(_decodedCommand(fakeTransport.sentBytes.last), 'disconnect');
    },
  );

  test('DAP debug adapter launcher exposes live session event state', () async {
    const codec = DapContentFrameCodec();
    late _FakeDapByteTransport fakeTransport;
    final launcher = DapDebugAdapterLauncher(
      transportFactory: (launch) async {
        fakeTransport = _FakeDapByteTransport();
        return fakeTransport;
      },
    );

    final handle = await launcher.launch(_readyLaunch());
    fakeTransport.addInbound(
      codec.encode(const <String, Object?>{
        'type': 'event',
        'event': 'stopped',
        'body': <String, Object?>{'reason': 'breakpoint', 'threadId': 1},
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handle.snapshot.status, DapSessionStatus.paused);
    expect(handle.snapshot.events.single.event, 'stopped');
    await handle.close();
  });

  test(
    'DAP debug adapter launcher refuses unready launch configuration',
    () async {
      final launcher = DapDebugAdapterLauncher(
        transportFactory: (launch) async => _FakeDapByteTransport(),
      );

      expect(
        () => launcher.launch(_missingProgramLaunch()),
        throwsA(isA<StateError>()),
      );
    },
  );
}

String _decodedCommand(List<int> bytes) {
  const codec = DapContentFrameCodec();
  return codec.decodeFirst(bytes)!.message['command']! as String;
}

DebugLaunchConfiguration _readyLaunch() {
  return DebugLaunchConfiguration.fromToolchainDescriptor(
    debugger: const ToolchainDescriptor(
      id: 'lldb-dap',
      kind: ToolchainKind.debugger,
      displayName: 'LLDB DAP',
      executablePath: '/usr/bin/lldb-dap',
      metadata: <String, Object?>{
        'adapterProtocol': 'dap',
        'programPath': 'build/vityo',
      },
    ),
    workspaceRoot: '/workspace/vityo',
    breakpoints: const <DebugLaunchBreakpoint>[
      DebugLaunchBreakpoint(filePath: 'src/main.cc', line: 0),
    ],
  );
}

DebugLaunchConfiguration _missingProgramLaunch() {
  return DebugLaunchConfiguration.fromToolchainDescriptor(
    debugger: const ToolchainDescriptor(
      id: 'lldb-dap',
      kind: ToolchainKind.debugger,
      displayName: 'LLDB DAP',
      executablePath: '/usr/bin/lldb-dap',
      metadata: <String, Object?>{'adapterProtocol': 'dap'},
    ),
    workspaceRoot: '/workspace/vityo',
  );
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_debug_launch_telemetry_test_',
  );
  addTearDown(() => tempRoot.delete(recursive: true));
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}

class _FakeDapByteTransport implements DapByteTransport {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentBytes = <List<int>>[];

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Future<void> send(List<int> bytes) async {
    sentBytes.add(List<int>.unmodifiable(bytes));
  }

  void addInbound(List<int> bytes) {
    _incoming.add(bytes);
  }

  @override
  Future<void> close() {
    return _incoming.close();
  }
}
