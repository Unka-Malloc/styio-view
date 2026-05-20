import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent workspace edit adapter converts replace patch to edit plan', () {
    const patch = AgentCodePatch(
      patchId: 'patch-text',
      summary: 'Update text.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 0,
          end: 5,
          replacementText: 'count',
        ),
        AgentCodePatchEdit(
          documentId: 'lib/math.styio',
          start: 7,
          end: 10,
          replacementText: 'next',
        ),
      ],
    );

    final conversion = const AgentWorkspaceEditPlanAdapter().convert(patch);
    final plan = conversion.plan;

    expect(conversion.converted, isTrue);
    expect(conversion.message, contains('Converted agent patch patch-text'));
    expect(plan, isNotNull);
    expect(plan!.id, 'patch-text');
    expect(plan.source, WorkspaceEditSource.agent);
    expect(plan.documentIds, <String>['lib/math.styio', 'main.styio']);
    expect(plan.editCount, 2);
    expect(plan.editsByDocument['main.styio']!.single.newText, 'count');
  });

  test(
    'agent workspace edit adapter converts file operations to edit plan',
    () {
      const patch = AgentCodePatch(
        patchId: 'patch-file-ops',
        summary: 'Create and delete files.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'new.styio',
            operation: AgentCodePatchEditOperation.create,
            start: 0,
            end: 0,
            replacementText: '#main := () => {\n  <| 0\n}\n',
          ),
          AgentCodePatchEdit(
            documentId: 'old.styio',
            operation: AgentCodePatchEditOperation.delete,
            start: 0,
            end: 0,
            replacementText: '',
          ),
        ],
      );

      final conversion = const AgentWorkspaceEditPlanAdapter().convert(patch);
      final plan = conversion.plan;

      expect(conversion.converted, isTrue);
      expect(plan, isNotNull);
      expect(plan!.editCount, 0);
      expect(plan.fileOperations, hasLength(2));
      expect(plan.documentIds, <String>['new.styio', 'old.styio']);
      expect(plan.fileOperations.first.kind, WorkspaceFileOperationKind.create);
      expect(plan.fileOperations.first.documentId, 'new.styio');
      expect(plan.fileOperations.first.text, contains('<| 0'));
      expect(plan.fileOperations.last.kind, WorkspaceFileOperationKind.delete);
    },
  );

  test('agent workspace edit adapter blocks mixed file and text edits', () {
    const patch = AgentCodePatch(
      patchId: 'patch-mixed',
      summary: 'Invalid mixed file op.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'new.styio',
          operation: AgentCodePatchEditOperation.create,
          start: 0,
          end: 0,
          replacementText: 'created\n',
        ),
        AgentCodePatchEdit(
          documentId: 'new.styio',
          start: 0,
          end: 0,
          replacementText: 'extra\n',
        ),
      ],
    );

    final conversion = const AgentWorkspaceEditPlanAdapter().convert(patch);

    expect(conversion.converted, isFalse);
    expect(conversion.plan, isNull);
    expect(conversion.skippedFileOperationCount, 1);
    expect(conversion.message, contains('mixes file operation'));
  });
}
