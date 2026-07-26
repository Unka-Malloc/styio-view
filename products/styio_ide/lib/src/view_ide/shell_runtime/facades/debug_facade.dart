// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public debugger facade backed by the debug domain controller.
mixin ShellRuntimeDebugFacade on ShellRuntimeFacadeHost {
  DebugSessionSnapshot get debugSession => _debugController.session;
  DebugRuntimeExecutionResult? get lastDebugRuntimeExecutionResult =>
      _debugController.lastRuntimeExecutionResult;
  List<DebugBreakpoint> get debugBreakpoints => _debugController.breakpoints;

  DebugCommandResult toggleBreakpointAtSelection() {
    final position = editorController.document.positionForOffset(
      editorController.selection.extentOffset,
    );
    return _debugController.toggleBreakpointAt(
      filePath: _activeDocumentPath,
      line: position.line,
    );
  }

  Future<DebugCommandResult> startDebugging() =>
      _debugController.startConfiguredSession();

  Future<DebugCommandResult> stopDebugging() =>
      _debugController.stopConfiguredSession();

  bool refreshDebugAdapterSession() =>
      _debugController.refreshConfiguredSession();

  Future<DebugCommandResult> continueDebugging() =>
      _debugController.continueConfiguredSession();

  Future<DebugCommandResult> stepOver() =>
      _debugController.stepOverConfiguredSession();

  Future<DebugCommandResult> selectDebugStackFrame(String frameId) =>
      _debugController.selectConfiguredStackFrame(frameId);

  Future<DebugCommandResult> selectDebugThread(String threadId) =>
      _debugController.selectConfiguredThread(threadId);
}
