import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent_code_patch_applier.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent_provider_adapter.dart';

void main() {
  test(
    'agent patch applies one resource through the transaction authority',
    () async {
      final harness = _PatchHarness(const <String, String>{
        'main.styio': 'value = 1\n',
      });
      const patch = AgentCodePatch(
        patchId: 'patch-1',
        summary: 'Change value.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            baseRevision: 0,
            start: 8,
            end: 9,
            replacementText: '2',
          ),
        ],
      );

      final result = await harness.applier.apply(patch);
      final snapshot = harness.revisions.snapshot();

      expect(result.applied, isTrue);
      expect(result.appliedEditCount, 1);
      expect(result.appliedOperationCounts, <String, int>{'replace': 1});
      expect(result.appliedDocumentIds, <String>['main.styio']);
      expect(result.skippedNoOpDocumentIds, isEmpty);
      expect(snapshot.document('main.styio').text, 'value = 2\n');
      expect(snapshot.document('main.styio').revision, 1);
      expect(snapshot.workspaceRevision, 1);
    },
  );

  test(
    'agent patch commits changes to multiple resources atomically',
    () async {
      final harness = _PatchHarness(const <String, String>{
        'main.styio': 'value = 1\n',
        'other.styio': 'name = old\n',
      });
      const patch = AgentCodePatch(
        patchId: 'patch-multi',
        summary: 'Update two resources.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
          AgentCodePatchEdit(
            documentId: 'other.styio',
            start: 7,
            end: 10,
            replacementText: 'new',
          ),
        ],
      );

      final result = await harness.applier.apply(patch);
      final snapshot = harness.revisions.snapshot();

      expect(result.applied, isTrue);
      expect(result.appliedEditCount, 2);
      expect(result.appliedDocumentIds, <String>['main.styio', 'other.styio']);
      expect(snapshot.document('main.styio').text, 'value = 2\n');
      expect(snapshot.document('other.styio').text, 'name = new\n');
      expect(snapshot.workspaceRevision, 1);
      expect(snapshot.document('main.styio').workspaceRevision, 1);
      expect(snapshot.document('other.styio').workspaceRevision, 1);
    },
  );

  test(
    'agent patch skips no-op resources without creating a revision',
    () async {
      final harness = _PatchHarness(const <String, String>{
        'main.styio': 'value = 1\n',
        'other.styio': 'name = old\n',
      });
      const patch = AgentCodePatch(
        patchId: 'patch-partial-noop',
        summary: 'Update one resource and leave one unchanged.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 0,
            end: 5,
            replacementText: 'value',
          ),
          AgentCodePatchEdit(
            documentId: 'other.styio',
            start: 7,
            end: 10,
            replacementText: 'new',
          ),
        ],
      );

      final result = await harness.applier.apply(patch);
      final snapshot = harness.revisions.snapshot();

      expect(result.applied, isTrue);
      expect(result.appliedEditCount, 2);
      expect(result.appliedDocumentIds, <String>['other.styio']);
      expect(result.skippedNoOpDocumentIds, <String>['main.styio']);
      expect(snapshot.document('main.styio').revision, 0);
      expect(snapshot.document('other.styio').revision, 1);
    },
  );

  test('agent patch rejects a patch containing only no-op edits', () async {
    final harness = _PatchHarness(const <String, String>{
      'main.styio': 'value = 1\n',
    });
    const patch = AgentCodePatch(
      patchId: 'patch-noop',
      summary: 'Leave the resource unchanged.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 0,
          end: 5,
          replacementText: 'value',
        ),
      ],
    );

    final result = await harness.applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.appliedEditCount, 0);
    expect(result.skippedNoOpDocumentIds, <String>['main.styio']);
    expect(harness.revisions.snapshot().workspaceRevision, 0);
  });

  test('agent patch rejects missing and unsafe resource identities', () async {
    final harness = _PatchHarness(const <String, String>{
      'main.styio': 'value = 1\n',
    });

    for (final patch in const <AgentCodePatch>[
      AgentCodePatch(
        patchId: 'patch-empty-document',
        summary: 'Missing resource identity.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: '',
            start: 0,
            end: 1,
            replacementText: 'x',
          ),
        ],
      ),
      AgentCodePatch(
        patchId: 'patch-unsafe-document',
        summary: 'Unsafe resource identity.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: '../secret.styio',
            start: 0,
            end: 1,
            replacementText: 'x',
          ),
        ],
      ),
    ]) {
      final result = await harness.applier.apply(patch);
      expect(result.applied, isFalse);
    }

    expect(harness.revisions.snapshot().workspaceRevision, 0);
  });

  test(
    'agent patch rejects unavailable resources and stale revisions',
    () async {
      final harness = _PatchHarness(const <String, String>{
        'main.styio': 'value = 1\n',
      });
      const missingPatch = AgentCodePatch(
        patchId: 'patch-missing',
        summary: 'Target an unavailable resource.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'missing.styio',
            start: 0,
            end: 0,
            replacementText: 'x',
          ),
        ],
      );
      const stalePatch = AgentCodePatch(
        patchId: 'patch-stale',
        summary: 'Use a stale document revision.',
        baseRevision: 3,
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
        ],
      );

      final missingResult = await harness.applier.apply(missingPatch);
      final staleResult = await harness.applier.apply(stalePatch);

      expect(missingResult.applied, isFalse);
      expect(missingResult.message, contains('unavailable resource'));
      expect(staleResult.applied, isFalse);
      expect(staleResult.message, contains('conflicts with the workspace'));
      expect(
        harness.revisions.snapshot().document('main.styio').text,
        'value = 1\n',
      );
    },
  );

  test(
    'agent patch rejects invalid, overlapping, and ambiguous ranges',
    () async {
      final harness = _PatchHarness(const <String, String>{
        'main.styio': 'value = 1\n',
      });
      final patches = <AgentCodePatch>[
        const AgentCodePatch(
          patchId: 'patch-invalid-range',
          summary: 'Use an invalid range.',
          edits: <AgentCodePatchEdit>[
            AgentCodePatchEdit(
              documentId: 'main.styio',
              start: 20,
              end: 21,
              replacementText: 'x',
            ),
          ],
        ),
        const AgentCodePatch(
          patchId: 'patch-overlap',
          summary: 'Use overlapping ranges.',
          edits: <AgentCodePatchEdit>[
            AgentCodePatchEdit(
              documentId: 'main.styio',
              start: 0,
              end: 7,
              replacementText: 'count',
            ),
            AgentCodePatchEdit(
              documentId: 'main.styio',
              start: 6,
              end: 9,
              replacementText: '2',
            ),
          ],
        ),
        const AgentCodePatch(
          patchId: 'patch-ambiguous-inserts',
          summary: 'Use ambiguous insert ordering.',
          edits: <AgentCodePatchEdit>[
            AgentCodePatchEdit(
              documentId: 'main.styio',
              start: 0,
              end: 0,
              replacementText: 'first\n',
            ),
            AgentCodePatchEdit(
              documentId: 'main.styio',
              start: 0,
              end: 0,
              replacementText: 'second\n',
            ),
          ],
        ),
      ];

      for (final patch in patches) {
        final result = await harness.applier.apply(patch);
        expect(result.applied, isFalse);
      }

      expect(harness.revisions.snapshot().workspaceRevision, 0);
    },
  );

  test(
    'agent patch rejects unsupported, oversized, and excessive edits',
    () async {
      final harness = _PatchHarness(const <String, String>{
        'main.styio': 'value = 1\n',
      });
      const unsupportedPatch = AgentCodePatch(
        patchId: 'patch-create',
        summary: 'Attempt a file operation.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            operation: AgentCodePatchEditOperation.create,
            start: 0,
            end: 0,
            replacementText: 'x',
          ),
        ],
      );
      final oversizedPatch = AgentCodePatch(
        patchId: 'patch-oversized',
        summary: 'Attempt an oversized edit.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 0,
            end: 0,
            replacementText: List<String>.filled(200001, 'x').join(),
          ),
        ],
      );
      final excessivePatch = AgentCodePatch(
        patchId: 'patch-excessive',
        summary: 'Attempt too many edits.',
        edits: List<AgentCodePatchEdit>.generate(
          501,
          (_) => const AgentCodePatchEdit(
            documentId: 'main.styio',
            start: 0,
            end: 0,
            replacementText: 'x',
          ),
        ),
      );

      for (final patch in <AgentCodePatch>[
        unsupportedPatch,
        oversizedPatch,
        excessivePatch,
      ]) {
        final result = await harness.applier.apply(patch);
        expect(result.applied, isFalse);
      }

      expect(harness.revisions.snapshot().workspaceRevision, 0);
    },
  );

  test('agent patch preserves the workspace when commit fails', () async {
    final harness = _PatchHarness(const <String, String>{
      'main.styio': 'value = 1\n',
      'other.styio': 'name = old\n',
    });
    harness.revisions.failNextCommit();
    const patch = AgentCodePatch(
      patchId: 'patch-failed-commit',
      summary: 'Exercise atomic commit failure.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
        AgentCodePatchEdit(
          documentId: 'other.styio',
          start: 7,
          end: 10,
          replacementText: 'new',
        ),
      ],
    );

    final result = await harness.applier.apply(patch);
    final snapshot = harness.revisions.snapshot();

    expect(result.applied, isFalse);
    expect(result.message, contains('was not committed'));
    expect(snapshot.workspaceRevision, 0);
    expect(snapshot.document('main.styio').text, 'value = 1\n');
    expect(snapshot.document('other.styio').text, 'name = old\n');
  });
}

final class _PatchHarness {
  _PatchHarness(Map<String, String> documents)
    : revisions = InMemoryWorkspaceRevisionService(
        initialDocuments: documents,
      ) {
    final transactionService = RevisionedWorkspaceTransactionService(revisions);
    applier = AgentCodePatchApplier(
      transactionService: transactionService,
      revisionService: revisions,
    );
  }

  final InMemoryWorkspaceRevisionService revisions;
  late final AgentCodePatchApplier applier;
}
