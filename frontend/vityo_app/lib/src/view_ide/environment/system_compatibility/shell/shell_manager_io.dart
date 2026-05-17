import 'dart:async';
import 'dart:io';

import '../../configuration/shell_configuration.dart';
import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'shell_adapter.dart';
import 'shell_facts.dart';
import 'shell_manager.dart';
import 'shell_prober.dart';
import 'shell_prober_io.dart';

Future<ShellManager> createPlatformShellManager({
  ShellProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null ? null : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.shell ?? await (prober ?? const LocalShellProber()).probe();
  return LocalShellManager(facts: facts, adapter: adapter?.shellAdapter);
}

class LocalShellManager implements ShellManager {
  LocalShellManager({
    required this.facts,
    ShellAdapter? adapter,
  }) : _adapter = adapter ?? ShellAdapter(facts),
       compatibility = (adapter ?? ShellAdapter(facts)).adapt();

  factory LocalShellManager.linuxDebianArmForTest({
    String shellPath = '/bin/sh',
  }) {
    return LocalShellManager(
      facts: ShellFacts.linuxDebianArm(defaultShellPath: shellPath),
    );
  }

  final ShellAdapter _adapter;

  @override
  final ShellFacts facts;

  @override
  final ShellCompatibility compatibility;

  @override
  ShellOperationFailure? failureFor(
    ShellCommandResult result, {
    String operation = 'shell.run',
    String? recoveryHint,
  }) {
    return const ShellFailureClassifier(
      sourceManager: 'LocalShellManager',
    ).classify(
      result,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<ShellCommandResult> run(
    ShellCommandRequest request, {
    ShellConfiguration? configuration,
  }) async {
    final plan = _adapter.plan(request, configuration: configuration);
    if (!plan.supported) {
      return ShellCommandResult(
        status: ShellCommandStatus.blocked,
        command: request.command,
        executablePath: '',
        arguments: const <String>[],
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
        message: plan.unsupportedMessage,
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final result = await Process.run(
        plan.executablePath,
        plan.arguments,
        workingDirectory: plan.workingDirectory,
        environment: plan.environment.isEmpty ? null : plan.environment,
      ).timeout(plan.timeout);
      stopwatch.stop();
      return ShellCommandResult(
        status: result.exitCode == 0
            ? ShellCommandStatus.succeeded
            : ShellCommandStatus.failed,
        command: request.command,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
        duration: stopwatch.elapsed,
      );
    } on TimeoutException {
      stopwatch.stop();
      return ShellCommandResult(
        status: ShellCommandStatus.timedOut,
        command: request.command,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: null,
        stdout: '',
        stderr: '',
        duration: stopwatch.elapsed,
        message: 'Shell command timed out after ${plan.timeout}.',
      );
    } on Object catch (error) {
      stopwatch.stop();
      return ShellCommandResult(
        status: ShellCommandStatus.failed,
        command: request.command,
        executablePath: plan.executablePath,
        arguments: plan.arguments,
        exitCode: null,
        stdout: '',
        stderr: error.toString(),
        duration: stopwatch.elapsed,
        message: 'Shell command failed before process completion.',
      );
    }
  }
}
