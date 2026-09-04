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
}
