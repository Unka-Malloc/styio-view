import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../view_ide/backend_toolchain/adapter_contracts.dart';
import '../../view_ide/agent/agent.dart';
import '../../view_ide/environment/configuration/configuration.dart';
import '../../view_ide/module_host/module_definition.dart';
import '../../view_ide/module_host/module_manifest.dart';
import '../../view_ide/platform/platform_target.dart';
import '../native_tool_result_summary.dart';
import '../platform/viewport_profile.dart';
import 'agent_activity_history_surface.dart';

class AgentSurface extends StatelessWidget {
  const AgentSurface({
    super.key,
    required this.platformTarget,
    required this.viewportProfile,
    required this.visibleModules,
    required this.adapterCapabilities,
    required this.sessionContext,
    required this.codingController,
    required this.onApplyPendingPatch,
    required this.onSaveProviderProfile,
    this.onApplyWorkspaceRevertPlan,
    this.onApplyAgentWorkspacePatch,
    this.workspaceSnapshotService,
    this.onRunAgentExtensionTool,
    this.extensionToolExecutionRegistry,
    this.onApplyIdeCommandSuggestion,
    this.onResolveIdeCommandResult,
    this.onMountSavedProviderProfile,
    this.activityHistory,
  });

  final PlatformTarget platformTarget;
  final ViewportProfile viewportProfile;
  final List<ModuleDefinition> visibleModules;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;
  final AgentSessionContext sessionContext;
  final AgentCodingSessionController codingController;
  final Future<void> Function() onApplyPendingPatch;
  final Future<void> Function()? onApplyWorkspaceRevertPlan;
  final AgentWorkspacePatchToolRunner? onApplyAgentWorkspacePatch;
  final AgentWorkspaceSnapshotService? workspaceSnapshotService;
  final AgentExtensionToolRunner? onRunAgentExtensionTool;
  final ExtensionAgentToolExecutionRegistry? extensionToolExecutionRegistry;
  final Future<bool> Function(AgentIdeCommandSuggestion suggestion)?
  onApplyIdeCommandSuggestion;
  final AgentCommandResultContext? Function(
    AgentIdeCommandSuggestion suggestion,
  )?
  onResolveIdeCommandResult;
  final Future<void> Function(AgentPromptProfile profile, {String? bearerToken})
  onSaveProviderProfile;
  final Future<void> Function(String profileKey)? onMountSavedProviderProfile;
  final AgentCodingSessionHistory? activityHistory;

  @override
  Widget build(BuildContext context) {
    final agentModules = visibleModules
        .where(
          (module) => switch (module.manifest.slot) {
            ModuleSlot.agentSurface || ModuleSlot.cloudRuntime => true,
            _ => false,
          },
        )
        .toList(growable: false);
    final providerRoute = _providerRouteForPlatform(platformTarget);

    return Card(
      key: ValueKey('agent-surface-${viewportProfile.label.toLowerCase()}'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Agent Surface',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '${platformTarget.label} agent route aligned to the ${viewportProfile.label.toLowerCase()} shell.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              _AgentProviderProfileSection(
                platformTarget: platformTarget,
                controller: codingController,
                savedProviderProfiles:
                    sessionContext.agent.savedProviderProfiles,
                onSaveProviderProfile: onSaveProviderProfile,
                onMountSavedProviderProfile: onMountSavedProviderProfile,
              ),
              const SizedBox(height: 14),
              _AgentRuntimeSection(controller: codingController),
              const SizedBox(height: 14),
              if (viewportProfile.isMobile) ...[
                _AgentSection(
                  title: 'Provider Route',
                  body:
                      '$providerRoute. Mobile and narrow Web keep the same provider contract, but compress the presentation into a single vertical stack.',
                  accent: const Color(0xFFE1E8F5),
                ),
                const SizedBox(height: 12),
                const _AgentSection(
                  title: 'Context Injection',
                  body:
                      'Current file, selection, diagnostics, and runtime context stay as separate injection channels for M6.',
                  accent: Color(0xFFEDE6D9),
                ),
                const SizedBox(height: 12),
                _AgentContextSection(context: sessionContext),
                const SizedBox(height: 12),
                _AgentSkillSection(context: sessionContext),
                const SizedBox(height: 12),
                _AgentPromptSection(
                  platformTarget: platformTarget,
                  controller: codingController,
                  sessionContext: sessionContext,
                  onApplyPendingPatch: onApplyPendingPatch,
                  onApplyWorkspaceRevertPlan: onApplyWorkspaceRevertPlan,
                  onApplyAgentWorkspacePatch: onApplyAgentWorkspacePatch,
                  workspaceSnapshotService: workspaceSnapshotService,
                  onRunAgentExtensionTool: onRunAgentExtensionTool,
                  extensionToolExecutionRegistry:
                      extensionToolExecutionRegistry,
                  onApplyIdeCommandSuggestion: onApplyIdeCommandSuggestion,
                  onResolveIdeCommandResult: onResolveIdeCommandResult,
                ),
                _AgentActivityHistoryBinding(
                  controller: codingController,
                  activityHistory: activityHistory,
                  topGap: 12,
                  onRestorePrompt: codingController.updatePrompt,
                ),
                const SizedBox(height: 12),
                _AdapterSection(adapterCapabilities: adapterCapabilities),
                const SizedBox(height: 12),
                _AgentModuleSection(modules: agentModules),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _AgentSection(
                        title: 'Provider Route',
                        body:
                            '$providerRoute. Desktop and wide Web keep the prompt/profile surface adjacent to runtime panels while sharing the same adapter contract.',
                        accent: const Color(0xFFE1E8F5),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: _AgentSection(
                        title: 'Context Injection',
                        body:
                            'Current file, selection, diagnostics, and runtime context remain independent channels so agent prompts do not collapse language-service boundaries.',
                        accent: Color(0xFFEDE6D9),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AgentContextSection(context: sessionContext),
                const SizedBox(height: 14),
                _AgentSkillSection(context: sessionContext),
                const SizedBox(height: 14),
                _AgentPromptSection(
                  platformTarget: platformTarget,
                  controller: codingController,
                  sessionContext: sessionContext,
                  onApplyPendingPatch: onApplyPendingPatch,
                  onApplyWorkspaceRevertPlan: onApplyWorkspaceRevertPlan,
                  onApplyAgentWorkspacePatch: onApplyAgentWorkspacePatch,
                  workspaceSnapshotService: workspaceSnapshotService,
                  onRunAgentExtensionTool: onRunAgentExtensionTool,
                  extensionToolExecutionRegistry:
                      extensionToolExecutionRegistry,
                  onApplyIdeCommandSuggestion: onApplyIdeCommandSuggestion,
                  onResolveIdeCommandResult: onResolveIdeCommandResult,
                ),
                _AgentActivityHistoryBinding(
                  controller: codingController,
                  activityHistory: activityHistory,
                  topGap: 14,
                  onRestorePrompt: codingController.updatePrompt,
                ),
                const SizedBox(height: 14),
                _AdapterSection(adapterCapabilities: adapterCapabilities),
                const SizedBox(height: 14),
                _AgentModuleSection(modules: agentModules),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentCodingLoopGateSummary extends StatelessWidget {
  const _AgentCodingLoopGateSummary({
    required this.executionReadiness,
    required this.changeReviewGate,
    required this.autonomyPolicy,
    required this.loopGuard,
  });

  final AgentCodingExecutionReadiness executionReadiness;
  final AgentCodingChangeReviewGate changeReviewGate;
  final AgentCodingAutonomyPolicy autonomyPolicy;
  final AgentCodingLoopGuard loopGuard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requiresReview = changeReviewGate.requiresUserReview;
    final canApplyPreview = changeReviewGate.canApplyPreview;
    final autonomyBlocked =
        autonomyPolicy.mode == AgentCodingAutonomyMode.blocked;
    final loopGuardBlocked = loopGuard.blocked;
    final loopGuardAttention =
        loopGuard.status == AgentCodingLoopGuardStatus.attention;
    final statusColor = requiresReview
        ? theme.colorScheme.primary
        : loopGuardBlocked
        ? theme.colorScheme.error
        : loopGuardAttention
        ? theme.colorScheme.tertiary
        : autonomyBlocked
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Coding loop gate',
              style: theme.textTheme.labelLarge?.copyWith(color: statusColor),
            ),
            const SizedBox(height: 4),
            Text(
              'Execution readiness: ${executionReadiness.status.wireValue}',
              style: theme.textTheme.bodySmall,
            ),
            if (executionReadiness.issues.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final issue in executionReadiness.issues.take(4))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${issue.code}: ${issue.message}',
                    key: ValueKey('agent-coding-readiness-issue-${issue.code}'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (executionReadiness.issues.length > 4)
                Text(
                  '+${executionReadiness.issues.length - 4} more readiness issue(s).',
                  key: const ValueKey('agent-coding-readiness-issue-overflow'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
            Text(
              'Change review: ${changeReviewGate.status.wireValue}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Autonomy policy: ${autonomyPolicy.mode.wireValue}',
              key: const ValueKey('agent-autonomy-policy-status'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: autonomyBlocked ? theme.colorScheme.error : null,
              ),
            ),
            Text(
              'Loop guard: ${loopGuard.status.wireValue}',
              key: const ValueKey('agent-loop-guard-status'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: loopGuardBlocked
                    ? theme.colorScheme.error
                    : loopGuardAttention
                    ? theme.colorScheme.tertiary
                    : null,
              ),
            ),
            if (loopGuard.attentionReasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final reason in loopGuard.attentionReasons.take(3))
                Text(
                  reason,
                  key: ValueKey('agent-loop-guard-attention-$reason'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                  ),
                ),
            ],
            if (loopGuard.blockingReasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final reason in loopGuard.blockingReasons.take(3))
                Text(
                  reason,
                  key: ValueKey('agent-loop-guard-reason-$reason'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
            if (autonomyPolicy.reasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final reason in autonomyPolicy.reasons.take(3))
                Text(
                  reason,
                  key: ValueKey(
                    'agent-autonomy-policy-reason-${autonomyPolicy.reasons.indexOf(reason)}',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (requiresReview) ...[
              const SizedBox(height: 4),
              Text(
                'Review required before applying agent changes.',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                canApplyPreview
                    ? 'Validation waits until the reviewed patch is applied.'
                    : 'Validation blocked until a reviewable patch preview exists.',
                style: theme.textTheme.bodySmall,
              ),
              if (changeReviewGate.reviewSurfaceActionIds.isNotEmpty)
                Text(
                  'Review actions: ${changeReviewGate.reviewSurfaceActionIds.join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentCodingValidationPlanSummary extends StatelessWidget {
  const _AgentCodingValidationPlanSummary({
    required this.validationPlan,
    required this.validationResult,
    required this.validationPipeline,
    required this.applyingIdeCommand,
    this.onApplyCommand,
  });

  final AgentCodingValidationPlan validationPlan;
  final AgentCodingValidationResult validationResult;
  final AgentCodingValidationPipeline validationPipeline;
  final bool applyingIdeCommand;
  final void Function(AgentIdeCommandSuggestion suggestion)? onApplyCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commandPlanText = validationPlan.commandPlans
        .map((commandPlan) => commandPlan.commandId)
        .join(' -> ');
    final runnableCommandPlans = validationPlan.commandPlans
        .where((commandPlan) => !commandPlan.requiresInput)
        .take(5)
        .toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Validation plan: ${validationPlan.status.wireValue}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: validationPlan.shouldRun
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(validationPlan.reason, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Validation result: ${validationResult.status.wireValue}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'Validation pipeline: ${validationPipeline.status.wireValue}'
              ' (${validationPipeline.progressNumerator}/${validationPipeline.progressDenominator})',
              style: theme.textTheme.bodySmall,
            ),
            if (validationPipeline.nextCommandId != null)
              Text(
                'Next validation command: ${validationPipeline.nextCommandId}',
                style: theme.textTheme.bodySmall,
              ),
            if (validationResult.missingCommandIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Missing validation commands: ${validationResult.missingCommandIds.join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (commandPlanText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Command plan: $commandPlanText',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (validationPipeline.nextCommandId != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const ValueKey('agent-validation-continue-next-command'),
                onPressed: applyingIdeCommand || onApplyCommand == null
                    ? null
                    : () => onApplyCommand!(
                        AgentIdeCommandSuggestion(
                          commandId: validationPipeline.nextCommandId!,
                          reason:
                              'Continue the agent coding validation pipeline.',
                        ),
                      ),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  'Continue Validation: ${validationPipeline.nextCommandId}',
                ),
              ),
            ],
            if (runnableCommandPlans.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final commandPlan in runnableCommandPlans)
                    OutlinedButton(
                      key: ValueKey(
                        'agent-validation-command-${commandPlan.commandId}',
                      ),
                      onPressed: applyingIdeCommand || onApplyCommand == null
                          ? null
                          : () => onApplyCommand!(
                              AgentIdeCommandSuggestion(
                                commandId: commandPlan.commandId,
                                reason:
                                    'Run ${commandPlan.phase} validation after agent patch application.',
                              ),
                            ),
                      child: Text(commandPlan.commandId),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _recoveryValidationSummary(AgentCodingSessionHistory history) {
  if (history.records.isEmpty) {
    return null;
  }
  final latest = history.records.first;
  final validationResult = _agentSurfaceMetadataObject(
    latest.metadata['validationResult'],
  );
  final validationPipeline = _agentSurfaceMetadataObject(
    latest.metadata['validationPipeline'],
  );
  if (validationResult.isEmpty && validationPipeline.isEmpty) {
    return null;
  }
  final resultStatus = validationResult['status'] as String? ?? 'unknown';
  final pipelineStatus = validationPipeline['status'] as String? ?? 'unknown';
  final progressNumerator = validationPipeline['progressNumerator'] as int?;
  final progressDenominator = validationPipeline['progressDenominator'] as int?;
  final nextCommandId = validationPipeline['nextCommandId'] as String?;
  final progress = progressNumerator == null || progressDenominator == null
      ? ''
      : ' $progressNumerator/$progressDenominator';
  final next = nextCommandId == null ? '' : ' · next $nextCommandId';
  return 'Last validation: $resultStatus · pipeline $pipelineStatus$progress$next';
}

String? _recoveryValidationNextCommandId(AgentCodingSessionHistory history) {
  if (history.records.isEmpty) {
    return null;
  }
  final latest = history.records.first;
  final validationPipeline = _agentSurfaceMetadataObject(
    latest.metadata['validationPipeline'],
  );
  final nextCommandId = validationPipeline['nextCommandId'] as String?;
  if (nextCommandId == null || nextCommandId.trim().isEmpty) {
    return null;
  }
  return nextCommandId;
}

List<String> _recoveryValidationFailedCommandIds(
  AgentCodingSessionHistory history,
) {
  if (history.records.isEmpty) {
    return const <String>[];
  }
  final latest = history.records.first;
  final validationResult = _agentSurfaceMetadataObject(
    latest.metadata['validationResult'],
  );
  final failedCommandIds = validationResult['failedCommandIds'];
  if (failedCommandIds is Iterable) {
    return failedCommandIds.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

String? _recoveryValidationFailureEvidence(AgentCodingSessionHistory history) {
  if (history.records.isEmpty) {
    return null;
  }
  final latest = history.records.first;
  final failedResults = latest.metadata['validationFailedCommandResults'];
  if (failedResults is! Iterable || failedResults.isEmpty) {
    return null;
  }
  final firstResult = _agentSurfaceMetadataObject(failedResults.first);
  final commandId = firstResult['commandId'] as String?;
  final message = firstResult['message'] as String?;
  if (commandId == null || message == null || message.trim().isEmpty) {
    return null;
  }
  return 'Failure evidence: $commandId · $message';
}

String _recoveryAuditFixPrompt(AgentCodingSessionAuditSummary summary) {
  final parts = <String>[
    'Resolve the latest agent recovery audit before retrying provider recovery.',
  ];
  if (summary.permissionDeniedToolIds.isNotEmpty) {
    parts.add(
      'Permission denied tools: ${summary.permissionDeniedToolIds.join(', ')}.',
    );
  }
  if (summary.reviewDeniedCallIds.isNotEmpty) {
    parts.add(
      'Review denied tool calls: ${summary.reviewDeniedCallIds.join(', ')}.',
    );
  }
  if (summary.blockingIssueCodes.isNotEmpty) {
    parts.add('Blocking issues: ${summary.blockingIssueCodes.join(', ')}.');
  }
  parts.add(
    'Revise the requested tool chain or propose a safer manual recovery path.',
  );
  return parts.join(' ');
}

Map<String, Object?> _agentSurfaceMetadataObject(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        result[key] = entry.value;
      }
    }
    return result;
  }
  return const <String, Object?>{};
}

class _AgentActivityHistoryBinding extends StatelessWidget {
  const _AgentActivityHistoryBinding({
    required this.controller,
    required this.topGap,
    this.activityHistory,
    this.onRestorePrompt,
  });

  final AgentCodingSessionController controller;
  final AgentCodingSessionHistory? activityHistory;
  final double topGap;
  final void Function(String prompt)? onRestorePrompt;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final history = activityHistory ?? controller.sessionHistorySnapshot;
        if (activityHistory == null && history.records.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topGap),
            AgentActivityHistorySurface(
              history: history,
              onRestorePrompt: onRestorePrompt == null
                  ? null
                  : (record) => onRestorePrompt!(record.prompt),
            ),
          ],
        );
      },
    );
  }
}

class _AgentProviderProfileSection extends StatefulWidget {
  const _AgentProviderProfileSection({
    required this.platformTarget,
    required this.controller,
    required this.savedProviderProfiles,
    required this.onSaveProviderProfile,
    this.onMountSavedProviderProfile,
  });

  final PlatformTarget platformTarget;
  final AgentCodingSessionController controller;
  final List<AgentPromptProfileManifestEntry> savedProviderProfiles;
  final Future<void> Function(AgentPromptProfile profile, {String? bearerToken})
  onSaveProviderProfile;
  final Future<void> Function(String profileKey)? onMountSavedProviderProfile;

  @override
  State<_AgentProviderProfileSection> createState() =>
      _AgentProviderProfileSectionState();
}

class _AgentRuntimeSection extends StatelessWidget {
  const _AgentRuntimeSection({required this.controller});

  final AgentCodingSessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final snapshot = controller.agentRegistrySnapshot;
        final activeAgent = snapshot.activeAgent;
        final visibleAgents = snapshot.agents
            .where((agent) => !agent.hidden)
            .toList(growable: false);
        return Container(
          key: const ValueKey('agent-runtime-section'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFE8E0D0),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agent Runtime', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                activeAgent == null
                    ? 'No active coding agent is selected.'
                    : 'Active: ${activeAgent.displayName} · ${activeAgent.mode.wireValue} · max ${activeAgent.maxSteps ?? 0} step(s).',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final agent in visibleAgents)
                    ChoiceChip(
                      key: ValueKey('agent-runtime-${agent.agentId}'),
                      label: Text(agent.displayName),
                      selected: snapshot.activeAgentId == agent.agentId,
                      onSelected: (_) {
                        controller.selectAgentRuntime(agent.agentId);
                      },
                    ),
                ],
              ),
              if (activeAgent?.capabilities.isNotEmpty ?? false) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final capability in activeAgent!.capabilities)
                      Chip(label: Text(capability)),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AgentProviderProfileSectionState
    extends State<_AgentProviderProfileSection> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late final TextEditingController _fallbackBaseUrlController;
  late final TextEditingController _fallbackModelController;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _bearerTokenController;
  late Set<String> _contextChannels;
  late String _profileId;
  late AgentProviderRoute _endpointRoute;
  late String _endpointApiKeyEnvironmentName;
  late String _endpointProtocol;
  String? _endpointReasoningEffort;
  CredentialReference? _endpointCredentialReference;
  late bool _endpointRequiresCredential;
  late String _profileSignature;
  late String _lockSignature;
  String? _failureSignature;
  bool _saving = false;
  String? _mountingProfileKey;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile;
    _displayNameController = TextEditingController(text: profile.displayName);
    _baseUrlController = TextEditingController(text: profile.endpoint.baseUrl);
    _modelController = TextEditingController(text: profile.endpoint.model);
    _fallbackBaseUrlController = TextEditingController(
      text: profile.fallbackEndpoints.isEmpty
          ? ''
          : profile.fallbackEndpoints.first.baseUrl,
    );
    _fallbackModelController = TextEditingController(
      text: profile.fallbackEndpoints.isEmpty
          ? ''
          : profile.fallbackEndpoints.first.model,
    );
    _systemPromptController = TextEditingController(text: profile.systemPrompt);
    _bearerTokenController = TextEditingController();
    _contextChannels = profile.contextChannels.toSet();
    _profileId = profile.profileId;
    _setEndpointContract(profile.endpoint);
    _profileSignature = _profileSignatureFor(profile);
    _lockSignature = _lockSignatureFor(widget.controller);
    _failureSignature = _failureSignatureFor(
      widget.controller.lastProviderFailure,
    );
    widget.controller.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(covariant _AgentProviderProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _lockSignature = _lockSignatureFor(widget.controller);
      _setProfileFields(widget.controller.profile);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _displayNameController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _fallbackBaseUrlController.dispose();
    _fallbackModelController.dispose();
    _systemPromptController.dispose();
    _bearerTokenController.dispose();
    super.dispose();
  }

  void _syncFromController() {
    final profile = widget.controller.profile;
    final profileSignature = _profileSignatureFor(profile);
    final failureSignature = _failureSignatureFor(
      widget.controller.lastProviderFailure,
    );
    final lockSignature = _lockSignatureFor(widget.controller);
    if (_profileSignature == profileSignature &&
        _failureSignature == failureSignature &&
        _lockSignature == lockSignature) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (_profileSignature != profileSignature) {
        _setProfileFields(profile);
        _errorMessage = null;
      }
      _failureSignature = failureSignature;
      _lockSignature = lockSignature;
    });
  }

  void _setProfileFields(AgentPromptProfile profile) {
    _profileSignature = _profileSignatureFor(profile);
    _displayNameController.text = profile.displayName;
    _baseUrlController.text = profile.endpoint.baseUrl;
    _modelController.text = profile.endpoint.model;
    _fallbackBaseUrlController.text = profile.fallbackEndpoints.isEmpty
        ? ''
        : profile.fallbackEndpoints.first.baseUrl;
    _fallbackModelController.text = profile.fallbackEndpoints.isEmpty
        ? ''
        : profile.fallbackEndpoints.first.model;
    _systemPromptController.text = profile.systemPrompt;
    _bearerTokenController.clear();
    _contextChannels = profile.contextChannels.toSet();
    _profileId = profile.profileId;
    _setEndpointContract(profile.endpoint);
  }

  String _profileSignatureFor(AgentPromptProfile profile) {
    return [
      profile.profileId,
      profile.displayName,
      profile.endpoint.route.wireValue,
      profile.endpoint.baseUrl,
      profile.endpoint.model,
      profile.endpoint.apiKeyEnvironmentName,
      profile.endpoint.protocol,
      profile.endpoint.reasoningEffort ?? '',
      profile.endpoint.credentialReference?.key.stableId ?? '',
      profile.endpoint.credentialReference?.kind.wireValue ?? '',
      profile.endpoint.requiresCredential,
      if (profile.fallbackEndpoints.isNotEmpty)
        profile.fallbackEndpoints.first.baseUrl,
      if (profile.fallbackEndpoints.isNotEmpty)
        profile.fallbackEndpoints.first.model,
      if (profile.fallbackEndpoints.isNotEmpty)
        profile.fallbackEndpoints.first.requiresCredential,
      profile.systemPrompt,
      ...profile.contextChannels,
    ].join('\n');
  }

  void _setEndpointContract(AgentProviderEndpoint endpoint) {
    _endpointRoute = endpoint.route;
    _endpointApiKeyEnvironmentName = endpoint.apiKeyEnvironmentName;
    _endpointProtocol = endpoint.protocol;
    _endpointReasoningEffort = endpoint.reasoningEffort;
    _endpointCredentialReference = endpoint.credentialReference;
    _endpointRequiresCredential = endpoint.requiresCredential;
  }

  void _applyCodexSparkPreset() {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      widget.platformTarget,
    );
    setState(() {
      _setProfileFields(profile);
      _errorMessage = null;
    });
  }

  String? _failureSignatureFor(AgentProviderTransportException? failure) {
    if (failure == null) {
      return null;
    }
    return [
      failure.kind.name,
      failure.statusCode?.toString() ?? '',
      failure.message,
      failure.recoveryHint ?? '',
    ].join('\n');
  }

  String _lockSignatureFor(AgentCodingSessionController controller) {
    return [
      controller.sending,
      controller.applyingPatch,
      controller.applyingIdeCommand,
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerFailure = widget.controller.lastProviderFailure;
    final providerSelection = widget.controller.providerSelectionPlan;
    final executionResolution = widget.controller.providerExecutionResolution;
    final locked =
        _saving ||
        _mountingProfileKey != null ||
        widget.controller.sending ||
        widget.controller.applyingPatch ||
        widget.controller.applyingIdeCommand;
    return Container(
      key: const ValueKey('agent-provider-profile-section'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF2),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Provider Profile', style: theme.textTheme.titleMedium),
          if (providerFailure != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('agent-provider-reconfiguration-guidance'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                'Provider reconfiguration recommended: ${providerFailure.kind.name}. Review base URL, model, and bearer token, then save this provider profile.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
          if (providerSelection != null) ...[
            const SizedBox(height: 8),
            _AgentProviderSelectionStatusCard(plan: providerSelection),
          ],
          if (executionResolution != null) ...[
            const SizedBox(height: 8),
            _AgentProviderExecutionStatusCard(
              resolution: executionResolution,
              onPromoteSelectedFallback: locked
                  ? null
                  : _promoteSelectedFallback,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('agent-profile-codex-spark-preset-button'),
                onPressed: locked ? null : _applyCodexSparkPreset,
                child: const Text('Use OpenAI Codex Spark preset'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Preset requires an explicit OpenAI API key or bearer token. Vityo stores the credential through Credential DataStore and does not read Codex OAuth from the host.',
            style: theme.textTheme.bodySmall,
          ),
          if (widget.savedProviderProfiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SavedProviderProfilesSection(
              profiles: widget.savedProviderProfiles,
              activeProfileId: widget.controller.profile.profileId,
              mountingProfileKey: _mountingProfileKey,
              locked: locked,
              onMountProfile: widget.onMountSavedProviderProfile == null
                  ? null
                  : _mountSavedProviderProfile,
            ),
          ],
          if (_endpointCredentialReference != null) ...[
            const SizedBox(height: 6),
            Text(
              'Credential reference: ${_endpointCredentialReference!.key.stableId} (${_endpointCredentialReference!.kind.wireValue})',
              key: const ValueKey('agent-profile-credential-reference'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('agent-profile-save-button'),
            onPressed: locked ? null : _saveProfile,
            child: Text(_saving ? 'Saving...' : 'Save Provider Profile'),
          ),
          const SizedBox(height: 10),
          Text('Context channels', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final channel in AgentPromptProfile.defaultContextChannels)
                SizedBox(
                  width: 220,
                  child: GestureDetector(
                    key: ValueKey('agent-context-channel-$channel'),
                    behavior: HitTestBehavior.opaque,
                    onTap: locked
                        ? null
                        : () {
                            final selected = !_contextChannels.contains(
                              channel,
                            );
                            setState(() {
                              if (selected) {
                                _contextChannels.add(channel);
                              } else {
                                _contextChannels.remove(channel);
                              }
                            });
                          },
                    child: AbsorbPointer(
                      child: FilterChip(
                        label: Text(channel),
                        selected: _contextChannels.contains(channel),
                        onSelected: locked ? null : (_) {},
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-display-name-input'),
            controller: _displayNameController,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-base-url-input'),
            controller: _baseUrlController,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'OpenAI-compatible base URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-model-input'),
            controller: _modelController,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-fallback-base-url-input'),
            controller: _fallbackBaseUrlController,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'Fallback cloud base URL (optional)',
              helperText:
                  'Used when the primary endpoint is blocked or unavailable.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-fallback-model-input'),
            controller: _fallbackModelController,
            enabled: !locked,
            decoration: const InputDecoration(
              labelText: 'Fallback cloud model (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-system-prompt-input'),
            controller: _systemPromptController,
            enabled: !locked,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'System prompt',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: const ValueKey('agent-profile-bearer-token-input'),
            controller: _bearerTokenController,
            enabled: !locked,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'OpenAI API key / bearer token (optional)',
              helperText:
                  'Stored in Credential DataStore, not in profile JSON.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    final fallbackBaseUrl = _fallbackBaseUrlController.text.trim();
    final fallbackModel = _fallbackModelController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _errorMessage = 'Base URL and model are required.';
      });
      return;
    }
    if (!_isValidProviderBaseUrl(baseUrl)) {
      setState(() {
        _errorMessage =
            'Base URL must be an http(s) URL or root-relative path.';
      });
      return;
    }
    final hasFallback = fallbackBaseUrl.isNotEmpty || fallbackModel.isNotEmpty;
    if (hasFallback && (fallbackBaseUrl.isEmpty || fallbackModel.isEmpty)) {
      setState(() {
        _errorMessage = 'Fallback base URL and model must both be provided.';
      });
      return;
    }
    if (hasFallback && !_isValidProviderBaseUrl(fallbackBaseUrl)) {
      setState(() {
        _errorMessage =
            'Fallback base URL must be an http(s) URL or root-relative path.';
      });
      return;
    }
    if (_contextChannels.isEmpty) {
      setState(() {
        _errorMessage = 'At least one context channel is required.';
      });
      return;
    }

    final current = widget.controller.profile;
    final profile = AgentPromptProfile(
      profileId: _profileId.startsWith('default-')
          ? 'configured-agent'
          : _profileId,
      displayName: _displayNameController.text.trim().isEmpty
          ? 'Configured Agent'
          : _displayNameController.text.trim(),
      systemPrompt: _systemPromptController.text.trim().isEmpty
          ? current.systemPrompt
          : _systemPromptController.text.trim(),
      endpoint: AgentProviderEndpoint(
        route: _endpointRoute,
        baseUrl: baseUrl,
        model: model,
        apiKeyEnvironmentName: _endpointApiKeyEnvironmentName,
        protocol: _endpointProtocol,
        reasoningEffort: _endpointReasoningEffort,
        credentialReference: _endpointCredentialReference,
        requiresCredential: _requiresCredentialForBaseUrl(
          baseUrl,
          currentValue: _endpointRequiresCredential,
        ),
      ),
      fallbackEndpoints: hasFallback
          ? <AgentProviderEndpoint>[
              AgentProviderEndpoint(
                route: AgentProviderRoute.webHosted,
                baseUrl: fallbackBaseUrl,
                model: fallbackModel,
                apiKeyEnvironmentName: _endpointApiKeyEnvironmentName,
                protocol: _endpointProtocol,
                reasoningEffort: _endpointReasoningEffort,
                requiresCredential: _requiresCredentialForBaseUrl(
                  fallbackBaseUrl,
                  currentValue: current.fallbackEndpoints.isNotEmpty
                      ? current.fallbackEndpoints.first.requiresCredential
                      : false,
                ),
              ),
            ]
          : const <AgentProviderEndpoint>[],
      contextChannels: _contextChannels.toList(growable: false),
    );

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.onSaveProviderProfile(
        profile,
        bearerToken: _bearerTokenController.text,
      );
      _bearerTokenController.clear();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = sanitizeAgentError(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _promoteSelectedFallback() {
    final selected =
        widget.controller.providerExecutionResolution?.selectedEndpoint;
    if (selected == null || !selected.fallback) {
      return;
    }
    setState(() {
      _baseUrlController.text = selected.endpoint.baseUrl;
      _modelController.text = selected.endpoint.model;
      _fallbackBaseUrlController.clear();
      _fallbackModelController.clear();
      _setEndpointContract(selected.endpoint);
      _errorMessage = null;
    });
  }

  Future<void> _mountSavedProviderProfile(
    AgentPromptProfileManifestEntry profile,
  ) async {
    final mountProfile = widget.onMountSavedProviderProfile;
    if (mountProfile == null) {
      return;
    }
    setState(() {
      _mountingProfileKey = profile.key;
      _errorMessage = null;
    });
    try {
      await mountProfile(profile.key);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = sanitizeAgentError(error.toString());
      });
    } finally {
      if (mounted) {
        setState(() {
          _mountingProfileKey = null;
        });
      }
    }
  }
}

class _SavedProviderProfilesSection extends StatelessWidget {
  const _SavedProviderProfilesSection({
    required this.profiles,
    required this.activeProfileId,
    required this.locked,
    this.mountingProfileKey,
    this.onMountProfile,
  });

  final List<AgentPromptProfileManifestEntry> profiles;
  final String activeProfileId;
  final bool locked;
  final String? mountingProfileKey;
  final Future<void> Function(AgentPromptProfileManifestEntry profile)?
  onMountProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('agent-saved-provider-profiles'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.54),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saved provider profiles (${profiles.length})',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final profile in profiles) ...[
            _SavedProviderProfileTile(
              profile: profile,
              active: profile.profileId == activeProfileId,
              mounting: mountingProfileKey == profile.key,
              locked: locked,
              onMountProfile: onMountProfile,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SavedProviderProfileTile extends StatelessWidget {
  const _SavedProviderProfileTile({
    required this.profile,
    required this.active,
    required this.mounting,
    required this.locked,
    this.onMountProfile,
  });

  final AgentPromptProfileManifestEntry profile;
  final bool active;
  final bool mounting;
  final bool locked;
  final Future<void> Function(AgentPromptProfileManifestEntry profile)?
  onMountProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mountAvailable = onMountProfile != null && !active && !locked;
    return Container(
      key: ValueKey('agent-saved-provider-profile-${profile.key}'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName.isEmpty
                          ? profile.profileId
                          : profile.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.model} / ${profile.protocol} / ${profile.route}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'key: ${profile.key}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                key: ValueKey(
                  'agent-saved-provider-profile-mount-${profile.key}',
                ),
                onPressed: mountAvailable
                    ? () async {
                        await onMountProfile!(profile);
                      }
                    : null,
                child: Text(
                  active ? 'Mounted' : (mounting ? 'Mounting...' : 'Mount'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Chip(label: Text('profile ${profile.profileId}')),
              if (profile.requiresCredential)
                const Chip(label: Text('credential required')),
              if (active) const Chip(label: Text('active')),
            ],
          ),
        ],
      ),
    );
  }
}

bool _requiresCredentialForBaseUrl(
  String baseUrl, {
  required bool currentValue,
}) {
  if (currentValue) {
    return true;
  }
  final trimmed = baseUrl.trim();
  if (trimmed.isEmpty || trimmed.startsWith('/')) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return false;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host != 'localhost' && host != '127.0.0.1' && host != '::1';
}

bool _isValidProviderBaseUrl(String value) {
  final endpointUri = Uri.tryParse(value);
  final isRootRelativePath = value.startsWith('/') && !value.startsWith('//');
  final isHttpUrl =
      endpointUri != null &&
      endpointUri.hasScheme &&
      (endpointUri.scheme == 'http' || endpointUri.scheme == 'https');
  return isRootRelativePath || isHttpUrl;
}

class _AgentProviderSelectionStatusCard extends StatelessWidget {
  const _AgentProviderSelectionStatusCard({required this.plan});

  final AgentProviderSelectionPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = plan.selectedProvider;
    return Container(
      key: const ValueKey('agent-provider-selection-status'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Provider selection: ${plan.status.wireValue}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selected == null
                ? 'No provider registration currently supports this profile.'
                : 'Selected provider ${selected.displayName} (${selected.providerId}).',
            key: const ValueKey('agent-provider-selection-selected'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Candidate providers: ${plan.candidates.length}',
            key: const ValueKey('agent-provider-selection-candidates'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Executable: ${plan.executable}',
            key: const ValueKey('agent-provider-selection-executable'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (plan.credentialReadiness != null) ...[
            const SizedBox(height: 6),
            Text(
              'Credential readiness: ${plan.credentialReadiness!.wireValue}',
              key: const ValueKey(
                'agent-provider-selection-credential-readiness',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
          if (plan.executionStatus != null) ...[
            const SizedBox(height: 6),
            Text(
              'Execution status: ${plan.executionStatus!.wireValue}',
              key: const ValueKey('agent-provider-selection-execution-status'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
          if (plan.requiresCredential) ...[
            const SizedBox(height: 6),
            Text(
              'Credential required before real provider requests.',
              key: const ValueKey('agent-provider-selection-credential'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (plan.todo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              plan.todo,
              key: const ValueKey('agent-provider-selection-todo'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentProviderExecutionStatusCard extends StatelessWidget {
  const _AgentProviderExecutionStatusCard({
    required this.resolution,
    this.onPromoteSelectedFallback,
  });

  final AgentProviderExecutionResolution resolution;
  final VoidCallback? onPromoteSelectedFallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = resolution.selectedEndpoint;
    final missingRequiredCredentialEndpoints = resolution.endpoints.where(
      (endpoint) =>
          endpoint.endpoint.requiresCredential &&
          endpoint.credentialReadiness ==
              AgentProviderCredentialReadiness.unavailable,
    );
    return Container(
      key: const ValueKey('agent-provider-execution-status'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Execution status: ${resolution.status.wireValue}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selected == null
                ? 'No executable provider endpoint is available.'
                : 'Selected ${selected.fallback ? 'fallback' : 'primary'} ${selected.plan.routeKind.wireValue} endpoint: ${selected.endpoint.baseUrl}',
            key: const ValueKey('agent-provider-execution-selected'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          if (missingRequiredCredentialEndpoints.isNotEmpty) ...[
            Text(
              'Credential required: add a bearer token for endpoint(s) ${missingRequiredCredentialEndpoints.map((endpoint) => endpoint.endpointIndex).join(', ')} before using real cloud agent providers.',
              key: const ValueKey(
                'agent-provider-execution-credential-guidance',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          for (final endpoint in resolution.endpoints)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${endpoint.fallback ? 'Fallback' : 'Primary'} ${endpoint.endpointIndex}: ${endpoint.plan.routeKind.wireValue}, credential ${endpoint.credentialReadiness.wireValue}, probe ${endpoint.probeResult.status.wireValue}, executable ${endpoint.executable}',
                key: ValueKey(
                  'agent-provider-execution-endpoint-${endpoint.endpointIndex}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          if (selected != null && selected.fallback) ...[
            const SizedBox(height: 6),
            OutlinedButton(
              key: const ValueKey('agent-provider-promote-fallback-button'),
              onPressed: onPromoteSelectedFallback,
              child: const Text('Promote Selected Fallback'),
            ),
          ],
        ],
      ),
    );
  }
}

Set<String> _registeredAgentCommandIds(AgentCommandCatalogContext commands) {
  return <String>{
    for (final command in commands.persistenceCommands) command.id,
    for (final command in commands.diagnosticCommands) command.id,
    for (final command in commands.languageServiceCommands) command.id,
    for (final command in commands.sourceControlCommands) command.id,
    for (final command in commands.codingCommands) command.id,
    for (final command in commands.navigationCommands) command.id,
    for (final command in commands.refactorCommands) command.id,
    for (final command in commands.toolchainCommands) command.id,
    for (final command in commands.nativeToolCommands) command.id,
    for (final command in commands.debugCommands) command.id,
    for (final command in commands.settingsCommands) command.id,
  };
}

Map<String, bool> _agentCommandRequiresInputById(
  AgentCommandCatalogContext commands,
) {
  return <String, bool>{
    for (final command in commands.persistenceCommands)
      command.id: command.requiresInput,
    for (final command in commands.diagnosticCommands)
      command.id: command.requiresInput,
    for (final command in commands.languageServiceCommands)
      command.id: command.requiresInput,
    for (final command in commands.sourceControlCommands)
      command.id: command.requiresInput,
    for (final command in commands.codingCommands)
      command.id: command.requiresInput,
    for (final command in commands.navigationCommands)
      command.id: command.requiresInput,
    for (final command in commands.refactorCommands)
      command.id: command.requiresInput,
    for (final command in commands.toolchainCommands)
      command.id: command.requiresInput,
    for (final command in commands.nativeToolCommands)
      command.id: command.requiresInput,
    for (final command in commands.debugCommands)
      command.id: command.requiresInput,
    for (final command in commands.settingsCommands)
      command.id: command.requiresInput,
  };
}

Map<String, String> _agentCommandInputLabelById(
  AgentCommandCatalogContext commands,
) {
  return <String, String>{
    for (final command in commands.persistenceCommands)
      command.id: command.inputLabel,
    for (final command in commands.diagnosticCommands)
      command.id: command.inputLabel,
    for (final command in commands.languageServiceCommands)
      command.id: command.inputLabel,
    for (final command in commands.sourceControlCommands)
      command.id: command.inputLabel,
    for (final command in commands.codingCommands)
      command.id: command.inputLabel,
    for (final command in commands.navigationCommands)
      command.id: command.inputLabel,
    for (final command in commands.refactorCommands)
      command.id: command.inputLabel,
    for (final command in commands.toolchainCommands)
      command.id: command.inputLabel,
    for (final command in commands.nativeToolCommands)
      command.id: command.inputLabel,
    for (final command in commands.debugCommands)
      command.id: command.inputLabel,
    for (final command in commands.settingsCommands)
      command.id: command.inputLabel,
  };
}

Map<String, String> _agentCommandInputContractById(
  AgentCommandCatalogContext commands,
) {
  return <String, String>{
    for (final command in commands.persistenceCommands)
      command.id: command.inputContract,
    for (final command in commands.diagnosticCommands)
      command.id: command.inputContract,
    for (final command in commands.languageServiceCommands)
      command.id: command.inputContract,
    for (final command in commands.sourceControlCommands)
      command.id: command.inputContract,
    for (final command in commands.codingCommands)
      command.id: command.inputContract,
    for (final command in commands.navigationCommands)
      command.id: command.inputContract,
    for (final command in commands.refactorCommands)
      command.id: command.inputContract,
    for (final command in commands.toolchainCommands)
      command.id: command.inputContract,
    for (final command in commands.nativeToolCommands)
      command.id: command.inputContract,
    for (final command in commands.debugCommands)
      command.id: command.inputContract,
    for (final command in commands.settingsCommands)
      command.id: command.inputContract,
  };
}

Map<String, List<String>> _agentCommandInputExamplesById(
  AgentCommandCatalogContext commands,
) {
  return <String, List<String>>{
    for (final command in commands.persistenceCommands)
      command.id: command.inputExamples,
    for (final command in commands.diagnosticCommands)
      command.id: command.inputExamples,
    for (final command in commands.languageServiceCommands)
      command.id: command.inputExamples,
    for (final command in commands.sourceControlCommands)
      command.id: command.inputExamples,
    for (final command in commands.codingCommands)
      command.id: command.inputExamples,
    for (final command in commands.navigationCommands)
      command.id: command.inputExamples,
    for (final command in commands.refactorCommands)
      command.id: command.inputExamples,
    for (final command in commands.toolchainCommands)
      command.id: command.inputExamples,
    for (final command in commands.nativeToolCommands)
      command.id: command.inputExamples,
    for (final command in commands.debugCommands)
      command.id: command.inputExamples,
    for (final command in commands.settingsCommands)
      command.id: command.inputExamples,
  };
}

bool _agentCommandMissingRequiredInput(
  String commandId,
  String? input,
  Map<String, bool> commandRequiresInputById,
) {
  if (commandRequiresInputById[commandId] != true) {
    return false;
  }
  return input == null || input.trim().isEmpty;
}

Map<String, _AgentCommandReadinessStatus> _commandReadinessById(
  AgentCommandCatalogContext commands,
) {
  return <String, _AgentCommandReadinessStatus>{
    for (final readiness in commands.nativeToolCommandReadiness)
      readiness.commandId: _AgentCommandReadinessStatus(
        ready: readiness.ready,
        reason: readiness.reason,
        requiredCommandId: readiness.requiredCommandId,
      ),
    for (final readiness in commands.debugCommandReadiness)
      readiness.commandId: _AgentCommandReadinessStatus(
        ready: readiness.ready,
        reason: readiness.reason,
        requiredCommandId: readiness.requiredCommandId,
      ),
  };
}

class _AgentCommandReadinessStatus {
  const _AgentCommandReadinessStatus({
    required this.ready,
    required this.reason,
    this.requiredCommandId,
  });

  final bool ready;
  final String reason;
  final String? requiredCommandId;
}

class _AgentIdeCommandSuggestionRow extends StatelessWidget {
  const _AgentIdeCommandSuggestionRow({
    required this.command,
    required this.registered,
    required this.missingRequiredInput,
    this.missingRequiredInputLabel,
    this.missingRequiredInputContract,
    this.missingRequiredInputExamples = const <String>[],
    required this.readiness,
    required this.requiredCommandRegistered,
    required this.applying,
    required this.onApply,
    required this.onApplyRequiredCommand,
    this.recoveryCommandId,
    this.onApplyRecoveryCommand,
  });

  final AgentIdeCommandSuggestion command;
  final bool registered;
  final bool missingRequiredInput;
  final String? missingRequiredInputLabel;
  final String? missingRequiredInputContract;
  final List<String> missingRequiredInputExamples;
  final _AgentCommandReadinessStatus? readiness;
  final bool requiredCommandRegistered;
  final bool applying;
  final VoidCallback? onApply;
  final VoidCallback? onApplyRequiredCommand;
  final String? recoveryCommandId;
  final VoidCallback? onApplyRecoveryCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commandReady = readiness?.ready ?? true;
    final requiredCommandId = readiness?.requiredCommandId;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${command.commandId}${command.input == null ? '' : ' · input ${command.input}'}${command.reason.isEmpty ? '' : ' · ${command.reason}'}',
          style: theme.textTheme.bodySmall,
        ),
        if (!registered)
          Text(
            'Unsupported command',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (!commandReady)
          Text(
            'Command not ready: ${readiness!.reason}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (missingRequiredInput) ...[
          Text(
            missingRequiredInputLabel == null ||
                    missingRequiredInputLabel!.isEmpty
                ? 'Missing required input'
                : 'Missing required input: $missingRequiredInputLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          if (missingRequiredInputContract != null &&
              missingRequiredInputContract!.isNotEmpty)
            Text(
              'Expected input: $missingRequiredInputContract',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (missingRequiredInputExamples.isNotEmpty)
            Text(
              'Examples: ${missingRequiredInputExamples.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ] else if (onApply != null)
          OutlinedButton(
            key: ValueKey('agent-apply-command-${command.commandId}'),
            onPressed: applying ? null : onApply,
            child: Text(applying ? 'Applying Command...' : 'Apply Command'),
          ),
        if (!commandReady &&
            requiredCommandId != null &&
            requiredCommandRegistered &&
            onApplyRequiredCommand != null)
          OutlinedButton(
            key: ValueKey(
              'agent-apply-required-command-${command.commandId}-$requiredCommandId',
            ),
            onPressed: applying ? null : onApplyRequiredCommand,
            child: Text(
              applying
                  ? 'Applying Command...'
                  : 'Apply Required Command: $requiredCommandId',
            ),
          ),
        if (!commandReady &&
            requiredCommandId == null &&
            recoveryCommandId != null &&
            onApplyRecoveryCommand != null)
          OutlinedButton(
            key: ValueKey(
              'agent-recover-command-${command.commandId}-$recoveryCommandId',
            ),
            onPressed: applying ? null : onApplyRecoveryCommand,
            child: Text(applying ? 'Applying Command...' : 'Open Settings'),
          ),
      ],
    );
  }
}

class _AgentPromptSection extends StatefulWidget {
  const _AgentPromptSection({
    required this.platformTarget,
    required this.controller,
    required this.sessionContext,
    required this.onApplyPendingPatch,
    this.onApplyWorkspaceRevertPlan,
    this.onApplyAgentWorkspacePatch,
    this.workspaceSnapshotService,
    this.onRunAgentExtensionTool,
    this.extensionToolExecutionRegistry,
    this.onApplyIdeCommandSuggestion,
    this.onResolveIdeCommandResult,
  });

  final PlatformTarget platformTarget;
  final AgentCodingSessionController controller;
  final AgentSessionContext sessionContext;
  final Future<void> Function() onApplyPendingPatch;
  final Future<void> Function()? onApplyWorkspaceRevertPlan;
  final AgentWorkspacePatchToolRunner? onApplyAgentWorkspacePatch;
  final AgentWorkspaceSnapshotService? workspaceSnapshotService;
  final AgentExtensionToolRunner? onRunAgentExtensionTool;
  final ExtensionAgentToolExecutionRegistry? extensionToolExecutionRegistry;
  final Future<bool> Function(AgentIdeCommandSuggestion suggestion)?
  onApplyIdeCommandSuggestion;
  final AgentCommandResultContext? Function(
    AgentIdeCommandSuggestion suggestion,
  )?
  onResolveIdeCommandResult;

  @override
  State<_AgentPromptSection> createState() => _AgentPromptSectionState();
}

class _AgentPromptSectionState extends State<_AgentPromptSection> {
  late final TextEditingController _promptController;
  bool _applyingPatch = false;
  bool _dispatchingToolCalls = false;
  AgentCodingToolLoopRuntimeReport? _lastToolLoopRuntimeReport;
  String? _lastCommandApplicationMessage;
  String? _recoveryDispatchMessage;
  AgentIdeCommandSuggestion? _lastRetryableCommandSuggestion;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(
      text: widget.controller.draftPrompt,
    );
    widget.controller.addListener(_syncPromptFromController);
  }

  @override
  void didUpdateWidget(covariant _AgentPromptSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncPromptFromController);
      widget.controller.addListener(_syncPromptFromController);
      _setPromptText(widget.controller.draftPrompt);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncPromptFromController);
    _promptController.dispose();
    super.dispose();
  }

  void _syncPromptFromController() {
    final draftPrompt = widget.controller.draftPrompt;
    if (_promptController.text == draftPrompt) {
      return;
    }
    _setPromptText(draftPrompt);
  }

  void _setPromptText(String value) {
    _promptController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _applyPendingPatch() async {
    if (_applyingPatch) {
      return;
    }
    setState(() {
      _applyingPatch = true;
    });
    try {
      await widget.onApplyPendingPatch();
    } on Object catch (error) {
      widget.controller.recordPatchApplicationError(error);
    } finally {
      if (mounted) {
        setState(() {
          _applyingPatch = false;
        });
      }
    }
  }

  Future<void> _applyWorkspaceRevertPlan() async {
    if (_applyingPatch) {
      return;
    }
    final callback = widget.onApplyWorkspaceRevertPlan;
    if (callback == null) {
      return;
    }
    setState(() {
      _applyingPatch = true;
    });
    try {
      await callback();
    } on Object catch (error) {
      widget.controller.recordPatchApplicationError(error);
    } finally {
      if (mounted) {
        setState(() {
          _applyingPatch = false;
        });
      }
    }
  }

  Future<void> _dispatchApprovedToolCalls() async {
    if (_dispatchingToolCalls) {
      return;
    }
    setState(() {
      _dispatchingToolCalls = true;
      _lastToolLoopRuntimeReport = null;
    });
    try {
      final executor = _agentToolExecutor();
      final report = await const AgentCodingToolLoopRuntime().run(
        controller: widget.controller,
        executor: executor.execute,
      );
      if (mounted) {
        setState(() {
          _lastToolLoopRuntimeReport = report;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _dispatchingToolCalls = false;
        });
      }
    }
  }

  Future<void> _replayToolCallJournal() async {
    if (_dispatchingToolCalls) {
      return;
    }
    setState(() {
      _dispatchingToolCalls = true;
    });
    try {
      final executor = _agentToolExecutor();
      await widget.controller.replayToolCallJournal(executor.execute);
    } finally {
      if (mounted) {
        setState(() {
          _dispatchingToolCalls = false;
        });
      }
    }
  }

  Future<void> _sendToolResultContinuation() async {
    if (widget.controller.sending) {
      return;
    }
    await widget.controller.dispatchToolResultContinuation(confirmed: true);
  }

  AgentBuiltinToolExecutor _agentToolExecutor() {
    return AgentBuiltinToolExecutor(
      context: widget.sessionContext,
      ideCommandRunner: widget.onApplyIdeCommandSuggestion == null
          ? null
          : _runIdeCommandTool,
      workspacePatchRunner: widget.onApplyAgentWorkspacePatch,
      workspaceSnapshotService: widget.workspaceSnapshotService,
      workspaceSnapshotCaptureRecorder:
          widget.controller.recordWorkspaceSnapshotCaptureResult,
      workspaceRevertPlanRecorder: widget.controller.recordWorkspaceRevertPlan,
      extensionToolRunner:
          widget.onRunAgentExtensionTool ??
          widget.extensionToolExecutionRegistry?.dispatch,
      validationContextProvider: () =>
          AgentCodingValidationToolContext.fromSessionContext(
            widget.sessionContext,
            validationPlan: widget.controller.codingValidationPlan,
            validationResult: widget.controller.codingValidationResult,
            validationPipeline: widget.controller.codingValidationPipeline,
            changeReviewGate: widget.controller.codingChangeReviewGate,
            autonomyPolicy: widget.controller.codingAutonomyPolicy,
          ),
      recoveryContextProvider: () =>
          widget.controller.sessionHistorySnapshot.toRecoveryContext(),
    );
  }

  Future<AgentCommandResultContext> _runIdeCommandTool(
    AgentIdeCommandSuggestion command,
  ) async {
    final callback = widget.onApplyIdeCommandSuggestion;
    if (callback == null || !widget.controller.beginIdeCommandApplication()) {
      return AgentCommandResultContext(
        commandId: command.commandId,
        input: command.input,
        applied: false,
        message:
            'Command ${command.commandId} cannot run because the IDE command runner is not available.',
        metadata: const <String, Object?>{'source': 'agent-tool-call'},
        completedAt: DateTime.now().toUtc(),
      );
    }
    try {
      final applied = await callback(command);
      final message = applied
          ? _appliedIdeCommandMessage(command)
          : 'Command ${command.commandId} was not applied.';
      final result = _resolvedIdeCommandResult(
        command: command,
        fallbackApplied: applied,
        fallbackMessage: message,
        resolver: widget.onResolveIdeCommandResult,
      );
      widget.controller.recordIdeCommandResult(result);
      return result;
    } on Object {
      final result = AgentCommandResultContext(
        commandId: command.commandId,
        input: command.input,
        applied: false,
        message: 'Command ${command.commandId} failed.',
        metadata: const <String, Object?>{'source': 'agent-tool-call'},
        completedAt: DateTime.now().toUtc(),
      );
      widget.controller.recordIdeCommandResult(result);
      return result;
    } finally {
      widget.controller.endIdeCommandApplication();
    }
  }

  Future<void> _applyIdeCommandSuggestion(
    AgentIdeCommandSuggestion command,
  ) async {
    if (!widget.controller.beginIdeCommandApplication()) {
      return;
    }
    final callback = widget.onApplyIdeCommandSuggestion;
    if (callback == null) {
      widget.controller.endIdeCommandApplication();
      return;
    }
    if (mounted && command.prerequisiteForCommandId == null) {
      setState(() {
        _lastRetryableCommandSuggestion = null;
      });
    }
    try {
      final applied = await callback(command);
      final message = applied
          ? _appliedIdeCommandMessage(command)
          : 'Command ${command.commandId} was not applied.';
      final result = _resolvedIdeCommandResult(
        command: command,
        fallbackApplied: applied,
        fallbackMessage: message,
        resolver: widget.onResolveIdeCommandResult,
      );
      widget.controller.recordIdeCommandResult(result);
      if (!mounted) {
        return;
      }
      setState(() {
        _lastCommandApplicationMessage = result.message;
        _lastRetryableCommandSuggestion =
            result.applied && _commandCompletesPrerequisite(command)
            ? AgentIdeCommandSuggestion(
                commandId: command.prerequisiteForCommandId!,
                reason: 'Retry after ${command.commandId}.',
              )
            : null;
      });
    } on Object {
      widget.controller.recordIdeCommandResult(
        AgentCommandResultContext(
          commandId: command.commandId,
          input: command.input,
          applied: false,
          message: 'Command ${command.commandId} failed.',
          metadata: <String, Object?>{
            'source': 'agent-surface',
            if (command.prerequisiteForCommandId != null)
              'prerequisiteForCommandId': command.prerequisiteForCommandId,
          },
          completedAt: DateTime.now().toUtc(),
        ),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _lastCommandApplicationMessage = 'Command ${command.commandId} failed.';
        _lastRetryableCommandSuggestion = null;
      });
    } finally {
      widget.controller.endIdeCommandApplication();
    }
  }

  Future<void> _dispatchRecoveryAction(
    AgentCodingSessionController controller,
    AgentCodingSessionRecoveryAction action,
  ) async {
    setState(() {
      _recoveryDispatchMessage = 'Running recovery...';
    });
    final command = controller.sessionRecoveryPlan.commandFor(action);
    final result = await controller.dispatchRecoveryRequestDraft(
      action,
      targetProviderProfileKey: command == null
          ? null
          : _recoveryProviderProfileKeyFor(command),
      confirmed: true,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _recoveryDispatchMessage = result.message;
    });
  }

  AgentIdeCommandSuggestion _recoveryCommandSuggestion(
    AgentCodingSessionRecoveryCommandPlan command,
  ) {
    return AgentIdeCommandSuggestion(
      commandId: command.commandId,
      input: _recoveryProviderProfileKeyFor(command),
      reason: 'Run ${command.label} recovery.',
    );
  }

  String? _recoveryProviderProfileKeyFor(
    AgentCodingSessionRecoveryCommandPlan command,
  ) {
    if (!command.requiresProviderSelection) {
      return null;
    }
    return _savedProviderProfileKeyForFailover();
  }

  String? _savedProviderProfileKeyForFailover() {
    final savedProfiles = widget.sessionContext.agent.savedProviderProfiles;
    if (savedProfiles.isEmpty) {
      return null;
    }
    final activeProfileId = widget.controller.profile.profileId;
    for (final profile in savedProfiles) {
      if (profile.key.trim().isNotEmpty &&
          profile.profileId != activeProfileId) {
        return profile.key;
      }
    }
    for (final profile in savedProfiles) {
      if (profile.key.trim().isNotEmpty) {
        return profile.key;
      }
    }
    return null;
  }

  String _appliedIdeCommandMessage(AgentIdeCommandSuggestion command) {
    final prerequisiteForCommandId = command.prerequisiteForCommandId;
    if (prerequisiteForCommandId == null) {
      return 'Command ${command.commandId} applied.';
    }
    if (!_commandCompletesPrerequisite(command)) {
      return 'Command ${command.commandId} applied. '
          'Review Settings before retrying $prerequisiteForCommandId.';
    }
    return 'Command ${command.commandId} applied. '
        '$prerequisiteForCommandId may now be retried.';
  }

  bool _commandCompletesPrerequisite(AgentIdeCommandSuggestion command) {
    return command.prerequisiteForCommandId != null &&
        command.commandId != 'openSettings';
  }

  AgentCommandResultContext _resolvedIdeCommandResult({
    required AgentIdeCommandSuggestion command,
    required bool fallbackApplied,
    required String fallbackMessage,
    required AgentCommandResultContext? Function(AgentIdeCommandSuggestion)?
    resolver,
  }) {
    final resolved = resolver?.call(command);
    if (resolved != null &&
        resolved.commandId == command.commandId &&
        resolved.input == command.input) {
      return resolved;
    }
    return AgentCommandResultContext(
      commandId: command.commandId,
      input: command.input,
      applied: fallbackApplied,
      message: fallbackMessage,
      metadata: <String, Object?>{
        'source': 'agent-surface',
        if (command.prerequisiteForCommandId != null)
          'prerequisiteForCommandId': command.prerequisiteForCommandId,
      },
      completedAt: DateTime.now().toUtc(),
    );
  }

  AgentRequestAttachment _activeDocumentAttachment() {
    final document = widget.sessionContext.document;
    return AgentRequestAttachment(
      attachmentId:
          'document:${document.documentId}:${document.revision}:${document.textStart}:${document.textEnd}',
      kind: 'document',
      name: document.documentId.isEmpty
          ? 'active document'
          : document.documentId,
      content: document.text,
      metadata: <String, Object?>{
        'documentId': document.documentId,
        'revision': document.revision,
        'textStart': document.textStart,
        'textEnd': document.textEnd,
      },
    );
  }

  AgentRequestAttachment _selectionAttachment() {
    final document = widget.sessionContext.document;
    final selection = widget.sessionContext.selection;
    return AgentRequestAttachment(
      attachmentId:
          'selection:${document.documentId}:${document.revision}:${selection.start}:${selection.end}',
      kind: 'selection',
      name: document.documentId.isEmpty
          ? 'active selection'
          : '${document.documentId} selection',
      content: selection.selectedText,
      metadata: <String, Object?>{
        'documentId': document.documentId,
        'revision': document.revision,
        'selectionStart': selection.start,
        'selectionEnd': selection.end,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final controller = widget.controller;
        final response = controller.lastResponse;
        final responseText = response?.contentParts
            .map((part) => part.text)
            .where((text) => text.isNotEmpty)
            .join('\n\n');
        final commandSuggestions =
            response?.contentParts
                .map((part) => part.ideCommand)
                .whereType<AgentIdeCommandSuggestion>()
                .toList(growable: false) ??
            const <AgentIdeCommandSuggestion>[];
        final planParts =
            response?.contentParts
                .where((part) => part.plan != null)
                .toList(growable: false) ??
            const <AgentContentPart>[];
        final diagnosticSummaryParts =
            response?.contentParts
                .where((part) => part.diagnosticSummary != null)
                .toList(growable: false) ??
            const <AgentContentPart>[];
        final registeredCommandIds = _registeredAgentCommandIds(
          widget.sessionContext.commands,
        );
        final commandRequiresInputById = _agentCommandRequiresInputById(
          widget.sessionContext.commands,
        );
        final commandInputLabelById = _agentCommandInputLabelById(
          widget.sessionContext.commands,
        );
        final commandInputContractById = _agentCommandInputContractById(
          widget.sessionContext.commands,
        );
        final commandInputExamplesById = _agentCommandInputExamplesById(
          widget.sessionContext.commands,
        );
        final nativeToolCommandIds = widget
            .sessionContext
            .commands
            .nativeToolCommands
            .map((command) => command.id)
            .toSet();
        final commandReadiness = _commandReadinessById(
          widget.sessionContext.commands,
        );
        final recentCommandResults =
            widget.sessionContext.commands.recentResults;
        final patch = controller.pendingPatch;
        final patchWorkspaceEditConversion =
            controller.pendingWorkspaceEditPlanConversion;
        final patchWorkspaceEditPlan = patchWorkspaceEditConversion?.plan;
        final patchResult = controller.lastPatchApplicationResult;
        final inactiveDirtyPatchTargets = patch == null
            ? const <String>[]
            : _inactiveDirtyPatchTargets(patch, widget.sessionContext);
        final activeFileOperationTargets = patch == null
            ? const <String>[]
            : _activeFileOperationTargets(patch, widget.sessionContext);
        final conversationTurns = controller.conversationTurns;
        final attachments = controller.attachments;
        final applyingPatch = _applyingPatch || controller.applyingPatch;
        final applyingIdeCommand = controller.applyingIdeCommand;
        final applyingAction =
            applyingPatch || applyingIdeCommand || _dispatchingToolCalls;
        final canApplyPendingPatch =
            !applyingPatch &&
            inactiveDirtyPatchTargets.isEmpty &&
            activeFileOperationTargets.isEmpty;
        final canAttachActiveDocument =
            !controller.sending &&
            !applyingAction &&
            widget.sessionContext.document.text.trim().isNotEmpty;
        final selectedText = widget.sessionContext.selection.selectedText;
        final canAttachSelection =
            !controller.sending &&
            !applyingAction &&
            selectedText.trim().isNotEmpty;
        final canClearConversationState =
            conversationTurns.isNotEmpty ||
            response != null ||
            patchResult != null ||
            controller.lastError != null ||
            controller.lastProviderFailure != null;
        final recoveryPlan = controller.sessionRecoveryPlan;
        final recoveryAuditSummary = controller.sessionHistorySnapshot
            .toRecoveryContext()
            .auditSummary;
        final recoveryActionBlockedByAudit =
            recoveryAuditSummary?.requiresUserReview == true;
        final recoveryCommand =
            recoveryPlan.status == AgentCodingSessionRecoveryStatus.available
            ? recoveryPlan.commandFor(recoveryPlan.recommendedAction)
            : null;
        final recoveryCommands =
            recoveryPlan.status == AgentCodingSessionRecoveryStatus.available
            ? recoveryPlan.availableActions
                  .map(recoveryPlan.commandFor)
                  .whereType<AgentCodingSessionRecoveryCommandPlan>()
                  .toList(growable: false)
            : const <AgentCodingSessionRecoveryCommandPlan>[];
        final recoveryValidationSummary = _recoveryValidationSummary(
          controller.sessionHistorySnapshot,
        );
        final recoveryValidationCommandId = _recoveryValidationNextCommandId(
          controller.sessionHistorySnapshot,
        );
        final recoveryValidationFailedCommandIds =
            _recoveryValidationFailedCommandIds(
              controller.sessionHistorySnapshot,
            );
        final recoveryValidationFailureEvidence =
            _recoveryValidationFailureEvidence(
              controller.sessionHistorySnapshot,
            );
        final toolCallTimeline = controller.toolCallTimeline;
        final toolCallExecutionPlan = controller.toolCallExecutionPlan;
        final toolCallReplayPlan = controller.toolCallReplayPlan;
        final recentToolCallResults = controller.recentToolCallResultContexts;
        final recentToolCallResultCount = recentToolCallResults.length;
        final projectToolPermissionRules =
            controller.projectToolPermissionRules;
        final workspaceSnapshotCapture =
            controller.lastWorkspaceSnapshotCaptureResult;
        final workspaceRevertPlan = controller.lastWorkspaceRevertPlan;

        return Container(
          key: const ValueKey('agent-prompt-section'),
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF1E9D8),
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Coding Agent', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(controller.profile.displayName)),
                  Chip(label: Text(controller.providerKind.wireValue)),
                  Chip(label: Text(controller.adapter.adapterId)),
                  Chip(
                    label: Text(
                      controller.providerSupportsCodePatch
                          ? 'code patch'
                          : 'text only',
                    ),
                  ),
                ],
              ),
              if (controller.providerMountMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.providerMountMessage!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              _AgentCodingLoopGateSummary(
                executionReadiness: widget.sessionContext.codingReadiness,
                changeReviewGate: widget.controller.codingChangeReviewGate,
                autonomyPolicy: widget.controller.codingAutonomyPolicy,
                loopGuard: widget.controller.codingLoopGuard,
              ),
              if (widget.extensionToolExecutionRegistry != null) ...[
                const SizedBox(height: 8),
                _AgentExtensionToolRegistrySummary(
                  registry: widget.extensionToolExecutionRegistry!,
                ),
              ],
              if (toolCallTimeline.status != AgentToolCallTimelineStatus.idle ||
                  toolCallExecutionPlan.status !=
                      AgentToolCallExecutionPlanStatus.idle) ...[
                const SizedBox(height: 8),
                _AgentToolCallReviewSurface(
                  timeline: toolCallTimeline,
                  executionPlan: toolCallExecutionPlan,
                  replayPlan: toolCallReplayPlan,
                  onApproveCall: applyingAction || controller.sending
                      ? null
                      : (callId) => controller.approveToolCallExecution(callId),
                  onDenyCall: applyingAction || controller.sending
                      ? null
                      : (callId) => controller.denyToolCallExecution(callId),
                  onDenyCallWithFeedback: applyingAction || controller.sending
                      ? null
                      : (callId, feedback) => controller.denyToolCallExecution(
                          callId,
                          reason: feedback,
                        ),
                  onApproveCallForSession: applyingAction || controller.sending
                      ? null
                      : (callId) => controller.approveToolCallExecution(
                          callId,
                          rememberForSession: true,
                        ),
                  onDenyCallForSession: applyingAction || controller.sending
                      ? null
                      : (callId) => controller.denyToolCallExecution(
                          callId,
                          rememberForSession: true,
                        ),
                  onApproveCallForProject: applyingAction || controller.sending
                      ? null
                      : (callId) => unawaited(
                          controller.approveToolCallExecutionForProject(callId),
                        ),
                  onDenyCallForProject: applyingAction || controller.sending
                      ? null
                      : (callId) => unawaited(
                          controller.denyToolCallExecutionForProject(callId),
                        ),
                  dispatching: _dispatchingToolCalls,
                  toolLoopRuntimeReport: _lastToolLoopRuntimeReport,
                  toolResultCount: recentToolCallResultCount,
                  toolResultContexts: recentToolCallResults,
                  onRunReadyCalls:
                      toolCallExecutionPlan.status ==
                              AgentToolCallExecutionPlanStatus.ready &&
                          !applyingAction &&
                          !controller.sending
                      ? () => unawaited(_dispatchApprovedToolCalls())
                      : null,
                  onReplayJournal:
                      toolCallReplayPlan.ready &&
                          !applyingAction &&
                          !controller.sending
                      ? () => unawaited(_replayToolCallJournal())
                      : null,
                  onDraftReview: applyingAction || controller.sending
                      ? null
                      : () => controller.updatePrompt(
                          _toolCallReviewPrompt(toolCallExecutionPlan),
                        ),
                  onDraftContinuation:
                      applyingAction ||
                          controller.sending ||
                          recentToolCallResultCount == 0
                      ? null
                      : () => controller.restoreToolResultContinuationDraft(),
                  onSendContinuation:
                      applyingAction ||
                          controller.sending ||
                          recentToolCallResultCount == 0
                      ? null
                      : () => unawaited(_sendToolResultContinuation()),
                ),
              ],
              if (projectToolPermissionRules.isNotEmpty) ...[
                const SizedBox(height: 8),
                _AgentProjectToolPermissionPolicySurface(
                  rules: projectToolPermissionRules,
                  onClearRule: applyingAction || controller.sending
                      ? null
                      : (toolId) => unawaited(
                          controller.clearProjectToolPermissionRule(toolId),
                        ),
                ),
              ],
              if (workspaceSnapshotCapture != null ||
                  workspaceRevertPlan != null) ...[
                const SizedBox(height: 8),
                _AgentWorkspaceSnapshotReviewSurface(
                  captureResult: workspaceSnapshotCapture,
                  revertPlan: workspaceRevertPlan,
                  applying: applyingPatch,
                  onApplyRevert:
                      workspaceRevertPlan?.ready == true &&
                          widget.onApplyWorkspaceRevertPlan != null &&
                          !applyingAction &&
                          !controller.sending
                      ? () => unawaited(_applyWorkspaceRevertPlan())
                      : null,
                  onDraftRevert:
                      workspaceRevertPlan?.ready == true &&
                          !applyingAction &&
                          !controller.sending
                      ? () => controller.updatePrompt(
                          _workspaceRevertPrompt(workspaceRevertPlan!),
                        )
                      : null,
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('agent-prompt-input'),
                controller: _promptController,
                minLines: 2,
                maxLines: 5,
                enabled: !controller.sending,
                decoration: const InputDecoration(
                  labelText: 'Prompt',
                  hintText:
                      'Ask the agent to explain, edit, or refactor the current context.',
                  border: OutlineInputBorder(),
                ),
                onChanged: controller.updatePrompt,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('agent-attach-active-document-button'),
                    onPressed: canAttachActiveDocument
                        ? () => controller.addAttachment(
                            _activeDocumentAttachment(),
                          )
                        : null,
                    child: const Text('Attach Active File'),
                  ),
                  if (!widget.sessionContext.selection.isCollapsed)
                    OutlinedButton(
                      key: const ValueKey('agent-attach-selection-button'),
                      onPressed: canAttachSelection
                          ? () =>
                                controller.addAttachment(_selectionAttachment())
                          : null,
                      child: const Text('Attach Selection'),
                    ),
                ],
              ),
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Attachments', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final attachment in attachments)
                      Chip(
                        label: Text('${attachment.name} · ${attachment.kind}'),
                        onDeleted: controller.sending
                            ? null
                            : () => controller.removeAttachment(
                                attachment.attachmentId,
                              ),
                        deleteButtonTooltipMessage: 'Remove ${attachment.name}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: controller.canSend && !applyingAction
                        ? () => unawaited(controller.sendPrompt())
                        : null,
                    child: Text(controller.sending ? 'Sending...' : 'Send'),
                  ),
                  if (controller.sending)
                    OutlinedButton(
                      onPressed: controller.cancelActiveRequest,
                      child: const Text('Cancel'),
                    ),
                  if (patch != null) ...[
                    FilledButton.tonal(
                      onPressed: canApplyPendingPatch
                          ? () => unawaited(_applyPendingPatch())
                          : null,
                      child: Text(
                        applyingPatch ? 'Applying Patch...' : 'Apply Patch',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: applyingPatch
                          ? null
                          : controller.clearPendingPatch,
                      child: const Text('Dismiss Patch'),
                    ),
                  ],
                  if (canClearConversationState)
                    OutlinedButton(
                      onPressed: applyingAction
                          ? null
                          : controller.clearConversation,
                      child: const Text('Clear Conversation'),
                    ),
                ],
              ),
              if (conversationTurns.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Conversation', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final turn
                    in conversationTurns.length > 4
                        ? conversationTurns.sublist(
                            conversationTurns.length - 4,
                          )
                        : conversationTurns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${turn.role.wireValue}: ${turn.text}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              if (controller.lastError != null) ...[
                const SizedBox(height: 10),
                Text(
                  controller.lastError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                if (controller.lastProviderFailure != null) ...[
                  _AgentProviderFailureDetails(
                    failure: controller.lastProviderFailure!,
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    key: const ValueKey('agent-provider-retry-button'),
                    onPressed: controller.canSend && !applyingAction
                        ? () => unawaited(controller.sendPrompt())
                        : null,
                    child: const Text('Retry Provider Request'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('agent-provider-local-fallback-button'),
                    onPressed: controller.sending || applyingAction
                        ? null
                        : () => controller.mountProvider(
                            profile: AgentPromptProfile.defaultForPlatform(
                              widget.platformTarget,
                            ),
                            adapter: const LocalOnlyAgentProviderAdapter(),
                            message:
                                'Cloud agent provider disabled; using local fallback.',
                          ),
                    child: const Text('Use Local Fallback'),
                  ),
                ],
              ],
              if (recoveryCommand != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('agent-recovery-action-card'),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery Available',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        recoveryCommand.label,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (recoveryAuditSummary != null &&
                          recoveryAuditSummary.hasToolExecutionEvidence) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Audit: ${recoveryAuditSummary.toolJournalStatus} · '
                          '${recoveryAuditSummary.toolJournalEntryCount} tool call(s) · '
                          '${recoveryAuditSummary.requiresUserReview ? 'needs review' : 'clear'}',
                          key: const ValueKey('agent-recovery-audit-summary'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: recoveryAuditSummary.requiresUserReview
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                        ),
                        if (recoveryAuditSummary
                            .permissionDeniedToolIds
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Permission denied tools: ${recoveryAuditSummary.permissionDeniedToolIds.join(', ')}',
                            key: const ValueKey(
                              'agent-recovery-audit-permission-denied',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        if (recoveryAuditSummary.blockingIssueCodes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Blocking issues: ${recoveryAuditSummary.blockingIssueCodes.join(', ')}',
                              key: const ValueKey(
                                'agent-recovery-audit-blocking-issues',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (recoveryActionBlockedByAudit) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Resolve the audit review before running provider recovery.',
                            key: const ValueKey(
                              'agent-recovery-audit-provider-recovery-block',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const ValueKey(
                              'agent-recovery-draft-audit-fix',
                            ),
                            onPressed: applyingAction || controller.sending
                                ? null
                                : () {
                                    controller.updatePrompt(
                                      _recoveryAuditFixPrompt(
                                        recoveryAuditSummary,
                                      ),
                                    );
                                    setState(() {
                                      _recoveryDispatchMessage = null;
                                    });
                                  },
                            icon: const Icon(Icons.rule_rounded),
                            label: const Text('Draft Audit Fix'),
                          ),
                        ],
                      ],
                      if (recoveryValidationSummary != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          recoveryValidationSummary,
                          key: const ValueKey(
                            'agent-recovery-validation-summary',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                      if (recoveryValidationCommandId != null) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const ValueKey(
                            'agent-recovery-continue-validation',
                          ),
                          onPressed:
                              widget.onApplyIdeCommandSuggestion == null ||
                                  applyingAction ||
                                  controller.sending
                              ? null
                              : () => unawaited(
                                  _applyIdeCommandSuggestion(
                                    AgentIdeCommandSuggestion(
                                      commandId: recoveryValidationCommandId,
                                      reason:
                                          'Continue validation from the latest recovered agent history.',
                                    ),
                                  ),
                                ),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            'Continue Validation: $recoveryValidationCommandId',
                          ),
                        ),
                      ],
                      if (recoveryValidationFailedCommandIds.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Validation failed commands: ${recoveryValidationFailedCommandIds.join(', ')}',
                          key: const ValueKey(
                            'agent-recovery-validation-failed-commands',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        if (recoveryValidationFailureEvidence != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            recoveryValidationFailureEvidence,
                            key: const ValueKey(
                              'agent-recovery-validation-failure-evidence',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const ValueKey(
                            'agent-recovery-draft-validation-fix',
                          ),
                          onPressed: applyingAction || controller.sending
                              ? null
                              : () {
                                  final evidence =
                                      recoveryValidationFailureEvidence == null
                                      ? ''
                                      : ' $recoveryValidationFailureEvidence';
                                  controller.updatePrompt(
                                    'Fix the latest agent validation failure. '
                                    'Failed validation commands: '
                                    '${recoveryValidationFailedCommandIds.join(', ')}.'
                                    '$evidence',
                                  );
                                  setState(() {
                                    _recoveryDispatchMessage = null;
                                  });
                                },
                          icon: const Icon(Icons.build_outlined),
                          label: const Text('Draft Validation Fix'),
                        ),
                      ],
                      if (recoveryCommands.length > 1) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Available recovery commands',
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final command in recoveryCommands)
                              Builder(
                                builder: (context) {
                                  final missingProviderProfileKey =
                                      command.requiresProviderSelection &&
                                      _recoveryProviderProfileKeyFor(command) ==
                                          null;
                                  return OutlinedButton(
                                    key: ValueKey(
                                      'agent-recovery-command-${command.action.wireValue}',
                                    ),
                                    onPressed:
                                        widget.onApplyIdeCommandSuggestion ==
                                                null ||
                                            applyingAction ||
                                            controller.sending ||
                                            missingProviderProfileKey
                                        ? null
                                        : () => unawaited(
                                            _applyIdeCommandSuggestion(
                                              _recoveryCommandSuggestion(
                                                command,
                                              ),
                                            ),
                                          ),
                                    child: Text(command.label),
                                  );
                                },
                              ),
                          ],
                        ),
                        if (recoveryCommands.any(
                          (command) => command.requiresProviderSelection,
                        )) ...[
                          const SizedBox(height: 6),
                          Text(
                            _savedProviderProfileKeyForFailover() == null
                                ? 'Provider-selection commands need a saved provider profile key. Save or mount a provider profile before failover recovery.'
                                : 'Provider-selection commands use saved provider profile keys. Default target: ${_savedProviderProfileKeyForFailover()}.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            key: const ValueKey(
                              'agent-recovery-restore-prompt',
                            ),
                            onPressed: applyingAction || controller.sending
                                ? null
                                : () {
                                    final restored = controller
                                        .restoreRecoveryDraft(
                                          recoveryPlan.recommendedAction,
                                        );
                                    if (restored) {
                                      setState(() {
                                        _recoveryDispatchMessage = null;
                                      });
                                    }
                                  },
                            child: const Text('Restore Prompt'),
                          ),
                          FilledButton.tonal(
                            key: const ValueKey(
                              'agent-recovery-dispatch-confirmed',
                            ),
                            onPressed:
                                applyingAction ||
                                    controller.sending ||
                                    recoveryActionBlockedByAudit ||
                                    (recoveryCommand
                                            .requiresProviderSelection &&
                                        _recoveryProviderProfileKeyFor(
                                              recoveryCommand,
                                            ) ==
                                            null)
                                ? null
                                : () => unawaited(
                                    _dispatchRecoveryAction(
                                      controller,
                                      recoveryPlan.recommendedAction,
                                    ),
                                  ),
                            child: const Text('Run Recovery'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (_recoveryDispatchMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _recoveryDispatchMessage!,
                  key: const ValueKey('agent-recovery-dispatch-status'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (responseText != null && responseText.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(responseText, style: theme.textTheme.bodySmall),
              ],
              if (planParts.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final part in planParts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AgentCodingPlanSection(part: part),
                  ),
              ],
              if (diagnosticSummaryParts.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final part in diagnosticSummaryParts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AgentDiagnosticSummarySection(part: part),
                  ),
              ],
              if (commandSuggestions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Suggested IDE Commands',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                for (final command in commandSuggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Builder(
                      builder: (context) {
                        final readiness = commandReadiness[command.commandId];
                        final requiredCommandId = readiness?.requiredCommandId;
                        final missingRequiredInput =
                            _agentCommandMissingRequiredInput(
                              command.commandId,
                              command.input,
                              commandRequiresInputById,
                            );
                        final recoveryCommandId =
                            readiness?.ready == false &&
                                requiredCommandId == null &&
                                nativeToolCommandIds.contains(
                                  command.commandId,
                                ) &&
                                registeredCommandIds.contains('openSettings')
                            ? 'openSettings'
                            : null;
                        return _AgentIdeCommandSuggestionRow(
                          command: command,
                          registered: registeredCommandIds.contains(
                            command.commandId,
                          ),
                          missingRequiredInput: missingRequiredInput,
                          missingRequiredInputLabel:
                              commandInputLabelById[command.commandId],
                          missingRequiredInputContract:
                              commandInputContractById[command.commandId],
                          missingRequiredInputExamples:
                              commandInputExamplesById[command.commandId] ??
                              const <String>[],
                          readiness: readiness,
                          requiredCommandRegistered:
                              requiredCommandId != null &&
                              registeredCommandIds.contains(requiredCommandId),
                          applying: applyingIdeCommand,
                          onApply:
                              widget.onApplyIdeCommandSuggestion == null ||
                                  readiness?.ready == false ||
                                  missingRequiredInput
                              ? null
                              : () => unawaited(
                                  _applyIdeCommandSuggestion(command),
                                ),
                          onApplyRequiredCommand:
                              widget.onApplyIdeCommandSuggestion == null ||
                                  requiredCommandId == null ||
                                  !registeredCommandIds.contains(
                                    requiredCommandId,
                                  )
                              ? null
                              : () => unawaited(
                                  _applyIdeCommandSuggestion(
                                    AgentIdeCommandSuggestion(
                                      commandId: requiredCommandId,
                                      prerequisiteForCommandId:
                                          command.commandId,
                                      reason:
                                          'Required before ${command.commandId}.',
                                    ),
                                  ),
                                ),
                          recoveryCommandId: recoveryCommandId,
                          onApplyRecoveryCommand:
                              widget.onApplyIdeCommandSuggestion == null ||
                                  recoveryCommandId == null
                              ? null
                              : () => unawaited(
                                  _applyIdeCommandSuggestion(
                                    AgentIdeCommandSuggestion(
                                      commandId: recoveryCommandId,
                                      prerequisiteForCommandId:
                                          command.commandId,
                                      reason:
                                          'Recover not-ready ${command.commandId}.',
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
              ],
              if (_lastCommandApplicationMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _lastCommandApplicationMessage!,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_lastRetryableCommandSuggestion != null) ...[
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: ValueKey(
                    'agent-retry-original-command-'
                    '${_lastRetryableCommandSuggestion!.commandId}',
                  ),
                  onPressed: applyingIdeCommand
                      ? null
                      : () => unawaited(
                          _applyIdeCommandSuggestion(
                            _lastRetryableCommandSuggestion!,
                          ),
                        ),
                  icon: const Icon(Icons.replay),
                  label: const Text('Retry Original Command'),
                ),
              ],
              if (recentCommandResults.isNotEmpty) ...[
                const SizedBox(height: 10),
                _AgentRecentIdeCommandsSection(
                  results: recentCommandResults,
                  registeredCommandIds: registeredCommandIds,
                  commandRequiresInputById: commandRequiresInputById,
                  commandInputLabelById: commandInputLabelById,
                  commandInputContractById: commandInputContractById,
                  commandInputExamplesById: commandInputExamplesById,
                  commandReadiness: commandReadiness,
                  applying: applyingIdeCommand,
                  onRetry: widget.onApplyIdeCommandSuggestion == null
                      ? null
                      : (result) => unawaited(
                          _applyIdeCommandSuggestion(
                            AgentIdeCommandSuggestion(
                              commandId: result.commandId,
                              input: result.input,
                              reason: 'Retry recent ${result.commandId}.',
                            ),
                          ),
                        ),
                  onApplyRequiredCommand:
                      widget.onApplyIdeCommandSuggestion == null
                      ? null
                      : (result, requiredCommandId) => unawaited(
                          _applyIdeCommandSuggestion(
                            AgentIdeCommandSuggestion(
                              commandId: requiredCommandId,
                              prerequisiteForCommandId: result.commandId,
                              reason:
                                  'Required before retrying ${result.commandId}.',
                            ),
                          ),
                        ),
                  onApplyRecoveryCommand:
                      widget.onApplyIdeCommandSuggestion == null
                      ? null
                      : (result, recoveryCommandId) => unawaited(
                          _applyIdeCommandSuggestion(
                            AgentIdeCommandSuggestion(
                              commandId: recoveryCommandId,
                              prerequisiteForCommandId: result.commandId,
                              reason: 'Recover ${result.commandId}.',
                            ),
                          ),
                        ),
                ),
              ],
              if (patch != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Pending patch: ${patch.summary} (${patch.edits.length} edit(s))',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Patch ${patch.patchId}${patch.baseRevision == null ? '' : ' · base rev ${patch.baseRevision}'}',
                  style: theme.textTheme.bodySmall,
                ),
                if (widget.onApplyIdeCommandSuggestion != null &&
                    registeredCommandIds.contains(
                      'collectAgentCodingCheckpoint',
                    )) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    key: const ValueKey('agent-coding-loop-collect-checkpoint'),
                    onPressed: applyingIdeCommand
                        ? null
                        : () => unawaited(
                            _applyIdeCommandSuggestion(
                              const AgentIdeCommandSuggestion(
                                commandId: 'collectAgentCodingCheckpoint',
                                reason:
                                    'Collect an IDE checkpoint before applying the pending agent patch.',
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Collect Checkpoint'),
                  ),
                ],
                if (patchWorkspaceEditConversion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    patchWorkspaceEditPlan == null
                        ? 'Workspace edit plan unavailable: ${patchWorkspaceEditConversion.message}'
                        : 'Workspace edit plan: ${patchWorkspaceEditPlan.documentIds.length} file(s), ${patchWorkspaceEditPlan.editCount} text edit(s), ${patchWorkspaceEditPlan.fileOperations.length} file operation(s)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 6),
                for (final edit in patch.edits.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${edit.operation.wireValue} ${edit.documentId}:${edit.start}-${edit.end} -> ${edit.replacementText.length} char(s)',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (patch.edits.length > 5)
                  Text(
                    '+ ${patch.edits.length - 5} more edit(s) hidden from preview',
                    style: theme.textTheme.bodySmall,
                  ),
                if (inactiveDirtyPatchTargets.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Patch blocked: dirty inactive files ${_documentListSummary(inactiveDirtyPatchTargets)}. Switch to those files and save or discard local changes first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (activeFileOperationTargets.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Patch blocked: file create/delete targets the active document ${_documentListSummary(activeFileOperationTargets)}. Use replace edits for the active editor document.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
              if (patchResult != null) ...[
                const SizedBox(height: 10),
                Text(patchResult.message, style: theme.textTheme.bodySmall),
                if (patchResult.appliedDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Changed files: ${_documentListSummary(patchResult.appliedDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (patchResult.createdDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Created files: ${_documentListSummary(patchResult.createdDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (patchResult.deletedDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deleted files: ${_documentListSummary(patchResult.deletedDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (patchResult.skippedNoOpDocumentIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Skipped no-op files: ${_documentListSummary(patchResult.skippedNoOpDocumentIds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (!patchResult.applied) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('agent-draft-patch-repair'),
                    onPressed: applyingAction || controller.sending
                        ? null
                        : () {
                            controller.updatePrompt(
                              'Repair the failed agent patch application. '
                              'Patch result: ${patchResult.message}',
                            );
                          },
                    icon: const Icon(Icons.construction_outlined),
                    label: const Text('Draft Patch Repair'),
                  ),
                ],
                if (widget.controller.codingValidationPlan.status !=
                    AgentCodingValidationPlanStatus.notNeeded) ...[
                  const SizedBox(height: 8),
                  _AgentCodingValidationPlanSummary(
                    validationPlan: widget.controller.codingValidationPlan,
                    validationResult: widget.controller.codingValidationResult,
                    validationPipeline:
                        widget.controller.codingValidationPipeline,
                    applyingIdeCommand: applyingIdeCommand,
                    onApplyCommand: widget.onApplyIdeCommandSuggestion == null
                        ? null
                        : (suggestion) =>
                              unawaited(_applyIdeCommandSuggestion(suggestion)),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AgentProjectToolPermissionPolicySurface extends StatelessWidget {
  const _AgentProjectToolPermissionPolicySurface({
    required this.rules,
    this.onClearRule,
  });

  final List<AgentToolPermissionRule> rules;
  final ValueChanged<String>? onClearRule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('agent-project-tool-permission-policy-card'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project tool policy', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Persisted project rules: ${rules.length}',
              style: theme.textTheme.bodySmall,
            ),
            for (final rule in rules.take(6)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${rule.toolIdPattern} · ${rule.action.wireValue}',
                    key: ValueKey(
                      'agent-project-tool-permission-rule-${rule.toolIdPattern}',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (rule.reason.isNotEmpty)
                    Text(rule.reason, style: theme.textTheme.bodySmall),
                  OutlinedButton.icon(
                    key: ValueKey(
                      'agent-project-tool-permission-clear-${rule.toolIdPattern}',
                    ),
                    onPressed: onClearRule == null
                        ? null
                        : () => onClearRule!(rule.toolIdPattern),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Project Rule'),
                  ),
                ],
              ),
            ],
            if (rules.length > 6) ...[
              const SizedBox(height: 6),
              Text(
                '+${rules.length - 6} more project rule(s).',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentToolCallReviewSurface extends StatelessWidget {
  const _AgentToolCallReviewSurface({
    required this.timeline,
    required this.executionPlan,
    required this.replayPlan,
    required this.dispatching,
    this.onApproveCall,
    this.onDenyCall,
    this.onDenyCallWithFeedback,
    this.onApproveCallForSession,
    this.onDenyCallForSession,
    this.onApproveCallForProject,
    this.onDenyCallForProject,
    this.onRunReadyCalls,
    this.onReplayJournal,
    this.onDraftReview,
    this.toolLoopRuntimeReport,
    this.toolResultCount = 0,
    this.toolResultContexts = const <AgentToolCallResultContext>[],
    this.onDraftContinuation,
    this.onSendContinuation,
  });

  final AgentToolCallTimeline timeline;
  final AgentToolCallExecutionPlan executionPlan;
  final AgentToolCallReplayPlan replayPlan;
  final bool dispatching;
  final ValueChanged<String>? onApproveCall;
  final ValueChanged<String>? onDenyCall;
  final void Function(String callId, String feedback)? onDenyCallWithFeedback;
  final ValueChanged<String>? onApproveCallForSession;
  final ValueChanged<String>? onDenyCallForSession;
  final ValueChanged<String>? onApproveCallForProject;
  final ValueChanged<String>? onDenyCallForProject;
  final VoidCallback? onRunReadyCalls;
  final VoidCallback? onReplayJournal;
  final VoidCallback? onDraftReview;
  final AgentCodingToolLoopRuntimeReport? toolLoopRuntimeReport;
  final int toolResultCount;
  final List<AgentToolCallResultContext> toolResultContexts;
  final VoidCallback? onDraftContinuation;
  final VoidCallback? onSendContinuation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (executionPlan.status) {
      AgentToolCallExecutionPlanStatus.blocked ||
      AgentToolCallExecutionPlanStatus.failed => theme.colorScheme.error,
      AgentToolCallExecutionPlanStatus.reviewRequired =>
        theme.colorScheme.primary,
      _ => theme.colorScheme.onSurfaceVariant,
    };

    return DecoratedBox(
      key: const ValueKey('agent-tool-call-review-card'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tool execution: ${executionPlan.status.wireValue}',
              style: theme.textTheme.titleSmall?.copyWith(color: statusColor),
            ),
            const SizedBox(height: 4),
            Text(
              'Lifecycle: ${timeline.status.wireValue} · calls ${timeline.calls.length}',
              style: theme.textTheme.bodySmall,
            ),
            if (replayPlan.status != AgentToolCallReplayPlanStatus.empty)
              Text(
                'Replay plan: ${replayPlan.status.wireValue} · requests ${replayPlan.requests.length}',
                style: theme.textTheme.bodySmall,
              ),
            if (toolLoopRuntimeReport != null)
              Text(
                'Tool loop runtime: ${toolLoopRuntimeReport!.status.wireValue} · rounds ${toolLoopRuntimeReport!.dispatchRoundCount}/${toolLoopRuntimeReport!.maxDispatchRounds}',
                key: const ValueKey('agent-tool-loop-runtime-summary'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _toolLoopRuntimeStatusColor(
                    theme,
                    toolLoopRuntimeReport!.status,
                  ),
                ),
              ),
            if (toolResultCount > 0)
              Text(
                'Tool results ready: $toolResultCount',
                key: const ValueKey('agent-tool-result-continuation-summary'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            if (toolResultContexts.isNotEmpty) ...[
              const SizedBox(height: 4),
              _AgentToolResultContextSummaryList(results: toolResultContexts),
            ],
            for (final execution in executionPlan.executions.take(4)) ...[
              const SizedBox(height: 4),
              Text(
                '${execution.toolId} · ${execution.status.wireValue} · ${execution.callId}',
                key: ValueKey('agent-tool-call-execution-${execution.callId}'),
                style: theme.textTheme.bodySmall,
              ),
              if (execution.issueCodes.isNotEmpty)
                Text(
                  'Issues: ${execution.issueCodes.join(', ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              if (execution.reviewDecisionStatus != null)
                Text(
                  'Review decision: ${execution.reviewDecisionStatus!.wireValue}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              if ((timeline.callFor(execution.callId)?.progressSummary ?? '')
                  .isNotEmpty)
                Text(
                  'Progress: ${timeline.callFor(execution.callId)!.progressSummary}',
                  key: ValueKey('agent-tool-call-progress-${execution.callId}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              if ((timeline.callFor(execution.callId)?.richErrorDetails ?? '')
                  .isNotEmpty)
                Text(
                  'Error details: ${timeline.callFor(execution.callId)!.richErrorDetails}',
                  key: ValueKey(
                    'agent-tool-call-error-details-${execution.callId}',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              if (execution.status ==
                  AgentToolCallExecutionStatus.reviewRequired)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        key: ValueKey(
                          'agent-tool-call-approve-${execution.callId}',
                        ),
                        onPressed: onApproveCall == null
                            ? null
                            : () => onApproveCall!(execution.callId),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Approve Tool Call'),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey(
                          'agent-tool-call-deny-${execution.callId}',
                        ),
                        onPressed: onDenyCall == null
                            ? null
                            : () => onDenyCall!(execution.callId),
                        icon: const Icon(Icons.block),
                        label: const Text('Deny Tool Call'),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey(
                          'agent-tool-call-deny-feedback-${execution.callId}',
                        ),
                        onPressed: onDenyCallWithFeedback == null
                            ? null
                            : () => unawaited(
                                _requestDenyFeedback(context, execution.callId),
                              ),
                        icon: const Icon(Icons.feedback_outlined),
                        label: const Text('Deny With Feedback'),
                      ),
                      FilledButton.tonalIcon(
                        key: ValueKey(
                          'agent-tool-call-approve-session-${execution.callId}',
                        ),
                        onPressed: onApproveCallForSession == null
                            ? null
                            : () => onApproveCallForSession!(execution.callId),
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Allow In Session'),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey(
                          'agent-tool-call-deny-session-${execution.callId}',
                        ),
                        onPressed: onDenyCallForSession == null
                            ? null
                            : () => onDenyCallForSession!(execution.callId),
                        icon: const Icon(Icons.lock),
                        label: const Text('Deny In Session'),
                      ),
                      FilledButton.tonalIcon(
                        key: ValueKey(
                          'agent-tool-call-approve-project-${execution.callId}',
                        ),
                        onPressed: onApproveCallForProject == null
                            ? null
                            : () => onApproveCallForProject!(execution.callId),
                        icon: const Icon(Icons.policy_outlined),
                        label: const Text('Allow In Project'),
                      ),
                      OutlinedButton.icon(
                        key: ValueKey(
                          'agent-tool-call-deny-project-${execution.callId}',
                        ),
                        onPressed: onDenyCallForProject == null
                            ? null
                            : () => onDenyCallForProject!(execution.callId),
                        icon: const Icon(Icons.gpp_bad_outlined),
                        label: const Text('Deny In Project'),
                      ),
                    ],
                  ),
                ),
            ],
            if (executionPlan.executions.length > 4)
              Text(
                '+${executionPlan.executions.length - 4} more tool call(s).',
                style: theme.textTheme.bodySmall,
              ),
            if (executionPlan.blockingIssueCodes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Blocking issues: ${executionPlan.blockingIssueCodes.take(4).join(', ')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (executionPlan.status ==
                    AgentToolCallExecutionPlanStatus.ready)
                  FilledButton.tonalIcon(
                    key: const ValueKey('agent-tool-call-run-approved'),
                    onPressed: dispatching ? null : onRunReadyCalls,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      dispatching ? 'Running Tools...' : 'Run Approved Tools',
                    ),
                  ),
                if (replayPlan.ready)
                  OutlinedButton.icon(
                    key: const ValueKey('agent-tool-call-replay-journal'),
                    onPressed: dispatching ? null : onReplayJournal,
                    icon: const Icon(Icons.replay),
                    label: Text(
                      dispatching
                          ? 'Replaying Tool Journal...'
                          : 'Replay Tool Journal',
                    ),
                  ),
                OutlinedButton.icon(
                  key: const ValueKey('agent-tool-call-draft-review'),
                  onPressed: dispatching ? null : onDraftReview,
                  icon: const Icon(Icons.rate_review_outlined),
                  label: const Text('Draft Tool Review'),
                ),
                if (toolResultCount > 0)
                  FilledButton.tonalIcon(
                    key: const ValueKey('agent-tool-call-draft-continuation'),
                    onPressed: dispatching ? null : onDraftContinuation,
                    icon: const Icon(Icons.auto_awesome_motion_outlined),
                    label: const Text('Draft Tool Continuation'),
                  ),
                if (toolResultCount > 0)
                  FilledButton.icon(
                    key: const ValueKey('agent-tool-call-send-continuation'),
                    onPressed: dispatching ? null : onSendContinuation,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Send Tool Continuation'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestDenyFeedback(BuildContext context, String callId) async {
    var currentFeedback = '';
    final feedback = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Deny Tool Call With Feedback'),
          content: TextField(
            key: const ValueKey('agent-tool-call-deny-feedback-input'),
            autofocus: true,
            maxLines: 4,
            onChanged: (value) => currentFeedback = value,
            decoration: const InputDecoration(
              labelText: 'Corrective feedback',
              hintText: 'Explain what the agent should change before retry.',
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('agent-tool-call-deny-feedback-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('agent-tool-call-deny-feedback-submit'),
              onPressed: () => Navigator.of(dialogContext).pop(currentFeedback),
              child: const Text('Send Feedback'),
            ),
          ],
        );
      },
    );
    final normalized = feedback?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    onDenyCallWithFeedback?.call(callId, normalized);
  }
}

class _AgentToolResultContextSummaryList extends StatelessWidget {
  const _AgentToolResultContextSummaryList({required this.results});

  final List<AgentToolCallResultContext> results;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleResults = results.take(4).toList(growable: false);

    return Column(
      key: const ValueKey('agent-tool-result-context-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < visibleResults.length; index++) ...[
          Text(
            'Tool result context: ${visibleResults[index].toolId} · ${visibleResults[index].status.wireValue} · ${visibleResults[index].callId}',
            key: ValueKey(
              'agent-tool-result-context-call-${visibleResults[index].callId}-$index',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: visibleResults[index].success
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          if (_structuredToolResultSummary(visibleResults[index]) != null)
            Text(
              'Structured result: ${_structuredToolResultSummary(visibleResults[index])}',
              key: ValueKey(
                'agent-tool-result-structured-summary-${visibleResults[index].callId}-$index',
              ),
              style: theme.textTheme.bodySmall,
            ),
        ],
        if (results.length > 4)
          Text(
            '+${results.length - 4} more tool result(s).',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

String? _structuredToolResultSummary(AgentToolCallResultContext result) {
  final output = _decodeToolResultObject(result.output);
  if (output == null) {
    return null;
  }
  final schema = _nonEmptyString(output['schema']);
  if (schema == 'vityo.agent-surface-context.v1') {
    final parts = <String>['Agent surface context'];
    final platformTarget = _nonEmptyString(output['platformTarget']);
    if (platformTarget != null) {
      parts.add('platform $platformTarget');
    }
    final providerCount = _providerRegistryProviderCount(
      output['providerRegistry'],
    );
    if (providerCount != null) {
      parts.add('providers $providerCount');
    }
    final transportAction = _nonEmptyString(output['transportAction']);
    if (transportAction != null) {
      parts.add('transport $transportAction');
    }
    return parts.join(' · ');
  }
  if (schema != null) {
    return 'Schema $schema';
  }
  return null;
}

Map<String, Object?>? _decodeToolResultObject(String output) {
  try {
    final decoded = jsonDecode(output);
    if (decoded is! Map) {
      return null;
    }
    return decoded.map(
      (key, value) => MapEntry(key is String ? key : '$key', value),
    );
  } on FormatException {
    return null;
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int? _providerRegistryProviderCount(Object? value) {
  if (value is! Map) {
    return null;
  }
  final providers = value['providers'];
  if (providers is List) {
    return providers.length;
  }
  final providerIds = value['providerIds'];
  if (providerIds is List) {
    return providerIds.length;
  }
  return null;
}

class _AgentExtensionToolRegistrySummary extends StatelessWidget {
  const _AgentExtensionToolRegistrySummary({required this.registry});

  final ExtensionAgentToolExecutionRegistry registry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolIds = registry.toolIds.toList(growable: false)..sort();
    final handlerToolIds = registry.handlerToolIds.toList(growable: false)
      ..sort();
    final handledToolIds = handlerToolIds.toSet();
    final missingHandlerToolIds = toolIds
        .where((toolId) => !handledToolIds.contains(toolId))
        .toList(growable: false);
    final statusColor = missingHandlerToolIds.isEmpty
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return DecoratedBox(
      key: const ValueKey('agent-extension-tool-registry-summary'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Extension tools: ${toolIds.length} declared · ${handlerToolIds.length} executable',
              key: const ValueKey('agent-extension-tool-registry-counts'),
              style: theme.textTheme.bodySmall?.copyWith(color: statusColor),
            ),
            if (toolIds.isNotEmpty)
              Text(
                'Registered extension tools: ${toolIds.take(4).join(', ')}',
                key: const ValueKey('agent-extension-tool-registry-tools'),
                style: theme.textTheme.bodySmall,
              ),
            if (missingHandlerToolIds.isNotEmpty)
              Text(
                'Missing handlers: ${missingHandlerToolIds.take(4).join(', ')}',
                key: const ValueKey(
                  'agent-extension-tool-registry-missing-handlers',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _toolLoopRuntimeStatusColor(
  ThemeData theme,
  AgentCodingToolLoopRuntimeStatus status,
) {
  return switch (status) {
    AgentCodingToolLoopRuntimeStatus.blocked ||
    AgentCodingToolLoopRuntimeStatus.failed ||
    AgentCodingToolLoopRuntimeStatus.limitReached => theme.colorScheme.error,
    AgentCodingToolLoopRuntimeStatus.complete => theme.colorScheme.primary,
    _ => theme.colorScheme.onSurfaceVariant,
  };
}

class _AgentWorkspaceSnapshotReviewSurface extends StatelessWidget {
  const _AgentWorkspaceSnapshotReviewSurface({
    required this.captureResult,
    required this.revertPlan,
    required this.applying,
    this.onApplyRevert,
    this.onDraftRevert,
  });

  final AgentWorkspaceSnapshotCaptureResult? captureResult;
  final AgentWorkspaceRevertPlan? revertPlan;
  final bool applying;
  final VoidCallback? onApplyRevert;
  final VoidCallback? onDraftRevert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capture = captureResult;
    final snapshot = capture?.snapshot;
    final plan = revertPlan;

    return DecoratedBox(
      key: const ValueKey('agent-workspace-snapshot-card'),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              capture == null
                  ? 'Workspace snapshot: unavailable'
                  : 'Workspace snapshot: ${capture.status.wireValue}',
              style: theme.textTheme.titleSmall,
            ),
            if (capture?.restored ?? false) ...[
              const SizedBox(height: 4),
              Text(
                'Restored from previous session. Review before applying this revert plan.',
                key: const ValueKey(
                  'agent-workspace-snapshot-restored-warning',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (snapshot != null) ...[
              const SizedBox(height: 4),
              Text(
                'Snapshot ${snapshot.snapshotId} · ${snapshot.documents.length} document(s)',
                key: const ValueKey('agent-workspace-snapshot-summary'),
                style: theme.textTheme.bodySmall,
              ),
              if (snapshot.unavailableDocumentIds.isNotEmpty)
                Text(
                  'Unavailable: ${_documentListSummary(snapshot.unavailableDocumentIds)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
            if (plan != null) ...[
              const SizedBox(height: 6),
              Text(
                'Revert plan: ${plan.status.wireValue} · changed ${plan.diffSummary.changedDocumentCount}',
                key: const ValueKey('agent-workspace-revert-plan-summary'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: plan.ready
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (plan.diffSummary.modifiedDocumentIds.isNotEmpty)
                Text(
                  'Modified: ${_documentListSummary(plan.diffSummary.modifiedDocumentIds)}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('agent-workspace-revert-apply-button'),
                  onPressed: applying ? null : onApplyRevert,
                  icon: const Icon(Icons.restore),
                  label: Text(
                    applying ? 'Applying Revert...' : 'Apply Revert Plan',
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('agent-workspace-revert-draft-button'),
                  onPressed: applying ? null : onDraftRevert,
                  icon: const Icon(Icons.undo),
                  label: const Text('Draft Revert Prompt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _documentListSummary(List<String> documentIds) {
  final visibleDocumentIds = documentIds.take(5).join(', ');
  final hiddenCount = documentIds.length - 5;
  if (hiddenCount <= 0) {
    return visibleDocumentIds;
  }
  return '$visibleDocumentIds, + $hiddenCount more';
}

String _toolCallReviewPrompt(AgentToolCallExecutionPlan plan) {
  final status = plan.status.wireValue;
  final callSummary = plan.executions
      .take(4)
      .map((execution) => '${execution.toolId}:${execution.status.wireValue}')
      .join(', ');
  final issues = plan.blockingIssueCodes.isEmpty
      ? ''
      : ' Blocking issues: ${plan.blockingIssueCodes.join(', ')}.';
  return 'Review pending agent tool calls. Tool execution status: $status. Calls: $callSummary.$issues';
}

String _workspaceRevertPrompt(AgentWorkspaceRevertPlan plan) {
  return 'Review the agent workspace revert plan ${plan.snapshotId}. '
      'Status: ${plan.status.wireValue}. Changed documents: '
      '${plan.diffSummary.changedDocumentCount}. '
      'Modified: ${_documentListSummary(plan.diffSummary.modifiedDocumentIds)}.';
}

List<String> _inactiveDirtyPatchTargets(
  AgentCodePatch patch,
  AgentSessionContext context,
) {
  final activeDocumentIds = <String>{
    context.document.documentId,
    context.workspace.activeFilePath,
  };
  final dirtyDocumentIds = context.workspace.dirtyDocumentIds.toSet();
  final targets = <String>[];
  for (final edit in patch.edits) {
    if (activeDocumentIds.contains(edit.documentId) ||
        !dirtyDocumentIds.contains(edit.documentId) ||
        targets.contains(edit.documentId)) {
      continue;
    }
    targets.add(edit.documentId);
  }
  return targets;
}

List<String> _activeFileOperationTargets(
  AgentCodePatch patch,
  AgentSessionContext context,
) {
  final activeDocumentIds = <String>{
    context.document.documentId,
    context.workspace.activeFilePath,
  };
  final targets = <String>[];
  for (final edit in patch.edits) {
    if (edit.operation == AgentCodePatchEditOperation.replace ||
        !activeDocumentIds.contains(edit.documentId) ||
        targets.contains(edit.documentId)) {
      continue;
    }
    targets.add(edit.documentId);
  }
  return targets;
}

class _AgentProviderFailureDetails extends StatelessWidget {
  const _AgentProviderFailureDetails({required this.failure});

  final AgentProviderTransportException failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ) ??
        TextStyle(color: theme.colorScheme.onErrorContainer);
    return Container(
      key: const ValueKey('agent-provider-failure-details'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: DefaultTextStyle(
        style: textStyle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Provider failure kind: ${failure.kind.name}'),
            if (failure.statusCode != null)
              Text('HTTP status: ${failure.statusCode}'),
            if (failure.recoveryHint != null)
              Text('Recovery: ${failure.recoveryHint}'),
          ],
        ),
      ),
    );
  }
}

class _AgentCodingPlanSection extends StatelessWidget {
  const _AgentCodingPlanSection({required this.part});

  final AgentContentPart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = part.plan!;
    return Container(
      key: const ValueKey('agent-coding-plan-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFE6EEF0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Agent Coding Plan', style: theme.textTheme.titleSmall),
          if (plan.summary.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(plan.summary, style: theme.textTheme.bodySmall),
          ],
          if (plan.steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Steps', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            for (var index = 0; index < plan.steps.length; index++)
              Text(
                '${index + 1}. ${plan.steps[index]}',
                style: theme.textTheme.bodySmall,
              ),
          ],
          if (plan.acceptanceCriteria.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Acceptance Criteria', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            for (final criterion in plan.acceptanceCriteria)
              Text('- $criterion', style: theme.textTheme.bodySmall),
          ],
          if (plan.risks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Risks', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            for (final risk in plan.risks)
              Text('- $risk', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _AgentDiagnosticSummarySection extends StatelessWidget {
  const _AgentDiagnosticSummarySection({required this.part});

  final AgentContentPart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = part.diagnosticSummary!;
    return Container(
      key: const ValueKey('agent-diagnostic-summary-section'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0E8E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Agent Diagnostic Summary', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(summary.severity)),
              Chip(label: Text('${summary.diagnosticCount} diagnostic(s)')),
              for (final documentId in summary.affectedDocuments.take(3))
                Chip(label: Text(documentId)),
            ],
          ),
          if (summary.title.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(summary.title, style: theme.textTheme.labelMedium),
          ],
          if (summary.summary.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(summary.summary, style: theme.textTheme.bodySmall),
          ],
          if (summary.suggestedCommandIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Suggested Commands', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final commandId in summary.suggestedCommandIds)
                  Chip(label: Text(commandId)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentRecentIdeCommandsSection extends StatelessWidget {
  const _AgentRecentIdeCommandsSection({
    required this.results,
    required this.registeredCommandIds,
    required this.commandRequiresInputById,
    required this.commandInputLabelById,
    required this.commandInputContractById,
    required this.commandInputExamplesById,
    required this.commandReadiness,
    required this.applying,
    this.onRetry,
    this.onApplyRequiredCommand,
    this.onApplyRecoveryCommand,
  });

  final List<AgentCommandResultContext> results;
  final Set<String> registeredCommandIds;
  final Map<String, bool> commandRequiresInputById;
  final Map<String, String> commandInputLabelById;
  final Map<String, String> commandInputContractById;
  final Map<String, List<String>> commandInputExamplesById;
  final Map<String, _AgentCommandReadinessStatus> commandReadiness;
  final bool applying;
  final void Function(AgentCommandResultContext result)? onRetry;
  final void Function(
    AgentCommandResultContext result,
    String requiredCommandId,
  )?
  onApplyRequiredCommand;
  final void Function(
    AgentCommandResultContext result,
    String recoveryCommandId,
  )?
  onApplyRecoveryCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleResults = results.take(5).toList(growable: false);
    return Column(
      key: const ValueKey('agent-recent-ide-commands-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent IDE Commands', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (var index = 0; index < visibleResults.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Builder(
              builder: (context) {
                final result = visibleResults[index];
                final readiness = commandReadiness[result.commandId];
                final commandReady = readiness?.ready ?? true;
                final missingRequiredInput = _agentCommandMissingRequiredInput(
                  result.commandId,
                  result.input,
                  commandRequiresInputById,
                );
                final missingInputLabel =
                    commandInputLabelById[result.commandId];
                final missingInputContract =
                    commandInputContractById[result.commandId];
                final missingInputExamples =
                    commandInputExamplesById[result.commandId] ??
                    const <String>[];
                final requiredCommandId =
                    readiness?.requiredCommandId ??
                    requiredCommandIdFromAgentMetadata(result.metadata);
                final hasRequiredCommand = requiredCommandId != null;
                final routeBlocked =
                    backendRouteFromAgentMetadata(result.metadata)?.blocked ??
                    false;
                final toolchainSelectionRecoverable =
                    toolchainSelectionFromAgentMetadata(
                      result.metadata,
                    )?.settingsRecoveryRecommended ??
                    false;
                final metadataSummary = nativeToolMetadataSummaryText(
                  result.metadata,
                );
                return Column(
                  key: ValueKey(
                    'agent-recent-ide-command-${result.commandId}-$index',
                  ),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${result.commandId} · '
                            '${result.applied ? 'applied' : 'not applied'}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (onRetry != null &&
                            commandReady &&
                            !missingRequiredInput &&
                            !hasRequiredCommand &&
                            !routeBlocked &&
                            !toolchainSelectionRecoverable &&
                            registeredCommandIds.contains(result.commandId))
                          OutlinedButton(
                            key: ValueKey(
                              'agent-retry-recent-command-'
                              '${result.commandId}-$index',
                            ),
                            onPressed: applying ? null : () => onRetry!(result),
                            child: const Text('Retry Command'),
                          ),
                        if (requiredCommandId != null &&
                            registeredCommandIds.contains(requiredCommandId) &&
                            onApplyRequiredCommand != null)
                          OutlinedButton(
                            key: ValueKey(
                              'agent-retry-recent-required-command-'
                              '${result.commandId}-$requiredCommandId-$index',
                            ),
                            onPressed: applying
                                ? null
                                : () => onApplyRequiredCommand!(
                                    result,
                                    requiredCommandId,
                                  ),
                            child: Text(
                              'Apply Required Command: $requiredCommandId',
                            ),
                          ),
                        if (routeBlocked &&
                            registeredCommandIds.contains('openSettings') &&
                            onApplyRecoveryCommand != null)
                          OutlinedButton(
                            key: ValueKey(
                              'agent-recover-recent-command-'
                              '${result.commandId}-openSettings-$index',
                            ),
                            onPressed: applying
                                ? null
                                : () => onApplyRecoveryCommand!(
                                    result,
                                    'openSettings',
                                  ),
                            child: const Text('Open Settings'),
                          ),
                        if (toolchainSelectionRecoverable &&
                            !routeBlocked &&
                            registeredCommandIds.contains('openSettings') &&
                            onApplyRecoveryCommand != null)
                          OutlinedButton(
                            key: ValueKey(
                              'agent-recover-recent-command-'
                              '${result.commandId}-openSettings-$index',
                            ),
                            onPressed: applying
                                ? null
                                : () => onApplyRecoveryCommand!(
                                    result,
                                    'openSettings',
                                  ),
                            child: const Text('Open Settings'),
                          ),
                      ],
                    ),
                    if (!commandReady)
                      Text(
                        'Retry not ready: ${readiness!.reason}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    if (missingRequiredInput)
                      Text(
                        missingInputLabel == null || missingInputLabel.isEmpty
                            ? 'Retry requires input'
                            : 'Retry requires input: $missingInputLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    if (missingRequiredInput &&
                        missingInputContract != null &&
                        missingInputContract.isNotEmpty)
                      Text(
                        'Expected input: $missingInputContract',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (missingRequiredInput && missingInputExamples.isNotEmpty)
                      Text(
                        'Examples: ${missingInputExamples.join(', ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (result.completedAt != null)
                      Text(
                        'Completed ${result.completedAt!.toUtc().toIso8601String()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (result.message.isNotEmpty)
                      Text(
                        result.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (metadataSummary != null)
                      Text(
                        metadataSummary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        if (results.length > visibleResults.length)
          Text(
            '+ ${results.length - visibleResults.length} older command(s)',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _AgentContextSection extends StatelessWidget {
  const _AgentContextSection({required this.context});

  final AgentSessionContext context;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionContext = this.context;
    final selectedText = sessionContext.selection.selectedText;
    final resolvedElement = sessionContext.language.resolvedElement;
    final resolvedReference = sessionContext.language.resolvedReference;
    final languageFactLabel = _agentLanguageFactLabel(
      resolvedElement: resolvedElement,
      resolvedReference: resolvedReference,
      semanticSpanCount: sessionContext.language.semanticSpanCount,
    );
    final selectionLabel = sessionContext.selection.isCollapsed
        ? 'caret ${sessionContext.selection.start}'
        : 'selection ${sessionContext.selection.start}-${sessionContext.selection.end}';
    final runtimeLabel = sessionContext.runtime.hasSession
        ? '${sessionContext.runtime.kind} ${sessionContext.runtime.status}'
        : 'no runtime session';

    return Container(
      key: const ValueKey('agent-session-context-section'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E5),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IDE Context', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(sessionContext.document.documentId)),
              Chip(label: Text('rev ${sessionContext.document.revision}')),
              Chip(label: Text(sessionContext.workspace.activeFilePath)),
              Chip(
                label: Text(
                  '${sessionContext.workspace.fileCount} workspace file(s)',
                ),
              ),
              Chip(label: Text(selectionLabel)),
              if (languageFactLabel != null)
                Chip(label: Text(languageFactLabel)),
              Chip(
                label: Text(
                  '${sessionContext.diagnostics.length} diagnostic(s)',
                ),
              ),
              Chip(label: Text(runtimeLabel)),
            ],
          ),
          if (selectedText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              sessionContext.selection.selectedTextTruncated
                  ? '$selectedText...'
                  : selectedText,
              style: theme.textTheme.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

String? _agentLanguageFactLabel({
  required AgentResolvedElementContext? resolvedElement,
  required AgentResolvedReferenceContext? resolvedReference,
  required int semanticSpanCount,
}) {
  final parts = <String>[];
  if (resolvedElement != null) {
    parts.add('resolved ${resolvedElement.name}/${resolvedElement.kind}');
  }
  if (resolvedReference != null) {
    parts.add('ref ${resolvedReference.access}');
  }
  if (semanticSpanCount > 0) {
    parts.add('$semanticSpanCount semantic');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

class _AgentSkillSection extends StatelessWidget {
  const _AgentSkillSection({required this.context});

  final AgentSessionContext context;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skills = this.context.skills;
    final activeSkillIds = skills.activeSkillIds.toSet();
    final activeSkills = skills.skills
        .where((skill) => activeSkillIds.contains(skill.skillId))
        .toList(growable: false);

    return Container(
      key: const ValueKey('agent-active-skills-section'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE8F1),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active Coding Skills', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '${skills.activeSkillCount} active / ${skills.skillCount} available skills',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (activeSkills.isEmpty)
            Text(
              'No workspace-activated coding skills are available for this context.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final skill in activeSkills.take(8))
                  Tooltip(
                    message: skill.skillId,
                    child: Chip(
                      key: ValueKey('agent-active-skill-${skill.skillId}'),
                      label: Text(skill.title),
                    ),
                  ),
              ],
            ),
          if (activeSkills.length > 8) ...[
            const SizedBox(height: 8),
            Text(
              '+ ${activeSkills.length - 8} more active skill(s)',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (skills.activationReasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final skill in activeSkills.take(3))
              if ((skills.activationReasons[skill.skillId] ?? const <String>[])
                  .isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${skill.title}: ${skills.activationReasons[skill.skillId]!.join(' ')}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _AgentSection extends StatelessWidget {
  const _AgentSection({
    required this.title,
    required this.body,
    required this.accent,
  });

  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AdapterSection extends StatelessWidget {
  const _AdapterSection({required this.adapterCapabilities});

  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Adapter Routes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final snapshot in adapterCapabilities)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${snapshot.adapterKind.label}: language ${snapshot.languageService.level.label}, execution ${snapshot.execution.level.label}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentModuleSection extends StatelessWidget {
  const _AgentModuleSection({required this.modules});

  final List<ModuleDefinition> modules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mounted Adapters And Slots',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (modules.isEmpty)
            Text(
              'No agent adapter modules are visible for this target.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: modules
                  .map(
                    (module) => Chip(label: Text(module.manifest.displayName)),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 12),
          Text(
            'Local agent runtime stays external; iOS keeps the cloud route as the compliance floor.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _providerRouteForPlatform(PlatformTarget platformTarget) {
  switch (platformTarget) {
    case PlatformTarget.ios:
      return 'Cloud-only OpenAI-compatible provider route';
    case PlatformTarget.web:
      return 'Hosted provider route with cloud profile sync';
    case PlatformTarget.android:
      return 'Cloud provider route with optional local bridge slot';
    case PlatformTarget.windows:
    case PlatformTarget.linux:
    case PlatformTarget.macos:
      return 'Desktop provider route with local bridge reservation';
    case PlatformTarget.unknown:
      return 'Provider route pending platform resolution';
  }
}
