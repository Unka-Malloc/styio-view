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

  ToolchainCatalog defaultNativeCompilerCatalog() {
    final catalog = ToolchainCatalog();
    catalog.register(
      const ToolchainDescriptor(
        id: 'native-clang-cpp-compiler',
        kind: ToolchainKind.compiler,
        displayName: 'Clang C/C++ Compiler',
        executablePath: '/usr/bin/clang++',
        metadata: <String, Object?>{
          'compilerFamily': 'clang',
          'cCompilerPath': '/usr/bin/clang',
          'cxxCompilerPath': '/usr/bin/clang++',
          'languages': <String>['c', 'cpp'],
          'defaultForNativeCode': true,
        },
      ),
      activate: true,
    );
    catalog.register(
      const ToolchainDescriptor(
        id: 'native-cmake-build-tool',
        kind: ToolchainKind.buildTool,
        displayName: 'CMake Build System',
        executablePath: '/usr/bin/cmake',
        metadata: <String, Object?>{
          'toolFamily': 'cmake',
          'languages': <String>['c', 'cpp'],
        },
      ),
    );
    catalog.register(
      const ToolchainDescriptor(
        id: 'native-clangd-language-service',
        kind: ToolchainKind.languageService,
        displayName: 'clangd C/C++ Language Server',
        executablePath: '/usr/bin/clangd',
        metadata: <String, Object?>{
          'toolFamily': 'clangd',
          'languages': <String>['c', 'cpp'],
          'consumesCompileCommands': true,
        },
      ),
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

  test(
    'app bootstrap merges default native C++ toolchains with Styio language service catalog',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_app_bootstrap_native_toolchain_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );

      await AppBootstrap.ensureDefaultLanguageServiceToolchainCatalog(
        toolchainStore: toolchainStore,
        workspaceId: 'workspace',
        targetId: 'local',
        defaultCatalogProvider: () async => defaultLanguageServiceCatalog(),
      );
      final catalog =
          await AppBootstrap.ensureDefaultNativeCompilerToolchainCatalog(
            toolchainStore: toolchainStore,
            workspaceId: 'workspace',
            targetId: 'local',
            defaultCatalogProvider: () async => defaultNativeCompilerCatalog(),
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
        persisted.active(ToolchainKind.compiler)!.id,
        'native-clang-cpp-compiler',
      );
      expect(
        persisted.lookup('native-cmake-build-tool')!.metadata['toolFamily'],
        'cmake',
      );
      expect(
        persisted
            .lookup('native-clangd-language-service')!
            .metadata['consumesCompileCommands'],
        isTrue,
      );
    },
  );

  test(
    'app bootstrap does not replace configured native compiler with default clang',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_app_bootstrap_keep_native_toolchain_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final configuredCatalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'configured-native-compiler',
            kind: ToolchainKind.compiler,
            displayName: 'Configured Native Compiler',
            executablePath: '/workspace/bin/c++',
            metadata: <String, Object?>{'compilerFamily': 'configured'},
          ),
          activate: true,
        );

      await toolchainStore.saveCatalog(
        configuredCatalog,
        workspaceId: 'workspace',
        targetId: 'local',
      );
      final catalog =
          await AppBootstrap.ensureDefaultNativeCompilerToolchainCatalog(
            toolchainStore: toolchainStore,
            workspaceId: 'workspace',
            targetId: 'local',
            defaultCatalogProvider: () async => defaultNativeCompilerCatalog(),
          );

      expect(
        catalog.active(ToolchainKind.compiler)!.id,
        'configured-native-compiler',
      );
      expect(catalog.lookup('native-clang-cpp-compiler'), isNotNull);
      expect(
        catalog.lookup('native-clang-cpp-compiler')!.metadata['compilerFamily'],
        'clang',
      );
    },
  );
}
