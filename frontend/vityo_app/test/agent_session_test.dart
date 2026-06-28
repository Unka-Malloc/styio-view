import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_session.dart';

void main() {
  test('permission request gates patch apply plan', () {
    const pendingRequest = PermissionRequest(
      requestId: 'perm-1',
      scope: PermissionRequestScope.workspaceWrite,
      reason: 'Apply generated patch.',
      createdAtIso8601: '2026-06-21T00:00:00Z',
      toolInvocationId: 'tool-1',
    );
    const preview = FileChangePreview(
      previewId: 'preview-1',
      source: 'agent-patch',
      changes: <FileChange>[
        FileChange(
          path: 'lib/main.styio',
          editCount: 2,
          summary: 'Rename task and update call site.',
        ),
      ],
      affectedSymbols: <String>['task:build'],
    );

    final pendingPlan = const PatchApplyPlan(
      planId: 'plan-1',
      preview: preview,
      permissionRequest: pendingRequest,
    );
    final approvedPlan = PatchApplyPlan(
      planId: 'plan-1',
      preview: preview,
      permissionRequest: pendingRequest.decide(PermissionDecision.allowOnce),
    );

    expect(preview.editCount, 2);
    expect(preview.changedFileCount, 1);
    expect(pendingPlan.canApply, isFalse);
    expect(approvedPlan.canApply, isTrue);
    expect(approvedPlan.toJson()['canApply'], isTrue);
  });

  test('agent session appends audit events without mutating prior session', () {
    const session = AgentSession(
      sessionId: 'session-1',
      profileId: 'default-macos',
      status: AgentSessionStatus.active,
      turns: <AgentTurn>[
        AgentTurn(
          turnId: 'turn-1',
          role: AgentMessageRole.user,
          createdAtIso8601: '2026-06-21T00:00:00Z',
          parts: <AgentMessagePart>[
            AgentMessagePart(
              kind: AgentMessagePartKind.text,
              text: 'Rename the build task.',
            ),
          ],
        ),
      ],
      toolInvocations: <ToolInvocation>[
        ToolInvocation(
          invocationId: 'tool-1',
          toolName: 'applyPatch',
          scope: PermissionRequestScope.workspaceWrite,
          status: ToolInvocationStatus.waitingForPermission,
        ),
      ],
      permissionRequests: <PermissionRequest>[],
      auditEvents: <AgentAuditEvent>[],
    );
    const event = AgentAuditEvent(
      eventId: 'audit-1',
      kind: AgentAuditEventKind.permissionRequested,
      sessionId: 'session-1',
      turnId: 'turn-1',
      createdAtIso8601: '2026-06-21T00:00:01Z',
      details: <String, Object?>{'scope': 'workspaceWrite'},
    );

    final next = session.appendAuditEvent(event);

    expect(session.auditEvents, isEmpty);
    expect(next.auditEvents, hasLength(1));
    expect(next.toJson()['sessionId'], 'session-1');
    expect(next.toJson()['auditEvents'], isA<List>());
  });
}
