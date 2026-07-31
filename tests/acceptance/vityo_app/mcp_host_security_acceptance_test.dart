import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/ide_mcp_server.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/workspace_root_registry.dart';
import 'package:vityo_app/src/ide/agent_client/tools/context_export_service.dart';
import 'package:vityo_app/src/ide/agent_client/tools/ide_tool_catalog.dart';
import 'package:vityo_app/src/ide/agent_client/tools/tool_security_policy.dart';
import 'package:vityo_app/src/ide/extensions/mcp_extension_registry.dart';
import 'package:vityo_app/src/ide/language/diagnostic_fact.dart';
import 'package:vityo_app/src/ide/workbench/capability_snapshot.dart';
import 'package:vityo_app/src/ide/workbench/ide_fact_provider.dart';

Future<void> main() async {
  await _dynamicDiscoveryAndBoundedRevisionedContext();
  await _rootsCapabilitiesAndExtensionsRevokeImmediately();
  await _securityPolicyDeniesBeforeEffectsAndRedactsReceipts();
  await _canonicalRootAuthorizationRejectsTraversalAndLinkEscape();
  await _rootRevocationDuringResolutionFailsClosed();
}

/// REQ-IDE-006 / criterion 1 / MCP lifecycle, discovery, truthful-fact,
/// context-budget, and real root seams.
///
/// Precondition: one consented temporary workspace, revision 12 IDE facts, and
/// root-limited context/read tools.
/// Action: initialize with stable MCP, list tools/resources/prompts, call the
/// context tool, read its resource, and read one approved workspace file.
/// Oracle: standard MCP shapes expose only visible capabilities; both context
/// routes carry the same revision/provenance; byte/item truncation is explicit;
/// a bearer-shaped source value is absent; approved file content is bounded.
Future<void> _dynamicDiscoveryAndBoundedRevisionedContext() async {
  final temporary = await Directory.systemTemp.createTemp('vityo-mcp-host-');
  final workspace = await Directory(
    '${temporary.path}${Platform.pathSeparator}workspace',
  ).create();
  final approvedFile = File(
    '${workspace.path}${Platform.pathSeparator}approved.txt',
  );
  await approvedFile.writeAsString(
    'approved workspace evidence ${List<String>.filled(2048, 'x').join()}',
  );

  final roots = WorkspaceRootRegistry();
  final context = RevisionedIdeContextExportService(
    provider: _FactsProvider(),
    currentWorkspaceRevision: () => 12,
    sanitizer: McpPayloadSanitizer.withSensitiveValues(const <String>{
      'private-fixture-value',
    }),
  );
  final catalog = IdeToolCatalog(
    adapters: <IdeToolAdapter>[
      ContextReadToolAdapter(context),
      WorkspaceReadTextToolAdapter(
        roots: roots,
        maxCodeUnits: 64,
        sanitizer: const McpPayloadSanitizer(),
      ),
    ],
  );
  catalog.replaceCapabilities('session-a', const <String>{
    'ide.context.read',
    'ide.workspace.read_text',
  });
  await roots.replaceRoots(
    sessionId: 'session-a',
    proposals: <WorkspaceRootProposal>[
      WorkspaceRootProposal(path: workspace.path, displayName: 'workspace'),
    ],
    consentReceiptId: 'consent-1',
  );
  final server = IdeMcpServer(
    roots: roots,
    tools: catalog,
    security: ToolSecurityPolicy(
      grants: ToolGrantRegistry(),
      auditLog: ToolAuditLog(maxEntries: 32),
      sanitizer: McpPayloadSanitizer.withSensitiveValues(const <String>{
        'private-fixture-value',
      }),
      maxResultBytes: 4096,
    ),
  );

  try {
    final initialized = await _initialize(server, 'session-a');
    _expect(
      initialized['protocolVersion'] == mcpProtocolVersion,
      'server must negotiate the stable MCP version',
    );
    final capabilities = initialized['capabilities'] as Map<String, Object?>;
    _expect(
      capabilities.keys.toSet().containsAll(const <String>{
        'tools',
        'resources',
        'prompts',
      }),
      'initialize must advertise dynamic tools, resources, and prompts',
    );

    final tools = await _requestResult(server, 'session-a', 'tools/list');
    final names = (tools['tools'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((tool) => tool['name'])
        .toSet();
    _expect(
      names.containsAll(const <String>{
            'ide.context.read',
            'ide.workspace.read_text',
          }) &&
          names.length == 2,
      'discovery must expose exactly the session capabilities',
    );

    final resources = await _requestResult(
      server,
      'session-a',
      'resources/list',
    );
    final resourceItems = (resources['resources'] as List<Object?>)
        .cast<Map<String, Object?>>();
    _expect(
      resourceItems.any((item) => item['uri'] == 'ide://context/facts') &&
          resourceItems.any(
            (item) => (item['uri'] as String).startsWith('ide-root://'),
          ),
      'resource discovery must include facts and the approved root',
    );
    final prompts = await _requestResult(server, 'session-a', 'prompts/list');
    _expect(
      (prompts['prompts'] as List<Object?>).cast<Map<String, Object?>>().any(
        (prompt) => prompt['name'] == 'ide.review_workspace',
      ),
      'root-aware review prompt must be discoverable',
    );

    final contextCall = await _callTool(
      server,
      'session-a',
      'ide.context.read',
      <String, Object?>{
        'expectedWorkspaceRevision': 12,
        'maxItems': 2,
        'maxUtf8Bytes': 700,
        'maxCodeUnitsPerItem': 220,
      },
    );
    _expect(contextCall['isError'] != true, 'context tool must succeed');
    final contextResult =
        contextCall['structuredContent'] as Map<String, Object?>;
    _expect(
      contextResult['workspaceRevision'] == 12 &&
          contextResult['provenance'] == 'vityo-facts' &&
          contextResult['truncated'] == true &&
          (contextResult['omittedItemCount'] as int) > 0,
      'bounded context must expose exact revision, provenance, and omissions',
    );
    _expect(
      !jsonEncode(contextCall).contains('private-fixture-value') &&
          !jsonEncode(contextCall).contains('Bearer fixture-token'),
      'context export must redact registered and bearer-shaped secrets',
    );

    final contextResource = await _requestResult(
      server,
      'session-a',
      'resources/read',
      <String, Object?>{
        'uri': 'ide://context/facts',
        '_meta': <String, Object?>{
          'expectedWorkspaceRevision': 12,
          'maxItems': 2,
          'maxUtf8Bytes': 700,
          'maxCodeUnitsPerItem': 220,
        },
      },
    );
    final resourceText =
        ((contextResource['contents'] as List<Object?>).single
                as Map<String, Object?>)['text']
            as String;
    final decodedResource = jsonDecode(resourceText) as Map<String, Object?>;
    _expect(
      decodedResource['workspaceRevision'] == 12 &&
          decodedResource['provenance'] == 'vityo-facts',
      'resource and tool must reuse the same revision-bound fact source',
    );

    final fileCall = await _callTool(
      server,
      'session-a',
      'ide.workspace.read_text',
      <String, Object?>{'path': approvedFile.path},
    );
    _expect(
      fileCall['isError'] != true &&
          jsonEncode(fileCall).contains('approved workspace evidence') &&
          fileCall['structuredContent'] is Map<String, Object?> &&
          (fileCall['structuredContent']
                  as Map<String, Object?>)['truncated'] ==
              true &&
          ((fileCall['structuredContent']
                      as Map<String, Object?>)['omittedUtf8Bytes']
                  as int) >
              0 &&
          (fileCall['structuredContent']
                  as Map<String, Object?>)['omittedCodeUnitsExact'] ==
              false,
      'approved root file must be read with explicit bounded omissions',
    );
  } finally {
    await server.close();
    await temporary.delete(recursive: true);
  }
}

/// REQ-IDE-006 / both criteria / immutable discovery snapshot, root-change,
/// capability-change, and extension contribution seams.
///
/// Precondition: a live initialized session with one approved root and a
/// dynamically contributed tool.
/// Action: register the extension, observe discovery, remove its capability,
/// revoke all roots, then unregister the contribution.
/// Oracle: list-changed notifications are emitted, removed tools disappear,
/// stale calls fail without adapter invocation, and root-bound resources and
/// prompts disappear immediately.
Future<void> _rootsCapabilitiesAndExtensionsRevokeImmediately() async {
  final temporary = await Directory.systemTemp.createTemp('vityo-mcp-live-');
  final roots = WorkspaceRootRegistry();
  await roots.replaceRoots(
    sessionId: 'session-live',
    proposals: <WorkspaceRootProposal>[
      WorkspaceRootProposal(path: temporary.path, displayName: 'live-root'),
    ],
    consentReceiptId: 'consent-live',
  );
  final extensionAdapter = _RecordingAdapter(
    descriptor: _descriptor(
      name: 'styio.extension.inspect',
      capability: 'extension.inspect',
      risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
    ),
    result: const <String, Object?>{'extension': 'visible'},
  );
  final catalog = IdeToolCatalog(
    adapters: <IdeToolAdapter>[
      WorkspaceReadTextToolAdapter(
        roots: roots,
        maxCodeUnits: 32,
        sanitizer: const McpPayloadSanitizer(),
      ),
    ],
  );
  catalog.replaceCapabilities('session-live', const <String>{
    'ide.workspace.read_text',
    'extension.inspect',
  });
  final extensions = McpExtensionRegistry(catalog);
  final server = IdeMcpServer(
    roots: roots,
    tools: catalog,
    security: ToolSecurityPolicy(
      grants: ToolGrantRegistry(),
      auditLog: ToolAuditLog(maxEntries: 16),
      sanitizer: const McpPayloadSanitizer(),
      maxResultBytes: 2048,
    ),
  );

  try {
    await _initialize(server, 'session-live');
    final duplicateInitialize = await server.handle(
      sessionId: 'session-live',
      message: JsonRpcRequest(
        id: const JsonRpcId.integer(999),
        method: 'initialize',
        params: const <String, Object?>{
          'protocolVersion': mcpProtocolVersion,
          'capabilities': <String, Object?>{},
        },
      ),
    );
    _expect(
      duplicateInitialize is JsonRpcErrorResponse &&
          (duplicateInitialize.error.data as Map<String, Object?>)['code'] ==
              'already_initialized',
      'duplicate initialize must fail without replacing live session state',
    );
    final notifications = <JsonRpcNotification>[];
    final subscription = server
        .notificationsFor('session-live')
        .listen(notifications.add);

    extensions.register(
      McpExtensionContribution(
        id: 'styio.test.extension',
        tools: <IdeToolAdapter>[extensionAdapter],
      ),
    );
    await _eventually(
      () => notifications.any(
        (notification) =>
            notification.method == 'notifications/tools/list_changed',
      ),
      'extension registration must invalidate tool discovery',
    );
    final listedAfterAdd = await _requestResult(
      server,
      'session-live',
      'tools/list',
    );
    _expect(
      jsonEncode(listedAfterAdd).contains('styio.extension.inspect'),
      'registered extension tool must be discoverable',
    );

    catalog.replaceCapabilities('session-live', const <String>{
      'ide.workspace.read_text',
    });
    final removedCall = await _callTool(
      server,
      'session-live',
      'styio.extension.inspect',
      const <String, Object?>{},
    );
    _expect(
      removedCall['isError'] == true &&
          _errorCode(removedCall) == 'capability_revoked' &&
          extensionAdapter.callCount == 0,
      'removed capability must be denied before extension execution',
    );

    await roots.replaceRoots(
      sessionId: 'session-live',
      proposals: const <WorkspaceRootProposal>[],
      consentReceiptId: 'consent-revoke',
    );
    await _eventually(
      () =>
          notifications.any(
            (notification) =>
                notification.method == 'notifications/resources/list_changed',
          ) &&
          notifications.any(
            (notification) =>
                notification.method == 'notifications/prompts/list_changed',
          ),
      'root revocation must invalidate root-aware discovery',
    );
    final resources = await _requestResult(
      server,
      'session-live',
      'resources/list',
    );
    final prompts = await _requestResult(
      server,
      'session-live',
      'prompts/list',
    );
    _expect(
      !jsonEncode(resources).contains('ide-root://') &&
          !jsonEncode(prompts).contains('ide.review_workspace'),
      'revoked roots must disappear from resources and prompts immediately',
    );

    extensions.unregister('styio.test.extension');
    await subscription.cancel();
  } finally {
    await server.close();
    await temporary.delete(recursive: true);
  }
}

/// REQ-IDE-007 / criterion 2 / authoritative risk, grants, credential input,
/// result limit, redaction, and bounded audit seams.
///
/// Precondition: a mutating adapter falsely advertises read-only, an oversized
/// adapter, and a secret-producing adapter.
/// Action: call without a grant, call with bearer input, grant once and replay,
/// then invoke oversized and secret-producing tools.
/// Oracle: policy uses authoritative risks rather than hints; rejected calls
/// have zero effects; once is consumed exactly once; oversized output fails
/// closed; secrets are redacted from results and every bounded receipt.
Future<void> _securityPolicyDeniesBeforeEffectsAndRedactsReceipts() async {
  final mutating = _RecordingAdapter(
    descriptor: _descriptor(
      name: 'ide.test.mutate',
      capability: 'test.mutate',
      risks: const <IdeToolRisk>{IdeToolRisk.mutating},
      annotations: const <String, Object?>{'readOnlyHint': true},
    ),
    result: const <String, Object?>{'changed': true},
  );
  final oversized = _RecordingAdapter(
    descriptor: _descriptor(
      name: 'ide.test.oversized',
      capability: 'test.oversized',
      risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
    ),
    result: <String, Object?>{'text': List<String>.filled(4096, 'x').join()},
  );
  final secret = _RecordingAdapter(
    descriptor: _descriptor(
      name: 'ide.test.secret',
      capability: 'test.secret',
      risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
    ),
    result: const <String, Object?>{
      'authorization': 'Bearer fixture-token',
      'value': 'private-fixture-value',
    },
  );
  final catalog = IdeToolCatalog(
    adapters: <IdeToolAdapter>[mutating, oversized, secret],
  );
  catalog.replaceCapabilities('session-security', const <String>{
    'test.mutate',
    'test.oversized',
    'test.secret',
  });
  final grants = ToolGrantRegistry();
  final audit = ToolAuditLog(maxEntries: 8);
  final server = IdeMcpServer(
    roots: WorkspaceRootRegistry(),
    tools: catalog,
    security: ToolSecurityPolicy(
      grants: grants,
      auditLog: audit,
      sanitizer: McpPayloadSanitizer.withSensitiveValues(const <String>{
        'private-fixture-value',
      }),
      maxResultBytes: 1024,
    ),
  );

  try {
    await _initialize(server, 'session-security');
    final withoutGrant = await _callTool(
      server,
      'session-security',
      'ide.test.mutate',
      const <String, Object?>{},
    );
    _expect(
      withoutGrant['isError'] == true &&
          _errorCode(withoutGrant) == 'permission_required' &&
          mutating.callCount == 0,
      'readOnlyHint must not bypass authoritative mutating risk policy',
    );

    final bearerInput = await _callTool(
      server,
      'session-security',
      'ide.test.mutate',
      const <String, Object?>{
        'authorization': 'Bearer unintended-audience-token',
      },
    );
    _expect(
      bearerInput['isError'] == true &&
          _errorCode(bearerInput) == 'credential_passthrough_denied' &&
          mutating.callCount == 0,
      'credential-shaped input must be denied before adapter execution',
    );

    grants.grant(
      ToolPermissionGrant(
        id: 'grant-once',
        sessionId: 'session-security',
        toolName: 'ide.test.mutate',
        risks: const <IdeToolRisk>{IdeToolRisk.mutating},
        scope: ToolGrantScope.once,
      ),
    );
    final granted = await _callTool(
      server,
      'session-security',
      'ide.test.mutate',
      const <String, Object?>{},
    );
    final replay = await _callTool(
      server,
      'session-security',
      'ide.test.mutate',
      const <String, Object?>{},
    );
    _expect(
      granted['isError'] != true &&
          replay['isError'] == true &&
          _errorCode(replay) == 'permission_required' &&
          mutating.callCount == 1,
      'once grant must authorize exactly one side effect',
    );

    final oversizedCall = await _callTool(
      server,
      'session-security',
      'ide.test.oversized',
      const <String, Object?>{},
    );
    _expect(
      oversizedCall['isError'] == true &&
          _errorCode(oversizedCall) == 'result_limit_exceeded',
      'oversized generic tool output must fail closed',
    );

    final secretCall = await _callTool(
      server,
      'session-security',
      'ide.test.secret',
      const <String, Object?>{},
    );
    final allEvidence = jsonEncode(<String, Object?>{
      'result': secretCall,
      'audit': audit.receipts.map((receipt) => receipt.toJson()).toList(),
    });
    _expect(
      !allEvidence.contains('private-fixture-value') &&
          !allEvidence.contains('fixture-token') &&
          allEvidence.contains('[REDACTED]') &&
          audit.receipts.length <= 8,
      'results and bounded audit receipts must redact secret material',
    );
    _expect(
      audit.receipts.any(
            (receipt) =>
                receipt.code == 'credential_passthrough_denied' &&
                receipt.outcome == ToolAuditOutcome.denied,
          ) &&
          audit.receipts.any(
            (receipt) =>
                receipt.code == 'result_limit_exceeded' &&
                receipt.outcome == ToolAuditOutcome.failed,
          ),
      'denial and output-limit outcomes must be auditable',
    );
  } finally {
    await server.close();
  }
}

/// REQ-IDE-006 and REQ-IDE-007 / criterion 2 / canonical resolver seam.
///
/// Precondition: one approved canonical root and a resolver that maps lexical
/// traversal and a simulated symlink path outside that root.
/// Action: authorize an in-root file, `..` escape, and symlink escape.
/// Oracle: only the canonical in-root path is allowed; both escapes carry
/// stable denial codes and the current root revision.
Future<void> _canonicalRootAuthorizationRejectsTraversalAndLinkEscape() async {
  final resolver = _MappingCanonicalPathResolver(
    mappings: const <String, CanonicalPath>{
      '/approved': CanonicalPath(path: '/approved'),
      '/approved/file.txt': CanonicalPath(path: '/approved/file.txt'),
      '/approved/../outside.txt': CanonicalPath(
        path: '/outside.txt',
        traversedLink: false,
      ),
      '/approved/link/secret.txt': CanonicalPath(
        path: '/outside/secret.txt',
        traversedLink: true,
      ),
    },
  );
  final roots = WorkspaceRootRegistry(resolver: resolver);
  final snapshot = await roots.replaceRoots(
    sessionId: 'session-root',
    proposals: const <WorkspaceRootProposal>[
      WorkspaceRootProposal(path: '/approved', displayName: 'approved'),
    ],
    consentReceiptId: 'consent-root',
  );
  final allowed = await roots.authorize(
    sessionId: 'session-root',
    candidate: '/approved/file.txt',
  );
  final traversal = await roots.authorize(
    sessionId: 'session-root',
    candidate: '/approved/../outside.txt',
  );
  final link = await roots.authorize(
    sessionId: 'session-root',
    candidate: '/approved/link/secret.txt',
  );
  _expect(
    allowed.allowed &&
        allowed.rootRevision == snapshot.revision &&
        !traversal.allowed &&
        traversal.code == 'root_escape_denied' &&
        traversal.rootRevision == snapshot.revision &&
        !link.allowed &&
        link.code == 'symlink_escape_denied' &&
        link.rootRevision == snapshot.revision,
    'canonical containment must reject traversal and symlink escape',
  );
}

Future<void> _rootRevocationDuringResolutionFailsClosed() async {
  final resolver = _ControlledCanonicalPathResolver();
  final roots = WorkspaceRootRegistry(resolver: resolver);
  final snapshot = await roots.replaceRoots(
    sessionId: 'session-race',
    proposals: const <WorkspaceRootProposal>[
      WorkspaceRootProposal(path: '/approved', displayName: 'approved'),
    ],
    consentReceiptId: 'consent-race',
  );

  final authorization = roots.authorize(
    sessionId: 'session-race',
    candidate: '/approved/file.txt',
  );
  await resolver.authorizationStarted.future;
  final revoked = await roots.replaceRoots(
    sessionId: 'session-race',
    proposals: const <WorkspaceRootProposal>[],
    consentReceiptId: 'consent-revoked',
  );
  resolver.releaseAuthorization.complete();
  final result = await authorization;

  _expect(
    !result.allowed &&
        result.code == 'root_revoked' &&
        result.rootRevision == revoked.revision &&
        revoked.revision == snapshot.revision + 1,
    'authorization must fail closed when consent is revoked during resolution',
  );
  await roots.close();
}

Future<Map<String, Object?>> _initialize(
  IdeMcpServer server,
  String sessionId,
) async {
  final result = await _requestResult(
    server,
    sessionId,
    'initialize',
    <String, Object?>{
      'protocolVersion': mcpProtocolVersion,
      'capabilities': const <String, Object?>{
        'roots': <String, Object?>{'listChanged': true},
      },
      'clientInfo': const <String, Object?>{
        'name': 'vityo-acceptance-client',
        'version': '1.0.0',
      },
    },
  );
  await server.handle(
    sessionId: sessionId,
    message: JsonRpcNotification(method: 'notifications/initialized'),
  );
  return result;
}

Future<Map<String, Object?>> _requestResult(
  IdeMcpServer server,
  String sessionId,
  String method, [
  Map<String, Object?> params = const <String, Object?>{},
]) async {
  final response = await server.handle(
    sessionId: sessionId,
    message: JsonRpcRequest(
      id: JsonRpcId.string('$sessionId-$method'),
      method: method,
      params: params,
    ),
  );
  if (response is JsonRpcErrorResponse) {
    throw StateError(
      'unexpected MCP error $method: ${response.error.toJson()}',
    );
  }
  _expect(
    response is JsonRpcSuccessResponse,
    '$method must return one JSON-RPC success response',
  );
  return requireJsonObject(
    (response as JsonRpcSuccessResponse).result,
    '$method result',
  );
}

Future<Map<String, Object?>> _callTool(
  IdeMcpServer server,
  String sessionId,
  String name,
  Map<String, Object?> arguments,
) => _requestResult(server, sessionId, 'tools/call', <String, Object?>{
  'name': name,
  'arguments': arguments,
});

String? _errorCode(Map<String, Object?> result) {
  final structured = result['structuredContent'];
  return structured is Map<String, Object?>
      ? structured['code'] as String?
      : null;
}

IdeToolDescriptor _descriptor({
  required String name,
  required String capability,
  required Set<IdeToolRisk> risks,
  Map<String, Object?> annotations = const <String, Object?>{},
}) => IdeToolDescriptor(
  name: name,
  title: name,
  description: 'Acceptance fixture tool.',
  requiredCapabilityId: capability,
  inputSchema: const <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
    'additionalProperties': true,
  },
  outputSchema: const <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    'type': 'object',
  },
  risks: risks,
  annotations: annotations,
);

Future<void> _eventually(bool Function() predicate, String message) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(message);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

final class _FactsProvider implements IdeFactProvider {
  @override
  Future<RevisionedIdeFacts> read(
    IdeFactQuery query,
    int expectedWorkspaceRevision,
  ) async {
    if (expectedWorkspaceRevision != 12) {
      throw StaleIdeFactRevision(
        expected: expectedWorkspaceRevision,
        current: 12,
      );
    }
    final capabilities = <String, IdeCapabilityFact>{
      'ide.run': IdeCapabilityFact(
        id: 'ide.run',
        domain: IdeCapabilityDomain.run,
        state: IdeCapabilityState.available,
        provenance: 'fixture-toolchain',
        message: 'Authorization: Bearer fixture-token',
      ),
      'ide.test': IdeCapabilityFact(
        id: 'ide.test',
        domain: IdeCapabilityDomain.test,
        state: IdeCapabilityState.degraded,
        provenance: 'fixture-test-adapter',
        message: 'private-fixture-value',
      ),
      'ide.debug': IdeCapabilityFact(
        id: 'ide.debug',
        domain: IdeCapabilityDomain.debug,
        state: IdeCapabilityState.blocked,
        provenance: 'fixture-debug-adapter',
        message: 'Debug adapter unavailable.',
      ),
    };
    return RevisionedIdeFacts(
      workspaceRevision: 12,
      capabilities: CapabilitySnapshot(
        schemaVersion: 1,
        workspaceRevision: 12,
        capabilities: query.capabilityIds.isEmpty
            ? capabilities
            : <String, IdeCapabilityFact>{
                for (final id in query.capabilityIds)
                  if (capabilities[id] case final capability?) id: capability,
              },
      ),
      diagnostics: RevisionedDiagnosticFacts(
        workspaceRevision: 12,
        state: IdeCapabilityState.available,
        provenance: 'fixture-analyzer',
        message: 'Diagnostics complete.',
        diagnostics: <IdeDiagnosticFact>[
          IdeDiagnosticFact(
            resourceId: 'lib/main.dart',
            severity: IdeDiagnosticSeverity.warning,
            code: 'fixture.warning',
            message: 'Fixture warning.',
            line: 1,
            column: 1,
            length: 1,
            provenance: 'fixture-analyzer',
          ),
        ],
      ),
      receipts: const <Never>[],
    );
  }
}

final class _RecordingAdapter implements IdeToolAdapter {
  _RecordingAdapter({required this.descriptor, required this.result});

  @override
  final IdeToolDescriptor descriptor;
  final Map<String, Object?> result;
  int callCount = 0;

  @override
  Future<IdeToolResult> invoke(IdeToolInvocation invocation) async {
    callCount += 1;
    return IdeToolResult(
      structuredContent: result,
      workspaceRevision: invocation.expectedWorkspaceRevision ?? 0,
      provenance: 'acceptance-adapter',
      sensitivity: ContextSensitivity.internal,
    );
  }
}

final class _MappingCanonicalPathResolver implements CanonicalPathResolver {
  const _MappingCanonicalPathResolver({required this.mappings});

  final Map<String, CanonicalPath> mappings;

  @override
  Future<CanonicalPath> resolve(String path) async {
    final resolved = mappings[path];
    if (resolved == null) {
      throw FileSystemException('fixture path is not mapped');
    }
    return resolved;
  }
}

final class _ControlledCanonicalPathResolver implements CanonicalPathResolver {
  final Completer<void> authorizationStarted = Completer<void>();
  final Completer<void> releaseAuthorization = Completer<void>();

  @override
  Future<CanonicalPath> resolve(String path) async {
    if (path == '/approved') {
      return const CanonicalPath(path: '/approved');
    }
    if (path == '/approved/file.txt') {
      if (!authorizationStarted.isCompleted) {
        authorizationStarted.complete();
      }
      await releaseAuthorization.future;
      return const CanonicalPath(path: '/approved/file.txt');
    }
    throw FileSystemException('fixture path is not mapped');
  }
}
