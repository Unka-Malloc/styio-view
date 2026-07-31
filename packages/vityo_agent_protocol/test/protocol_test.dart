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
        JsonRpcSuccessResponse(
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
      expect(
        () => JsonRpcCodec.encode(
          JsonRpcSuccessResponse(
            id: JsonRpcId.string(''),
            result: <String, Object?>{},
          ),
        ),
        throwsA(
          isA<AgentProtocolException>().having(
            (error) => error.code,
            'code',
            'invalid_identifier',
          ),
        ),
      );
    });

    test('deeply snapshots mutable request parameters before encoding', () {
      final nested = <Object?>[1];
      final params = <String, Object?>{'value': nested};
      final request = JsonRpcRequest(
        id: const JsonRpcId.integer(1),
        method: 'fixture',
        params: params,
      );
      nested.add(2);
      params['value'] = <Object?>[3];

      expect(request.params['value'], <Object?>[1]);
      expect(() => request.params['value'] = 3, throwsUnsupportedError);
      expect(
        () => (request.params['value']! as List<Object?>).add(4),
        throwsUnsupportedError,
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
      () => validateVityoExtensionMethod(
        '_vityo.dev/test/write',
        const <String>{},
      ),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          'capability_revoked',
        ),
      ),
    );
    expect(
      () => validateVityoExtensionMethod('_vityo.dev/', const <String>{
        '_vityo.dev/',
      }),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          'invalid_extension_namespace',
        ),
      ),
    );
  });

  test('workspace proposals round-trip with strict revision bounds', () {
    final proposal = VityoWorkspaceChangeProposal(
      id: 'change-1',
      baseWorkspaceRevision: 7,
      resources: <VityoResourceChange>[
        VityoResourceChange(
          resourceId: 'lib/example.dart',
          baseDocumentRevision: 3,
          edits: <VityoTextChange>[
            VityoTextChange(start: 2, end: 4, replacement: 'after'),
          ],
        ),
      ],
    );

    final params = proposal.toNotificationParamsJson('session-1');
    final decoded = VityoWorkspaceChangeProposal.fromNotificationParams(params);
    expect(jsonEncode(decoded.toJson()), jsonEncode(proposal.toJson()));
    expect(params['sessionId'], 'session-1');
    expect(decoded.editCount, 1);

    expect(
      () => VityoWorkspaceChangeProposal.fromJson(<String, Object?>{
        'id': 'invalid',
        'baseWorkspaceRevision': 0,
        'resources': <Object?>[
          <String, Object?>{
            'resourceId': 'file',
            'baseDocumentRevision': 0,
            'edits': <Object?>[
              <String, Object?>{'start': 2, 'end': 1, 'replacement': ''},
            ],
          },
        ],
      }),
      throwsA(
        isA<AgentProtocolException>().having(
          (error) => error.code,
          'code',
          'malformed_message',
        ),
      ),
    );
  });
}
