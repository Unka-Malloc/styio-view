import 'dart:convert';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('JSON-RPC 2.0 codec', () {
    test('round-trips ACP request and response IDs', () {
      final messages = <JsonRpcMessage>[
        JsonRpcRequest(
          id: const JsonRpcId.string('request-1'),
          method: AcpMethod.initialize,
          params: const <String, Object?>{'protocolVersion': 1},
        ),
        const JsonRpcSuccessResponse(
          id: JsonRpcId.integer(1),
          result: <String, Object?>{'protocolVersion': 1},
        ),
      ];

      for (final message in messages) {
        final decoded = JsonRpcCodec.decode(JsonRpcCodec.encode(message));
        expect(jsonEncode(decoded.toJson()), jsonEncode(message.toJson()));
      }
    });

    test('rejects malformed, ambiguous, and oversized messages', () {
      expect(
        () => JsonRpcCodec.decode('{"jsonrpc":"2.0","method":'),
        throwsA(
          isA<AgentProtocolException>().having(
            (error) => error.code,
            'code',
            'malformed_message',
          ),
        ),
      );
      expect(
        () => JsonRpcCodec.decode(
          '{"jsonrpc":"2.0","id":1,"result":{},"error":{}}',
        ),
        throwsA(isA<AgentProtocolException>()),
      );
      expect(
        () => JsonRpcCodec.decode(
          '{"jsonrpc":"2.0","method":"x"}',
          maxMessageBytes: 4,
        ),
        throwsA(
          isA<AgentProtocolException>().having(
            (error) => error.code,
            'code',
            'message_too_large',
          ),
        ),
      );
    });
  });

  test('extensions are namespaced and currently negotiated', () {
    expect(
      () => validateVityoExtensionMethod('unsafe', const <String>{}),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          'invalid_extension_namespace',
        ),
      ),
    );
    expect(
      () => validateVityoExtensionMethod('vityo/test/write', const <String>{}),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          'capability_revoked',
        ),
      ),
    );
  });
}
