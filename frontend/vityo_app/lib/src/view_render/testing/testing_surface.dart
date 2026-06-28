import 'package:flutter/material.dart';

import '../../view_ide/commands/commands.dart';
import '../../view_ide/shell_runtime/shell_runtime.dart';
import '../../view_ide/testing/testing.dart';
import '../native_tool_result_summary.dart';
import '../platform/viewport_profile.dart';

class TestingSurface extends StatelessWidget {
  const TestingSurface({
    super.key,
    required this.viewportProfile,
    required this.nativeToolResults,
    this.discovery,
    this.lastRun,
    this.runHistory = const <TestRunResult>[],
    this.failedRetryHistory = const <FailedTestRetryRecord>[],
    this.configurationSet,
    this.failedDebugCancellationRoute,
    this.onRunTests,
    this.onRunConfiguration,
    this.onDebugConfiguration,
    this.onCancelFailedTestDebug,
    this.onRerunFailed,
    this.onSelectRunConfiguration,
    this.onSelectFailedTest,
    this.onOpenDiagnostics,
  });

  final ViewportProfile viewportProfile;
  final List<NativeToolResultRecord> nativeToolResults;
  final TestDiscoveryResult? discovery;
  final TestRunResult? lastRun;
  final List<TestRunResult> runHistory;
  final List<FailedTestRetryRecord> failedRetryHistory;
  final TestRunConfigurationSet? configurationSet;
  final FailedTestDebugCancellationRoute? failedDebugCancellationRoute;
  final Future<void> Function()? onRunTests;
  final Future<void> Function(TestRunConfiguration configuration)?
  onRunConfiguration;
  final Future<void> Function(TestRunConfiguration configuration)?
  onDebugConfiguration;
  final Future<void> Function(Map<String, Object?> failedTest)?
  onCancelFailedTestDebug;
  final Future<void> Function()? onRerunFailed;
  final ValueChanged<TestRunConfiguration>? onSelectRunConfiguration;
  final ValueChanged<Map<String, Object?>>? onSelectFailedTest;
  final VoidCallback? onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final testResults = nativeToolResults
        .where((result) => result.command == AppCommandId.runTests)
        .toList(growable: false);
    final latest = testResults.isEmpty ? null : testResults.first;
    final testResult = lastRun?.toJson() ?? _testResultMap(latest);
    final failedTests = _failedTests(testResult);
    final diagnosticCount = latest?.diagnostics.length ?? 0;
    final selectedConfiguration = configurationSet?.selectedConfiguration;

    return Card(
      key: const ValueKey('testing-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: ListView(
          key: const ValueKey('testing-content-scroll'),
          children: [
            Text('Testing', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Test result surface backed by registered test providers, persisted run configurations, failed-test rerun planning, the runTests command, native tool result records, and debug adapter launch routing handoff.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('test-runs ${testResults.length}')),
                Chip(label: Text('history ${runHistory.length}')),
                Chip(label: Text('retries ${failedRetryHistory.length}')),
                if (configurationSet != null)
                  Chip(
                    label: Text(
                      'configs ${configurationSet!.configurations.length}',
                    ),
                  ),
                if (selectedConfiguration != null)
                  Chip(label: Text('selected ${selectedConfiguration.id}')),
                if (selectedConfiguration != null)
                  Chip(
                    label: Text(
                      selectedConfiguration.ready
                          ? 'config ready'
                          : 'config blocked',
                    ),
                  ),
                if (failedDebugCancellationRoute != null)
                  Chip(
                    label: Text(
                      'debug-cancel ${failedDebugCancellationRoute!.status}',
                    ),
                  ),
                if (discovery != null)
                  Chip(label: Text('discovered ${discovery!.testCount}')),
                Chip(label: Text('status ${testResult['status'] ?? 'none'}')),
                if (testResult['runner'] != null)
                  Chip(label: Text('runner ${testResult['runner']}')),
                if (testResult['totalCount'] != null)
                  Chip(label: Text('total ${testResult['totalCount']}')),
                if (testResult['passedCount'] != null)
                  Chip(label: Text('passed ${testResult['passedCount']}')),
                if (testResult['failedCount'] != null)
                  Chip(label: Text('failed ${testResult['failedCount']}')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('testing-run-tests'),
                  onPressed: onRunTests,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Run Tests'),
                ),
                if (selectedConfiguration != null)
                  FilledButton.tonalIcon(
                    key: const ValueKey('testing-run-selected-configuration'),
                    onPressed:
                        selectedConfiguration.ready &&
                            onRunConfiguration != null
                        ? () {
                            onRunConfiguration!(selectedConfiguration);
                          }
                        : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run Selected'),
                  ),
                if (selectedConfiguration != null)
                  OutlinedButton.icon(
                    key: const ValueKey('testing-debug-selected-configuration'),
                    onPressed:
                        selectedConfiguration.ready &&
                            onDebugConfiguration != null
                        ? () {
                            onDebugConfiguration!(selectedConfiguration);
                          }
                        : null,
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Debug Selected'),
                  ),
                if (failedTests.isNotEmpty)
                  OutlinedButton.icon(
                    key: const ValueKey('testing-rerun-failed'),
                    onPressed: onRerunFailed ?? onRunTests,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Rerun Failed'),
                  ),
                if (diagnosticCount > 0 && onOpenDiagnostics != null)
                  OutlinedButton.icon(
                    key: const ValueKey('testing-open-diagnostics'),
                    onPressed: onOpenDiagnostics,
                    icon: const Icon(Icons.report_problem_outlined),
                    label: Text('Open diagnostics ($diagnosticCount)'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (latest == null && lastRun == null && discovery == null)
              Text(
                'No test command has completed yet.',
                style: theme.textTheme.bodySmall,
              )
            else
              ListView(
                key: const ValueKey('testing-result-list'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  if (discovery != null) ...[
                    ListTile(
                      key: const ValueKey('testing-discovery-result'),
                      title: Text('Discovered ${discovery!.testCount} test(s)'),
                      subtitle: Text(
                        discovery!.message.isEmpty
                            ? 'Provider ${discovery!.providerId}'
                            : discovery!.message,
                      ),
                    ),
                    for (final root in discovery!.roots)
                      ListTile(
                        key: ValueKey('testing-discovery-${root.id}'),
                        dense: true,
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(root.label),
                        subtitle: Text(
                          '${root.kind.wireValue} · ${root.testCount} test(s)',
                        ),
                      ),
                  ],
                  if (lastRun != null)
                    ListTile(
                      key: const ValueKey('testing-provider-run-result'),
                      title: Text('Provider ${lastRun!.providerId}'),
                      subtitle: Text(lastRun!.message),
                    )
                  else if (latest != null)
                    ListTile(
                      key: const ValueKey('testing-latest-result'),
                      title: Text(latest.label),
                      subtitle: Text(
                        nativeToolMetadataSummaryText(
                              latest.metadata,
                              describeUnstructured: true,
                            ) ??
                            latest.message,
                      ),
                    ),
                  if (runHistory.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'Run History',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (final entry in runHistory.take(5))
                      ListTile(
                        key: ValueKey(
                          'testing-history-${entry.providerId}-${entry.status.wireValue}',
                        ),
                        dense: true,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(
                          entry.runner.isEmpty
                              ? entry.providerId
                              : entry.runner,
                        ),
                        subtitle: Text(
                          '${entry.status.wireValue} · ${entry.message}',
                        ),
                      ),
                  ],
                  if (failedRetryHistory.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'Failed Retry History',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (final record in failedRetryHistory.take(5))
                      ListTile(
                        key: ValueKey(
                          'testing-failed-retry-${record.providerId}-${record.status.wireValue}-${record.debug ? 'debug' : 'run'}',
                        ),
                        dense: true,
                        leading: Icon(
                          record.debug
                              ? Icons.bug_report_outlined
                              : Icons.replay_rounded,
                        ),
                        title: Text(
                          record.debug
                              ? 'Debug failed tests'
                              : 'Rerun failed tests',
                        ),
                        subtitle: Text(_failedRetrySummary(record)),
                      ),
                  ],
                  if (configurationSet?.configurations.isNotEmpty == true) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'Run Configurations',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (final configuration
                        in configurationSet!.configurations.take(6))
                      ListTile(
                        key: ValueKey(
                          'testing-run-configuration-${configuration.id}',
                        ),
                        dense: true,
                        selected:
                            configuration.id ==
                            configurationSet!.selectedConfiguration?.id,
                        leading: Icon(
                          configuration.debug
                              ? Icons.bug_report_outlined
                              : Icons.play_circle_outline,
                        ),
                        title: Text(configuration.label),
                        subtitle: Text(_configurationSummary(configuration)),
                        onTap: onSelectRunConfiguration == null
                            ? null
                            : () {
                                onSelectRunConfiguration!(configuration);
                              },
                      ),
                  ],
                  if (failedTests.isNotEmpty) ...[
                    if (failedDebugCancellationRoute != null)
                      ListTile(
                        key: const ValueKey(
                          'testing-failed-debug-cancellation-route',
                        ),
                        dense: true,
                        leading: const Icon(Icons.cancel_schedule_send),
                        title: const Text('Failed-test debug cancellation'),
                        subtitle: Text(failedDebugCancellationRoute!.message),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: 4,
                      ),
                      child: Text(
                        'Failed Tests',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    for (final failed in failedTests)
                      ListTile(
                        key: ValueKey('testing-failed-${failed['name']}'),
                        dense: true,
                        leading: const Icon(Icons.cancel_outlined),
                        title: Text('${failed['name'] ?? 'unknown'}'),
                        subtitle: Text('${failed['status'] ?? 'failed'}'),
                        trailing: onCancelFailedTestDebug == null
                            ? null
                            : IconButton(
                                key: ValueKey(
                                  'testing-cancel-failed-debug-${failed['name']}',
                                ),
                                tooltip: 'Cancel failed-test debug',
                                icon: const Icon(Icons.stop_circle_outlined),
                                onPressed: () {
                                  onCancelFailedTestDebug!(failed);
                                },
                              ),
                        onTap: onSelectFailedTest == null
                            ? null
                            : () {
                                onSelectFailedTest!(failed);
                              },
                      ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _failedRetrySummary(FailedTestRetryRecord record) {
  final parts = <String>[
    record.status.wireValue,
    if (record.providerId.isNotEmpty) record.providerId,
    if (record.filter.isNotEmpty) 'filter ${record.filter}',
    'failed ${record.failedCount}',
  ];
  return parts.join(' · ');
}

String _configurationSummary(TestRunConfiguration configuration) {
  final parts = <String>[
    configuration.ready ? 'ready' : 'blocked',
    if (configuration.providerId.isNotEmpty) configuration.providerId,
    if (configuration.targetId.isNotEmpty) 'target ${configuration.targetId}',
    if (configuration.filter.isNotEmpty) 'filter ${configuration.filter}',
    if (configuration.debug) 'debug',
  ];
  return parts.join(' · ');
}

Map<String, Object?> _testResultMap(NativeToolResultRecord? result) {
  final value = result?.metadata['testResult'];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _failedTests(Map<String, Object?> testResult) {
  final value = testResult['failedTests'];
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  return value
      .whereType<Map>()
      .map(
        (entry) => entry.map((key, value) => MapEntry(key.toString(), value)),
      )
      .toList(growable: false);
}
