import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';

void main() {
  test(
    'agent tool call lifecycle exposes idle timeline without stale TODOs',
    () {
      final timeline = const AgentToolCallLifecycleTracker().track(
        const <AgentToolCallEvent>[],
      );
      final payload = timeline.toJson();

      expect(timeline.status, AgentToolCallTimelineStatus.idle);
      expect(timeline.todoItems, isEmpty);
      expect(payload.containsKey('todoItems'), isFalse);
    },
  );

  test('agent tool call lifecycle tracks input streaming through result', () {
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.inputStart(
            callId: 'call-1',
            toolId: 'previewWorkspaceEdit',
          ),
          const AgentToolCallEvent.inputDelta(
            callId: 'call-1',
            inputDelta: '{"ed',
          ),
          const AgentToolCallEvent.inputDelta(
            callId: 'call-1',
            inputDelta: 'its":[]}',
          ),
          const AgentToolCallEvent.inputEnd(callId: 'call-1'),
          const AgentToolCallEvent.callStarted(
            callId: 'call-1',
            toolId: 'previewWorkspaceEdit',
          ),
          const AgentToolCallEvent.result(
            callId: 'call-1',
            toolId: 'previewWorkspaceEdit',
            result: 'preview ready',
          ),
        ]);
    final call = timeline.callFor('call-1')!;

    expect(timeline.status, AgentToolCallTimelineStatus.complete);
    expect(timeline.callIds, <String>['call-1']);
    expect(call.status, AgentToolCallStatus.completed);
    expect(call.inputComplete, isTrue);
    expect(call.inputText, '{"edits":[]}');
    expect(call.resultSample, 'preview ready');
    expect(call.eventCount, 6);
    expect(timeline.toJson()['status'], 'complete');
  });

  test('agent tool call lifecycle exposes permission blocked state', () {
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-denied',
            toolId: 'applyWorkspacePatch',
            input: '{"patch":"..."}',
          ),
          const AgentToolCallEvent.permissionBlocked(
            callId: 'call-denied',
            toolId: 'applyWorkspacePatch',
            permissionReason: 'Patch application requires review.',
          ),
        ]);
    final call = timeline.callFor('call-denied')!;

    expect(timeline.status, AgentToolCallTimelineStatus.blocked);
    expect(timeline.blockedCallIds, <String>['call-denied']);
    expect(call.status, AgentToolCallStatus.permissionBlocked);
    expect(call.terminal, isTrue);
    expect(call.permissionReason, contains('requires review'));
    expect(
      timeline.todoItems.join('\n'),
      isNot(contains('progress rendering')),
    );
    expect(timeline.todoItems.join('\n'), isNot(contains('result truncation')));
  });

  test('agent tool call lifecycle preserves first provider stream order', () {
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.inputStart(
            callId: 'call-b',
            toolId: 'readWorkspaceFile',
          ),
          const AgentToolCallEvent.inputStart(
            callId: 'call-a',
            toolId: 'writeWorkspaceFile',
          ),
          const AgentToolCallEvent.inputDelta(
            callId: 'call-b',
            inputDelta: '{"path":"b.styio"}',
          ),
          const AgentToolCallEvent.inputEnd(callId: 'call-a'),
        ]);

    expect(timeline.callIds, <String>['call-b', 'call-a']);
    expect(timeline.toJson()['callIds'], <String>['call-b', 'call-a']);
    expect(
      timeline.todoItems.join('\n'),
      isNot(contains('persist provider-native tool stream ordering')),
    );
  });

  test('agent tool call lifecycle exposes provider progress metadata', () {
    final timeline = const AgentToolCallLifecycleTracker().track(
      <AgentToolCallEvent>[
        const AgentToolCallEvent.callStarted(
          callId: 'call-progress',
          toolId: 'readWorkspaceFile',
          metadata: <String, Object?>{
            'progress': <String, Object?>{
              'label': 'Reading workspace',
              'current': 2,
              'total': 5,
              'unit': 'files',
            },
          },
        ),
      ],
    );
    final call = timeline.callFor('call-progress')!;

    expect(call.progressSummary, 'Reading workspace · 2/5 files');
    expect(call.toJson()['progressSummary'], 'Reading workspace · 2/5 files');
    expect(
      timeline.todoItems.join('\n'),
      isNot(contains('progress rendering')),
    );
  });

  test('agent tool call lifecycle tracks failures and truncates buffers', () {
    final timeline =
        const AgentToolCallLifecycleTracker(
          maxInputLength: 5,
          maxResultSampleLength: 4,
        ).track(<AgentToolCallEvent>[
          const AgentToolCallEvent.inputDelta(
            callId: 'call-failed',
            toolId: 'runIdeCommand',
            inputDelta: '0123456789',
          ),
          const AgentToolCallEvent.error(
            callId: 'call-failed',
            toolId: 'runIdeCommand',
            errorMessage: 'command failed',
          ),
        ]);
    final call = timeline.callFor('call-failed')!;

    expect(timeline.status, AgentToolCallTimelineStatus.failed);
    expect(call.status, AgentToolCallStatus.failed);
    expect(call.inputText, '01234');
    expect(call.errorMessage, 'command failed');
    expect(call.terminal, isTrue);
  });

  test('agent tool call lifecycle exposes rich provider errors', () {
    final timeline = const AgentToolCallLifecycleTracker().track(
      <AgentToolCallEvent>[
        const AgentToolCallEvent.error(
          callId: 'call-rich-error',
          toolId: 'readWorkspaceFile',
          errorMessage: 'tool failed',
          metadata: <String, Object?>{
            'errorDetails': <String, Object?>{
              'code': 'ENOENT',
              'path': 'missing.styio',
            },
          },
        ),
      ],
    );
    final call = timeline.callFor('call-rich-error')!;

    expect(call.richErrorDetails, contains('ENOENT'));
    expect(call.richErrorDetails, contains('missing.styio'));
    expect(call.toJson()['richErrorDetails'], contains('ENOENT'));
  });

  test('agent tool call lifecycle keeps result samples bounded', () {
    final timeline =
        const AgentToolCallLifecycleTracker(
          maxResultSampleLength: 4,
        ).track(<AgentToolCallEvent>[
          const AgentToolCallEvent.result(
            callId: 'call-result',
            toolId: 'readWorkspaceFile',
            result: 'abcdef',
          ),
        ]);
    final call = timeline.callFor('call-result')!;

    expect(timeline.status, AgentToolCallTimelineStatus.complete);
    expect(call.resultSample, 'abcd');
  });
}
