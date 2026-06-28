/// Models for Agent context snapshot, scope, redaction,
/// action plan, and workspace edit application.
///
/// These models keep the Agent within Vityo's product boundaries:
/// - Agent consumes structured context, not raw filesystem access
/// - Agent actions go through command registry or workspace edit transactions
/// - Agent never bypasses the Source Buffer / Document Model
/// - Secrets and tokens are redacted from context snapshots
library;

import '../commands/app_commands.dart';
import '../environment/configuration/log_redactor.dart';
import 'agent_session.dart';

final LogRedactor _agentContextSnapshotRedactor = LogRedactor();

Map<String, Object?> _redactAgentContextSnapshotJson(
  Map<String, Object?> json,
) {
  return _agentContextSnapshotRedactor.redactJson(json);
}

// ── Context Scope ─────────────────────────────────────────────────

/// Controls which context channels the agent receives.
class AgentContextScope {
  const AgentContextScope({
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
    this.includeWorkspace = true,
    this.includeActiveDocument = true,
    this.includeSelection = true,
    this.includeDiagnostics = true,
    this.includeProjectGraph = true,
    this.includeRuntimeEvents = true,
    this.includeCommands = true,
    this.includeCapabilityGaps = true,
    this.includeSettings = false,
    this.includeProfile = false,
  });

  final int schemaVersion;
  final Map<String, Object?> extensions;
  final bool includeWorkspace;
  final bool includeActiveDocument;
  final bool includeSelection;
  final bool includeDiagnostics;
  final bool includeProjectGraph;
  final bool includeRuntimeEvents;
  final bool includeCommands;
  final bool includeCapabilityGaps;
  final bool includeSettings;
  final bool includeProfile;

  static const AgentContextScope full = AgentContextScope();
  static const AgentContextScope minimal = AgentContextScope(
    includeDiagnostics: false,
    includeProjectGraph: false,
    includeRuntimeEvents: false,
    includeCommands: false,
    includeCapabilityGaps: false,
  );

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'includeWorkspace',
    'includeActiveDocument',
    'includeSelection',
    'includeDiagnostics',
    'includeProjectGraph',
    'includeRuntimeEvents',
    'includeCommands',
    'includeCapabilityGaps',
    'includeSettings',
    'includeProfile',
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'includeWorkspace': includeWorkspace,
    'includeActiveDocument': includeActiveDocument,
    'includeSelection': includeSelection,
    'includeDiagnostics': includeDiagnostics,
    'includeProjectGraph': includeProjectGraph,
    'includeRuntimeEvents': includeRuntimeEvents,
    'includeCommands': includeCommands,
    'includeCapabilityGaps': includeCapabilityGaps,
    'includeSettings': includeSettings,
    'includeProfile': includeProfile,
    ...extensions,
  };

  factory AgentContextScope.fromJson(Map<String, Object?> json) {
    return AgentContextScope(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
      includeWorkspace: json['includeWorkspace'] as bool? ?? true,
      includeActiveDocument: json['includeActiveDocument'] as bool? ?? true,
      includeSelection: json['includeSelection'] as bool? ?? true,
      includeDiagnostics: json['includeDiagnostics'] as bool? ?? true,
      includeProjectGraph: json['includeProjectGraph'] as bool? ?? true,
      includeRuntimeEvents: json['includeRuntimeEvents'] as bool? ?? true,
      includeCommands: json['includeCommands'] as bool? ?? true,
      includeCapabilityGaps: json['includeCapabilityGaps'] as bool? ?? true,
      includeSettings: json['includeSettings'] as bool? ?? false,
      includeProfile: json['includeProfile'] as bool? ?? false,
    );
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

// ── Redaction ─────────────────────────────────────────────────────

/// Policy controlling what is redacted from agent context snapshots.
class AgentRedactionPolicy {
  const AgentRedactionPolicy({
    this.redactEnvironmentVariableValues = true,
    this.redactApiKeyReferences = true,
    this.redactHomeDirectoryPaths = true,
    this.redactUserSpecificPaths = true,
    this.redactSecretFields = true,
    this.additionalPatterns = const <String>[],
  });

  /// Replace env var values with '[REDACTED]'.
  final bool redactEnvironmentVariableValues;

  /// Replace API key references (env var names like *_API_KEY) with '[SECRET]'.
  final bool redactApiKeyReferences;

  /// Replace user-home paths such as /home/[user], /Users/[user], and C:\Users\[user].
  final bool redactHomeDirectoryPaths;

  /// Replace other user-specific paths (Desktop, Documents, etc.).
  final bool redactUserSpecificPaths;

  /// Replace fields named 'secret', 'token', 'key', 'password', 'apiKey'.
  final bool redactSecretFields;

  /// Additional regex patterns to redact.
  final List<String> additionalPatterns;

  /// Default policy: redact all sensitive content.
  static const AgentRedactionPolicy defaultPolicy = AgentRedactionPolicy();

  /// Minimal policy: only redact API keys. For local-only agent use
  /// where full paths may be needed for tool execution.
  static const AgentRedactionPolicy localOnly = AgentRedactionPolicy(
    redactHomeDirectoryPaths: false,
    redactUserSpecificPaths: false,
    redactSecretFields: false,
    redactEnvironmentVariableValues: false,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'redactEnvironmentVariableValues': redactEnvironmentVariableValues,
    'redactApiKeyReferences': redactApiKeyReferences,
    'redactHomeDirectoryPaths': redactHomeDirectoryPaths,
    'redactUserSpecificPaths': redactUserSpecificPaths,
    'redactSecretFields': redactSecretFields,
    'additionalPatterns': additionalPatterns,
  };
}

// ── Context Channel Payloads ──────────────────────────────────────

/// Summary of the active workspace for agent context.
class AgentWorkspaceSummaryContext {
  const AgentWorkspaceSummaryContext({
    this.workspaceRoot = '',
    this.memberCount = 0,
    this.activeFilePath = '',
    this.activeFileLanguage = 'styio',
    this.openDocumentPaths = const <String>[],
  });

  final String workspaceRoot;
  final int memberCount;
  final String activeFilePath;
  final String activeFileLanguage;
  final List<String> openDocumentPaths;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceRoot': workspaceRoot,
    'memberCount': memberCount,
    'activeFilePath': activeFilePath,
    'activeFileLanguage': activeFileLanguage,
    'openDocumentPaths': openDocumentPaths,
  };
}

/// Active document context (redacted Source Buffer excerpt).
class AgentActiveDocumentContext {
  const AgentActiveDocumentContext({
    this.filePath = '',
    this.language = 'styio',
    this.lineCount = 0,
    this.selectionStartOffset = -1,
    this.selectionEndOffset = -1,
    this.selectionText = '',
    this.selectedSymbolName = '',
  });

  final String filePath;
  final String language;
  final int lineCount;
  final int selectionStartOffset;
  final int selectionEndOffset;
  final String selectionText;
  final String selectedSymbolName;

  bool get hasSelection => selectionStartOffset >= 0 && selectionEndOffset >= 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'filePath': filePath,
    'language': language,
    'lineCount': lineCount,
    'selectionStartOffset': selectionStartOffset,
    'selectionEndOffset': selectionEndOffset,
    'selectionText': selectionText,
    'selectedSymbolName': selectedSymbolName,
  };
}

/// Diagnostic context summary for agent.
class AgentDiagnosticsContext {
  const AgentDiagnosticsContext({
    this.errorCount = 0,
    this.warningCount = 0,
    this.hintCount = 0,
    this.fileCount = 0,
    this.topErrors = const <String>[],
  });

  final int errorCount;
  final int warningCount;
  final int hintCount;
  final int fileCount;
  final List<String> topErrors;

  Map<String, Object?> toJson() => <String, Object?>{
    'errorCount': errorCount,
    'warningCount': warningCount,
    'hintCount': hintCount,
    'fileCount': fileCount,
    'topErrors': topErrors,
  };
}

/// Project graph summary for agent context.
class AgentProjectGraphContext {
  const AgentProjectGraphContext({
    this.projectTitle = '',
    this.projectKind = '',
    this.packageCount = 0,
    this.targetCount = 0,
    this.dependencyCount = 0,
    this.lockState = '',
    this.vendorState = '',
    this.toolchainChannel = '',
    this.toolchainVersion = '',
    this.graphSource = '',
    this.blockedInfo = const <String>[],
  });

  final String projectTitle;
  final String projectKind;
  final int packageCount;
  final int targetCount;
  final int dependencyCount;
  final String lockState;
  final String vendorState;
  final String toolchainChannel;
  final String toolchainVersion;
  final String graphSource;
  final List<String> blockedInfo;

  Map<String, Object?> toJson() => <String, Object?>{
    'projectTitle': projectTitle,
    'projectKind': projectKind,
    'packageCount': packageCount,
    'targetCount': targetCount,
    'dependencyCount': dependencyCount,
    'lockState': lockState,
    'vendorState': vendorState,
    'toolchainChannel': toolchainChannel,
    'toolchainVersion': toolchainVersion,
    'graphSource': graphSource,
    'blockedInfo': blockedInfo,
  };
}

/// Runtime event summary for agent context.
class AgentRuntimeSummaryContext {
  const AgentRuntimeSummaryContext({
    this.lastRunStatus = '',
    this.lastRunUnitRange = '',
    this.lastRunSessionId = '',
    this.eventCount = 0,
    this.compileErrorCount = 0,
    this.testFailCount = 0,
    this.laneStatuses = const <String, String>{},
  });

  final String lastRunStatus;
  final String lastRunUnitRange;
  final String lastRunSessionId;
  final int eventCount;
  final int compileErrorCount;
  final int testFailCount;
  final Map<String, String> laneStatuses;

  Map<String, Object?> toJson() => <String, Object?>{
    'lastRunStatus': lastRunStatus,
    'lastRunUnitRange': lastRunUnitRange,
    'lastRunSessionId': lastRunSessionId,
    'eventCount': eventCount,
    'compileErrorCount': compileErrorCount,
    'testFailCount': testFailCount,
    'laneStatuses': laneStatuses,
  };
}

/// Capability gap summary for agent context.
class AgentCapabilityGapContext {
  const AgentCapabilityGapContext({
    this.missingCapabilities = const <String>[],
    this.degradedCapabilities = const <String>[],
    this.upstreamBlocked = const <String>[],
    this.availableCapabilities = const <String>[],
  });

  final List<String> missingCapabilities;
  final List<String> degradedCapabilities;
  final List<String> upstreamBlocked;
  final List<String> availableCapabilities;

  bool get hasBlockers => missingCapabilities.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'missingCapabilities': missingCapabilities,
    'degradedCapabilities': degradedCapabilities,
    'upstreamBlocked': upstreamBlocked,
    'availableCapabilities': availableCapabilities,
  };
}

/// Agent-visible command catalog snapshot.
class AgentCommandSummaryContext {
  const AgentCommandSummaryContext({
    this.availableCommandCount = 0,
    this.blockedCommandCount = 0,
    this.availableCommandIds = const <String>[],
    this.blockedCommands = const <String, String>{},
  });

  final int availableCommandCount;
  final int blockedCommandCount;
  final List<String> availableCommandIds;
  final Map<String, String> blockedCommands;

  Map<String, Object?> toJson() => <String, Object?>{
    'availableCommandCount': availableCommandCount,
    'blockedCommandCount': blockedCommandCount,
    'availableCommandIds': availableCommandIds,
    'blockedCommands': blockedCommands,
  };
}

// ── Agent Context Snapshot ────────────────────────────────────────

/// The complete context snapshot consumed by the Agent.
/// Serializable, redactable, and scope-filterable.
class AgentContextSnapshot {
  const AgentContextSnapshot({
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
    this.snapshotId = '',
    this.createdAtIso8601 = '',
    this.scope = AgentContextScope.full,
    this.workspaceContext,
    this.documentContext,
    this.diagnosticsContext,
    this.projectGraphContext,
    this.runtimeContext,
    this.commandCatalogContext,
    this.capabilityGapContext,
    this.settingsSummary = const <String, String>{},
    this.profileId = '',
    this.redactionPolicy = AgentRedactionPolicy.defaultPolicy,
  });

  final int schemaVersion;
  final Map<String, Object?> extensions;
  final String snapshotId;
  final String createdAtIso8601;
  final AgentContextScope scope;
  final AgentWorkspaceSummaryContext? workspaceContext;
  final AgentActiveDocumentContext? documentContext;
  final AgentDiagnosticsContext? diagnosticsContext;
  final AgentProjectGraphContext? projectGraphContext;
  final AgentRuntimeSummaryContext? runtimeContext;
  final AgentCommandSummaryContext? commandCatalogContext;
  final AgentCapabilityGapContext? capabilityGapContext;
  final Map<String, String> settingsSummary;
  final String profileId;
  final AgentRedactionPolicy redactionPolicy;

  bool get hasWorkspace => scope.includeWorkspace && workspaceContext != null;
  bool get hasDocument =>
      scope.includeActiveDocument && documentContext != null;
  bool get hasSelection =>
      scope.includeSelection &&
      documentContext != null &&
      documentContext!.hasSelection;
  bool get hasDiagnostics =>
      scope.includeDiagnostics && diagnosticsContext != null;
  bool get hasProjectGraph =>
      scope.includeProjectGraph && projectGraphContext != null;
  bool get hasRuntime => scope.includeRuntimeEvents && runtimeContext != null;
  bool get hasCommands =>
      scope.includeCommands && commandCatalogContext != null;
  bool get hasCapabilityGaps =>
      scope.includeCapabilityGaps && capabilityGapContext != null;

  /// Projects a display-safe summary (secrets redacted, paths normalized)
  /// suitable for rendering in the Agent panel.
  AgentContextSummary toDisplaySummary() {
    return AgentContextSummary(
      workspace: _agentContextSnapshotRedactor.redact(
        workspaceContext?.workspaceRoot ?? '',
      ),
      activeFile: _agentContextSnapshotRedactor.redact(
        documentContext?.filePath ?? '',
      ),
      hasSelection: hasSelection,
      errorCount: diagnosticsContext?.errorCount ?? 0,
      warningCount: diagnosticsContext?.warningCount ?? 0,
      project: projectGraphContext?.projectTitle ?? '',
      lastRun: runtimeContext?.lastRunStatus ?? '',
      availableCommands: commandCatalogContext?.availableCommandCount ?? 0,
      blockedCount: commandCatalogContext?.blockedCommandCount ?? 0,
      hasCapabilityBlockers: capabilityGapContext?.hasBlockers ?? false,
    );
  }

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'snapshotId',
    'createdAtIso8601',
    'scope',
    'workspaceContext',
    'documentContext',
    'diagnosticsContext',
    'projectGraphContext',
    'runtimeContext',
    'commandCatalogContext',
    'capabilityGapContext',
    'settingsSummary',
    'profileId',
    'redactionPolicy',
  };

  Map<String, Object?> toJson() =>
      _redactAgentContextSnapshotJson(<String, Object?>{
        'schemaVersion': schemaVersion,
        'snapshotId': snapshotId,
        'createdAtIso8601': createdAtIso8601,
        'scope': scope.toJson(),
        'workspaceContext': workspaceContext?.toJson(),
        'documentContext': documentContext?.toJson(),
        'diagnosticsContext': diagnosticsContext?.toJson(),
        'projectGraphContext': projectGraphContext?.toJson(),
        'runtimeContext': runtimeContext?.toJson(),
        'commandCatalogContext': commandCatalogContext?.toJson(),
        'capabilityGapContext': capabilityGapContext?.toJson(),
        'settingsSummary': settingsSummary,
        'profileId': profileId,
        'redactionPolicy': redactionPolicy.toJson(),
        ...extensions,
      });

  factory AgentContextSnapshot.fromJson(Map<String, Object?> json) {
    return AgentContextSnapshot(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
      snapshotId: json['snapshotId'] as String? ?? '',
      createdAtIso8601: json['createdAtIso8601'] as String? ?? '',
      scope: json['scope'] != null
          ? AgentContextScope.fromJson(
              Map<String, Object?>.from(json['scope'] as Map),
            )
          : AgentContextScope.full,
      workspaceContext: json['workspaceContext'] != null
          ? AgentWorkspaceSummaryContext(
              workspaceRoot:
                  (json['workspaceContext'] as Map)['workspaceRoot']
                      as String? ??
                  '',
              memberCount:
                  (json['workspaceContext'] as Map)['memberCount'] as int? ?? 0,
              activeFilePath:
                  (json['workspaceContext'] as Map)['activeFilePath']
                      as String? ??
                  '',
              activeFileLanguage:
                  (json['workspaceContext'] as Map)['activeFileLanguage']
                      as String? ??
                  'styio',
              openDocumentPaths:
                  ((json['workspaceContext'] as Map)['openDocumentPaths']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
            )
          : null,
      documentContext: json['documentContext'] != null
          ? AgentActiveDocumentContext(
              filePath:
                  (json['documentContext'] as Map)['filePath'] as String? ?? '',
              language:
                  (json['documentContext'] as Map)['language'] as String? ??
                  'styio',
              lineCount:
                  (json['documentContext'] as Map)['lineCount'] as int? ?? 0,
              selectionStartOffset:
                  (json['documentContext'] as Map)['selectionStartOffset']
                      as int? ??
                  -1,
              selectionEndOffset:
                  (json['documentContext'] as Map)['selectionEndOffset']
                      as int? ??
                  -1,
              selectionText:
                  (json['documentContext'] as Map)['selectionText']
                      as String? ??
                  '',
              selectedSymbolName:
                  (json['documentContext'] as Map)['selectedSymbolName']
                      as String? ??
                  '',
            )
          : null,
      diagnosticsContext: json['diagnosticsContext'] != null
          ? AgentDiagnosticsContext(
              errorCount:
                  (json['diagnosticsContext'] as Map)['errorCount'] as int? ??
                  0,
              warningCount:
                  (json['diagnosticsContext'] as Map)['warningCount'] as int? ??
                  0,
              hintCount:
                  (json['diagnosticsContext'] as Map)['hintCount'] as int? ?? 0,
              fileCount:
                  (json['diagnosticsContext'] as Map)['fileCount'] as int? ?? 0,
              topErrors:
                  ((json['diagnosticsContext'] as Map)['topErrors'] as List?)
                      ?.cast<String>() ??
                  const <String>[],
            )
          : null,
      projectGraphContext: json['projectGraphContext'] != null
          ? AgentProjectGraphContext(
              projectTitle:
                  (json['projectGraphContext'] as Map)['projectTitle']
                      as String? ??
                  '',
              projectKind:
                  (json['projectGraphContext'] as Map)['projectKind']
                      as String? ??
                  '',
              packageCount:
                  (json['projectGraphContext'] as Map)['packageCount']
                      as int? ??
                  0,
              targetCount:
                  (json['projectGraphContext'] as Map)['targetCount'] as int? ??
                  0,
              dependencyCount:
                  (json['projectGraphContext'] as Map)['dependencyCount']
                      as int? ??
                  0,
              lockState:
                  (json['projectGraphContext'] as Map)['lockState']
                      as String? ??
                  '',
              vendorState:
                  (json['projectGraphContext'] as Map)['vendorState']
                      as String? ??
                  '',
              toolchainChannel:
                  (json['projectGraphContext'] as Map)['toolchainChannel']
                      as String? ??
                  '',
              toolchainVersion:
                  (json['projectGraphContext'] as Map)['toolchainVersion']
                      as String? ??
                  '',
              graphSource:
                  (json['projectGraphContext'] as Map)['graphSource']
                      as String? ??
                  '',
              blockedInfo:
                  ((json['projectGraphContext'] as Map)['blockedInfo'] as List?)
                      ?.cast<String>() ??
                  const <String>[],
            )
          : null,
      runtimeContext: json['runtimeContext'] != null
          ? AgentRuntimeSummaryContext(
              lastRunStatus:
                  (json['runtimeContext'] as Map)['lastRunStatus'] as String? ??
                  '',
              lastRunUnitRange:
                  (json['runtimeContext'] as Map)['lastRunUnitRange']
                      as String? ??
                  '',
              lastRunSessionId:
                  (json['runtimeContext'] as Map)['lastRunSessionId']
                      as String? ??
                  '',
              eventCount:
                  (json['runtimeContext'] as Map)['eventCount'] as int? ?? 0,
              compileErrorCount:
                  (json['runtimeContext'] as Map)['compileErrorCount']
                      as int? ??
                  0,
              testFailCount:
                  (json['runtimeContext'] as Map)['testFailCount'] as int? ?? 0,
              laneStatuses:
                  ((json['runtimeContext'] as Map)['laneStatuses']
                          as Map<String, Object?>?)
                      ?.cast<String, String>() ??
                  const <String, String>{},
            )
          : null,
      commandCatalogContext: json['commandCatalogContext'] != null
          ? AgentCommandSummaryContext(
              availableCommandCount:
                  (json['commandCatalogContext']
                          as Map)['availableCommandCount']
                      as int? ??
                  0,
              blockedCommandCount:
                  (json['commandCatalogContext'] as Map)['blockedCommandCount']
                      as int? ??
                  0,
              availableCommandIds:
                  ((json['commandCatalogContext'] as Map)['availableCommandIds']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
              blockedCommands:
                  ((json['commandCatalogContext'] as Map)['blockedCommands']
                          as Map<String, Object?>?)
                      ?.cast<String, String>() ??
                  const <String, String>{},
            )
          : null,
      capabilityGapContext: json['capabilityGapContext'] != null
          ? AgentCapabilityGapContext(
              missingCapabilities:
                  ((json['capabilityGapContext'] as Map)['missingCapabilities']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
              degradedCapabilities:
                  ((json['capabilityGapContext'] as Map)['degradedCapabilities']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
              upstreamBlocked:
                  ((json['capabilityGapContext'] as Map)['upstreamBlocked']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
              availableCapabilities:
                  ((json['capabilityGapContext']
                              as Map)['availableCapabilities']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
            )
          : null,
      settingsSummary:
          (json['settingsSummary'] as Map<String, Object?>?)
              ?.cast<String, String>() ??
          const <String, String>{},
      profileId: json['profileId'] as String? ?? '',
      redactionPolicy: json['redactionPolicy'] != null
          ? AgentRedactionPolicy(
              redactEnvironmentVariableValues:
                  (json['redactionPolicy']
                          as Map)['redactEnvironmentVariableValues']
                      as bool? ??
                  true,
              redactApiKeyReferences:
                  (json['redactionPolicy'] as Map)['redactApiKeyReferences']
                      as bool? ??
                  true,
              redactHomeDirectoryPaths:
                  (json['redactionPolicy'] as Map)['redactHomeDirectoryPaths']
                      as bool? ??
                  true,
              redactUserSpecificPaths:
                  (json['redactionPolicy'] as Map)['redactUserSpecificPaths']
                      as bool? ??
                  true,
              redactSecretFields:
                  (json['redactionPolicy'] as Map)['redactSecretFields']
                      as bool? ??
                  true,
              additionalPatterns:
                  ((json['redactionPolicy'] as Map)['additionalPatterns']
                          as List?)
                      ?.cast<String>() ??
                  const <String>[],
            )
          : AgentRedactionPolicy.defaultPolicy,
    );
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

/// Lightweight display summary derived from AgentContextSnapshot.
class AgentContextSummary {
  const AgentContextSummary({
    this.workspace = '',
    this.activeFile = '',
    this.hasSelection = false,
    this.errorCount = 0,
    this.warningCount = 0,
    this.project = '',
    this.lastRun = '',
    this.availableCommands = 0,
    this.blockedCount = 0,
    this.hasCapabilityBlockers = false,
  });

  final String workspace;
  final String activeFile;
  final bool hasSelection;
  final int errorCount;
  final int warningCount;
  final String project;
  final String lastRun;
  final int availableCommands;
  final int blockedCount;
  final bool hasCapabilityBlockers;
}

// ── Agent Action Plan ─────────────────────────────────────────────

/// An action plan proposed by the Agent, referencing only commands
/// and workspace edits — never direct filesystem access.
class AgentActionPlan {
  const AgentActionPlan({
    required this.planId,
    required this.description,
    this.commands = const <AppCommandId>[],
    this.workspaceEdits = const <AgentWorkspaceEditIntent>[],
    this.requiresPermission = true,
    this.permissionScope = PermissionRequestScope.readOnly,
    this.permissionReason = '',
  });

  final String planId;
  final String description;
  final List<AppCommandId> commands;
  final List<AgentWorkspaceEditIntent> workspaceEdits;
  final bool requiresPermission;
  final PermissionRequestScope permissionScope;
  final String permissionReason;

  bool get hasEdits => workspaceEdits.isNotEmpty;
  bool get hasCommands => commands.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'planId': planId,
    'description': description,
    'commands': commands.map((c) => c.name).toList(growable: false),
    'workspaceEdits': workspaceEdits
        .map((e) => e.toJson())
        .toList(growable: false),
    'requiresPermission': requiresPermission,
    'permissionScope': permissionScope.name,
    'permissionReason': permissionReason,
  };
}

/// A single workspace edit intent from the Agent. Applied through
/// the workspace edit transaction system, never through direct
/// file writes.
class AgentWorkspaceEditIntent {
  const AgentWorkspaceEditIntent({
    required this.intentId,
    required this.filePath,
    required this.editKind,
    this.rangeStart = -1,
    this.rangeEnd = -1,
    this.newText = '',
    this.originalText = '',
    this.summary = '',
    this.symbolName = '',
  });

  final String intentId;
  final String filePath;
  final String editKind;
  final int rangeStart;
  final int rangeEnd;
  final String newText;
  final String originalText;
  final String summary;
  final String symbolName;

  bool get isRangeEdit => rangeStart >= 0 && rangeEnd >= 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'intentId': intentId,
    'filePath': filePath,
    'editKind': editKind,
    'rangeStart': rangeStart,
    'rangeEnd': rangeEnd,
    'newText': newText,
    'originalText': originalText,
    'summary': summary,
    'symbolName': symbolName,
  };
}

// ── Agent Workspace Edit Application ──────────────────────────────

/// Result of applying an agent's workspace edits through the
/// transaction system.
class AgentWorkspaceEditApplication {
  const AgentWorkspaceEditApplication({
    required this.applicationId,
    required this.planId,
    required this.appliedAtIso8601,
    this.editCount = 0,
    this.affectedFilePaths = const <String>[],
    this.appliedIntents = const <AgentWorkspaceEditIntent>[],
    this.failedIntents = const <AgentWorkspaceEditIntent>[],
    this.errorMessages = const <String>[],
    this.rollbackAvailable = true,
    this.rollbackTransactionId = '',
  });

  final String applicationId;
  final String planId;
  final String appliedAtIso8601;
  final int editCount;
  final List<String> affectedFilePaths;
  final List<AgentWorkspaceEditIntent> appliedIntents;
  final List<AgentWorkspaceEditIntent> failedIntents;
  final List<String> errorMessages;
  final bool rollbackAvailable;
  final String rollbackTransactionId;

  bool get hasFailures => failedIntents.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'applicationId': applicationId,
    'planId': planId,
    'appliedAtIso8601': appliedAtIso8601,
    'editCount': editCount,
    'affectedFilePaths': affectedFilePaths,
    'appliedCount': appliedIntents.length,
    'failedCount': failedIntents.length,
    'errorMessages': errorMessages,
    'rollbackAvailable': rollbackAvailable,
    'rollbackTransactionId': rollbackTransactionId,
  };
}
