import '../foundation/foundation.dart';
import '../runtime/runtime.dart';
import '../toolchain/toolchain_catalog.dart';

enum DebugLaunchReadiness { ready, missingProgram, unsupportedProtocol }

enum DebugLaunchRouteStatus { ready, blocked }

enum DebugLaunchFailureNavigationKind {
  selectProgram,
  selectAdapter,
  changeProtocol,
  openSettings,
}

extension DebugLaunchReadinessX on DebugLaunchReadiness {
  String get wireValue => switch (this) {
    DebugLaunchReadiness.ready => 'ready',
    DebugLaunchReadiness.missingProgram => 'missing-program',
    DebugLaunchReadiness.unsupportedProtocol => 'unsupported-protocol',
  };
}

extension DebugLaunchRouteStatusX on DebugLaunchRouteStatus {
  String get wireValue => switch (this) {
    DebugLaunchRouteStatus.ready => 'ready',
    DebugLaunchRouteStatus.blocked => 'blocked',
  };
}

extension DebugLaunchFailureNavigationKindX
    on DebugLaunchFailureNavigationKind {
  String get wireValue => switch (this) {
    DebugLaunchFailureNavigationKind.selectProgram => 'select-program',
    DebugLaunchFailureNavigationKind.selectAdapter => 'select-adapter',
    DebugLaunchFailureNavigationKind.changeProtocol => 'change-protocol',
    DebugLaunchFailureNavigationKind.openSettings => 'open-settings',
  };
}

DebugLaunchReadiness _debugLaunchReadinessFromWire(Object? value) {
  return switch (value) {
    'ready' => DebugLaunchReadiness.ready,
    'missing-program' => DebugLaunchReadiness.missingProgram,
    'unsupported-protocol' => DebugLaunchReadiness.unsupportedProtocol,
    _ => DebugLaunchReadiness.missingProgram,
  };
}

class DebugLaunchBreakpoint {
  const DebugLaunchBreakpoint({
    required this.filePath,
    required this.line,
    this.enabled = true,
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  final String filePath;
  final int line;
  final bool enabled;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  static const Set<String> _knownKeys = {
    'schemaVersion',
    'filePath',
    'line',
    'enabled',
  };

  factory DebugLaunchBreakpoint.fromJson(Map<String, Object?> json) {
    return DebugLaunchBreakpoint(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      filePath: json['filePath'] as String? ?? '',
      line: json['line'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      extensions: _collectUnknown(json),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'filePath': filePath,
      'line': line,
      'enabled': enabled,
      ...extensions,
    };
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

class DebugLaunchConfiguration {
  const DebugLaunchConfiguration({
    required this.readiness,
    required this.reason,
    required this.debuggerId,
    required this.debuggerLabel,
    required this.debuggerExecutablePath,
    this.debuggerArguments = const <String>[],
    required this.adapterProtocol,
    required this.programPath,
    required this.cwd,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.stopOnEntry = false,
    this.breakpoints = const <DebugLaunchBreakpoint>[],
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  factory DebugLaunchConfiguration.fromJson(Map<String, Object?> json) {
    return DebugLaunchConfiguration(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      readiness: _debugLaunchReadinessFromWire(json['readiness']),
      reason: json['reason'] as String? ?? '',
      debuggerId: json['debuggerId'] as String? ?? '',
      debuggerLabel: json['debuggerLabel'] as String? ?? '',
      debuggerExecutablePath: json['debuggerExecutablePath'] as String? ?? '',
      debuggerArguments: _jsonStringList(json['debuggerArguments']),
      adapterProtocol: json['adapterProtocol'] as String? ?? 'dap',
      programPath: json['programPath'] as String?,
      cwd: json['cwd'] as String? ?? '',
      arguments: _jsonStringList(json['arguments']),
      environment: _jsonStringMap(json['environment']),
      stopOnEntry: json['stopOnEntry'] as bool? ?? false,
      breakpoints: _jsonBreakpoints(json['breakpoints']),
      extensions: _collectUnknown(json),
    );
  }

  factory DebugLaunchConfiguration.fromToolchainDescriptor({
    required ToolchainDescriptor debugger,
    required String workspaceRoot,
    Iterable<DebugLaunchBreakpoint> breakpoints =
        const <DebugLaunchBreakpoint>[],
  }) {
    final protocol =
        _metadataString(debugger.metadata, 'adapterProtocol') ??
        _metadataString(debugger.metadata, 'debugAdapterProtocol') ??
        'dap';
    final normalizedProtocol = protocol.toLowerCase();
    final programPath = _resolveLaunchPath(
      _metadataString(debugger.metadata, 'programPath') ??
          _metadataString(debugger.metadata, 'launchProgram') ??
          _metadataString(debugger.metadata, 'program') ??
          _metadataString(debugger.metadata, 'executableTarget'),
      workspaceRoot,
    );
    final cwd =
        _resolveLaunchPath(
          _metadataString(debugger.metadata, 'cwd'),
          workspaceRoot,
        ) ??
        workspaceRoot;
    final List<String> arguments =
        _metadataStringList(debugger.metadata, 'arguments') ??
        _metadataStringList(debugger.metadata, 'args') ??
        const <String>[];
    final List<String> debuggerArguments =
        _metadataStringList(debugger.metadata, 'debuggerArguments') ??
        _metadataStringList(debugger.metadata, 'debugAdapterArguments') ??
        _metadataStringList(debugger.metadata, 'adapterArguments') ??
        const <String>[];
    final environment = _metadataStringMap(debugger.metadata, 'environment');
    final stopOnEntry =
        _metadataBool(debugger.metadata, 'stopOnEntry') ?? false;
    final launchBreakpoints = breakpoints.toList(growable: false);
    if (normalizedProtocol != 'dap') {
      return DebugLaunchConfiguration(
        readiness: DebugLaunchReadiness.unsupportedProtocol,
        reason:
            'Debug launch blocked: debugger ${debugger.id} uses unsupported protocol $protocol.',
        debuggerId: debugger.id,
        debuggerLabel: debugger.displayName,
        debuggerExecutablePath: debugger.executablePath,
        debuggerArguments: debuggerArguments,
        adapterProtocol: protocol,
        programPath: programPath,
        cwd: cwd,
        arguments: arguments,
        environment: environment,
        stopOnEntry: stopOnEntry,
        breakpoints: launchBreakpoints,
      );
    }
    if (programPath == null || programPath.trim().isEmpty) {
      return DebugLaunchConfiguration(
        readiness: DebugLaunchReadiness.missingProgram,
        reason:
            'Debug launch blocked: debugger ${debugger.id} does not declare metadata.programPath.',
        debuggerId: debugger.id,
        debuggerLabel: debugger.displayName,
        debuggerExecutablePath: debugger.executablePath,
        debuggerArguments: debuggerArguments,
        adapterProtocol: protocol,
        programPath: null,
        cwd: cwd,
        arguments: arguments,
        environment: environment,
        stopOnEntry: stopOnEntry,
        breakpoints: launchBreakpoints,
      );
    }
    return DebugLaunchConfiguration(
      readiness: DebugLaunchReadiness.ready,
      reason: 'Debug launch configuration is ready.',
      debuggerId: debugger.id,
      debuggerLabel: debugger.displayName,
      debuggerExecutablePath: debugger.executablePath,
      debuggerArguments: debuggerArguments,
      adapterProtocol: protocol,
      programPath: programPath,
      cwd: cwd,
      arguments: arguments,
      environment: environment,
      stopOnEntry: stopOnEntry,
      breakpoints: launchBreakpoints,
    );
  }

  final DebugLaunchReadiness readiness;
  final String reason;
  final String debuggerId;
  final String debuggerLabel;
  final String debuggerExecutablePath;
  final List<String> debuggerArguments;
  final String adapterProtocol;
  final String? programPath;
  final String cwd;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool stopOnEntry;
  final List<DebugLaunchBreakpoint> breakpoints;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  bool get ready => readiness == DebugLaunchReadiness.ready;

  static const Set<String> _knownKeys = {
    'schemaVersion',
    'readiness',
    'ready',
    'reason',
    'debuggerId',
    'debuggerLabel',
    'debuggerExecutablePath',
    'debuggerArguments',
    'adapterProtocol',
    'programPath',
    'cwd',
    'arguments',
    'environment',
    'stopOnEntry',
    'breakpointCount',
    'failureNavigationActions',
    'breakpoints',
  };

  List<DebugLaunchFailureNavigationAction> get failureNavigationActions {
    if (ready) {
      return const <DebugLaunchFailureNavigationAction>[];
    }
    return switch (readiness) {
      DebugLaunchReadiness.ready =>
        const <DebugLaunchFailureNavigationAction>[],
      DebugLaunchReadiness.missingProgram =>
        <DebugLaunchFailureNavigationAction>[
          DebugLaunchFailureNavigationAction(
            kind: DebugLaunchFailureNavigationKind.selectProgram,
            label: 'Select debug program',
            target: debuggerId,
            message: 'Set metadata.programPath for this launch profile.',
          ),
          DebugLaunchFailureNavigationAction(
            kind: DebugLaunchFailureNavigationKind.openSettings,
            label: 'Open debug launch settings',
            target: debuggerId,
            message: 'Edit the selected debug launch profile.',
          ),
        ],
      DebugLaunchReadiness.unsupportedProtocol =>
        <DebugLaunchFailureNavigationAction>[
          DebugLaunchFailureNavigationAction(
            kind: DebugLaunchFailureNavigationKind.selectAdapter,
            label: 'Select DAP adapter',
            target: debuggerId,
            message: 'Choose a debugger adapter that supports DAP.',
          ),
          DebugLaunchFailureNavigationAction(
            kind: DebugLaunchFailureNavigationKind.changeProtocol,
            label: 'Change adapter protocol',
            target: adapterProtocol,
            message: 'Set adapterProtocol to dap or install a DAP bridge.',
          ),
        ],
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'readiness': readiness.wireValue,
      'ready': ready,
      'reason': reason,
      'debuggerId': debuggerId,
      'debuggerLabel': debuggerLabel,
      'debuggerExecutablePath': debuggerExecutablePath,
      'debuggerArguments': debuggerArguments,
      'adapterProtocol': adapterProtocol,
      if (programPath != null) 'programPath': programPath,
      'cwd': cwd,
      'arguments': arguments,
      'environment': environment,
      'stopOnEntry': stopOnEntry,
      'breakpointCount': breakpoints.length,
      'failureNavigationActions': failureNavigationActions
          .map((action) => action.toJson())
          .toList(growable: false),
      'breakpoints': breakpoints
          .map((breakpoint) => breakpoint.toJson())
          .toList(growable: false),
      ...extensions,
    };
  }

  RuntimeTaskDefinition toRuntimeTaskDefinition({
    String? taskId,
    String? label,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeTaskDefinition(
      id: taskId ?? 'debug.$debuggerId',
      label: label ?? 'Debug $debuggerLabel',
      kind: RuntimeTaskKind.debug,
      command: ready ? debuggerExecutablePath : '',
      arguments: <String>[
        ...debuggerArguments,
        if (programPath != null) programPath!,
      ],
      workingDirectory: cwd,
      environment: environment,
      group: 'debug',
      metadata: <String, Object?>{
        ...metadata,
        'launch': toJson(),
        'adapterProtocol': adapterProtocol,
        'source': 'DebugLaunchConfiguration',
        'debugConsole': 'runtime-output-channel',
      },
    );
  }

  RuntimeExecutionHandoff toRuntimeExecutionHandoff({
    String? taskId,
    String? label,
    RuntimeExecutionHandoffTarget target =
        RuntimeExecutionHandoffTarget.terminalRuntime,
    String? outputChannelId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final definition = toRuntimeTaskDefinition(
      taskId: taskId,
      label: label,
      metadata: <String, Object?>{
        'debugLaunchReadiness': readiness.wireValue,
        ...metadata,
      },
    );
    final plan = RuntimeExecutionPlan(
      definition: definition,
      status: ready
          ? RuntimeExecutionPlanStatus.ready
          : RuntimeExecutionPlanStatus.blockedUnrunnable,
      message: ready
          ? 'Debug launch $debuggerId is ready for ${target.wireValue}.'
          : reason,
      executionOrder: ready ? <String>[definition.id] : const <String>[],
      metadata: <String, Object?>{
        'debuggerId': debuggerId,
        'adapterProtocol': adapterProtocol,
        'debugLaunchReadiness': readiness.wireValue,
      },
    );
    return plan.createHandoff(
      target: target,
      outputChannelId: outputChannelId ?? 'debug.$debuggerId.console',
      metadata: <String, Object?>{
        'debuggerId': debuggerId,
        'adapterProtocol': adapterProtocol,
        'debugLaunchReadiness': readiness.wireValue,
      },
    );
  }

  DebugLaunchRoutePlan toRoutePlan({
    required String profileId,
    RuntimeExecutionHandoffTarget target =
        RuntimeExecutionHandoffTarget.terminalRuntime,
    String? taskId,
    String? label,
  }) {
    return DebugLaunchRoutePlan.fromConfiguration(
      profileId: profileId,
      configuration: this,
      target: target,
      taskId: taskId,
      label: label,
    );
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

class DebugLaunchFailureNavigationAction {
  const DebugLaunchFailureNavigationAction({
    required this.kind,
    required this.label,
    required this.target,
    required this.message,
  });

  final DebugLaunchFailureNavigationKind kind;
  final String label;
  final String target;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'label': label,
      'target': target,
      'message': message,
    };
  }
}

class DebugLaunchRoutePlan {
  const DebugLaunchRoutePlan({
    required this.profileId,
    required this.status,
    required this.target,
    required this.handoff,
    this.failureNavigationActions =
        const <DebugLaunchFailureNavigationAction>[],
  });

  factory DebugLaunchRoutePlan.fromConfiguration({
    required String profileId,
    required DebugLaunchConfiguration configuration,
    RuntimeExecutionHandoffTarget target =
        RuntimeExecutionHandoffTarget.terminalRuntime,
    String? taskId,
    String? label,
  }) {
    final handoff = configuration.toRuntimeExecutionHandoff(
      taskId: taskId ?? 'debug.$profileId',
      label: label,
      target: target,
      metadata: <String, Object?>{
        'debugLaunchProfileId': profileId,
        'debugRouteTarget': target.wireValue,
      },
    );
    return DebugLaunchRoutePlan(
      profileId: profileId,
      status: configuration.ready
          ? DebugLaunchRouteStatus.ready
          : DebugLaunchRouteStatus.blocked,
      target: target,
      handoff: handoff,
      failureNavigationActions:
          List<DebugLaunchFailureNavigationAction>.unmodifiable(
            configuration.failureNavigationActions,
          ),
    );
  }

  final String profileId;
  final DebugLaunchRouteStatus status;
  final RuntimeExecutionHandoffTarget target;
  final RuntimeExecutionHandoff handoff;
  final List<DebugLaunchFailureNavigationAction> failureNavigationActions;

  bool get ready => status == DebugLaunchRouteStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'status': status.wireValue,
      'ready': ready,
      'target': target.wireValue,
      'handoff': handoff.toJson(),
      'failureNavigationActions': failureNavigationActions
          .map((action) => action.toJson())
          .toList(growable: false),
    };
  }
}

class DebugLaunchProfile {
  const DebugLaunchProfile({
    required this.id,
    required this.displayName,
    required this.configuration,
    this.isDefault = false,
    this.preLaunchTaskId,
    this.metadata = const <String, Object?>{},
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  factory DebugLaunchProfile.fromConfiguration({
    required String id,
    required String displayName,
    required DebugLaunchConfiguration configuration,
    bool isDefault = false,
    String? preLaunchTaskId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return DebugLaunchProfile(
      id: id,
      displayName: displayName,
      configuration: configuration,
      isDefault: isDefault,
      preLaunchTaskId: preLaunchTaskId,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  factory DebugLaunchProfile.fromJson(Map<String, Object?> json) {
    final configuration = json['configuration'];
    return DebugLaunchProfile(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      configuration: configuration is Map<String, Object?>
          ? DebugLaunchConfiguration.fromJson(configuration)
          : configuration is Map
          ? DebugLaunchConfiguration.fromJson(
              configuration.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const DebugLaunchConfiguration(
              readiness: DebugLaunchReadiness.missingProgram,
              reason: 'Debug launch profile is missing configuration.',
              debuggerId: '',
              debuggerLabel: '',
              debuggerExecutablePath: '',
              adapterProtocol: 'dap',
              programPath: null,
              cwd: '',
            ),
      isDefault: json['isDefault'] as bool? ?? false,
      preLaunchTaskId: _jsonNullableString(json['preLaunchTaskId']),
      metadata: _jsonObjectMap(json['metadata']),
      extensions: _collectUnknown(json),
    );
  }

  final String id;
  final String displayName;
  final DebugLaunchConfiguration configuration;
  final bool isDefault;
  final String? preLaunchTaskId;
  final Map<String, Object?> metadata;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  static const Set<String> _knownKeys = {
    'schemaVersion',
    'id',
    'displayName',
    'configuration',
    'isDefault',
    'preLaunchTaskId',
    'metadata',
  };

  DebugLaunchProfile copyWith({
    String? id,
    String? displayName,
    DebugLaunchConfiguration? configuration,
    bool? isDefault,
    String? preLaunchTaskId,
    bool clearPreLaunchTaskId = false,
    Map<String, Object?>? metadata,
  }) {
    return DebugLaunchProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      configuration: configuration ?? this.configuration,
      isDefault: isDefault ?? this.isDefault,
      preLaunchTaskId: clearPreLaunchTaskId
          ? null
          : preLaunchTaskId ?? this.preLaunchTaskId,
      metadata: metadata == null
          ? this.metadata
          : Map<String, Object?>.unmodifiable(metadata),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': id,
      'displayName': displayName,
      'configuration': configuration.toJson(),
      'isDefault': isDefault,
      if (preLaunchTaskId != null) 'preLaunchTaskId': preLaunchTaskId,
      'metadata': metadata,
      ...extensions,
    };
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

class DebugLaunchConfigurationSet {
  const DebugLaunchConfigurationSet({
    required this.workspaceId,
    this.selectedProfileId,
    this.profiles = const <DebugLaunchProfile>[],
    this.updatedAt,
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  factory DebugLaunchConfigurationSet.fromJson(Map<String, Object?> json) {
    return DebugLaunchConfigurationSet(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      workspaceId: json['workspaceId'] as String? ?? '',
      selectedProfileId: _jsonNullableString(json['selectedProfileId']),
      profiles: _jsonProfiles(json['profiles']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
      extensions: _collectUnknown(json),
    );
  }

  final String workspaceId;
  final String? selectedProfileId;
  final List<DebugLaunchProfile> profiles;
  final DateTime? updatedAt;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  static const Set<String> _knownKeys = {
    'schemaVersion',
    'workspaceId',
    'selectedProfileId',
    'profiles',
    'updatedAt',
    'hasRunnableProfile',
    'selectedProfileReady',
  };

  DebugLaunchProfile? get selectedProfile {
    final selectedId = selectedProfileId;
    if (selectedId != null) {
      for (final profile in profiles) {
        if (profile.id == selectedId) {
          return profile;
        }
      }
    }
    for (final profile in profiles) {
      if (profile.isDefault) {
        return profile;
      }
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  bool get hasRunnableProfile =>
      profiles.any((profile) => profile.configuration.ready);

  DebugLaunchConfigurationSet upsertProfile(DebugLaunchProfile profile) {
    final nextProfiles = <DebugLaunchProfile>[];
    var replaced = false;
    for (final existing in profiles) {
      if (existing.id == profile.id) {
        nextProfiles.add(profile);
        replaced = true;
      } else if (profile.isDefault && existing.isDefault) {
        nextProfiles.add(existing.copyWith(isDefault: false));
      } else {
        nextProfiles.add(existing);
      }
    }
    if (!replaced) {
      nextProfiles.add(profile);
    }
    return copyWith(
      profiles: nextProfiles,
      selectedProfileId: selectedProfileId ?? profile.id,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  DebugLaunchConfigurationSet selectProfile(String profileId) {
    final exists = profiles.any((profile) => profile.id == profileId);
    return exists
        ? copyWith(
            selectedProfileId: profileId,
            updatedAt: DateTime.now().toUtc(),
          )
        : this;
  }

  DebugLaunchConfigurationSet removeProfile(String profileId) {
    final nextProfiles = profiles
        .where((profile) => profile.id != profileId)
        .toList(growable: false);
    final nextSelected = selectedProfileId == profileId
        ? null
        : selectedProfileId;
    return copyWith(
      profiles: nextProfiles,
      selectedProfileId: nextSelected,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  DebugLaunchConfigurationSet copyWith({
    String? workspaceId,
    String? selectedProfileId,
    bool clearSelectedProfileId = false,
    List<DebugLaunchProfile>? profiles,
    DateTime? updatedAt,
  }) {
    return DebugLaunchConfigurationSet(
      workspaceId: workspaceId ?? this.workspaceId,
      selectedProfileId: clearSelectedProfileId
          ? null
          : selectedProfileId ?? this.selectedProfileId,
      profiles: profiles ?? this.profiles,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'workspaceId': workspaceId,
      if (selectedProfileId != null) 'selectedProfileId': selectedProfileId,
      'profiles': profiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'hasRunnableProfile': hasRunnableProfile,
      'selectedProfileReady': selectedProfile?.configuration.ready ?? false,
      ...extensions,
    };
  }

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }
}

class DebugLaunchConfigurationStore {
  DebugLaunchConfigurationStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'debug.launch-configuration',
             layer: 'debugger',
             stateFamily: 'launch-configuration',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const DebugLaunchConfigurationStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'debug.launch-configurations';
  static const String _key = 'profiles';

  final FoundationDataStoreOwner _owner;

  Future<void> saveConfigurationSet(DebugLaunchConfigurationSet set) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: set.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: set.workspaceId,
    );
  }

  Future<DebugLaunchConfigurationSet> loadConfigurationSet({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return DebugLaunchConfigurationSet(workspaceId: workspaceId);
    }
    final set = DebugLaunchConfigurationSet.fromJson(value);
    return set.workspaceId.isEmpty
        ? set.copyWith(workspaceId: workspaceId)
        : set;
  }

  Future<bool> deleteConfigurationSet({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchConfigurationSet({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool? _metadataBool(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is bool ? value : null;
}

List<String>? _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is List) {
    return value
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
  if (value is String && value.trim().isNotEmpty) {
    return <String>[value.trim()];
  }
  return null;
}

Map<String, String> _metadataStringMap(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final mapKey = entry.key;
    final mapValue = entry.value;
    if (mapKey is String && mapValue is String && mapKey.trim().isNotEmpty) {
      result[mapKey.trim()] = mapValue;
    }
  }
  return Map<String, String>.unmodifiable(result);
}

String? _resolveLaunchPath(String? path, String workspaceRoot) {
  final normalizedPath = path?.trim();
  if (normalizedPath == null || normalizedPath.isEmpty) {
    return null;
  }
  if (_isAbsolutePath(normalizedPath)) {
    return normalizedPath;
  }
  final root = workspaceRoot.trim();
  if (root.isEmpty) {
    return normalizedPath;
  }
  final separator = root.contains('\\') ? '\\' : '/';
  if (root.endsWith('/') || root.endsWith('\\')) {
    return '$root$normalizedPath';
  }
  return '$root$separator$normalizedPath';
}

bool _isAbsolutePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String? _jsonNullableString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _jsonStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final entryValue = entry.value;
    if (key is String && entryValue is String && key.trim().isNotEmpty) {
      result[key.trim()] = entryValue;
    }
  }
  return Map<String, String>.unmodifiable(result);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}

List<DebugLaunchBreakpoint> _jsonBreakpoints(Object? value) {
  if (value is! List) {
    return const <DebugLaunchBreakpoint>[];
  }
  return value
      .whereType<Map>()
      .map(
        (breakpoint) => DebugLaunchBreakpoint.fromJson(
          breakpoint.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

List<DebugLaunchProfile> _jsonProfiles(Object? value) {
  if (value is! List) {
    return const <DebugLaunchProfile>[];
  }
  return value
      .whereType<Map>()
      .map(
        (profile) => DebugLaunchProfile.fromJson(
          profile.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
