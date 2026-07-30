import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../environment/environment.dart';
import 'module_definition.dart';
import 'module_lifecycle.dart';
import 'module_registry.dart';

enum ModulePackageOperationStatus {
  installed,
  staged,
  activated,
  rolledBack,
  uninstalled,
  blocked,
}

extension ModulePackageOperationStatusX on ModulePackageOperationStatus {
  String get wireValue {
    return switch (this) {
      ModulePackageOperationStatus.installed => 'installed',
      ModulePackageOperationStatus.staged => 'staged',
      ModulePackageOperationStatus.activated => 'activated',
      ModulePackageOperationStatus.rolledBack => 'rolledBack',
      ModulePackageOperationStatus.uninstalled => 'uninstalled',
      ModulePackageOperationStatus.blocked => 'blocked',
    };
  }
}

class ModulePackageArtifact {
  ModulePackageArtifact({
    required this.definition,
    required List<int> bytes,
    required this.expectedSha256,
  }) : bytes = List<int>.unmodifiable(bytes);

  final ModuleDefinition definition;
  final List<int> bytes;
  final String expectedSha256;

  String get moduleId => definition.manifest.moduleId;
  String get version => definition.manifest.version;
  String get actualSha256 => sha256.convert(bytes).toString();
  String get expectedSha256Hex => expectedSha256.startsWith('sha256:')
      ? expectedSha256.substring('sha256:'.length)
      : expectedSha256;
  bool get verified => actualSha256 == expectedSha256Hex;
}

class ModulePackageDownloadRequest {
  const ModulePackageDownloadRequest({
    required this.definition,
    required this.sourcePath,
    required this.expectedSha256,
  });

  final ModuleDefinition definition;
  final String sourcePath;
  final String expectedSha256;

  String get moduleId => definition.manifest.moduleId;
  String get version => definition.manifest.version;
}

abstract class ModulePackageDownloader {
  Future<ModulePackageArtifact> download(ModulePackageDownloadRequest request);
}

class FileSystemModulePackageDownloader implements ModulePackageDownloader {
  const FileSystemModulePackageDownloader({
    required FileSystemManager fileSystemManager,
  }) : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;

  @override
  Future<ModulePackageArtifact> download(
    ModulePackageDownloadRequest request,
  ) async {
    return ModulePackageArtifact(
      definition: request.definition,
      bytes: await _fileSystemManager.readBytes(request.sourcePath),
      expectedSha256: request.expectedSha256,
    );
  }
}

class ModulePackageCleanupReport {
  const ModulePackageCleanupReport({
    required this.path,
    required this.requested,
    required this.reclaimed,
    required this.attempts,
    this.failure,
  });

  final String path;
  final bool requested;
  final bool reclaimed;
  final int attempts;
  final FileSystemOperationFailure? failure;

  bool get blocked => failure != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'requested': requested,
      'reclaimed': reclaimed,
      'attempts': attempts,
      'blocked': blocked,
      if (failure != null) 'failure': failure!.toJson(),
    };
  }
}

class ModulePackageOperationResult {
  const ModulePackageOperationResult({
    required this.status,
    required this.moduleId,
    required this.version,
    required this.message,
    this.activePackagePath,
    this.stagedPackagePath,
    this.registry,
    this.lifecyclePlan,
    this.stagedUpdateResolution,
    this.uninstallReconciliation,
    this.cleanupReports = const <ModulePackageCleanupReport>[],
    this.failure,
  });

  final ModulePackageOperationStatus status;
  final String moduleId;
  final String version;
  final String message;
  final String? activePackagePath;
  final String? stagedPackagePath;
  final ModuleRegistry? registry;
  final ModuleLifecyclePlan? lifecyclePlan;
  final ModuleStagedUpdateResolution? stagedUpdateResolution;
  final ModuleUninstallReconciliation? uninstallReconciliation;
  final List<ModulePackageCleanupReport> cleanupReports;
  final FileSystemOperationFailure? failure;

  bool get succeeded =>
      status != ModulePackageOperationStatus.blocked &&
      failure == null &&
      cleanupReports.every((report) => !report.blocked);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'moduleId': moduleId,
      'version': version,
      'message': message,
      'succeeded': succeeded,
      if (activePackagePath != null) 'activePackagePath': activePackagePath,
      if (stagedPackagePath != null) 'stagedPackagePath': stagedPackagePath,
      if (failure != null) 'failure': failure!.toJson(),
      if (cleanupReports.isNotEmpty)
        'cleanupReports': cleanupReports
            .map((report) => report.toJson())
            .toList(growable: false),
    };
  }
}

class ModulePackageStore {
  const ModulePackageStore({
    required FileSystemManager fileSystemManager,
    required this.rootPath,
    this.cleanupRetryCount = 2,
    this.retryDelay = Duration.zero,
  }) : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;
  final String rootPath;
  final int cleanupRetryCount;
  final Duration retryDelay;

  String moduleRootPath(String moduleId) {
    return _fileSystemManager.joinPath(<String>[
      rootPath,
      'modules',
      _safePathSegment(moduleId, label: 'moduleId'),
    ]);
  }

  String activePackagePath(String moduleId) {
    return _fileSystemManager.joinPath(<String>[
      moduleRootPath(moduleId),
      'active',
    ]);
  }

  String stagedRootPath(String moduleId) {
    return _fileSystemManager.joinPath(<String>[
      moduleRootPath(moduleId),
      'staged',
    ]);
  }

  String stagedPackagePath(String moduleId, String version) {
    return _fileSystemManager.joinPath(<String>[
      stagedRootPath(moduleId),
      _safePathSegment(version, label: 'version'),
    ]);
  }

  String cachePath(String moduleId) {
    return _fileSystemManager.joinPath(<String>[
      moduleRootPath(moduleId),
      'cache',
    ]);
  }

  String dataPath(String moduleId) {
    return _fileSystemManager.joinPath(<String>[
      moduleRootPath(moduleId),
      'data',
    ]);
  }

  Future<ModulePackageOperationResult> downloadAndInstallPackage({
    required ModuleRegistry registry,
    required ModulePackageDownloader downloader,
    required ModulePackageDownloadRequest request,
  }) async {
    try {
      return installPackage(
        registry: registry,
        artifact: await downloader.download(request),
      );
    } catch (error) {
      return _blockedDownload(request, error);
    }
  }

  Future<ModulePackageOperationResult> installPackage({
    required ModuleRegistry registry,
    required ModulePackageArtifact artifact,
  }) async {
    final plan = planOptionalModuleInstall(
      registry: registry,
      moduleId: artifact.moduleId,
      platformTarget: registry.platformTarget,
    );
    if (plan.action != ModuleLifecycleAction.install) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: plan.reason,
        lifecyclePlan: plan,
      );
    }
    final verification = _verifyArtifact(artifact);
    if (verification != null) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: verification.message,
        failure: verification,
        lifecyclePlan: plan,
      );
    }

    final activePath = activePackagePath(artifact.moduleId);
    final cleanup = await _replacePackageDirectory(activePath);
    if (cleanup.blocked) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: 'Module package install could not replace active package.',
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
        lifecyclePlan: plan,
      );
    }

    final writeFailure = await _writePackage(activePath, artifact);
    if (writeFailure != null) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: 'Module package install failed while writing package files.',
        failure: writeFailure,
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
        lifecyclePlan: plan,
      );
    }
    await _fileSystemManager.createDirectory(cachePath(artifact.moduleId));
    await _fileSystemManager.createDirectory(dataPath(artifact.moduleId));

    return ModulePackageOperationResult(
      status: ModulePackageOperationStatus.installed,
      moduleId: artifact.moduleId,
      version: artifact.version,
      message: 'Module package installed.',
      activePackagePath: activePath,
      registry: registry.withReplacedModules(<ModuleDefinition>[
        artifact.definition,
      ]),
      lifecyclePlan: plan,
      cleanupReports: <ModulePackageCleanupReport>[cleanup],
    );
  }

  Future<ModulePackageOperationResult> downloadAndStageUpdatePackage({
    required ModuleRegistry runningRegistry,
    required ModulePackageDownloader downloader,
    required ModulePackageDownloadRequest request,
  }) async {
    try {
      return stageUpdatePackage(
        runningRegistry: runningRegistry,
        artifact: await downloader.download(request),
      );
    } catch (error) {
      return _blockedDownload(request, error);
    }
  }

  Future<ModulePackageOperationResult> stageUpdatePackage({
    required ModuleRegistry runningRegistry,
    required ModulePackageArtifact artifact,
  }) async {
    if (runningRegistry.findById(artifact.moduleId) == null) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: 'Module is not installed in the running registry.',
      );
    }
    final verification = _verifyArtifact(artifact);
    if (verification != null) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: verification.message,
        failure: verification,
      );
    }

    final stagedPath = stagedPackagePath(artifact.moduleId, artifact.version);
    final cleanup = await _replacePackageDirectory(stagedPath);
    if (cleanup.blocked) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: 'Module package update could not replace staged package.',
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
      );
    }

    final writeFailure = await _writePackage(stagedPath, artifact);
    if (writeFailure != null) {
      return _blocked(
        moduleId: artifact.moduleId,
        version: artifact.version,
        message: 'Module package update failed while writing package files.',
        stagedPackagePath: stagedPath,
        failure: writeFailure,
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
      );
    }

    final resolution = resolveStagedModuleUpdates(
      runningRegistry: runningRegistry,
      stagedModules: <ModuleDefinition>[artifact.definition],
      restartCompleted: false,
    );
    return ModulePackageOperationResult(
      status: ModulePackageOperationStatus.staged,
      moduleId: artifact.moduleId,
      version: artifact.version,
      message: 'Module package update staged until restart.',
      activePackagePath: activePackagePath(artifact.moduleId),
      stagedPackagePath: stagedPath,
      registry: resolution.registry,
      stagedUpdateResolution: resolution,
      cleanupReports: <ModulePackageCleanupReport>[cleanup],
    );
  }

  Future<ModulePackageOperationResult> activateStagedPackage({
    required ModuleRegistry runningRegistry,
    required ModuleDefinition stagedDefinition,
  }) async {
    final moduleId = stagedDefinition.manifest.moduleId;
    final version = stagedDefinition.manifest.version;
    final stagedPath = stagedPackagePath(moduleId, version);
    if (!await _fileSystemManager.exists(stagedPath)) {
      return _blocked(
        moduleId: moduleId,
        version: version,
        message: 'No staged module package is available for activation.',
        stagedPackagePath: stagedPath,
      );
    }

    final resolution = resolveStagedModuleUpdates(
      runningRegistry: runningRegistry,
      stagedModules: <ModuleDefinition>[stagedDefinition],
      restartCompleted: true,
    );
    if (!resolution.activatedModuleIds.contains(moduleId)) {
      return _blocked(
        moduleId: moduleId,
        version: version,
        message: 'Staged module package is blocked for this platform.',
        stagedPackagePath: stagedPath,
        registry: resolution.registry,
        stagedUpdateResolution: resolution,
      );
    }

    final activePath = activePackagePath(moduleId);
    final cleanup = await _deletePath(activePath, requested: true);
    if (cleanup.blocked) {
      return _blocked(
        moduleId: moduleId,
        version: version,
        message: 'Staged module package could not replace active package.',
        activePackagePath: activePath,
        stagedPackagePath: stagedPath,
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
        stagedUpdateResolution: resolution,
      );
    }

    try {
      await _fileSystemManager.move(stagedPath, activePath);
    } catch (error) {
      return _blocked(
        moduleId: moduleId,
        version: version,
        message: 'Staged module package activation failed.',
        activePackagePath: activePath,
        stagedPackagePath: stagedPath,
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
        stagedUpdateResolution: resolution,
        failure: _classifyFailure(
          error,
          operation: 'activateModulePackage',
          target: activePath,
        ),
      );
    }

    return ModulePackageOperationResult(
      status: ModulePackageOperationStatus.activated,
      moduleId: moduleId,
      version: version,
      message: 'Staged module package activated after restart.',
      activePackagePath: activePath,
      registry: resolution.registry,
      stagedUpdateResolution: resolution,
      cleanupReports: <ModulePackageCleanupReport>[cleanup],
    );
  }

  Future<ModulePackageOperationResult> rollbackStagedPackage({
    required ModuleRegistry runningRegistry,
    required String moduleId,
    required String version,
  }) async {
    final stagedPath = stagedPackagePath(moduleId, version);
    final cleanup = await _deletePath(stagedPath, requested: true);
    if (cleanup.blocked) {
      return _blocked(
        moduleId: moduleId,
        version: version,
        message: 'Staged module package rollback could not remove staged data.',
        stagedPackagePath: stagedPath,
        cleanupReports: <ModulePackageCleanupReport>[cleanup],
      );
    }

    return ModulePackageOperationResult(
      status: ModulePackageOperationStatus.rolledBack,
      moduleId: moduleId,
      version: version,
      message: 'Staged module package rollback removed staged data.',
      activePackagePath: activePackagePath(moduleId),
      stagedPackagePath: stagedPath,
      registry: runningRegistry,
      cleanupReports: <ModulePackageCleanupReport>[cleanup],
    );
  }

  Future<ModulePackageOperationResult> uninstallPackage({
    required ModuleRegistry registry,
    required String moduleId,
    ModuleUninstallDataPolicy dataPolicy =
        ModuleUninstallDataPolicy.platformDefault,
    Iterable<ModuleWorkspaceReference> workspaceReferences = const [],
  }) async {
    final module = registry.findById(moduleId);
    if (module == null) {
      return _blocked(
        moduleId: moduleId,
        version: '',
        message: 'Module is not registered.',
      );
    }

    final plan = planModuleLifecycle(
      module: module,
      platformTarget: registry.platformTarget,
      uninstallRequested: true,
      uninstallDataPolicy: dataPolicy,
    );
    if (plan.action != ModuleLifecycleAction.uninstall) {
      return _blocked(
        moduleId: moduleId,
        version: module.manifest.version,
        message: plan.reason,
        lifecyclePlan: plan,
      );
    }

    final cleanupReports = <ModulePackageCleanupReport>[
      if (plan.reclaimPackage)
        await _deletePath(activePackagePath(moduleId), requested: true),
      if (plan.reclaimPackage)
        await _deletePath(stagedRootPath(moduleId), requested: true),
      if (plan.reclaimCache)
        await _deletePath(cachePath(moduleId), requested: true),
      if (plan.reclaimData)
        await _deletePath(dataPath(moduleId), requested: true)
      else
        ModulePackageCleanupReport(
          path: dataPath(moduleId),
          requested: false,
          reclaimed: false,
          attempts: 0,
        ),
    ];
    final blockedCleanup = cleanupReports
        .where((report) => report.blocked)
        .toList(growable: false);
    if (blockedCleanup.isNotEmpty) {
      return _blocked(
        moduleId: moduleId,
        version: module.manifest.version,
        message: 'Module package uninstall cleanup is blocked.',
        activePackagePath: activePackagePath(moduleId),
        lifecyclePlan: plan,
        cleanupReports: cleanupReports,
      );
    }

    final reconciliation = reconcileModuleUninstall(
      registry: registry,
      uninstalledModuleIds: <String>[moduleId],
      workspaceReferences: workspaceReferences,
    );
    return ModulePackageOperationResult(
      status: ModulePackageOperationStatus.uninstalled,
      moduleId: moduleId,
      version: module.manifest.version,
      message: plan.reason,
      activePackagePath: activePackagePath(moduleId),
      registry: reconciliation.registry,
      lifecyclePlan: plan,
      uninstallReconciliation: reconciliation,
      cleanupReports: cleanupReports,
    );
  }

  FileSystemOperationFailure? _verifyArtifact(ModulePackageArtifact artifact) {
    if (artifact.verified) {
      return null;
    }
    return FileSystemOperationFailure(
      kind: FileSystemFailureKind.policyBlocked,
      operation: 'verifyModulePackage',
      target: artifact.moduleId,
      sourceManager: 'ModulePackageStore',
      message:
          'Module package sha256 mismatch: expected ${artifact.expectedSha256Hex}, got ${artifact.actualSha256}.',
      recoveryHint: 'Download the module package again from a trusted source.',
    );
  }

  Future<ModulePackageCleanupReport> _replacePackageDirectory(
    String path,
  ) async {
    final cleanup = await _deletePath(path, requested: true);
    if (cleanup.blocked) {
      return cleanup;
    }
    try {
      await _fileSystemManager.createDirectory(path);
    } catch (error) {
      return ModulePackageCleanupReport(
        path: path,
        requested: true,
        reclaimed: false,
        attempts: cleanup.attempts,
        failure: _classifyFailure(
          error,
          operation: 'prepareModulePackageDirectory',
          target: path,
        ),
      );
    }
    return cleanup;
  }

  Future<FileSystemOperationFailure?> _writePackage(
    String packagePath,
    ModulePackageArtifact artifact,
  ) async {
    try {
      await _fileSystemManager.writeBytes(
        _fileSystemManager.joinPath(<String>[packagePath, 'package.bin']),
        artifact.bytes,
      );
      await _fileSystemManager.writeText(
        _fileSystemManager.joinPath(<String>[packagePath, 'package.json']),
        jsonEncode(<String, Object?>{
          'moduleId': artifact.moduleId,
          'version': artifact.version,
          'sha256': artifact.actualSha256,
          'entrypoint': artifact.definition.manifest.entrypoint,
          'distributionPolicyRef':
              artifact.definition.manifest.distributionPolicyRef,
        }),
      );
      return null;
    } catch (error) {
      return _classifyFailure(
        error,
        operation: 'writeModulePackage',
        target: packagePath,
      );
    }
  }

  Future<ModulePackageCleanupReport> _deletePath(
    String path, {
    required bool requested,
  }) async {
    if (!requested) {
      return ModulePackageCleanupReport(
        path: path,
        requested: false,
        reclaimed: false,
        attempts: 0,
      );
    }

    var attempts = 0;
    Object? lastError;
    for (var attempt = 0; attempt <= cleanupRetryCount; attempt += 1) {
      attempts += 1;
      try {
        await _fileSystemManager.delete(path, recursive: true);
        return ModulePackageCleanupReport(
          path: path,
          requested: true,
          reclaimed: !await _fileSystemManager.exists(path),
          attempts: attempts,
        );
      } catch (error) {
        lastError = error;
        if (attempt == cleanupRetryCount) {
          break;
        }
        if (retryDelay != Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }

    return ModulePackageCleanupReport(
      path: path,
      requested: true,
      reclaimed: false,
      attempts: attempts,
      failure: _classifyFailure(
        lastError ?? StateError('Unknown delete failure.'),
        operation: 'deleteModulePackagePath',
        target: path,
      ),
    );
  }

  FileSystemOperationFailure _classifyFailure(
    Object error, {
    required String operation,
    required String target,
  }) {
    if (error is FileSystemBoundaryException) {
      return error.failure;
    }
    return _fileSystemManager.classifyFailure(
      error,
      operation: operation,
      target: target,
      recoveryHint:
          'Close running module processes or retry after the current session ends.',
    );
  }

  ModulePackageOperationResult _blockedDownload(
    ModulePackageDownloadRequest request,
    Object error,
  ) {
    final failure = _classifyFailure(
      error,
      operation: 'downloadModulePackage',
      target: request.sourcePath,
    );
    return _blocked(
      moduleId: request.moduleId,
      version: request.version,
      message: 'Module package download failed.',
      failure: failure,
    );
  }

  ModulePackageOperationResult _blocked({
    required String moduleId,
    required String version,
    required String message,
    String? activePackagePath,
    String? stagedPackagePath,
    ModuleRegistry? registry,
    ModuleLifecyclePlan? lifecyclePlan,
    ModuleStagedUpdateResolution? stagedUpdateResolution,
    List<ModulePackageCleanupReport> cleanupReports =
        const <ModulePackageCleanupReport>[],
    FileSystemOperationFailure? failure,
  }) {
    return ModulePackageOperationResult(
      status: ModulePackageOperationStatus.blocked,
      moduleId: moduleId,
      version: version,
      message: message,
      activePackagePath: activePackagePath,
      stagedPackagePath: stagedPackagePath,
      registry: registry,
      lifecyclePlan: lifecyclePlan,
      stagedUpdateResolution: stagedUpdateResolution,
      cleanupReports: cleanupReports,
      failure: failure,
    );
  }
}

String _safePathSegment(String value, {required String label}) {
  if (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
    return value;
  }
  throw FormatException('Invalid module package $label path segment: $value');
}
