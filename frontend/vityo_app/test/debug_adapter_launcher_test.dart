import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_launcher.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_transport.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
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
