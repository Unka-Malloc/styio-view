import 'dart:async';

import '../../../../ide/local_service/vityod_client.dart';
import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'process_adapter.dart';
import 'process_facts.dart';
import 'process_manager.dart';
import 'process_prober.dart';
import 'process_prober_io.dart';

var _globalTaskSequence = 0;

Future<ProcessManager> createPlatformProcessManager({
  ProcessProber? prober,
  PlatformContextSnapshot? platformContext,
  VityodClient? vityodClient,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.process ??
      await (prober ?? const LocalProcessProber()).probe();
  if (vityodClient == null) return UnsupportedProcessManager(facts: facts);
  return LocalProcessManager(
    facts: facts,
    client: vityodClient,
    adapter: adapter?.processAdapter,
  );
}

class LocalProcessManager implements ProcessManager {
  LocalProcessManager({
    required this.facts,
    required VityodClient client,
    ProcessAdapter? adapter,
  }) : _client = client,
       _adapter = adapter ?? ProcessAdapter(facts),
       compatibility = (adapter ?? ProcessAdapter(facts)).adapt();

  factory LocalProcessManager.linuxDebianArmForTest({
    required VityodClient client,
  }) =>
      LocalProcessManager(facts: ProcessFacts.linuxDebianArm(), client: client);

  final VityodClient _client;
  final ProcessAdapter _adapter;

  @override
  final ProcessFacts facts;

  @override
  final ProcessCompatibility compatibility;

  @override
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    return const ProcessFailureClassifier(
      sourceManager: 'VityodProcessManager',
    ).classify(result, operation: operation, recoveryHint: recoveryHint);
  }

  @override
  Future<ProcessCommandResult> run(ProcessCommandRequest request) async {
    final plan = _adapter.plan(request);
    if (!plan.supported) {
      return ProcessCommandResult(
        status: ProcessCommandStatus.blocked,
        executablePath: request.executablePath,
        arguments: request.arguments,
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
        message: plan.unsupportedMessage,
      );
    }
    if (!_client.state.canDispatch) {
      return ProcessCommandResult(
        status: ProcessCommandStatus.blocked,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
        message: 'The local service is disconnected.',
      );
    }
    final servicePrefix = request.serviceKind == ProcessServiceKind.generic
        ? 'task'
        : request.serviceKind.name;
    final typedService = request.serviceKind != ProcessServiceKind.generic;
    final taskId =
        '$servicePrefix-${_client.clientInstanceId}-${++_globalTaskSequence}';
    final stopwatch = Stopwatch()..start();
    try {
      final start = await _client.request(
        method: typedService ? '$servicePrefix.request' : 'task.start',
        idempotencyKey: 'task-start-$taskId',
        params: <String, Object?>{
          'taskId': taskId,
          if (typedService) 'action': 'start',
          'executable': plan.executablePath,
          'arguments': plan.arguments,
          'workingDirectory': plan.workingDirectory,
          'environment': plan.environment,
          'standardInput': plan.standardInput,
          'timeoutMillis': plan.timeout.inMilliseconds,
        },
      );
      _throwIfError(start);
      var pollSequence = 0;
      while (true) {
        final output = await _client.request(
          method: typedService ? '$servicePrefix.request' : 'task.output',
          idempotencyKey: 'task-output-$taskId-${++pollSequence}',
          params: <String, Object?>{
            'taskId': taskId,
            if (typedService) 'action': 'output',
          },
          deadline: const Duration(seconds: 5),
        );
        _throwIfError(output);
        if (output.params['running'] == true) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        stopwatch.stop();
        final timedOut = output.params['timedOut'] == true;
        final exitCode = output.params['exitCode'];
        final stdout = output.params['stdout'];
        final stderr = output.params['stderr'];
        final durationMillis = output.params['durationMillis'];
        if (exitCode is! int ||
            stdout is! String ||
            stderr is! String ||
            durationMillis is! int) {
          throw StateError('vityod returned an invalid task receipt');
        }
        final close = await _client.request(
          method: typedService ? '$servicePrefix.request' : 'task.close',
          idempotencyKey: 'task-close-$taskId',
          params: <String, Object?>{
            'taskId': taskId,
            if (typedService) 'action': 'close',
          },
        );
        _throwIfError(close);
        return ProcessCommandResult(
          status: timedOut
              ? ProcessCommandStatus.timedOut
              : exitCode == 0
              ? ProcessCommandStatus.succeeded
              : ProcessCommandStatus.failed,
          executablePath: plan.executablePath,
          arguments: plan.arguments,
          exitCode: exitCode,
          stdout: stdout,
          stderr: stderr,
          duration: Duration(milliseconds: durationMillis),
          message: timedOut ? 'Process timed out inside vityod.' : null,
          metadata: <String, Object?>{
            'processHandleId': taskId,
            'processHandleSource': 'vityod',
            if (output.params['stdoutTruncated'] == true)
              'stdoutTruncated': true,
            if (output.params['stderrTruncated'] == true)
              'stderrTruncated': true,
          },
        );
      }
    } on Object catch (error) {
      stopwatch.stop();
      return ProcessCommandResult(
        status: ProcessCommandStatus.failed,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: stopwatch.elapsed,
        message: 'vityod process supervision failed: $error',
      );
    }
  }
}

void _throwIfError(dynamic response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw StateError(code is String ? code : 'task_service_error');
}
