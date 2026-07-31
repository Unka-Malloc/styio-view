import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_coding_agent/vityo_coding_agent.dart';

Future<void> main() async {
  await _realStdioHandshake();
  await _permissionAndMcpRouting();
}

Future<void> _realStdioHandshake() async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    const <String>['run', 'bin/vityo_coding_agent.dart', '--stdio-agent'],
    workingDirectory: Directory.current.path,
    runInShell: false,
  );
  unawaited(process.stderr.drain<void>());
  final lines = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .asBroadcastStream();
  process.stdin.writeln(
    JsonRpcCodec.encode(
      JsonRpcRequest(
        id: const JsonRpcId.integer(1),
        method: AcpMethod.initialize,
        params: const <String, Object?>{
          'protocolVersion': acpProtocolVersion,
          'clientInfo': <String, Object?>{'name': 'vityo', 'version': '0.1.0'},
        },
      ),
    ),
  );
  await process.stdin.flush();
  final response = JsonRpcCodec.decode(
    await lines.first.timeout(const Duration(seconds: 5)),
  );
  if (response is! JsonRpcSuccessResponse ||
      requireJsonObject(
            response.result,
            'initialize result',
          )['protocolVersion'] !=
          acpProtocolVersion) {
    throw StateError('real stdio Agent did not negotiate with the IDE shape');
  }
  await process.stdin.close();
  final exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
  if (exitCode != 0) {
    throw StateError('real stdio Agent exited with code $exitCode');
  }
}

Future<void> _permissionAndMcpRouting() async {
  final attachments = _RecordingMcpAttachments();
  final endpoint = AgentSessionEndpoint(
    runtime: AgentRuntime(
      sessionService: AgentSessionService(
        host: InMemoryHostWorkspace(
          roots: const <HostRoot>[
            HostRoot(id: 'workspace', uri: 'memory://workspace'),
          ],
        ),
      ),
    ),
    defaultRootId: 'workspace',
    policy: const AgentEndpointPolicy(
      maxConcurrentSessions: 1,
      maxPendingRequests: 4,
      maxSessions: 2,
      maxPromptCharacters: 256,
    ),
    sessionIdFactory: (_) => 'routed-session',
    mcpAttachments: attachments,
  );
  final transport = _RoutingTransport();
  final serving = endpoint.serve(transport);
  await transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.integer(1),
      method: AcpMethod.initialize,
      params: const <String, Object?>{'protocolVersion': acpProtocolVersion},
    ),
  );
  await transport.exchange(
    JsonRpcRequest(
      id: const JsonRpcId.integer(2),
      method: AcpMethod.sessionNew,
      params: <String, Object?>{
        'cwd': Directory.current.path,
        'mcpServers': const <Object?>[
          <String, Object?>{'name': 'fixture', 'transport': 'memory'},
        ],
      },
    ),
  );
  final decision = await endpoint.requestPermission(
    sessionId: 'routed-session',
    toolCallId: 'tool-routed-session',
    options: const <String>{'allow_once', 'reject_once'},
  );
  if (decision != 'allow_once' ||
      attachments.sessionId != 'routed-session' ||
      attachments.servers.length != 1) {
    throw StateError('permission or MCP routing lost its session correlation');
  }
  await transport.closeInput();
  await serving;
}

final class _RecordingMcpAttachments implements McpSessionAttachmentHandler {
  String? sessionId;
  List<Map<String, Object?>> servers = const <Map<String, Object?>>[];

  @override
  Future<void> attach({
    required String sessionId,
    required List<Map<String, Object?>> servers,
  }) async {
    this.sessionId = sessionId;
    this.servers = List<Map<String, Object?>>.unmodifiable(servers);
  }
}

final class _RoutingTransport implements AgentServerTransport {
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>();
  final StreamController<JsonRpcMessage> _outgoing =
      StreamController<JsonRpcMessage>.broadcast();

  @override
  Stream<JsonRpcMessage> get incoming => _incoming.stream;

  Future<JsonRpcMessage> exchange(JsonRpcRequest request) {
    final response = _outgoing.stream.firstWhere(
      (message) =>
          (message is JsonRpcSuccessResponse && message.id == request.id) ||
          (message is JsonRpcErrorResponse && message.id == request.id),
    );
    _incoming.add(request);
    return response.timeout(const Duration(seconds: 2));
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    _outgoing.add(message);
    if (message is JsonRpcRequest &&
        message.method == AcpMethod.sessionRequestPermission) {
      scheduleMicrotask(
        () => _incoming.add(
          JsonRpcSuccessResponse(
            id: message.id,
            result: const <String, Object?>{
              'outcome': <String, Object?>{
                'outcome': 'selected',
                'optionId': 'allow_once-agent-permission-1',
              },
            },
          ),
        ),
      );
    }
  }

  Future<void> closeInput() => _incoming.close();

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
    if (!_outgoing.isClosed) await _outgoing.close();
  }
}
