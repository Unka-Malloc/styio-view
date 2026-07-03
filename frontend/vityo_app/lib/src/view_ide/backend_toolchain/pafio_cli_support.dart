import 'dart:convert';
import 'dart:io';

import 'project_graph_contract.dart';
import 'pafio_cli_discovery.dart';

const String missingLocalPafioBinaryMessage =
    'No pafio binary was resolved. Set VITYO_PAFIO_BIN or keep styio-pafio available in the local workspace.';

enum LocalPafioCommandOutcome { blocked, succeeded, failed }

typedef PafioCommandResultFactory<T> =
    T Function({
      required LocalPafioCommandOutcome outcome,
      required String command,
      required String statusMessage,
      required String stdout,
      required String stderr,
      Map<String, dynamic>? payload,
      Map<String, dynamic>? errorPayload,
    });

T blockedPafioCommandResult<T>({
  required PafioCommandResultFactory<T> factory,
  required String command,
  required String statusMessage,
}) {
  return factory(
    outcome: LocalPafioCommandOutcome.blocked,
    command: command,
    statusMessage: statusMessage,
    stdout: '',
    stderr: '',
  );
}

List<String> pafioManifestArgs(ProjectGraphSnapshot projectGraph) {
  final manifestPath = projectGraph.manifestPath;
  if (manifestPath == null || manifestPath.isEmpty) {
    return const <String>[];
  }
  return <String>['--manifest-path', manifestPath];
}

Map<String, dynamic>? parseJsonObjectPayload(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) {
    return null;
  }

  try {
    final decoded = jsonDecode(trimmed);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Future<T> runLocalPafioCommand<T>({
  required ProjectGraphSnapshot projectGraph,
  required String command,
  required List<String> args,
  required PafioCommandResultFactory<T> factory,
  String missingBinaryMessage = missingLocalPafioBinaryMessage,
}) async {
  final pafioBinary = await resolvePafioBinary(
    workspaceRoot: projectGraph.workspaceRoot,
  );
  if (pafioBinary == null) {
    return blockedPafioCommandResult(
      factory: factory,
      command: command,
      statusMessage: missingBinaryMessage,
    );
  }

  try {
    final result = await Process.run(
      pafioBinary,
      args,
      workingDirectory: projectGraph.workspaceRoot,
    );
    final stdout = '${result.stdout}';
    final stderr = '${result.stderr}';
    final successPayload = parseJsonObjectPayload(stdout);
    final failurePayload = parseJsonObjectPayload(stderr);
    if (result.exitCode == 0) {
      return factory(
        outcome: LocalPafioCommandOutcome.succeeded,
        command: command,
        statusMessage:
            successPayload?['message'] as String? ??
            '$command completed through pafio.',
        stdout: stdout,
        stderr: stderr,
        payload: successPayload,
      );
    }

    return factory(
      outcome: LocalPafioCommandOutcome.failed,
      command: command,
      statusMessage:
          failurePayload?['message'] as String? ??
          '$command exited with code ${result.exitCode}.',
      stdout: stdout,
      stderr: stderr,
      errorPayload: failurePayload,
    );
  } on ProcessException catch (error) {
    return factory(
      outcome: LocalPafioCommandOutcome.failed,
      command: command,
      statusMessage: 'Failed to execute pafio: ${error.message}',
      stdout: '',
      stderr: '',
    );
  }
}
