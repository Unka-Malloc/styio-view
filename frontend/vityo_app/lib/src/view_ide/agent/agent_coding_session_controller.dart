import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_coding_session_history_store.dart';
import 'agent_code_patch_applier.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_route_executor.dart';
import 'agent_provider_streaming_runtime.dart';
import 'agent_session_context.dart';
import 'agent_workspace_edit_adapter.dart';
import '../runtime/runtime.dart';

typedef AgentSessionContextProvider = AgentSessionContext Function();

const int _maxAgentPatchApplicationContextHistory = 12;
const int _maxAgentRecentPatchProposalContexts = 6;
const int _maxAgentPendingPatchContextEdits = 20;
const int _maxAgentPendingPatchReplacementTextSampleLength = 2000;
const int _maxAgentCommandResultContextHistory = 12;
const int _maxAgentPendingIdeCommandContexts = 10;
const int _maxAgentRecentIdeCommandSuggestionContexts = 12;
const int _maxAgentRecentCodingPlanContexts = 8;
const int _maxAgentRecentDiagnosticSummaryContexts = 8;

class AgentCodingSessionController extends ChangeNotifier {
  AgentCodingSessionController({
    required this.profile,
    required this.adapter,
    required this.contextProvider,
    this.maxConversationTurns = 20,
    this.maxConversationTurnTextLength = 12000,
    this.maxAttachments = 10,
    this.sessionHistoryStore,
    this.sessionHistoryWorkspaceId = 'default',
    this.sessionHistoryMaxEntries = 50,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    AgentProviderSelectionPlan? providerSelectionPlan,
    AgentProviderExecutionResolution? providerExecutionResolution,
  }) : _runtimeOutputBuffer = runtimeOutputBuffer,
       _providerSelectionPlan = providerSelectionPlan,
       _providerExecutionResolution = providerExecutionResolution;

  AgentPromptProfile profile;
  AgentProviderAdapter adapter;
  AgentSessionContextProvider contextProvider;
  final int maxConversationTurns;
  final int maxConversationTurnTextLength;
  final int maxAttachments;
  final AgentCodingSessionHistoryStore? sessionHistoryStore;
  final String sessionHistoryWorkspaceId;
  final int sessionHistoryMaxEntries;
  final RuntimeOutputLiveBuffer? _runtimeOutputBuffer;

  int _requestSequence = 0;
  int _activeRequestSerial = 0;
  int _patchApplicationSerial = 0;
  String _draftPrompt = '';
  bool _sending = false;
  bool _applyingPatch = false;
  bool _applyingIdeCommand = false;
  AgentProviderResponseEnvelope? _lastResponse;
  AgentCodePatch? _pendingPatch;
  AgentCodePatchApplicationResult? _lastPatchApplicationResult;
  AgentPatchApplicationContext? _lastPatchApplicationContext;
  AgentCommandResultContext? _lastIdeCommandResultContext;
  bool _hasPreservedAgentState = false;
  AgentProviderResponseEnvelope? _preservedLastResponse;
  AgentCodePatch? _preservedPendingPatch;
  AgentCodePatchApplicationResult? _preservedLastPatchApplicationResult;
  final List<AgentCommandResultContext> _recentIdeCommandResultContexts =
      <AgentCommandResultContext>[];
  final Set<String> _completedIdeCommandSuggestionKeys = <String>{};
  final List<AgentPatchApplicationContext> _recentPatchApplicationContexts =
      <AgentPatchApplicationContext>[];
  final List<AgentPendingPatchContext> _recentPatchProposalContexts =
      <AgentPendingPatchContext>[];
  final List<AgentPendingIdeCommandContext>
  _recentIdeCommandSuggestionContexts = <AgentPendingIdeCommandContext>[];
  final List<AgentCodingPlanContext> _recentCodingPlanContexts =
      <AgentCodingPlanContext>[];
  final List<AgentDiagnosticSummaryContext> _recentDiagnosticSummaryContexts =
      <AgentDiagnosticSummaryContext>[];
  String? _providerMountMessage;
  AgentProviderSelectionPlan? _providerSelectionPlan;
  AgentProviderExecutionResolution? _providerExecutionResolution;
  String? _lastError;
  AgentProviderTransportException? _lastProviderFailure;
  String? _activeProviderRequestId;
  String? _activeProviderPrompt;
  DateTime? _activeProviderStartedAt;
  AgentCodingSessionHistory? _sessionHistorySnapshot;
  final List<AgentRequestAttachment> _attachments = <AgentRequestAttachment>[];
  final List<AgentConversationTurn> _conversationTurns =
      <AgentConversationTurn>[];

  String get draftPrompt => _draftPrompt;
  bool get sending => _sending;
  bool get applyingPatch => _applyingPatch;
  bool get applyingIdeCommand => _applyingIdeCommand;
  AgentProviderResponseEnvelope? get lastResponse => _lastResponse;
  AgentCodePatch? get pendingPatch => _pendingPatch;
  AgentWorkspaceEditPlanConversion? get pendingWorkspaceEditPlanConversion =>
      _pendingPatch == null
      ? null
      : const AgentWorkspaceEditPlanAdapter().convert(_pendingPatch!);
  AgentCodePatchApplicationResult? get lastPatchApplicationResult =>
      _lastPatchApplicationResult;
  AgentPatchApplicationContext? get lastPatchApplicationContext =>
      _lastPatchApplicationContext;
  AgentCommandResultContext? get lastIdeCommandResultContext =>
      _lastIdeCommandResultContext;
  List<AgentPatchApplicationContext> get recentPatchApplicationContexts =>
      List<AgentPatchApplicationContext>.unmodifiable(
        _recentPatchApplicationContexts,
      );
  String? get providerMountMessage => _providerMountMessage;
  AgentProviderSelectionPlan? get providerSelectionPlan =>
      _providerSelectionPlan;
  AgentProviderExecutionResolution? get providerExecutionResolution =>
      _providerExecutionResolution;
  AgentProviderKind get providerKind => adapter.kind;
  bool get providerSupportsCodePatch => adapter.supportsCodePatch;
  String get providerSummary =>
      '${profile.displayName} / ${adapter.adapterId} / ${adapter.kind.wireValue}';
  AgentCodingSessionHistory get sessionHistorySnapshot =>
      _sessionHistorySnapshot ??
      AgentCodingSessionHistory(workspaceId: sessionHistoryWorkspaceId);
  AgentCodingSessionCheckpoint get sessionCheckpoint =>
      sessionHistorySnapshot.toCheckpoint();
  String? get lastError => _lastError;
  AgentProviderTransportException? get lastProviderFailure =>
      _lastProviderFailure;
  List<AgentRequestAttachment> get attachments =>
      List<AgentRequestAttachment>.unmodifiable(_attachments);
  List<AgentConversationTurn> get conversationTurns =>
      List<AgentConversationTurn>.unmodifiable(_conversationTurns);
  bool get canSend =>
      !_sending &&
      !_applyingPatch &&
      !_applyingIdeCommand &&
      _draftPrompt.trim().isNotEmpty;

  void mountProvider({
    required AgentPromptProfile profile,
    required AgentProviderAdapter adapter,
    String? message,
    AgentProviderSelectionPlan? selectionPlan,
    AgentProviderExecutionResolution? executionResolution,
  }) {
    this.profile = profile;
    this.adapter = adapter;
    _providerSelectionPlan = selectionPlan;
    _providerExecutionResolution = executionResolution;
    _activeRequestSerial += 1;
    _patchApplicationSerial += 1;
    _cancelActiveProviderRequest();
    _sending = false;
    _applyingPatch = false;
    _applyingIdeCommand = false;
    _providerMountMessage = message == null
        ? null
        : sanitizeAgentError(message);
    _lastError = null;
    _lastProviderFailure = null;
    _lastResponse = null;
    _pendingPatch = null;
    _lastPatchApplicationResult = null;
    _lastPatchApplicationContext = null;
    _lastIdeCommandResultContext = null;
    _clearPreservedAgentState();
    _recentIdeCommandResultContexts.clear();
    _completedIdeCommandSuggestionKeys.clear();
    _recentPatchApplicationContexts.clear();
    _recentPatchProposalContexts.clear();
    _recentIdeCommandSuggestionContexts.clear();
    _recentCodingPlanContexts.clear();
    _recentDiagnosticSummaryContexts.clear();
    _attachments.clear();
    _conversationTurns.clear();
    notifyListeners();
  }

  Future<void> loadSessionHistory() async {
    final store = sessionHistoryStore;
    if (store == null) {
      _sessionHistorySnapshot = AgentCodingSessionHistory(
        workspaceId: sessionHistoryWorkspaceId,
      );
      return;
    }
    try {
      _sessionHistorySnapshot = await store.readHistory(
        workspaceId: sessionHistoryWorkspaceId,
      );
      notifyListeners();
    } on Object catch (error) {
      _sessionHistorySnapshot = AgentCodingSessionHistory(
        workspaceId: sessionHistoryWorkspaceId,
      );
      _publishAgentRuntimeDiagnostic(
        operation: 'agent.history.restore',
        message:
            'Agent history restore failed: ${sanitizeAgentError(error.toString())}',
      );
      notifyListeners();
    }
  }

  void updatePrompt(String value) {
    if (_draftPrompt == value) {
      return;
    }
    _draftPrompt = value;
    notifyListeners();
  }

  void cancelActiveRequest() {
    if (!_sending) {
      return;
    }
    _cancelActiveProviderRequest();
    _activeRequestSerial += 1;
    _restorePreservedAgentState();
    _sending = false;
    _lastError = 'Agent request cancelled.';
    _lastProviderFailure = null;
    notifyListeners();
  }

  void addAttachment(AgentRequestAttachment attachment) {
    if (attachment.attachmentId.trim().isEmpty ||
        attachment.kind.trim().isEmpty ||
        attachment.name.trim().isEmpty ||
        attachment.content.trim().isEmpty) {
      return;
    }
    _attachments.removeWhere(
      (existing) => existing.attachmentId == attachment.attachmentId,
    );
    _attachments.add(attachment);
    _trimAttachments();
    notifyListeners();
  }

  void removeAttachment(String attachmentId) {
    final before = _attachments.length;
    _attachments.removeWhere(
      (attachment) => attachment.attachmentId == attachmentId,
    );
    if (_attachments.length != before) {
      notifyListeners();
    }
  }

  void clearAttachments() {
    if (_attachments.isEmpty) {
      return;
    }
    _attachments.clear();
    notifyListeners();
  }

  Future<AgentProviderResponseEnvelope?> sendPrompt() async {
    final prompt = _draftPrompt.trim();
    if (_sending || _applyingPatch || prompt.isEmpty) {
      return null;
    }

    final requestSerial = _activeRequestSerial + 1;
    _activeRequestSerial = requestSerial;
    final requestContext = _contextForProviderRequest();
    final patchApplicationContextSent = _lastPatchApplicationContext;
    _preserveAgentStateForActiveRequest();
    _sending = true;
    _lastError = null;
    _lastProviderFailure = null;
    _lastResponse = null;
    _pendingPatch = null;
    _lastPatchApplicationResult = null;
    notifyListeners();

    final requestId = _nextRequestId();
    final requestStartedAt = DateTime.now().toUtc();
    try {
      final request = AgentProviderRequest(
        requestId: requestId,
        profile: profile,
        context: requestContext,
        userPrompt: prompt,
        attachments: attachments,
        conversationTurns: _conversationWindow(),
      );
      _activeProviderRequestId = request.requestId;
      _activeProviderPrompt = prompt;
      _activeProviderStartedAt = requestStartedAt;
      final response = await _sendProviderRequest(request);
      if (requestSerial != _activeRequestSerial) {
        return null;
      }
      _lastResponse = response;
      _completedIdeCommandSuggestionKeys.clear();
      _pendingPatch = _firstPatch(response);
      _recordRecentPatchProposalContext(_pendingPatch);
      _recordRecentCodingPlanContexts(response);
      _recordRecentDiagnosticSummaryContexts(response);
      _recordRecentIdeCommandSuggestionContexts(response);
      _clearPreservedAgentState();
      if (identical(
        _lastPatchApplicationContext,
        patchApplicationContextSent,
      )) {
        _lastPatchApplicationContext = null;
      }
      _appendConversationTurn(role: AgentConversationRole.user, text: prompt);
      _appendAssistantTurn(response);
      _draftPrompt = '';
      _attachments.clear();
      await _appendAgentCodingSessionHistory(
        AgentCodingSessionHistoryRecord.fromResponse(
          profile: profile,
          providerKind: adapter.kind,
          prompt: prompt,
          response: response,
          createdAt: requestStartedAt,
          completedAt: DateTime.now().toUtc(),
        ),
      );
      return response;
    } on Object catch (error) {
      if (requestSerial == _activeRequestSerial) {
        _restorePreservedActionableAgentState();
        _lastError = sanitizeAgentError(error.toString());
        _lastProviderFailure = error is AgentProviderTransportException
            ? error
            : null;
        await _appendAgentCodingSessionHistory(
          AgentCodingSessionHistoryRecord.failure(
            requestId: requestId,
            profile: profile,
            providerKind: adapter.kind,
            prompt: prompt,
            errorMessage: _lastError!,
            createdAt: requestStartedAt,
            completedAt: DateTime.now().toUtc(),
          ),
        );
      }
      return null;
    } finally {
      if (requestSerial == _activeRequestSerial) {
        _activeProviderRequestId = null;
        _activeProviderPrompt = null;
        _activeProviderStartedAt = null;
        _sending = false;
        notifyListeners();
      }
    }
  }

  void _cancelActiveProviderRequest() {
    final requestId = _activeProviderRequestId;
    if (requestId == null) {
      return;
    }
    final prompt = _activeProviderPrompt;
    final startedAt = _activeProviderStartedAt;
    if (prompt != null && startedAt != null) {
      unawaited(
        _appendAgentCodingSessionHistory(
          AgentCodingSessionHistoryRecord.failure(
            requestId: requestId,
            profile: profile,
            providerKind: adapter.kind,
            prompt: prompt,
            errorMessage: 'Agent request cancelled.',
            createdAt: startedAt,
            completedAt: DateTime.now().toUtc(),
            outcome: AgentCodingSessionOutcome.cancelled,
          ),
        ),
      );
    }
    _activeProviderRequestId = null;
    _activeProviderPrompt = null;
    _activeProviderStartedAt = null;
    final cancellableAdapter = adapter is CancellableAgentProviderAdapter
        ? adapter as CancellableAgentProviderAdapter
        : null;
    cancellableAdapter?.cancelRequest(requestId);
  }

  Future<AgentProviderResponseEnvelope> _sendProviderRequest(
    AgentProviderRequest request,
  ) {
    final streamingAdapter = adapter is StreamingAgentProviderAdapter
        ? adapter as StreamingAgentProviderAdapter
        : null;
    if (streamingAdapter == null) {
      return adapter.send(request);
    }
    const binding = AgentProviderStreamRuntimeOutputBinding();
    final events = streamingAdapter.stream(request).map((event) {
      _runtimeOutputBuffer?.addEvent(binding.eventFor(event));
      return event;
    });
    return const AgentProviderStreamingResponseCollector().collect(
      requestId: request.requestId,
      events: events,
    );
  }

  Future<void> _appendAgentCodingSessionHistory(
    AgentCodingSessionHistoryRecord record,
  ) async {
    _runtimeOutputBuffer?.addEvent(_agentRuntimeOutputEvent(record));
    final store = sessionHistoryStore;
    if (store == null) {
      return;
    }
    try {
      _sessionHistorySnapshot = await store.appendRecord(
        workspaceId: sessionHistoryWorkspaceId,
        record: record,
        maxEntries: sessionHistoryMaxEntries,
      );
    } on Object catch (error) {
      _publishAgentRuntimeDiagnostic(
        operation: 'agent.history.persist',
        message:
            'Agent history persistence failed: ${sanitizeAgentError(error.toString())}',
      );
    }
  }

  void _publishAgentRuntimeDiagnostic({
    required String operation,
    required String message,
  }) {
    _runtimeOutputBuffer?.addEvent(
      RuntimeOutputEvent(
        channelId: 'agent.activity',
        label: 'Agent Activity',
        kind: RuntimeOutputChannelKind.agent,
        message: message,
        timestamp: DateTime.now().toUtc(),
        metadata: <String, Object?>{
          'operation': operation,
          'outcome': 'failed',
        },
      ),
    );
  }

  RuntimeOutputEvent _agentRuntimeOutputEvent(
    AgentCodingSessionHistoryRecord record,
  ) {
    final summary = switch (record.outcome) {
      AgentCodingSessionOutcome.succeeded =>
        record.responseTextSample.trim().isEmpty
            ? 'Agent completed ${record.contentPartCount} content part(s).'
            : record.responseTextSample.trim(),
      AgentCodingSessionOutcome.failed =>
        record.errorMessage ?? 'Agent request failed.',
      AgentCodingSessionOutcome.cancelled => 'Agent request cancelled.',
    };
    return RuntimeOutputEvent(
      channelId: 'agent.activity',
      label: 'Agent Activity',
      kind: RuntimeOutputChannelKind.agent,
      message: summary,
      timestamp: record.completedAt,
      metadata: <String, Object?>{
        'requestId': record.requestId,
        'profileId': record.profileId,
        'providerKind': record.providerKind,
        'outcome': record.outcome.wireValue,
        'contentPartCount': record.contentPartCount,
        'patchCount': record.patchCount,
        'ideCommandCount': record.ideCommandCount,
        'planCount': record.planCount,
        'diagnosticSummaryCount': record.diagnosticSummaryCount,
      },
    );
  }

  void clearPendingPatch() {
    if (_pendingPatch == null) {
      return;
    }
    _patchApplicationSerial += 1;
    _applyingPatch = false;
    _pendingPatch = null;
    _lastPatchApplicationResult = null;
    _lastPatchApplicationContext = null;
    _clearPreservedAgentState();
    notifyListeners();
  }

  void clearConversation() {
    if (_conversationTurns.isEmpty &&
        _lastResponse == null &&
        _pendingPatch == null &&
        _lastPatchApplicationResult == null &&
        _lastPatchApplicationContext == null &&
        _lastIdeCommandResultContext == null &&
        _recentIdeCommandResultContexts.isEmpty &&
        _recentPatchApplicationContexts.isEmpty &&
        _recentPatchProposalContexts.isEmpty &&
        _recentIdeCommandSuggestionContexts.isEmpty &&
        _lastError == null &&
        _lastProviderFailure == null) {
      return;
    }
    if (_applyingPatch) {
      _patchApplicationSerial += 1;
      _applyingPatch = false;
    }
    _applyingIdeCommand = false;
    _conversationTurns.clear();
    _lastResponse = null;
    _pendingPatch = null;
    _lastPatchApplicationResult = null;
    _lastPatchApplicationContext = null;
    _lastIdeCommandResultContext = null;
    _clearPreservedAgentState();
    _recentIdeCommandResultContexts.clear();
    _completedIdeCommandSuggestionKeys.clear();
    _recentPatchApplicationContexts.clear();
    _recentPatchProposalContexts.clear();
    _recentIdeCommandSuggestionContexts.clear();
    _lastError = null;
    _lastProviderFailure = null;
    notifyListeners();
  }

  AgentCodePatchApplicationResult? applyPendingPatch(
    AgentCodePatchApplier applier,
  ) {
    final patch = _pendingPatch;
    if (patch == null) {
      return null;
    }
    if (_applyingPatch) {
      final result = const AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch application is already in progress.',
      );
      _recordPatchApplicationResult(patch, result);
      notifyListeners();
      return result;
    }

    final applicationSerial = _patchApplicationSerial + 1;
    _patchApplicationSerial = applicationSerial;
    _applyingPatch = true;
    notifyListeners();
    late final AgentCodePatchApplicationResult result;
    try {
      result = applier.apply(patch);
    } finally {
      if (applicationSerial == _patchApplicationSerial) {
        _applyingPatch = false;
      }
    }
    if (applicationSerial != _patchApplicationSerial) {
      notifyListeners();
      return null;
    }
    _recordPatchApplicationResult(patch, result);
    if (result.applied) {
      _pendingPatch = null;
    }
    notifyListeners();
    return result;
  }

  Future<AgentCodePatchApplicationResult?> applyPendingWorkspacePatch(
    AgentWorkspaceCodePatchApplier applier,
  ) async {
    final patch = _pendingPatch;
    if (patch == null) {
      return null;
    }
    if (_applyingPatch) {
      final result = const AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch application is already in progress.',
      );
      _recordPatchApplicationResult(patch, result);
      notifyListeners();
      return result;
    }

    final applicationSerial = _patchApplicationSerial + 1;
    _patchApplicationSerial = applicationSerial;
    _applyingPatch = true;
    notifyListeners();
    try {
      final result = await applier.apply(patch);
      if (applicationSerial != _patchApplicationSerial) {
        return null;
      }
      _recordPatchApplicationResult(patch, result);
      if (result.applied) {
        _pendingPatch = null;
      }
      return result;
    } finally {
      if (applicationSerial == _patchApplicationSerial) {
        _applyingPatch = false;
        notifyListeners();
      }
    }
  }

  void recordPatchApplicationError(Object error) {
    final result = AgentCodePatchApplicationResult(
      applied: false,
      message: sanitizeAgentError(error.toString()),
    );
    final patch = _pendingPatch;
    if (patch == null) {
      _lastPatchApplicationResult = result;
    } else {
      _recordPatchApplicationResult(patch, result);
    }
    notifyListeners();
  }

  bool beginIdeCommandApplication() {
    if (_sending || _applyingPatch || _applyingIdeCommand) {
      return false;
    }
    _applyingIdeCommand = true;
    notifyListeners();
    return true;
  }

  void endIdeCommandApplication() {
    if (!_applyingIdeCommand) {
      return;
    }
    _applyingIdeCommand = false;
    notifyListeners();
  }

  void recordIdeCommandResult(AgentCommandResultContext result) {
    if (result.commandId.trim().isEmpty) {
      return;
    }
    _lastIdeCommandResultContext = result;
    _recordRecentIdeCommandResultContext(result);
    if (result.applied) {
      _completedIdeCommandSuggestionKeys.add(
        _ideCommandSuggestionKey(result.commandId, result.input),
      );
    }
    _appendConversationTurn(
      role: AgentConversationRole.user,
      text: _ideCommandResultConversationText(result),
    );
    notifyListeners();
  }

  void _recordPatchApplicationResult(
    AgentCodePatch patch,
    AgentCodePatchApplicationResult result,
  ) {
    final recordedAt = DateTime.now().toUtc();
    _lastPatchApplicationResult = result;
    _lastPatchApplicationContext = _patchApplicationContext(
      patch: patch,
      result: result,
      recordedAt: recordedAt,
    );
    _recordRecentPatchApplicationContext(_lastPatchApplicationContext!);
    _appendConversationTurn(
      role: AgentConversationRole.user,
      text: _patchApplicationConversationText(patch, result),
    );
  }

  void _preserveAgentStateForActiveRequest() {
    _hasPreservedAgentState = true;
    _preservedLastResponse = _lastResponse;
    _preservedPendingPatch = _pendingPatch;
    _preservedLastPatchApplicationResult = _lastPatchApplicationResult;
  }

  void _restorePreservedAgentState() {
    if (!_hasPreservedAgentState) {
      return;
    }
    _lastResponse = _preservedLastResponse;
    _pendingPatch = _preservedPendingPatch;
    _lastPatchApplicationResult = _preservedLastPatchApplicationResult;
    _clearPreservedAgentState();
  }

  void _restorePreservedActionableAgentState() {
    if (!_hasPreservedAgentState) {
      return;
    }
    final preservedResponse = _preservedLastResponse;
    final preservedPendingPatch = _preservedPendingPatch;
    final shouldRestoreResponse =
        preservedPendingPatch != null ||
        _hasActionableResponsePart(preservedResponse);
    _lastResponse = shouldRestoreResponse ? preservedResponse : null;
    _pendingPatch = preservedPendingPatch;
    _lastPatchApplicationResult = _preservedLastPatchApplicationResult;
    _clearPreservedAgentState();
  }

  void _clearPreservedAgentState() {
    _hasPreservedAgentState = false;
    _preservedLastResponse = null;
    _preservedPendingPatch = null;
    _preservedLastPatchApplicationResult = null;
  }

  bool _hasActionableResponsePart(AgentProviderResponseEnvelope? response) {
    if (response == null) {
      return false;
    }
    return response.contentParts.any(
      (part) =>
          part.ideCommand != null ||
          part.plan != null ||
          part.diagnosticSummary != null,
    );
  }

  AgentSessionContext _contextForProviderRequest() {
    return contextProvider().withAgentCodingState(
      pendingPatch: _pendingPatch == null
          ? null
          : _pendingPatchContext(_pendingPatch!),
      recentPatchProposals: _recentPatchProposalContexts,
      lastCommandResult: _lastIdeCommandResultContext,
      recentCommandResults: _recentIdeCommandResultContexts,
      pendingIdeCommands: _pendingIdeCommandContexts(_lastResponse).where(
        (command) => !_completedIdeCommandSuggestionKeys.contains(
          _ideCommandSuggestionKey(command.commandId, command.input),
        ),
      ),
      recentIdeCommandSuggestions: _recentIdeCommandSuggestionContexts,
      lastProviderFailure: _lastProviderFailure == null
          ? null
          : _providerFailureContext(_lastProviderFailure!),
      providerSelectionPlan: _providerSelectionPlan,
      providerExecutionResolution: _providerExecutionResolution,
      lastPatchApplication: _lastPatchApplicationContext,
      recentPatchApplications: _recentPatchApplicationContexts,
      recentCodingPlans: _recentCodingPlanContexts,
      recentDiagnosticSummaries: _recentDiagnosticSummaryContexts,
    );
  }

  void _recordRecentIdeCommandResultContext(AgentCommandResultContext result) {
    _recentIdeCommandResultContexts.insert(0, result);
    if (_recentIdeCommandResultContexts.length >
        _maxAgentCommandResultContextHistory) {
      _recentIdeCommandResultContexts.removeRange(
        _maxAgentCommandResultContextHistory,
        _recentIdeCommandResultContexts.length,
      );
    }
  }

  void _recordRecentPatchApplicationContext(
    AgentPatchApplicationContext context,
  ) {
    _recentPatchApplicationContexts.insert(0, context);
    if (_recentPatchApplicationContexts.length >
        _maxAgentPatchApplicationContextHistory) {
      _recentPatchApplicationContexts.removeRange(
        _maxAgentPatchApplicationContextHistory,
        _recentPatchApplicationContexts.length,
      );
    }
  }

  void _recordRecentPatchProposalContext(AgentCodePatch? patch) {
    if (patch == null) {
      return;
    }
    _recentPatchProposalContexts.insert(0, _pendingPatchContext(patch));
    if (_recentPatchProposalContexts.length >
        _maxAgentRecentPatchProposalContexts) {
      _recentPatchProposalContexts.removeRange(
        _maxAgentRecentPatchProposalContexts,
        _recentPatchProposalContexts.length,
      );
    }
  }

  void _recordRecentIdeCommandSuggestionContexts(
    AgentProviderResponseEnvelope response,
  ) {
    final suggestions = _pendingIdeCommandContexts(response);
    if (suggestions.isEmpty) {
      return;
    }
    _recentIdeCommandSuggestionContexts.insertAll(0, suggestions);
    if (_recentIdeCommandSuggestionContexts.length >
        _maxAgentRecentIdeCommandSuggestionContexts) {
      _recentIdeCommandSuggestionContexts.removeRange(
        _maxAgentRecentIdeCommandSuggestionContexts,
        _recentIdeCommandSuggestionContexts.length,
      );
    }
  }

  void _recordRecentCodingPlanContexts(AgentProviderResponseEnvelope response) {
    final plans = _codingPlanContexts(response);
    if (plans.isEmpty) {
      return;
    }
    _recentCodingPlanContexts.insertAll(0, plans);
    if (_recentCodingPlanContexts.length > _maxAgentRecentCodingPlanContexts) {
      _recentCodingPlanContexts.removeRange(
        _maxAgentRecentCodingPlanContexts,
        _recentCodingPlanContexts.length,
      );
    }
  }

  void _recordRecentDiagnosticSummaryContexts(
    AgentProviderResponseEnvelope response,
  ) {
    final summaries = _diagnosticSummaryContexts(response);
    if (summaries.isEmpty) {
      return;
    }
    _recentDiagnosticSummaryContexts.insertAll(0, summaries);
    if (_recentDiagnosticSummaryContexts.length >
        _maxAgentRecentDiagnosticSummaryContexts) {
      _recentDiagnosticSummaryContexts.removeRange(
        _maxAgentRecentDiagnosticSummaryContexts,
        _recentDiagnosticSummaryContexts.length,
      );
    }
  }

  String _nextRequestId() {
    _requestSequence += 1;
    return 'agent-request-$_requestSequence';
  }

  String _nextTurnId() {
    return 'agent-turn-${_conversationTurns.length + 1}';
  }

  void _appendConversationTurn({
    required AgentConversationRole role,
    required String text,
    String? providerMessageId,
  }) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }
    _conversationTurns.add(
      AgentConversationTurn(
        turnId: _nextTurnId(),
        role: role,
        text: _truncateConversationTurnText(normalizedText),
        createdAt: DateTime.now().toUtc(),
        providerMessageId: providerMessageId,
      ),
    );
    _trimConversationWindow();
  }

  void _appendAssistantTurn(AgentProviderResponseEnvelope response) {
    final text = response.contentParts
        .map((part) => part.text)
        .where((partText) => partText.trim().isNotEmpty)
        .join('\n\n');
    _appendConversationTurn(
      role: AgentConversationRole.assistant,
      text: text,
      providerMessageId: response.providerMessageId,
    );
  }

  AgentCodePatch? _firstPatch(AgentProviderResponseEnvelope response) {
    for (final part in response.contentParts) {
      final patch = part.patch;
      if (patch != null) {
        return patch;
      }
    }
    return null;
  }

  List<AgentConversationTurn> _conversationWindow() {
    if (_conversationTurns.length <= maxConversationTurns) {
      return conversationTurns;
    }
    return List<AgentConversationTurn>.unmodifiable(
      _conversationTurns.sublist(
        _conversationTurns.length - maxConversationTurns,
      ),
    );
  }

  void _trimConversationWindow() {
    if (_conversationTurns.length <= maxConversationTurns) {
      return;
    }
    _conversationTurns.removeRange(
      0,
      _conversationTurns.length - maxConversationTurns,
    );
  }

  void _trimAttachments() {
    if (maxAttachments <= 0) {
      _attachments.clear();
      return;
    }
    if (_attachments.length <= maxAttachments) {
      return;
    }
    _attachments.removeRange(0, _attachments.length - maxAttachments);
  }

  String _truncateConversationTurnText(String text) {
    if (maxConversationTurnTextLength <= 0) {
      return '[truncated ${text.length} char(s)]';
    }
    if (text.length <= maxConversationTurnTextLength) {
      return text;
    }
    return '${text.substring(0, maxConversationTurnTextLength)}\n[truncated ${text.length - maxConversationTurnTextLength} char(s)]';
  }
}

String _ideCommandResultConversationText(AgentCommandResultContext result) {
  final lines = <String>[
    'IDE command result:',
    'commandId: ${result.commandId}',
    if (result.input != null && result.input!.trim().isNotEmpty)
      'input: ${result.input}',
    'applied: ${result.applied}',
    'message: ${result.message}',
    if (result.completedAt != null)
      'completedAt: ${result.completedAt!.toUtc().toIso8601String()}',
  ];
  final metadataKeys = result.metadata.keys
      .where((key) => key.trim().isNotEmpty)
      .toList(growable: false);
  if (metadataKeys.isNotEmpty) {
    lines.add('metadataKeys: ${metadataKeys.join(', ')}');
  }
  final metadataSummaryLines = _ideCommandMetadataConversationLines(
    result.metadata,
  );
  if (metadataSummaryLines.isNotEmpty) {
    lines.add('metadata:');
    lines.addAll(metadataSummaryLines.map((line) => '  $line'));
  }
  return lines.join('\n');
}

const List<String> _ideCommandConversationMetadataKeys = <String>[
  'agentContextSchemaVersion',
  'workspaceRoot',
  'requiredCommand',
  'completedRequiredCommandFor',
  'recoveryForCommandId',
  'settingsRoute',
  'settingsSection',
  'toolchainSelectionStatus',
  'toolchainId',
  'clangCppSelection',
  'cppStandard',
  'preferredBuildEngineHandoff',
  'cmakeExecutablePath',
  'ninjaExecutablePath',
];

List<String> _ideCommandMetadataConversationLines(
  Map<String, Object?> metadata,
) {
  if (metadata.isEmpty) {
    return const <String>[];
  }
  final lines = <String>[];
  for (final key in _ideCommandConversationMetadataKeys) {
    final value = metadata[key];
    final text = _conversationMetadataScalarText(value);
    if (text != null) {
      lines.add('$key: $text');
    }
  }
  final backendRouteSelection = metadata['backendRouteSelection'];
  if (backendRouteSelection is Map<String, Object?>) {
    final routeKind = _conversationMetadataScalarText(
      backendRouteSelection['routeKind'],
    );
    final allowed = _conversationMetadataScalarText(
      backendRouteSelection['allowed'],
    );
    final blockedReason = _conversationMetadataScalarText(
      backendRouteSelection['blockedReason'],
    );
    if (routeKind != null || allowed != null || blockedReason != null) {
      final fields = <String>[
        if (routeKind != null) 'routeKind=$routeKind',
        if (allowed != null) 'allowed=$allowed',
        if (blockedReason != null) 'blockedReason=$blockedReason',
      ];
      lines.add('backendRouteSelection: ${fields.join(', ')}');
    }
  }
  final sourceControlContext = metadata['sourceControlContext'];
  if (sourceControlContext is Map<String, Object?>) {
    final provider = _conversationMetadataScalarText(
      sourceControlContext['providerKind'],
    );
    final branch = _conversationMetadataScalarText(
      sourceControlContext['branchName'],
    );
    final changeCount = _conversationMetadataScalarText(
      sourceControlContext['changeCount'],
    );
    final stagedCount = _conversationMetadataListLength(
      sourceControlContext['stagedPaths'],
    );
    final unstagedCount = _conversationMetadataListLength(
      sourceControlContext['unstagedPaths'],
    );
    final conflictCount = _conversationMetadataListLength(
      sourceControlContext['conflictedPaths'],
    );
    lines.add(
      'sourceControlContext: provider=${provider ?? 'unknown'}, '
      'branch=${branch ?? 'unknown'}, changes=${changeCount ?? '0'}, '
      'staged=$stagedCount, unstaged=$unstagedCount, conflicts=$conflictCount',
    );
  }
  final languageServiceStatus = metadata['languageServiceStatus'];
  if (languageServiceStatus is Map<String, Object?>) {
    final severity = _conversationMetadataScalarText(
      languageServiceStatus['severity'],
    );
    final syntaxReady = _conversationMetadataScalarText(
      languageServiceStatus['syntaxValidationReady'],
    );
    final semanticReady = _conversationMetadataScalarText(
      languageServiceStatus['semanticFactsReady'],
    );
    lines.add(
      'languageServiceStatus: severity=${severity ?? 'unknown'}, '
      'syntaxReady=${syntaxReady ?? 'unknown'}, '
      'semanticReady=${semanticReady ?? 'unknown'}',
    );
  }
  final testing = metadata['testing'];
  if (testing is Map<String, Object?>) {
    final hasLastRun = _conversationMetadataScalarText(testing['hasLastRun']);
    final hasFailingTests = _conversationMetadataScalarText(
      testing['hasFailingTests'],
    );
    final rerunFailed = testing['rerunFailed'];
    final rerunFilter = rerunFailed is Map<String, Object?>
        ? _conversationMetadataScalarText(rerunFailed['filter'])
        : null;
    lines.add(
      'testing: hasLastRun=${hasLastRun ?? 'false'}, '
      'hasFailingTests=${hasFailingTests ?? 'false'}'
      '${rerunFilter == null ? '' : ', rerunFilter=$rerunFilter'}',
    );
  }
  return lines;
}

int _conversationMetadataListLength(Object? value) {
  return value is List ? value.length : 0;
}

String? _conversationMetadataScalarText(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return null;
}

String _patchApplicationConversationText(
  AgentCodePatch patch,
  AgentCodePatchApplicationResult result,
) {
  final lines = <String>[
    'IDE patch application result:',
    'patchId: ${patch.patchId}',
    if (patch.summary.trim().isNotEmpty) 'summary: ${patch.summary}',
    if (patch.baseRevision != null) 'patchBaseRevision: ${patch.baseRevision}',
    if (patch.edits.isNotEmpty)
      'patchDocumentIds: ${_patchDocumentIdsText(patch)}',
    'patchEditCount: ${patch.edits.length}',
    if (patch.edits.isNotEmpty)
      'patchOperationCounts: ${_patchEditOperationCountsText(patch)}',
    'applied: ${result.applied}',
    'pendingPatchRetained: ${!result.applied}',
    'message: ${result.message}',
    'appliedEditCount: ${result.appliedEditCount}',
    if (result.appliedOperationCounts.isNotEmpty)
      'operationCounts: ${_patchOperationCountsText(result.appliedOperationCounts)}',
    if (result.appliedDocumentIds.isNotEmpty)
      'changedDocuments: ${result.appliedDocumentIds.join(', ')}',
    if (result.createdDocumentIds.isNotEmpty)
      'createdDocuments: ${result.createdDocumentIds.join(', ')}',
    if (result.deletedDocumentIds.isNotEmpty)
      'deletedDocuments: ${result.deletedDocumentIds.join(', ')}',
    if (result.skippedNoOpDocumentIds.isNotEmpty)
      'skippedNoOpDocuments: ${result.skippedNoOpDocumentIds.join(', ')}',
  ];
  return lines.join('\n');
}

String _patchEditOperationCountsText(AgentCodePatch patch) {
  return _patchOperationCountsText(_patchEditOperationCounts(patch));
}

String _patchDocumentIdsText(AgentCodePatch patch) {
  return _patchDocumentIds(patch).join(', ');
}

AgentProviderFailureContext _providerFailureContext(
  AgentProviderTransportException failure,
) {
  return AgentProviderFailureContext(
    kind: failure.kind.name,
    message: failure.message,
    operation: failure.operation,
    statusCode: failure.statusCode,
    target: failure.target,
    recoveryHint: failure.recoveryHint,
  );
}

List<AgentPendingIdeCommandContext> _pendingIdeCommandContexts(
  AgentProviderResponseEnvelope? response,
) {
  if (response == null) {
    return const <AgentPendingIdeCommandContext>[];
  }
  final commands = <AgentPendingIdeCommandContext>[];
  for (final part in response.contentParts) {
    final command = part.ideCommand;
    if (command == null || command.commandId.trim().isEmpty) {
      continue;
    }
    commands.add(
      AgentPendingIdeCommandContext(
        commandId: command.commandId,
        input: command.input,
        reason: command.reason,
        prerequisiteForCommandId: command.prerequisiteForCommandId,
        text: part.text,
      ),
    );
    if (commands.length >= _maxAgentPendingIdeCommandContexts) {
      break;
    }
  }
  return List<AgentPendingIdeCommandContext>.unmodifiable(commands);
}

String _ideCommandSuggestionKey(String commandId, String? input) {
  return '${commandId.trim()}\u0000${(input ?? '').trim()}';
}

List<AgentCodingPlanContext> _codingPlanContexts(
  AgentProviderResponseEnvelope response,
) {
  final plans = <AgentCodingPlanContext>[];
  for (final part in response.contentParts) {
    final plan = part.plan;
    if (plan == null) {
      continue;
    }
    plans.add(
      AgentCodingPlanContext(
        summary: plan.summary,
        steps: plan.steps,
        acceptanceCriteria: plan.acceptanceCriteria,
        risks: plan.risks,
        text: part.text,
      ),
    );
    if (plans.length >= _maxAgentRecentCodingPlanContexts) {
      break;
    }
  }
  return List<AgentCodingPlanContext>.unmodifiable(plans);
}

List<AgentDiagnosticSummaryContext> _diagnosticSummaryContexts(
  AgentProviderResponseEnvelope response,
) {
  final summaries = <AgentDiagnosticSummaryContext>[];
  for (final part in response.contentParts) {
    final diagnosticSummary = part.diagnosticSummary;
    if (diagnosticSummary == null) {
      continue;
    }
    summaries.add(
      AgentDiagnosticSummaryContext(
        title: diagnosticSummary.title,
        summary: diagnosticSummary.summary,
        severity: diagnosticSummary.severity,
        diagnosticCount: diagnosticSummary.diagnosticCount,
        affectedDocuments: diagnosticSummary.affectedDocuments,
        suggestedCommandIds: diagnosticSummary.suggestedCommandIds,
        text: part.text,
      ),
    );
    if (summaries.length >= _maxAgentRecentDiagnosticSummaryContexts) {
      break;
    }
  }
  return List<AgentDiagnosticSummaryContext>.unmodifiable(summaries);
}

AgentPendingPatchContext _pendingPatchContext(AgentCodePatch patch) {
  final edits = patch.edits
      .take(_maxAgentPendingPatchContextEdits)
      .map(_pendingPatchEditContext)
      .toList(growable: false);
  return AgentPendingPatchContext(
    patchId: patch.patchId,
    summary: patch.summary,
    baseRevision: patch.baseRevision,
    documentIds: _patchDocumentIds(patch),
    editCount: patch.edits.length,
    operationCounts: _patchEditOperationCounts(patch),
    edits: edits,
    editsTruncated: patch.edits.length > edits.length,
  );
}

AgentPendingPatchEditContext _pendingPatchEditContext(AgentCodePatchEdit edit) {
  final replacementTextSample = _pendingPatchReplacementTextSample(
    edit.replacementText,
  );
  return AgentPendingPatchEditContext(
    documentId: edit.documentId,
    operation: edit.operation.wireValue,
    baseRevision: edit.baseRevision,
    start: edit.start,
    end: edit.end,
    replacementTextSample: replacementTextSample,
    replacementTextLength: edit.replacementText.length,
    replacementTextTruncated:
        edit.replacementText.length >
        _maxAgentPendingPatchReplacementTextSampleLength,
  );
}

String _pendingPatchReplacementTextSample(String replacementText) {
  if (replacementText.length <=
      _maxAgentPendingPatchReplacementTextSampleLength) {
    return replacementText;
  }
  return replacementText.substring(
    0,
    _maxAgentPendingPatchReplacementTextSampleLength,
  );
}

AgentPatchApplicationContext _patchApplicationContext({
  required AgentCodePatch patch,
  required AgentCodePatchApplicationResult result,
  required DateTime recordedAt,
}) {
  return AgentPatchApplicationContext(
    patchId: patch.patchId,
    summary: patch.summary,
    baseRevision: patch.baseRevision,
    documentIds: _patchDocumentIds(patch),
    editCount: patch.edits.length,
    operationCounts: _patchEditOperationCounts(patch),
    applied: result.applied,
    pendingPatchRetained: !result.applied,
    message: result.message,
    appliedEditCount: result.appliedEditCount,
    appliedOperationCounts: Map<String, int>.unmodifiable(
      result.appliedOperationCounts,
    ),
    changedDocumentIds: List<String>.unmodifiable(result.appliedDocumentIds),
    createdDocumentIds: List<String>.unmodifiable(result.createdDocumentIds),
    deletedDocumentIds: List<String>.unmodifiable(result.deletedDocumentIds),
    skippedNoOpDocumentIds: List<String>.unmodifiable(
      result.skippedNoOpDocumentIds,
    ),
    recordedAt: recordedAt,
  );
}

List<String> _patchDocumentIds(AgentCodePatch patch) {
  return patch.edits
      .map((edit) => edit.documentId)
      .where((documentId) => documentId.trim().isNotEmpty)
      .toSet()
      .toList(growable: false);
}

Map<String, int> _patchEditOperationCounts(AgentCodePatch patch) {
  final operationCounts = <String, int>{};
  for (final edit in patch.edits) {
    final operation = edit.operation.wireValue;
    operationCounts[operation] = (operationCounts[operation] ?? 0) + 1;
  }
  return Map<String, int>.unmodifiable(operationCounts);
}

String _patchOperationCountsText(Map<String, int> operationCounts) {
  return operationCounts.entries
      .map((entry) => '${entry.key} ${entry.value}')
      .join(', ');
}

String sanitizeAgentError(String message) {
  var sanitized = message.replaceAll(
    RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
    'Bearer [redacted]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'((?:api[_-]?key|access[_-]?token|token)=)[^&\s,;]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}[redacted]',
  );
  return sanitized;
}
