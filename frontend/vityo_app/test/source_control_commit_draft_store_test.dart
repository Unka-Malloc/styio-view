import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('source control commit draft produces commit action plan', () {
    const emptyDraft = SourceControlCommitDraft(workspaceId: 'demo');
    final draft =
        const SourceControlCommitDraft(
          workspaceId: 'demo',
          message: ' checkpoint ',
          signOff: true,
        ).copyWith(
          selectedPaths: const <String>[
            ' lib/main.styio ',
            'lib/main.styio',
            '',
          ],
        );

    final emptyPlan = emptyDraft.toCommitActionPlan();
    final plan = draft.toCommitActionPlan();

    expect(emptyPlan.canRun, isFalse);
    expect(emptyPlan.blockedReason, contains('commit message'));
    expect(draft.selectedPaths, <String>['lib/main.styio']);
    expect(draft.hasMessage, isTrue);
    expect(plan.canRun, isTrue);
    expect(plan.requiresConfirmation, isTrue);
    expect(plan.risk, SourceControlActionRisk.createsRevision);
    expect(SourceControlCommitDraft.fromJson(draft.toJson()).signOff, isTrue);
  });

  test('source control commit dialog state validates editable draft', () {
    final closed = SourceControlCommitDialogState.fromDraft(
      draft: const SourceControlCommitDraft(workspaceId: 'demo'),
    );
    final blocked = SourceControlCommitDialogState.fromDraft(
      open: true,
      draft: const SourceControlCommitDraft(workspaceId: 'demo'),
    );
    final ready = blocked.edit(
      message: 'Commit source control dialog',
      selectedPaths: const <String>['src/main.styio'],
      signOff: true,
    );

    expect(closed.open, isFalse);
    expect(closed.status, SourceControlCommitDialogStatus.closed);
    expect(blocked.open, isTrue);
    expect(blocked.canSubmit, isFalse);
    expect(blocked.validationMessage, contains('commit message'));
    expect(ready.status, SourceControlCommitDialogStatus.ready);
    expect(ready.canSubmit, isTrue);
    expect(ready.draft.selectedPaths, <String>['src/main.styio']);
    expect(ready.toJson()['status'], 'ready');
    expect(ready.toJson()['plan'], isA<Map<String, Object?>>());
  });

  test(
    'source control commit draft persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_source_control_commit_draft_test_',
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
      final store = SourceControlCommitDraftStore.fromDataStore(
        dataStore: dataStore,
      );

      await store.saveDraft(
        const SourceControlCommitDraft(
          workspaceId: 'demo',
          message: 'Add source control draft',
          selectedPaths: <String>['lib/main.styio'],
          amend: true,
        ),
      );
      final restored = await store.readDraft(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.message, 'Add source control draft');
      expect(restored.selectedPaths, <String>['lib/main.styio']);
      expect(restored.amend, isTrue);
      expect(restored.toJson()['commitPlan'], isA<Map<String, Object?>>());
      expect(await store.deleteDraft(workspaceId: 'demo'), isTrue);
      expect((await store.readDraft(workspaceId: 'demo')).hasMessage, isFalse);
    },
  );
}
