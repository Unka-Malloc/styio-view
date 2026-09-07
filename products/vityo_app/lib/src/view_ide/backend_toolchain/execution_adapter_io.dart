import 'dart:convert';

import '../../ide/editor/document_state.dart';
import '../environment/system_compatibility/file_system/file_system.dart';
import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../environment/system_compatibility/process/process.dart';
import '../language/language_contract.dart';
import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'execution_adapter.dart';
import 'hosted_control_plane.dart';
import 'hosted_execution_codec.dart';
import 'project_workflow_selection.dart';
import 'project_graph_contract.dart';
import 'runtime_event_adapter.dart';
import 'pafio_cli_discovery.dart';
import 'pafio_cli_support.dart';
import '../services/observable_topology/observable_runtime_decoder.dart';
import '../services/observable_topology/observable_runtime_model.dart';
import '../services/observable_topology/observable_snapshot_model.dart';

const AdapterCapabilitySnapshot
_iosLocalCliExecutionCapabilitySnapshot = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cli,
  languageService: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'iOS does not expose local CLI language execution.',
  ),
  projectGraph: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail:
        'Project graph is not driven through the local execution path on iOS.',
  ),
  execution: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'iOS execution remains cloud-routed by policy.',
  ),
  runtimeEvents: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'Runtime events remain cloud-routed on iOS.',
  ),
);

const String _missingLocalStyioBinaryMessage =
    'No local styio binary was resolved. Set VITYO_STYIO_BIN or install styio on PATH.';

const int _executionOverlaySnapshotMaxEntries = 20000;
const int _executionOverlaySnapshotMaxBytes = 256 * 1024 * 1024;
int _executionTempSequence = 0;

const ExecutionSession _iosCloudOnlyExecutionSession = ExecutionSession(
  sessionId: 'ios-cloud-only',
  kind: 'run',
  status: ExecutionSessionStatus.blocked,
  statusMessage:
      'iOS execution is cloud-only and is not routed through the local CLI adapter.',
  diagnostics: <Diagnostic>[],
  stdoutEvents: <ExecutionLogEvent>[],
  stderrEvents: <ExecutionLogEvent>[],
);

ExecutionSession _blockedRunExecutionSession({
  required String sessionId,
  required String message,
}) {
  return ExecutionSession(
    sessionId: sessionId,
    kind: 'run',
    status: ExecutionSessionStatus.blocked,
    statusMessage: message,
    diagnostics: const <Diagnostic>[],
    stdoutEvents: const <ExecutionLogEvent>[],
    stderrEvents: const <ExecutionLogEvent>[],
  );
}

Future<ExecutionAdapter> createPlatformExecutionAdapter({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  PlatformManagerBundle? platformManagers,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient != null) {
    return _HostedExecutionAdapter(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      hostedClient: hostedClient,
    );
  }
  final compiler = projectGraph.activeCompiler;
  return _LocalCliExecutionAdapter(
    platformTarget: platformTarget,
    projectGraph: projectGraph,
    compiler: compiler,
    platformManagers: platformManagers,
  );
}

class _HostedExecutionAdapter implements ExecutionAdapter {
  const _HostedExecutionAdapter({
    required this.platformTarget,
    required this.projectGraph,
    required this.hostedClient,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot projectGraph;
  final HostedControlPlaneClient hostedClient;

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cloud,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail: 'Hosted language service stays reserved behind the cloud route.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted project graph is live through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted execution is live through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Hosted execution publishes runtime event payloads through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
  );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return _blockedRunExecutionSession(
        sessionId: 'missing-hosted-workspace',
        message:
            'Hosted workspace identity is unavailable for cloud execution.',
      );
    }

    final workflow = selectProjectWorkflow(
      projectGraph: projectGraph,
      activeFilePath: activeFilePath,
    );
    try {
      final response = switch (workflow.command) {
        'test' => await hostedClient.testWorkflow(
          workspaceId: workspaceId,
          activeFilePath: activeFilePath,
          documentText: document.text,
          packageName: workflow.packageName,
          targetName: workflow.targetName,
          targetKind: workflow.targetKind,
        ),
        'build' => await hostedClient.buildWorkflow(
          workspaceId: workspaceId,
          activeFilePath: activeFilePath,
          documentText: document.text,
          packageName: workflow.packageName,
          targetName: workflow.targetName,
          targetKind: workflow.targetKind,
        ),
        _ => await hostedClient.runWorkflow(
          workspaceId: workspaceId,
          activeFilePath: activeFilePath,
          documentText: document.text,
          packageName: workflow.packageName,
          targetName: workflow.targetName,
          targetKind: workflow.targetKind,
        ),
      };
      final decoded = executionSessionFromHostedResponse(
        response: response,
        workflowKind: workflow.kind,
        successMessage: workflow.successMessage,
        documentText: document.text,
        activeFilePath: activeFilePath,
      );
      if (decoded.runtimeEvents.isEmpty) {
        clearRuntimeEventsForSession(decoded.session.sessionId);
      } else {
        recordRuntimeEventsForSession(
          decoded.session.sessionId,
          decoded.runtimeEvents,
        );
      }
      return decoded.session;
    } catch (error) {
      return ExecutionSession(
        sessionId: 'hosted-execution-error',
        kind: workflow.kind,
        status: ExecutionSessionStatus.failed,
        statusMessage: 'Hosted execution failed: $error',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: const <ExecutionLogEvent>[],
        stderrEvents: const <ExecutionLogEvent>[],
        unitRange: SourceRange(start: 0, end: document.length),
      );
    }
  }
}

class _LocalCliExecutionAdapter
    implements ExecutionAdapter, ObservedExecutionAdapter {
  const _LocalCliExecutionAdapter({
    required this.platformTarget,
    required this.projectGraph,
    required this.compiler,
    required this.platformManagers,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot projectGraph;
  final CompilerHandshakeSnapshot? compiler;
  final PlatformManagerBundle? platformManagers;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => switch (platformTarget) {
    PlatformTarget.ios => _iosLocalCliExecutionCapabilitySnapshot,
    _ => _localCliExecutionCapabilitySnapshot(
      projectGraph: projectGraph,
      compiler: compiler,
    ),
  };

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    switch (platformTarget) {
      case PlatformTarget.ios:
        return _iosCloudOnlyExecutionSession;
      case PlatformTarget.web:
      case PlatformTarget.windows:
      case PlatformTarget.linux:
      case PlatformTarget.android:
      case PlatformTarget.macos:
      case PlatformTarget.unknown:
        break;
    }

    final resolvedCompiler = compiler;
    final managers = platformManagers;
    if (resolvedCompiler == null || managers == null) {
      return _blockedRunExecutionSession(
        sessionId: 'missing-styio-binary',
        message: _missingLocalStyioBinaryMessage,
      );
    }

    if (projectGraph.hasManifest) {
      if (!resolvedCompiler.supportsContract('compile_plan')) {
        return _blockedRunExecutionSession(
          sessionId: 'compile-plan-preview-only',
          message:
              'Project build/run is blocked because the active styio binary does not advertise compile-plan support.',
        );
      }
      return _runProjectWorkflow(
        compiler: resolvedCompiler,
        projectGraph: projectGraph,
        document: document,
        activeFilePath: activeFilePath,
        platformManagers: managers,
      );
    }

    final _PreparedExecutionInput preparedInput;
    try {
      preparedInput = await _prepareSingleFileExecutionInput(
        activeFilePath: activeFilePath,
        document: document,
        platformManagers: managers,
      );
    } on _ExecutionOverlayException catch (error) {
      return _blockedRunExecutionSession(
        sessionId: 'execution-overlay-blocked',
        message: error.message,
      );
    }
    try {
      final result = await managers.process.run(
        ProcessCommandRequest(
          executablePath: resolvedCompiler.binaryPath,
          arguments: <String>[
            '--file',
            preparedInput.filePath,
            '--error-format=jsonl',
          ],
          workingDirectory: projectGraph.workspaceRoot,
          serviceKind: ProcessServiceKind.styio,
        ),
      );

      final normalizedPath = preparedInput.pathOverlay?.normalize;
      final stdoutChannel = _parseOutputChannel(
        result.stdout,
        documentText: document.text,
        activeFilePath: activeFilePath,
        normalizePath: normalizedPath,
      );
      final stderrChannel = _parseOutputChannel(
        result.stderr,
        documentText: document.text,
        activeFilePath: activeFilePath,
        normalizePath: normalizedPath,
      );

      return ExecutionSession(
        sessionId: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: 'run',
        status: result.succeeded
            ? ExecutionSessionStatus.succeeded
            : ExecutionSessionStatus.failed,
        statusMessage: result.succeeded
            ? 'Single-file CLI run completed through styio.'
            : 'styio exited with code ${result.exitCode}.',
        diagnostics: <Diagnostic>[
          ...stdoutChannel.diagnostics,
          ...stderrChannel.diagnostics,
        ],
        stdoutEvents: stdoutChannel.logEvents,
        stderrEvents: stderrChannel.logEvents,
        unitRange: SourceRange(start: 0, end: document.length),
      );
    } finally {
      await _cleanupPreparedExecutionInput(
        preparedInput,
        fileSystem: managers.fileSystem,
      );
    }
  }

  @override
  Future<ObservedExecutionRun> runActiveDocumentObserved({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
    required RuntimeObservationRequest observation,
  }) async {
    switch (platformTarget) {
      case PlatformTarget.ios:
        return ObservedExecutionRun(
          session: _iosCloudOnlyExecutionSession,
          unavailableReason: ObservableReasonCode.unsupportedPlatform,
        );
      case PlatformTarget.web:
      case PlatformTarget.windows:
      case PlatformTarget.linux:
      case PlatformTarget.android:
      case PlatformTarget.macos:
      case PlatformTarget.unknown:
        break;
    }

    final managers = platformManagers;
    if (compiler == null || managers == null) {
      return ObservedExecutionRun(
        session: _blockedRunExecutionSession(
          sessionId: 'missing-styio-binary',
          message: _missingLocalStyioBinaryMessage,
        ),
        unavailableReason: ObservableReasonCode.noToolchain,
      );
    }

    if (!projectGraph.hasManifest) {
      return ObservedExecutionRun(
        session: _blockedRunExecutionSession(
          sessionId: 'missing-manifest',
          message: 'Project execution requires a resolved pafio manifest.',
        ),
        unavailableReason: ObservableReasonCode.noManifest,
      );
    }

    if (!compiler!.supportsContract('compile_plan')) {
      return ObservedExecutionRun(
        session: _blockedRunExecutionSession(
          sessionId: 'compile-plan-preview-only',
          message:
              'Project build/run is blocked because the active styio binary does not advertise compile-plan support.',
        ),
        unavailableReason: ObservableReasonCode.unsupportedPlatform,
      );
    }

    return _runProjectWorkflowObserved(
      compiler: compiler!,
      projectGraph: projectGraph,
      document: document,
      activeFilePath: activeFilePath,
      observation: observation,
      platformManagers: managers,
    );
  }
}

AdapterCapabilitySnapshot _localCliExecutionCapabilitySnapshot({
  required ProjectGraphSnapshot projectGraph,
  required CompilerHandshakeSnapshot? compiler,
}) {
  if (compiler == null) {
    return const AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cli,
      languageService: AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail:
            'No published local styio binary was resolved for CLI language services.',
      ),
      projectGraph: AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail:
            'Project graph is handled by the dedicated project graph adapter.',
      ),
      execution: AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: _missingLocalStyioBinaryMessage,
      ),
      runtimeEvents: AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail:
            'Runtime events require a published execution/runtime contract.',
      ),
    );
  }

  final hasProjectExecution =
      projectGraph.hasManifest && compiler.supportsContract('compile_plan');
  final hasRuntimeEvents = compiler.supportsContract('runtime_events');
  final executionDetail = hasProjectExecution
      ? 'Project execution routes through pafio build/run/test with a live published compile-plan handoff.'
      : projectGraph.hasManifest
      ? 'Project execution remains blocked until the active compiler advertises compile-plan support.'
      : 'CLI execution is available through published single-file entry plus jsonl diagnostics.';

  return AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail:
          'System Styio provides machine-info and jsonl diagnostics directly.',
    ),
    projectGraph: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail:
          'Project graph is handled by the dedicated project graph adapter.',
    ),
    execution: AdapterEndpointCapability(
      level: hasProjectExecution || !projectGraph.hasManifest
          ? AdapterCapabilityLevel.available
          : AdapterCapabilityLevel.partial,
      detail: executionDetail,
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: hasRuntimeEvents
          ? AdapterCapabilityLevel.available
          : AdapterCapabilityLevel.unavailable,
      detail: hasRuntimeEvents
          ? 'Runtime events route through the published styio runtime_events contract.'
          : 'Runtime events stay unavailable until styio publishes a runtime event machine contract.',
      supportedContractVersions: hasRuntimeEvents
          ? List<int>.unmodifiable(
              compiler.supportedContractVersions[kRuntimeEventsContractVersionsKey] ??
                  const <int>[],
            )
          : const <int>[],
    ),
  );
}

class _ProjectWorkflowSelection {
  const _ProjectWorkflowSelection({
    required this.command,
    required this.kind,
    required this.args,
    required this.successMessage,
  });

  final String command;
  final String kind;
  final List<String> args;
  final String successMessage;
}

class _PreparedExecutionInput {
  const _PreparedExecutionInput({
    required this.filePath,
    this.temporaryDirectory,
    this.pathOverlay,
  });

  final String filePath;
  final String? temporaryDirectory;
  final _PathOverlayMapping? pathOverlay;
}

class _PreparedProjectWorkflowInput {
  const _PreparedProjectWorkflowInput({
    required this.workspaceRoot,
    required this.manifestPath,
    this.temporaryDirectory,
    this.pathOverlay,
  });

  final String workspaceRoot;
  final String manifestPath;
  final String? temporaryDirectory;
  final _PathOverlayMapping? pathOverlay;
}

class _PathOverlayMapping {
  const _PathOverlayMapping({
    required this.sourceRoot,
    required this.overlayRoot,
  });

  final String sourceRoot;
  final String overlayRoot;

  String normalize(String path) {
    final relativePath = _relativePathWithinRoot(path, overlayRoot);
    if (relativePath == null) {
      return path;
    }
    return _appendRelativePath(sourceRoot, relativePath);
  }

  String? overlayPathForSource(String path) {
    final relativePath = _relativePathWithinRoot(path, sourceRoot);
    if (relativePath == null) {
      return null;
    }
    return _appendRelativePath(overlayRoot, relativePath);
  }
}

class _ExecutionOverlayException implements Exception {
  const _ExecutionOverlayException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _OverlaySnapshotBudget {
  int _entries = 0;
  int _bytes = 0;

  void accountDirectory(String path) {
    _accountEntry(path);
  }

  void accountFile(FileSystemEntitySnapshot file) {
    _accountEntry(file.path);
    _bytes += file.size ?? 0;
    if (_bytes > _executionOverlaySnapshotMaxBytes) {
      throw _ExecutionOverlayException(
        'Execution overlay snapshot exceeded $_executionOverlaySnapshotMaxBytes bytes while copying ${file.path}.',
      );
    }
  }

  void accountDocument(String path, String documentText) {
    _accountEntry(path);
    _bytes += utf8.encode(documentText).length;
    if (_bytes > _executionOverlaySnapshotMaxBytes) {
      throw _ExecutionOverlayException(
        'Execution overlay snapshot exceeded $_executionOverlaySnapshotMaxBytes bytes while writing $path.',
      );
    }
  }

  void _accountEntry(String path) {
    _entries += 1;
    if (_entries > _executionOverlaySnapshotMaxEntries) {
      throw _ExecutionOverlayException(
        'Execution overlay snapshot exceeded $_executionOverlaySnapshotMaxEntries filesystem entries while copying $path.',
      );
    }
  }
}

class _ParsedDiagnostics {
  const _ParsedDiagnostics({
    required this.diagnostics,
    required this.logEvents,
  });

  final List<Diagnostic> diagnostics;
  final List<ExecutionLogEvent> logEvents;
}

class _ParsedDiagnosticRecord {
  const _ParsedDiagnosticRecord({this.diagnostic, this.logMessage});

  final Diagnostic? diagnostic;
  final String? logMessage;
}

Future<ExecutionSession> _runProjectWorkflow({
  required CompilerHandshakeSnapshot compiler,
  required ProjectGraphSnapshot projectGraph,
  required DocumentState document,
  required String activeFilePath,
  required PlatformManagerBundle platformManagers,
}) async {
  final outcome = await _executeProjectWorkflow(
    compiler: compiler,
    projectGraph: projectGraph,
    document: document,
    activeFilePath: activeFilePath,
    platformManagers: platformManagers,
  );
  return outcome.session;
}

Future<ObservedExecutionRun> _runProjectWorkflowObserved({
  required CompilerHandshakeSnapshot compiler,
  required ProjectGraphSnapshot projectGraph,
  required DocumentState document,
  required String activeFilePath,
  required RuntimeObservationRequest observation,
  required PlatformManagerBundle platformManagers,
}) async {
  return _executeProjectWorkflow(
    compiler: compiler,
    projectGraph: projectGraph,
    document: document,
    activeFilePath: activeFilePath,
    observation: observation,
    platformManagers: platformManagers,
  );
}

Future<ObservedExecutionRun> _executeProjectWorkflow({
  required CompilerHandshakeSnapshot compiler,
  required ProjectGraphSnapshot projectGraph,
  required DocumentState document,
  required String activeFilePath,
  required PlatformManagerBundle platformManagers,
  RuntimeObservationRequest? observation,
}) async {
  final manifestPath = projectGraph.manifestPath;
  if (manifestPath == null) {
    return ObservedExecutionRun(
      session: _blockedRunExecutionSession(
        sessionId: 'missing-manifest',
        message: 'Project execution requires a resolved pafio manifest.',
      ),
      unavailableReason: ObservableReasonCode.noManifest,
    );
  }

  final pafioBinary = await resolvePafioBinary(platformManagers);
  if (pafioBinary == null) {
    return ObservedExecutionRun(
      session: _blockedRunExecutionSession(
        sessionId: 'missing-pafio-binary',
        message: missingLocalPafioBinaryMessage,
      ),
    );
  }
  final workflow = _selectProjectWorkflow(
    projectGraph: projectGraph,
    activeFilePath: activeFilePath,
  );
  final _PreparedProjectWorkflowInput preparedInput;
  try {
    preparedInput = await _prepareProjectWorkflowInput(
      projectGraph: projectGraph,
      manifestPath: manifestPath,
      activeFilePath: activeFilePath,
      document: document,
      platformManagers: platformManagers,
    );
  } on _ExecutionOverlayException catch (error) {
    return ObservedExecutionRun(
      session: _blockedRunExecutionSession(
        sessionId: 'execution-overlay-blocked',
        message: error.message,
      ),
    );
  }
  final normalizedPath = preparedInput.pathOverlay?.normalize;
  final deferCleanup = observation != null;

  Future<void> releaseOverlay() => _cleanupPreparedProjectWorkflowInput(
    preparedInput,
    fileSystem: platformManagers.fileSystem,
  );

  try {
    final command = <String>[
      '--json',
      workflow.command,
      '--manifest-path',
      preparedInput.manifestPath,
      '--styio-bin',
      compiler.binaryPath,
      ...workflow.args,
    ];
    if (observation != null) {
      command.add('$kRuntimePafioEmitOption=$kRuntimeEventsSchemaVersion');
      command.add(kRuntimePafioModeOption);
      command.add(observation.mode.wireValue);
      for (final name in observation.requiredCapabilities) {
        command.add(kRuntimePafioCapabilityOption);
        command.add(name);
      }
    }
    final result = await platformManagers.process.run(
      ProcessCommandRequest(
        executablePath: pafioBinary,
        arguments: command,
        workingDirectory: preparedInput.workspaceRoot,
        serviceKind: ProcessServiceKind.pafio,
      ),
    );

    final stdout = result.stdout;
    final stderr = result.stderr;
    final payload = result.succeeded
        ? parseJsonObjectPayload(stdout) ?? parseJsonObjectPayload(stderr)
        : parseJsonObjectPayload(stderr) ?? parseJsonObjectPayload(stdout);
    final artifactPath = await _locateRuntimeEventsArtifact(
      payload: payload,
      workspaceRoot: preparedInput.workspaceRoot,
      fileSystem: platformManagers.fileSystem,
    );
    ExecutionSession? session;
    if (result.succeeded) {
      session = await _sessionFromWorkflowSuccessPayload(
        stdout: stdout,
        stderr: stderr,
        workflow: workflow,
        document: document,
        activeFilePath: activeFilePath,
        workspaceRoot: preparedInput.workspaceRoot,
        normalizePath: normalizedPath,
        fileSystem: platformManagers.fileSystem,
      );
    }
    session ??= _sessionFromWorkflowFailurePayload(
      stdout: stdout,
      stderr: stderr,
      workflow: workflow,
      document: document,
      activeFilePath: activeFilePath,
      normalizePath: normalizedPath,
      exitCode: result.exitCode,
    );
    final runtimeEvents = await readRuntimeEventsV2ForSession(
      artifactPath: artifactPath,
      sessionId: session.sessionId,
      fileSystem: platformManagers.fileSystem,
    );
    if (runtimeEvents.isEmpty) {
      clearRuntimeEventsForSession(session.sessionId);
    } else {
      recordRuntimeEventsForSession(session.sessionId, runtimeEvents);
    }
    return ObservedExecutionRun(
      session: session,
      runtimeEventsPath: artifactPath,
      release: deferCleanup ? releaseOverlay : null,
    );
  } on Object catch (error) {
    final session = ExecutionSession(
      sessionId: 'pafio-process-error',
      kind: workflow.kind,
      status: ExecutionSessionStatus.failed,
      statusMessage: 'Failed to execute pafio: $error',
      diagnostics: const <Diagnostic>[],
      stdoutEvents: const <ExecutionLogEvent>[],
      stderrEvents: const <ExecutionLogEvent>[],
      unitRange: SourceRange(start: 0, end: document.length),
    );
    return ObservedExecutionRun(
      session: session,
      release: deferCleanup ? releaseOverlay : null,
    );
  } finally {
    if (!deferCleanup) {
      await releaseOverlay();
    }
  }
}

Future<ExecutionSession?> _sessionFromWorkflowSuccessPayload({
  required String stdout,
  required String stderr,
  required _ProjectWorkflowSelection workflow,
  required DocumentState document,
  required String activeFilePath,
  required String workspaceRoot,
  required FileSystemManager fileSystem,
  String Function(String path)? normalizePath,
}) async {
  final trimmed = stdout.trim();
  if (!trimmed.startsWith('{')) {
    return null;
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    if (decoded['workflow_payload_version'] != 1) {
      return null;
    }

    final sessionId =
        _workflowSessionIdFromPayload(decoded) ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final receiptPayload = decoded['receipt'];
    final receipt = ExecutionReceiptSnapshot.decode(
      receiptPayload,
      fallbackSessionId: sessionId,
    );
    if (receiptPayload != null && receipt == null) {
      return ExecutionSession(
        sessionId: sessionId,
        kind: workflow.kind,
        status: ExecutionSessionStatus.failed,
        statusMessage:
            'Workflow receipt rejected: only receipt schema version 1 is supported.',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: const <ExecutionLogEvent>[],
        stderrEvents: const <ExecutionLogEvent>[],
        unitRange: SourceRange(start: 0, end: document.length),
      );
    }
    final payloadStdout = decoded['stdout'] as String? ?? '';
    final payloadStderr = decoded['stderr'] as String? ?? '';
    final workflowDiagnostics = await _readWorkflowDiagnostics(
      rawDiagnostics: decoded['diagnostics'],
      diagnosticsPath: decoded['diagnostics_path'],
      workspaceRoot: workspaceRoot,
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
      fileSystem: fileSystem,
    );
    final payloadStdoutChannel = _parseOutputChannel(
      payloadStdout,
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
    final payloadStderrChannel = _parseOutputChannel(
      payloadStderr,
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
    final stderrChannel = _parseOutputChannel(
      stderr,
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );

    return ExecutionSession(
      sessionId: sessionId,
      kind: workflow.kind,
      status: ExecutionSessionStatus.succeeded,
      statusMessage: decoded['message'] as String? ?? workflow.successMessage,
      diagnostics: <Diagnostic>[
        ...workflowDiagnostics.diagnostics,
        ...payloadStdoutChannel.diagnostics,
        ...payloadStderrChannel.diagnostics,
        ...stderrChannel.diagnostics,
      ],
      stdoutEvents: payloadStdoutChannel.logEvents,
      stderrEvents: <ExecutionLogEvent>[
        ...workflowDiagnostics.logEvents,
        ...payloadStderrChannel.logEvents,
        ...stderrChannel.logEvents,
      ],
      receipt: receipt,
      unitRange: SourceRange(start: 0, end: document.length),
    );
  } on FormatException {
    return null;
  }
}

ExecutionSession _sessionFromWorkflowFailurePayload({
  required String stdout,
  required String stderr,
  required _ProjectWorkflowSelection workflow,
  required DocumentState document,
  required String activeFilePath,
  required int? exitCode,
  String Function(String path)? normalizePath,
}) {
  final failurePayload =
      parseJsonObjectPayload(stderr) ?? parseJsonObjectPayload(stdout);
  final sessionId =
      _workflowSessionIdFromPayload(failurePayload) ??
      DateTime.now().microsecondsSinceEpoch.toString();
  final payloadDiagnostics = _parsePayloadDiagnostics(
    failurePayload?['diagnostics'],
    documentText: document.text,
    activeFilePath: activeFilePath,
    normalizePath: normalizePath,
  );
  final stdoutChannel = _parseOutputChannel(
    stdout,
    documentText: document.text,
    activeFilePath: activeFilePath,
    normalizePath: normalizePath,
  );
  final stderrChannel = _parseOutputChannel(
    stderr,
    documentText: document.text,
    activeFilePath: activeFilePath,
    normalizePath: normalizePath,
  );
  return ExecutionSession(
    sessionId: sessionId,
    kind: workflow.kind,
    status: exitCode == 0
        ? ExecutionSessionStatus.succeeded
        : ExecutionSessionStatus.failed,
    statusMessage: exitCode == 0
        ? workflow.successMessage
        : (failurePayload?['message'] as String? ??
              (exitCode == null
                  ? 'pafio ${workflow.command} failed before reporting an exit code.'
                  : 'pafio ${workflow.command} exited with code $exitCode.')),
    diagnostics: <Diagnostic>[
      ...payloadDiagnostics.diagnostics,
      ...stdoutChannel.diagnostics,
      ...stderrChannel.diagnostics,
    ],
    stdoutEvents: stdoutChannel.logEvents,
    stderrEvents: <ExecutionLogEvent>[
      ...payloadDiagnostics.logEvents,
      ...stderrChannel.logEvents,
    ],
    unitRange: SourceRange(start: 0, end: document.length),
  );
}

Future<_ParsedDiagnostics> _readWorkflowDiagnostics({
  required Object? rawDiagnostics,
  required Object? diagnosticsPath,
  required String workspaceRoot,
  required String documentText,
  required String activeFilePath,
  required FileSystemManager fileSystem,
  String Function(String path)? normalizePath,
}) async {
  final inlineDiagnostics = _parsePayloadDiagnostics(
    rawDiagnostics,
    documentText: documentText,
    activeFilePath: activeFilePath,
    normalizePath: normalizePath,
  );
  final diagnostics = <Diagnostic>[...inlineDiagnostics.diagnostics];
  final logEvents = <ExecutionLogEvent>[...inlineDiagnostics.logEvents];

  final resolvedDiagnosticsPath = _resolveWorkflowDiagnosticsPath(
    diagnosticsPath,
    workspaceRoot: workspaceRoot,
  );
  if (resolvedDiagnosticsPath == null) {
    return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
  }

  try {
    if (!await fileSystem.exists(resolvedDiagnosticsPath)) {
      return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
    }
    final fileDiagnostics = _parseOutputChannel(
      await fileSystem.readText(resolvedDiagnosticsPath),
      documentText: documentText,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
    diagnostics.addAll(fileDiagnostics.diagnostics);
    logEvents.addAll(fileDiagnostics.logEvents);
  } on Object {
    // Keep inline diagnostics when the artifact cannot be read.
  }

  return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
}

Future<String?> _locateRuntimeEventsArtifact({
  required Map<String, dynamic>? payload,
  required String workspaceRoot,
  required FileSystemManager fileSystem,
}) async {
  if (payload == null) {
    return null;
  }
  final plan = payload['plan'];
  if (plan is! Map) {
    return null;
  }
  final buildRootRaw = _stringValue(plan['build_root']);
  if (buildRootRaw == null) {
    return null;
  }
  final buildRoot = _isAbsolutePath(buildRootRaw)
      ? buildRootRaw
      : _joinPath(workspaceRoot, buildRootRaw);
  if (!_runtimePathContained(buildRoot, workspaceRoot)) {
    return null;
  }
  final receiptPath = _joinPath(buildRoot, 'receipt.json');
  if (!await fileSystem.exists(receiptPath)) {
    return null;
  }
  Map<String, dynamic>? receipt;
  try {
    final decoded = jsonDecode(await fileSystem.readText(receiptPath));
    if (decoded is Map<String, dynamic>) {
      receipt = decoded;
    }
  } on Object {
    return null;
  }
  if (receipt == null) {
    return null;
  }
  final schema = _intValue(receipt['schema_version']);
  if (schema != 1) {
    return null;
  }
  final outputs = receipt['outputs'];
  if (outputs is! Map) {
    return null;
  }
  final namedPath = _stringValue(outputs[kRuntimeEventsReceiptPathField]);
  if (namedPath == null) {
    return null;
  }
  final resolved = _isAbsolutePath(namedPath)
      ? namedPath
      : _joinPath(buildRoot, namedPath);
  if (!_runtimePathContained(resolved, workspaceRoot) ||
      !_runtimePathContained(resolved, buildRoot)) {
    return null;
  }
  if (!await fileSystem.exists(resolved)) {
    return null;
  }
  return resolved;
}

bool _runtimePathContained(String path, String root) {
  if (_pathIsWithinRoot(path, root)) {
    return true;
  }
  final pafioTree = _joinPath(root, '.pafio');
  return _pathIsWithinRoot(path, pafioTree);
}

Future<List<RuntimeEventEnvelope>> readRuntimeEventsV2ForSession({
  required String? artifactPath,
  required String sessionId,
  required FileSystemManager fileSystem,
}) async {
  if (artifactPath == null || artifactPath.isEmpty) {
    return const <RuntimeEventEnvelope>[];
  }
  if (!await fileSystem.exists(artifactPath)) {
    return const <RuntimeEventEnvelope>[];
  }
  late final String text;
  try {
    text = await fileSystem.readText(artifactPath);
  } on Object {
    return const <RuntimeEventEnvelope>[];
  }
  final decoded = decodeRuntimeStream(text.split('\n'));
  if (!decoded.isOk) {
    return const <RuntimeEventEnvelope>[];
  }
  return [
    for (final record in decoded.records)
      RuntimeEventEnvelope(
        schemaVersion: kRuntimeEventsSchemaVersion,
        sessionId: sessionId,
        sequence: 0,
        timestamp: DateTime.fromMicrosecondsSinceEpoch(
          runtimeRecordMonotonicNs(record) ~/ 1000,
          isUtc: true,
        ),
        eventKind: runtimeRecordEventKind(record),
        origin: kRuntimeEventsContract,
        payload: runtimeRecordEnvelopePayload(record),
      ),
  ];
}

_ParsedDiagnostics _parsePayloadDiagnostics(
  Object? rawDiagnostics, {
  required String documentText,
  required String activeFilePath,
  String Function(String path)? normalizePath,
}) {
  if (rawDiagnostics is! List) {
    return const _ParsedDiagnostics(
      diagnostics: <Diagnostic>[],
      logEvents: <ExecutionLogEvent>[],
    );
  }

  final diagnostics = <Diagnostic>[];
  final logEvents = <ExecutionLogEvent>[];
  for (final item in rawDiagnostics) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final record = _parseDiagnosticObject(
      item,
      allowPayloadShape: true,
      documentText: documentText,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
    if (record?.diagnostic != null) {
      diagnostics.add(record!.diagnostic!);
    }
    if (record?.logMessage != null) {
      logEvents.add(ExecutionLogEvent(message: record!.logMessage!));
    }
  }
  return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
}

String? _workflowSessionIdFromPayload(Map<String, dynamic>? payload) {
  if (payload == null) {
    return null;
  }

  final runtimeSessionId = _stringValue(payload['runtime_session_id']);
  if (runtimeSessionId != null) {
    return runtimeSessionId;
  }

  final receipt = payload['receipt'];
  if (receipt is Map<String, dynamic>) {
    return _stringValue(receipt['session_id']) ??
        _stringValue(receipt['sessionId']);
  }
  return null;
}

_ProjectWorkflowSelection _selectProjectWorkflow({
  required ProjectGraphSnapshot projectGraph,
  required String activeFilePath,
}) {
  ProjectTargetDescriptor? target;
  for (final candidate in projectGraph.targets) {
    if (candidate.filePath == activeFilePath) {
      target = candidate;
      break;
    }
  }

  if (target == null) {
    final packageName = _packageNameForPath(
      projectGraph: projectGraph,
      activeFilePath: activeFilePath,
    );
    final packageTargets = packageName == null
        ? const <ProjectTargetDescriptor>[]
        : projectGraph.targets
              .where((candidate) => candidate.packageName == packageName)
              .toList(growable: false);
    if (packageTargets.length == 1) {
      target = packageTargets.single;
    } else if (projectGraph.targets.length == 1) {
      target = projectGraph.targets.single;
    } else {
      return _ProjectWorkflowSelection(
        command: 'build',
        kind: 'build',
        args: packageName == null
            ? const <String>[]
            : _packageArgs(packageName),
        successMessage: packageName == null
            ? 'Project build completed through pafio.'
            : 'Project package build completed through pafio.',
      );
    }
  }

  switch (target.kind) {
    case ProjectTargetKind.test:
      return _ProjectWorkflowSelection(
        command: 'test',
        kind: 'test',
        args: <String>[
          ..._packageArgs(target.packageName),
          '--test',
          target.name,
        ],
        successMessage: 'Project test target completed through pafio.',
      );
    case ProjectTargetKind.lib:
      return _ProjectWorkflowSelection(
        command: 'build',
        kind: 'build',
        args: <String>[..._packageArgs(target.packageName), '--lib'],
        successMessage: 'Project library build completed through pafio.',
      );
    case ProjectTargetKind.bin:
      return _ProjectWorkflowSelection(
        command: 'run',
        kind: 'run',
        args: <String>[
          ..._packageArgs(target.packageName),
          '--bin',
          target.name,
        ],
        successMessage: 'Project binary run completed through pafio.',
      );
  }
}

Future<_PreparedExecutionInput> _prepareSingleFileExecutionInput({
  required String activeFilePath,
  required DocumentState document,
  required PlatformManagerBundle platformManagers,
}) async {
  final fileSystem = platformManagers.fileSystem;
  if (_isAbsolutePath(activeFilePath)) {
    if (!await _shouldUseDocumentOverlay(
      activeFilePath: activeFilePath,
      document: document,
      fileSystem: fileSystem,
    )) {
      return _PreparedExecutionInput(filePath: activeFilePath);
    }

    final sourceRoot = await _singleFileOverlayRoot(
      activeFilePath,
      fileSystem: fileSystem,
    );
    final overlay = await _createDocumentOverlay(
      sourceRoot: sourceRoot,
      activeFilePath: activeFilePath,
      document: document,
      fileSystem: fileSystem,
      temporaryRoot: platformManagers.resource.snapshot().systemTempPath,
    );
    return _PreparedExecutionInput(
      filePath:
          overlay.pathOverlay.overlayPathForSource(activeFilePath) ??
          activeFilePath,
      temporaryDirectory: overlay.temporaryDirectory,
      pathOverlay: overlay.pathOverlay,
    );
  }

  final tempDirectory = await _createTemporaryOverlayDirectory(
    fileSystem: fileSystem,
    temporaryRoot: platformManagers.resource.snapshot().systemTempPath,
    label: 'single-file',
  );
  final tempFile = fileSystem.joinPath(<String>[tempDirectory, 'main.styio']);
  await fileSystem.writeText(tempFile, document.text);
  return _PreparedExecutionInput(
    filePath: tempFile,
    temporaryDirectory: tempDirectory,
  );
}

Future<void> _cleanupPreparedExecutionInput(
  _PreparedExecutionInput input, {
  required FileSystemManager fileSystem,
}) async {
  final temporaryDirectory = input.temporaryDirectory;
  if (temporaryDirectory == null) {
    return;
  }
  await _deleteTemporaryOverlayRoot(temporaryDirectory, fileSystem: fileSystem);
}

Future<_PreparedProjectWorkflowInput> _prepareProjectWorkflowInput({
  required ProjectGraphSnapshot projectGraph,
  required String manifestPath,
  required String activeFilePath,
  required DocumentState document,
  required PlatformManagerBundle platformManagers,
}) async {
  final fileSystem = platformManagers.fileSystem;
  if (!_isAbsolutePath(activeFilePath)) {
    return _PreparedProjectWorkflowInput(
      workspaceRoot: projectGraph.workspaceRoot,
      manifestPath: manifestPath,
    );
  }
  final shouldUseOverlay = await _shouldUseDocumentOverlay(
    activeFilePath: activeFilePath,
    document: document,
    fileSystem: fileSystem,
  );
  if (!_pathIsWithinRoot(activeFilePath, projectGraph.workspaceRoot)) {
    if (shouldUseOverlay) {
      throw _ExecutionOverlayException(
        'Active file path $activeFilePath resolves outside workspace root ${projectGraph.workspaceRoot}.',
      );
    }
    return _PreparedProjectWorkflowInput(
      workspaceRoot: projectGraph.workspaceRoot,
      manifestPath: manifestPath,
    );
  }
  if (!shouldUseOverlay) {
    return _PreparedProjectWorkflowInput(
      workspaceRoot: projectGraph.workspaceRoot,
      manifestPath: manifestPath,
    );
  }

  final overlay = await _createDocumentOverlay(
    sourceRoot: projectGraph.workspaceRoot,
    activeFilePath: activeFilePath,
    document: document,
    fileSystem: fileSystem,
    temporaryRoot: platformManagers.resource.snapshot().systemTempPath,
  );
  return _PreparedProjectWorkflowInput(
    workspaceRoot: overlay.pathOverlay.overlayRoot,
    manifestPath:
        overlay.pathOverlay.overlayPathForSource(manifestPath) ?? manifestPath,
    temporaryDirectory: overlay.temporaryDirectory,
    pathOverlay: overlay.pathOverlay,
  );
}

Future<void> _cleanupPreparedProjectWorkflowInput(
  _PreparedProjectWorkflowInput input, {
  required FileSystemManager fileSystem,
}) async {
  final temporaryDirectory = input.temporaryDirectory;
  if (temporaryDirectory == null) {
    return;
  }
  await _deleteTemporaryOverlayRoot(temporaryDirectory, fileSystem: fileSystem);
}

Future<bool> _shouldUseDocumentOverlay({
  required String activeFilePath,
  required DocumentState document,
  required FileSystemManager fileSystem,
}) async {
  if (!_isAbsolutePath(activeFilePath)) {
    return false;
  }
  try {
    if (!await fileSystem.exists(activeFilePath)) {
      return true;
    }
    return await fileSystem.readText(activeFilePath) != document.text;
  } on VityodFileSystemException catch (error) {
    if (error.code == 'workspace_root_escape') {
      throw _ExecutionOverlayException(
        'Active file path $activeFilePath resolves outside workspace root.',
      );
    }
    return true;
  } on Object {
    return true;
  }
}

Future<String> _singleFileOverlayRoot(
  String activeFilePath, {
  required FileSystemManager fileSystem,
}) async {
  final activeParent = _pathParent(fileSystem.normalizePath(activeFilePath));
  var current = activeParent;
  while (true) {
    final hasConfig =
        await fileSystem.exists(
          fileSystem.joinPath(<String>[current, 'styio.toml']),
        ) ||
        await fileSystem.exists(
          fileSystem.joinPath(<String>[current, '.styio.toml']),
        );
    if (hasConfig) {
      return current;
    }
    final parent = _pathParent(current);
    if (_samePath(parent, current)) {
      return activeParent;
    }
    current = parent;
  }
}

Future<({String temporaryDirectory, _PathOverlayMapping pathOverlay})>
_createDocumentOverlay({
  required String sourceRoot,
  required String activeFilePath,
  required DocumentState document,
  required FileSystemManager fileSystem,
  required String temporaryRoot,
}) async {
  final resolvedSourceRoot = fileSystem.normalizePath(sourceRoot);
  String? overlayRoot;
  try {
    overlayRoot = await _createTemporaryOverlayDirectory(
      fileSystem: fileSystem,
      temporaryRoot: temporaryRoot,
      label: _pathBasename(resolvedSourceRoot),
    );
    final snapshotBudget = _OverlaySnapshotBudget();
    await _expandOverlayPathChain(
      sourceRoot: resolvedSourceRoot,
      overlayRoot: overlayRoot,
      activeFilePath: activeFilePath,
      documentText: document.text,
      snapshotBudget: snapshotBudget,
      fileSystem: fileSystem,
    );
    return (
      temporaryDirectory: overlayRoot,
      pathOverlay: _PathOverlayMapping(
        sourceRoot: resolvedSourceRoot,
        overlayRoot: overlayRoot,
      ),
    );
  } on _ExecutionOverlayException {
    await _deleteTemporaryOverlayRoot(overlayRoot, fileSystem: fileSystem);
    rethrow;
  } on VityodFileSystemException catch (error) {
    await _deleteTemporaryOverlayRoot(overlayRoot, fileSystem: fileSystem);
    if (error.code == 'workspace_root_escape') {
      throw _ExecutionOverlayException(
        'Active file path $activeFilePath resolves outside workspace root $sourceRoot.',
      );
    }
    throw _ExecutionOverlayException(
      'Execution overlay preparation failed: $error',
    );
  } on Object catch (error) {
    await _deleteTemporaryOverlayRoot(overlayRoot, fileSystem: fileSystem);
    throw _ExecutionOverlayException(
      'Execution overlay preparation failed: $error',
    );
  }
}

Future<void> _deleteTemporaryOverlayRoot(
  String? overlayRoot, {
  required FileSystemManager fileSystem,
}) async {
  if (overlayRoot == null) {
    return;
  }
  try {
    if (await fileSystem.exists(overlayRoot)) {
      await fileSystem.delete(overlayRoot, recursive: true);
    }
  } on Object {
    // The overlay has already failed closed; cleanup failure should not mask it.
  }
}

Future<String> _createTemporaryOverlayDirectory({
  required FileSystemManager fileSystem,
  required String temporaryRoot,
  required String label,
}) async {
  final safeLabel = label.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  for (var attempt = 0; attempt < 8; attempt += 1) {
    final sequence = ++_executionTempSequence;
    final candidate = fileSystem.joinPath(<String>[
      temporaryRoot,
      'Vityo-${safeLabel.isEmpty ? 'run' : safeLabel}-${DateTime.now().microsecondsSinceEpoch}-$sequence',
    ]);
    try {
      if (await fileSystem.exists(candidate)) {
        continue;
      }
      await fileSystem.createDirectory(candidate);
      return candidate;
    } on Object {
      if (attempt == 7) rethrow;
    }
  }
  throw const _ExecutionOverlayException(
    'Execution overlay could not allocate a temporary directory.',
  );
}

Future<void> _expandOverlayPathChain({
  required String sourceRoot,
  required String overlayRoot,
  required String activeFilePath,
  required String documentText,
  required _OverlaySnapshotBudget snapshotBudget,
  required FileSystemManager fileSystem,
}) async {
  final relativePath = _relativePathWithinRoot(activeFilePath, sourceRoot);
  if (relativePath == null) {
    throw _ExecutionOverlayException(
      'Active file path $activeFilePath resolves outside execution overlay root $sourceRoot.',
    );
  }

  await _copySnapshotChildrenIntoOverlay(
    sourceDirectory: sourceRoot,
    overlayDirectory: overlayRoot,
    snapshotBudget: snapshotBudget,
    fileSystem: fileSystem,
  );

  final overlayFilePath = _appendRelativePath(overlayRoot, relativePath);
  snapshotBudget.accountDocument(overlayFilePath, documentText);
  await _deleteOverlayEntity(overlayFilePath, fileSystem: fileSystem);
  await fileSystem.writeText(overlayFilePath, documentText);
}

Future<void> _copySnapshotChildrenIntoOverlay({
  required String sourceDirectory,
  required String overlayDirectory,
  required _OverlaySnapshotBudget snapshotBudget,
  required FileSystemManager fileSystem,
}) async {
  if (!await fileSystem.exists(sourceDirectory)) {
    await fileSystem.createDirectory(overlayDirectory);
    return;
  }
  await fileSystem.createDirectory(overlayDirectory);
  final entries = await fileSystem.list(sourceDirectory);
  for (final entity in entries) {
    final name = _pathBasename(entity.path);
    if (name.isEmpty) {
      continue;
    }
    final overlayPath = _appendRelativePath(overlayDirectory, name);
    if (await fileSystem.exists(overlayPath)) {
      continue;
    }
    await _copySnapshotEntity(
      sourcePath: entity.path,
      overlayPath: overlayPath,
      snapshotBudget: snapshotBudget,
      fileSystem: fileSystem,
      snapshot: entity,
    );
  }
}

Future<void> _copySnapshotEntity({
  required String sourcePath,
  required String overlayPath,
  required _OverlaySnapshotBudget snapshotBudget,
  required FileSystemManager fileSystem,
  FileSystemEntitySnapshot? snapshot,
}) async {
  final entity = snapshot ?? await fileSystem.stat(sourcePath);
  switch (entity.type) {
    case VityoFileSystemEntityType.directory:
      await _copySnapshotDirectory(
        sourceDirectory: sourcePath,
        destinationDirectory: overlayPath,
        snapshotBudget: snapshotBudget,
        fileSystem: fileSystem,
      );
      return;
    case VityoFileSystemEntityType.file:
      snapshotBudget.accountFile(entity);
      await fileSystem.writeBytes(
        overlayPath,
        await fileSystem.readBytes(sourcePath),
      );
      return;
    case VityoFileSystemEntityType.link:
    case VityoFileSystemEntityType.notFound:
    case VityoFileSystemEntityType.other:
      return;
  }
}

Future<void> _copySnapshotDirectory({
  required String sourceDirectory,
  required String destinationDirectory,
  required _OverlaySnapshotBudget snapshotBudget,
  required FileSystemManager fileSystem,
}) async {
  snapshotBudget.accountDirectory(sourceDirectory);
  await fileSystem.createDirectory(destinationDirectory);
  final entries = await fileSystem.list(sourceDirectory);
  for (final entity in entries) {
    final name = _pathBasename(entity.path);
    if (name.isEmpty) {
      continue;
    }
    final destinationPath = _appendRelativePath(destinationDirectory, name);
    await _copySnapshotEntity(
      sourcePath: entity.path,
      overlayPath: destinationPath,
      snapshotBudget: snapshotBudget,
      fileSystem: fileSystem,
      snapshot: entity,
    );
  }
}

Future<void> _deleteOverlayEntity(
  String path, {
  required FileSystemManager fileSystem,
}) async {
  final entity = await fileSystem.stat(path);
  if (!entity.exists) return;
  await fileSystem.delete(path, recursive: entity.isDirectory);
}

String _pathParent(String path) {
  final normalized = _normalizeAbsolutePath(path);
  final separator = _pathSeparatorFor(normalized);
  final rootLength = _portableRootLength(normalized);
  var end = normalized.length;
  while (end > rootLength && normalized.substring(end - 1, end) == separator) {
    end -= 1;
  }
  final index = normalized.lastIndexOf(separator, end - 1);
  if (index < rootLength) return normalized.substring(0, rootLength);
  if (index == 0) return separator;
  return normalized.substring(0, index);
}

String _pathBasename(String path) {
  final normalized = _normalizeAbsolutePath(path);
  final separator = _pathSeparatorFor(normalized);
  final trimmed = normalized.endsWith(separator) && normalized.length > 1
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf(separator);
  return index < 0 ? trimmed : trimmed.substring(index + 1);
}

_ParsedDiagnostics _parseOutputChannel(
  String output, {
  required String documentText,
  required String activeFilePath,
  String Function(String path)? normalizePath,
}) {
  final diagnostics = <Diagnostic>[];
  final logEvents = <ExecutionLogEvent>[];
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final record = _parseDiagnosticLine(
      trimmed,
      documentText: documentText,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
    if (record?.diagnostic != null) {
      diagnostics.add(record!.diagnostic!);
      continue;
    }
    if (record?.logMessage != null) {
      logEvents.add(ExecutionLogEvent(message: record!.logMessage!));
      continue;
    }
    logEvents.add(ExecutionLogEvent(message: trimmed));
  }
  return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
}

List<String> _packageArgs(String packageName) {
  if (packageName.isEmpty) {
    return const <String>[];
  }
  return <String>['--package', packageName];
}

String? _packageNameForPath({
  required ProjectGraphSnapshot projectGraph,
  required String activeFilePath,
}) {
  if (!_isAbsolutePath(activeFilePath)) {
    return null;
  }

  for (final package in projectGraph.packages) {
    if (_pathIsWithinRoot(activeFilePath, package.rootPath)) {
      return package.packageName;
    }
  }
  return null;
}

bool _pathIsWithinRoot(String path, String rootPath) {
  if (!_isAbsolutePath(path) || !_isAbsolutePath(rootPath)) {
    return false;
  }

  return _pathHasRootPrefix(
    _normalizeAbsolutePath(path),
    _normalizeAbsolutePath(rootPath),
  );
}

String? _relativePathWithinRoot(String path, String rootPath) {
  if (!_isAbsolutePath(path) || !_isAbsolutePath(rootPath)) {
    return null;
  }
  final absolutePath = _normalizeAbsolutePath(path);
  final absoluteRoot = _normalizeAbsolutePath(rootPath);
  if (!_pathHasRootPrefix(absolutePath, absoluteRoot)) {
    return null;
  }
  if (_samePath(absolutePath, absoluteRoot)) {
    return '';
  }
  final separator = _pathSeparatorFor(absoluteRoot);
  final rootPrefix = absoluteRoot.endsWith(separator)
      ? absoluteRoot
      : '$absoluteRoot$separator';
  return absolutePath.substring(rootPrefix.length);
}

String _canonicalPathForContainment(String path) {
  return _normalizeAbsolutePath(path);
}

bool _pathHasRootPrefix(String path, String rootPath) {
  if (_samePath(path, rootPath)) {
    return true;
  }
  final separator = _pathSeparatorFor(rootPath);
  final rootPrefix = rootPath.endsWith(separator)
      ? rootPath
      : '$rootPath$separator';
  return _pathStartsWith(path, rootPrefix);
}

bool _samePath(String left, String right) {
  if (!_isWindowsPath(left) && !_isWindowsPath(right)) {
    return left == right;
  }
  return left.toLowerCase() == right.toLowerCase();
}

bool _sameDiagnosticFile(String left, String right) {
  if (!_isAbsolutePath(left) || !_isAbsolutePath(right)) {
    return left == right;
  }
  return _samePath(
    _canonicalPathForContainment(left),
    _canonicalPathForContainment(right),
  );
}

bool _pathStartsWith(String path, String prefix) {
  if (!_isWindowsPath(path) && !_isWindowsPath(prefix)) {
    return path.startsWith(prefix);
  }
  return path.toLowerCase().startsWith(prefix.toLowerCase());
}

String _normalizeAbsolutePath(String path) {
  if (!_isAbsolutePath(path)) return path;
  final windows = _isWindowsPath(path);
  final separator = windows ? r'\' : '/';
  var source = windows
      ? path.replaceAll('/', r'\')
      : path.replaceAll(r'\', '/');
  final drive = windows && RegExp(r'^[A-Za-z]:').hasMatch(source)
      ? source.substring(0, 2)
      : '';
  final unc = windows && source.startsWith(r'\\');
  if (drive.isNotEmpty) source = source.substring(2);
  final parts = <String>[];
  for (final segment in source.split(separator)) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  if (windows) {
    final root = drive.isNotEmpty
        ? '$drive$separator'
        : (unc ? r'\\' : separator);
    return parts.isEmpty ? root : '$root${parts.join(separator)}';
  }
  return parts.isEmpty ? '/' : '/${parts.join('/')}';
}

String _appendRelativePath(String rootPath, String relativePath) {
  if (relativePath.isEmpty) {
    return rootPath;
  }
  final separator = _pathSeparatorFor(rootPath);
  final normalizedRelative = relativePath.replaceAll(
    separator == '/' ? r'\' : '/',
    separator,
  );
  if (rootPath.endsWith(separator)) {
    return '$rootPath$normalizedRelative';
  }
  return '$rootPath$separator$normalizedRelative';
}

bool _isWindowsPath(String path) =>
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) || path.startsWith(r'\\');

String _pathSeparatorFor(String path) => _isWindowsPath(path) ? r'\' : '/';

int _portableRootLength(String path) {
  if (RegExp(r'^[A-Za-z]:\\').hasMatch(path)) return 3;
  if (path.startsWith(r'\\')) return 2;
  return path.startsWith('/') ? 1 : 0;
}

_ParsedDiagnosticRecord? _parseDiagnosticLine(
  String line, {
  required String documentText,
  required String activeFilePath,
  String Function(String path)? normalizePath,
}) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return null;
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return _parseDiagnosticObject(
      decoded,
      allowPayloadShape: false,
      documentText: documentText,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
  } on FormatException {
    return null;
  }
}

_ParsedDiagnosticRecord? _parseDiagnosticObject(
  Map<String, dynamic> decoded, {
  required bool allowPayloadShape,
  required String documentText,
  required String activeFilePath,
  String Function(String path)? normalizePath,
}) {
  if (decoded['eventKind'] == 'diagnostic.emitted') {
    final payload = decoded['payload'];
    if (payload is Map<String, dynamic>) {
      return _parseDiagnosticObject(
        payload,
        allowPayloadShape: true,
        documentText: documentText,
        activeFilePath: activeFilePath,
        normalizePath: normalizePath,
      );
    }
  }

  final message = _diagnosticMessage(decoded);
  if (message == null || message.isEmpty) {
    return null;
  }

  final category = _stringValue(decoded['category']);
  final severityLabel = _stringValue(decoded['severity']);
  final kind = _stringValue(decoded['kind'])?.toLowerCase();
  final type = _stringValue(decoded['type'])?.toLowerCase();
  final range = _diagnosticRangeFromPayload(
    decoded,
    activeFilePath: activeFilePath,
    normalizePath: normalizePath,
  );
  final hasDiagnosticMarker =
      category != null ||
      kind == 'diagnostic' ||
      type == 'diagnostic' ||
      decoded['diagnostic'] == true ||
      decoded['eventKind'] == 'diagnostic.emitted';
  final hasPayloadShape =
      severityLabel != null ||
      _stringValue(decoded['code']) != null ||
      _stringValue(decoded['subcode']) != null ||
      _stringValue(decoded['file']) != null ||
      decoded.containsKey('range') ||
      decoded.containsKey('span') ||
      decoded.containsKey('location') ||
      decoded.containsKey('offset') ||
      decoded.containsKey('length');
  if (!hasDiagnosticMarker &&
      range == null &&
      (!allowPayloadShape || !hasPayloadShape)) {
    return null;
  }

  final severity = severityLabel == null || severityLabel.isEmpty
      ? _severityFromCategory(category ?? 'diagnostic')
      : _severityFromCategory(severityLabel);
  final code = _diagnosticCode(decoded, category: category);
  final rawFilePath = _stringValue(decoded['file']);
  final filePath = rawFilePath == null
      ? null
      : (normalizePath == null ? rawFilePath : normalizePath(rawFilePath));
  final displayMessage = _decorateDiagnosticMessage(
    message,
    filePath: filePath,
    activeFilePath: activeFilePath,
  );
  if (filePath != null &&
      filePath.isNotEmpty &&
      activeFilePath.isNotEmpty &&
      !_sameDiagnosticFile(filePath, activeFilePath)) {
    return _ParsedDiagnosticRecord(logMessage: displayMessage);
  }
  return _ParsedDiagnosticRecord(
    diagnostic: Diagnostic(
      severity: severity,
      code: code,
      message: displayMessage,
      range: range ?? const SourceRange(start: 0, end: 0),
    ),
  );
}

String? _diagnosticMessage(Map<String, dynamic> decoded) {
  for (final key in const <String>[
    'message',
    'text',
    'detail',
    'reason',
    'raw',
  ]) {
    final value = _messageValue(decoded[key]);
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String? _messageValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is Map<String, dynamic>) {
    final parts = <String>[];
    for (final key in const <String>['text', 'summary', 'detail', 'message']) {
      final nested = _messageValue(value[key]);
      if (nested != null && !parts.contains(nested)) {
        parts.add(nested);
      }
    }
    if (parts.isNotEmpty) {
      return parts.join(' ');
    }
  }
  return null;
}

String _diagnosticCode(
  Map<String, dynamic> decoded, {
  required String? category,
}) {
  final primary = _stringValue(decoded['code']) ?? category ?? 'diagnostic';
  final subcode = _stringValue(decoded['subcode']);
  if (subcode == null || subcode.isEmpty) {
    return primary;
  }
  return '$primary:$subcode';
}

String _decorateDiagnosticMessage(
  String message, {
  required String? filePath,
  required String activeFilePath,
}) {
  if (filePath == null || filePath.isEmpty || filePath == activeFilePath) {
    return message;
  }
  if (message.startsWith('$filePath: ')) {
    return message;
  }
  return '$filePath: $message';
}

SourceRange? _diagnosticRangeFromPayload(
  Map<String, dynamic> decoded, {
  required String activeFilePath,
  String Function(String path)? normalizePath,
}) {
  final rawFilePath = _stringValue(decoded['file']);
  final filePath = rawFilePath == null
      ? null
      : (normalizePath == null ? rawFilePath : normalizePath(rawFilePath));
  if (filePath != null &&
      filePath.isNotEmpty &&
      activeFilePath.isNotEmpty &&
      !_sameDiagnosticFile(filePath, activeFilePath)) {
    return null;
  }

  return _sourceRangeFromObject(decoded['range']) ??
      _sourceRangeFromObject(decoded['span']) ??
      _sourceRangeFromObject(decoded['location']) ??
      _sourceRangeFromOffsetFields(decoded);
}

SourceRange? _sourceRangeFromObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }

  final directRange = _sourceRangeFromOffsetFields(value);
  if (directRange != null) {
    return directRange;
  }

  final start = _offsetFromObject(value['start']);
  final end = _offsetFromObject(value['end']);
  if (start != null && end != null) {
    return _normalizedRange(start, end);
  }

  return null;
}

SourceRange? _sourceRangeFromOffsetFields(Map<String, dynamic> value) {
  final start = _intValue(value['start']) ?? _intValue(value['startOffset']);
  final end = _intValue(value['end']) ?? _intValue(value['endOffset']);
  if (start != null && end != null) {
    return _normalizedRange(start, end);
  }

  final offset = _intValue(value['offset']);
  final length = _intValue(value['length']);
  if (offset != null && length != null) {
    final safeLength = length < 0 ? 0 : length;
    return SourceRange(start: offset, end: offset + safeLength);
  }

  return null;
}

int? _offsetFromObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return _intValue(value['offset']) ??
        _intValue(value['index']) ??
        _intValue(value['position']) ??
        _intValue(value['value']);
  }
  return _intValue(value);
}

SourceRange _normalizedRange(int start, int end) {
  if (end < start) {
    return SourceRange(start: end, end: start);
  }
  return SourceRange(start: start, end: end);
}

String? _resolveWorkflowArtifactPath(
  Object? artifactPath, {
  required String workspaceRoot,
}) {
  final path = _stringValue(artifactPath);
  if (path == null || path.isEmpty) {
    return null;
  }
  if (_isAbsolutePath(path)) {
    return path;
  }
  return _joinPath(workspaceRoot, path);
}

String? _resolveWorkflowDiagnosticsPath(
  Object? diagnosticsPath, {
  required String workspaceRoot,
}) {
  return _resolveWorkflowArtifactPath(
    diagnosticsPath,
    workspaceRoot: workspaceRoot,
  );
}

String? _stringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) {
    return '$value';
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DiagnosticSeverity _severityFromCategory(String category) {
  final normalized = category.toLowerCase();
  if (normalized.contains('runtime') || normalized.contains('type')) {
    return DiagnosticSeverity.error;
  }
  if (normalized.contains('warning')) {
    return DiagnosticSeverity.warning;
  }
  return DiagnosticSeverity.error;
}

bool _isAbsolutePath(String path) {
  return path.startsWith('/') ||
      path.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String _joinPath(String base, String child) {
  var result = base;
  for (final segment
      in child
          .replaceAll('\\', '/')
          .split('/')
          .where((segment) => segment.isNotEmpty && segment != '.')) {
    result = _appendRelativePath(result, segment);
  }
  return result;
}
