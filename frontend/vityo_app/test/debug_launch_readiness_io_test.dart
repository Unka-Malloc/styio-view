import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_readiness_io.dart';

void main() {
  test(
    'debug launch IO readiness accepts available debugger program and cwd',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_debug_launch_ready_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final program = File('${tempRoot.path}/demo')..writeAsStringSync('');
      final probe = DebugLaunchIoReadinessProbe(
        lookupExecutable: (name) async {
          return name == 'lldb-dap' ? '/usr/bin/lldb-dap' : null;
        },
      );

      final readiness = await probe.check(
        _launch(
          debuggerExecutablePath: 'lldb-dap',
          programPath: program.path,
          cwd: tempRoot.path,
        ),
      );

      expect(readiness.ready, isTrue);
      expect(readiness.resolvedDebuggerExecutablePath, '/usr/bin/lldb-dap');
    },
  );

  test('debug launch IO readiness blocks unready launch contract', () async {
    const probe = DebugLaunchIoReadinessProbe();

    final readiness = await probe.check(
      _launch(
        readiness: DebugLaunchReadiness.missingProgram,
        reason: 'missing program',
        programPath: null,
      ),
    );

    expect(readiness.ready, isFalse);
    expect(readiness.reason, 'missing program');
  });

  test(
    'debug launch IO readiness blocks missing debugger executable',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_debug_launch_missing_debugger_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final program = File('${tempRoot.path}/demo')..writeAsStringSync('');
      final probe = DebugLaunchIoReadinessProbe(
        lookupExecutable: (name) async => null,
      );

      final readiness = await probe.check(
        _launch(
          debuggerExecutablePath: 'missing-lldb-dap',
          programPath: program.path,
          cwd: tempRoot.path,
        ),
      );

      expect(readiness.ready, isFalse);
      expect(readiness.reason, contains('debugger executable'));
    },
  );

  test('debug launch IO readiness blocks missing program path', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_debug_launch_missing_program_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final probe = DebugLaunchIoReadinessProbe(
      lookupExecutable: (name) async => '/usr/bin/lldb-dap',
    );

    final readiness = await probe.check(
      _launch(programPath: '${tempRoot.path}/missing-demo', cwd: tempRoot.path),
    );

    expect(readiness.ready, isFalse);
    expect(readiness.reason, contains('program'));
  });

  test('debug launch IO readiness blocks missing cwd', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_debug_launch_missing_cwd_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final program = File('${tempRoot.path}/demo')..writeAsStringSync('');
    final probe = DebugLaunchIoReadinessProbe(
      lookupExecutable: (name) async => '/usr/bin/lldb-dap',
    );

    final readiness = await probe.check(
      _launch(programPath: program.path, cwd: '${tempRoot.path}/missing-cwd'),
    );

    expect(readiness.ready, isFalse);
    expect(readiness.reason, contains('cwd'));
  });
}

DebugLaunchConfiguration _launch({
  DebugLaunchReadiness readiness = DebugLaunchReadiness.ready,
  String reason = 'ready',
  String debuggerExecutablePath = 'lldb-dap',
  String? programPath = '/workspace/demo',
  String cwd = '/workspace',
}) {
  return DebugLaunchConfiguration(
    readiness: readiness,
    reason: reason,
    debuggerId: 'lldb-dap',
    debuggerLabel: 'LLDB DAP',
    debuggerExecutablePath: debuggerExecutablePath,
    adapterProtocol: 'dap',
    programPath: programPath,
    cwd: cwd,
  );
}
