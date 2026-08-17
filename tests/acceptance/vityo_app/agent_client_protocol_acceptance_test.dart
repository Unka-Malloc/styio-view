import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/agent_collaboration_service.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';

import '../../../products/vityo_app/test/support/vityod_test_harness.dart';

late VityodTestHarness _harness;

Future<void> main() async {
  if (!VityodTestHarness.isSupported) return;
  _harness = await VityodTestHarness.start(
    clientId: 'agent-client-protocol-acceptance',
  );
  try {
    await _canonicalAcpV1ContractRoundTrips();
    await _concurrentConnectAndRemoteSessionRoutesRemainUnique();
    await _negotiationConcurrentStreamingPermissionAndCancellation();
    await _crossAgentIdentifiersRemainIsolated();
    await _protocolChangeProposalRoutesThroughWorkbenchTransaction();
    await _processFailureClearsWorkbenchPermissionState();
    await _dynamicCapabilityRevocationAndReconnect();
    await _boundedFailuresAreConnectionLocal();
  } finally {
    await _harness.close();
  }
}

/// REQ-IDE-005 / both criteria / schema and atomic-cutover seam.
///
/// Precondition: the Vityo-owned shared protocol package and canonical schema
/// are present.
/// Action: decode one request, notification, success, and error response.
/// Oracle: the exact JSON-RPC 2.0 shapes round-trip under ACP wire version 1,
/// and Vityo extensions require ACP's reserved `_vityo.dev/` namespace.
Future<void> _canonicalAcpV1ContractRoundTrips() async {
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
    () => validateVityoExtensionMethod('_vityo.dev/test/write', const <String>{
      '_vityo.dev/test/status',
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
}

/// Concurrent callers share one supervised process, while a broken Agent
/// cannot alias two client sessions onto the same active remote route.
Future<void> _concurrentConnectAndRemoteSessionRoutesRemainUnique() async {
  final shared = _registry(<String, String>{'healthy': 'normal'});
  try {
    final snapshots = await Future.wait<AgentConnectionSnapshot>(
      List<Future<AgentConnectionSnapshot>>.generate(
        8,
        (_) => shared.connect('healthy'),
      ),
    );
    _expect(
      shared.activeConnectionCount == 1 &&
          snapshots.map((snapshot) => snapshot.generation).toSet().length == 1,
      'concurrent first connections must share one process generation',
    );
  } finally {
    final receipts = await shared.close();
    _expect(
      receipts.length == 1 && receipts.single.terminated,
      'coalesced connection must produce exactly one shutdown receipt',
    );
  }

  final reused = _registry(<String, String>{'reused': 'reused-session'});
  try {
    await reused.newSession(agentId: 'reused', cwd: Directory.current.uri);
    await _expectClientFailure(
      () => reused.newSession(agentId: 'reused', cwd: Directory.current.uri),
      'session_collision',
    );
  } finally {
    await reused.close();
  }
}

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
      connection.metadata.isEmpty,
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

    await _expectClientFailure(
      () => first.prompt(List<String>.filled(64 * 1024 + 1, 'x').join()),
      'message_too_large',
    );
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

    final awaitingApproval = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    final approvalPrompt = awaitingApproval.prompt('cancel-permission');
    final pendingPermission = await _next(registry.permissionRequests);
    _expect(
      pendingPermission.sessionId == awaitingApproval.id &&
          pendingPermission.toolCallId.isNotEmpty,
      'permission requests must retain their ACP tool-call correlation',
    );
    _expect(
      await awaitingApproval.cancel(),
      'cancelling a permission-blocked turn must be sent',
    );
    final approvalCancelled = await approvalPrompt;
    _expect(
      approvalCancelled.stopReason == AcpStopReason.cancelled,
      'permission-blocked cancellation must complete with cancelled',
    );
    await _expectClientFailure(
      () => registry.resolvePermission(
        pendingPermission.id,
        AgentPermissionDecision.allowOnce,
      ),
      'unknown_permission',
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

/// Two independent Agent processes are allowed to reuse their own remote
/// session and JSON-RPC request identifiers. Client-facing identifiers must
/// remain unique so neither projection nor permission resolution can cross
/// the process boundary.
Future<void> _crossAgentIdentifiersRemainIsolated() async {
  final registry = _registry(<String, String>{
    'first-agent': 'normal',
    'second-agent': 'normal',
  });
  try {
    final first = await registry.newSession(
      agentId: 'first-agent',
      cwd: Directory.current.uri,
    );
    final second = await registry.newSession(
      agentId: 'second-agent',
      cwd: Directory.current.uri,
    );
    _expect(
      first.id != second.id,
      'client session identifiers must be unique across Agent processes',
    );

    final firstPrompt = first.prompt('first-agent-prompt');
    final secondPrompt = second.prompt('second-agent-prompt');
    final permissions = <AgentPermissionRequest>[
      await _next(registry.permissionRequests),
      await _next(registry.permissionRequests),
    ];
    _expect(
      permissions[0].id != permissions[1].id,
      'client permission identifiers must not reuse remote JSON-RPC ids',
    );
    _expect(
      permissions.map((request) => request.sessionId).toSet().length == 2,
      'permissions must retain distinct client session ownership',
    );

    for (final permission in permissions.reversed) {
      await registry.resolvePermission(
        permission.id,
        AgentPermissionDecision.allowOnce,
      );
    }
    final results = await Future.wait(<Future<AcpPromptResult>>[
      firstPrompt,
      secondPrompt,
    ]);
    _expect(
      results.every((result) => result.stopReason == AcpStopReason.endTurn),
      'each permission decision must return to its owning Agent process',
    );
  } finally {
    await registry.close();
  }
}

/// REQ-IDE-004/005/007 / protocol-to-transaction change review.
///
/// A supervised Agent emits one negotiated, revision-bound proposal. The
/// collaboration projection must retain it for explicit review, and only the
/// IDE-owned transaction service may mutate the document after approval.
Future<void> _protocolChangeProposalRoutesThroughWorkbenchTransaction() async {
  final revisions = InMemoryWorkspaceRevisionService(
    initialDocuments: const <String, String>{'file': 'before'},
  );
  final collaboration = AgentCollaborationService(
    registry: _registry(<String, String>{'healthy': 'normal'}),
    transactions: RevisionedWorkspaceTransactionService(revisions),
    workspaceRoot: Directory.current.uri,
  );
  try {
    final opened = await collaboration.openSession('healthy');
    final prompt = collaboration.steer(opened.sessionId, 'propose-change');
    await _eventually(
      () => collaboration.projection
          .session(opened.sessionId)
          .pendingPermissions
          .isNotEmpty,
      'protocol permission must reach the workbench projection',
    );
    final permission = collaboration.projection
        .session(opened.sessionId)
        .pendingPermissions
        .values
        .single;
    await permission.resolve(AgentPermissionDecision.allowOnce);
    await prompt;
    await _eventually(
      () => collaboration.projection
          .session(opened.sessionId)
          .changeReviews
          .isNotEmpty,
      'protocol change proposal must reach the workbench projection',
    );

    final review = collaboration.projection
        .session(opened.sessionId)
        .changeReviews
        .values
        .single;
    _expect(
      review.outcome == WorkspaceTransactionOutcome.ready &&
          revisions.snapshot().document('file').text == 'before',
      'proposal preview must not mutate the IDE-owned workspace',
    );
    final committed = await collaboration.resolveChange(
      sessionId: opened.sessionId,
      changeSetId: review.changeSet.id,
      decision: AgentChangeReviewDecision.commit,
    );
    _expect(
      committed.outcome == WorkspaceTransactionOutcome.committed &&
          revisions.snapshot().document('file').text == 'after',
      'only explicit review may commit the protocol proposal',
    );
  } finally {
    await collaboration.close();
  }
}

/// A child that dies with a permission request outstanding must fail its
/// session projection and remove the now-unresolvable approval affordance.
Future<void> _processFailureClearsWorkbenchPermissionState() async {
  final collaboration = AgentCollaborationService(
    registry: _registry(<String, String>{'unstable': 'crash-with-permission'}),
    transactions: RevisionedWorkspaceTransactionService(
      InMemoryWorkspaceRevisionService(),
    ),
    workspaceRoot: Directory.current.uri,
  );
  try {
    final opened = await collaboration.openSession('unstable');
    final prompt = collaboration.steer(opened.sessionId, 'crash-now');
    await _eventually(
      () => collaboration.projection
          .session(opened.sessionId)
          .pendingPermissions
          .isNotEmpty,
      'permission must be visible before the child exits',
    );
    try {
      await prompt;
      throw StateError('crashed prompt unexpectedly completed');
    } on CollaborationFailure catch (failure) {
      _expect(
        failure.code == 'process_failed',
        'child exit must retain the process failure code',
      );
    }
    await _eventually(() {
      final session = collaboration.projection.session(opened.sessionId);
      return session.status == CollaborationTaskStatus.failed &&
          session.pendingPermissions.isEmpty;
    }, 'failed session must not retain an unresolvable permission');
  } finally {
    await collaboration.close();
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
      method: '_vityo.dev/test/write',
    );
    final capabilityPrompt = session.prompt('capabilities');
    await capabilityPrompt;
    await _eventually(
      () => !registry
          .connection('healthy')
          .capabilities
          .contains('_vityo.dev/test/write'),
      'dynamic capability removal must reach the connection snapshot',
    );
    await _expectClientFailure(
      () => registry.invokeExtension(
        agentId: 'healthy',
        method: '_vityo.dev/test/write',
      ),
      'capability_revoked',
    );
    final status =
        await registry.invokeExtension(
              agentId: 'healthy',
              method: '_vityo.dev/test/status',
            )
            as Map<String, Object?>;
    _expect(
      status['effectCount'] == 1,
      'revoked capability must be denied before a second side effect',
    );

    final beforeGeneration = initial.generation;
    final beforeReconnect = session.snapshot;
    _expect(
      beforeReconnect.updates.any(
        (update) => update.text?.contains('capabilities') ?? false,
      ),
      'completed prompt must reach the session projection before reconnect',
    );
    final shutdown = await registry.disconnect('healthy');
    _expect(shutdown.terminated, 'explicit disconnect must reap the child');
    await _expectClientFailure(
      () => registry.reconnectSession(
        agentId: 'healthy',
        sessionId: session.id,
        cwd: Directory.systemTemp.uri,
      ),
      'session_workspace_mismatch',
    );
    final loadedSessions = await Future.wait<AgentClientSession>(
      List<Future<AgentClientSession>>.generate(
        8,
        (_) => registry.reconnectSession(
          agentId: 'healthy',
          sessionId: session.id,
          cwd: Directory.current.uri,
        ),
      ),
    );
    final loaded = loadedSessions.first;
    _expect(
      registry.connection('healthy').generation > beforeGeneration,
      'reconnect must advance the supervised process generation',
    );
    _expect(
      loadedSessions.every((candidate) => identical(candidate, loaded)),
      'concurrent reconnect must coalesce to one client projection',
    );
    _expect(loaded.id == session.id, 'reconnect must retain the session id');
    _expect(
      loaded.snapshot.revision > beforeReconnect.revision,
      'reconnect must advance the session projection revision',
    );
    _expect(
      loaded.snapshot.updates.any(
        (update) => update.text?.contains('capabilities') ?? false,
      ),
      'reconnect must retain prior bounded session events',
    );
    _expect(
      loaded.snapshot.updates.last.payload['status'] == 'active',
      'reconnect must end with the daemon-restored active state',
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
          arguments: <String>[fixture.path, entry.value],
          workingDirectory: Directory.current.path,
        ),
    },
    client: _harness.client,
    policy: const AgentClientPolicy(
      maxMessageBytes: 64 * 1024,
      maxBufferedUpdatesPerSession: 32,
      maxPendingRequests: 32,
      requestTimeout: Duration(seconds: 3),
      shutdownTimeout: Duration(seconds: 2),
      allowedExtensions: <String>{
        '_vityo.dev/test/write',
        '_vityo.dev/test/status',
        VityoCapability.workspaceChangeProposal,
      },
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
