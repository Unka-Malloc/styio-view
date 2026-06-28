import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent_context.dart';
import 'package:vityo_app/src/view_ide/agent/agent_session.dart';

void main() {
  group('PatchApplyPlan', () {
    test('canApply is true when permission is allowOnce', () {
      final preview = const FileChangePreview(
        previewId: 'prev-1',
        source: 'agent',
        changes: [
          FileChange(
            path: 'main.styio',
            editCount: 1,
            summary: 'Fix reference',
          ),
        ],
      );
      final plan = PatchApplyPlan(
        planId: 'plan-1',
        preview: preview,
        permissionRequest: const PermissionRequest(
          requestId: 'req-1',
          scope: PermissionRequestScope.workspaceWrite,
          reason: 'Modifying main.styio',
          createdAtIso8601: '2026-06-24T00:00:00Z',
        ).decide(PermissionDecision.allowOnce),
      );
      expect(plan.canApply, isTrue);
    });

    test('canApply is false when permission is denied', () {
      final preview = const FileChangePreview(
        previewId: 'prev-2',
        source: 'agent',
        changes: [
          FileChange(
            path: 'lib.styio',
            editCount: 2,
            summary: 'Refactor',
          ),
        ],
      );
      final plan = PatchApplyPlan(
        planId: 'plan-2',
        preview: preview,
        permissionRequest: const PermissionRequest(
          requestId: 'req-2',
          scope: PermissionRequestScope.workspaceWrite,
          reason: 'Refactoring lib.styio',
          createdAtIso8601: '2026-06-24T00:00:00Z',
        ).decide(PermissionDecision.deny),
      );
      expect(plan.canApply, isFalse);
    });

    test('canApply is true when permission is allowForSession', () {
      final preview = const FileChangePreview(
        previewId: 'prev-3',
        source: 'agent',
        changes: [
          FileChange(path: 'a.styio', editCount: 1, summary: 'Add import'),
        ],
      );
      final plan = PatchApplyPlan(
        planId: 'plan-3',
        preview: preview,
        permissionRequest: const PermissionRequest(
          requestId: 'req-3',
          scope: PermissionRequestScope.workspaceWrite,
          reason: 'Adding import',
          createdAtIso8601: '2026-06-24T00:00:00Z',
        ).decide(PermissionDecision.allowForSession),
      );
      expect(plan.canApply, isTrue);
    });

    test('serializes with canApply computed field', () {
      final preview = const FileChangePreview(
        previewId: 'prev-4',
        source: 'agent',
        changes: [
          FileChange(path: 'main.styio', editCount: 1, summary: 'Fix'),
        ],
      );
      final plan = PatchApplyPlan(
        planId: 'plan-4',
        preview: preview,
        permissionRequest: const PermissionRequest(
          requestId: 'req-4',
          scope: PermissionRequestScope.workspaceWrite,
          reason: 'Fixing main.styio',
          createdAtIso8601: '2026-06-24T00:00:00Z',
        ).decide(PermissionDecision.allowOnce),
      );
      final json = plan.toJson();
      expect(json['planId'], 'plan-4');
      expect(json['canApply'], isTrue);
    });
  });

  group('FileChange', () {
    test('tracks edit count and content hashes', () {
      const change = FileChange(
        path: 'main.styio',
        editCount: 3,
        summary: 'Renamed symbols',
        beforeContentHash: 'abc123',
        afterContentHash: 'def456',
      );
      expect(change.path, 'main.styio');
      expect(change.editCount, 3);
      expect(change.beforeContentHash, 'abc123');
      expect(change.afterContentHash, 'def456');
    });

    test('serializes with nullable hashes', () {
      const change = FileChange(
        path: 'lib.styio',
        editCount: 1,
        summary: 'Added function',
      );
      final json = change.toJson();
      expect(json['path'], 'lib.styio');
      expect(json['editCount'], 1);
      expect(json['beforeContentHash'], isNull);
      expect(json['afterContentHash'], isNull);
    });
  });

  group('FileChangePreview', () {
    test('computes total editCount across all changes', () {
      const preview = FileChangePreview(
        previewId: 'prev-5',
        source: 'agent',
        changes: [
          FileChange(path: 'a.styio', editCount: 2, summary: 'Edit a'),
          FileChange(path: 'b.styio', editCount: 3, summary: 'Edit b'),
          FileChange(path: 'c.styio', editCount: 1, summary: 'Edit c'),
        ],
      );
      expect(preview.editCount, 6);
      expect(preview.changedFileCount, 3);
    });

    test('empty changes result in zero counts', () {
      const preview = FileChangePreview(
        previewId: 'prev-6',
        source: 'agent',
        changes: [],
      );
      expect(preview.editCount, 0);
      expect(preview.changedFileCount, 0);
    });

    test('serializes affected symbols', () {
      const preview = FileChangePreview(
        previewId: 'prev-7',
        source: 'agent',
        changes: [
          FileChange(path: 'main.styio', editCount: 1, summary: 'Rename'),
        ],
        affectedSymbols: ['myFunction', 'MyClass'],
      );
      final json = preview.toJson();
      expect(json['previewId'], 'prev-7');
      expect(json['affectedSymbols'], ['myFunction', 'MyClass']);
      expect((json['changes'] as List).length, 1);
    });
  });

  group('AgentWorkspaceEditIntent', () {
    test('isRangeEdit is true when range is set', () {
      const intent = AgentWorkspaceEditIntent(
        intentId: 'edit-1',
        filePath: 'main.styio',
        editKind: 'replace',
        rangeStart: 10,
        rangeEnd: 20,
        newText: 'fixed',
      );
      expect(intent.isRangeEdit, isTrue);
    });

    test('isRangeEdit is false without range', () {
      const intent = AgentWorkspaceEditIntent(
        intentId: 'edit-2',
        filePath: 'new.styio',
        editKind: 'create',
        newText: 'pipeline main { }',
      );
      expect(intent.isRangeEdit, isFalse);
    });

    test('serializes to JSON', () {
      const intent = AgentWorkspaceEditIntent(
        intentId: 'edit-3',
        filePath: 'lib.styio',
        editKind: 'insert',
        rangeStart: 42,
        rangeEnd: 42,
        newText: 'import std.math;\n',
        summary: 'Add import',
        symbolName: 'math',
      );
      final json = intent.toJson();
      expect(json['intentId'], 'edit-3');
      expect(json['filePath'], 'lib.styio');
      expect(json['editKind'], 'insert');
      expect(json['rangeStart'], 42);
      expect(json['symbolName'], 'math');
    });
  });

  group('AgentWorkspaceEditApplication', () {
    test('hasFailures only when failedIntents non-empty', () {
      final success = const AgentWorkspaceEditApplication(
        applicationId: 'app-1',
        planId: 'plan-1',
        appliedAtIso8601: '2026-06-24T00:00:00Z',
        editCount: 1,
        affectedFilePaths: ['main.styio'],
        appliedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'edit-1', filePath: 'main.styio', editKind: 'replace'),
        ],
        failedIntents: [],
        errorMessages: [],
      );
      expect(success.hasFailures, isFalse);

      final failure = const AgentWorkspaceEditApplication(
        applicationId: 'app-2',
        planId: 'plan-2',
        appliedAtIso8601: '2026-06-24T00:00:00Z',
        editCount: 2,
        affectedFilePaths: ['main.styio'],
        appliedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'edit-1', filePath: 'main.styio', editKind: 'replace'),
        ],
        failedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'edit-2', filePath: 'lib.styio', editKind: 'insert',
            summary: 'Out of range'),
        ],
        errorMessages: ['edit-2: range out of bounds'],
        rollbackAvailable: true,
        rollbackTransactionId: 'txn-1',
      );
      expect(failure.hasFailures, isTrue);
    });

    test('serializes with applied and failed counts', () {
      final application = const AgentWorkspaceEditApplication(
        applicationId: 'app-3',
        planId: 'plan-3',
        appliedAtIso8601: '2026-06-24T00:00:00Z',
        editCount: 3,
        affectedFilePaths: ['a.styio', 'b.styio'],
        appliedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'e1', filePath: 'a.styio', editKind: 'replace'),
          AgentWorkspaceEditIntent(
            intentId: 'e2', filePath: 'b.styio', editKind: 'replace'),
        ],
        failedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'e3', filePath: 'c.styio', editKind: 'delete',
            summary: 'File not found'),
        ],
        errorMessages: ['e3: file not found'],
        rollbackAvailable: true,
        rollbackTransactionId: 'txn-1',
      );
      final json = application.toJson();
      expect(json['applicationId'], 'app-3');
      expect(json['appliedCount'], 2);
      expect(json['failedCount'], 1);
      expect(json['rollbackAvailable'], isTrue);
      expect(json['rollbackTransactionId'], 'txn-1');
    });

    test('rollbackAvailable can be false', () {
      final application = const AgentWorkspaceEditApplication(
        applicationId: 'app-4',
        planId: 'plan-4',
        appliedAtIso8601: '2026-06-24T00:00:00Z',
        editCount: 1,
        affectedFilePaths: ['main.styio'],
        appliedIntents: [
          AgentWorkspaceEditIntent(
            intentId: 'e1', filePath: 'main.styio', editKind: 'delete'),
        ],
        failedIntents: [],
        errorMessages: [],
        rollbackAvailable: false,
        rollbackTransactionId: '',
      );
      expect(application.rollbackAvailable, isFalse);
      expect(application.rollbackTransactionId, isEmpty);
    });
  });

  group('AgentActionPlan patch workflow', () {
    test('action plan with workspaceWrite requires permission', () {
      final plan = const AgentActionPlan(
        planId: 'plan-patch',
        description: 'Apply patch to fix references',
        workspaceEdits: [
          AgentWorkspaceEditIntent(
            intentId: 'e1',
            filePath: 'main.styio',
            editKind: 'replace',
            rangeStart: 10,
            rangeEnd: 20,
            newText: 'corrected',
            summary: 'Fix reference',
          ),
        ],
        requiresPermission: true,
        permissionScope: PermissionRequestScope.workspaceWrite,
        permissionReason: 'Modifying source file',
      );

      expect(plan.hasEdits, isTrue);
      expect(plan.requiresPermission, isTrue);
      expect(plan.permissionScope, PermissionRequestScope.workspaceWrite);

      final json = plan.toJson();
      expect(json['permissionScope'], 'workspaceWrite');
      expect((json['workspaceEdits'] as List).length, 1);
    });
  });
}
