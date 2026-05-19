import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('runtime task history appends latest task first and caps entries', () {
    final first = _task('test.one', RuntimeTaskStatus.succeeded);
    final second = _task('test.two', RuntimeTaskStatus.failed);

    final history = const RuntimeTaskHistorySnapshot(
      workspaceId: 'demo',
    ).append(first).append(second, maxEntries: 1);

    expect(history.tasks, hasLength(1));
    expect(history.tasks.single.definition.id, 'test.two');
    expect(history.toJson()['taskCount'], 1);
  });

  test(
    'runtime task history store persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_runtime_task_history_test_',
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
      final store = RuntimeTaskHistoryStore.fromDataStore(dataStore: dataStore);

      await store.appendTask(
        workspaceId: 'demo',
        task: _task('terminal.sh', RuntimeTaskStatus.succeeded),
      );
      await store.appendTask(
        workspaceId: 'demo',
        task: _task('test.styio', RuntimeTaskStatus.failed),
      );
      final restored = await store.readHistory(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.tasks.map((task) => task.definition.id), <String>[
        'test.styio',
        'terminal.sh',
      ]);
      expect(restored.tasks.first.status, RuntimeTaskStatus.failed);
      expect(restored.updatedAt, isNotNull);
      expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
      expect((await store.readHistory(workspaceId: 'demo')).tasks, isEmpty);
    },
  );
}

RuntimeTaskSnapshot _task(String id, RuntimeTaskStatus status) {
  return RuntimeTaskSnapshot(
    definition: RuntimeTaskDefinition(
      id: id,
      label: id,
      kind: RuntimeTaskKind.test,
      command: 'runner',
    ),
    status: status,
    statusMessage: status.wireValue,
    finishedAt: DateTime.utc(2026, 5, 20),
  );
}
