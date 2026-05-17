import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';

void main() {
  test(
    'persists editor session state through Foundation DataStore owner',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_editor_session_datastore_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
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
      final store = EditorSessionDataStore.fromDataStore(dataStore: dataStore);

      await store.saveSession(
        workspaceId: 'demo workspace',
        snapshot: const EditorSessionSnapshot(
          activeDocumentId: 'main.styio',
          openDocumentIds: <String>['main.styio', 'lib/counts.styio'],
          dirtyDocumentIds: <String>['main.styio'],
          cursorOffsets: <String, int>{'main.styio': 12},
          selectionAnchors: <String, int>{'main.styio': 8},
        ),
      );

      final restored = await store.readSession(workspaceId: 'demo workspace');

      expect(restored?.activeDocumentId, 'main.styio');
      expect(restored?.openDocumentIds, <String>[
        'main.styio',
        'lib/counts.styio',
      ]);
      expect(restored?.dirtyDocumentIds, <String>['main.styio']);
      expect(restored?.cursorOffsets['main.styio'], 12);
      expect(restored?.selectionAnchors['main.styio'], 8);
    },
  );

  test('deletes editor session state without touching project files', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_editor_session_delete_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
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
    final store = EditorSessionDataStore.fromDataStore(dataStore: dataStore);

    await store.saveSession(
      workspaceId: 'demo',
      snapshot: const EditorSessionSnapshot(
        activeDocumentId: 'main.styio',
        openDocumentIds: <String>['main.styio'],
      ),
    );

    expect(await store.deleteSession(workspaceId: 'demo'), isTrue);
    expect(await store.readSession(workspaceId: 'demo'), isNull);
  });

  test('emits workspace-scoped editor session changes', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_editor_session_watch_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
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
    final store = EditorSessionDataStore.fromDataStore(dataStore: dataStore);
    final changes = <FoundationDataStoreChange>[];
    final subscription = store
        .watchSessions(workspaceId: 'demo')
        .listen(changes.add);
    addTearDown(subscription.cancel);

    await store.saveSession(
      workspaceId: 'demo',
      snapshot: const EditorSessionSnapshot(
        activeDocumentId: 'main.styio',
        openDocumentIds: <String>['main.styio'],
      ),
    );
    await store.deleteSession(workspaceId: 'demo');

    expect(
      changes.map((change) => change.kind),
      <FoundationDataStoreChangeKind>[
        FoundationDataStoreChangeKind.written,
        FoundationDataStoreChangeKind.deleted,
      ],
    );
    expect(changes.map((change) => change.workspaceId).toSet(), <String>{
      'demo',
    });
    expect(changes.map((change) => change.namespace).toSet(), <String>{
      'editor.session',
    });
  });

  test('captures editor controller state as a session snapshot', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\nvalue\n',
        revision: 1,
      ),
      languageService: const LocalStyioLanguageService(),
    );

    controller.selectRange(baseOffset: 2, extentOffset: 7);
    final snapshot = controller.toSessionSnapshot(
      openDocumentIds: <String>['main.styio', 'lib/counts.styio'],
      dirtyDocumentIds: <String>['main.styio'],
    );

    expect(snapshot.activeDocumentId, 'main.styio');
    expect(snapshot.openDocumentIds, <String>[
      'main.styio',
      'lib/counts.styio',
    ]);
    expect(snapshot.dirtyDocumentIds, <String>['main.styio']);
    expect(snapshot.cursorOffsets['main.styio'], 7);
    expect(snapshot.selectionAnchors['main.styio'], 2);
  });
}
