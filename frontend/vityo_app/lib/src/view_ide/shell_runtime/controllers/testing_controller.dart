import 'package:flutter/foundation.dart';

import '../../runtime/runtime.dart';
import '../../testing/testing.dart';

class ShellTestingController extends ChangeNotifier {
  ShellTestingController({
    required this.sessionController,
    required this.workspaceRoot,
    required this.runTestsFallback,
    required this.runtimeOutputBuffer,
    required this.log,
  });

  final TestingSessionController? sessionController;
  final String Function() workspaceRoot;
  final Future<void> Function() runTestsFallback;
  final RuntimeOutputLiveBuffer runtimeOutputBuffer;
  final void Function(String message) log;

  String _selectedConfigurationId = '';

  TestDiscoveryResult? get discovery => sessionController?.discovery;
  TestRunResult? get lastRun => sessionController?.lastRun;
  List<TestRunResult> get runHistory =>
      sessionController?.runHistory ?? const <TestRunResult>[];
  List<FailedTestRetryRecord> get failedRetryHistory =>
      sessionController?.failedRetryHistory ?? const <FailedTestRetryRecord>[];
  FailedTestDebugCancellationRoute? get failedDebugCancellationRoute =>
      sessionController?.lastFailedDebugCancellationRoute;

  TestRunConfigurationSet get configurationSet {
    final root = workspaceRoot();
    final providerId = lastRun?.providerId ?? 'native-tool-runTests';
    final configurations = <TestRunConfiguration>[
      TestRunConfiguration(
        id: 'all-tests',
        label: 'All Tests',
        workspaceRoot: root,
        providerId: providerId,
      ),
    ];
    final failedDebugConfiguration = sessionController?.rerunPlanner.plan(
      lastRun: lastRun,
      workspaceRoot: root,
      debug: true,
    );
    if (failedDebugConfiguration != null) {
      configurations.add(failedDebugConfiguration);
    }
    final selectedId =
        configurations.any(
          (configuration) => configuration.id == _selectedConfigurationId,
        )
        ? _selectedConfigurationId
        : configurations.first.id;
    return TestRunConfigurationSet(
      workspaceId: root,
      selectedConfigurationId: selectedId,
      configurations: List<TestRunConfiguration>.unmodifiable(configurations),
    );
  }

  TestRunConfiguration? configurationForId(String configurationId) {
    final normalizedId = configurationId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final configuration in configurationSet.configurations) {
      if (configuration.id == normalizedId) {
        return configuration;
      }
    }
    return null;
  }

  void selectConfiguration(TestRunConfiguration configuration) {
    _selectedConfigurationId = configuration.id;
    log('Selected test run configuration ${configuration.id}.');
    notifyListeners();
  }

  Future<void> rerunFailed() async {
    final controller = sessionController;
    if (controller == null || controller.runProvider == null) {
      await runTestsFallback();
      return;
    }
    final result = await controller.rerunFailed(workspaceRoot: workspaceRoot());
    log(resultMessage('Rerun failed tests', result));
    notifyListeners();
  }

  Future<void> debugFailed() async {
    final controller = sessionController;
    if (controller == null || controller.runProvider == null) {
      await rerunFailed();
      return;
    }
    final result = await controller.rerunFailed(
      workspaceRoot: workspaceRoot(),
      debug: true,
    );
    log(resultMessage('Debug failed tests', result));
    notifyListeners();
  }

  Future<void> runConfiguration(TestRunConfiguration configuration) async {
    final controller = sessionController;
    if (controller == null) {
      await runTestsFallback();
      return;
    }
    final result = await controller.runConfiguration(configuration);
    log(resultMessage('Run test configuration', result));
    notifyListeners();
  }

  Future<void> debugConfiguration(TestRunConfiguration configuration) async {
    final debugConfiguration = configuration.debug
        ? configuration
        : configuration.copyWith(debug: true);
    final route = const TestDebugLaunchRoutePlanner().plan(debugConfiguration);
    runtimeOutputBuffer.addEvent(
      RuntimeOutputEvent(
        channelId: route.handoff.outputChannelId ?? 'debug.tests',
        label: 'Test Debug',
        kind: RuntimeOutputChannelKind.debug,
        message:
            '${route.ready ? 'ready' : 'blocked'} ${route.profileId}: ${route.handoff.plan.message}',
        timestamp: DateTime.now().toUtc(),
        metadata: <String, Object?>{
          'testDebugLaunchRoute': route.toJson(),
          'configuration': debugConfiguration.toJson(),
        },
      ),
    );
    final controller = sessionController;
    if (controller == null) {
      log('Debug test configuration routed: ${route.profileId}.');
      notifyListeners();
      return;
    }
    final result = await controller.debugConfiguration(debugConfiguration);
    log(resultMessage('Debug test configuration', result));
    notifyListeners();
  }

  Future<void> cancelFailedDebug(Map<String, Object?> failedTest) async {
    final controller = sessionController;
    if (controller == null) {
      log('Failed-test debug cancellation skipped: no test controller.');
      notifyListeners();
      return;
    }
    final route = await controller.cancelFailedTestDebug(
      failedTest: failedTest,
    );
    log(route.message);
    notifyListeners();
  }

  String resultMessage(String action, TestRunResult result) {
    return '$action: ${result.status.wireValue} · ${result.message}';
  }

  bool agentCommandApplied(TestRunResult? result) {
    return result != null && result.status != TestRunStatus.notRun;
  }

  Map<String, Object?> agentCommandMetadata(TestRunResult? result) {
    return <String, Object?>{
      if (result != null) 'testResult': result.toJson(),
      'failedRetryHistory': failedRetryHistory
          .map((record) => record.toJson())
          .toList(growable: false),
    };
  }

  Map<String, Object?> configurationCommandMetadata({
    TestRunConfiguration? configuration,
    TestRunResult? result,
  }) {
    return <String, Object?>{
      'availableConfigurationIds': configurationSet.configurations
          .map((configuration) => configuration.id)
          .toList(growable: false),
      if (configuration != null) 'configuration': configuration.toJson(),
      ...agentCommandMetadata(result),
    };
  }

  void recordNativeToolResult({
    required String message,
    required Object? metadata,
  }) {
    final controller = sessionController;
    if (controller == null) {
      return;
    }
    final normalized = switch (metadata) {
      Map<String, Object?> value => value,
      Map value => value.map((key, value) => MapEntry(key.toString(), value)),
      _ => null,
    };
    if (normalized == null) {
      return;
    }
    controller.recordRunResult(
      _testRunResultFromNativeToolMetadata(normalized, message: message),
    );
  }

  TestRunResult _testRunResultFromNativeToolMetadata(
    Map<String, Object?> metadata, {
    required String message,
  }) {
    return TestRunResult(
      providerId: 'native-tool-runTests',
      runner: metadata['runner']?.toString() ?? 'native-tool',
      status: _testRunStatusFromNativeToolMetadata(metadata['status']),
      message: message,
      totalCount: _intFromNativeToolMetadata(metadata['totalCount']) ?? 0,
      passedCount: _intFromNativeToolMetadata(metadata['passedCount']) ?? 0,
      failedCount: _intFromNativeToolMetadata(metadata['failedCount']) ?? 0,
      skippedCount: _intFromNativeToolMetadata(metadata['skippedCount']) ?? 0,
      cases: _failedTestCasesFromNativeToolMetadata(metadata),
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  List<TestCaseResult> _failedTestCasesFromNativeToolMetadata(
    Map<String, Object?> metadata,
  ) {
    final value = metadata['failedTests'];
    if (value is! List) {
      return const <TestCaseResult>[];
    }
    return value
        .whereType<Map>()
        .map((entry) {
          final normalized = entry.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return TestCaseResult(
            id: normalized['id']?.toString() ?? '',
            name: normalized['name']?.toString() ?? 'unknown',
            status: _testRunStatusFromNativeToolMetadata(
              normalized['status'] ?? 'failed',
            ),
            message: normalized['message']?.toString() ?? '',
          );
        })
        .toList(growable: false);
  }

  TestRunStatus _testRunStatusFromNativeToolMetadata(Object? value) {
    return switch (value?.toString()) {
      'passed' => TestRunStatus.passed,
      'failed' => TestRunStatus.failed,
      'skipped' => TestRunStatus.skipped,
      'not-run' || 'blocked' => TestRunStatus.notRun,
      _ => TestRunStatus.error,
    };
  }

  int? _intFromNativeToolMetadata(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
