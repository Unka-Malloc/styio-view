part of '../shell_runtime_model.dart';

/// Public observable-topology facade backed by the optional graph controller.
mixin ShellRuntimeObservableFacade on ShellRuntimeFacadeHost {
  ObservableGraphState get observableGraphState {
    return observableGraphController?.state ?? ObservableGraphState.initial();
  }

  Future<void> refreshObservableGraph() async {
    await observableGraphController?.refreshNow();
  }

  void selectObservableNode(String? nodeId) {
    observableGraphController?.selectNode(nodeId);
  }

  String? resolvedObservableAnchorPath(String nodeId) {
    return observableGraphController?.resolvedAnchorPath(nodeId);
  }

  Future<void> runObservedProgram(RuntimeObservationMode mode) async {
    final controller = observableGraphController;
    if (controller == null) {
      return;
    }
    if (!controller.beginObservation(mode)) {
      return;
    }
    ObservedExecutionRun? run;
    try {
      final observed = await _executionController.runObserved(
        platformTarget: platformTarget,
        projectGraph: workspaceController.activeProject,
        adapterCapabilities: adapterCapabilities,
        document: editorController.document,
        selection: editorController.selection,
        activeFilePath: workspaceController.activeFilePath,
        observation: RuntimeObservationRequest(mode: mode),
      );
      run = observed;
      await controller.completeObservation(
        sessionFailed: observed.session.status != ExecutionSessionStatus.succeeded,
        runtimeEventsPath: observed.runtimeEventsPath,
      );
    } catch (_) {
      // Never wedge the phase machine in `observing`: an unexpected failure
      // resolves to `rejected`/`run-failed` so a later observation can start.
      await controller.completeObservation(sessionFailed: true);
    } finally {
      await run?.release();
    }
  }
}
