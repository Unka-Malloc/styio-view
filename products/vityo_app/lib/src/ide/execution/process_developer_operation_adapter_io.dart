import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../language/dart_analyze_diagnostic_decoder.dart';
import '../workbench/capability_snapshot.dart';
import 'developer_operation_adapter.dart';
import 'execution_receipt.dart';

final class ProcessDeveloperOperationAdapter
    implements DeveloperOperationAdapter {
  ProcessDeveloperOperationAdapter({
    required this.kind,
    required Iterable<IdeCapabilityFact> capabilities,
    required this.executable,
    required List<String> arguments,
    required this.workingDirectory,
    this.maxOutputCodeUnits = 4096,
    this.diagnosticDecoder,
  }) : capabilities = List<IdeCapabilityFact>.unmodifiable(capabilities),
       arguments = List<String>.unmodifiable(arguments) {
    if (this.capabilities.isEmpty) {
      throw ArgumentError.value(
        capabilities,
        'capabilities',
        'must not be empty',
      );
    }
    if (executable.trim().isEmpty || workingDirectory.trim().isEmpty) {
      throw ArgumentError(
        'Executable and working directory must not be empty.',
      );
    }
    if (maxOutputCodeUnits < 0) {
      throw ArgumentError.value(
        maxOutputCodeUnits,
        'maxOutputCodeUnits',
        'must not be negative',
      );
    }
  }

  @override
  final DeveloperOperationKind kind;

  @override
  final List<IdeCapabilityFact> capabilities;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final int maxOutputCodeUnits;
  final DeveloperDiagnosticDecoder? diagnosticDecoder;

  @override
  Future<DeveloperOperationResult> execute(
    DeveloperOperationContext context,
  ) async {
    if (context.cancellation.isCancelled) {
      return const DeveloperOperationResult(
        status: ExecutionReceiptStatus.cancelled,
        provenance: 'process-adapter',
        message: 'Operation was cancelled before process launch.',
      );
    }

    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    } on ProcessException {
      return const DeveloperOperationResult(
        status: ExecutionReceiptStatus.blocked,
        provenance: 'process-adapter',
        message: 'Configured process adapter is unavailable.',
      );
    }

    final output = _BoundedOutputCollector(maxOutputCodeUnits);
    final errorOutput = _BoundedOutputCollector(maxOutputCodeUnits);
    final outputDone = output.collect(process.stdout);
    final errorDone = errorOutput.collect(process.stderr);

    final completion =
        await Future.any<_ProcessCompletion>(<Future<_ProcessCompletion>>[
          process.exitCode.then((_) => const _ProcessCompletion.exited()),
          context.cancellation.whenCancelled.then(
            (_) => const _ProcessCompletion.cancelled(),
          ),
        ]);
    if (completion.cancelled) {
      process.kill();
    }
    final exitCode = await process.exitCode;
    await Future.wait<void>(<Future<void>>[outputDone, errorDone]);

    if (completion.cancelled) {
      return DeveloperOperationResult(
        status: ExecutionReceiptStatus.cancelled,
        provenance: 'process-adapter',
        message: 'Operation was cancelled.',
        exitCode: exitCode,
        output: output.value,
        errorOutput: errorOutput.value,
      );
    }
    final boundedOutput = output.value;
    final boundedErrorOutput = errorOutput.value;
    return DeveloperOperationResult(
      status: exitCode == 0
          ? ExecutionReceiptStatus.succeeded
          : ExecutionReceiptStatus.failed,
      provenance: 'process-adapter',
      message: exitCode == 0
          ? 'Process completed successfully.'
          : 'Process exited with a non-zero status.',
      exitCode: exitCode,
      output: boundedOutput,
      errorOutput: boundedErrorOutput,
      diagnostics: diagnosticDecoder?.decode(
        output: boundedOutput,
        errorOutput: boundedErrorOutput,
        exitCode: exitCode,
      ),
    );
  }
}

final class _ProcessCompletion {
  const _ProcessCompletion.exited() : cancelled = false;

  const _ProcessCompletion.cancelled() : cancelled = true;

  final bool cancelled;
}

final class _BoundedOutputCollector {
  _BoundedOutputCollector(this.limit);

  final int limit;
  final StringBuffer _buffer = StringBuffer();
  var _written = 0;
  var _omitted = 0;

  Future<void> collect(Stream<List<int>> stream) async {
    await for (final chunk in stream.transform(utf8.decoder)) {
      final remaining = limit - _written;
      if (remaining <= 0) {
        _omitted += chunk.length;
        continue;
      }
      var accepted = chunk.length < remaining ? chunk.length : remaining;
      if (accepted > 0) {
        final last = chunk.codeUnitAt(accepted - 1);
        if (last >= 0xD800 && last <= 0xDBFF) {
          accepted -= 1;
        }
      }
      if (accepted > 0) {
        _buffer.write(chunk.substring(0, accepted));
        _written += accepted;
      }
      _omitted += chunk.length - accepted;
    }
  }

  BoundedText get value =>
      BoundedText(text: _buffer.toString(), omittedCodeUnits: _omitted);
}
