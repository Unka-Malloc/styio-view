/// Sandboxed tool router for AI tool execution.
///
/// Routes AI tool calls through a sandboxed execution pipeline instead of
/// allowing direct shell or file system access. This is a critical safety
/// layer that enforces permissions, capability checks, and execution mode
/// constraints before any tool reaches the underlying executor.
///
/// Key invariants:
/// - AI tool execution goes through this sandboxed router, NOT the underlying
///   transport directly.
/// - Each tool call is validated against permissions, capabilities, and mode.
/// - Tool execution context includes the agent execution mode policy.
/// - Build/run tools require explicit tool permission grants.
/// - Tool output is checked for size limits before returning to the adapter.
/// - All tool calls are logged for audit.
library;

import 'agent_execution_mode.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_permission.dart';
import 'agent_tool_registry.dart';

/// Result of a sandboxed tool call.
class SandboxedToolResult {
  const SandboxedToolResult({
    required this.callId,
    required this.toolId,
    required this.success,
    this.output = '',
    this.error,
    this.metadata = const <String, Object?>{},
    this.blocked = false,
    this.blockedReasons = const <String>[],
  });

  factory SandboxedToolResult.blocked({
    required String callId,
    required String toolId,
    required List<String> reasons,
  }) {
    return SandboxedToolResult(
      callId: callId,
      toolId: toolId,
      success: false,
      blocked: true,
      blockedReasons: reasons,
      error: 'Tool execution blocked: ${reasons.join("; ")}.',
    );
  }

  final String callId;
  final String toolId;
  final bool success;
  final String output;
  final String? error;
  final Map<String, Object?> metadata;
  final bool blocked;
  final List<String> blockedReasons;

  bool get failed => !success;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'success': success,
      if (blocked) 'blocked': blocked,
      if (blockedReasons.isNotEmpty) 'blockedReasons': blockedReasons,
      if (output.isNotEmpty) 'output': output,
      if (error != null) 'error': error,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Sandbox validation report for a single tool call.
class SandboxToolValidationReport {
  const SandboxToolValidationReport({
    required this.allowed,
    this.reasons = const <String>[],
  });

  final bool allowed;
  final List<String> reasons;

  bool get blocked => !allowed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'allowed': allowed,
      if (!allowed) 'reasons': reasons,
    };
  }
}

/// Callback type for executing a sandboxed tool call.
typedef SandboxToolExecutor = Future<SandboxedToolResult> Function({
  required String callId,
  required String toolId,
  required String input,
  required Map<String, Object?> metadata,
});

/// Sanboxed tool router that enforces permissions and execution mode constraints.
class AgentToolSandboxRouter {
  AgentToolSandboxRouter({
    required this.executor,
    this.permissionPolicy = const AgentToolPermissionPlan(
      status: AgentToolPermissionPlanStatus.ready,
      decisions: <AgentToolPermissionDecision>[],
    ),
    this.executionModePolicy = const AgentExecutionModePolicy(),
    this.maxOutputLength = 100000,
    this.sensitiveCapabilities = _defaultSensitiveCapabilities,
    this.auditEnabled = true,
    AgentToolRegistry? toolRegistry,
  }) : _toolRegistry = toolRegistry ?? AgentToolRegistry();

  /// The underlying tool executor (NOT direct shell access).
  final SandboxToolExecutor executor;

  /// Tool permission policy for executing tools.
  final AgentToolPermissionPlan permissionPolicy;

  /// Agent execution mode policy (plan-only, build-capable, etc.).
  final AgentExecutionModePolicy executionModePolicy;

  /// Registry of known tools with their capabilities and schemas.
  final AgentToolRegistry _toolRegistry;

  /// Public accessor for the tool registry.
  AgentToolRegistry get toolRegistry => _toolRegistry;

  /// Maximum output length for any tool call result.
  final int maxOutputLength;

  /// Capabilities considered "sensitive" (require explicit permission).
  static const Set<String> _defaultSensitiveCapabilities = <String>{
    'destructive',
    'network',
    'openWorld',
    'runtime.shell',
    'build',
    'workspace.patch.apply',
    'ide.command',
  };

  final Set<String> sensitiveCapabilities;

  /// Whether to log audit events for tool calls.
  final bool auditEnabled;

  /// The audit log for this router session.
  final List<SandboxedToolResult> _auditLog = <SandboxedToolResult>[];

  List<SandboxedToolResult> get auditLog =>
      List<SandboxedToolResult>.unmodifiable(_auditLog);

  /// Execute a tool call through the sandboxed router.
  Future<SandboxedToolResult> execute({
    required String callId,
    required String toolId,
    required String input,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    // Step 1: Validate against execution mode
    final modeCheck = _validateExecutionMode(toolId: toolId, input: input);
    if (modeCheck.blocked) {
      final result = SandboxedToolResult.blocked(
        callId: callId,
        toolId: toolId,
        reasons: modeCheck.reasons,
      );
      _logIfAuditEnabled(result);
      return result;
    }

    // Step 2: Validate against tool permissions
    final permissionCheck = _validateToolPermission(
      toolId: toolId,
      input: input,
    );
    if (permissionCheck.blocked) {
      final result = SandboxedToolResult.blocked(
        callId: callId,
        toolId: toolId,
        reasons: permissionCheck.reasons,
      );
      _logIfAuditEnabled(result);
      return result;
    }

    // Step 3: Validate against capabilities and sensitive operations
    final capabilityCheck = _validateCapabilities(
      toolId: toolId,
      input: input,
    );
    if (capabilityCheck.blocked) {
      final result = SandboxedToolResult.blocked(
        callId: callId,
        toolId: toolId,
        reasons: capabilityCheck.reasons,
      );
      _logIfAuditEnabled(result);
      return result;
    }

    // Step 4: Execute through the sandboxed executor
    try {
      final result = await executor(
        callId: callId,
        toolId: toolId,
        input: input,
        metadata: metadata,
      );

      // Step 5: Validate output size
      final trimmedResult = _validateOutput(result);

      _logIfAuditEnabled(trimmedResult);
      return trimmedResult;
    } on Object catch (error) {
      final result = SandboxedToolResult(
        callId: callId,
        toolId: toolId,
        success: false,
        error: 'Sandboxed tool execution failed: $error',
        metadata: <String, Object?>{
          ...metadata,
          'sandboxError': error.toString(),
        },
      );
      _logIfAuditEnabled(result);
      return result;
    }
  }

  SandboxToolValidationReport _validateExecutionMode({
    required String toolId,
    required String input,
  }) {
    // Find the tool definition to check capabilities
    final tool = _findTool(toolId);
    final capabilities = tool?.capabilities ?? <String>[];
    final permission = _findToolPermission(toolId);

    final result = executionModePolicy.checkToolAllowed(
      toolId: toolId,
      toolCapabilities: capabilities,
      toolPermissionAction: permission,
    );

    if (!result.allowed) {
      return SandboxToolValidationReport(
        allowed: false,
        reasons: result.blockedMessages,
      );
    }

    // Check if this is a write/patch action and mode allows it
    if (capabilities.any((c) => c.contains('patch') || c.contains('write')) &&
        !executionModePolicy.mode.allowsSideEffects) {
      return SandboxToolValidationReport(
        allowed: false,
        reasons: <String>[
          'Tool $toolId performs write operations, which are not allowed in '
          '${executionModePolicy.mode.wireValue} mode.',
        ],
      );
    }

    // Check IDE command execution against mode
    if (capabilities.contains('ide.command') &&
        executionModePolicy.mode == AgentExecutionMode.planOnly) {
      return SandboxToolValidationReport(
        allowed: false,
        reasons: <String>[
          AgentExecutionBlockedReason.planOnlyBlocksIdeCommands.displayMessage,
        ],
      );
    }

    return const SandboxToolValidationReport(allowed: true);
  }

  SandboxToolValidationReport _validateToolPermission({
    required String toolId,
    required String input,
  }) {
    final decision = permissionPolicy.decisions
        .where((d) => d.toolId == toolId)
        .toList(growable: false);

    if (decision.isEmpty) {
      // Unknown tool — check with deny-by-default for executable actions
      return SandboxToolValidationReport(
        allowed: false,
        reasons: <String>[
          'Tool $toolId is not registered in the tool permission plan.',
        ],
      );
    }

    final blockedDecisions =
        decision.where((d) => d.blocksDispatch).toList(growable: false);
    if (blockedDecisions.isNotEmpty) {
      return SandboxToolValidationReport(
        allowed: false,
        reasons: blockedDecisions.map((d) => d.reason).toList(growable: false),
      );
    }

    final reviewDecisions =
        decision.where((d) => d.requiresReview).toList(growable: false);
    if (reviewDecisions.isNotEmpty) {
      // Review-required tools are allowed through sandbox but logged for review
    }

    return const SandboxToolValidationReport(allowed: true);
  }

  SandboxToolValidationReport _validateCapabilities({
    required String toolId,
    required String input,
  }) {
    final tool = _findTool(toolId);
    if (tool == null) {
      return const SandboxToolValidationReport(allowed: true);
    }
    final caps = tool.capabilities.toSet();

    // Check for sensitive capabilities that might need additional checks
    final matchedSensitive = sensitiveCapabilities.intersection(caps);
    if (matchedSensitive.isNotEmpty) {
      // Sensitive capabilities are logged for audit
      // But they are allowed if permission check passed
    }

    return const SandboxToolValidationReport(allowed: true);
  }

  AgentToolDefinition? _findTool(String toolId) {
    try {
      return toolRegistry.tools
          .where((t) => t.toolId == toolId)
          .toList(growable: false)
          .firstOrNull;
    } on Object {
      return null;
    }
  }

  AgentToolPermissionAction _findToolPermission(String toolId) {
    final decisions = permissionPolicy.decisions
        .where((d) => d.toolId == toolId)
        .toList(growable: false);
    if (decisions.isEmpty) {
      return AgentToolPermissionAction.deny;
    }
    // If any decision says deny, tool is denied
    if (decisions.any((d) => d.action == AgentToolPermissionAction.deny)) {
      return AgentToolPermissionAction.deny;
    }
    // If any says ask, require review
    if (decisions.any((d) => d.action == AgentToolPermissionAction.ask)) {
      return AgentToolPermissionAction.ask;
    }
    return AgentToolPermissionAction.allow;
  }

  SandboxedToolResult _validateOutput(SandboxedToolResult result) {
    if (!result.success || result.output.length <= maxOutputLength) {
      return result;
    }
    final truncated = result.output.substring(0, maxOutputLength);
    return SandboxedToolResult(
      callId: result.callId,
      toolId: result.toolId,
      success: result.success,
      output: truncated,
      metadata: <String, Object?>{
        ...result.metadata,
        'outputTruncated': true,
        'outputOriginalLength': result.output.length,
        'outputLimit': maxOutputLength,
        'outputOmittedLength': result.output.length - maxOutputLength,
      },
      error: result.error,
      blocked: result.blocked,
      blockedReasons: result.blockedReasons,
    );
  }

  void _logIfAuditEnabled(SandboxedToolResult result) {
    if (auditEnabled) {
      _auditLog.add(result);
    }
  }

  /// Create an AgentToolCallEvent from a sandboxed tool result.
  AgentToolCallEvent toToolCallEvent(SandboxedToolResult result) {
    return AgentToolCallEvent.callStarted(
      callId: result.callId,
      toolId: result.toolId,
      input: result.output,
      metadata: <String, Object?>{
        'source': 'sandboxed-tool-router',
        'blocked': result.blocked,
        if (result.blockedReasons.isNotEmpty)
          'blockedReasons': result.blockedReasons,
        if (result.error != null) 'error': result.error!,
      },
    );
  }
}
