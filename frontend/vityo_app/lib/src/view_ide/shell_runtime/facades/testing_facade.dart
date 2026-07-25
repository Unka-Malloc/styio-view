part of '../shell_runtime_model.dart';

/// Public testing facade backed by the testing domain controller.
mixin ShellRuntimeTestingFacade on ShellRuntimeFacadeHost {
  TestDiscoveryResult? get testDiscovery => _testingController.discovery;
  TestRunResult? get lastTestRun => _testingController.lastRun;
  List<TestRunResult> get testRunHistory => _testingController.runHistory;
  List<FailedTestRetryRecord> get failedTestRetryHistory =>
      _testingController.failedRetryHistory;
  FailedTestDebugCancellationRoute? get failedDebugCancellationRoute =>
      _testingController.failedDebugCancellationRoute;
  TestRunConfigurationSet get testRunConfigurationSet =>
      _testingController.configurationSet;

  Future<void> rerunFailedTests() => _testingController.rerunFailed();

  Future<void> debugFailedTests() => _testingController.debugFailed();

  void selectTestRunConfiguration(TestRunConfiguration configuration) =>
      _testingController.selectConfiguration(configuration);

  Future<void> runTestConfiguration(TestRunConfiguration configuration) =>
      _testingController.runConfiguration(configuration);

  Future<void> debugTestConfiguration(TestRunConfiguration configuration) =>
      _testingController.debugConfiguration(configuration);

  Future<void> cancelFailedTestDebug(Map<String, Object?> failedTest) =>
      _testingController.cancelFailedDebug(failedTest);
}
