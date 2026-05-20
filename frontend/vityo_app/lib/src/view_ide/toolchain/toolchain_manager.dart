import 'dart:convert';

import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import 'clang_cpp_version_configuration.dart';
import 'toolchain_catalog.dart';
import 'toolchain_configuration_store.dart';
import 'toolchain_environment.dart';
import 'toolchain_health_check.dart';
import 'toolchain_install_executor.dart';
import 'toolchain_install_policy.dart';
import 'toolchain_resolver.dart';
import 'toolchain_runtime.dart';
import 'styio_toolchain_lifecycle.dart';

class ToolchainStateEntry {
  const ToolchainStateEntry({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.executablePath,
    required this.active,
    this.version,
    this.channel,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final ToolchainKind kind;
  final String displayName;
  final String executablePath;
  final bool active;
  final String? version;
  final String? channel;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.wireValue,
      'displayName': displayName,
      'executablePath': executablePath,
      'active': active,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
      'metadata': metadata,
    };
  }
}

class ToolchainStateSnapshot {
  const ToolchainStateSnapshot({
    required this.targetId,
    required this.entries,
    this.workspaceId,
  });

  final String targetId;
  final String? workspaceId;
  final List<ToolchainStateEntry> entries;

  List<ToolchainStateEntry> list({ToolchainKind? kind}) {
    return entries
        .where((entry) {
          return kind == null || entry.kind == kind;
        })
        .toList(growable: false);
  }

  ToolchainStateEntry? active(ToolchainKind kind) {
    for (final entry in entries) {
      if (entry.kind == kind && entry.active) {
        return entry;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetId': targetId,
      if (workspaceId != null) 'workspaceId': workspaceId,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

enum ToolchainManagerStatus { ready, unresolved, unhealthy }

enum ToolchainCapabilityState { active, available, unresolved, unhealthy }

enum ToolchainRecoveryStateKind {
  none,
  needsSelection,
  needsInstall,
  retryAvailable,
}

class ToolchainRecoveryState {
  const ToolchainRecoveryState({
    required this.kind,
    required this.actionIds,
    this.message,
  });

  final ToolchainRecoveryStateKind kind;
  final List<String> actionIds;
  final String? message;

  bool get actionable => kind != ToolchainRecoveryStateKind.none;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'actionIds': actionIds,
      if (message != null) 'message': message,
      'actionable': actionable,
    };
  }
}

class ToolchainCapabilityStatus {
  const ToolchainCapabilityStatus({
    required this.kind,
    required this.state,
    required this.active,
    this.descriptorId,
    this.message,
  });

  final ToolchainKind kind;
  final ToolchainCapabilityState state;
  final bool active;
  final String? descriptorId;
  final String? message;

  bool get usable {
    return state == ToolchainCapabilityState.active ||
        state == ToolchainCapabilityState.available;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'state': state.name,
      'active': active,
      if (descriptorId != null) 'descriptorId': descriptorId,
      if (message != null) 'message': message,
      'usable': usable,
    };
  }
}

class ToolchainManagerStatusReport {
  const ToolchainManagerStatusReport({
    required this.status,
    required this.snapshot,
    required this.requirement,
    required this.resolution,
    this.capabilities = const <ToolchainCapabilityStatus>[],
    this.recoveryState = const ToolchainRecoveryState(
      kind: ToolchainRecoveryStateKind.none,
      actionIds: <String>[],
    ),
    this.installHistory,
    this.health,
    this.message,
  });

  final ToolchainManagerStatus status;
  final ToolchainStateSnapshot snapshot;
  final ToolchainRequirement requirement;
  final ToolchainResolution resolution;
  final List<ToolchainCapabilityStatus> capabilities;
  final ToolchainRecoveryState recoveryState;
  final ToolchainInstallHistorySnapshot? installHistory;
  final ToolchainHealthReport? health;
  final String? message;

  bool get ready => status == ToolchainManagerStatus.ready;

  ToolchainCapabilityStatus? capability(ToolchainKind kind) {
    for (final capability in capabilities) {
      if (capability.kind == kind) {
        return capability;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'snapshot': snapshot.toJson(),
      'requirement': requirement.toJson(),
      'resolution': resolution.toJson(),
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(growable: false),
      'recoveryState': recoveryState.toJson(),
      if (installHistory != null) 'installHistory': installHistory!.toJson(),
      if (health != null) 'health': health!.toJson(),
      if (message != null) 'message': message,
      'ready': ready,
    };
  }
}

class ToolchainManagerBootstrapSummary {
  const ToolchainManagerBootstrapSummary({
    required this.managerReport,
    required this.styioLifecycle,
    required this.settingsActionIds,
    required this.installerActionIds,
    required this.projectBootstrapActionIds,
  });

  factory ToolchainManagerBootstrapSummary.fromReports({
    required ToolchainManagerStatusReport managerReport,
    required StyioToolchainLifecycleReport styioLifecycle,
  }) {
    final settingsActions = <String>{
      ...managerReport.recoveryState.actionIds,
      for (final role in styioLifecycle.selectableRequiredRoles)
        'select-styio-${role.role.wireValue}',
      for (final role in styioLifecycle.missingRequiredRoles)
        'install-styio-${role.role.wireValue}',
    };
    final installerActions = <String>{
      if (styioLifecycle.missingRequiredRoles.isNotEmpty)
        'install-managed-styio-toolchain',
      if (managerReport.recoveryState.kind ==
          ToolchainRecoveryStateKind.retryAvailable)
        'retry-toolchain-action',
      if (styioLifecycle.ready) 'verify-styio-toolchain',
    };
    final projectBootstrapActions = <String>{
      if (managerReport.ready && styioLifecycle.ready)
        'validate-project-toolchain'
      else ...<String>{'open-toolchain-settings', 'bootstrap-styio-toolchain'},
    };
    return ToolchainManagerBootstrapSummary(
      managerReport: managerReport,
      styioLifecycle: styioLifecycle,
      settingsActionIds: List<String>.unmodifiable(settingsActions),
      installerActionIds: List<String>.unmodifiable(installerActions),
      projectBootstrapActionIds: List<String>.unmodifiable(
        projectBootstrapActions,
      ),
    );
  }

  final ToolchainManagerStatusReport managerReport;
  final StyioToolchainLifecycleReport styioLifecycle;
  final List<String> settingsActionIds;
  final List<String> installerActionIds;
  final List<String> projectBootstrapActionIds;

  bool get ready => managerReport.ready && styioLifecycle.ready;

  Map<String, Object?> get agentContext {
    final activeEntries = managerReport.snapshot.entries
        .where((entry) => entry.active)
        .toList(growable: false);
    return <String, Object?>{
      'toolchainReady': ready,
      'managerStatus': managerReport.status.name,
      'styioLifecycleState': styioLifecycle.state.name,
      'activeToolchains': activeEntries
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'requiredStyioRoles': styioLifecycle.requiredRoles
          .map((role) => role.wireValue)
          .toList(growable: false),
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'managerReport': managerReport.toJson(),
      'styioLifecycle': styioLifecycle.toJson(),
      'settingsActionIds': settingsActionIds,
      'installerActionIds': installerActionIds,
      'projectBootstrapActionIds': projectBootstrapActionIds,
      'agentContext': agentContext,
    };
  }
}

enum ToolchainSelectionStatus { selected, cleared, missing }

enum ToolchainRegistrationStatus { registered, duplicate, invalid }

enum ToolchainInstallRegistrationStatus {
  registered,
  installFailed,
  notStaged,
  invalidManifest,
  registrationFailed,
}

class ToolchainRegistrationResult {
  const ToolchainRegistrationResult({
    required this.status,
    required this.snapshot,
    this.toolchainId,
    this.kind,
    this.message,
  });

  final ToolchainRegistrationStatus status;
  final String? toolchainId;
  final ToolchainKind? kind;
  final String? message;
  final ToolchainStateSnapshot snapshot;

  bool get succeeded => status == ToolchainRegistrationStatus.registered;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      if (toolchainId != null) 'toolchainId': toolchainId,
      if (kind != null) 'kind': kind!.wireValue,
      if (message != null) 'message': message,
      'snapshot': snapshot.toJson(),
      'succeeded': succeeded,
    };
  }
}

class ToolchainInstallRegistrationResult {
  const ToolchainInstallRegistrationResult({
    required this.status,
    required this.execution,
    required this.snapshot,
    this.registration,
    this.rolledBack = false,
    this.rollbackMessage,
    this.message,
  });

  final ToolchainInstallRegistrationStatus status;
  final ToolchainInstallExecutionResult execution;
  final ToolchainRegistrationResult? registration;
  final ToolchainStateSnapshot snapshot;
  final bool rolledBack;
  final String? rollbackMessage;
  final String? message;

  bool get succeeded => status == ToolchainInstallRegistrationStatus.registered;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'execution': execution.toJson(),
      if (registration != null) 'registration': registration!.toJson(),
      'snapshot': snapshot.toJson(),
      'rolledBack': rolledBack,
      if (rollbackMessage != null) 'rollbackMessage': rollbackMessage,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class ToolchainSelectionResult {
  const ToolchainSelectionResult({
    required this.status,
    required this.snapshot,
    this.kind,
    this.toolchainId,
    this.message,
  });

  final ToolchainSelectionStatus status;
  final ToolchainKind? kind;
  final String? toolchainId;
  final String? message;
  final ToolchainStateSnapshot snapshot;

  bool get succeeded {
    return status == ToolchainSelectionStatus.selected ||
        status == ToolchainSelectionStatus.cleared;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      if (kind != null) 'kind': kind!.wireValue,
      if (toolchainId != null) 'toolchainId': toolchainId,
      if (message != null) 'message': message,
      'snapshot': snapshot.toJson(),
    };
  }
}

class ToolchainManager {
  ToolchainManager({
    required ToolchainConfigurationStore configurationStore,
    required PlatformManagerBundle platformManagers,
    this.workspaceId,
    ToolchainResolver resolver = const ToolchainResolver(),
    ToolchainEnvironmentBuilder? environmentBuilder,
  }) : _configurationStore = configurationStore,
       _platformManagers = platformManagers,
       _resolver = resolver,
       _environmentBuilder =
           environmentBuilder ??
           ToolchainEnvironmentBuilder.fromPlatformContext(
             platformManagers.context,
           );

  final ToolchainConfigurationStore _configurationStore;
  final PlatformManagerBundle _platformManagers;
  final String? workspaceId;
  final ToolchainResolver _resolver;
  final ToolchainEnvironmentBuilder _environmentBuilder;

  PlatformManagerBundle get platformManagers => _platformManagers;

  String get _targetId => _platformManagers.context.targetId;

  Future<ToolchainCatalog> loadCatalog() {
    return _configurationStore.loadCatalog(
      workspaceId: workspaceId,
      targetId: _targetId,
    );
  }

  Future<void> saveCatalog(ToolchainCatalog catalog) {
    return _configurationStore.saveCatalog(
      catalog,
      workspaceId: workspaceId,
      targetId: _targetId,
    );
  }

  Future<bool> clearCatalog() {
    return _configurationStore.deleteCatalog(
      workspaceId: workspaceId,
      targetId: _targetId,
    );
  }

  Future<void> saveClangCppVersionPreference(
    ClangCppVersionPreference preference,
  ) {
    return _configurationStore.saveClangCppVersionPreference(
      preference,
      workspaceId: workspaceId,
      targetId: _targetId,
    );
  }

  Future<ClangCppVersionPreference?> loadClangCppVersionPreference() {
    return _configurationStore.loadClangCppVersionPreference(
      workspaceId: workspaceId,
      targetId: _targetId,
    );
  }

  Future<bool> clearClangCppVersionPreference() {
    return _configurationStore.deleteClangCppVersionPreference(
      workspaceId: workspaceId,
      targetId: _targetId,
    );
  }

  ToolchainInstallPlan planInstallation(
    ToolchainInstallRequest request, {
    ToolchainInstallPolicy policy = const ToolchainInstallPolicy(),
  }) {
    return policy.plan(request);
  }

  Future<ToolchainInstallExecutionResult> executeInstallPlan(
    ToolchainInstallPlan plan, {
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final result =
        await ToolchainInstallExecutor(
          platformManagers: _platformManagers,
          environmentBuilder: _environmentBuilder,
        ).execute(
          plan,
          environment: environment,
          environmentOverlays: environmentOverlays,
          workingDirectory: workingDirectory,
          timeout: timeout,
        );
    final recordedAt = DateTime.now().toUtc();
    await _configurationStore.appendInstallHistory(
      ToolchainInstallHistoryEntry(
        id: recordedAt.toIso8601String(),
        status: result.status.name,
        mode: result.plan.mode.name,
        kind: result.plan.requirement.kind.wireValue,
        succeeded: result.succeeded,
        recordedAt: recordedAt,
        message: result.message,
      ),
      workspaceId: workspaceId,
      targetId: _targetId,
    );
    return result;
  }

  Future<ToolchainInstallRegistrationResult> installAndRegisterStagedToolchain(
    ToolchainInstallPlan plan, {
    required String toolchainId,
    required String displayName,
    bool activate = false,
    bool rollbackOnInstallFailure = true,
    bool rollbackOnRegistrationFailure = true,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final execution = await executeInstallPlan(
      plan,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    if (execution.status == ToolchainInstallExecutionStatus.failed ||
        execution.status == ToolchainInstallExecutionStatus.blocked ||
        execution.status ==
            ToolchainInstallExecutionStatus.requiresUserAction) {
      var rolledBack = false;
      String? rollbackMessage;
      if (rollbackOnInstallFailure) {
        final rollbackResult = await _rollbackStagedArtifact(execution);
        rolledBack = rollbackResult.rolledBack;
        rollbackMessage = rollbackResult.message;
      }
      return ToolchainInstallRegistrationResult(
        status: ToolchainInstallRegistrationStatus.installFailed,
        execution: execution,
        snapshot: await snapshot(),
        rolledBack: rolledBack,
        rollbackMessage: rollbackMessage,
        message: execution.message,
      );
    }
    final executablePath =
        execution.extractedExecutablePath ?? execution.stagedPath;
    if (executablePath == null || executablePath.isEmpty) {
      return ToolchainInstallRegistrationResult(
        status: ToolchainInstallRegistrationStatus.notStaged,
        execution: execution,
        snapshot: await snapshot(),
        message: 'Install plan did not produce a staged toolchain artifact.',
      );
    }
    final registration = await registerToolchain(
      ToolchainDescriptor(
        id: toolchainId,
        kind: plan.requirement.kind,
        displayName: displayName,
        executablePath: executablePath,
        version: plan.requirement.version,
        channel: plan.requirement.channel,
        metadata: <String, Object?>{
          ...metadata,
          'installMode': plan.mode.name,
          if (execution.artifactSha256 != null)
            'artifactSha256': execution.artifactSha256,
          if (execution.artifactSizeBytes != null)
            'artifactSizeBytes': execution.artifactSizeBytes,
          if (execution.verificationStatus != null)
            'verificationStatus': execution.verificationStatus!.name,
          'executablePermissionApplied': execution.executablePermissionApplied,
        },
      ),
      activate: activate,
    );
    var rolledBack = false;
    String? rollbackMessage;
    if (!registration.succeeded && rollbackOnRegistrationFailure) {
      final rollbackResult = await _rollbackStagedArtifact(execution);
      rolledBack = rollbackResult.rolledBack;
      rollbackMessage = rollbackResult.message;
    }
    return ToolchainInstallRegistrationResult(
      status: registration.succeeded
          ? ToolchainInstallRegistrationStatus.registered
          : ToolchainInstallRegistrationStatus.registrationFailed,
      execution: execution,
      registration: registration,
      snapshot: registration.snapshot,
      rolledBack: rolledBack,
      rollbackMessage: rollbackMessage,
      message: registration.message,
    );
  }

  Future<_ToolchainInstallRollbackResult> _rollbackStagedArtifact(
    ToolchainInstallExecutionResult execution,
  ) async {
    final rollbackPaths = <String>{
      if (execution.stagingDirectory != null &&
          execution.stagingDirectory!.isNotEmpty)
        execution.stagingDirectory!,
      if (execution.extractionDirectory != null &&
          execution.extractionDirectory!.isNotEmpty)
        execution.extractionDirectory!,
    };
    if (rollbackPaths.isEmpty) {
      return const _ToolchainInstallRollbackResult(
        rolledBack: false,
        message:
            'No staging or extraction directory was available for rollback.',
      );
    }
    final failures = <String>[];
    var rolledBack = false;
    for (final path in rollbackPaths) {
      try {
        await _platformManagers.fileSystem.delete(path, recursive: true);
        rolledBack = true;
      } on Object catch (error) {
        failures.add('$path: $error');
      }
    }
    if (failures.isNotEmpty) {
      return _ToolchainInstallRollbackResult(
        rolledBack: rolledBack,
        message: failures.join('; '),
      );
    }
    return _ToolchainInstallRollbackResult(rolledBack: rolledBack);
  }

  Future<ToolchainInstallRegistrationResult>
  installAndRegisterArchiveManifestToolchain(
    ToolchainInstallPlan plan, {
    bool activate = false,
    bool rollbackOnInstallFailure = true,
    bool rollbackOnRegistrationFailure = true,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final execution = await executeInstallPlan(
      plan,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    if (execution.status == ToolchainInstallExecutionStatus.failed ||
        execution.status == ToolchainInstallExecutionStatus.blocked ||
        execution.status ==
            ToolchainInstallExecutionStatus.requiresUserAction) {
      var rolledBack = false;
      String? rollbackMessage;
      if (rollbackOnInstallFailure) {
        final rollbackResult = await _rollbackStagedArtifact(execution);
        rolledBack = rollbackResult.rolledBack;
        rollbackMessage = rollbackResult.message;
      }
      return ToolchainInstallRegistrationResult(
        status: ToolchainInstallRegistrationStatus.installFailed,
        execution: execution,
        snapshot: await snapshot(),
        rolledBack: rolledBack,
        rollbackMessage: rollbackMessage,
        message: execution.message,
      );
    }
    final manifestPath = execution.extractedManifestPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      final rollbackResult = rollbackOnRegistrationFailure
          ? await _rollbackStagedArtifact(execution)
          : const _ToolchainInstallRollbackResult(rolledBack: false);
      return ToolchainInstallRegistrationResult(
        status: ToolchainInstallRegistrationStatus.invalidManifest,
        execution: execution,
        snapshot: await snapshot(),
        rolledBack: rollbackResult.rolledBack,
        rollbackMessage: rollbackResult.message,
        message: 'Archive install manifest was not produced.',
      );
    }

    final manifest = await _readToolchainManifest(manifestPath);
    if (manifest == null) {
      final rollbackResult = rollbackOnRegistrationFailure
          ? await _rollbackStagedArtifact(execution)
          : const _ToolchainInstallRollbackResult(rolledBack: false);
      return ToolchainInstallRegistrationResult(
        status: ToolchainInstallRegistrationStatus.invalidManifest,
        execution: execution,
        snapshot: await snapshot(),
        rolledBack: rollbackResult.rolledBack,
        rollbackMessage: rollbackResult.message,
        message: 'Archive install manifest is invalid.',
      );
    }

    final executablePath = _archiveExecutablePathFromManifest(
      execution,
      manifest,
    );
    if (executablePath == null) {
      final rollbackResult = rollbackOnRegistrationFailure
          ? await _rollbackStagedArtifact(execution)
          : const _ToolchainInstallRollbackResult(rolledBack: false);
      return ToolchainInstallRegistrationResult(
        status: ToolchainInstallRegistrationStatus.invalidManifest,
        execution: execution,
        snapshot: await snapshot(),
        rolledBack: rollbackResult.rolledBack,
        rollbackMessage: rollbackResult.message,
        message: 'Archive install manifest executablePath is invalid.',
      );
    }

    final descriptor = ToolchainDescriptor.fromJson(manifest);
    final registration = await registerToolchain(
      ToolchainDescriptor(
        id: descriptor.id,
        kind: descriptor.kind,
        displayName: descriptor.displayName,
        executablePath: executablePath,
        version: descriptor.version,
        channel: descriptor.channel,
        metadata: <String, Object?>{
          ...descriptor.metadata,
          ...metadata,
          'installMode': plan.mode.name,
          if (execution.artifactSha256 != null)
            'artifactSha256': execution.artifactSha256,
          if (execution.artifactSizeBytes != null)
            'artifactSizeBytes': execution.artifactSizeBytes,
          if (execution.verificationStatus != null)
            'verificationStatus': execution.verificationStatus!.name,
          'executablePermissionApplied': execution.executablePermissionApplied,
        },
      ),
      activate: activate,
    );
    var rolledBack = false;
    String? rollbackMessage;
    if (!registration.succeeded && rollbackOnRegistrationFailure) {
      final rollbackResult = await _rollbackStagedArtifact(execution);
      rolledBack = rollbackResult.rolledBack;
      rollbackMessage = rollbackResult.message;
    }
    return ToolchainInstallRegistrationResult(
      status: registration.succeeded
          ? ToolchainInstallRegistrationStatus.registered
          : ToolchainInstallRegistrationStatus.registrationFailed,
      execution: execution,
      registration: registration,
      snapshot: registration.snapshot,
      rolledBack: rolledBack,
      rollbackMessage: rollbackMessage,
      message: registration.message,
    );
  }

  Future<Map<String, Object?>?> _readToolchainManifest(String path) async {
    try {
      final decoded = jsonDecode(
        await _platformManagers.fileSystem.readText(path),
      );
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        );
      }
      return null;
    } on Object {
      return null;
    }
  }

  String? _archiveExecutablePathFromManifest(
    ToolchainInstallExecutionResult execution,
    Map<String, Object?> manifest,
  ) {
    final extractionDirectory = execution.extractionDirectory;
    final executablePath = manifest['executablePath'];
    if (extractionDirectory == null ||
        executablePath is! String ||
        executablePath.isEmpty ||
        executablePath.startsWith('/')) {
      return null;
    }
    for (final segment in executablePath.split('/')) {
      if (segment == '..') {
        return null;
      }
    }
    return _platformManagers.fileSystem.joinPath(<String>[
      extractionDirectory,
      executablePath,
    ]);
  }

  Future<ToolchainRegistrationResult> registerToolchain(
    ToolchainDescriptor descriptor, {
    bool activate = false,
  }) async {
    if (descriptor.id.isEmpty || descriptor.executablePath.isEmpty) {
      return ToolchainRegistrationResult(
        status: ToolchainRegistrationStatus.invalid,
        toolchainId: descriptor.id.isEmpty ? null : descriptor.id,
        kind: descriptor.kind,
        message: 'Toolchain id and executable path are required.',
        snapshot: await snapshot(),
      );
    }
    var duplicate = false;
    await _configurationStore.editCatalog(
      (catalog) {
        if (catalog.lookup(descriptor.id) != null) {
          duplicate = true;
          return ToolchainCatalogEditDecision.keep;
        }
        catalog.register(descriptor, activate: activate);
        return ToolchainCatalogEditDecision.write(catalog);
      },
      workspaceId: workspaceId,
      targetId: _targetId,
    );
    if (duplicate) {
      return ToolchainRegistrationResult(
        status: ToolchainRegistrationStatus.duplicate,
        toolchainId: descriptor.id,
        kind: descriptor.kind,
        message: 'Toolchain ${descriptor.id} is already registered.',
        snapshot: await snapshot(),
      );
    }
    return ToolchainRegistrationResult(
      status: ToolchainRegistrationStatus.registered,
      toolchainId: descriptor.id,
      kind: descriptor.kind,
      snapshot: await snapshot(),
    );
  }

  Future<ToolchainSelectionResult> selectToolchain(String id) async {
    ToolchainDescriptor? selected;
    await _configurationStore.editCatalog(
      (catalog) {
        final descriptor = catalog.lookup(id);
        if (descriptor == null) {
          return ToolchainCatalogEditDecision.keep;
        }
        selected = descriptor;
        catalog.activate(id);
        return ToolchainCatalogEditDecision.write(catalog);
      },
      workspaceId: workspaceId,
      targetId: _targetId,
    );
    if (selected == null) {
      return ToolchainSelectionResult(
        status: ToolchainSelectionStatus.missing,
        toolchainId: id,
        message: 'Toolchain $id is not registered.',
        snapshot: await snapshot(),
      );
    }
    return ToolchainSelectionResult(
      status: ToolchainSelectionStatus.selected,
      kind: selected!.kind,
      toolchainId: id,
      snapshot: await snapshot(),
    );
  }

  Future<ToolchainSelectionResult> clearActiveToolchain(
    ToolchainKind kind,
  ) async {
    var cleared = false;
    await _configurationStore.editCatalog(
      (catalog) {
        cleared = catalog.deactivate(kind);
        return cleared
            ? ToolchainCatalogEditDecision.write(catalog)
            : ToolchainCatalogEditDecision.keep;
      },
      workspaceId: workspaceId,
      targetId: _targetId,
    );
    return ToolchainSelectionResult(
      status: ToolchainSelectionStatus.cleared,
      kind: kind,
      message: cleared ? null : 'No active ${kind.wireValue} toolchain.',
      snapshot: await snapshot(),
    );
  }

  Future<ToolchainStateSnapshot> snapshot({ToolchainKind? kind}) async {
    final catalog = await loadCatalog();
    final catalogSnapshot = catalog.snapshot();
    final entries = <ToolchainStateEntry>[];
    for (final descriptor in catalog.list(kind: kind)) {
      entries.add(
        ToolchainStateEntry(
          id: descriptor.id,
          kind: descriptor.kind,
          displayName: descriptor.displayName,
          executablePath: descriptor.executablePath,
          version: descriptor.version,
          channel: descriptor.channel,
          metadata: descriptor.metadata,
          active:
              catalogSnapshot.activeToolchainIds[descriptor.kind] ==
              descriptor.id,
        ),
      );
    }
    return ToolchainStateSnapshot(
      targetId: _platformManagers.context.targetId,
      workspaceId: workspaceId,
      entries: entries,
    );
  }

  ToolchainRuntime runtimeFor(ToolchainCatalog catalog) {
    return ToolchainRuntime.fromPlatformManagers(
      catalog: catalog,
      platformManagers: _platformManagers,
      resolver: _resolver,
      environmentBuilder: _environmentBuilder,
    );
  }

  Future<ToolchainManagerStatusReport> statusReport({
    required ToolchainKind kind,
    ToolchainRequirement? requirement,
    bool includeHealth = false,
    List<String>? probeArguments,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final catalog = await loadCatalog();
    final effectiveRequirement =
        requirement ?? ToolchainRequirement(kind: kind);
    final snapshot = await this.snapshot();
    final installHistory = await _configurationStore.loadInstallHistory(
      workspaceId: workspaceId,
      targetId: _targetId,
    );
    final resolution = _resolver.resolve(catalog, effectiveRequirement);
    if (!resolution.resolved) {
      final capabilities = _capabilitiesFor(
        snapshot: snapshot,
        requirement: effectiveRequirement,
        resolution: resolution,
      );
      final recoveryState = _recoveryStateFor(
        resolution: resolution,
        installHistory: installHistory,
      );
      return ToolchainManagerStatusReport(
        status: ToolchainManagerStatus.unresolved,
        snapshot: snapshot,
        requirement: effectiveRequirement,
        resolution: resolution,
        capabilities: capabilities,
        recoveryState: recoveryState,
        installHistory: installHistory,
        message: resolution.message,
      );
    }
    if (!includeHealth && probeArguments == null) {
      final capabilities = _capabilitiesFor(
        snapshot: snapshot,
        requirement: effectiveRequirement,
        resolution: resolution,
      );
      final recoveryState = _recoveryStateFor(
        resolution: resolution,
        installHistory: installHistory,
      );
      return ToolchainManagerStatusReport(
        status: ToolchainManagerStatus.ready,
        snapshot: snapshot,
        requirement: effectiveRequirement,
        resolution: resolution,
        capabilities: capabilities,
        recoveryState: recoveryState,
        installHistory: installHistory,
      );
    }
    final health = await runtimeFor(catalog).checkHealth(
      kind: kind,
      requirement: effectiveRequirement,
      probeArguments: probeArguments,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    final capabilities = _capabilitiesFor(
      snapshot: snapshot,
      requirement: effectiveRequirement,
      resolution: resolution,
      health: health,
    );
    final recoveryState = _recoveryStateFor(
      resolution: resolution,
      installHistory: installHistory,
      health: health,
    );
    return ToolchainManagerStatusReport(
      status: health.healthy
          ? ToolchainManagerStatus.ready
          : ToolchainManagerStatus.unhealthy,
      snapshot: snapshot,
      requirement: effectiveRequirement,
      resolution: resolution,
      capabilities: capabilities,
      recoveryState: recoveryState,
      installHistory: installHistory,
      health: health,
      message: health.message,
    );
  }

  Future<ToolchainManagerBootstrapSummary> bootstrapSummary({
    ToolchainKind kind = ToolchainKind.languageService,
    ToolchainRequirement? requirement,
    List<StyioToolchainRole> requiredStyioRoles =
        StyioToolchainLifecycleManager.defaultRequiredRoles,
  }) async {
    final report = await statusReport(kind: kind, requirement: requirement);
    final catalog = await loadCatalog();
    final lifecycle = StyioToolchainLifecycleManager(
      catalog: catalog,
    ).inspect(requiredRoles: requiredStyioRoles);
    return ToolchainManagerBootstrapSummary.fromReports(
      managerReport: report,
      styioLifecycle: lifecycle,
    );
  }

  List<ToolchainCapabilityStatus> _capabilitiesFor({
    required ToolchainStateSnapshot snapshot,
    required ToolchainRequirement requirement,
    required ToolchainResolution resolution,
    ToolchainHealthReport? health,
  }) {
    return ToolchainKind.values
        .map((kind) {
          final active = snapshot.active(kind);
          final entries = snapshot.list(kind: kind);
          if (kind == requirement.kind) {
            if (health != null && !health.healthy) {
              return ToolchainCapabilityStatus(
                kind: kind,
                state: ToolchainCapabilityState.unhealthy,
                active: active != null,
                descriptorId: resolution.descriptor?.id ?? active?.id,
                message: health.message ?? resolution.message,
              );
            }
            if (!resolution.resolved) {
              return ToolchainCapabilityStatus(
                kind: kind,
                state: ToolchainCapabilityState.unresolved,
                active: active != null,
                descriptorId: resolution.descriptor?.id ?? active?.id,
                message: resolution.message,
              );
            }
            final descriptor = resolution.descriptor;
            return ToolchainCapabilityStatus(
              kind: kind,
              state: active?.id == descriptor?.id
                  ? ToolchainCapabilityState.active
                  : ToolchainCapabilityState.available,
              active: active?.id == descriptor?.id,
              descriptorId: descriptor?.id ?? active?.id,
            );
          }
          if (active != null) {
            return ToolchainCapabilityStatus(
              kind: kind,
              state: ToolchainCapabilityState.active,
              active: true,
              descriptorId: active.id,
            );
          }
          if (entries.isNotEmpty) {
            return ToolchainCapabilityStatus(
              kind: kind,
              state: ToolchainCapabilityState.available,
              active: false,
              descriptorId: entries.first.id,
            );
          }
          return ToolchainCapabilityStatus(
            kind: kind,
            state: ToolchainCapabilityState.unresolved,
            active: false,
            message: 'No ${kind.wireValue} toolchain is registered.',
          );
        })
        .toList(growable: false);
  }

  ToolchainRecoveryState _recoveryStateFor({
    required ToolchainResolution resolution,
    required ToolchainInstallHistorySnapshot installHistory,
    ToolchainHealthReport? health,
  }) {
    final latestInstall = installHistory.entries.isEmpty
        ? null
        : installHistory.entries.first;
    if (health != null && !health.healthy) {
      return ToolchainRecoveryState(
        kind: ToolchainRecoveryStateKind.retryAvailable,
        actionIds: const <String>[
          'retry-toolchain-health-check',
          'select-existing-toolchain',
        ],
        message: health.message ?? 'Toolchain health check failed.',
      );
    }
    if (!resolution.resolved) {
      return ToolchainRecoveryState(
        kind: ToolchainRecoveryStateKind.needsSelection,
        actionIds: const <String>[
          'select-existing-toolchain',
          'install-managed-toolchain',
          'use-degraded-mode',
        ],
        message: resolution.message,
      );
    }
    if (latestInstall != null && !latestInstall.succeeded) {
      return ToolchainRecoveryState(
        kind: ToolchainRecoveryStateKind.retryAvailable,
        actionIds: const <String>[
          'retry-install-toolchain',
          'select-existing-toolchain',
        ],
        message: latestInstall.message ?? 'Latest toolchain install failed.',
      );
    }
    return const ToolchainRecoveryState(
      kind: ToolchainRecoveryStateKind.none,
      actionIds: <String>[],
    );
  }

  Future<ToolchainRuntimeResult> run({
    required ToolchainKind kind,
    ToolchainRequirement? requirement,
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
    String? standardInput,
  }) async {
    final catalog = await loadCatalog();
    return runtimeFor(catalog).run(
      kind: kind,
      requirement: requirement,
      arguments: arguments,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
      standardInput: standardInput,
    );
  }

  Future<ToolchainHealthReport> checkHealth({
    required ToolchainKind kind,
    ToolchainRequirement? requirement,
    List<String>? probeArguments,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final catalog = await loadCatalog();
    return runtimeFor(catalog).checkHealth(
      kind: kind,
      requirement: requirement,
      probeArguments: probeArguments,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }
}

class _ToolchainInstallRollbackResult {
  const _ToolchainInstallRollbackResult({
    required this.rolledBack,
    this.message,
  });

  final bool rolledBack;
  final String? message;
}
