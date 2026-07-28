import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_transport.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test('DAP transport bridge sends encoded launch plan requests', () async {
    final transport = _FakeDapByteTransport();
    final bridge = DapSessionTransportBridge(transport: transport);
    final plan = DapLaunchRequestPlan.fromLaunchConfiguration(
      launch: _readyLaunch(),
    );

    await bridge.sendLaunchPlan(plan);

    expect(transport.sentBytes, hasLength(4));
    expect(_decodedCommand(transport.sentBytes.first), 'initialize');
    expect(_decodedCommand(transport.sentBytes[1]), 'setBreakpoints');
    expect(_decodedCommand(transport.sentBytes[2]), 'launch');
    expect(_decodedCommand(transport.sentBytes[3]), 'configurationDone');
    expect(bridge.snapshot.pendingRequests, hasLength(4));
    expect(bridge.snapshot.status, DapSessionStatus.launching);
  });

  test('DAP transport bridge accepts split inbound response frames', () async {
    const codec = DapContentFrameCodec();
    final transport = _FakeDapByteTransport();
    final bridge = DapSessionTransportBridge(transport: transport);
    bridge.attach();
    await bridge.sendRequest(
      const DapRequest(seq: 1, command: 'configurationDone'),
    );
    final response = codec.encode(const <String, Object?>{
      'type': 'response',
      'request_seq': 1,
      'command': 'configurationDone',
      'success': true,
    });

    transport.addInbound(response.take(8).toList());
    await Future<void>.delayed(Duration.zero);
    expect(bridge.snapshot.pendingRequests, hasLength(1));

    transport.addInbound(response.skip(8).toList());
    await Future<void>.delayed(Duration.zero);

    expect(bridge.snapshot.pendingRequests, isEmpty);
    expect(bridge.snapshot.status, DapSessionStatus.running);
    await bridge.close();
  });

  test(
    'DAP transport bridge emits session snapshots for outbound and inbound traffic',
    () async {
      const codec = DapContentFrameCodec();
      final transport = _FakeDapByteTransport();
      final bridge = DapSessionTransportBridge(transport: transport);
      final snapshots = <DapSessionSnapshot>[];
      final subscription = bridge.snapshotEvents.listen(snapshots.add);
      bridge.attach();

      await bridge.sendRequest(
        const DapRequest(seq: 1, command: 'configurationDone'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(snapshots, hasLength(1));
      expect(snapshots.single.status, DapSessionStatus.launching);
      expect(snapshots.single.pendingRequests, hasLength(1));

      transport.addInbound(
        codec.encode(const <String, Object?>{
          'type': 'response',
          'request_seq': 1,
          'command': 'configurationDone',
          'success': true,
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(snapshots.last.status, DapSessionStatus.running);
      expect(snapshots.last.pendingRequests, isEmpty);
      await subscription.cancel();
      await bridge.close();
    },
  );

  test('DAP transport bridge feeds stopped event into session state', () async {
    const codec = DapContentFrameCodec();
    final transport = _FakeDapByteTransport();
    final bridge = DapSessionTransportBridge(transport: transport);
    bridge.attach();

    transport.addInbound(
      codec.encode(const <String, Object?>{
        'type': 'event',
        'event': 'stopped',
        'body': <String, Object?>{'reason': 'breakpoint', 'threadId': 1},
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(bridge.snapshot.status, DapSessionStatus.paused);
    expect(bridge.snapshot.events.single.event, 'stopped');
    await bridge.close();
  });
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

class _FakeDapByteTransport implements DapByteTransport {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentBytes = <List<int>>[];
  var closed = false;

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
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}
