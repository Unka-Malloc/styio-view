/// Debug / Runtime Workbench contract model.
///
/// Defines the IDE-level contract for run/debug capabilities.
/// Borrows structural ideas from DAP but does NOT depend on or
/// promise DAP compatibility. All backend-specific capabilities
/// are blocked/preview-only until Styio runtime supports them.
///
/// Pure Dart, no Flutter imports.
library;

// ── Breakpoint ────────────────────────────────────────────────────

class Breakpoint {
  const Breakpoint({
    required this.breakpointId,
    required this.filePath,
    required this.line,
    this.column,
    this.condition = '',
    this.enabled = true,
    this.verified = false,
    this.verificationMessage = '',
  });

  final String breakpointId;
  final String filePath;
  final int line;
  final int? column;
  final String condition;
  final bool enabled;
  final bool verified;
  final String verificationMessage;

  Map<String, Object?> toJson() => <String, Object?>{
        'breakpointId': breakpointId,
        'filePath': filePath,
        'line': line,
        'column': column,
        'condition': condition,
        'enabled': enabled,
        'verified': verified,
        'verificationMessage': verificationMessage,
      };
}

class BreakpointSet {
  const BreakpointSet({
    this.breakpoints = const <Breakpoint>[],
  });

  final List<Breakpoint> breakpoints;

  bool get isEmpty => breakpoints.isEmpty;

  int get enabledCount => breakpoints.where((b) => b.enabled).length;

  List<Breakpoint> forFile(String filePath) =>
      breakpoints.where((b) => b.filePath == filePath).toList(growable: false);
}

// ── Run Configuration ─────────────────────────────────────────────

enum RunConfigurationKind {
  minimalCompilableUnit,
  projectTarget,
  scratchFile,
  testTarget,
}

class RunConfigurationTarget {
  const RunConfigurationTarget({
    this.targetName = '',
    this.targetKind = '',
    this.filePath = '',
    this.unitRange = '',
  });

  final String targetName;
  final String targetKind;
  final String filePath;
  final String unitRange;

  static const RunConfigurationTarget defaultTarget = RunConfigurationTarget();

  Map<String, Object?> toJson() => <String, Object?>{
        'targetName': targetName,
        'targetKind': targetKind,
        'filePath': filePath,
        'unitRange': unitRange,
      };
}

class RunConfiguration {
  const RunConfiguration({
    required this.configurationId,
    required this.kind,
    this.label = '',
    this.target = RunConfigurationTarget.defaultTarget,
    this.environmentOverrides = const <String, String>{},
    this.buildBeforeRun = true,
    this.available = true,
    this.blockedReason = '',
  });

  final String configurationId;
  final RunConfigurationKind kind;
  final String label;
  final RunConfigurationTarget target;
  final Map<String, String> environmentOverrides;
  final bool buildBeforeRun;
  final bool available;
  final String blockedReason;

  bool get isBlocked => !available;

  Map<String, Object?> toJson() => <String, Object?>{
        'configurationId': configurationId,
        'kind': kind.name,
        'label': label,
        'target': target.toJson(),
        'environmentOverrides': environmentOverrides,
        'buildBeforeRun': buildBeforeRun,
        'available': available,
        'blockedReason': blockedReason,
      };
}

extension RunConfigurationTargetX on RunConfigurationTarget {
  static const RunConfigurationTarget defaultTarget = RunConfigurationTarget();
}

// ── Debug Session ─────────────────────────────────────────────────

enum DebugSessionStatus {
  idle,
  launching,
  running,
  stopped,
  terminated,
  failed,
}

enum DebugStoppedReason {
  breakpoint,
  step,
  exception,
  pause,
  entry,
}

class StackFrameSnapshot {
  const StackFrameSnapshot({
    required this.frameId,
    required this.name,
    this.filePath = '',
    this.line = -1,
    this.column = -1,
  });

  final int frameId;
  final String name;
  final String filePath;
  final int line;
  final int column;

  Map<String, Object?> toJson() => <String, Object?>{
        'frameId': frameId,
        'name': name,
        'filePath': filePath,
        'line': line,
        'column': column,
      };
}

class RuntimeVariableSnapshot {
  const RuntimeVariableSnapshot({
    required this.variableId,
    required this.name,
    required this.value,
    this.typeName = '',
    this.children = const <RuntimeVariableSnapshot>[],
  });

  final int variableId;
  final String name;
  final String value;
  final String typeName;
  final List<RuntimeVariableSnapshot> children;

  Map<String, Object?> toJson() => <String, Object?>{
        'variableId': variableId,
        'name': name,
        'value': value,
        'typeName': typeName,
        'children': children.map((c) => c.toJson()).toList(growable: false),
      };
}

class DebugSessionSnapshot {
  const DebugSessionSnapshot({
    required this.sessionId,
    required this.status,
    this.stoppedReason,
    this.stoppedFilePath = '',
    this.stoppedLine = -1,
    this.stackFrames = const <StackFrameSnapshot>[],
    this.variables = const <RuntimeVariableSnapshot>[],
    this.available = false,
    this.blockedReason = 'Styio runtime debug contract not yet published.',
  });

  final String sessionId;
  final DebugSessionStatus status;
  final DebugStoppedReason? stoppedReason;
  final String stoppedFilePath;
  final int stoppedLine;
  final List<StackFrameSnapshot> stackFrames;
  final List<RuntimeVariableSnapshot> variables;
  final bool available;
  final String blockedReason;

  bool get isBlocked => !available;
  bool get isStopped => status == DebugSessionStatus.stopped;

  Map<String, Object?> toJson() => <String, Object?>{
        'sessionId': sessionId,
        'status': status.name,
        'stoppedReason': stoppedReason?.name,
        'stoppedFilePath': stoppedFilePath,
        'stoppedLine': stoppedLine,
        'stackFrames':
            stackFrames.map((f) => f.toJson()).toList(growable: false),
        'variables':
            variables.map((v) => v.toJson()).toList(growable: false),
        'available': available,
        'blockedReason': blockedReason,
      };
}

// ── Runtime Command Availability ──────────────────────────────────

/// Describes which runtime/debug commands are available given
/// the current adapter capabilities and platform route.
class RuntimeCommandAvailability {
  const RuntimeCommandAvailability({
    this.canRun = true,
    this.canBuild = true,
    this.canTest = true,
    this.canDebug = false,
    this.canSetBreakpoints = false,
    this.canStep = false,
    this.canInspectVariables = false,
    this.canReplayRuntimeEvents = true,
    this.canStreamRuntimeEvents = false,
    this.blockedDebugReason =
        'Styio runtime does not yet expose debug adapter contract.',
    this.blockedBreakpointReason =
        'Breakpoint support requires Styio runtime debug contract.',
    this.blockedStepReason =
        'Step execution requires Styio runtime debug contract.',
    this.blockedVariableReason =
        'Variable inspection requires Styio runtime debug contract.',
  });

  final bool canRun;
  final bool canBuild;
  final bool canTest;
  final bool canDebug;
  final bool canSetBreakpoints;
  final bool canStep;
  final bool canInspectVariables;
  final bool canReplayRuntimeEvents;
  final bool canStreamRuntimeEvents;
  final String blockedDebugReason;
  final String blockedBreakpointReason;
  final String blockedStepReason;
  final String blockedVariableReason;

  Map<String, Object?> toJson() => <String, Object?>{
        'canRun': canRun,
        'canBuild': canBuild,
        'canTest': canTest,
        'canDebug': canDebug,
        'canSetBreakpoints': canSetBreakpoints,
        'canStep': canStep,
        'canInspectVariables': canInspectVariables,
        'canReplayRuntimeEvents': canReplayRuntimeEvents,
        'canStreamRuntimeEvents': canStreamRuntimeEvents,
        'blockedDebugReason': blockedDebugReason,
        'blockedBreakpointReason': blockedBreakpointReason,
        'blockedStepReason': blockedStepReason,
        'blockedVariableReason': blockedVariableReason,
      };
}
