enum AgentSessionStatus {
  idle,
  active,
  waitingForPermission,
  completed,
  failed,
  cancelled,
}

enum AgentMessageRole { system, user, assistant, tool }

enum AgentMessagePartKind {
  text,
  fileReference,
  diagnostics,
  runtime,
  toolResult,
}

enum ToolInvocationStatus {
  pending,
  running,
  waitingForPermission,
  completed,
  failed,
  cancelled,
}

enum PermissionRequestScope {
  readOnly,
  workspaceWrite,
  toolchainManaged,
  network,
  destructive,
  openWorld,
  fullAccessDisabledByDefault,
}

enum PermissionDecision {
  pending,
  allowOnce,
  allowForSession,
  deny,
  cancel,
}

enum AgentAuditEventKind {
  sessionCreated,
  turnStarted,
  toolRequested,
  permissionRequested,
  permissionDecided,
  patchPreviewed,
  patchApplied,
  commandExited,
  diagnosticsReported,
}

class AgentMessagePart {
  const AgentMessagePart({
    required this.kind,
    this.text = '',
    this.metadata = const <String, Object?>{},
  });

  final AgentMessagePartKind kind;
  final String text;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'text': text,
      'metadata': metadata,
    };
  }
}

class AgentTurn {
  const AgentTurn({
    required this.turnId,
    required this.role,
    required this.parts,
    required this.createdAtIso8601,
  });

  final String turnId;
  final AgentMessageRole role;
  final List<AgentMessagePart> parts;
  final String createdAtIso8601;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'turnId': turnId,
      'role': role.name,
      'parts': parts.map((part) => part.toJson()).toList(growable: false),
      'createdAtIso8601': createdAtIso8601,
    };
  }
}

class ToolInvocation {
  const ToolInvocation({
    required this.invocationId,
    required this.toolName,
    required this.scope,
    required this.status,
    this.arguments = const <String, Object?>{},
    this.result = const <String, Object?>{},
  });

  final String invocationId;
  final String toolName;
  final PermissionRequestScope scope;
  final ToolInvocationStatus status;
  final Map<String, Object?> arguments;
  final Map<String, Object?> result;

  ToolInvocation copyWith({
    ToolInvocationStatus? status,
    Map<String, Object?>? result,
  }) {
    return ToolInvocation(
      invocationId: invocationId,
      toolName: toolName,
      scope: scope,
      status: status ?? this.status,
      arguments: arguments,
      result: result ?? this.result,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'invocationId': invocationId,
      'toolName': toolName,
      'scope': scope.name,
      'status': status.name,
      'arguments': arguments,
      'result': result,
    };
  }
}

class PermissionRequest {
  const PermissionRequest({
    required this.requestId,
    required this.scope,
    required this.reason,
    required this.createdAtIso8601,
    this.toolInvocationId,
    this.decision = PermissionDecision.pending,
  });

  final String requestId;
  final PermissionRequestScope scope;
  final String reason;
  final String createdAtIso8601;
  final String? toolInvocationId;
  final PermissionDecision decision;

  bool get isPending => decision == PermissionDecision.pending;

  PermissionRequest decide(PermissionDecision decision) {
    return PermissionRequest(
      requestId: requestId,
      scope: scope,
      reason: reason,
      createdAtIso8601: createdAtIso8601,
      toolInvocationId: toolInvocationId,
      decision: decision,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'scope': scope.name,
      'reason': reason,
      'createdAtIso8601': createdAtIso8601,
      'toolInvocationId': toolInvocationId,
      'decision': decision.name,
    };
  }
}

class FileChange {
  const FileChange({
    required this.path,
    required this.editCount,
    required this.summary,
    this.beforeContentHash,
    this.afterContentHash,
  });

  final String path;
  final int editCount;
  final String summary;
  final String? beforeContentHash;
  final String? afterContentHash;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'editCount': editCount,
      'summary': summary,
      'beforeContentHash': beforeContentHash,
      'afterContentHash': afterContentHash,
    };
  }
}

class FileChangePreview {
  const FileChangePreview({
    required this.previewId,
    required this.source,
    required this.changes,
    this.affectedSymbols = const <String>[],
  });

  final String previewId;
  final String source;
  final List<FileChange> changes;
  final List<String> affectedSymbols;

  int get editCount {
    return changes.fold(0, (count, change) => count + change.editCount);
  }

  int get changedFileCount => changes.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'previewId': previewId,
      'source': source,
      'changes': changes
          .map((change) => change.toJson())
          .toList(growable: false),
      'affectedSymbols': affectedSymbols,
    };
  }
}

class PatchApplyPlan {
  const PatchApplyPlan({
    required this.planId,
    required this.preview,
    required this.permissionRequest,
  });

  final String planId;
  final FileChangePreview preview;
  final PermissionRequest permissionRequest;

  bool get canApply =>
      permissionRequest.decision == PermissionDecision.allowOnce ||
      permissionRequest.decision == PermissionDecision.allowForSession;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'preview': preview.toJson(),
      'permissionRequest': permissionRequest.toJson(),
      'canApply': canApply,
    };
  }
}

class AgentAuditEvent {
  const AgentAuditEvent({
    required this.eventId,
    required this.kind,
    required this.sessionId,
    required this.createdAtIso8601,
    this.turnId,
    this.details = const <String, Object?>{},
  });

  final String eventId;
  final AgentAuditEventKind kind;
  final String sessionId;
  final String createdAtIso8601;
  final String? turnId;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'eventId': eventId,
      'kind': kind.name,
      'sessionId': sessionId,
      'turnId': turnId,
      'createdAtIso8601': createdAtIso8601,
      'details': details,
    };
  }
}

class AgentSession {
  const AgentSession({
    required this.sessionId,
    required this.profileId,
    required this.status,
    required this.turns,
    required this.toolInvocations,
    required this.permissionRequests,
    required this.auditEvents,
  });

  final String sessionId;
  final String profileId;
  final AgentSessionStatus status;
  final List<AgentTurn> turns;
  final List<ToolInvocation> toolInvocations;
  final List<PermissionRequest> permissionRequests;
  final List<AgentAuditEvent> auditEvents;

  AgentSession copyWith({
    AgentSessionStatus? status,
    List<AgentTurn>? turns,
    List<ToolInvocation>? toolInvocations,
    List<PermissionRequest>? permissionRequests,
    List<AgentAuditEvent>? auditEvents,
  }) {
    return AgentSession(
      sessionId: sessionId,
      profileId: profileId,
      status: status ?? this.status,
      turns: turns ?? this.turns,
      toolInvocations: toolInvocations ?? this.toolInvocations,
      permissionRequests: permissionRequests ?? this.permissionRequests,
      auditEvents: auditEvents ?? this.auditEvents,
    );
  }

  AgentSession appendAuditEvent(AgentAuditEvent event) {
    return copyWith(
      auditEvents: List<AgentAuditEvent>.unmodifiable(
        <AgentAuditEvent>[...auditEvents, event],
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'profileId': profileId,
      'status': status.name,
      'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
      'toolInvocations': toolInvocations
          .map((invocation) => invocation.toJson())
          .toList(growable: false),
      'permissionRequests': permissionRequests
          .map((request) => request.toJson())
          .toList(growable: false),
      'auditEvents': auditEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }
}
