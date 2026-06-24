import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'process_adapter.dart';
import 'process_facts.dart';
import 'process_manager.dart';
import 'process_prober.dart';
import 'process_prober_io.dart';

Future<ProcessManager> createPlatformProcessManager({
  ProcessProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.process ??
      await (prober ?? const LocalProcessProber()).probe();
  return LocalProcessManager(facts: facts, adapter: adapter?.processAdapter);
}

class LocalProcessManager implements ProcessManager {
  LocalProcessManager({required this.facts, ProcessAdapter? adapter})
    : _adapter = adapter ?? ProcessAdapter(facts),
      compatibility = (adapter ?? ProcessAdapter(facts)).adapt();

  factory LocalProcessManager.linuxDebianArmForTest() =>
      LocalProcessManager(facts: ProcessFacts.linuxDebianArm());

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
      sourceManager: 'LocalProcessManager',
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
    final stopwatch = Stopwatch()..start();
    io.Process? process;
    try {
      if (plan.standardInput != null) {
        process = await io.Process.start(
          plan.executablePath,
          plan.arguments,
          environment: plan.environment.isEmpty ? null : plan.environment,
          workingDirectory: plan.workingDirectory,
        );
        process.stdin.write(plan.standardInput);
        await process.stdin.close();
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.transform(utf8.decoder).join();
        final exitCode = await process.exitCode.timeout(plan.timeout);
        final pid = process.pid;
        stopwatch.stop();
        return ProcessCommandResult(
          status: exitCode == 0
              ? ProcessCommandStatus.succeeded
              : ProcessCommandStatus.failed,
          executablePath: plan.executablePath,
          arguments: plan.arguments,
          exitCode: exitCode,
          stdout: await stdout,
          stderr: await stderr,
          duration: stopwatch.elapsed,
          metadata: <String, Object?>{
            'pid': pid,
            'processHandleId': '$pid',
            'processHandleSource': 'LocalProcessManager',
          },
        );
      }
      final result = await io.Process.run(
        plan.executablePath,
        plan.arguments,
        environment: plan.environment.isEmpty ? null : plan.environment,
        workingDirectory: plan.workingDirectory,
      ).timeout(plan.timeout);
      stopwatch.stop();
      return ProcessCommandResult(
        status: result.exitCode == 0
            ? ProcessCommandStatus.succeeded
            : ProcessCommandStatus.failed,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
        duration: stopwatch.elapsed,
      );
    } on TimeoutException {
      process?.kill();
      stopwatch.stop();
      return ProcessCommandResult(
        status: ProcessCommandStatus.timedOut,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: stopwatch.elapsed,
        message: 'Process timed out after ${plan.timeout}.',
        metadata: <String, Object?>{
          if (process != null) 'pid': process.pid,
          if (process != null) 'processHandleId': '${process.pid}',
          if (process != null) 'processHandleSource': 'LocalProcessManager',
        },
      );
    } on Object catch (error) {
      stopwatch.stop();
      return ProcessCommandResult(
        status: ProcessCommandStatus.failed,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: null,
        stdout: '',
        stderr: error.toString(),
        duration: stopwatch.elapsed,
        message: 'Process failed before completion.',
      );
    }
  }
}
