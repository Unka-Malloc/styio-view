import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../environment/system_compatibility/process/process_manager.dart';
import 'toolchain_catalog.dart';
import 'toolchain_environment.dart';
import 'toolchain_health_check.dart';
import 'toolchain_resolver.dart';

enum ToolchainRuntimeStatus { succeeded, failed, blocked }

class ToolchainRuntimeResult {
  const ToolchainRuntimeResult({
    required this.status,
    required this.toolchainId,
    required this.stdout,
    required this.stderr,
    this.exitCode,
    this.message,
    this.metadata = const <String, Object?>{},
  });

  final ToolchainRuntimeStatus status;
  final String toolchainId;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final String? message;
  final Map<String, Object?> metadata;

  bool get succeeded => status == ToolchainRuntimeStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'toolchainId': toolchainId,
      'stdout': stdout,
      'stderr': stderr,
      if (exitCode != null) 'exitCode': exitCode,
      if (message != null) 'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'succeeded': succeeded,
    };
  }
}

class ToolchainRuntime {
  const ToolchainRuntime({
    required ToolchainCatalog catalog,
    required ProcessManager processManager,
    ToolchainResolver resolver = const ToolchainResolver(),
    ToolchainEnvironmentBuilder environmentBuilder =
        const ToolchainEnvironmentBuilder(),
  }) : _catalog = catalog,
       _processManager = processManager,
       _resolver = resolver,
       _environmentBuilder = environmentBuilder;

  factory ToolchainRuntime.fromPlatformManagers({
    required ToolchainCatalog catalog,
    required PlatformManagerBundle platformManagers,
    ToolchainResolver resolver = const ToolchainResolver(),
    ToolchainEnvironmentBuilder? environmentBuilder,
  }) {
    return ToolchainRuntime(
      catalog: catalog,
      processManager: platformManagers.process,
      resolver: resolver,
      environmentBuilder:
          environmentBuilder ??
          ToolchainEnvironmentBuilder.fromPlatformContext(
            platformManagers.context,
          ),
    );
  }

  final ToolchainCatalog _catalog;
  final ProcessManager _processManager;
  final ToolchainResolver _resolver;
  final ToolchainEnvironmentBuilder _environmentBuilder;

  Future<ToolchainRuntimeResult> run({
    required ToolchainKind kind,
    ToolchainRequirement? requirement,
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
    String? standardInput,
  }) async {
    final resolution = _resolver.resolve(
      _catalog,
      requirement ?? ToolchainRequirement(kind: kind),
    );
    final descriptor = resolution.descriptor;
    if (!resolution.resolved || descriptor == null) {
      return ToolchainRuntimeResult(
        status: ToolchainRuntimeStatus.blocked,
        toolchainId: '',
        stdout: '',
        stderr: '',
        message: resolution.message ?? 'No active toolchain is selected.',
      );
    }
    final result = await _processManager.run(
      ProcessCommandRequest(
        executablePath: descriptor.executablePath,
        arguments: arguments,
        environment: _environmentBuilder.build(
          overlays: environmentOverlays,
          runtimeOverrides: environment,
        ),
        workingDirectory: workingDirectory,
        timeout: timeout,
        standardInput: standardInput,
      ),
    );
    return ToolchainRuntimeResult(
      status: result.succeeded
          ? ToolchainRuntimeStatus.succeeded
          : ToolchainRuntimeStatus.failed,
      toolchainId: descriptor.id,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      message: result.message,
      metadata: result.metadata,
    );
  }

  Future<ToolchainHealthReport> checkHealth({
    required ToolchainKind kind,
    ToolchainRequirement? requirement,
    List<String>? probeArguments,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) {
    return ToolchainHealthChecker(
      resolver: _resolver,
      environmentBuilder: _environmentBuilder,
    ).check(
      catalog: _catalog,
      processManager: _processManager,
      requirement: requirement ?? ToolchainRequirement(kind: kind),
      probeArguments: probeArguments,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }
}
