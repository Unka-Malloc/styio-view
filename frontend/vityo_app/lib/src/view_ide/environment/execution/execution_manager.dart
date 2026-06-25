import 'dart:convert';

import '../configuration/environment_variable_configuration.dart';
import '../system_compatibility/platform_context/platform_context_model.dart';
import '../system_compatibility/platform_manager/platform_manager.dart';
import '../system_compatibility/process/process_manager.dart';
import 'execution_sandbox.dart';

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
    this.requiresWorkspaceWrite = false,
    this.requiresNetwork = false,
  });

  final String executablePath;
  final List<String> arguments;
  final Iterable<Map<String, String?>> envFileVariables;
  final Iterable<EnvironmentVariableOverlay> environmentOverlays;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration? timeout;
  final String operation;
  final bool requiresWorkspaceWrite;
  final bool requiresNetwork;
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
    ExecutionSandbox? executionSandbox,
  }) : _processManager = processManager,
       _environmentResolver = environmentResolver,
       _redactionPolicy = redactionPolicy,
       _inheritedEnvironment = inheritedEnvironment,
       _pathSeparator = pathSeparator,
       _executionSandbox = executionSandbox;

  factory ExecutionManager.fromPlatformContext({
    required PlatformContextSnapshot platformContext,
    required ProcessManager processManager,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
    ExecutionSandbox? executionSandbox,
  }) {
    return ExecutionManager(
      processManager: processManager,
      environmentResolver: environmentResolver,
      redactionPolicy: redactionPolicy,
      inheritedEnvironment: inheritedEnvironment,
      pathSeparator: pathListSeparatorForPlatformContext(platformContext),
      executionSandbox: executionSandbox,
    );
  }

  factory ExecutionManager.fromPlatformManagers({
    required PlatformManagerBundle platformManagers,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
    ExecutionSandbox? executionSandbox,
  }) {
    return ExecutionManager.fromPlatformContext(
      platformContext: platformManagers.context,
      processManager: platformManagers.process,
      environmentResolver: environmentResolver,
      redactionPolicy: redactionPolicy,
      inheritedEnvironment: inheritedEnvironment,
      executionSandbox: executionSandbox,
    );
  }

  final ProcessManager _processManager;
  final EnvironmentVariableResolver _environmentResolver;
  final EnvironmentVariableRedactionPolicy _redactionPolicy;
  final Map<String, String> _inheritedEnvironment;
  final String _pathSeparator;
  final ExecutionSandbox? _executionSandbox;

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
    final sandbox = _executionSandbox;
    ExecutionSandboxDecision? sandboxDecision;
    if (sandbox != null) {
      final decision = sandbox.evaluate(
        ExecutionSandboxRequest(
          executable: request.executablePath,
          arguments: request.arguments,
          cwd: request.workingDirectory ?? '.',
          environment: environment,
          requiresWorkspaceWrite: request.requiresWorkspaceWrite,
          requiresNetwork: request.requiresNetwork,
          timeout: request.timeout,
          correlationId: request.operation,
        ),
      );
      sandboxDecision = decision;
      if (!decision.isAllowed) {
        final failure = decision.failure;
        return ExecutionResult(
          status: ExecutionManagerStatus.blocked,
          processResult: ProcessCommandResult(
            status: ProcessCommandStatus.blocked,
            executablePath: request.executablePath,
            arguments: request.arguments,
            exitCode: null,
            stdout: '',
            stderr: '',
            duration: Duration.zero,
            message: failure?.message ?? 'Execution blocked by sandbox.',
            metadata: <String, Object?>{
              'sandboxFailureCode': failure?.code.name,
              'recoveryAction': failure?.recoveryAction,
              'developerDetail': failure?.developerDetail,
              'correlationId': failure?.correlationId,
            },
          ),
          redactedEnvironment: _redactionPolicy.redactEnvironment(environment),
        );
      }
    }
    final rawProcessResult = await _processManager.run(
      ProcessCommandRequest(
        executablePath: request.executablePath,
        arguments: request.arguments,
        environment: environment,
        workingDirectory:
            sandboxDecision?.normalizedCwd ?? request.workingDirectory,
        timeout: sandboxDecision?.effectiveTimeout ?? request.timeout,
      ),
    );
    final processResult = sandbox == null
        ? rawProcessResult
        : _applyOutputLimits(
            rawProcessResult,
            maxStdoutBytes: sandbox.policy.maxStdoutBytes,
            maxStderrBytes: sandbox.policy.maxStderrBytes,
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

  ProcessCommandResult _applyOutputLimits(
    ProcessCommandResult result, {
    required int maxStdoutBytes,
    required int maxStderrBytes,
  }) {
    final stdout = _limitUtf8(result.stdout, maxStdoutBytes);
    final stderr = _limitUtf8(result.stderr, maxStderrBytes);
    if (!stdout.truncated && !stderr.truncated) {
      return result;
    }
    return ProcessCommandResult(
      status: result.status,
      executablePath: result.executablePath,
      arguments: result.arguments,
      exitCode: result.exitCode,
      stdout: stdout.value,
      stderr: stderr.value,
      duration: result.duration,
      message: result.message,
      metadata: <String, Object?>{
        ...result.metadata,
        if (stdout.truncated) 'stdoutTruncated': true,
        if (stdout.truncated) 'stdoutLimitBytes': maxStdoutBytes,
        if (stderr.truncated) 'stderrTruncated': true,
        if (stderr.truncated) 'stderrLimitBytes': maxStderrBytes,
      },
    );
  }

  _LimitedString _limitUtf8(String value, int maxBytes) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxBytes) {
      return _LimitedString(value: value, truncated: false);
    }
    return _LimitedString(
      value: utf8.decode(bytes.take(maxBytes).toList(), allowMalformed: true),
      truncated: true,
    );
  }
}

class _LimitedString {
  const _LimitedString({required this.value, required this.truncated});

  final String value;
  final bool truncated;
}
