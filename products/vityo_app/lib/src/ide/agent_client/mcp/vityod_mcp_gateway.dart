import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../../local_service/vityod_client.dart';

final class VityodMcpGateway {
  VityodMcpGateway({required VityodClient client}) : _client = client;

  final VityodClient _client;
  var _sequence = 0;

  Future<void> startSession({
    required String sessionId,
    required String workspaceId,
    required int workspaceRevision,
    required Set<String> capabilities,
  }) async {
    final response = await _request(
      method: 'agent.session.start',
      params: <String, Object?>{
        'sessionId': sessionId,
        'workspaceId': workspaceId,
        'workspaceRevision': workspaceRevision,
        'capabilities': capabilities.toList(growable: false)..sort(),
      },
    );
    _throwIfError(response);
  }

  Future<Map<String, Object?>> invoke({
    required String sessionId,
    required String workspaceId,
    required int workspaceRevision,
    required String tool,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    final response = await _request(
      method: 'agent.mcp.invoke',
      params: <String, Object?>{
        'sessionId': sessionId,
        'workspaceId': workspaceId,
        'workspaceRevision': workspaceRevision,
        'tool': tool,
        ...arguments,
      },
    );
    _throwIfError(response);
    return response.params;
  }

  Future<void> revokeSession(String sessionId) async {
    final response = await _request(
      method: 'agent.session.cancel',
      params: <String, Object?>{'sessionId': sessionId},
    );
    _throwIfError(response);
  }

  Future<Map<String, Object?>> resumeSession(
    String sessionId, {
    int afterSequence = 0,
  }) async {
    final response = await _request(
      method: 'agent.session.resume',
      params: <String, Object?>{
        'sessionId': sessionId,
        'afterSequence': afterSequence,
      },
    );
    _throwIfError(response);
    return response.params;
  }

  Future<void> requestPermission({
    required String sessionId,
    required String permissionId,
  }) async {
    final response = await _request(
      method: 'agent.permission.request',
      params: <String, Object?>{
        'sessionId': sessionId,
        'permissionId': permissionId,
      },
    );
    _throwIfError(response);
  }

  Future<void> decidePermission({
    required String sessionId,
    required String permissionId,
    required bool allowOnce,
  }) async {
    final response = await _request(
      method: 'agent.permission.decide',
      params: <String, Object?>{
        'sessionId': sessionId,
        'permissionId': permissionId,
        'decision': allowOnce ? 'allow_once' : 'deny',
      },
    );
    _throwIfError(response);
  }

  Future<VityodControlEnvelope> _request({
    required String method,
    required Map<String, Object?> params,
  }) {
    return _client.request(
      method: method,
      idempotencyKey: 'mcp-${++_sequence}-$method',
      params: params,
      capabilities: const <String>['agent.mcp.invoke'],
    );
  }
}

final class VityodMcpFailure implements Exception {
  const VityodMcpFailure(this.code);

  final String code;

  @override
  String toString() => 'VityodMcpFailure($code)';
}

void _throwIfError(VityodControlEnvelope response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw VityodMcpFailure(code is String ? code : 'service_error');
}
