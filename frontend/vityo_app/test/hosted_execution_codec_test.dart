import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_execution_codec.dart';

void main() {
  test(
    'hosted execution codec maps overlay diagnostics back to the active document',
    () {
      const activeFilePath =
          '/tmp/styio-hosted/workspaces/demo-workspace/src/main.styio';
      final result = executionSessionFromHostedResponse(
        response: <String, dynamic>{
          'returncode': 1,
          'message': 'run failed through hosted control plane',
          'error_payload': <String, dynamic>{
            'session_id': 'hosted-session-1',
            'diagnostics': <Map<String, dynamic>>[
              <String, dynamic>{
                'category': 'parse',
                'severity': 'error',
                'file':
                    '/tmp/styio-hosted-overlay/run/workspace/src/main.styio',
                'message': 'unexpected token',
                'range': <String, dynamic>{'start': 2, 'end': 7},
              },
            ],
            'runtime_events': <Map<String, dynamic>>[
              <String, dynamic>{
                'schema_version': 1,
                'session_id': 'hosted-session-1',
                'sequence': 1,
                'timestamp': '2026-04-19T00:00:00Z',
                'eventKind': 'compile.failed',
                'origin': 'styio.compile-plan',
                'payload': <String, Object?>{'intent': 'run'},
              },
            ],
          },
        },
        workflowKind: 'run',
        successMessage: 'run completed through hosted control plane',
        documentText: '>_("demo")\n',
        activeFilePath: activeFilePath,
      );

      expect(result.session.status, ExecutionSessionStatus.failed);
      expect(result.session.sessionId, 'hosted-session-1');
      expect(result.session.diagnostics, hasLength(1));
      expect(result.session.diagnostics.single.message, 'unexpected token');
      expect(result.session.diagnostics.single.range.start, 2);
      expect(result.session.diagnostics.single.range.end, 7);
      expect(result.session.stderrEvents, isEmpty);
      expect(
        result.runtimeEvents.map((event) => event.eventKind),
        contains('compile.failed'),
      );
    },
  );

  test(
    'hosted execution codec keeps non-active-file diagnostics as log lines',
    () {
      const activeFilePath =
          '/tmp/styio-hosted/workspaces/demo-workspace/src/main.styio';
      final result = executionSessionFromHostedResponse(
        response: <String, dynamic>{
          'returncode': 1,
          'error_payload': <String, dynamic>{
            'session_id': 'hosted-session-2',
            'diagnostics': <Map<String, dynamic>>[
              <String, dynamic>{
                'category': 'parse',
                'severity': 'error',
                'file':
                    '/tmp/styio-hosted-overlay/run/workspace/src/other.styio',
                'message': 'unexpected token in sibling file',
                'range': <String, dynamic>{'start': 0, 'end': 4},
              },
            ],
          },
        },
        workflowKind: 'run',
        successMessage: 'run completed through hosted control plane',
        documentText: '>_("demo")\n',
        activeFilePath: activeFilePath,
      );

      expect(result.session.diagnostics, isEmpty);
      expect(result.session.stderrEvents, hasLength(1));
      expect(
        result.session.stderrEvents.single.message,
        contains('other.styio: unexpected token in sibling file'),
      );
    },
  );

  test('hosted execution codec parses top-level failure envelopes', () {
    const activeFilePath =
        '/tmp/styio-hosted/workspaces/demo-workspace/src/main.styio';
    final result = executionSessionFromHostedResponse(
      response: <String, dynamic>{
        'returncode': 1,
        'message': 'top-level hosted failure',
        'session_id': 'hosted-top-level-failure',
        'diagnostics': <Map<String, dynamic>>[
          <String, dynamic>{
            'category': 'syntax',
            'severity': 'error',
            'file': activeFilePath,
            'message': 'missing expression',
            'offset': 3,
            'length': 4,
          },
        ],
        'runtime_events': <Map<String, dynamic>>[
          <String, dynamic>{
            'schema_version': 1,
            'session_id': 'hosted-top-level-failure',
            'sequence': 7,
            'timestamp': '2026-05-18T00:00:00Z',
            'event_kind': 'compile.failed',
            'origin': 'styio.hosted',
            'payload': <String, Object?>{'phase': 'parse'},
          },
        ],
        'stderr': 'compiler stderr line',
      },
      workflowKind: 'run',
      successMessage: 'run completed through hosted control plane',
      documentText: '>_("demo")\n',
      activeFilePath: activeFilePath,
    );

    expect(result.session.status, ExecutionSessionStatus.failed);
    expect(result.session.sessionId, 'hosted-top-level-failure');
    expect(result.session.statusMessage, 'top-level hosted failure');
    expect(result.session.diagnostics, hasLength(1));
    expect(result.session.diagnostics.single.code, 'syntax');
    expect(result.session.diagnostics.single.message, 'missing expression');
    expect(result.session.diagnostics.single.range.start, 3);
    expect(result.session.diagnostics.single.range.end, 7);
    expect(
      result.runtimeEvents.map((event) => event.eventKind),
      <String>['compile.failed'],
    );
    expect(result.session.stderrEvents.last.message, 'compiler stderr line');
  });
}
