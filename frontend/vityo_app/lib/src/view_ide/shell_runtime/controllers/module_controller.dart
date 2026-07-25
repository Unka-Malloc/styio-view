import 'package:flutter/foundation.dart';

import '../../module_host/module_host.dart';
import '../../platform/platform.dart';

/// Owns module-host projections and refresh behavior.
final class ModuleController extends ChangeNotifier {
  ModuleController({
    required this.registry,
    required this.nativeModuleLoader,
    required this.platformTarget,
    required this.refreshProjectGraph,
    required this.log,
  });

  final ModuleRegistry registry;
  final NativeModuleLoader nativeModuleLoader;
  final PlatformTarget platformTarget;
  final Future<void> Function(String reason) refreshProjectGraph;
  final void Function(String message) log;

  List<ModuleDefinition> get mountedModules => registry.mountedModules;
  List<ModuleDefinition> get visibleModules => registry.visibleModules;

  Future<void> refresh() async {
    log('Module host refresh requested on ${platformTarget.label}.');
    await refreshProjectGraph(
      'manual refresh requested from the shell command registry',
    );
    final bridge = await nativeModuleLoader.describe('local.runtime.desktop');
    log(
      'Native bridge ${bridge.moduleId}: ${bridge.state.name} '
      '(${bridge.detail})',
    );
    notifyListeners();
  }

  Future<Map<String, Object?>> agentRefreshMetadata() async {
    final bridge = await nativeModuleLoader.describe('local.runtime.desktop');
    return <String, Object?>{
      'visibleModuleCount': visibleModules.length,
      'mountedModuleCount': mountedModules.length,
      'visibleModuleIds': visibleModules
          .map((module) => module.manifest.moduleId)
          .toList(growable: false),
      'mountedModuleIds': mountedModules
          .map((module) => module.manifest.moduleId)
          .toList(growable: false),
      'nativeBridge': <String, Object?>{
        'moduleId': bridge.moduleId,
        'state': bridge.state.name,
        'detail': bridge.detail,
      },
    };
  }
}
