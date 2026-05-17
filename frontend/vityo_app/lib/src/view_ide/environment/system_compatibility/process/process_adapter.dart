import 'process_facts.dart';
import 'process_manager.dart';

class ProcessAdapter {
  const ProcessAdapter(this.facts);
  final ProcessFacts facts;

  ProcessCompatibility adapt() => ProcessCompatibility(
    targetId: facts.targetId,
    compatibilityTarget: facts.compatibilityTarget,
    supportsSpawn: facts.supportsSpawn,
    supportsSignals: facts.supportsSignals,
    supportsProcessGroups: facts.supportsProcessGroups,
    supportsEnvironmentOverlay: facts.supportsEnvironmentOverlay,
    supportsWorkingDirectory: facts.supportsWorkingDirectory,
  );

  ProcessExecutionPlan plan(ProcessCommandRequest request) {
    final compatibility = adapt();
    if (!compatibility.supportsSpawn) {
      return ProcessExecutionPlan.unsupported(request, 'Process spawning is not supported.');
    }
    return ProcessExecutionPlan(
      request: request,
      executablePath: request.executablePath,
      arguments: request.arguments,
      environment: compatibility.supportsEnvironmentOverlay ? request.environment : const <String, String>{},
      workingDirectory: compatibility.supportsWorkingDirectory ? request.workingDirectory : null,
      timeout: request.timeout ?? const Duration(seconds: 30),
      standardInput: request.standardInput,
      supported: true,
    );
  }
}

class ProcessCompatibility {
  const ProcessCompatibility({
    required this.targetId,
    required this.compatibilityTarget,
    required this.supportsSpawn,
    required this.supportsSignals,
    required this.supportsProcessGroups,
    required this.supportsEnvironmentOverlay,
    required this.supportsWorkingDirectory,
  });

  final String targetId;
  final String compatibilityTarget;
  final bool supportsSpawn;
  final bool supportsSignals;
  final bool supportsProcessGroups;
  final bool supportsEnvironmentOverlay;
  final bool supportsWorkingDirectory;
  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}

class ProcessExecutionPlan {
  const ProcessExecutionPlan({
    required this.request,
    required this.executablePath,
    required this.arguments,
    required this.environment,
    required this.workingDirectory,
    required this.timeout,
    required this.standardInput,
    required this.supported,
    this.unsupportedMessage,
  });

  factory ProcessExecutionPlan.unsupported(ProcessCommandRequest request, String message) => ProcessExecutionPlan(
    request: request,
    executablePath: '',
    arguments: const <String>[],
    environment: const <String, String>{},
    workingDirectory: null,
    timeout: request.timeout ?? const Duration(seconds: 30),
    standardInput: null,
    supported: false,
    unsupportedMessage: message,
  );

  final ProcessCommandRequest request;
  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration timeout;
  final String? standardInput;
  final bool supported;
  final String? unsupportedMessage;
}
