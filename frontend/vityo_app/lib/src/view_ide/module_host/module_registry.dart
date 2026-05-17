import 'dart:convert';

import 'package:flutter/services.dart';

import '../platform/platform_target.dart';
import 'module_capability_matrix.dart';
import 'module_definition.dart';
import 'module_manifest.dart';

class ModuleRegistry {
  ModuleRegistry({
    required this.platformTarget,
    required List<ModuleDefinition> definitions,
  }) : _definitions = List<ModuleDefinition>.unmodifiable(definitions);

  final PlatformTarget platformTarget;
  final List<ModuleDefinition> _definitions;

  List<ModuleDefinition> get allModules => _definitions;

  List<ModuleDefinition> get visibleModules {
    return _definitions
        .where((definition) => definition.isVisibleOn(platformTarget))
        .toList(growable: false);
  }

  List<ModuleDefinition> get mountedModules {
    return visibleModules
        .where((definition) => definition.isMountedOn(platformTarget))
        .toList(growable: false);
  }

  List<ModuleDefinition> modulesForSlot(ModuleSlot slot) {
    return visibleModules
        .where((definition) => definition.manifest.slot == slot)
        .toList(growable: false);
  }

  ModuleDefinition? findById(String moduleId) {
    for (final definition in _definitions) {
      if (definition.manifest.moduleId == moduleId) {
        return definition;
      }
    }
    return null;
  }

  bool isMounted(String moduleId) {
    final definition = findById(moduleId);
    if (definition == null) {
      return false;
    }
    return definition.isMountedOn(platformTarget);
  }

  static Future<ModuleRegistry> loadFromAssets({
    required String indexAssetPath,
    required PlatformTarget platformTarget,
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final rawIndex = await assetBundle.loadString(indexAssetPath);
    final decodedIndex = Map<String, dynamic>.from(
      jsonDecode(rawIndex) as Map,
    );
    final rawEntries = List<Map<String, dynamic>>.from(
      (decodedIndex['modules'] as List).map(
        (entry) => Map<String, dynamic>.from(entry as Map),
      ),
    );

    final definitions = <ModuleDefinition>[];
    for (final entry in rawEntries) {
      final manifest = ModuleManifest.parse(
        await assetBundle.loadString(entry['manifest'] as String),
      );
      final matrix = ModuleCapabilityMatrix.parse(
        await assetBundle.loadString(entry['matrix'] as String),
      );
      definitions.add(ModuleDefinition(manifest: manifest, matrix: matrix));
    }

    return ModuleRegistry(
      platformTarget: platformTarget,
      definitions: definitions,
    );
  }
}
