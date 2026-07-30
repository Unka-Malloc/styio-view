import 'dart:convert';
import 'dart:io';

import 'package:vityo_coding_agent/vityo_coding_agent.dart';

Future<void> main() async {
  await _acceptsCompletedCancelledAndFailedLibrarySessions();
  await _reportsStructuredCliOutcomes();
  _rejectsForbiddenRuntimeDependencies();
}

Future<void> _acceptsCompletedCancelledAndFailedLibrarySessions() async {
  final host = InMemoryHostWorkspace(
    roots: const <HostRoot>[
      HostRoot(id: 'workspace', uri: 'memory://workspace'),
    ],
    facts: const <String, Object?>{'language': 'dart'},
  );
  final runtime = AgentRuntime(
    sessionService: AgentSessionService(host: host),
  );

  final completed = await runtime.run(
    const AgentRunRequest(
      sessionId: 'complete-session',
      goal: 'Inspect the workspace',
      rootId: 'workspace',
    ),
  );
  _expect(
    completed.state == AgentSessionState.completed,
    'a valid in-memory session must complete',
  );
  _expect(
    completed.failure == null && completed.observedRevision == 0,
    'a completed receipt must expose the observed host revision',
  );

  final cancellation = AgentCancellationController()..cancel();
  final cancelled = await runtime.run(
    AgentRunRequest(
      sessionId: 'cancelled-session',
      goal: 'Do not start host work',
      rootId: 'workspace',
      cancellation: cancellation.token,
    ),
  );
  _expect(
    cancelled.state == AgentSessionState.cancelled,
    'a pre-cancelled session must terminate as cancelled',
  );
  _expect(
    host.inspectionCount == 1,
    'a pre-cancelled session must not call the host',
  );

  final failedRuntime = AgentRuntime(
    sessionService: AgentSessionService(
      host: InMemoryHostWorkspace(
        roots: const <HostRoot>[
          HostRoot(id: 'workspace', uri: 'memory://workspace'),
        ],
        failure: const HostFailure(
          code: HostFailureCode.capabilityUnavailable,
          message: 'facts unavailable',
        ),
      ),
    ),
  );
  final failed = await failedRuntime.run(
    const AgentRunRequest(
      sessionId: 'failed-session',
      goal: 'Read unavailable facts',
      rootId: 'workspace',
    ),
  );
  _expect(
    failed.state == AgentSessionState.failed &&
        failed.failure?.code == HostFailureCode.capabilityUnavailable,
    'typed host failures must produce a truthful failed receipt',
  );
}

Future<void> _reportsStructuredCliOutcomes() async {
  final repository = File.fromUri(Platform.script).parent.parent.parent.parent;
  final product = Directory.fromUri(
    repository.uri.resolve('products/vityo_coding_agent/'),
  );
  final cli = 'bin/vityo_coding_agent.dart';

  final completed = await Process.run(
    Platform.resolvedExecutable,
    <String>[
      'run',
      cli,
      '--headless',
      '--session',
      'cli-complete',
      '--goal',
      'Inspect',
      '--root',
      'memory://workspace',
    ],
    workingDirectory: product.path,
  );
  _expect(completed.exitCode == 0, 'completed CLI session must exit 0');
  final completedJson = _decodeCliJson(completed.stdout);
  _expect(
    completedJson['state'] == 'completed' &&
        completedJson['sessionId'] == 'cli-complete',
    'completed CLI output must be a correlated structured receipt',
  );

  final cancelled = await Process.run(
    Platform.resolvedExecutable,
    <String>[
      'run',
      cli,
      '--headless',
      '--session',
      'cli-cancelled',
      '--goal',
      'Inspect',
      '--root',
      'memory://workspace',
      '--cancel-before-start',
    ],
    workingDirectory: product.path,
  );
  _expect(cancelled.exitCode == 75, 'cancelled CLI session must exit 75');
  _expect(
    _decodeCliJson(cancelled.stdout)['state'] == 'cancelled',
    'cancelled CLI output must be structured',
  );

  final failed = await Process.run(
    Platform.resolvedExecutable,
    <String>[
      'run',
      cli,
      '--headless',
      '--session',
      'cli-failed',
      '--goal',
      'Inspect',
      '--root',
      'memory://missing',
    ],
    workingDirectory: product.path,
  );
  _expect(failed.exitCode == 69, 'unavailable CLI host root must exit 69');
  final failedJson = _decodeCliJson(failed.stdout);
  final failure = failedJson['failure'] as Map<String, Object?>?;
  _expect(
    failedJson['state'] == 'failed' && failure?['code'] == 'rootRejected',
    'failed CLI output must preserve its typed failure code',
  );
}

void _rejectsForbiddenRuntimeDependencies() {
  final repository = File.fromUri(Platform.script).parent.parent.parent.parent;
  final product = Directory.fromUri(
    repository.uri.resolve('products/vityo_coding_agent/'),
  );
  final pubspec = File.fromUri(product.uri.resolve('pubspec.yaml'))
      .readAsStringSync();
  _expect(
    !pubspec.contains('flutter:') && !pubspec.contains('vityo_app:'),
    'the Coding Agent pubspec must not depend on Flutter or Vityo',
  );

  final library = Directory.fromUri(product.uri.resolve('lib/'));
  const libraryForbidden = <String>[
    'package:flutter/',
    'package:vityo_app/',
    'dart:io',
    'ChangeNotifier',
    'WorkspaceController',
    'WorkspaceDocumentStore',
  ];
  for (final file in library
      .listSync(recursive: true)
      .whereType<File>()
      .where((entry) => entry.path.endsWith('.dart'))) {
    final source = file.readAsStringSync();
    for (final forbidden in libraryForbidden) {
      _expect(
        !source.contains(forbidden),
        '${file.path} contains forbidden runtime dependency $forbidden',
      );
    }
  }

  for (final relative in const <String>[
    'lib/src/application',
    'lib/src/hosts',
  ]) {
    final root = Directory.fromUri(product.uri.resolve('$relative/'));
    for (final file in root
        .listSync(recursive: true)
        .whereType<File>()
        .where((entry) => entry.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      _expect(
        !source.contains('AgentClientConnection') &&
            !source.contains('VityoCodingAgentRuntime'),
        '${file.path} retains the transport-coupled runtime API',
      );
    }
  }
}

Map<String, Object?> _decodeCliJson(Object? output) {
  final decoded = jsonDecode(output.toString().trim());
  _expect(decoded is Map<String, Object?>, 'CLI output must be one JSON object');
  return decoded as Map<String, Object?>;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
