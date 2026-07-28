import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/testing_controller.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';

void main() {
  test('native CTest receipt becomes typed testing session result', () {
    final sessionController = TestingSessionController();
    final outputBuffer = RuntimeOutputLiveBuffer();
    final controller = ShellTestingController(
      sessionController: sessionController,
      workspaceRoot: () => '/workspace',
      runTestsFallback: () async {},
      runtimeOutputBuffer: outputBuffer,
      log: (_) {},
    );
    addTearDown(controller.dispose);
    addTearDown(sessionController.dispose);
    addTearDown(outputBuffer.dispose);

    controller.recordNativeToolResult(
      message: 'Run Tests failed.',
      metadata: <String, Object?>{
        'runner': 'ctest',
        'status': 'failed',
        'totalCount': '2',
        'passedCount': 1,
        'failedCount': 1.0,
        'failedTests': <Map<Object?, Object?>>[
          <Object?, Object?>{
            'id': 'parser',
            'name': 'parser_test',
            'status': 'failed',
            'message': 'assertion failed',
          },
        ],
      },
    );

    final result = sessionController.lastRun;
    expect(result, isNotNull);
    expect(result?.providerId, 'native-tool-runTests');
    expect(result?.runner, 'ctest');
    expect(result?.status, TestRunStatus.failed);
    expect(result?.totalCount, 2);
    expect(result?.passedCount, 1);
    expect(result?.failedCount, 1);
    expect(result?.cases.single.id, 'parser');
    expect(result?.cases.single.message, 'assertion failed');
  });

  test('native non-map metadata is ignored honestly', () {
    final sessionController = TestingSessionController();
    final outputBuffer = RuntimeOutputLiveBuffer();
    final controller = ShellTestingController(
      sessionController: sessionController,
      workspaceRoot: () => '/workspace',
      runTestsFallback: () async {},
      runtimeOutputBuffer: outputBuffer,
      log: (_) {},
    );
    addTearDown(controller.dispose);
    addTearDown(sessionController.dispose);
    addTearDown(outputBuffer.dispose);

    controller.recordNativeToolResult(
      message: 'Malformed result.',
      metadata: 'not-a-map',
    );

    expect(sessionController.lastRun, isNull);
  });
}
