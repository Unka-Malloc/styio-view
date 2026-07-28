import 'dart:async';

import 'package:styio_coding_agent/styio_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  test('resolved paths require the same exact approved root', () {
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
    final decision = const DefaultPolicyEvaluator().evaluate(
      effect: const ToolEffect(
        toolId: 'read',
        risk: ToolRisk.read,
        requestedPath: 'workspace://root/link',
        resolvedPath: 'workspace://rooted/escaped',
      ),
      policy: const ExecutionPolicy(
        version: 1,
        allowedRisks: <ToolRisk>{ToolRisk.read},
        maxResultBytes: 64,
      ),
      roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
      grants: grants,
      sessionId: 'session',
    );
    expect(decision.code, PolicyDecisionCode.policyDenied);
  });

  test('revocation changes the execution-time permission decision', () {
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
    grants.revoke('grant');
    final decision = const DefaultPolicyEvaluator().evaluate(
      effect: const ToolEffect(toolId: 'read', risk: ToolRisk.read),
      policy: const ExecutionPolicy(
        version: 1,
        allowedRisks: <ToolRisk>{ToolRisk.read},
        maxResultBytes: 64,
      ),
      roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
      grants: grants,
      sessionId: 'session',
    );
    expect(decision.code, PolicyDecisionCode.permissionDenied);
  });

  test('grant and policy snapshots resist caller mutation', () {
    final risks = <ToolRisk>{ToolRisk.read};
    final roots = <String>{'root'};
    final grants = PermissionGrantStore(maxGrants: 1)
      ..grant(
        PermissionGrant(
          id: 'grant',
          sessionId: 'session',
          toolId: 'read',
          risks: risks,
          rootIds: roots,
        ),
      );
    risks.clear();
    roots.clear();
    final allowedRisks = <ToolRisk>{ToolRisk.read};
    final context = ToolExecutionContext(
      sessionId: 'session',
      observedAt: DateTime.now(),
      cancellation: AgentCancellationController().token,
      roots: const <ToolRoot>[ToolRoot(id: 'root', uri: 'workspace://root/')],
      policy: ExecutionPolicy(
        version: 1,
        allowedRisks: allowedRisks,
        maxResultBytes: 64,
      ),
      grants: grants,
      pathResolver: (uri) async => uri,
    );
    allowedRisks.clear();
    final decision = const DefaultPolicyEvaluator().evaluate(
      effect: const ToolEffect(toolId: 'read', risk: ToolRisk.read),
      policy: context.policy,
      roots: context.roots,
      grants: grants,
      sessionId: 'session',
    );
    expect(decision.allowed, isTrue);
  });

  test(
    'secret resolution is deadline-bound and embedded values redact',
    () async {
      final descriptor = ToolDescriptor(
        id: 'cloud',
        description: 'cloud fixture',
        sourceKind: ToolSourceKind.builtin,
        inputSchema: const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'credential': <String, Object?>{'type': 'string'},
          },
          'required': <String>['credential'],
          'additionalProperties': false,
        },
        outputSchema: const <String, Object?>{'type': 'object'},
        risk: ToolRisk.credential,
        tags: const <String>{'cloud'},
        secretArguments: const <String, String>{'credential': 'cloud'},
      );
      final grants = PermissionGrantStore(maxGrants: 1)
        ..grant(
          const PermissionGrant(
            id: 'grant',
            sessionId: 'session',
            toolId: 'cloud',
            risks: <ToolRisk>{ToolRisk.credential},
            rootIds: <String>{'root'},
          ),
        );
      final executor = ToolExecutor(
        catalogProvider: () =>
            ToolCatalog(version: '1', tools: <ToolDescriptor>[descriptor]),
        adapters: <String, ToolAdapter>{'cloud': _SecretEchoAdapter()},
        policyEvaluator: const DefaultPolicyEvaluator(),
        hooks: const <ExecutionHook>[],
        maxReceiptEntries: 2,
      );
      const call = ToolCall(
        callId: 'secret',
        toolId: 'cloud',
        catalogVersion: '1',
        arguments: <String, Object?>{
          'credential': 'secret://id?audience=cloud',
        },
      );
      ToolExecutionContext context(SecretVault vault, {DateTime? deadline}) =>
          ToolExecutionContext(
            sessionId: 'session',
            observedAt: DateTime.now(),
            deadline: deadline,
            cancellation: AgentCancellationController().token,
            roots: const <ToolRoot>[
              ToolRoot(id: 'root', uri: 'workspace://root/'),
            ],
            policy: const ExecutionPolicy(
              version: 1,
              allowedRisks: <ToolRisk>{ToolRisk.credential},
              maxResultBytes: 128,
            ),
            grants: grants,
            pathResolver: (uri) async => uri,
            secretVault: vault,
          );
      final allowed = await executor.execute(
        call,
        context(const _SecretVault()),
      );
      expect(allowed.output['message'], '[redacted]');
      final timedOut = await executor.execute(
        const ToolCall(
          callId: 'secret-timeout',
          toolId: 'cloud',
          catalogVersion: '1',
          arguments: <String, Object?>{
            'credential': 'secret://id?audience=cloud',
          },
        ),
        context(
          _NeverVault(),
          deadline: DateTime.now().add(const Duration(milliseconds: 20)),
        ),
      );
      expect(timedOut.failure?.code, ToolFailureCode.timeout);
    },
  );
}

final class _SecretVault implements SecretVault {
  const _SecretVault();

  @override
  Future<String?> resolve(String secretId, {required String audience}) async =>
      'secret-value';
}

final class _NeverVault implements SecretVault {
  @override
  Future<String?> resolve(String secretId, {required String audience}) =>
      Completer<String?>().future;
}

final class _SecretEchoAdapter implements ToolAdapter {
  @override
  Future<Map<String, Object?>> execute(
    ToolDescriptor descriptor,
    Map<String, Object?> arguments,
    AgentCancellationToken cancellation,
  ) async => <String, Object?>{
    'message': 'prefix ${arguments['credential']} suffix',
  };
}
