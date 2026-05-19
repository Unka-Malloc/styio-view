import 'package:flutter/foundation.dart';

import 'testing_provider.dart';

class TestingSessionController extends ChangeNotifier {
  TestingSessionController({this.discoveryProvider, this.runProvider});

  final TestDiscoveryProvider? discoveryProvider;
  final TestRunProvider? runProvider;

  TestDiscoveryResult? _discovery;
  TestRunResult? _lastRun;
  final List<TestRunResult> _runHistory = <TestRunResult>[];
  int _discoveryGeneration = 0;
  int _runGeneration = 0;

  TestDiscoveryResult? get discovery => _discovery;
  TestRunResult? get lastRun => _lastRun;
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
    _storeRunResult(result);
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
    if (provider == null) {
      final result = const TestRunResult(
        providerId: 'unavailable',
        status: TestRunStatus.error,
        message:
            'Test run provider is not configured. '
            'TODO: register Styio, CTest, and custom task adapters.',
      );
      _storeRun(result, generation);
      return result;
    }

    try {
      final result = await provider.run(request);
      _storeRun(result, generation);
      return result;
    } on Object catch (error) {
      final result = TestRunResult(
        providerId: provider.providerId,
        status: TestRunStatus.error,
        message:
            'Test run unavailable: $error. '
            'TODO: expose runner logs and retry actions.',
      );
      _storeRun(result, generation);
      return result;
    }
  }

  void clear() {
    if (_discovery == null && _lastRun == null) {
      return;
    }
    _discoveryGeneration++;
    _runGeneration++;
    _discovery = null;
    _lastRun = null;
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

  void _storeRun(TestRunResult result, int generation) {
    if (generation != _runGeneration) {
      return;
    }
    _storeRunResult(result);
    notifyListeners();
  }

  void _storeRunResult(TestRunResult result) {
    _lastRun = result;
    _runHistory.insert(0, result);
    if (_runHistory.length > 20) {
      _runHistory.removeRange(20, _runHistory.length);
    }
  }
}
