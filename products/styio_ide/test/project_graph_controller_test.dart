import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/project_graph_controller.dart';
import 'package:styio_ide/src/ide/workspace/workspace.dart';

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

final class _FakeProjectGraphAdapter implements ProjectGraphAdapter {
  const _FakeProjectGraphAdapter(this.graph);

  final ProjectGraphSnapshot graph;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capability;

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async => graph;
}
