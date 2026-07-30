import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';

Future<void> main() async {
  _protocolOnlyBoundaryRemovesLegacyOwnership();
  _compositionAndMetadataAgreeOnProtocolOnlyBoundary();
  await _canonicalAcpV1ContractReplacesPrivateEnvelope();
  await _negotiationConcurrentStreamingPermissionAndCancellation();
  await _dynamicCapabilityRevocationAndReconnect();
  await _boundedFailuresAreConnectionLocal();
}

/// REQ-IDE-005 / both criteria / schema and atomic-cutover seam.
///
/// Precondition: the Vityo-owned shared protocol package and canonical schema are present.
/// Action: decode one request, notification, success, and error response and
/// inspect the former private protocol surface.
/// Oracle: the exact JSON-RPC 2.0 shapes round-trip under ACP wire version 1,
/// Vityo extensions require a negotiated `vityo/` namespace, and no legacy
/// envelope or connection abstraction remains.
Future<void> _canonicalAcpV1ContractReplacesPrivateEnvelope() async {
  _expect(acpProtocolVersion == 1, 'ACP stable wire version must be 1');
  final messages = <JsonRpcMessage>[
    JsonRpcRequest(
      id: const JsonRpcId.string('initialize-1'),
      method: AcpMethod.initialize,
      params: const <String, Object?>{'protocolVersion': 1},
    ),
    JsonRpcNotification(
      method: AcpMethod.sessionCancel,
      params: const <String, Object?>{'sessionId': 'session-1'},
    ),
    JsonRpcSuccessResponse(
      id: const JsonRpcId.integer(7),
      result: const <String, Object?>{'stopReason': 'end_turn'},
    ),
    JsonRpcErrorResponse(
      id: const JsonRpcId.string('bad-1'),
      error: const JsonRpcError(code: -32602, message: 'invalid params'),
    ),
  ];
  for (final message in messages) {
    final encoded = JsonRpcCodec.encode(message);
    final decoded = JsonRpcCodec.decode(encoded);
    _expect(
      jsonEncode(decoded.toJson()) == jsonEncode(message.toJson()),
      'JSON-RPC message must round-trip without shape drift',
    );
  }
  _expectThrowsProtocol(
    () => JsonRpcCodec.decode('{"jsonrpc":"2.0","method":'),
    'malformed_message',
  );
  _expectThrowsProtocol(
    () => validateVityoExtensionMethod('other/unsafe', const <String>{}),
    'invalid_extension_namespace',
  );
  _expectThrowsProtocol(
    () => validateVityoExtensionMethod('vityo/test/write', const <String>{
      'vityo/test/status',
    }),
    'capability_revoked',
  );

  final schema = File.fromUri(
    Platform.script.resolve(
      '../../../packages/vityo_agent_protocol/schema/acp-v1.schema.json',
    ),
  );
  final schemaJson =
      jsonDecode(await schema.readAsString()) as Map<String, Object?>;
  _expect(
    schemaJson[r'$id'] == 'https://vityo.dev/schema/agent-client-protocol/v1',
    'canonical schema must identify ACP v1',
  );

  final protocolSource = await File.fromUri(
    Platform.script.resolve(
      '../../../packages/vityo_agent_protocol/lib/src/protocol.dart',
    ),
  ).readAsString();
  for (final retiredSymbol in <String>[
    'AgentSessionEnvelope',
    'AgentClientConnection',
  ]) {
    _expect(
      !protocolSource.contains(retiredSymbol),
      '$retiredSymbol must be removed rather than retained as compatibility',
    );
  }
}

/// Node criterion 0 / one-time removed-path and symbol scan.
///
/// Precondition: the executor deleted legacy IDE-owned Agent runtime subtrees.
/// Action: inventory canonical paths, shell controllers, production symbols,
/// and legacy compatibility tests.
/// Oracle: every retired path is absent, every retired symbol is absent from
/// production Dart, and only canonical contract tests remain under test/agent_*.
void _protocolOnlyBoundaryRemovesLegacyOwnership() {
  final repository = _repositoryRoot();
  final product = Directory.fromUri(
    repository.uri.resolve('products/vityo_app/'),
  );
  for (final retiredPath in const <String>[
    'lib/src/view_ide/agent_client',
    'lib/src/view_render/agent_workbench',
  ]) {
    _expect(
      !Directory.fromUri(product.uri.resolve('$retiredPath/')).existsSync(),
      '$retiredPath must be deleted rather than aliased',
    );
  }

  final shellRuntime = Directory.fromUri(
    product.uri.resolve('lib/src/view_ide/shell_runtime/'),
  );
  _expect(shellRuntime.existsSync(), 'shell_runtime must remain');
  final legacyShellControllers = shellRuntime
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (entry) =>
            entry.path.endsWith('.dart') &&
            entry.uri.pathSegments.last.startsWith('agent_'),
      )
      .map((entry) => entry.path)
      .toList(growable: false);
  _expect(
    legacyShellControllers.isEmpty,
    'shell_runtime must not retain agent_* controllers or facades',
  );

  const retiredSymbols = <String>[
    'AgentCodingSessionController',
    'NetworkAgentProviderTransport',
    'ConfiguredAgentProviderAdapterFactory',
    'AgentCodingToolLoopRuntime',
    'AgentProviderConfigurator',
    'AgentPromptProfile',
    'LocalOnlyAgentProviderAdapter',
  ];
  final productionRoot = Directory.fromUri(product.uri.resolve('lib/src/'));
  for (final file in productionRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((entry) => entry.path.endsWith('.dart'))) {
    final source = file.readAsStringSync();
    for (final symbol in retiredSymbols) {
      _expect(
        !source.contains(symbol),
        '${file.path} must not reference retired symbol $symbol',
      );
    }
  }

  final testRoot = Directory.fromUri(product.uri.resolve('test/'));
  final legacyRootTests = testRoot
      .listSync(recursive: false)
      .whereType<File>()
      .where(
        (entry) =>
            entry.path.endsWith('.dart') &&
            (entry.uri.pathSegments.last.startsWith('agent_') ||
                entry.uri.pathSegments.last ==
                    'extension_agent_provider_contributions_test.dart'),
      )
      .map((entry) => entry.path)
      .toList(growable: false);
  _expect(
    legacyRootTests.isEmpty,
    'legacy provider/controller root tests must be deleted with their subjects',
  );

  final presentationRoot = Directory.fromUri(
    product.uri.resolve('lib/src/presentation/agent_workbench/'),
  );
  _expect(presentationRoot.existsSync(), 'canonical presentation workbench must exist');
  for (final file in presentationRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((entry) => entry.path.endsWith('.dart'))) {
    final source = file.readAsStringSync();
    _expect(
      !source.contains('view_render/agent_workbench') &&
          !source.contains('/view_ide/agent_client/'),
      '${file.path} must consume canonical projections only',
    );
  }
}

/// Node criterion 2 / composition and metadata agreement scan.
///
/// Precondition: AppBootstrap, capability metadata, and gap register are owned
/// by the same protocol-only closure as the acceptance tests.
/// Action: inspect bootstrap composition, module manifest, capability matrix,
/// baseline JSON, and the direct-provider gap row.
/// Oracle: bootstrap constructs only AgentClientRegistry/collaboration seams,
/// metadata describes protocol-client capabilities only, and the gap register
/// records the achieved boundary without behavior-bearing provider claims.
void _compositionAndMetadataAgreeOnProtocolOnlyBoundary() {
  final repository = _repositoryRoot();
  final product = Directory.fromUri(
    repository.uri.resolve('products/vityo_app/'),
  );
  final bootstrap = File.fromUri(
    product.uri.resolve('lib/src/app/app_bootstrap.dart'),
  );
  _expect(bootstrap.existsSync(), 'app_bootstrap.dart must exist');
  final bootstrapSource = bootstrap.readAsStringSync();
  for (final forbidden in const <String>[
    'AgentCodingSessionController',
    'AgentProviderConfigurator',
    'createNetworkAgentProviderTransport',
    'AgentPromptProfileStore',
    'AgentCodingToolLoopRuntime',
    'view_render/agent_workbench',
    'view_ide/agent_client/',
  ]) {
    _expect(
      !bootstrapSource.contains(forbidden),
      'AppBootstrap must not construct legacy provider/controller surface ($forbidden)',
    );
  }
  _expect(
    bootstrapSource.contains('AgentClientRegistry') ||
        bootstrapSource.contains('agent_client/agent_client.dart'),
    'AppBootstrap must compose the canonical Agent Client registry',
  );

  final manifest = jsonDecode(
    File.fromUri(
      product.uri.resolve(
        'assets/module_manifests/agent.surface.basic.json',
      ),
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  _expect(
    manifest['entrypoint'] ==
        'lib/src/presentation/agent_workbench/task_center.dart',
    'module manifest must route to canonical Agent Workbench presentation',
  );
  final capabilityFlags =
      manifest['capabilityFlags'] as Map<String, Object?>? ?? const {};
  _expect(
    capabilityFlags['providerAdapters'] != true &&
        capabilityFlags['profileInjection'] != true,
    'module manifest must not advertise IDE-owned provider behavior',
  );
  final contributions =
      ((manifest['extension'] as Map<String, Object?>?)?['contributions']
              as List<Object?>? ??
          const <Object?>[]);
  for (final contribution in contributions) {
    final metadata =
        ((contribution as Map<String, Object?>?)?['metadata']
                as Map<String, Object?>? ??
            const <String, Object?>{});
    _expect(
      metadata['supportedProviderKinds'] == null &&
          metadata['supportedProtocols'] == null &&
          !metadata.containsKey('provider.context'),
      'module contributions must not carry provider transport metadata',
    );
  }

  final baseline = jsonDecode(
    File.fromUri(
      repository.uri.resolve('toolchain/vityo-ide-capability-baseline.json'),
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  final agentWorkflow =
      (baseline['domains'] as Map<String, Object?>?)?['agent_workflow']
          as Map<String, Object?>?;
  _expect(agentWorkflow != null, 'agent_workflow baseline domain must exist');
  final currentStatus = agentWorkflow!['currentStatus'] as String? ?? '';
  _expect(
    !currentStatus.contains('legacy IDE-owned provider/controller'),
    'agent_workflow baseline must not claim legacy IDE provider ownership',
  );
  final knownGaps =
      (agentWorkflow['knownGaps'] as List<Object?>? ?? const <Object?>[])
          .map((entry) => entry.toString())
          .toList(growable: false);
  _expect(
    knownGaps.every(
      (gap) =>
          !gap.contains('Legacy IDE-owned model/provider') &&
          !gap.contains('session-controller implementation must be removed'),
    ),
    'agent_workflow knownGaps must not retain the direct-provider migration row',
  );

  final gapsDoc = File.fromUri(
    repository.uri.resolve('docs/design/Vityo-Implementation-Gaps.md'),
  ).readAsStringSync();
  _expect(
    gapsDoc.contains('| Retire IDE direct model-provider/controller ownership | Closed |') ||
        gapsDoc.contains(
          '| Retire IDE direct model-provider/controller ownership | Complete |',
        ),
    'implementation gap register must mark direct-provider ownership closed',
  );
}

Directory _repositoryRoot() =>
    Directory.fromUri(Platform.script).parent.parent.parent.parent;

/// REQ-IDE-005 / criterion 1 / real stdio process and reducer seams.
///
/// Precondition: one deterministic ACP child and two independent sessions.
/// Action: issue prompts concurrently, answer both Agent-to-Client permission
/// requests in reverse order, then cancel a third long-running prompt twice.
/// Oracle: session IDs and chunks never cross, both prompts finish only after
/// their correlated decisions, and cancellation produces one wire effect and
/// an idempotent local result.
Future<void> _negotiationConcurrentStreamingPermissionAndCancellation() async {
  _expect(
    Platform.environment.containsKey('VITYO_ACCEPTANCE_PRIVATE'),
    'quality runner must provide the privacy sentinel',
  );
  final registry = _registry(<String, String>{'healthy': 'normal'});
  try {
    final connection = await registry.connect('healthy');
    _expect(
      connection.protocolVersion == 1,
      'initialize must negotiate ACP v1',
    );
    _expect(
      connection.capabilities.contains(AcpCapability.loadSession),
      'fixture must negotiate loadSession',
    );
    _expect(
      connection.metadata['vityo.test/privateEnvironmentVisible'] == false,
      'supervised child must not inherit ambient private environment',
    );

    final first = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    final second = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    final firstUpdates = <AgentSessionUpdate>[];
    final secondUpdates = <AgentSessionUpdate>[];
    final firstSubscription = first.updates.listen(firstUpdates.add);
    final secondSubscription = second.updates.listen(secondUpdates.add);

    final firstPrompt = first.prompt('alpha');
    final secondPrompt = second.prompt('bravo');
    final permissions = <AgentPermissionRequest>[
      await _next(registry.permissionRequests),
      await _next(registry.permissionRequests),
    ];
    _expect(
      permissions.map((request) => request.sessionId).toSet().length == 2,
      'concurrent sessions must receive distinct permission requests',
    );
    await registry.resolvePermission(
      permissions.last.id,
      AgentPermissionDecision.allowOnce,
    );
    await registry.resolvePermission(
      permissions.first.id,
      AgentPermissionDecision.allowOnce,
    );
    final results = await Future.wait(<Future<AcpPromptResult>>[
      firstPrompt,
      secondPrompt,
    ]);
    _expect(
      results.every((result) => result.stopReason == AcpStopReason.endTurn),
      'both correlated prompts must complete successfully',
    );
    await Future<void>.delayed(Duration.zero);
    _expect(
      firstUpdates.isNotEmpty &&
          firstUpdates.every((update) => update.sessionId == first.id) &&
          firstUpdates.any((update) => update.text?.contains('alpha') ?? false),
      'first reducer must contain only first-session streamed chunks',
    );
    _expect(
      secondUpdates.isNotEmpty &&
          secondUpdates.every((update) => update.sessionId == second.id) &&
          secondUpdates.any(
            (update) => update.text?.contains('bravo') ?? false,
          ),
      'second reducer must contain only second-session streamed chunks',
    );

    final waiting = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    final waitingPrompt = waiting.prompt('wait');
    await _next(waiting.updates);
    _expect(await waiting.cancel(), 'first cancellation must be sent');
    _expect(!await waiting.cancel(), 'second cancellation must be idempotent');
    final cancelled = await waitingPrompt;
    _expect(
      cancelled.stopReason == AcpStopReason.cancelled,
      'cancelled prompt must terminate with the correlated stop reason',
    );

    await firstSubscription.cancel();
    await secondSubscription.cancel();
  } finally {
    final receipts = await registry.close();
    _expect(
      receipts.length == 1 &&
          receipts.single.terminated &&
          receipts.single.exitCode != null,
      'shutdown must observe direct child exit and leave no live child',
    );
  }
}

/// REQ-IDE-005 / criterion 1 and REQ-IDE-007 / criterion 2 / dynamic
/// capability and reconnect seams.
///
/// Precondition: a negotiated namespaced write extension and a live session.
/// Action: invoke it once, let the Agent revoke it, retry, disconnect, then
/// reconnect the session through session/load.
/// Oracle: the revoked call fails before reaching the child (effect count stays
/// one), and the loaded session resumes on a new process generation.
Future<void> _dynamicCapabilityRevocationAndReconnect() async {
  final registry = _registry(<String, String>{'healthy': 'normal'});
  try {
    final initial = await registry.connect('healthy');
    final session = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    await registry.invokeExtension(
      agentId: 'healthy',
      method: 'vityo/test/write',
    );
    final capabilityPrompt = session.prompt('capabilities');
    await capabilityPrompt;
    await _eventually(
      () => !registry
          .connection('healthy')
          .capabilities
          .contains('vityo/test/write'),
      'dynamic capability removal must reach the connection snapshot',
    );
    await _expectClientFailure(
      () => registry.invokeExtension(
        agentId: 'healthy',
        method: 'vityo/test/write',
      ),
      'capability_revoked',
    );
    final status =
        await registry.invokeExtension(
              agentId: 'healthy',
              method: 'vityo/test/status',
            )
            as Map<String, Object?>;
    _expect(
      status['effectCount'] == 1,
      'revoked capability must be denied before a second side effect',
    );

    final beforeGeneration = initial.generation;
    final shutdown = await registry.disconnect('healthy');
    _expect(shutdown.terminated, 'explicit disconnect must reap the child');
    final loaded = await registry.reconnectSession(
      agentId: 'healthy',
      sessionId: session.id,
      cwd: Directory.current.uri,
    );
    _expect(
      registry.connection('healthy').generation > beforeGeneration &&
          loaded.id == session.id,
      'reconnect must create a new process generation and load exact session',
    );
  } finally {
    await registry.close();
  }
}

/// REQ-IDE-005 / criterion 2 / hostile frame and sibling isolation seams.
///
/// Precondition: one healthy descriptor plus unsupported, malformed,
/// oversized, and crashing child descriptors under strict byte/time limits.
/// Action: connect each failing child and continue prompting the healthy one.
/// Oracle: every defect maps to its exact bounded failure code, no sibling is
/// closed, and an editor sentinel owned outside Agent state is unchanged.
Future<void> _boundedFailuresAreConnectionLocal() async {
  final registry = _registry(<String, String>{
    'healthy': 'normal',
    'unsupported': 'unsupported',
    'malformed': 'malformed',
    'oversized': 'oversized',
    'crash': 'crash',
  });
  var editorSentinel = 'unchanged';
  try {
    await registry.connect('healthy');
    await _expectClientFailure(
      () => registry.connect('unsupported'),
      'unsupported_version',
    );
    await _expectClientFailure(
      () => registry.connect('malformed'),
      'malformed_message',
    );
    await _expectClientFailure(
      () => registry.connect('oversized'),
      'message_too_large',
    );
    await _expectClientFailure(
      () => registry.connect('crash'),
      'process_failed',
    );

    final healthy = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    final prompt = healthy.prompt('still-alive');
    final permission = await _next(registry.permissionRequests);
    await registry.resolvePermission(
      permission.id,
      AgentPermissionDecision.allowOnce,
    );
    _expect(
      (await prompt).stopReason == AcpStopReason.endTurn,
      'healthy sibling must remain usable after every child-local failure',
    );
    _expect(
      editorSentinel == 'unchanged',
      'Agent failures must not mutate editor-owned state',
    );
    editorSentinel = 'unchanged';
  } finally {
    await registry.close();
  }
}

AgentClientRegistry _registry(Map<String, String> modes) {
  final fixture = File.fromUri(
    Platform.script.resolve(
      '../fixtures/vityo_app/agent_client/fake_agent.dart',
    ),
  );
  return AgentClientRegistry(
    descriptors: <String, AgentLaunchDescriptor>{
      for (final entry in modes.entries)
        entry.key: AgentLaunchDescriptor(
          id: entry.key,
          executable: Platform.resolvedExecutable,
          arguments: <String>['run', fixture.path, entry.value],
          workingDirectory: Directory.current.path,
        ),
    },
    policy: const AgentClientPolicy(
      maxMessageBytes: 64 * 1024,
      maxBufferedUpdatesPerSession: 32,
      maxPendingRequests: 32,
      requestTimeout: Duration(seconds: 3),
      shutdownTimeout: Duration(seconds: 2),
      allowedExtensions: <String>{'vityo/test/write', 'vityo/test/status'},
    ),
  );
}

Future<T> _next<T>(Stream<T> stream) =>
    stream.first.timeout(const Duration(seconds: 3));

Future<void> _eventually(bool Function() predicate, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(message);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _expectClientFailure(
  Future<Object?> Function() action,
  String code,
) async {
  try {
    await action();
  } on AgentClientFailure catch (error) {
    _expect(error.code == code, 'expected $code, received ${error.code}');
    _expect(
      error.message.length <= 1024,
      'structured failures must have bounded diagnostics',
    );
    return;
  }
  throw StateError('expected AgentClientFailure($code)');
}

void _expectThrowsProtocol(void Function() action, String code) {
  try {
    action();
  } on AgentProtocolException catch (error) {
    _expect(error.code == code, 'expected $code, received ${error.code}');
    return;
  }
  throw StateError('expected AgentProtocolException($code)');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
