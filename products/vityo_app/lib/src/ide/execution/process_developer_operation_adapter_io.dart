import 'dart:async';

import '../local_service/vityod_client.dart';
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
    required VityodClient client,
    this.maxOutputCodeUnits = 4096,
    this.diagnosticDecoder,
  }) : _client = client,
       capabilities = List<IdeCapabilityFact>.unmodifiable(capabilities),
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
  final VityodClient _client;

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

    final taskId = 'developer-${context.operationId}-${++_taskSequence}';
    try {
      final start = await _client.request(
        method: 'task.start',
        idempotencyKey: 'developer-start-$taskId',
        params: <String, Object?>{
          'taskId': taskId,
          'executable': executable,
          'arguments': arguments,
          'workingDirectory': workingDirectory,
          'timeoutMillis': 30 * 60 * 1000,
        },
      );
      _throwIfError(start);
    } on Object {
      return const DeveloperOperationResult(
        status: ExecutionReceiptStatus.blocked,
        provenance: 'vityod-process-adapter',
        message: 'Configured process adapter is unavailable.',
      );
    }

    var pollSequence = 0;
    while (true) {
      if (context.cancellation.isCancelled) {
        final cancelled = await _client.request(
          method: 'task.cancel',
          idempotencyKey: 'developer-cancel-$taskId',
          params: <String, Object?>{'taskId': taskId},
        );
        _throwIfError(cancelled);
        final output = await _readOutput(taskId, ++pollSequence);
        await _close(taskId);
        final exitCode = output.params['exitCode'];
        final stdout = _boundedText(output.params['stdout']);
        final stderr = _boundedText(output.params['stderr']);
        return DeveloperOperationResult(
          status: ExecutionReceiptStatus.cancelled,
          provenance: 'vityod-process-adapter',
          message: 'Operation was cancelled.',
          exitCode: exitCode is int ? exitCode : null,
          output: stdout,
          errorOutput: stderr,
        );
      }
      final output = await _readOutput(taskId, ++pollSequence);
      if (output.params['running'] == true) {
        await Future.any<void>(<Future<void>>[
          Future<void>.delayed(const Duration(milliseconds: 10)),
          context.cancellation.whenCancelled,
        ]);
        continue;
      }
      final exitCode = output.params['exitCode'];
      if (exitCode is! int) {
        await _close(taskId);
        return const DeveloperOperationResult(
          status: ExecutionReceiptStatus.failed,
          provenance: 'vityod-process-adapter',
          message: 'The daemon returned an invalid task receipt.',
        );
      }
      final stdout = _boundedText(output.params['stdout']);
      final stderr = _boundedText(output.params['stderr']);
      await _close(taskId);
      return DeveloperOperationResult(
        status: exitCode == 0
            ? ExecutionReceiptStatus.succeeded
            : ExecutionReceiptStatus.failed,
        provenance: 'vityod-process-adapter',
        message: exitCode == 0
            ? 'Process completed successfully.'
            : 'Process exited with a non-zero status.',
        exitCode: exitCode,
        output: stdout,
        errorOutput: stderr,
        diagnostics: diagnosticDecoder?.decode(
          output: stdout,
          errorOutput: stderr,
          exitCode: exitCode,
        ),
      );
    }
  }

  Future<dynamic> _readOutput(String taskId, int sequence) async {
    final response = await _client.request(
      method: 'task.output',
      idempotencyKey: 'developer-output-$taskId-$sequence',
      params: <String, Object?>{'taskId': taskId},
      deadline: const Duration(seconds: 5),
    );
    _throwIfError(response);
    return response;
  }

  Future<void> _close(String taskId) async {
    final response = await _client.request(
      method: 'task.close',
      idempotencyKey: 'developer-close-$taskId',
      params: <String, Object?>{'taskId': taskId},
    );
    _throwIfError(response);
  }

  BoundedText _boundedText(Object? value) {
    final text = value is String ? value : '';
    if (text.length <= maxOutputCodeUnits) {
      return BoundedText(text: text, omittedCodeUnits: 0);
    }
    var accepted = maxOutputCodeUnits;
    if (accepted > 0) {
      final last = text.codeUnitAt(accepted - 1);
      if (last >= 0xD800 && last <= 0xDBFF) accepted -= 1;
    }
    return BoundedText(
      text: text.substring(0, accepted),
      omittedCodeUnits: text.length - accepted,
    );
  }
}

var _taskSequence = 0;

void _throwIfError(dynamic response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw StateError(code is String ? code : 'task_service_error');
}
