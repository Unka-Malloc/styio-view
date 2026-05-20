import 'dart:async';

import 'package:flutter/foundation.dart';

import '../runtime/runtime.dart';
import 'test_run_history_store.dart';
import 'testing_provider.dart';

class TestingSessionController extends ChangeNotifier {
  TestingSessionController({
    this.discoveryProvider,
    this.runProvider,
    this.rerunPlanner = const FailedTestRerunPlanner(),
    RuntimeTaskLifecycleController? runtimeTaskLifecycleController,
    RuntimeTaskHistoryStore? runtimeTaskHistoryStore,
    TestRunHistoryStore? testRunHistoryStore,
    this.runtimeTaskHistoryWorkspaceId = 'default',
    this.runtimeTaskHistoryMaxEntries = 50,
    this.testRunHistoryWorkspaceId = 'default',
    this.testRunHistoryMaxEntries = 30,
  }) : _runtimeTaskLifecycleController = runtimeTaskLifecycleController,
       _runtimeTaskHistoryStore = runtimeTaskHistoryStore,
       _testRunHistoryStore = testRunHistoryStore;

  final TestDiscoveryProvider? discoveryProvider;
  final TestRunProvider? runProvider;
  final FailedTestRerunPlanner rerunPlanner;
  final RuntimeTaskLifecycleController? _runtimeTaskLifecycleController;
  final RuntimeTaskHistoryStore? _runtimeTaskHistoryStore;
  final TestRunHistoryStore? _testRunHistoryStore;
  final String runtimeTaskHistoryWorkspaceId;
  final int runtimeTaskHistoryMaxEntries;
  final String testRunHistoryWorkspaceId;
  final int testRunHistoryMaxEntries;

  TestDiscoveryResult? _discovery;
  TestRunResult? _lastRun;
  TestRunRequest? _lastRunRequest;
  TestRunConfiguration? _lastRunConfiguration;
  RuntimeTaskSnapshot? _lastRuntimeTask;
  final List<TestRunResult> _runHistory = <TestRunResult>[];
  int _discoveryGeneration = 0;
  int _runGeneration = 0;

  TestDiscoveryResult? get discovery => _discovery;
  TestRunResult? get lastRun => _lastRun;
  TestRunRequest? get lastRunRequest => _lastRunRequest;
  TestRunConfiguration? get lastRunConfiguration => _lastRunConfiguration;
  RuntimeTaskSnapshot? get lastRuntimeTask => _lastRuntimeTask;
  List<TestRunResult> get runHistory =>
      List<TestRunResult>.unmodifiable(_runHistory);
  bool get hasDiscovery => _discovery != null;
  bool get hasLastRun => _lastRun != null;

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
    _lastRun = _runHistory.isEmpty ? null : _runHistory.first;
    notifyListeners();
  }

  Future<TestDiscoveryResult> discover(TestDiscoveryRequest request) async {
    final provider = discoveryProvider;
    final generation = ++_discoveryGeneration;
    if (provider == null) {
      final result = const TestDiscoveryResult(
        providerId: 'unavailable',
        roots: <TestNode>[],
        message:
            'Test discovery provider is not configured. '
            'TODO: register Styio test discovery and external runner adapters.',
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
            'TODO: expose provider health and retry actions.',
      );
      _storeDiscovery(result, generation);
      return result;
    }
  }

  Future<TestRunResult> run(TestRunRequest request) async {
    final provider = runProvider;
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
        const TestRunResult(
          providerId: 'unavailable',
          status: TestRunStatus.error,
          message:
              'Test run provider is not configured. '
              'TODO: register Styio, CTest, and custom task adapters.',
        ),
        finishedTask,
      );
      await _storeRun(result, generation);
      return result;
    }

    try {
      final providerResult = await provider.run(request);
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
              'TODO: expose runner logs and retry actions.',
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
      notifyListeners();
      return result;
    }
    return runConfiguration(configuration);
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
      return controller.block(
        taskId,
        message: 'Test task $taskId has no runnable provider.',
        metadata: const <String, Object?>{'phase': 'provider-selection'},
      );
    }
    return controller.start(taskId, message: 'Test task $taskId started.');
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
}
