import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/local_service/vityod_client.dart';
import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

void main() {
  test(
    'connect sends revisioned resume request and accepts ordered snapshot',
    () async {
      final transport = MemoryVityodTransport(instanceId: 'daemon-1');
      final client = VityodClient(
        transport: transport,
        clientInstanceId: 'client-1',
        clock: () => DateTime.utc(2030),
      );

      await client.connect();

      expect(client.state.phase, VityodConnectionPhase.connected);
      expect(transport.sent, hasLength(2));
      final handshake = VityodControlCodec.decode(transport.sent.first);
      expect(handshake.method, 'handshake.negotiate');
      expect(
        handshake.params['requiredCapabilities'],
        containsAll(<String>['event.resume', 'workspace.snapshot']),
      );
      final resume = VityodControlCodec.decode(transport.sent.last);
      expect(resume.method, 'event.resume');
      expect(resume.params['afterCursor'], 0);

      client.acceptSnapshot(
        const VityodServiceSnapshot(
          eventCursor: 8,
          workspaceRevision: 3,
          capabilities: <String>{'workspace.snapshot'},
        ),
      );
      expect(client.state.lastEventCursor, 8);
      expect(client.snapshot?.workspaceRevision, 3);
      await client.dispose();
    },
  );

  test('connect fails closed when negotiation is rejected', () async {
    final transport = MemoryVityodTransport(automaticallyNegotiate: false);
    final client = VityodClient(
      transport: transport,
      clientInstanceId: 'client-rejected',
    );

    final connect = client.connect();
    await Future<void>.delayed(Duration.zero);
    final request = VityodControlCodec.decode(transport.sent.single);
    transport.receiveControl(
      VityodControlCodec.encode(
        VityodControlEnvelope(
          method: 'handshake.negotiate.error',
          requestId: request.requestId,
          clientInstanceId: 'daemon',
          idempotencyKey: request.idempotencyKey,
          deadlineUnixMillis: request.deadlineUnixMillis,
          params: const <String, Object?>{
            'errorCode': 'required_capability_unsupported',
            'retryable': false,
          },
        ),
      ),
    );

    await expectLater(
      connect,
      throwsA(
        isA<VityodProtocolException>().having(
          (error) => error.code,
          'code',
          'required_capability_unsupported',
        ),
      ),
    );
    expect(client.state.phase, VityodConnectionPhase.disconnected);
    await client.dispose();
    await transport.dispose();
  });

  test('resume validates a contiguous ordered event digest', () async {
    final transport = MemoryVityodTransport(instanceId: 'daemon-events');
    final client = VityodClient(
      transport: transport,
      clientInstanceId: 'client-events',
    );
    await client.connect();
    final resume = VityodControlCodec.decode(transport.sent.last);
    transport.receiveControl(
      VityodControlCodec.encode(
        VityodControlEnvelope(
          method: 'event.resume.result',
          requestId: resume.requestId,
          clientInstanceId: 'daemon-events',
          idempotencyKey: resume.idempotencyKey,
          deadlineUnixMillis: resume.deadlineUnixMillis,
          params: <String, Object?>{
            'eventCursor': 1,
            'eventDigest': 'bf3851d909f822ed',
            'events': <Object?>[
              <String, Object?>{
                'cursor': 1,
                'kind': 'workspace.transaction.committed',
                'workspaceRevision': 2,
                'payloadBase64': base64Encode(utf8.encode('workspace-commit')),
              },
            ],
            'workspaceRevision': 2,
            'capabilities': const <String>[
              'event.resume',
              'workspace.snapshot',
            ],
            'activeTerminalIds': const <String>[],
            'activeTaskIds': const <String>[],
            'activeAgentSessionIds': const <String>[],
          },
        ),
      ),
    );

    expect(client.state.phase, VityodConnectionPhase.connected);
    expect(client.snapshot?.eventCursor, 1);
    expect(client.snapshot?.events.single.workspaceRevision, 2);
    expect(client.snapshot?.eventDigest, 'bf3851d909f822ed');
    await client.dispose();
    await transport.dispose();
  });

  test('pruned resume requests and accepts one full snapshot', () async {
    final transport = MemoryVityodTransport(instanceId: 'daemon-gap');
    final client = VityodClient(
      transport: transport,
      clientInstanceId: 'client-gap',
    );
    await client.connect();
    final resume = VityodControlCodec.decode(transport.sent.last);
    transport.receiveControl(
      VityodControlCodec.encode(
        VityodControlEnvelope(
          method: 'event.resume.error',
          requestId: resume.requestId,
          clientInstanceId: 'daemon-gap',
          idempotencyKey: resume.idempotencyKey,
          deadlineUnixMillis: resume.deadlineUnixMillis,
          params: const <String, Object?>{
            'errorCode': 'event_cursor_pruned',
            'retryable': true,
            'context': <String, Object?>{'resyncMode': 'full_snapshot'},
          },
        ),
      ),
    );

    expect(client.state.phase, VityodConnectionPhase.resyncRequired);
    expect(client.state.reasonCode, 'event_cursor_pruned');
    await Future<void>.delayed(Duration.zero);
    final snapshotRequest = VityodControlCodec.decode(transport.sent.last);
    expect(snapshotRequest.method, 'snapshot.get');
    transport.receiveControl(
      VityodControlCodec.encode(
        VityodControlEnvelope(
          method: 'snapshot.get.result',
          requestId: snapshotRequest.requestId,
          clientInstanceId: 'daemon-gap',
          idempotencyKey: snapshotRequest.idempotencyKey,
          deadlineUnixMillis: snapshotRequest.deadlineUnixMillis,
          params: const <String, Object?>{
            'eventCursor': 7,
            'eventDigest': 'cbf29ce484222325',
            'events': <Object?>[],
            'workspaceRevision': 3,
            'capabilities': <String>['event.resume', 'workspace.snapshot'],
            'activeTerminalIds': <String>[],
            'activeTaskIds': <String>[],
            'activeAgentSessionIds': <String>[],
            'dirtyBuffers': <Object?>[
              <String, Object?>{
                'documentId': 'main',
                'revision': 2,
                'contents': 'dirty',
              },
            ],
          },
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.state.phase, VityodConnectionPhase.connected);
    expect(client.snapshot?.eventCursor, 7);
    expect(client.snapshot?.dirtyBuffers.single.contents, 'dirty');
    await client.dispose();
    await transport.dispose();
  });

  test('buffer outbox is bounded, contiguous, and acknowledgement-driven', () {
    final outbox = BufferDeltaOutbox(maximumPendingDeltas: 2);
    outbox.add(
      const BufferDelta(
        documentId: 'doc',
        baseRevision: 1,
        targetRevision: 2,
        startOffset: 0,
        deletedLength: 0,
        insertedText: 'a',
      ),
    );
    outbox.add(
      const BufferDelta(
        documentId: 'doc',
        baseRevision: 2,
        targetRevision: 3,
        startOffset: 1,
        deletedLength: 0,
        insertedText: 'b',
      ),
    );
    expect(
      () => outbox.add(
        const BufferDelta(
          documentId: 'doc',
          baseRevision: 3,
          targetRevision: 4,
          startOffset: 2,
          deletedLength: 0,
          insertedText: 'c',
        ),
      ),
      throwsStateError,
    );
    outbox.acknowledge(documentId: 'doc', revision: 2);
    expect(outbox.pending.map((delta) => delta.targetRevision), <int>[3]);
  });

  test('stale service snapshot is rejected', () async {
    final client = VityodClient(
      transport: MemoryVityodTransport(),
      clientInstanceId: 'client',
    );
    await client.connect();
    client.acceptSnapshot(
      const VityodServiceSnapshot(
        eventCursor: 4,
        workspaceRevision: 1,
        capabilities: <String>{},
      ),
    );
    expect(
      () => client.acceptSnapshot(
        const VityodServiceSnapshot(
          eventCursor: 3,
          workspaceRevision: 1,
          capabilities: <String>{},
        ),
      ),
      throwsStateError,
    );
    await client.dispose();
  });

  test(
    'request correlates one daemon response and clears it on completion',
    () async {
      final transport = MemoryVityodTransport();
      final client = VityodClient(
        transport: transport,
        clientInstanceId: 'client-request',
      );
      await client.connect();
      final responseFuture = client.request(
        method: 'health.get',
        idempotencyKey: 'health-1',
      );
      final request = VityodControlCodec.decode(transport.sent.last);
      transport.receiveControl(
        VityodControlCodec.encode(
          VityodControlEnvelope(
            method: 'health.get.result',
            requestId: request.requestId,
            clientInstanceId: 'vityod',
            idempotencyKey: request.idempotencyKey,
            deadlineUnixMillis: request.deadlineUnixMillis,
            params: const <String, Object?>{'status': 'ready'},
          ),
        ),
      );

      final response = await responseFuture;
      expect(response.method, 'health.get.result');
      expect(response.params['status'], 'ready');
      await client.dispose();
      await transport.dispose();
    },
  );
}
