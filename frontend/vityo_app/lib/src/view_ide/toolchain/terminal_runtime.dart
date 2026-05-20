import 'dart:async';

import 'package:flutter/foundation.dart';

import '../environment/environment.dart';
import '../runtime/runtime.dart';

class TerminalSessionSnapshot {
  const TerminalSessionSnapshot({
    required this.sessionId,
    required this.state,
    this.outputLines = const <String>[],
    this.events = const <TerminalInteractionEvent>[],
    this.lastInput = '',
    this.lastResize,
    this.taskSnapshot,
  });

  final String sessionId;
  final PtySessionState state;
  final List<String> outputLines;
  final List<TerminalInteractionEvent> events;
  final String lastInput;
  final PtyResizeResult? lastResize;
  final RuntimeTaskSnapshot? taskSnapshot;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'state': state.name,
      'outputLines': outputLines,
      'events': events.map((event) => event.toJson()).toList(growable: false),
      if (lastInput.isNotEmpty) 'lastInput': lastInput,
      if (lastResize != null)
        'lastResize': <String, Object?>{
          'status': lastResize!.status.name,
          'rows': lastResize!.rows,
          'cols': lastResize!.cols,
          if (lastResize!.message != null) 'message': lastResize!.message,
        },
      if (taskSnapshot != null) 'task': taskSnapshot!.toJson(),
    };
  }

  List<RuntimeOutputEvent> runtimeOutputEvents({
    String? channelId,
    String label = 'Terminal',
  }) {
    final resolvedChannelId = channelId ?? 'terminal.$sessionId';
    return events
        .map(
          (event) => event.toRuntimeOutputEvent(
            channelId: resolvedChannelId,
            label: label,
          ),
        )
        .toList(growable: false);
  }

  RuntimeOutputPanelSnapshot outputPanelSnapshot({
    String? channelId,
    String label = 'Terminal',
    RuntimeOutputChannelFilterState filter =
        const RuntimeOutputChannelFilterState(),
  }) {
    return RuntimeOutputPanelSnapshot(
      events: runtimeOutputEvents(channelId: channelId, label: label),
      filter: filter,
    );
  }
}

enum TerminalInteractionEventKind { started, output, input, resized, closed }

extension TerminalInteractionEventKindX on TerminalInteractionEventKind {
  String get wireValue => switch (this) {
    TerminalInteractionEventKind.started => 'started',
    TerminalInteractionEventKind.output => 'output',
    TerminalInteractionEventKind.input => 'input',
    TerminalInteractionEventKind.resized => 'resized',
    TerminalInteractionEventKind.closed => 'closed',
  };
}

class TerminalInteractionEvent {
  const TerminalInteractionEvent({
    required this.sequence,
    required this.kind,
    required this.sessionId,
    required this.timestamp,
    this.message = '',
    this.rows,
    this.cols,
    this.exitCode,
  });

  final int sequence;
  final TerminalInteractionEventKind kind;
  final String sessionId;
  final DateTime timestamp;
  final String message;
  final int? rows;
  final int? cols;
  final int? exitCode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sequence': sequence,
      'kind': kind.wireValue,
      'sessionId': sessionId,
      'timestamp': timestamp.toIso8601String(),
      if (message.isNotEmpty) 'message': message,
      if (rows != null) 'rows': rows,
      if (cols != null) 'cols': cols,
      if (exitCode != null) 'exitCode': exitCode,
    };
  }

  RuntimeOutputEvent toRuntimeOutputEvent({
    required String channelId,
    required String label,
  }) {
    return RuntimeOutputEvent(
      channelId: channelId,
      label: label,
      kind: kind == TerminalInteractionEventKind.output
          ? RuntimeOutputChannelKind.stdout
          : RuntimeOutputChannelKind.runtimeEvents,
      message: message.isEmpty ? kind.wireValue : message,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'terminalSessionId': sessionId,
        'terminalEventKind': kind.wireValue,
        'sequence': sequence,
        if (rows != null) 'rows': rows,
        if (cols != null) 'cols': cols,
        if (exitCode != null) 'exitCode': exitCode,
      },
    );
  }
}

class TerminalShellCommandOutputBinding {
  const TerminalShellCommandOutputBinding({
    required this.result,
    required this.channelId,
    required this.label,
    required this.timestamp,
  });

  final ShellCommandResult result;
  final String channelId;
  final String label;
  final DateTime timestamp;

  List<RuntimeOutputEvent> get events {
    return <RuntimeOutputEvent>[
      RuntimeOutputEvent(
        channelId: channelId,
        label: label,
        kind: RuntimeOutputChannelKind.runtimeEvents,
        message: result.message ?? 'Shell command ${result.command} completed.',
        timestamp: timestamp,
        metadata: _metadata('status'),
      ),
      if (result.stdout.isNotEmpty)
        RuntimeOutputEvent(
          channelId: '$channelId.stdout',
          label: '$label stdout',
          kind: RuntimeOutputChannelKind.stdout,
          message: result.stdout,
          timestamp: timestamp,
          metadata: _metadata('stdout'),
        ),
      if (result.stderr.isNotEmpty)
        RuntimeOutputEvent(
          channelId: '$channelId.stderr',
          label: '$label stderr',
          kind: RuntimeOutputChannelKind.stderr,
          message: result.stderr,
          timestamp: timestamp,
          metadata: _metadata('stderr'),
        ),
    ];
  }

  RuntimeOutputPanelSnapshot outputPanelSnapshot({
    RuntimeOutputChannelFilterState filter =
        const RuntimeOutputChannelFilterState(),
  }) {
    return RuntimeOutputPanelSnapshot(events: events, filter: filter);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'channelId': channelId,
      'label': label,
      'status': result.status.name,
      'succeeded': result.succeeded,
      'exitCode': result.exitCode,
      'eventCount': events.length,
      'events': events.map((event) => event.toJson()).toList(growable: false),
    };
  }

  Map<String, Object?> _metadata(String stream) {
    return <String, Object?>{
      'stream': stream,
      'command': result.command,
      'executablePath': result.executablePath,
      'status': result.status.name,
      if (result.exitCode != null) 'exitCode': result.exitCode,
      'durationMs': result.duration.inMilliseconds,
    };
  }
}

class ShellManagerRuntimeOutputExecution {
  const ShellManagerRuntimeOutputExecution({
    required this.result,
    required this.binding,
  });

  final ShellCommandResult result;
  final TerminalShellCommandOutputBinding binding;

  bool get succeeded => result.succeeded;
  int get eventCount => binding.events.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'succeeded': succeeded,
      'eventCount': eventCount,
      'binding': binding.toJson(),
    };
  }
}

class ShellManagerRuntimeOutputAdapter {
  ShellManagerRuntimeOutputAdapter({
    required this.shellManager,
    this.configuration,
    RuntimeTaskClock? clock,
  }) : _clock = clock ?? DateTime.now().toUtc;

  final ShellManager shellManager;
  final ShellConfiguration? configuration;
  final RuntimeTaskClock _clock;

  Future<ShellManagerRuntimeOutputExecution> runAndBind({
    required ShellCommandRequest request,
    required RuntimeOutputLiveBuffer buffer,
    required String channelId,
    required String label,
  }) async {
    final result = await shellManager.run(
      request,
      configuration: configuration,
    );
    final binding = TerminalShellCommandOutputBinding(
      result: result,
      channelId: channelId,
      label: label,
      timestamp: _clock(),
    );
    for (final event in binding.events) {
      buffer.addEvent(event);
    }
    return ShellManagerRuntimeOutputExecution(result: result, binding: binding);
  }
}

class TerminalRuntimeStartResult {
  const TerminalRuntimeStartResult({required this.session, this.taskSnapshot});

  final PtySession session;
  final RuntimeTaskSnapshot? taskSnapshot;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': session.id,
      'state': session.state.name,
      if (taskSnapshot != null) 'task': taskSnapshot!.toJson(),
    };
  }
}

class TerminalInteractionController extends ChangeNotifier {
  TerminalInteractionController({
    required this.runtime,
    RuntimeTaskClock? clock,
    this.runtimeOutputLabel = 'Terminal',
  }) : _clock = clock ?? DateTime.now().toUtc;

  final TerminalRuntime runtime;
  final RuntimeTaskClock _clock;
  final String runtimeOutputLabel;
  final StreamController<RuntimeOutputEvent> _runtimeOutputEvents =
      StreamController<RuntimeOutputEvent>.broadcast(sync: true);

  PtySession? _session;
  StreamSubscription<String>? _outputSubscription;
  List<String> _outputLines = const <String>[];
  List<TerminalInteractionEvent> _events = const <TerminalInteractionEvent>[];
  String _lastInput = '';
  PtyResizeResult? _lastResize;
  RuntimeTaskSnapshot? _taskSnapshot;
  int _eventSequence = 0;

  Stream<RuntimeOutputEvent> get runtimeOutputEvents =>
      _runtimeOutputEvents.stream;

  TerminalSessionSnapshot? get snapshot {
    final session = _session;
    if (session == null) {
      return null;
    }
    return TerminalSessionSnapshot(
      sessionId: session.id,
      state: session.state,
      outputLines: List<String>.unmodifiable(_outputLines),
      events: List<TerminalInteractionEvent>.unmodifiable(_events),
      lastInput: _lastInput,
      lastResize: _lastResize,
      taskSnapshot: _taskSnapshot,
    );
  }

  StreamSubscription<RuntimeOutputEvent> bindRuntimeOutputBuffer(
    RuntimeOutputLiveBuffer buffer,
  ) {
    return buffer.bind(runtimeOutputEvents);
  }

  Future<TerminalSessionSnapshot> start({
    ShellProfileConfiguration? profile,
    String? workingDirectory,
    String? taskId,
    String? taskLabel,
    int rows = 24,
    int cols = 80,
  }) async {
    await _outputSubscription?.cancel();
    _outputLines = const <String>[];
    _events = const <TerminalInteractionEvent>[];
    _lastInput = '';
    _lastResize = null;
    _taskSnapshot = null;
    _eventSequence = 0;
    final startResult = await runtime.startWithLifecycle(
      profile: profile,
      workingDirectory: workingDirectory,
      taskId: taskId,
      taskLabel: taskLabel,
      rows: rows,
      cols: cols,
    );
    final session = startResult.session;
    _taskSnapshot = startResult.taskSnapshot;
    _session = session;
    _recordEvent(
      kind: TerminalInteractionEventKind.started,
      sessionId: session.id,
      rows: rows,
      cols: cols,
    );
    _outputSubscription = session.output.listen((chunk) {
      _outputLines = List<String>.unmodifiable(<String>[
        ..._outputLines,
        chunk,
      ]);
      _recordEvent(
        kind: TerminalInteractionEventKind.output,
        sessionId: session.id,
        message: chunk,
      );
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
    _recordEvent(
      kind: TerminalInteractionEventKind.input,
      sessionId: session.id,
      message: input,
    );
    notifyListeners();
  }

  Future<PtyResizeResult?> resize({
    required int rows,
    required int cols,
  }) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    _lastResize = await session.resize(rows: rows, cols: cols);
    _recordEvent(
      kind: TerminalInteractionEventKind.resized,
      sessionId: session.id,
      rows: rows,
      cols: cols,
      message: _lastResize?.status.name ?? '',
    );
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
    final taskId = _taskSnapshot?.definition.id;
    if (taskId != null) {
      _taskSnapshot = await runtime.completeTask(taskId, exitCode: exitCode);
    }
    _recordEvent(
      kind: TerminalInteractionEventKind.closed,
      sessionId: session.id,
      exitCode: exitCode,
    );
    notifyListeners();
    return exitCode;
  }

  void _recordEvent({
    required TerminalInteractionEventKind kind,
    required String sessionId,
    String message = '',
    int? rows,
    int? cols,
    int? exitCode,
  }) {
    _eventSequence += 1;
    final event = TerminalInteractionEvent(
      sequence: _eventSequence,
      kind: kind,
      sessionId: sessionId,
      timestamp: _clock(),
      message: message,
      rows: rows,
      cols: cols,
      exitCode: exitCode,
    );
    _events = List<TerminalInteractionEvent>.unmodifiable(
      <TerminalInteractionEvent>[..._events, event],
    );
    if (!_runtimeOutputEvents.isClosed) {
      _runtimeOutputEvents.add(
        event.toRuntimeOutputEvent(
          channelId: 'terminal.$sessionId',
          label: runtimeOutputLabel,
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_outputSubscription?.cancel());
    unawaited(_runtimeOutputEvents.close());
    super.dispose();
  }
}

class TerminalRuntime {
  const TerminalRuntime({
    required PtyManager ptyManager,
    required ShellConfiguration shellConfiguration,
    RuntimeTaskLifecycleController? taskLifecycleController,
    RuntimeTaskHistoryStore? taskHistoryStore,
    this.taskHistoryWorkspaceId = 'default',
    this.taskHistoryMaxEntries = 50,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
    String pathSeparator = ':',
  }) : _ptyManager = ptyManager,
       _shellConfiguration = shellConfiguration,
       _taskLifecycleController = taskLifecycleController,
       _taskHistoryStore = taskHistoryStore,
       _environmentResolver = environmentResolver,
       _inheritedEnvironment = inheritedEnvironment,
       _pathSeparator = pathSeparator;

  factory TerminalRuntime.fromPlatformContext({
    required PlatformContextSnapshot platformContext,
    required PtyManager ptyManager,
    required ShellConfiguration shellConfiguration,
    RuntimeTaskLifecycleController? taskLifecycleController,
    RuntimeTaskHistoryStore? taskHistoryStore,
    String taskHistoryWorkspaceId = 'default',
    int taskHistoryMaxEntries = 50,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return TerminalRuntime(
      ptyManager: ptyManager,
      shellConfiguration: shellConfiguration,
      taskLifecycleController: taskLifecycleController,
      taskHistoryStore: taskHistoryStore,
      taskHistoryWorkspaceId: taskHistoryWorkspaceId,
      taskHistoryMaxEntries: taskHistoryMaxEntries,
      environmentResolver: environmentResolver,
      inheritedEnvironment: inheritedEnvironment,
      pathSeparator: pathListSeparatorForPlatformContext(platformContext),
    );
  }

  factory TerminalRuntime.fromPlatformManagers({
    required PlatformManagerBundle platformManagers,
    required ShellConfiguration shellConfiguration,
    RuntimeTaskLifecycleController? taskLifecycleController,
    RuntimeTaskHistoryStore? taskHistoryStore,
    String taskHistoryWorkspaceId = 'default',
    int taskHistoryMaxEntries = 50,
    EnvironmentVariableResolver environmentResolver =
        const EnvironmentVariableResolver(),
    Map<String, String> inheritedEnvironment = const <String, String>{},
  }) {
    return TerminalRuntime.fromPlatformContext(
      platformContext: platformManagers.context,
      ptyManager: platformManagers.pty,
      shellConfiguration: shellConfiguration,
      taskLifecycleController: taskLifecycleController,
      taskHistoryStore: taskHistoryStore,
      taskHistoryWorkspaceId: taskHistoryWorkspaceId,
      taskHistoryMaxEntries: taskHistoryMaxEntries,
      environmentResolver: environmentResolver,
      inheritedEnvironment: inheritedEnvironment,
    );
  }

  final PtyManager _ptyManager;
  final ShellConfiguration _shellConfiguration;
  final RuntimeTaskLifecycleController? _taskLifecycleController;
  final RuntimeTaskHistoryStore? _taskHistoryStore;
  final String taskHistoryWorkspaceId;
  final int taskHistoryMaxEntries;
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

  Future<TerminalRuntimeStartResult> startWithLifecycle({
    ShellProfileConfiguration? profile,
    Iterable<Map<String, String?>> envFileVariables =
        const <Map<String, String?>>[],
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    Map<String, String> environment = const <String, String>{},
    String? workingDirectory,
    String? taskId,
    String? taskLabel,
    int rows = 24,
    int cols = 80,
  }) async {
    final selectedProfile = profile ?? _shellConfiguration.defaultProfile;
    final taskSnapshot = _startTaskSnapshot(
      profile: selectedProfile,
      environment: environment,
      workingDirectory: workingDirectory,
      taskId: taskId,
      taskLabel: taskLabel,
    );
    try {
      final session = await start(
        profile: profile,
        envFileVariables: envFileVariables,
        environmentOverlays: environmentOverlays,
        environment: environment,
        workingDirectory: workingDirectory,
        rows: rows,
        cols: cols,
      );
      return TerminalRuntimeStartResult(
        session: session,
        taskSnapshot: taskSnapshot,
      );
    } catch (error) {
      final failedTaskId = taskSnapshot?.definition.id;
      if (failedTaskId != null) {
        _taskLifecycleController?.fail(
          failedTaskId,
          message: 'Terminal task $failedTaskId failed to start: $error',
          metadata: <String, Object?>{'phase': 'pty-start'},
        );
      }
      rethrow;
    }
  }

  Future<RuntimeTaskSnapshot?> completeTask(
    String taskId, {
    int? exitCode,
  }) async {
    final controller = _taskLifecycleController;
    if (controller == null) {
      return null;
    }
    final completed = controller.complete(
      taskId,
      exitCode: exitCode ?? 0,
      message: 'Terminal task $taskId closed.',
    );
    await _persistTask(completed);
    return completed;
  }

  RuntimeTaskSnapshot? _startTaskSnapshot({
    required ShellProfileConfiguration? profile,
    required Map<String, String> environment,
    required String? workingDirectory,
    required String? taskId,
    required String? taskLabel,
  }) {
    final controller = _taskLifecycleController;
    if (controller == null) {
      return null;
    }
    final id = taskId ?? 'terminal.${profile?.id ?? 'unsupported'}';
    final definition = RuntimeTaskDefinition(
      id: id,
      label: taskLabel ?? 'Terminal ${profile?.id ?? 'unsupported'}',
      kind: RuntimeTaskKind.shell,
      command: profile?.executablePath ?? '',
      arguments: profile?.arguments ?? const <String>[],
      workingDirectory: workingDirectory,
      environment: environment,
      group: 'terminal',
      terminalProfileId: profile?.id,
      metadata: <String, Object?>{
        'source': 'TerminalRuntime',
        'taskHistory': _taskHistoryStore == null ? 'disabled' : 'enabled',
      },
    );
    controller.register(definition);
    if (!definition.runnable) {
      return controller.block(
        id,
        message: 'Terminal task $id has no runnable shell profile.',
        metadata: const <String, Object?>{'phase': 'profile-selection'},
      );
    }
    return controller.start(id, message: 'Terminal task $id started.');
  }

  Future<void> _persistTask(RuntimeTaskSnapshot task) async {
    final store = _taskHistoryStore;
    if (store == null) {
      return;
    }
    await store.appendTask(
      workspaceId: taskHistoryWorkspaceId,
      task: task,
      maxEntries: taskHistoryMaxEntries,
    );
  }
}
