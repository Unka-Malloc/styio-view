import '../backend_toolchain/project_graph_contract.dart';
import '../backend_toolchain/toolchain_management_adapter.dart';
import '../toolchain/clang_cpp_version_configuration.dart';
import '../toolchain/clang_cpp_version_manager.dart';
import '../toolchain/toolchain_catalog.dart';
import '../toolchain/toolchain_configuration_store.dart';
import '../toolchain/toolchain_install_executor.dart'
    hide ToolchainRecoveryAction;
import '../toolchain/toolchain_install_policy.dart';
import '../toolchain/toolchain_manager.dart';

enum ToolchainStatusSeverity { ready, unavailable, blocked, failed }

class ToolchainRecoveryAction {
  const ToolchainRecoveryAction({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'description': description,
    };
  }
}

class ToolchainStatusSurface {
  const ToolchainStatusSurface({
    required this.source,
    required this.severity,
    required this.title,
    required this.message,
    required this.recoveryActions,
    this.version,
    this.channel,
    this.pinPath,
    this.lastCommand,
    this.lastCommandStatus,
    this.lastCommandMessage,
  });

  factory ToolchainStatusSurface.fromProjectToolchain(
    ToolchainStatusSnapshot snapshot, {
    ToolchainCommandResult? lastCommand,
  }) {
    final severity = _severityFor(snapshot, lastCommand);
    return ToolchainStatusSurface(
      source: snapshot.source.label,
      severity: severity,
      title: _titleFor(severity),
      message: lastCommand?.statusMessage ?? snapshot.detail,
      version: snapshot.version,
      channel: snapshot.channel,
      pinPath: snapshot.pinPath,
      lastCommand: lastCommand?.command,
      lastCommandStatus: lastCommand?.status.name,
      lastCommandMessage: lastCommand?.statusMessage,
      recoveryActions: _recoveryActionsFor(severity, lastCommand),
    );
  }

  factory ToolchainStatusSurface.fromManagerStatusReport(
    ToolchainManagerStatusReport report, {
    ToolchainCommandResult? lastCommand,
  }) {
    final severity = lastCommand != null && !lastCommand.succeeded
        ? _severityForCommand(lastCommand)
        : _severityForManagerStatus(report.status);
    final descriptor = report.resolution.descriptor;
    return ToolchainStatusSurface(
      source: 'manager-report',
      severity: severity,
      title: _titleFor(severity),
      message:
          lastCommand?.statusMessage ??
          report.message ??
          report.health?.message ??
          report.resolution.message ??
          _managerMessageFor(report.status),
      version: descriptor?.version,
      channel: descriptor?.channel,
      lastCommand: lastCommand?.command,
      lastCommandStatus: lastCommand?.status.name,
      lastCommandMessage: lastCommand?.statusMessage,
      recoveryActions: _recoveryActionsFor(severity, lastCommand),
    );
  }

  final String source;
  final ToolchainStatusSeverity severity;
  final String title;
  final String message;
  final String? version;
  final String? channel;
  final String? pinPath;
  final String? lastCommand;
  final String? lastCommandStatus;
  final String? lastCommandMessage;
  final List<ToolchainRecoveryAction> recoveryActions;

  bool get actionable {
    return severity == ToolchainStatusSeverity.unavailable ||
        severity == ToolchainStatusSeverity.blocked ||
        severity == ToolchainStatusSeverity.failed;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source,
      'severity': severity.name,
      'title': title,
      'message': message,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
      if (pinPath != null) 'pinPath': pinPath,
      if (lastCommand != null) 'lastCommand': lastCommand,
      if (lastCommandStatus != null) 'lastCommandStatus': lastCommandStatus,
      if (lastCommandMessage != null) 'lastCommandMessage': lastCommandMessage,
      'recoveryActions': recoveryActions
          .map((action) => action.toJson())
          .toList(growable: false),
      'actionable': actionable,
    };
  }

  static ToolchainStatusSeverity _severityFor(
    ToolchainStatusSnapshot snapshot,
    ToolchainCommandResult? lastCommand,
  ) {
    if (lastCommand != null) {
      return _severityForCommand(lastCommand);
    }
    return switch (snapshot.source) {
      ToolchainResolutionSource.projectPin ||
      ToolchainResolutionSource.managedCurrent ||
      ToolchainResolutionSource.environment => ToolchainStatusSeverity.ready,
      ToolchainResolutionSource.unavailable =>
        ToolchainStatusSeverity.unavailable,
      ToolchainResolutionSource.unknown => ToolchainStatusSeverity.unavailable,
    };
  }

  static ToolchainStatusSeverity _severityForCommand(
    ToolchainCommandResult command,
  ) {
    return switch (command.status) {
      ToolchainCommandStatus.succeeded => ToolchainStatusSeverity.ready,
      ToolchainCommandStatus.blocked => ToolchainStatusSeverity.blocked,
      ToolchainCommandStatus.failed => ToolchainStatusSeverity.failed,
    };
  }

  static ToolchainStatusSeverity _severityForManagerStatus(
    ToolchainManagerStatus status,
  ) {
    return switch (status) {
      ToolchainManagerStatus.ready => ToolchainStatusSeverity.ready,
      ToolchainManagerStatus.unresolved => ToolchainStatusSeverity.unavailable,
      ToolchainManagerStatus.unhealthy => ToolchainStatusSeverity.failed,
    };
  }

  static String _titleFor(ToolchainStatusSeverity severity) {
    return switch (severity) {
      ToolchainStatusSeverity.ready => 'Toolchain ready',
      ToolchainStatusSeverity.unavailable => 'Toolchain unavailable',
      ToolchainStatusSeverity.blocked => 'Toolchain action blocked',
      ToolchainStatusSeverity.failed => 'Toolchain command failed',
    };
  }

  static String _managerMessageFor(ToolchainManagerStatus status) {
    return switch (status) {
      ToolchainManagerStatus.ready =>
        'Toolchain manager resolved a usable toolchain.',
      ToolchainManagerStatus.unresolved =>
        'Toolchain manager could not resolve a matching toolchain.',
      ToolchainManagerStatus.unhealthy =>
        'Toolchain manager resolved a toolchain, but health probing failed.',
    };
  }

  static List<ToolchainRecoveryAction> _recoveryActionsFor(
    ToolchainStatusSeverity severity,
    ToolchainCommandResult? lastCommand,
  ) {
    return switch (severity) {
      ToolchainStatusSeverity.ready => const <ToolchainRecoveryAction>[],
      ToolchainStatusSeverity.unavailable => const <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select toolchain',
          description: 'Choose an existing Styio toolchain for this workspace.',
        ),
        ToolchainRecoveryAction(
          id: 'install-managed-toolchain',
          label: 'Install managed toolchain',
          description: 'Install a Vityo-managed Styio toolchain when allowed.',
        ),
        ToolchainRecoveryAction(
          id: 'use-degraded-mode',
          label: 'Use degraded mode',
          description: 'Continue with features that do not require Styio.',
        ),
      ],
      ToolchainStatusSeverity.blocked => <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'fix-toolchain-precondition',
          label: 'Fix precondition',
          description:
              lastCommand?.statusMessage ??
              'Resolve the blocked toolchain command precondition.',
        ),
        const ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select toolchain',
          description: 'Choose a compatible local Styio toolchain.',
        ),
      ],
      ToolchainStatusSeverity.failed => <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'retry-${(lastCommand?.command ?? 'toolchain').replaceAll(' ', '-')}',
          label: 'Retry command',
          description:
              lastCommand?.statusMessage ??
              'Retry the failed toolchain command after reviewing logs.',
        ),
        const ToolchainRecoveryAction(
          id: 'show-toolchain-logs',
          label: 'Show logs',
          description: 'Open the latest toolchain command logs.',
        ),
        const ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select toolchain',
          description: 'Switch to another compatible Styio toolchain.',
        ),
      ],
    };
  }
}

class ToolchainSettingsSurface {
  const ToolchainSettingsSurface({
    required this.status,
    required this.toolchains,
    required this.capabilities,
    required this.recoveryState,
    required this.installHistory,
    this.targetId,
    this.workspaceId,
    this.clangCppVersions,
  });

  factory ToolchainSettingsSurface.fromStatus(ToolchainStatusSurface status) {
    return ToolchainSettingsSurface(
      status: status,
      toolchains: const <ToolchainCandidateSurface>[],
      capabilities: const <ToolchainCapabilitySurface>[],
      recoveryState: const ToolchainRecoveryStateSurface(
        kind: 'unknown',
        actionIds: <String>[],
        actionable: false,
      ),
      installHistory: const <ToolchainInstallHistorySurface>[],
    );
  }

  factory ToolchainSettingsSurface.fromManagerStatusReport(
    ToolchainManagerStatusReport report, {
    ToolchainCommandResult? lastCommand,
    ClangCppVersionPreference? clangCppVersionPreference,
  }) {
    return ToolchainSettingsSurface(
      status: ToolchainStatusSurface.fromManagerStatusReport(
        report,
        lastCommand: lastCommand,
      ),
      targetId: report.snapshot.targetId,
      workspaceId: report.snapshot.workspaceId,
      toolchains: report.snapshot.entries
          .map(ToolchainCandidateSurface.fromEntry)
          .toList(growable: false),
      capabilities: report.capabilities
          .map(ToolchainCapabilitySurface.fromCapability)
          .toList(growable: false),
      clangCppVersions: ClangCppVersionSettingsSurface.fromSnapshot(
        report.snapshot,
        preference: clangCppVersionPreference,
      ),
      recoveryState: ToolchainRecoveryStateSurface.fromState(
        report.recoveryState,
      ),
      installHistory:
          report.installHistory?.entries
              .map(ToolchainInstallHistorySurface.fromEntry)
              .toList(growable: false) ??
          const <ToolchainInstallHistorySurface>[],
    );
  }

  final ToolchainStatusSurface status;
  final String? targetId;
  final String? workspaceId;
  final List<ToolchainCandidateSurface> toolchains;
  final List<ToolchainCapabilitySurface> capabilities;
  final ClangCppVersionSettingsSurface? clangCppVersions;
  final ToolchainRecoveryStateSurface recoveryState;
  final List<ToolchainInstallHistorySurface> installHistory;

  bool get hasManagerSnapshot => targetId != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.toJson(),
      if (targetId != null) 'targetId': targetId,
      if (workspaceId != null) 'workspaceId': workspaceId,
      'toolchains': toolchains
          .map((toolchain) => toolchain.toJson())
          .toList(growable: false),
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(growable: false),
      if (clangCppVersions != null)
        'clangCppVersions': clangCppVersions!.toJson(),
      'recoveryState': recoveryState.toJson(),
      'installHistory': installHistory
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'hasManagerSnapshot': hasManagerSnapshot,
    };
  }
}

class ClangCppVersionSettingsSurface {
  const ClangCppVersionSettingsSurface({
    required this.candidates,
    required this.preferenceStatus,
    required this.defaultCppStandard,
    required this.defaultCompilerFlag,
    required this.supportedStandards,
    required this.cmakeAvailable,
    required this.ninjaAvailable,
    required this.buildEngineHandoffs,
    this.activeVersionId,
    this.requestedVersionId,
    this.preferenceMessage,
    this.preferredBuildEngineHandoff,
  });

  static ClangCppVersionSettingsSurface? fromSnapshot(
    ToolchainStateSnapshot snapshot, {
    ClangCppVersionPreference? preference,
  }) {
    final manager = ClangCppVersionManager.fromSnapshot(
      snapshot,
      preference: preference,
    );
    if (!manager.hasCandidates) {
      return null;
    }
    final selection = manager.select();
    final handoffs =
        selection?.buildEngineHandoffs
            .map(ClangCppBuildEngineHandoffSurface.fromHandoff)
            .toList(growable: false) ??
        const <ClangCppBuildEngineHandoffSurface>[];
    final preferred = selection?.preferredBuildEngineHandoff;
    return ClangCppVersionSettingsSurface(
      candidates: manager.candidates
          .map(
            (candidate) => ClangCppVersionCandidateSurface.fromCandidate(
              candidate,
              active: candidate.versionId == manager.activeVersionId,
            ),
          )
          .toList(growable: false),
      activeVersionId: manager.activeVersionId,
      requestedVersionId: manager.requestedVersionId,
      preferenceStatus: manager.preferenceStatus.name,
      preferenceMessage: manager.preferenceMessage,
      defaultCppStandard: manager.defaultCppStandard.cmakeValue,
      defaultCompilerFlag: manager.defaultCppStandard.compilerFlag,
      supportedStandards: CppLanguageStandard.values
          .map(
            (standard) => ClangCppStandardSettingsSurface(
              cmakeValue: standard.cmakeValue,
              compilerFlag: standard.compilerFlag,
              active: standard == manager.defaultCppStandard,
            ),
          )
          .toList(growable: false),
      cmakeAvailable: manager.cmakeAvailable,
      ninjaAvailable: manager.ninjaAvailable,
      buildEngineHandoffs: handoffs,
      preferredBuildEngineHandoff: preferred == null
          ? null
          : ClangCppBuildEngineHandoffSurface.fromHandoff(preferred),
    );
  }

  final List<ClangCppVersionCandidateSurface> candidates;
  final String? activeVersionId;
  final String? requestedVersionId;
  final String preferenceStatus;
  final String? preferenceMessage;
  final String defaultCppStandard;
  final String defaultCompilerFlag;
  final List<ClangCppStandardSettingsSurface> supportedStandards;
  final bool cmakeAvailable;
  final bool ninjaAvailable;
  final List<ClangCppBuildEngineHandoffSurface> buildEngineHandoffs;
  final ClangCppBuildEngineHandoffSurface? preferredBuildEngineHandoff;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'candidateCount': candidates.length,
      'candidates': candidates
          .map((candidate) => candidate.toJson())
          .toList(growable: false),
      if (activeVersionId != null) 'activeVersionId': activeVersionId,
      if (requestedVersionId != null) 'requestedVersionId': requestedVersionId,
      'preferenceStatus': preferenceStatus,
      if (preferenceMessage != null) 'preferenceMessage': preferenceMessage,
      'defaultCppStandard': defaultCppStandard,
      'defaultCompilerFlag': defaultCompilerFlag,
      'supportedStandards': supportedStandards
          .map((standard) => standard.toJson())
          .toList(growable: false),
      'cmakeAvailable': cmakeAvailable,
      'ninjaAvailable': ninjaAvailable,
      'buildEngineHandoffs': buildEngineHandoffs
          .map((handoff) => handoff.toJson())
          .toList(growable: false),
      if (preferredBuildEngineHandoff != null)
        'preferredBuildEngineHandoff': preferredBuildEngineHandoff!.toJson(),
    };
  }
}

class ClangCppStandardSettingsSurface {
  const ClangCppStandardSettingsSurface({
    required this.cmakeValue,
    required this.compilerFlag,
    required this.active,
  });

  final String cmakeValue;
  final String compilerFlag;
  final bool active;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'cmakeValue': cmakeValue,
      'compilerFlag': compilerFlag,
      'active': active,
    };
  }
}

class ClangCppVersionCandidateSurface {
  const ClangCppVersionCandidateSurface({
    required this.versionId,
    required this.displayName,
    required this.cCompilerPath,
    required this.cxxCompilerPath,
    required this.active,
    this.version,
    this.vendor,
    this.source,
  });

  factory ClangCppVersionCandidateSurface.fromCandidate(
    ClangCppVersionCandidate candidate, {
    required bool active,
  }) {
    return ClangCppVersionCandidateSurface(
      versionId: candidate.versionId,
      displayName: candidate.displayName,
      cCompilerPath: candidate.cCompilerPath,
      cxxCompilerPath: candidate.cxxCompilerPath,
      active: active,
      version: candidate.version,
      vendor: _stringValue(candidate.metadata['clangVendor']),
      source: candidate.source,
    );
  }

  final String versionId;
  final String displayName;
  final String cCompilerPath;
  final String cxxCompilerPath;
  final bool active;
  final String? version;
  final String? vendor;
  final String? source;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'versionId': versionId,
      'displayName': displayName,
      'cCompilerPath': cCompilerPath,
      'cxxCompilerPath': cxxCompilerPath,
      'active': active,
      if (version != null) 'version': version,
      if (vendor != null) 'vendor': vendor,
      if (source != null) 'source': source,
    };
  }
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class ClangCppBuildEngineHandoffSurface {
  const ClangCppBuildEngineHandoffSurface({
    required this.engineFamily,
    required this.executablePath,
    required this.arguments,
    required this.environment,
    this.generatorFamily,
  });

  factory ClangCppBuildEngineHandoffSurface.fromHandoff(
    ClangCppBuildEngineHandoff handoff,
  ) {
    return ClangCppBuildEngineHandoffSurface(
      engineFamily: handoff.engineFamily,
      executablePath: handoff.executablePath,
      generatorFamily: handoff.generatorFamily,
      arguments: handoff.arguments,
      environment: handoff.environment,
    );
  }

  final String engineFamily;
  final String? generatorFamily;
  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;

  String get label {
    final generator = generatorFamily == null ? '' : '+$generatorFamily';
    return '$engineFamily$generator';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'engineFamily': engineFamily,
      if (generatorFamily != null) 'generatorFamily': generatorFamily,
      'executablePath': executablePath,
      'arguments': arguments,
      if (environment.isNotEmpty) 'environment': environment,
    };
  }
}

class ToolchainCandidateSurface {
  const ToolchainCandidateSurface({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.executablePath,
    required this.active,
    this.version,
    this.channel,
  });

  factory ToolchainCandidateSurface.fromEntry(ToolchainStateEntry entry) {
    return ToolchainCandidateSurface(
      id: entry.id,
      kind: entry.kind,
      displayName: entry.displayName,
      executablePath: entry.executablePath,
      active: entry.active,
      version: entry.version,
      channel: entry.channel,
    );
  }

  final String id;
  final ToolchainKind kind;
  final String displayName;
  final String executablePath;
  final bool active;
  final String? version;
  final String? channel;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.wireValue,
      'displayName': displayName,
      'executablePath': executablePath,
      'active': active,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
    };
  }
}

class ToolchainCapabilitySurface {
  const ToolchainCapabilitySurface({
    required this.kind,
    required this.state,
    required this.active,
    required this.usable,
    this.descriptorId,
    this.message,
  });

  factory ToolchainCapabilitySurface.fromCapability(
    ToolchainCapabilityStatus capability,
  ) {
    return ToolchainCapabilitySurface(
      kind: capability.kind,
      state: capability.state.name,
      active: capability.active,
      usable: capability.usable,
      descriptorId: capability.descriptorId,
      message: capability.message,
    );
  }

  final ToolchainKind kind;
  final String state;
  final bool active;
  final bool usable;
  final String? descriptorId;
  final String? message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'state': state,
      'active': active,
      'usable': usable,
      if (descriptorId != null) 'descriptorId': descriptorId,
      if (message != null) 'message': message,
    };
  }
}

class ToolchainRecoveryStateSurface {
  const ToolchainRecoveryStateSurface({
    required this.kind,
    required this.actionIds,
    required this.actionable,
    this.message,
  });

  factory ToolchainRecoveryStateSurface.fromState(
    ToolchainRecoveryState state,
  ) {
    return ToolchainRecoveryStateSurface(
      kind: state.kind.name,
      actionIds: state.actionIds,
      actionable: state.actionable,
      message: state.message,
    );
  }

  final String kind;
  final List<String> actionIds;
  final bool actionable;
  final String? message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind,
      'actionIds': actionIds,
      'actionable': actionable,
      if (message != null) 'message': message,
    };
  }
}

class ToolchainInstallHistorySurface {
  const ToolchainInstallHistorySurface({
    required this.id,
    required this.status,
    required this.mode,
    required this.kind,
    required this.succeeded,
    required this.recordedAt,
    this.message,
  });

  factory ToolchainInstallHistorySurface.fromEntry(
    ToolchainInstallHistoryEntry entry,
  ) {
    return ToolchainInstallHistorySurface(
      id: entry.id,
      status: entry.status,
      mode: entry.mode,
      kind: entry.kind,
      succeeded: entry.succeeded,
      recordedAt: entry.recordedAt,
      message: entry.message,
    );
  }

  final String id;
  final String status;
  final String mode;
  final String kind;
  final bool succeeded;
  final DateTime recordedAt;
  final String? message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'status': status,
      'mode': mode,
      'kind': kind,
      'succeeded': succeeded,
      'recordedAt': recordedAt.toUtc().toIso8601String(),
      if (message != null) 'message': message,
    };
  }
}

class ToolchainInstallPlanSurface {
  const ToolchainInstallPlanSurface({
    required this.status,
    required this.mode,
    required this.kind,
    required this.actionable,
    this.message,
    this.downloadUri,
    this.externalCommand,
  });

  factory ToolchainInstallPlanSurface.fromPlan(ToolchainInstallPlan plan) {
    return ToolchainInstallPlanSurface(
      status: plan.status.name,
      mode: plan.mode.name,
      kind: plan.requirement.kind.wireValue,
      actionable: plan.actionable,
      message: plan.message,
      downloadUri: plan.downloadUri?.toString(),
      externalCommand: plan.externalCommand,
    );
  }

  final String status;
  final String mode;
  final String kind;
  final bool actionable;
  final String? message;
  final String? downloadUri;
  final String? externalCommand;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'mode': mode,
      'kind': kind,
      'actionable': actionable,
      if (message != null) 'message': message,
      if (downloadUri != null) 'downloadUri': downloadUri,
      if (externalCommand != null) 'externalCommand': externalCommand,
    };
  }
}

class ToolchainInstallExecutionSurface {
  const ToolchainInstallExecutionSurface({
    required this.status,
    required this.mode,
    required this.kind,
    required this.succeeded,
    this.message,
    this.recoveryActions = const <ToolchainRecoveryAction>[],
  });

  factory ToolchainInstallExecutionSurface.fromResult(
    ToolchainInstallExecutionResult result,
  ) {
    return ToolchainInstallExecutionSurface(
      status: result.status.name,
      mode: result.plan.mode.name,
      kind: result.plan.requirement.kind.wireValue,
      succeeded: result.succeeded,
      message: result.message,
      recoveryActions: result.recoveryActions
          .map(
            (action) => ToolchainRecoveryAction(
              id: action.id,
              label: action.label,
              description: action.detail,
            ),
          )
          .toList(growable: false),
    );
  }

  final String status;
  final String mode;
  final String kind;
  final bool succeeded;
  final String? message;
  final List<ToolchainRecoveryAction> recoveryActions;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'mode': mode,
      'kind': kind,
      'succeeded': succeeded,
      if (message != null) 'message': message,
      if (recoveryActions.isNotEmpty)
        'recoveryActions': recoveryActions
            .map((action) => action.toJson())
            .toList(growable: false),
    };
  }
}
