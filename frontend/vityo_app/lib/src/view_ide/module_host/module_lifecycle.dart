import '../platform/platform_target.dart';
import 'module_definition.dart';
import 'module_manifest.dart';
import 'module_registry.dart';

enum ModuleLifecycleAction { install, mount, leaveUnmounted, uninstall, blocked }

enum ModuleUninstallDataPolicy { platformDefault, clearData, keepData }

enum ModuleTrustState { trusted, untrusted, blocked }

extension ModuleTrustStateX on ModuleTrustState {
  String get wireValue {
    return switch (this) {
      ModuleTrustState.trusted => 'trusted',
      ModuleTrustState.untrusted => 'untrusted',
      ModuleTrustState.blocked => 'blocked',
    };
  }
}

class ModuleLifecyclePlan {
  const ModuleLifecyclePlan({
    required this.moduleId,
    required this.action,
    required this.reason,
    this.stageUpdate = false,
    this.reclaimPackage = false,
    this.reclaimCache = false,
    this.reclaimData = false,
  });

  final String moduleId;
  final ModuleLifecycleAction action;
  final String reason;
  final bool stageUpdate;
  final bool reclaimPackage;
  final bool reclaimCache;
  final bool reclaimData;
}

class ModuleLifecycleState {
  const ModuleLifecycleState({
    required this.moduleId,
    this.installed = true,
    this.enabled = true,
    this.trustState = ModuleTrustState.trusted,
    this.updateAvailable = false,
    this.message = '',
  });

  final String moduleId;
  final bool installed;
  final bool enabled;
  final ModuleTrustState trustState;
  final bool updateAvailable;
  final String message;

  bool get trusted => trustState == ModuleTrustState.trusted;
  bool get canMount => installed && enabled && trusted;

  ModuleLifecycleState copyWith({
    bool? installed,
    bool? enabled,
    ModuleTrustState? trustState,
    bool? updateAvailable,
    String? message,
  }) {
    return ModuleLifecycleState(
      moduleId: moduleId,
      installed: installed ?? this.installed,
      enabled: enabled ?? this.enabled,
      trustState: trustState ?? this.trustState,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      message: message ?? this.message,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'moduleId': moduleId,
      'installed': installed,
      'enabled': enabled,
      'trustState': trustState.wireValue,
      'trusted': trusted,
      'canMount': canMount,
      'updateAvailable': updateAvailable,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class ModuleWorkspaceReference {
  const ModuleWorkspaceReference({
    required this.referenceId,
    required this.moduleId,
    this.path,
  });

  final String referenceId;
  final String moduleId;
  final String? path;
}

class ModuleUninstallReconciliation {
  const ModuleUninstallReconciliation({
    required this.registry,
    required this.removedModuleIds,
    required this.removedWorkspaceReferences,
    required this.retainedWorkspaceReferences,
  });

  final ModuleRegistry registry;
  final List<String> removedModuleIds;
  final List<ModuleWorkspaceReference> removedWorkspaceReferences;
  final List<ModuleWorkspaceReference> retainedWorkspaceReferences;
}

class ModuleStagedUpdateResolution {
  const ModuleStagedUpdateResolution({
    required this.registry,
    required this.pendingRestartModuleIds,
    required this.activatedModuleIds,
    required this.blockedModuleIds,
  });

  final ModuleRegistry registry;
  final List<String> pendingRestartModuleIds;
  final List<String> activatedModuleIds;
  final List<String> blockedModuleIds;

  bool get requiresRestart => pendingRestartModuleIds.isNotEmpty;
}

ModuleLifecycleState defaultModuleLifecycleState(ModuleDefinition module) {
  return ModuleLifecycleState(
    moduleId: module.manifest.moduleId,
    installed: true,
    enabled: module.manifest.enabledByDefault,
  );
}

ModuleLifecyclePlan planModuleLifecycle({
  required ModuleDefinition module,
  required PlatformTarget platformTarget,
  bool installed = true,
  bool userEnabled = true,
  ModuleTrustState trustState = ModuleTrustState.trusted,
  bool updateAvailable = false,
  bool uninstallRequested = false,
  ModuleUninstallDataPolicy uninstallDataPolicy =
      ModuleUninstallDataPolicy.platformDefault,
}) {
  final manifest = module.manifest;
  final rule = module.ruleFor(platformTarget);

  if (uninstallRequested) {
    if (manifest.kind == ModuleKind.core) {
      return ModuleLifecyclePlan(
        moduleId: manifest.moduleId,
        action: ModuleLifecycleAction.blocked,
        reason: 'Core modules cannot be uninstalled.',
      );
    }
    return ModuleLifecyclePlan(
      moduleId: manifest.moduleId,
      action: ModuleLifecycleAction.uninstall,
      reason: _uninstallReason(platformTarget, uninstallDataPolicy),
      reclaimPackage: true,
      reclaimCache: true,
      reclaimData: _shouldReclaimData(platformTarget, uninstallDataPolicy),
    );
  }

  if (!installed) {
    return ModuleLifecyclePlan(
      moduleId: manifest.moduleId,
      action: ModuleLifecycleAction.leaveUnmounted,
      reason: 'Module is not installed.',
    );
  }

  if (trustState != ModuleTrustState.trusted) {
    return ModuleLifecyclePlan(
      moduleId: manifest.moduleId,
      action: ModuleLifecycleAction.blocked,
      reason: trustState == ModuleTrustState.blocked
          ? 'Module trust policy blocks activation.'
          : 'Module requires user trust before activation.',
    );
  }

  if (!rule.supported || !rule.visible) {
    return ModuleLifecyclePlan(
      moduleId: manifest.moduleId,
      action: ModuleLifecycleAction.blocked,
      reason: rule.note.isEmpty
          ? 'Module is not supported on ${platformTarget.label}.'
          : rule.note,
    );
  }

  final shouldMount =
      manifest.kind == ModuleKind.core ||
      (userEnabled && manifest.enabledByDefault && rule.mountedByDefault);
  return ModuleLifecyclePlan(
    moduleId: manifest.moduleId,
    action: shouldMount
        ? ModuleLifecycleAction.mount
        : ModuleLifecycleAction.leaveUnmounted,
    reason: shouldMount
        ? 'Module is supported and selected for this platform.'
        : 'Module remains installed but unmounted until selected.',
    stageUpdate: updateAvailable,
  );
}

ModuleLifecyclePlan planOptionalModuleInstall({
  required ModuleRegistry registry,
  required String moduleId,
  required PlatformTarget platformTarget,
}) {
  final module = registry.findById(moduleId);
  if (module == null) {
    return ModuleLifecyclePlan(
      moduleId: moduleId,
      action: ModuleLifecycleAction.blocked,
      reason: 'Module is not registered.',
    );
  }

  final manifest = module.manifest;
  if (manifest.kind == ModuleKind.core) {
    return ModuleLifecyclePlan(
      moduleId: moduleId,
      action: ModuleLifecycleAction.blocked,
      reason: 'Core modules are installed with the product.',
    );
  }

  final rule = module.ruleFor(platformTarget);
  if (!rule.supported || !rule.visible) {
    return ModuleLifecyclePlan(
      moduleId: moduleId,
      action: ModuleLifecycleAction.blocked,
      reason: rule.note.isEmpty
          ? 'Module is not supported on ${platformTarget.label}.'
          : rule.note,
    );
  }
  if (!rule.installable) {
    return ModuleLifecyclePlan(
      moduleId: moduleId,
      action: ModuleLifecycleAction.blocked,
      reason:
          'Module is visible but not user-installable on ${platformTarget.label}.',
    );
  }
  if (!module.isDistributionAllowedOn(platformTarget)) {
    return ModuleLifecyclePlan(
      moduleId: moduleId,
      action: ModuleLifecycleAction.blocked,
      reason:
          'Module distribution policy blocks installation on ${platformTarget.label}.',
    );
  }

  return ModuleLifecyclePlan(
    moduleId: moduleId,
    action: ModuleLifecycleAction.install,
    reason: 'Optional module can be installed on ${platformTarget.label}.',
  );
}

ModuleUninstallReconciliation reconcileModuleUninstall({
  required ModuleRegistry registry,
  required Iterable<String> uninstalledModuleIds,
  Iterable<ModuleWorkspaceReference> workspaceReferences = const [],
}) {
  final removedIds = uninstalledModuleIds.toSet();
  final removedReferences = <ModuleWorkspaceReference>[];
  final retainedReferences = <ModuleWorkspaceReference>[];

  for (final reference in workspaceReferences) {
    if (removedIds.contains(reference.moduleId)) {
      removedReferences.add(reference);
    } else {
      retainedReferences.add(reference);
    }
  }

  return ModuleUninstallReconciliation(
    registry: registry.withoutModules(removedIds),
    removedModuleIds: List<String>.unmodifiable(removedIds),
    removedWorkspaceReferences: List<ModuleWorkspaceReference>.unmodifiable(
      removedReferences,
    ),
    retainedWorkspaceReferences: List<ModuleWorkspaceReference>.unmodifiable(
      retainedReferences,
    ),
  );
}

ModuleStagedUpdateResolution resolveStagedModuleUpdates({
  required ModuleRegistry runningRegistry,
  required Iterable<ModuleDefinition> stagedModules,
  required bool restartCompleted,
}) {
  final stagedById = <String, ModuleDefinition>{};
  for (final module in stagedModules) {
    if (runningRegistry.findById(module.manifest.moduleId) != null) {
      stagedById[module.manifest.moduleId] = module;
    }
  }

  if (!restartCompleted) {
    return ModuleStagedUpdateResolution(
      registry: runningRegistry,
      pendingRestartModuleIds: List<String>.unmodifiable(stagedById.keys),
      activatedModuleIds: const <String>[],
      blockedModuleIds: const <String>[],
    );
  }

  final activated = <ModuleDefinition>[];
  final blockedIds = <String>[];
  for (final module in stagedById.values) {
    if (module.isVisibleOn(runningRegistry.platformTarget)) {
      activated.add(module);
    } else {
      blockedIds.add(module.manifest.moduleId);
    }
  }

  return ModuleStagedUpdateResolution(
    registry: runningRegistry.withReplacedModules(activated),
    pendingRestartModuleIds: const <String>[],
    activatedModuleIds: List<String>.unmodifiable(
      activated.map((module) => module.manifest.moduleId),
    ),
    blockedModuleIds: List<String>.unmodifiable(blockedIds),
  );
}

bool _shouldReclaimData(
  PlatformTarget platformTarget,
  ModuleUninstallDataPolicy policy,
) {
  switch (policy) {
    case ModuleUninstallDataPolicy.clearData:
      return true;
    case ModuleUninstallDataPolicy.keepData:
      return false;
    case ModuleUninstallDataPolicy.platformDefault:
      return platformTarget == PlatformTarget.android ||
          platformTarget == PlatformTarget.ios;
  }
}

String _uninstallReason(
  PlatformTarget platformTarget,
  ModuleUninstallDataPolicy policy,
) {
  if (_shouldReclaimData(platformTarget, policy)) {
    return 'Optional module uninstall reclaims package, cache, and data.';
  }
  return 'Optional module uninstall reclaims package and cache while retaining user data.';
}
