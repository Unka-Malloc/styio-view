import '../../view_ide/commands/commands.dart';
import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/shell_runtime/shell_runtime.dart';

enum BottomSurfaceTab { runtime, agent, debug, settings }

class ShellModel extends ShellRuntimeModel {
  ShellModel({
    required super.platformTarget,
    required super.supplementalAdapterCapabilities,
    required super.projectGraphAdapter,
    required super.workspaceController,
    required super.workspaceDocumentStore,
    required super.moduleRegistry,
    required super.nativeModuleLoader,
    required super.editorController,
    required super.executionAdapter,
    required super.executionAdapterFactory,
    required super.runtimeEventAdapter,
    required super.dependencySourceAdapter,
    required super.deploymentAdapter,
    required super.toolchainManagementAdapter,
    super.toolchainManager,
    super.editorSessionDataStore,
    super.editorSessionWorkspaceId,
    super.languageServiceStatus,
    super.toolchainStatusReport,
  });

  BottomSurfaceTab _activeBottomTab = BottomSurfaceTab.runtime;

  BottomSurfaceTab get activeBottomTab => _activeBottomTab;

  void selectBottomTab(BottomSurfaceTab tab) {
    if (_activeBottomTab == tab) {
      return;
    }
    _activeBottomTab = tab;
    appendLog('Bottom surface switched to ${tab.name}.');
  }

  @override
  Future<void> handleToolchainRecoveryAction(
    ToolchainRecoveryAction action,
  ) async {
    await super.handleToolchainRecoveryAction(action);
    if (action.id == 'show-toolchain-logs') {
      selectBottomTab(BottomSurfaceTab.debug);
    }
  }

  @override
  Future<void> executeCommand(AppCommandId commandId) async {
    switch (commandId) {
      case AppCommandId.showRuntime:
        selectBottomTab(BottomSurfaceTab.runtime);
        return;
      case AppCommandId.showAgent:
        selectBottomTab(BottomSurfaceTab.agent);
        return;
      case AppCommandId.showDebug:
        selectBottomTab(BottomSurfaceTab.debug);
        return;
      case AppCommandId.openSettings:
        selectBottomTab(BottomSurfaceTab.settings);
        appendLog('Settings surface opened.');
        return;
      case AppCommandId.save:
      case AppCommandId.run:
      case AppCommandId.fetchDependencies:
      case AppCommandId.vendorDependencies:
      case AppCommandId.useActiveCompiler:
      case AppCommandId.pinActiveCompiler:
      case AppCommandId.clearPinnedCompiler:
      case AppCommandId.packProject:
      case AppCommandId.preparePublish:
      case AppCommandId.refreshModules:
        await super.executeCommand(commandId);
        if (commandId == AppCommandId.run) {
          selectBottomTab(BottomSurfaceTab.runtime);
        }
        return;
    }
  }
}
