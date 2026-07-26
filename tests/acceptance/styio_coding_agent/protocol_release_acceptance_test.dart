import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:styio_agent_protocol/styio_agent_protocol.dart';
import 'package:styio_coding_agent/styio_coding_agent.dart';

Future<void> main() async {
  await _servesConcurrentCorrelatedSessionsAndCancellation();
  await _failsClosedForUnsupportedVersionsAndPublishesCapabilities();
  await _releaseCorpusIsVersionedDeterministicAndBudgeted();
}

Future<void> _servesConcurrentCorrelatedSessionsAndCancellation() async {
  final host = _ControlledHost();
  final runtime = AgentRuntime(
    sessionService: AgentSessionService(host: host),
  );
  final endpoint = AgentSessionEndpoint(
    runtime: runtime,
    defaultRootId: 'workspace',
    policy: const AgentEndpointPolicy(
      maxConcurrentSessions: 2,
      maxPendingRequests: 8,
      maxSessions: 4,
      maxPromptCharacters: 1024,
    ),
    sessionIdFactory: (sequence) => 'session-$sequence',
  );
  final transport = _MemoryServerTransport();
  final serving = endpoint.serve(transport);

  final initialized = await transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.integer(1),
      method: AcpMethod.initialize,
      params: const <String, Object?>{
        'protocolVersion': acpProtocolVersion,
        'clientInfo': <String, Object?>{
          'name': 'styio-ide',
          'version': '0.1.0',
        },
        'clientCapabilities': <String, Object?>{},
      },
    ),
  );
  final initializeResult = _successObject(initialized);
  _expect(
    initializeResult['protocolVersion'] == acpProtocolVersion &&
        initializeResult['agentCapabilities'] is Map<String, Object?>,
    'the real IDE handshake shape must negotiate one supported protocol',
  );

  final first = _successObject(
    await transport.exchange(
      JsonRpcRequest(
        id: const JsonRpcId.integer(2),
        method: AcpMethod.sessionNew,
        params: const <String, Object?>{
          'cwd': 'controlled-workspace',
          'mcpServers': <Object?>[],
        },
      ),
    ),
  );
  final second = _successObject(
    await transport.exchange(
      JsonRpcRequest(
        id: const JsonRpcId.integer(3),
        method: AcpMethod.sessionNew,
        params: const <String, Object?>{
          'cwd': 'controlled-workspace',
          'mcpServers': <Object?>[],
        },
      ),
    ),
  );
  _expect(
    first['sessionId'] == 'session-1' &&
        second['sessionId'] == 'session-2',
    'session routing must allocate bounded, distinct correlations',
  );

  final cancelledPrompt = transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.integer(4),
      method: AcpMethod.sessionPrompt,
      params: const <String, Object?>{
        'sessionId': 'session-1',
        'prompt': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'wait-for-cancel'},
        ],
      },
    ),
  );
  final completedPrompt = transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.integer(5),
      method: AcpMethod.sessionPrompt,
      params: const <String, Object?>{
        'sessionId': 'session-2',
        'prompt': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'inspect workspace'},
        ],
      },
    ),
  );
  await host.cancelSessionStarted.future;
  transport.add(
    JsonRpcNotification(
      method: AcpMethod.sessionCancel,
      params: const <String, Object?>{'sessionId': 'session-1'},
    ),
  );

  final cancelledResult = _successObject(await cancelledPrompt);
  final completedResult = _successObject(await completedPrompt);
  _expect(
    host.maxActive == 2 &&
        cancelledResult['stopReason'] == AcpStopReason.cancelled &&
        completedResult['stopReason'] == AcpStopReason.endTurn,
    'two sessions must progress concurrently and cancellation must remain session-local',
  );
  final updatedSessions = transport.sent
      .whereType<JsonRpcNotification>()
      .where((message) => message.method == AcpMethod.sessionUpdate)
      .map((message) => message.params['sessionId'])
      .toSet();
  _expect(
    updatedSessions.containsAll(<String>{'session-1', 'session-2'}),
    'each prompt must emit correlated session updates before its terminal response',
  );

  await transport.closeInput();
  await serving;
  runtime.dispose();
}

Future<void>
_failsClosedForUnsupportedVersionsAndPublishesCapabilities() async {
  final endpoint = AgentSessionEndpoint(
    runtime: AgentRuntime(
      sessionService: AgentSessionService(host: _ControlledHost()),
    ),
    defaultRootId: 'workspace',
    policy: const AgentEndpointPolicy(
      maxConcurrentSessions: 1,
      maxPendingRequests: 4,
      maxSessions: 2,
      maxPromptCharacters: 256,
    ),
    sessionIdFactory: (sequence) => 'capability-$sequence',
  );
  final transport = _MemoryServerTransport();
  final serving = endpoint.serve(transport);
  final rejected = await transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.string('unsupported'),
      method: AcpMethod.initialize,
      params: const <String, Object?>{
        'protocolVersion': acpProtocolVersion + 1,
      },
    ),
  );
  _expect(
    rejected is JsonRpcErrorResponse &&
        rejected.error.code == -32001 &&
        rejected.error.message == 'unsupported protocol version',
    'unsupported protocol versions must fail closed with a stable error',
  );

  final accepted = await transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.string('supported'),
      method: AcpMethod.initialize,
      params: const <String, Object?>{
        'protocolVersion': acpProtocolVersion,
      },
    ),
  );
  _expect(
    accepted is JsonRpcSuccessResponse,
    'a supported client must still be able to negotiate after rejection',
  );
  final capabilityMessage = transport.nextWhere(
    (message) =>
        message is JsonRpcNotification &&
        message.method == AcpMethod.capabilitiesChanged,
  );
  await endpoint.updateCapabilities(const <String>{AcpCapability.loadSession});
  final changed = await capabilityMessage;
  _expect(
    changed is JsonRpcNotification &&
        (changed.params['capabilities'] as List<Object?>).contains(
          AcpCapability.loadSession,
        ),
    'dynamic capabilities must be explicit, correlated transport facts',
  );

  await transport.closeInput();
  await serving;
}

Future<void> _releaseCorpusIsVersionedDeterministicAndBudgeted() async {
  final file = File('fixtures/evaluation/manifest.json');
  _expect(file.existsSync(), 'the release corpus manifest must exist');
  final manifest =
      jsonDecode(await file.readAsString()) as Map<String, Object?>;
  final cases = (manifest['cases'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final categories = <String>{
    for (final testCase in cases) testCase['category']! as String,
  };
  const requiredCategories = <String>{
    'task_quality',
    'allowed_effects',
    'security',
    'cancellation',
    'latency',
    'memory',
    'unsupported_capability',
  };
  final ids = <String>{
    for (final testCase in cases) testCase['id']! as String,
  };
  _expect(
    manifest['schemaVersion'] == 1 &&
        manifest['corpusVersion'] == '1.0.0' &&
        manifest['protocolVersion'] == acpProtocolVersion &&
        cases.length == ids.length &&
        categories.containsAll(requiredCategories),
    'the corpus must be versioned, unique, and cover every release dimension',
  );
  for (final testCase in cases) {
    final fixture = testCase['fixture'] as Map<String, Object?>;
    final expected = testCase['expected'] as Map<String, Object?>;
    final budgets = testCase['budgets'] as Map<String, Object?>;
    _expect(
      fixture['provider'] == 'deterministic-fake-v1' &&
          fixture['goal'] is String &&
          (fixture['goal'] as String).isNotEmpty &&
          expected['finalFacts'] is Map<String, Object?> &&
          expected['allowedEffects'] is List<Object?> &&
          budgets['maxOperations'] is int &&
          (budgets['maxOperations'] as int) > 0 &&
          budgets['maxDurationMs'] is int &&
          (budgets['maxDurationMs'] as int) > 0 &&
          budgets['maxPeakMemoryBytes'] is int &&
          (budgets['maxPeakMemoryBytes'] as int) > 0,
      'every case must use deterministic inputs, final facts, allowed effects, and positive budgets',
    );
  }
  final canonicalCases = jsonEncode(cases);
  _expect(
    manifest['casesDigest'] == sha256.convert(utf8.encode(canonicalCases)).toString(),
    'the corpus digest must bind the exact ordered fixture content',
  );
}

Map<String, Object?> _successObject(JsonRpcMessage message) {
  _expect(message is JsonRpcSuccessResponse, 'expected a success response');
  return requireJsonObject(
    (message as JsonRpcSuccessResponse).result,
    'success result',
  );
}

final class _MemoryServerTransport implements AgentServerTransport {
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>();
  final StreamController<JsonRpcMessage> _outgoing =
      StreamController<JsonRpcMessage>.broadcast(sync: true);
  final List<JsonRpcMessage> sent = <JsonRpcMessage>[];

  @override
  Stream<JsonRpcMessage> get incoming => _incoming.stream;

  void add(JsonRpcMessage message) => _incoming.add(message);

  Future<JsonRpcMessage> exchange(JsonRpcRequest request) {
    final response = nextWhere(
      (message) =>
          (message is JsonRpcSuccessResponse && message.id == request.id) ||
          (message is JsonRpcErrorResponse && message.id == request.id),
    );
    add(request);
    return response;
  }

  Future<JsonRpcMessage> nextWhere(
    bool Function(JsonRpcMessage) predicate,
  ) => _outgoing.stream
      .firstWhere(predicate)
      .timeout(const Duration(seconds: 2));

  @override
  Future<void> send(JsonRpcMessage message) async {
    sent.add(message);
    _outgoing.add(message);
  }

  Future<void> closeInput() => _incoming.close();

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
    if (!_outgoing.isClosed) await _outgoing.close();
  }
}

final class _ControlledHost implements HostWorkspace {
  final Completer<void> cancelSessionStarted = Completer<void>();
  int active = 0;
  int maxActive = 0;

  @override
  List<HostRoot> get roots => const <HostRoot>[
    HostRoot(id: 'workspace', uri: 'memory://workspace'),
  ];

  @override
  Future<HostResult<HostWorkspaceSnapshot>> inspect(
    HostWorkspaceRequest request,
  ) async {
    active += 1;
    if (active > maxActive) maxActive = active;
    try {
      if (request.goal == 'wait-for-cancel') {
        if (!cancelSessionStarted.isCompleted) {
          cancelSessionStarted.complete();
        }
        await request.context.cancellation.whenCancelled;
        return const HostRejected<HostWorkspaceSnapshot>(
          HostFailure(
            code: HostFailureCode.cancelled,
            message: 'cancelled by fixture',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return HostSuccess<HostWorkspaceSnapshot>(
        HostWorkspaceSnapshot(
          rootId: request.rootId,
          revision: 1,
          facts: const <String, Object?>{'reviewed': true},
        ),
      );
    } finally {
      active -= 1;
    }
  }
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
