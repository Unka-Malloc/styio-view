import '../environment/environment.dart';

class ToolchainShellRuntime {
  const ToolchainShellRuntime({
    required this.shellManager,
    required this.configuration,
  });

  final ShellManager shellManager;
  final ShellConfiguration configuration;

  ShellFacts get facts => shellManager.facts;

  ShellCompatibility get compatibility => shellManager.compatibility;

  Future<ShellCommandResult> run(
    String command, {
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
    String? workingDirectory,
    Duration? timeout,
    ShellProfileConfiguration? profile,
    bool? loginShell,
  }) {
    return shellManager.run(
      ShellCommandRequest(
        command: command,
        arguments: arguments,
        environment: environment,
        workingDirectory: workingDirectory,
        timeout: timeout,
        profile: profile,
        loginShell: loginShell,
      ),
      configuration: configuration,
    );
  }
}

Future<ToolchainShellRuntime> createPlatformToolchainShellRuntime({
  ShellProber? prober,
  PlatformContextSnapshot? platformContext,
  ShellConfiguration? configuration,
}) async {
  final manager = await createPlatformShellManager(
    prober: prober,
    platformContext: platformContext,
  );
  return ToolchainShellRuntime(
    shellManager: manager,
    configuration: configuration ?? ShellConfiguration.fromFacts(manager.facts),
  );
}
