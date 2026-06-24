import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_route_executor.dart';
import 'agent_session_context.dart';
import 'agent_tool_permission.dart';
import 'agent_tool_registry.dart';

enum AgentCodingDispatchStatus { ready, blocked }

extension AgentCodingDispatchStatusX on AgentCodingDispatchStatus {
  String get wireValue => switch (this) {
    AgentCodingDispatchStatus.ready => 'ready',
    AgentCodingDispatchStatus.blocked => 'blocked',
  };
}

class AgentCodingDispatchPlan {
  const AgentCodingDispatchPlan({
    required this.status,
    required this.profileId,
    required this.profileDisplayName,
    required this.providerAdapterId,
    required this.providerKind,
    required this.providerSupportsCodePatch,
    required this.endpoint,
    required this.fallbackEndpointCount,
    required this.readiness,
    required this.activeSkillIds,
    required this.promptLength,
    required this.promptPreview,
    required this.attachmentCount,
    required this.conversationTurnCount,
    required this.toolSelection,
    required this.toolPermissionPlan,
    required this.todoItems,
    this.providerSelectionPlan,
    this.providerExecutionResolution,
  });

  factory AgentCodingDispatchPlan.fromContext({
    required AgentPromptProfile profile,
    required AgentProviderAdapter adapter,
    required AgentSessionContext context,
    required AgentCodingExecutionReadiness readiness,
    required String prompt,
    required int attachmentCount,
    required int conversationTurnCount,
    AgentToolRegistry? toolRegistry,
    Iterable<AgentToolPermissionRule> toolPermissionRules =
        const <AgentToolPermissionRule>[],
    AgentProviderSelectionPlan? providerSelectionPlan,
    AgentProviderExecutionResolution? providerExecutionResolution,
  }) {
    final todos = <String>{
      ...readiness.todoItems,
      if (providerSelectionPlan != null &&
          providerSelectionPlan.todo.isNotEmpty)
        providerSelectionPlan.todo,
    };
    final toolSelection = (toolRegistry ?? AgentToolRegistry())
        .selectForProfile(profile: profile, providerKind: adapter.kind);
    final toolPermissionPlan = AgentToolPermissionPlan.fromSelection(
      toolSelection,
      rules: toolPermissionRules,
    );
    todos.addAll(toolSelection.todoItems);
    todos.addAll(toolPermissionPlan.todoItems);
    final canDispatch =
        readiness.canDispatchProviderRequest &&
        !toolPermissionPlan.blocksDispatch;
    return AgentCodingDispatchPlan(
      status: canDispatch
          ? AgentCodingDispatchStatus.ready
          : AgentCodingDispatchStatus.blocked,
      profileId: profile.profileId,
      profileDisplayName: profile.displayName,
      providerAdapterId: adapter.adapterId,
      providerKind: adapter.kind,
      providerSupportsCodePatch: adapter.supportsCodePatch,
      endpoint: profile.endpoint,
      fallbackEndpointCount: profile.fallbackEndpoints.length,
      readiness: readiness,
      activeSkillIds: context.skills.activeSkillIds,
      promptLength: prompt.length,
      promptPreview: _promptPreview(prompt),
      attachmentCount: attachmentCount,
      conversationTurnCount: conversationTurnCount,
      toolSelection: toolSelection,
      toolPermissionPlan: toolPermissionPlan,
      providerSelectionPlan: providerSelectionPlan,
      providerExecutionResolution: providerExecutionResolution,
      todoItems: List<String>.unmodifiable(todos),
    );
  }

  final AgentCodingDispatchStatus status;
  final String profileId;
  final String profileDisplayName;
  final String providerAdapterId;
  final AgentProviderKind providerKind;
  final bool providerSupportsCodePatch;
  final AgentProviderEndpoint endpoint;
  final int fallbackEndpointCount;
  final AgentCodingExecutionReadiness readiness;
  final List<String> activeSkillIds;
  final int promptLength;
  final String promptPreview;
  final int attachmentCount;
  final int conversationTurnCount;
  final AgentToolSelection toolSelection;
  final AgentToolPermissionPlan toolPermissionPlan;
  final AgentProviderSelectionPlan? providerSelectionPlan;
  final AgentProviderExecutionResolution? providerExecutionResolution;
  final List<String> todoItems;

  bool get ready => status == AgentCodingDispatchStatus.ready;

  List<String> get issueCodes {
    return <String>[...readiness.issueCodes, ...toolPermissionPlan.issueCodes];
  }

  List<String> get blockingIssueCodes {
    return <String>[
      ...readiness.issues
          .where((issue) => issue.isBlocking)
          .map((issue) => issue.code),
      ...toolPermissionPlan.blockingIssueCodes,
    ];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'promptReady': promptLength > 0,
      'promptLength': promptLength,
      if (promptPreview.isNotEmpty) 'promptPreview': promptPreview,
      'attachmentCount': attachmentCount,
      'conversationTurnCount': conversationTurnCount,
      'provider': <String, Object?>{
        'profileId': profileId,
        'displayName': profileDisplayName,
        'adapterId': providerAdapterId,
        'kind': providerKind.wireValue,
        'supportsCodePatch': providerSupportsCodePatch,
        'fallbackEndpointCount': fallbackEndpointCount,
        'endpoint': endpoint.toJson(),
      },
      'readiness': readiness.toJson(),
      'issueCodes': issueCodes,
      'blockingIssueCodes': blockingIssueCodes,
      if (providerSelectionPlan != null)
        'providerSelection': providerSelectionPlan!.toJson(),
      if (providerExecutionResolution != null)
        'providerExecution': providerExecutionResolution!.toJson(),
      'tools': toolSelection.toJson(),
      'toolPermissions': toolPermissionPlan.toJson(),
      'skills': <String, Object?>{
        'activeSkillCount': activeSkillIds.length,
        'activeSkillIds': activeSkillIds,
      },
      'todoItems': todoItems,
    };
  }
}

String _promptPreview(String prompt) {
  final normalized = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 160) {
    return normalized;
  }
  return '${normalized.substring(0, 157)}...';
}
