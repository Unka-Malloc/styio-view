import 'dart:convert';

import '../editor/document_state.dart';
import '../workspace/workspace_document_store_types.dart';
import 'agent_session_context.dart';
import 'agent_tool_call_dispatcher.dart';

class AgentBuiltinToolExecutor {
  const AgentBuiltinToolExecutor({
    required this.context,
    this.documentStore,
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
  final List<String> checkpointChannels;

  Future<AgentToolCallDispatchResult> execute(
    AgentToolCallDispatchRequest request,
  ) async {
    return switch (request.toolId) {
      'readWorkspaceFile' => _readWorkspaceFile(request),
      'collectAgentCodingCheckpoint' => _collectAgentCodingCheckpoint(request),
      _ => AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Agent builtin tool ${request.toolId} is not implemented by this executor.',
      ),
    };
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
