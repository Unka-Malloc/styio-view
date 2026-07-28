part of '../shell_runtime_model.dart';

/// Registry-checked Agent IDE command dispatcher.
mixin ShellRuntimeAgentCommandDispatchFacade on ShellRuntimeFacadeHost {
  Future<bool> applyAgentIdeCommandSuggestion(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    final registeredCommand = VityoCommandRegistry.descriptorForName(
      suggestion.commandId,
    );
    if (registeredCommand == null) {
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message:
            'Agent command ${suggestion.commandId} skipped: command is not registered in the IDE command catalog.',
        metadata: <String, Object?>{
          'registered': false,
          'knownCommandCount': VityoCommandRegistry.commands.length,
          // TODO(agent-command-registry): include dynamic extension command ids
          // once extension-contributed commands can be safely invoked by agents.
        },
      );
      appendLog(_lastAgentIdeCommandResult!.message);
      return false;
    }

    switch (registeredCommand.id.name) {
      case 'save':
      case 'saveAll':
        return _agentCommandReceiptController.executeSave(suggestion);
      case 'openWorkspaceFile':
      case 'createWorkspaceFile':
      case 'renameWorkspaceFile':
      case 'deleteWorkspaceFile':
      case 'revealWorkspaceFile':
      case 'searchWorkspace':
      case 'renameSymbol':
        return _agentWorkspaceCommandController.apply(suggestion);
      case 'previewWorkspaceReplace':
      case 'applyWorkspaceReplace':
        return _agentWorkspaceReplaceCommandController.apply(suggestion);
      case 'applyQuickFix':
      case 'previewQuickFix':
        return _agentQuickFixCommandController.apply(suggestion);
      case 'nextDiagnostic':
      case 'previousDiagnostic':
        return _agentWorkspaceCommandController.apply(suggestion);
      case 'refreshLanguageService':
        return _languageRefreshCommandController.execute(
          suggestion: suggestion,
        );
      case 'refreshWorkspaceDiagnostics':
        final snapshot = await refreshWorkspaceDiagnostics();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: _workspaceDiagnosticsRuntimeController.available,
          message: _workspaceDiagnosticsRefreshMessage(snapshot),
          metadata: <String, Object?>{
            'workspaceDiagnostics': snapshot.toJson(),
          },
        );
        return _workspaceDiagnosticsRuntimeController.available;
      case 'refreshSourceControl':
      case 'previewSourceControlDiff':
      case 'stageSourceControl':
      case 'unstageSourceControl':
      case 'planSourceControlBranchSwitch':
      case 'planSourceControlCommitDraft':
        return _agentSourceControlCommandController.apply(suggestion);
      case 'collectAgentCodingCheckpoint':
      case 'collectProjectLanguageContext':
        return _agentContextCommandController.apply(suggestion);
      case 'retryAgentProvider':
      case 'replayAgentPrompt':
      case 'failoverAgentProvider':
        return _agentProviderRecoveryCommandController.apply(suggestion);
      case 'goToDefinition':
      case 'nextReference':
      case 'previousReference':
        return _agentWorkspaceCommandController.apply(suggestion);
      case 'toggleBreakpoint':
      case 'startDebugging':
      case 'stopDebugging':
      case 'continueDebugging':
      case 'stepOver':
      case 'selectDebugThread':
      case 'selectDebugStackFrame':
        return _agentDebugCommandController.apply(suggestion);
      case 'safeDelete':
      case 'inlineVariable':
        return _agentRefactorCommandController.apply(suggestion);
      case 'openSettings':
        return _agentSurfaceCommandController.apply(suggestion);
      case 'selectClangCppVersion':
        return _agentToolchainCommandController.apply(suggestion);
      case 'run':
        return _agentExecutionCommandController.apply(suggestion);
      case 'fetchDependencies':
      case 'vendorDependencies':
      case 'packProject':
      case 'preparePublish':
        return _agentProjectLifecycleCommandController.apply(suggestion);
      case 'useActiveCompiler':
      case 'pinActiveCompiler':
      case 'clearPinnedCompiler':
      case 'bootstrapStyioToolchain':
      case 'executeToolchainInstallPlan':
        return _agentToolchainCommandController.apply(suggestion);
      case 'refreshModules':
        return _agentContextCommandController.apply(suggestion);
      case 'showRuntime':
      case 'showAgent':
      case 'showDebug':
        return _agentSurfaceCommandController.apply(suggestion);
      case 'runBuild':
      case 'formatActiveDocument':
      case 'runStaticAnalysis':
      case 'runTests':
        return _agentNativeToolCommandController.apply(suggestion);
      case 'rerunFailedTests':
      case 'debugFailedTests':
      case 'runTestConfiguration':
      case 'debugTestConfiguration':
        return _agentTestingCommandController.apply(suggestion);
      default:
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command ${registeredCommand.id.name} skipped: registered command has no agent executor.',
          metadata: <String, Object?>{
            'registered': true,
            'commandCategory': registeredCommand.id.category.wireValue,
            // TODO(agent-command-execution): bind this registered command to an
            // explicit agent executor or mark it as UI-only in the registry.
          },
        );
        appendLog(_lastAgentIdeCommandResult!.message);
        return false;
    }
  }
}
