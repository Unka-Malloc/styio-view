import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/process/process_manager.dart';
import 'toolchain_catalog.dart';
import 'toolchain_environment.dart';
import 'toolchain_resolver.dart';

enum ToolchainHealthStatus {
  healthy,
  unresolved,
  probeFailed,
}

class ToolchainHealthReport {
  const ToolchainHealthReport({
    required this.status,
    required this.requirement,
    required this.resolution,
    this.processResult,
    this.message,
  });

  final ToolchainHealthStatus status;
  final ToolchainRequirement requirement;
  final ToolchainResolution resolution;
  final ProcessCommandResult? processResult;
  final String? message;

  bool get healthy => status == ToolchainHealthStatus.healthy;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'requirement': requirement.toJson(),
      'resolution': resolution.toJson(),
      if (processResult != null) 'processResult': processResult!.toJson(),
      if (message != null) 'message': message,
      'healthy': healthy,
    };
  }
}

class ToolchainHealthChecker {
  const ToolchainHealthChecker({
    this.resolver = const ToolchainResolver(),
    this.environmentBuilder = const ToolchainEnvironmentBuilder(),
  });

  final ToolchainResolver resolver;
  final ToolchainEnvironmentBuilder environmentBuilder;

  Future<ToolchainHealthReport> check({
    required ToolchainCatalog catalog,
    required ProcessManager processManager,
    required ToolchainRequirement requirement,
    List<String>? probeArguments,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final resolution = resolver.resolve(catalog, requirement);
    if (!resolution.resolved) {
      return ToolchainHealthReport(
        status: ToolchainHealthStatus.unresolved,
        requirement: requirement,
        resolution: resolution,
        message: resolution.message,
      );
    }

    if (probeArguments == null) {
      return ToolchainHealthReport(
        status: ToolchainHealthStatus.healthy,
        requirement: requirement,
        resolution: resolution,
      );
    }

    final descriptor = resolution.descriptor!;
    final result = await processManager.run(
      ProcessCommandRequest(
        executablePath: descriptor.executablePath,
        arguments: probeArguments,
        environment: environmentBuilder.build(
          overlays: environmentOverlays,
          runtimeOverrides: environment,
        ),
        workingDirectory: workingDirectory,
        timeout: timeout,
      ),
    );

    return ToolchainHealthReport(
      status: result.succeeded
          ? ToolchainHealthStatus.healthy
          : ToolchainHealthStatus.probeFailed,
      requirement: requirement,
      resolution: resolution,
      processResult: result,
      message: result.message,
    );
  }
}
