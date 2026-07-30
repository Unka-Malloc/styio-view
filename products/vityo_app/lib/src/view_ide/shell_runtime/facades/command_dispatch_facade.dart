part of '../shell_runtime_model.dart';

/// Exhaustive public command dispatcher backed by domain command controllers.
mixin ShellRuntimeCommandDispatchFacade on ShellRuntimeFacadeHost {
  Future<void> executeCommand(AppCommandId commandId) async {
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      appendLog(
        '${VityoCommandRegistry.descriptorFor(commandId).label} blocked: $blockedReason',
      );
      return;
    }

    switch (commandId) {
      case AppCommandId.save:
        await _workspacePersistenceController.executeActiveSave();
        return;
      case AppCommandId.saveAll:
        await saveAllWorkspaceFileChanges();
        return;
      case AppCommandId.refreshLanguageService:
        await _languageRefreshCommandController.execute();
        return;
      case AppCommandId.refreshWorkspaceDiagnostics:
        final snapshot = await refreshWorkspaceDiagnostics();
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: _workspaceDiagnosticsRuntimeController.available,
          message: _workspaceDiagnosticsRefreshMessage(snapshot),
          metadata: <String, Object?>{
            'workspaceDiagnostics': snapshot.toJson(),
          },
        );
        return;
      case AppCommandId.refreshSourceControl:
      case AppCommandId.previewSourceControlDiff:
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
      case AppCommandId.planSourceControlBranchSwitch:
      case AppCommandId.planSourceControlCommitDraft:
        await _agentSourceControlCommandController.executeOrdinary(commandId);
        return;
      case AppCommandId.collectAgentCodingCheckpoint:
      case AppCommandId.collectProjectLanguageContext:
        await _agentContextCommandController.executeOrdinary(commandId);
        return;
      case AppCommandId.retryAgentProvider:
      case AppCommandId.replayAgentPrompt:
        await _agentProviderRecoveryCommandController.apply(
          AgentIdeCommandSuggestion(commandId: commandId.name),
        );
        return;
      case AppCommandId.run:
        await _executionController.run(
          platformTarget: platformTarget,
          projectGraph: workspaceController.activeProject,
          adapterCapabilities: adapterCapabilities,
          document: editorController.document,
          selection: editorController.selection,
          activeFilePath: workspaceController.activeFilePath,
        );
        return;
      case AppCommandId.syncDependencies:
        await syncDependencies();
        return;
      case AppCommandId.vendorDependencies:
        await vendorDependencies();
        return;
      case AppCommandId.executeToolchainInstallPlan:
        await _agentToolchainCommandController.apply(
          AgentIdeCommandSuggestion(commandId: commandId.name),
        );
        return;
      case AppCommandId.packProject:
        await packProject();
        return;
      case AppCommandId.preparePublish:
        await preparePublish();
        return;
      case AppCommandId.nextDiagnostic:
      case AppCommandId.previousDiagnostic:
      case AppCommandId.goToDefinition:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
        await _editorNavigationCommandController.execute(commandId);
        return;
      case AppCommandId.toggleBreakpoint:
        toggleBreakpointAtSelection();
        return;
      case AppCommandId.startDebugging:
        await startDebugging();
        return;
      case AppCommandId.stopDebugging:
        await stopDebugging();
        return;
      case AppCommandId.continueDebugging:
        await continueDebugging();
        return;
      case AppCommandId.stepOver:
        await stepOver();
        return;
      case AppCommandId.previewQuickFix:
      case AppCommandId.applyQuickFix:
        await _editorQuickFixCommandController.execute(commandId);
        return;
      case AppCommandId.applyWorkspaceReplace:
        await _agentWorkspaceReplaceCommandController.apply(
          AgentIdeCommandSuggestion(commandId: commandId.name),
        );
        return;
      case AppCommandId.runBuild:
      case AppCommandId.formatActiveDocument:
      case AppCommandId.runStaticAnalysis:
      case AppCommandId.runTests:
        await _agentNativeToolCommandController.executeOrdinary(commandId);
        return;
      case AppCommandId.rerunFailedTests:
      case AppCommandId.debugFailedTests:
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
        await _agentTestingCommandController.executeOrdinary(commandId);
        return;
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
        _agentRefactorCommandController.executeEditorCommand(commandId);
        return;
      case AppCommandId.refreshModules:
        await _moduleController.refresh();
        return;
      default:
        _shellCommandFallbackController.execute(commandId);
        return;
    }
  }

  Future<void> executeCommandWithInput(AppCommandId commandId, String input) =>
      _shellInputCommandController.execute(commandId, input);

  String? blockedReasonForCommand(AppCommandId commandId) =>
      _backendCommandPolicyController.blockedReason(
        commandId: commandId,
        projectGraph: workspaceController.activeProject,
      );
}
