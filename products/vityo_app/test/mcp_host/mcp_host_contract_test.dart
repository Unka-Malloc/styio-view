import 'package:vityo_app/src/ide/agent_client/mcp/workspace_root_registry.dart';
import 'package:vityo_app/src/ide/agent_client/tools/ide_tool_catalog.dart';
import 'package:vityo_app/src/ide/extensions/mcp_extension_registry.dart';
import 'package:test/test.dart';

void main() {
  test('canonical roots replace atomically and revoke immediately', () async {
    final roots = WorkspaceRootRegistry(
      resolver: const _Resolver(<String, CanonicalPath>{
        '/workspace': CanonicalPath(path: '/workspace'),
        '/workspace/file.txt': CanonicalPath(path: '/workspace/file.txt'),
      }),
    );
    final changes = <WorkspaceRootChange>[];
    final subscription = roots.changes.listen(changes.add);

    final approved = await roots.replaceRoots(
      sessionId: 'session',
      proposals: const <WorkspaceRootProposal>[
        WorkspaceRootProposal(path: '/workspace', displayName: 'workspace'),
      ],
      consentReceiptId: 'consent',
    );
    expect(
      await roots.authorize(
        sessionId: 'session',
        candidate: '/workspace/file.txt',
      ),
      isA<RootAuthorization>()
          .having((value) => value.allowed, 'allowed', isTrue)
          .having(
            (value) => value.rootRevision,
            'rootRevision',
            approved.revision,
          ),
    );

    final revoked = await roots.replaceRoots(
      sessionId: 'session',
      proposals: const <WorkspaceRootProposal>[],
      consentReceiptId: 'revoke',
    );
    expect(revoked.roots, isEmpty);
    expect(changes.map((change) => change.revision), <int>[1, 2]);
    expect(
      await roots.authorize(
        sessionId: 'session',
        candidate: '/workspace/file.txt',
      ),
      isA<RootAuthorization>()
          .having((value) => value.allowed, 'allowed', isFalse)
          .having((value) => value.code, 'code', 'root_revoked'),
    );

    await subscription.cancel();
    await roots.close();
  });

  test('extension removal publishes one atomic catalog change', () async {
    final catalog = IdeToolCatalog(adapters: const <IdeToolAdapter>[]);
    catalog.replaceCapabilities('session', const <String>{'extension.read'});
    final changes = <ToolCatalogChange>[];
    final subscription = catalog.changes.listen(changes.add);
    final extensions = McpExtensionRegistry(catalog);
    extensions.register(
      McpExtensionContribution(
        id: 'styio.fixture',
        tools: <IdeToolAdapter>[
          _Adapter('styio.fixture.one'),
          _Adapter('styio.fixture.two'),
        ],
      ),
    );
    extensions.unregister('styio.fixture');

    expect(changes, hasLength(2));
    expect(catalog.visibleTools('session', hasRoots: false), isEmpty);
    await subscription.cancel();
    await catalog.close();
  });
}

final class _Resolver implements CanonicalPathResolver {
  const _Resolver(this.paths);

  final Map<String, CanonicalPath> paths;

  @override
  Future<CanonicalPath> resolve(String path) async {
    final resolved = paths[path];
    if (resolved == null) {
      throw StateError('unmapped fixture path');
    }
    return resolved;
  }
}

final class _Adapter implements IdeToolAdapter {
  _Adapter(String name)
    : descriptor = IdeToolDescriptor(
        name: name,
        title: name,
        description: 'Fixture extension tool.',
        requiredCapabilityId: 'extension.read',
        inputSchema: const <String, Object?>{'type': 'object'},
        outputSchema: const <String, Object?>{'type': 'object'},
        risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
      );

  @override
  final IdeToolDescriptor descriptor;

  @override
  Future<IdeToolResult> invoke(IdeToolInvocation invocation) async =>
      IdeToolResult(
        structuredContent: const <String, Object?>{},
        workspaceRevision: 0,
        provenance: 'fixture',
        sensitivity: ContextSensitivity.internal,
      );
}
