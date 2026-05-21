import 'styio_service_subscription.dart';

typedef StyioServiceDaemonProcessLauncher =
    Future<StyioServiceDaemonProcessLaunchResult> Function(
      StyioServiceDaemonProcessLaunchRequest request,
    );

enum StyioServiceDaemonProcessLauncherKind {
  localProcess,
  remoteService,
  inProcessFixture,
}

extension StyioServiceDaemonProcessLauncherKindX
    on StyioServiceDaemonProcessLauncherKind {
  String get wireValue => switch (this) {
    StyioServiceDaemonProcessLauncherKind.localProcess => 'local-process',
    StyioServiceDaemonProcessLauncherKind.remoteService => 'remote-service',
    StyioServiceDaemonProcessLauncherKind.inProcessFixture =>
      'in-process-fixture',
  };
}

class StyioServiceDaemonProcessLaunchRequest {
  StyioServiceDaemonProcessLaunchRequest({
    required this.providerId,
    required this.reason,
    required this.attempt,
    required this.restartable,
    required Iterable<String> arguments,
    this.workingDirectory = '',
    Map<String, String> environment = const <String, String>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = Map<String, String>.unmodifiable(environment),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  factory StyioServiceDaemonProcessLaunchRequest.fromRestartPlan(
    StyioServiceDaemonRestartPlan plan, {
    Iterable<String> arguments = const <String>[],
    String workingDirectory = '',
    Map<String, String> environment = const <String, String>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return StyioServiceDaemonProcessLaunchRequest(
      providerId: plan.providerId,
      reason: plan.reason,
      attempt: plan.nextAttempt,
      restartable: plan.restartable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      metadata: metadata,
    );
  }

  final String providerId;
  final StyioServiceDaemonRestartReason reason;
  final int attempt;
  final bool restartable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'reason': reason.name,
      'attempt': attempt,
      'restartable': restartable,
      if (arguments.isNotEmpty) 'arguments': arguments,
      if (workingDirectory.isNotEmpty) 'workingDirectory': workingDirectory,
      if (environment.isNotEmpty) 'environmentKeys': environment.keys.toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class StyioServiceDaemonProcessLaunchResult {
  const StyioServiceDaemonProcessLaunchResult({
    required this.started,
    required this.message,
    this.providerId = '',
    this.processId,
    this.endpoint = '',
    this.metadata = const <String, Object?>{},
  });

  const StyioServiceDaemonProcessLaunchResult.started({
    String message = 'StyioService daemon process started.',
    String providerId = '',
    int? processId,
    String endpoint = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         started: true,
         message: message,
         providerId: providerId,
         processId: processId,
         endpoint: endpoint,
         metadata: metadata,
       );

  const StyioServiceDaemonProcessLaunchResult.failed({
    String message = 'StyioService daemon process failed to start.',
    String providerId = '',
    int? processId,
    String endpoint = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         started: false,
         message: message,
         providerId: providerId,
         processId: processId,
         endpoint: endpoint,
         metadata: metadata,
       );

  final bool started;
  final String message;
  final String providerId;
  final int? processId;
  final String endpoint;
  final Map<String, Object?> metadata;

  StyioServiceDaemonLifecycleSnapshot toLifecycleSnapshot({
    required String fallbackProviderId,
  }) {
    return StyioServiceDaemonLifecycleSnapshot(
      state: started
          ? StyioServiceDaemonLifecycleState.active
          : StyioServiceDaemonLifecycleState.failed,
      providerId: providerId.isEmpty ? fallbackProviderId : providerId,
      message: message,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'started': started,
      'message': message,
      if (providerId.isNotEmpty) 'providerId': providerId,
      if (processId != null) 'processId': processId,
      if (endpoint.isNotEmpty) 'endpoint': endpoint,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class StyioServiceDaemonProcessLauncherRegistration {
  StyioServiceDaemonProcessLauncherRegistration({
    required this.launcherId,
    required this.label,
    required this.kind,
    required this.launcher,
    Iterable<String> providerIds = const <String>[],
    this.available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : providerIds = Set<String>.unmodifiable(providerIds),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String launcherId;
  final String label;
  final StyioServiceDaemonProcessLauncherKind kind;
  final StyioServiceDaemonProcessLauncher launcher;
  final Set<String> providerIds;
  final bool available;
  final Map<String, Object?> metadata;

  bool accepts(StyioServiceDaemonProcessLaunchRequest request) {
    return available &&
        (providerIds.isEmpty || providerIds.contains(request.providerId));
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'launcherId': launcherId,
      'label': label,
      'kind': kind.wireValue,
      'providerIds': providerIds.toList(),
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class StyioServiceDaemonProcessLauncherRegistry {
  StyioServiceDaemonProcessLauncherRegistry({
    Iterable<StyioServiceDaemonProcessLauncherRegistration> launchers =
        const <StyioServiceDaemonProcessLauncherRegistration>[],
  }) {
    for (final launcher in launchers) {
      register(launcher);
    }
  }

  final List<StyioServiceDaemonProcessLauncherRegistration> _launchers =
      <StyioServiceDaemonProcessLauncherRegistration>[];

  List<StyioServiceDaemonProcessLauncherRegistration> get launchers {
    return List<StyioServiceDaemonProcessLauncherRegistration>.unmodifiable(
      _launchers,
    );
  }

  void register(StyioServiceDaemonProcessLauncherRegistration launcher) {
    _launchers.removeWhere(
      (candidate) => candidate.launcherId == launcher.launcherId,
    );
    _launchers.add(launcher);
  }

  StyioServiceDaemonProcessLauncherRegistration? resolve(
    StyioServiceDaemonProcessLaunchRequest request,
  ) {
    for (final launcher in _launchers) {
      if (launcher.accepts(request)) {
        return launcher;
      }
    }
    return null;
  }

  Future<StyioServiceDaemonProcessLaunchResult> launch(
    StyioServiceDaemonProcessLaunchRequest request,
  ) async {
    final registration = resolve(request);
    if (registration == null) {
      return StyioServiceDaemonProcessLaunchResult.failed(
        providerId: request.providerId,
        message:
            'StyioService daemon process launcher is missing for provider '
            '${request.providerId}.',
        metadata: const <String, Object?>{'launcherMissing': true},
      );
    }
    try {
      final result = await registration.launcher(request);
      return StyioServiceDaemonProcessLaunchResult(
        started: result.started,
        message: result.message,
        providerId: result.providerId.isEmpty
            ? request.providerId
            : result.providerId,
        processId: result.processId,
        endpoint: result.endpoint,
        metadata: <String, Object?>{
          'launcherId': registration.launcherId,
          'launcherKind': registration.kind.wireValue,
          ...registration.metadata,
          ...result.metadata,
        },
      );
    } on Object catch (error) {
      return StyioServiceDaemonProcessLaunchResult.failed(
        providerId: request.providerId,
        message: 'StyioService daemon process launcher failed: $error',
        metadata: <String, Object?>{
          'launcherId': registration.launcherId,
          'launcherKind': registration.kind.wireValue,
          'error': error.toString(),
        },
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'launcherCount': _launchers.length,
      'launchers': _launchers
          .map((launcher) => launcher.toJson())
          .toList(growable: false),
    };
  }
}

typedef StyioServiceDaemonLocalProcessStarter =
    Future<StyioServiceDaemonLocalProcessStartResult> Function(
      StyioServiceDaemonLocalProcessStartRequest request,
    );

class StyioServiceDaemonLocalProcessStartRequest {
  StyioServiceDaemonLocalProcessStartRequest({
    required this.executablePath,
    required Iterable<String> arguments,
    this.workingDirectory = '',
    Map<String, String> environment = const <String, String>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = Map<String, String>.unmodifiable(environment),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String executablePath;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'executablePath': executablePath,
      'arguments': arguments,
      if (workingDirectory.isNotEmpty) 'workingDirectory': workingDirectory,
      if (environment.isNotEmpty) 'environmentKeys': environment.keys.toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class StyioServiceDaemonLocalProcessStartResult {
  const StyioServiceDaemonLocalProcessStartResult({
    required this.started,
    required this.message,
    this.pid,
    this.endpoint = '',
    this.metadata = const <String, Object?>{},
  });

  const StyioServiceDaemonLocalProcessStartResult.started({
    String message = 'StyioService local process started.',
    int? pid,
    String endpoint = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         started: true,
         message: message,
         pid: pid,
         endpoint: endpoint,
         metadata: metadata,
       );

  const StyioServiceDaemonLocalProcessStartResult.failed({
    String message = 'StyioService local process failed to start.',
    int? pid,
    String endpoint = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         started: false,
         message: message,
         pid: pid,
         endpoint: endpoint,
         metadata: metadata,
       );

  final bool started;
  final String message;
  final int? pid;
  final String endpoint;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'started': started,
      'message': message,
      if (pid != null) 'pid': pid,
      if (endpoint.isNotEmpty) 'endpoint': endpoint,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class StyioServiceDaemonLocalProcessLauncher {
  StyioServiceDaemonLocalProcessLauncher({
    required this.executablePath,
    required this.starter,
    this.endpoint = 'stdio://styio-service',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : metadata = Map<String, Object?>.unmodifiable(metadata);

  final String executablePath;
  final String endpoint;
  final StyioServiceDaemonLocalProcessStarter starter;
  final Map<String, Object?> metadata;

  StyioServiceDaemonProcessLauncherRegistration registration({
    String launcherId = 'styio-service-local-process',
    String label = 'StyioService Local Process',
    Iterable<String> providerIds = const <String>[],
    bool available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return StyioServiceDaemonProcessLauncherRegistration(
      launcherId: launcherId,
      label: label,
      kind: StyioServiceDaemonProcessLauncherKind.localProcess,
      providerIds: providerIds,
      available: available,
      metadata: <String, Object?>{...this.metadata, ...metadata},
      launcher: launch,
    );
  }

  Future<StyioServiceDaemonProcessLaunchResult> launch(
    StyioServiceDaemonProcessLaunchRequest request,
  ) async {
    final executable = executablePath.trim();
    if (executable.isEmpty) {
      return StyioServiceDaemonProcessLaunchResult.failed(
        providerId: request.providerId,
        message: 'StyioService local process launcher has no executable path.',
        metadata: const <String, Object?>{
          'localProcessLauncher': true,
          'TODO': 'Resolve StyioService executable from ToolchainManager.',
        },
      );
    }
    final startRequest = StyioServiceDaemonLocalProcessStartRequest(
      executablePath: executable,
      arguments: request.arguments,
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      metadata: <String, Object?>{
        ...metadata,
        ...request.metadata,
        'providerId': request.providerId,
        'restartReason': request.reason.name,
        'attempt': request.attempt,
      },
    );
    try {
      final result = await starter(startRequest);
      final resolvedEndpoint = result.endpoint.isEmpty
          ? endpoint
          : result.endpoint;
      final generatedHandle = result.pid == null
          ? const <String, Object?>{}
          : <String, Object?>{
              'pid': result.pid,
              'processHandleId': '${result.pid}',
              'processHandleSource': 'StyioServiceDaemonLocalProcessLauncher',
            };
      return StyioServiceDaemonProcessLaunchResult(
        started: result.started,
        providerId: request.providerId,
        processId: result.pid,
        endpoint: resolvedEndpoint,
        message: result.message,
        metadata: <String, Object?>{
          'localProcessLauncher': true,
          'executablePath': executable,
          ...generatedHandle,
          ...result.metadata,
        },
      );
    } on Object catch (error) {
      return StyioServiceDaemonProcessLaunchResult.failed(
        providerId: request.providerId,
        message: 'StyioService local process launcher failed: $error',
        metadata: <String, Object?>{
          'localProcessLauncher': true,
          'executablePath': executable,
          'error': error.toString(),
        },
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'executablePath': executablePath,
      'endpoint': endpoint,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class StyioServiceDaemonProcessAdapter
    implements StyioServiceDaemonProcessSupervisor {
  StyioServiceDaemonProcessAdapter({
    required this.launcher,
    Iterable<String> defaultArguments = const <String>[],
    this.workingDirectory = '',
    Map<String, String> environment = const <String, String>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : defaultArguments = List<String>.unmodifiable(defaultArguments),
       environment = Map<String, String>.unmodifiable(environment),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  factory StyioServiceDaemonProcessAdapter.fromRegistry({
    required StyioServiceDaemonProcessLauncherRegistry registry,
    Iterable<String> defaultArguments = const <String>[],
    String workingDirectory = '',
    Map<String, String> environment = const <String, String>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return StyioServiceDaemonProcessAdapter(
      launcher: registry.launch,
      defaultArguments: defaultArguments,
      workingDirectory: workingDirectory,
      environment: environment,
      metadata: <String, Object?>{'launcherRegistry': true, ...metadata},
    );
  }

  final StyioServiceDaemonProcessLauncher launcher;
  final List<String> defaultArguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final Map<String, Object?> metadata;

  @override
  Future<StyioServiceDaemonLifecycleSnapshot> restartStyioServiceDaemon(
    StyioServiceDaemonRestartPlan plan,
  ) async {
    final request = StyioServiceDaemonProcessLaunchRequest.fromRestartPlan(
      plan,
      arguments: defaultArguments,
      workingDirectory: workingDirectory,
      environment: environment,
      metadata: metadata,
    );
    try {
      final result = await launcher(request);
      return result.toLifecycleSnapshot(fallbackProviderId: plan.providerId);
    } on Object catch (error) {
      return StyioServiceDaemonLifecycleSnapshot(
        state: StyioServiceDaemonLifecycleState.failed,
        providerId: plan.providerId,
        message: 'StyioService daemon process launcher failed: $error',
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'defaultArguments': defaultArguments,
      if (workingDirectory.isNotEmpty) 'workingDirectory': workingDirectory,
      if (environment.isNotEmpty) 'environmentKeys': environment.keys.toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}
