import 'styio_service_subscription.dart';

typedef StyioServiceDaemonProcessLauncher =
    Future<StyioServiceDaemonProcessLaunchResult> Function(
      StyioServiceDaemonProcessLaunchRequest request,
    );

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
