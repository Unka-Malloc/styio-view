import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent coding dispatch plan previews Styio skills and provider TODOs', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _styioContext,
    );

    final emptyPlan = controller.previewDispatchPlan();
    expect(emptyPlan.ready, isFalse);
    expect(emptyPlan.issueCodes, contains('agent.prompt.empty'));

    controller.updatePrompt('Refactor this Styio diagnostic flow.');
    final plan = controller.previewDispatchPlan();
    final json = plan.toJson();
    final providerJson = json['provider']! as Map<String, Object?>;
    final toolsJson = json['tools']! as Map<String, Object?>;
    final toolPermissionsJson =
        json['toolPermissions']! as Map<String, Object?>;
    final skillsJson = json['skills']! as Map<String, Object?>;

    expect(plan.status, AgentCodingDispatchStatus.ready);
    expect(plan.ready, isTrue);
    expect(plan.activeSkillIds.first, 'styio-language-service-truth');
    expect(plan.activeSkillIds, contains('styio-agent-command-loop'));
    expect(
      plan.todoItems,
      contains(
        'Attach provider execution resolution so Agent Surface can report endpoint health before autonomous provider requests.',
      ),
    );
    expect(plan.readiness.todoItems.join('\n'), isNot(contains('TODO:')));
    expect(json['status'], 'ready');
    expect(json['promptReady'], isTrue);
    expect(json['promptPreview'], 'Refactor this Styio diagnostic flow.');
    expect(providerJson['profileId'], 'default-web');
    expect(providerJson['kind'], 'local_only_fallback');
    expect(toolsJson['toolIds'], contains('readWorkspaceFile'));
    expect(toolsJson['toolIds'], contains('previewWorkspaceEdit'));
    expect(toolsJson['todoItems'], isA<List<Object?>>());
    expect(toolPermissionsJson['status'], 'review_required');
    expect(toolPermissionsJson['reviewToolIds'], contains('runIdeCommand'));
    expect(
      toolPermissionsJson['allowedToolIds'],
      contains('readWorkspaceFile'),
    );
    expect(plan.toolPermissionPlan.requiresReview, isTrue);
    expect(plan.toolPermissionPlan.blocksDispatch, isFalse);
    expect(
      skillsJson['activeSkillIds'],
      contains('styio-language-service-truth'),
    );
    expect(json.keys, isNot(contains('uiBindingTodo')));
    expect(
      plan.todoItems.join('\n'),
      isNot(contains('Agent Surface provider picker')),
    );
  });

  test('agent coding dispatch plan blocks unresolved execution routes', () {
    const resolution = AgentProviderExecutionResolution(
      profileId: 'blocked-provider',
      status: AgentProviderExecutionResolutionStatus.blocked,
      endpoints: <AgentProviderEndpointReadiness>[],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _styioContext,
      providerExecutionResolution: resolution,
    );

    controller.updatePrompt('Try a provider-backed change.');
    final plan = controller.previewDispatchPlan();
    final json = plan.toJson();

    expect(plan.status, AgentCodingDispatchStatus.blocked);
    expect(plan.ready, isFalse);
    expect(plan.blockingIssueCodes, contains('agent.provider.route.blocked'));
    expect(json['providerExecution'], isA<Map<String, Object?>>());
    expect(
      json['blockingIssueCodes'],
      contains('agent.provider.route.blocked'),
    );
    expect(
      plan.todoItems,
      contains(
        'Resolve provider credentials, endpoint reachability, or route execution before dispatching agent coding requests.',
      ),
    );
  });
}

AgentSessionContext _styioContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}
