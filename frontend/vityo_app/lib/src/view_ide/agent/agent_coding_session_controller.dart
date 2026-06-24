import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_coding_session_history_store.dart';
import 'agent_coding_dispatch_plan.dart';
import 'agent_coding_loop_guard.dart';
import 'agent_coding_loop_plan.dart';
import 'agent_code_patch_applier.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_route_executor.dart';
import 'agent_provider_streaming_runtime.dart';
import 'agent_registry.dart';
import 'agent_session_context.dart';
import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_call_execution_journal.dart';
import 'agent_tool_call_execution_plan.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_call_result_context.dart';
import 'agent_tool_session_processor.dart';
import 'agent_tool_session_transcript.dart';
import 'agent_tool_permission.dart';
import 'agent_tool_permission_policy_store.dart';
import 'agent_tool_registry.dart';
import 'agent_workspace_snapshot.dart';
import 'agent_workspace_snapshot_store.dart';
import 'agent_workspace_edit_adapter.dart';
import '../runtime/runtime.dart';

typedef AgentSessionContextProvider = AgentSessionContext Function();

enum AgentCodingSessionRecoveryDispatchStatus { blocked, dispatched, failed }

extension AgentCodingSessionRecoveryDispatchStatusX
    on AgentCodingSessionRecoveryDispatchStatus {
  String get wireValue => switch (this) {
    AgentCodingSessionRecoveryDispatchStatus.blocked => 'blocked',
    AgentCodingSessionRecoveryDispatchStatus.dispatched => 'dispatched',
    AgentCodingSessionRecoveryDispatchStatus.failed => 'failed',
  };
}

class AgentCodingSessionRecoveryDispatchResult {
  const AgentCodingSessionRecoveryDispatchResult({
    required this.status,
    required this.message,
    this.draft,
    this.responseRequestId,
  });

  final AgentCodingSessionRecoveryDispatchStatus status;
  final String message;
  final AgentCodingSessionRecoveryRequestDraft? draft;
  final String? responseRequestId;

  bool get dispatched =>
      status == AgentCodingSessionRecoveryDispatchStatus.dispatched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'message': message,
      'dispatched': dispatched,
      if (draft != null) 'draft': draft!.toJson(),
      if (responseRequestId != null) 'responseRequestId': responseRequestId,
    };
  }
}

const int _maxAgentPatchApplicationContextHistory = 12;
const int _maxAgentRecentPatchProposalContexts = 6;
const int _maxAgentPendingPatchContextEdits = 20;
const int _maxAgentPendingPatchReplacementTextSampleLength = 2000;
const int _maxAgentCommandResultContextHistory = 12;
const int _maxAgentToolCallResultContextHistory = 12;
const int _maxAgentPendingIdeCommandContexts = 10;
const int _maxAgentRecentIdeCommandSuggestionContexts = 12;
const int _maxAgentRecentCodingPlanContexts = 8;
const int _maxAgentRecentDiagnosticSummaryContexts = 8;
const int _maxAgentConversationCompactionSummaryLength = 4000;
const int _maxAgentConversationCompactionTurnSampleLength = 400;

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
    this.toolPermissionPolicyStore,
    String? toolPermissionPolicyWorkspaceId,
    this.workspaceSnapshotStore,
    String? workspaceSnapshotWorkspaceId,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    AgentRegistry? agentRegistry,
    String? activeAgentId,
    AgentToolRegistry? toolRegistry,
    AgentProviderSelectionPlan? providerSelectionPlan,
    AgentProviderExecutionResolution? providerExecutionResolution,
  }) : _runtimeOutputBuffer = runtimeOutputBuffer,
       _agentRegistry = agentRegistry ?? AgentRegistry(),
       _activeAgentId = activeAgentId,
       _toolRegistry = toolRegistry ?? AgentToolRegistry(),
       _providerSelectionPlan = providerSelectionPlan,
       _providerExecutionResolution = providerExecutionResolution,
       _toolPermissionPolicyWorkspaceId =
           toolPermissionPolicyWorkspaceId ?? sessionHistoryWorkspaceId,
       _workspaceSnapshotWorkspaceId =
           workspaceSnapshotWorkspaceId ?? sessionHistoryWorkspaceId,
       _mountedProviderProfileKey = profile.profileId;

  AgentPromptProfile profile;
  AgentProviderAdapter adapter;
  AgentSessionContextProvider contextProvider;
  final int maxConversationTurns;
  final int maxConversationTurnTextLength;
  final int maxAttachments;
  final AgentCodingSessionHistoryStore? sessionHistoryStore;
  final String sessionHistoryWorkspaceId;
  final int sessionHistoryMaxEntries;
  final AgentToolPermissionPolicyStore? toolPermissionPolicyStore;
  final String _toolPermissionPolicyWorkspaceId;
  final AgentWorkspaceSnapshotStore? workspaceSnapshotStore;
  final String _workspaceSnapshotWorkspaceId;
  final RuntimeOutputLiveBuffer? _runtimeOutputBuffer;
  final AgentRegistry _agentRegistry;
  String? _activeAgentId;
  final AgentToolRegistry _toolRegistry;

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
  final List<AgentToolCallResultContext> _recentToolCallResultContexts =
      <AgentToolCallResultContext>[];
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
  String? _mountedProviderProfileKey;
  AgentProviderSelectionPlan? _providerSelectionPlan;
  AgentProviderExecutionResolution? _providerExecutionResolution;
  String? _lastError;
  AgentProviderTransportException? _lastProviderFailure;
  String? _activeProviderRequestId;
  String? _activeProviderPrompt;
  DateTime? _activeProviderStartedAt;
  Map<String, Object?>? _pendingToolResultContinuationMetadata;
  AgentCodingSessionHistory? _sessionHistorySnapshot;
  AgentWorkspaceSnapshotCaptureResult? _lastWorkspaceSnapshotCaptureResult;
  AgentWorkspaceChangeSnapshot? _lastWorkspaceSnapshot;
  AgentWorkspaceRevertPlan? _lastWorkspaceRevertPlan;
  final AgentToolSessionProcessor _toolSessionProcessor =
      const AgentToolSessionProcessor();
  AgentToolCallTimeline _toolCallTimeline = AgentToolCallTimeline.empty();
  AgentToolCallExecutionJournal _toolCallExecutionJournal =
      AgentToolCallExecutionJournal.fromTimeline(
        timeline: AgentToolCallTimeline.empty(),
      );
  final Map<String, AgentToolCallReviewDecision> _toolCallReviewDecisions =
      <String, AgentToolCallReviewDecision>{};
  final List<AgentToolPermissionRule> _projectToolPermissionRules =
      <AgentToolPermissionRule>[];
  final List<AgentToolPermissionRule> _sessionToolPermissionRules =
      <AgentToolPermissionRule>[];
  final Map<String, int> _agentRuntimeStepCounts = <String, int>{};
  final List<AgentRequestAttachment> _attachments = <AgentRequestAttachment>[];
  final List<AgentConversationTurn> _conversationTurns =
      <AgentConversationTurn>[];
  int _omittedConversationTurnCount = 0;
  int _conversationCompactionSummaryTurnCount = 0;
  String _conversationCompactionSummary = '';
  DateTime? _conversationCompactionSummaryUpdatedAt;

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
  AgentWorkspaceSnapshotCaptureResult? get lastWorkspaceSnapshotCaptureResult =>
      _lastWorkspaceSnapshotCaptureResult;
  AgentWorkspaceChangeSnapshot? get lastWorkspaceSnapshot =>
      _lastWorkspaceSnapshot;
  AgentWorkspaceRevertPlan? get lastWorkspaceRevertPlan =>
      _lastWorkspaceRevertPlan;
  AgentCommandResultContext? get lastIdeCommandResultContext =>
      _lastIdeCommandResultContext;
  List<AgentPatchApplicationContext> get recentPatchApplicationContexts =>
      List<AgentPatchApplicationContext>.unmodifiable(
        _recentPatchApplicationContexts,
      );
  String? get providerMountMessage => _providerMountMessage;
  String? get mountedProviderProfileKey => _mountedProviderProfileKey;
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
  AgentCodingSessionRecoveryPlan get sessionRecoveryPlan =>
      sessionHistorySnapshot.toRecoveryPlan();
  AgentCodingSessionRecoveryRequestDraft? recoveryRequestDraftFor(
    AgentCodingSessionRecoveryAction action, {
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
  }) {
    return sessionHistorySnapshot.toRecoveryRequestDraft(
      action,
      targetProviderProfileKey:
          targetProviderProfileKey ?? targetProviderProfileId,
    );
  }

  String? get lastError => _lastError;
  AgentProviderTransportException? get lastProviderFailure =>
      _lastProviderFailure;
  List<AgentRequestAttachment> get attachments =>
      List<AgentRequestAttachment>.unmodifiable(_attachments);
  List<AgentConversationTurn> get conversationTurns =>
      List<AgentConversationTurn>.unmodifiable(_conversationTurns);
  AgentConversationCompactionContext get conversationCompaction =>
      _conversationCompactionContext(
        sentTurnCount: _conversationWindow().length,
      );
  AgentToolCallTimeline get toolCallTimeline => _toolCallTimeline;
  AgentToolCallExecutionJournal get toolCallExecutionJournal =>
      _toolCallExecutionJournal;
  AgentToolCallReplayPlan get toolCallReplayPlan =>
      AgentToolCallReplayPlan.fromJournal(_toolCallExecutionJournal);
  AgentToolSessionTranscript get toolSessionTranscript =>
      _toolSessionProcessor.buildTranscript(
        timeline: _toolCallTimeline,
        executionPlan: toolCallExecutionPlan,
        resultContexts: _recentToolCallResultContexts,
      );
  List<AgentToolCallResultContext> get recentToolCallResultContexts =>
      List<AgentToolCallResultContext>.unmodifiable(
        _recentToolCallResultContexts,
      );
  List<AgentToolCallReviewDecision> get toolCallReviewDecisions =>
      List<AgentToolCallReviewDecision>.unmodifiable(
        _toolCallReviewDecisions.values,
      );
  List<AgentToolPermissionRule> get projectToolPermissionRules =>
      List<AgentToolPermissionRule>.unmodifiable(_projectToolPermissionRules);
  List<AgentToolPermissionRule> get sessionToolPermissionRules =>
      List<AgentToolPermissionRule>.unmodifiable(_sessionToolPermissionRules);
  AgentRegistrySnapshot get agentRegistrySnapshot {
    return _agentRegistry.snapshot(activeAgentId: _activeAgentId);
  }

  String get activeAgentId => agentRegistrySnapshot.activeAgentId;

  bool selectAgentRuntime(String agentId) {
    final agent = _agentRegistry.resolve(agentId.trim());
    if (agent == null || agent.hidden) {
      return false;
    }
    if (_activeAgentId == agent.agentId) {
      return true;
    }
    _activeAgentId = agent.agentId;
    notifyListeners();
    return true;
  }

  AgentToolCallExecutionPlan get toolCallExecutionPlan {
    final dispatchPlan = previewDispatchPlan();
    return AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: dispatchPlan.toolSelection,
      permissionPlan: dispatchPlan.toolPermissionPlan,
      timeline: _toolCallTimeline,
      reviewDecisions: _toolCallReviewDecisions.values,
    );
  }

  bool get canSend => codingExecutionReadiness.canDispatchProviderRequest;
  AgentCodingExecutionReadiness get codingExecutionReadiness =>
      _contextForProviderRequest().codingReadiness
          .withControllerState(
            hasDraftPrompt: _draftPrompt.trim().isNotEmpty,
            sending: _sending,
            applyingPatch: _applyingPatch,
            applyingIdeCommand: _applyingIdeCommand,
          )
          .withLoopGuard(_currentCodingLoopGuard());
  AgentCodingChangeReviewGate get codingChangeReviewGate =>
      AgentCodingChangeReviewGate.fromControllerState(
        hasPendingPatch: _pendingPatch != null,
        hasWorkspaceEditPreview: pendingWorkspaceEditPlanConversion != null,
        applyingPatch: _applyingPatch,
        applyingIdeCommand: _applyingIdeCommand,
        executionReadiness: codingExecutionReadiness,
      );
  AgentCodingAutonomyPolicy get codingAutonomyPolicy =>
      AgentCodingAutonomyPolicy.fromGates(
        readiness: codingExecutionReadiness,
        changeReviewGate: codingChangeReviewGate,
      );
  AgentCodingValidationPlan get codingValidationPlan =>
      AgentCodingValidationPlan.fromAgentState(
        autonomyPolicy: codingAutonomyPolicy,
        changeReviewGate: codingChangeReviewGate,
        lastPatchApplication: _lastPatchApplicationContext,
      );
  AgentCodingValidationResult get codingValidationResult =>
      AgentCodingValidationResult.fromPlan(
        plan: codingValidationPlan,
        recentCommandResults: _recentIdeCommandResultContexts,
      );
  AgentCodingValidationPipeline get codingValidationPipeline =>
      AgentCodingValidationPipeline.fromPlan(
        plan: codingValidationPlan,
        result: codingValidationResult,
      );
  AgentCodingLoopGuard get codingLoopGuard => _currentCodingLoopGuard();
  AgentWorkspaceCheckpointContext? get workspaceCheckpointContext =>
      _workspaceCheckpointContext();
  AgentToolSelection get toolCatalog => _currentToolSelection();
  AgentToolPermissionPlan get toolPermissionPlan =>
      _currentToolPermissionPlan();

  AgentCodingLoopPlan get codingLoopPlan {
    return AgentCodingLoopPlan.fromState(
      dispatchPlan: previewDispatchPlan(),
      changeReviewGate: codingChangeReviewGate,
      validationPlan: codingValidationPlan,
      validationPipeline: codingValidationPipeline,
      hasProviderFailure: _lastProviderFailure != null,
      loopGuard: _currentCodingLoopGuard(),
    );
  }

  AgentCodingDispatchPlan previewDispatchPlan() {
    final prompt = _draftPrompt.trim();
    final requestContext = _contextForProviderRequest();
    final readiness = requestContext.codingReadiness
        .withControllerState(
          hasDraftPrompt: prompt.isNotEmpty,
          sending: _sending,
          applyingPatch: _applyingPatch,
          applyingIdeCommand: _applyingIdeCommand,
        )
        .withLoopGuard(_currentCodingLoopGuard());
    return AgentCodingDispatchPlan.fromContext(
      profile: profile,
      adapter: adapter,
      context: requestContext,
      readiness: readiness,
      prompt: prompt,
      attachmentCount: _attachments.length,
      conversationTurnCount: _conversationWindow().length,
      toolRegistry: _toolRegistry,
      toolPermissionRules: _toolPermissionRules(),
      providerSelectionPlan: _providerSelectionPlan,
      providerExecutionResolution: _providerExecutionResolution,
    );
  }

  void mountProvider({
    required AgentPromptProfile profile,
    required AgentProviderAdapter adapter,
    String? message,
    String? profileKey,
    AgentProviderSelectionPlan? selectionPlan,
    AgentProviderExecutionResolution? executionResolution,
  }) {
    this.profile = profile;
    this.adapter = adapter;
    _mountedProviderProfileKey = profileKey ?? profile.profileId;
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
    _toolCallTimeline = AgentToolCallTimeline.empty();
    _toolCallReviewDecisions.clear();
    _attachments.clear();
    _conversationTurns.clear();
    _omittedConversationTurnCount = 0;
    _clearConversationCompactionSummary();
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

  bool restoreRecoveryDraft(
    AgentCodingSessionRecoveryAction action, {
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
  }) {
    final draft = recoveryRequestDraftFor(
      action,
      targetProviderProfileKey:
          targetProviderProfileKey ?? targetProviderProfileId,
    );
    if (draft == null || draft.prompt.trim().isEmpty) {
      return false;
    }
    updatePrompt(draft.prompt);
    return true;
  }

  bool restoreToolResultContinuationDraft({String? prompt}) {
    final plan = _toolSessionProcessor.buildContinuationPlan(
      resultContexts: _recentToolCallResultContexts,
      prompt: prompt,
    );
    if (!plan.ready) {
      return false;
    }
    updatePrompt(plan.prompt);
    return true;
  }

  Future<AgentProviderResponseEnvelope?> dispatchToolResultContinuation({
    String? prompt,
    bool confirmed = false,
  }) async {
    final plan = _toolSessionProcessor.buildContinuationPlan(
      resultContexts: _recentToolCallResultContexts,
      prompt: prompt,
    );
    if (!plan.ready) {
      _lastError =
          'Agent tool continuation blocked: no tool results are available.';
      notifyListeners();
      return null;
    }
    if (!confirmed) {
      _lastError =
          'Agent tool continuation blocked: explicit user confirmation is required.';
      notifyListeners();
      return null;
    }
    _pendingToolResultContinuationMetadata = plan.metadata;
    updatePrompt(plan.prompt);
    try {
      return await sendPrompt();
    } finally {
      _pendingToolResultContinuationMetadata = null;
    }
  }

  Future<AgentCodingSessionRecoveryDispatchResult> dispatchRecoveryRequestDraft(
    AgentCodingSessionRecoveryAction action, {
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
    bool confirmed = false,
  }) async {
    final normalizedTargetProviderProfileKey =
        (targetProviderProfileKey ?? targetProviderProfileId)?.trim();
    final draft = recoveryRequestDraftFor(
      action,
      targetProviderProfileKey: normalizedTargetProviderProfileKey,
    );
    if (draft == null) {
      return const AgentCodingSessionRecoveryDispatchResult(
        status: AgentCodingSessionRecoveryDispatchStatus.blocked,
        message: 'Agent recovery dispatch blocked: no recovery draft exists.',
      );
    }
    if (!confirmed) {
      return AgentCodingSessionRecoveryDispatchResult(
        status: AgentCodingSessionRecoveryDispatchStatus.blocked,
        message:
            'Agent recovery dispatch blocked: explicit user confirmation is required.',
        draft: draft,
      );
    }
    if (!draft.readyToDispatch) {
      return AgentCodingSessionRecoveryDispatchResult(
        status: AgentCodingSessionRecoveryDispatchStatus.blocked,
        message:
            'Agent recovery dispatch blocked: provider selection or prompt is missing.',
        draft: draft,
      );
    }
    if (action == AgentCodingSessionRecoveryAction.failoverProvider &&
        normalizedTargetProviderProfileKey != null &&
        normalizedTargetProviderProfileKey.isNotEmpty &&
        normalizedTargetProviderProfileKey != mountedProviderProfileKey &&
        normalizedTargetProviderProfileKey != profile.profileId) {
      return AgentCodingSessionRecoveryDispatchResult(
        status: AgentCodingSessionRecoveryDispatchStatus.blocked,
        message:
            'Agent provider failover requires mounting the target provider profile before dispatch.',
        draft: draft,
      );
    }
    updatePrompt(draft.prompt);
    final response = await sendPrompt();
    if (response == null) {
      return AgentCodingSessionRecoveryDispatchResult(
        status: AgentCodingSessionRecoveryDispatchStatus.failed,
        message: lastError ?? 'Agent recovery dispatch failed.',
        draft: draft,
      );
    }
    return AgentCodingSessionRecoveryDispatchResult(
      status: AgentCodingSessionRecoveryDispatchStatus.dispatched,
      message: 'Agent recovery request dispatched.',
      draft: draft,
      responseRequestId: response.requestId,
    );
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

  void recordToolCallEvent(AgentToolCallEvent event) {
    final next = _toolSessionProcessor.applyEvent(_toolCallTimeline, event);
    if (identical(next, _toolCallTimeline)) {
      return;
    }
    _toolCallTimeline = next;
    _refreshToolCallExecutionJournal();
    notifyListeners();
  }

  void recordToolCallEvents(Iterable<AgentToolCallEvent> events) {
    final next = _toolSessionProcessor.applyEvents(_toolCallTimeline, events);
    if (identical(next, _toolCallTimeline)) {
      return;
    }
    _toolCallTimeline = next;
    _refreshToolCallExecutionJournal();
    notifyListeners();
  }

  void clearToolCallTimeline() {
    if (_toolCallTimeline.status == AgentToolCallTimelineStatus.idle &&
        _toolCallReviewDecisions.isEmpty) {
      return;
    }
    _toolCallTimeline = AgentToolCallTimeline.empty();
    _refreshToolCallExecutionJournal();
    _toolCallReviewDecisions.clear();
    notifyListeners();
  }

  bool approveToolCallExecution(
    String callId, {
    String? reason,
    bool rememberForSession = false,
  }) {
    final call = _toolCallTimeline.callFor(callId);
    if (call == null || call.callId.trim().isEmpty) {
      return false;
    }
    final decisionReason = reason ?? 'User approved this agent tool call.';
    _toolCallReviewDecisions[call.callId] =
        AgentToolCallReviewDecision.approved(
          callId: call.callId,
          toolId: call.toolId,
          reason: decisionReason,
          decidedAt: DateTime.now().toUtc(),
        );
    if (rememberForSession) {
      _upsertSessionToolPermissionRule(
        toolId: call.toolId,
        action: AgentToolPermissionAction.allow,
        reason: decisionReason,
      );
    }
    notifyListeners();
    return true;
  }

  bool denyToolCallExecution(
    String callId, {
    String? reason,
    bool rememberForSession = false,
  }) {
    final call = _toolCallTimeline.callFor(callId);
    if (call == null || call.callId.trim().isEmpty) {
      return false;
    }
    final decisionReason = reason ?? 'User denied this agent tool call.';
    _toolCallReviewDecisions[call.callId] = AgentToolCallReviewDecision.denied(
      callId: call.callId,
      toolId: call.toolId,
      reason: decisionReason,
      decidedAt: DateTime.now().toUtc(),
    );
    if (rememberForSession) {
      _upsertSessionToolPermissionRule(
        toolId: call.toolId,
        action: AgentToolPermissionAction.deny,
        reason: decisionReason,
      );
    }
    _recordRecentToolCallResultContexts(<AgentToolCallDispatchResult>[
      _toolSessionProcessor.reviewDeniedResult(
        call: call,
        reason: decisionReason,
      ),
    ]);
    return true;
  }

  bool clearSessionToolPermissionRule(String toolId) {
    final ruleId = _sessionToolPermissionRuleId(toolId);
    final before = _sessionToolPermissionRules.length;
    _sessionToolPermissionRules.removeWhere((rule) => rule.ruleId == ruleId);
    if (_sessionToolPermissionRules.length == before) {
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<void> loadToolPermissionPolicy() async {
    final store = toolPermissionPolicyStore;
    if (store == null) {
      return;
    }
    try {
      final policy = await store.readPolicy(
        workspaceId: _toolPermissionPolicyWorkspaceId,
      );
      _projectToolPermissionRules
        ..clear()
        ..addAll(policy.rules);
      notifyListeners();
    } on Object catch (error) {
      _lastError =
          'Agent tool permission policy restore failed: ${sanitizeAgentError(error.toString())}';
      notifyListeners();
    }
  }

  Future<void> loadWorkspaceSnapshot({
    AgentWorkspaceSnapshotService? snapshotService,
  }) async {
    final store = workspaceSnapshotStore;
    if (store == null) {
      return;
    }
    try {
      final snapshot = await store.readSnapshot(
        workspaceId: _workspaceSnapshotWorkspaceId,
      );
      if (snapshot == null) {
        return;
      }
      _lastWorkspaceSnapshot = snapshot;
      _lastWorkspaceSnapshotCaptureResult = AgentWorkspaceSnapshotCaptureResult(
        status: snapshot.complete
            ? AgentWorkspaceSnapshotCaptureStatus.captured
            : AgentWorkspaceSnapshotCaptureStatus.partial,
        message:
            'Restored workspace snapshot ${snapshot.snapshotId} from Foundation DataStore.',
        restored: true,
        snapshot: snapshot,
      );
      _lastWorkspaceRevertPlan = snapshotService == null
          ? null
          : await snapshotService.buildRevertPlan(snapshot);
      notifyListeners();
    } on Object catch (error) {
      _lastError =
          'Agent workspace snapshot restore failed: ${sanitizeAgentError(error.toString())}';
      notifyListeners();
    }
  }

  Future<bool> approveToolCallExecutionForProject(
    String callId, {
    String? reason,
  }) {
    return _rememberToolCallExecutionForProject(
      callId,
      action: AgentToolPermissionAction.allow,
      reason: reason ?? 'Allow this agent tool for this workspace.',
    );
  }

  Future<bool> denyToolCallExecutionForProject(
    String callId, {
    String? reason,
  }) {
    return _rememberToolCallExecutionForProject(
      callId,
      action: AgentToolPermissionAction.deny,
      reason: reason ?? 'Deny this agent tool for this workspace.',
    );
  }

  Future<bool> clearProjectToolPermissionRule(String toolId) async {
    final ruleId = _projectToolPermissionRuleId(toolId);
    final before = _projectToolPermissionRules.length;
    _projectToolPermissionRules.removeWhere((rule) => rule.ruleId == ruleId);
    if (_projectToolPermissionRules.length == before) {
      return false;
    }
    final persisted = await _persistProjectToolPermissionPolicy();
    notifyListeners();
    return persisted;
  }

  Future<AgentToolCallDispatchReport> dispatchReadyToolCalls(
    AgentToolCallExecutor executor, {
    AgentToolCallDispatcher dispatcher = const AgentToolCallDispatcher(),
  }) async {
    final executionPlan = toolCallExecutionPlan;
    final report = await _toolSessionProcessor.dispatchReady(
      executionPlan: executionPlan,
      timeline: _toolCallTimeline,
      executor: executor,
      toolSelection: _currentToolSelection(),
      dispatcher: dispatcher,
    );
    if (report.events.isNotEmpty) {
      recordToolCallEvents(report.events);
    }
    if (report.results.isNotEmpty) {
      _recordRecentToolCallResultContexts(report.results);
    }
    _refreshToolCallExecutionJournal(dispatchReport: report);
    await _persistLatestAgentToolExecutionJournal();
    notifyListeners();
    return report;
  }

  Future<AgentToolCallReplayReport> replayToolCallJournal(
    AgentToolCallExecutor executor, {
    bool includeCompleted = false,
  }) async {
    final report = await _toolSessionProcessor.replayJournal(
      journal: _toolCallExecutionJournal,
      executor: executor,
      includeCompleted: includeCompleted,
      toolSelection: _currentToolSelection(),
    );
    if (report.events.isNotEmpty) {
      recordToolCallEvents(report.events);
    }
    if (report.results.isNotEmpty) {
      _recordRecentToolCallResultContexts(report.results);
    }
    _refreshToolCallExecutionJournal();
    notifyListeners();
    await _persistLatestAgentToolReplayReport(report);
    return report;
  }

  void _refreshToolCallExecutionJournal({
    AgentToolCallDispatchReport? dispatchReport,
  }) {
    _toolCallExecutionJournal = _toolSessionProcessor.buildJournal(
      timeline: _toolCallTimeline,
      executionPlan: toolCallExecutionPlan,
      dispatchReport: dispatchReport,
    );
  }

  Future<AgentProviderResponseEnvelope?> sendPrompt() async {
    final prompt = _draftPrompt.trim();
    if (_sending || _applyingPatch || _applyingIdeCommand || prompt.isEmpty) {
      return null;
    }

    final requestContext = _contextForProviderRequest();
    final readiness = requestContext.codingReadiness
        .withControllerState(
          hasDraftPrompt: true,
          sending: _sending,
          applyingPatch: _applyingPatch,
          applyingIdeCommand: _applyingIdeCommand,
        )
        .withLoopGuard(_currentCodingLoopGuard());
    if (!readiness.canDispatchProviderRequest) {
      _lastError = sanitizeAgentError(_agentReadinessBlockMessage(readiness));
      final blockedAt = DateTime.now().toUtc();
      await _appendAgentCodingSessionHistory(
        AgentCodingSessionHistoryRecord.failure(
          requestId: _nextRequestId(),
          profile: profile,
          providerKind: adapter.kind,
          prompt: prompt,
          errorMessage: _lastError!,
          createdAt: blockedAt,
          completedAt: blockedAt,
        ),
      );
      notifyListeners();
      return null;
    }
    final toolCallJournalForHistory = _recentToolCallResultContexts.isEmpty
        ? null
        : _toolCallExecutionJournal;
    final toolSessionTranscriptForRequest = toolSessionTranscript;

    final requestSerial = _activeRequestSerial + 1;
    _activeRequestSerial = requestSerial;
    final patchApplicationContextSent = _lastPatchApplicationContext;
    _preserveAgentStateForActiveRequest();
    _sending = true;
    _lastError = null;
    _lastProviderFailure = null;
    _lastResponse = null;
    _pendingPatch = null;
    _lastPatchApplicationResult = null;
    _clearWorkspaceSnapshotState();
    _toolCallTimeline = AgentToolCallTimeline.empty();
    _toolCallReviewDecisions.clear();
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
        toolCallResults: _toolCallResultWindow(),
        toolSessionTranscript: toolSessionTranscriptForRequest.parts.isEmpty
            ? null
            : toolSessionTranscriptForRequest,
      );
      _activeProviderRequestId = request.requestId;
      _activeProviderPrompt = prompt;
      _activeProviderStartedAt = requestStartedAt;
      final response = await _sendProviderRequest(request);
      if (requestSerial != _activeRequestSerial) {
        return null;
      }
      final responseToolCallEvents = response.toolCallEvents
          .where((event) => !_isStreamedProviderToolCallEvent(event))
          .toList(growable: false);
      if (responseToolCallEvents.isNotEmpty) {
        recordToolCallEvents(responseToolCallEvents);
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
      _recordActiveAgentRuntimeStep();
      _recentToolCallResultContexts.clear();
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
          metadata: _agentCodingHistoryMetadata(
            requestContext,
            toolCallExecutionJournal: toolCallJournalForHistory,
            toolSessionTranscript: toolSessionTranscriptForRequest,
            toolResultContinuation: _pendingToolResultContinuationMetadata,
          ),
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
            metadata: _agentCodingHistoryMetadata(
              requestContext,
              toolCallExecutionJournal: toolCallJournalForHistory,
              toolSessionTranscript: toolSessionTranscriptForRequest,
              toolResultContinuation: _pendingToolResultContinuationMetadata,
            ),
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
  ) async {
    final result = await const AgentProviderStreamingRuntime().run(
      adapter: adapter,
      request: request,
      onOutputEvent: (event) {
        _runtimeOutputBuffer?.addEvent(event);
      },
      onProviderEvent: (event) {
        final toolCallEvent = _toolSessionProcessor.eventForProviderStream(
          event,
        );
        if (toolCallEvent != null) {
          recordToolCallEvent(toolCallEvent);
        }
      },
    );
    if (result.succeeded && result.response != null) {
      return result.response!;
    }
    final error = result.error;
    if (error is AgentProviderTransportException) {
      throw error;
    }
    if (error != null) {
      throw error;
    }
    throw AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.unknown,
      message: result.errorMessage ?? 'Agent provider request failed.',
      operation: 'agent.provider.streaming_runtime',
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
    _clearWorkspaceSnapshotState();
    _clearPreservedAgentState();
    notifyListeners();
  }

  void clearConversation() {
    if (_conversationTurns.isEmpty &&
        _lastResponse == null &&
        _pendingPatch == null &&
        _lastPatchApplicationResult == null &&
        _lastPatchApplicationContext == null &&
        _lastWorkspaceSnapshotCaptureResult == null &&
        _lastWorkspaceSnapshot == null &&
        _lastWorkspaceRevertPlan == null &&
        _lastIdeCommandResultContext == null &&
        _recentIdeCommandResultContexts.isEmpty &&
        _recentPatchApplicationContexts.isEmpty &&
        _recentPatchProposalContexts.isEmpty &&
        _recentIdeCommandSuggestionContexts.isEmpty &&
        _omittedConversationTurnCount == 0 &&
        _conversationCompactionSummary.isEmpty &&
        _toolCallTimeline.status == AgentToolCallTimelineStatus.idle &&
        _toolCallReviewDecisions.isEmpty &&
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
    _omittedConversationTurnCount = 0;
    _clearConversationCompactionSummary();
    _lastResponse = null;
    _pendingPatch = null;
    _lastPatchApplicationResult = null;
    _lastPatchApplicationContext = null;
    _clearWorkspaceSnapshotState();
    _lastIdeCommandResultContext = null;
    _clearPreservedAgentState();
    _recentIdeCommandResultContexts.clear();
    _completedIdeCommandSuggestionKeys.clear();
    _recentPatchApplicationContexts.clear();
    _recentPatchProposalContexts.clear();
    _recentIdeCommandSuggestionContexts.clear();
    _toolCallTimeline = AgentToolCallTimeline.empty();
    _toolCallReviewDecisions.clear();
    _agentRuntimeStepCounts.clear();
    _lastError = null;
    _lastProviderFailure = null;
    notifyListeners();
  }

  Future<AgentWorkspaceSnapshotCaptureResult?> capturePendingPatchSnapshot(
    AgentWorkspaceSnapshotService snapshotService,
  ) async {
    final patch = _pendingPatch;
    if (patch == null) {
      return null;
    }
    return _captureWorkspaceSnapshotForPatch(
      patch: patch,
      snapshotService: snapshotService,
    );
  }

  void recordWorkspaceSnapshotCaptureResult(
    AgentWorkspaceSnapshotCaptureResult result,
  ) {
    _lastWorkspaceSnapshotCaptureResult = result;
    _lastWorkspaceSnapshot = result.snapshot;
    _lastWorkspaceRevertPlan = null;
    unawaited(_persistWorkspaceSnapshot(result.snapshot));
    notifyListeners();
  }

  Future<AgentWorkspaceRevertPlan?> buildWorkspaceRevertPlan(
    AgentWorkspaceSnapshotService snapshotService,
  ) async {
    final snapshot = _lastWorkspaceSnapshot;
    if (snapshot == null) {
      return null;
    }
    final plan = await snapshotService.buildRevertPlan(snapshot);
    _lastWorkspaceRevertPlan = plan;
    notifyListeners();
    return plan;
  }

  void recordWorkspaceRevertPlan(AgentWorkspaceRevertPlan plan) {
    _lastWorkspaceRevertPlan = plan;
    notifyListeners();
  }

  AgentCodePatchApplicationResult? applyLastWorkspaceRevertPlan(
    AgentCodePatchApplier applier,
  ) {
    final plan = _lastWorkspaceRevertPlan;
    if (plan == null) {
      return null;
    }
    final patch = plan.patch;
    if (!plan.ready) {
      final result = _revertPlanNotReadyResult(plan);
      _recordPatchApplicationResult(patch, result);
      notifyListeners();
      return result;
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
      _clearWorkspaceSnapshotState();
    }
    notifyListeners();
    return result;
  }

  Future<AgentCodePatchApplicationResult?>
  applyLastWorkspaceRevertPlanToWorkspace(
    AgentWorkspaceCodePatchApplier applier,
  ) async {
    final plan = _lastWorkspaceRevertPlan;
    if (plan == null) {
      return null;
    }
    final patch = plan.patch;
    if (!plan.ready) {
      final result = _revertPlanNotReadyResult(plan);
      _recordPatchApplicationResult(patch, result);
      notifyListeners();
      return result;
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
        _clearWorkspaceSnapshotState();
      }
      return result;
    } finally {
      if (applicationSerial == _patchApplicationSerial) {
        _applyingPatch = false;
        notifyListeners();
      }
    }
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

  Future<AgentCodePatchApplicationResult?> applyPendingPatchWithSnapshot({
    required AgentCodePatchApplier applier,
    required AgentWorkspaceSnapshotService snapshotService,
  }) async {
    final patch = _pendingPatch;
    if (patch == null) {
      return null;
    }
    if (_applyingPatch) {
      return applyPendingPatch(applier);
    }

    final snapshotResult = await _captureWorkspaceSnapshotForPatch(
      patch: patch,
      snapshotService: snapshotService,
    );
    if (!_snapshotIsComplete(snapshotResult)) {
      final result = _snapshotBlockedApplicationResult(patch, snapshotResult);
      _recordPatchApplicationResult(patch, result);
      notifyListeners();
      return result;
    }

    final result = applyPendingPatch(applier);
    if (result?.applied == true) {
      await buildWorkspaceRevertPlan(snapshotService);
    }
    return result;
  }

  Future<AgentCodePatchApplicationResult?> applyPendingWorkspacePatch(
    AgentWorkspaceCodePatchApplier applier, {
    AgentWorkspaceSnapshotService? snapshotService,
  }) async {
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

    if (snapshotService != null) {
      final snapshotResult = await _captureWorkspaceSnapshotForPatch(
        patch: patch,
        snapshotService: snapshotService,
      );
      if (!_snapshotIsComplete(snapshotResult)) {
        final result = _snapshotBlockedApplicationResult(patch, snapshotResult);
        _recordPatchApplicationResult(patch, result);
        notifyListeners();
        return result;
      }
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
        if (snapshotService != null) {
          await buildWorkspaceRevertPlan(snapshotService);
        }
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
    _refreshLastPatchValidationSnapshot();
    unawaited(_persistLatestAgentValidationSnapshot());
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
    _runtimeOutputBuffer?.addEvent(
      _patchApplicationRuntimeOutputEvent(
        patch: patch,
        result: result,
        recordedAt: recordedAt,
      ),
    );
    _recordRecentPatchApplicationContext(_lastPatchApplicationContext!);
    _appendConversationTurn(
      role: AgentConversationRole.user,
      text: _patchApplicationConversationText(patch, result),
    );
  }

  Future<AgentWorkspaceSnapshotCaptureResult>
  _captureWorkspaceSnapshotForPatch({
    required AgentCodePatch patch,
    required AgentWorkspaceSnapshotService snapshotService,
  }) async {
    final result = await snapshotService.captureBeforePatch(patch);
    _lastWorkspaceSnapshotCaptureResult = result;
    _lastWorkspaceSnapshot = result.snapshot;
    _lastWorkspaceRevertPlan = null;
    await _persistWorkspaceSnapshot(result.snapshot);
    notifyListeners();
    return result;
  }

  bool _snapshotIsComplete(AgentWorkspaceSnapshotCaptureResult result) {
    return result.status == AgentWorkspaceSnapshotCaptureStatus.captured &&
        result.snapshot != null &&
        result.snapshot!.complete;
  }

  AgentCodePatchApplicationResult _snapshotBlockedApplicationResult(
    AgentCodePatch patch,
    AgentWorkspaceSnapshotCaptureResult result,
  ) {
    return AgentCodePatchApplicationResult(
      applied: false,
      message:
          'Agent patch ${patch.patchId} was not applied because workspace snapshot capture was incomplete: ${result.message}',
    );
  }

  AgentCodePatchApplicationResult _revertPlanNotReadyResult(
    AgentWorkspaceRevertPlan plan,
  ) {
    return AgentCodePatchApplicationResult(
      applied: false,
      message:
          'Agent workspace revert plan ${plan.snapshotId} is not ready: ${plan.status.wireValue}.',
    );
  }

  void _clearWorkspaceSnapshotState() {
    _lastWorkspaceSnapshotCaptureResult = null;
    _lastWorkspaceSnapshot = null;
    _lastWorkspaceRevertPlan = null;
    unawaited(_deleteWorkspaceSnapshot());
  }

  Future<void> _persistWorkspaceSnapshot(
    AgentWorkspaceChangeSnapshot? snapshot,
  ) async {
    final store = workspaceSnapshotStore;
    if (store == null || snapshot == null) {
      return;
    }
    try {
      await store.saveSnapshot(
        workspaceId: _workspaceSnapshotWorkspaceId,
        snapshot: snapshot,
      );
    } on Object catch (error) {
      _lastError =
          'Agent workspace snapshot persistence failed: ${sanitizeAgentError(error.toString())}';
    }
  }

  Future<void> _deleteWorkspaceSnapshot() async {
    final store = workspaceSnapshotStore;
    if (store == null) {
      return;
    }
    try {
      await store.deleteSnapshot(workspaceId: _workspaceSnapshotWorkspaceId);
    } on Object catch (error) {
      _lastError =
          'Agent workspace snapshot cleanup failed: ${sanitizeAgentError(error.toString())}';
    }
  }

  RuntimeOutputEvent _patchApplicationRuntimeOutputEvent({
    required AgentCodePatch patch,
    required AgentCodePatchApplicationResult result,
    required DateTime recordedAt,
  }) {
    return RuntimeOutputEvent(
      channelId: 'agent.activity',
      label: 'Agent Activity',
      kind: RuntimeOutputChannelKind.agent,
      message: result.message,
      timestamp: recordedAt,
      metadata: <String, Object?>{
        'operation': 'agent.patch.apply',
        'patchId': patch.patchId,
        'applied': result.applied,
        'appliedEditCount': result.appliedEditCount,
        'changedDocumentCount': result.appliedDocumentIds.length,
        'createdDocumentCount': result.createdDocumentIds.length,
        'deletedDocumentCount': result.deletedDocumentIds.length,
        'skippedNoOpDocumentCount': result.skippedNoOpDocumentIds.length,
        'outcome': result.applied ? 'succeeded' : 'failed',
      },
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
      recoveryPlan: sessionRecoveryPlan,
      loopGuard: _currentCodingLoopGuard(),
      conversationCompaction: _conversationCompactionContext(
        sentTurnCount: _conversationWindow().length,
      ),
      workspaceCheckpoint: _workspaceCheckpointContext(),
      toolCallTimeline: _toolCallTimeline,
      toolCallExecutionJournal: _toolCallExecutionJournal,
      toolReplayPlan: toolCallReplayPlan,
      agentRegistry: agentRegistrySnapshot,
      toolCatalog: _currentToolSelection(),
      toolPermissionPlan: _currentToolPermissionPlan(),
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

  void _refreshLastPatchValidationSnapshot() {
    final lastPatchApplication = _lastPatchApplicationContext;
    if (lastPatchApplication == null) {
      return;
    }
    final validationSnapshot = _contextForProviderRequest()
        .agent
        .lastPatchApplication
        ?.validationSnapshot;
    if (validationSnapshot == null) {
      return;
    }
    final updated = lastPatchApplication.withValidationSnapshot(
      validationSnapshot,
    );
    _lastPatchApplicationContext = updated;
    for (
      var index = 0;
      index < _recentPatchApplicationContexts.length;
      index++
    ) {
      if (_recentPatchApplicationContexts[index].patchId ==
          lastPatchApplication.patchId) {
        _recentPatchApplicationContexts[index] = updated;
        return;
      }
    }
  }

  Future<void> _persistLatestAgentValidationSnapshot() async {
    final store = sessionHistoryStore;
    final lastPatchApplication = _lastPatchApplicationContext;
    if (store == null ||
        lastPatchApplication == null ||
        lastPatchApplication.validationSnapshot == null) {
      return;
    }
    try {
      final current =
          _sessionHistorySnapshot ??
          await store.readHistory(workspaceId: sessionHistoryWorkspaceId);
      if (current.records.isEmpty) {
        return;
      }
      final latest = current.records.first;
      final metadata = <String, Object?>{
        ...latest.metadata,
        ..._agentCodingHistoryMetadata(_contextForProviderRequest()),
      };
      final next = current.replaceLatest(latest.copyWith(metadata: metadata));
      _sessionHistorySnapshot = next;
      await store.saveHistory(next);
    } on Object catch (error) {
      _publishAgentRuntimeDiagnostic(
        operation: 'agent.history.validation-persist',
        message:
            'Agent validation snapshot persistence failed: ${sanitizeAgentError(error.toString())}',
      );
    }
  }

  Future<void> _persistLatestAgentToolReplayReport(
    AgentToolCallReplayReport report,
  ) async {
    final store = sessionHistoryStore;
    if (store == null) {
      return;
    }
    try {
      final current =
          _sessionHistorySnapshot ??
          await store.readHistory(workspaceId: sessionHistoryWorkspaceId);
      if (current.records.isEmpty) {
        return;
      }
      final latest = current.records.first;
      final replayReportPayload = report.toJson();
      final previousReports = latest.metadata['toolCallReplayReports'] is List
          ? (latest.metadata['toolCallReplayReports'] as List)
                .whereType<Map>()
                .map(
                  (item) =>
                      item.map((key, value) => MapEntry(key.toString(), value)),
                )
                .toList(growable: false)
          : const <Map<String, Object?>>[];
      final replayReports = <Map<String, Object?>>[
        replayReportPayload,
        ...previousReports.take(4),
      ];
      final metadata = <String, Object?>{
        ...latest.metadata,
        'lastToolCallReplayReport': replayReportPayload,
        'toolCallReplayReports': replayReports,
        'toolCallReplayReportCount': replayReports.length,
      };
      final next = current.replaceLatest(latest.copyWith(metadata: metadata));
      _sessionHistorySnapshot = next;
      await store.saveHistory(next);
    } on Object catch (error) {
      _publishAgentRuntimeDiagnostic(
        operation: 'agent.history.tool-replay-persist',
        message:
            'Agent tool replay report persistence failed: ${sanitizeAgentError(error.toString())}',
      );
    }
  }

  Future<void> _persistLatestAgentToolExecutionJournal() async {
    final store = sessionHistoryStore;
    if (store == null || _toolCallExecutionJournal.entries.isEmpty) {
      return;
    }
    try {
      final current =
          _sessionHistorySnapshot ??
          await store.readHistory(workspaceId: sessionHistoryWorkspaceId);
      if (current.records.isEmpty) {
        return;
      }
      final latest = current.records.first;
      final transcript = toolSessionTranscript;
      final metadata = <String, Object?>{
        ...latest.metadata,
        'toolCallExecutionJournal': _toolCallExecutionJournal.toJson(),
        if (transcript.parts.isNotEmpty)
          'toolSessionTranscript': transcript.toJson(),
      };
      final next = current.replaceLatest(latest.copyWith(metadata: metadata));
      _sessionHistorySnapshot = next;
      await store.saveHistory(next);
    } on Object catch (error) {
      _publishAgentRuntimeDiagnostic(
        operation: 'agent.history.tool-journal-persist',
        message:
            'Agent tool execution journal persistence failed: ${sanitizeAgentError(error.toString())}',
      );
    }
  }

  int _latestToolReplayReportCount() {
    final records = sessionHistorySnapshot.records;
    if (records.isEmpty) {
      return 0;
    }
    final value = records.first.metadata['toolCallReplayReportCount'];
    return value is int ? value : 0;
  }

  AgentCodingLoopGuard _currentCodingLoopGuard() {
    final activeAgent = agentRegistrySnapshot.activeAgent;
    return AgentCodingLoopGuard.fromSignals(
      toolReplayReportCount: _latestToolReplayReportCount(),
      failedToolResultCount: _recentToolCallResultContexts
          .where((result) => !result.success)
          .length,
      agentStepCount: _activeAgentRuntimeStepCount(),
      maxAgentSteps: activeAgent?.maxSteps,
      activeAgentId: activeAgent?.agentId ?? activeAgentId,
      hasProviderFailure: _lastProviderFailure != null,
    );
  }

  int _activeAgentRuntimeStepCount() {
    return _agentRuntimeStepCounts[activeAgentId] ?? 0;
  }

  void _recordActiveAgentRuntimeStep() {
    final agentId = activeAgentId.trim();
    if (agentId.isEmpty) {
      return;
    }
    _agentRuntimeStepCounts[agentId] =
        (_agentRuntimeStepCounts[agentId] ?? 0) + 1;
  }

  AgentWorkspaceCheckpointContext? _workspaceCheckpointContext() {
    final capture = _lastWorkspaceSnapshotCaptureResult;
    final snapshot = _lastWorkspaceSnapshot;
    final revertPlan = _lastWorkspaceRevertPlan;
    if (capture == null && snapshot == null && revertPlan == null) {
      return null;
    }
    final diffSummary = revertPlan?.diffSummary;
    return AgentWorkspaceCheckpointContext(
      captureStatus: capture?.status.wireValue ?? 'unknown',
      snapshotId: snapshot?.snapshotId ?? revertPlan?.snapshotId,
      patchId: snapshot?.patchId,
      activeDocumentId: snapshot?.activeDocumentId,
      capturedAt: snapshot?.capturedAt,
      captureMessage: capture?.message,
      capturedDocumentCount: snapshot?.documents.length ?? 0,
      unavailableDocumentIds:
          snapshot?.unavailableDocumentIds ?? const <String>[],
      revertPlanStatus: revertPlan?.status.wireValue,
      revertReady: revertPlan?.ready ?? false,
      revertPatchId: revertPlan?.patch.patchId,
      revertChangedDocumentCount: diffSummary?.changedDocumentCount ?? 0,
      revertAddedDocumentIds: diffSummary?.addedDocumentIds ?? const <String>[],
      revertDeletedDocumentIds:
          diffSummary?.deletedDocumentIds ?? const <String>[],
      revertModifiedDocumentIds:
          diffSummary?.modifiedDocumentIds ?? const <String>[],
      revertUnavailableDocumentIds:
          diffSummary?.unavailableDocumentIds ?? const <String>[],
      todoItems: <String>{
        ...?snapshot?.todoItems,
        ...?revertPlan?.todoItems,
      }.toList(growable: false),
    );
  }

  AgentToolPermissionPlan _currentToolPermissionPlan() {
    return AgentToolPermissionPlan.fromSelection(
      _currentToolSelection(),
      rules: _toolPermissionRules(),
    );
  }

  AgentToolSelection _currentToolSelection() {
    return _toolRegistry.selectForProfile(
      profile: profile,
      providerKind: adapter.kind,
    );
  }

  void _upsertSessionToolPermissionRule({
    required String toolId,
    required AgentToolPermissionAction action,
    required String reason,
  }) {
    final normalizedToolId = toolId.trim();
    if (normalizedToolId.isEmpty) {
      return;
    }
    final ruleId = _sessionToolPermissionRuleId(normalizedToolId);
    _sessionToolPermissionRules.removeWhere((rule) => rule.ruleId == ruleId);
    _sessionToolPermissionRules.add(
      AgentToolPermissionRule(
        ruleId: ruleId,
        toolIdPattern: normalizedToolId,
        action: action,
        priority: 1000,
        reason: reason,
      ),
    );
  }

  Future<bool> _rememberToolCallExecutionForProject(
    String callId, {
    required AgentToolPermissionAction action,
    required String reason,
  }) async {
    final call = _toolCallTimeline.callFor(callId);
    if (call == null || call.callId.trim().isEmpty) {
      return false;
    }
    _upsertProjectToolPermissionRule(
      toolId: call.toolId,
      action: action,
      reason: reason,
    );
    final persisted = await _persistProjectToolPermissionPolicy();
    notifyListeners();
    return persisted;
  }

  void _upsertProjectToolPermissionRule({
    required String toolId,
    required AgentToolPermissionAction action,
    required String reason,
  }) {
    final normalizedToolId = toolId.trim();
    if (normalizedToolId.isEmpty) {
      return;
    }
    final ruleId = _projectToolPermissionRuleId(normalizedToolId);
    _projectToolPermissionRules.removeWhere((rule) => rule.ruleId == ruleId);
    _projectToolPermissionRules.add(
      AgentToolPermissionRule(
        ruleId: ruleId,
        toolIdPattern: normalizedToolId,
        action: action,
        priority: 500,
        reason: reason,
      ),
    );
  }

  Future<bool> _persistProjectToolPermissionPolicy() async {
    final store = toolPermissionPolicyStore;
    if (store == null) {
      return true;
    }
    try {
      await store.savePolicy(
        AgentToolPermissionPolicy(
          workspaceId: _toolPermissionPolicyWorkspaceId,
          rules: _projectToolPermissionRules,
        ),
      );
      return true;
    } on Object catch (error) {
      _lastError =
          'Agent tool permission policy persistence failed: ${sanitizeAgentError(error.toString())}';
      return false;
    }
  }

  List<AgentToolPermissionRule> _toolPermissionRules() {
    final activeAgentRules =
        agentRegistrySnapshot.activeAgent?.permissionRules ??
        const <AgentToolPermissionRule>[];
    return <AgentToolPermissionRule>[
      ...activeAgentRules,
      ..._projectToolPermissionRules,
      ..._sessionToolPermissionRules,
    ];
  }

  String _projectToolPermissionRuleId(String toolId) {
    return 'project-tool-permission-${toolId.trim()}';
  }

  String _sessionToolPermissionRuleId(String toolId) {
    return 'session-tool-permission-${toolId.trim()}';
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
    if (maxConversationTurns <= 0) {
      return const <AgentConversationTurn>[];
    }
    if (_conversationTurns.length <= maxConversationTurns) {
      return conversationTurns;
    }
    return List<AgentConversationTurn>.unmodifiable(
      _conversationTurns.sublist(
        _conversationTurns.length - maxConversationTurns,
      ),
    );
  }

  AgentConversationCompactionContext _conversationCompactionContext({
    required int sentTurnCount,
  }) {
    return AgentConversationCompactionContext.fromConversationState(
      retainedTurnTexts: _conversationTurns.map((turn) => turn.text),
      omittedTurnCount: _omittedConversationTurnCount,
      sentTurnCount: sentTurnCount,
      maxRetainedTurnCount: maxConversationTurns,
      maxTurnTextLength: maxConversationTurnTextLength,
      summary: _conversationCompactionSummary,
      summaryTurnCount: _conversationCompactionSummaryTurnCount,
      summaryUpdatedAt: _conversationCompactionSummaryUpdatedAt,
    );
  }

  List<AgentToolCallResultContext> _toolCallResultWindow() {
    return List<AgentToolCallResultContext>.unmodifiable(
      _recentToolCallResultContexts,
    );
  }

  void _recordRecentToolCallResultContexts(
    Iterable<AgentToolCallDispatchResult> results,
  ) {
    final createdAt = DateTime.now().toUtc();
    final selectionContext = AgentToolSelectionContext.fromProfile(
      profile: profile,
      providerKind: adapter.kind,
    );
    _recentToolCallResultContexts.addAll(
      results.map((result) {
        final outputLimit = _toolRegistry.outputLimitForTool(
          toolId: result.toolId,
          context: selectionContext,
        );
        return outputLimit == null
            ? AgentToolCallResultContext.fromDispatchResult(
                result,
                createdAt: createdAt,
              )
            : AgentToolCallResultContext.fromDispatchResult(
                result,
                createdAt: createdAt,
                outputLimit: outputLimit,
              );
      }),
    );
    if (_recentToolCallResultContexts.length >
        _maxAgentToolCallResultContextHistory) {
      _recentToolCallResultContexts.removeRange(
        0,
        _recentToolCallResultContexts.length -
            _maxAgentToolCallResultContextHistory,
      );
    }
    notifyListeners();
  }

  void _trimConversationWindow() {
    if (maxConversationTurns <= 0) {
      _appendConversationCompactionSummary(_conversationTurns);
      _omittedConversationTurnCount += _conversationTurns.length;
      _conversationTurns.clear();
      return;
    }
    if (_conversationTurns.length <= maxConversationTurns) {
      return;
    }
    final omittedCount = _conversationTurns.length - maxConversationTurns;
    _appendConversationCompactionSummary(_conversationTurns.take(omittedCount));
    _omittedConversationTurnCount += omittedCount;
    _conversationTurns.removeRange(0, omittedCount);
  }

  void _appendConversationCompactionSummary(
    Iterable<AgentConversationTurn> omittedTurns,
  ) {
    final turns = omittedTurns.toList(growable: false);
    if (turns.isEmpty) {
      return;
    }
    final lines = turns
        .map((turn) {
          final role = turn.role.wireValue;
          final text = _conversationCompactionTurnSample(turn.text);
          return '- $role: $text';
        })
        .join('\n');
    final next = _conversationCompactionSummary.isEmpty
        ? lines
        : '${_conversationCompactionSummary.trim()}\n$lines';
    _conversationCompactionSummary = _truncateCompactionSummary(next);
    _conversationCompactionSummaryTurnCount += turns.length;
    _conversationCompactionSummaryUpdatedAt = DateTime.now().toUtc();
  }

  void _clearConversationCompactionSummary() {
    _conversationCompactionSummary = '';
    _conversationCompactionSummaryTurnCount = 0;
    _conversationCompactionSummaryUpdatedAt = null;
  }

  String _conversationCompactionTurnSample(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= _maxAgentConversationCompactionTurnSampleLength) {
      return normalized;
    }
    final omitted =
        normalized.length - _maxAgentConversationCompactionTurnSampleLength;
    return '${normalized.substring(0, _maxAgentConversationCompactionTurnSampleLength)} [...$omitted char(s) omitted]';
  }

  String _truncateCompactionSummary(String summary) {
    if (summary.length <= _maxAgentConversationCompactionSummaryLength) {
      return summary;
    }
    final omitted =
        summary.length - _maxAgentConversationCompactionSummaryLength;
    return '${summary.substring(summary.length - _maxAgentConversationCompactionSummaryLength)}\n[older compaction summary omitted $omitted char(s)]';
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

bool _isStreamedProviderToolCallEvent(AgentToolCallEvent event) {
  final metadata = event.metadata;
  if (metadata['providerEventType'] != null ||
      metadata['toolCallEventKind'] != null ||
      metadata['tool_call_event_kind'] != null) {
    return true;
  }
  final source = metadata['source'];
  return source is String && source.contains('stream');
}

String _agentReadinessBlockMessage(AgentCodingExecutionReadiness readiness) {
  final issueMessages = readiness.issues
      .map((issue) => '${issue.code}: ${issue.message}')
      .toList(growable: false);
  if (issueMessages.isEmpty) {
    return 'Agent request blocked by coding readiness gate.';
  }
  return 'Agent request blocked by coding readiness gate: ${issueMessages.join(' ')}';
}

Map<String, Object?> _agentCodingHistoryMetadata(
  AgentSessionContext context, {
  AgentToolCallExecutionJournal? toolCallExecutionJournal,
  AgentToolSessionTranscript? toolSessionTranscript,
  Map<String, Object?>? toolResultContinuation,
}) {
  final agent = context.agent;
  final metadata = <String, Object?>{};
  if (toolResultContinuation != null) {
    metadata.addAll(toolResultContinuation);
  }
  if (toolCallExecutionJournal != null &&
      toolCallExecutionJournal.entries.isNotEmpty) {
    metadata['toolCallExecutionJournal'] = toolCallExecutionJournal.toJson();
  }
  if (toolSessionTranscript != null && toolSessionTranscript.parts.isNotEmpty) {
    metadata['toolSessionTranscript'] = toolSessionTranscript.toJson();
  }
  final lastPatchApplication = agent.lastPatchApplication;
  if (lastPatchApplication != null) {
    metadata['lastPatchApplication'] = <String, Object?>{
      'patchId': lastPatchApplication.patchId,
      'applied': lastPatchApplication.applied,
      'pendingPatchRetained': lastPatchApplication.pendingPatchRetained,
      'changedDocumentIds': lastPatchApplication.changedDocumentIds,
      'message': lastPatchApplication.message,
      if (lastPatchApplication.validationSnapshot != null)
        'validationSnapshot': lastPatchApplication.validationSnapshot!.toJson(),
    };
  }
  if (agent.validationPlan.status !=
      AgentCodingValidationPlanStatus.notNeeded) {
    metadata['validationPlan'] = <String, Object?>{
      'status': agent.validationPlan.status.wireValue,
      'shouldRun': agent.validationPlan.shouldRun,
      'registeredCommandIds': agent.validationPlan.registeredCommandIds,
    };
    metadata['validationResult'] = <String, Object?>{
      'status': agent.validationResult.status.wireValue,
      'completedCommandIds': agent.validationResult.completedCommandIds,
      'failedCommandIds': agent.validationResult.failedCommandIds,
      'missingCommandIds': agent.validationResult.missingCommandIds,
      'resultCount': agent.validationResult.resultCount,
    };
    metadata['validationPipeline'] = <String, Object?>{
      'status': agent.validationPipeline.status.wireValue,
      if (agent.validationPipeline.nextCommandId != null)
        'nextCommandId': agent.validationPipeline.nextCommandId,
      'progressNumerator': agent.validationPipeline.progressNumerator,
      'progressDenominator': agent.validationPipeline.progressDenominator,
      'remainingCommandIds': agent.validationPipeline.remainingCommandIds,
    };
    final validationCommandIds = <String>{
      ...agent.validationResult.completedCommandIds,
      ...agent.validationResult.failedCommandIds,
      ...agent.validationResult.missingCommandIds,
    };
    final validationCommandResults = context.commands.recentResults
        .where((result) => validationCommandIds.contains(result.commandId))
        .map((result) => result.toJson())
        .toList(growable: false);
    if (validationCommandResults.isNotEmpty) {
      metadata['validationCommandResults'] = validationCommandResults;
    }
    final failedCommandIds = agent.validationResult.failedCommandIds.toSet();
    final failedCommandResults = context.commands.recentResults
        .where((result) => failedCommandIds.contains(result.commandId))
        .map((result) => result.toJson())
        .toList(growable: false);
    if (failedCommandResults.isNotEmpty) {
      metadata['validationFailedCommandResults'] = failedCommandResults;
    }
  }
  return metadata;
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
    final health = _conversationMetadataScalarText(
      languageServiceStatus['capabilityHealth'],
    );
    final missing = _conversationMetadataScalarText(
      languageServiceStatus['missingCapabilityCount'],
    );
    final blocked = _conversationMetadataScalarText(
      languageServiceStatus['blockedCapabilityCount'],
    );
    final cacheLookups = _conversationMetadataScalarText(
      languageServiceStatus['cacheLookupCount'],
    );
    final cacheHitRate = _conversationMetadataScalarText(
      languageServiceStatus['cacheLookupHitRate'],
    );
    final cacheSummary = cacheLookups == null && cacheHitRate == null
        ? ''
        : ', cacheLookups=${cacheLookups ?? 'unknown'}, '
              'cacheHitRate=${cacheHitRate ?? 'unknown'}';
    lines.add(
      'languageServiceStatus: severity=${severity ?? 'unknown'}, '
      'syntaxReady=${syntaxReady ?? 'unknown'}, '
      'semanticReady=${semanticReady ?? 'unknown'}, '
      'health=${health ?? 'unknown'}, '
      'missing=${missing ?? 'unknown'}, '
      'blocked=${blocked ?? 'unknown'}$cacheSummary',
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
