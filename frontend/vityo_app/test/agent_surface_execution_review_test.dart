import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/agent/agent_surface.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  final widget = tester.widget<Widget>(finder);
  if (widget is FilledButton) {
    widget.onPressed?.call();
    return;
  }
  if (widget is OutlinedButton) {
    widget.onPressed?.call();
    return;
  }
  await tester.tap(finder);
}

void main() {
  testWidgets('agent surface exposes tool call review status', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    AgentIdeCommandSuggestion? appliedToolCommand;
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-command',
        toolId: 'runIdeCommand',
        input: '{"commandId":"runTests"}',
      ),
    );

    await _pumpSurface(
      tester,
      controller,
      onApplyIdeCommandSuggestion: (command) async {
        appliedToolCommand = command;
        return true;
      },
    );

    expect(
      find.byKey(const ValueKey('agent-tool-call-review-card')),
      findsOneWidget,
    );
    expect(find.text('Tool execution: review_required'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-tool-call-execution-call-command')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-approve-call-command')),
    );
    await tester.pump();

    expect(
      controller.toolCallExecutionPlan.executionFor('call-command')?.status,
      AgentToolCallExecutionStatus.ready,
    );
    expect(find.text('runIdeCommand · ready · call-command'), findsOneWidget);
    expect(find.text('Review decision: approved'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-run-approved')),
    );
    await tester.pump();

    expect(appliedToolCommand?.commandId, 'runTests');
    expect(controller.lastIdeCommandResultContext?.commandId, 'runTests');
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(
      controller.toolCallExecutionPlan.executionFor('call-command')?.status,
      AgentToolCallExecutionStatus.completed,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-draft-review')),
    );
    await tester.pump();

    expect(controller.draftPrompt, contains('Review pending agent tool calls'));
  });

  testWidgets('agent surface exposes workspace snapshot revert plan', (
    tester,
  ) async {
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    const patch = AgentCodePatch(
      patchId: 'surface-snapshot-patch',
      summary: 'Update value.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const _FakeAgentProviderAdapter(
        response: AgentProviderResponseEnvelope(
          requestId: 'surface-snapshot-request',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[
            AgentContentPart(
              kind: AgentContentPartKind.codePatch,
              text: 'Patch ready.',
              patch: patch,
            ),
          ],
        ),
      ),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    await controller.applyPendingPatchWithSnapshot(
      applier: AgentCodePatchApplier(editorController: editorController),
      snapshotService: AgentWorkspaceSnapshotService(
        editorController: editorController,
      ),
    );
    await _pumpSurface(
      tester,
      controller,
      onApplyWorkspaceRevertPlan: () async {
        controller.applyLastWorkspaceRevertPlan(
          AgentCodePatchApplier(editorController: editorController),
        );
      },
    );

    expect(
      find.byKey(const ValueKey('agent-workspace-snapshot-card')),
      findsOneWidget,
    );
    expect(find.text('Workspace snapshot: captured'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-workspace-revert-plan-summary')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-workspace-revert-draft-button')),
    );
    await tester.pump();

    expect(
      controller.draftPrompt,
      contains('Review the agent workspace revert plan'),
    );

    expect(editorController.document.text, 'value = 2\n');

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-workspace-revert-apply-button')),
    );
    await tester.pump();

    expect(editorController.document.text, 'value = 1\n');
    expect(controller.lastWorkspaceRevertPlan, isNull);
  });

  testWidgets('agent surface runs approved workspace patch tools', (
    tester,
  ) async {
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final workspaceStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: <String, DocumentState>{
        'main.styio': editorController.document,
      },
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    AgentCodePatch? appliedPatch;
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-apply-patch',
        toolId: 'applyWorkspacePatch',
        input:
            '{"patch":{"patchId":"patch-tool","summary":"Change value.","edits":[{"documentId":"main.styio","start":8,"end":9,"replacementText":"2"}]}}',
      ),
    );
    controller.approveToolCallExecution('call-apply-patch');

    await _pumpSurface(
      tester,
      controller,
      onApplyAgentWorkspacePatch: (patch) async {
        appliedPatch = patch;
        return AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ).apply(patch);
      },
      workspaceSnapshotService: AgentWorkspaceSnapshotService(
        editorController: editorController,
        workspaceDocumentStore: workspaceStore,
      ),
    );

    expect(
      find.text('applyWorkspacePatch · ready · call-apply-patch'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-run-approved')),
    );
    await tester.pump();

    expect(appliedPatch?.patchId, 'patch-tool');
    expect(
      controller
          .recentToolCallResultContexts
          .single
          .metadata['workspaceSnapshotCaptured'],
      isTrue,
    );
    expect(editorController.document.text, 'value = 2\n');
    expect(controller.workspaceCheckpointContext?.captureStatus, 'captured');
    expect(controller.workspaceCheckpointContext?.revertPlanStatus, 'ready');
    expect(controller.workspaceCheckpointContext?.revertReady, isTrue);
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(
      controller.toolCallExecutionPlan.executionFor('call-apply-patch')?.status,
      AgentToolCallExecutionStatus.completed,
    );
  });

  testWidgets('agent surface runs approved extension tools', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
      toolRegistry: AgentToolRegistry(
        tools: const <AgentToolDefinition>[
          ...AgentToolRegistry.defaultAgentTools,
          AgentToolDefinition(
            toolId: 'collectExtensionContext',
            displayName: 'Collect Extension Context',
            description: 'Collect context from an extension.',
            permissionMode: AgentToolPermissionMode.review,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    AgentToolCallDispatchRequest? receivedRequest;
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-extension',
        toolId: 'collectExtensionContext',
        input: '{"extensionId":"demo"}',
      ),
    );

    await _pumpSurface(
      tester,
      controller,
      onRunAgentExtensionTool: (request) async {
        receivedRequest = request;
        return AgentToolCallDispatchResult.success(
          callId: request.callId,
          toolId: request.toolId,
          output: '{"extension":"ok"}',
        );
      },
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-approve-call-extension')),
    );
    await tester.pump();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-run-approved')),
    );
    await tester.pump();

    expect(receivedRequest?.toolId, 'collectExtensionContext');
    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(
      controller.toolCallExecutionPlan.executionFor('call-extension')?.status,
      AgentToolCallExecutionStatus.completed,
    );
  });

  testWidgets('agent surface exposes controller recovery context tools', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-recovery',
        toolId: 'collectAgentRecoveryContext',
        input: '{}',
      ),
    );

    await _pumpSurface(tester, controller);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-run-approved')),
    );
    await tester.pump();

    expect(
      controller.recentToolCallResultContexts.single.output,
      contains('"source":"agent-recovery-context"'),
    );
    expect(
      controller.toolCallExecutionPlan.executionFor('call-recovery')?.status,
      AgentToolCallExecutionStatus.completed,
    );
  });

  testWidgets('agent surface replays tool execution journal', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.recordToolCallEvent(
      const AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: '{"path":"main.styio"}',
      ),
    );
    await controller.dispatchReadyToolCalls((request) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'temporary read failure',
      );
    });

    await _pumpSurface(tester, controller);

    expect(find.text('Replay plan: ready · requests 1'), findsOneWidget);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-tool-call-replay-journal')),
    );
    await tester.pump();

    expect(
      controller.toolCallTimeline.status,
      AgentToolCallTimelineStatus.complete,
    );
    expect(
      controller.toolCallReplayPlan.status,
      AgentToolCallReplayPlanStatus.blocked,
    );
    expect(
      controller.recentToolCallResultContexts.any(
        (result) => result.output.contains('"source":"agent-session-context"'),
      ),
      isTrue,
    );
  });

  testWidgets('agent surface shows blocked loop guard', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    for (final callId in <String>[
      'call-read-1',
      'call-read-2',
      'call-read-3',
    ]) {
      controller.recordToolCallEvent(
        AgentToolCallEvent.callStarted(
          callId: callId,
          toolId: 'readWorkspaceFile',
          input: '{"path":"$callId.styio"}',
        ),
      );
    }
    await controller.dispatchReadyToolCalls((request) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'temporary read failure',
      );
    });

    await _pumpSurface(tester, controller);

    expect(find.text('Loop guard: blocked'), findsOneWidget);
    expect(find.text('agent.loop.failedToolResultLimit:3'), findsOneWidget);
  });
}

Future<void> _pumpSurface(
  WidgetTester tester,
  AgentCodingSessionController controller, {
  Future<void> Function()? onApplyWorkspaceRevertPlan,
  AgentWorkspacePatchToolRunner? onApplyAgentWorkspacePatch,
  AgentWorkspaceSnapshotService? workspaceSnapshotService,
  AgentExtensionToolRunner? onRunAgentExtensionTool,
  Future<bool> Function(AgentIdeCommandSuggestion)? onApplyIdeCommandSuggestion,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 900,
          child: AgentSurface(
            platformTarget: PlatformTarget.web,
            viewportProfile: const ViewportProfile(
              family: ViewportFamily.desktop,
              width: 1200,
              height: 900,
            ),
            visibleModules: const [],
            adapterCapabilities: const [],
            sessionContext: _context(),
            codingController: controller,
            onApplyPendingPatch: () async {},
            onApplyWorkspaceRevertPlan: onApplyWorkspaceRevertPlan,
            onApplyAgentWorkspacePatch: onApplyAgentWorkspacePatch,
            workspaceSnapshotService: workspaceSnapshotService,
            onRunAgentExtensionTool: onRunAgentExtensionTool,
            onApplyIdeCommandSuggestion: onApplyIdeCommandSuggestion,
            onSaveProviderProfile: (profile, {bearerToken}) async {},
          ),
        ),
      ),
    ),
  );
}

AgentSessionContext _context() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}

class _FakeAgentProviderAdapter implements AgentProviderAdapter {
  const _FakeAgentProviderAdapter({required this.response});

  final AgentProviderResponseEnvelope response;

  @override
  String get adapterId => 'fake';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return response;
  }
}
