import 'package:flutter/material.dart';

import '../../view_ide/commands/commands.dart';
import '../../view_ide/shell_runtime/shell_runtime.dart';
import '../native_tool_result_summary.dart';
import '../platform/viewport_profile.dart';

class TestingSurface extends StatelessWidget {
  const TestingSurface({
    super.key,
    required this.viewportProfile,
    required this.nativeToolResults,
    this.onRunTests,
    this.onOpenDiagnostics,
  });

  final ViewportProfile viewportProfile;
  final List<NativeToolResultRecord> nativeToolResults;
  final Future<void> Function()? onRunTests;
  final VoidCallback? onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final testResults = nativeToolResults
        .where((result) => result.command == AppCommandId.runTests)
        .toList(growable: false);
    final latest = testResults.isEmpty ? null : testResults.first;
    final testResult = _testResultMap(latest);
    final failedTests = _failedTests(testResult);
    final diagnosticCount = latest?.diagnostics.length ?? 0;

    return Card(
      key: const ValueKey('testing-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Testing', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Test result surface backed by the registered runTests command and native tool result records. TODO: add test discovery, test tree, per-test rerun, and debug-test launch contracts.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('test-runs ${testResults.length}')),
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
            if (latest == null)
              Text(
                'No test command has completed yet.',
                style: theme.textTheme.bodySmall,
              )
            else
              Expanded(
                child: ListView(
                  key: const ValueKey('testing-result-list'),
                  children: [
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
                    if (failedTests.isNotEmpty) ...[
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
                        ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
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
