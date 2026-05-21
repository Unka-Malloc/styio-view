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
          'TODO: bind failed-test debug cancellation route to concrete debug adapter and test runner process implementations.',
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

class TestingSessionController extends ChangeNotifier {
  TestingSessionController({
    this.discoveryProvider,
    this.runProvider,
    this.providerCatalog,
    this.rerunPlanner = const FailedTestRerunPlanner(),
    this.failedTestDebugCancellationAdapter,
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
    final route = FailedTestDebugCancellationRoute.fromState(
      runtimeTask: _lastRuntimeTask,
      configuration: _lastRunConfiguration,
      failedTest: failedTest,
      processHandleId: failedTestDebugCancellationAdapter?.processHandleId ?? '',
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
    final adapter = failedTestDebugCancellationAdapter;
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
          processHandleId:
              failedTestDebugCancellationAdapter?.processHandleId ?? '',
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
      processHandleId: failedTestDebugCancellationAdapter?.processHandleId ?? '',
      cancelled: true,
      message:
          'Failed-test debug cancellation routed for ${route.failedTestName}.',
    );
    _lastFailedDebugCancellationRoute = cancelledRoute;
    notifyListeners();
    return cancelledRoute;
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
