import '../platform/platform_target.dart';
import 'module_definition.dart';
import 'module_manifest.dart';

enum ModuleLifecycleAction { mount, leaveUnmounted, uninstall, blocked }

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

ModuleLifecyclePlan planModuleLifecycle({
  required ModuleDefinition module,
  required PlatformTarget platformTarget,
  bool installed = true,
  bool userEnabled = true,
  bool updateAvailable = false,
  bool uninstallRequested = false,
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
      reason: 'Optional module uninstall reclaims package, cache, and data.',
      reclaimPackage: true,
      reclaimCache: true,
      reclaimData: true,
    );
  }

  if (!installed) {
    return ModuleLifecyclePlan(
      moduleId: manifest.moduleId,
      action: ModuleLifecycleAction.leaveUnmounted,
      reason: 'Module is not installed.',
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
