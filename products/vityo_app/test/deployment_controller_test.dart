import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/deployment_controller.dart';

void main() {
  test(
    'deployment controller records result, payload facts, and arguments',
    () async {
      final graph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/main.styio',
        title: 'demo',
        notes: const <String>[],
      );
      const result = DeploymentCommandResult(
        command: 'pafio publish',
        status: DeploymentCommandStatus.succeeded,
        statusMessage: 'published',
        stdout: '',
        stderr: '',
        payload: <String, dynamic>{
          'package': 'demo',
          'archive_path': '/workspace/demo/demo.tar.zst',
        },
      );
      final adapter = _RecordingDeploymentAdapter(result);
      final logs = <String>[];
      final controller = DeploymentController(
        adapter: adapter,
        projectGraph: () => graph,
        log: logs.add,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      final actual = await controller.publishToRegistry(
        registryRoot: '/registry',
        packageName: 'demo',
        outputPath: '/output',
      );

      expect(actual, same(result));
      expect(controller.lastCommand, same(result));
      expect(adapter.lastProjectGraph, same(graph));
      expect(adapter.lastRegistryRoot, '/registry');
      expect(adapter.lastPackageName, 'demo');
      expect(adapter.lastOutputPath, '/output');
      expect(logs, <String>[
        'pafio publish succeeded: published',
        'deploy package: demo',
        'deploy archive: /workspace/demo/demo.tar.zst',
      ]);
      expect(notifications, 1);
    },
  );
}

final class _RecordingDeploymentAdapter implements DeploymentAdapter {
  _RecordingDeploymentAdapter(this.result);

  final DeploymentCommandResult result;
  ProjectGraphSnapshot? lastProjectGraph;
  String? lastRegistryRoot;
  String? lastPackageName;
  String? lastOutputPath;

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    _record(projectGraph, packageName, outputPath);
    return result;
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    _record(projectGraph, packageName, outputPath);
    return result;
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    _record(projectGraph, packageName, outputPath);
    lastRegistryRoot = registryRoot;
    return result;
  }

  void _record(
    ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  ) {
    lastProjectGraph = projectGraph;
    lastPackageName = packageName;
    lastOutputPath = outputPath;
  }
}
