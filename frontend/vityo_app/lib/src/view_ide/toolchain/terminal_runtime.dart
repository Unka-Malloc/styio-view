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

  List<RuntimeOutputProducerEmission> runtimeOutputProducerEmissions({
    String? channelId,
    String label = 'Terminal',
  }) {
    final resolvedChannelId = channelId ?? 'terminal.$sessionId';
    return events
        .map(
          (event) => event.toRuntimeOutputProducerEmission(
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

enum TerminalInteractionEventKind {
  started,
  output,
  input,
  resized,
  signal,
  closed,
}

extension TerminalInteractionEventKindX on TerminalInteractionEventKind {
  String get wireValue => switch (this) {
    TerminalInteractionEventKind.started => 'started',
    TerminalInteractionEventKind.output => 'output',
    TerminalInteractionEventKind.input => 'input',
    TerminalInteractionEventKind.resized => 'resized',
    TerminalInteractionEventKind.signal => 'signal',
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
    this.signal,
    this.exitCode,
  });

  final int sequence;
  final TerminalInteractionEventKind kind;
  final String sessionId;
  final DateTime timestamp;
  final String message;
  final int? rows;
  final int? cols;
  final String? signal;
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
      if (signal != null) 'signal': signal,
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
        if (signal != null) 'signal': signal,
        if (exitCode != null) 'exitCode': exitCode,
      },
    );
  }

  RuntimeOutputProducerEmission toRuntimeOutputProducerEmission({
    required String channelId,
    required String label,
  }) {
    final metadata = <String, Object?>{
      'terminalSessionId': sessionId,
      'terminalEventKind': kind.wireValue,
      'sequence': sequence,
      if (rows != null) 'rows': rows,
      if (cols != null) 'cols': cols,
      if (signal != null) 'signal': signal,
      if (exitCode != null) 'exitCode': exitCode,
    };
    if (kind == TerminalInteractionEventKind.output) {
      return RuntimeOutputProducerEmission.stdout(
        message: message,
        timestamp: timestamp,
        channelId: channelId,
        label: label,
        metadata: metadata,
      );
    }
    return RuntimeOutputProducerEmission.runtimeEvent(
      message: message.isEmpty ? kind.wireValue : message,
      timestamp: timestamp,
      channelId: channelId,
      label: label,
      metadata: metadata,
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
      ..._streamEvents(
        stream: 'stdout',
        kind: RuntimeOutputChannelKind.stdout,
        output: result.stdout,
      ),
      ..._streamEvents(
        stream: 'stderr',
        kind: RuntimeOutputChannelKind.stderr,
        output: result.stderr,
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
      ...result.metadata,
    };
  }

  List<RuntimeOutputEvent> _streamEvents({
    required String stream,
    required RuntimeOutputChannelKind kind,
    required String output,
  }) {
    final chunks = _outputChunks(output);
    return <RuntimeOutputEvent>[
      for (var index = 0; index < chunks.length; index += 1)
        RuntimeOutputEvent(
          channelId: '$channelId.$stream',
          label: '$label $stream',
          kind: kind,
          message: chunks[index],
          timestamp: timestamp,
          metadata: <String, Object?>{
            ..._metadata(stream),
            'chunkIndex': index,
            'chunkCount': chunks.length,
          },
        ),
    ];
  }

  List<String> _outputChunks(String output) {
    if (output.isEmpty) {
      return const <String>[];
    }
    final normalized = output.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.isEmpty ? <String>[output] : lines;
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

enum ShellManagerRuntimeExecutionStatus { executed, blocked, wrongRoute }

extension ShellManagerRuntimeExecutionStatusX
    on ShellManagerRuntimeExecutionStatus {
  String get wireValue => switch (this) {
    ShellManagerRuntimeExecutionStatus.executed => 'executed',
    ShellManagerRuntimeExecutionStatus.blocked => 'blocked',
    ShellManagerRuntimeExecutionStatus.wrongRoute => 'wrong-route',
  };
}

class ShellManagerRuntimeExecutionResult {
  const ShellManagerRuntimeExecutionResult({
    required this.binding,
    required this.status,
    required this.outputEvent,
    this.execution,
  });

  final RuntimeExecutionHandoffBinding binding;
  final ShellManagerRuntimeExecutionStatus status;
  final RuntimeOutputEvent outputEvent;
  final ShellManagerRuntimeOutputExecution? execution;

  bool get executed => status == ShellManagerRuntimeExecutionStatus.executed;
  bool get succeeded => execution?.succeeded ?? false;
  RuntimeProcessHandleIdentity? get processHandle {
    final metadata = execution?.result.metadata ?? const <String, Object?>{};
    return RuntimeProcessHandleIdentity.tryFromMetadata(
      metadata,
      managerId: binding.managerId,
    );
  }

  Map<String, Object?> toJson() {
    final handle = processHandle;
    return <String, Object?>{
      'status': status.wireValue,
      'executed': executed,
      'succeeded': succeeded,
      'binding': binding.toJson(),
      'outputEvent': outputEvent.toJson(),
      if (execution != null) 'execution': execution!.toJson(),
      if (handle != null) 'processHandle': handle.toJson(),
    };
  }
}

class ShellManagerRuntimeExecutionAdapter {
  ShellManagerRuntimeExecutionAdapter({
    required ShellManager shellManager,
    ShellConfiguration? configuration,
    RuntimeTaskClock? clock,
  }) : _clock = clock ?? DateTime.now().toUtc,
       _outputAdapter = ShellManagerRuntimeOutputAdapter(
         shellManager: shellManager,
         configuration: configuration,
         clock: clock,
       );

  final RuntimeTaskClock _clock;
  final ShellManagerRuntimeOutputAdapter _outputAdapter;

  Future<ShellManagerRuntimeExecutionResult> executeHandoff({
    required RuntimeExecutionHandoffBinding binding,
    required RuntimeOutputLiveBuffer buffer,
  }) async {
    if (binding.managerId != 'shell-manager') {
      return _controlResult(
        binding: binding,
        buffer: buffer,
        status: ShellManagerRuntimeExecutionStatus.wrongRoute,
        message:
            'Runtime shell execution ignored non-shell route ${binding.managerId}.',
      );
    }
    if (!binding.ready) {
      return _controlResult(
        binding: binding,
        buffer: buffer,
        status: ShellManagerRuntimeExecutionStatus.blocked,
        message: 'Runtime shell execution blocked before process start.',
      );
    }

    final execution = await _outputAdapter.runAndBind(
      request: ShellCommandRequest(
        command: binding.handoff.command,
        arguments: binding.handoff.arguments,
        environment: binding.handoff.environment,
        workingDirectory: binding.handoff.workingDirectory,
      ),
      buffer: buffer,
      channelId: binding.outputChannel.id,
      label: binding.outputChannel.label,
    );
    final outputEvent = binding.outputEvent(
      message: execution.succeeded
          ? 'Runtime shell handoff ${binding.handoff.taskId} completed.'
          : 'Runtime shell handoff ${binding.handoff.taskId} failed.',
      timestamp: _clock(),
      kind: RuntimeOutputChannelKind.runtimeEvents,
      metadata: <String, Object?>{
        'runtimeShellExecutionStatus':
            ShellManagerRuntimeExecutionStatus.executed.wireValue,
        'succeeded': execution.succeeded,
        'eventCount': execution.eventCount,
        ...execution.result.metadata,
      },
    );
    buffer.addEvent(outputEvent, now: _clock());
    return ShellManagerRuntimeExecutionResult(
      binding: binding,
      status: ShellManagerRuntimeExecutionStatus.executed,
      outputEvent: outputEvent,
      execution: execution,
    );
  }

  ShellManagerRuntimeExecutionResult _controlResult({
    required RuntimeExecutionHandoffBinding binding,
    required RuntimeOutputLiveBuffer buffer,
    required ShellManagerRuntimeExecutionStatus status,
    required String message,
  }) {
    final outputEvent = binding.outputEvent(
      message: message,
      timestamp: _clock(),
      kind: RuntimeOutputChannelKind.runtimeEvents,
      metadata: <String, Object?>{
        'runtimeShellExecutionStatus': status.wireValue,
      },
    );
    buffer.addEvent(outputEvent, now: _clock());
    return ShellManagerRuntimeExecutionResult(
      binding: binding,
      status: status,
      outputEvent: outputEvent,
    );
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

class TerminalRuntimeStartPlan {
  const TerminalRuntimeStartPlan({
    required this.profileId,
    required this.executablePath,
    required this.workingDirectory,
    required this.rows,
    required this.cols,
    required this.ptyPlan,
  });

  final String profileId;
  final String executablePath;
  final String? workingDirectory;
  final int rows;
  final int cols;
  final PtyExecutionPlan ptyPlan;

  bool get supported => ptyPlan.supported;
  String get providerKind => ptyPlan.providerKind.wireValue;
  String get backendExecutablePath => ptyPlan.backendExecutablePath;
  List<String> get backendArguments => ptyPlan.backendArguments;
  String? get unsupportedMessage => ptyPlan.unsupportedMessage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'executablePath': executablePath,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      'rows': rows,
      'cols': cols,
      'supported': supported,
      'providerKind': providerKind,
      'backendExecutablePath': backendExecutablePath,
      'backendArguments': backendArguments,
      if (unsupportedMessage != null) 'unsupportedMessage': unsupportedMessage,
    };
  }
}

class TerminalRuntimeOutputBinding {
  const TerminalRuntimeOutputBinding({this.startPlan, this.sessionSnapshot});

  final TerminalRuntimeStartPlan? startPlan;
  final TerminalSessionSnapshot? sessionSnapshot;

  List<RuntimeOutputEvent> runtimeOutputEvents({
    DateTime? timestamp,
    String channelId = 'terminal.runtime',
    String label = 'Terminal',
  }) {
    final resolvedTimestamp = timestamp ?? DateTime.now().toUtc();
    return <RuntimeOutputEvent>[
      if (startPlan != null)
        RuntimeOutputEvent(
          channelId: channelId,
          label: label,
          kind: RuntimeOutputChannelKind.runtimeEvents,
          message:
              'Terminal start plan ${startPlan!.supported ? 'ready' : 'blocked'} for ${startPlan!.profileId}.',
          timestamp: resolvedTimestamp,
          metadata: <String, Object?>{
            'terminalStartPlan': true,
            'profileId': startPlan!.profileId,
            'executablePath': startPlan!.executablePath,
            'workingDirectory': startPlan!.workingDirectory,
            'rows': startPlan!.rows,
            'cols': startPlan!.cols,
            'supported': startPlan!.supported,
            'providerKind': startPlan!.providerKind,
            'backendExecutablePath': startPlan!.backendExecutablePath,
            'backendArguments': startPlan!.backendArguments,
            if (startPlan!.unsupportedMessage != null)
              'unsupportedMessage': startPlan!.unsupportedMessage,
          },
        ),
      if (sessionSnapshot != null)
        ...sessionSnapshot!.runtimeOutputEvents(
          channelId: channelId,
          label: label,
        ),
    ];
  }

  RuntimeOutputPanelSnapshot outputPanelSnapshot({
    DateTime? timestamp,
    String channelId = 'terminal.runtime',
    String label = 'Terminal',
    RuntimeOutputChannelFilterState filter =
        const RuntimeOutputChannelFilterState(),
  }) {
    return RuntimeOutputPanelSnapshot(
      events: runtimeOutputEvents(
        timestamp: timestamp,
        channelId: channelId,
        label: label,
      ),
      filter: filter,
    );
  }

  Map<String, Object?> toJson() {
    final snapshot = outputPanelSnapshot();
    return <String, Object?>{
      'hasStartPlan': startPlan != null,
      'hasSessionSnapshot': sessionSnapshot != null,
      'outputEventCount': snapshot.events.length,
      if (startPlan != null) 'startPlan': startPlan!.toJson(),
      if (sessionSnapshot != null) 'sessionSnapshot': sessionSnapshot!.toJson(),
      'outputSnapshot': snapshot.toJson(),
    };
  }
}

enum TerminalSessionRecoveryAction {
  none,
  replayStartPlan,
  rebindOutputSubscription,
  closeStaleSession,
  markUnsupported,
}

extension TerminalSessionRecoveryActionX on TerminalSessionRecoveryAction {
  String get wireValue {
    return switch (this) {
      TerminalSessionRecoveryAction.none => 'none',
      TerminalSessionRecoveryAction.replayStartPlan => 'replay-start-plan',
      TerminalSessionRecoveryAction.rebindOutputSubscription =>
        'rebind-output-subscription',
      TerminalSessionRecoveryAction.closeStaleSession => 'close-stale-session',
      TerminalSessionRecoveryAction.markUnsupported => 'mark-unsupported',
    };
  }
}

class TerminalSessionRecoveryPlan {
  const TerminalSessionRecoveryPlan({
    required this.action,
    this.sessionId = '',
    this.profileId = '',
    this.canRetry = false,
    this.requiresUserConfirmation = false,
    this.message = '',
  });

  factory TerminalSessionRecoveryPlan.fromState({
    TerminalRuntimeStartPlan? startPlan,
    TerminalSessionSnapshot? snapshot,
    bool outputSubscriptionActive = true,
  }) {
    if (startPlan != null && !startPlan.supported) {
      return TerminalSessionRecoveryPlan(
        action: TerminalSessionRecoveryAction.markUnsupported,
        profileId: startPlan.profileId,
        message:
            startPlan.unsupportedMessage ??
            'Terminal PTY backend is unsupported.',
      );
    }
    if (snapshot == null) {
      return TerminalSessionRecoveryPlan(
        action: startPlan == null
            ? TerminalSessionRecoveryAction.none
            : TerminalSessionRecoveryAction.replayStartPlan,
        profileId: startPlan?.profileId ?? '',
        canRetry: startPlan != null,
        message: startPlan == null
            ? 'Terminal recovery has no session or start plan.'
            : 'Terminal session can be recovered by replaying the start plan.',
      );
    }
    if (snapshot.state == PtySessionState.running &&
        !outputSubscriptionActive) {
      return TerminalSessionRecoveryPlan(
        action: TerminalSessionRecoveryAction.rebindOutputSubscription,
        sessionId: snapshot.sessionId,
        profileId: startPlan?.profileId ?? '',
        canRetry: true,
        message:
            'Terminal session is running but output subscription is detached.',
      );
    }
    if (snapshot.state == PtySessionState.failed ||
        snapshot.state == PtySessionState.unsupported) {
      return TerminalSessionRecoveryPlan(
        action: TerminalSessionRecoveryAction.replayStartPlan,
        sessionId: snapshot.sessionId,
        profileId: startPlan?.profileId ?? '',
        canRetry: startPlan?.supported ?? false,
        message: 'Terminal session failed and can be restarted if supported.',
      );
    }
    if (snapshot.state == PtySessionState.starting) {
      return TerminalSessionRecoveryPlan(
        action: TerminalSessionRecoveryAction.closeStaleSession,
        sessionId: snapshot.sessionId,
        profileId: startPlan?.profileId ?? '',
        canRetry: true,
        requiresUserConfirmation: true,
        message: 'Terminal session is still starting and may be stale.',
      );
    }
    return TerminalSessionRecoveryPlan(
      action: TerminalSessionRecoveryAction.none,
      sessionId: snapshot.sessionId,
      profileId: startPlan?.profileId ?? '',
      message: 'Terminal session does not need recovery.',
    );
  }

  final TerminalSessionRecoveryAction action;
  final String sessionId;
  final String profileId;
  final bool canRetry;
  final bool requiresUserConfirmation;
  final String message;

  bool get hasRecoveryAction => action != TerminalSessionRecoveryAction.none;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'action': action.wireValue,
      'hasRecoveryAction': hasRecoveryAction,
      'canRetry': canRetry,
      'requiresUserConfirmation': requiresUserConfirmation,
      if (sessionId.isNotEmpty) 'sessionId': sessionId,
      if (profileId.isNotEmpty) 'profileId': profileId,
      if (message.isNotEmpty) 'message': message,
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
  final StreamController<RuntimeOutputProducerEmission>
  _runtimeOutputEmissions =
      StreamController<RuntimeOutputProducerEmission>.broadcast(sync: true);

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
  Stream<RuntimeOutputProducerEmission> get runtimeOutputEmissions =>
      _runtimeOutputEmissions.stream;

  TerminalSessionRecoveryPlan recoveryPlan({
    TerminalRuntimeStartPlan? startPlan,
  }) {
    return TerminalSessionRecoveryPlan.fromState(
      startPlan: startPlan,
      snapshot: snapshot,
      outputSubscriptionActive: _outputSubscription != null,
    );
  }

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

  StreamSubscription<RuntimeOutputProducerEmission>
  bindRuntimeOutputProducerAdapter(
    RuntimeOutputProducerAdapter adapter,
    RuntimeOutputLiveBuffer buffer,
  ) {
    return adapter.bind(runtimeOutputEmissions, buffer);
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

  Future<PtySignalResult?> sendSignal(PtySignal signal) async {
    final session = _session;
    if (session == null) {
      return null;
    }
    final result = await session.sendSignal(signal);
    _recordEvent(
      kind: TerminalInteractionEventKind.signal,
      sessionId: session.id,
      signal: signal.name,
      message: result.message ?? result.status.name,
    );
    notifyListeners();
    return result;
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
    String? signal,
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
      signal: signal,
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
    if (!_runtimeOutputEmissions.isClosed) {
      _runtimeOutputEmissions.add(
        event.toRuntimeOutputProducerEmission(
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
    unawaited(_runtimeOutputEmissions.close());
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

  TerminalRuntimeStartPlan planStart({
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
    final request = _buildPtySessionRequest(
      selectedProfile: selectedProfile,
      envFileVariables: envFileVariables,
      environmentOverlays: environmentOverlays,
      environment: environment,
      workingDirectory: workingDirectory,
      rows: rows,
      cols: cols,
    );
    return TerminalRuntimeStartPlan(
      profileId: selectedProfile?.id ?? 'unconfigured',
      executablePath: request.executablePath,
      workingDirectory: workingDirectory,
      rows: rows,
      cols: cols,
      ptyPlan: PtyAdapter(_ptyManager.facts).plan(request),
    );
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
    return _ptyManager.start(
      _buildPtySessionRequest(
        selectedProfile: selectedProfile,
        envFileVariables: envFileVariables,
        environmentOverlays: environmentOverlays,
        environment: environment,
        workingDirectory: workingDirectory,
        rows: rows,
        cols: cols,
      ),
    );
  }

  PtySessionRequest _buildPtySessionRequest({
    required ShellProfileConfiguration? selectedProfile,
    required Iterable<Map<String, String?>> envFileVariables,
    required Iterable<EnvironmentVariableOverlay> environmentOverlays,
    required Map<String, String> environment,
    required String? workingDirectory,
    required int rows,
    required int cols,
  }) {
    if (selectedProfile == null) {
      return PtySessionRequest(
        executablePath: '',
        workingDirectory: workingDirectory,
        rows: rows,
        cols: cols,
      );
    }
    return PtySessionRequest(
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
