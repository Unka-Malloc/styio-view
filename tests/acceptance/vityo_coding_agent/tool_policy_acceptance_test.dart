import 'dart:async';

import 'package:vityo_coding_agent/vityo_coding_agent.dart';

Future<void> main() async {
  await _catalogAndMcpDiscoveryAreVersionedBoundedAndDynamic();
  await _executionIsSchemaFirstBoundedAndIdempotent();
  await _policyFailsClosedForPathsGrantsNetworkAndHooks();
  await _secretsAreAudienceBoundAndNeverPassThroughReceipts();
  await _cancellationTimeoutAndServerLossRemainTyped();
}

Future<void> _catalogAndMcpDiscoveryAreVersionedBoundedAndDynamic() async {
  final client = _FakeMcpClient(
    discoveries: <Object>[
      McpDiscoveryPage(
        serverVersion: 'v1',
        tools: <McpToolMetadata>[
          _mcpMetadata('mcp.edit', tags: const <String>{'edit'}),
          _mcpMetadata('mcp.search', tags: const <String>{'search'}),
        ],
        hasMore: true,
      ),
      McpDiscoveryPage(
        serverVersion: 'v2',
        tools: <McpToolMetadata>[
          _mcpMetadata('mcp.search', tags: const <String>{'search'}),
        ],
        hasMore: false,
      ),
      McpDiscoveryPage(
        serverVersion: 'v3',
        tools: <McpToolMetadata>[
          const McpToolMetadata(
            id: 'mcp.invalid',
            description: 'invalid schema fixture',
            inputSchema: <String, Object?>{'type': 'string'},
            outputSchema: <String, Object?>{'type': 'object'},
            risk: ToolRisk.read,
            tags: <String>{'invalid'},
          ),
        ],
        hasMore: false,
      ),
      const McpTransportFailure(
        code: McpTransportFailureCode.unavailable,
        message: 'fixture unavailable',
      ),
    ],
  );
  final source = McpToolSource(
    client: client,
    maxTools: 4,
    maxSchemaBytes: 1024,
  );
  final cancellation = AgentCancellationController().token;
  final first = await source.refresh(cancellation);
  _expect(client.requestedLimits.single == 4, 'discovery must be bounded');
  _expect(
    first.version == 'mcp:v1' && first.truncated,
    'server version and discovery truncation must remain visible',
  );
  _expect(
    first.relevantFor(const <String>{'edit'}, limit: 1).single.id == 'mcp.edit',
    'only task-relevant tools should be selected for a provider',
  );
  final second = await source.refresh(cancellation);
  _expect(
    second.version == 'mcp:v2' && second.find('mcp.edit') == null,
    'refresh must remove tools that disappeared from discovery',
  );
  await _expectMcpFailure(
    () => source.refresh(cancellation),
    McpSourceFailureCode.schemaInvalid,
  );
  await _expectMcpFailure(
    () => source.refresh(cancellation),
    McpSourceFailureCode.unavailable,
  );
}

Future<void> _executionIsSchemaFirstBoundedAndIdempotent() async {
  final adapter = _RecordingAdapter(
    result: <String, Object?>{'message': 'written', 'password': 'must-redact'},
  );
  final catalog = ToolCatalog(
    version: 'catalog-1',
    tools: <ToolDescriptor>[
      _descriptor(
        id: 'file.write',
        risk: ToolRisk.write,
        pathArgument: 'path',
        maxResultBytes: 128,
      ),
    ],
  );
  final grants = PermissionGrantStore(maxGrants: 8)
    ..grant(
      const PermissionGrant(
        id: 'write-grant',
        sessionId: 'session',
        toolId: 'file.write',
        risks: <ToolRisk>{ToolRisk.write},
        rootIds: <String>{'root'},
      ),
    );
  final executor = ToolExecutor(
    catalogProvider: () => catalog,
    adapters: <String, ToolAdapter>{'file.write': adapter},
    policyEvaluator: const DefaultPolicyEvaluator(),
    hooks: const <ExecutionHook>[],
    maxReceiptEntries: 8,
  );
  final context = _context(
    grants: grants,
    policy: const ExecutionPolicy(
      version: 1,
      allowedRisks: <ToolRisk>{ToolRisk.write},
      maxResultBytes: 128,
    ),
  );
  const call = ToolCall(
    callId: 'call-1',
    toolId: 'file.write',
    catalogVersion: 'catalog-1',
    arguments: <String, Object?>{'path': 'workspace://root/lib/a.dart'},
    idempotencyKey: 'effect-1',
  );
  final first = await executor.execute(call, context);
  final replay = await executor.execute(call, context);
  _expect(
    first.succeeded &&
        replay.succeeded &&
        replay.reused &&
        first.effectId == replay.effectId &&
        adapter.invocationCount == 1,
    'idempotency must return the original effect receipt without replay',
  );
  _expect(
    first.output['password'] == '[redacted]' &&
        first.untrustedEvidence &&
        first.outputBytes <= 128,
    'tool output must be bounded, redacted, and marked untrusted',
  );
  final invalid = await executor.execute(
    const ToolCall(
      callId: 'invalid',
      toolId: 'file.write',
      catalogVersion: 'catalog-1',
      arguments: <String, Object?>{},
    ),
    context,
  );
  _expect(
    invalid.failure?.code == ToolFailureCode.schemaInvalid &&
        adapter.invocationCount == 1,
    'invalid input must fail before adapter execution',
  );
  final stale = await executor.execute(
    const ToolCall(
      callId: 'stale',
      toolId: 'file.write',
      catalogVersion: 'catalog-0',
      arguments: <String, Object?>{'path': 'workspace://root/lib/a.dart'},
    ),
    context,
  );
  _expect(
    stale.failure?.code == ToolFailureCode.toolRemoved,
    'a stale catalog snapshot must not invoke a current tool',
  );
  final oversizedExecutor = ToolExecutor(
    catalogProvider: () => catalog,
    adapters: <String, ToolAdapter>{
      'file.write': _RecordingAdapter(
        result: <String, Object?>{'message': 'x' * 512},
      ),
    },
    policyEvaluator: const DefaultPolicyEvaluator(),
    hooks: const <ExecutionHook>[],
    maxReceiptEntries: 2,
  );
  final oversized = await oversizedExecutor.execute(
    const ToolCall(
      callId: 'large',
      toolId: 'file.write',
      catalogVersion: 'catalog-1',
      arguments: <String, Object?>{'path': 'workspace://root/lib/a.dart'},
    ),
    context,
  );
  _expect(
    oversized.failure?.code == ToolFailureCode.resultTooLarge,
    'oversized output must fail closed',
  );
}

Future<void> _policyFailsClosedForPathsGrantsNetworkAndHooks() async {
  final adapter = _RecordingAdapter(
    result: const <String, Object?>{'ok': true},
  );
  final descriptors = <ToolDescriptor>[
    _descriptor(id: 'file.read', risk: ToolRisk.read, pathArgument: 'path'),
    _descriptor(
      id: 'network.get',
      risk: ToolRisk.network,
      networkHostArgument: 'host',
    ),
    _descriptor(id: 'process.run', risk: ToolRisk.process),
    _descriptor(id: 'file.destroy', risk: ToolRisk.destructive),
  ];
  final catalog = ToolCatalog(version: 'security-1', tools: descriptors);
  final grants = PermissionGrantStore(maxGrants: 8)
    ..grant(
      const PermissionGrant(
        id: 'read-grant',
        sessionId: 'session',
        toolId: 'file.read',
        risks: <ToolRisk>{ToolRisk.read},
        rootIds: <String>{'root'},
      ),
    )
    ..grant(
      const PermissionGrant(
        id: 'network-grant',
        sessionId: 'session',
        toolId: 'network.get',
        risks: <ToolRisk>{ToolRisk.network},
        rootIds: <String>{'root'},
      ),
    );
  final executor = ToolExecutor(
    catalogProvider: () => catalog,
    adapters: <String, ToolAdapter>{
      for (final descriptor in descriptors) descriptor.id: adapter,
    },
    policyEvaluator: const DefaultPolicyEvaluator(),
    hooks: const <ExecutionHook>[],
    maxReceiptEntries: 8,
  );
  final context = _context(
    grants: grants,
    policy: const ExecutionPolicy(
      version: 1,
      allowedRisks: <ToolRisk>{ToolRisk.read, ToolRisk.network},
      allowedNetworkHosts: <String>{'api.example.test'},
      maxResultBytes: 128,
    ),
  );
  final traversal = await executor.execute(
    const ToolCall(
      callId: 'traversal',
      toolId: 'file.read',
      catalogVersion: 'security-1',
      arguments: <String, Object?>{'path': 'workspace://root/../private'},
    ),
    context,
  );
  _expect(
    traversal.failure?.code == ToolFailureCode.policyDenied,
    'path traversal must be rejected',
  );
  final symlinkEscape = await executor.execute(
    const ToolCall(
      callId: 'symlink',
      toolId: 'file.read',
      catalogVersion: 'security-1',
      arguments: <String, Object?>{'path': 'workspace://root/link'},
    ),
    _context(
      grants: grants,
      policy: context.policy,
      pathResolver: (uri) async => 'workspace://other/escaped',
    ),
  );
  _expect(
    symlinkEscape.failure?.code == ToolFailureCode.policyDenied,
    'resolved symlink escape must be rejected',
  );
  grants.revoke('read-grant');
  final revoked = await executor.execute(
    const ToolCall(
      callId: 'revoked',
      toolId: 'file.read',
      catalogVersion: 'security-1',
      arguments: <String, Object?>{'path': 'workspace://root/lib/a.dart'},
    ),
    context,
  );
  _expect(
    revoked.failure?.code == ToolFailureCode.permissionDenied,
    'revoked grants must be checked at execution time',
  );
  final network = await executor.execute(
    const ToolCall(
      callId: 'network',
      toolId: 'network.get',
      catalogVersion: 'security-1',
      arguments: <String, Object?>{'host': 'evil.example.test'},
    ),
    context,
  );
  _expect(
    network.failure?.code == ToolFailureCode.policyDenied,
    'network hosts outside the exact allowlist must be denied',
  );
  for (final toolId in <String>['process.run', 'file.destroy']) {
    final denied = await executor.execute(
      ToolCall(
        callId: 'deny-$toolId',
        toolId: toolId,
        catalogVersion: 'security-1',
        arguments: const <String, Object?>{},
      ),
      context,
    );
    _expect(
      denied.failure?.code == ToolFailureCode.policyDenied,
      '$toolId must be denied by risk policy',
    );
  }
  final hookExecutor = ToolExecutor(
    catalogProvider: () => catalog,
    adapters: <String, ToolAdapter>{'network.get': adapter},
    policyEvaluator: const DefaultPolicyEvaluator(),
    hooks: const <ExecutionHook>[_RejectingHook()],
    maxReceiptEntries: 2,
  );
  final hookDenied = await hookExecutor.execute(
    const ToolCall(
      callId: 'hook',
      toolId: 'network.get',
      catalogVersion: 'security-1',
      arguments: <String, Object?>{'host': 'api.example.test'},
    ),
    context,
  );
  _expect(
    hookDenied.failure?.code == ToolFailureCode.hookRejected,
    'pre-execution hook rejection must prevent adapter execution',
  );
}

Future<void> _secretsAreAudienceBoundAndNeverPassThroughReceipts() async {
  const secretValue = 'fixture-secret-value';
  final adapter = _RecordingAdapter(
    result: const <String, Object?>{'echo': secretValue},
  );
  final descriptor = _descriptor(
    id: 'cloud.call',
    risk: ToolRisk.credential,
    secretArguments: const <String, String>{'credential': 'cloud-api'},
  );
  final catalog = ToolCatalog(
    version: 'secret-1',
    tools: <ToolDescriptor>[descriptor],
  );
  final grants = PermissionGrantStore(maxGrants: 4)
    ..grant(
      const PermissionGrant(
        id: 'credential-grant',
        sessionId: 'session',
        toolId: 'cloud.call',
        risks: <ToolRisk>{ToolRisk.credential},
        rootIds: <String>{'root'},
      ),
    );
  final executor = ToolExecutor(
    catalogProvider: () => catalog,
    adapters: <String, ToolAdapter>{'cloud.call': adapter},
    policyEvaluator: const DefaultPolicyEvaluator(),
    hooks: const <ExecutionHook>[],
    maxReceiptEntries: 4,
  );
  final context = _context(
    grants: grants,
    policy: const ExecutionPolicy(
      version: 1,
      allowedRisks: <ToolRisk>{ToolRisk.credential},
      maxResultBytes: 128,
    ),
    secretVault: const _FakeSecretVault(
      id: 'cloud-token',
      audience: 'cloud-api',
      value: secretValue,
    ),
  );
  final raw = await executor.execute(
    const ToolCall(
      callId: 'raw',
      toolId: 'cloud.call',
      catalogVersion: 'secret-1',
      arguments: <String, Object?>{'credential': 'Bearer raw-token'},
    ),
    context,
  );
  _expect(
    raw.failure?.code == ToolFailureCode.policyDenied &&
        adapter.invocationCount == 0,
    'raw credential passthrough must be rejected',
  );
  final wrongAudience = await executor.execute(
    const ToolCall(
      callId: 'wrong-audience',
      toolId: 'cloud.call',
      catalogVersion: 'secret-1',
      arguments: <String, Object?>{
        'credential': 'secret://cloud-token?audience=other-api',
      },
    ),
    context,
  );
  _expect(
    wrongAudience.failure?.code == ToolFailureCode.policyDenied,
    'secret references must be bound to the descriptor audience',
  );
  final allowed = await executor.execute(
    const ToolCall(
      callId: 'secret',
      toolId: 'cloud.call',
      catalogVersion: 'secret-1',
      arguments: <String, Object?>{
        'credential': 'secret://cloud-token?audience=cloud-api',
      },
    ),
    context,
  );
  _expect(
    allowed.succeeded &&
        adapter.lastArguments['credential'] == secretValue &&
        !allowed.toString().contains(secretValue) &&
        allowed.output['echo'] == '[redacted]',
    'resolved secrets may reach only the intended adapter and never the receipt',
  );
}

Future<void> _cancellationTimeoutAndServerLossRemainTyped() async {
  final descriptor = _descriptor(id: 'slow.read', risk: ToolRisk.read);
  final catalog = ToolCatalog(
    version: 'slow-1',
    tools: <ToolDescriptor>[descriptor],
  );
  final grants = PermissionGrantStore(maxGrants: 2)
    ..grant(
      const PermissionGrant(
        id: 'slow-grant',
        sessionId: 'session',
        toolId: 'slow.read',
        risks: <ToolRisk>{ToolRisk.read},
        rootIds: <String>{'root'},
      ),
    );
  final cancellation = AgentCancellationController()..cancel();
  final executor = ToolExecutor(
    catalogProvider: () => catalog,
    adapters: <String, ToolAdapter>{'slow.read': _NeverAdapter()},
    policyEvaluator: const DefaultPolicyEvaluator(),
    hooks: const <ExecutionHook>[],
    maxReceiptEntries: 2,
  );
  final cancelled = await executor.execute(
    const ToolCall(
      callId: 'cancelled',
      toolId: 'slow.read',
      catalogVersion: 'slow-1',
      arguments: <String, Object?>{},
    ),
    _context(
      grants: grants,
      cancellation: cancellation.token,
      policy: const ExecutionPolicy(
        version: 1,
        allowedRisks: <ToolRisk>{ToolRisk.read},
        maxResultBytes: 64,
      ),
    ),
  );
  _expect(
    cancelled.failure?.code == ToolFailureCode.cancelled,
    'pre-cancelled execution must remain typed',
  );
  final timedOut = await executor.execute(
    const ToolCall(
      callId: 'timeout',
      toolId: 'slow.read',
      catalogVersion: 'slow-1',
      arguments: <String, Object?>{},
    ),
    _context(
      grants: grants,
      deadline: DateTime.now().add(const Duration(milliseconds: 20)),
      policy: const ExecutionPolicy(
        version: 1,
        allowedRisks: <ToolRisk>{ToolRisk.read},
        maxResultBytes: 64,
      ),
    ),
  );
  _expect(
    timedOut.failure?.code == ToolFailureCode.timeout,
    'deadline must terminate a hanging adapter',
  );
}

ToolDescriptor _descriptor({
  required String id,
  required ToolRisk risk,
  String? pathArgument,
  String? networkHostArgument,
  Map<String, String> secretArguments = const <String, String>{},
  int maxResultBytes = 256,
}) => ToolDescriptor(
  id: id,
  description: 'fixture $id',
  sourceKind: ToolSourceKind.builtin,
  inputSchema: <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      if (pathArgument != null)
        pathArgument: const <String, Object?>{'type': 'string'},
      if (networkHostArgument != null)
        networkHostArgument: const <String, Object?>{'type': 'string'},
      for (final argument in secretArguments.keys)
        argument: const <String, Object?>{'type': 'string'},
    },
    'required': <String>[
      if (pathArgument != null) pathArgument,
      if (networkHostArgument != null) networkHostArgument,
      ...secretArguments.keys,
    ],
    'additionalProperties': false,
  },
  outputSchema: const <String, Object?>{'type': 'object'},
  risk: risk,
  tags: <String>{risk.name},
  pathArgument: pathArgument,
  networkHostArgument: networkHostArgument,
  secretArguments: secretArguments,
  maxResultBytes: maxResultBytes,
);

McpToolMetadata _mcpMetadata(String id, {required Set<String> tags}) =>
    McpToolMetadata(
      id: id,
      description: 'fixture $id',
      inputSchema: const <String, Object?>{'type': 'object'},
      outputSchema: const <String, Object?>{'type': 'object'},
      risk: ToolRisk.read,
      tags: tags,
    );

ToolExecutionContext _context({
  required PermissionGrantStore grants,
  required ExecutionPolicy policy,
  AgentCancellationToken? cancellation,
  DateTime? deadline,
  Future<String> Function(String uri)? pathResolver,
  SecretVault? secretVault,
}) => ToolExecutionContext(
  sessionId: 'session',
  observedAt: DateTime.now(),
  deadline: deadline,
  cancellation: cancellation ?? AgentCancellationController().token,
  roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
  policy: policy,
  grants: grants,
  pathResolver: pathResolver ?? (uri) async => uri,
  secretVault: secretVault,
);

final class _FakeMcpClient implements McpClient {
  _FakeMcpClient({required List<Object> discoveries})
    : _discoveries = List<Object>.of(discoveries);

  final List<Object> _discoveries;
  final List<int> requestedLimits = <int>[];

  @override
  Future<McpDiscoveryPage> listTools({
    required int limit,
    required AgentCancellationToken cancellation,
  }) async {
    requestedLimits.add(limit);
    final next = _discoveries.removeAt(0);
    if (next is McpTransportFailure) throw next;
    return next as McpDiscoveryPage;
  }

  @override
  Future<Map<String, Object?>> callTool(
    String id,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) async => <String, Object?>{'id': id};
}

final class _RecordingAdapter implements ToolAdapter {
  _RecordingAdapter({required this.result});

  final Map<String, Object?> result;
  int invocationCount = 0;
  Map<String, Object?> lastArguments = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) async {
    invocationCount += 1;
    lastArguments = Map<String, Object?>.of(arguments);
    return result;
  }
}

final class _NeverAdapter implements ToolAdapter {
  @override
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) => Completer<Map<String, Object?>>().future;
}

final class _RejectingHook implements ExecutionHook {
  const _RejectingHook();

  @override
  Future<Map<String, Object?>> before(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
  ) => throw const ToolHookRejection('fixture rejection');

  @override
  Future<Map<String, Object?>> after(
    ToolDescriptor descriptor,
    Map<String, Object?> output,
  ) async => output;
}

final class _FakeSecretVault implements SecretVault {
  const _FakeSecretVault({
    required this.id,
    required this.audience,
    required this.value,
  });

  final String id;
  final String audience;
  final String value;

  @override
  Future<String?> resolve(String secretId, {required String audience}) async =>
      secretId == id && audience == this.audience ? value : null;
}

Future<void> _expectMcpFailure(
  Future<Object?> Function() action,
  McpSourceFailureCode code,
) async {
  try {
    await action();
  } on McpSourceFailure catch (error) {
    _expect(
      error.code == code,
      'expected ${code.name}, got ${error.code.name}',
    );
    return;
  }
  throw StateError('expected McpSourceFailure(${code.name})');
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
