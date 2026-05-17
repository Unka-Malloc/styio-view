import '../configuration/environment_variable_configuration.dart';
import '../system_compatibility/platform_context/platform_context_model.dart';
import '../system_compatibility/platform_manager/platform_manager.dart';
import '../system_compatibility/process/process_manager.dart';

enum ExecutionManagerStatus { succeeded, failed, blocked }

class ExecutionRequest {
  const ExecutionRequest({
    required this.executablePath,
    this.arguments = const <String>[],
    this.envFileVariables = const <Map<String, String?>>[],
    this.environmentOverlays = const <EnvironmentVariableOverlay>[],
    this.environment = const <String, String>{},
    this.workingDirectory,
    this.timeout,
    this.operation = 'execution.run',
  });

  final String executablePath;
  final List<String> arguments;
  final Iterable<Map<String, String?>> envFileVariables;
  final Iterable<EnvironmentVariableOverlay> environmentOverlays;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration? timeout;
  final String operation;
}

class ExecutionResult {
  const ExecutionResult({
    required this.status,
    required this.processResult,
    required this.redactedEnvironment,
    this.platformFailure,
  });

  final ExecutionManagerStatus status;
  final ProcessCommandResult processResult;
  final Map<String, String> redactedEnvironment;
  final ProcessOperationFailure? platformFailure;

  bool get succeeded => status == ExecutionManagerStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'processResult': _processResultStatusJson(processResult),
      'redactedEnvironment': redactedEnvironment,
      if (platformFailure != null) 'platformFailure': platformFailure!.toJson(),
      'succeeded': succeeded,
    };
  }

  Map<String, Object?> _processResultStatusJson(ProcessCommandResult result) {
    return <String, Object?>{
      'status': result.status.name,
      'executablePath': result.executablePath,
      'arguments': result.arguments,
      if (result.exitCode != null) 'exitCode': result.exitCode,
      'durationMilliseconds': result.duration.inMilliseconds,
      if (result.message != null) 'message': result.message,
      'succeeded': result.succeeded,
    };
  }
}

class ExecutionManager {
  const ExecutionManager({
    required ProcessManager processManager,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
    String pathSeparator = ':',
  }) : _processManager = processManager,
       _environmentResolver = environmentResolver,
       _redactionPolicy = redactionPolicy,
       _inheritedEnvironment = inheritedEnvironment,
       _pathSeparator = pathSeparator;

  factory ExecutionManager.fromPlatformContext({
    required PlatformContextSnapshot platformContext,
    required ProcessManager processManager,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return ExecutionManager(
      processManager: processManager,
      environmentResolver: environmentResolver,
      redactionPolicy: redactionPolicy,
      inheritedEnvironment: inheritedEnvironment,
      pathSeparator: pathListSeparatorForPlatformContext(platformContext),
    );
  }

  factory ExecutionManager.fromPlatformManagers({
    required PlatformManagerBundle platformManagers,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return ExecutionManager.fromPlatformContext(
      platformContext: platformManagers.context,
      processManager: platformManagers.process,
      environmentResolver: environmentResolver,
      redactionPolicy: redactionPolicy,
      inheritedEnvironment: inheritedEnvironment,
    );
  }

  final ProcessManager _processManager;
  final EnvironmentVariableResolver _environmentResolver;
  final EnvironmentVariableRedactionPolicy _redactionPolicy;
  final Map<String, String> _inheritedEnvironment;
  final String _pathSeparator;

  static String pathListSeparatorForPlatformContext(
    PlatformContextSnapshot context,
  ) {
    return context.environmentPathListSeparator;
  }

  Future<ExecutionResult> run(ExecutionRequest request) async {
    final environment = _environmentResolver.resolve(
      inherited: _inheritedEnvironment,
      envFileVariables: request.envFileVariables,
      overlays: request.environmentOverlays,
      runtimeOverrides: request.environment,
      pathSeparator: _pathSeparator,
    );
    final processResult = await _processManager.run(
      ProcessCommandRequest(
        executablePath: request.executablePath,
        arguments: request.arguments,
        environment: environment,
        workingDirectory: request.workingDirectory,
        timeout: request.timeout,
      ),
    );
    final platformFailure = _processManager.failureFor(
      processResult,
      operation: request.operation,
    );
    return ExecutionResult(
      status: _statusFor(processResult),
      processResult: processResult,
      platformFailure: platformFailure,
      redactedEnvironment: _redactionPolicy.redactEnvironment(environment),
    );
  }

  ExecutionManagerStatus _statusFor(ProcessCommandResult result) {
    return switch (result.status) {
      ProcessCommandStatus.succeeded => ExecutionManagerStatus.succeeded,
      ProcessCommandStatus.blocked => ExecutionManagerStatus.blocked,
      ProcessCommandStatus.failed ||
      ProcessCommandStatus.timedOut => ExecutionManagerStatus.failed,
    };
  }
}
