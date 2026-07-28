import 'package:styio_ide/src/ide/agent_client/agent_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'session reducer serializes and bounds its immutable projection',
    () async {
      final reducer = AgentSessionReducer(
        sessionId: 'session-1',
        maxBufferedUpdates: 2,
      );
      await Future.wait(<Future<void>>[
        reducer.reduce(
          const AgentSessionUpdate(
            sessionId: 'session-1',
            kind: 'chunk',
            text: 'one',
            payload: <String, Object?>{},
          ),
        ),
        reducer.reduce(
          const AgentSessionUpdate(
            sessionId: 'session-1',
            kind: 'chunk',
            text: 'two',
            payload: <String, Object?>{},
          ),
        ),
        reducer.reduce(
          const AgentSessionUpdate(
            sessionId: 'session-1',
            kind: 'chunk',
            text: 'three',
            payload: <String, Object?>{},
          ),
        ),
      ]);

      expect(reducer.snapshot.revision, 3);
      expect(reducer.snapshot.updates.map((update) => update.text), <String?>[
        'two',
        'three',
      ]);
      await reducer.close();
    },
  );

  test('policy rejects extensions outside the Styio namespace', () {
    expect(
      () => AgentClientRegistry(
        descriptors: <String, AgentLaunchDescriptor>{
          'agent': AgentLaunchDescriptor(
            id: 'agent',
            executable: 'agent',
            arguments: const <String>[],
            workingDirectory: '.',
          ),
        },
        policy: const AgentClientPolicy(allowedExtensions: <String>{'unsafe'}),
      ),
      throwsArgumentError,
    );
  });
}
