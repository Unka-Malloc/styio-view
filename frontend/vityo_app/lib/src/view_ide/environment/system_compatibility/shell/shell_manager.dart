import '../../configuration/shell_configuration.dart';
import 'shell_adapter.dart';
import 'shell_facts.dart';

enum ShellCommandStatus { succeeded, failed, timedOut, blocked }

enum ShellFailureKind {
  unsupported,
  shellUnavailable,
  timedOut,
  nonZeroExit,
  spawnFailed,
  unknownFailure,
}

class ShellCommandRequest {
  const ShellCommandRequest({
    required this.command,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.workingDirectory,
    this.timeout,
    this.profile,
    this.loginShell,
  });

  final String command;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration? timeout;
  final ShellProfileConfiguration? profile;
  final bool? loginShell;
}

class ShellOperationFailure {
  const ShellOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final ShellFailureKind kind;
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

class ShellCommandResult {
  const ShellCommandResult({
    required this.status,
    required this.command,
    required this.executablePath,
    required this.arguments,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
    this.message,
    this.metadata = const <String, Object?>{},
  });

  final ShellCommandStatus status;
  final String command;
  final String executablePath;
  final List<String> arguments;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;
  final String? message;
  final Map<String, Object?> metadata;

  bool get succeeded => status == ShellCommandStatus.succeeded;
}

class ShellFailureClassifier {
  const ShellFailureClassifier({required this.sourceManager});

  final String sourceManager;

  ShellOperationFailure? classify(
    ShellCommandResult result, {
    String operation = 'shell.run',
    String? recoveryHint,
  }) {
    if (result.succeeded) {
      return null;
    }
    return ShellOperationFailure(
      kind: _kindFor(result),
      operation: operation,
      target: result.executablePath.isEmpty
          ? result.command
          : result.executablePath,
      sourceManager: sourceManager,
      message: result.message ?? result.stderr,
      recoveryHint: recoveryHint,
    );
  }

  ShellFailureKind _kindFor(ShellCommandResult result) {
    return switch (result.status) {
      ShellCommandStatus.succeeded => ShellFailureKind.unknownFailure,
      ShellCommandStatus.blocked => ShellFailureKind.unsupported,
      ShellCommandStatus.timedOut => ShellFailureKind.timedOut,
      ShellCommandStatus.failed =>
        result.exitCode == null
            ? ShellFailureKind.spawnFailed
            : ShellFailureKind.nonZeroExit,
    };
  }
}

abstract class ShellManager {
  ShellFacts get facts;

  ShellCompatibility get compatibility;

  Future<ShellCommandResult> run(
    ShellCommandRequest request, {
    ShellConfiguration? configuration,
  });

  ShellOperationFailure? failureFor(
    ShellCommandResult result, {
    String operation = 'shell.run',
    String? recoveryHint,
  });
}

class UnsupportedShellManager implements ShellManager {
  UnsupportedShellManager({required this.facts})
    : compatibility = ShellAdapter(facts).adapt();

  @override
  final ShellFacts facts;

  @override
  final ShellCompatibility compatibility;

  @override
  Future<ShellCommandResult> run(
    ShellCommandRequest request, {
    ShellConfiguration? configuration,
  }) async {
    return ShellCommandResult(
      status: ShellCommandStatus.blocked,
      command: request.command,
      executablePath: '',
      arguments: const <String>[],
      exitCode: null,
      stdout: '',
      stderr: '',
      duration: Duration.zero,
      message: 'Shell execution is not available on this platform.',
    );
  }

  @override
  ShellOperationFailure? failureFor(
    ShellCommandResult result, {
    String operation = 'shell.run',
    String? recoveryHint,
  }) {
    return const ShellFailureClassifier(
      sourceManager: 'UnsupportedShellManager',
    ).classify(result, operation: operation, recoveryHint: recoveryHint);
  }
}
