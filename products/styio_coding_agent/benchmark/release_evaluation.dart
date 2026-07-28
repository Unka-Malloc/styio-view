import 'dart:convert';
import 'dart:io';

import 'package:styio_coding_agent/styio_coding_agent.dart';

Future<void> main() async {
  final report = await const ReleaseEvaluationRunner().run(
    manifest:
        jsonDecode(
              await File('fixtures/evaluation/manifest.json').readAsString(),
            )
            as Map<String, Object?>,
    executor: const _DeterministicReleaseExecutor(),
  );
  stdout.writeln(jsonEncode(report.toJson()));
  if (!report.passed) exitCode = 1;
}

final class _DeterministicReleaseExecutor implements ReleaseCaseExecutor {
  const _DeterministicReleaseExecutor();

  @override
  Future<ReleaseCaseObservation> execute(ReleaseCase testCase) async {
    final scenario = _scenarios[testCase.id];
    if (scenario == null) {
      throw StateError('Unknown release fixture.');
    }
    return scenario;
  }
}

final Map<String, ReleaseCaseObservation> _scenarios =
    <String, ReleaseCaseObservation>{
      'task-quality-reviewed-change': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{
          'terminalState': 'completed',
          'reviewRequired': true,
        },
        effects: const <String>{
          'workspace.inspect',
          'change.propose',
          'validation.run',
        },
        operations: 3,
        durationMs: 20,
        peakMemoryBytes: 1048576,
      ),
      'allowed-effects-root-boundary': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{'rootEscapes': 0},
        effects: const <String>{'workspace.inspect'},
        operations: 1,
        durationMs: 5,
        peakMemoryBytes: 524288,
      ),
      'security-denied-capability': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{
          'terminalState': 'blocked',
          'secretValuesExposed': 0,
        },
        effects: const <String>{},
        operations: 1,
        durationMs: 5,
        peakMemoryBytes: 524288,
      ),
      'cancellation-session-local': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{
          'cancelledSessions': 1,
          'completedSessions': 1,
        },
        effects: const <String>{'workspace.inspect'},
        operations: 2,
        durationMs: 20,
        peakMemoryBytes: 1048576,
      ),
      'latency-initialize-and-prompt': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{'terminalState': 'completed'},
        effects: const <String>{'workspace.inspect'},
        operations: 2,
        durationMs: 20,
        peakMemoryBytes: 1048576,
      ),
      'memory-bounded-transport': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{
          'messageLimitBytes': 1048576,
          'sessionLimit': 64,
        },
        effects: const <String>{},
        operations: 1,
        durationMs: 5,
        peakMemoryBytes: 1048576,
      ),
      'unsupported-capability-fails-closed': ReleaseCaseObservation(
        finalFacts: const <String, Object?>{
          'errorCode': -32003,
          'fallbackUsed': false,
        },
        effects: const <String>{},
        operations: 1,
        durationMs: 5,
        peakMemoryBytes: 524288,
      ),
    };
