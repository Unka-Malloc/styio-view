import 'dart:convert';

import '../editor/document_state.dart';
import '../workspace/workspace_document_store_types.dart';
import 'agent_code_patch_applier.dart';
import 'agent_coding_session_history_store.dart';
import 'agent_provider_adapter.dart';
import 'agent_session_context.dart';
import 'agent_tool_call_dispatcher.dart';
import 'agent_workspace_edit_adapter.dart';
import 'agent_workspace_snapshot.dart';

typedef AgentIdeCommandToolRunner =
    Future<AgentCommandResultContext> Function(
      AgentIdeCommandSuggestion suggestion,
    );
typedef AgentWorkspacePatchToolRunner =
    Future<AgentCodePatchApplicationResult> Function(AgentCodePatch patch);
typedef AgentWorkspaceSnapshotCaptureRecorder =
    void Function(AgentWorkspaceSnapshotCaptureResult result);
typedef AgentWorkspaceRevertPlanRecorder =
    void Function(AgentWorkspaceRevertPlan plan);
typedef AgentValidationContextProvider =
    AgentCodingValidationToolContext Function();
typedef AgentRecoveryContextProvider =
    AgentCodingSessionRecoveryContext Function();
typedef AgentExtensionToolRunner =
    Future<AgentToolCallDispatchResult> Function(
      AgentToolCallDispatchRequest request,
    );

class AgentCodingValidationToolContext {
  const AgentCodingValidationToolContext({
    required this.validationPlan,
    required this.validationResult,
    required this.validationPipeline,
    required this.changeReviewGate,
    required this.autonomyPolicy,
    required this.validationCommands,
    required this.recentCommandResults,
    required this.failedCommandResults,
    required this.testing,
  });

  factory AgentCodingValidationToolContext.fromSessionContext(
    AgentSessionContext context, {
    AgentCodingValidationPlan? validationPlan,
    AgentCodingValidationResult? validationResult,
    AgentCodingValidationPipeline? validationPipeline,
    AgentCodingChangeReviewGate? changeReviewGate,
    AgentCodingAutonomyPolicy? autonomyPolicy,
  }) {
    final plan = validationPlan ?? context.agent.validationPlan;
    final result = validationResult ?? context.agent.validationResult;
    final pipeline = validationPipeline ?? context.agent.validationPipeline;
    final commandIds = plan.registeredCommandIds.toSet();
    final validationCommands = _allCommandContexts(context.commands)
        .where((command) => commandIds.contains(command.id))
        .toList(growable: false);
    final failedCommandIds = result.failedCommandIds.toSet();
    final failedCommandResults = context.commands.recentResults
        .where(
          (commandResult) => failedCommandIds.contains(commandResult.commandId),
        )
        .toList(growable: false);
    return AgentCodingValidationToolContext(
      validationPlan: plan,
      validationResult: result,
      validationPipeline: pipeline,
      changeReviewGate: changeReviewGate ?? context.agent.changeReviewGate,
      autonomyPolicy: autonomyPolicy ?? context.agent.autonomyPolicy,
      validationCommands: validationCommands,
      recentCommandResults: context.commands.recentResults,
      failedCommandResults: failedCommandResults,
      testing: context.testing,
    );
  }

  final AgentCodingValidationPlan validationPlan;
  final AgentCodingValidationResult validationResult;
  final AgentCodingValidationPipeline validationPipeline;
  final AgentCodingChangeReviewGate changeReviewGate;
  final AgentCodingAutonomyPolicy autonomyPolicy;
  final List<AgentCommandContext> validationCommands;
  final List<AgentCommandResultContext> recentCommandResults;
  final List<AgentCommandResultContext> failedCommandResults;
  final AgentTestingContext testing;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'validationPlan': validationPlan.toJson(),
      'validationResult': validationResult.toJson(),
      'validationPipeline': validationPipeline.toJson(),
      'changeReviewGate': changeReviewGate.toJson(),
      'autonomyPolicy': autonomyPolicy.toJson(),
      'validationCommands': validationCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'recentCommandResults': recentCommandResults
          .map((result) => result.toJson())
          .toList(growable: false),
      'failedCommandResults': failedCommandResults
          .map((result) => result.toJson())
          .toList(growable: false),
      'testing': testing.toJson(),
    };
  }
}

class AgentBuiltinToolExecutor {
  const AgentBuiltinToolExecutor({
    required this.context,
    this.documentStore,
    this.ideCommandRunner,
    this.workspacePatchRunner,
    this.workspaceSnapshotService,
    this.workspaceSnapshotCaptureRecorder,
    this.workspaceRevertPlanRecorder,
    this.validationContextProvider,
    this.recoveryContextProvider,
    this.extensionToolRunner,
    this.checkpointChannels = const <String>[
      'file',
      'selection',
      'diagnostics',
      'workspace',
      'agent',
      'language',
      'commands',
      'testing',
      'toolchains',
      'ideCapabilities',
      'ideCapabilityClosure',
    ],
  });

  final AgentSessionContext context;
  final WorkspaceDocumentStore? documentStore;
  final AgentIdeCommandToolRunner? ideCommandRunner;
  final AgentWorkspacePatchToolRunner? workspacePatchRunner;
  final AgentWorkspaceSnapshotService? workspaceSnapshotService;
  final AgentWorkspaceSnapshotCaptureRecorder? workspaceSnapshotCaptureRecorder;
  final AgentWorkspaceRevertPlanRecorder? workspaceRevertPlanRecorder;
  final AgentValidationContextProvider? validationContextProvider;
  final AgentRecoveryContextProvider? recoveryContextProvider;
  final AgentExtensionToolRunner? extensionToolRunner;
  final List<String> checkpointChannels;

  Future<AgentToolCallDispatchResult> execute(
    AgentToolCallDispatchRequest request,
  ) async {
    return switch (request.toolId) {
      'readWorkspaceFile' => _readWorkspaceFile(request),
      'previewWorkspaceEdit' => _previewWorkspaceEdit(request),
      'applyWorkspacePatch' => _applyWorkspacePatch(request),
      'runIdeCommand' => _runIdeCommand(request),
      'collectStyioLanguageContext' => _collectStyioLanguageContext(request),
      'collectAgentValidationContext' => _collectAgentValidationContext(
        request,
      ),
      'collectAgentRecoveryContext' => _collectAgentRecoveryContext(request),
      'collectAgentCodingCheckpoint' => _collectAgentCodingCheckpoint(request),
      _ => _runExtensionTool(request),
    };
  }

  Future<AgentToolCallDispatchResult> _runExtensionTool(
    AgentToolCallDispatchRequest request,
  ) async {
    final runner = extensionToolRunner;
    if (runner == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Agent extension tool ${request.toolId} cannot run because no AgentExtensionToolRunner is attached.',
      );
    }
    try {
      return await runner(request);
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'Agent extension tool ${request.toolId} failed: $error',
      );
    }
  }

  Future<AgentToolCallDispatchResult> _collectStyioLanguageContext(
    AgentToolCallDispatchRequest request,
  ) async {
    final language = context.language.toJson();
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'agent-session-context',
        'language': language,
      }),
      metadata: <String, Object?>{
        'completionCount': context.language.completionCount,
        'codeActionCount': context.language.codeActionCount,
        'referenceCount': context.language.referenceCount,
        'semanticSpanCount': context.language.semanticSpanCount,
      },
    );
  }

  Future<AgentToolCallDispatchResult> _collectAgentValidationContext(
    AgentToolCallDispatchRequest request,
  ) async {
    final validationContext =
        validationContextProvider?.call() ??
        AgentCodingValidationToolContext.fromSessionContext(context);
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'agent-validation-context',
        'validation': validationContext.toJson(),
      }),
      metadata: <String, Object?>{
        'planStatus': validationContext.validationPlan.status.wireValue,
        'resultStatus': validationContext.validationResult.status.wireValue,
        'pipelineStatus': validationContext.validationPipeline.status.wireValue,
        'shouldRun': validationContext.validationPlan.shouldRun,
        if (validationContext.validationPipeline.nextCommandId != null)
          'nextCommandId': validationContext.validationPipeline.nextCommandId,
        'runnableCommandCount':
            validationContext.validationPipeline.runnableCommandIds.length,
        'failedCommandCount':
            validationContext.validationResult.failedCommandIds.length,
      },
    );
  }

  Future<AgentToolCallDispatchResult> _collectAgentRecoveryContext(
    AgentToolCallDispatchRequest request,
  ) async {
    final recoveryContext = recoveryContextProvider?.call();
    if (recoveryContext == null) {
      return AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output: jsonEncode(<String, Object?>{
          'source': 'agent-session-context',
          'recovery': <String, Object?>{
            'recoveryPlan': context.agent.recoveryPlan?.toJson(),
            'lastProviderFailure': context.agent.lastProviderFailure?.toJson(),
            'suggestedCommandIds': context.agent.suggestedCommandIds,
            'fallbackMode': 'agentSessionContextOnly',
            'fullHistoryUnavailable': true,
            'historyStoreRequired': 'AgentCodingSessionHistoryStore',
          },
        }),
        metadata: <String, Object?>{
          'hasRecoveryPlan': context.agent.recoveryPlan != null,
          'suggestedCommandCount': context.agent.suggestedCommandIds.length,
          'fullHistoryUnavailable': true,
        },
      );
    }
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'agent-recovery-context',
        'recovery': recoveryContext.toJson(),
      }),
      metadata: <String, Object?>{
        'hasRecoverableSession': recoveryContext.hasRecoverableSession,
        'hasReplayDraft': recoveryContext.hasReplayDraft,
        'readyToDispatchAny': recoveryContext.readyToDispatchAny,
        'commandPlanCount': recoveryContext.commandPlans.length,
        'requestDraftCount': recoveryContext.requestDrafts.length,
      },
    );
  }

  Future<AgentToolCallDispatchResult> _previewWorkspaceEdit(
    AgentToolCallDispatchRequest request,
  ) async {
    final input = _inputObject(request);
    if (input == null) {
      return _inputFailure(request, 'input must be a JSON object.');
    }
    final patch = _patchFromInput(request, input);
    if (patch == null) {
      return _inputFailure(
        request,
        'patch must be a JSON object, JSON string, or object with edits.',
      );
    }
    final conversion = const AgentWorkspaceEditPlanAdapter().convert(patch);
    if (!conversion.converted) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: conversion.message,
        metadata: <String, Object?>{'patch': patch.toJson()},
      );
    }
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'agent-workspace-edit-preview',
        'patch': patch.toJson(),
        'conversion': _workspaceEditPlanConversionPayload(conversion),
      }),
      metadata: <String, Object?>{'patchId': patch.patchId},
    );
  }

  Future<AgentToolCallDispatchResult> _applyWorkspacePatch(
    AgentToolCallDispatchRequest request,
  ) async {
    final input = _inputObject(request);
    if (input == null) {
      return _inputFailure(request, 'input must be a JSON object.');
    }
    final patch = _patchFromInput(request, input);
    if (patch == null) {
      return _inputFailure(
        request,
        'patch must be a JSON object, JSON string, or object with edits.',
      );
    }
    final runner = workspacePatchRunner;
    if (runner == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Workspace patch ${patch.patchId} cannot run because no AgentWorkspacePatchToolRunner is attached.',
        metadata: <String, Object?>{'patch': patch.toJson()},
      );
    }
    final snapshotCapture = await _captureWorkspaceSnapshot(request, patch);
    if (snapshotCapture != null) {
      workspaceSnapshotCaptureRecorder?.call(snapshotCapture);
    }
    if (snapshotCapture != null && !snapshotCapture.captured) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Workspace patch ${patch.patchId} cannot run because the workspace snapshot was not captured: ${snapshotCapture.message}',
        metadata: <String, Object?>{
          'patch': patch.toJson(),
          'workspaceSnapshot': snapshotCapture.toJson(),
          'workspaceSnapshotCaptured': false,
        },
      );
    }
    late final AgentCodePatchApplicationResult result;
    try {
      result = await runner(patch);
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'Workspace patch ${patch.patchId} failed: $error',
        metadata: <String, Object?>{
          'patch': patch.toJson(),
          if (snapshotCapture != null)
            'workspaceSnapshot': snapshotCapture.toJson(),
        },
      );
    }
    if (!result.applied) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: result.message,
        metadata: <String, Object?>{
          'patch': patch.toJson(),
          'applicationResult': _patchApplicationResultPayload(result),
          if (snapshotCapture != null)
            'workspaceSnapshot': snapshotCapture.toJson(),
        },
      );
    }
    final revertPlan = await _buildWorkspaceRevertPlan(snapshotCapture);
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'agent-workspace-patch-runner',
        'patch': patch.toJson(),
        'result': _patchApplicationResultPayload(result),
        if (snapshotCapture != null)
          'workspaceSnapshot': snapshotCapture.toJson(),
        if (revertPlan != null) 'workspaceRevertPlan': revertPlan.toJson(),
      }),
      metadata: <String, Object?>{
        'patchId': patch.patchId,
        if (snapshotCapture != null) ...<String, Object?>{
          'workspaceSnapshotCaptured': snapshotCapture.captured,
          'workspaceSnapshotStatus': snapshotCapture.status.wireValue,
          if (snapshotCapture.snapshot != null)
            'workspaceSnapshotId': snapshotCapture.snapshot!.snapshotId,
          if (snapshotCapture.snapshot != null)
            'workspaceSnapshotDocumentCount':
                snapshotCapture.snapshot!.documents.length,
        },
        if (revertPlan != null) ...<String, Object?>{
          'workspaceRevertPlanStatus': revertPlan.status.wireValue,
          'workspaceRevertPlanReady': revertPlan.ready,
          'workspaceRevertChangedDocumentCount':
              revertPlan.diffSummary.changedDocumentCount,
        },
      },
    );
  }

  Future<AgentWorkspaceSnapshotCaptureResult?> _captureWorkspaceSnapshot(
    AgentToolCallDispatchRequest request,
    AgentCodePatch patch,
  ) async {
    final service = workspaceSnapshotService;
    if (service == null) {
      return null;
    }
    try {
      return await service.captureBeforePatch(
        patch,
        snapshotId: 'agent-tool-snapshot-${request.callId}-${patch.patchId}',
      );
    } on Object catch (error) {
      return AgentWorkspaceSnapshotCaptureResult(
        status: AgentWorkspaceSnapshotCaptureStatus.empty,
        message: 'Failed to capture workspace snapshot: $error',
      );
    }
  }

  Future<AgentWorkspaceRevertPlan?> _buildWorkspaceRevertPlan(
    AgentWorkspaceSnapshotCaptureResult? capture,
  ) async {
    final service = workspaceSnapshotService;
    final snapshot = capture?.snapshot;
    if (service == null || snapshot == null) {
      return null;
    }
    try {
      final plan = await service.buildRevertPlan(snapshot);
      workspaceRevertPlanRecorder?.call(plan);
      return plan;
    } on Object {
      return null;
    }
  }

  Future<AgentToolCallDispatchResult> _runIdeCommand(
    AgentToolCallDispatchRequest request,
  ) async {
    final input = _inputObject(request);
    if (input == null) {
      return _inputFailure(request, 'input must be a JSON object.');
    }
    final commandId = input['commandId'];
    if (commandId is! String || commandId.trim().isEmpty) {
      return _inputFailure(request, 'commandId is required.');
    }
    final normalizedCommandId = commandId.trim();
    final command = _commandForId(normalizedCommandId);
    if (command == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'IDE command $normalizedCommandId is not registered in this Vityo command context.',
      );
    }
    final commandInput = _commandInputString(input['input']);
    if (command.requiresInput && (commandInput?.trim().isEmpty ?? true)) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'IDE command $normalizedCommandId requires input: ${command.inputLabel}.',
      );
    }
    final runner = ideCommandRunner;
    if (runner == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'IDE command $normalizedCommandId cannot run because no AgentIdeCommandToolRunner is attached.',
      );
    }

    late final AgentCommandResultContext result;
    try {
      result = await runner(
        AgentIdeCommandSuggestion(
          commandId: normalizedCommandId,
          input: commandInput,
          reason: 'Run IDE command requested by agent tool call.',
        ),
      );
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'IDE command $normalizedCommandId failed: $error',
      );
    }
    if (!result.applied) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: result.message,
        metadata: <String, Object?>{'commandResult': result.toJson()},
      );
    }
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'ide-command-runner',
        'result': result.toJson(),
      }),
      metadata: <String, Object?>{'commandId': normalizedCommandId},
    );
  }

  Future<AgentToolCallDispatchResult> _readWorkspaceFile(
    AgentToolCallDispatchRequest request,
  ) async {
    final input = _inputObject(request);
    if (input == null) {
      return _inputFailure(request, 'input must be a JSON object.');
    }
    final path = input['path'];
    if (path is! String || path.trim().isEmpty) {
      return _inputFailure(request, 'path is required.');
    }
    final normalizedPath = _normalizeWorkspacePath(path);
    if (_unsafeWorkspacePath(normalizedPath)) {
      return _inputFailure(
        request,
        'path must be workspace-relative and cannot contain parent traversal.',
      );
    }

    final sample = _sampleForDocumentId(normalizedPath);
    if (sample != null) {
      return AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output: jsonEncode(<String, Object?>{
          'source': 'agent-session-context',
          'document': sample.toJson(),
        }),
      );
    }

    final store = documentStore;
    if (store == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Workspace file $normalizedPath is not available in agent context and no WorkspaceDocumentStore is attached.',
      );
    }
    try {
      final document = await store.loadDocument(normalizedPath);
      return AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output: jsonEncode(<String, Object?>{
          'source': 'workspace-document-store',
          'document': _documentPayload(document),
        }),
      );
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'Failed to read workspace file $normalizedPath: $error',
      );
    }
  }

  Future<AgentToolCallDispatchResult> _collectAgentCodingCheckpoint(
    AgentToolCallDispatchRequest request,
  ) async {
    return AgentToolCallDispatchResult.success(
      callId: request.callId,
      toolId: request.toolId,
      output: jsonEncode(<String, Object?>{
        'source': 'agent-session-context',
        'checkpoint': context.toJsonForChannels(checkpointChannels),
      }),
    );
  }

  AgentWorkspaceDocumentSampleContext? _sampleForDocumentId(String documentId) {
    for (final sample in context.workspace.documentSamples) {
      if (_normalizeWorkspacePath(sample.documentId) == documentId) {
        return sample;
      }
    }
    return null;
  }

  AgentCommandContext? _commandForId(String commandId) {
    for (final command in _allCommandContexts(context.commands)) {
      if (command.id == commandId) {
        return command;
      }
    }
    return null;
  }
}

List<AgentCommandContext> _allCommandContexts(
  AgentCommandCatalogContext commands,
) {
  return <AgentCommandContext>[
    ...commands.persistenceCommands,
    ...commands.executionCommands,
    ...commands.diagnosticCommands,
    ...commands.languageServiceCommands,
    ...commands.sourceControlCommands,
    ...commands.workspaceFileCommands,
    ...commands.codingCommands,
    ...commands.navigationCommands,
    ...commands.refactorCommands,
    ...commands.dependencyCommands,
    ...commands.toolchainCommands,
    ...commands.deploymentCommands,
    ...commands.moduleCommands,
    ...commands.surfaceCommands,
    ...commands.nativeToolCommands,
    ...commands.testingCommands,
    ...commands.debugCommands,
    ...commands.settingsCommands,
  ];
}

Map<String, Object?>? _inputObject(AgentToolCallDispatchRequest request) {
  try {
    final decoded = jsonDecode(request.inputText);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
  } on Object {
    return null;
  }
  return null;
}

AgentToolCallDispatchResult _inputFailure(
  AgentToolCallDispatchRequest request,
  String message,
) {
  return AgentToolCallDispatchResult.failure(
    callId: request.callId,
    toolId: request.toolId,
    message: 'Invalid ${request.toolId} input: $message',
  );
}

String? _commandInputString(Object? input) {
  if (input == null) {
    return null;
  }
  if (input is String) {
    return input;
  }
  return jsonEncode(input);
}

Map<String, Object?> _documentPayload(DocumentState document) {
  return <String, Object?>{
    'documentId': document.documentId,
    'revision': document.revision,
    'length': document.length,
    'lineCount': document.lines.length,
    'text': document.text,
    'textStart': 0,
    'textEnd': document.text.length,
    'textTruncated': false,
  };
}

AgentCodePatch? _patchFromInput(
  AgentToolCallDispatchRequest request,
  Map<String, Object?> input,
) {
  final patchValue = input['patch'] ?? input['workspaceEdit'] ?? input;
  Map<String, Object?>? patchJson;
  if (patchValue is String) {
    try {
      final decoded = jsonDecode(patchValue);
      if (decoded is Map<String, Object?>) {
        patchJson = decoded;
      } else if (decoded is Map) {
        patchJson = decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } on Object {
      return null;
    }
  } else if (patchValue is Map<String, Object?>) {
    patchJson = Map<String, Object?>.from(patchValue);
  } else if (patchValue is Map) {
    patchJson = patchValue.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  if (patchJson == null) {
    return null;
  }
  patchJson.putIfAbsent('patchId', () => 'agent-tool-${request.callId}');
  patchJson.putIfAbsent(
    'summary',
    () => 'Workspace edit from ${request.toolId}.',
  );
  final patch = AgentCodePatch.fromJson(patchJson);
  if (patch.edits.isEmpty) {
    return null;
  }
  return patch;
}

Map<String, Object?> _workspaceEditPlanConversionPayload(
  AgentWorkspaceEditPlanConversion conversion,
) {
  return <String, Object?>{
    'converted': conversion.converted,
    'message': conversion.message,
    'skippedFileOperationCount': conversion.skippedFileOperationCount,
    if (conversion.plan != null) 'plan': conversion.plan!.toJson(),
  };
}

Map<String, Object?> _patchApplicationResultPayload(
  AgentCodePatchApplicationResult result,
) {
  return <String, Object?>{
    'applied': result.applied,
    'message': result.message,
    'appliedEditCount': result.appliedEditCount,
    'appliedOperationCounts': result.appliedOperationCounts,
    'appliedDocumentIds': result.appliedDocumentIds,
    'createdDocumentIds': result.createdDocumentIds,
    'deletedDocumentIds': result.deletedDocumentIds,
    'skippedNoOpDocumentIds': result.skippedNoOpDocumentIds,
  };
}

String _normalizeWorkspacePath(String path) {
  return path.trim().replaceAll('\\', '/');
}

bool _unsafeWorkspacePath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith('~')) {
    return true;
  }
  return path.split('/').any((segment) => segment == '..');
}
