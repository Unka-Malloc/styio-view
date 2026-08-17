import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import 'vityod_client.dart';

final class VityodLspGateway {
  VityodLspGateway({required VityodClient client}) : _client = client;

  final VityodClient _client;
  var _sequence = 0;

  Future<VityodLspSession> start({
    required String executable,
    List<String> arguments = const <String>[],
    String? workingDirectory,
    Map<String, String> environment = const <String, String>{},
  }) async {
    final processId = 'lsp-${_client.clientInstanceId}-${++_sequence}';
    final response = await _client.request(
      method: 'lsp.start',
      idempotencyKey: 'lsp-start-$processId',
      params: <String, Object?>{
        'processId': processId,
        'executable': executable,
        'arguments': arguments,
        'workingDirectory': workingDirectory,
        'environment': environment,
      },
    );
    _throwIfError(response);
    return VityodLspSession._(client: _client, processId: processId);
  }
}

final class VityodLspSession {
  VityodLspSession._({required VityodClient client, required this.processId})
    : _client = client;

  final VityodClient _client;
  final String processId;
  var _sequence = 0;
  var _stopped = false;

  Future<void> write(List<int> bytes) async {
    if (_stopped) throw const VityodLspFailure('lsp_session_stopped');
    if (bytes.isEmpty) return;
    final response = await _client.request(
      method: 'lsp.request',
      idempotencyKey: 'lsp-write-$processId-${++_sequence}',
      params: <String, Object?>{
        'processId': processId,
        'action': 'write',
        'bytes': bytes,
      },
    );
    _throwIfError(response);
  }

  Future<VityodLspPoll> poll({int maximumBytes = 64 * 1024}) async {
    if (_stopped) throw const VityodLspFailure('lsp_session_stopped');
    final response = await _client.request(
      method: 'lsp.request',
      idempotencyKey: 'lsp-poll-$processId-${++_sequence}',
      params: <String, Object?>{
        'processId': processId,
        'action': 'poll',
        'maximumBytes': maximumBytes.clamp(1, 1024 * 1024),
      },
    );
    _throwIfError(response);
    final stdout = _bytes(response.params['stdout']);
    final stderr = _bytes(response.params['stderr']);
    final exitCode = response.params['exitCode'];
    if (exitCode != null && exitCode is! int) {
      throw const VityodLspFailure('invalid_lsp_response');
    }
    return VityodLspPoll(
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode as int?,
      overflowed: response.params['overflowed'] == true,
    );
  }

  Future<int> stop() async {
    if (_stopped) return 0;
    final response = await _client.request(
      method: 'lsp.stop',
      idempotencyKey: 'lsp-stop-$processId',
      params: <String, Object?>{'processId': processId},
    );
    _throwIfError(response);
    _stopped = true;
    final exitCode = response.params['exitCode'];
    if (exitCode is! int) {
      throw const VityodLspFailure('invalid_lsp_response');
    }
    return exitCode;
  }
}

final class VityodLspPoll {
  const VityodLspPoll({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.overflowed,
  });

  final List<int> stdout;
  final List<int> stderr;
  final int? exitCode;
  final bool overflowed;
}

final class VityodLspFailure implements Exception {
  const VityodLspFailure(this.code);

  final String code;

  @override
  String toString() => 'VityodLspFailure($code)';
}

List<int> _bytes(Object? value) {
  if (value is List &&
      value.length <= 1024 * 1024 &&
      value.every((item) => item is int && item >= 0 && item <= 255)) {
    return List<int>.unmodifiable(value.cast<int>());
  }
  throw const VityodLspFailure('invalid_lsp_response');
}

void _throwIfError(VityodControlEnvelope response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw VityodLspFailure(code is String ? code : 'lsp_service_error');
}
