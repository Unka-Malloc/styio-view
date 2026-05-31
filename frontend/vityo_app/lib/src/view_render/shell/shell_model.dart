import '../../view_ide/commands/commands.dart';
import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/shell_runtime/shell_runtime.dart';

enum BottomSurfaceTab {
  runtime,
  commands,
  navigate,
  locations,
  definitions,
  typeDefinitions,
  outline,
  rename,
  symbols,
  usages,
  calls,
  search,
  problems,
  actions,
  agent,
  debug,
  settings,
}

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
      case AppCommandId.commandPalette:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.commands);
        return;
      case AppCommandId.quickOpen:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.navigate);
        return;
      case AppCommandId.showRecentLocations:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.locations);
        return;
      case AppCommandId.goToWorkspaceDefinition:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.definitions);
        return;
      case AppCommandId.goToWorkspaceTypeDefinition:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.typeDefinitions);
        return;
      case AppCommandId.navigateBack:
      case AppCommandId.navigateForward:
        await super.executeCommand(commandId);
        return;
      case AppCommandId.showWorkspaceOutline:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.outline);
        return;
      case AppCommandId.renameWorkspaceSymbol:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.rename);
        return;
      case AppCommandId.searchWorkspaceSymbols:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.symbols);
        return;
      case AppCommandId.findWorkspaceReferences:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.usages);
        return;
      case AppCommandId.showWorkspaceCallHierarchy:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.calls);
        return;
      case AppCommandId.save:
      case AppCommandId.run:
        await super.executeCommand(commandId);
        if (commandId == AppCommandId.run) {
          selectBottomTab(BottomSurfaceTab.runtime);
        }
        return;
      case AppCommandId.searchWorkspace:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.search);
        return;
      case AppCommandId.showWorkspaceProblems:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.problems);
        return;
      case AppCommandId.showWorkspaceCodeActions:
        await super.executeCommand(commandId);
        selectBottomTab(BottomSurfaceTab.actions);
        return;
      case AppCommandId.fetchDependencies:
      case AppCommandId.vendorDependencies:
      case AppCommandId.useActiveCompiler:
      case AppCommandId.pinActiveCompiler:
      case AppCommandId.clearPinnedCompiler:
      case AppCommandId.packProject:
      case AppCommandId.preparePublish:
      case AppCommandId.refreshModules:
        await super.executeCommand(commandId);
        return;
    }
  }
}
