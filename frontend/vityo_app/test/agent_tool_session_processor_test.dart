import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';

void main() {
  test(
    'tool session processor applies events and builds session artifacts',
    () {
      const processor = AgentToolSessionProcessor();
      final timeline = processor.applyEvents(
        AgentToolCallTimeline.empty(),
        const <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{"path":"main.styio"}',
          ),
          AgentToolCallEvent.result(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            result: '{"text":"value = 1"}',
          ),
        ],
      );
      final journal = processor.buildJournal(timeline: timeline);
      final transcript = processor.buildTranscript(
        timeline: timeline,
        executionPlan: const AgentToolCallExecutionPlan(
          status: AgentToolCallExecutionPlanStatus.complete,
          executions: <AgentToolCallExecution>[
            AgentToolCallExecution(
              callId: 'call-read',
              toolId: 'readWorkspaceFile',
              status: AgentToolCallExecutionStatus.completed,
            ),
          ],
        ),
      );

      expect(timeline.status, AgentToolCallTimelineStatus.complete);
      expect(journal.status, AgentToolCallExecutionJournalStatus.complete);
      expect(journal.entries.single.callId, 'call-read');
      expect(transcript.status, AgentToolCallTimelineStatus.complete);
      expect(
        transcript.parts.single.status,
        AgentToolSessionPartStatus.completed,
      );
      expect(transcript.parts.single.output, '{"text":"value = 1"}');
    },
  );

  test('tool session processor records execution evidence in journal', () {
    const processor = AgentToolSessionProcessor();
    final timeline = processor
        .applyEvents(AgentToolCallTimeline.empty(), const <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-preview',
            toolId: 'previewWorkspaceEdit',
            input: '{"patch":{}}',
          ),
        ]);
    final journal = processor.buildJournal(
      timeline: timeline,
      executionPlan: const AgentToolCallExecutionPlan(
        status: AgentToolCallExecutionPlanStatus.reviewRequired,
        executions: <AgentToolCallExecution>[
          AgentToolCallExecution(
            callId: 'call-preview',
            toolId: 'previewWorkspaceEdit',
            status: AgentToolCallExecutionStatus.reviewRequired,
            permissionStatus: AgentToolPermissionDecisionStatus.reviewRequired,
            reviewDecisionStatus: AgentToolCallReviewDecisionStatus.denied,
            issues: <AgentToolCallExecutionIssue>[
              AgentToolCallExecutionIssue(
                code: 'agent.tool.review.denied.call-preview',
                message: 'Denied by user.',
              ),
            ],
          ),
        ],
      ),
    );
    final entry = journal.entries.single;
    final json = entry.toJson();
    final replayRequest = entry.toReplayRequest();

    expect(entry.executionStatus, 'review_required');
    expect(entry.permissionStatus, 'review_required');
    expect(entry.reviewDecisionStatus, 'denied');
    expect(
      entry.executionIssueCodes,
      contains('agent.tool.review.denied.call-preview'),
    );
    expect(json['permissionStatus'], 'review_required');
    expect(
      replayRequest.metadata['journalPermissionStatus'],
      'review_required',
    );
    expect(replayRequest.metadata['journalReviewDecisionStatus'], 'denied');
  });

  test(
    'tool session processor feeds invalid tool input back as result',
    () async {
      const processor = AgentToolSessionProcessor();
      var executed = false;

      final report = await processor.dispatchReady(
        timeline: AgentToolCallTimeline.empty(),
        executionPlan: const AgentToolCallExecutionPlan(
          status: AgentToolCallExecutionPlanStatus.blocked,
          executions: <AgentToolCallExecution>[
            AgentToolCallExecution(
              callId: 'call-invalid',
              toolId: 'readWorkspaceFile',
              status: AgentToolCallExecutionStatus.blocked,
              issues: <AgentToolCallExecutionIssue>[
                AgentToolCallExecutionIssue(
                  code: 'agent.tool.input.missing.path',
                  message: 'Missing required path.',
                ),
              ],
            ),
          ],
        ),
        executor: (_) {
          executed = true;
          return const AgentToolCallDispatchResult.success(
            callId: 'call-invalid',
            toolId: 'readWorkspaceFile',
            output: 'unexpected',
          );
        },
      );

      expect(executed, isFalse);
      expect(report.status, AgentToolCallDispatchReportStatus.failed);
      expect(report.results.single.callId, 'call-invalid');
      expect(report.results.single.success, isFalse);
      expect(
        report.results.single.metadata['source'],
        'agent-tool-input-validation',
      );
      expect(report.events.single.kind, AgentToolCallEventKind.error);
    },
  );

  test(
    'tool session processor replays journal entries with metadata',
    () async {
      const processor = AgentToolSessionProcessor();
      final timeline = processor.applyEvents(
        AgentToolCallTimeline.empty(),
        const <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{"path":"main.styio"}',
          ),
          AgentToolCallEvent.error(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            errorMessage: 'temporary failure',
          ),
        ],
      );
      final journal = processor.buildJournal(timeline: timeline);

      final report = await processor.replayJournal(
        journal: journal,
        executor: (request) {
          return AgentToolCallDispatchResult.success(
            callId: request.callId,
            toolId: request.toolId,
            output: '{"text":"value = 1"}',
          );
        },
      );

      expect(report.status, AgentToolCallReplayReportStatus.replayed);
      expect(report.results.single.metadata['replayedFromJournal'], isTrue);
      expect(report.results.single.metadata['replayCallId'], 'call-read');
      expect(report.events.single.kind, AgentToolCallEventKind.result);
    },
  );

  test(
    'tool session processor validates replay result schema when available',
    () async {
      const processor = AgentToolSessionProcessor();
      final timeline = processor.applyEvents(
        AgentToolCallTimeline.empty(),
        const <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{"path":"main.styio"}',
          ),
          AgentToolCallEvent.error(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            errorMessage: 'temporary failure',
          ),
        ],
      );
      final journal = processor.buildJournal(timeline: timeline);

      final report = await processor.replayJournal(
        journal: journal,
        toolSelection: const AgentToolSelection(
          context: AgentToolSelectionContext(
            providerKind: AgentProviderKind.localOnlyFallback,
            protocol: 'openai-compatible',
            model: 'local',
          ),
          tools: <AgentToolDefinition>[
            AgentToolDefinition(
              toolId: 'readWorkspaceFile',
              displayName: 'Read Workspace File',
              description: 'Read a file.',
              resultSchema: <AgentToolSchemaProperty>[
                AgentToolSchemaProperty(
                  name: 'source',
                  type: 'string',
                  required: true,
                ),
                AgentToolSchemaProperty(
                  name: 'document',
                  type: 'object',
                  required: true,
                ),
              ],
            ),
          ],
        ),
        executor: (request) {
          return AgentToolCallDispatchResult.success(
            callId: request.callId,
            toolId: request.toolId,
            output: '{"document":{"text":"value = 1"}}',
          );
        },
      );

      expect(report.status, AgentToolCallReplayReportStatus.failed);
      expect(report.results.single.success, isFalse);
      expect(
        report.results.single.metadata['source'],
        'agent-tool-result-validation',
      );
      expect(report.results.single.metadata['replayedFromJournal'], isTrue);
      expect(report.events.single.kind, AgentToolCallEventKind.error);
    },
  );

  test('tool session processor builds continuation plan for tool results', () {
    const processor = AgentToolSessionProcessor();

    final plan = processor.buildContinuationPlan(
      resultContexts: <AgentToolCallResultContext>[
        AgentToolCallResultContext(
          callId: 'call-read',
          toolId: 'readWorkspaceFile',
          status: AgentToolCallResultContextStatus.success,
          message: 'completed',
          output: '{"text":"value = 1"}',
          createdAt: DateTime.utc(2026, 5, 22),
        ),
        AgentToolCallResultContext(
          callId: 'call-shell',
          toolId: 'runShellCommand',
          status: AgentToolCallResultContextStatus.failure,
          message: 'command failed',
          output: 'exit 1',
          createdAt: DateTime.utc(2026, 5, 22),
        ),
      ],
    );

    expect(plan.ready, isTrue);
    expect(plan.resultCount, 2);
    expect(plan.failedCount, 1);
    expect(plan.prompt, contains('Continue after 2 agent tool result(s).'));
    expect(plan.prompt, contains('1 result(s) failed'));
    expect(plan.metadata['toolResultContinuation'], isTrue);
    expect(plan.metadata['toolResultContinuationCallIds'], <String>[
      'call-read',
      'call-shell',
    ]);
  });

  test('tool session processor builds denied review feedback result', () {
    const processor = AgentToolSessionProcessor();
    const call = AgentToolCallState(
      callId: 'call-command',
      toolId: 'runIdeCommand',
      status: AgentToolCallStatus.inputReady,
      inputText: '{"commandId":"runTests"}',
      inputComplete: true,
    );

    final result = processor.reviewDeniedResult(
      call: call,
      reason: 'Collect validation context first.',
    );

    expect(result.success, isFalse);
    expect(result.callId, 'call-command');
    expect(result.toolId, 'runIdeCommand');
    expect(result.output, contains('correctiveFeedback'));
    expect(result.output, contains('Collect validation context first.'));
    expect(result.metadata['source'], 'agent-tool-review');
    expect(result.metadata['reviewDecision'], 'denied');
    expect(result.metadata['recoveryAction'], 'reviseToolRequest');
  });

  test('tool session processor maps provider stream events', () {
    const processor = AgentToolSessionProcessor();

    final event = processor.eventForProviderStream(
      AgentProviderStreamEvent.completed(
        requestId: 'request-1',
        metadata: const <String, Object?>{
          'toolCallEventKind': 'tool-result',
          'toolCallId': 'call-read',
          'toolId': 'readWorkspaceFile',
          'toolResult': 'value = 1',
        },
      ),
    );

    expect(event?.kind, AgentToolCallEventKind.result);
    expect(event?.callId, 'call-read');
    expect(event?.toolId, 'readWorkspaceFile');
    expect(event?.result, 'value = 1');
  });
}
