import '../environment/environment.dart';

class TerminalRuntime {
  const TerminalRuntime({
    required PtyManager ptyManager,
    required ShellConfiguration shellConfiguration,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
    String pathSeparator = ':',
  }) : _ptyManager = ptyManager,
       _shellConfiguration = shellConfiguration,
       _environmentResolver = environmentResolver,
       _inheritedEnvironment = inheritedEnvironment,
       _pathSeparator = pathSeparator;

  factory TerminalRuntime.fromPlatformContext({
    required PlatformContextSnapshot platformContext,
    required PtyManager ptyManager,
    required ShellConfiguration shellConfiguration,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return TerminalRuntime(
      ptyManager: ptyManager,
      shellConfiguration: shellConfiguration,
      environmentResolver: environmentResolver,
      inheritedEnvironment: inheritedEnvironment,
      pathSeparator: pathListSeparatorForPlatformContext(platformContext),
    );
  }

  factory TerminalRuntime.fromPlatformManagers({
    required PlatformManagerBundle platformManagers,
    required ShellConfiguration shellConfiguration,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return TerminalRuntime.fromPlatformContext(
      platformContext: platformManagers.context,
      ptyManager: platformManagers.pty,
      shellConfiguration: shellConfiguration,
      environmentResolver: environmentResolver,
      inheritedEnvironment: inheritedEnvironment,
    );
  }

  final PtyManager _ptyManager;
  final ShellConfiguration _shellConfiguration;
  final EnvironmentVariableResolver _environmentResolver;
  final Map<String, String> _inheritedEnvironment;
  final String _pathSeparator;

  static String pathListSeparatorForPlatformContext(
    PlatformContextSnapshot context,
  ) {
    return context.environmentPathListSeparator;
  }

  Future<PtySession> start({
    ShellProfileConfiguration? profile,
    Iterable<Map<String, String?>> envFileVariables =
        const <Map<String, String?>>[],
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    Map<String, String> environment = const <String, String>{},
    String? workingDirectory,
    int rows = 24,
    int cols = 80,
  }) {
    final selectedProfile = profile ?? _shellConfiguration.defaultProfile;
    if (selectedProfile == null) {
      return _ptyManager.start(
        PtySessionRequest(
          executablePath: '',
          workingDirectory: workingDirectory,
          rows: rows,
          cols: cols,
        ),
      );
    }
    return _ptyManager.start(
      PtySessionRequest(
        executablePath: selectedProfile.executablePath,
        arguments: selectedProfile.arguments,
        environment: _environmentResolver.resolve(
          inherited: _inheritedEnvironment,
          envFileVariables: envFileVariables,
          overlays: <EnvironmentVariableOverlay>[
            EnvironmentVariableOverlay(
              id: 'shell-configuration',
              scope: EnvironmentVariableOverlayScope.profile,
              target: 'terminal',
              variables: _shellConfiguration.environmentOverlay,
            ),
            ...environmentOverlays,
            EnvironmentVariableOverlay(
              id: selectedProfile.id,
              scope: EnvironmentVariableOverlayScope.profile,
              target: 'terminal',
              variables: selectedProfile.environment,
            ),
          ],
          runtimeOverrides: environment,
          pathSeparator: _pathSeparator,
        ),
        workingDirectory: workingDirectory,
        rows: rows,
        cols: cols,
      ),
    );
  }
}
