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

  test('hosted execution codec decodes diagnostic fallbacks and logs', () {
    const activeFilePath =
        '/tmp/styio-hosted/workspaces/demo-workspace/src/main.styio';
    final result = executionSessionFromHostedResponse(
      response: <String, dynamic>{
        'returncode': 0,
        'payload': <String, dynamic>{
          'stdout': ' first line\n\nsecond line ',
          'stderr': ' warning line\n ',
          'runtime_events': <Map<String, dynamic>>[
            <String, dynamic>{
              'schemaVersion': 2,
              'sessionId': 'runtime-session',
              'sequence': 7,
              'timestamp': 'not-a-date',
              'event_kind': 'run.started',
              'payload': <Object?, Object?>{
                'ok': true,
                3: 'ignored',
              },
            },
          ],
          'diagnostics': <Map<String, dynamic>>[
            <String, dynamic>{
              'category': 'warning',
              'text': 'warning text',
              'code': 'W',
              'subcode': '001',
              'span': <String, dynamic>{
                'start': <String, dynamic>{'offset': 9},
                'end': <String, dynamic>{'value': 3},
              },
            },
            <String, dynamic>{
              'category': 'type',
              'detail': 'type text',
              'location': <String, dynamic>{'offset': 4, 'length': -9},
            },
            <String, dynamic>{
              'severity': 'runtime',
              'reason': 'workspace suffix text',
              'file': '/tmp/hosted-run/workspace/src/main.styio',
              'range': <String, dynamic>{'startOffset': '1', 'endOffset': '2'},
            },
            <String, dynamic>{
              'raw': 'other file text',
              'file': '/tmp/hosted-run/workspace/src/other.styio',
              'range': <String, dynamic>{'start': 0, 'end': 1},
            },
            <String, dynamic>{'message': ''},
          ],
        },
      },
      workflowKind: 'run',
      successMessage: 'run completed through hosted control plane',
      documentText: '>_("demo")\n',
      activeFilePath: activeFilePath,
    );

    expect(result.session.status, ExecutionSessionStatus.succeeded);
    expect(result.session.sessionId, isNotEmpty);
    expect(result.session.statusMessage, contains('completed'));
    expect(result.session.stdoutEvents.map((event) => event.message), <String>[
      'first line',
      'second line',
    ]);
    final stderrMessages = result.session.stderrEvents
        .map((event) => event.message)
        .toList(growable: false);
    expect(stderrMessages, contains('warning line'));
    expect(stderrMessages, contains(contains('other.styio')));
    expect(result.session.diagnostics, hasLength(3));
    expect(result.session.diagnostics[0].severity.name, 'warning');
    expect(result.session.diagnostics[0].code, 'W:001');
    expect(result.session.diagnostics[0].range.start, 3);
    expect(result.session.diagnostics[0].range.end, 9);
    expect(result.session.diagnostics[1].severity.name, 'error');
    expect(result.session.diagnostics[1].range.start, 4);
    expect(result.session.diagnostics[1].range.end, 4);
    expect(result.session.diagnostics[2].message, 'workspace suffix text');
    expect(result.session.diagnostics[2].range.start, 1);
    expect(result.session.diagnostics[2].range.end, 2);
    expect(result.runtimeEvents.single.schemaVersion, 2);
    expect(result.runtimeEvents.single.sessionId, 'runtime-session');
    expect(
      result.runtimeEvents.single.timestamp,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(result.runtimeEvents.single.payload, <String, Object?>{'ok': true});
  });

  test('hosted execution codec uses top level fallback payload fields', () {
    final result = executionSessionFromHostedResponse(
      response: <String, dynamic>{
        'returncode': 1,
        'stdout': 'top stdout',
        'stderr': 'top stderr',
      },
      workflowKind: 'check',
      successMessage: 'check completed',
      documentText: 'abc',
      activeFilePath: '',
    );

    expect(result.session.status, ExecutionSessionStatus.failed);
    expect(result.session.statusMessage, contains('check failed'));
    expect(result.session.sessionId, isNotEmpty);
    expect(result.session.stdoutEvents.single.message, 'top stdout');
    expect(result.session.stderrEvents.single.message, 'top stderr');
    expect(result.runtimeEvents, isEmpty);
    expect(result.session.unitRange!.end, 3);
  });
}
