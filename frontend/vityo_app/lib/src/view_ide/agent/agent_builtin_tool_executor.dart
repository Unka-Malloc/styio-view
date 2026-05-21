import 'dart:convert';

import '../editor/document_state.dart';
import '../workspace/workspace_document_store_types.dart';
import 'agent_provider_adapter.dart';
import 'agent_session_context.dart';
import 'agent_tool_call_dispatcher.dart';

typedef AgentIdeCommandToolRunner =
    Future<AgentCommandResultContext> Function(
      AgentIdeCommandSuggestion suggestion,
    );

class AgentBuiltinToolExecutor {
  const AgentBuiltinToolExecutor({
    required this.context,
    this.documentStore,
    this.ideCommandRunner,
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
  final List<String> checkpointChannels;

  Future<AgentToolCallDispatchResult> execute(
    AgentToolCallDispatchRequest request,
  ) async {
    return switch (request.toolId) {
      'readWorkspaceFile' => _readWorkspaceFile(request),
      'runIdeCommand' => _runIdeCommand(request),
      'collectAgentCodingCheckpoint' => _collectAgentCodingCheckpoint(request),
      _ => AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Agent builtin tool ${request.toolId} is not implemented by this executor.',
      ),
    };
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

String _normalizeWorkspacePath(String path) {
  return path.trim().replaceAll('\\', '/');
}

bool _unsafeWorkspacePath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.startsWith('~')) {
    return true;
  }
  return path.split('/').any((segment) => segment == '..');
}
