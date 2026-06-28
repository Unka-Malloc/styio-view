import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_render/testing/testing.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('testing controller routes failed-test debug cancellation', () async {
    final completer = Completer<TestRunResult>();
    final lifecycle = RuntimeTaskLifecycleController();
    final controller = TestingSessionController(
      runtimeTaskLifecycleController: lifecycle,
      runProvider: _PendingTestRunProvider(completer.future),
    );
    addTearDown(controller.dispose);
    controller.recordRunResult(
      const TestRunResult(
        providerId: 'fixture-runner',
        status: TestRunStatus.failed,
        message: 'failed',
        failedCount: 1,
        cases: <TestCaseResult>[
          TestCaseResult(
            id: 'parser.syntax',
            name: 'parser syntax',
            status: TestRunStatus.failed,
          ),
        ],
        metadata: <String, Object?>{
          'debuggerExecutablePath': '/usr/bin/lldb-dap',
          'programPath': 'build/vityo-tests',
        },
      ),
    );

    final pending = controller.rerunFailed(
      workspaceRoot: '/workspace/vityo',
      debug: true,
    );
    await Future<void>.delayed(Duration.zero);

    final planned = controller.planFailedTestDebugCancellation(
      failedTest: const <String, Object?>{
        'id': 'parser.syntax',
        'name': 'parser syntax',
      },
    );
    final cancelled = await controller.cancelFailedTestDebug(
      failedTest: const <String, Object?>{
        'id': 'parser.syntax',
        'name': 'parser syntax',
      },
    );
    completer.complete(
      const TestRunResult(
        providerId: 'fixture-runner',
        status: TestRunStatus.passed,
        message: 'late pass ignored after cancellation.',
      ),
    );
    final result = await pending;

    expect(planned.ready, isTrue);
    expect(planned.routeKind, 'lifecycle');
    expect(planned.processHandleBound, isFalse);
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.status, 'cancelled');
    expect(
      lifecycle.snapshotFor(planned.taskId)?.status,
      RuntimeTaskStatus.cancelled,
    );
    expect(result.status, TestRunStatus.notRun);
    expect(result.message, contains('cancelled'));
  });

  test(
    'testing controller forwards failed-test debug cancellation to process handle',
    () async {
      final completer = Completer<TestRunResult>();
      final lifecycle = RuntimeTaskLifecycleController();
      final handle = _FakeFailedTestDebugProcessCancellationHandle(
        handleId: 'debug-process-7',
        result: const FailedTestDebugCancellationResult.accepted(
          processTerminated: true,
          message: 'Terminated failed-test debug process.',
          metadata: <String, Object?>{'pid': 707},
        ),
      );
      final controller = TestingSessionController(
        runtimeTaskLifecycleController: lifecycle,
        runProvider: _PendingTestRunProvider(completer.future),
        failedTestDebugCancellationAdapter:
            FailedTestDebugCancellationAdapter.processHandle(handle),
      );
      addTearDown(controller.dispose);
      controller.recordRunResult(
        const TestRunResult(
          providerId: 'fixture-runner',
          status: TestRunStatus.failed,
          message: 'failed',
          failedCount: 1,
          cases: <TestCaseResult>[
            TestCaseResult(
              id: 'parser.syntax',
              name: 'parser syntax',
              status: TestRunStatus.failed,
            ),
          ],
        ),
      );

      final pending = controller.rerunFailed(
        workspaceRoot: '/workspace/vityo',
        debug: true,
      );
      await Future<void>.delayed(Duration.zero);
      final planned = controller.planFailedTestDebugCancellation(
        failedTest: const <String, Object?>{
          'id': 'parser.syntax',
          'name': 'parser syntax',
        },
      );
      final cancelled = await controller.cancelFailedTestDebug(
        failedTest: const <String, Object?>{
          'id': 'parser.syntax',
          'name': 'parser syntax',
        },
      );
      completer.complete(
        const TestRunResult(
          providerId: 'fixture-runner',
          status: TestRunStatus.passed,
          message: 'late pass ignored after cancellation.',
        ),
      );
      await pending;
      final cancellationEvent = lifecycle
          .snapshotFor(planned.taskId)
          ?.events
          .last;
      final cancellationMetadata =
          cancellationEvent?.metadata['failedTestDebugCancellation']!
              as Map<String, Object?>;
      final processMetadata =
          cancellationMetadata['metadata']! as Map<String, Object?>;

      expect(planned.processHandleBound, isTrue);
      expect(planned.processHandleId, 'debug-process-7');
      expect(planned.toJson()['routeKind'], 'process-handle');
      expect(handle.cancelledTaskIds, <String>[planned.taskId]);
      expect(handle.lastFailedTestName, 'parser syntax');
      expect(handle.lastReason, contains(planned.taskId));
      expect(cancelled.cancelled, isTrue);
      expect(
        cancelled.message,
        'Failed-test debug cancellation routed for parser syntax.',
      );
      expect(cancellationMetadata['processTerminated'], isTrue);
      expect(processMetadata['pid'], 707);
      expect(processMetadata['processHandleId'], 'debug-process-7');
    },
  );

  test(
    'testing controller resolves failed-test debug cancellation handle registry',
    () async {
      final completer = Completer<TestRunResult>();
      final lifecycle = RuntimeTaskLifecycleController();
      final handle = _FakeFailedTestDebugProcessCancellationHandle(
        handleId: 'debug-adapter-process-9',
        result: const FailedTestDebugCancellationResult.accepted(
          processTerminated: true,
          message: 'Terminated registered debug adapter process.',
          metadata: <String, Object?>{'pid': 909},
        ),
      );
      final registry = FailedTestDebugCancellationHandleRegistry()
        ..register(
          FailedTestDebugCancellationHandleRegistration(
            kind: FailedTestDebugCancellationHandleKind.debugAdapter,
            providerId: 'fixture-runner',
            handle: handle,
          ),
        );
      final controller = TestingSessionController(
        runtimeTaskLifecycleController: lifecycle,
        runProvider: _PendingTestRunProvider(completer.future),
        failedTestDebugCancellationHandleRegistry: registry,
      );
      addTearDown(controller.dispose);
      controller.recordRunResult(
        const TestRunResult(
          providerId: 'fixture-runner',
          status: TestRunStatus.failed,
          message: 'failed',
          failedCount: 1,
          cases: <TestCaseResult>[
            TestCaseResult(
              id: 'parser.syntax',
              name: 'parser syntax',
              status: TestRunStatus.failed,
            ),
          ],
        ),
      );

      final pending = controller.rerunFailed(
        workspaceRoot: '/workspace/vityo',
        debug: true,
      );
      await Future<void>.delayed(Duration.zero);
      final planned = controller.planFailedTestDebugCancellation(
        failedTest: const <String, Object?>{
          'id': 'parser.syntax',
          'name': 'parser syntax',
        },
      );
      final cancelled = await controller.cancelFailedTestDebug(
        failedTest: const <String, Object?>{
          'id': 'parser.syntax',
          'name': 'parser syntax',
        },
      );
      completer.complete(
        const TestRunResult(
          providerId: 'fixture-runner',
          status: TestRunStatus.passed,
          message: 'late pass ignored after cancellation.',
        ),
      );
      await pending;

      expect(planned.processHandleBound, isTrue);
      expect(planned.processHandleId, 'debug-adapter-process-9');
      expect(cancelled.cancelled, isTrue);
      expect(handle.cancelledTaskIds, <String>[planned.taskId]);
      expect(registry.registrationCount, 1);
      expect(registry.toJson()['registrationCount'], 1);
    },
  );

  test(
    'testing failed-test debug process binder registers runtime snapshot handles',
    () async {
      const configuration = TestRunConfiguration(
        id: 'rerun-failed',
        label: 'Rerun Failed',
        workspaceRoot: '/workspace/vityo',
        providerId: 'fixture-runner',
        debug: true,
      );
      final runtimeTask = RuntimeTaskSnapshot(
        definition: const RuntimeTaskDefinition(
          id: 'test.fixture-runner.1',
          label: 'Debug tests',
          kind: RuntimeTaskKind.debug,
          command: 'fixture-runner',
        ),
        status: RuntimeTaskStatus.running,
        statusMessage: 'Debug test task is running.',
        startedAt: DateTime.utc(2026, 5, 21, 8),
        events: <RuntimeTaskLifecycleEvent>[
          RuntimeTaskLifecycleEvent(
            taskId: 'test.fixture-runner.1',
            sequence: 1,
            status: RuntimeTaskStatus.running,
            timestamp: DateTime.utc(2026, 5, 21, 8),
            message: 'Debug adapter started.',
            metadata: const <String, Object?>{
              'processHandleId': 'debug-runtime-42',
            },
          ),
        ],
      );
      final registry = FailedTestDebugCancellationHandleRegistry();
      final terminationRequests = <FailedTestDebugProcessTerminationRequest>[];
      final binding = const FailedTestDebugProcessHandleBinder().bind(
        runtimeTask: runtimeTask,
        registry: registry,
        providerId: configuration.providerId,
        configurationId: configuration.id,
        terminate: (request) async {
          terminationRequests.add(request);
          return const FailedTestDebugCancellationResult.accepted(
            processTerminated: true,
            message: 'Bound failed-test debug process terminated.',
          );
        },
      );
      final adapter = registry.adapterFor(
        providerId: configuration.providerId,
        configurationId: configuration.id,
      );
      final route = FailedTestDebugCancellationRoute.fromState(
        runtimeTask: runtimeTask,
        configuration: configuration,
        failedTest: const <String, Object?>{
          'id': 'parser.syntax',
          'name': 'parser syntax',
        },
        processHandleId: adapter?.processHandleId ?? '',
      );

      final cancelled = await adapter!.cancel(
        route: route,
        runtimeTask: runtimeTask,
        configuration: configuration,
        failedTest: const <String, Object?>{
          'id': 'parser.syntax',
          'name': 'parser syntax',
        },
        reason: 'agent cancelled failed-test debug',
      );

      expect(binding.registered, isTrue);
      expect(binding.processHandleId, 'debug-runtime-42');
      expect(route.processHandleBound, isTrue);
      expect(cancelled.processTerminated, isTrue);
      expect(terminationRequests.single.processHandleId, 'debug-runtime-42');
      expect(
        terminationRequests.single.kind,
        FailedTestDebugCancellationHandleKind.debugAdapter,
      );
      expect(cancelled.toJson()['metadata'], isA<Map<String, Object?>>());
    },
  );

  test(
    'testing failed-test debug process binder exposes typed pid handles',
    () {
      final runtimeTask = RuntimeTaskSnapshot(
        definition: const RuntimeTaskDefinition(
          id: 'test.fixture-runner.pid',
          label: 'Debug tests',
          kind: RuntimeTaskKind.debug,
          command: 'fixture-runner',
        ),
        status: RuntimeTaskStatus.running,
        statusMessage: 'Debug test task is running.',
        startedAt: DateTime.utc(2026, 5, 21, 9),
        events: <RuntimeTaskLifecycleEvent>[
          RuntimeTaskLifecycleEvent(
            taskId: 'test.fixture-runner.pid',
            sequence: 1,
            status: RuntimeTaskStatus.running,
            timestamp: DateTime.utc(2026, 5, 21, 9),
            message: 'Debug adapter started.',
            metadata: const <String, Object?>{
              'pid': 9090,
              'managerId': 'debug-adapter',
              'processHandleSource': 'debug-adapter',
            },
          ),
        ],
      );
      final registry = FailedTestDebugCancellationHandleRegistry();
      final binding = const FailedTestDebugProcessHandleBinder().bind(
        runtimeTask: runtimeTask,
        registry: registry,
        providerId: 'fixture-runner',
        configurationId: 'rerun-failed',
        terminate: (request) async {
          return const FailedTestDebugCancellationResult.accepted(
            processTerminated: true,
            message: 'Bound failed-test debug process terminated.',
          );
        },
      );
      final processHandle =
          binding.metadata['processHandle']! as Map<String, Object?>;

      expect(binding.registered, isTrue);
      expect(binding.processHandleId, '9090');
      expect(processHandle['pid'], 9090);
      expect(processHandle['managerId'], 'debug-adapter');
      expect(processHandle['source'], 'debug-adapter');
    },
  );

  testWidgets('testing surface emits failed-test debug cancellation action', (
    tester,
  ) async {
    Map<String, Object?>? cancelledFailedTest;

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
            lastRun: const TestRunResult(
              providerId: 'ctest',
              status: TestRunStatus.failed,
              message: 'One failed.',
              failedCount: 1,
              cases: <TestCaseResult>[
                TestCaseResult(
                  id: 'parser.syntax',
                  name: 'parser syntax',
                  status: TestRunStatus.failed,
                ),
              ],
            ),
            failedDebugCancellationRoute:
                const FailedTestDebugCancellationRoute(
                  taskId: 'debug.test.rerun-failed',
                  providerId: 'ctest',
                  configurationId: 'rerun-failed',
                  failedTestName: 'parser syntax',
                  failedTestId: 'parser.syntax',
                  status: 'running',
                  ready: true,
                  cancelled: false,
                  message: 'Cancellation is ready.',
                ),
            onCancelFailedTestDebug: (failedTest) async {
              cancelledFailedTest = failedTest;
            },
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('testing-cancel-failed-debug-parser syntax')),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('testing-content-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(
      find.byKey(const ValueKey('testing-cancel-failed-debug-parser syntax')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('testing-failed-debug-cancellation-route')),
      findsOneWidget,
    );
    expect(cancelledFailedTest?['name'], 'parser syntax');
  });
}

class _PendingTestRunProvider extends TestRunProvider {
  const _PendingTestRunProvider(this.result);

  final Future<TestRunResult> result;

  @override
  String get providerId => 'fixture-runner';

  @override
  Future<TestRunResult> run(TestRunRequest request) {
    return result;
  }
}

class _FakeFailedTestDebugProcessCancellationHandle
    implements FailedTestDebugProcessCancellationHandle {
  _FakeFailedTestDebugProcessCancellationHandle({
    required this.handleId,
    required this.result,
  });

  @override
  final String handleId;

  final FailedTestDebugCancellationResult result;
  final List<String> cancelledTaskIds = <String>[];
  String lastFailedTestName = '';
  String lastReason = '';

  @override
  Future<FailedTestDebugCancellationResult> cancelFailedTestDebug({
    required FailedTestDebugCancellationRoute route,
    required RuntimeTaskSnapshot runtimeTask,
    required TestRunConfiguration? configuration,
    required Map<String, Object?> failedTest,
    required String reason,
  }) async {
    cancelledTaskIds.add(runtimeTask.definition.id);
    lastFailedTestName = route.failedTestName;
    lastReason = reason;
    return result;
  }
}
