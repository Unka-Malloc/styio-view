import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';

void main() {
  test(
    'testing session controller persists completed runtime task history',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_testing_runtime_task_history_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final historyStore = RuntimeTaskHistoryStore.fromDataStore(
        dataStore: dataStore,
      );
      final controller = TestingSessionController(
        runtimeTaskLifecycleController: RuntimeTaskLifecycleController(
          clock: () => DateTime.utc(2026, 5, 20),
        ),
        runtimeTaskHistoryStore: historyStore,
        runtimeTaskHistoryWorkspaceId: 'demo',
        runProvider: const StaticTestRunProvider(
          providerId: 'styio-test',
          result: TestRunResult(
            providerId: 'styio-test',
            runner: 'fixture',
            status: TestRunStatus.passed,
            message: 'Styio tests passed.',
            totalCount: 1,
            passedCount: 1,
          ),
        ),
      );
      addTearDown(controller.dispose);

      final result = await controller.run(
        const TestRunRequest(workspaceRoot: '/workspace/vityo'),
      );
      final history = await historyStore.readHistory(workspaceId: 'demo');

      expect(result.status, TestRunStatus.passed);
      expect(history.tasks, hasLength(1));
      expect(history.tasks.single.definition.id, 'test.styio-test.1');
      expect(history.tasks.single.status, RuntimeTaskStatus.succeeded);
      expect(
        (result.metadata['runtimeTask']! as Map<String, Object?>)['status'],
        'succeeded',
      );
    },
  );
}
