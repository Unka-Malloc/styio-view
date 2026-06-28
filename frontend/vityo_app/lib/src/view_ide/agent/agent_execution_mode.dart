/// Agent execution mode: dry-run/plan-only, build-capable, and permission requirements.
///
/// Key invariants:
/// - Dry-run/plan-only mode prevents any side effects (patches, commands, tool calls).
/// - Build-capable mode requires explicit tool permissions for build/run tools.
/// - Blocked reasons are exposed through the agent context and Agent Surface UI.
library;

import 'agent_tool_permission.dart';

/// Execution mode for an agent session or request.
enum AgentExecutionMode {
  /// Full execution mode: AI can propose, apply patches, run IDE commands, and execute tools.
  full,

  /// Plan-only mode: AI can analyze and plan, but cannot write files, run commands, or execute tools.
  /// This is equivalent to a dry run that generates plans and suggestions without side effects.
  planOnly,

  /// Review mode: AI can propose changes but all writes require explicit user approval.
  reviewRequired,

  /// Build-capable mode: AI can propose and apply patches, but building/running requires tool permission.
  buildCapable,
}

extension AgentExecutionModeX on AgentExecutionMode {
  String get wireValue {
    return switch (this) {
      AgentExecutionMode.full => 'full',
      AgentExecutionMode.planOnly => 'plan_only',
      AgentExecutionMode.reviewRequired => 'review_required',
      AgentExecutionMode.buildCapable => 'build_capable',
    };
  }

  /// Whether this mode allows any side effects (file writes, command execution).
  bool get allowsSideEffects {
    return switch (this) {
      AgentExecutionMode.full => true,
      AgentExecutionMode.planOnly => false,
      AgentExecutionMode.reviewRequired => true,
      AgentExecutionMode.buildCapable => true,
    };
  }

  /// Whether this mode allows building/running without explicit permission.
  bool get allowsBuildActions {
    return switch (this) {
      AgentExecutionMode.full => true,
      AgentExecutionMode.planOnly => false,
      AgentExecutionMode.reviewRequired => false,
      AgentExecutionMode.buildCapable => false,
    };
  }

  /// Whether plan-only requires explicit user override to proceed to execution.
  bool get requiresPlanOnlyOverride {
    return switch (this) {
      AgentExecutionMode.planOnly => true,
      _ => false,
    };
  }

  /// Whether build actions require explicit tool permission grants.
  bool get requiresBuildPermission {
    return switch (this) {
      AgentExecutionMode.buildCapable => true,
      _ => false,
    };
  }
}

/// Blocked reasons for an agent execution mode constraint.
enum AgentExecutionBlockedReason {
  /// Mode is plan-only; side effects are blocked.
  planOnlyBlocksWrite,

  /// Mode is plan-only; tool execution is blocked.
  planOnlyBlocksToolExecution,

  /// Mode is review-required; patches need explicit approval.
  reviewRequiredBlocksAutoApply,

  /// Build-capable mode requires build tool permission.
  buildCapableRequiresPermission,

  /// Mode is plan-only; IDE command execution is blocked.
  planOnlyBlocksIdeCommands,
}

extension AgentExecutionBlockedReasonX on AgentExecutionBlockedReason {
  String get wireValue {
    return switch (this) {
      AgentExecutionBlockedReason.planOnlyBlocksWrite => 'plan_only_blocks_write',
      AgentExecutionBlockedReason.planOnlyBlocksToolExecution =>
        'plan_only_blocks_tool_execution',
      AgentExecutionBlockedReason.reviewRequiredBlocksAutoApply =>
        'review_required_blocks_auto_apply',
      AgentExecutionBlockedReason.buildCapableRequiresPermission =>
        'build_capable_requires_permission',
      AgentExecutionBlockedReason.planOnlyBlocksIdeCommands =>
        'plan_only_blocks_ide_commands',
    };
  }

  String get displayMessage {
    return switch (this) {
      AgentExecutionBlockedReason.planOnlyBlocksWrite =>
        'Agent is in plan-only mode. File writes and patches are not allowed.',
      AgentExecutionBlockedReason.planOnlyBlocksToolExecution =>
        'Agent is in plan-only mode. AI tool execution is not allowed.',
      AgentExecutionBlockedReason.reviewRequiredBlocksAutoApply =>
        'Agent changes require explicit user review before applying.',
      AgentExecutionBlockedReason.buildCapableRequiresPermission =>
        'Build-capable mode requires explicit build tool permission.',
      AgentExecutionBlockedReason.planOnlyBlocksIdeCommands =>
        'Agent is in plan-only mode. IDE command execution is not allowed.',
    };
  }
}

/// Result of checking whether an action is allowed in the current execution mode.
class AgentExecutionModeCheckResult {
  const AgentExecutionModeCheckResult({
    required this.allowed,
    this.blockedReasons = const <AgentExecutionBlockedReason>[],
    this.requiredToolPermissions = const <String>[],
  });

  factory AgentExecutionModeCheckResult.allowed() {
    return const AgentExecutionModeCheckResult(allowed: true);
  }

  factory AgentExecutionModeCheckResult.blocked({
    AgentExecutionBlockedReason reason =
        AgentExecutionBlockedReason.planOnlyBlocksWrite,
    List<AgentExecutionBlockedReason> additionalReasons =
        const <AgentExecutionBlockedReason>[],
    List<String> requiredPermissions = const <String>[],
  }) {
    return AgentExecutionModeCheckResult(
      allowed: false,
      blockedReasons: <AgentExecutionBlockedReason>[reason, ...additionalReasons],
      requiredToolPermissions: requiredPermissions,
    );
  }

  final bool allowed;
  final List<AgentExecutionBlockedReason> blockedReasons;
  final List<String> requiredToolPermissions;

  List<String> get blockedReasonCodes =>
      blockedReasons.map((r) => r.wireValue).toList(growable: false);

  List<String> get blockedMessages =>
      blockedReasons.map((r) => r.displayMessage).toList(growable: false);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'allowed': allowed,
      if (!allowed) 'blockedReasonCodes': blockedReasonCodes,
      if (!allowed) 'blockedMessages': blockedMessages,
      if (requiredToolPermissions.isNotEmpty)
        'requiredToolPermissions': requiredToolPermissions,
    };
  }
}

/// Agent execution mode policy that governs what an agent can do.
class AgentExecutionModePolicy {
  const AgentExecutionModePolicy({
    this.mode = AgentExecutionMode.full,
    this.allowedToolPermissions = const <AgentToolPermissionAction>[],
    this.buildToolIds = const <String>[],
    this.planOnlyAllowedToolIds = const <String>[],
    this.planOnlyBlockedReason = '',
  });

  /// The current execution mode.
  final AgentExecutionMode mode;

  /// Tool permission actions that are explicitly allowed (for build-capable mode).
  final List<AgentToolPermissionAction> allowedToolPermissions;

  /// Tool IDs that count as "build" tools for build-capable mode.
  final List<String> buildToolIds;

  /// Tool IDs that are still allowed in plan-only mode (e.g., read-only tools).
  final List<String> planOnlyAllowedToolIds;

  /// Optional human-readable reason when plan-only mode is enforced.
  final String planOnlyBlockedReason;

  /// Check if a code patch (write) is allowed.
  AgentExecutionModeCheckResult checkPatchAllowed() {
    if (mode == AgentExecutionMode.planOnly) {
      return AgentExecutionModeCheckResult.blocked(
        reason: AgentExecutionBlockedReason.planOnlyBlocksWrite,
      );
    }
    if (mode == AgentExecutionMode.reviewRequired) {
      return AgentExecutionModeCheckResult.blocked(
        reason: AgentExecutionBlockedReason.reviewRequiredBlocksAutoApply,
      );
    }
    return AgentExecutionModeCheckResult.allowed();
  }

  /// Check if an IDE command execution is allowed.
  AgentExecutionModeCheckResult checkIdeCommandAllowed() {
    if (mode == AgentExecutionMode.planOnly) {
      return AgentExecutionModeCheckResult.blocked(
        reason: AgentExecutionBlockedReason.planOnlyBlocksIdeCommands,
      );
    }
    return AgentExecutionModeCheckResult.allowed();
  }

  /// Check if a tool call with the given tool ID and permissions is allowed.
  AgentExecutionModeCheckResult checkToolAllowed({
    required String toolId,
    required List<String> toolCapabilities,
    required AgentToolPermissionAction toolPermissionAction,
  }) {
    // Plan-only mode: only explicitly allowed tools are permitted.
    if (mode == AgentExecutionMode.planOnly) {
      if (planOnlyAllowedToolIds.contains(toolId)) {
        return AgentExecutionModeCheckResult.allowed();
      }
      return AgentExecutionModeCheckResult.blocked(
        reason: AgentExecutionBlockedReason.planOnlyBlocksToolExecution,
      );
    }

    // Build-capable mode: build tools need explicit permission.
    if (mode == AgentExecutionMode.buildCapable) {
      final isBuildTool =
          buildToolIds.contains(toolId) ||
          toolCapabilities.any(
            (cap) =>
                cap.contains('build') ||
                cap.contains('run') ||
                cap == 'destructive',
          );
      if (isBuildTool &&
          toolPermissionAction == AgentToolPermissionAction.deny) {
        return AgentExecutionModeCheckResult.blocked(
          reason: AgentExecutionBlockedReason.buildCapableRequiresPermission,
          requiredPermissions: <String>[toolId],
        );
      }
    }

    return AgentExecutionModeCheckResult.allowed();
  }

  AgentExecutionModePolicy withMode(AgentExecutionMode newMode) {
    return AgentExecutionModePolicy(
      mode: newMode,
      allowedToolPermissions: allowedToolPermissions,
      buildToolIds: buildToolIds,
      planOnlyAllowedToolIds: planOnlyAllowedToolIds,
      planOnlyBlockedReason: planOnlyBlockedReason,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': mode.wireValue,
      'allowsSideEffects': mode.allowsSideEffects,
      'allowsBuildActions': mode.allowsBuildActions,
      'requiresPlanOnlyOverride': mode.requiresPlanOnlyOverride,
      'requiresBuildPermission': mode.requiresBuildPermission,
      if (buildToolIds.isNotEmpty) 'buildToolIds': buildToolIds,
      if (planOnlyAllowedToolIds.isNotEmpty)
        'planOnlyAllowedToolIds': planOnlyAllowedToolIds,
      if (planOnlyBlockedReason.isNotEmpty)
        'planOnlyBlockedReason': planOnlyBlockedReason,
    };
  }
}
