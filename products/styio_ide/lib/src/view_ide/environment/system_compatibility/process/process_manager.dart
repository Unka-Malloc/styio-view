import 'process_adapter.dart';
import 'process_facts.dart';

enum ProcessCommandStatus { succeeded, failed, timedOut, blocked }

enum ProcessFailureKind {
  unsupported,
  executableNotFound,
  permissionDenied,
  timedOut,
  nonZeroExit,
  spawnFailed,
  unknownFailure,
}

class ProcessCommandRequest {
  const ProcessCommandRequest({
    required this.executablePath,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.workingDirectory,
    this.timeout,
    this.standardInput,
  });

  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration? timeout;
  final String? standardInput;
}

class ProcessOperationFailure {
  const ProcessOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final ProcessFailureKind kind;
  final String operation;
  final String target;
  final String sourceManager;
  final String message;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'target': target,
      'sourceManager': sourceManager,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

class ProcessCommandResult {
  const ProcessCommandResult({
    required this.status,
    required this.executablePath,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
    this.message,
    this.metadata = const <String, Object?>{},
  });

  final ProcessCommandStatus status;
  final String executablePath;
  final List<String> arguments;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final String? message;
  final Map<String, Object?> metadata;
  bool get succeeded => status == ProcessCommandStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'executablePath': executablePath,
      'arguments': arguments,
      if (exitCode != null) 'exitCode': exitCode,
      'stdout': stdout,
      'stderr': stderr,
      'durationMilliseconds': duration.inMilliseconds,
      if (message != null) 'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'succeeded': succeeded,
    };
  }
}

class ProcessFailureClassifier {
  const ProcessFailureClassifier({required this.sourceManager});

  final String sourceManager;

  ProcessOperationFailure? classify(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    if (result.succeeded) {
      return null;
    }
    return ProcessOperationFailure(
      kind: _kindFor(result),
      operation: operation,
      target: result.executablePath,
      sourceManager: sourceManager,
      message: result.message ?? result.stderr,
      recoveryHint: recoveryHint,
    );
  }

  ProcessFailureKind _kindFor(ProcessCommandResult result) {
    return switch (result.status) {
      ProcessCommandStatus.succeeded => ProcessFailureKind.unknownFailure,
      ProcessCommandStatus.blocked => ProcessFailureKind.unsupported,
      ProcessCommandStatus.timedOut => ProcessFailureKind.timedOut,
      ProcessCommandStatus.failed =>
        result.exitCode == null
            ? ProcessFailureKind.spawnFailed
            : ProcessFailureKind.nonZeroExit,
    };
  }
}

abstract class ProcessManager {
  ProcessFacts get facts;
  ProcessCompatibility get compatibility;
  Future<ProcessCommandResult> run(ProcessCommandRequest request);
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  });
}

class UnsupportedProcessManager implements ProcessManager {
  UnsupportedProcessManager({required this.facts})
    : compatibility = ProcessAdapter(facts).adapt();
  @override
  final ProcessFacts facts;
  @override
  final ProcessCompatibility compatibility;
  @override
  Future<ProcessCommandResult> run(ProcessCommandRequest request) async =>
      ProcessCommandResult(
        status: ProcessCommandStatus.blocked,
        executablePath: request.executablePath,
        arguments: request.arguments,
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
        message: 'Process execution is not available.',
      );
  @override
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    return const ProcessFailureClassifier(
      sourceManager: 'UnsupportedProcessManager',
    ).classify(result, operation: operation, recoveryHint: recoveryHint);
  }
}
