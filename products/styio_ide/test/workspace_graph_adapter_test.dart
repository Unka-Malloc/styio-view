import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_adapter.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/workspace_graph_adapter.dart';

void main() {
  test('canonical-file project facts keep workspace graph partial', () async {
    final adapter = WorkspaceGraphAdapter(
      projectGraphAdapter: _StaticProjectGraphAdapter(
        _projectGraph(ProjectGraphSnapshot.canonicalFileSourceConfidence()),
      ),
      workspaceRootUri: Uri.parse('file:///workspace'),
    );

    final event = await adapter.loadWorkspaceGraph();

    expect(event.snapshot.isPartial, isTrue);
    expect(event.snapshot.upstreamPayloadMissing, isFalse);
    expect(event.snapshot.partialReason, contains('canonical-file'));
  });

  test('machine-payload project facts allow full workspace graph', () async {
    final adapter = WorkspaceGraphAdapter(
      projectGraphAdapter: _StaticProjectGraphAdapter(
        _projectGraph(ProjectGraphSnapshot.machinePayloadSourceConfidence()),
      ),
      workspaceRootUri: Uri.parse('file:///workspace'),
    );

    final event = await adapter.loadWorkspaceGraph();

    expect(event.snapshot.isPartial, isFalse);
    expect(event.snapshot.partialReason, isNull);
  });
}

ProjectGraphSnapshot _projectGraph(
  Map<String, ProjectGraphFieldSourceConfidence> sourceConfidenceByField,
) {
  const target = ProjectTargetDescriptor(
    id: 'demo/app:bin:demo',
    packageName: 'demo/app',
    kind: ProjectTargetKind.bin,
    name: 'demo',
    filePath: '/workspace/src/main.styio',
  );
  return ProjectGraphSnapshot(
    id: '/workspace/pafio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/pafio.toml',
    packages: const <ProjectPackageSnapshot>[
      ProjectPackageSnapshot(
        packageName: 'demo/app',
        version: '0.1.0',
        rootPath: '/workspace',
        manifestPath: '/workspace/pafio.toml',
        targets: <ProjectTargetDescriptor>[target],
      ),
    ],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[target],
    editorFiles: const <String>['/workspace/src/main.styio'],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'No toolchain resolved for this fixture.',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.missing,
    sourceConfidenceByField: sourceConfidenceByField,
    notes: const <String>[],
  );
}

class _StaticProjectGraphAdapter implements ProjectGraphAdapter {
  const _StaticProjectGraphAdapter(this.snapshot);

  final ProjectGraphSnapshot snapshot;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot =>
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Not used by this fixture.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail: 'Static project graph fixture.',
          supportedContractVersions: <int>[1],
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Not used by this fixture.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Not used by this fixture.',
        ),
      );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async => snapshot;
}
