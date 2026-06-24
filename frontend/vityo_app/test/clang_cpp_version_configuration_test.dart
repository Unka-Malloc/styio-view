import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('Clang C++ version preference round-trips through JSON', () {
    const preference = ClangCppVersionPreference(
      versionId: 'clang-18',
      cppStandard: CppLanguageStandard.cpp23,
    );

    final restored = ClangCppVersionPreference.fromJson(preference.toJson());

    expect(restored.versionId, 'clang-18');
    expect(restored.cppStandard, CppLanguageStandard.cpp23);
  });

  test(
    'toolchain store persists Clang C++ version preference by target',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_clang_cpp_preference_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await _createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );

      await toolchainStore.saveClangCppVersionPreference(
        const ClangCppVersionPreference(
          versionId: 'clang-18',
          cppStandard: CppLanguageStandard.cpp23,
        ),
        workspaceId: 'workspace-a',
        targetId: 'linux-x64',
      );

      final loaded = await toolchainStore.loadClangCppVersionPreference(
        workspaceId: 'workspace-a',
        targetId: 'linux-x64',
      );
      final otherTarget = await toolchainStore.loadClangCppVersionPreference(
        workspaceId: 'workspace-a',
        targetId: 'macos-arm64',
      );
      final deleted = await toolchainStore.deleteClangCppVersionPreference(
        workspaceId: 'workspace-a',
        targetId: 'linux-x64',
      );
      final afterDelete = await toolchainStore.loadClangCppVersionPreference(
        workspaceId: 'workspace-a',
        targetId: 'linux-x64',
      );

      expect(loaded, isNotNull);
      expect(loaded!.versionId, 'clang-18');
      expect(loaded.cppStandard, CppLanguageStandard.cpp23);
      expect(otherTarget, isNull);
      expect(deleted, isTrue);
      expect(afterDelete, isNull);
    },
  );
}

Future<ConfigurationStore> _createConfigurationStore(Directory root) async {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  final coordinator = FoundationResourceCoordinator(
    resourceManager: resourceManager,
    fileSystemManager: fileSystemManager,
  );
  return ConfigurationStore(
    dataStore: FoundationDataStore(
      resourceCoordinator: coordinator,
      fileSystemManager: fileSystemManager,
    ),
    credentialDataStore: InMemoryCredentialDataStore(),
  );
}
