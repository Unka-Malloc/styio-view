import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_code_patch_applier.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_history_store.dart';
import 'package:vityo_app/src/view_ide/agent/agent_prompt_profile_store.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/agent/agent_surface.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';
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
  if (widget is TextButton) {
    widget.onPressed?.call();
    return;
  }
  if (widget is IconButton) {
    widget.onPressed?.call();
    return;
  }
  await tester.tap(finder);
}

void main() {
  testWidgets('agent surface displays active workspace coding skills', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Active Coding Skills'), findsOneWidget);
    expect(find.textContaining('active /'), findsOneWidget);
    expect(find.text('Styio Language Service Truth'), findsOneWidget);
    expect(find.text('Styio IDE Feature Loop'), findsOneWidget);
    expect(find.text('Styio Fixture Confidence Matrix'), findsOneWidget);
    expect(find.text('Reference-Grounded IDE Development'), findsOneWidget);
    expect(
      find.textContaining('Styio source files require StyioService-backed'),
      findsOneWidget,
    );
  });

  testWidgets('agent surface selects active agent runtime', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agent Runtime'), findsOneWidget);
    expect(find.text('Vityo Coding Agent'), findsOneWidget);
    expect(find.text('Vityo Review Agent'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-runtime-vityo-recovery-agent')),
      findsNothing,
    );

    final reviewAgentChip = find.byKey(
      const ValueKey('agent-runtime-vityo-review-agent'),
    );
    await tester.ensureVisible(reviewAgentChip);
    await tester.tap(reviewAgentChip);
    await tester.pump();

    expect(controller.activeAgentId, 'vityo-review-agent');
    expect(find.textContaining('Active: Vityo Review Agent'), findsOneWidget);
  });

  testWidgets('agent surface displays recovery action from history', (
    tester,
  ) async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    const savedProfiles = <AgentPromptProfileManifestEntry>[
      AgentPromptProfileManifestEntry(
        key: 'agent.provider.backup-cloud',
        profileId: 'backup-cloud',
        displayName: 'Backup Cloud',
        route: 'web-hosted',
        protocol: 'openai-compatible',
        model: 'gpt-backup',
        requiresCredential: false,
      ),
    ];
    AgentIdeCommandSuggestion? appliedRecoveryCommand;
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-failed',
          profileId: profile.profileId,
          providerKind: AgentProviderKind.cloudOpenAICompatible.wireValue,
          prompt: 'Recover this failed prompt.',
          outcome: AgentCodingSessionOutcome.failed,
          errorMessage: 'provider timed out',
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          metadata: const <String, Object?>{
            'validationResult': <String, Object?>{
              'status': 'failed',
              'completedCommandIds': <String>['saveAll'],
              'failedCommandIds': <String>['runTests'],
              'missingCommandIds': <String>['runTests'],
            },
            'validationPipeline': <String, Object?>{
              'status': 'failed',
              'nextCommandId': 'runTests',
              'progressNumerator': 1,
              'progressDenominator': 5,
            },
            'toolCallExecutionJournal': <String, Object?>{
              'status': 'blocked',
              'entryCount': 1,
              'replayCandidateCount': 0,
              'entries': <Object?>[
                <String, Object?>{
                  'callId': 'call-apply',
                  'toolId': 'applyWorkspacePatch',
                  'executionStatus': 'blocked',
                  'permissionStatus': 'denied',
                  'blockingIssueCodes': <String>[
                    'agent.tool.permission.denied.applyWorkspacePatch',
                  ],
                },
              ],
            },
            'validationFailedCommandResults': <Object?>[
              <String, Object?>{
                'commandId': 'runTests',
                'applied': false,
                'message': 'runTests failed.',
              },
            ],
          },
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: profile,
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
      sessionHistoryStore: _MemoryAgentCodingSessionHistoryStore(history),
      sessionHistoryWorkspaceId: 'demo',
    );
    addTearDown(controller.dispose);
    await controller.loadSessionHistory();

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
              sessionContext: _context(savedProviderProfiles: savedProfiles),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedRecoveryCommand = command;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-recovery-action-card')),
      findsOneWidget,
    );
    expect(find.text('Recovery Available'), findsOneWidget);
    expect(find.text('Retry same provider'), findsWidgets);
    expect(
      find.byKey(const ValueKey('agent-recovery-validation-summary')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Last validation: failed · pipeline failed 1/5 · next runTests',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-recovery-audit-summary')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Audit: blocked · 1 tool call(s) · needs review'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-recovery-audit-permission-denied')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Permission denied tools: applyWorkspacePatch'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-recovery-audit-blocking-issues')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('agent-recovery-audit-provider-recovery-block'),
      ),
      findsOneWidget,
    );
    final runRecoveryButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Run Recovery'),
    );
    expect(runRecoveryButton.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('agent-recovery-draft-audit-fix')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recovery-draft-audit-fix')),
    );
    await tester.pump();

    expect(
      controller.draftPrompt,
      'Resolve the latest agent recovery audit before retrying provider recovery. '
      'Permission denied tools: applyWorkspacePatch. '
      'Blocking issues: agent.tool.permission.denied.applyWorkspacePatch. '
      'Revise the requested tool chain or propose a safer manual recovery path.',
    );
    expect(find.text('Validation failed commands: runTests'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-recovery-validation-failure-evidence')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-recovery-draft-validation-fix')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-recovery-continue-validation')),
      findsOneWidget,
    );
    expect(find.text('Fail over provider'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-recovery-command-failoverProvider')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recovery-restore-prompt')),
    );
    await tester.pump();

    expect(controller.draftPrompt, 'Recover this failed prompt.');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('agent-prompt-input')),
          )
          .controller
          ?.text,
      'Recover this failed prompt.',
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recovery-continue-validation')),
    );
    await tester.pump();

    expect(appliedRecoveryCommand?.commandId, 'runTests');

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recovery-draft-validation-fix')),
    );
    await tester.pump();

    expect(
      controller.draftPrompt,
      'Fix the latest agent validation failure. Failed validation commands: runTests. Failure evidence: runTests · runTests failed.',
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recovery-command-failoverProvider')),
    );
    await tester.pump();

    expect(appliedRecoveryCommand?.commandId, 'failoverAgentProvider');
    expect(appliedRecoveryCommand?.input, 'agent.provider.backup-cloud');
  });

  testWidgets('agent surface dispatches confirmed recovery action', (
    tester,
  ) async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final adapter = _RecoveryDispatchSurfaceAgentProviderAdapter();
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord.failure(
          requestId: 'agent-failed',
          profile: profile,
          providerKind: AgentProviderKind.cloudOpenAICompatible,
          prompt: 'Retry this failed prompt.',
          errorMessage: 'provider timed out',
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: profile,
      adapter: adapter,
      contextProvider: _context,
      sessionHistoryStore: _MemoryAgentCodingSessionHistoryStore(history),
      sessionHistoryWorkspaceId: 'demo',
    );
    addTearDown(controller.dispose);
    await controller.loadSessionHistory();

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recovery-dispatch-confirmed')),
    );
    await tester.pumpAndSettle();

    expect(adapter.requests.single.userPrompt, 'Retry this failed prompt.');
    expect(controller.draftPrompt, isEmpty);
    expect(
      find.byKey(const ValueKey('agent-recovery-dispatch-status')),
      findsOneWidget,
    );
    expect(find.text('Agent recovery request dispatched.'), findsOneWidget);
    expect(find.text('recovery ok'), findsWidgets);
  });

  testWidgets('agent surface displays structured coding plan', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PlanAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Plan the edit.');
    await controller.sendPrompt();

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agent Coding Plan'), findsOneWidget);
    expect(find.text('Update active document safely.'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('1. Inspect IDE facts.'), findsOneWidget);
    expect(find.text('2. Prepare patch.'), findsOneWidget);
    expect(find.text('Acceptance Criteria'), findsOneWidget);
    expect(find.text('- Patch preview is shown.'), findsOneWidget);
  });

  testWidgets('agent surface displays structured diagnostic summary', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _DiagnosticSummaryAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Summarize diagnostics.');
    await controller.sendPrompt();

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Agent Diagnostic Summary'), findsOneWidget);
    expect(find.text('error'), findsOneWidget);
    expect(find.text('1 diagnostic(s)'), findsOneWidget);
    expect(find.text('src/parser.cc'), findsOneWidget);
    expect(find.text('Build failed.'), findsOneWidget);
    expect(find.text('Parser target failed with one error.'), findsOneWidget);
    expect(find.text('Suggested Commands'), findsOneWidget);
    expect(find.text('runBuild'), findsOneWidget);
  });

  testWidgets('agent surface previews pending patch edit ranges', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    controller.updatePrompt('Follow up while patch applies.');

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Patch patch-1'), findsOneWidget);
    expect(find.textContaining('base rev 1'), findsOneWidget);
    expect(find.textContaining('replace main.styio:8-9'), findsOneWidget);
    expect(find.textContaining('create helper.txt:0-0'), findsOneWidget);
    expect(find.textContaining('delete obsolete.txt:0-0'), findsOneWidget);
    expect(
      find.text(
        'Workspace edit plan: 3 file(s), 1 text edit(s), 2 file operation(s)',
      ),
      findsOneWidget,
    );
    expect(find.text('2 workspace file(s)'), findsOneWidget);
    expect(
      find.text('resolved value/variable · ref read · 1 semantic'),
      findsOneWidget,
    );
  });

  testWidgets('agent surface displays structured IDE command suggestions', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _CommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();
    AgentIdeCommandSuggestion? appliedCommand;

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
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommand = command;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Suggested IDE Commands'), findsOneWidget);
    expect(find.textContaining('renameSymbol'), findsOneWidget);
    expect(find.textContaining('input price'), findsOneWidget);
    expect(find.textContaining('Use the safe rename refactor'), findsOneWidget);

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Command'),
    );
    await tester.pump();

    expect(appliedCommand?.commandId, 'renameSymbol');
    expect(appliedCommand?.input, 'price');
    expect(find.text('Command renameSymbol applied.'), findsOneWidget);
  });

  testWidgets('agent surface applies registered toolchain IDE commands', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _ClangCppVersionCommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Use Clang 18 with C++23.');
    await controller.sendPrompt();
    AgentIdeCommandSuggestion? appliedCommand;

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
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommand = command;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'selectClangCppVersion · input fake-clang-18 c++23 · Use the registered Clang/C++ version manager.',
      ),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Command'),
    );
    await tester.pump();

    expect(appliedCommand?.commandId, 'selectClangCppVersion');
    expect(appliedCommand?.input, 'fake-clang-18 c++23');
    expect(find.text('Command selectClangCppVersion applied.'), findsOneWidget);
  });

  testWidgets('agent surface blocks registered commands missing input', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _MissingInputCommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Rename without a target name.');
    await controller.sendPrompt();
    var applied = false;

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
              onApplyIdeCommandSuggestion: (command) async {
                applied = true;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('renameSymbol'), findsOneWidget);
    expect(
      find.text('Missing required input: New symbol name'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Expected input: New symbol name valid for the active language syntax contract.',
      ),
      findsOneWidget,
    );
    expect(find.text('Examples: newName'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Apply Command'), findsNothing);
    expect(applied, isFalse);
  });

  testWidgets('agent pending IDE command reaches next provider request', (
    tester,
  ) async {
    final adapter = _RecordingCommandSuggestionAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();
    controller.updatePrompt('Explain the pending command.');
    await controller.sendPrompt();

    expect(adapter.requests.length, 2);
    final pendingCommand =
        adapter.requests.last.context.agent.pendingIdeCommands.single;
    expect(pendingCommand.commandId, 'renameSymbol');
    expect(pendingCommand.input, 'price');
    expect(pendingCommand.reason, 'Use the safe rename refactor.');
    expect(pendingCommand.text, 'Use Rename Symbol.');
    expect(
      adapter
          .requests
          .last
          .context
          .agent
          .recentIdeCommandSuggestions
          .single
          .commandId,
      'renameSymbol',
    );
  });

  testWidgets(
    'agent applied IDE command result reaches next provider request',
    (tester) async {
      final adapter = _RecordingCommandSuggestionAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Rename value.');
      await controller.sendPrompt();

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
                onApplyIdeCommandSuggestion: (command) async => true,
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Apply Command'),
      );
      await tester.pump();

      controller.updatePrompt('Continue after command.');
      await controller.sendPrompt();

      expect(adapter.requests.length, 2);
      final nextContext = adapter.requests.last.context;
      expect(nextContext.agent.pendingIdeCommands, isEmpty);
      expect(nextContext.commands.lastResult?.commandId, 'renameSymbol');
      expect(nextContext.commands.lastResult?.input, 'price');
      expect(nextContext.commands.lastResult?.applied, isTrue);
      expect(
        nextContext.commands.lastResult?.message,
        'Command renameSymbol applied.',
      );
      expect(
        nextContext.commands.lastResult?.metadata['source'],
        'agent-surface',
      );
    },
  );

  testWidgets(
    'agent surface preserves structured IDE command result metadata',
    (tester) async {
      final adapter = _RecordingCommandSuggestionAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      AgentCommandResultContext? structuredResult;

      controller.updatePrompt('Rename value.');
      await controller.sendPrompt();

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
                onApplyIdeCommandSuggestion: (command) async {
                  structuredResult = AgentCommandResultContext(
                    commandId: command.commandId,
                    input: command.input,
                    applied: true,
                    message: 'Structured command result.',
                    metadata: const <String, Object?>{
                      'buildResult': <String, Object?>{'exitCode': 0},
                    },
                    completedAt: DateTime.utc(2026, 5, 19, 13),
                  );
                  return true;
                },
                onResolveIdeCommandResult: (command) => structuredResult,
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );
      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Apply Command'),
      );
      await tester.pump();

      expect(find.text('Structured command result.'), findsOneWidget);

      controller.updatePrompt('Continue after structured command.');
      await controller.sendPrompt();

      final lastResult = adapter.requests.last.context.commands.lastResult;
      expect(lastResult?.message, 'Structured command result.');
      expect(lastResult?.metadata['buildResult'], <String, Object?>{
        'exitCode': 0,
      });
    },
  );

  testWidgets('agent preserves pending IDE command when follow-up fails', (
    tester,
  ) async {
    final adapter = _FailingSecondCommandRequestAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();
    expect(
      controller.lastResponse?.contentParts.single.ideCommand?.commandId,
      'renameSymbol',
    );

    controller.updatePrompt('Explain pending command.');
    final response = await controller.sendPrompt();

    expect(response, isNull);
    expect(adapter.requests.length, 2);
    expect(
      adapter.requests.last.context.agent.pendingIdeCommands.single.commandId,
      'renameSymbol',
    );
    expect(
      controller.lastResponse?.contentParts.single.ideCommand?.commandId,
      'renameSymbol',
    );
    expect(
      controller.lastProviderFailure?.kind,
      AgentProviderTransportFailureKind.timeout,
    );
  });

  testWidgets(
    'agent preserves pending IDE command when follow-up is cancelled',
    (tester) async {
      final adapter = _DelayedSecondCommandRequestAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Rename value.');
      await controller.sendPrompt();
      expect(
        controller.lastResponse?.contentParts.single.ideCommand?.commandId,
        'renameSymbol',
      );

      controller.updatePrompt('Explain pending command.');
      final sendFuture = controller.sendPrompt();
      await adapter.secondRequestStarted.future;

      controller.cancelActiveRequest();
      expect(
        controller.lastResponse?.contentParts.single.ideCommand?.commandId,
        'renameSymbol',
      );
      expect(controller.lastError, 'Agent request cancelled.');

      adapter.completeSecond();
      expect(await sendFuture, isNull);
      expect(
        controller.lastResponse?.contentParts.single.ideCommand?.commandId,
        'renameSymbol',
      );
    },
  );

  testWidgets(
    'agent surface accepts persistence native and debug command suggestions',
    (tester) async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _NativeDebugCommandSuggestionAgentProviderAdapter(),
        contextProvider: _nativeBuildReadyContext,
      );
      addTearDown(controller.dispose);
      controller.updatePrompt('Build and debug.');
      await controller.sendPrompt();
      final appliedCommands = <String>[];

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
                sessionContext: _nativeBuildReadyContext(),
                codingController: controller,
                onApplyPendingPatch: () async {},
                onApplyIdeCommandSuggestion: (command) async {
                  appliedCommands.add(command.commandId);
                  return true;
                },
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('saveAll'), findsOneWidget);
      expect(
        find.text('runBuild · Use the registered build command.'),
        findsOneWidget,
      );
      expect(find.textContaining('startDebugging'), findsOneWidget);
      expect(find.textContaining('refreshLanguageService'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Apply Command'),
        findsNWidgets(4),
      );

      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Apply Command').first,
      );
      await tester.pump();
      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Apply Command').at(2),
      );
      await tester.pump();
      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Apply Command').last,
      );
      await tester.pump();

      expect(appliedCommands, <String>[
        'saveAll',
        'startDebugging',
        'refreshLanguageService',
      ]);
    },
  );

  testWidgets('agent surface blocks native tool commands that are not ready', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _RunBuildCommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Build without tools.');
    await controller.sendPrompt();
    final appliedCommands = <AgentIdeCommandSuggestion>[];

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
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('runBuild · Use the registered build command.'),
      findsOneWidget,
    );
    expect(find.textContaining('Command not ready'), findsOneWidget);
    expect(
      find.textContaining(
        'Requires a registered cmake or ninja build-tool toolchain.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Apply Command'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Open Settings'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-recover-command-runBuild-openSettings')),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'openSettings');
    expect(appliedCommands.single.prerequisiteForCommandId, 'runBuild');
    expect(
      find.text(
        'Command openSettings applied. Review Settings before retrying runBuild.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Retry Original Command'),
      findsNothing,
    );
  });

  testWidgets('agent surface offers required command for dirty native tools', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _RunBuildCommandSuggestionAgentProviderAdapter(),
      contextProvider: _dirtyNativeBuildReadyContext,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Build dirty workspace.');
    await controller.sendPrompt();
    final appliedCommands = <AgentIdeCommandSuggestion>[];

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
              sessionContext: _dirtyNativeBuildReadyContext(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('runBuild · Use the registered build command.'),
      findsOneWidget,
    );
    expect(find.textContaining('Command not ready'), findsOneWidget);
    expect(
      find.textContaining('Requires saveAll before runBuild'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Apply Command'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Apply Required Command: saveAll'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Required Command: saveAll'),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'saveAll');
    expect(appliedCommands.single.prerequisiteForCommandId, 'runBuild');
    expect(
      find.widgetWithText(OutlinedButton, 'Retry Original Command'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Retry Original Command'),
    );
    await tester.pump();

    expect(appliedCommands.map((command) => command.commandId), <String>[
      'saveAll',
      'runBuild',
    ]);
    expect(appliedCommands.last.prerequisiteForCommandId, isNull);
  });

  testWidgets('agent surface offers runBuild for CMake static analysis', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _StaticAnalysisCommandSuggestionAgentProviderAdapter(),
      contextProvider: _cmakeStaticAnalysisBlockedContext,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Analyze CMake project.');
    await controller.sendPrompt();
    final appliedCommands = <AgentIdeCommandSuggestion>[];

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
              sessionContext: _cmakeStaticAnalysisBlockedContext(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('runStaticAnalysis · Run clang-tidy through IDE command.'),
      findsOneWidget,
    );
    expect(find.textContaining('Command not ready'), findsOneWidget);
    expect(
      find.textContaining('compile_commands.json is missing'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Apply Command'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Apply Required Command: runBuild'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey(
          'agent-apply-required-command-runStaticAnalysis-runBuild',
        ),
      ),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'runBuild');
    expect(
      appliedCommands.single.prerequisiteForCommandId,
      'runStaticAnalysis',
    );
  });

  testWidgets('agent surface displays recent IDE command results', (
    tester,
  ) async {
    final saveCompletedAt = DateTime.utc(2026, 5, 19, 1, 2, 3);
    final saveAllCompletedAt = DateTime.utc(2026, 5, 19, 1, 3, 4);
    final checkpointCompletedAt = DateTime.utc(2026, 5, 19, 1, 4, 5);
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const [],
      lastCommandResult: AgentCommandResultContext(
        commandId: 'formatActiveDocument',
        applied: true,
        message: 'Format completed.',
        metadata: const <String, Object?>{
          'formatResult': <String, Object?>{
            'status': 'passed',
            'changed': true,
          },
        },
        completedAt: saveCompletedAt,
      ),
      recentCommandResults: <AgentCommandResultContext>[
        AgentCommandResultContext(
          commandId: 'formatActiveDocument',
          applied: true,
          message: 'Format completed.',
          metadata: const <String, Object?>{
            'formatResult': <String, Object?>{
              'status': 'passed',
              'changed': true,
            },
          },
          completedAt: saveCompletedAt,
        ),
        AgentCommandResultContext(
          commandId: 'runStaticAnalysis',
          applied: false,
          message: 'Static analysis failed.',
          metadata: const <String, Object?>{
            'staticAnalysisResult': <String, Object?>{
              'status': 'failed',
              'diagnosticCount': 2,
            },
            'backendRouteSelection': <String, Object?>{
              'routeKind': 'local-cli',
              'adapterKind': 'cli',
              'allowed': true,
              'previewOnly': false,
            },
          },
          completedAt: checkpointCompletedAt,
        ),
        AgentCommandResultContext(
          commandId: 'collectAgentCodingCheckpoint',
          applied: true,
          message: 'Agent coding checkpoint collected.',
          metadata: const <String, Object?>{
            'workspaceDiagnostics': <String, Object?>{'totalCount': 2},
            'sourceControl': <String, Object?>{'changeCount': 1},
            'sourceControlDiff': <String, Object?>{
              'path': 'src/main.styio',
              'lineCount': 7,
            },
          },
          completedAt: saveAllCompletedAt,
        ),
      ],
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-recent-native-tools',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-clang-format-formatter',
            kind: ToolchainKind.formatter,
            displayName: 'clang-format Formatter',
            executablePath: '/usr/bin/clang-format',
            active: true,
            metadata: <String, Object?>{'toolFamily': 'clang-format'},
          ),
          ToolchainStateEntry(
            id: 'native-clang-tidy-static-analyzer',
            kind: ToolchainKind.staticAnalyzer,
            displayName: 'clang-tidy Static Analyzer',
            executablePath: '/usr/bin/clang-tidy',
            active: true,
            metadata: <String, Object?>{'toolFamily': 'clang-tidy'},
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: () => context,
    );
    final appliedCommands = <AgentIdeCommandSuggestion>[];
    addTearDown(controller.dispose);

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
              sessionContext: context,
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Recent IDE Commands'), findsOneWidget);
    expect(find.text('formatActiveDocument · applied'), findsOneWidget);
    expect(
      find.text('Completed ${saveCompletedAt.toIso8601String()}'),
      findsOneWidget,
    );
    expect(find.text('Format completed.'), findsOneWidget);
    expect(find.text('format passed · changed yes'), findsOneWidget);
    expect(find.text('runStaticAnalysis · not applied'), findsOneWidget);
    expect(
      find.text('Completed ${saveAllCompletedAt.toIso8601String()}'),
      findsOneWidget,
    );
    expect(find.text('Static analysis failed.'), findsOneWidget);
    expect(
      find.text(
        'static analysis failed · diagnostics 2 · route local-cli via cli',
      ),
      findsOneWidget,
    );
    expect(find.text('collectAgentCodingCheckpoint · applied'), findsOneWidget);
    expect(find.text('Agent coding checkpoint collected.'), findsOneWidget);
    expect(
      find.text(
        'checkpoint diagnostics 2 · source changes 1 · diff src/main.styio 7 lines',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Retry Command'),
      findsNWidgets(3),
    );

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('agent-retry-recent-command-runStaticAnalysis-1'),
      ),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'runStaticAnalysis');
    expect(appliedCommands.single.reason, 'Retry recent runStaticAnalysis.');
  });

  testWidgets('agent surface gates recent command retry readiness', (
    tester,
  ) async {
    final context = _dirtyNativeBuildReadyContext(
      recentCommandResults: const <AgentCommandResultContext>[
        AgentCommandResultContext(
          commandId: 'runBuild',
          applied: false,
          message: 'Build blocked by dirty workspace.',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: () => context,
    );
    final appliedCommands = <AgentIdeCommandSuggestion>[];
    addTearDown(controller.dispose);

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
              sessionContext: context,
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('runBuild · not applied'), findsOneWidget);
    expect(find.textContaining('Retry not ready'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry Command'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Apply Required Command: saveAll'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey(
          'agent-retry-recent-required-command-runBuild-saveAll-0',
        ),
      ),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'saveAll');
    expect(appliedCommands.single.prerequisiteForCommandId, 'runBuild');
  });

  testWidgets('agent surface explains recent retry missing input', (
    tester,
  ) async {
    final context = _dirtyNativeBuildReadyContext(
      recentCommandResults: const <AgentCommandResultContext>[
        AgentCommandResultContext(
          commandId: 'renameSymbol',
          applied: false,
          message: 'Rename skipped.',
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: () => context,
    );
    final appliedCommands = <AgentIdeCommandSuggestion>[];
    addTearDown(controller.dispose);

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
              sessionContext: context,
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('renameSymbol · not applied'), findsOneWidget);
    expect(find.text('Retry requires input: New symbol name'), findsOneWidget);
    expect(
      find.text(
        'Expected input: New symbol name valid for the active language syntax contract.',
      ),
      findsOneWidget,
    );
    expect(find.text('Examples: newName'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry Command'), findsNothing);
    expect(appliedCommands, isEmpty);
  });

  testWidgets('agent surface applies required command from recent metadata', (
    tester,
  ) async {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      recentCommandResults: const <AgentCommandResultContext>[
        AgentCommandResultContext(
          commandId: 'runTests',
          applied: false,
          message: 'Run Tests blocked before build.',
          metadata: <String, Object?>{
            'testResult': <String, Object?>{
              'status': 'blocked',
              'requiredCommand': 'runBuild',
            },
          },
        ),
      ],
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-required-command-metadata',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-ctest-runner',
            kind: ToolchainKind.testRunner,
            displayName: 'CTest Runner',
            executablePath: '/usr/bin/ctest',
            active: true,
            metadata: <String, Object?>{'toolFamily': 'ctest'},
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: () => context,
    );
    final appliedCommands = <AgentIdeCommandSuggestion>[];
    addTearDown(controller.dispose);

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
              sessionContext: context,
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('runTests · not applied'), findsOneWidget);
    expect(find.text('tests blocked · requires runBuild'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry Command'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Apply Required Command: runBuild'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey(
          'agent-retry-recent-required-command-runTests-runBuild-0',
        ),
      ),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'runBuild');
    expect(appliedCommands.single.prerequisiteForCommandId, 'runTests');
  });

  testWidgets('agent surface blocks retry for route-blocked recent command', (
    tester,
  ) async {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      recentCommandResults: const <AgentCommandResultContext>[
        AgentCommandResultContext(
          commandId: 'runBuild',
          applied: false,
          message: 'Run Build blocked by backend route.',
          metadata: <String, Object?>{
            'backendRouteSelection': <String, Object?>{
              'routeKind': 'blocked',
              'adapterKind': 'none',
              'allowed': false,
              'previewOnly': false,
              'blockedReason': 'no-backend-route',
            },
          },
        ),
      ],
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-route-blocked-retry',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-cmake-build-tool',
            kind: ToolchainKind.buildTool,
            displayName: 'CMake Build Tool',
            executablePath: '/usr/bin/cmake',
            active: true,
            metadata: <String, Object?>{'toolFamily': 'cmake'},
          ),
        ],
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: () => context,
    );
    final appliedCommands = <AgentIdeCommandSuggestion>[];
    addTearDown(controller.dispose);

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
              sessionContext: context,
              codingController: controller,
              onApplyPendingPatch: () async {},
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommands.add(command);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('runBuild · not applied'), findsOneWidget);
    expect(
      find.text('route blocked via none · blocked no-backend-route'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Retry Command'), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Open Settings'),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('agent-recover-recent-command-runBuild-openSettings-0'),
      ),
    );
    await tester.pump();

    expect(appliedCommands.single.commandId, 'openSettings');
    expect(appliedCommands.single.prerequisiteForCommandId, 'runBuild');
    expect(
      find.text(
        'Command openSettings applied. Review Settings before retrying runBuild.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Retry Original Command'),
      findsNothing,
    );
  });

  testWidgets(
    'agent surface offers settings recovery for failed toolchain selection',
    (tester) async {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value := 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        recentCommandResults: const <AgentCommandResultContext>[
          AgentCommandResultContext(
            commandId: 'selectClangCppVersion',
            input: 'missing-clang c++23',
            applied: false,
            message: 'Clang C++ version was not found.',
            metadata: <String, Object?>{
              'toolchainSelectionStatus': 'missing',
              'toolchainId': 'missing-clang',
              'cppStandard': 'c++23',
            },
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: () => context,
      );
      final appliedCommands = <AgentIdeCommandSuggestion>[];
      addTearDown(controller.dispose);

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
                sessionContext: context,
                codingController: controller,
                onApplyPendingPatch: () async {},
                onApplyIdeCommandSuggestion: (command) async {
                  appliedCommands.add(command);
                  return true;
                },
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('selectClangCppVersion · not applied'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Retry Command'),
        findsNothing,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Open Settings'),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(
          const ValueKey(
            'agent-recover-recent-command-selectClangCppVersion-openSettings-0',
          ),
        ),
      );
      await tester.pump();

      expect(appliedCommands.single.commandId, 'openSettings');
      expect(
        appliedCommands.single.prerequisiteForCommandId,
        'selectClangCppVersion',
      );
      expect(
        find.text(
          'Command openSettings applied. Review Settings before retrying selectClangCppVersion.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Retry Original Command'),
        findsNothing,
      );
    },
  );

  testWidgets('agent surface blocks debug commands that are not ready', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _StartDebugCommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Start debugger without launch.');
    await controller.sendPrompt();
    var applied = false;

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
              onApplyIdeCommandSuggestion: (command) async {
                applied = true;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('startDebugging'), findsOneWidget);
    expect(find.textContaining('Command not ready'), findsOneWidget);
    expect(
      find.textContaining('Requires a ready debug launch configuration.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Apply Command'), findsNothing);
    expect(applied, isFalse);
  });

  testWidgets('agent surface reports rejected IDE command suggestions', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _CommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();

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
              onApplyIdeCommandSuggestion: (command) async => false,
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Command'),
    );
    await tester.pump();

    expect(find.text('Command renameSymbol was not applied.'), findsOneWidget);
  });

  testWidgets('agent surface disables IDE command while applying', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _CommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();
    controller.updatePrompt('Follow up while command applies.');
    final completer = Completer<bool>();

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
              onApplyIdeCommandSuggestion: (command) => completer.future,
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Command'),
    );
    await tester.pump();

    expect(find.text('Applying Command...'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send'),
    );
    expect(sendButton.onPressed, isNull);
    final profileSaveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('agent-profile-save-button')),
    );
    expect(profileSaveButton.onPressed, isNull);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Applying Command...'),
          )
          .onPressed,
      isNull,
    );

    completer.complete(true);
    await tester.pump();

    expect(find.text('Command renameSymbol applied.'), findsOneWidget);
  });

  testWidgets('agent surface disables provider retry while command applies', (
    tester,
  ) async {
    final adapter = _FailingSecondCommandRequestAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    final completer = Completer<bool>();

    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();
    controller.updatePrompt('Trigger provider failure.');
    await controller.sendPrompt();
    controller.updatePrompt('Retry while command applies.');

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
              onApplyIdeCommandSuggestion: (command) => completer.future,
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Command'),
    );
    await tester.pump();

    final retryButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('agent-provider-retry-button')),
    );
    expect(retryButton.onPressed, isNull);

    completer.complete(true);
    await tester.pump();
  });

  testWidgets('agent surface reports IDE command application errors', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _CommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Rename value.');
    await controller.sendPrompt();

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
              onApplyIdeCommandSuggestion: (command) async {
                throw StateError('secret-token');
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Apply Command'),
    );
    await tester.pump();

    expect(find.text('Command renameSymbol failed.'), findsOneWidget);
    expect(find.textContaining('secret-token'), findsNothing);
  });

  testWidgets('agent surface does not apply unregistered IDE commands', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _UnsupportedCommandSuggestionAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Run unsupported command.');
    await controller.sendPrompt();
    var applied = false;

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
              onApplyIdeCommandSuggestion: (command) async {
                applied = true;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('deleteWorkspace · This is not registered.'),
      findsOneWidget,
    );
    expect(find.text('Unsupported command'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Apply Command'), findsNothing);
    expect(applied, isFalse);
  });

  testWidgets('agent surface reports hidden patch preview edits', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _LargePatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change several values.');
    await controller.sendPrompt();
    String? appliedCommandId;

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
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommandId = command.commandId;
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Pending patch: Large patch (7 edit(s))'),
      findsOneWidget,
    );
    expect(find.text('Coding loop gate'), findsOneWidget);
    expect(find.text('Change review: needsReview'), findsOneWidget);
    expect(
      find.text('Review required before applying agent changes.'),
      findsOneWidget,
    );
    expect(
      find.text('Validation waits until the reviewed patch is applied.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Review actions: reviewWorkspaceEditPreview'),
      findsOneWidget,
    );
    expect(find.textContaining('applyPendingPatch'), findsOneWidget);
    expect(find.textContaining('dismissPendingPatch'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Collect Checkpoint'),
      findsOneWidget,
    );
    expect(find.text('+ 2 more edit(s) hidden from preview'), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(OutlinedButton, 'Collect Checkpoint'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Collect Checkpoint'));
    await tester.pump();

    expect(appliedCommandId, 'collectAgentCodingCheckpoint');
  });

  testWidgets('agent surface displays applied patch operation counts', (
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
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _ReplacePatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    controller.applyPendingPatch(
      AgentCodePatchApplier(editorController: editorController),
    );
    final patchApplicationTurn = controller.conversationTurns.last;

    expect(patchApplicationTurn.role, AgentConversationRole.user);
    expect(
      patchApplicationTurn.text,
      contains('IDE patch application result:'),
    );
    expect(patchApplicationTurn.text, contains('patchId: patch-replace'));
    expect(patchApplicationTurn.text, contains('patchDocumentIds: main.styio'));
    expect(patchApplicationTurn.text, contains('patchEditCount: 1'));
    expect(
      patchApplicationTurn.text,
      contains('patchOperationCounts: replace 1'),
    );
    expect(patchApplicationTurn.text, contains('applied: true'));
    expect(patchApplicationTurn.text, contains('pendingPatchRetained: false'));
    expect(patchApplicationTurn.text, contains('operationCounts: replace 1'));
    expect(patchApplicationTurn.text, contains('changedDocuments: main.styio'));
    final appliedCommandIds = <String>[];

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
              onApplyIdeCommandSuggestion: (command) async {
                appliedCommandIds.add(command.commandId);
                return true;
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Applied 1 agent patch edit(s). Operations: replace 1.'),
      findsOneWidget,
    );
    expect(find.text('Changed files: main.styio'), findsOneWidget);
    expect(find.text('Validation plan: ready'), findsOneWidget);
    expect(
      find.text('Generated code was applied and needs validation.'),
      findsOneWidget,
    );
    expect(find.text('Validation result: notStarted'), findsOneWidget);
    expect(find.text('Validation pipeline: ready (0/5)'), findsOneWidget);
    expect(find.text('Next validation command: saveAll'), findsOneWidget);
    expect(
      find.textContaining('Missing validation commands: saveAll'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Command plan: saveAll -> refreshLanguageService'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Continue Validation: saveAll'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'saveAll'), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Continue Validation: saveAll'),
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Continue Validation: saveAll'),
    );
    await tester.pump();

    expect(appliedCommandIds, <String>['saveAll']);
  });

  testWidgets('agent surface renders skipped no-op patch files', (
    tester,
  ) async {
    final editorController = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 4,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _NoOpPatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Apply no-op.');
    await controller.sendPrompt();
    controller.applyPendingPatch(
      AgentCodePatchApplier(editorController: editorController),
    );

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Agent patch patch-noop produced no text changes for the active document.',
      ),
      findsOneWidget,
    );
    expect(find.text('Skipped no-op files: main.styio'), findsOneWidget);
  });

  testWidgets(
    'agent patch application feedback reaches next provider request',
    (tester) async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final adapter = _RecordingPatchFeedbackAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Change value.');
      await controller.sendPrompt();
      controller.applyPendingPatch(
        AgentCodePatchApplier(editorController: editorController),
      );
      controller.updatePrompt('Continue after patch.');
      await controller.sendPrompt();

      expect(adapter.requests.length, 2);
      final feedbackTurns = adapter.requests.last.conversationTurns
          .where((turn) => turn.text.contains('IDE patch application result:'))
          .toList(growable: false);

      expect(feedbackTurns, hasLength(1));
      expect(feedbackTurns.single.role, AgentConversationRole.user);
      expect(feedbackTurns.single.text, contains('patchId: patch-recorded'));
      expect(
        feedbackTurns.single.text,
        contains('patchDocumentIds: main.styio'),
      );
      expect(feedbackTurns.single.text, contains('patchEditCount: 1'));
      expect(
        feedbackTurns.single.text,
        contains('patchOperationCounts: replace 1'),
      );
      expect(feedbackTurns.single.text, contains('applied: true'));
      expect(
        feedbackTurns.single.text,
        contains('pendingPatchRetained: false'),
      );
      expect(
        feedbackTurns.single.text,
        contains('changedDocuments: main.styio'),
      );
      final patchApplication =
          adapter.requests.last.context.agent.lastPatchApplication!;
      expect(patchApplication.patchId, 'patch-recorded');
      expect(patchApplication.documentIds, <String>['main.styio']);
      expect(patchApplication.editCount, 1);
      expect(patchApplication.operationCounts, <String, int>{'replace': 1});
      expect(patchApplication.applied, isTrue);
      expect(patchApplication.pendingPatchRetained, isFalse);
      expect(patchApplication.changedDocumentIds, <String>['main.styio']);
      expect(
        adapter
            .requests
            .last
            .context
            .agent
            .recentPatchApplications
            .single
            .patchId,
        'patch-recorded',
      );
    },
  );

  testWidgets('agent pending patch reaches next provider request', (
    tester,
  ) async {
    final adapter = _RecordingPatchFeedbackAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    controller.updatePrompt('Revise pending patch.');
    await controller.sendPrompt();

    expect(adapter.requests.length, 2);
    final pendingPatch = adapter.requests.last.context.agent.pendingPatch!;
    expect(pendingPatch.patchId, 'patch-recorded');
    expect(pendingPatch.summary, 'Change value.');
    expect(pendingPatch.documentIds, <String>['main.styio']);
    expect(pendingPatch.editCount, 1);
    expect(pendingPatch.operationCounts, <String, int>{'replace': 1});
    expect(pendingPatch.editsTruncated, isFalse);
    expect(pendingPatch.edits.single.documentId, 'main.styio');
    expect(pendingPatch.edits.single.operation, 'replace');
    expect(pendingPatch.edits.single.replacementTextSample, '2');
    expect(
      adapter.requests.last.context.agent.recentPatchProposals.single.patchId,
      'patch-recorded',
    );
  });

  testWidgets('agent preserves pending patch when follow-up provider fails', (
    tester,
  ) async {
    final adapter = _FailingSecondPatchRequestAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    expect(controller.pendingPatch?.patchId, 'patch-preserved');

    controller.updatePrompt('Explain pending patch.');
    final response = await controller.sendPrompt();

    expect(response, isNull);
    expect(adapter.requests.length, 2);
    expect(
      adapter.requests.last.context.agent.pendingPatch?.patchId,
      'patch-preserved',
    );
    expect(controller.pendingPatch?.patchId, 'patch-preserved');
    expect(
      controller.lastResponse?.contentParts.single.patch?.patchId,
      'patch-preserved',
    );
    expect(
      controller.lastProviderFailure?.kind,
      AgentProviderTransportFailureKind.timeout,
    );
    expect(controller.lastError, contains('provider timed out'));
  });

  testWidgets('agent preserves pending patch when follow-up is cancelled', (
    tester,
  ) async {
    final adapter = _DelayedSecondPatchRequestAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Change value.');
    await controller.sendPrompt();
    expect(controller.pendingPatch?.patchId, 'patch-cancel');

    controller.updatePrompt('Explain pending patch.');
    final sendFuture = controller.sendPrompt();
    await adapter.secondRequestStarted.future;

    controller.cancelActiveRequest();
    expect(controller.pendingPatch?.patchId, 'patch-cancel');
    expect(controller.lastError, 'Agent request cancelled.');

    adapter.completeSecond();
    expect(await sendFuture, isNull);
    expect(controller.pendingPatch?.patchId, 'patch-cancel');
  });

  testWidgets(
    'agent failed patch application feedback reaches next provider request',
    (tester) async {
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final adapter = _RecordingFailedPatchFeedbackAgentProviderAdapter();
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: adapter,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Change inactive file.');
      await controller.sendPrompt();
      controller.applyPendingPatch(
        AgentCodePatchApplier(editorController: editorController),
      );
      controller.updatePrompt('Fix failed patch.');
      await controller.sendPrompt();

      expect(adapter.requests.length, 2);
      expect(controller.pendingPatch, isNull);
      final feedbackTurns = adapter.requests.last.conversationTurns
          .where((turn) => turn.text.contains('IDE patch application result:'))
          .toList(growable: false);

      expect(feedbackTurns, hasLength(1));
      expect(feedbackTurns.single.role, AgentConversationRole.user);
      expect(feedbackTurns.single.text, contains('patchId: patch-failed'));
      expect(
        feedbackTurns.single.text,
        contains('patchDocumentIds: other.styio'),
      );
      expect(feedbackTurns.single.text, contains('patchEditCount: 1'));
      expect(
        feedbackTurns.single.text,
        contains('patchOperationCounts: replace 1'),
      );
      expect(feedbackTurns.single.text, contains('applied: false'));
      expect(feedbackTurns.single.text, contains('pendingPatchRetained: true'));
      expect(
        feedbackTurns.single.text,
        contains(
          'Agent patch patch-failed has no edits for the active document.',
        ),
      );
      final patchApplication =
          adapter.requests.last.context.agent.lastPatchApplication!;
      expect(patchApplication.patchId, 'patch-failed');
      expect(patchApplication.documentIds, <String>['other.styio']);
      expect(patchApplication.editCount, 1);
      expect(patchApplication.operationCounts, <String, int>{'replace': 1});
      expect(patchApplication.applied, isFalse);
      expect(patchApplication.pendingPatchRetained, isTrue);
      expect(
        patchApplication.message,
        'Agent patch patch-failed has no edits for the active document.',
      );
      expect(
        adapter
            .requests
            .last
            .context
            .agent
            .recentPatchApplications
            .single
            .patchId,
        'patch-failed',
      );
    },
  );

  testWidgets('agent surface displays applied patch document lists', (
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
      seededDocuments: const <String, DocumentState>{
        'obsolete.txt': DocumentState(
          documentId: 'obsolete.txt',
          text: 'remove me\n',
          revision: 1,
        ),
      },
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change workspace.');
    await controller.sendPrompt();
    await controller.applyPendingWorkspacePatch(
      AgentWorkspaceCodePatchApplier(
        editorController: editorController,
        workspaceDocumentStore: workspaceStore,
      ),
    );

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Changed files: helper.txt, obsolete.txt, main.styio'),
      findsOneWidget,
    );
    expect(find.text('Created files: helper.txt'), findsOneWidget);
    expect(find.text('Deleted files: obsolete.txt'), findsOneWidget);
  });

  testWidgets('agent workspace patch feedback reaches next provider request', (
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
      seededDocuments: const <String, DocumentState>{
        'obsolete.txt': DocumentState(
          documentId: 'obsolete.txt',
          text: 'remove me\n',
          revision: 1,
        ),
      },
    );
    final adapter = _RecordingWorkspacePatchFeedbackAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    controller.updatePrompt('Change workspace.');
    await controller.sendPrompt();
    await controller.applyPendingWorkspacePatch(
      AgentWorkspaceCodePatchApplier(
        editorController: editorController,
        workspaceDocumentStore: workspaceStore,
      ),
    );
    controller.updatePrompt('Continue after workspace patch.');
    await controller.sendPrompt();

    expect(adapter.requests.length, 2);
    final feedbackTurns = adapter.requests.last.conversationTurns
        .where((turn) => turn.text.contains('IDE patch application result:'))
        .toList(growable: false);

    expect(feedbackTurns, hasLength(1));
    expect(feedbackTurns.single.text, contains('patchId: patch-workspace'));
    expect(feedbackTurns.single.text, contains('patchBaseRevision: 1'));
    expect(feedbackTurns.single.text, contains('applied: true'));
    expect(
      feedbackTurns.single.text,
      contains('patchDocumentIds: main.styio, helper.txt, obsolete.txt'),
    );
    expect(feedbackTurns.single.text, contains('patchEditCount: 3'));
    expect(
      feedbackTurns.single.text,
      contains('patchOperationCounts: replace 1, create 1, delete 1'),
    );
    expect(feedbackTurns.single.text, contains('changedDocuments:'));
    expect(feedbackTurns.single.text, contains('main.styio'));
    expect(feedbackTurns.single.text, contains('obsolete.txt'));
    expect(feedbackTurns.single.text, contains('helper.txt'));
    expect(feedbackTurns.single.text, contains('createdDocuments: helper.txt'));
    expect(
      feedbackTurns.single.text,
      contains('deletedDocuments: obsolete.txt'),
    );
    final patchApplication =
        adapter.requests.last.context.agent.lastPatchApplication!;
    expect(patchApplication.patchId, 'patch-workspace');
    expect(patchApplication.baseRevision, 1);
    expect(patchApplication.documentIds, <String>[
      'main.styio',
      'helper.txt',
      'obsolete.txt',
    ]);
    expect(patchApplication.editCount, 3);
    expect(patchApplication.operationCounts, <String, int>{
      'replace': 1,
      'create': 1,
      'delete': 1,
    });
    expect(patchApplication.applied, isTrue);
    expect(patchApplication.createdDocumentIds, <String>['helper.txt']);
    expect(patchApplication.deletedDocumentIds, <String>['obsolete.txt']);
    expect(
      adapter
          .requests
          .last
          .context
          .agent
          .recentPatchApplications
          .single
          .patchId,
      'patch-workspace',
    );
  });

  testWidgets('agent surface blocks applying patch for inactive dirty files', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _OtherFilePatchAgentProviderAdapter(),
      contextProvider: _dirtyOtherContext,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change other file.');
    await controller.sendPrompt();

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
              sessionContext: _dirtyOtherContext(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Patch blocked: dirty inactive files other.styio'),
      findsOneWidget,
    );
    final applyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply Patch'),
    );
    expect(applyButton.onPressed, isNull);
  });

  testWidgets('agent surface blocks active document file operations', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _ActiveDeletePatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Delete active file.');
    await controller.sendPrompt();

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining(
        'Patch blocked: file create/delete targets the active document main.styio',
      ),
      findsOneWidget,
    );
    final applyButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Apply Patch'),
    );
    expect(applyButton.onPressed, isNull);
  });

  testWidgets('agent surface displays prompt attachments', (tester) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.addAttachment(
      const AgentRequestAttachment(
        attachmentId: 'note-1',
        kind: 'text',
        name: 'note.txt',
        content: 'prefer simple edits',
      ),
    );

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Attachments'), findsOneWidget);
    expect(find.text('note.txt · text'), findsOneWidget);
  });

  testWidgets('agent surface removes prompt attachment from chip action', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.addAttachment(
      const AgentRequestAttachment(
        attachmentId: 'note-1',
        kind: 'text',
        name: 'note.txt',
        content: 'prefer simple edits',
      ),
    );

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(tester, find.byTooltip('Remove note.txt'));
    await tester.pump();

    expect(controller.attachments, isEmpty);
    expect(find.text('note.txt · text'), findsNothing);
  });

  testWidgets('agent surface attaches active document from IDE context', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-attach-active-document-button')),
    );
    await tester.pump();

    expect(controller.attachments.single.kind, 'document');
    expect(controller.attachments.single.name, 'main.styio');
    expect(controller.attachments.single.content, 'value = 1\n');
    expect(controller.attachments.single.metadata['documentId'], 'main.styio');
    expect(controller.attachments.single.metadata['revision'], 1);
    expect(controller.attachments.single.metadata['textStart'], 0);
    expect(controller.attachments.single.metadata['textEnd'], 10);
    expect(find.text('main.styio · document'), findsOneWidget);
  });

  testWidgets('agent surface attaches selected text from IDE context', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _selectionContext,
    );
    addTearDown(controller.dispose);

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
              sessionContext: _selectionContext(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-attach-selection-button')),
    );
    await tester.pump();

    expect(controller.attachments.single.kind, 'selection');
    expect(controller.attachments.single.name, 'main.styio selection');
    expect(controller.attachments.single.content, 'value');
    expect(controller.attachments.single.metadata['documentId'], 'main.styio');
    expect(controller.attachments.single.metadata['revision'], 1);
    expect(controller.attachments.single.metadata['selectionStart'], 0);
    expect(controller.attachments.single.metadata['selectionEnd'], 5);
    expect(find.text('main.styio selection · selection'), findsOneWidget);
  });

  testWidgets('agent surface disables attachment actions for empty context', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _emptySelectionContext,
    );
    addTearDown(controller.dispose);

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
              sessionContext: _emptySelectionContext(),
              codingController: controller,
              onApplyPendingPatch: () async {},
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    final activeDocumentButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Attach Active File'),
    );
    final selectionButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Attach Selection'),
    );

    expect(activeDocumentButton.onPressed, isNull);
    expect(selectionButton.onPressed, isNull);
  });

  testWidgets('agent surface updates when controller attachments change', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('late-note.txt · text'), findsNothing);

    controller.addAttachment(
      const AgentRequestAttachment(
        attachmentId: 'late-note',
        kind: 'text',
        name: 'late-note.txt',
        content: 'added after render',
      ),
    );
    await tester.pump();

    expect(find.text('late-note.txt · text'), findsOneWidget);
  });

  testWidgets('agent surface clears prompt input after successful send', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    final promptInput = find.byKey(const ValueKey('agent-prompt-input'));
    await tester.enterText(promptInput, 'Change value.');
    expect(controller.draftPrompt, 'Change value.');

    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    await tester.pump();

    final promptField = tester.widget<TextFormField>(promptInput);
    expect(controller.draftPrompt, '');
    expect(promptField.controller?.text, '');
    expect(controller.pendingPatch?.patchId, 'patch-1');
  });

  testWidgets(
    'agent surface can clear provider error without conversation turns',
    (tester) async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _ThrowingSurfaceAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

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
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('agent-prompt-input')),
        'Explain this file.',
      );
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('provider unavailable'), findsOneWidget);
      expect(find.text('Clear Conversation'), findsOneWidget);

      await _tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Clear Conversation'),
      );
      await tester.pump();

      expect(controller.lastError, isNull);
      expect(find.textContaining('provider unavailable'), findsNothing);
    },
  );

  testWidgets('agent surface renders structured provider failure recovery', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _StructuredFailureSurfaceAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-prompt-input')),
      'Explain this file.',
    );
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('agent-provider-failure-details')),
      findsOneWidget,
    );
    expect(find.text('Provider failure kind: timeout'), findsOneWidget);
    expect(find.text('Recovery: Check provider credentials.'), findsOneWidget);

    await _tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Clear Conversation'),
    );
    await tester.pump();

    expect(controller.lastProviderFailure, isNull);
    expect(
      find.byKey(const ValueKey('agent-provider-failure-details')),
      findsNothing,
    );
  });

  testWidgets('agent surface retries structured provider failure request', (
    tester,
  ) async {
    final adapter = _RetryableFailureSurfaceAgentProviderAdapter();
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: adapter,
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-prompt-input')),
      'Explain this file.',
    );
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    await tester.pump();

    expect(adapter.sendCount, 1);
    expect(
      find.byKey(const ValueKey('agent-provider-failure-details')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-provider-retry-button')),
    );
    await tester.pump();
    await tester.pump();

    expect(adapter.sendCount, 2);
    expect(
      adapter.requests.last.context.agent.lastProviderFailure?.kind,
      'timeout',
    );
    expect(
      adapter.requests.last.context.agent.lastProviderFailure?.message,
      'provider timed out',
    );
    expect(controller.lastError, isNull);
    expect(controller.lastProviderFailure, isNull);
    expect(controller.lastResponse?.contentParts.single.text, 'retry ok');
    expect(
      find.byKey(const ValueKey('agent-provider-failure-details')),
      findsNothing,
    );
  });

  testWidgets('agent surface can switch provider failure to local fallback', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _StructuredFailureSurfaceAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-prompt-input')),
      'Explain this file.',
    );
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('agent-provider-failure-details')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-provider-local-fallback-button')),
    );
    await tester.pump();

    expect(controller.providerKind, AgentProviderKind.localOnlyFallback);
    expect(controller.lastError, isNull);
    expect(controller.lastProviderFailure, isNull);
    expect(
      controller.providerMountMessage,
      'Cloud agent provider disabled; using local fallback.',
    );
    expect(
      find.byKey(const ValueKey('agent-provider-failure-details')),
      findsNothing,
    );
  });

  testWidgets(
    'agent provider profile shows reconfiguration guidance on failure',
    (tester) async {
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _StructuredFailureSurfaceAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

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
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('agent-prompt-input')),
        'Explain this file.',
      );
      await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const ValueKey('agent-provider-profile-section')),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('agent-provider-reconfiguration-guidance')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Provider reconfiguration recommended: timeout'),
        findsOneWidget,
      );

      controller.clearConversation();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('agent-provider-reconfiguration-guidance')),
        findsNothing,
      );
    },
  );

  testWidgets('agent provider profile save remounts after provider failure', (
    tester,
  ) async {
    AgentPromptProfile? savedProfile;
    String? savedBearerToken;
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _StructuredFailureSurfaceAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

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
              onSaveProviderProfile: (profile, {bearerToken}) async {
                savedProfile = profile;
                savedBearerToken = bearerToken;
                controller.mountProvider(
                  profile: profile,
                  adapter: _PatchAgentProviderAdapter(),
                  message: 'Agent provider profile saved and mounted.',
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-prompt-input')),
      'Explain this file.',
    );
    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('agent-provider-profile-section')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('agent-provider-reconfiguration-guidance')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-base-url-input')),
      'https://agent.fixed.test/v1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-model-input')),
      'gpt-fixed',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-profile-bearer-token-input')),
      'fixed-token',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-profile-save-button')),
    );
    await tester.pump();

    expect(savedProfile?.endpoint.baseUrl, 'https://agent.fixed.test/v1');
    expect(savedProfile?.endpoint.model, 'gpt-fixed');
    expect(savedBearerToken, 'fixed-token');
    expect(controller.providerKind, AgentProviderKind.cloudOpenAICompatible);
    expect(
      controller.providerMountMessage,
      'Agent provider profile saved and mounted.',
    );
    expect(controller.lastError, isNull);
    expect(controller.lastProviderFailure, isNull);
    expect(
      find.byKey(const ValueKey('agent-provider-reconfiguration-guidance')),
      findsNothing,
    );
  });

  testWidgets(
    'agent surface disables apply patch while application is in flight',
    (tester) async {
      final applyCompleter = Completer<void>();
      var applyCount = 0;
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: _PatchAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      controller.updatePrompt('Change value.');
      await controller.sendPrompt();

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
                onApplyPendingPatch: () {
                  applyCount += 1;
                  return applyCompleter.future;
                },
                onSaveProviderProfile: (profile, {bearerToken}) async {},
              ),
            ),
          ),
        ),
      );

      await _tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Apply Patch'),
      );
      await tester.pump();

      expect(find.text('Applying Patch...'), findsOneWidget);
      final sendButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send'),
      );
      expect(sendButton.onPressed, isNull);

      final dismissButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Dismiss Patch'),
      );
      expect(dismissButton.onPressed, isNull);
      final clearConversationButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Clear Conversation'),
      );
      expect(clearConversationButton.onPressed, isNull);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Applying Patch...'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(applyCount, 1);

      applyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('Apply Patch'), findsOneWidget);
    },
  );

  testWidgets('agent surface records unexpected patch application errors', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _PatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change value.');
    await controller.sendPrompt();

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
              onApplyPendingPatch: () async {
                throw StateError('apply failed Bearer secret-token');
              },
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    await _tapVisible(tester, find.widgetWithText(FilledButton, 'Apply Patch'));
    await tester.pump();
    await tester.pump();

    expect(controller.lastPatchApplicationResult?.applied, isFalse);
    expect(
      controller.lastPatchApplicationResult?.message,
      contains('Bearer [redacted]'),
    );
    expect(
      controller.lastPatchApplicationResult?.message,
      isNot(contains('secret-token')),
    );
    expect(
      find.byKey(const ValueKey('agent-draft-patch-repair')),
      findsOneWidget,
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('agent-draft-patch-repair')),
    );
    await tester.pump();

    expect(
      controller.draftPrompt,
      contains('Repair the failed agent patch application.'),
    );
    expect(controller.draftPrompt, contains('Bearer [redacted]'));
    expect(controller.draftPrompt, isNot(contains('secret-token')));
  });

  testWidgets('agent surface follows controller patch application state', (
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
    final workspaceStore = _DelayedSurfaceWorkspaceDocumentStore(
      const DocumentState(
        documentId: 'other.styio',
        text: 'name = old\n',
        revision: 1,
      ),
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: _OtherFilePatchAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    controller.updatePrompt('Change other file.');
    await controller.sendPrompt();
    controller.updatePrompt('Follow up while patch applies.');
    final applyResult = controller.applyPendingWorkspacePatch(
      AgentWorkspaceCodePatchApplier(
        editorController: editorController,
        workspaceDocumentStore: workspaceStore,
      ),
    );
    await workspaceStore.loadStarted.future;

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
              onSaveProviderProfile: (profile, {bearerToken}) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Applying Patch...'), findsOneWidget);
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send'),
    );
    expect(sendButton.onPressed, isNull);

    workspaceStore.releaseLoad();
    await applyResult;
  });
}

AgentSessionContext _context({
  Iterable<AgentPromptProfileManifestEntry> savedProviderProfiles =
      const <AgentPromptProfileManifestEntry>[],
}) {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    resolvedElement: const ResolvedElement(
      name: 'value',
      kind: ResolvedElementKind.variable,
      nameRange: SourceRange(start: 0, end: 5),
      declarationRange: SourceRange(start: 0, end: 9),
      detail: 'i64',
    ),
    resolvedReference: const ResolvedReference(
      name: 'value',
      range: SourceRange(start: 0, end: 5),
      target: ResolvedElement(
        name: 'value',
        kind: ResolvedElementKind.variable,
        nameRange: SourceRange(start: 0, end: 5),
        declarationRange: SourceRange(start: 0, end: 9),
        detail: 'i64',
      ),
      access: ResolvedReferenceAccess.read,
      isDeclaration: false,
    ),
    semanticSpans: const <SemanticSpan>[
      SemanticSpan(
        range: SourceRange(start: 0, end: 5),
        kind: SemanticKind.variable,
      ),
    ],
    workspaceFiles: const <String>['main.styio', 'other.styio'],
    activeFilePath: 'main.styio',
    savedProviderProfiles: savedProviderProfiles,
  );
}

AgentSessionContext _nativeBuildReadyContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    workspaceFiles: const <String>['main.styio', 'other.styio'],
    activeFilePath: 'main.styio',
    debug: const AgentDebugContext(
      status: 'idle',
      message: 'Debug launch configuration is ready.',
      breakpointCount: 0,
      breakpoints: <AgentDebugBreakpointContext>[],
      threadCount: 0,
      threads: <AgentDebugThreadContext>[],
      stackFrameCount: 0,
      stackFrames: <AgentDebugStackFrameContext>[],
      variableCount: 0,
      variables: <AgentDebugVariableContext>[],
      launch: AgentDebugLaunchContext(
        ready: true,
        readiness: 'ready',
        reason: 'Debug launch configuration is ready.',
        adapterProtocol: 'dap',
        debuggerId: 'native-lldb-debugger',
        debuggerLabel: 'LLDB Native Debugger',
        debuggerExecutablePath: '/usr/bin/lldb-dap',
        cwd: '.',
        breakpointCount: 0,
      ),
    ),
    toolchainSnapshot: const ToolchainStateSnapshot(
      targetId: 'agent-native-build',
      entries: <ToolchainStateEntry>[
        ToolchainStateEntry(
          id: 'native-cmake-build-tool',
          kind: ToolchainKind.buildTool,
          displayName: 'CMake Build System',
          executablePath: '/usr/bin/cmake',
          active: true,
          metadata: <String, Object?>{'toolFamily': 'cmake'},
        ),
      ],
    ),
  );
}

AgentSessionContext _dirtyNativeBuildReadyContext({
  Iterable<AgentCommandResultContext> recentCommandResults =
      const <AgentCommandResultContext>[],
}) {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    workspaceFiles: const <String>['main.styio', 'other.styio'],
    dirtyDocumentIds: const <String>['other.styio'],
    lastCommandResult: recentCommandResults.isEmpty
        ? null
        : recentCommandResults.first,
    recentCommandResults: recentCommandResults,
    activeFilePath: 'main.styio',
    toolchainSnapshot: const ToolchainStateSnapshot(
      targetId: 'agent-dirty-native-build',
      entries: <ToolchainStateEntry>[
        ToolchainStateEntry(
          id: 'native-cmake-build-tool',
          kind: ToolchainKind.buildTool,
          displayName: 'CMake Build System',
          executablePath: '/usr/bin/cmake',
          active: true,
          metadata: <String, Object?>{'toolFamily': 'cmake'},
        ),
      ],
    ),
  );
}

AgentSessionContext _cmakeStaticAnalysisBlockedContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'src/main.cc',
      text: 'int main() { return 0; }\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    workspaceFiles: const <String>['CMakeLists.txt', 'src/main.cc'],
    activeFilePath: 'src/main.cc',
    toolchainSnapshot: const ToolchainStateSnapshot(
      targetId: 'agent-cmake-static-analysis-blocked',
      entries: <ToolchainStateEntry>[
        ToolchainStateEntry(
          id: 'native-cmake-build-tool',
          kind: ToolchainKind.buildTool,
          displayName: 'CMake Build System',
          executablePath: '/usr/bin/cmake',
          active: true,
          metadata: <String, Object?>{'toolFamily': 'cmake'},
        ),
        ToolchainStateEntry(
          id: 'native-clang-tidy-static-analyzer',
          kind: ToolchainKind.staticAnalyzer,
          displayName: 'clang-tidy Static Analyzer',
          executablePath: '/usr/bin/clang-tidy',
          active: true,
          metadata: <String, Object?>{'toolFamily': 'clang-tidy'},
        ),
      ],
    ),
  );
}

AgentSessionContext _selectionContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState(baseOffset: 0, extentOffset: 5),
    diagnostics: const [],
    workspaceFiles: const <String>['main.styio', 'other.styio'],
    activeFilePath: 'main.styio',
  );
}

AgentSessionContext _emptySelectionContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'empty.styio',
      text: '   ',
      revision: 1,
    ),
    selection: const SelectionState(baseOffset: 0, extentOffset: 3),
    diagnostics: const [],
    workspaceFiles: const <String>['empty.styio'],
    activeFilePath: 'empty.styio',
  );
}

AgentSessionContext _dirtyOtherContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
    workspaceFiles: const <String>['main.styio', 'other.styio'],
    openDocumentIds: const <String>['main.styio', 'other.styio'],
    dirtyDocumentIds: const <String>['other.styio'],
    activeFilePath: 'main.styio',
  );
}

class _PatchAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'patch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return const AgentProviderResponseEnvelope(
      requestId: 'agent-request-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.codePatch,
          text: 'Patch ready.',
          patch: AgentCodePatch(
            patchId: 'patch-1',
            summary: 'Change value.',
            baseRevision: 1,
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'main.styio',
                start: 8,
                end: 9,
                replacementText: '2',
              ),
              AgentCodePatchEdit(
                documentId: 'helper.txt',
                operation: AgentCodePatchEditOperation.create,
                start: 0,
                end: 0,
                replacementText: 'created by agent\n',
              ),
              AgentCodePatchEdit(
                documentId: 'obsolete.txt',
                operation: AgentCodePatchEditOperation.delete,
                start: 0,
                end: 0,
                replacementText: '',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingWorkspacePatchFeedbackAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'recording-workspace-patch-feedback';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.codePatch,
            text: 'Patch ready.',
            patch: AgentCodePatch(
              patchId: 'patch-workspace',
              summary: 'Change workspace.',
              baseRevision: 1,
              edits: <AgentCodePatchEdit>[
                AgentCodePatchEdit(
                  documentId: 'main.styio',
                  start: 8,
                  end: 9,
                  replacementText: '2',
                ),
                AgentCodePatchEdit(
                  documentId: 'helper.txt',
                  operation: AgentCodePatchEditOperation.create,
                  start: 0,
                  end: 0,
                  replacementText: 'created by agent\n',
                ),
                AgentCodePatchEdit(
                  documentId: 'obsolete.txt',
                  operation: AgentCodePatchEditOperation.delete,
                  start: 0,
                  end: 0,
                  replacementText: '',
                ),
              ],
            ),
          ),
        ],
      );
    }
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'Continuing.'),
      ],
    );
  }
}

class _PlanAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'plan';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.plan,
          text: 'Plan before patch.',
          plan: AgentCodingPlan(
            summary: 'Update active document safely.',
            steps: <String>['Inspect IDE facts.', 'Prepare patch.'],
            acceptanceCriteria: <String>['Patch preview is shown.'],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticSummaryAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'diagnostic-summary';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.diagnosticSummary,
          text: 'Diagnostics summarized.',
          diagnosticSummary: AgentDiagnosticSummary(
            title: 'Build failed.',
            summary: 'Parser target failed with one error.',
            severity: 'error',
            diagnosticCount: 1,
            affectedDocuments: <String>['src/parser.cc'],
            suggestedCommandIds: <String>['runBuild'],
          ),
        ),
      ],
    );
  }
}

class _CommandSuggestionAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Use Rename Symbol.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'renameSymbol',
            input: 'price',
            reason: 'Use the safe rename refactor.',
          ),
        ),
      ],
    );
  }
}

class _ClangCppVersionCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'clang-cpp-version-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Select Clang/C++ version.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'selectClangCppVersion',
            input: 'fake-clang-18 c++23',
            reason: 'Use the registered Clang/C++ version manager.',
          ),
        ),
      ],
    );
  }
}

class _MissingInputCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'missing-input-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Rename without input.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'renameSymbol',
            reason: 'Missing rename target.',
          ),
        ),
      ],
    );
  }
}

class _RecordingCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'recording-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return AgentProviderResponseEnvelope(
        requestId: request.requestId,
        role: 'assistant',
        finishReason: 'stop',
        contentParts: const <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.ideCommand,
            text: 'Use Rename Symbol.',
            ideCommand: AgentIdeCommandSuggestion(
              commandId: 'renameSymbol',
              input: 'price',
              reason: 'Use the safe rename refactor.',
            ),
          ),
        ],
      );
    }
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'Continuing.'),
      ],
    );
  }
}

class _FailingSecondCommandRequestAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'failing-second-command-request';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return AgentProviderResponseEnvelope(
        requestId: request.requestId,
        role: 'assistant',
        finishReason: 'stop',
        contentParts: const <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.ideCommand,
            text: 'Use Rename Symbol.',
            ideCommand: AgentIdeCommandSuggestion(
              commandId: 'renameSymbol',
              input: 'price',
              reason: 'Use the safe rename refactor.',
            ),
          ),
        ],
      );
    }
    throw const AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.timeout,
      message: 'provider timed out',
      recoveryHint: 'Retry the provider request.',
    );
  }
}

class _DelayedSecondCommandRequestAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];
  final Completer<void> secondRequestStarted = Completer<void>();
  Completer<AgentProviderResponseEnvelope>? _secondResponse;

  @override
  String get adapterId => 'delayed-second-command-request';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return AgentProviderResponseEnvelope(
        requestId: request.requestId,
        role: 'assistant',
        finishReason: 'stop',
        contentParts: const <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.ideCommand,
            text: 'Use Rename Symbol.',
            ideCommand: AgentIdeCommandSuggestion(
              commandId: 'renameSymbol',
              input: 'price',
              reason: 'Use the safe rename refactor.',
            ),
          ),
        ],
      );
    }
    if (!secondRequestStarted.isCompleted) {
      secondRequestStarted.complete();
    }
    _secondResponse = Completer<AgentProviderResponseEnvelope>();
    return _secondResponse!.future;
  }

  void completeSecond() {
    final response = _secondResponse;
    if (response == null || response.isCompleted) {
      return;
    }
    response.complete(
      const AgentProviderResponseEnvelope(
        requestId: 'agent-request-2',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(kind: AgentContentPartKind.text, text: 'Late.'),
        ],
      ),
    );
  }
}

class _NativeDebugCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'native-debug-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Save workspace files.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'saveAll',
            reason: 'Persist dirty files before disk-backed tools.',
          ),
        ),
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Run the build.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'runBuild',
            reason: 'Use the registered build command.',
          ),
        ),
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Start debugging.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'startDebugging',
            reason: 'Use the registered debug command.',
          ),
        ),
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Refresh language facts.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'refreshLanguageService',
            reason: 'Refresh stale language service facts.',
          ),
        ),
      ],
    );
  }
}

class _RunBuildCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'run-build-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Run the build.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'runBuild',
            reason: 'Use the registered build command.',
          ),
        ),
      ],
    );
  }
}

class _StaticAnalysisCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'static-analysis-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Run static analysis.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'runStaticAnalysis',
            reason: 'Run clang-tidy through IDE command.',
          ),
        ),
      ],
    );
  }
}

class _StartDebugCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'start-debug-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Start debugging.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'startDebugging',
            reason: 'Use the registered debug command.',
          ),
        ),
      ],
    );
  }
}

class _UnsupportedCommandSuggestionAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'unsupported-command-suggestion';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.ideCommand,
          text: 'Unsupported command.',
          ideCommand: AgentIdeCommandSuggestion(
            commandId: 'deleteWorkspace',
            reason: 'This is not registered.',
          ),
        ),
      ],
    );
  }
}

class _ReplacePatchAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'replace-patch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return const AgentProviderResponseEnvelope(
      requestId: 'agent-request-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.codePatch,
          text: 'Patch ready.',
          patch: AgentCodePatch(
            patchId: 'patch-replace',
            summary: 'Change value.',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'main.styio',
                start: 8,
                end: 9,
                replacementText: '2',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingPatchFeedbackAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'recording-patch-feedback';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.codePatch,
            text: 'Patch ready.',
            patch: AgentCodePatch(
              patchId: 'patch-recorded',
              summary: 'Change value.',
              edits: <AgentCodePatchEdit>[
                AgentCodePatchEdit(
                  documentId: 'main.styio',
                  start: 8,
                  end: 9,
                  replacementText: '2',
                ),
              ],
            ),
          ),
        ],
      );
    }
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'Continuing.'),
      ],
    );
  }
}

class _FailingSecondPatchRequestAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'failing-second-patch-request';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.codePatch,
            text: 'Patch ready.',
            patch: AgentCodePatch(
              patchId: 'patch-preserved',
              summary: 'Change value.',
              edits: <AgentCodePatchEdit>[
                AgentCodePatchEdit(
                  documentId: 'main.styio',
                  start: 8,
                  end: 9,
                  replacementText: '2',
                ),
              ],
            ),
          ),
        ],
      );
    }
    throw const AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.timeout,
      message: 'provider timed out',
      recoveryHint: 'Retry the provider request.',
    );
  }
}

class _DelayedSecondPatchRequestAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];
  final Completer<void> secondRequestStarted = Completer<void>();
  Completer<AgentProviderResponseEnvelope>? _secondResponse;

  @override
  String get adapterId => 'delayed-second-patch-request';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.codePatch,
            text: 'Patch ready.',
            patch: AgentCodePatch(
              patchId: 'patch-cancel',
              summary: 'Change value.',
              edits: <AgentCodePatchEdit>[
                AgentCodePatchEdit(
                  documentId: 'main.styio',
                  start: 8,
                  end: 9,
                  replacementText: '2',
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (!secondRequestStarted.isCompleted) {
      secondRequestStarted.complete();
    }
    _secondResponse = Completer<AgentProviderResponseEnvelope>();
    return _secondResponse!.future;
  }

  void completeSecond() {
    final response = _secondResponse;
    if (response == null || response.isCompleted) {
      return;
    }
    response.complete(
      const AgentProviderResponseEnvelope(
        requestId: 'agent-request-2',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(kind: AgentContentPartKind.text, text: 'Late.'),
        ],
      ),
    );
  }
}

class _RecordingFailedPatchFeedbackAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'recording-failed-patch-feedback';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    if (requests.length == 1) {
      return const AgentProviderResponseEnvelope(
        requestId: 'agent-request-1',
        role: 'assistant',
        finishReason: 'stop',
        contentParts: <AgentContentPart>[
          AgentContentPart(
            kind: AgentContentPartKind.codePatch,
            text: 'Patch ready.',
            patch: AgentCodePatch(
              patchId: 'patch-failed',
              summary: 'Change inactive file.',
              edits: <AgentCodePatchEdit>[
                AgentCodePatchEdit(
                  documentId: 'other.styio',
                  start: 0,
                  end: 0,
                  replacementText: 'other = 2\n',
                ),
              ],
            ),
          ),
        ],
      );
    }
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'Repairing.'),
      ],
    );
  }
}

class _NoOpPatchAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'noop-patch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return const AgentProviderResponseEnvelope(
      requestId: 'agent-request-noop',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.codePatch,
          text: 'Patch ready.',
          patch: AgentCodePatch(
            patchId: 'patch-noop',
            summary: 'No-op value.',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'main.styio',
                start: 0,
                end: 5,
                replacementText: 'value',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LargePatchAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'large-patch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: 'agent-request-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.codePatch,
          text: 'Large patch ready.',
          patch: AgentCodePatch(
            patchId: 'patch-large',
            summary: 'Large patch',
            edits: List<AgentCodePatchEdit>.generate(
              7,
              (index) => AgentCodePatchEdit(
                documentId: 'main.styio',
                start: index,
                end: index,
                replacementText: 'x',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OtherFilePatchAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'other-file-patch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return const AgentProviderResponseEnvelope(
      requestId: 'agent-request-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.codePatch,
          text: 'Patch ready.',
          patch: AgentCodePatch(
            patchId: 'patch-other-file',
            summary: 'Change other file.',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'other.styio',
                baseRevision: 1,
                start: 7,
                end: 10,
                replacementText: 'new',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveDeletePatchAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'active-delete-patch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return const AgentProviderResponseEnvelope(
      requestId: 'agent-request-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.codePatch,
          text: 'Patch ready.',
          patch: AgentCodePatch(
            patchId: 'patch-active-delete',
            summary: 'Delete active file.',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'main.styio',
                operation: AgentCodePatchEditOperation.delete,
                start: 0,
                end: 0,
                replacementText: '',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThrowingSurfaceAgentProviderAdapter implements AgentProviderAdapter {
  @override
  String get adapterId => 'throwing';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => false;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    throw StateError('provider unavailable');
  }
}

class _StructuredFailureSurfaceAgentProviderAdapter
    implements AgentProviderAdapter {
  @override
  String get adapterId => 'structured-failure';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    throw const AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.timeout,
      message: 'provider timed out',
      recoveryHint: 'Check provider credentials.',
    );
  }
}

class _MemoryAgentCodingSessionHistoryStore
    implements AgentCodingSessionHistoryStore {
  _MemoryAgentCodingSessionHistoryStore(this.history);

  AgentCodingSessionHistory history;

  @override
  Future<AgentCodingSessionHistory> readHistory({
    required String workspaceId,
  }) async {
    return history.workspaceId == workspaceId
        ? history
        : AgentCodingSessionHistory(workspaceId: workspaceId);
  }

  @override
  Future<AgentCodingSessionHistory> appendRecord({
    required String workspaceId,
    required AgentCodingSessionHistoryRecord record,
    int maxEntries = 50,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    history = current.append(record, maxEntries: maxEntries);
    return history;
  }

  @override
  Future<AgentCodingSessionCheckpoint> readCheckpoint({
    required String workspaceId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toCheckpoint();
  }

  @override
  Future<AgentCodingSessionRecoveryPlan> readRecoveryPlan({
    required String workspaceId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toRecoveryPlan();
  }

  @override
  Future<AgentCodingSessionRecoveryContext> readRecoveryContext({
    required String workspaceId,
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toRecoveryContext(
      targetProviderProfileKey:
          targetProviderProfileKey ?? targetProviderProfileId,
    );
  }

  @override
  Future<void> saveHistory(AgentCodingSessionHistory history) async {
    this.history = history;
  }
}

class _RecoveryDispatchSurfaceAgentProviderAdapter
    implements AgentProviderAdapter {
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'recovery-dispatch';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'recovery ok'),
      ],
    );
  }
}

class _RetryableFailureSurfaceAgentProviderAdapter
    implements AgentProviderAdapter {
  var sendCount = 0;
  final List<AgentProviderRequest> requests = <AgentProviderRequest>[];

  @override
  String get adapterId => 'retryable-failure';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    requests.add(request);
    sendCount += 1;
    if (sendCount == 1) {
      throw const AgentProviderTransportException(
        kind: AgentProviderTransportFailureKind.timeout,
        message: 'provider timed out',
        recoveryHint: 'Retry the provider request.',
      );
    }
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'retry ok'),
      ],
    );
  }
}

class _DelayedSurfaceWorkspaceDocumentStore implements WorkspaceDocumentStore {
  _DelayedSurfaceWorkspaceDocumentStore(this._document);

  DocumentState _document;
  final Completer<void> loadStarted = Completer<void>();
  final Completer<void> _releaseLoad = Completer<void>();

  @override
  Future<DocumentState> loadDocument(String path) async {
    if (!loadStarted.isCompleted) {
      loadStarted.complete();
    }
    await _releaseLoad.future;
    return _document;
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _document = document;
  }

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => true;

  @override
  String? filePathForDocumentId(String documentId) => documentId;

  void releaseLoad() {
    if (!_releaseLoad.isCompleted) {
      _releaseLoad.complete();
    }
  }
}
