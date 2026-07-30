import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../debugger/debug_launch_contract.dart';
import '../../debugger/debug_launch_telemetry_store.dart';
import '../../debugger/debug_runtime_task_history.dart';
import '../../runtime/runtime_task_history_store.dart';
import '../../runtime/runtime_output_channels.dart';
import '../../toolchain/toolchain_catalog.dart';
import '../../toolchain/toolchain_manager.dart';
import '../../debugger/debug_adapter_protocol.dart';
import '../../debugger/debug_adapter_launcher.dart';
import '../../debugger/debug_adapter_session.dart';

enum DebugSessionStatus {
  idle,
  blocked,
  configured,
  launching,
  running,
  paused,
  stopped,
}

class DebugBreakpoint {
  const DebugBreakpoint({
    required this.filePath,
    required this.line,
    this.enabled = true,
  });

  final String filePath;
  final int line;
  final bool enabled;

  String get key => '$filePath:$line';
}

class DebugStackFrame {
  const DebugStackFrame({
    required this.id,
    required this.name,
    required this.filePath,
    required this.line,
    required this.column,
  });

  final String id;
  final String name;
  final String filePath;
  final int line;
  final int column;
}

class DebugThread {
  const DebugThread({required this.id, required this.name});

  final String id;
  final String name;
}

class DebugVariable {
  const DebugVariable({required this.name, required this.value, this.type});

  final String name;
  final String value;
  final String? type;
}

class DebugSessionSnapshot {
  const DebugSessionSnapshot({
    required this.status,
    required this.message,
    this.debuggerId,
    this.debuggerLabel,
    this.breakpoints = const <DebugBreakpoint>[],
    this.threads = const <DebugThread>[],
    this.stackFrames = const <DebugStackFrame>[],
    this.variables = const <DebugVariable>[],
    this.launchConfiguration,
    this.adapterSessionStatus,
    this.adapterPendingRequestCount = 0,
    this.adapterEventCount = 0,
  });

  final DebugSessionStatus status;
  final String message;
  final String? debuggerId;
  final String? debuggerLabel;
  final List<DebugBreakpoint> breakpoints;
  final List<DebugThread> threads;
  final List<DebugStackFrame> stackFrames;
  final List<DebugVariable> variables;
  final DebugLaunchConfiguration? launchConfiguration;
  final String? adapterSessionStatus;
  final int adapterPendingRequestCount;
  final int adapterEventCount;

  bool get hasConfiguredDebugger => debuggerId != null;
}

class DebugCommandResult {
  const DebugCommandResult({required this.applied, required this.message});

  final bool applied;
  final String message;
}

/// Owns debugger presentation state independently from shell composition.
final class DebugController extends ChangeNotifier {
  DebugController();

  DebugController.configured({
    required ToolchainManager? toolchainManager,
    required String Function() workspaceRoot,
    required DapDebugAdapterLauncher? launcher,
    required RuntimeOutputLiveBuffer runtimeOutputBuffer,
    required DebugRuntimeTaskHistoryBinder runtimeTaskHistoryBinder,
    required RuntimeTaskHistoryStore? runtimeTaskHistoryStore,
    required String runtimeTaskHistoryWorkspaceId,
    required int runtimeTaskHistoryMaxEntries,
    required void Function(String message) log,
  }) : _configuredToolchainManager = toolchainManager,
       _configuredWorkspaceRoot = workspaceRoot,
       _configuredLauncher = launcher,
       _configuredRuntimeOutputBuffer = runtimeOutputBuffer,
       _configuredRuntimeTaskHistoryBinder = runtimeTaskHistoryBinder,
       _configuredRuntimeTaskHistoryStore = runtimeTaskHistoryStore,
       _configuredRuntimeTaskHistoryWorkspaceId = runtimeTaskHistoryWorkspaceId,
       _configuredRuntimeTaskHistoryMaxEntries = runtimeTaskHistoryMaxEntries,
       _configuredLog = log;

  ToolchainManager? _configuredToolchainManager;
  String Function()? _configuredWorkspaceRoot;
  DapDebugAdapterLauncher? _configuredLauncher;
  RuntimeOutputLiveBuffer? _configuredRuntimeOutputBuffer;
  DebugRuntimeTaskHistoryBinder? _configuredRuntimeTaskHistoryBinder;
  RuntimeTaskHistoryStore? _configuredRuntimeTaskHistoryStore;
  String? _configuredRuntimeTaskHistoryWorkspaceId;
  int? _configuredRuntimeTaskHistoryMaxEntries;
  void Function(String message)? _configuredLog;

  final List<DebugBreakpoint> _breakpoints = <DebugBreakpoint>[];
  DebugSessionSnapshot _session = const DebugSessionSnapshot(
    status: DebugSessionStatus.idle,
    message: 'No debug session has been started.',
  );
  DebugRuntimeExecutionResult? _lastRuntimeExecutionResult;
  DapDebugSessionHandle? _sessionHandle;
  StreamSubscription<DapSessionSnapshot>? _sessionSubscription;
  bool _inspectionRequestInFlight = false;
  Future<void> _runtimeTaskHistoryAppendQueue = Future<void>.value();

  DebugSessionSnapshot get session => _session;
  List<DebugBreakpoint> get breakpoints =>
      List<DebugBreakpoint>.unmodifiable(_breakpoints);
  DebugRuntimeExecutionResult? get lastRuntimeExecutionResult =>
      _lastRuntimeExecutionResult;
  DapDebugSessionHandle? get sessionHandle => _sessionHandle;

  DebugCommandResult toggleBreakpointAt({
    required String filePath,
    required int line,
  }) {
    final breakpoint = DebugBreakpoint(filePath: filePath, line: line);
    final added = toggleBreakpoint(breakpoint);
    final message =
        '${added ? 'Added' : 'Removed'} breakpoint at ${breakpoint.filePath}:${breakpoint.line + 1}.';
    _configuredLog?.call(message);
    return DebugCommandResult(applied: true, message: message);
  }

  Future<DebugCommandResult> startConfiguredSession() async {
    final workspaceRoot = _configuredWorkspaceRoot;
    final runtimeOutputBuffer = _configuredRuntimeOutputBuffer;
    if (workspaceRoot == null || runtimeOutputBuffer == null) {
      final result = _applyCommandSnapshot(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Start Debugging blocked: debug runtime is not configured.',
        ),
      );
      _configuredLog?.call(result.message);
      return result;
    }
    final result = await startSession(
      toolchainManager: _configuredToolchainManager,
      workspaceRoot: workspaceRoot(),
      launcher: _configuredLauncher,
      runtimeOutputBuffer: runtimeOutputBuffer,
      onSnapshot: _handleConfiguredDapSnapshot,
    );
    _configuredLog?.call(result.message);
    return result;
  }

  Future<DebugCommandResult> stopConfiguredSession() async {
    final result = await stopSession();
    _configuredLog?.call(result.message);
    return result;
  }

  Future<DebugCommandResult> continueConfiguredSession() async {
    final result = await continueSession();
    _configuredLog?.call(result.message);
    return result;
  }

  Future<DebugCommandResult> stepOverConfiguredSession() async {
    final result = await stepOverSession();
    _configuredLog?.call(result.message);
    return result;
  }

  Future<DebugCommandResult> selectConfiguredStackFrame(String frameId) async {
    final result = await selectStackFrame(frameId);
    _configuredLog?.call(result.message);
    return result;
  }

  Future<DebugCommandResult> selectConfiguredThread(String threadId) async {
    final result = await selectThread(threadId);
    _configuredLog?.call(result.message);
    return result;
  }

  bool refreshConfiguredSession() {
    if (refreshAttachedSession()) {
      return true;
    }
    _configuredLog?.call(
      'Debug adapter refresh skipped: no DAP session is active.',
    );
    notifyListeners();
    return false;
  }

  Future<void> attachSession(
    DapDebugSessionHandle handle, {
    required void Function(DapSessionSnapshot snapshot) onSnapshot,
  }) async {
    final previousHandle = _sessionHandle;
    await _sessionSubscription?.cancel();
    _sessionHandle = handle;
    _sessionSubscription = handle.snapshotEvents.listen(onSnapshot);
    if (previousHandle != null && !identical(previousHandle, handle)) {
      unawaited(previousHandle.close());
    }
  }

  Future<DapDebugSessionHandle?> detachSession() async {
    final handle = _sessionHandle;
    _sessionHandle = null;
    _inspectionRequestInFlight = false;
    final subscription = _sessionSubscription;
    _sessionSubscription = null;
    await subscription?.cancel();
    return handle;
  }

  DapDebugSessionHandle? detachTerminatedSession() {
    final handle = _sessionHandle;
    _sessionHandle = null;
    _inspectionRequestInFlight = false;
    final subscription = _sessionSubscription;
    _sessionSubscription = null;
    unawaited(subscription?.cancel());
    return handle;
  }

  bool refreshAttachedSession() {
    final handle = _sessionHandle;
    if (handle == null) {
      return false;
    }
    final snapshot = handle.snapshot;
    syncFromDapSnapshot(
      snapshot,
      message: 'Debug adapter session refreshed: ${snapshot.status.name}.',
    );
    return true;
  }

  void requestPausedInspection(
    DapSessionSnapshot snapshot, {
    required void Function(String message) onError,
  }) {
    if (_inspectionRequestInFlight) {
      return;
    }
    final handle = _sessionHandle;
    if (handle == null) {
      return;
    }
    final request = nextInspectionRequest(
      snapshot,
      reserveSeq: handle.bridge.session.reserveSeq,
    );
    if (request == null) {
      return;
    }
    _inspectionRequestInFlight = true;
    unawaited(
      (() async {
        try {
          await handle.sendRequest(request);
        } on Object catch (error) {
          onError('DAP inspection request failed: $error');
        } finally {
          _inspectionRequestInFlight = false;
        }
      })(),
    );
  }

  void _handleConfiguredDapSnapshot(DapSessionSnapshot snapshot) {
    syncFromDapSnapshot(
      snapshot,
      message: 'Debug adapter session updated: ${snapshot.status.name}.',
    );
    final binder = _configuredRuntimeTaskHistoryBinder;
    final workspaceId = _configuredRuntimeTaskHistoryWorkspaceId;
    final maxEntries = _configuredRuntimeTaskHistoryMaxEntries;
    if (binder != null && workspaceId != null && maxEntries != null) {
      queueRuntimeTaskHistoryAppend(
        snapshot,
        binder: binder,
        store: _configuredRuntimeTaskHistoryStore,
        workspaceId: workspaceId,
        maxEntries: maxEntries,
      );
    }
    if (snapshot.status == DapSessionStatus.terminated ||
        snapshot.status == DapSessionStatus.failed) {
      final handle = detachTerminatedSession();
      if (handle != null) {
        unawaited(handle.close());
      }
      return;
    }
    requestPausedInspection(
      snapshot,
      onError: (message) {
        _configuredLog?.call(message);
        notifyListeners();
      },
    );
  }

  void queueRuntimeTaskHistoryAppend(
    DapSessionSnapshot snapshot, {
    required DebugRuntimeTaskHistoryBinder binder,
    required RuntimeTaskHistoryStore? store,
    required String workspaceId,
    required int maxEntries,
  }) {
    final launch = _session.launchConfiguration;
    if (store == null || launch == null) {
      return;
    }
    _runtimeTaskHistoryAppendQueue = _runtimeTaskHistoryAppendQueue.then((
      _,
    ) async {
      try {
        await binder.appendSnapshot(
          store: store,
          workspaceId: workspaceId,
          launch: launch,
          adapterSnapshot: snapshot,
          taskId: 'debug.${launch.debuggerId}',
          maxEntries: maxEntries,
        );
      } on Object {
        // Persistence failure must not interrupt the live debug session.
      }
    });
    unawaited(_runtimeTaskHistoryAppendQueue);
  }

  bool toggleBreakpoint(DebugBreakpoint breakpoint) {
    final existingIndex = _breakpoints.indexWhere(
      (candidate) => candidate.key == breakpoint.key,
    );
    final added = existingIndex < 0;
    if (added) {
      _breakpoints.add(breakpoint);
    } else {
      _breakpoints.removeAt(existingIndex);
    }
    refreshSessionBreakpoints();
    notifyListeners();
    return added;
  }

  void replaceSession(DebugSessionSnapshot snapshot) {
    _session = DebugSessionSnapshot(
      status: snapshot.status,
      message: snapshot.message,
      debuggerId: snapshot.debuggerId,
      debuggerLabel: snapshot.debuggerLabel,
      breakpoints: List<DebugBreakpoint>.unmodifiable(snapshot.breakpoints),
      threads: List<DebugThread>.unmodifiable(snapshot.threads),
      stackFrames: List<DebugStackFrame>.unmodifiable(snapshot.stackFrames),
      variables: List<DebugVariable>.unmodifiable(snapshot.variables),
      launchConfiguration: snapshot.launchConfiguration,
      adapterSessionStatus: snapshot.adapterSessionStatus,
      adapterPendingRequestCount: snapshot.adapterPendingRequestCount,
      adapterEventCount: snapshot.adapterEventCount,
    );
    notifyListeners();
  }

  void refreshSessionBreakpoints() {
    _session = DebugSessionSnapshot(
      status: _session.status,
      message: _session.message,
      debuggerId: _session.debuggerId,
      debuggerLabel: _session.debuggerLabel,
      breakpoints: breakpoints,
      threads: _session.threads,
      stackFrames: _session.stackFrames,
      variables: _session.variables,
      launchConfiguration: _session.launchConfiguration,
      adapterSessionStatus: _session.adapterSessionStatus,
      adapterPendingRequestCount: _session.adapterPendingRequestCount,
      adapterEventCount: _session.adapterEventCount,
    );
  }

  DapRequest? nextInspectionRequest(
    DapSessionSnapshot snapshot, {
    required int Function() reserveSeq,
  }) {
    if (snapshot.status != DapSessionStatus.paused) {
      return null;
    }
    const requestFactory = DapProtocolRequestFactory();
    if (snapshot.stackFrames.isEmpty) {
      final threadId =
          snapshot.activeThreadId ??
          _firstInspectableThreadId(snapshot.threads);
      if (threadId == null) {
        if (_hasPendingDapCommand(snapshot, 'threads')) {
          return null;
        }
        return requestFactory.threads(seq: reserveSeq());
      }
      if (_hasPendingDapCommand(snapshot, 'stackTrace')) {
        return null;
      }
      return requestFactory.stackTrace(seq: reserveSeq(), threadId: threadId);
    }
    if (snapshot.scopes.isEmpty) {
      if (_hasPendingDapCommand(snapshot, 'scopes')) {
        return null;
      }
      return requestFactory.scopes(
        seq: reserveSeq(),
        frameId: snapshot.stackFrames.first.id,
      );
    }
    if (snapshot.variables.isEmpty) {
      if (_hasPendingDapCommand(snapshot, 'variables')) {
        return null;
      }
      final variablesReference = _firstScopeVariablesReference(snapshot.scopes);
      if (variablesReference == null) {
        return null;
      }
      return requestFactory.variables(
        seq: reserveSeq(),
        variablesReference: variablesReference,
      );
    }
    return null;
  }

  void syncFromDapSnapshot(
    DapSessionSnapshot snapshot, {
    required String message,
  }) {
    replaceSession(
      DebugSessionSnapshot(
        status: statusFromDapSession(snapshot.status),
        message: message,
        debuggerId: _session.debuggerId,
        debuggerLabel: _session.debuggerLabel,
        breakpoints: breakpoints,
        threads: snapshot.threads
            .map((thread) => DebugThread(id: '${thread.id}', name: thread.name))
            .toList(growable: false),
        stackFrames: snapshot.stackFrames
            .map(
              (frame) => DebugStackFrame(
                id: '${frame.id}',
                name: frame.name,
                filePath: frame.sourcePath,
                line: frame.line,
                column: frame.column,
              ),
            )
            .toList(growable: false),
        variables: snapshot.variables
            .map(
              (variable) => DebugVariable(
                name: variable.name,
                value: variable.value,
                type: variable.type,
              ),
            )
            .toList(growable: false),
        launchConfiguration: _session.launchConfiguration,
        adapterSessionStatus: snapshot.status.name,
        adapterPendingRequestCount: snapshot.pendingRequests.length,
        adapterEventCount: snapshot.events.length,
      ),
    );
  }

  DebugSessionStatus statusFromDapSession(DapSessionStatus status) {
    return switch (status) {
      DapSessionStatus.idle => DebugSessionStatus.configured,
      DapSessionStatus.initializing ||
      DapSessionStatus.launching => DebugSessionStatus.launching,
      DapSessionStatus.running => DebugSessionStatus.running,
      DapSessionStatus.paused => DebugSessionStatus.paused,
      DapSessionStatus.terminated => DebugSessionStatus.stopped,
      DapSessionStatus.failed => DebugSessionStatus.blocked,
    };
  }

  Future<DebugCommandResult> continueSession() async {
    final sessionHandle = _sessionHandle;
    if (_session.status != DebugSessionStatus.paused) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Continue Debugging blocked: no paused debug session.',
          breakpoints: breakpoints,
        ),
      );
    }
    if (sessionHandle != null) {
      final adapterSnapshot = sessionHandle.snapshot;
      final threadId = adapterSnapshot.activeThreadId;
      if (threadId == null) {
        return _applyCommandSnapshot(
          DebugSessionSnapshot(
            status: DebugSessionStatus.blocked,
            message:
                'Continue Debugging blocked: DAP stopped event did not provide a threadId.',
            breakpoints: breakpoints,
            launchConfiguration: _session.launchConfiguration,
            adapterSessionStatus: adapterSnapshot.status.name,
            adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
            adapterEventCount: adapterSnapshot.events.length,
          ),
        );
      }
      await sessionHandle.sendRequest(
        const DapProtocolRequestFactory().continueThread(
          seq: sessionHandle.bridge.session.reserveSeq(),
          threadId: threadId,
        ),
      );
      final refreshed = sessionHandle.snapshot;
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.running,
          message: 'Continue Debugging request sent to DAP adapter.',
          debuggerId: _session.debuggerId,
          debuggerLabel: _session.debuggerLabel,
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: refreshed.status.name,
          adapterPendingRequestCount: refreshed.pendingRequests.length,
          adapterEventCount: refreshed.events.length,
        ),
      );
    }
    return _applyCommandSnapshot(
      DebugSessionSnapshot(
        status: DebugSessionStatus.running,
        message: 'Debug session continued.',
        debuggerId: _session.debuggerId,
        debuggerLabel: _session.debuggerLabel,
        breakpoints: breakpoints,
        threads: _session.threads,
        stackFrames: _session.stackFrames,
        variables: _session.variables,
        launchConfiguration: _session.launchConfiguration,
        adapterSessionStatus: _session.adapterSessionStatus,
        adapterPendingRequestCount: _session.adapterPendingRequestCount,
        adapterEventCount: _session.adapterEventCount,
      ),
    );
  }

  Future<DebugCommandResult> stopSession() async {
    final handle = await detachSession();
    if (handle != null) {
      await handle.sendRequest(
        const DapProtocolRequestFactory().disconnect(
          seq: handle.bridge.session.reserveSeq(),
        ),
      );
      final adapterSnapshot = handle.snapshot;
      unawaited(handle.close());
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.stopped,
          message: 'Stop Debugging request sent to DAP adapter.',
          breakpoints: breakpoints,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    }
    return _applyCommandSnapshot(
      DebugSessionSnapshot(
        status: DebugSessionStatus.stopped,
        message: 'Debug session stopped.',
        breakpoints: breakpoints,
      ),
    );
  }

  Future<DebugCommandResult> startSession({
    required ToolchainManager? toolchainManager,
    required String workspaceRoot,
    required DapDebugAdapterLauncher? launcher,
    required RuntimeOutputLiveBuffer runtimeOutputBuffer,
    required void Function(DapSessionSnapshot snapshot) onSnapshot,
  }) async {
    if (toolchainManager == null) {
      return _applyCommandSnapshot(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Start Debugging blocked: no toolchain manager is available.',
        ),
      );
    }
    final catalog = await toolchainManager.loadCatalog();
    final activeDebugger =
        catalog.active(ToolchainKind.debugger) ??
        (() {
          final debuggers = catalog.list(kind: ToolchainKind.debugger);
          return debuggers.isEmpty ? null : debuggers.first;
        })();
    if (activeDebugger == null) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Start Debugging blocked: no native debugger is registered.',
          breakpoints: breakpoints,
        ),
      );
    }
    final launchConfiguration =
        DebugLaunchConfiguration.fromToolchainDescriptor(
          debugger: activeDebugger,
          workspaceRoot: workspaceRoot,
          breakpoints: breakpoints
              .map(
                (breakpoint) => DebugLaunchBreakpoint(
                  filePath: breakpoint.filePath,
                  line: breakpoint.line,
                  enabled: breakpoint.enabled,
                ),
              )
              .toList(growable: false),
        );
    if (!launchConfiguration.ready) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: launchConfiguration.reason,
          debuggerId: activeDebugger.id,
          debuggerLabel: activeDebugger.displayName,
          breakpoints: breakpoints,
          launchConfiguration: launchConfiguration,
        ),
      );
    }
    if (launcher == null) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.configured,
          message:
              'Debug session configured with ${activeDebugger.displayName} for ${launchConfiguration.programPath}; process launch adapter is not attached yet.',
          debuggerId: activeDebugger.id,
          debuggerLabel: activeDebugger.displayName,
          breakpoints: breakpoints,
          launchConfiguration: launchConfiguration,
        ),
      );
    }
    try {
      final executionPlan = DapDebugAdapterExecutionPlan.fromConfiguration(
        profileId: activeDebugger.id,
        launchConfiguration: launchConfiguration,
      );
      final executionResult = await DebugRuntimeExecutionAdapter(
        launcher: launcher,
        workspaceId: workspaceRoot,
      ).executePlan(plan: executionPlan, buffer: runtimeOutputBuffer);
      _lastRuntimeExecutionResult = executionResult;
      if (!executionResult.launched || executionResult.handle == null) {
        final record = executionResult.telemetry.records.isEmpty
            ? null
            : executionResult.telemetry.records.first;
        return _applyCommandSnapshot(
          DebugSessionSnapshot(
            status: DebugSessionStatus.blocked,
            message: record?.message ?? executionResult.dispatchResult.message,
            debuggerId: activeDebugger.id,
            debuggerLabel: activeDebugger.displayName,
            breakpoints: breakpoints,
            launchConfiguration: launchConfiguration,
          ),
        );
      }
      final handle = executionResult.handle!;
      await attachSession(handle, onSnapshot: onSnapshot);
      final adapterSnapshot = handle.snapshot;
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: statusFromDapSession(adapterSnapshot.status),
          message:
              'Debug adapter launch plan sent with ${adapterSnapshot.pendingRequests.length} pending DAP request(s).',
          debuggerId: activeDebugger.id,
          debuggerLabel: activeDebugger.displayName,
          breakpoints: breakpoints,
          launchConfiguration: launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    } on Object catch (error) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Start Debugging failed: $error',
          debuggerId: activeDebugger.id,
          debuggerLabel: activeDebugger.displayName,
          breakpoints: breakpoints,
          launchConfiguration: launchConfiguration,
        ),
      );
    }
  }

  Future<DebugCommandResult> stepOverSession() async {
    final sessionHandle = _sessionHandle;
    if (_session.status != DebugSessionStatus.paused) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Step Over blocked: no paused debug session.',
          breakpoints: breakpoints,
        ),
      );
    }
    if (sessionHandle != null) {
      final adapterSnapshot = sessionHandle.snapshot;
      final threadId = adapterSnapshot.activeThreadId;
      if (threadId == null) {
        return _applyCommandSnapshot(
          DebugSessionSnapshot(
            status: DebugSessionStatus.blocked,
            message:
                'Step Over blocked: DAP stopped event did not provide a threadId.',
            breakpoints: breakpoints,
            launchConfiguration: _session.launchConfiguration,
            adapterSessionStatus: adapterSnapshot.status.name,
            adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
            adapterEventCount: adapterSnapshot.events.length,
          ),
        );
      }
      await sessionHandle.sendRequest(
        const DapProtocolRequestFactory().next(
          seq: sessionHandle.bridge.session.reserveSeq(),
          threadId: threadId,
        ),
      );
      final refreshed = sessionHandle.snapshot;
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.running,
          message: 'Step Over request sent to DAP adapter.',
          debuggerId: _session.debuggerId,
          debuggerLabel: _session.debuggerLabel,
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: refreshed.status.name,
          adapterPendingRequestCount: refreshed.pendingRequests.length,
          adapterEventCount: refreshed.events.length,
        ),
      );
    }
    return _applyCommandSnapshot(
      DebugSessionSnapshot(
        status: DebugSessionStatus.paused,
        message: 'Step Over completed.',
        debuggerId: _session.debuggerId,
        debuggerLabel: _session.debuggerLabel,
        breakpoints: breakpoints,
        threads: _session.threads,
        stackFrames: _session.stackFrames,
        variables: _session.variables,
        launchConfiguration: _session.launchConfiguration,
        adapterSessionStatus: _session.adapterSessionStatus,
        adapterPendingRequestCount: _session.adapterPendingRequestCount,
        adapterEventCount: _session.adapterEventCount,
      ),
    );
  }

  Future<DebugCommandResult> selectStackFrame(String frameId) async {
    final sessionHandle = _sessionHandle;
    if (_session.status != DebugSessionStatus.paused) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Stack Frame blocked: no paused debug session.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: _session.adapterSessionStatus,
          adapterPendingRequestCount: _session.adapterPendingRequestCount,
          adapterEventCount: _session.adapterEventCount,
        ),
      );
    }
    if (sessionHandle == null) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Stack Frame blocked: no DAP session is active.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: _session.adapterSessionStatus,
          adapterPendingRequestCount: _session.adapterPendingRequestCount,
          adapterEventCount: _session.adapterEventCount,
        ),
      );
    }
    final frameIdValue = int.tryParse(frameId);
    if (frameIdValue == null) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Stack Frame blocked: invalid frame id $frameId.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: _session.adapterSessionStatus,
          adapterPendingRequestCount: _session.adapterPendingRequestCount,
          adapterEventCount: _session.adapterEventCount,
        ),
      );
    }
    final adapterSnapshot = sessionHandle.snapshot;
    if (!adapterSnapshot.stackFrames.any((frame) => frame.id == frameIdValue)) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Stack Frame blocked: frame $frameId was not found.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    }
    await sessionHandle.sendRequest(
      const DapProtocolRequestFactory().scopes(
        seq: sessionHandle.bridge.session.reserveSeq(),
        frameId: frameIdValue,
      ),
    );
    final refreshed = sessionHandle.snapshot;
    return _applyCommandSnapshot(
      DebugSessionSnapshot(
        status: DebugSessionStatus.paused,
        message:
            'Select Debug Stack Frame request sent to DAP adapter for frame $frameId.',
        debuggerId: _session.debuggerId,
        debuggerLabel: _session.debuggerLabel,
        breakpoints: breakpoints,
        threads: _session.threads,
        stackFrames: _session.stackFrames,
        variables: const <DebugVariable>[],
        launchConfiguration: _session.launchConfiguration,
        adapterSessionStatus: refreshed.status.name,
        adapterPendingRequestCount: refreshed.pendingRequests.length,
        adapterEventCount: refreshed.events.length,
      ),
    );
  }

  Future<DebugCommandResult> selectThread(String threadId) async {
    final sessionHandle = _sessionHandle;
    if (_session.status != DebugSessionStatus.paused) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Thread blocked: no paused debug session.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: _session.adapterSessionStatus,
          adapterPendingRequestCount: _session.adapterPendingRequestCount,
          adapterEventCount: _session.adapterEventCount,
        ),
      );
    }
    if (sessionHandle == null) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Thread blocked: no DAP session is active.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: _session.adapterSessionStatus,
          adapterPendingRequestCount: _session.adapterPendingRequestCount,
          adapterEventCount: _session.adapterEventCount,
        ),
      );
    }
    final threadIdValue = int.tryParse(threadId);
    if (threadIdValue == null) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Thread blocked: invalid thread id $threadId.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: _session.adapterSessionStatus,
          adapterPendingRequestCount: _session.adapterPendingRequestCount,
          adapterEventCount: _session.adapterEventCount,
        ),
      );
    }
    final adapterSnapshot = sessionHandle.snapshot;
    if (!adapterSnapshot.threads.any((thread) => thread.id == threadIdValue)) {
      return _applyCommandSnapshot(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Thread blocked: thread $threadId was not found.',
          breakpoints: breakpoints,
          threads: _session.threads,
          stackFrames: _session.stackFrames,
          variables: _session.variables,
          launchConfiguration: _session.launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    }
    await sessionHandle.sendRequest(
      const DapProtocolRequestFactory().stackTrace(
        seq: sessionHandle.bridge.session.reserveSeq(),
        threadId: threadIdValue,
      ),
    );
    final refreshed = sessionHandle.snapshot;
    return _applyCommandSnapshot(
      DebugSessionSnapshot(
        status: DebugSessionStatus.paused,
        message:
            'Select Debug Thread request sent to DAP adapter for thread $threadId.',
        debuggerId: _session.debuggerId,
        debuggerLabel: _session.debuggerLabel,
        breakpoints: breakpoints,
        threads: _session.threads,
        stackFrames: const <DebugStackFrame>[],
        variables: const <DebugVariable>[],
        launchConfiguration: _session.launchConfiguration,
        adapterSessionStatus: refreshed.status.name,
        adapterPendingRequestCount: refreshed.pendingRequests.length,
        adapterEventCount: refreshed.events.length,
      ),
    );
  }

  DebugCommandResult _applyCommandSnapshot(DebugSessionSnapshot snapshot) {
    replaceSession(snapshot);
    return DebugCommandResult(
      applied:
          snapshot.status != DebugSessionStatus.blocked &&
          snapshot.status != DebugSessionStatus.idle,
      message: snapshot.message,
    );
  }

  bool _hasPendingDapCommand(DapSessionSnapshot snapshot, String command) {
    return snapshot.pendingRequests.any(
      (request) => request.command == command,
    );
  }

  int? _firstScopeVariablesReference(List<DapScope> scopes) {
    for (final scope in scopes) {
      if (scope.variablesReference > 0) {
        return scope.variablesReference;
      }
    }
    return null;
  }

  int? _firstInspectableThreadId(List<DapThread> threads) {
    for (final thread in threads) {
      if (thread.id > 0) {
        return thread.id;
      }
    }
    return null;
  }

  @override
  void dispose() {
    final handle = _sessionHandle;
    _sessionHandle = null;
    _inspectionRequestInFlight = false;
    final subscription = _sessionSubscription;
    _sessionSubscription = null;
    unawaited(subscription?.cancel());
    if (handle != null) {
      unawaited(handle.close());
    }
    super.dispose();
  }
}
