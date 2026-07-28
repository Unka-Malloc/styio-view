import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/dependency_source_controller.dart';

void main() {
  test(
    'vendor success records facts and refreshes the project graph',
    () async {
      final graph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/main.styio',
        title: 'demo',
        notes: const <String>[],
      );
      const result = DependencySourceCommandResult(
        command: 'pafio vendor',
        status: DependencySourceCommandStatus.succeeded,
        statusMessage: 'vendored',
        stdout: '',
        stderr: '',
        payload: <String, dynamic>{
          'packages': 3,
          'vendor_root': '/workspace/demo/vendor',
          'metadata_path': '/workspace/demo/vendor/metadata.json',
        },
      );
      final adapter = _RecordingDependencySourceAdapter(result);
      final logs = <String>[];
      final refreshReasons = <String?>[];
      final controller = DependencySourceController(
        adapter: adapter,
        projectGraph: () => graph,
        refreshProjectGraph: ({String? reason}) async {
          refreshReasons.add(reason);
        },
        log: logs.add,
      );
      addTearDown(controller.dispose);

      final actual = await controller.vendorDependencies(
        outputPath: '/vendor-output',
        locked: true,
        offline: true,
      );

      expect(actual, same(result));
      expect(controller.lastCommand, same(result));
      expect(adapter.lastProjectGraph, same(graph));
      expect(adapter.lastOutputPath, '/vendor-output');
      expect(adapter.lastLocked, isTrue);
      expect(adapter.lastOffline, isTrue);
      expect(refreshReasons, <String?>['vendor completed']);
      expect(logs, <String>[
        'pafio vendor succeeded: vendored',
        'pafio vendor packages: 3',
        'vendor root: /workspace/demo/vendor',
        'vendor metadata: /workspace/demo/vendor/metadata.json',
      ]);
    },
  );
}

final class _RecordingDependencySourceAdapter
    implements DependencySourceAdapter {
  _RecordingDependencySourceAdapter(this.result);

  final DependencySourceCommandResult result;
  ProjectGraphSnapshot? lastProjectGraph;
  String? lastOutputPath;
  bool? lastLocked;
  bool? lastOffline;

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    _record(projectGraph, null, locked, offline);
    return result;
  }

  @override
  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    _record(projectGraph, outputPath, locked, offline);
    return result;
  }

  void _record(
    ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked,
    bool offline,
  ) {
    lastProjectGraph = projectGraph;
    lastOutputPath = outputPath;
    lastLocked = locked;
    lastOffline = offline;
  }
}
