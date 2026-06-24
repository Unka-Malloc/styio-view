import 'dart:async';

import 'package:flutter/foundation.dart';

import '../runtime/runtime.dart';
import 'test_run_history_store.dart';
import 'testing_provider.dart';

class FailedTestDebugCancellationRoute {
  const FailedTestDebugCancellationRoute({
    required this.taskId,
    required this.providerId,
    required this.configurationId,
    required this.failedTestName,
    required this.failedTestId,
    required this.status,
    required this.ready,
    required this.cancelled,
    required this.message,
    this.routeKind = 'lifecycle',
    this.processHandleBound = false,
    this.processHandleId = '',
  });

  factory FailedTestDebugCancellationRoute.fromState({
    required RuntimeTaskSnapshot? runtimeTask,
    required TestRunConfiguration? configuration,
    required Map<String, Object?> failedTest,
    String processHandleId = '',
    bool cancelled = false,
    String? message,
  }) {
    final failedTestName =
        failedTest['name'] as String? ?? failedTest['id'] as String? ?? '';
    final failedTestId =
        failedTest['id'] as String? ?? failedTest['name'] as String? ?? '';
    final isDebugTask = runtimeTask?.definition.kind == RuntimeTaskKind.debug;
    final active = runtimeTask?.active ?? false;
    final ready = runtimeTask != null && isDebugTask && active && !cancelled;
    final handleId = processHandleId.trim();
    final blockedReason = runtimeTask == null
        ? 'No active test debug runtime task is available.'
        : !isDebugTask
        ? 'The active test runtime task is not a debug task.'
        : !active
        ? 'The test debug runtime task is not active.'
        : '';
    return FailedTestDebugCancellationRoute(
      taskId: runtimeTask?.definition.id ?? '',
      providerId: configuration?.providerId ?? '',
      configurationId: configuration?.id ?? '',
      failedTestName: failedTestName,
      failedTestId: failedTestId,
      status: cancelled
          ? RuntimeTaskStatus.cancelled.wireValue
          : runtimeTask?.status.wireValue ?? 'unavailable',
      ready: ready,
      cancelled: cancelled,
      routeKind: handleId.isEmpty ? 'lifecycle' : 'process-handle',
      processHandleBound: handleId.isNotEmpty,
      processHandleId: handleId,
      message:
          message ??
          (ready
              ? 'Failed-test debug cancellation is ready for $failedTestName.'
              : blockedReason),
    );
  }

  final String taskId;
  final String providerId;
  final String configurationId;
  final String failedTestName;
  final String failedTestId;
  final String status;
  final bool ready;
  final bool cancelled;
  final String message;
  final String routeKind;
  final bool processHandleBound;
  final String processHandleId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'taskId': taskId,
      'providerId': providerId,
      'configurationId': configurationId,
      'failedTestName': failedTestName,
      'failedTestId': failedTestId,
      'status': status,
      'ready': ready,
      'cancelled': cancelled,
      'message': message,
      'routeKind': routeKind,
      'processHandleBound': processHandleBound,
      if (processHandleId.isNotEmpty) 'processHandleId': processHandleId,
      'todo':
          'TODO: ensure concrete debug adapter and test runner runtime snapshots expose processHandleId/pid metadata.',
    };
  }
}

class FailedTestDebugCancellationResult {
  const FailedTestDebugCancellationResult({
    required this.accepted,
    required this.processTerminated,
    required this.message,
    this.metadata = const <String, Object?>{},
  });

  const FailedTestDebugCancellationResult.accepted({
    bool processTerminated = false,
    String message = 'Failed-test debug cancellation requested.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: true,
         processTerminated: processTerminated,
         message: message,
         metadata: metadata,
       );

  const FailedTestDebugCancellationResult.rejected({
    String message = 'Failed-test debug cancellation was rejected.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: false,
         processTerminated: false,
         message: message,
         metadata: metadata,
       );

  final bool accepted;
  final bool processTerminated;
  final String message;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accepted': accepted,
      'processTerminated': processTerminated,
      'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

typedef FailedTestDebugCancellationHandler =
    Future<FailedTestDebugCancellationResult> Function({
      required FailedTestDebugCancellationRoute route,
      required RuntimeTaskSnapshot runtimeTask,
      required TestRunConfiguration? configuration,
      required Map<String, Object?> failedTest,
      required String reason,
    });

typedef FailedTestDebugProcessTerminator =
    Future<FailedTestDebugCancellationResult> Function(
      FailedTestDebugProcessTerminationRequest request,
    );

class FailedTestDebugProcessTerminationRequest {
  const FailedTestDebugProcessTerminationRequest({
    required this.route,
    required this.runtimeTask,
    required this.configuration,
    required this.failedTest,
    required this.reason,
    required this.processHandleId,
    required this.kind,
  });

  final FailedTestDebugCancellationRoute route;
  final RuntimeTaskSnapshot runtimeTask;
  final TestRunConfiguration? configuration;
  final Map<String, Object?> failedTest;
  final String reason;
  final String processHandleId;
  final FailedTestDebugCancellationHandleKind kind;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'taskId': runtimeTask.definition.id,
      'providerId': route.providerId,
      'configurationId': route.configurationId,
      'failedTestName': route.failedTestName,
      'failedTestId': route.failedTestId,
      'reason': reason,
      'processHandleId': processHandleId,
      'kind': kind.name,
    };
  }
}

abstract class FailedTestDebugProcessCancellationHandle {
  const FailedTestDebugProcessCancellationHandle();

  String get handleId;

  Future<FailedTestDebugCancellationResult> cancelFailedTestDebug({
    required FailedTestDebugCancellationRoute route,
    required RuntimeTaskSnapshot runtimeTask,
    required TestRunConfiguration? configuration,
    required Map<String, Object?> failedTest,
    required String reason,
  });
}

class FailedTestDebugRuntimeProcessCancellationHandle
    extends FailedTestDebugProcessCancellationHandle {
  const FailedTestDebugRuntimeProcessCancellationHandle({
    required this.handleId,
    required this.kind,
    required FailedTestDebugProcessTerminator terminate,
  }) : _terminate = terminate;

  @override
  final String handleId;
  final FailedTestDebugCancellationHandleKind kind;
  final FailedTestDebugProcessTerminator _terminate;

  @override
  Future<FailedTestDebugCancellationResult> cancelFailedTestDebug({
    required FailedTestDebugCancellationRoute route,
    required RuntimeTaskSnapshot runtimeTask,
    required TestRunConfiguration? configuration,
    required Map<String, Object?> failedTest,
    required String reason,
  }) async {
    final request = FailedTestDebugProcessTerminationRequest(
      route: route,
      runtimeTask: runtimeTask,
      configuration: configuration,
      failedTest: failedTest,
      reason: reason,
      processHandleId: handleId,
      kind: kind,
    );
    final result = await _terminate(request);
    return FailedTestDebugCancellationResult(
      accepted: result.accepted,
      processTerminated: result.processTerminated,
      message: result.message,
      metadata: <String, Object?>{
        ...result.metadata,
        'terminationRequest': request.toJson(),
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'processHandleId': handleId, 'kind': kind.name};
  }
}

class FailedTestDebugCancellationAdapter {
  const FailedTestDebugCancellationAdapter({
    required FailedTestDebugCancellationHandler cancel,
    this.processHandleId = '',
  }) : _cancel = cancel;

  factory FailedTestDebugCancellationAdapter.processHandle(
    FailedTestDebugProcessCancellationHandle handle,
  ) {
    return FailedTestDebugCancellationAdapter(
      cancel:
          ({
            required route,
            required runtimeTask,
            required configuration,
            required failedTest,
            required reason,
          }) async {
            final result = await handle.cancelFailedTestDebug(
              route: route,
              runtimeTask: runtimeTask,
              configuration: configuration,
              failedTest: failedTest,
              reason: reason,
            );
            return FailedTestDebugCancellationResult(
              accepted: result.accepted,
              processTerminated: result.processTerminated,
              message: result.message,
              metadata: <String, Object?>{
                ...result.metadata,
                'processHandleId': handle.handleId,
              },
            );
          },
      processHandleId: handle.handleId,
    );
  }

  final FailedTestDebugCancellationHandler _cancel;
  final String processHandleId;

  Future<FailedTestDebugCancellationResult> cancel({
    required FailedTestDebugCancellationRoute route,
    required RuntimeTaskSnapshot runtimeTask,
    required TestRunConfiguration? configuration,
    required Map<String, Object?> failedTest,
    required String reason,
  }) {
    return _cancel(
      route: route,
      runtimeTask: runtimeTask,
      configuration: configuration,
      failedTest: failedTest,
      reason: reason,
    );
  }
}

enum FailedTestDebugCancellationHandleKind { debugAdapter, testRunner }

enum FailedTestDebugProcessHandleBindingStatus {
  registered,
  missingHandle,
  skipped,
}

class FailedTestDebugProcessHandleBindingResult {
  const FailedTestDebugProcessHandleBindingResult({
    required this.status,
    required this.message,
    this.processHandleId = '',
    this.metadata = const <String, Object?>{},
  });

  const FailedTestDebugProcessHandleBindingResult.registered({
    required String processHandleId,
    String message = 'Failed-test debug process handle registered.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: FailedTestDebugProcessHandleBindingStatus.registered,
         processHandleId: processHandleId,
         message: message,
         metadata: metadata,
       );

  const FailedTestDebugProcessHandleBindingResult.missingHandle({
    String message =
        'Failed-test debug runtime task did not expose a process handle.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: FailedTestDebugProcessHandleBindingStatus.missingHandle,
         message: message,
         metadata: metadata,
       );

  const FailedTestDebugProcessHandleBindingResult.skipped({
    String message =
        'Failed-test debug runtime task was not eligible for handle binding.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: FailedTestDebugProcessHandleBindingStatus.skipped,
         message: message,
         metadata: metadata,
       );

  final FailedTestDebugProcessHandleBindingStatus status;
  final String message;
  final String processHandleId;
  final Map<String, Object?> metadata;

  bool get registered =>
      status == FailedTestDebugProcessHandleBindingStatus.registered;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'registered': registered,
      'message': message,
      if (processHandleId.isNotEmpty) 'processHandleId': processHandleId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class FailedTestDebugProcessHandleBinder {
  const FailedTestDebugProcessHandleBinder({
    this.handleIdKeys = const <String>[
      'processHandleId',
      'processId',
      'pid',
      'debugProcessHandleId',
    ],
  });

  final List<String> handleIdKeys;

  FailedTestDebugProcessHandleBindingResult bind({
    required RuntimeTaskSnapshot runtimeTask,
    required FailedTestDebugCancellationHandleRegistry registry,
    required FailedTestDebugProcessTerminator terminate,
    required String providerId,
    String configurationId = '',
    FailedTestDebugCancellationHandleKind kind =
        FailedTestDebugCancellationHandleKind.debugAdapter,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (runtimeTask.definition.kind != RuntimeTaskKind.debug) {
      return FailedTestDebugProcessHandleBindingResult.skipped(
        message:
            'Runtime task ${runtimeTask.definition.id} is not a debug task; no failed-test debug handle was bound.',
        metadata: metadata,
      );
    }
    final processHandle = _processHandleFromRuntimeTask(runtimeTask);
    final handleId =
        _handleIdFromProcessHandle(processHandle) ??
        _handleIdFromRuntimeTask(runtimeTask);
    if (handleId == null) {
      return FailedTestDebugProcessHandleBindingResult.missingHandle(
        message:
            'Runtime task ${runtimeTask.definition.id} did not expose a failed-test debug process handle.',
        metadata: metadata,
      );
    }
    registry.register(
      FailedTestDebugCancellationHandleRegistration(
        kind: kind,
        providerId: providerId,
        configurationId: configurationId,
        handle: FailedTestDebugRuntimeProcessCancellationHandle(
          handleId: handleId,
          kind: kind,
          terminate: terminate,
        ),
      ),
    );
    return FailedTestDebugProcessHandleBindingResult.registered(
      processHandleId: handleId,
      message:
          'Failed-test debug process handle $handleId registered for ${runtimeTask.definition.id}.',
      metadata: <String, Object?>{
        'source': 'runtime-task-snapshot',
        'providerId': providerId,
        if (configurationId.isNotEmpty) 'configurationId': configurationId,
        if (processHandle != null) 'processHandle': processHandle.toJson(),
        ...metadata,
      },
    );
  }

  RuntimeProcessHandleIdentity? _processHandleFromRuntimeTask(
    RuntimeTaskSnapshot runtimeTask,
  ) {
    for (final source in <Map<String, Object?>>[
      runtimeTask.definition.metadata,
      if (runtimeTask.lastEvent != null) runtimeTask.lastEvent!.metadata,
      for (final event in runtimeTask.events.reversed) event.metadata,
    ]) {
      final handle = RuntimeProcessHandleIdentity.tryFromMetadata(
        source,
        managerId: _managerIdFromMetadata(source),
      );
      if (handle != null) {
        return handle;
      }
    }
    return null;
  }

  String? _handleIdFromProcessHandle(RuntimeProcessHandleIdentity? handle) {
    if (handle == null || !handle.available) {
      return null;
    }
    if (handle.processHandleId.isNotEmpty) {
      return handle.processHandleId;
    }
    final pid = handle.pid;
    return pid == null ? null : '$pid';
  }

  String? _handleIdFromRuntimeTask(RuntimeTaskSnapshot runtimeTask) {
    for (final source in <Map<String, Object?>>[
      runtimeTask.definition.metadata,
      if (runtimeTask.lastEvent != null) runtimeTask.lastEvent!.metadata,
      for (final event in runtimeTask.events.reversed) event.metadata,
    ]) {
      final handleId = _handleIdFromMetadata(source);
      if (handleId != null) {
        return handleId;
      }
    }
    return null;
  }

  String _managerIdFromMetadata(Map<String, Object?> metadata) {
    final value = metadata['managerId'];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '';
  }

  String? _handleIdFromMetadata(Map<String, Object?> metadata) {
    for (final key in handleIdKeys) {
      final value = metadata[key];
      if (value == null) {
        continue;
      }
      final handleId = '$value'.trim();
      if (handleId.isNotEmpty) {
        return handleId;
      }
    }
    return null;
  }
}

class FailedTestDebugCancellationHandleRegistration {
  const FailedTestDebugCancellationHandleRegistration({
    required this.kind,
    required this.handle,
    this.providerId = '',
    this.configurationId = '',
  });

  final FailedTestDebugCancellationHandleKind kind;
  final FailedTestDebugProcessCancellationHandle handle;
  final String providerId;
  final String configurationId;

  bool matches({required String providerId, required String configurationId}) {
    final providerMatches =
        this.providerId.trim().isEmpty || this.providerId == providerId;
    final configurationMatches =
        this.configurationId.trim().isEmpty ||
        this.configurationId == configurationId;
    return providerMatches && configurationMatches;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'providerId': providerId,
      'configurationId': configurationId,
      'processHandleId': handle.handleId,
    };
  }
}

class FailedTestDebugCancellationHandleRegistry {
  FailedTestDebugCancellationHandleRegistry({
    Iterable<FailedTestDebugCancellationHandleRegistration> registrations =
        const <FailedTestDebugCancellationHandleRegistration>[],
  }) : _registrations = <FailedTestDebugCancellationHandleRegistration>[
         ...registrations,
       ];

  final List<FailedTestDebugCancellationHandleRegistration> _registrations;

  int get registrationCount => _registrations.length;

  void register(FailedTestDebugCancellationHandleRegistration registration) {
    _registrations.removeWhere(
      (existing) =>
          existing.kind == registration.kind &&
          existing.providerId == registration.providerId &&
          existing.configurationId == registration.configurationId,
    );
    _registrations.add(registration);
  }

  bool unregister({
    required FailedTestDebugCancellationHandleKind kind,
    String providerId = '',
    String configurationId = '',
  }) {
    final before = _registrations.length;
    _registrations.removeWhere(
      (existing) =>
          existing.kind == kind &&
          existing.providerId == providerId &&
          existing.configurationId == configurationId,
    );
    return _registrations.length != before;
  }

  FailedTestDebugCancellationHandleRegistration? registrationFor({
    required String providerId,
    required String configurationId,
  }) {
    final matches = _registrations
        .where(
          (registration) => registration.matches(
            providerId: providerId,
            configurationId: configurationId,
          ),
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }
    matches.sort((left, right) => left.kind.index.compareTo(right.kind.index));
    return matches.first;
  }

  FailedTestDebugCancellationAdapter? adapterFor({
    required String providerId,
    required String configurationId,
  }) {
    final registration = registrationFor(
      providerId: providerId,
      configurationId: configurationId,
    );
    if (registration == null) {
      return null;
    }
    return FailedTestDebugCancellationAdapter.processHandle(
      registration.handle,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'registrationCount': registrationCount,
      'registrations': _registrations
          .map((registration) => registration.toJson())
          .toList(growable: false),
    };
  }
}

class TestingSessionController extends ChangeNotifier {
  TestingSessionController({
    this.discoveryProvider,
    this.runProvider,
    this.providerCatalog,
    this.rerunPlanner = const FailedTestRerunPlanner(),
    this.failedTestDebugCancellationAdapter,
    this.failedTestDebugCancellationHandleRegistry,
    RuntimeTaskLifecycleController? runtimeTaskLifecycleController,
    RuntimeTaskHistoryStore? runtimeTaskHistoryStore,
    TestRunHistoryStore? testRunHistoryStore,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    RuntimeTaskClock? clock,
    this.runtimeTaskHistoryWorkspaceId = 'default',
    this.runtimeTaskHistoryMaxEntries = 50,
    this.testRunHistoryWorkspaceId = 'default',
    this.testRunHistoryMaxEntries = 30,
  }) : _runtimeTaskLifecycleController = runtimeTaskLifecycleController,
       _runtimeTaskHistoryStore = runtimeTaskHistoryStore,
       _testRunHistoryStore = testRunHistoryStore,
       _runtimeOutputBuffer = runtimeOutputBuffer,
       _clock = clock ?? DateTime.now().toUtc;

  final TestDiscoveryProvider? discoveryProvider;
  final TestRunProvider? runProvider;
  final TestingProviderCatalog? providerCatalog;
  final FailedTestRerunPlanner rerunPlanner;
  final FailedTestDebugCancellationAdapter? failedTestDebugCancellationAdapter;
  final FailedTestDebugCancellationHandleRegistry?
  failedTestDebugCancellationHandleRegistry;
  final RuntimeTaskLifecycleController? _runtimeTaskLifecycleController;
  final RuntimeTaskHistoryStore? _runtimeTaskHistoryStore;
  final TestRunHistoryStore? _testRunHistoryStore;
  final RuntimeOutputLiveBuffer? _runtimeOutputBuffer;
  final RuntimeTaskClock _clock;
  final String runtimeTaskHistoryWorkspaceId;
  final int runtimeTaskHistoryMaxEntries;
  final String testRunHistoryWorkspaceId;
  final int testRunHistoryMaxEntries;

  TestDiscoveryResult? _discovery;
  TestRunResult? _lastRun;
  TestRunRequest? _lastRunRequest;
  TestRunConfiguration? _lastRunConfiguration;
  RuntimeTaskSnapshot? _lastRuntimeTask;
  FailedTestDebugCancellationRoute? _lastFailedDebugCancellationRoute;
  final List<TestRunResult> _runHistory = <TestRunResult>[];
  final List<FailedTestRetryRecord> _failedRetryHistory =
      <FailedTestRetryRecord>[];
  int _discoveryGeneration = 0;
  int _runGeneration = 0;

  TestDiscoveryResult? get discovery => _discovery;
  TestRunResult? get lastRun => _lastRun;
  TestRunRequest? get lastRunRequest => _lastRunRequest;
  TestRunConfiguration? get lastRunConfiguration => _lastRunConfiguration;
  RuntimeTaskSnapshot? get lastRuntimeTask => _lastRuntimeTask;
  FailedTestDebugCancellationRoute? get lastFailedDebugCancellationRoute =>
      _lastFailedDebugCancellationRoute;
  List<TestRunResult> get runHistory =>
      List<TestRunResult>.unmodifiable(_runHistory);
  List<FailedTestRetryRecord> get failedRetryHistory =>
      List<FailedTestRetryRecord>.unmodifiable(_failedRetryHistory);
  bool get hasDiscovery => _discovery != null;
  bool get hasLastRun => _lastRun != null;

  String providerRetryPlanMessage(String surface) {
    final retryPlan = providerCatalog?.retryPlan();
    if (retryPlan == null) {
      return 'Testing provider retry plan is unavailable.';
    }
    final surfaceActions = retryPlan.actions
        .where((action) => action.surface == surface)
        .toList(growable: false);
    if (surfaceActions.isEmpty) {
      return retryPlan.message;
    }
    final labels = surfaceActions.map((action) => action.label).join(', ');
    return '${retryPlan.message} Retry actions: $labels.';
  }

  void recordDiscoveryResult(TestDiscoveryResult result) {
    _discoveryGeneration++;
    _discovery = result;
    notifyListeners();
  }

  void recordRunResult(TestRunResult result) {
    _runGeneration++;
    _lastRuntimeTask = null;
    _storeRunResult(result);
    unawaited(_persistTestRunResult(result));
    notifyListeners();
  }

  Future<void> loadRunHistory() async {
    final store = _testRunHistoryStore;
    if (store == null) {
      return;
    }
    final history = await store.readHistory(
      workspaceId: testRunHistoryWorkspaceId,
    );
    _runHistory
      ..clear()
      ..addAll(history.runs.take(20));
    final failedRetryHistory = await store.readFailedRetryHistory(
      workspaceId: testRunHistoryWorkspaceId,
    );
    _failedRetryHistory
      ..clear()
      ..addAll(failedRetryHistory.records.take(20));
    _lastRun = _runHistory.isEmpty ? null : _runHistory.first;
    notifyListeners();
  }

  Future<TestDiscoveryResult> discover(TestDiscoveryRequest request) async {
    final provider = discoveryProvider ?? providerCatalog?.discoveryProvider();
    final generation = ++_discoveryGeneration;
    if (provider == null) {
      final result = TestDiscoveryResult(
        providerId: 'unavailable',
        roots: <TestNode>[],
        message:
            'Test discovery provider is not configured. '
            '${providerRetryPlanMessage('discovery')}',
      );
      _storeDiscovery(result, generation);
      return result;
    }

    try {
      final result = await provider.discover(request);
      _storeDiscovery(result, generation);
      return result;
    } on Object catch (error) {
      final result = TestDiscoveryResult(
        providerId: provider.providerId,
        roots: const <TestNode>[],
        message:
            'Test discovery unavailable: $error. '
            '${providerRetryPlanMessage('discovery')}',
      );
      _storeDiscovery(result, generation);
      return result;
    }
  }

  Future<TestRunResult> run(TestRunRequest request) async {
    final provider = runProvider ?? providerCatalog?.runProvider();
    final generation = ++_runGeneration;
    _lastRunRequest = request;
    _lastRunConfiguration = null;
    final runtimeTask = _startRuntimeTask(
      request: request,
      providerId: provider?.providerId ?? 'unavailable',
      runnable: provider != null,
    );
    if (provider == null) {
      final finishedTask = _finishRuntimeTask(
        runtimeTask,
        status: TestRunStatus.error,
        message: 'Test run task blocked: provider is not configured.',
      );
      await _persistRuntimeTask(finishedTask);
      final result = _attachRuntimeTask(
        TestRunResult(
          providerId: 'unavailable',
          status: TestRunStatus.error,
          message:
              'Test run provider is not configured. '
              '${providerRetryPlanMessage('run')}',
        ),
        finishedTask,
      );
      await _storeRun(result, generation);
      return result;
    }

    try {
      final providerResult = await provider.run(request);
      if (_isRuntimeTaskCancelled(runtimeTask)) {
        final result = await _storeCancelledRun(
          providerId: provider.providerId,
          runtimeTask: runtimeTask,
          generation: generation,
        );
        return result;
      }
      final finishedTask = _finishRuntimeTask(
        runtimeTask,
        status: providerResult.status,
        message: providerResult.message,
      );
      await _persistRuntimeTask(finishedTask);
      final result = _attachRuntimeTask(providerResult, finishedTask);
      await _storeRun(result, generation);
      return result;
    } on Object catch (error) {
      if (_isRuntimeTaskCancelled(runtimeTask)) {
        final result = await _storeCancelledRun(
          providerId: provider.providerId,
          runtimeTask: runtimeTask,
          generation: generation,
        );
        return result;
      }
      final finishedTask = _finishRuntimeTask(
        runtimeTask,
        status: TestRunStatus.error,
        message: 'Test run task failed: $error',
      );
      await _persistRuntimeTask(finishedTask);
      final result = _attachRuntimeTask(
        TestRunResult(
          providerId: provider.providerId,
          status: TestRunStatus.error,
          message:
              'Test run unavailable: $error. '
              '${providerRetryPlanMessage('run')}',
        ),
        finishedTask,
      );
      await _storeRun(result, generation);
      return result;
    }
  }

  Future<TestRunResult> runConfiguration(
    TestRunConfiguration configuration,
  ) async {
    if (!configuration.ready) {
      final runtimeTask = _blockConfigurationRuntimeTask(configuration);
      await _persistRuntimeTask(runtimeTask);
      final result = _attachRuntimeTask(
        TestRunResult(
          providerId: configuration.providerId.isEmpty
              ? 'unavailable'
              : configuration.providerId,
          status: TestRunStatus.error,
          message:
              'Test run configuration is not ready. '
              'TODO: surface configuration repair actions.',
          metadata: <String, Object?>{'configuration': configuration.toJson()},
        ),
        runtimeTask,
      );
      _storeRunResult(result);
      await _persistTestRunResult(result);
      notifyListeners();
      return result;
    }
    final result = await run(configuration.toRunRequest());
    _lastRunConfiguration = configuration;
    return result;
  }

  Future<TestRunResult> debugConfiguration(TestRunConfiguration configuration) {
    return runConfiguration(configuration.copyWith(debug: true));
  }

  FailedTestDebugCancellationRoute planFailedTestDebugCancellation({
    Map<String, Object?> failedTest = const <String, Object?>{},
  }) {
    final adapter = _failedTestDebugCancellationAdapterFor();
    final route = FailedTestDebugCancellationRoute.fromState(
      runtimeTask: _lastRuntimeTask,
      configuration: _lastRunConfiguration,
      failedTest: failedTest,
      processHandleId: adapter?.processHandleId ?? '',
    );
    _lastFailedDebugCancellationRoute = route;
    notifyListeners();
    return route;
  }

  Future<FailedTestDebugCancellationRoute> cancelFailedTestDebug({
    Map<String, Object?> failedTest = const <String, Object?>{},
  }) async {
    final route = planFailedTestDebugCancellation(failedTest: failedTest);
    final controller = _runtimeTaskLifecycleController;
    final runtimeTask = _lastRuntimeTask;
    if (!route.ready || controller == null || runtimeTask == null) {
      return route;
    }
    final cancellationMessage =
        'Cancelled failed-test debug task ${route.taskId} for ${route.failedTestName}.';
    final adapter = _failedTestDebugCancellationAdapterFor();
    FailedTestDebugCancellationResult? adapterResult;
    if (adapter != null) {
      adapterResult = await adapter.cancel(
        route: route,
        runtimeTask: runtimeTask,
        configuration: _lastRunConfiguration,
        failedTest: failedTest,
        reason: cancellationMessage,
      );
      if (!adapterResult.accepted) {
        final rejectedRoute = FailedTestDebugCancellationRoute.fromState(
          runtimeTask: runtimeTask,
          configuration: _lastRunConfiguration,
          failedTest: failedTest,
          processHandleId: adapter.processHandleId,
          message: adapterResult.message,
        );
        _lastFailedDebugCancellationRoute = rejectedRoute;
        notifyListeners();
        return rejectedRoute;
      }
    }
    final cancelled = controller.cancel(
      route.taskId,
      message: adapterResult?.message ?? cancellationMessage,
      metadata: adapterResult == null
          ? const <String, Object?>{}
          : <String, Object?>{
              'failedTestDebugCancellation': adapterResult.toJson(),
            },
    );
    _cancelledRuntimeTaskIds.add(route.taskId);
    _lastRuntimeTask = cancelled;
    await _persistRuntimeTask(cancelled);
    final cancelledRoute = FailedTestDebugCancellationRoute.fromState(
      runtimeTask: cancelled,
      configuration: _lastRunConfiguration,
      failedTest: failedTest,
      processHandleId: adapter?.processHandleId ?? '',
      cancelled: true,
      message:
          'Failed-test debug cancellation routed for ${route.failedTestName}.',
    );
    _lastFailedDebugCancellationRoute = cancelledRoute;
    notifyListeners();
    return cancelledRoute;
  }

  FailedTestDebugCancellationAdapter? _failedTestDebugCancellationAdapterFor() {
    final directAdapter = failedTestDebugCancellationAdapter;
    if (directAdapter != null) {
      return directAdapter;
    }
    final configuration = _lastRunConfiguration;
    return failedTestDebugCancellationHandleRegistry?.adapterFor(
      providerId: configuration?.providerId ?? _lastRun?.providerId ?? '',
      configurationId: configuration?.id ?? '',
    );
  }

  Future<TestRunResult> rerunFailed({
    required String workspaceRoot,
    bool debug = false,
  }) async {
    final configuration = rerunPlanner.plan(
      lastRun: _lastRun,
      workspaceRoot: workspaceRoot,
      debug: debug,
    );
    if (configuration == null) {
      final result = const TestRunResult(
        providerId: 'unavailable',
        status: TestRunStatus.notRun,
        message:
            'Rerun failed skipped: no failed test cases are available. '
            'TODO: preserve provider-specific failed test identifiers.',
      );
      _storeRunResult(result);
      await _persistTestRunResult(result);
      await _persistFailedRetryRecord(
        FailedTestRetryRecord.fromResult(result: result, attemptedAt: _clock()),
      );
      notifyListeners();
      return result;
    }
    final result = await runConfiguration(configuration);
    await _persistFailedRetryRecord(
      FailedTestRetryRecord.fromResult(
        result: result,
        configuration: configuration,
        attemptedAt: _clock(),
      ),
    );
    return result;
  }

  void clear() {
    if (_discovery == null && _lastRun == null) {
      return;
    }
    _discoveryGeneration++;
    _runGeneration++;
    _discovery = null;
    _lastRun = null;
    _lastRunRequest = null;
    _lastRunConfiguration = null;
    _lastRuntimeTask = null;
    _runHistory.clear();
    _failedRetryHistory.clear();
    notifyListeners();
  }

  void _storeDiscovery(TestDiscoveryResult result, int generation) {
    if (generation != _discoveryGeneration) {
      return;
    }
    _discovery = result;
    notifyListeners();
  }

  Future<void> _storeRun(TestRunResult result, int generation) async {
    if (generation != _runGeneration) {
      return;
    }
    _storeRunResult(result);
    await _persistTestRunResult(result);
    notifyListeners();
  }

  void _storeRunResult(TestRunResult result) {
    _lastRun = result;
    _runHistory.insert(0, result);
    if (_runHistory.length > 20) {
      _runHistory.removeRange(20, _runHistory.length);
    }
    _runtimeOutputBuffer?.addEvent(result.outputEvent(timestamp: _clock()));
  }

  RuntimeTaskSnapshot? _startRuntimeTask({
    required TestRunRequest request,
    required String providerId,
    required bool runnable,
  }) {
    final controller = _runtimeTaskLifecycleController;
    if (controller == null) {
      return null;
    }
    final taskId = 'test.$providerId.$_runGeneration';
    final definition = RuntimeTaskDefinition(
      id: taskId,
      label: request.debug ? 'Debug tests' : 'Run tests',
      kind: request.debug ? RuntimeTaskKind.debug : RuntimeTaskKind.test,
      command: runnable ? providerId : '',
      arguments: <String>[
        if (request.targetId.isNotEmpty) request.targetId,
        if (request.filter.isNotEmpty) request.filter,
      ],
      workingDirectory: request.workspaceRoot,
      metadata: <String, Object?>{
        'request': request.toJson(),
        'providerId': providerId,
        'source': 'TestingSessionController',
        'todo': 'TODO: attach test task output streams to runtime history.',
      },
    );
    controller.register(definition);
    if (!definition.runnable) {
      final blocked = controller.block(
        taskId,
        message: 'Test task $taskId has no runnable provider.',
        metadata: const <String, Object?>{'phase': 'provider-selection'},
      );
      _lastRuntimeTask = blocked;
      return blocked;
    }
    final started = controller.start(
      taskId,
      message: 'Test task $taskId started.',
    );
    _lastRuntimeTask = started;
    return started;
  }

  final Set<String> _cancelledRuntimeTaskIds = <String>{};

  bool _isRuntimeTaskCancelled(RuntimeTaskSnapshot? runtimeTask) {
    return runtimeTask != null &&
        _cancelledRuntimeTaskIds.contains(runtimeTask.definition.id);
  }

  Future<TestRunResult> _storeCancelledRun({
    required String providerId,
    required RuntimeTaskSnapshot? runtimeTask,
    required int generation,
  }) async {
    final taskId = runtimeTask?.definition.id ?? '';
    if (taskId.isNotEmpty) {
      _cancelledRuntimeTaskIds.remove(taskId);
    }
    final snapshot = taskId.isEmpty
        ? runtimeTask
        : _runtimeTaskLifecycleController?.snapshotFor(taskId) ?? runtimeTask;
    await _persistRuntimeTask(snapshot);
    final result = _attachRuntimeTask(
      TestRunResult(
        providerId: providerId,
        status: TestRunStatus.notRun,
        message: taskId.isEmpty
            ? 'Test debug run cancelled.'
            : 'Test debug run cancelled: $taskId.',
      ),
      snapshot,
    );
    await _storeRun(result, generation);
    return result;
  }

  RuntimeTaskSnapshot? _finishRuntimeTask(
    RuntimeTaskSnapshot? snapshot, {
    required TestRunStatus status,
    required String message,
  }) {
    final controller = _runtimeTaskLifecycleController;
    if (controller == null || snapshot == null) {
      _lastRuntimeTask = snapshot;
      return snapshot;
    }
    final taskId = snapshot.definition.id;
    final finished = switch (status) {
      TestRunStatus.passed || TestRunStatus.skipped => controller.complete(
        taskId,
        message: message.isEmpty ? 'Test task $taskId completed.' : message,
      ),
      TestRunStatus.failed || TestRunStatus.error => controller.fail(
        taskId,
        message: message.isEmpty ? 'Test task $taskId failed.' : message,
        exitCode: 1,
      ),
      TestRunStatus.notRun => controller.block(
        taskId,
        message: message.isEmpty ? 'Test task $taskId was not run.' : message,
      ),
    };
    _lastRuntimeTask = finished;
    return finished;
  }

  RuntimeTaskSnapshot? _blockConfigurationRuntimeTask(
    TestRunConfiguration configuration,
  ) {
    final controller = _runtimeTaskLifecycleController;
    if (controller == null) {
      _lastRuntimeTask = null;
      return null;
    }
    final taskId =
        'test.configuration.${configuration.id.trim().isEmpty ? 'unready' : configuration.id}';
    final definition = RuntimeTaskDefinition(
      id: taskId,
      label: configuration.label.trim().isEmpty
          ? 'Unready test configuration'
          : configuration.label,
      kind: configuration.debug ? RuntimeTaskKind.debug : RuntimeTaskKind.test,
      command: '',
      workingDirectory: configuration.workspaceRoot,
      metadata: <String, Object?>{
        'configuration': configuration.toJson(),
        'source': 'TestingSessionController',
      },
    );
    controller.register(definition);
    final blocked = controller.block(
      taskId,
      message: 'Test run configuration ${configuration.id} is not ready.',
      metadata: const <String, Object?>{'phase': 'configuration'},
    );
    _lastRuntimeTask = blocked;
    return blocked;
  }

  TestRunResult _attachRuntimeTask(
    TestRunResult result,
    RuntimeTaskSnapshot? runtimeTask,
  ) {
    if (runtimeTask == null) {
      _lastRuntimeTask = null;
      return result;
    }
    _lastRuntimeTask = runtimeTask;
    return TestRunResult(
      providerId: result.providerId,
      runner: result.runner,
      status: result.status,
      message: result.message,
      totalCount: result.totalCount,
      passedCount: result.passedCount,
      failedCount: result.failedCount,
      skippedCount: result.skippedCount,
      cases: result.cases,
      metadata: <String, Object?>{
        ...result.metadata,
        'runtimeTask': runtimeTask.toJson(),
        'outputSubscription': result
            .outputSubscriptionPlan(taskId: runtimeTask.definition.id)
            .toJson(),
      },
    );
  }

  Future<void> _persistRuntimeTask(RuntimeTaskSnapshot? runtimeTask) async {
    final store = _runtimeTaskHistoryStore;
    if (store == null || runtimeTask == null) {
      return;
    }
    await store.appendTask(
      workspaceId: runtimeTaskHistoryWorkspaceId,
      task: runtimeTask,
      maxEntries: runtimeTaskHistoryMaxEntries,
    );
  }

  Future<void> _persistTestRunResult(TestRunResult result) async {
    final store = _testRunHistoryStore;
    if (store == null) {
      return;
    }
    await store.appendRun(
      workspaceId: testRunHistoryWorkspaceId,
      result: result,
      maxEntries: testRunHistoryMaxEntries,
    );
  }

  Future<void> _persistFailedRetryRecord(FailedTestRetryRecord record) async {
    _failedRetryHistory.insert(0, record);
    if (_failedRetryHistory.length > testRunHistoryMaxEntries) {
      _failedRetryHistory.removeRange(
        testRunHistoryMaxEntries,
        _failedRetryHistory.length,
      );
    }
    final store = _testRunHistoryStore;
    if (store != null) {
      await store.appendFailedRetry(
        workspaceId: testRunHistoryWorkspaceId,
        record: record,
        maxEntries: testRunHistoryMaxEntries,
      );
    }
    notifyListeners();
  }
}
