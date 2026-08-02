import 'dart:convert';

import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/agent_client/tools/context_export_service.dart';
import 'package:vityo_app/src/ide/agent_client/tools/ide_tool_catalog.dart';
import 'package:vityo_app/src/ide/agent_client/tools/tool_security_policy.dart';
import 'package:vityo_app/src/ide/language/diagnostic_fact.dart';
import 'package:vityo_app/src/ide/workbench/capability_snapshot.dart';
import 'package:vityo_app/src/ide/workbench/ide_fact_provider.dart';
import 'package:test/test.dart';

void main() {
  test(
    'session reducer serializes and bounds its immutable projection',
    () async {
      final reducer = AgentSessionReducer(
        sessionId: 'session-1',
        maxBufferedUpdates: 2,
        backpressurePolicy: const AgentEventBackpressurePolicy(
          maxQueuedEvents: 3,
          maxQueuedBytes: 1024 * 1024,
          maxHotHistoryEvents: 2,
          maxHotHistoryBytes: 1024 * 1024,
        ),
      );
      await Future.wait(<Future<void>>[
        reducer.reduce(
          const AgentSessionUpdate(
            sessionId: 'session-1',
            kind: 'chunk',
            text: 'one',
            payload: <String, Object?>{},
          ),
        ),
        reducer.reduce(
          const AgentSessionUpdate(
            sessionId: 'session-1',
            kind: 'chunk',
            text: 'two',
            payload: <String, Object?>{},
          ),
        ),
        reducer.reduce(
          const AgentSessionUpdate(
            sessionId: 'session-1',
            kind: 'chunk',
            text: 'three',
            payload: <String, Object?>{},
          ),
        ),
      ]);

      expect(reducer.snapshot.revision, 3);
      expect(reducer.snapshot.updates.map((update) => update.text), <String?>[
        'two',
        'three',
      ]);
      await reducer.close();
    },
  );

  test('policy rejects extensions outside the Vityo namespace', () {
    expect(
      () => AgentClientRegistry(
        descriptors: <String, AgentLaunchDescriptor>{
          'agent': AgentLaunchDescriptor(
            id: 'agent',
            executable: 'agent',
            arguments: const <String>[],
            workingDirectory: '.',
          ),
        },
        policy: const AgentClientPolicy(allowedExtensions: <String>{'unsafe'}),
      ),
      throwsArgumentError,
    );
  });

  test('registry validates policy at runtime and snapshots extension sets', () {
    expect(
      () => AgentClientRegistry(
        descriptors: <String, AgentLaunchDescriptor>{
          'agent': AgentLaunchDescriptor(
            id: 'agent',
            executable: 'agent',
            arguments: const <String>[],
            workingDirectory: '.',
          ),
        },
        policy: const AgentClientPolicy(requestTimeout: Duration.zero),
      ),
      throwsArgumentError,
    );

    final extensions = <String>{'_vityo.dev/test'};
    final registry = AgentClientRegistry(
      descriptors: <String, AgentLaunchDescriptor>{
        'agent': AgentLaunchDescriptor(
          id: 'agent',
          executable: 'agent',
          arguments: const <String>[],
          workingDirectory: '.',
        ),
      },
      policy: AgentClientPolicy(allowedExtensions: extensions),
    );
    addTearDown(registry.close);
    extensions.clear();
    expect(registry.policy.allowedExtensions, contains('_vityo.dev/test'));
  });

  test(
    'workspace routes and pending permission delivery are bounded',
    () async {
      final registry = AgentClientRegistry(
        descriptors: <String, AgentLaunchDescriptor>{
          'agent': AgentLaunchDescriptor(
            id: 'agent',
            executable: 'agent',
            arguments: const <String>[],
            workingDirectory: '.',
          ),
        },
      );
      addTearDown(registry.close);
      await expectLater(
        registry.newSession(
          agentId: 'agent',
          cwd: Uri.parse('https://example.invalid/workspace'),
        ),
        throwsA(
          isA<AgentClientFailure>().having(
            (failure) => failure.code,
            'code',
            'invalid_workspace',
          ),
        ),
      );

      final permissions = PermissionRequestQueue(maxItems: 1);
      const first = AgentPermissionRequest(
        id: 'permission-1',
        agentId: 'agent',
        sessionId: 'session',
        toolCallId: 'tool-permission-1',
        options: <String>{'allow_once'},
      );
      expect(permissions.add(first), isTrue);
      expect(
        permissions.add(
          const AgentPermissionRequest(
            id: 'permission-2',
            agentId: 'agent',
            sessionId: 'session',
            toolCallId: 'tool-permission-2',
            options: <String>{'reject_once'},
          ),
        ),
        isFalse,
      );
      permissions.removeWhere((request) => request.id == first.id);
      expect(
        permissions.add(
          const AgentPermissionRequest(
            id: 'permission-2',
            agentId: 'agent',
            sessionId: 'session',
            toolCallId: 'tool-permission-2',
            options: <String>{'reject_once'},
          ),
        ),
        isTrue,
      );
      permissions.close();
    },
  );

  test('cancelled permission consumers release waiter capacity', () async {
    final permissions = PermissionRequestQueue(maxItems: 1);
    final abandoned = permissions.stream().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await abandoned.cancel();

    final next = permissions.stream().first;
    await Future<void>.delayed(Duration.zero);
    const request = AgentPermissionRequest(
      id: 'permission',
      agentId: 'agent',
      sessionId: 'session',
      toolCallId: 'tool-permission',
      options: <String>{'allow_once'},
    );
    expect(permissions.add(request), isTrue);
    expect(await next, same(request));
    permissions.close();
  });

  test(
    'priority lifecycle update survives a saturated reducer queue',
    () async {
      final reducer = AgentSessionReducer(
        sessionId: 'session-1',
        maxBufferedUpdates: 1,
        backpressurePolicy: const AgentEventBackpressurePolicy(
          maxQueuedEvents: 1,
          maxQueuedBytes: 1024,
          maxHotHistoryEvents: 1,
          maxHotHistoryBytes: 1024,
        ),
      );
      final ordinary = reducer.reduce(
        const AgentSessionUpdate(
          sessionId: 'session-1',
          kind: 'chunk',
          text: 'ordinary',
          payload: <String, Object?>{},
        ),
      );
      await reducer.reducePriority(
        const AgentSessionUpdate(
          sessionId: 'session-1',
          kind: 'session_state',
          payload: <String, Object?>{'status': 'failed'},
        ),
      );
      await ordinary;

      expect(reducer.snapshot.updates.single.kind, 'session_state');
      await reducer.close();
    },
  );

  test(
    'context pagination skips evidence that cannot fit an empty page',
    () async {
      const revision = 7;
      final facts = RevisionedIdeFacts(
        workspaceRevision: revision,
        capabilities: CapabilitySnapshot(
          schemaVersion: 1,
          workspaceRevision: revision,
          capabilities: <String, IdeCapabilityFact>{
            'a-large': IdeCapabilityFact(
              id: 'a-large',
              domain: IdeCapabilityDomain.language,
              state: IdeCapabilityState.available,
              provenance: 'test',
              message: List<String>.filled(4096, 'x').join(),
            ),
            'b-small': IdeCapabilityFact(
              id: 'b-small',
              domain: IdeCapabilityDomain.language,
              state: IdeCapabilityState.available,
              provenance: 'test',
              message: 'ready',
            ),
          },
        ),
        diagnostics: RevisionedDiagnosticFacts(
          workspaceRevision: revision,
          state: IdeCapabilityState.available,
          provenance: 'test',
          message: 'ready',
          diagnostics: const <IdeDiagnosticFact>[],
        ),
        receipts: const [],
      );
      final service = RevisionedIdeContextExportService(
        provider: _StaticIdeFactProvider(facts),
        currentWorkspaceRevision: () => revision,
        sanitizer: const McpPayloadSanitizer(),
      );
      final complete = await service.read(
        const ContextQuery(expectedWorkspaceRevision: revision),
        const ContextBudget(
          maxItems: 3,
          maxUtf8Bytes: 1024 * 1024,
          maxCodeUnitsPerItem: 8192,
        ),
      );
      final smallItem = complete.items.singleWhere(
        (item) => item.id == 'capability:b-small',
      );
      final smallItemBytes = utf8.encode(jsonEncode(smallItem.toJson())).length;

      final first = await service.read(
        const ContextQuery(expectedWorkspaceRevision: revision),
        ContextBudget(
          maxItems: 1,
          maxUtf8Bytes: smallItemBytes,
          maxCodeUnitsPerItem: 8192,
        ),
      );

      expect(first.items.single.id, 'capability:b-small');
      expect(first.omittedItemCount, 2);
      expect(first.omittedUtf8Bytes, greaterThan(0));
      expect(first.truncated, isTrue);
      expect(first.nextCursor, isNotNull);

      final second = await service.read(
        ContextQuery(
          expectedWorkspaceRevision: revision,
          cursor: first.nextCursor,
        ),
        ContextBudget(
          maxItems: 1,
          maxUtf8Bytes: smallItemBytes,
          maxCodeUnitsPerItem: 8192,
        ),
      );
      expect(second.nextCursor, isNot(first.nextCursor));

      final negativeCursor = base64Url.encode(
        utf8.encode(
          jsonEncode(<String, Object?>{'revision': revision, 'index': -1}),
        ),
      );
      await expectLater(
        service.read(
          ContextQuery(
            expectedWorkspaceRevision: revision,
            cursor: negativeCursor,
          ),
          const ContextBudget(
            maxItems: 1,
            maxUtf8Bytes: 1024,
            maxCodeUnitsPerItem: 1024,
          ),
        ),
        throwsA(
          isA<IdeToolFailure>().having(
            (failure) => failure.code,
            'code',
            'invalid_cursor',
          ),
        ),
      );
    },
  );
}

final class _StaticIdeFactProvider implements IdeFactProvider {
  const _StaticIdeFactProvider(this.facts);

  final RevisionedIdeFacts facts;

  @override
  Future<RevisionedIdeFacts> read(
    IdeFactQuery query,
    int expectedWorkspaceRevision,
  ) async {
    if (expectedWorkspaceRevision != facts.workspaceRevision) {
      throw StaleIdeFactRevision(
        expected: expectedWorkspaceRevision,
        current: facts.workspaceRevision,
      );
    }
    return facts;
  }
}
