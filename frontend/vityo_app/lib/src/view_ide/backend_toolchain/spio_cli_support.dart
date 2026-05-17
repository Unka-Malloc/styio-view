import 'dart:convert';
import 'dart:io';

import 'project_graph_contract.dart';
import 'spio_cli_discovery.dart';

const String missingLocalSpioBinaryMessage =
    'No spio binary was resolved. Set VITYO_SPIO_BIN or keep styio-spio available in the local workspace.';

enum LocalSpioCommandOutcome { blocked, succeeded, failed }

typedef SpioCommandResultFactory<T> =
    T Function({
      required LocalSpioCommandOutcome outcome,
      required String command,
      required String statusMessage,
      required String stdout,
      required String stderr,
      Map<String, dynamic>? payload,
      Map<String, dynamic>? errorPayload,
    });

T blockedSpioCommandResult<T>({
  required SpioCommandResultFactory<T> factory,
  required String command,
  required String statusMessage,
}) {
  return factory(
    outcome: LocalSpioCommandOutcome.blocked,
    command: command,
    statusMessage: statusMessage,
    stdout: '',
    stderr: '',
  );
}

List<String> spioManifestArgs(ProjectGraphSnapshot projectGraph) {
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

Future<T> runLocalSpioCommand<T>({
  required ProjectGraphSnapshot projectGraph,
  required String command,
  required List<String> args,
  required SpioCommandResultFactory<T> factory,
  String missingBinaryMessage = missingLocalSpioBinaryMessage,
}) async {
  final spioBinary = await resolveSpioBinary(
    workspaceRoot: projectGraph.workspaceRoot,
  );
  if (spioBinary == null) {
    return blockedSpioCommandResult(
      factory: factory,
      command: command,
      statusMessage: missingBinaryMessage,
    );
  }

  try {
    final result = await Process.run(
      spioBinary,
      args,
      workingDirectory: projectGraph.workspaceRoot,
    );
    final stdout = '${result.stdout}';
    final stderr = '${result.stderr}';
    final successPayload = parseJsonObjectPayload(stdout);
    final failurePayload = parseJsonObjectPayload(stderr);
    if (result.exitCode == 0) {
      return factory(
        outcome: LocalSpioCommandOutcome.succeeded,
        command: command,
        statusMessage:
            successPayload?['message'] as String? ??
            '$command completed through spio.',
        stdout: stdout,
        stderr: stderr,
        payload: successPayload,
      );
    }

    return factory(
      outcome: LocalSpioCommandOutcome.failed,
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
      outcome: LocalSpioCommandOutcome.failed,
      command: command,
      statusMessage: 'Failed to execute spio: ${error.message}',
      stdout: '',
      stderr: '',
    );
  }
}
