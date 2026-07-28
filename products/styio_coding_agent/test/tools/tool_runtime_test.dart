import 'dart:async';

import 'package:styio_coding_agent/styio_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  test('catalog relevance is deterministic and schema rejects extras', () {
    final catalog = ToolCatalog(
      version: '1',
      tools: <ToolDescriptor>[
        _descriptor('z.search', const <String>{'search'}),
        _descriptor('a.edit', const <String>{'edit'}),
      ],
    );
    expect(
      catalog
          .relevantFor(const <String>{'edit'}, limit: 1)
          .map((tool) => tool.id),
      <String>['a.edit'],
    );
    expect(
      ToolSchema.accepts(
        catalog.find('a.edit')!.inputSchema,
        const <String, Object?>{'unknown': true},
      ),
      isFalse,
    );
  });

  test('same idempotency key executes an adapter once', () async {
    final descriptor = _descriptor('read', const <String>{'read'});
    final catalog = ToolCatalog(
      version: '1',
      tools: <ToolDescriptor>[descriptor],
    );
    final grants = PermissionGrantStore(maxGrants: 2)
      ..grant(
        const PermissionGrant(
          id: 'grant',
          sessionId: 'session',
          toolId: 'read',
          risks: <ToolRisk>{ToolRisk.read},
          rootIds: <String>{'root'},
        ),
      );
    final adapter = _Adapter();
    final executor = ToolExecutor(
      catalogProvider: () => catalog,
      adapters: <String, ToolAdapter>{'read': adapter},
      policyEvaluator: const DefaultPolicyEvaluator(),
      hooks: const <ExecutionHook>[],
      maxReceiptEntries: 2,
    );
    const call = ToolCall(
      callId: 'call',
      toolId: 'read',
      catalogVersion: '1',
      arguments: <String, Object?>{},
      idempotencyKey: 'same-effect',
    );
    final context = ToolExecutionContext(
      sessionId: 'session',
      observedAt: DateTime.now(),
      cancellation: AgentCancellationController().token,
      roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
      policy: const ExecutionPolicy(
        version: 1,
        allowedRisks: <ToolRisk>{ToolRisk.read},
        maxResultBytes: 64,
      ),
      grants: grants,
      pathResolver: (uri) async => uri,
    );
    final first = await executor.execute(call, context);
    final second = await executor.execute(call, context);
    expect(first.succeeded, isTrue);
    expect(second.reused, isTrue);
    expect(adapter.count, 1);
  });

  test('pre-effect denial is not cached as an idempotent effect', () async {
    final descriptor = _descriptor('read', const <String>{'read'});
    final catalog = ToolCatalog(
      version: '1',
      tools: <ToolDescriptor>[descriptor],
    );
    final grants = PermissionGrantStore(maxGrants: 2);
    final adapter = _Adapter();
    final executor = ToolExecutor(
      catalogProvider: () => catalog,
      adapters: <String, ToolAdapter>{'read': adapter},
      policyEvaluator: const DefaultPolicyEvaluator(),
      hooks: const <ExecutionHook>[],
      maxReceiptEntries: 2,
    );
    const call = ToolCall(
      callId: 'denied-then-allowed',
      toolId: 'read',
      catalogVersion: '1',
      arguments: <String, Object?>{},
      idempotencyKey: 'effect',
    );
    final context = ToolExecutionContext(
      sessionId: 'session',
      observedAt: DateTime.now(),
      cancellation: AgentCancellationController().token,
      roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
      policy: const ExecutionPolicy(
        version: 1,
        allowedRisks: <ToolRisk>{ToolRisk.read},
        maxResultBytes: 64,
      ),
      grants: grants,
      pathResolver: (uri) async => uri,
    );
    final denied = await executor.execute(call, context);
    grants.grant(
      const PermissionGrant(
        id: 'grant',
        sessionId: 'session',
        toolId: 'read',
        risks: <ToolRisk>{ToolRisk.read},
        rootIds: <String>{'root'},
      ),
    );
    final allowed = await executor.execute(call, context);
    expect(denied.effectState, ToolEffectState.none);
    expect(allowed.succeeded, isTrue);
    expect(allowed.reused, isFalse);
    expect(adapter.count, 1);
  });

  test(
    'concurrent effects are bounded and malformed MCP schema stays typed',
    () async {
      final descriptor = _descriptor('read', const <String>{'read'});
      final grants = PermissionGrantStore(maxGrants: 1)
        ..grant(
          const PermissionGrant(
            id: 'grant',
            sessionId: 'session',
            toolId: 'read',
            risks: <ToolRisk>{ToolRisk.read},
            rootIds: <String>{'root'},
          ),
        );
      final adapter = _ControlledAdapter();
      final executor = ToolExecutor(
        catalogProvider: () =>
            ToolCatalog(version: '1', tools: <ToolDescriptor>[descriptor]),
        adapters: <String, ToolAdapter>{'read': adapter},
        policyEvaluator: const DefaultPolicyEvaluator(),
        hooks: const <ExecutionHook>[],
        maxReceiptEntries: 1,
      );
      final context = ToolExecutionContext(
        sessionId: 'session',
        observedAt: DateTime.now(),
        cancellation: AgentCancellationController().token,
        roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
        policy: const ExecutionPolicy(
          version: 1,
          allowedRisks: <ToolRisk>{ToolRisk.read},
          maxResultBytes: 64,
        ),
        grants: grants,
        pathResolver: (uri) async => uri,
      );
      final first = executor.execute(
        const ToolCall(
          callId: 'first',
          toolId: 'read',
          catalogVersion: '1',
          arguments: <String, Object?>{},
        ),
        context,
      );
      await adapter.started.future;
      final saturated = await executor.execute(
        const ToolCall(
          callId: 'second',
          toolId: 'read',
          catalogVersion: '1',
          arguments: <String, Object?>{},
        ),
        context,
      );
      expect(saturated.failure?.code, ToolFailureCode.capacityExceeded);
      adapter.complete();
      expect((await first).succeeded, isTrue);

      final schema = <String, Object?>{'type': 'object'};
      final untrustedSource = McpToolSource(
        client: _McpClient(schema),
        maxTools: 1,
        maxSchemaBytes: 128,
      );
      expect(
        (await untrustedSource.refresh(
          AgentCancellationController().token,
        )).tools.single.risk,
        ToolRisk.destructive,
      );
      final trustedSource = McpToolSource(
        client: _McpClient(schema),
        maxTools: 1,
        maxSchemaBytes: 128,
        trustedRiskOverrides: const <String, ToolRisk>{'cyclic': ToolRisk.read},
      );
      expect(
        (await trustedSource.refresh(
          AgentCancellationController().token,
        )).tools.single.risk,
        ToolRisk.read,
      );
      schema['properties'] = <String, Object?>{'self': schema};
      final invalidSource = McpToolSource(
        client: _McpClient(schema),
        maxTools: 1,
        maxSchemaBytes: 128,
      );
      await expectLater(
        invalidSource.refresh(AgentCancellationController().token),
        throwsA(
          isA<McpSourceFailure>().having(
            (error) => error.code,
            'code',
            McpSourceFailureCode.schemaInvalid,
          ),
        ),
      );
    },
  );
}

ToolDescriptor _descriptor(String id, Set<String> tags) => ToolDescriptor(
  id: id,
  description: id,
  sourceKind: ToolSourceKind.builtin,
  inputSchema: const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
    'additionalProperties': false,
  },
  outputSchema: const <String, Object?>{'type': 'object'},
  risk: ToolRisk.read,
  tags: tags,
);

final class _Adapter implements ToolAdapter {
  int count = 0;

  @override
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) async {
    count += 1;
    return const <String, Object?>{'ok': true};
  }
}

final class _ControlledAdapter implements ToolAdapter {
  final Completer<void> started = Completer<void>();
  final Completer<Map<String, Object?>> _result =
      Completer<Map<String, Object?>>();

  void complete() => _result.complete(const <String, Object?>{'ok': true});

  @override
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) {
    started.complete();
    return _result.future;
  }
}

final class _McpClient implements McpClient {
  _McpClient(this.schema);

  final Map<String, Object?> schema;

  @override
  Future<McpDiscoveryPage> listTools({
    required int limit,
    required AgentCancellationToken cancellation,
  }) async => McpDiscoveryPage(
    serverVersion: '1',
    tools: <McpToolMetadata>[
      McpToolMetadata(
        id: 'cyclic',
        description: 'cyclic',
        inputSchema: schema,
        outputSchema: const <String, Object?>{'type': 'object'},
        risk: ToolRisk.read,
        tags: const <String>{'read'},
      ),
    ],
    hasMore: false,
  );

  @override
  Future<Map<String, Object?>> callTool(
    String id,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) async => const <String, Object?>{};
}
