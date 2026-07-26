import '../module_host/module_definition.dart';
import '../module_host/module_manifest.dart';

class RuntimeSurfaceFeatureEntry {
  const RuntimeSurfaceFeatureEntry({
    required this.moduleId,
    required this.displayName,
    required this.version,
    required this.slot,
    required this.entrypoint,
  });

  final String moduleId;
  final String displayName;
  final String version;
  final ModuleSlot slot;
  final String entrypoint;

  String get featureKey => '${slot.wireValue}:$moduleId';
}

List<RuntimeSurfaceFeatureEntry> runtimeSurfaceFeatureEntriesFor(
  Iterable<ModuleDefinition> mountedModules,
) {
  return mountedModules
      .where(_isRuntimeSurfaceModule)
      .map(
        (module) => RuntimeSurfaceFeatureEntry(
          moduleId: module.manifest.moduleId,
          displayName: module.manifest.displayName,
          version: module.manifest.version,
          slot: module.manifest.slot,
          entrypoint: module.manifest.entrypoint,
        ),
      )
      .toList(growable: false);
}

bool _isRuntimeSurfaceModule(ModuleDefinition module) {
  return switch (module.manifest.slot) {
    ModuleSlot.runtimeSurface ||
    ModuleSlot.localRuntime ||
    ModuleSlot.cloudRuntime ||
    ModuleSlot.debugTools => true,
    _ => false,
  };
}
