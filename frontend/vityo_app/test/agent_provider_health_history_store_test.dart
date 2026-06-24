import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('agent provider health history keeps newest reports first', () {
    final history = const AgentProviderHealthHistory(workspaceId: 'demo')
        .append(_health('primary', AgentProviderServiceHealthStatus.ready))
        .append(_health('fallback', AgentProviderServiceHealthStatus.degraded));
    final restored = AgentProviderHealthHistory.fromJson(history.toJson());

    expect(restored.reports.map((report) => report.profileId), <String>[
      'fallback',
      'primary',
    ]);
    expect(restored.latestFor('primary')?.ready, isTrue);
    expect(restored.latestFor('fallback')?.fallbackActive, isTrue);
  });

  test(
    'agent provider health history persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_provider_health_history_test_',
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
      final store = AgentProviderHealthHistoryStore.fromDataStore(
        dataStore: dataStore,
      );

      await store.appendReport(
        workspaceId: 'demo',
        report: _health('primary', AgentProviderServiceHealthStatus.blocked),
      );
      await store.appendReport(
        workspaceId: 'demo',
        report: _health('fallback', AgentProviderServiceHealthStatus.ready),
      );
      final restored = await store.readHistory(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.reports, hasLength(2));
      expect(restored.latestFor('fallback')?.executable, isTrue);
      expect(restored.latestFor('primary')?.message, contains('primary'));
      expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
      expect((await store.readHistory(workspaceId: 'demo')).reports, isEmpty);
    },
  );
}

AgentProviderServiceHealthReport _health(
  String profileId,
  AgentProviderServiceHealthStatus status,
) {
  return AgentProviderServiceHealthReport(
    profileId: profileId,
    status: status,
    endpointCount: 1,
    blockedEndpointCount: status == AgentProviderServiceHealthStatus.blocked
        ? 1
        : 0,
    missingCredentialCount: status == AgentProviderServiceHealthStatus.blocked
        ? 1
        : 0,
    unreachableEndpointCount: 0,
    fallbackActive: status == AgentProviderServiceHealthStatus.degraded,
    message: 'Health for $profileId is ${status.wireValue}.',
  );
}
