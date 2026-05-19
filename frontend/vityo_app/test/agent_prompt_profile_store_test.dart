import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_prompt_profile_store.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('agent prompt profile persists through Foundation DataStore', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_profile_store_test_',
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
    final store = AgentPromptProfileStore.fromDataStore(dataStore: dataStore);
    final profile = AgentPromptProfile.defaultForPlatform(
      PlatformTarget.macos,
    );

    await store.saveProfile(workspaceId: 'demo', profile: profile);
    final restored = await store.readProfile(workspaceId: 'demo');

    expect(restored, isNotNull);
    expect(restored!.profileId, profile.profileId);
    expect(restored.endpoint.route, AgentProviderRoute.desktopLocalBridge);
    expect(restored.contextChannels, profile.contextChannels);

    final deleted = await store.deleteProfile(workspaceId: 'demo');
    expect(deleted, isTrue);
    expect(await store.readProfile(workspaceId: 'demo'), isNull);
  });
}
