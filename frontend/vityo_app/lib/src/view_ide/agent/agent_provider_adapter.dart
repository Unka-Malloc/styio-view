import 'dart:convert';

import 'agent_command_metadata.dart';
import 'agent_profile.dart';
import 'agent_session_context.dart';

const int _maxAgentAttachmentContentLength = 20000;

enum AgentProviderKind { cloudOpenAICompatible, localBridge, localOnlyFallback }

extension AgentProviderKindX on AgentProviderKind {
  String get wireValue {
    switch (this) {
      case AgentProviderKind.cloudOpenAICompatible:
        return 'cloud_openai_compatible';
      case AgentProviderKind.localBridge:
        return 'local_bridge';
      case AgentProviderKind.localOnlyFallback:
        return 'local_only_fallback';
    }
  }
}

enum AgentContentPartKind {
  text,
  plan,
  codePatch,
  diagnosticSummary,
  ideCommand,
}

extension AgentContentPartKindX on AgentContentPartKind {
  String get wireValue {
    switch (this) {
      case AgentContentPartKind.text:
        return 'text';
      case AgentContentPartKind.plan:
        return 'plan';
      case AgentContentPartKind.codePatch:
        return 'code_patch';
      case AgentContentPartKind.diagnosticSummary:
        return 'diagnostic_summary';
      case AgentContentPartKind.ideCommand:
        return 'ide_command';
    }
  }
}

AgentContentPartKind _agentContentPartKindFromWireValue(String? value) {
  return switch (value) {
    'plan' => AgentContentPartKind.plan,
    'code_patch' => AgentContentPartKind.codePatch,
    'diagnostic_summary' => AgentContentPartKind.diagnosticSummary,
    'ide_command' => AgentContentPartKind.ideCommand,
    _ => AgentContentPartKind.text,
  };
}

class AgentProviderRequest {
  const AgentProviderRequest({
    required this.requestId,
    required this.profile,
    required this.context,
    required this.userPrompt,
    this.attachments = const <AgentRequestAttachment>[],
    this.conversationTurns = const <AgentConversationTurn>[],
  });

  final String requestId;
  final AgentPromptProfile profile;
  final AgentSessionContext context;
  final String userPrompt;
  final List<AgentRequestAttachment> attachments;
  final List<AgentConversationTurn> conversationTurns;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'profile': profile.toJson(),
      'context': context.toJson(),
      'userPrompt': userPrompt,
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(growable: false),
      if (conversationTurns.isNotEmpty)
        'conversationTurns': conversationTurns
            .map((turn) => turn.toJson())
            .toList(growable: false),
    };
  }
}

class AgentRequestAttachment {
  const AgentRequestAttachment({
    required this.attachmentId,
    required this.kind,
    required this.name,
    required this.content,
    this.metadata = const <String, Object?>{},
  });

  final String attachmentId;
  final String kind;
  final String name;
  final String content;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    final metadataJson = _attachmentMetadataJson(metadata);
    return <String, Object?>{
      'attachmentId': attachmentId,
      'kind': kind,
      'name': name,
      'content': content,
      if (metadataJson.isNotEmpty) 'metadata': metadataJson,
    };
  }
}

Map<String, Object?> _attachmentMetadataJson(Map<String, Object?> metadata) {
  final result = <String, Object?>{};
  for (final entry in metadata.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) {
      continue;
    }
    final value = _attachmentMetadataValueJson(entry.value);
    if (value != _unsupportedAttachmentMetadataValue) {
      result[key] = value;
    }
  }
  return result;
}

const Object _unsupportedAttachmentMetadataValue = Object();

Object? _attachmentMetadataValueJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    final values = <Object?>[];
    for (final item in value) {
      final itemJson = _attachmentMetadataValueJson(item);
      if (itemJson == _unsupportedAttachmentMetadataValue) {
        return _unsupportedAttachmentMetadataValue;
      }
      values.add(itemJson);
    }
    return values;
  }
  if (value is Map) {
    final values = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || key.trim().isEmpty) {
        return _unsupportedAttachmentMetadataValue;
      }
      final itemJson = _attachmentMetadataValueJson(entry.value);
      if (itemJson == _unsupportedAttachmentMetadataValue) {
        return _unsupportedAttachmentMetadataValue;
      }
      values[key.trim()] = itemJson;
    }
    return values;
  }
  return _unsupportedAttachmentMetadataValue;
}

enum AgentConversationRole { user, assistant }

extension AgentConversationRoleX on AgentConversationRole {
  String get wireValue {
    switch (this) {
      case AgentConversationRole.user:
        return 'user';
      case AgentConversationRole.assistant:
        return 'assistant';
    }
  }
}

class AgentConversationTurn {
  const AgentConversationTurn({
    required this.turnId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.providerMessageId,
  });

  final String turnId;
  final AgentConversationRole role;
  final String text;
  final DateTime createdAt;
  final String? providerMessageId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'turnId': turnId,
      'role': role.wireValue,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      if (providerMessageId != null) 'providerMessageId': providerMessageId,
    };
  }
}

class AgentProviderResponseEnvelope {
  const AgentProviderResponseEnvelope({
    required this.requestId,
    required this.role,
    required this.contentParts,
    required this.finishReason,
    this.providerMessageId,
    this.usage,
  });

  final String requestId;
  final String? providerMessageId;
  final String role;
  final List<AgentContentPart> contentParts;
  final String finishReason;
  final Map<String, Object?>? usage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      if (providerMessageId != null) 'providerMessageId': providerMessageId,
      'role': role,
      'contentParts': contentParts
          .map((part) => part.toJson())
          .toList(growable: false),
      'finishReason': finishReason,
      if (usage != null) 'usage': usage,
    };
  }
}

class AgentContentPart {
  const AgentContentPart({
    required this.kind,
    required this.text,
    this.plan,
    this.diagnosticSummary,
    this.patch,
    this.ideCommand,
  });

  final AgentContentPartKind kind;
  final String text;
  final AgentCodingPlan? plan;
  final AgentDiagnosticSummary? diagnosticSummary;
  final AgentCodePatch? patch;
  final AgentIdeCommandSuggestion? ideCommand;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'text': text,
      if (plan != null) 'plan': plan!.toJson(),
      if (diagnosticSummary != null)
        'diagnosticSummary': diagnosticSummary!.toJson(),
      if (patch != null) 'patch': patch!.toJson(),
      if (ideCommand != null) 'ideCommand': ideCommand!.toJson(),
    };
  }

  factory AgentContentPart.fromJson(Map<String, Object?> json) {
    final planJson = json['plan'] ?? json['codingPlan'];
    final diagnosticSummaryJson =
        json['diagnosticSummary'] ?? json['diagnostic_summary'];
    final patchJson = json['patch'] ?? json['codePatch'];
    final ideCommandJson = json['ideCommand'] ?? json['command'];
    return AgentContentPart(
      kind: _agentContentPartKindFromWireValue(json['kind'] as String?),
      text: json['text'] as String? ?? json['content'] as String? ?? '',
      plan: planJson is Map<String, Object?>
          ? AgentCodingPlan.fromJson(planJson)
          : planJson is Map
          ? AgentCodingPlan.fromJson(
              planJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
      diagnosticSummary: diagnosticSummaryJson is Map<String, Object?>
          ? AgentDiagnosticSummary.fromJson(diagnosticSummaryJson)
          : diagnosticSummaryJson is Map
          ? AgentDiagnosticSummary.fromJson(
              diagnosticSummaryJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
      patch: patchJson is Map<String, Object?>
          ? AgentCodePatch.fromJson(patchJson)
          : patchJson is Map
          ? AgentCodePatch.fromJson(
              patchJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
      ideCommand: ideCommandJson is Map<String, Object?>
          ? AgentIdeCommandSuggestion.fromJson(ideCommandJson)
          : ideCommandJson is Map
          ? AgentIdeCommandSuggestion.fromJson(
              ideCommandJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
    );
  }
}

class AgentCodingPlan {
  const AgentCodingPlan({
    required this.summary,
    required this.steps,
    required this.acceptanceCriteria,
    this.risks = const <String>[],
  });

  final String summary;
  final List<String> steps;
  final List<String> acceptanceCriteria;
  final List<String> risks;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'summary': summary,
      'steps': steps,
      'acceptanceCriteria': acceptanceCriteria,
      if (risks.isNotEmpty) 'risks': risks,
    };
  }

  factory AgentCodingPlan.fromJson(Map<String, Object?> json) {
    return AgentCodingPlan(
      summary: json['summary'] as String? ?? '',
      steps: _stringListFromJson(json['steps']),
      acceptanceCriteria: _stringListFromJson(
        json['acceptanceCriteria'] ?? json['acceptance_criteria'],
      ),
      risks: _stringListFromJson(json['risks'] ?? json['riskNotes']),
    );
  }
}

class AgentDiagnosticSummary {
  const AgentDiagnosticSummary({
    required this.title,
    required this.summary,
    this.severity = 'info',
    this.diagnosticCount = 0,
    this.affectedDocuments = const <String>[],
    this.suggestedCommandIds = const <String>[],
  });

  final String title;
  final String summary;
  final String severity;
  final int diagnosticCount;
  final List<String> affectedDocuments;
  final List<String> suggestedCommandIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'summary': summary,
      'severity': severity,
      'diagnosticCount': diagnosticCount,
      if (affectedDocuments.isNotEmpty) 'affectedDocuments': affectedDocuments,
      if (suggestedCommandIds.isNotEmpty)
        'suggestedCommandIds': suggestedCommandIds,
    };
  }

  factory AgentDiagnosticSummary.fromJson(Map<String, Object?> json) {
    return AgentDiagnosticSummary(
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      diagnosticCount: _intFromJson(
        json['diagnosticCount'] ?? json['diagnostic_count'],
      ),
      affectedDocuments: _stringListFromJson(
        json['affectedDocuments'] ?? json['affected_documents'],
      ),
      suggestedCommandIds: _stringListFromJson(
        json['suggestedCommandIds'] ?? json['suggested_command_ids'],
      ),
    );
  }
}

int _intFromJson(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

List<String> _stringListFromJson(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? const <String>[] : <String>[trimmed];
  }
  if (value is List) {
    return value
        .whereType<Object?>()
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

class AgentIdeCommandSuggestion {
  const AgentIdeCommandSuggestion({
    required this.commandId,
    this.input,
    this.reason = '',
    this.prerequisiteForCommandId,
  });

  final String commandId;
  final String? input;
  final String reason;
  final String? prerequisiteForCommandId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId,
      if (input != null) 'input': input,
      'reason': reason,
      if (prerequisiteForCommandId != null)
        'prerequisiteForCommandId': prerequisiteForCommandId,
    };
  }

  factory AgentIdeCommandSuggestion.fromJson(Map<String, Object?> json) {
    return AgentIdeCommandSuggestion(
      commandId: json['commandId'] as String? ?? json['id'] as String? ?? '',
      input: json['input'] as String? ?? json['argument'] as String?,
      reason: json['reason'] as String? ?? '',
      prerequisiteForCommandId:
          json['prerequisiteForCommandId'] as String? ??
          json['requiredForCommandId'] as String? ??
          json['prerequisite_for_command_id'] as String?,
    );
  }
}

class AgentCodePatch {
  const AgentCodePatch({
    required this.patchId,
    required this.summary,
    required this.edits,
    this.baseRevision,
  });

  final String patchId;
  final String summary;
  final List<AgentCodePatchEdit> edits;
  final int? baseRevision;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'patchId': patchId,
      'summary': summary,
      if (baseRevision != null) 'baseRevision': baseRevision,
      'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
    };
  }

  factory AgentCodePatch.fromJson(Map<String, Object?> json) {
    final editsJson = json['edits'];
    return AgentCodePatch(
      patchId:
          json['patchId'] as String? ??
          json['patch_id'] as String? ??
          'agent-patch',
      summary: json['summary'] as String? ?? '',
      baseRevision:
          json['baseRevision'] as int? ?? json['base_revision'] as int?,
      edits: editsJson is List
          ? editsJson
                .map(_agentCodePatchEditFromJson)
                .whereType<AgentCodePatchEdit>()
                .toList(growable: false)
          : const <AgentCodePatchEdit>[],
    );
  }
}

enum AgentCodePatchEditOperation { replace, create, delete }

extension AgentCodePatchEditOperationX on AgentCodePatchEditOperation {
  String get wireValue {
    switch (this) {
      case AgentCodePatchEditOperation.replace:
        return 'replace';
      case AgentCodePatchEditOperation.create:
        return 'create';
      case AgentCodePatchEditOperation.delete:
        return 'delete';
    }
  }
}

AgentCodePatchEditOperation _agentCodePatchEditOperationFromWireValue(
  Object? value,
) {
  return switch (value) {
    'create' => AgentCodePatchEditOperation.create,
    'delete' => AgentCodePatchEditOperation.delete,
    _ => AgentCodePatchEditOperation.replace,
  };
}

class AgentCodePatchEdit {
  const AgentCodePatchEdit({
    required this.documentId,
    required this.start,
    required this.end,
    required this.replacementText,
    this.operation = AgentCodePatchEditOperation.replace,
    this.baseRevision,
  });

  final String documentId;
  final AgentCodePatchEditOperation operation;
  final int start;
  final int end;
  final String replacementText;
  final int? baseRevision;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      if (operation != AgentCodePatchEditOperation.replace)
        'operation': operation.wireValue,
      if (baseRevision != null) 'baseRevision': baseRevision,
      'start': start,
      'end': end,
      'replacementText': replacementText,
    };
  }

  factory AgentCodePatchEdit.fromJson(Map<String, Object?> json) {
    return AgentCodePatchEdit(
      documentId:
          json['documentId'] as String? ?? json['document_id'] as String? ?? '',
      operation: _agentCodePatchEditOperationFromWireValue(json['operation']),
      baseRevision:
          json['baseRevision'] as int? ?? json['base_revision'] as int?,
      start: json['start'] as int? ?? 0,
      end: json['end'] as int? ?? 0,
      replacementText:
          json['replacementText'] as String? ??
          json['replacement_text'] as String? ??
          '',
    );
  }
}

AgentCodePatchEdit? _agentCodePatchEditFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return AgentCodePatchEdit.fromJson(value);
  }
  if (value is Map) {
    return AgentCodePatchEdit.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return null;
}

abstract class AgentProviderAdapter {
  AgentProviderKind get kind;
  String get adapterId;
  bool get supportsCodePatch;

  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request);
}

abstract class CancellableAgentProviderAdapter implements AgentProviderAdapter {
  void cancelRequest(String requestId);
}

abstract class AgentProviderTransport {
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });
}

abstract class CancellableAgentProviderTransport
    implements AgentProviderTransport {
  Future<Map<String, Object?>> postJsonCancellable({
    required String requestId,
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  });

  void cancelRequest(String requestId);
}

enum AgentProviderTransportFailureKind {
  unsupported,
  timeout,
  cancelled,
  httpStatus,
  tlsFailure,
  hostUnreachable,
  invalidResponse,
  unknown,
}

class AgentProviderTransportException implements Exception {
  const AgentProviderTransportException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.target,
    this.operation = 'agent.provider.postJson',
    this.recoveryHint,
    this.cause,
  });

  final AgentProviderTransportFailureKind kind;
  final String message;
  final int? statusCode;
  final String? target;
  final String operation;
  final String? recoveryHint;
  final Object? cause;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      if (target != null) 'target': target,
      if (statusCode != null) 'statusCode': statusCode,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }

  @override
  String toString() {
    final details = <String>[
      'kind=${kind.name}',
      'operation=$operation',
      if (statusCode != null) 'statusCode=$statusCode',
      if (target != null) 'target=$target',
    ].join(', ');
    final recovery = recoveryHint == null ? '' : ' Recovery: $recoveryHint';
    return 'Agent provider request failed ($details): $message$recovery';
  }
}

class OpenAICompatibleAgentProviderAdapter
    implements AgentProviderAdapter, CancellableAgentProviderAdapter {
  const OpenAICompatibleAgentProviderAdapter({
    required this.transport,
    required this.endpoint,
    this.authorizationToken,
    this.adapterId = 'openai-compatible',
    this.providerKind = AgentProviderKind.cloudOpenAICompatible,
  });

  final AgentProviderTransport transport;
  final AgentProviderEndpoint endpoint;
  final String? authorizationToken;
  final AgentProviderKind providerKind;

  @override
  final String adapterId;

  @override
  AgentProviderKind get kind => providerKind;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    final token = authorizationToken?.trim();
    final endpointUri = _chatCompletionsEndpoint(endpoint.baseUrl);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final body = _openAICompatibleRequestBody(
      request,
      endpointOverride: endpoint,
    );
    final cancellableTransport = transport is CancellableAgentProviderTransport
        ? transport as CancellableAgentProviderTransport
        : null;
    final response = cancellableTransport == null
        ? await transport.postJson(
            endpoint: endpointUri,
            headers: headers,
            body: body,
          )
        : await cancellableTransport.postJsonCancellable(
            requestId: request.requestId,
            endpoint: endpointUri,
            headers: headers,
            body: body,
          );
    return _responseEnvelopeFromOpenAICompatibleResponse(
      requestId: request.requestId,
      response: response,
    );
  }

  @override
  void cancelRequest(String requestId) {
    final cancellableTransport = transport is CancellableAgentProviderTransport
        ? transport as CancellableAgentProviderTransport
        : null;
    cancellableTransport?.cancelRequest(requestId);
  }
}

class LocalOnlyAgentProviderAdapter implements AgentProviderAdapter {
  const LocalOnlyAgentProviderAdapter();

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  String get adapterId => 'local-only-fallback';

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'provider_not_configured',
      contentParts: <AgentContentPart>[
        const AgentContentPart(
          kind: AgentContentPartKind.text,
          text:
              'No agent provider adapter is mounted. Vityo captured the IDE context locally, but cannot send it to a coding agent until a cloud or local bridge provider is configured.',
        ),
      ],
      usage: <String, Object?>{
        'contextChannels': request.profile.contextChannels,
        'contextSchemaVersion': request.context.schemaVersion,
        'documentId': request.context.document.documentId,
        'selectionStartLine': request.context.selection.startLine,
        'selectionStartColumn': request.context.selection.startColumn,
        'selectionEndLine': request.context.selection.endLine,
        'selectionEndColumn': request.context.selection.endColumn,
        'diagnosticCount': request.context.diagnostics.length,
        'workspaceFileCount': request.context.workspace.fileCount,
        'openDocumentCount': request.context.workspace.openDocumentIds.length,
        'dirtyDocumentCount': request.context.workspace.dirtyDocumentIds.length,
        'workspaceDocumentSampleCount':
            request.context.workspace.documentSampleCount,
        'workspaceDocumentSamplesTruncated':
            request.context.workspace.documentSamplesTruncated,
        'workspaceBuildSystemHints':
            request.context.workspace.buildFacts.buildSystemHints,
        'workspaceToolingHints':
            request.context.workspace.buildFacts.toolingHints,
        ..._agentCodingMetadata(request.context.agent),
        if (request.context.workspace.lastSearch != null)
          'workspaceLastSearchMatchCount':
              request.context.workspace.lastSearch!.matchCount,
        if (request.context.workspace.lastSymbolSearch != null)
          'workspaceLastSymbolSearchMatchCount':
              request.context.workspace.lastSymbolSearch!.matchCount,
        'hasLanguageHover': request.context.language.hasHover,
        'hasFocusToken': request.context.language.focusToken != null,
        if (request.context.language.focusToken != null)
          'focusTokenKind': request.context.language.focusToken!.kind,
        if (request.context.language.focusToken?.semanticKind != null)
          'focusSemanticKind':
              request.context.language.focusToken!.semanticKind,
        'languageFocusedDiagnosticCount':
            request.context.language.focusedDiagnosticCount,
        'languageReferenceCount': request.context.language.referenceCount,
        'hasResolvedElement': request.context.language.resolvedElement != null,
        'hasResolvedReference':
            request.context.language.resolvedReference != null,
        'hasParameterInfo': request.context.language.parameterInfo != null,
        'languageParameterCount':
            request.context.language.parameterInfo?.parameterCount ?? 0,
        'languageCompletionCount': request.context.language.completionCount,
        'languageCodeActionCount': request.context.language.codeActionCount,
        'languageSemanticSpanCount': request.context.language.semanticSpanCount,
        'languageDocumentSymbolCount':
            request.context.language.documentSymbolCount,
        'languageInlayHintCount': request.context.language.inlayHintCount,
        'languageSemanticBlockCount':
            request.context.language.semanticBlockCount,
        'languageRefactorPreviewCount':
            request.context.language.refactorPreviewCount,
        'languageSurroundTemplateCount':
            request.context.language.surroundTemplateCount,
        if (request.context.language.serviceStatus != null)
          'languageServiceSeverity':
              request.context.language.serviceStatus!.severity,
        if (request.context.language.serviceStatus != null)
          'languageServiceUsableCapabilityCount':
              request.context.language.serviceStatus!.usableCapabilityCount,
        if (request.context.language.serviceStatus != null)
          'languageServiceFreshCapabilityCount':
              request.context.language.serviceStatus!.freshCapabilityCount,
        if (request.context.language.serviceStatus != null)
          'languageServiceLocalFallbackEnabled':
              request.context.language.serviceStatus!.localFallbackEnabled,
        if (request.context.language.serviceStatus?.parserEngine != null)
          'languageServiceParserEngine':
              request.context.language.serviceStatus!.parserEngine,
        if (request.context.language.serviceStatus?.grammarVersion != null)
          'languageServiceGrammarVersion':
              request.context.language.serviceStatus!.grammarVersion,
        if (request.context.language.serviceStatus != null)
          'languageServicePrimaryCapabilityStates':
              request.context.language.serviceStatus!.primaryCapabilityStates,
        'debugStatus': request.context.debug.status,
        'debugBreakpointCount': request.context.debug.breakpointCount,
        'debugThreadCount': request.context.debug.threadCount,
        'debugStackFrameCount': request.context.debug.stackFrameCount,
        'debugVariableCount': request.context.debug.variableCount,
        'persistenceCommandCount':
            request.context.commands.persistenceCommands.length,
        'diagnosticCommandCount':
            request.context.commands.diagnosticCommands.length,
        'languageServiceCommandCount':
            request.context.commands.languageServiceCommands.length,
        'navigationCommandCount':
            request.context.commands.navigationCommands.length,
        'refactorCommandCount':
            request.context.commands.refactorCommands.length,
        'toolchainCommandCount':
            request.context.commands.toolchainCommands.length,
        'nativeToolCommandCount':
            request.context.commands.nativeToolCommands.length,
        'nativeToolReadyCommandCount':
            request.context.commands.nativeToolReadyCommandCount,
        'nativeToolBlockedCommandCount':
            request.context.commands.nativeToolBlockedCommandCount,
        'debugCommandCount': request.context.commands.debugCommands.length,
        'debugReadyCommandCount':
            request.context.commands.debugReadyCommandCount,
        'debugBlockedCommandCount':
            request.context.commands.debugBlockedCommandCount,
        'settingsCommandCount':
            request.context.commands.settingsCommands.length,
        'recentCommandResultCount':
            request.context.commands.recentResults.length,
        if (request.context.commands.recentResults.isNotEmpty)
          'recentCommandIds': request.context.commands.recentResults
              .map((result) => result.commandId)
              .toList(growable: false),
        ..._lastCommandResultMetadata(request.context.commands.lastResult),
        'skillCount': request.context.skills.skillCount,
        'skillIds': request.context.skills.skillIds,
        'toolchainCount': request.context.toolchains.entryCount,
        'hasNativeCompiler': request.context.toolchains.hasNativeCompiler,
        ..._nativeToolMetadata(request.context.toolchains.nativeTools),
        if (request.context.toolchains.activeCompiler != null)
          'activeCompilerId': request.context.toolchains.activeCompiler!.id,
        'attachmentCount': request.attachments.length,
        'attachmentKinds': _attachmentKinds(request.attachments),
        'attachmentTruncatedCount': request.attachments
            .where(
              (attachment) =>
                  attachment.content.length > _maxAgentAttachmentContentLength,
            )
            .length,
        'conversationTurnCount': request.conversationTurns.length,
      },
    );
  }
}

Map<String, Object?> _openAICompatibleRequestBody(
  AgentProviderRequest request, {
  AgentProviderEndpoint? endpointOverride,
}) {
  final contextJson = jsonEncode(
    request.context.toJsonForChannels(request.profile.contextChannels),
  );
  final attachmentsJson = jsonEncode(<String, Object?>{
    'attachments': request.attachments
        .map(_attachmentJsonForProvider)
        .toList(growable: false),
  });
  final historicalMessages = request.conversationTurns
      .where((turn) => turn.text.trim().isNotEmpty)
      .map(
        (turn) => <String, Object?>{
          'role': turn.role.wireValue,
          'content': turn.text,
        },
      );
  return <String, Object?>{
    'model': endpointOverride?.model ?? request.profile.endpoint.model,
    'messages': <Map<String, Object?>>[
      <String, Object?>{
        'role': 'system',
        'content': _systemPromptWithStructuredResponseContract(
          request.profile.systemPrompt,
        ),
      },
      ...historicalMessages,
      <String, Object?>{
        'role': 'user',
        'name': 'vityo_ide_context',
        'content': contextJson,
      },
      if (request.attachments.isNotEmpty)
        <String, Object?>{
          'role': 'user',
          'name': 'vityo_agent_attachments',
          'content': attachmentsJson,
        },
      <String, Object?>{'role': 'user', 'content': request.userPrompt},
    ],
    'metadata': <String, Object?>{
      'requestId': request.requestId,
      'profileId': request.profile.profileId,
      'contextSchemaVersion': request.context.schemaVersion,
      'contextChannels': request.profile.contextChannels,
      'workspaceFileCount': request.context.workspace.fileCount,
      'selectionStartLine': request.context.selection.startLine,
      'selectionStartColumn': request.context.selection.startColumn,
      'selectionEndLine': request.context.selection.endLine,
      'selectionEndColumn': request.context.selection.endColumn,
      'openDocumentCount': request.context.workspace.openDocumentIds.length,
      'dirtyDocumentCount': request.context.workspace.dirtyDocumentIds.length,
      'workspaceDocumentSampleCount':
          request.context.workspace.documentSampleCount,
      'workspaceDocumentSamplesTruncated':
          request.context.workspace.documentSamplesTruncated,
      'workspaceBuildSystemHints':
          request.context.workspace.buildFacts.buildSystemHints,
      'workspaceToolingHints':
          request.context.workspace.buildFacts.toolingHints,
      ..._agentCodingMetadata(request.context.agent),
      if (request.context.workspace.lastSearch != null)
        'workspaceLastSearchMatchCount':
            request.context.workspace.lastSearch!.matchCount,
      if (request.context.workspace.lastSymbolSearch != null)
        'workspaceLastSymbolSearchMatchCount':
            request.context.workspace.lastSymbolSearch!.matchCount,
      'hasLanguageHover': request.context.language.hasHover,
      'hasFocusToken': request.context.language.focusToken != null,
      if (request.context.language.focusToken != null)
        'focusTokenKind': request.context.language.focusToken!.kind,
      if (request.context.language.focusToken?.semanticKind != null)
        'focusSemanticKind': request.context.language.focusToken!.semanticKind,
      'languageFocusedDiagnosticCount':
          request.context.language.focusedDiagnosticCount,
      'languageReferenceCount': request.context.language.referenceCount,
      'hasResolvedElement': request.context.language.resolvedElement != null,
      'hasResolvedReference':
          request.context.language.resolvedReference != null,
      'hasParameterInfo': request.context.language.parameterInfo != null,
      'languageParameterCount':
          request.context.language.parameterInfo?.parameterCount ?? 0,
      'languageCompletionCount': request.context.language.completionCount,
      'languageCodeActionCount': request.context.language.codeActionCount,
      'languageSemanticSpanCount': request.context.language.semanticSpanCount,
      'languageDocumentSymbolCount':
          request.context.language.documentSymbolCount,
      'languageInlayHintCount': request.context.language.inlayHintCount,
      'languageSemanticBlockCount': request.context.language.semanticBlockCount,
      'languageRefactorPreviewCount':
          request.context.language.refactorPreviewCount,
      'languageSurroundTemplateCount':
          request.context.language.surroundTemplateCount,
      if (request.context.language.serviceStatus != null)
        'languageServiceSeverity':
            request.context.language.serviceStatus!.severity,
      if (request.context.language.serviceStatus != null)
        'languageServiceUsableCapabilityCount':
            request.context.language.serviceStatus!.usableCapabilityCount,
      if (request.context.language.serviceStatus != null)
        'languageServiceFreshCapabilityCount':
            request.context.language.serviceStatus!.freshCapabilityCount,
      if (request.context.language.serviceStatus != null)
        'languageServiceLocalFallbackEnabled':
            request.context.language.serviceStatus!.localFallbackEnabled,
      if (request.context.language.serviceStatus?.parserEngine != null)
        'languageServiceParserEngine':
            request.context.language.serviceStatus!.parserEngine,
      if (request.context.language.serviceStatus?.grammarVersion != null)
        'languageServiceGrammarVersion':
            request.context.language.serviceStatus!.grammarVersion,
      if (request.context.language.serviceStatus != null)
        'languageServicePrimaryCapabilityStates':
            request.context.language.serviceStatus!.primaryCapabilityStates,
      'debugStatus': request.context.debug.status,
      'debugBreakpointCount': request.context.debug.breakpointCount,
      'debugThreadCount': request.context.debug.threadCount,
      'debugStackFrameCount': request.context.debug.stackFrameCount,
      'debugVariableCount': request.context.debug.variableCount,
      'persistenceCommandCount':
          request.context.commands.persistenceCommands.length,
      'diagnosticCommandCount':
          request.context.commands.diagnosticCommands.length,
      'languageServiceCommandCount':
          request.context.commands.languageServiceCommands.length,
      'navigationCommandCount':
          request.context.commands.navigationCommands.length,
      'refactorCommandCount': request.context.commands.refactorCommands.length,
      'toolchainCommandCount':
          request.context.commands.toolchainCommands.length,
      'nativeToolCommandCount':
          request.context.commands.nativeToolCommands.length,
      'nativeToolReadyCommandCount':
          request.context.commands.nativeToolReadyCommandCount,
      'nativeToolBlockedCommandCount':
          request.context.commands.nativeToolBlockedCommandCount,
      'debugCommandCount': request.context.commands.debugCommands.length,
      'debugReadyCommandCount': request.context.commands.debugReadyCommandCount,
      'debugBlockedCommandCount':
          request.context.commands.debugBlockedCommandCount,
      'settingsCommandCount': request.context.commands.settingsCommands.length,
      ..._lastCommandResultMetadata(request.context.commands.lastResult),
      'recentCommandResultCount': request.context.commands.recentResults.length,
      if (request.context.commands.recentResults.isNotEmpty)
        'recentCommandIds': request.context.commands.recentResults
            .map((result) => result.commandId)
            .toList(growable: false),
      'skillCount': request.context.skills.skillCount,
      'skillIds': request.context.skills.skillIds,
      'activeSkillCount': request.context.skills.activeSkillCount,
      'activeSkillIds': request.context.skills.activeSkillIds,
      'toolchainCount': request.context.toolchains.entryCount,
      'hasNativeCompiler': request.context.toolchains.hasNativeCompiler,
      ..._nativeToolMetadata(request.context.toolchains.nativeTools),
      if (request.context.toolchains.activeCompiler != null)
        'activeCompilerId': request.context.toolchains.activeCompiler!.id,
      'attachmentCount': request.attachments.length,
      'attachmentKinds': _attachmentKinds(request.attachments),
      'attachmentTruncatedCount': request.attachments
          .where(
            (attachment) =>
                attachment.content.length > _maxAgentAttachmentContentLength,
          )
          .length,
      'conversationTurnCount': request.conversationTurns.length,
    },
  };
}

List<String> _attachmentKinds(List<AgentRequestAttachment> attachments) {
  final kinds = <String>[];
  for (final attachment in attachments) {
    if (!kinds.contains(attachment.kind)) {
      kinds.add(attachment.kind);
    }
  }
  return kinds;
}

Map<String, Object?> _nativeToolMetadata(
  AgentNativeToolchainSummaryContext nativeTools,
) {
  return <String, Object?>{
    'nativeBuildToolCount': nativeTools.buildTools.length,
    'nativeBuildToolFamilies': _toolFamilies(nativeTools.buildTools),
    'nativeDebuggerCount': nativeTools.debuggers.length,
    'nativeDebuggerFamilies': _toolFamilies(nativeTools.debuggers),
    'nativeFormatterCount': nativeTools.formatters.length,
    'nativeFormatterFamilies': _toolFamilies(nativeTools.formatters),
    'nativeStaticAnalyzerCount': nativeTools.staticAnalyzers.length,
    'nativeStaticAnalyzerFamilies': _toolFamilies(nativeTools.staticAnalyzers),
    'nativeTestRunnerCount': nativeTools.testRunners.length,
    'nativeTestRunnerFamilies': _toolFamilies(nativeTools.testRunners),
    'nativeLanguageServiceCount': nativeTools.languageServices.length,
    'nativeLanguageServiceFamilies': _toolFamilies(
      nativeTools.languageServices,
    ),
  };
}

List<String> _toolFamilies(Iterable<AgentToolchainEntryContext> entries) {
  final families = <String>[];
  for (final entry in entries) {
    final family = entry.metadata['toolFamily'];
    if (family is String && family.trim().isNotEmpty) {
      final normalized = family.trim();
      if (!families.contains(normalized)) {
        families.add(normalized);
      }
    }
  }
  return List<String>.unmodifiable(families);
}

Map<String, Object?> _lastCommandResultMetadata(
  AgentCommandResultContext? result,
) {
  if (result == null) {
    return const <String, Object?>{};
  }
  final metadataKeys = result.metadata.keys
      .where((key) => key.trim().isNotEmpty)
      .toList(growable: false);
  final requiredCommandId = requiredCommandIdFromAgentMetadata(result.metadata);
  final recoveryForCommandId = _metadataString(
    result.metadata['recoveryForCommandId'],
  );
  final backendRoute = backendRouteFromAgentMetadata(result.metadata);
  final settingsRoute = _metadataString(result.metadata['settingsRoute']);
  final settingsSection = _metadataString(result.metadata['settingsSection']);
  final toolchainSelectionStatus = _metadataString(
    result.metadata['toolchainSelectionStatus'],
  );
  final toolchainSelectionMessage = _metadataString(
    result.metadata['toolchainSelectionMessage'],
  );
  final toolchainId = _metadataString(result.metadata['toolchainId']);
  final cppStandard = _metadataString(result.metadata['cppStandard']);
  final preferredBuildEngineHandoff = _metadataMap(
    result.metadata['preferredBuildEngineHandoff'],
  );
  final preferredBuildEngine = _metadataString(
    preferredBuildEngineHandoff?['engineFamily'],
  );
  final preferredBuildGenerator = _metadataString(
    preferredBuildEngineHandoff?['generatorFamily'],
  );
  final buildEngineHandoffCount = _metadataInt(
    result.metadata['buildEngineHandoffCount'],
  );
  return <String, Object?>{
    'lastCommandId': result.commandId,
    if (result.input != null) 'lastCommandInput': result.input,
    'lastCommandApplied': result.applied,
    'lastCommandMessage': result.message,
    if (metadataKeys.isNotEmpty) 'lastCommandMetadataKeys': metadataKeys,
    if (requiredCommandId != null)
      'lastCommandRequiredCommandId': requiredCommandId,
    if (recoveryForCommandId != null)
      'lastCommandRecoveryForCommandId': recoveryForCommandId,
    if (backendRoute != null) ...<String, Object?>{
      'lastCommandBackendRouteKind': backendRoute.routeKind,
      if (backendRoute.adapterKind != null)
        'lastCommandBackendRouteAdapterKind': backendRoute.adapterKind,
      'lastCommandBackendRouteAllowed': backendRoute.allowed,
      'lastCommandBackendRoutePreviewOnly': backendRoute.previewOnly,
      if (backendRoute.blockedReason != null)
        'lastCommandBackendRouteBlockedReason': backendRoute.blockedReason,
    },
    if (settingsRoute != null) 'lastCommandSettingsRoute': settingsRoute,
    if (settingsSection != null) 'lastCommandSettingsSection': settingsSection,
    if (toolchainSelectionStatus != null)
      'lastCommandToolchainSelectionStatus': toolchainSelectionStatus,
    if (toolchainSelectionMessage != null)
      'lastCommandToolchainSelectionMessage': toolchainSelectionMessage,
    if (toolchainId != null) 'lastCommandToolchainId': toolchainId,
    if (cppStandard != null) 'lastCommandCppStandard': cppStandard,
    if (buildEngineHandoffCount != null)
      'lastCommandBuildEngineHandoffCount': buildEngineHandoffCount,
    if (preferredBuildEngine != null)
      'lastCommandPreferredBuildEngine': preferredBuildEngine,
    if (preferredBuildGenerator != null)
      'lastCommandPreferredBuildGenerator': preferredBuildGenerator,
    if (result.completedAt != null)
      'lastCommandCompletedAt': result.completedAt!.toUtc().toIso8601String(),
  };
}

Map<Object?, Object?>? _metadataMap(Object? value) {
  if (value is Map) {
    return value;
  }
  return null;
}

int? _metadataInt(Object? value) {
  if (value is int) {
    return value;
  }
  return null;
}

String? _metadataString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, Object?> _agentCodingMetadata(AgentCodingLoopContext agent) {
  final metadata = <String, Object?>{};
  final pendingPatch = agent.pendingPatch;
  if (pendingPatch != null) {
    metadata.addAll(<String, Object?>{
      'pendingPatchId': pendingPatch.patchId,
      'pendingPatchEditCount': pendingPatch.editCount,
      'pendingPatchDocumentCount': pendingPatch.documentIds.length,
      'pendingPatchEditsTruncated': pendingPatch.editsTruncated,
    });
  }
  if (agent.recentPatchProposals.isNotEmpty) {
    metadata.addAll(<String, Object?>{
      'recentPatchProposalCount': agent.recentPatchProposals.length,
      'recentPatchProposalIds': agent.recentPatchProposals
          .map((patch) => patch.patchId)
          .toList(growable: false),
    });
  }
  if (agent.pendingIdeCommands.isNotEmpty) {
    metadata.addAll(<String, Object?>{
      'pendingIdeCommandCount': agent.pendingIdeCommands.length,
      'pendingIdeCommandIds': agent.pendingIdeCommands
          .map((command) => command.commandId)
          .toList(growable: false),
    });
  }
  if (agent.recentIdeCommandSuggestions.isNotEmpty) {
    metadata.addAll(<String, Object?>{
      'recentIdeCommandSuggestionCount':
          agent.recentIdeCommandSuggestions.length,
      'recentIdeCommandSuggestionIds': agent.recentIdeCommandSuggestions
          .map((command) => command.commandId)
          .toList(growable: false),
    });
  }
  final providerExecution = agent.providerExecution;
  if (providerExecution != null) {
    final selectedEndpoint = providerExecution.selectedEndpoint;
    metadata.addAll(<String, Object?>{
      'providerExecutionStatus': providerExecution.status,
      'providerExecutionEndpointCount': providerExecution.endpoints.length,
      'providerExecutionMissingCredentialEndpointCount':
          providerExecution.missingCredentialEndpointCount,
      if (providerExecution.selectedEndpointIndex != null)
        'providerExecutionSelectedEndpointIndex':
            providerExecution.selectedEndpointIndex,
      if (selectedEndpoint != null)
        'providerExecutionSelectedRouteKind': selectedEndpoint.routeKind,
      if (selectedEndpoint != null)
        'providerExecutionSelectedProviderKind': selectedEndpoint.providerKind,
      if (selectedEndpoint != null)
        'providerExecutionSelectedCredentialReadiness':
            selectedEndpoint.credentialReadiness,
    });
  }
  final providerFailure = agent.lastProviderFailure;
  if (providerFailure != null) {
    metadata.addAll(<String, Object?>{
      'lastProviderFailureKind': providerFailure.kind,
      'lastProviderFailureOperation': providerFailure.operation,
      if (providerFailure.statusCode != null)
        'lastProviderFailureStatusCode': providerFailure.statusCode,
    });
  }
  final patchApplication =
      agent.lastPatchApplication ??
      (agent.recentPatchApplications.isEmpty
          ? null
          : agent.recentPatchApplications.first);
  if (patchApplication == null) {
    return metadata;
  }
  metadata.addAll(<String, Object?>{
    'recentPatchApplicationCount': agent.recentPatchApplications.length,
    if (agent.recentPatchApplications.isNotEmpty)
      'recentPatchApplicationPatchIds': agent.recentPatchApplications
          .map((application) => application.patchId)
          .toList(growable: false),
    'lastPatchApplicationPatchId': patchApplication.patchId,
    'lastPatchApplicationApplied': patchApplication.applied,
    'lastPatchApplicationPendingPatchRetained':
        patchApplication.pendingPatchRetained,
    'lastPatchApplicationMessage': patchApplication.message,
    'lastPatchApplicationEditCount': patchApplication.editCount,
    'lastPatchApplicationAppliedEditCount': patchApplication.appliedEditCount,
    'lastPatchApplicationChangedDocumentCount':
        patchApplication.changedDocumentIds.length,
    'lastPatchApplicationSkippedNoOpDocumentCount':
        patchApplication.skippedNoOpDocumentIds.length,
  });
  return metadata;
}

Map<String, Object?> _attachmentJsonForProvider(
  AgentRequestAttachment attachment,
) {
  final content = attachment.content;
  final truncated = content.length > _maxAgentAttachmentContentLength;
  final metadataJson = _attachmentMetadataJson(attachment.metadata);
  return <String, Object?>{
    'attachmentId': attachment.attachmentId,
    'kind': attachment.kind,
    'name': attachment.name,
    if (metadataJson.isNotEmpty) 'metadata': metadataJson,
    'content': truncated
        ? content.substring(0, _maxAgentAttachmentContentLength)
        : content,
    'contentTruncated': truncated,
  };
}

String _systemPromptWithStructuredResponseContract(String systemPrompt) {
  return '''
$systemPrompt

Vityo structured response contract:
- For normal explanation, return plain assistant text.
- For code changes, return a JSON object with a top-level "contentParts" array.
- A planning part may use {"kind":"plan","text":"...","plan":{"summary":"...","steps":["..."],"acceptanceCriteria":["..."],"risks":["..."]}} before code_patch or ide_command parts.
- A diagnostic summary part may use {"kind":"diagnostic_summary","text":"...","diagnosticSummary":{"title":"...","summary":"...","severity":"warning","diagnosticCount":1,"affectedDocuments":["..."],"suggestedCommandIds":["previewQuickFix","applyQuickFix"]}}.
- A code change part must use {"kind":"code_patch","text":"...","patch":{"patchId":"...","summary":"...","baseRevision":0,"edits":[{"documentId":"...","operation":"replace","start":0,"end":0,"replacementText":"..."}]}}.
- To suggest a registered IDE command without directly patching files, use {"kind":"ide_command","text":"...","command":{"commandId":"renameSymbol","input":"...","reason":"..."}}. If a command is only a prerequisite for another command, include "prerequisiteForCommandId":"runBuild".
- ide_command.commandId must come from the IDE context commands catalog; do not invent command IDs.
- To create a new file, use a single edit for that document with {"operation":"create","start":0,"end":0,"replacementText":"full file text"}.
- To delete an existing file, use a single edit for that document with {"operation":"delete","start":0,"end":0,"replacementText":""}.
- patch.baseRevision is a fallback for replace edits only; create/delete file operations should set edit.baseRevision only when checking the target file revision.
- Edit offsets are UTF-16 code unit offsets in the full active document, not just the provided text window.
- If Vityo IDE context includes document.textStart greater than 0, add document.textStart to offsets derived from document.text.
- selection and source range line and column fields use zero-based coordinates; edit offsets are still authoritative for patches.
- documentId must not contain "." or ".." path segments.
- Before multi-file patches, read workspace.files, workspace.documentSamples, workspace.openDocumentIds, and workspace.dirtyDocumentIds from the IDE context.
- workspace.documentSamples is a capped content sample of active/open/cached documents, not a full workspace index; do not assume unsampled files have been read.
- If workspace.lastSearch is present, use it as the latest IDE-confirmed workspace text search result before requesting additional file opens.
- If workspace.lastSymbolSearch is present, use it as the latest IDE-confirmed workspace symbol search result before broad refactors, rename planning, or multi-file edits.
- For C/C++ work, read workspace.buildFacts.buildSystemHints and workspace.buildFacts.toolingHints before choosing compile database, CMake, CMake presets, Ninja, clangd, formatter, static-analysis, or test-runner assumptions.
- Do not patch inactive dirty documents from workspace.dirtyDocumentIds; ask the user to switch, save, or discard those local changes first.
- If the IDE context includes language.focusToken, treat it as the token nearest the current selection before editing a single identifier or operator.
- If the IDE context includes language.focusedDiagnostics, treat them as the diagnostics nearest the current selection before choosing quick fixes or code edits.
- If the IDE context includes language.resolvedElement or language.resolvedReference, treat them as the primary resolved symbol facts for the current selection.
- If the IDE context includes language.parameterInfo, use its signature, activeParameterIndex, activeParameter, and parameter ranges as signature-help facts before changing a call expression.
- If the IDE context includes language.codeActions.edits, treat those edits as IDE-produced quick-fix workspace edit facts before inventing a replacement patch.
- If commands.diagnosticCommands includes previewQuickFix, suggest previewQuickFix before applyQuickFix for cross-file quick fixes and inspect commands.lastResult.metadata.workspaceEditPreview before applying.
- If the IDE context includes language.documentSymbols, use them as the current document outline before planning broad edits.
- If the IDE context includes language.inlayHints, use them as language-derived parameter/type hint facts before changing calls or inferred values.
- If the IDE context includes language.semanticBlocks, use them as structural block ranges before extract, move, fold, or broad rewrite operations.
- If the IDE context includes language.refactorPreviews, treat safeDelete and inlineVariable previews as IDE-produced refactor edit facts before suggesting those commands or equivalent patches.
- If the IDE context includes language.surroundTemplates, use those IDE-produced templates before inventing surround-with edits for the current selection.
- If the IDE context includes language.hoverMarkdown, language.definition, language.references, language.completions, language.codeActions, language.semanticSpans, language.documentSymbols, language.inlayHints, language.semanticBlocks, language.refactorPreviews, or language.surroundTemplates, treat them as compiler-derived facts for the current selection or document.
- If the IDE context includes language.serviceStatus, inspect capability states before using language facts; treat derived or fallback-backed facts as weaker evidence than available StyioService payloads, and do not present unsupported or unavailable capabilities as real compiler truth.
- If language.serviceStatus includes parserEngine or grammarVersion, treat them as the active Styio syntax contract before making syntax-sensitive edits; do not invent syntax outside that reported contract.
- If the IDE context includes debug.status, debug.launch.ready, debug.breakpoints, debug.threads, debug.stackFrames, or debug.variables, treat them as the latest IDE debugger facts before proposing debug commands or patches. Do not propose launch, continue, or step actions when debug.launch.ready is false.
- When proposing selectDebugThread or selectDebugStackFrame, use an id from debug.threads or debug.stackFrames instead of inventing thread or frame ids.
- If the IDE context includes commands.persistenceCommands, commands.diagnosticCommands, commands.navigationCommands, commands.refactorCommands, commands.toolchainCommands, commands.nativeToolCommands, commands.debugCommands, or commands.settingsCommands, prefer those registered IDE actions for save/save-all, diagnostics, quick fixes, definitions, references, refactors, toolchain selection, native tool actions, debug actions, and settings/profile recovery instead of inventing unsupported commands.
- If a registered command has requiresInput true, include ide_command.command.input using that command's inputLabel; do not propose missing-input commands.
- If commands.toolchainCommands includes selectClangCppVersion and toolchains.clangCpp.candidates contains the desired version, propose selectClangCppVersion with input "versionId" or "versionId c++23" instead of editing toolchain configuration files directly.
- If commands.nativeToolCommandReadiness is present, inspect each entry's ready flag, requiredKind, requiredToolFamily, requiredToolFamilies, toolFamily, toolchainId, requiredCommandId, dirtyDocumentIds, and reason before proposing runBuild, formatActiveDocument, runStaticAnalysis, or runTests.
- If commands.debugCommandReadiness is present, inspect each entry's ready flag, requiredState, requiredCommandId, dirtyDocumentIds, candidateIds, and reason before proposing startDebugging, continueDebugging, stepOver, selectDebugThread, selectDebugStackFrame, or stopDebugging.
- If a command readiness entry is not ready and includes requiredCommandId, propose that registered required command before the blocked command.
- If a native tool command readiness entry is not ready, has no requiredCommandId, and commands.settingsCommands includes openSettings, propose openSettings before retrying the missing-tool command.
- If language.serviceStatus is stale, unavailable, failed, or missing usable facts and commands.languageServiceCommands includes refreshLanguageService, propose that registered command before making language-fact-sensitive edits.
- Before proposing build, test, static-analysis, or debug commands for dirty workspace documents, prefer commands.persistenceCommands save or saveAll when the user needs disk-backed tool feedback.
- If the IDE context includes commands.recentResults, read it as newest-first user-confirmed IDE command outcomes before deciding the next step.
- If the IDE context includes commands.lastResult, treat it as the latest user-confirmed IDE command outcome before deciding the next step.
- If commands.recentResults includes metadata.requiredCommand or nested buildResult/staticAnalysisResult/testResult.requiredCommand, propose that registered required command before retrying that recent result.
- If the IDE context includes agent.pendingPatch, treat it as the current unapplied structured patch that the user may want to apply, revise, explain, or discard.
- If the IDE context includes agent.recentPatchProposals, read it as newest-first structured code patch proposals from recent assistant responses.
- If the IDE context includes agent.recentCodingPlans, read it as newest-first structured plan, step, acceptance, and risk evidence from recent assistant responses.
- If the IDE context includes agent.recentDiagnosticSummaries, read it as newest-first structured diagnostic triage from recent assistant responses.
- If the IDE context includes agent.pendingIdeCommands, treat them as current unapplied IDE command suggestions waiting for user confirmation or revision.
- If the IDE context includes agent.recentIdeCommandSuggestions, read it as newest-first structured IDE command suggestions from recent assistant responses.
- If the IDE context includes agent.lastProviderFailure, read it as the latest structured provider transport failure before proposing retry, failover, or provider reconfiguration.
- If the IDE context includes agent.providerExecution, read status, selectedEndpointIndex, credentialReadiness, requiresCredential, and missingCredentialEndpointCount before assuming the current assistant is backed by a real provider instead of fallback or local-only execution.
- If the IDE context includes agent.recentPatchApplications, read it as newest-first structured IDE patch application outcomes before deciding whether to retry, repair, or continue after a patch.
- If the IDE context includes agent.lastPatchApplication, treat it as the latest structured IDE patch application outcome.
- If agent.lastPatchApplication.skippedNoOpDocumentIds is non-empty, treat those documents as unchanged by the last patch attempt before retrying or proposing another patch.
- If agent.lastPatchApplication.pendingPatchRetained is true, repair, revise, explain, or discard the retained pending patch before proposing an unrelated new patch.
- If commands.lastResult.metadata.requiredCommand is present, propose that registered command before retrying the blocked operation.
- If commands.lastResult.metadata.completedRequiredCommandFor is present, treat that command ID as the previously blocked operation that may now be retried when still relevant.
- If commands.lastResult.metadata.recoveryForCommandId is present, treat that command ID as still blocked until the user or settings flow changes the underlying readiness facts.
- If commands.lastResult.metadata.backendRouteSelection is present, inspect routeKind, adapterKind, allowed, previewOnly, and blockedReason before proposing build, run, test, retry, or provider/toolchain reconfiguration.
- If commands.lastResult.metadata.backendRouteSelection.allowed is false and commands.settingsCommands includes openSettings, propose openSettings before retrying the blocked route.
- If commands.lastResult.metadata.toolchainSelectionStatus is present, inspect toolchainId, cppStandard, toolchainSelectionMessage, and status before proposing build, test, or another selectClangCppVersion command.
- If commands.lastResult.metadata.toolchainSelectionStatus is present, status is not selected, and commands.settingsCommands includes openSettings, propose openSettings before another selection or build/test retry.
- If commands.lastResult.metadata.preferredBuildEngineHandoff is present, use its engineFamily, generatorFamily, arguments, and environment for the next CMake/Ninja handoff instead of inventing build flags.
- If commands.lastResult.metadata.buildResult is present, treat it as the latest structured build outcome before proposing another build, test, debug, or code patch step.
- If commands.lastResult.metadata.formatResult is present, treat it as the latest structured formatting outcome before proposing another formatter run or patch cleanup.
- If commands.lastResult.metadata.staticAnalysisResult is present, treat it as the latest structured static-analysis outcome before proposing another analysis run, test, or code patch step.
- If commands.lastResult.metadata.testResult is present, treat it as the latest structured test outcome before proposing another test, debug, or code patch step.
- If the IDE context includes skills.activeSkillIds, prefer those activated skills for the current workspace before falling back to the full skills catalog.
- If the IDE context includes skills, treat those entries as available coding skills. For Styio language work, prefer the Styio-first skills and StyioService facts; use C++/Clang skills only when workspace evidence or user intent proves native compiler work.
- If the IDE context includes reference-grounded IDE development skills, use mature open-source IDE references only as evidence for Vityo-local contracts, then validate the resulting Vityo artifact with a targeted test or gate.
- If the IDE context includes toolchains.activeCompiler, treat it as the IDE-selected compiler route. For native C/C++ patches, prefer toolchains.activeCompiler.metadata.cCompilerPath and cxxCompilerPath when present.
- If the IDE context includes toolchains.clangCpp, treat it as the IDE-selected Clang/C++ version manager. Inspect toolchains.clangCpp.preferenceStatus, preferenceMessage, toolchains.clangCpp.selection.candidate.version, and toolchains.clangCpp.selection.candidate.metadata.clangVendor before relying on the selected compiler. Prefer toolchains.clangCpp.selection.preferredBuildEngineHandoff and toolchains.clangCpp.selection.buildEngineHandoffs when choosing an external CMake or Ninja handoff; fall back to toolchains.clangCpp.cmakeExecutablePath plus toolchains.clangCpp.selection.cmakeConfigureArguments for CMake, toolchains.clangCpp.selection.cmakeNinjaConfigureArguments for CMake with the Ninja generator, and toolchains.clangCpp.ninjaExecutablePath plus toolchains.clangCpp.selection.ninjaEnvironment for direct Ninja handoff, instead of inventing compiler paths, build engine paths, or C++ standard flags.
- If toolchains.nativeTools.languageServices includes clangd, pair that fact with workspace.buildFacts.hasCompilationDatabase before relying on C/C++ language-service facts.
- If the IDE context includes toolchains.nativeTools, use its build/debug/format/static-analysis/test-runner/language-service groups before proposing C++ build, debug, formatting, static-analysis, or test actions.
- For replace/delete edits, documentId should refer to an existing workspace file; use create only for new files.
- For the active editor document, use replace edits; do not use create/delete file operations on the active document.
- Do not include secrets, credentials, or unrelated files in code patches.
'''
      .trim();
}

AgentProviderResponseEnvelope _responseEnvelopeFromOpenAICompatibleResponse({
  required String requestId,
  required Map<String, Object?> response,
}) {
  final choices = response['choices'];
  if (choices is! List || choices.isEmpty) {
    return _responseEnvelopeFromOpenAIOutputResponse(
      requestId: requestId,
      response: response,
    );
  }
  final firstChoice = choices.first;
  final choice = firstChoice is Map
      ? firstChoice.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        )
      : const <String, Object?>{};
  final message = choice['message'];
  final messageMap = message is Map
      ? message.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        )
      : const <String, Object?>{};
  final usage = response['usage'];

  final contentParts = _contentPartsFromAssistantMessage(messageMap);
  return AgentProviderResponseEnvelope(
    requestId: requestId,
    providerMessageId: response['id'] as String?,
    role: messageMap['role'] as String? ?? 'assistant',
    finishReason: choice['finish_reason'] as String? ?? 'unknown',
    contentParts: contentParts.isEmpty
        ? const <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: ''),
          ]
        : contentParts,
    usage: usage is Map
        ? usage.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          )
        : null,
  );
}

AgentProviderResponseEnvelope _responseEnvelopeFromOpenAIOutputResponse({
  required String requestId,
  required Map<String, Object?> response,
}) {
  final parts = <AgentContentPart>[];
  var role = 'assistant';
  final output = response['output'];
  if (output is List) {
    for (final item in output) {
      if (item is! Map) {
        continue;
      }
      final itemMap = item.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
      role = itemMap['role'] as String? ?? role;
      parts.addAll(_contentPartsFromAssistantMessage(itemMap));
      for (final arguments in _openAIOutputArgumentCandidates(itemMap)) {
        final structuredParts = _structuredContentPartsFromString(arguments);
        if (structuredParts != null) {
          parts.addAll(structuredParts);
        }
      }
    }
  }
  if (parts.isEmpty) {
    final outputText = response['output_text'];
    if (outputText is String && outputText.trim().isNotEmpty) {
      parts.addAll(_contentPartsFromAssistantContent(outputText));
    }
  }

  final usage = response['usage'];
  return AgentProviderResponseEnvelope(
    requestId: requestId,
    providerMessageId: response['id'] as String?,
    role: role,
    finishReason: response['status'] as String? ?? 'unknown',
    contentParts: parts.isEmpty
        ? const <AgentContentPart>[
            AgentContentPart(kind: AgentContentPartKind.text, text: ''),
          ]
        : parts,
    usage: usage is Map
        ? usage.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          )
        : null,
  );
}

List<AgentContentPart> _contentPartsFromAssistantMessage(
  Map<String, Object?> messageMap,
) {
  final parts = <AgentContentPart>[];
  final content = messageMap['content'];
  if (_assistantContentHasValue(content)) {
    parts.addAll(_contentPartsFromAssistantContent(content));
  }

  for (final arguments in _assistantToolCallArgumentCandidates(messageMap)) {
    final structuredParts = _structuredContentPartsFromString(arguments);
    if (structuredParts != null) {
      parts.addAll(structuredParts);
    }
  }

  if (parts.isNotEmpty) {
    return parts;
  }
  if (content == null) {
    return const <AgentContentPart>[];
  }
  return _contentPartsFromAssistantContent(content);
}

List<String> _assistantToolCallArgumentCandidates(
  Map<String, Object?> messageMap,
) {
  final toolCalls = messageMap['tool_calls'];
  if (toolCalls is! List || toolCalls.isEmpty) {
    return const <String>[];
  }
  final candidates = <String>[];
  for (final toolCall in toolCalls) {
    if (toolCall is! Map) {
      continue;
    }
    final function = toolCall['function'];
    if (function is! Map) {
      continue;
    }
    final arguments = function['arguments'];
    if (arguments is String && arguments.trim().isNotEmpty) {
      candidates.add(arguments);
    }
  }
  return List.unmodifiable(candidates);
}

List<String> _openAIOutputArgumentCandidates(Map<String, Object?> outputItem) {
  final candidates = <String>[];
  final arguments = outputItem['arguments'];
  if (arguments is String && arguments.trim().isNotEmpty) {
    candidates.add(arguments);
  }
  final function = outputItem['function'];
  if (function is Map) {
    final functionArguments = function['arguments'];
    if (functionArguments is String && functionArguments.trim().isNotEmpty) {
      candidates.add(functionArguments);
    }
  }
  return List.unmodifiable(candidates);
}

bool _assistantContentHasValue(Object? content) {
  if (content is String) {
    return content.trim().isNotEmpty;
  }
  if (content is List) {
    return content.isNotEmpty;
  }
  return content != null;
}

List<AgentContentPart> _contentPartsFromAssistantContent(Object? content) {
  if (content is String) {
    final structuredParts = _structuredContentPartsFromString(content);
    if (structuredParts != null) {
      return structuredParts;
    }
    return <AgentContentPart>[
      AgentContentPart(kind: AgentContentPartKind.text, text: content),
    ];
  }
  if (content is List) {
    final text = content
        .map(_textFromOpenAIContentBlock)
        .where((blockText) => blockText.isNotEmpty)
        .join('\n\n');
    final structuredParts = _structuredContentPartsFromString(text);
    if (structuredParts != null) {
      return structuredParts;
    }
    return <AgentContentPart>[
      AgentContentPart(kind: AgentContentPartKind.text, text: text),
    ];
  }
  return const <AgentContentPart>[
    AgentContentPart(kind: AgentContentPartKind.text, text: ''),
  ];
}

List<AgentContentPart>? _structuredContentPartsFromString(String content) {
  for (final candidate in _jsonPayloadCandidates(content)) {
    try {
      final decoded = jsonDecode(candidate);
      final decodedMap = decoded is Map<String, Object?>
          ? decoded
          : decoded is Map
          ? decoded.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : null;
      final contentParts =
          decodedMap?['contentParts'] ?? decodedMap?['content_parts'];
      if (contentParts is! List) {
        continue;
      }
      final parsed = contentParts
          .map(_agentContentPartFromJson)
          .whereType<AgentContentPart>()
          .toList(growable: false);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    } on Object {
      continue;
    }
  }
  return null;
}

List<String> _jsonPayloadCandidates(String content) {
  final trimmed = content.trim();
  final candidates = <String>[];
  void addCandidate(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || candidates.contains(candidate)) {
      return;
    }
    candidates.add(candidate);
  }

  addCandidate(trimmed);
  for (final match in RegExp(
    r'```[^\n]*\n?([\s\S]*?)```',
  ).allMatches(trimmed)) {
    final fencedContent = match.group(1);
    if (fencedContent != null) {
      addCandidate(fencedContent);
    }
  }

  final firstBrace = trimmed.indexOf('{');
  final lastBrace = trimmed.lastIndexOf('}');
  if (firstBrace >= 0 && lastBrace > firstBrace) {
    addCandidate(trimmed.substring(firstBrace, lastBrace + 1));
  }

  return List.unmodifiable(candidates);
}

AgentContentPart? _agentContentPartFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return AgentContentPart.fromJson(value);
  }
  if (value is Map) {
    return AgentContentPart.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return null;
}

String _textFromOpenAIContentBlock(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is Map) {
    final type = value['type'];
    if (type == 'text' || type == 'output_text') {
      return value['text']?.toString() ?? '';
    }
  }
  return '';
}

Uri _chatCompletionsEndpoint(String baseUrl) {
  final normalized = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  if (normalized.endsWith('/chat/completions')) {
    return Uri.parse(normalized);
  }
  return Uri.parse('$normalized/chat/completions');
}
