import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test(
    'debug launch contract builds DAP launch configuration from toolchain',
    () {
      final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
        debugger: const ToolchainDescriptor(
          id: 'lldb-dap',
          kind: ToolchainKind.debugger,
          displayName: 'LLDB DAP',
          executablePath: '/usr/bin/lldb-dap',
          metadata: <String, Object?>{
            'adapterProtocol': 'dap',
            'programPath': 'build/vityo',
            'cwd': 'build',
            'debugAdapterArguments': <String>['--stdio'],
            'arguments': <String>['--smoke'],
            'environment': <String, Object?>{'VITYO_ENV': 'test'},
            'stopOnEntry': true,
          },
        ),
        workspaceRoot: '/workspace/vityo',
        breakpoints: const <DebugLaunchBreakpoint>[
          DebugLaunchBreakpoint(filePath: 'src/main.cc', line: 2),
        ],
      );

      final json = launch.toJson();

      expect(launch.ready, isTrue);
      expect(json['readiness'], 'ready');
      expect(json['adapterProtocol'], 'dap');
      expect(json['programPath'], '/workspace/vityo/build/vityo');
      expect(json['cwd'], '/workspace/vityo/build');
      expect(json['debuggerArguments'], <String>['--stdio']);
      expect(json['arguments'], <String>['--smoke']);
      expect(json['environment'], <String, String>{'VITYO_ENV': 'test'});
      expect(json['stopOnEntry'], isTrue);
      expect(json['breakpointCount'], 1);
    },
  );

  test('debug launch contract blocks debugger without launch program', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'lldb-dap',
        kind: ToolchainKind.debugger,
        displayName: 'LLDB DAP',
        executablePath: '/usr/bin/lldb-dap',
        metadata: <String, Object?>{'adapterProtocol': 'dap'},
      ),
      workspaceRoot: '/workspace/vityo',
    );

    expect(launch.ready, isFalse);
    expect(launch.readiness, DebugLaunchReadiness.missingProgram);
    expect(launch.reason, contains('metadata.programPath'));
  });

  test('debug launch contract blocks unsupported adapter protocol', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'custom-debugger',
        kind: ToolchainKind.debugger,
        displayName: 'Custom Debugger',
        executablePath: '/usr/bin/custom-debugger',
        metadata: <String, Object?>{
          'adapterProtocol': 'custom',
          'programPath': '/tmp/app',
        },
      ),
      workspaceRoot: '/workspace/vityo',
    );

    expect(launch.ready, isFalse);
    expect(launch.readiness, DebugLaunchReadiness.unsupportedProtocol);
    expect(launch.reason, contains('unsupported protocol custom'));
  });
}
