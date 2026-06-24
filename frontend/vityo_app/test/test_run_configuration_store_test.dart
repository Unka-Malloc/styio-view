import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';

void main() {
  test('test run configuration set selects and round trips configs', () {
    final set = const TestRunConfigurationSet(workspaceId: 'demo')
        .upsertConfiguration(
          const TestRunConfiguration(
            id: 'all',
            label: 'All tests',
            workspaceRoot: '/workspace/vityo',
            providerId: 'ctest',
          ),
        )
        .upsertConfiguration(
          const TestRunConfiguration(
            id: 'debug',
            label: 'Debug one test',
            workspaceRoot: '/workspace/vityo',
            providerId: 'ctest',
            targetId: 'unit',
            debug: true,
          ),
        )
        .selectConfiguration('debug');
    final restored = TestRunConfigurationSet.fromJson(set.toJson());

    expect(restored.configurations.map((config) => config.id), <String>[
      'all',
      'debug',
    ]);
    expect(restored.selectedConfiguration?.id, 'debug');
    expect(restored.selectedConfiguration?.toRunRequest().debug, isTrue);
    expect(restored.toJson()['selectedConfigurationReady'], isTrue);
  });

  test(
    'test run configuration store persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_test_run_configuration_store_test_',
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
      final store = TestRunConfigurationStore.fromDataStore(
        dataStore: dataStore,
      );

      await store.saveConfigurationSet(
        const TestRunConfigurationSet(
          workspaceId: 'demo',
          selectedConfigurationId: 'all',
          configurations: <TestRunConfiguration>[
            TestRunConfiguration(
              id: 'all',
              label: 'All tests',
              workspaceRoot: '/workspace/vityo',
              providerId: 'styio-test',
            ),
          ],
        ),
      );
      final restored = await store.readConfigurationSet(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.selectedConfiguration?.providerId, 'styio-test');
      expect(restored.selectedConfiguration?.ready, isTrue);
      expect(await store.deleteConfigurationSet(workspaceId: 'demo'), isTrue);
      expect(
        (await store.readConfigurationSet(workspaceId: 'demo')).configurations,
        isEmpty,
      );
    },
  );
}
