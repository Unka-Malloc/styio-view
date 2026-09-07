import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/project_graph_controller.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';

void main() {
  test(
    'project graph refresh updates execution, capabilities, and workspace',
    () async {
      final initial = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/main.styio',
        title: 'before',
        notes: const <String>[],
      );
      final refreshed = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/main.styio',
        title: 'after',
        notes: const <String>[],
      );
      final workspace = WorkspaceController(projectSnapshot: initial);
      addTearDown(workspace.dispose);
      final executionRefreshes = <ProjectGraphSnapshot>[];
      final logs = <String>[];
      final controller = ProjectGraphController(
        adapter: _FakeProjectGraphAdapter(refreshed),
        workspaceController: workspace,
        refreshExecutionAdapter: (graph) async {
          executionRefreshes.add(graph);
        },
        executionCapability: () => _capability,
        runtimeEventCapability: () => _capability,
        supplementalCapabilities: const <AdapterCapabilitySnapshot>[],
        log: logs.add,
      );

      await controller.refresh(reason: 'test refresh');

      expect(executionRefreshes, <ProjectGraphSnapshot>[refreshed]);
      expect(workspace.activeProject, same(refreshed));
      expect(controller.capabilities, hasLength(1));
      expect(logs.single, contains('after (test refresh)'));
    },
  );

  test('unavailable project route suppresses optimistic same-kind routes', () {
    final project = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: '/workspace/demo/main.styio',
      title: 'unavailable',
      notes: const <String>[],
    );
    final workspace = WorkspaceController(projectSnapshot: project);
    addTearDown(workspace.dispose);
    final controller = ProjectGraphController(
      adapter: _FakeProjectGraphAdapter(
        project,
        capability: _cloudUnavailableCapability,
      ),
      workspaceController: workspace,
      refreshExecutionAdapter: (_) async {},
      executionCapability: () => _cloudAvailableCapability,
      runtimeEventCapability: () => _cloudAvailableCapability,
      supplementalCapabilities: const <AdapterCapabilitySnapshot>[
        _cloudAvailableCapability,
        _ffiAvailableCapability,
      ],
      log: (_) {},
    );

    final cloud = controller.capabilities.singleWhere(
      (capability) => capability.adapterKind == AdapterKind.cloud,
    );
    expect(cloud.projectGraph.level, AdapterCapabilityLevel.unavailable);
    expect(cloud.execution.level, AdapterCapabilityLevel.unavailable);
    expect(cloud.runtimeEvents.level, AdapterCapabilityLevel.unavailable);
    expect(
      controller.capabilities.any(
        (capability) => capability.adapterKind == AdapterKind.ffi,
      ),
      isTrue,
    );
  });
}

const _unavailableEndpoint = AdapterEndpointCapability(
  level: AdapterCapabilityLevel.unavailable,
  detail: 'not available in test',
);

const _capability = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cli,
  languageService: _unavailableEndpoint,
  projectGraph: _unavailableEndpoint,
  execution: _unavailableEndpoint,
  runtimeEvents: _unavailableEndpoint,
);

const _availableEndpoint = AdapterEndpointCapability(
  level: AdapterCapabilityLevel.available,
  detail: 'available in test',
);

const _cloudUnavailableCapability = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cloud,
  languageService: _unavailableEndpoint,
  projectGraph: _unavailableEndpoint,
  execution: _unavailableEndpoint,
  runtimeEvents: _unavailableEndpoint,
);

const _cloudAvailableCapability = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cloud,
  languageService: _availableEndpoint,
  projectGraph: _availableEndpoint,
  execution: _availableEndpoint,
  runtimeEvents: _availableEndpoint,
);

const _ffiAvailableCapability = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.ffi,
  languageService: _availableEndpoint,
  projectGraph: _availableEndpoint,
  execution: _availableEndpoint,
  runtimeEvents: _availableEndpoint,
);

final class _FakeProjectGraphAdapter implements ProjectGraphAdapter {
  const _FakeProjectGraphAdapter(this.graph, {this.capability = _capability});

  final ProjectGraphSnapshot graph;
  final AdapterCapabilitySnapshot capability;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => capability;

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async => graph;
}
