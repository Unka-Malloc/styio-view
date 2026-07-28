import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_session.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test('DAP session records launch plan pending requests', () {
    final launch = _readyLaunch();
    final plan = DapLaunchRequestPlan.fromLaunchConfiguration(launch: launch);
    final session = DapSessionController();

    session.recordLaunchPlan(plan);
    final snapshot = session.snapshot.toJson();

    expect(snapshot['status'], 'launching');
    expect(snapshot['pendingRequestCount'], 4);
    expect(snapshot['nextSeq'], 5);
    expect(
      (snapshot['pendingRequests']! as List<Object?>).map(
        (request) => (request! as Map<String, Object?>)['command'],
      ),
      <String>['initialize', 'setBreakpoints', 'launch', 'configurationDone'],
    );
  });

  test('DAP session clears pending responses and tracks stopped events', () {
    final session = DapSessionController();
    session.recordOutboundRequest(
      const DapRequest(seq: 1, command: 'initialize'),
    );
    session.recordOutboundRequest(
      const DapRequest(seq: 2, command: 'configurationDone'),
    );

    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 1,
      'command': 'initialize',
      'success': true,
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 2,
      'command': 'configurationDone',
      'success': true,
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'event',
      'event': 'stopped',
      'body': <String, Object?>{'reason': 'breakpoint', 'threadId': 7},
    });

    final snapshot = session.snapshot.toJson();

    expect(snapshot['status'], 'paused');
    expect(snapshot['activeThreadId'], 7);
    expect(snapshot['pendingRequestCount'], 0);
    expect(
      (snapshot['lastResponse']! as Map<String, Object?>)['command'],
      'configurationDone',
    );
    expect(snapshot['eventCount'], 1);
    expect(
      (((snapshot['events']! as List<Object?>).single!
              as Map<String, Object?>)['body']!
          as Map<String, Object?>)['reason'],
      'breakpoint',
    );
  });

  test('DAP session marks failed response as failed', () {
    final session = DapSessionController();
    session.recordOutboundRequest(const DapRequest(seq: 1, command: 'launch'));

    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 1,
      'command': 'launch',
      'success': false,
      'message': 'program missing',
    });

    final snapshot = session.snapshot.toJson();

    expect(snapshot['status'], 'failed');
    expect(snapshot['failureMessage'], 'program missing');
    expect(snapshot['pendingRequestCount'], 0);
  });

  test('DAP session parses stack trace and variable response bodies', () {
    final session = DapSessionController();

    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 1,
      'command': 'threads',
      'success': true,
      'body': <String, Object?>{
        'threads': <Object?>[
          <String, Object?>{'id': 1, 'name': 'main thread'},
        ],
      },
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 2,
      'command': 'stackTrace',
      'success': true,
      'body': <String, Object?>{
        'stackFrames': <Object?>[
          <String, Object?>{
            'id': 11,
            'name': 'main',
            'source': <String, Object?>{'path': 'src/main.cc'},
            'line': 12,
            'column': 3,
          },
        ],
      },
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 3,
      'command': 'scopes',
      'success': true,
      'body': <String, Object?>{
        'scopes': <Object?>[
          <String, Object?>{
            'name': 'Locals',
            'variablesReference': 101,
            'expensive': false,
          },
        ],
      },
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 4,
      'command': 'variables',
      'success': true,
      'body': <String, Object?>{
        'variables': <Object?>[
          <String, Object?>{
            'name': 'argc',
            'value': '1',
            'type': 'int',
            'variablesReference': 0,
          },
        ],
      },
    });

    final snapshot = session.snapshot.toJson();
    final threads = snapshot['threads']! as List<Object?>;
    final stackFrames = snapshot['stackFrames']! as List<Object?>;
    final scopes = snapshot['scopes']! as List<Object?>;
    final variables = snapshot['variables']! as List<Object?>;

    expect(snapshot['threadCount'], 1);
    expect((threads.single! as Map<String, Object?>)['name'], 'main thread');
    expect(snapshot['stackFrameCount'], 1);
    expect((stackFrames.single! as Map<String, Object?>)['name'], 'main');
    expect(
      (stackFrames.single! as Map<String, Object?>)['sourcePath'],
      'src/main.cc',
    );
    expect(snapshot['scopeCount'], 1);
    expect((scopes.single! as Map<String, Object?>)['name'], 'Locals');
    expect((scopes.single! as Map<String, Object?>)['variablesReference'], 101);
    expect(snapshot['variableCount'], 1);
    expect((variables.single! as Map<String, Object?>)['name'], 'argc');
    expect((variables.single! as Map<String, Object?>)['type'], 'int');
  });

  test(
    'DAP session clears stopped facts after continued and terminated events',
    () {
      final session = DapSessionController();

      session.acceptMessage(const <String, Object?>{
        'type': 'event',
        'event': 'stopped',
        'body': <String, Object?>{'reason': 'breakpoint', 'threadId': 7},
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 1,
        'command': 'threads',
        'success': true,
        'body': <String, Object?>{
          'threads': <Object?>[
            <String, Object?>{'id': 7, 'name': 'main thread'},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 2,
        'command': 'stackTrace',
        'success': true,
        'body': <String, Object?>{
          'stackFrames': <Object?>[
            <String, Object?>{'id': 11, 'name': 'main', 'line': 12},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 3,
        'command': 'scopes',
        'success': true,
        'body': <String, Object?>{
          'scopes': <Object?>[
            <String, Object?>{'name': 'Locals', 'variablesReference': 101},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 4,
        'command': 'variables',
        'success': true,
        'body': <String, Object?>{
          'variables': <Object?>[
            <String, Object?>{'name': 'argc', 'value': '1'},
          ],
        },
      });

      expect(session.snapshot.activeThreadId, 7);
      expect(session.snapshot.threads, hasLength(1));
      expect(session.snapshot.stackFrames, hasLength(1));
      expect(session.snapshot.scopes, hasLength(1));
      expect(session.snapshot.variables, hasLength(1));

      session.acceptMessage(const <String, Object?>{
        'type': 'event',
        'event': 'continued',
        'body': <String, Object?>{'threadId': 7},
      });

      expect(session.snapshot.status, DapSessionStatus.running);
      expect(session.snapshot.activeThreadId, isNull);
      expect(session.snapshot.threads, isEmpty);
      expect(session.snapshot.stackFrames, isEmpty);
      expect(session.snapshot.scopes, isEmpty);
      expect(session.snapshot.variables, isEmpty);

      session.acceptMessage(const <String, Object?>{
        'type': 'event',
        'event': 'stopped',
        'body': <String, Object?>{'reason': 'step', 'threadId': 9},
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 5,
        'command': 'threads',
        'success': true,
        'body': <String, Object?>{
          'threads': <Object?>[
            <String, Object?>{'id': 9, 'name': 'worker thread'},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 6,
        'command': 'stackTrace',
        'success': true,
        'body': <String, Object?>{
          'stackFrames': <Object?>[
            <String, Object?>{'id': 12, 'name': 'worker', 'line': 20},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 7,
        'command': 'scopes',
        'success': true,
        'body': <String, Object?>{
          'scopes': <Object?>[
            <String, Object?>{'name': 'Locals', 'variablesReference': 202},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'response',
        'request_seq': 8,
        'command': 'variables',
        'success': true,
        'body': <String, Object?>{
          'variables': <Object?>[
            <String, Object?>{'name': 'count', 'value': '2'},
          ],
        },
      });
      session.acceptMessage(const <String, Object?>{
        'type': 'event',
        'event': 'terminated',
      });

      expect(session.snapshot.status, DapSessionStatus.terminated);
      expect(session.snapshot.activeThreadId, isNull);
      expect(session.snapshot.threads, isEmpty);
      expect(session.snapshot.stackFrames, isEmpty);
      expect(session.snapshot.scopes, isEmpty);
      expect(session.snapshot.variables, isEmpty);
    },
  );

  test('DAP session selects a thread from threads response while paused', () {
    final session = DapSessionController();

    session.acceptMessage(const <String, Object?>{
      'type': 'event',
      'event': 'stopped',
      'body': <String, Object?>{'reason': 'pause'},
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 1,
      'command': 'threads',
      'success': true,
      'body': <String, Object?>{
        'threads': <Object?>[
          <String, Object?>{'id': 5, 'name': 'worker thread'},
        ],
      },
    });

    expect(session.snapshot.status, DapSessionStatus.paused);
    expect(session.snapshot.activeThreadId, 5);
    expect(session.snapshot.threads.single.name, 'worker thread');
  });

  test('DAP session clears variables when a new scopes request starts', () {
    final session = DapSessionController();

    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 1,
      'command': 'stackTrace',
      'success': true,
      'body': <String, Object?>{
        'stackFrames': <Object?>[
          <String, Object?>{'id': 11, 'name': 'main'},
          <String, Object?>{'id': 12, 'name': 'worker'},
        ],
      },
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 2,
      'command': 'scopes',
      'success': true,
      'body': <String, Object?>{
        'scopes': <Object?>[
          <String, Object?>{'name': 'Locals', 'variablesReference': 101},
        ],
      },
    });
    session.acceptMessage(const <String, Object?>{
      'type': 'response',
      'request_seq': 3,
      'command': 'variables',
      'success': true,
      'body': <String, Object?>{
        'variables': <Object?>[
          <String, Object?>{'name': 'argc', 'value': '1'},
        ],
      },
    });

    expect(session.snapshot.variables.single.name, 'argc');

    session.recordOutboundRequest(const DapRequest(seq: 4, command: 'scopes'));

    expect(session.snapshot.scopes, isEmpty);
    expect(session.snapshot.variables, isEmpty);

    session.recordOutboundRequest(
      const DapRequest(
        seq: 5,
        command: 'stackTrace',
        arguments: <String, Object?>{'threadId': 2},
      ),
    );

    expect(session.snapshot.activeThreadId, 2);
    expect(session.snapshot.stackFrames, isEmpty);
  });

  test('DAP session accepts framed response bytes', () {
    const codec = DapContentFrameCodec();
    final session = DapSessionController(codec: codec);
    session.recordOutboundRequest(
      const DapRequest(seq: 1, command: 'configurationDone'),
    );

    final frame = session.acceptFrameBytes(
      codec.encode(const <String, Object?>{
        'type': 'response',
        'request_seq': 1,
        'command': 'configurationDone',
        'success': true,
      }),
    );

    expect(frame, isNotNull);
    expect(session.snapshot.pendingRequests, isEmpty);
    expect(session.snapshot.status, DapSessionStatus.running);
  });
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
