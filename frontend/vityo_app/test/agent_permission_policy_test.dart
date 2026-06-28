import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent_session.dart';

void main() {
  group('PermissionRequestScope', () {
    test('all scopes are distinct and nameable', () {
      expect(PermissionRequestScope.readOnly.name, 'readOnly');
      expect(PermissionRequestScope.workspaceWrite.name, 'workspaceWrite');
      expect(PermissionRequestScope.toolchainManaged.name, 'toolchainManaged');
      expect(PermissionRequestScope.fullAccessDisabledByDefault.name,
          'fullAccessDisabledByDefault');
    });

    test('scopes form increasing permission levels', () {
      // readOnly is the most restrictive
      // fullAccessDisabledByDefault is the most permissive
      const scopes = PermissionRequestScope.values;
      expect(scopes.length, 7);
      expect(scopes.first, PermissionRequestScope.readOnly);
      expect(scopes.last, PermissionRequestScope.fullAccessDisabledByDefault);
    });
  });

  group('PermissionDecision', () {
    test('pending is initial state', () {
      expect(PermissionDecision.pending.name, 'pending');
    });

    test('all decisions are distinct', () {
      const decisions = PermissionDecision.values;
      expect(decisions.length, 5); // pending, allowOnce, allowForSession, deny, cancel
      expect(decisions.toSet().length, 5);
    });
  });

  group('PermissionRequest', () {
    test('is pending when decision is pending', () {
      const request = PermissionRequest(
        requestId: 'req-1',
        scope: PermissionRequestScope.workspaceWrite,
        reason: 'Modifying main.styio',
        createdAtIso8601: '2026-06-24T00:00:00Z',
      );
      expect(request.isPending, isTrue);
      expect(request.decision, PermissionDecision.pending);
    });

    test('decide transitions to allowOnce', () {
      const request = PermissionRequest(
        requestId: 'req-2',
        scope: PermissionRequestScope.workspaceWrite,
        reason: 'Creating new file',
        createdAtIso8601: '2026-06-24T00:00:00Z',
      );
      final decided = request.decide(PermissionDecision.allowOnce);
      expect(decided.isPending, isFalse);
      expect(decided.decision, PermissionDecision.allowOnce);
    });

    test('decide transitions to deny', () {
      const request = PermissionRequest(
        requestId: 'req-3',
        scope: PermissionRequestScope.fullAccessDisabledByDefault,
        reason: 'Full access requested',
        createdAtIso8601: '2026-06-24T00:00:00Z',
      );
      final decided = request.decide(PermissionDecision.deny);
      expect(decided.decision, PermissionDecision.deny);
    });

    test('serializes to JSON and preserves scope', () {
      const request = PermissionRequest(
        requestId: 'req-4',
        scope: PermissionRequestScope.toolchainManaged,
        reason: 'Running cargo build',
        createdAtIso8601: '2026-06-24T00:00:00Z',
        toolInvocationId: 'tool-1',
        decision: PermissionDecision.pending,
      );
      final json = request.toJson();
      expect(json['requestId'], 'req-4');
      expect(json['scope'], 'toolchainManaged');
      expect(json['reason'], 'Running cargo build');
      expect(json['toolInvocationId'], 'tool-1');
      expect(json['decision'], 'pending');
    });

    test('permission request with allowOnce serializes decision', () {
      const request = PermissionRequest(
        requestId: 'req-5',
        scope: PermissionRequestScope.readOnly,
        reason: 'Reading file',
        createdAtIso8601: '2026-06-24T00:00:00Z',
      );
      final decided = request.decide(PermissionDecision.allowForSession);
      final json = decided.toJson();
      expect(json['decision'], 'allowForSession');
    });
  });

  group('ToolInvocation', () {
    test('tracks tool call lifecycle', () {
      const invocation = ToolInvocation(
        invocationId: 'inv-1',
        toolName: 'read_file',
        scope: PermissionRequestScope.readOnly,
        status: ToolInvocationStatus.pending,
        arguments: {'path': 'main.styio'},
      );
      expect(invocation.invocationId, 'inv-1');
      expect(invocation.toolName, 'read_file');
      expect(invocation.scope, PermissionRequestScope.readOnly);
      expect(invocation.status, ToolInvocationStatus.pending);
    });

    test('copyWith transitions status', () {
      const invocation = ToolInvocation(
        invocationId: 'inv-2',
        toolName: 'edit_file',
        scope: PermissionRequestScope.workspaceWrite,
        status: ToolInvocationStatus.running,
        arguments: {'path': 'main.styio'},
      );
      final completed = invocation.copyWith(
        status: ToolInvocationStatus.completed,
        result: {'changed': true},
      );
      expect(completed.status, ToolInvocationStatus.completed);
      expect(completed.result['changed'], true);
      // Original unchanged
      expect(invocation.status, ToolInvocationStatus.running);
    });

    test('serializes to JSON including scope and status', () {
      const invocation = ToolInvocation(
        invocationId: 'inv-3',
        toolName: 'run_test',
        scope: PermissionRequestScope.toolchainManaged,
        status: ToolInvocationStatus.waitingForPermission,
        arguments: {'target': 'unit_tests'},
      );
      final json = invocation.toJson();
      expect(json['invocationId'], 'inv-3');
      expect(json['toolName'], 'run_test');
      expect(json['scope'], 'toolchainManaged');
      expect(json['status'], 'waitingForPermission');
    });
  });

  group('AgentSession audit events', () {
    test('audit event kinds cover permission and patch flows', () {
      const kinds = AgentAuditEventKind.values;
      final names = kinds.map((k) => k.name).toSet();
      expect(names.contains('sessionCreated'), isTrue);
      expect(names.contains('toolRequested'), isTrue);
      expect(names.contains('permissionRequested'), isTrue);
      expect(names.contains('permissionDecided'), isTrue);
      expect(names.contains('patchPreviewed'), isTrue);
      expect(names.contains('patchApplied'), isTrue);
    });

    test('audit event serializes with details', () {
      const event = AgentAuditEvent(
        eventId: 'evt-1',
        kind: AgentAuditEventKind.permissionRequested,
        sessionId: 'sess-1',
        createdAtIso8601: '2026-06-24T00:00:00Z',
        details: {'tool': 'edit_file', 'scope': 'workspaceWrite'},
      );
      final json = event.toJson();
      expect(json['eventId'], 'evt-1');
      expect(json['kind'], 'permissionRequested');
      expect(json['sessionId'], 'sess-1');
      expect((json['details'] as Map)['tool'], 'edit_file');
    });
  });

  group('AgentSession', () {
    test('copyWith preserves immutability', () {
      final session = const AgentSession(
        sessionId: 'sess-1',
        profileId: 'default',
        status: AgentSessionStatus.idle,
        turns: [],
        toolInvocations: [],
        permissionRequests: [],
        auditEvents: [],
      );

      final active = session.copyWith(status: AgentSessionStatus.active);
      expect(active.status, AgentSessionStatus.active);
      expect(session.status, AgentSessionStatus.idle); // original unchanged
    });

    test('appendAuditEvent adds event immutably', () {
      final session = const AgentSession(
        sessionId: 'sess-2',
        profileId: 'default',
        status: AgentSessionStatus.active,
        turns: [],
        toolInvocations: [],
        permissionRequests: [],
        auditEvents: [],
      );

      const event = AgentAuditEvent(
        eventId: 'evt-1',
        kind: AgentAuditEventKind.sessionCreated,
        sessionId: 'sess-2',
        createdAtIso8601: '2026-06-24T00:00:00Z',
      );

      final updated = session.appendAuditEvent(event);
      expect(updated.auditEvents.length, 1);
      expect(session.auditEvents.length, 0); // original unchanged
      expect(updated.auditEvents.first.eventId, 'evt-1');
    });

    test('session serializes with all collections', () {
      final session = const AgentSession(
        sessionId: 'sess-3',
        profileId: 'default-linux',
        status: AgentSessionStatus.completed,
        turns: [],
        toolInvocations: [
          ToolInvocation(
            invocationId: 'inv-1',
            toolName: 'read_file',
            scope: PermissionRequestScope.readOnly,
            status: ToolInvocationStatus.completed,
          ),
        ],
        permissionRequests: [
          PermissionRequest(
            requestId: 'req-1',
            scope: PermissionRequestScope.workspaceWrite,
            reason: 'Edit file',
            createdAtIso8601: '2026-06-24T00:00:00Z',
            decision: PermissionDecision.allowOnce,
          ),
        ],
        auditEvents: [],
      );

      final json = session.toJson();
      expect(json['sessionId'], 'sess-3');
      expect(json['status'], 'completed');
      expect((json['toolInvocations'] as List).length, 1);
      expect((json['permissionRequests'] as List).length, 1);
    });
  });

  group('Permission audit safety', () {
    test('fullAccessDisabledByDefault is never allowed without explicit decision', () {
      const request = PermissionRequest(
        requestId: 'req-audit',
        scope: PermissionRequestScope.fullAccessDisabledByDefault,
        reason: 'Admin operation',
        createdAtIso8601: '2026-06-24T00:00:00Z',
      );
      // Must be pending until explicitly decided
      expect(request.isPending, isTrue);
      expect(request.decision, PermissionDecision.pending);
    });

    test('readOnly does not require elevation for allow', () {
      const request = PermissionRequest(
        requestId: 'req-safe',
        scope: PermissionRequestScope.readOnly,
        reason: 'Reading diagnostics',
        createdAtIso8601: '2026-06-24T00:00:00Z',
        decision: PermissionDecision.allowOnce,
      );
      expect(request.isPending, isFalse);
      expect(request.decision, PermissionDecision.allowOnce);
      expect(request.scope, PermissionRequestScope.readOnly);
    });
  });
}
