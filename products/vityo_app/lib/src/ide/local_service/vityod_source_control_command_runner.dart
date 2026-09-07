import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../workspace/source_control_status.dart';
import 'vityod_client.dart';

final class VityodSourceControlCommandRunner {
  VityodSourceControlCommandRunner({
    required VityodClient client,
    required this.workspaceId,
  }) : _client = client;

  final VityodClient _client;
  final String workspaceId;
  var _sequence = 0;

  Future<SourceControlCommandResult> call(
    SourceControlCommandRequest request,
  ) async {
    final launch = _gitLaunchFor(request);
    if (launch == null) {
      return const SourceControlCommandResult(
        exitCode: 126,
        stderr: 'Unsupported Git operation.',
      );
    }
    final taskId = 'git-${_client.clientInstanceId}-${++_sequence}';
    try {
      final start = await _client.request(
        method: 'git.start',
        idempotencyKey: 'git-start-$taskId',
        workspaceId: workspaceId,
        params: <String, Object?>{'taskId': taskId, ...launch},
      );
      _throwIfError(start);
      var pollSequence = 0;
      while (true) {
        final output = await _client.request(
          method: 'git.output',
          idempotencyKey: 'git-output-$taskId-${++pollSequence}',
          workspaceId: workspaceId,
          params: <String, Object?>{'taskId': taskId},
        );
        _throwIfError(output);
        if (output.params['running'] == true) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        final exitCode = output.params['exitCode'];
        final stdout = output.params['stdout'];
        final stderr = output.params['stderr'];
        if (exitCode is! int || stdout is! String || stderr is! String) {
          throw const VityodGitFailure('invalid_git_receipt');
        }
        await _close(taskId);
        return SourceControlCommandResult(
          exitCode: exitCode,
          stdout: stdout,
          stderr: stderr,
        );
      }
    } on VityodGitFailure catch (error) {
      return SourceControlCommandResult(exitCode: 126, stderr: error.code);
    }
  }

  Future<void> _close(String taskId) async {
    final response = await _client.request(
      method: 'git.close',
      idempotencyKey: 'git-close-$taskId',
      workspaceId: workspaceId,
      params: <String, Object?>{'taskId': taskId},
    );
    _throwIfError(response);
  }
}

final class BlockedSourceControlCommandRunner {
  const BlockedSourceControlCommandRunner();

  Future<SourceControlCommandResult> call(
    SourceControlCommandRequest request,
  ) async {
    return const SourceControlCommandResult(
      exitCode: 126,
      stderr: 'Source control requires the desktop local service.',
    );
  }
}

final class VityodGitFailure implements Exception {
  const VityodGitFailure(this.code);

  final String code;

  @override
  String toString() => 'VityodGitFailure($code)';
}

Map<String, Object?>? _gitLaunchFor(SourceControlCommandRequest request) {
  if (request.executable != 'git') return null;
  final arguments = request.arguments;
  if (_equals(arguments, GitPorcelainStatusProvider.statusArguments)) {
    return const <String, Object?>{'operation': 'status'};
  }
  if (arguments.length == 3 && arguments[0] == 'diff' && arguments[1] == '--') {
    return <String, Object?>{'operation': 'diff', 'path': arguments[2]};
  }
  if (arguments.length >= 3 && arguments[0] == 'add' && arguments[1] == '--') {
    return <String, Object?>{
      'operation': 'stage',
      'paths': arguments.sublist(2),
    };
  }
  if (arguments.length >= 3 &&
      arguments[0] == 'restore' &&
      arguments[1] == '--') {
    return <String, Object?>{
      'operation': 'discard',
      'paths': arguments.sublist(2),
    };
  }
  if (arguments.length >= 4 &&
      arguments[0] == 'restore' &&
      arguments[1] == '--staged' &&
      arguments[2] == '--') {
    return <String, Object?>{
      'operation': 'unstage',
      'paths': arguments.sublist(3),
    };
  }
  if (arguments.length >= 3 && arguments[0] == 'commit') {
    final messageIndex = arguments.indexOf('-m');
    if (messageIndex < 0 || messageIndex + 1 >= arguments.length) return null;
    final separator = arguments.indexOf('--');
    return <String, Object?>{
      'operation': 'commit',
      'message': arguments[messageIndex + 1],
      'paths': separator < 0
          ? const <String>[]
          : arguments.sublist(separator + 1),
    };
  }
  if (arguments.isNotEmpty && arguments.first == 'apply') {
    final cached = arguments.contains('--cached');
    final reverse = arguments.contains('--reverse');
    final action = cached
        ? reverse
              ? 'unstage'
              : 'stage'
        : reverse
        ? 'discard'
        : null;
    if (action == null || request.standardInput == null) return null;
    return <String, Object?>{
      'operation': 'patch',
      'action': action,
      'patch': request.standardInput,
    };
  }
  if (_equals(arguments, const <String>['branch', '--show-current'])) {
    return const <String, Object?>{'operation': 'branchCurrent'};
  }
  if (_equals(arguments, GitSourceControlBranchProvider.branchArguments)) {
    return const <String, Object?>{'operation': 'branches'};
  }
  if (arguments.length == 2 && arguments.first == 'switch') {
    return <String, Object?>{'operation': 'switch', 'branch': arguments[1]};
  }
  if (arguments.isNotEmpty && arguments.first == 'log') {
    final limitIndex = arguments.indexOf('-n');
    final limit = limitIndex >= 0 && limitIndex + 1 < arguments.length
        ? int.tryParse(arguments[limitIndex + 1])
        : null;
    if (limit == null) return null;
    return <String, Object?>{'operation': 'history', 'limit': limit};
  }
  return null;
}

bool _equals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _throwIfError(VityodControlEnvelope response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw VityodGitFailure(code is String ? code : 'git_service_error');
}
