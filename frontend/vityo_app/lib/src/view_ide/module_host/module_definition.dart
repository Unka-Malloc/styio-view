import '../platform/platform_target.dart';
import 'module_capability_matrix.dart';
import 'module_manifest.dart';

class ModuleDefinition {
  const ModuleDefinition({
    required this.manifest,
    required this.matrix,
  });

  final ModuleManifest manifest;
  final ModuleCapabilityMatrix matrix;

  ModuleCapabilityRule ruleFor(PlatformTarget target) {
    return matrix.ruleFor(target);
  }

  bool isVisibleOn(PlatformTarget target) {
    return matrix.isVisibleOn(target);
  }

  bool isMountedOn(PlatformTarget target) {
    return matrix.isMountedOn(target);
  }
}
