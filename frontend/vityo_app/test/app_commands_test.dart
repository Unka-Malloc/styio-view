import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';

void main() {
  test('command registry exposes primary command strip in mainline order', () {
    expect(
      StyioCommandRegistry.primaryCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.save,
        AppCommandId.saveAll,
        AppCommandId.run,
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
        AppCommandId.refreshModules,
      ],
    );
  });

  test(
    'command registry resolves descriptors and shortcuts for source ops',
    () {
      final save = StyioCommandRegistry.descriptorFor(AppCommandId.save);
      final fetch = StyioCommandRegistry.descriptorFor(
        AppCommandId.fetchDependencies,
      );
      final vendor = StyioCommandRegistry.descriptorFor(
        AppCommandId.vendorDependencies,
      );
      final saveAll = StyioCommandRegistry.descriptorFor(AppCommandId.saveAll);
      final nextDiagnostic = StyioCommandRegistry.descriptorFor(
        AppCommandId.nextDiagnostic,
      );
      final previousDiagnostic = StyioCommandRegistry.descriptorFor(
        AppCommandId.previousDiagnostic,
      );
      final applyQuickFix = StyioCommandRegistry.descriptorFor(
        AppCommandId.applyQuickFix,
      );
      final previewQuickFix = StyioCommandRegistry.descriptorFor(
        AppCommandId.previewQuickFix,
      );
      final refreshLanguageService = StyioCommandRegistry.descriptorFor(
        AppCommandId.refreshLanguageService,
      );
      final refreshWorkspaceDiagnostics = StyioCommandRegistry.descriptorFor(
        AppCommandId.refreshWorkspaceDiagnostics,
      );
      final openWorkspaceFile = StyioCommandRegistry.descriptorFor(
        AppCommandId.openWorkspaceFile,
      );
      final createWorkspaceFile = StyioCommandRegistry.descriptorFor(
        AppCommandId.createWorkspaceFile,
      );
      final renameWorkspaceFile = StyioCommandRegistry.descriptorFor(
        AppCommandId.renameWorkspaceFile,
      );
      final deleteWorkspaceFile = StyioCommandRegistry.descriptorFor(
        AppCommandId.deleteWorkspaceFile,
      );
      final revealWorkspaceFile = StyioCommandRegistry.descriptorFor(
        AppCommandId.revealWorkspaceFile,
      );
      final searchWorkspace = StyioCommandRegistry.descriptorFor(
        AppCommandId.searchWorkspace,
      );
      final previewWorkspaceReplace = StyioCommandRegistry.descriptorFor(
        AppCommandId.previewWorkspaceReplace,
      );
      final applyWorkspaceReplace = StyioCommandRegistry.descriptorFor(
        AppCommandId.applyWorkspaceReplace,
      );
      final runBuild = StyioCommandRegistry.descriptorFor(
        AppCommandId.runBuild,
      );
      final formatActiveDocument = StyioCommandRegistry.descriptorFor(
        AppCommandId.formatActiveDocument,
      );
      final runStaticAnalysis = StyioCommandRegistry.descriptorFor(
        AppCommandId.runStaticAnalysis,
      );
      final runTests = StyioCommandRegistry.descriptorFor(
        AppCommandId.runTests,
      );
      final toggleBreakpoint = StyioCommandRegistry.descriptorFor(
        AppCommandId.toggleBreakpoint,
      );
      final startDebugging = StyioCommandRegistry.descriptorFor(
        AppCommandId.startDebugging,
      );
      final stopDebugging = StyioCommandRegistry.descriptorFor(
        AppCommandId.stopDebugging,
      );
      final stepOver = StyioCommandRegistry.descriptorFor(
        AppCommandId.stepOver,
      );
      final selectDebugThread = StyioCommandRegistry.descriptorFor(
        AppCommandId.selectDebugThread,
      );
      final selectDebugStackFrame = StyioCommandRegistry.descriptorFor(
        AppCommandId.selectDebugStackFrame,
      );
      final goToDefinition = StyioCommandRegistry.descriptorFor(
        AppCommandId.goToDefinition,
      );
      final nextReference = StyioCommandRegistry.descriptorFor(
        AppCommandId.nextReference,
      );
      final previousReference = StyioCommandRegistry.descriptorFor(
        AppCommandId.previousReference,
      );
      final renameSymbol = StyioCommandRegistry.descriptorFor(
        AppCommandId.renameSymbol,
      );
      final safeDelete = StyioCommandRegistry.descriptorFor(
        AppCommandId.safeDelete,
      );
      final inlineVariable = StyioCommandRegistry.descriptorFor(
        AppCommandId.inlineVariable,
      );
      final selectClangCppVersion = StyioCommandRegistry.descriptorFor(
        AppCommandId.selectClangCppVersion,
      );
      final previewSourceControlDiff = StyioCommandRegistry.descriptorFor(
        AppCommandId.previewSourceControlDiff,
      );
      final stageSourceControl = StyioCommandRegistry.descriptorFor(
        AppCommandId.stageSourceControl,
      );
      final unstageSourceControl = StyioCommandRegistry.descriptorFor(
        AppCommandId.unstageSourceControl,
      );
      final planSourceControlBranchSwitch = StyioCommandRegistry.descriptorFor(
        AppCommandId.planSourceControlBranchSwitch,
      );
      final planSourceControlCommitDraft = StyioCommandRegistry.descriptorFor(
        AppCommandId.planSourceControlCommitDraft,
      );
      final collectAgentCodingCheckpoint = StyioCommandRegistry.descriptorFor(
        AppCommandId.collectAgentCodingCheckpoint,
      );
      final collectProjectLanguageContext = StyioCommandRegistry.descriptorFor(
        AppCommandId.collectProjectLanguageContext,
      );
      final retryAgentProvider = StyioCommandRegistry.descriptorFor(
        AppCommandId.retryAgentProvider,
      );
      final failoverAgentProvider = StyioCommandRegistry.descriptorFor(
        AppCommandId.failoverAgentProvider,
      );
      final replayAgentPrompt = StyioCommandRegistry.descriptorFor(
        AppCommandId.replayAgentPrompt,
      );

      expect(save.label, 'Save');
      expect(save.shortcutHint, 'Cmd/Ctrl+S');
      expect(save.category, AppCommandCategory.persistence);
      expect(save.primary, isTrue);
      expect(save.shortcuts, hasLength(2));

      expect(fetch.label, 'Fetch');
      expect(fetch.shortcutHint, 'Cmd/Ctrl+Shift+F');
      expect(fetch.primary, isTrue);
      expect(fetch.shortcuts, hasLength(2));

      expect(vendor.label, 'Vendor');
      expect(vendor.shortcutHint, 'Cmd/Ctrl+Shift+V');
      expect(vendor.primary, isTrue);
      expect(vendor.shortcuts, hasLength(2));

      expect(saveAll.label, 'Save All');
      expect(saveAll.shortcutHint, 'Cmd/Ctrl+Shift+S');
      expect(saveAll.primary, isTrue);
      expect(saveAll.shortcuts, hasLength(2));

      expect(nextDiagnostic.label, 'Next Diagnostic');
      expect(nextDiagnostic.shortcutHint, 'F8');
      expect(nextDiagnostic.shortcuts, hasLength(1));

      expect(previousDiagnostic.label, 'Previous Diagnostic');
      expect(previousDiagnostic.shortcutHint, 'Shift+F8');
      expect(previousDiagnostic.shortcuts, hasLength(1));

      expect(applyQuickFix.label, 'Quick Fix');
      expect(applyQuickFix.shortcutHint, 'Cmd/Ctrl+.');
      expect(applyQuickFix.shortcuts, hasLength(2));
      expect(previewQuickFix.label, 'Preview Quick Fix');
      expect(previewQuickFix.shortcutHint, 'Route');
      expect(previewQuickFix.requiresInput, isFalse);

      expect(refreshLanguageService.label, 'Refresh Language Service');
      expect(refreshLanguageService.shortcutHint, 'Route');
      expect(refreshLanguageService.requiresInput, isFalse);
      expect(
        refreshWorkspaceDiagnostics.label,
        'Refresh Workspace Diagnostics',
      );
      expect(refreshWorkspaceDiagnostics.shortcutHint, 'Route');
      expect(refreshWorkspaceDiagnostics.requiresInput, isFalse);

      expect(openWorkspaceFile.label, 'Open Workspace File');
      expect(openWorkspaceFile.category, AppCommandCategory.navigation);
      expect(openWorkspaceFile.shortcutHint, 'Route');
      expect(openWorkspaceFile.requiresInput, isTrue);
      expect(openWorkspaceFile.inputLabel, 'Workspace file path');
      expect(createWorkspaceFile.label, 'Create Workspace File');
      expect(createWorkspaceFile.category, AppCommandCategory.workspace);
      expect(createWorkspaceFile.requiresInput, isTrue);
      expect(createWorkspaceFile.inputLabel, 'New workspace file path');
      expect(renameWorkspaceFile.label, 'Rename Workspace File');
      expect(renameWorkspaceFile.category, AppCommandCategory.workspace);
      expect(renameWorkspaceFile.inputLabel, 'Current path -> next path');
      expect(deleteWorkspaceFile.label, 'Delete Workspace File');
      expect(deleteWorkspaceFile.inputLabel, 'Workspace file path');
      expect(revealWorkspaceFile.label, 'Reveal Workspace File');
      expect(revealWorkspaceFile.inputLabel, 'Workspace file path');

      expect(searchWorkspace.label, 'Search Workspace');
      expect(searchWorkspace.category, AppCommandCategory.navigation);
      expect(searchWorkspace.shortcutHint, 'Route');
      expect(searchWorkspace.requiresInput, isTrue);
      expect(searchWorkspace.inputLabel, 'Search query');
      expect(previewWorkspaceReplace.label, 'Preview Workspace Replace');
      expect(previewWorkspaceReplace.category, AppCommandCategory.navigation);
      expect(previewWorkspaceReplace.requiresInput, isTrue);
      expect(previewWorkspaceReplace.inputLabel, 'Search query -> replacement');
      expect(applyWorkspaceReplace.label, 'Apply Workspace Replace');
      expect(applyWorkspaceReplace.category, AppCommandCategory.navigation);
      expect(applyWorkspaceReplace.requiresInput, isFalse);

      expect(runBuild.label, 'Run Build');
      expect(runBuild.category, AppCommandCategory.execution);
      expect(runBuild.shortcutHint, 'Route');
      expect(formatActiveDocument.label, 'Format Active Document');
      expect(formatActiveDocument.shortcutHint, 'Route');
      expect(runStaticAnalysis.label, 'Run Static Analysis');
      expect(runStaticAnalysis.shortcutHint, 'Route');
      expect(runTests.label, 'Run Tests');
      expect(runTests.shortcutHint, 'Route');
      expect(toggleBreakpoint.label, 'Toggle Breakpoint');
      expect(toggleBreakpoint.shortcutHint, 'F9');
      expect(startDebugging.label, 'Start Debugging');
      expect(startDebugging.shortcutHint, 'F5');
      expect(stopDebugging.label, 'Stop Debugging');
      expect(stopDebugging.shortcutHint, 'Shift+F5');
      expect(stepOver.label, 'Step Over');
      expect(stepOver.shortcutHint, 'F10');
      expect(selectDebugThread.label, 'Select Debug Thread');
      expect(selectDebugThread.shortcutHint, 'Route');
      expect(selectDebugThread.requiresInput, isTrue);
      expect(selectDebugThread.inputLabel, 'DAP thread id');
      expect(selectDebugStackFrame.label, 'Select Debug Stack Frame');
      expect(selectDebugStackFrame.shortcutHint, 'Route');
      expect(selectDebugStackFrame.requiresInput, isTrue);
      expect(selectDebugStackFrame.inputLabel, 'DAP stack frame id');

      expect(goToDefinition.label, 'Go to Definition');
      expect(goToDefinition.shortcutHint, 'F12');
      expect(goToDefinition.shortcuts, hasLength(1));

      expect(nextReference.label, 'Next Reference');
      expect(nextReference.shortcutHint, 'Shift+F12');
      expect(nextReference.shortcuts, hasLength(1));

      expect(previousReference.label, 'Previous Reference');
      expect(previousReference.shortcutHint, 'Cmd/Ctrl+Shift+F12');
      expect(previousReference.shortcuts, hasLength(2));

      expect(renameSymbol.label, 'Rename Symbol');
      expect(renameSymbol.shortcutHint, 'Route');
      expect(renameSymbol.requiresInput, isTrue);
      expect(renameSymbol.inputLabel, 'New symbol name');

      expect(safeDelete.label, 'Safe Delete');
      expect(safeDelete.shortcutHint, 'Route');
      expect(safeDelete.requiresInput, isFalse);
      expect(safeDelete.shortcuts, isEmpty);

      expect(inlineVariable.label, 'Inline Variable');
      expect(inlineVariable.shortcutHint, 'Route');
      expect(inlineVariable.shortcuts, isEmpty);

      expect(selectClangCppVersion.label, 'Select Clang/C++');
      expect(selectClangCppVersion.shortcutHint, 'Route');
      expect(selectClangCppVersion.requiresInput, isTrue);
      expect(
        selectClangCppVersion.inputLabel,
        'Clang/C++ version id and optional C++ standard',
      );

      expect(previewSourceControlDiff.label, 'Preview Source Control Diff');
      expect(previewSourceControlDiff.shortcutHint, 'Route');
      expect(previewSourceControlDiff.requiresInput, isTrue);
      expect(previewSourceControlDiff.inputLabel, 'Changed file path');
      expect(stageSourceControl.label, 'Stage Source Control Paths');
      expect(stageSourceControl.category, AppCommandCategory.sourceControl);
      expect(stageSourceControl.requiresInput, isTrue);
      expect(stageSourceControl.inputLabel, 'Changed file path(s)');
      expect(unstageSourceControl.label, 'Unstage Source Control Paths');
      expect(unstageSourceControl.category, AppCommandCategory.sourceControl);
      expect(unstageSourceControl.requiresInput, isTrue);
      expect(unstageSourceControl.inputLabel, 'Changed file path(s)');
      expect(
        planSourceControlBranchSwitch.label,
        'Plan Source Control Branch Switch',
      );
      expect(
        planSourceControlBranchSwitch.category,
        AppCommandCategory.sourceControl,
      );
      expect(planSourceControlBranchSwitch.requiresInput, isTrue);
      expect(planSourceControlBranchSwitch.inputLabel, 'Target branch');
      expect(
        planSourceControlCommitDraft.label,
        'Plan Source Control Commit Draft',
      );
      expect(
        planSourceControlCommitDraft.category,
        AppCommandCategory.sourceControl,
      );
      expect(planSourceControlCommitDraft.requiresInput, isTrue);
      expect(
        planSourceControlCommitDraft.inputLabel,
        'Commit message or message -> path(s)',
      );

      expect(collectAgentCodingCheckpoint.label, 'Collect Coding Checkpoint');
      expect(collectAgentCodingCheckpoint.shortcutHint, 'Route');
      expect(collectAgentCodingCheckpoint.requiresInput, isFalse);
      expect(
        collectProjectLanguageContext.label,
        'Collect Project Language Context',
      );
      expect(collectProjectLanguageContext.shortcutHint, 'Route');
      expect(collectProjectLanguageContext.requiresInput, isFalse);
      expect(retryAgentProvider.label, 'Retry Agent Provider');
      expect(retryAgentProvider.category, AppCommandCategory.agentCoding);
      expect(retryAgentProvider.requiresInput, isFalse);
      expect(failoverAgentProvider.label, 'Fail Over Agent Provider');
      expect(failoverAgentProvider.category, AppCommandCategory.agentCoding);
      expect(failoverAgentProvider.requiresInput, isTrue);
      expect(failoverAgentProvider.inputLabel, 'Agent provider profile id');
      expect(replayAgentPrompt.label, 'Replay Agent Prompt');
      expect(replayAgentPrompt.category, AppCommandCategory.agentCoding);
      expect(replayAgentPrompt.requiresInput, isFalse);
    },
  );

  test('command registry exposes editor assist command groups', () {
    expect(
      StyioCommandRegistry.commandsForCategory(
        AppCommandCategory.navigation,
      ).map((command) => command.id),
      <AppCommandId>[
        AppCommandId.goToDefinition,
        AppCommandId.openWorkspaceFile,
        AppCommandId.searchWorkspace,
        AppCommandId.previewWorkspaceReplace,
        AppCommandId.applyWorkspaceReplace,
        AppCommandId.nextReference,
        AppCommandId.previousReference,
      ],
    );
    expect(
      StyioCommandRegistry.persistenceCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.save, AppCommandId.saveAll],
    );
    expect(
      StyioCommandRegistry.diagnosticCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.nextDiagnostic,
        AppCommandId.previousDiagnostic,
        AppCommandId.applyQuickFix,
        AppCommandId.previewQuickFix,
        AppCommandId.refreshWorkspaceDiagnostics,
      ],
    );
    expect(
      StyioCommandRegistry.languageServiceCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.refreshLanguageService],
    );
    expect(
      StyioCommandRegistry.navigationCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.goToDefinition,
        AppCommandId.openWorkspaceFile,
        AppCommandId.searchWorkspace,
        AppCommandId.previewWorkspaceReplace,
        AppCommandId.applyWorkspaceReplace,
        AppCommandId.nextReference,
        AppCommandId.previousReference,
      ],
    );
    expect(
      StyioCommandRegistry.workspaceFileCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.createWorkspaceFile,
        AppCommandId.renameWorkspaceFile,
        AppCommandId.deleteWorkspaceFile,
        AppCommandId.revealWorkspaceFile,
      ],
    );
    expect(
      StyioCommandRegistry.refactorCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.renameSymbol,
        AppCommandId.safeDelete,
        AppCommandId.inlineVariable,
      ],
    );
    expect(
      StyioCommandRegistry.debugCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.toggleBreakpoint,
        AppCommandId.startDebugging,
        AppCommandId.stopDebugging,
        AppCommandId.continueDebugging,
        AppCommandId.stepOver,
        AppCommandId.selectDebugThread,
        AppCommandId.selectDebugStackFrame,
      ],
    );
    expect(
      StyioCommandRegistry.nativeToolCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.runBuild,
        AppCommandId.formatActiveDocument,
        AppCommandId.runStaticAnalysis,
        AppCommandId.runTests,
      ],
    );
    expect(
      StyioCommandRegistry.sourceControlCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.refreshSourceControl,
        AppCommandId.previewSourceControlDiff,
        AppCommandId.stageSourceControl,
        AppCommandId.unstageSourceControl,
        AppCommandId.planSourceControlBranchSwitch,
        AppCommandId.planSourceControlCommitDraft,
      ],
    );
    expect(
      StyioCommandRegistry.agentCodingCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.previewQuickFix,
        AppCommandId.collectAgentCodingCheckpoint,
        AppCommandId.collectProjectLanguageContext,
        AppCommandId.retryAgentProvider,
        AppCommandId.failoverAgentProvider,
        AppCommandId.replayAgentPrompt,
      ],
    );
  });

  test('command registry exports stable contribution manifest', () {
    final manifest = StyioCommandRegistry.contributionManifest;
    final commands = manifest['commands']! as List<Object?>;
    final save = commands.cast<Map<String, Object?>>().firstWhere(
      (command) => command['id'] == AppCommandId.save.name,
    );
    final searchWorkspace = commands.cast<Map<String, Object?>>().firstWhere(
      (command) => command['id'] == AppCommandId.searchWorkspace.name,
    );

    expect(manifest['schema'], 'vityo.command-contributions.v1');
    expect(
      manifest['categories'],
      contains(AppCommandCategory.navigation.wireValue),
    );
    expect(commands.length, StyioCommandRegistry.commands.length);
    expect(save['category'], AppCommandCategory.persistence.wireValue);
    expect(save['shortcutHint'], 'Cmd/Ctrl+S');
    expect(save['shortcuts'], hasLength(2));
    expect(
      searchWorkspace['category'],
      AppCommandCategory.navigation.wireValue,
    );
    expect(searchWorkspace['requiresInput'], isTrue);
    expect(searchWorkspace['inputLabel'], 'Search query');
  });

  test('command registry exposes toolchain and deployment route commands', () {
    expect(
      StyioCommandRegistry.executionCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.run],
    );
    expect(
      StyioCommandRegistry.dependencyCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
      ],
    );
    expect(
      StyioCommandRegistry.toolchainCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.useActiveCompiler,
        AppCommandId.pinActiveCompiler,
        AppCommandId.clearPinnedCompiler,
        AppCommandId.selectClangCppVersion,
      ],
    );
    expect(
      StyioCommandRegistry.settingsCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.openSettings],
    );
    expect(
      StyioCommandRegistry.deploymentCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.packProject, AppCommandId.preparePublish],
    );
    expect(
      StyioCommandRegistry.workflowCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.run,
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
        AppCommandId.useActiveCompiler,
        AppCommandId.pinActiveCompiler,
        AppCommandId.clearPinnedCompiler,
        AppCommandId.selectClangCppVersion,
        AppCommandId.packProject,
        AppCommandId.preparePublish,
      ],
    );

    expect(
      StyioCommandRegistry.descriptorFor(AppCommandId.useActiveCompiler).label,
      'Use Compiler',
    );
    expect(
      StyioCommandRegistry.descriptorFor(AppCommandId.preparePublish).label,
      'Preflight',
    );
  });

  test('command keybinding resolver reports remap conflicts', () {
    final profile = CommandKeybindingProfile(
      workspaceId: 'demo',
      overrides: <AppCommandId, CommandKeybindingOverride>{
        AppCommandId.run: const CommandKeybindingOverride(
          commandId: AppCommandId.run,
          shortcuts: <AppCommandShortcutSpec>[
            AppCommandShortcutSpec('keyS', control: true),
          ],
        ),
      },
    );

    final review = CommandKeybindingResolver.reviewConflicts(
      profile: profile,
      descriptors: <AppCommandDescriptor>[
        StyioCommandRegistry.descriptorFor(AppCommandId.save),
        StyioCommandRegistry.descriptorFor(AppCommandId.run),
      ],
    );

    expect(review.hasConflicts, isTrue);
    expect(review.conflicts.single.signature, 'ctrl+keyS');
    expect(
      review.conflicts.single.commandIds,
      containsAll(<AppCommandId>[AppCommandId.save, AppCommandId.run]),
    );
    expect(
      CommandKeybindingResolver.effectiveShortcutsFor(
        descriptor: StyioCommandRegistry.descriptorFor(AppCommandId.run),
        profile: profile,
      ).single.key,
      'keyS',
    );
  });

  test('render shortcut adapter exposes command intents', () {
    final intents = AppCommandShortcutRegistry.shortcutIntents.values
        .whereType<AppCommandIntent>()
        .map((intent) => intent.commandId)
        .toSet();

    expect(intents, contains(AppCommandId.run));
    expect(intents, contains(AppCommandId.save));
    expect(intents, contains(AppCommandId.saveAll));
    expect(intents, contains(AppCommandId.nextDiagnostic));
    expect(intents, contains(AppCommandId.previousDiagnostic));
    expect(intents, contains(AppCommandId.applyQuickFix));
    expect(intents, contains(AppCommandId.goToDefinition));
    expect(intents, contains(AppCommandId.nextReference));
    expect(intents, contains(AppCommandId.previousReference));
    expect(intents, contains(AppCommandId.refreshModules));
  });
}
