import '../../configuration/shell_configuration.dart';
import 'shell_facts.dart';
import 'shell_manager.dart';

class ShellAdapter {
  const ShellAdapter(this.facts);

  final ShellFacts facts;

  ShellCompatibility adapt() {
    return ShellCompatibility(
      targetId: facts.targetId,
      compatibilityTarget: facts.compatibilityTarget,
      supportsPty: facts.supportsPty,
      supportsLoginShell: facts.supportsLoginShell,
      supportsInteractiveShell: facts.supportsInteractiveShell,
      scriptExtension: facts.scriptExtension,
      defaultShell: facts.defaultShell,
    );
  }

  ShellExecutionPlan plan(
    ShellCommandRequest request, {
    ShellConfiguration? configuration,
  }) {
    final compatibility = adapt();
    final effectiveConfiguration =
        configuration ?? ShellConfiguration.fromFacts(facts);
    final profile = request.profile ?? effectiveConfiguration.defaultProfile;
    final shell = profile == null
        ? compatibility.defaultShell
        : ShellExecutableFact(
            path: profile.executablePath,
            family: profile.family,
            isDefault: profile.id == effectiveConfiguration.defaultProfileId,
          );
    if (shell == null) {
      return ShellExecutionPlan.unsupported(
        request: request,
        message: 'No executable shell is available for ${facts.targetId}.',
      );
    }
    final command = _composeCommand(request.command, request.arguments, shell);
    final shellArguments = <String>[
      if (profile != null) ...profile.arguments,
      ..._shellArgumentsFor(
        shell.family,
        command,
        login: request.loginShell ?? effectiveConfiguration.loginShell,
      ),
    ];
    return ShellExecutionPlan(
      request: request,
      executablePath: shell.path,
      arguments: shellArguments,
      environment: <String, String>{
        ...effectiveConfiguration.environmentOverlay,
        if (profile != null) ...profile.environment,
        ...request.environment,
      },
      workingDirectory: request.workingDirectory,
      timeout: request.timeout ?? effectiveConfiguration.timeout,
      family: shell.family,
      supported: true,
    );
  }

  String quoteArgument(String value, ShellFamily family) {
    return switch (family) {
      ShellFamily.bash || ShellFamily.sh || ShellFamily.zsh || ShellFamily.fish =>
        _quotePosix(value),
      ShellFamily.powershell => "'${value.replaceAll("'", "''")}'",
      ShellFamily.cmd => '"${value.replaceAll('"', '\\"')}"',
      ShellFamily.unknown => _quotePosix(value),
    };
  }

  String _composeCommand(
    String command,
    List<String> arguments,
    ShellExecutableFact shell,
  ) {
    if (arguments.isEmpty) {
      return command;
    }
    return <String>[
      command,
      ...arguments.map((argument) => quoteArgument(argument, shell.family)),
    ].join(' ');
  }

  List<String> _shellArgumentsFor(
    ShellFamily family,
    String command, {
    required bool login,
  }) {
    switch (family) {
      case ShellFamily.bash:
      case ShellFamily.sh:
      case ShellFamily.zsh:
      case ShellFamily.fish:
        return <String>[login ? '-lc' : '-c', command];
      case ShellFamily.powershell:
        return <String>['-NoLogo', '-NoProfile', '-Command', command];
      case ShellFamily.cmd:
        return <String>['/C', command];
      case ShellFamily.unknown:
        return <String>['-c', command];
    }
  }

  String _quotePosix(String value) {
    if (value.isEmpty) {
      return "''";
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

class ShellCompatibility {
  const ShellCompatibility({
    required this.targetId,
    required this.compatibilityTarget,
    required this.supportsPty,
    required this.supportsLoginShell,
    required this.supportsInteractiveShell,
    required this.scriptExtension,
    required this.defaultShell,
  });

  final String targetId;
  final String compatibilityTarget;
  final bool supportsPty;
  final bool supportsLoginShell;
  final bool supportsInteractiveShell;
  final String scriptExtension;
  final ShellExecutableFact? defaultShell;

  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}

class ShellExecutionPlan {
  const ShellExecutionPlan({
    required this.request,
    required this.executablePath,
    required this.arguments,
    required this.environment,
    required this.workingDirectory,
    required this.timeout,
    required this.family,
    required this.supported,
    this.unsupportedMessage,
  });

  factory ShellExecutionPlan.unsupported({
    required ShellCommandRequest request,
    required String message,
  }) {
    return ShellExecutionPlan(
      request: request,
      executablePath: '',
      arguments: const <String>[],
      environment: const <String, String>{},
      workingDirectory: request.workingDirectory,
      timeout: request.timeout ?? const Duration(seconds: 30),
      family: ShellFamily.unknown,
      supported: false,
      unsupportedMessage: message,
    );
  }

  final ShellCommandRequest request;
  final String executablePath;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
  final Duration timeout;
  final ShellFamily family;
  final bool supported;
  final String? unsupportedMessage;
}
