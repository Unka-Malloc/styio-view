import 'package:flutter_test/flutter_test.dart';

import '../support/vityod_test_harness.dart';

void main() {
  test(
    'workspace effects and receipts commit once across a new request id',
    () async {
      final harness = await VityodTestHarness.start(
        clientId: 'idempotency-test',
      );
      addTearDown(harness.close);
      const params = <String, Object?>{
        'expectedWorkspaceRevision': 0,
        'changes': <Object?>[
          <String, Object?>{
            'relativePath': 'lib/once.styio',
            'expectedDocumentRevision': 0,
            'contents': 'once',
          },
        ],
      };

      final first = await harness.client.request(
        method: 'workspace.transaction.commit',
        idempotencyKey: 'commit-once',
        params: params,
      );
      final retried = await harness.client.request(
        method: 'workspace.transaction.commit',
        idempotencyKey: 'commit-once',
        params: params,
      );
      final read = await harness.client.request(
        method: 'workspace.read',
        idempotencyKey: 'read-after-retry',
        params: const <String, Object?>{'relativePath': 'lib/once.styio'},
      );

      expect(first.params['workspaceRevision'], 1);
      expect(retried.params, first.params);
      expect(retried.requestId, isNot(first.requestId));
      expect(read.params['workspaceRevision'], 1);
      expect(read.params['documentRevision'], 1);
      expect(read.params['contents'], 'once');
    },
    skip: !VityodTestHarness.isSupported
        ? 'Unix vityod transport only.'
        : false,
  );
}
