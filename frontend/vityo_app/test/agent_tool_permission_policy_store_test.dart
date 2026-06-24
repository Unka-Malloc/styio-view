import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test(
    'agent tool permission policy persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_tool_permission_policy_test_',
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
      final store = AgentToolPermissionPolicyStore.fromDataStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
      );
      const rule = AgentToolPermissionRule(
        ruleId: 'project-tool-permission-runIdeCommand',
        toolIdPattern: 'runIdeCommand',
        action: AgentToolPermissionAction.deny,
        priority: 500,
        reason: 'Project policy blocks IDE command tools.',
      );

      final saved = await store.upsertRule(workspaceId: 'demo', rule: rule);
      final restored = await store.readPolicy(workspaceId: 'demo');
      final removed = await store.removeRule(
        workspaceId: 'demo',
        ruleId: rule.ruleId,
      );

      expect(saved.workspaceId, 'demo');
      expect(saved.rules.single.action, AgentToolPermissionAction.deny);
      expect(saved.toJson()['ruleCount'], 1);
      expect(restored.rules.single.ruleId, rule.ruleId);
      expect(restored.rules.single.reason, contains('Project policy'));
      expect(removed.rules, isEmpty);
      expect((await store.readPolicy(workspaceId: 'demo')).rules, isEmpty);
    },
  );
}
