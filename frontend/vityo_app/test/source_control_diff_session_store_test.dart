import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('source control diff session records window and hunk selection', () {
    const diff = SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: 'src/main.styio',
      unifiedDiff: '''
diff --git a/src/main.styio b/src/main.styio
@@ -1 +1 @@
-old
+new
@@ -8 +8 @@
-left
+right
''',
    );
    final binding = const SourceControlDiffWindowBinding(
      snapshot: diff,
      startLine: 2,
      lineLimit: 4,
    );
    final selection = SourceControlHunkSelectionState.fromDiff(
      snapshot: diff,
      selectedHunkIndexes: const <int>[1, 1, -1, 0],
    );

    final session = SourceControlDiffSessionState.fromDiffWindow(
      workspaceId: 'demo',
      binding: binding,
      hunkSelectionState: selection,
    );
    final restored = SourceControlDiffSessionState.fromJson(session.toJson());

    expect(session.workspaceId, 'demo');
    expect(session.providerKind, SourceControlProviderKind.git);
    expect(session.path, 'src/main.styio');
    expect(session.windowStartLine, 2);
    expect(session.windowLineLimit, 4);
    expect(session.selectedHunkIndexes, <int>[0, 1]);
    expect(session.hasHunkSelection, isTrue);
    expect(restored.selectedHunkIndexes, <int>[0, 1]);
    expect(restored.toJson()['selectedHunkCount'], 2);
  });

  test(
    'source control diff session persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_source_control_diff_session_test_',
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
      final store = SourceControlDiffSessionStore.fromDataStore(
        dataStore: dataStore,
      );

      await store.saveSession(
        const SourceControlDiffSessionState(
          workspaceId: 'demo',
          providerKind: SourceControlProviderKind.git,
          path: 'src/main.styio',
          windowStartLine: 20,
          windowLineLimit: 60,
          selectedHunkIndexes: <int>[2, 0],
        ),
      );
      final restored = await store.readSession(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.path, 'src/main.styio');
      expect(restored.windowStartLine, 20);
      expect(restored.windowLineLimit, 60);
      expect(restored.selectedHunkIndexes, <int>[0, 2]);
      expect(restored.updatedAt, isNotNull);
      expect(await store.deleteSession(workspaceId: 'demo'), isTrue);
      expect((await store.readSession(workspaceId: 'demo')).hasPath, isFalse);
    },
  );
}
