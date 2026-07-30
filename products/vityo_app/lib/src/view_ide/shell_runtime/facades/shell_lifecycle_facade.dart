part of '../shell_runtime_model.dart';

/// Listener callbacks and deterministic owned-resource teardown.
mixin ShellRuntimeLifecycleFacade on ShellRuntimeFacadeHost {
  void _handleSettingsChanged() => _notifyShellListeners();
  void _handleExecutionChanged() => _notifyShellListeners();
  void _handleDebugChanged() => _notifyShellListeners();
  void _handleDeploymentChanged() => _notifyShellListeners();
  void _handleDependencySourceChanged() => _notifyShellListeners();
  void _handleToolchainControllerChanged() => _notifyShellListeners();
  void _handleLanguageControllerChanged() => _notifyShellListeners();
  void _handleWorkspaceDiagnosticsChanged() => _notifyShellListeners();
  void _handleWorkspaceReplaceChanged() => _notifyShellListeners();
  void _handleWorkspaceQuickFixChanged() => _notifyShellListeners();
  void _handleWorkspaceNavigationChanged() => _notifyShellListeners();
  void _handleProjectLanguageContextChanged() => _notifyShellListeners();
  void _handleWorkspaceRenameChanged() => _notifyShellListeners();
  void _handleModuleChanged() => _notifyShellListeners();
  void _handleSourceControlChanged() => _notifyShellListeners();
  void _handleTestingChanged() => _notifyShellListeners();
  void _handleSemanticTelemetryChanged() => _notifyShellListeners();
  void _handleLanguageServiceStatusChanged() => _notifyShellListeners();

  void _handleWorkspaceChanged() =>
      _workspaceDocumentController.handleWorkspaceChanged();

  void _handleDocumentChanged() {
    _workspaceDocumentController.handleDocumentChanged();
    _languageController.publishDocument(editorController.document);
  }

  void _handleEditorFileBindingSnapshot(
    DocumentResourceBindingSnapshot snapshot,
  ) {
    switch (snapshot.state) {
      case DocumentResourceBindingState.externalChanged:
        if (snapshot.externalDocument != null) {
          acceptEditorExternalChange();
          return;
        }
        _notifyShellListeners();
        return;
      case DocumentResourceBindingState.conflicted:
        appendLog(
          'External change conflicted for '
          '${snapshot.externalDocument?.documentId ?? _activeDocumentPath}.',
        );
        return;
      case DocumentResourceBindingState.deletedOnDisk:
      case DocumentResourceBindingState.readonly:
      case DocumentResourceBindingState.providerUnavailable:
        appendLog(
          'Editor file binding ${snapshot.state.name} for $_activeDocumentPath.',
        );
        return;
      case DocumentResourceBindingState.unbound:
      case DocumentResourceBindingState.binding:
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.boundDirty:
        _notifyShellListeners();
        return;
    }
  }

  void _disposeOwnedResources() {
    workspaceController.removeListener(_handleWorkspaceChanged);
    editorController.removeListener(_handleDocumentChanged);
    languageServiceStatus.removeListener(_handleLanguageServiceStatusChanged);
    unawaited(_editorFileBindingSubscription?.cancel());
    _editorFileBindingSubscription = null;
    _settingsController.removeListener(_handleSettingsChanged);
    _settingsController.dispose();
    _executionController.removeListener(_handleExecutionChanged);
    _executionController.dispose();
    _deploymentController.removeListener(_handleDeploymentChanged);
    _deploymentController.dispose();
    _dependencySourceController.removeListener(_handleDependencySourceChanged);
    _dependencySourceController.dispose();
    _toolchainController.removeListener(_handleToolchainControllerChanged);
    _toolchainController.dispose();
    _languageController.removeListener(_handleLanguageControllerChanged);
    _languageController.dispose();
    _workspaceDiagnosticsRuntimeController.removeListener(
      _handleWorkspaceDiagnosticsChanged,
    );
    _workspaceDiagnosticsRuntimeController.dispose();
    _workspaceReplaceController.removeListener(_handleWorkspaceReplaceChanged);
    _workspaceReplaceController.dispose();
    _workspaceQuickFixController.removeListener(
      _handleWorkspaceQuickFixChanged,
    );
    _workspaceQuickFixController.dispose();
    _workspaceNavigationController.removeListener(
      _handleWorkspaceNavigationChanged,
    );
    _workspaceNavigationController.dispose();
    _projectLanguageContextController.removeListener(
      _handleProjectLanguageContextChanged,
    );
    _projectLanguageContextController.dispose();
    _workspaceRenameController.removeListener(_handleWorkspaceRenameChanged);
    _workspaceRenameController.dispose();
    _moduleController.removeListener(_handleModuleChanged);
    _moduleController.dispose();
    _debugController.removeListener(_handleDebugChanged);
    _debugController.dispose();
    _sourceControlController.removeListener(_handleSourceControlChanged);
    _sourceControlController.dispose();
    _testingController.removeListener(_handleTestingChanged);
    _testingController.dispose();
    _semanticTelemetryController.removeListener(
      _handleSemanticTelemetryChanged,
    );
    _semanticTelemetryController.dispose();
    if (_ownsRuntimeOutputBuffer) {
      unawaited(runtimeOutputBuffer.dispose());
    }
    if (_ownsLanguageServiceStatus &&
        languageServiceStatus is ValueNotifier<LanguageServiceStatusSurface>) {
      (languageServiceStatus as ValueNotifier<LanguageServiceStatusSurface>)
          .dispose();
    }
    unawaited(_editorFileBinding.dispose());
  }
}
