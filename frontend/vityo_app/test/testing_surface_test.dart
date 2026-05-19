import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/testing/testing.dart';

void main() {
  testWidgets('testing surface renders latest test result and actions', (
    tester,
  ) async {
    var runCount = 0;
    var rerunFailedCount = 0;
    var diagnosticsOpenCount = 0;
    Map<String, Object?>? selectedFailedTest;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TestingSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            nativeToolResults: <NativeToolResultRecord>[
              NativeToolResultRecord(
                command: AppCommandId.runTests,
                label: 'Run Tests',
                applied: false,
                message: 'Run Tests failed.',
                metadata: const <String, Object?>{
                  'testResult': <String, Object?>{
                    'runner': 'ctest',
                    'status': 'failed',
                    'totalCount': 2,
                    'passedCount': 1,
                    'failedCount': 1,
                    'failedTests': <Map<String, Object?>>[
                      <String, Object?>{
                        'name': 'parser rejects invalid resource',
                        'status': 'failed',
                      },
                    ],
                  },
                },
                diagnostics: const <Diagnostic>[
                  Diagnostic(
                    severity: DiagnosticSeverity.error,
                    code: 'test-failed',
                    message: 'A test failed.',
                    range: SourceRange(start: 0, end: 1),
                  ),
                ],
                completedAt: DateTime.utc(2026, 5, 20),
              ),
            ],
            runHistory: const <TestRunResult>[
              TestRunResult(
                providerId: 'ctest',
                runner: 'ctest',
                status: TestRunStatus.failed,
                message: 'One test failed.',
                totalCount: 2,
                passedCount: 1,
                failedCount: 1,
              ),
            ],
            onRunTests: () async {
              runCount += 1;
            },
            onRerunFailed: () async {
              rerunFailedCount += 1;
            },
            onSelectFailedTest: (failedTest) {
              selectedFailedTest = failedTest;
            },
            onOpenDiagnostics: () {
              diagnosticsOpenCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('testing-surface')), findsOneWidget);
    expect(find.text('Testing'), findsOneWidget);
    expect(find.text('test-runs 1'), findsOneWidget);
    expect(find.text('history 1'), findsOneWidget);
    expect(find.text('status failed'), findsOneWidget);
    expect(find.text('runner ctest'), findsOneWidget);
    expect(find.text('total 2'), findsOneWidget);
    expect(find.text('passed 1'), findsOneWidget);
    expect(find.text('failed 1'), findsOneWidget);
    expect(find.text('Run History'), findsOneWidget);
    expect(find.text('parser rejects invalid resource'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('testing-run-tests')));
    await tester.tap(find.byKey(const ValueKey('testing-rerun-failed')));
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('testing-failed-parser rejects invalid resource'),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey('testing-failed-parser rejects invalid resource'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('testing-open-diagnostics')));
    await tester.pump();

    expect(runCount, 1);
    expect(rerunFailedCount, 1);
    expect(selectedFailedTest?['name'], 'parser rejects invalid resource');
    expect(diagnosticsOpenCount, 1);
  });

  testWidgets('testing surface renders provider discovery and run state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TestingSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            nativeToolResults: const <NativeToolResultRecord>[],
            discovery: const TestDiscoveryResult(
              providerId: 'static-discovery',
              roots: <TestNode>[
                TestNode(
                  id: 'suite:styio',
                  label: 'Styio',
                  kind: TestNodeKind.suite,
                  children: <TestNode>[
                    TestNode(
                      id: 'test:syntax',
                      label: 'syntax fixture',
                      kind: TestNodeKind.test,
                    ),
                  ],
                ),
              ],
            ),
            lastRun: const TestRunResult(
              providerId: 'static-runner',
              runner: 'fixture',
              status: TestRunStatus.passed,
              message: 'Fixture tests passed.',
              totalCount: 1,
              passedCount: 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('discovered 1'), findsOneWidget);
    expect(find.text('status passed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('testing-discovery-result')),
      findsOneWidget,
    );
    expect(find.text('Styio'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('testing-provider-run-result')),
      findsOneWidget,
    );
  });
}
