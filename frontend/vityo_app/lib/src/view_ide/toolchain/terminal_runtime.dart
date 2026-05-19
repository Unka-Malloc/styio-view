import 'dart:async';

import 'package:flutter/foundation.dart';

import '../environment/environment.dart';

class TerminalSessionSnapshot {
  const TerminalSessionSnapshot({
    required this.sessionId,
    required this.state,
    this.outputLines = const <String>[],
    this.lastInput = '',
    this.lastResize,
  });

  final String sessionId;
  final PtySessionState state;
  final List<String> outputLines;
  final String lastInput;
  final PtyResizeResult? lastResize;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'state': state.name,
      'outputLines': outputLines,
      if (lastInput.isNotEmpty) 'lastInput': lastInput,
      if (lastResize != null)
        'lastResize': <String, Object?>{
          'status': lastResize!.status.name,
          'rows': lastResize!.rows,
          'cols': lastResize!.cols,
          if (lastResize!.message != null) 'message': lastResize!.message,
        },
    };
  }
}

class TerminalInteractionController extends ChangeNotifier {
  TerminalInteractionController({required this.runtime});

  final TerminalRuntime runtime;

  PtySession? _session;
  StreamSubscription<String>? _outputSubscription;
  List<String> _outputLines = const <String>[];
  String _lastInput = '';
  PtyResizeResult? _lastResize;

  TerminalSessionSnapshot? get snapshot {
    final session = _session;
    if (session == null) {
      return null;
    }
    return TerminalSessionSnapshot(
      sessionId: session.id,
      state: session.state,
      outputLines: List<String>.unmodifiable(_outputLines),
      lastInput: _lastInput,
      lastResize: _lastResize,
    );
  }

  Future<TerminalSessionSnapshot> start({
    ShellProfileConfiguration? profile,
    String? workingDirectory,
    int rows = 24,
    int cols = 80,
  }) async {
    await _outputSubscription?.cancel();
    _outputLines = const <String>[];
    _lastInput = '';
    _lastResize = null;
    final session = await runtime.start(
      profile: profile,
      workingDirectory: workingDirectory,
      rows: rows,
      cols: cols,
    );
    _session = session;
    _outputSubscription = session.output.listen((chunk) {
      _outputLines = List<String>.unmodifiable(<String>[
        ..._outputLines,
        chunk,
      ]);
      notifyListeners();
    });
    notifyListeners();
    return snapshot!;
  }

  Future<void> sendInput(String input) async {
    final session = _session;
    if (session == null || input.isEmpty) {
      return;
    }
    _lastInput = input;
    await session.write(input);
    notifyListeners();
  }

  Future<PtyResizeResult?> resize({required int rows, required int cols}) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    _lastResize = await session.resize(rows: rows, cols: cols);
    notifyListeners();
    return _lastResize;
  }

  Future<int?> close({bool force = false}) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    final exitCode = await session.close(force: force);
    notifyListeners();
    return exitCode;
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    super.dispose();
  }
}

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
