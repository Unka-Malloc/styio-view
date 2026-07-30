import '../../backend_toolchain/backend_toolchain.dart';
import '../../commands/commands.dart';
import '../../../ide/editor/editor.dart';
import '../../language/language_contract.dart';
import '../../platform/platform.dart';
import '../../toolchain/toolchain.dart';
import '../../../ide/workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';
import 'execution_controller.dart';
import 'testing_controller.dart';

/// Orchestrates native-tool commands across execution, editor, and testing.
final class NativeToolRuntimeController {
  const NativeToolRuntimeController({
    required this.executionController,
    required this.testingController,
    required this.toolchainManager,
    required this.platformTarget,
    required this.workspaceController,
    required this.editorController,
    required this.editorWorkspaceState,
    required this.activeDocumentPath,
    required this.adapterCapabilities,
    required this.loadClangCppSelection,
    required this.cacheDocument,
    required this.log,
    required this.notify,
  });

  final ExecutionController executionController;
  final ShellTestingController testingController;
  final ToolchainManager? toolchainManager;
  final PlatformTarget platformTarget;
  final WorkspaceController workspaceController;
  final EditorSessionController editorController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final String Function() activeDocumentPath;
  final List<AdapterCapabilitySnapshot> Function() adapterCapabilities;
  final Future<ClangCppVersionSelection?> Function(ToolchainManager manager)
  loadClangCppSelection;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final void Function(String message) log;
  final void Function() notify;

  Future<NativeToolCommandResult> run(NativeToolCommand command) async {
    final commandId = command.appCommandId;
    final backendRouteMetadata = executionController
        .nativeToolBackendRouteMetadata(
          command: command,
          platformTarget: platformTarget,
          projectGraph: workspaceController.activeProject,
          adapterCapabilities: adapterCapabilities(),
        );
    final manager = toolchainManager;
    if (manager == null) {
      final message =
          '${label(commandId)} skipped: no toolchain manager is available.';
      final result = NativeToolCommandResult(
        applied: false,
        message: message,
        metadata: backendRouteMetadata,
      );
      _record(commandId, result);
      log(message);
      notify();
      return result;
    }
    final layout = NativeBuildWorkspaceLayout.fromFiles(
      workspaceController.files,
    );
    return switch (command) {
      NativeToolCommand.build => _build(manager, layout, backendRouteMetadata),
      NativeToolCommand.formatDocument => _format(manager),
      NativeToolCommand.staticAnalysis => _analyze(manager, layout),
      NativeToolCommand.tests => _tests(manager, layout, backendRouteMetadata),
    };
  }

  String label(AppCommandId commandId) =>
      VityoCommandRegistry.labelFor(commandId);

  bool openFirstDiagnostic(AppCommandId commandId) {
    NativeToolResultRecord? target;
    for (final result in executionController.nativeToolResults) {
      if (result.command == commandId && result.diagnostics.isNotEmpty) {
        target = result;
        break;
      }
    }
    if (target == null) {
      log(
        '${label(commandId)} diagnostic navigation skipped: '
        'no diagnostic result is available.',
      );
      return false;
    }
    final selected = editorController.selectDiagnostic(
      target.diagnostics.first,
    );
    log(
      selected
          ? '${target.label} diagnostic selected in editor.'
          : '${target.label} diagnostic navigation failed: range is no longer valid.',
    );
    return selected;
  }

  Future<NativeToolCommandResult> _build(
    ToolchainManager manager,
    NativeBuildWorkspaceLayout layout,
    Map<String, Object?> routeMetadata,
  ) async {
    final path = activeDocumentPath();
    final execution = await executionController.runNativeBuild(
      manager: manager,
      workspaceLayout: layout,
      workspaceRoot: workspaceController.activeProject.workspaceRoot,
      activeDocumentPath: path,
      document: editorController.document,
      loadClangCppSelection: () => loadClangCppSelection(manager),
    );
    for (final artifactPath in execution.generatedArtifactPaths) {
      workspaceController.registerFile(artifactPath);
    }
    _applyDiagnostics(execution.commandResult.diagnostics);
    return _complete(
      NativeToolCommand.build.appCommandId,
      NativeToolCommandResult(
        applied: execution.commandResult.applied,
        message: execution.commandResult.message,
        metadata: <String, Object?>{
          ...execution.commandResult.metadata,
          ...routeMetadata,
        },
        diagnostics: execution.commandResult.diagnostics,
      ),
    );
  }

  Future<NativeToolCommandResult> _format(ToolchainManager manager) async {
    final path = activeDocumentPath();
    final result = await executionController.formatNativeDocument(
      manager: manager,
      activeDocumentPath: path,
      document: editorController.document,
    );
    if (result.changed) {
      editorController.applyFormattingEdits(<FormattingEdit>[
        FormattingEdit(
          range: SourceRange(start: 0, end: editorController.document.length),
          newText: result.formattedText,
        ),
      ]);
      cacheDocument(path, editorController.document);
      editorWorkspaceState.markDirty(path);
    }
    return _complete(
      NativeToolCommand.formatDocument.appCommandId,
      result.commandResult,
    );
  }

  Future<NativeToolCommandResult> _analyze(
    ToolchainManager manager,
    NativeBuildWorkspaceLayout layout,
  ) async {
    final result = await executionController.runNativeStaticAnalysis(
      manager: manager,
      workspaceLayout: layout,
      workspaceRoot: workspaceController.activeProject.workspaceRoot,
      activeDocumentPath: activeDocumentPath(),
      document: editorController.document,
    );
    _applyDiagnostics(result.diagnostics);
    return _complete(NativeToolCommand.staticAnalysis.appCommandId, result);
  }

  Future<NativeToolCommandResult> _tests(
    ToolchainManager manager,
    NativeBuildWorkspaceLayout layout,
    Map<String, Object?> routeMetadata,
  ) async {
    final execution = await executionController.runNativeTests(
      manager: manager,
      workspaceLayout: layout,
      workspaceRoot: workspaceController.activeProject.workspaceRoot,
    );
    return _complete(
      NativeToolCommand.tests.appCommandId,
      NativeToolCommandResult(
        applied: execution.applied,
        message: execution.message,
        metadata: <String, Object?>{...execution.metadata, ...routeMetadata},
        diagnostics: execution.diagnostics,
      ),
    );
  }

  NativeToolCommandResult _complete(
    AppCommandId commandId,
    NativeToolCommandResult result,
  ) {
    _record(commandId, result);
    log(result.message);
    notify();
    return result;
  }

  void _applyDiagnostics(List<Diagnostic> diagnostics) {
    if (diagnostics.isNotEmpty) {
      editorController.applyExternalDiagnostics(diagnostics);
    }
  }

  void _record(AppCommandId commandId, NativeToolCommandResult result) {
    final record = executionController.recordNativeToolResult(
      command: commandId,
      label: label(commandId),
      applied: result.applied,
      message: result.message,
      metadata: result.metadata,
      diagnostics: result.diagnostics,
    );
    if (record.command == AppCommandId.runTests) {
      testingController.recordNativeToolResult(
        message: record.message,
        metadata: record.metadata['testResult'],
      );
    }
  }
}
