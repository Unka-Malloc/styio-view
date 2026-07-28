import 'dart:convert';
import 'dart:io';

import 'package:styio_agent_protocol/styio_agent_protocol.dart';
import 'package:styio_coding_agent/styio_coding_agent.dart';

const int _usageExitCode = 64;
const int _hostUnavailableExitCode = 69;
const int _runtimeFailureExitCode = 70;
const int _cancelledExitCode = 75;

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--version')) {
    stdout.writeln(
      'styio-coding-agent 0.1.0 protocol $styioAgentProtocolVersion',
    );
    return;
  }
  if (arguments.length == 1 && arguments.single == '--stdio-agent') {
    await _serveStdioAgent();
    return;
  }

  final parsed = _parseArguments(arguments);
  if (parsed case _ArgumentFailure(:final message)) {
    _writeJson(stderr, <String, Object?>{
      'state': 'failed',
      'failure': <String, Object?>{
        'code': HostFailureCode.invalidRequest.name,
        'message': message,
      },
    });
    exitCode = _usageExitCode;
    return;
  }
  final options = parsed as _HeadlessOptions;
  final cancellation = AgentCancellationController();
  if (options.cancelBeforeStart) {
    cancellation.cancel();
  }

  final runtime = AgentRuntime(
    sessionService: AgentSessionService(
      host: InMemoryHostWorkspace(
        roots: const <HostRoot>[
          HostRoot(id: 'workspace', uri: 'memory://workspace'),
        ],
      ),
    ),
  );
  final receipt = await runtime.run(
    AgentRunRequest(
      sessionId: options.sessionId,
      goal: options.goal,
      rootId: options.rootId,
      cancellation: cancellation.token,
    ),
  );
  _writeJson(stdout, receipt.toJson());
  exitCode = _exitCodeFor(receipt);
  runtime.dispose();
}

Future<void> _serveStdioAgent() async {
  final runtime = AgentRuntime(
    sessionService: AgentSessionService(
      host: InMemoryHostWorkspace(
        roots: const <HostRoot>[
          HostRoot(id: 'workspace', uri: 'memory://workspace'),
        ],
      ),
    ),
  );
  final endpoint = AgentSessionEndpoint(
    runtime: runtime,
    defaultRootId: 'workspace',
    policy: const AgentEndpointPolicy(
      maxConcurrentSessions: 4,
      maxPendingRequests: 128,
      maxSessions: 64,
      maxPromptCharacters: 64 * 1024,
    ),
  );
  try {
    await endpoint.serve(
      StdioAgentServerTransport(
        input: stdin,
        writeLine: stdout.writeln,
        flush: stdout.flush,
      ),
    );
  } on AgentProtocolException {
    exitCode = _usageExitCode;
  } on Object {
    exitCode = _runtimeFailureExitCode;
  } finally {
    runtime.dispose();
  }
}

int _exitCodeFor(AgentRunReceipt receipt) {
  return switch (receipt.state) {
    AgentSessionState.completed => 0,
    AgentSessionState.cancelled => _cancelledExitCode,
    AgentSessionState.failed
        when receipt.failure?.code == HostFailureCode.rootRejected ||
            receipt.failure?.code == HostFailureCode.capabilityUnavailable =>
      _hostUnavailableExitCode,
    AgentSessionState.failed => _runtimeFailureExitCode,
    AgentSessionState.idle ||
    AgentSessionState.running => _runtimeFailureExitCode,
  };
}

void _writeJson(IOSink sink, Map<String, Object?> value) {
  sink.writeln(jsonEncode(value));
}

sealed class _ParsedArguments {
  const _ParsedArguments();
}

final class _ArgumentFailure extends _ParsedArguments {
  const _ArgumentFailure(this.message);

  final String message;
}

final class _HeadlessOptions extends _ParsedArguments {
  const _HeadlessOptions({
    required this.sessionId,
    required this.goal,
    required this.rootId,
    required this.cancelBeforeStart,
  });

  final String sessionId;
  final String goal;
  final String rootId;
  final bool cancelBeforeStart;
}

_ParsedArguments _parseArguments(List<String> arguments) {
  if (!arguments.contains('--headless')) {
    return const _ArgumentFailure(
      'Usage: styio_coding_agent --headless --session ID '
      '--goal TEXT --root memory://ROOT',
    );
  }
  final values = <String, String>{};
  var cancelBeforeStart = false;
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (argument == '--headless') {
      continue;
    }
    if (argument == '--cancel-before-start') {
      cancelBeforeStart = true;
      continue;
    }
    if (argument != '--session' &&
        argument != '--goal' &&
        argument != '--root') {
      return _ArgumentFailure('unknown argument: $argument');
    }
    if (index + 1 >= arguments.length) {
      return _ArgumentFailure('missing value for $argument');
    }
    values[argument] = arguments[index + 1];
    index += 1;
  }
  final sessionId = values['--session'];
  final goal = values['--goal'];
  final root = values['--root'];
  if (sessionId == null ||
      sessionId.trim().isEmpty ||
      goal == null ||
      goal.trim().isEmpty ||
      root == null ||
      root.trim().isEmpty) {
    return const _ArgumentFailure('--session, --goal, and --root are required');
  }
  final rootUri = Uri.tryParse(root);
  if (rootUri == null ||
      rootUri.scheme != 'memory' ||
      rootUri.host.isEmpty ||
      rootUri.path.isNotEmpty) {
    return const _ArgumentFailure('--root must be a memory://ROOT URI');
  }
  return _HeadlessOptions(
    sessionId: sessionId,
    goal: goal,
    rootId: rootUri.host,
    cancelBeforeStart: cancelBeforeStart,
  );
}
