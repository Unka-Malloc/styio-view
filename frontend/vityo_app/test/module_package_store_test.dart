import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/module_host/module_capability_matrix.dart';
import 'package:vityo_app/src/module_host/module_definition.dart';
import 'package:vityo_app/src/module_host/module_lifecycle.dart';
import 'package:vityo_app/src/module_host/module_manifest.dart';
import 'package:vityo_app/src/module_host/module_package_store.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/file_system/file_system_manager_io.dart'
    as file_system_io;

void main() {
  test('module package store installs verified optional packages', () async {
    final fs = await file_system_io.createPlatformFileSystemManager();
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_module_package_install_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final module = _module(platformTarget: PlatformTarget.windows);
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.windows,
      definitions: <ModuleDefinition>[module],
    );
    final store = ModulePackageStore(
      fileSystemManager: fs,
      rootPath: tempRoot.path,
    );

    final result = await store.installPackage(
      registry: registry,
      artifact: _artifact(module, 'v1 package'),
    );

    expect(result.status, ModulePackageOperationStatus.installed);
    expect(result.succeeded, isTrue);
    expect(
      result.activePackagePath,
      store.activePackagePath(module.manifest.moduleId),
    );
    expect(
      await fs.readBytes(
        fs.joinPath(<String>[result.activePackagePath!, 'package.bin']),
      ),
      utf8.encode('v1 package'),
    );
    final packageJson =
        jsonDecode(
              await fs.readText(
                fs.joinPath(<String>[
                  result.activePackagePath!,
                  'package.json',
                ]),
              ),
            )
            as Map<String, Object?>;
    expect(packageJson['moduleId'], module.manifest.moduleId);
    expect(packageJson['version'], '1.0.0');
    expect(
      result.registry!.findById(module.manifest.moduleId)!.manifest.version,
      '1.0.0',
    );
  });

  test(
    'module package store downloads and installs verified packages',
    () async {
      final fs = await file_system_io.createPlatformFileSystemManager();
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_module_package_download_install_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final module = _module(platformTarget: PlatformTarget.windows);
      final registry = ModuleRegistry(
        platformTarget: PlatformTarget.windows,
        definitions: <ModuleDefinition>[module],
      );
      final store = ModulePackageStore(
        fileSystemManager: fs,
        rootPath: tempRoot.path,
      );
      final downloader = FileSystemModulePackageDownloader(
        fileSystemManager: fs,
      );
      final sourceBytes = utf8.encode('downloaded package');
      final sourcePath = fs.joinPath(<String>[
        tempRoot.path,
        'downloads',
        'optional.agent-1.0.0.pkg',
      ]);
      await fs.writeBytes(sourcePath, sourceBytes);

      final result = await store.downloadAndInstallPackage(
        registry: registry,
        downloader: downloader,
        request: ModulePackageDownloadRequest(
          definition: module,
          sourcePath: sourcePath,
          expectedSha256: 'sha256:${sha256.convert(sourceBytes)}',
        ),
      );

      expect(result.status, ModulePackageOperationStatus.installed);
      expect(result.succeeded, isTrue);
      expect(
        await fs.readBytes(
          fs.joinPath(<String>[result.activePackagePath!, 'package.bin']),
        ),
        sourceBytes,
      );
    },
  );

  test(
    'staged package update keeps running package until restart activation',
    () async {
      final fs = await file_system_io.createPlatformFileSystemManager();
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_module_package_stage_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final running = _module(
        platformTarget: PlatformTarget.linux,
        moduleId: 'runtime.surface',
        version: '1.0.0',
        slot: ModuleSlot.runtimeSurface,
      );
      final staged = _module(
        platformTarget: PlatformTarget.linux,
        moduleId: 'runtime.surface',
        version: '1.1.0',
        slot: ModuleSlot.runtimeSurface,
      );
      final registry = ModuleRegistry(
        platformTarget: PlatformTarget.linux,
        definitions: <ModuleDefinition>[running],
      );
      final store = ModulePackageStore(
        fileSystemManager: fs,
        rootPath: tempRoot.path,
      );

      await store.installPackage(
        registry: registry,
        artifact: _artifact(running, 'v1 package'),
      );
      final stagedBytes = utf8.encode('v2 package');
      final stagedSourcePath = fs.joinPath(<String>[
        tempRoot.path,
        'downloads',
        'runtime.surface-1.1.0.pkg',
      ]);
      await fs.writeBytes(stagedSourcePath, stagedBytes);
      final stagedResult = await store.downloadAndStageUpdatePackage(
        runningRegistry: registry,
        downloader: FileSystemModulePackageDownloader(fileSystemManager: fs),
        request: ModulePackageDownloadRequest(
          definition: staged,
          sourcePath: stagedSourcePath,
          expectedSha256: 'sha256:${sha256.convert(stagedBytes)}',
        ),
      );

      expect(stagedResult.status, ModulePackageOperationStatus.staged);
      expect(stagedResult.stagedUpdateResolution!.requiresRestart, isTrue);
      expect(
        stagedResult.registry!.findById('runtime.surface')!.manifest.version,
        '1.0.0',
      );
      expect(
        await fs.readBytes(
          fs.joinPath(<String>[
            store.activePackagePath('runtime.surface'),
            'package.bin',
          ]),
        ),
        utf8.encode('v1 package'),
      );

      final rolledBack = await store.rollbackStagedPackage(
        runningRegistry: registry,
        moduleId: 'runtime.surface',
        version: '1.1.0',
      );

      expect(rolledBack.status, ModulePackageOperationStatus.rolledBack);
      expect(
        await fs.exists(store.stagedPackagePath('runtime.surface', '1.1.0')),
        isFalse,
      );
      expect(
        await fs.readBytes(
          fs.joinPath(<String>[
            store.activePackagePath('runtime.surface'),
            'package.bin',
          ]),
        ),
        utf8.encode('v1 package'),
      );

      await store.stageUpdatePackage(
        runningRegistry: registry,
        artifact: _artifact(staged, 'v2 package'),
      );

      final activated = await store.activateStagedPackage(
        runningRegistry: registry,
        stagedDefinition: staged,
      );

      expect(activated.status, ModulePackageOperationStatus.activated);
      expect(
        activated.registry!.findById('runtime.surface')!.manifest.version,
        '1.1.0',
      );
      expect(
        await fs.exists(store.stagedPackagePath('runtime.surface', '1.1.0')),
        isFalse,
      );
      expect(
        await fs.readBytes(
          fs.joinPath(<String>[
            store.activePackagePath('runtime.surface'),
            'package.bin',
          ]),
        ),
        utf8.encode('v2 package'),
      );
    },
  );

  test('desktop uninstall keeps or clears user data by policy', () async {
    final fs = await file_system_io.createPlatformFileSystemManager();
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_module_package_uninstall_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final module = _module(platformTarget: PlatformTarget.windows);
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.windows,
      definitions: <ModuleDefinition>[module],
    );
    final store = ModulePackageStore(
      fileSystemManager: fs,
      rootPath: tempRoot.path,
    );

    await store.installPackage(
      registry: registry,
      artifact: _artifact(module, 'desktop package'),
    );
    await fs.writeText(
      fs.joinPath(<String>[
        store.dataPath(module.manifest.moduleId),
        'prefs.json',
      ]),
      '{}',
    );
    final keepData = await store.uninstallPackage(
      registry: registry,
      moduleId: module.manifest.moduleId,
      workspaceReferences: <ModuleWorkspaceReference>[
        ModuleWorkspaceReference(
          referenceId: 'agent-panel',
          moduleId: module.manifest.moduleId,
        ),
      ],
    );

    expect(keepData.status, ModulePackageOperationStatus.uninstalled);
    expect(keepData.lifecyclePlan!.reclaimData, isFalse);
    expect(
      await fs.exists(store.activePackagePath(module.manifest.moduleId)),
      isFalse,
    );
    expect(await fs.exists(store.cachePath(module.manifest.moduleId)), isFalse);
    expect(await fs.exists(store.dataPath(module.manifest.moduleId)), isTrue);
    expect(keepData.registry!.findById(module.manifest.moduleId), isNull);
    expect(
      keepData
          .uninstallReconciliation!
          .removedWorkspaceReferences
          .single
          .referenceId,
      'agent-panel',
    );

    await store.installPackage(
      registry: registry,
      artifact: _artifact(module, 'desktop package reinstall'),
    );
    final clearData = await store.uninstallPackage(
      registry: registry,
      moduleId: module.manifest.moduleId,
      dataPolicy: ModuleUninstallDataPolicy.clearData,
    );

    expect(clearData.status, ModulePackageOperationStatus.uninstalled);
    expect(clearData.lifecyclePlan!.reclaimData, isTrue);
    expect(await fs.exists(store.dataPath(module.manifest.moduleId)), isFalse);
  });

  test(
    'locked package cleanup retries before reclaiming active package',
    () async {
      final base = await file_system_io.createPlatformFileSystemManager();
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_module_package_retry_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final module = _module(platformTarget: PlatformTarget.windows);
      final registry = ModuleRegistry(
        platformTarget: PlatformTarget.windows,
        definitions: <ModuleDefinition>[module],
      );
      final baseStore = ModulePackageStore(
        fileSystemManager: base,
        rootPath: tempRoot.path,
      );
      await baseStore.installPackage(
        registry: registry,
        artifact: _artifact(module, 'retry package'),
      );

      final retryingFs = _TransientDeleteFileSystemManager(
        facts: base.facts,
        failuresBeforeSuccessByPath: <String, int>{
          baseStore.activePackagePath(module.manifest.moduleId): 1,
        },
      );
      final retryingStore = ModulePackageStore(
        fileSystemManager: retryingFs,
        rootPath: tempRoot.path,
        cleanupRetryCount: 2,
      );

      final result = await retryingStore.uninstallPackage(
        registry: registry,
        moduleId: module.manifest.moduleId,
      );

      final activeCleanup = result.cleanupReports.firstWhere(
        (report) =>
            report.path ==
            retryingStore.activePackagePath(module.manifest.moduleId),
      );
      expect(result.status, ModulePackageOperationStatus.uninstalled);
      expect(activeCleanup.attempts, 2);
      expect(activeCleanup.blocked, isFalse);
    },
  );

  test(
    'locked package cleanup reports blocked after retry exhaustion',
    () async {
      final base = await file_system_io.createPlatformFileSystemManager();
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_module_package_blocked_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final module = _module(platformTarget: PlatformTarget.windows);
      final registry = ModuleRegistry(
        platformTarget: PlatformTarget.windows,
        definitions: <ModuleDefinition>[module],
      );
      final baseStore = ModulePackageStore(
        fileSystemManager: base,
        rootPath: tempRoot.path,
      );
      await baseStore.installPackage(
        registry: registry,
        artifact: _artifact(module, 'blocked package'),
      );

      final lockedFs = _TransientDeleteFileSystemManager(
        facts: base.facts,
        failuresBeforeSuccessByPath: <String, int>{
          baseStore.activePackagePath(module.manifest.moduleId): 3,
        },
      );
      final lockedStore = ModulePackageStore(
        fileSystemManager: lockedFs,
        rootPath: tempRoot.path,
        cleanupRetryCount: 1,
      );

      final result = await lockedStore.uninstallPackage(
        registry: registry,
        moduleId: module.manifest.moduleId,
      );

      expect(result.status, ModulePackageOperationStatus.blocked);
      expect(result.succeeded, isFalse);
      expect(result.cleanupReports.any((report) => report.blocked), isTrue);
      expect(
        await base.exists(
          baseStore.activePackagePath(module.manifest.moduleId),
        ),
        isTrue,
      );
    },
  );
}

ModulePackageArtifact _artifact(ModuleDefinition definition, String payload) {
  final bytes = utf8.encode(payload);
  return ModulePackageArtifact(
    definition: definition,
    bytes: bytes,
    expectedSha256: 'sha256:${sha256.convert(bytes)}',
  );
}

ModuleDefinition _module({
  required PlatformTarget platformTarget,
  String moduleId = 'optional.agent',
  String version = '1.0.0',
  ModuleSlot slot = ModuleSlot.agentSurface,
}) {
  return ModuleDefinition(
    manifest: ModuleManifest(
      moduleId: moduleId,
      displayName: moduleId,
      version: version,
      kind: ModuleKind.optional,
      slot: slot,
      description: 'test module package',
      enabledByDefault: true,
      entrypoint: 'module.dart',
      distributionPolicyRef: 'test',
      capabilityFlags: const <String, bool>{},
    ),
    matrix: ModuleCapabilityMatrix(
      moduleId: moduleId,
      platforms: <PlatformTarget, ModuleCapabilityRule>{
        for (final target in <PlatformTarget>[
          PlatformTarget.windows,
          PlatformTarget.linux,
          PlatformTarget.macos,
        ])
          target: ModuleCapabilityRule(
            supported: target == platformTarget,
            visible: target == platformTarget,
            installable: target == platformTarget,
            mountedByDefault: target == platformTarget,
            iosSafe: true,
            distributionChannel: 'self-hosted',
            note: '${target.label} package test rule',
          ),
      },
    ),
  );
}

class _TransientDeleteFileSystemManager
    extends file_system_io.LocalFileSystemManager {
  _TransientDeleteFileSystemManager({
    required super.facts,
    required Map<String, int> failuresBeforeSuccessByPath,
  }) : _failuresBeforeSuccessByPath = Map<String, int>.from(
         failuresBeforeSuccessByPath,
       );

  final Map<String, int> _failuresBeforeSuccessByPath;

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final normalizedPath = normalizePath(path);
    for (final key in _failuresBeforeSuccessByPath.keys.toList()) {
      if (normalizedPath != normalizePath(key)) {
        continue;
      }
      final remainingFailures = _failuresBeforeSuccessByPath[key] ?? 0;
      if (remainingFailures > 0) {
        _failuresBeforeSuccessByPath[key] = remainingFailures - 1;
        throw FileSystemException(
          'The process cannot access the file because it is being used by another process.',
          path,
          const OSError('sharing violation', 32),
        );
      }
    }
    return super.delete(path, recursive: recursive);
  }
}
