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
}
