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

  test('testing session controller persists failed retry history', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_testing_failed_retry_history_test_',
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
    final historyStore = TestRunHistoryStore.fromDataStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
    );
    final controller = TestingSessionController(
      testRunHistoryStore: historyStore,
      testRunHistoryWorkspaceId: 'demo',
      clock: () => DateTime.utc(2026, 5, 20, 12),
      runProvider: const StaticTestRunProvider(
        providerId: 'styio-test',
        result: TestRunResult(
          providerId: 'styio-test',
          runner: 'fixture',
          status: TestRunStatus.failed,
          message: 'Rerun still failed.',
          totalCount: 1,
          failedCount: 1,
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.recordRunResult(
      const TestRunResult(
        providerId: 'styio-test',
        runner: 'fixture',
        status: TestRunStatus.failed,
        message: 'Initial failure.',
        totalCount: 1,
        failedCount: 1,
        cases: <TestCaseResult>[
          TestCaseResult(name: 'syntax fixture', status: TestRunStatus.failed),
        ],
      ),
    );

    final rerun = await controller.rerunFailed(
      workspaceRoot: '/workspace/vityo',
      debug: true,
    );
    final retryHistory = await historyStore.readFailedRetryHistory(
      workspaceId: 'demo',
    );

    expect(rerun.status, TestRunStatus.failed);
    expect(controller.failedRetryHistory, hasLength(1));
    expect(retryHistory.records, hasLength(1));
    expect(retryHistory.records.single.debug, isTrue);
    expect(retryHistory.records.single.filter, 'syntax fixture');
    expect(retryHistory.records.single.status, TestRunStatus.failed);
    expect(retryHistory.toJson()['retryCount'], 1);
  });
}
