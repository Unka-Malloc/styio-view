import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test('DAP content frame codec encodes and decodes JSON messages', () {
    const codec = DapContentFrameCodec();
    final encoded = codec.encode(const <String, Object?>{
      'seq': 1,
      'type': 'request',
      'command': 'initialize',
    });

    final header = ascii.decode(encoded.take(24).toList());
    final decoded = codec.decodeFirst(encoded);

    expect(header, startsWith('Content-Length:'));
    expect(decoded?.message['command'], 'initialize');
    expect(decoded?.consumedBytes, encoded.length);
  });

  test('DAP content frame codec waits for partial body', () {
    const codec = DapContentFrameCodec();
    final encoded = codec.encode(const <String, Object?>{
      'seq': 1,
      'type': 'request',
      'command': 'threads',
    });

    expect(
      codec.decodeFirst(encoded.take(encoded.length - 2).toList()),
      isNull,
    );
  });

  test(
    'DAP launch request plan follows initialize breakpoints launch order',
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
            'arguments': <String>['--smoke'],
          },
        ),
        workspaceRoot: '/workspace/vityo',
        breakpoints: const <DebugLaunchBreakpoint>[
          DebugLaunchBreakpoint(filePath: 'src/main.cc', line: 0),
          DebugLaunchBreakpoint(filePath: 'src/lib.cc', line: 4),
        ],
      );

      final plan = DapLaunchRequestPlan.fromLaunchConfiguration(launch: launch);
      final json = plan.toJson();
      final requests = json['requests']! as List<Object?>;

      expect(json['requestCount'], 5);
      expect((requests[0]! as Map<String, Object?>)['command'], 'initialize');
      expect(
        (requests[1]! as Map<String, Object?>)['command'],
        'setBreakpoints',
      );
      expect(
        (requests[2]! as Map<String, Object?>)['command'],
        'setBreakpoints',
      );
      expect((requests[3]! as Map<String, Object?>)['command'], 'launch');
      expect(
        (requests[4]! as Map<String, Object?>)['command'],
        'configurationDone',
      );
      final setBreakpointsArguments =
          (requests[1]! as Map<String, Object?>)['arguments']!
              as Map<String, Object?>;
      final breakpoints =
          setBreakpointsArguments['breakpoints']! as List<Object?>;
      expect((breakpoints.single! as Map<String, Object?>)['line'], 1);
      final launchArguments =
          (requests[3]! as Map<String, Object?>)['arguments']!
              as Map<String, Object?>;
      expect(launchArguments['program'], '/workspace/vityo/build/vityo');
      expect(launchArguments['args'], <String>['--smoke']);
    },
  );

  test('DAP request factory builds continue step and variable requests', () {
    const factory = DapProtocolRequestFactory();

    expect(factory.threads(seq: 1).toJson()['command'], 'threads');
    expect(factory.stackTrace(seq: 2, threadId: 9).toJson()['arguments'], {
      'threadId': 9,
    });
    expect(factory.scopes(seq: 3, frameId: 4).toJson()['arguments'], {
      'frameId': 4,
    });
    expect(
      factory.variables(seq: 4, variablesReference: 7).toJson()['arguments'],
      {'variablesReference': 7},
    );
    expect(
      factory.continueThread(seq: 5, threadId: 9).toJson()['command'],
      'continue',
    );
    expect(factory.next(seq: 6, threadId: 9).toJson()['command'], 'next');
  });
}
