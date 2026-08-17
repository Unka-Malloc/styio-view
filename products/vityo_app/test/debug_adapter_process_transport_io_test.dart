import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_process_transport_io.dart';

import 'support/vityod_test_harness.dart';

void main() {
  VityodTestHarness? vityod;

  setUpAll(() async {
    if (!VityodTestHarness.isSupported) return;
    vityod = await VityodTestHarness.start(clientId: 'dap-transport-test');
  });

  tearDownAll(() => vityod?.close());

  test(
    'DAP byte transport streams through the real daemon process owner',
    () async {
      final transport = DapProcessTransport(
        executable: Platform.isMacOS ? '/bin/cat' : '/usr/bin/cat',
        client: vityod!.client,
      );
      await transport.start();
      final echoed = transport.incomingBytes.first;
      await transport.send(<int>[100, 97, 112, 45, 111, 107, 10]);

      expect(await echoed.timeout(const Duration(seconds: 5)), <int>[
        100,
        97,
        112,
        45,
        111,
        107,
        10,
      ]);
      expect((await transport.shutdown()).processTerminated, isTrue);
    },
    skip: !VityodTestHarness.isSupported
        ? 'Unix vityod transport only.'
        : false,
  );

  test('DAP process shutdown escalates from terminate to kill', () async {
    final process = _FakeManagedProcess(exitOnKill: true);
    final transport = DapProcessTransport(
      executable: 'fixture-debugger',
      processStarter: (_) async => process,
      terminateGrace: Duration.zero,
      killGrace: const Duration(seconds: 1),
    );
    await transport.start();

    final result = await transport.shutdown();

    expect(result.status, DapProcessShutdownStatus.exitedAfterKill);
    expect(result.processTerminated, isTrue);
    expect(result.orphanDetected, isFalse);
    expect(result.exitCode, -1);
    expect(process.terminateCalls, 1);
    expect(process.killCalls, 1);
    expect(process.closeInputCalls, 1);
    expect(transport.lastShutdownResult, same(result));
  });

  test('DAP process shutdown reports an orphan after bounded kill', () async {
    final process = _FakeManagedProcess();
    final transport = DapProcessTransport(
      executable: 'fixture-debugger',
      processStarter: (_) async => process,
      terminateGrace: Duration.zero,
      killGrace: Duration.zero,
    );
    await transport.start();

    final result = await transport.shutdown();

    expect(result.status, DapProcessShutdownStatus.orphaned);
    expect(result.processTerminated, isFalse);
    expect(result.orphanDetected, isTrue);
    expect(result.toJson()['orphanDetected'], isTrue);
    expect(process.killCalls, 1);
  });

  test('DAP process shutdown is idempotent for concurrent callers', () async {
    final process = _FakeManagedProcess(exitOnTerminate: true);
    final transport = DapProcessTransport(
      executable: 'fixture-debugger',
      processStarter: (_) async => process,
    );
    await transport.start();

    final results = await Future.wait(<Future<DapProcessShutdownResult>>[
      transport.shutdown(),
      transport.shutdown(),
    ]);

    expect(results[1], same(results[0]));
    expect(results.first.status, DapProcessShutdownStatus.exitedAfterTerminate);
    expect(process.terminateCalls, 1);
    expect(process.killCalls, 0);
  });
}

final class _FakeManagedProcess implements DapManagedProcess {
  _FakeManagedProcess({this.exitOnTerminate = false, this.exitOnKill = false});

  final bool exitOnTerminate;
  final bool exitOnKill;
  final Completer<int> _exit = Completer<int>();
  int terminateCalls = 0;
  int killCalls = 0;
  int closeInputCalls = 0;

  @override
  int get pid => 4242;
  @override
  Stream<List<int>> get stdoutBytes => const Stream<List<int>>.empty();
  @override
  Stream<List<int>> get stderrBytes => const Stream<List<int>>.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  void write(List<int> bytes) {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> closeInput() async {
    closeInputCalls += 1;
  }

  @override
  bool terminate() {
    terminateCalls += 1;
    if (exitOnTerminate && !_exit.isCompleted) {
      _exit.complete(0);
    }
    return true;
  }

  @override
  bool kill() {
    killCalls += 1;
    if (exitOnKill && !_exit.isCompleted) {
      _exit.complete(-1);
    }
    return true;
  }
}
