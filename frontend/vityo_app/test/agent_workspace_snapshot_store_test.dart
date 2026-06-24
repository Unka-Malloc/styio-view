import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test(
    'agent workspace snapshot persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_workspace_snapshot_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final store = AgentWorkspaceSnapshotStore.fromDataStore(
        dataStore: _dataStore(tempRoot),
      );
      final snapshot = AgentWorkspaceChangeSnapshot(
        snapshotId: 'snapshot-1',
        patchId: 'patch-1',
        activeDocumentId: 'main.styio',
        capturedAt: DateTime.utc(2026, 5, 22),
        documents: const <AgentWorkspaceSnapshotDocument>[
          AgentWorkspaceSnapshotDocument(
            documentId: 'main.styio',
            existed: true,
            text: 'value = 1\n',
            revision: 7,
          ),
        ],
      );

      await store.saveSnapshot(workspaceId: 'demo', snapshot: snapshot);
      final restored = await store.readSnapshot(workspaceId: 'demo');
      final deleted = await store.deleteSnapshot(workspaceId: 'demo');

      expect(restored?.snapshotId, 'snapshot-1');
      expect(restored?.documentFor('main.styio')?.text, 'value = 1\n');
      expect(restored?.documentFor('main.styio')?.revision, 7);
      expect(restored?.toJson()['documents'], isA<List<Object?>>());
      expect(deleted, isTrue);
      expect(await store.readSnapshot(workspaceId: 'demo'), isNull);
    },
  );
}

FoundationDataStore _dataStore(Directory root) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}
