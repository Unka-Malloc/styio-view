import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/app_bootstrap.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  Future<ConfigurationStore> createConfigurationStore(Directory root) async {
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: root.path,
        homePath: root.path,
      ),
    );
    return ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: InMemoryCredentialDataStore(),
    );
  }

  ToolchainCatalog defaultLanguageServiceCatalog() {
    final catalog = ToolchainCatalog();
    catalog.register(
      const ToolchainDescriptor(
        id: 'default-styio-language-service',
        kind: ToolchainKind.languageService,
        displayName: 'Default Styio Language Service',
        executablePath: '/opt/styio/bin/styio',
      ),
      activate: true,
    );
    return catalog;
  }

  test(
    'app bootstrap seeds default Styio language service catalog when missing',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_app_bootstrap_default_toolchain_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );

      final catalog =
          await AppBootstrap.ensureDefaultLanguageServiceToolchainCatalog(
            toolchainStore: toolchainStore,
            workspaceId: 'workspace',
            targetId: 'local',
            defaultCatalogProvider: () async => defaultLanguageServiceCatalog(),
          );
      final persisted = await toolchainStore.loadCatalog(
        workspaceId: 'workspace',
        targetId: 'local',
      );

      expect(
        catalog.active(ToolchainKind.languageService)!.id,
        'default-styio-language-service',
      );
      expect(
        persisted.active(ToolchainKind.languageService)!.executablePath,
        '/opt/styio/bin/styio',
      );
    },
  );

  test(
    'app bootstrap keeps configured Styio language service over default',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_app_bootstrap_configured_toolchain_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final configuredCatalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'configured-styio-language-service',
            kind: ToolchainKind.languageService,
            displayName: 'Configured Styio Language Service',
            executablePath: '/workspace/toolchains/styio',
          ),
          activate: true,
        );
      var defaultCatalogRequested = false;

      await toolchainStore.saveCatalog(
        configuredCatalog,
        workspaceId: 'workspace',
        targetId: 'local',
      );
      final catalog =
          await AppBootstrap.ensureDefaultLanguageServiceToolchainCatalog(
            toolchainStore: toolchainStore,
            workspaceId: 'workspace',
            targetId: 'local',
            defaultCatalogProvider: () async {
              defaultCatalogRequested = true;
              return defaultLanguageServiceCatalog();
            },
          );

      expect(defaultCatalogRequested, isFalse);
      expect(
        catalog.list(kind: ToolchainKind.languageService).single.id,
        'configured-styio-language-service',
      );
      expect(
        catalog.active(ToolchainKind.languageService)!.executablePath,
        '/workspace/toolchains/styio',
      );
    },
  );
}
