import 'dart:convert';

import '../platform/platform_target.dart';

class ModuleCapabilityRule {
  const ModuleCapabilityRule({
    required this.supported,
    required this.visible,
    required this.installable,
    required this.mountedByDefault,
    required this.iosSafe,
    required this.distributionChannel,
    required this.note,
  });

  final bool supported;
  final bool visible;
  final bool installable;
  final bool mountedByDefault;
  final bool iosSafe;
  final String distributionChannel;
  final String note;

  factory ModuleCapabilityRule.fromJson(Map<String, dynamic> json) {
    return ModuleCapabilityRule(
      supported: json['supported'] as bool? ?? false,
      visible: json['visible'] as bool? ?? false,
      installable: json['installable'] as bool? ?? false,
      mountedByDefault: json['mountedByDefault'] as bool? ?? false,
      iosSafe: json['iosSafe'] as bool? ?? false,
      distributionChannel: json['distributionChannel'] as String? ?? 'unknown',
      note: json['note'] as String? ?? '',
    );
  }
}

class ModuleCapabilityMatrix {
  const ModuleCapabilityMatrix({
    required this.moduleId,
    required this.platforms,
  });

  final String moduleId;
  final Map<PlatformTarget, ModuleCapabilityRule> platforms;

  ModuleCapabilityRule ruleFor(PlatformTarget target) {
    return platforms[target] ??
        const ModuleCapabilityRule(
          supported: false,
          visible: false,
          installable: false,
          mountedByDefault: false,
          iosSafe: false,
          distributionChannel: 'unknown',
          note: 'No platform rule found.',
        );
  }

  bool isVisibleOn(PlatformTarget target) => ruleFor(target).visible;

  bool isMountedOn(PlatformTarget target) {
    final rule = ruleFor(target);
    return rule.supported && rule.visible && rule.mountedByDefault;
  }

  factory ModuleCapabilityMatrix.fromJson(Map<String, dynamic> json) {
    final rawPlatforms =
        Map<String, dynamic>.from(json['platforms'] as Map? ?? {});
    final platforms = <PlatformTarget, ModuleCapabilityRule>{};

    for (final entry in rawPlatforms.entries) {
      platforms[platformTargetFromWireValue(entry.key)] =
          ModuleCapabilityRule.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return ModuleCapabilityMatrix(
      moduleId: json['moduleId'] as String,
      platforms: platforms,
    );
  }

  static ModuleCapabilityMatrix parse(String source) {
    return ModuleCapabilityMatrix.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );
  }
}
