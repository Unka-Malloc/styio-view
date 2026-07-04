import 'dart:convert';
import 'dart:io';

import '../editor/document_state.dart';
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
    'No local styio binary was resolved. Set VITYO_STYIO_BIN or install styio through pafio.';

const int _executionOverlaySnapshotMaxEntries = 20000;
const int _executionOverlaySnapshotMaxBytes = 256 * 1024 * 1024;

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

class _LocalCliExecutionAdapter implements ExecutionAdapter {
  const _LocalCliExecutionAdapter({
    required this.platformTarget,
    required this.projectGraph,
    required this.compiler,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot projectGraph;
  final CompilerHandshakeSnapshot? compiler;

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
    if (resolvedCompiler == null) {
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
      );
    }

    final _PreparedExecutionInput preparedInput;
    try {
      preparedInput = await _prepareSingleFileExecutionInput(
        activeFilePath: activeFilePath,
        document: document,
      );
    } on _ExecutionOverlayException catch (error) {
      return _blockedRunExecutionSession(
        sessionId: 'execution-overlay-blocked',
        message: error.message,
      );
    }
    try {
      final result = await Process.run(resolvedCompiler.binaryPath, <String>[
        '--file',
        preparedInput.filePath,
        '--error-format=jsonl',
      ]);

      final normalizedPath = preparedInput.pathOverlay?.normalize;
      final stdoutChannel = _parseOutputChannel(
        '${result.stdout}',
        documentText: document.text,
        activeFilePath: activeFilePath,
        normalizePath: normalizedPath,
      );
      final stderrChannel = _parseOutputChannel(
        '${result.stderr}',
        documentText: document.text,
        activeFilePath: activeFilePath,
        normalizePath: normalizedPath,
      );

      return ExecutionSession(
        sessionId: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: 'run',
        status: result.exitCode == 0
            ? ExecutionSessionStatus.succeeded
            : ExecutionSessionStatus.failed,
        statusMessage: result.exitCode == 0
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
      await _cleanupPreparedExecutionInput(preparedInput);
    }
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
          'Published CLI contract currently provides machine-info and jsonl diagnostics only.',
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
          ? const <int>[1]
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
  final Directory? temporaryDirectory;
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
  final Directory? temporaryDirectory;
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

  Future<void> accountFile(File file) async {
    _accountEntry(file.path);
    final bytes = await file.length();
    _bytes += bytes;
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
}) async {
  final manifestPath = projectGraph.manifestPath;
  if (manifestPath == null) {
    return _blockedRunExecutionSession(
      sessionId: 'missing-manifest',
      message: 'Project execution requires a resolved pafio manifest.',
    );
  }

  final pafioBinary = await resolvePafioBinary(
    workspaceRoot: projectGraph.workspaceRoot,
  );
  if (pafioBinary == null) {
    return _blockedRunExecutionSession(
      sessionId: 'missing-pafio-binary',
      message: missingLocalPafioBinaryMessage,
    );
  }
  final useWorkflowPayloads = await _supportsPafioWorkflowSuccessPayloads(
    pafioBinary,
  );

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
    );
  } on _ExecutionOverlayException catch (error) {
    return _blockedRunExecutionSession(
      sessionId: 'execution-overlay-blocked',
      message: error.message,
    );
  }
  final normalizedPath = preparedInput.pathOverlay?.normalize;

  try {
    final result = await Process.run(pafioBinary, <String>[
      if (useWorkflowPayloads) '--json',
      workflow.command,
      '--manifest-path',
      preparedInput.manifestPath,
      '--styio-bin',
      compiler.binaryPath,
      ...workflow.args,
    ], workingDirectory: preparedInput.workspaceRoot);

    final stdout = '${result.stdout}';
    final stderr = '${result.stderr}';
    if (useWorkflowPayloads && result.exitCode == 0) {
      final session = await _sessionFromWorkflowSuccessPayload(
        stdout: stdout,
        stderr: stderr,
        workflow: workflow,
        document: document,
        activeFilePath: activeFilePath,
        workspaceRoot: preparedInput.workspaceRoot,
        normalizePath: normalizedPath,
      );
      if (session != null) {
        return session;
      }
    }
    final failurePayload =
        parseJsonObjectPayload(stderr) ?? parseJsonObjectPayload(stdout);
    final sessionId =
        _workflowSessionIdFromPayload(failurePayload) ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final runtimeEvents = await _readWorkflowRuntimeEvents(
      rawRuntimeEvents: failurePayload == null
          ? null
          : failurePayload['runtime_events'],
      runtimeEventsPath: failurePayload == null
          ? null
          : failurePayload['runtime_events_path'],
      sessionId: sessionId,
      workspaceRoot: preparedInput.workspaceRoot,
      normalizePath: normalizedPath,
    );
    if (runtimeEvents.isEmpty) {
      clearRuntimeEventsForSession(sessionId);
    } else {
      recordRuntimeEventsForSession(sessionId, runtimeEvents);
    }
    final payloadDiagnostics = _parsePayloadDiagnostics(
      failurePayload?['diagnostics'],
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizedPath,
    );
    final stdoutChannel = _parseOutputChannel(
      stdout,
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizedPath,
    );
    final stderrChannel = _parseOutputChannel(
      stderr,
      documentText: document.text,
      activeFilePath: activeFilePath,
      normalizePath: normalizedPath,
    );
    return ExecutionSession(
      sessionId: sessionId,
      kind: workflow.kind,
      status: result.exitCode == 0
          ? ExecutionSessionStatus.succeeded
          : ExecutionSessionStatus.failed,
      statusMessage: result.exitCode == 0
          ? workflow.successMessage
          : (failurePayload?['message'] as String? ??
                'pafio ${workflow.command} exited with code ${result.exitCode}.'),
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
  } on ProcessException catch (error) {
    return ExecutionSession(
      sessionId: 'pafio-process-error',
      kind: workflow.kind,
      status: ExecutionSessionStatus.failed,
      statusMessage: 'Failed to execute pafio: ${error.message}',
      diagnostics: const <Diagnostic>[],
      stdoutEvents: const <ExecutionLogEvent>[],
      stderrEvents: const <ExecutionLogEvent>[],
      unitRange: SourceRange(start: 0, end: document.length),
    );
  } finally {
    await _cleanupPreparedProjectWorkflowInput(preparedInput);
  }
}

Future<bool> _supportsPafioWorkflowSuccessPayloads(String pafioBinary) async {
  try {
    final result = await Process.run(pafioBinary, const <String>[
      'machine-info',
      '--json',
    ]);
    if (result.exitCode != 0) {
      return false;
    }

    final decoded = jsonDecode('${result.stdout}');
    if (decoded is! Map<String, dynamic>) {
      return false;
    }

    final featureFlags = decoded['feature_flags'];
    if (featureFlags is Map<String, dynamic> &&
        featureFlags['workflow_success_payloads'] == true) {
      return true;
    }

    final contracts = decoded['supported_contract_versions'];
    if (contracts is Map<String, dynamic>) {
      final versions = contracts['workflow_success_payloads'];
      if (versions is List && versions.contains(1)) {
        return true;
      }
    }
  } on ProcessException {
    return false;
  } on FormatException {
    return false;
  }

  return false;
}

Future<ExecutionSession?> _sessionFromWorkflowSuccessPayload({
  required String stdout,
  required String stderr,
  required _ProjectWorkflowSelection workflow,
  required DocumentState document,
  required String activeFilePath,
  required String workspaceRoot,
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
    final runtimeEvents = await _readWorkflowRuntimeEvents(
      rawRuntimeEvents: decoded['runtime_events'],
      runtimeEventsPath: decoded['runtime_events_path'],
      sessionId: sessionId,
      workspaceRoot: workspaceRoot,
      normalizePath: normalizePath,
    );
    if (runtimeEvents.isEmpty) {
      clearRuntimeEventsForSession(sessionId);
    } else {
      recordRuntimeEventsForSession(sessionId, runtimeEvents);
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
      unitRange: SourceRange(start: 0, end: document.length),
    );
  } on FormatException {
    return null;
  }
}

Future<_ParsedDiagnostics> _readWorkflowDiagnostics({
  required Object? rawDiagnostics,
  required Object? diagnosticsPath,
  required String workspaceRoot,
  required String documentText,
  required String activeFilePath,
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
    final file = File(resolvedDiagnosticsPath);
    if (!await file.exists()) {
      return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
    }
    final fileDiagnostics = _parseOutputChannel(
      await file.readAsString(),
      documentText: documentText,
      activeFilePath: activeFilePath,
      normalizePath: normalizePath,
    );
    diagnostics.addAll(fileDiagnostics.diagnostics);
    logEvents.addAll(fileDiagnostics.logEvents);
  } on FileSystemException {
    // Keep inline diagnostics when the artifact cannot be read.
  }

  return _ParsedDiagnostics(diagnostics: diagnostics, logEvents: logEvents);
}

Future<List<RuntimeEventEnvelope>> _readWorkflowRuntimeEvents({
  required Object? rawRuntimeEvents,
  required Object? runtimeEventsPath,
  required String sessionId,
  required String workspaceRoot,
  String Function(String path)? normalizePath,
}) async {
  final inlineEvents = _parsePayloadRuntimeEvents(
    rawRuntimeEvents,
    sessionId: sessionId,
    normalizePath: normalizePath,
  );
  if (inlineEvents.isNotEmpty) {
    return inlineEvents;
  }

  final resolvedRuntimeEventsPath = _resolveWorkflowArtifactPath(
    runtimeEventsPath,
    workspaceRoot: workspaceRoot,
  );
  if (resolvedRuntimeEventsPath == null) {
    return const <RuntimeEventEnvelope>[];
  }

  try {
    final file = File(resolvedRuntimeEventsPath);
    if (!await file.exists()) {
      return const <RuntimeEventEnvelope>[];
    }
    return _parseRuntimeEventLines(
      await file.readAsString(),
      sessionId: sessionId,
      normalizePath: normalizePath,
    );
  } on FileSystemException {
    return const <RuntimeEventEnvelope>[];
  }
}

List<RuntimeEventEnvelope> _parsePayloadRuntimeEvents(
  Object? rawRuntimeEvents, {
  required String sessionId,
  String Function(String path)? normalizePath,
}) {
  if (rawRuntimeEvents is! List) {
    return const <RuntimeEventEnvelope>[];
  }

  final events = <RuntimeEventEnvelope>[];
  for (final item in rawRuntimeEvents) {
    if (item is! Map<String, dynamic>) {
      continue;
    }
    final event = _parseRuntimeEventObject(
      item,
      sessionId: sessionId,
      normalizePath: normalizePath,
    );
    if (event != null) {
      events.add(event);
    }
  }
  return events;
}

List<RuntimeEventEnvelope> _parseRuntimeEventLines(
  String text, {
  required String sessionId,
  String Function(String path)? normalizePath,
}) {
  final events = <RuntimeEventEnvelope>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) {
      continue;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final event = _parseRuntimeEventObject(
        decoded,
        sessionId: sessionId,
        normalizePath: normalizePath,
      );
      if (event != null) {
        events.add(event);
      }
    } on FormatException {
      continue;
    }
  }
  return events;
}

RuntimeEventEnvelope? _parseRuntimeEventObject(
  Map<String, dynamic> decoded, {
  required String sessionId,
  String Function(String path)? normalizePath,
}) {
  final eventKind =
      _stringValue(decoded['eventKind']) ?? _stringValue(decoded['event_kind']);
  if (eventKind == null || eventKind.isEmpty) {
    return null;
  }

  final resolvedSessionId =
      _stringValue(decoded['session_id']) ??
      _stringValue(decoded['sessionId']) ??
      sessionId;
  final timestampValue = _stringValue(decoded['timestamp']);
  final payload = decoded['payload'];
  final payloadMap = payload is Map<String, dynamic>
      ? Map<String, Object?>.from(payload)
      : <String, Object?>{};
  final rawFilePath = payloadMap['file'];
  if (rawFilePath is String && normalizePath != null) {
    payloadMap['file'] = normalizePath(rawFilePath);
  }
  return RuntimeEventEnvelope(
    schemaVersion:
        _intValue(decoded['schema_version'] ?? decoded['schemaVersion']) ?? 1,
    sessionId: resolvedSessionId,
    sequence: _intValue(decoded['sequence']) ?? 0,
    timestamp:
        DateTime.tryParse(timestampValue ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    eventKind: eventKind,
    origin: _stringValue(decoded['origin']) ?? 'styio.runtime',
    payload: payloadMap,
  );
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
}) async {
  if (_isAbsolutePath(activeFilePath)) {
    if (!await _shouldUseDocumentOverlay(
      activeFilePath: activeFilePath,
      document: document,
    )) {
      return _PreparedExecutionInput(filePath: activeFilePath);
    }

    final sourceRoot = await _singleFileOverlayRoot(activeFilePath);
    final overlay = await _createDocumentOverlay(
      sourceRoot: sourceRoot,
      activeFilePath: activeFilePath,
      document: document,
    );
    return _PreparedExecutionInput(
      filePath:
          overlay.pathOverlay.overlayPathForSource(activeFilePath) ??
          activeFilePath,
      temporaryDirectory: overlay.temporaryDirectory,
      pathOverlay: overlay.pathOverlay,
    );
  }

  final tempDirectory = await Directory.systemTemp.createTemp('Vityo-run-');
  final tempFile = File(
    '${tempDirectory.path}${Platform.pathSeparator}main.styio',
  );
  await tempFile.writeAsString(document.text);
  return _PreparedExecutionInput(
    filePath: tempFile.path,
    temporaryDirectory: tempDirectory,
  );
}

Future<void> _cleanupPreparedExecutionInput(
  _PreparedExecutionInput input,
) async {
  final temporaryDirectory = input.temporaryDirectory;
  if (temporaryDirectory == null) {
    return;
  }
  if (await temporaryDirectory.exists()) {
    await temporaryDirectory.delete(recursive: true);
  }
}

Future<_PreparedProjectWorkflowInput> _prepareProjectWorkflowInput({
  required ProjectGraphSnapshot projectGraph,
  required String manifestPath,
  required String activeFilePath,
  required DocumentState document,
}) async {
  if (!_isAbsolutePath(activeFilePath)) {
    return _PreparedProjectWorkflowInput(
      workspaceRoot: projectGraph.workspaceRoot,
      manifestPath: manifestPath,
    );
  }
  final shouldUseOverlay = await _shouldUseDocumentOverlay(
    activeFilePath: activeFilePath,
    document: document,
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
  _PreparedProjectWorkflowInput input,
) async {
  final temporaryDirectory = input.temporaryDirectory;
  if (temporaryDirectory == null) {
    return;
  }
  if (await temporaryDirectory.exists()) {
    await temporaryDirectory.delete(recursive: true);
  }
}

Future<bool> _shouldUseDocumentOverlay({
  required String activeFilePath,
  required DocumentState document,
}) async {
  if (!_isAbsolutePath(activeFilePath)) {
    return false;
  }
  try {
    final file = File(activeFilePath);
    if (!await file.exists()) {
      return true;
    }
    return await file.readAsString() != document.text;
  } on FileSystemException {
    return true;
  }
}

Future<String> _singleFileOverlayRoot(String activeFilePath) async {
  var current = File(activeFilePath).parent.absolute;
  while (true) {
    final hasConfig =
        await File(
          '${current.path}${Platform.pathSeparator}styio.toml',
        ).exists() ||
        await File(
          '${current.path}${Platform.pathSeparator}.styio.toml',
        ).exists();
    if (hasConfig) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      return File(activeFilePath).parent.absolute.path;
    }
    current = parent;
  }
}

Future<({Directory temporaryDirectory, _PathOverlayMapping pathOverlay})>
_createDocumentOverlay({
  required String sourceRoot,
  required String activeFilePath,
  required DocumentState document,
}) async {
  final resolvedSourceRoot = _canonicalPathForContainment(sourceRoot);
  Directory? overlayRoot;
  try {
    overlayRoot = await _createSiblingOverlayDirectory(resolvedSourceRoot);
    final snapshotBudget = _OverlaySnapshotBudget();
    await _expandOverlayPathChain(
      sourceRoot: resolvedSourceRoot,
      overlayRoot: overlayRoot.path,
      activeFilePath: activeFilePath,
      documentText: document.text,
      snapshotBudget: snapshotBudget,
    );
    return (
      temporaryDirectory: overlayRoot,
      pathOverlay: _PathOverlayMapping(
        sourceRoot: resolvedSourceRoot,
        overlayRoot: overlayRoot.path,
      ),
    );
  } on _ExecutionOverlayException {
    await _deleteTemporaryOverlayRoot(overlayRoot);
    rethrow;
  } on FileSystemException catch (error) {
    await _deleteTemporaryOverlayRoot(overlayRoot);
    throw _ExecutionOverlayException(
      'Execution overlay preparation failed: ${error.message}',
    );
  }
}

Future<void> _deleteTemporaryOverlayRoot(Directory? overlayRoot) async {
  if (overlayRoot == null || !await overlayRoot.exists()) {
    return;
  }
  try {
    await overlayRoot.delete(recursive: true);
  } on FileSystemException {
    // The overlay has already failed closed; cleanup failure should not mask it.
  }
}

Future<Directory> _createSiblingOverlayDirectory(String sourceRoot) async {
  final parentDirectory = Directory(sourceRoot).absolute.parent;
  final sourceName = Directory(sourceRoot).uri.pathSegments.lastWhere(
    (segment) => segment.isNotEmpty,
    orElse: () => 'workspace',
  );
  try {
    return parentDirectory.createTemp('.Vityo-$sourceName-');
  } on FileSystemException {
    return Directory.systemTemp.createTemp('Vityo-run-');
  }
}

Future<void> _expandOverlayPathChain({
  required String sourceRoot,
  required String overlayRoot,
  required String activeFilePath,
  required String documentText,
  required _OverlaySnapshotBudget snapshotBudget,
}) async {
  final relativePath = _relativePathWithinRoot(activeFilePath, sourceRoot);
  if (relativePath == null) {
    throw _ExecutionOverlayException(
      'Active file path $activeFilePath resolves outside execution overlay root $sourceRoot.',
    );
  }

  await _copySnapshotChildrenIntoOverlay(
    sourceDirectory: Directory(sourceRoot),
    overlayDirectory: Directory(overlayRoot),
    snapshotBudget: snapshotBudget,
  );

  final overlayFilePath = _appendRelativePath(overlayRoot, relativePath);
  final overlayFile = File(overlayFilePath);
  snapshotBudget.accountDocument(overlayFile.path, documentText);
  await _deleteOverlayEntity(overlayFile.path);
  await overlayFile.parent.create(recursive: true);
  await overlayFile.writeAsString(documentText);
}

Future<void> _copySnapshotChildrenIntoOverlay({
  required Directory sourceDirectory,
  required Directory overlayDirectory,
  required _OverlaySnapshotBudget snapshotBudget,
}) async {
  if (!await sourceDirectory.exists()) {
    await overlayDirectory.create(recursive: true);
    return;
  }
  await overlayDirectory.create(recursive: true);
  await for (final entity in sourceDirectory.list(followLinks: false)) {
    final name = entity.uri.pathSegments.isEmpty
        ? ''
        : entity.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
            orElse: () => '',
          );
    if (name.isEmpty) {
      continue;
    }
    final overlayPath = _appendRelativePath(overlayDirectory.path, name);
    if (await FileSystemEntity.type(overlayPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      continue;
    }
    await _copySnapshotEntity(
      sourcePath: entity.path,
      overlayPath: overlayPath,
      snapshotBudget: snapshotBudget,
    );
  }
}

Future<void> _copySnapshotEntity({
  required String sourcePath,
  required String overlayPath,
  required _OverlaySnapshotBudget snapshotBudget,
}) async {
  final entityType = await FileSystemEntity.type(
    sourcePath,
    followLinks: false,
  );
  switch (entityType) {
    case FileSystemEntityType.directory:
      await _copySnapshotDirectory(
        sourceDirectory: Directory(sourcePath),
        destinationDirectory: Directory(overlayPath),
        snapshotBudget: snapshotBudget,
      );
      return;
    case FileSystemEntityType.file:
      final sourceFile = File(sourcePath);
      await snapshotBudget.accountFile(sourceFile);
      await File(overlayPath).parent.create(recursive: true);
      await sourceFile.copy(overlayPath);
      return;
    case FileSystemEntityType.link:
      return;
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
    case FileSystemEntityType.notFound:
      return;
  }
}

Future<void> _copySnapshotDirectory({
  required Directory sourceDirectory,
  required Directory destinationDirectory,
  required _OverlaySnapshotBudget snapshotBudget,
}) async {
  snapshotBudget.accountDirectory(sourceDirectory.path);
  await destinationDirectory.create(recursive: true);
  await for (final entity in sourceDirectory.list(followLinks: false)) {
    final name = entity.uri.pathSegments.isEmpty
        ? ''
        : entity.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
            orElse: () => '',
          );
    if (name.isEmpty) {
      continue;
    }
    final destinationPath = _appendRelativePath(
      destinationDirectory.path,
      name,
    );
    await _copySnapshotEntity(
      sourcePath: entity.path,
      overlayPath: destinationPath,
      snapshotBudget: snapshotBudget,
    );
  }
}

Future<void> _deleteOverlayEntity(String path) async {
  final entityType = await FileSystemEntity.type(path, followLinks: false);
  switch (entityType) {
    case FileSystemEntityType.directory:
      await Directory(path).delete(recursive: true);
      return;
    case FileSystemEntityType.file:
      await File(path).delete();
      return;
    case FileSystemEntityType.link:
      await Link(path).delete();
      return;
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
    case FileSystemEntityType.notFound:
      return;
  }
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
    _canonicalPathForContainment(path),
    _canonicalPathForContainment(rootPath),
  );
}

String? _relativePathWithinRoot(String path, String rootPath) {
  if (!_isAbsolutePath(path) || !_isAbsolutePath(rootPath)) {
    return null;
  }
  final absolutePath = _canonicalPathForContainment(path);
  final absoluteRoot = _canonicalPathForContainment(rootPath);
  if (!_pathHasRootPrefix(absolutePath, absoluteRoot)) {
    return null;
  }
  if (_samePath(absolutePath, absoluteRoot)) {
    return '';
  }
  final rootPrefix = absoluteRoot.endsWith(Platform.pathSeparator)
      ? absoluteRoot
      : '$absoluteRoot${Platform.pathSeparator}';
  return absolutePath.substring(rootPrefix.length);
}

String _canonicalPathForContainment(String path) {
  final absolutePath = _normalizeAbsolutePath(path);
  final existingPath = _nearestExistingPath(absolutePath);
  if (existingPath == null) {
    return absolutePath;
  }

  final resolvedExistingPath = _resolveExistingPath(existingPath);
  final relativeRemainder = _relativeLexicalPath(
    path: absolutePath,
    rootPath: existingPath,
  );
  return _appendRelativePath(resolvedExistingPath, relativeRemainder);
}

String? _nearestExistingPath(String absolutePath) {
  var cursor = absolutePath;
  while (cursor.isNotEmpty) {
    if (FileSystemEntity.typeSync(cursor, followLinks: false) !=
        FileSystemEntityType.notFound) {
      return cursor;
    }
    final parent = Directory(cursor).parent.path;
    if (parent == cursor) {
      return null;
    }
    cursor = parent;
  }
  return null;
}

String _resolveExistingPath(String path) {
  try {
    final entityType = FileSystemEntity.typeSync(path, followLinks: false);
    return switch (entityType) {
      FileSystemEntityType.directory => _normalizeAbsolutePath(
        Directory(path).resolveSymbolicLinksSync(),
      ),
      FileSystemEntityType.file => _normalizeAbsolutePath(
        File(path).resolveSymbolicLinksSync(),
      ),
      FileSystemEntityType.link => _normalizeAbsolutePath(
        Link(path).resolveSymbolicLinksSync(),
      ),
      FileSystemEntityType.pipe ||
      FileSystemEntityType.unixDomainSock ||
      FileSystemEntityType.notFound ||
      _ => _normalizeAbsolutePath(path),
    };
  } on FileSystemException {
    return _normalizeAbsolutePath(path);
  }
}

String _relativeLexicalPath({required String path, required String rootPath}) {
  final absolutePath = _normalizeAbsolutePath(path);
  final absoluteRoot = _normalizeAbsolutePath(rootPath);
  if (_samePath(absolutePath, absoluteRoot)) {
    return '';
  }
  final rootPrefix = absoluteRoot.endsWith(Platform.pathSeparator)
      ? absoluteRoot
      : '$absoluteRoot${Platform.pathSeparator}';
  if (!_pathStartsWith(absolutePath, rootPrefix)) {
    return '';
  }
  return absolutePath.substring(rootPrefix.length);
}

bool _pathHasRootPrefix(String path, String rootPath) {
  if (_samePath(path, rootPath)) {
    return true;
  }
  final rootPrefix = rootPath.endsWith(Platform.pathSeparator)
      ? rootPath
      : '$rootPath${Platform.pathSeparator}';
  return _pathStartsWith(path, rootPrefix);
}

bool _samePath(String left, String right) {
  if (!Platform.isWindows) {
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
  if (!Platform.isWindows) {
    return path.startsWith(prefix);
  }
  return path.toLowerCase().startsWith(prefix.toLowerCase());
}

String _normalizeAbsolutePath(String path) {
  final absolutePath = _isAbsolutePath(path) ? path : File(path).absolute.path;
  return Uri.file(
    absolutePath,
    windows: Platform.isWindows,
  ).normalizePath().toFilePath(windows: Platform.isWindows);
}

String _appendRelativePath(String rootPath, String relativePath) {
  if (relativePath.isEmpty) {
    return rootPath;
  }
  if (rootPath.endsWith(Platform.pathSeparator)) {
    return '$rootPath$relativePath';
  }
  return '$rootPath${Platform.pathSeparator}$relativePath';
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
