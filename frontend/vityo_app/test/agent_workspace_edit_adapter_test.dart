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
    'agent workspace edit adapter keeps file operations on agent applier',
    () {
      const patch = AgentCodePatch(
        patchId: 'patch-create',
        summary: 'Create file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'new.styio',
            operation: AgentCodePatchEditOperation.create,
            start: 0,
            end: 0,
            replacementText: '#main := () => {\n  <| 0\n}\n',
          ),
        ],
      );

      final conversion = const AgentWorkspaceEditPlanAdapter().convert(patch);

      expect(conversion.converted, isFalse);
      expect(conversion.plan, isNull);
      expect(conversion.skippedFileOperationCount, 1);
      expect(conversion.message, contains('AgentWorkspaceCodePatchApplier'));
    },
  );
}
