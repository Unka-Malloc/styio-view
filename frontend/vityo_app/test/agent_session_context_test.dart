import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_prompt_profile_store.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_registry.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_history_store.dart';
import 'package:vityo_app/src/agent/agent_tool_registry.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/interaction/language_service_status_surface.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_provider.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent autonomy policy does not report surfaced blocked-panel TODO', () {
    final policy = AgentCodingAutonomyPolicy.fromGates(
      readiness: const AgentCodingExecutionReadiness(
        status: AgentCodingExecutionReadinessStatus.blocked,
        issues: <AgentCodingExecutionReadinessIssue>[
          AgentCodingExecutionReadinessIssue(
            code: 'ide.runtime-contracts.blocking',
            message: 'Runtime contract is blocked.',
            severity: AgentCodingExecutionReadinessIssueSeverity.blocking,
            ownerLayer: 'foundation',
          ),
        ],
        todoItems: <String>['Close runtime-contract blockers.'],
      ),
      changeReviewGate: const AgentCodingChangeReviewGate(
        status: AgentCodingChangeReviewGateStatus.idle,
        canApplyPreview: false,
        requiresUserReview: false,
      ),
    );
    final validationPlan = AgentCodingValidationPlan.fromAgentState(
      autonomyPolicy: policy,
      changeReviewGate: const AgentCodingChangeReviewGate(
        status: AgentCodingChangeReviewGateStatus.idle,
        canApplyPreview: false,
        requiresUserReview: false,
      ),
      lastPatchApplication: null,
    );

    expect(policy.mode, AgentCodingAutonomyMode.blocked);
    expect(policy.todoItems, contains('Close runtime-contract blockers.'));
    expect(policy.todoItems.join('\n'), isNot(contains('TODO:')));
    expect(
      policy.todoItems,
      isNot(
        contains(
          'TODO: surface blocked autonomy policy in the agent coding panel.',
        ),
      ),
    );
    expect(validationPlan.status, AgentCodingValidationPlanStatus.blocked);
    expect(
      validationPlan.todoItems,
      isNot(
        contains(
          'TODO: expose blocked validation state in the agent activity panel.',
        ),
      ),
    );
  });

  test('agent session context serializes coding execution readiness facts', () {
    const document = DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: 'value := 1\n',
      revision: 1,
    );
    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      dirtyDocumentIds: const <String>['/workspace/demo/src/main.styio'],
    );

    expect(
      context.codingReadiness.hasIssue('workspace.dirty-documents'),
      isTrue,
    );
    expect(
      context.codingReadiness.hasIssue('styio.service.status.missing'),
      isTrue,
    );
    expect(context.codingReadiness.canDispatchProviderRequest, isTrue);

    final json = context.toJson();
    final readiness = json['codingReadiness']! as Map<String, Object?>;
    expect(readiness['status'], 'needsAttention');
    expect(
      readiness['issueCodes'],
      containsAll(<String>[
        'workspace.dirty-documents',
        'styio.service.status.missing',
      ]),
    );
    final blockedProviderContext = AgentSessionContext.fromEditorState(
      document: document,
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      providerExecutionResolution: const AgentProviderExecutionResolution(
        profileId: 'blocked-provider',
        status: AgentProviderExecutionResolutionStatus.blocked,
        endpoints: <AgentProviderEndpointReadiness>[],
      ),
    );
    final blockedReadiness =
        blockedProviderContext.toJson()['codingReadiness']!
            as Map<String, Object?>;
    expect(blockedReadiness['status'], 'blocked');
    expect(blockedReadiness['canDispatchProviderRequest'], isFalse);
    expect(
      blockedReadiness['issueCodes'],
      contains('agent.provider.route.blocked'),
    );

    final agentChannel = context.toJsonForChannels(const <String>['agent']);
    expect(agentChannel['codingReadiness'], isA<Map<String, Object?>>());

    final guardedContext = context.withAgentCodingState(
      loopGuard: AgentCodingLoopGuard.fromSignals(
        toolReplayReportCount: 3,
        failedToolResultCount: 1,
        hasProviderFailure: true,
      ),
    );
    final guardedAgent =
        guardedContext.toJsonForChannels(const <String>['agent'])['agent']!
            as Map<String, Object?>;
    final loopGuard = guardedAgent['loopGuard']! as Map<String, Object?>;
    expect(loopGuard['status'], 'blocked');
    expect(loopGuard['blocked'], isTrue);
    expect(loopGuard['toolReplayReportCount'], 3);
    expect(loopGuard['failedToolResultCount'], 1);
    expect(loopGuard['hasProviderFailure'], isTrue);
    expect(loopGuard['requiresUserReview'], isTrue);
    expect(
      loopGuard['blockingReasons'],
      contains('agent.loop.replayReportLimit:3'),
    );
    expect(loopGuard.containsKey('todoItems'), isFalse);

    final checkpointContext = context.withAgentCodingState(
      workspaceCheckpoint: AgentWorkspaceCheckpointContext(
        captureStatus: 'captured',
        snapshotId: 'agent-snapshot-1',
        patchId: 'patch-1',
        activeDocumentId: '/workspace/demo/src/main.styio',
        capturedAt: DateTime.utc(2026, 5, 22, 1, 2, 3),
        captureMessage: 'Captured 1 workspace document snapshot.',
        capturedDocumentCount: 1,
        revertPlanStatus: 'ready',
        revertReady: true,
        revertPatchId: 'revert-agent-snapshot-1',
        revertChangedDocumentCount: 1,
        revertModifiedDocumentIds: const <String>[
          '/workspace/demo/src/main.styio',
        ],
      ),
    );
    final checkpointAgent =
        checkpointContext.toJsonForChannels(const <String>['agent'])['agent']!
            as Map<String, Object?>;
    final workspaceCheckpoint =
        checkpointAgent['workspaceCheckpoint']! as Map<String, Object?>;
    expect(workspaceCheckpoint['captureStatus'], 'captured');
    expect(workspaceCheckpoint['snapshotId'], 'agent-snapshot-1');
    expect(workspaceCheckpoint['patchId'], 'patch-1');
    expect(workspaceCheckpoint['capturedDocumentCount'], 1);
    expect(workspaceCheckpoint['revertPlanStatus'], 'ready');
    expect(workspaceCheckpoint['revertReady'], isTrue);
    expect(workspaceCheckpoint['revertChangedDocumentCount'], 1);

    final catalogContext = context.withAgentCodingState(
      toolCatalog: const AgentToolSelection(
        context: AgentToolSelectionContext(
          providerKind: AgentProviderKind.cloudOpenAICompatible,
          protocol: 'openai-compatible',
          model: 'gpt-5.3-codex-spark',
        ),
        tools: <AgentToolDefinition>[
          AgentToolDefinition(
            toolId: 'readWorkspaceFile',
            displayName: 'Read Workspace File',
            description: 'Read an IDE-owned workspace file.',
            permissionMode: AgentToolPermissionMode.never,
            capabilities: <String>['workspace.read'],
          ),
        ],
        rejectedToolIds: <String>['openLocalShell'],
      ),
    );
    final catalogAgent =
        catalogContext.toJsonForChannels(const <String>['agent'])['agent']!
            as Map<String, Object?>;
    final toolCatalog = catalogAgent['toolCatalog']! as Map<String, Object?>;
    expect(toolCatalog['toolCount'], 1);
    expect(toolCatalog['toolIds'], <String>['readWorkspaceFile']);
    expect(toolCatalog['rejectedToolIds'], <String>['openLocalShell']);
    expect(
      ((toolCatalog['tools']! as List<Object?>).single!
          as Map<String, Object?>)['permissionMode'],
      'never',
    );

    final toolCallTimeline = const AgentToolCallLifecycleTracker()
        .track(const <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{"path":"main.styio"}',
          ),
        ]);
    final toolCallJournal = AgentToolCallExecutionJournal.fromTimeline(
      timeline: toolCallTimeline,
    );
    final toolReplayPlan = AgentToolCallReplayPlan.fromJournal(toolCallJournal);
    final toolLifecycleContext = context.withAgentCodingState(
      toolCallTimeline: toolCallTimeline,
      toolCallExecutionJournal: toolCallJournal,
      toolReplayPlan: toolReplayPlan,
    );
    final toolLifecycleAgent =
        toolLifecycleContext.toJsonForChannels(const <String>[
              'agent',
            ])['agent']!
            as Map<String, Object?>;
    final toolTimelineJson =
        toolLifecycleAgent['toolCallTimeline']! as Map<String, Object?>;
    final toolJournalJson =
        toolLifecycleAgent['toolCallExecutionJournal']! as Map<String, Object?>;
    final toolReplayJson =
        toolLifecycleAgent['toolReplayPlan']! as Map<String, Object?>;
    expect(toolTimelineJson['status'], 'running');
    expect(toolTimelineJson['callIds'], <String>['call-read']);
    expect(toolJournalJson['status'], 'running');
    expect(toolJournalJson['replayCandidateCount'], 1);
    expect(toolReplayJson['status'], 'ready');
    expect(toolReplayJson['ready'], isTrue);

    final compactionContext = context.withAgentCodingState(
      conversationCompaction: AgentConversationCompactionContext(
        status: AgentConversationCompactionStatus.windowedAndTruncated,
        retainedTurnCount: 2,
        sentTurnCount: 2,
        omittedTurnCount: 4,
        maxRetainedTurnCount: 2,
        maxTurnTextLength: 10,
        truncatedRetainedTurnCount: 1,
        summary: 'Anchored summary\n- user: previous request',
        summaryTurnCount: 4,
        summaryUpdatedAt: DateTime.utc(2026, 5, 22, 2, 3, 4),
      ),
    );
    final compactionAgent =
        compactionContext.toJsonForChannels(const <String>['agent'])['agent']!
            as Map<String, Object?>;
    final conversationCompaction =
        compactionAgent['conversationCompaction']! as Map<String, Object?>;
    expect(conversationCompaction['status'], 'windowedAndTruncated');
    expect(conversationCompaction['active'], isTrue);
    expect(conversationCompaction['omittedTurnCount'], 4);
    expect(conversationCompaction['truncatedRetainedTurnCount'], 1);
    expect(conversationCompaction['hasSummary'], isTrue);
    expect(conversationCompaction['summaryTurnCount'], 4);
    expect(
      conversationCompaction['summaryStrategy'],
      'deterministic-extractive',
    );
    expect(conversationCompaction['providerAssisted'], isFalse);
    expect(conversationCompaction['summary'], contains('previous request'));
    expect(conversationCompaction.containsKey('todoItems'), isFalse);
    expect(
      conversationCompaction['summaryUpdatedAt'],
      '2026-05-22T02:03:04.000Z',
    );

    final permissionContext = context.withAgentCodingState(
      toolPermissionPlan: const AgentToolPermissionPlan(
        status: AgentToolPermissionPlanStatus.reviewRequired,
        decisions: <AgentToolPermissionDecision>[
          AgentToolPermissionDecision(
            toolId: 'applyWorkspacePatch',
            displayName: 'Apply Workspace Patch',
            permissionMode: AgentToolPermissionMode.review,
            action: AgentToolPermissionAction.ask,
            status: AgentToolPermissionDecisionStatus.reviewRequired,
            source: 'tool-default',
            reason: 'Tool applyWorkspacePatch requires review.',
          ),
        ],
      ),
    );
    final permissionAgent =
        permissionContext.toJsonForChannels(const <String>['agent'])['agent']!
            as Map<String, Object?>;
    final toolPermissions =
        permissionAgent['toolPermissions']! as Map<String, Object?>;
    expect(toolPermissions['status'], 'review_required');
    expect(toolPermissions['reviewToolIds'], <String>['applyWorkspacePatch']);
  });

  test('agent change review gate reports blocked remediation facts', () {
    final gate = AgentCodingChangeReviewGate.fromControllerState(
      hasPendingPatch: true,
      hasWorkspaceEditPreview: false,
      applyingPatch: false,
      applyingIdeCommand: false,
      executionReadiness: const AgentCodingExecutionReadiness(
        status: AgentCodingExecutionReadinessStatus.blocked,
        issues: <AgentCodingExecutionReadinessIssue>[
          AgentCodingExecutionReadinessIssue(
            code: 'ide.runtime-contracts.blocking',
            message: 'Runtime contracts are not ready.',
            severity: AgentCodingExecutionReadinessIssueSeverity.blocking,
            ownerLayer: 'foundation',
          ),
        ],
      ),
    );

    expect(gate.status, AgentCodingChangeReviewGateStatus.blocked);
    expect(gate.canApplyPreview, isFalse);
    expect(gate.hasIssue('agent.change.preview-missing'), isTrue);
    expect(gate.hasIssue('agent.execution-readiness.blocked'), isTrue);
    expect(
      gate.todoItems,
      contains(
        'Require AgentWorkspaceEditPlanAdapter conversion before apply.',
      ),
    );
    expect(gate.todoItems.join('\n'), isNot(contains('TODO:')));
  });

  test('agent session context serializes editor and runtime facts', () {
    const document = DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: 'value = 1\nvalue\n',
      revision: 4,
    );
    const selection = SelectionState(baseOffset: 0, extentOffset: 5);
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'demo-warning',
      message: 'demo diagnostic',
      range: SourceRange(start: 0, end: 5),
    );
    const session = ExecutionSession(
      sessionId: 'run-1',
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage: 'run completed',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[ExecutionLogEvent(message: 'ok')],
      stderrEvents: <ExecutionLogEvent>[],
    );
    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: selection,
      diagnostics: const <Diagnostic>[diagnostic],
      focusedDiagnostics: const <Diagnostic>[diagnostic],
      lastExecutionSession: session,
      workspaceFiles: const <String>[
        '/workspace/demo/src/main.styio',
        '/workspace/demo/src/other.styio',
      ],
      openDocumentIds: const <String>[
        '/workspace/demo/src/main.styio',
        '/workspace/demo/src/other.styio',
      ],
      dirtyDocumentIds: const <String>['/workspace/demo/src/other.styio'],
      workspaceDocuments: const <DocumentState>[
        DocumentState(
          documentId: '/workspace/demo/src/other.styio',
          text: 'other = 2\n',
          revision: 2,
        ),
      ],
      focusToken: const TokenSpan(
        range: SourceRange(start: 0, end: 5),
        kind: TokenKind.identifier,
        lexeme: 'value',
      ),
      focusSemanticKind: SemanticKind.variable,
      hover: const HoverPayload(
        range: SourceRange(start: 0, end: 5),
        markdown: '**value**: i64',
      ),
      definition: const DefinitionTarget(
        symbol: DocumentSymbol(
          name: 'value',
          kind: SymbolKind.state,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 9),
          detail: 'i64',
          documentation: 'Current value.',
        ),
        originRange: SourceRange(start: 10, end: 15),
      ),
      resolvedElement: const ResolvedElement(
        name: 'value',
        kind: ResolvedElementKind.variable,
        nameRange: SourceRange(start: 0, end: 5),
        declarationRange: SourceRange(start: 0, end: 9),
        detail: 'i64',
        documentation: 'Current value.',
      ),
      resolvedReference: const ResolvedReference(
        name: 'value',
        range: SourceRange(start: 10, end: 15),
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
      parameterInfo: const ParameterInfoPayload(
        callableName: 'blend',
        signature: 'fn blend(left: f64, right: f64 = 0.0)',
        parameters: <ParameterInfoParameter>[
          ParameterInfoParameter(
            name: 'left',
            range: SourceRange(start: 100, end: 109),
            type: 'f64',
            documentation: 'Base price before tax.',
          ),
          ParameterInfoParameter(
            name: 'right',
            range: SourceRange(start: 111, end: 128),
            type: 'f64',
            defaultValue: '0.0',
            documentation: 'Tax component to add.',
          ),
        ],
        activeParameterIndex: 1,
        invocationRange: SourceRange(start: 160, end: 177),
        callableRange: SourceRange(start: 160, end: 165),
        documentation: 'Blends price and tax inputs.',
      ),
      safeDeletePlan: const SafeDeletePlan(
        target: DocumentSymbol(
          name: 'unused',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 20, end: 26),
          declarationRange: SourceRange(start: 20, end: 31),
        ),
        references: <ReferenceSpan>[],
        edits: <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 20, end: 31), newText: ''),
        ],
      ),
      inlineVariablePlan: const InlineVariablePlan(
        target: DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 9),
        ),
        initializerRange: SourceRange(start: 8, end: 9),
        initializerText: '1',
        references: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 10, end: 15),
            targetRange: SourceRange(start: 0, end: 5),
          ),
        ],
        edits: <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 10, end: 15), newText: '1'),
        ],
      ),
      surroundTemplates: const <SurroundTemplate>[
        SurroundTemplate(
          id: 'if-block',
          label: 'if block',
          openingLine: 'if condition {',
          closingLine: '}',
          detail: 'Wrap selection in an if block.',
        ),
      ],
      references: const <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.state,
          range: SourceRange(start: 0, end: 5),
          targetRange: SourceRange(start: 0, end: 5),
          isDeclaration: true,
          access: ReferenceAccess.write,
        ),
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.state,
          range: SourceRange(start: 10, end: 15),
          targetRange: SourceRange(start: 0, end: 5),
        ),
      ],
      completions: const <CompletionItem>[
        CompletionItem(
          label: 'value',
          kind: CompletionItemKind.variable,
          insertText: 'value',
          detail: 'i64',
          documentation: 'Current value.',
          replacementRange: SourceRange(start: 10, end: 15),
        ),
      ],
      codeActions: const <DiagnosticQuickFix>[
        DiagnosticQuickFix(
          label: 'Replace with value',
          detail: 'Use the resolved symbol.',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 10, end: 15),
              newText: 'value',
            ),
          ],
        ),
      ],
      semanticSpans: const <SemanticSpan>[
        SemanticSpan(
          range: SourceRange(start: 0, end: 5),
          kind: SemanticKind.variable,
          modifiers: <String>['declaration'],
        ),
        SemanticSpan(
          range: SourceRange(start: 10, end: 15),
          kind: SemanticKind.variable,
        ),
      ],
      documentSymbols: const <DocumentSymbol>[
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.state,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 9),
          detail: 'i64',
          documentation: 'Current value.',
        ),
      ],
      inlayHints: const <InlayHint>[
        InlayHint(
          label: 'right:',
          kind: InlayHintKind.parameter,
          position: 170,
          range: SourceRange(start: 166, end: 175),
        ),
      ],
      semanticBlocks: const <SemanticBlockRange>[
        SemanticBlockRange(
          label: 'state value',
          range: SourceRange(start: 0, end: 16),
        ),
      ],
      languageServiceStatus: _agentLanguageServiceStatus,
      debug: const AgentDebugContext(
        status: 'paused',
        message: 'Paused at main.',
        debuggerId: 'fake-lldb',
        debuggerLabel: 'Fake LLDB',
        breakpointCount: 1,
        breakpoints: <AgentDebugBreakpointContext>[
          AgentDebugBreakpointContext(
            filePath: '/workspace/demo/src/main.cc',
            line: 7,
            enabled: true,
          ),
        ],
        threadCount: 1,
        threads: <AgentDebugThreadContext>[
          AgentDebugThreadContext(id: '1', name: 'main thread'),
        ],
        stackFrameCount: 1,
        stackFrames: <AgentDebugStackFrameContext>[
          AgentDebugStackFrameContext(
            id: 'frame-0',
            name: 'main',
            filePath: '/workspace/demo/src/main.cc',
            line: 7,
            column: 5,
          ),
        ],
        variableCount: 1,
        variables: <AgentDebugVariableContext>[
          AgentDebugVariableContext(name: 'argc', value: '1', type: 'int'),
        ],
        launch: AgentDebugLaunchContext(
          ready: true,
          readiness: 'ready',
          reason: 'Debug launch configuration is ready.',
          adapterProtocol: 'dap',
          debuggerId: 'fake-lldb',
          debuggerLabel: 'Fake LLDB',
          debuggerExecutablePath: '/usr/bin/lldb-dap',
          debuggerArguments: <String>['--stdio'],
          programPath: '/workspace/demo/build/demo',
          cwd: '/workspace/demo',
          arguments: <String>['--smoke'],
          environment: <String, String>{'VITYO_ENV': 'test'},
          stopOnEntry: true,
          breakpointCount: 1,
        ),
      ),
      activeFilePath: '/workspace/demo/src/main.styio',
      workspaceDiagnostics: const WorkspaceDiagnosticsSnapshot(
        providerId: 'workspace-diagnostics',
        diagnostics: <WorkspaceDiagnostic>[
          WorkspaceDiagnostic(
            documentId: '/workspace/demo/src/main.styio',
            diagnostic: diagnostic,
            providerId: 'styio-service',
          ),
        ],
      ),
      sourceControlStatus: const SourceControlStatusSnapshot(
        providerKind: SourceControlProviderKind.git,
        branchName: 'ai-dev',
        changes: <SourceControlFileChange>[
          SourceControlFileChange(
            path: '/workspace/demo/src/main.styio',
            unstagedStatus: SourceControlFileStatus.modified,
          ),
        ],
      ),
      sourceControlDiff: const SourceControlDiffSnapshot(
        providerKind: SourceControlProviderKind.git,
        path: '/workspace/demo/src/main.styio',
        unifiedDiff: 'diff --git a/src/main.styio b/src/main.styio\n+value\n',
      ),
      sourceControlContext: SourceControlAgentContextSnapshot.fromState(
        workspaceRoot: '/workspace/demo',
        status: const SourceControlStatusSnapshot(
          providerKind: SourceControlProviderKind.git,
          branchName: 'ai-dev',
          changes: <SourceControlFileChange>[
            SourceControlFileChange(
              path: '/workspace/demo/src/main.styio',
              unstagedStatus: SourceControlFileStatus.modified,
            ),
          ],
        ),
        diffPreview: const SourceControlDiffSnapshot(
          providerKind: SourceControlProviderKind.git,
          path: '/workspace/demo/src/main.styio',
          unifiedDiff: 'diff --git a/src/main.styio b/src/main.styio\n+value\n',
        ),
        pendingActionPlan: SourceControlActionPlan.fromRequest(
          const SourceControlActionRequest(
            kind: SourceControlActionKind.discard,
            paths: <String>['/workspace/demo/src/main.styio'],
          ),
        ),
        lastActionResult: const SourceControlActionResult(
          kind: SourceControlActionKind.stage,
          applied: true,
          paths: <String>['/workspace/demo/src/main.styio'],
          message: 'staged for review',
        ),
      ),
      workspaceRoot: '/workspace/demo',
      testDiscovery: const TestDiscoveryResult(
        providerId: 'ctest-discovery',
        roots: <TestNode>[
          TestNode(
            id: 'suite:language',
            label: 'language',
            kind: TestNodeKind.suite,
            children: <TestNode>[
              TestNode(
                id: 'test:syntax',
                label: 'syntax contract',
                kind: TestNodeKind.test,
              ),
            ],
          ),
        ],
      ),
      lastTestRun: const TestRunResult(
        providerId: 'ctest',
        runner: 'ctest',
        status: TestRunStatus.failed,
        message: 'CTest reported 1 failed test(s).',
        totalCount: 2,
        passedCount: 1,
        failedCount: 1,
        cases: <TestCaseResult>[
          TestCaseResult(name: 'syntax contract', status: TestRunStatus.failed),
        ],
      ),
      testRunConfigurationSet: const TestRunConfigurationSet(
        workspaceId: '/workspace/demo',
        selectedConfigurationId: 'all-tests',
        configurations: <TestRunConfiguration>[
          TestRunConfiguration(
            id: 'all-tests',
            label: 'All Tests',
            workspaceRoot: '/workspace/demo',
            providerId: 'ctest',
          ),
        ],
      ),
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-toolchain',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-clang-cpp-compiler',
            kind: ToolchainKind.compiler,
            displayName: 'Clang C/C++ Compiler',
            executablePath: '/usr/bin/clang++',
            active: true,
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': '/usr/bin/clang',
              'cxxCompilerPath': '/usr/bin/clang++',
              'defaultForNativeCode': true,
            },
          ),
        ],
      ),
      lastRuntimeEvents: <RuntimeEventEnvelope>[
        RuntimeEventEnvelope(
          schemaVersion: 1,
          sessionId: 'run-1',
          sequence: 1,
          timestamp: DateTime.utc(2026, 5, 18),
          eventKind: 'runtime.stdout',
          origin: 'test',
          payload: const <String, Object?>{'line': 'ok'},
        ),
      ],
    );

    final json = context.toJson();
    final documentJson = json['document']! as Map<String, Object?>;
    final selectionJson = json['selection']! as Map<String, Object?>;
    final diagnosticsJson = json['diagnostics']! as List<Object?>;
    final runtimeJson = json['runtime']! as Map<String, Object?>;
    final debugJson = json['debug']! as Map<String, Object?>;
    final workspaceJson = json['workspace']! as Map<String, Object?>;
    final agentJson = json['agent']! as Map<String, Object?>;
    final workspaceSamples = workspaceJson['documentSamples']! as List<Object?>;
    final commandsJson = json['commands']! as Map<String, Object?>;
    final languageJson = json['language']! as Map<String, Object?>;
    final languageFocusToken =
        languageJson['focusToken']! as Map<String, Object?>;
    final skillsJson = json['skills']! as Map<String, Object?>;
    final testingJson = json['testing']! as Map<String, Object?>;
    final toolchainsJson = json['toolchains']! as Map<String, Object?>;
    final ideCapabilitiesJson =
        json['ideCapabilities']! as Map<String, Object?>;
    final ideCapabilityClosureJson =
        json['ideCapabilityClosure']! as Map<String, Object?>;
    final ideCapabilityEntries =
        ideCapabilitiesJson['entries']! as List<Object?>;
    final languageDefinition =
        languageJson['definition']! as Map<String, Object?>;
    final languageFocusedDiagnostics =
        languageJson['focusedDiagnostics']! as List<Object?>;
    final languageReferences = languageJson['references']! as List<Object?>;
    final languageCompletions = languageJson['completions']! as List<Object?>;
    final languageCodeActions = languageJson['codeActions']! as List<Object?>;
    final languageServiceStatus =
        languageJson['serviceStatus']! as Map<String, Object?>;
    final languagePrimaryCapabilityStates =
        languageServiceStatus['primaryCapabilityStates']!
            as Map<String, Object?>;
    final languageCapabilities =
        languageServiceStatus['capabilities']! as List<Object?>;
    final persistenceCommands =
        commandsJson['persistenceCommands']! as List<Object?>;
    final executionCommands =
        commandsJson['executionCommands']! as List<Object?>;
    final diagnosticCommands =
        commandsJson['diagnosticCommands']! as List<Object?>;
    final languageServiceCommands =
        commandsJson['languageServiceCommands']! as List<Object?>;
    final workspaceFileCommands =
        commandsJson['workspaceFileCommands']! as List<Object?>;
    final codingCommands = commandsJson['codingCommands']! as List<Object?>;
    final navigationCommands =
        commandsJson['navigationCommands']! as List<Object?>;
    final refactorCommands = commandsJson['refactorCommands']! as List<Object?>;
    final dependencyCommands =
        commandsJson['dependencyCommands']! as List<Object?>;
    final toolchainCommands =
        commandsJson['toolchainCommands']! as List<Object?>;
    final deploymentCommands =
        commandsJson['deploymentCommands']! as List<Object?>;
    final moduleCommands = commandsJson['moduleCommands']! as List<Object?>;
    final surfaceCommands = commandsJson['surfaceCommands']! as List<Object?>;
    final nativeToolCommands =
        commandsJson['nativeToolCommands']! as List<Object?>;
    final nativeToolCommandReadiness =
        commandsJson['nativeToolCommandReadiness']! as List<Object?>;
    final testingCommands = commandsJson['testingCommands']! as List<Object?>;
    final debugCommands = commandsJson['debugCommands']! as List<Object?>;
    final debugCommandReadiness =
        commandsJson['debugCommandReadiness']! as List<Object?>;
    final settingsCommands = commandsJson['settingsCommands']! as List<Object?>;
    final debugBreakpoints = debugJson['breakpoints']! as List<Object?>;
    final debugThreads = debugJson['threads']! as List<Object?>;
    final debugStackFrames = debugJson['stackFrames']! as List<Object?>;
    final debugVariables = debugJson['variables']! as List<Object?>;
    final debugLaunch = debugJson['launch']! as Map<String, Object?>;
    final workspaceDiagnostics =
        workspaceJson['diagnostics']! as Map<String, Object?>;
    final sourceControl =
        workspaceJson['sourceControl']! as Map<String, Object?>;
    final sourceControlDiff =
        workspaceJson['sourceControlDiff']! as Map<String, Object?>;
    final sourceControlContext =
        workspaceJson['sourceControlContext']! as Map<String, Object?>;
    final testingDiscovery = testingJson['discovered']! as Map<String, Object?>;
    final testingLastRun = testingJson['lastRun']! as Map<String, Object?>;
    final testingRerunFailed =
        testingJson['rerunFailed']! as Map<String, Object?>;
    final testingDebugFailed =
        testingJson['debugFailed']! as Map<String, Object?>;
    final testingDebugRoute =
        testingJson['debugFailedRoutePlan']! as Map<String, Object?>;
    final testingConfigurationSet =
        testingJson['configurationSet']! as Map<String, Object?>;

    expect(json['schemaVersion'], 88);
    final registeredCommandIds =
        commandsJson['registeredCommandIds']! as List<Object?>;
    expect(commandsJson['commandCount'], registeredCommandIds.length);
    expect(registeredCommandIds, contains('runBuild'));
    expect(registeredCommandIds, contains('renameSymbol'));
    expect(registeredCommandIds.toSet().length, registeredCommandIds.length);
    expect(workspaceDiagnostics['providerId'], 'workspace-diagnostics');
    expect(workspaceDiagnostics['totalCount'], 1);
    expect(sourceControl['providerKind'], 'git');
    expect(sourceControl['branchName'], 'ai-dev');
    expect(sourceControlDiff['path'], '/workspace/demo/src/main.styio');
    expect(sourceControlDiff['unifiedDiff'], contains('+value'));
    expect(sourceControlContext['workspaceRoot'], '/workspace/demo');
    expect(sourceControlContext['providerKind'], 'git');
    expect(sourceControlContext['branchName'], 'ai-dev');
    expect(sourceControlContext['unstagedPaths'], <String>[
      '/workspace/demo/src/main.styio',
    ]);
    expect(
      sourceControlContext['diffReview'],
      containsPair('additionCount', 1),
    );
    final sourceControlPendingAction =
        sourceControlContext['pendingActionPlan']! as Map<String, Object?>;
    final sourceControlPendingRequest =
        sourceControlPendingAction['request']! as Map<String, Object?>;
    final sourceControlLastAction =
        sourceControlContext['lastActionResult']! as Map<String, Object?>;
    expect(sourceControlPendingRequest['kind'], 'discard');
    expect(sourceControlPendingAction['requiresConfirmation'], isTrue);
    expect(sourceControlLastAction['kind'], 'stage');
    expect(sourceControlLastAction['applied'], isTrue);
    expect(sourceControlLastAction['message'], 'staged for review');
    expect(testingJson['hasDiscovery'], isTrue);
    expect(testingJson['hasLastRun'], isTrue);
    expect(testingJson['hasFailingTests'], isTrue);
    expect(
      testingJson['suggestedCommandIds'],
      containsAll(<String>[
        'rerunFailedTests',
        'debugFailedTests',
        'runTestConfiguration',
        'debugTestConfiguration',
      ]),
    );
    expect(testingDiscovery['testCount'], 1);
    expect(testingLastRun['status'], 'failed');
    expect(testingLastRun['failedCount'], 1);
    expect(testingConfigurationSet['configurationCount'], 1);
    expect(testingConfigurationSet['selectedConfigurationId'], 'all-tests');
    expect(testingRerunFailed['id'], 'rerun-failed');
    expect(testingRerunFailed['workspaceRoot'], '/workspace/demo');
    expect(testingRerunFailed['filter'], contains('syntax contract'));
    expect(testingDebugFailed['debug'], isTrue);
    expect(testingDebugRoute['ready'], isFalse);
    expect(testingDebugRoute['status'], 'blocked');
    expect(ideCapabilitiesJson['version'], 'vityo-ide-capability-framework-v1');
    expect(ideCapabilitiesJson['followUpCount'], greaterThan(0));
    expect(ideCapabilityClosureJson['isFrameworkClosed'], isTrue);
    expect(ideCapabilityClosureJson['isRuntimeMature'], isFalse);
    expect(
      ideCapabilityClosureJson['severityCounts'],
      containsPair('todo', greaterThan(0)),
    );
    expect(ideCapabilityClosureJson['readyCount'], greaterThan(0));
    expect(ideCapabilityClosureJson['todoCount'], greaterThan(0));
    expect(ideCapabilityClosureJson['failedCount'], 0);
    expect(ideCapabilityClosureJson['hardFailureCount'], 0);
    expect(
      ideCapabilityClosureJson['runtimeMaturityBlockerCapabilityIds'],
      isNot(contains('runtime.execution')),
    );
    expect(
      agentJson['suggestedCommandIds'],
      contains('collectAgentCodingCheckpoint'),
    );
    expect(
      (ideCapabilitiesJson['statusCounts']!
          as Map<String, Object?>)['scaffolded'],
      greaterThan(0),
    );
    expect(
      ideCapabilityEntries
          .map((entry) => (entry! as Map<String, Object?>)['id'])
          .toSet(),
      contains('runtime.execution'),
    );
    expect(documentJson['documentId'], '/workspace/demo/src/main.styio');
    expect(documentJson['revision'], 4);
    expect(documentJson['text'], 'value = 1\nvalue\n');
    expect(documentJson['textStart'], 0);
    expect(documentJson['textEnd'], 16);
    expect(documentJson['textTruncated'], isFalse);
    expect(selectionJson['selectedText'], 'value');
    expect(selectionJson['isCollapsed'], isFalse);
    expect(selectionJson['coordinateBase'], 'zero-based');
    expect(selectionJson['baseLine'], 0);
    expect(selectionJson['baseColumn'], 0);
    expect(selectionJson['extentLine'], 0);
    expect(selectionJson['extentColumn'], 5);
    expect(selectionJson['startLine'], 0);
    expect(selectionJson['startColumn'], 0);
    expect(selectionJson['endLine'], 0);
    expect(selectionJson['endColumn'], 5);
    expect(diagnosticsJson.single, isA<Map<String, Object?>>());
    expect(json['diagnosticCount'], 1);
    expect(json['diagnosticsTruncated'], isFalse);
    expect(
      (diagnosticsJson.single! as Map<String, Object?>)['severity'],
      'warning',
    );
    expect(
      (diagnosticsJson.single! as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect((diagnosticsJson.single! as Map<String, Object?>)['startLine'], 0);
    expect((diagnosticsJson.single! as Map<String, Object?>)['startColumn'], 0);
    expect((diagnosticsJson.single! as Map<String, Object?>)['endLine'], 0);
    expect((diagnosticsJson.single! as Map<String, Object?>)['endColumn'], 5);
    expect(
      (diagnosticsJson.single! as Map<String, Object?>)['suggestedCommandIds'],
      contains('applyQuickFix'),
    );
    expect(languageJson['focusedDiagnosticCount'], 1);
    expect(languageJson['focusedDiagnosticsTruncated'], isFalse);
    expect(
      (languageFocusedDiagnostics.single! as Map<String, Object?>)['code'],
      'demo-warning',
    );
    expect(
      (languageFocusedDiagnostics.single!
          as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect(
      (languageFocusedDiagnostics.single! as Map<String, Object?>)['startLine'],
      0,
    );
    expect(
      (languageFocusedDiagnostics.single!
          as Map<String, Object?>)['suggestedCommandIds'],
      contains('previewQuickFix'),
    );
    expect(
      (languageFocusedDiagnostics.single!
          as Map<String, Object?>)['startColumn'],
      0,
    );
    expect(runtimeJson['hasSession'], isTrue);
    expect(runtimeJson['sessionId'], 'run-1');
    expect(runtimeJson['status'], 'succeeded');
    expect(runtimeJson['stdoutTail'], <String>['ok']);
    expect(runtimeJson['stdoutEventCount'], 1);
    expect(runtimeJson['stdoutTruncated'], isFalse);
    expect(runtimeJson['eventKinds'], <String>['runtime.stdout']);
    expect(runtimeJson['eventKindCount'], 1);
    expect(runtimeJson['eventKindsTruncated'], isFalse);
    expect(debugJson['status'], 'paused');
    expect(debugJson['message'], 'Paused at main.');
    expect(debugJson['suggestedCommandIds'], <String>[
      'toggleBreakpoint',
      'saveAll',
      'stopDebugging',
      'continueDebugging',
      'stepOver',
      'selectDebugThread',
      'selectDebugStackFrame',
    ]);
    expect(debugJson['debuggerId'], 'fake-lldb');
    expect(debugJson['debuggerLabel'], 'Fake LLDB');
    expect(debugJson['breakpointCount'], 1);
    expect(
      (debugBreakpoints.single! as Map<String, Object?>)['filePath'],
      '/workspace/demo/src/main.cc',
    );
    expect((debugBreakpoints.single! as Map<String, Object?>)['line'], 7);
    expect(debugJson['threadCount'], 1);
    expect(
      (debugThreads.single! as Map<String, Object?>)['name'],
      'main thread',
    );
    expect(debugJson['stackFrameCount'], 1);
    expect((debugStackFrames.single! as Map<String, Object?>)['name'], 'main');
    expect((debugStackFrames.single! as Map<String, Object?>)['column'], 5);
    expect(debugJson['variableCount'], 1);
    expect((debugVariables.single! as Map<String, Object?>)['name'], 'argc');
    expect((debugVariables.single! as Map<String, Object?>)['type'], 'int');
    expect(debugLaunch['ready'], isTrue);
    expect(debugLaunch['readiness'], 'ready');
    expect(debugLaunch['adapterProtocol'], 'dap');
    expect(debugLaunch['debuggerArguments'], <String>['--stdio']);
    expect(debugLaunch['programPath'], '/workspace/demo/build/demo');
    expect(debugLaunch['arguments'], <String>['--smoke']);
    expect(debugLaunch['stopOnEntry'], isTrue);
    expect(workspaceJson['activeFilePath'], '/workspace/demo/src/main.styio');
    expect(workspaceJson['fileCount'], 2);
    expect(workspaceJson['files'], contains('/workspace/demo/src/other.styio'));
    expect(workspaceJson['openDocumentIds'], <String>[
      '/workspace/demo/src/main.styio',
      '/workspace/demo/src/other.styio',
    ]);
    expect(workspaceJson['dirtyDocumentIds'], <String>[
      '/workspace/demo/src/other.styio',
    ]);
    expect(workspaceJson['documentSampleCount'], 2);
    expect(workspaceJson['documentSamplesTruncated'], isFalse);
    expect(
      (workspaceSamples.first! as Map<String, Object?>)['documentId'],
      '/workspace/demo/src/main.styio',
    );
    expect((workspaceSamples.first! as Map<String, Object?>)['active'], isTrue);
    expect((workspaceSamples.first! as Map<String, Object?>)['open'], isTrue);
    expect((workspaceSamples.first! as Map<String, Object?>)['dirty'], isFalse);
    expect(
      (workspaceSamples.last! as Map<String, Object?>)['documentId'],
      '/workspace/demo/src/other.styio',
    );
    expect(
      (workspaceSamples.last! as Map<String, Object?>)['text'],
      'other = 2\n',
    );
    expect((workspaceSamples.last! as Map<String, Object?>)['dirty'], isTrue);
    expect(agentJson['lastPatchApplication'], isNull);
    expect(languageJson['hasHover'], isTrue);
    expect(languageJson['hoverMarkdown'], '**value**: i64');
    expect(
      (languageJson['hoverRange']! as Map<String, Object?>)['endColumn'],
      5,
    );
    expect(languageFocusToken['lexeme'], 'value');
    expect(languageFocusToken['kind'], 'identifier');
    expect(languageFocusToken['semanticKind'], 'variable');
    expect(languageFocusToken['start'], 0);
    expect(
      (languageFocusToken['range']! as Map<String, Object?>)['endColumn'],
      5,
    );
    expect(languageDefinition['name'], 'value');
    expect(languageDefinition['kind'], 'state');
    expect(
      (languageDefinition['originRange']!
          as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect(
      (languageDefinition['originRange']! as Map<String, Object?>)['startLine'],
      1,
    );
    expect(
      (languageDefinition['originRange']!
          as Map<String, Object?>)['startColumn'],
      0,
    );
    expect(
      (languageDefinition['nameRange']! as Map<String, Object?>)['startLine'],
      0,
    );
    expect(languageDefinition['agentCommandId'], 'goToDefinition');
    final resolvedElement =
        languageJson['resolvedElement']! as Map<String, Object?>;
    final resolvedReference =
        languageJson['resolvedReference']! as Map<String, Object?>;
    final languageParameterInfo =
        languageJson['parameterInfo']! as Map<String, Object?>;
    final languageParameterInfoParameters =
        languageParameterInfo['parameters']! as List<Object?>;
    expect(resolvedElement['name'], 'value');
    expect(resolvedElement['kind'], 'variable');
    expect(resolvedElement['detail'], 'i64');
    expect(
      (resolvedElement['nameRange']! as Map<String, Object?>)['startColumn'],
      0,
    );
    expect(resolvedReference['name'], 'value');
    expect(resolvedReference['access'], 'read');
    expect(
      (resolvedReference['range']! as Map<String, Object?>)['startLine'],
      1,
    );
    expect(
      (resolvedReference['range']! as Map<String, Object?>)['endColumn'],
      5,
    );
    expect(
      (resolvedReference['target']! as Map<String, Object?>)['name'],
      'value',
    );
    expect(languageParameterInfo['callableName'], 'blend');
    expect(
      languageParameterInfo['signature'],
      'fn blend(left: f64, right: f64 = 0.0)',
    );
    expect(languageParameterInfo['activeParameterIndex'], 1);
    expect(languageParameterInfo['parameterCount'], 2);
    expect(languageParameterInfo['parametersTruncated'], isFalse);
    expect(languageParameterInfo['invocationStart'], 160);
    expect(languageParameterInfo['callableEnd'], 165);
    expect(
      (languageParameterInfo['invocationRange']!
          as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect(
      (languageParameterInfo['callableRange']!
          as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect(
      (languageParameterInfo['activeParameter']!
          as Map<String, Object?>)['name'],
      'right',
    );
    expect(
      ((languageParameterInfo['activeParameter']!
              as Map<String, Object?>)['range']!
          as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect(
      (languageParameterInfoParameters.last!
          as Map<String, Object?>)['defaultValue'],
      '0.0',
    );
    expect(languageJson['referenceCount'], 2);
    expect(languageJson['referencesTruncated'], isFalse);
    expect(
      (languageReferences.first! as Map<String, Object?>)['isDeclaration'],
      isTrue,
    );
    expect(
      (languageReferences.first! as Map<String, Object?>)['agentCommandIds'],
      contains('nextReference'),
    );
    expect(
      (languageReferences.first! as Map<String, Object?>)['agentCommandIds'],
      contains('previousReference'),
    );
    expect(
      ((languageReferences.last! as Map<String, Object?>)['range']!
          as Map<String, Object?>)['startLine'],
      1,
    );
    expect(
      ((languageReferences.last! as Map<String, Object?>)['targetRange']!
          as Map<String, Object?>)['startLine'],
      0,
    );
    expect(languageJson['completionCount'], 1);
    expect(languageJson['completionsTruncated'], isFalse);
    expect(
      (languageCompletions.single! as Map<String, Object?>)['label'],
      'value',
    );
    expect(
      (languageCompletions.single! as Map<String, Object?>)['replacementStart'],
      10,
    );
    expect(
      ((languageCompletions.single!
              as Map<String, Object?>)['replacementRange']!
          as Map<String, Object?>)['startLine'],
      1,
    );
    expect(languageJson['codeActionCount'], 1);
    expect(languageJson['codeActionsTruncated'], isFalse);
    expect(
      (languageCodeActions.single! as Map<String, Object?>)['label'],
      'Replace with value',
    );
    expect(
      (languageCodeActions.single! as Map<String, Object?>)['selectionIndex'],
      1,
    );
    expect(
      (languageCodeActions.single! as Map<String, Object?>)['agentCommandId'],
      'applyQuickFix',
    );
    expect(
      (languageCodeActions.single!
          as Map<String, Object?>)['agentCommandInput'],
      '1',
    );
    expect(
      (languageCodeActions.single!
          as Map<String, Object?>)['agentCommandLabelInput'],
      'Replace with value',
    );
    expect(
      (languageCodeActions.single! as Map<String, Object?>)['firstEditStart'],
      10,
    );
    expect(
      ((languageCodeActions.single! as Map<String, Object?>)['firstEditRange']!
          as Map<String, Object?>)['startLine'],
      1,
    );
    final languageCodeActionEdits =
        (languageCodeActions.single! as Map<String, Object?>)['edits']!
            as List<Object?>;
    expect(
      (languageCodeActionEdits.single! as Map<String, Object?>)['start'],
      10,
    );
    expect(
      (languageCodeActionEdits.single! as Map<String, Object?>)['end'],
      15,
    );
    expect(
      ((languageCodeActionEdits.single! as Map<String, Object?>)['range']!
          as Map<String, Object?>)['endColumn'],
      5,
    );
    expect(
      (languageCodeActionEdits.single! as Map<String, Object?>)['newText'],
      'value',
    );
    expect(
      (languageCodeActions.single! as Map<String, Object?>)['editsTruncated'],
      isFalse,
    );
    expect(languageJson['semanticSpanCount'], 2);
    expect(languageJson['semanticSpansTruncated'], isFalse);
    final languageSemanticSpans =
        languageJson['semanticSpans']! as List<Object?>;
    final languageDocumentSymbols =
        languageJson['documentSymbols']! as List<Object?>;
    final languageInlayHints = languageJson['inlayHints']! as List<Object?>;
    final languageSemanticBlocks =
        languageJson['semanticBlocks']! as List<Object?>;
    final languageRefactorPreviews =
        languageJson['refactorPreviews']! as List<Object?>;
    final languageSurroundTemplates =
        languageJson['surroundTemplates']! as List<Object?>;
    expect(languageSemanticSpans, hasLength(2));
    expect(
      (languageSemanticSpans.first! as Map<String, Object?>)['kind'],
      'variable',
    );
    expect(
      (languageSemanticSpans.first! as Map<String, Object?>)['modifiers'],
      <String>['declaration'],
    );
    expect(
      ((languageSemanticSpans.first! as Map<String, Object?>)['range']!
          as Map<String, Object?>)['startLine'],
      0,
    );
    expect(languageJson['documentSymbolCount'], 1);
    expect(languageJson['documentSymbolsTruncated'], isFalse);
    expect(
      (languageDocumentSymbols.single! as Map<String, Object?>)['name'],
      'value',
    );
    expect(
      (languageDocumentSymbols.single! as Map<String, Object?>)['kind'],
      'state',
    );
    expect(
      (languageDocumentSymbols.single!
          as Map<String, Object?>)['declarationEnd'],
      9,
    );
    expect(
      ((languageDocumentSymbols.single! as Map<String, Object?>)['nameRange']!
          as Map<String, Object?>)['startLine'],
      0,
    );
    expect(languageJson['inlayHintCount'], 1);
    expect(languageJson['inlayHintsTruncated'], isFalse);
    expect(
      (languageInlayHints.single! as Map<String, Object?>)['label'],
      'right:',
    );
    expect(
      (languageInlayHints.single! as Map<String, Object?>)['kind'],
      'parameter',
    );
    expect(
      (languageInlayHints.single! as Map<String, Object?>)['position'],
      170,
    );
    expect(
      (languageInlayHints.single! as Map<String, Object?>)['positionLine'],
      isA<int>(),
    );
    expect(
      ((languageInlayHints.single! as Map<String, Object?>)['range']!
          as Map<String, Object?>)['coordinateBase'],
      'zero-based',
    );
    expect(languageJson['semanticBlockCount'], 1);
    expect(languageJson['semanticBlocksTruncated'], isFalse);
    expect(
      (languageSemanticBlocks.single! as Map<String, Object?>)['label'],
      'state value',
    );
    expect((languageSemanticBlocks.single! as Map<String, Object?>)['end'], 16);
    expect(
      ((languageSemanticBlocks.single! as Map<String, Object?>)['range']!
          as Map<String, Object?>)['startLine'],
      0,
    );
    expect(languageJson['refactorPreviewCount'], 2);
    final safeDeletePreview =
        languageRefactorPreviews.first! as Map<String, Object?>;
    final inlinePreview =
        languageRefactorPreviews.last! as Map<String, Object?>;
    expect(safeDeletePreview['kind'], 'safeDelete');
    expect(safeDeletePreview['agentCommandId'], 'safeDelete');
    expect(
      (safeDeletePreview['target']! as Map<String, Object?>)['name'],
      'unused',
    );
    expect(safeDeletePreview['editCount'], 1);
    expect(inlinePreview['kind'], 'inlineVariable');
    expect(inlinePreview['agentCommandId'], 'inlineVariable');
    expect(inlinePreview['initializerText'], '1');
    expect(inlinePreview['referenceCount'], 1);
    expect(
      ((inlinePreview['edits']! as List<Object?>).single!
          as Map<String, Object?>)['newText'],
      '1',
    );
    expect(
      (((inlinePreview['edits']! as List<Object?>).single!
              as Map<String, Object?>)['range']!
          as Map<String, Object?>)['startLine'],
      1,
    );
    expect(languageJson['surroundTemplateCount'], 1);
    expect(languageJson['surroundTemplatesTruncated'], isFalse);
    expect(
      (languageSurroundTemplates.single! as Map<String, Object?>)['id'],
      'if-block',
    );
    expect(
      (languageSurroundTemplates.single!
          as Map<String, Object?>)['openingLine'],
      'if condition {',
    );
    expect(languageServiceStatus['severity'], 'ready');
    expect(languageServiceStatus['toolchainId'], 'styio-cli-nightly');
    expect(languageServiceStatus['parserEngine'], 'nightly');
    expect(languageServiceStatus['grammarVersion'], '2026.05');
    expect(languageServiceStatus['usableCapabilityCount'], 2);
    expect(languageServiceStatus['freshCapabilityCount'], 1);
    expect(languageServiceStatus['capabilityHealth'], 'degraded');
    expect(languageServiceStatus['missingCapabilityCount'], 1);
    expect(languageServiceStatus['blockedCapabilityCount'], 1);
    expect(languageServiceStatus['providerReadiness'], 'degraded');
    expect(languageServiceStatus['providerReadinessSummary'], contains('8/10'));
    expect(languageServiceStatus['providerMissingCapabilityCount'], 2);
    expect(languageServiceStatus['cacheLookupHits'], 6);
    expect(languageServiceStatus['cacheLookupMisses'], 2);
    expect(languageServiceStatus['cacheLookupCount'], 8);
    expect(languageServiceStatus['cacheLookupHitRate'], 0.75);
    expect(languageServiceStatus['localFallbackEnabled'], isTrue);
    expect(languageServiceStatus['refreshRecommended'], isTrue);
    expect(
      languageServiceStatus['suggestedCommandIds'],
      contains('refreshLanguageService'),
    );
    expect(languageServiceStatus['syntaxValidationReady'], isTrue);
    expect(languageServiceStatus['semanticFactsReady'], isFalse);
    expect(
      languageServiceStatus['unavailablePrimaryCapabilities'],
      contains('hover'),
    );
    expect(languagePrimaryCapabilityStates['diagnostics'], 'available');
    expect(languagePrimaryCapabilityStates['completion'], 'derived');
    expect(languagePrimaryCapabilityStates['hover'], 'unsupported');
    expect(
      (languageCapabilities.first! as Map<String, Object?>)['capability'],
      'diagnostics',
    );
    expect(
      (languageCapabilities.first! as Map<String, Object?>)['fresh'],
      isTrue,
    );
    expect((persistenceCommands.first! as Map<String, Object?>)['id'], 'save');
    expect(
      (persistenceCommands.last! as Map<String, Object?>)['id'],
      'saveAll',
    );
    expect((executionCommands.single! as Map<String, Object?>)['id'], 'run');
    expect(
      (diagnosticCommands.first! as Map<String, Object?>)['id'],
      'nextDiagnostic',
    );
    expect(
      (diagnosticCommands[2]! as Map<String, Object?>)['id'],
      'applyQuickFix',
    );
    expect(
      (diagnosticCommands[3]! as Map<String, Object?>)['id'],
      'previewQuickFix',
    );
    expect(
      (diagnosticCommands.last! as Map<String, Object?>)['id'],
      'refreshWorkspaceDiagnostics',
    );
    expect(
      (languageServiceCommands.single! as Map<String, Object?>)['id'],
      'refreshLanguageService',
    );
    expect(
      (codingCommands.first! as Map<String, Object?>)['id'],
      'previewQuickFix',
    );
    expect(
      (codingCommands[1]! as Map<String, Object?>)['id'],
      'collectAgentCodingCheckpoint',
    );
    expect(
      (codingCommands[2]! as Map<String, Object?>)['id'],
      'collectProjectLanguageContext',
    );
    expect(
      (navigationCommands.first! as Map<String, Object?>)['id'],
      'searchWorkspace',
    );
    expect(
      (navigationCommands[1]! as Map<String, Object?>)['id'],
      'goToDefinition',
    );
    expect(
      (navigationCommands[2]! as Map<String, Object?>)['id'],
      'openWorkspaceFile',
    );
    expect(
      (navigationCommands[2]! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect(
      (navigationCommands[3]! as Map<String, Object?>)['id'],
      'previewWorkspaceReplace',
    );
    expect(
      (navigationCommands[3]! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect(
      (navigationCommands[4]! as Map<String, Object?>)['id'],
      'applyWorkspaceReplace',
    );
    expect(
      (workspaceFileCommands.first! as Map<String, Object?>)['id'],
      'createWorkspaceFile',
    );
    expect(
      (workspaceFileCommands[1]! as Map<String, Object?>)['id'],
      'renameWorkspaceFile',
    );
    expect(
      (workspaceFileCommands[2]! as Map<String, Object?>)['id'],
      'deleteWorkspaceFile',
    );
    expect(
      (workspaceFileCommands.last! as Map<String, Object?>)['id'],
      'revealWorkspaceFile',
    );
    expect(
      (workspaceFileCommands.last! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect(
      (navigationCommands.last! as Map<String, Object?>)['id'],
      'previousReference',
    );
    expect(
      (refactorCommands.first! as Map<String, Object?>)['id'],
      'renameSymbol',
    );
    expect(
      (refactorCommands.first! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect((refactorCommands[1]! as Map<String, Object?>)['id'], 'safeDelete');
    expect(
      (refactorCommands.last! as Map<String, Object?>)['id'],
      'inlineVariable',
    );
    expect(
      dependencyCommands.map(
        (command) => (command! as Map<String, Object?>)['id'],
      ),
      <String>['fetchDependencies', 'vendorDependencies'],
    );
    expect(
      (toolchainCommands.last! as Map<String, Object?>)['id'],
      'selectClangCppVersion',
    );
    expect(
      (toolchainCommands.last! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect(
      deploymentCommands.map(
        (command) => (command! as Map<String, Object?>)['id'],
      ),
      <String>['packProject', 'preparePublish'],
    );
    expect(
      (moduleCommands.single! as Map<String, Object?>)['id'],
      'refreshModules',
    );
    expect(
      surfaceCommands.map(
        (command) => (command! as Map<String, Object?>)['id'],
      ),
      StyioCommandRegistry.surfaceCommands.map((command) => command.id.name),
    );
    expect(
      (nativeToolCommands.first! as Map<String, Object?>)['id'],
      'runBuild',
    );
    expect(
      (nativeToolCommands[1]! as Map<String, Object?>)['id'],
      'formatActiveDocument',
    );
    expect(
      (nativeToolCommands[2]! as Map<String, Object?>)['id'],
      'runStaticAnalysis',
    );
    expect(
      (nativeToolCommands.last! as Map<String, Object?>)['id'],
      'runTests',
    );
    expect(nativeToolCommandReadiness, hasLength(4));
    expect(
      (nativeToolCommandReadiness.first! as Map<String, Object?>)['commandId'],
      'runBuild',
    );
    expect(
      (nativeToolCommandReadiness.first! as Map<String, Object?>)['ready'],
      isFalse,
    );
    expect(
      (nativeToolCommandReadiness.first! as Map<String, Object?>)['reason'],
      contains('Requires a registered cmake or ninja build-tool toolchain.'),
    );
    expect(
      testingCommands.map(
        (command) => (command! as Map<String, Object?>)['id'],
      ),
      <String>[
        'rerunFailedTests',
        'debugFailedTests',
        'runTestConfiguration',
        'debugTestConfiguration',
      ],
    );
    expect(
      (debugCommands.first! as Map<String, Object?>)['id'],
      'toggleBreakpoint',
    );
    expect(debugCommands, hasLength(7));
    expect(
      (debugCommands[5]! as Map<String, Object?>)['id'],
      'selectDebugThread',
    );
    expect(
      (debugCommands[5]! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect(
      (debugCommands.last! as Map<String, Object?>)['id'],
      'selectDebugStackFrame',
    );
    expect(
      (debugCommands.last! as Map<String, Object?>)['requiresInput'],
      isTrue,
    );
    expect(debugCommandReadiness, hasLength(7));
    expect(
      (debugCommandReadiness[1]! as Map<String, Object?>)['commandId'],
      'startDebugging',
    );
    expect(
      (debugCommandReadiness[1]! as Map<String, Object?>)['ready'],
      isFalse,
    );
    expect(
      (debugCommandReadiness[1]! as Map<String, Object?>)['requiredCommandId'],
      'saveAll',
    );
    expect(
      (debugCommandReadiness[1]! as Map<String, Object?>)['dirtyDocumentIds'],
      <String>['/workspace/demo/src/other.styio'],
    );
    expect(
      (debugCommandReadiness[5]! as Map<String, Object?>)['candidateIds'],
      <String>['1'],
    );
    expect(
      (debugCommandReadiness.last! as Map<String, Object?>)['candidateIds'],
      <String>['frame-0'],
    );
    expect(
      (settingsCommands.single! as Map<String, Object?>)['id'],
      'openSettings',
    );
    expect(skillsJson['skillIds'], contains('cpp-clang-toolchain-defaults'));
    expect(skillsJson['skillIds'], contains('styio-language-service-truth'));
    expect(skillsJson['skillIds'], contains('styio-ide-feature-loop'));
    expect(skillsJson['skillIds'], contains('styio-fixture-confidence-matrix'));
    expect(skillsJson['skillIds'], contains('cpp-clang-version-handoff'));
    expect(skillsJson['skillIds'], contains('cpp-compilation-database'));
    expect(skillsJson['skillIds'], contains('cpp-clang-format-tidy'));
    expect(skillsJson['skillIds'], contains('cpp-cmake-build-graph'));
    expect(skillsJson['skillIds'], contains('cpp-clangd-indexing'));
    expect(skillsJson['skillIds'], contains('cpp-test-debug-loop'));
    expect(
      skillsJson['skillIds'],
      contains('reference-grounded-ide-development'),
    );
    expect(skillsJson['skillIds'], contains('styio-cpp-compiler-project'));
    expect(skillsJson['skillIds'], contains('styio-agent-command-loop'));
    expect(skillsJson['skillCount'], 15);
    final skills = skillsJson['skills']! as List<Object?>;
    final referenceSkill = skills.whereType<Map<String, Object?>>().singleWhere(
      (skill) => skill['skillId'] == 'reference-grounded-ide-development',
    );
    expect(referenceSkill['title'], 'Reference-Grounded IDE Development');
    expect(
      referenceSkill['toolchainDefaults'],
      contains(
        'Use VS Code, IntelliJ Community, Eclipse Theia, Monaco Editor, LSP, clangd, and Tree-sitter as reference implementations for IDE-facing work.',
      ),
    );
    expect(
      referenceSkill['validationHints'],
      contains(
        'Every code change must have a targeted test, integration test, or documented gate that covers the changed behavior.',
      ),
    );
    expect(toolchainsJson['hasNativeCompiler'], isTrue);
    expect(
      (toolchainsJson['activeCompiler']! as Map<String, Object?>)['id'],
      'native-clang-cpp-compiler',
    );
  });

  test('agent source control context suggests registered coding commands', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      sourceControlContext: SourceControlAgentContextSnapshot.fromState(
        workspaceRoot: '/workspace/demo',
        status: const SourceControlStatusSnapshot(
          providerKind: SourceControlProviderKind.git,
          branchName: 'ai-dev',
          changes: <SourceControlFileChange>[
            SourceControlFileChange(
              path: 'src/main.styio',
              stagedStatus: SourceControlFileStatus.modified,
            ),
            SourceControlFileChange(
              path: 'test/main_test.dart',
              unstagedStatus: SourceControlFileStatus.modified,
            ),
          ],
        ),
      ),
    );

    final workspaceJson =
        context.toJson()['workspace']! as Map<String, Object?>;
    final sourceControlContext =
        workspaceJson['sourceControlContext']! as Map<String, Object?>;

    expect(sourceControlContext['suggestedCommandIds'], <String>[
      'stageSourceControl',
      'unstageSourceControl',
      'planSourceControlCommitDraft',
    ]);
  });

  test('agent command catalog exposes every registered app command', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'state value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
    );

    final commandsJson = context.toJson()['commands']! as Map<String, Object?>;
    const catalogKeys = <String>[
      'persistenceCommands',
      'executionCommands',
      'diagnosticCommands',
      'languageServiceCommands',
      'sourceControlCommands',
      'workspaceFileCommands',
      'codingCommands',
      'navigationCommands',
      'refactorCommands',
      'dependencyCommands',
      'toolchainCommands',
      'deploymentCommands',
      'moduleCommands',
      'surfaceCommands',
      'nativeToolCommands',
      'testingCommands',
      'debugCommands',
      'settingsCommands',
    ];
    final exposedCommandIds = <String>{};
    for (final catalogKey in catalogKeys) {
      final commands = commandsJson[catalogKey]! as List<Object?>;
      for (final command in commands) {
        exposedCommandIds.add(
          (command! as Map<String, Object?>)['id']! as String,
        );
      }
    }
    final registeredCommandIds =
        (commandsJson['registeredCommandIds']! as List<Object?>)
            .cast<String>()
            .toSet();

    expect(exposedCommandIds, registeredCommandIds);
    expect(registeredCommandIds, contains(AppCommandId.runBuild.name));
    expect(registeredCommandIds, contains(AppCommandId.renameSymbol.name));

    final diagnosticCommands =
        commandsJson['diagnosticCommands']! as List<Object?>;
    final applyQuickFix = diagnosticCommands
        .cast<Map<String, Object?>>()
        .firstWhere(
          (command) => command['id'] == AppCommandId.applyQuickFix.name,
        );
    expect(applyQuickFix['inputLabel'], 'Optional quick fix index or label');
    expect(applyQuickFix['inputContract'], contains('1-based quick fix index'));
    expect(applyQuickFix['inputExamples'], contains('Replace with second'));
  });

  test('agent session context serializes recovery plan', () {
    final recoveryPlan = AgentCodingSessionRecoveryPlan.fromCheckpoint(
      AgentCodingSessionCheckpoint(
        workspaceId: '/workspace/demo',
        status: AgentCodingSessionCheckpointStatus.needsRecovery,
        updatedAt: DateTime.utc(2026, 5, 21),
        recordCount: 1,
        latestRequestId: 'agent-failed',
        latestProfileId: 'cloud',
        latestProviderKind: 'cloud_openai_compatible',
        latestOutcome: AgentCodingSessionOutcome.failed,
        latestPromptSample: 'Fix the current file.',
        latestCompletedAt: DateTime.utc(2026, 5, 21, 1),
      ),
    );
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'state value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      recoveryPlan: recoveryPlan,
      savedProviderProfiles: const <AgentPromptProfileManifestEntry>[
        AgentPromptProfileManifestEntry(
          key: 'cloud-key',
          profileId: 'cloud',
          displayName: 'Cloud Agent',
          route: 'web-hosted',
          protocol: 'openai-compatible',
          model: 'gpt-test',
          requiresCredential: true,
        ),
      ],
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final recoveryJson = agentJson['recoveryPlan']! as Map<String, Object?>;
    final checkpointJson = recoveryJson['checkpoint']! as Map<String, Object?>;
    final savedProfilesJson =
        agentJson['savedProviderProfiles']! as List<Object?>;
    final savedProfileJson = savedProfilesJson.single! as Map<String, Object?>;

    expect(context.schemaVersion, 88);
    final agentRegistryJson =
        agentJson['agentRegistry']! as Map<String, Object?>;
    expect(agentRegistryJson['defaultAgentId'], 'vityo-coding-agent');
    expect(agentRegistryJson['activeAgentId'], 'vityo-coding-agent');
    expect(agentRegistryJson['activeAgent'], isA<Map<String, Object?>>());
    expect(
      agentRegistryJson['primaryAgentIds'],
      contains('vityo-coding-agent'),
    );
    expect(agentRegistryJson['subagentIds'], contains('vityo-review-agent'));
    expect(agentJson['savedProviderProfileCount'], 1);
    expect(savedProfileJson['key'], 'cloud-key');
    expect(savedProfileJson['profileId'], 'cloud');
    expect(savedProfileJson['requiresCredential'], isTrue);
    expect(recoveryJson['status'], 'available');
    expect(recoveryJson['recommendedAction'], 'retrySameProvider');
    expect(
      recoveryJson['availableActions'],
      containsAll(<String>[
        'retrySameProvider',
        'failoverProvider',
        'replayPrompt',
      ]),
    );
    expect(recoveryJson['canFailoverProvider'], isTrue);
    expect(checkpointJson['latestRequestId'], 'agent-failed');
    expect(checkpointJson['latestOutcome'], 'failed');
  });

  test('agent command context reports native tool command readiness', () {
    const document = DocumentState(
      documentId: '/workspace/demo/main.cc',
      text: '',
      revision: 1,
    );
    const selection = SelectionState(baseOffset: 0, extentOffset: 0);

    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: selection,
      diagnostics: const <Diagnostic>[],
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-native-tools',
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
            id: 'native-clang-format-formatter',
            kind: ToolchainKind.formatter,
            displayName: 'clang-format Formatter',
            executablePath: '/usr/bin/clang-format',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'clang-format'},
          ),
          ToolchainStateEntry(
            id: 'native-clang-tidy-static-analyzer',
            kind: ToolchainKind.staticAnalyzer,
            displayName: 'clang-tidy Static Analyzer',
            executablePath: '/usr/bin/clang-tidy',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'clang-tidy'},
          ),
        ],
      ),
    );

    final commandsJson = context.toJson()['commands']! as Map<String, Object?>;
    final readiness =
        commandsJson['nativeToolCommandReadiness']! as List<Object?>;
    final byCommandId = <String, Map<String, Object?>>{};
    for (final entry in readiness) {
      final readinessJson = entry! as Map<String, Object?>;
      byCommandId[readinessJson['commandId']! as String] = readinessJson;
    }

    expect(byCommandId['runBuild']!['ready'], isTrue);
    expect(byCommandId['runBuild']!['toolchainId'], 'native-cmake-build-tool');
    expect(byCommandId['runBuild']!['toolFamily'], 'cmake');
    expect(byCommandId['runBuild']!['requiredToolFamilies'], <String>[
      'cmake',
      'ninja',
    ]);
    expect(byCommandId['formatActiveDocument']!['ready'], isTrue);
    expect(
      byCommandId['formatActiveDocument']!['toolchainId'],
      'native-clang-format-formatter',
    );
    expect(byCommandId['runStaticAnalysis']!['ready'], isTrue);
    expect(byCommandId['runTests']!['ready'], isFalse);
    expect(byCommandId['runTests']!['requiredToolFamily'], 'ctest');
    expect(
      byCommandId['runTests']!['reason'],
      'Requires a registered ctest test-runner toolchain.',
    );
  });

  test('agent command readiness requires CMake build artifacts', () {
    const document = DocumentState(
      documentId: '/workspace/demo/src/main.cc',
      text: 'int main() { return 0; }\n',
      revision: 1,
    );
    const selection = SelectionState(baseOffset: 0, extentOffset: 0);
    const nativeTools = ToolchainStateSnapshot(
      targetId: 'agent-cmake-native-tools',
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
        ToolchainStateEntry(
          id: 'native-ctest-test-runner',
          kind: ToolchainKind.testRunner,
          displayName: 'CTest Test Runner',
          executablePath: '/usr/bin/ctest',
          active: true,
          metadata: <String, Object?>{'toolFamily': 'ctest'},
        ),
      ],
    );

    final missingArtifacts = AgentSessionContext.fromEditorState(
      document: document,
      selection: selection,
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>['CMakeLists.txt', 'src/main.cc'],
      activeFilePath: 'src/main.cc',
      toolchainSnapshot: nativeTools,
    );
    final missingReadiness =
        (missingArtifacts.toJson()['commands']!
                as Map<String, Object?>)['nativeToolCommandReadiness']!
            as List<Object?>;
    final missingByCommandId = <String, Map<String, Object?>>{};
    for (final entry in missingReadiness) {
      final readinessJson = entry! as Map<String, Object?>;
      missingByCommandId[readinessJson['commandId']! as String] = readinessJson;
    }

    expect(missingByCommandId['runBuild']!['ready'], isTrue);
    expect(missingByCommandId['runStaticAnalysis']!['ready'], isFalse);
    expect(
      missingByCommandId['runStaticAnalysis']!['requiredCommandId'],
      'runBuild',
    );
    expect(
      missingByCommandId['runStaticAnalysis']!['reason'],
      contains('compile_commands.json is missing'),
    );
    expect(missingByCommandId['runTests']!['ready'], isFalse);
    expect(missingByCommandId['runTests']!['requiredCommandId'], 'runBuild');
    expect(
      missingByCommandId['runTests']!['reason'],
      contains('CTest build files are missing'),
    );

    final registeredArtifacts = AgentSessionContext.fromEditorState(
      document: document,
      selection: selection,
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>[
        'CMakeLists.txt',
        'build/compile_commands.json',
        'build/CTestTestfile.cmake',
        'src/main.cc',
      ],
      activeFilePath: 'src/main.cc',
      toolchainSnapshot: nativeTools,
    );
    final registeredReadiness =
        (registeredArtifacts.toJson()['commands']!
                as Map<String, Object?>)['nativeToolCommandReadiness']!
            as List<Object?>;
    final registeredByCommandId = <String, Map<String, Object?>>{};
    for (final entry in registeredReadiness) {
      final readinessJson = entry! as Map<String, Object?>;
      registeredByCommandId[readinessJson['commandId']! as String] =
          readinessJson;
    }

    expect(registeredByCommandId['runStaticAnalysis']!['ready'], isTrue);
    expect(
      registeredByCommandId['runStaticAnalysis']!['requiredCommandId'],
      isNull,
    );
    expect(registeredByCommandId['runTests']!['ready'], isTrue);
    expect(registeredByCommandId['runTests']!['requiredCommandId'], isNull);
  });

  test('agent command context accepts Ninja as build tool readiness', () {
    const document = DocumentState(
      documentId: '/workspace/demo/main.cc',
      text: '',
      revision: 1,
    );
    const selection = SelectionState(baseOffset: 0, extentOffset: 0);

    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: selection,
      diagnostics: const <Diagnostic>[],
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-ninja-build-tool',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-ninja-build-tool',
            kind: ToolchainKind.buildTool,
            displayName: 'Ninja Build Tool',
            executablePath: '/usr/bin/ninja',
            active: true,
            metadata: <String, Object?>{'toolFamily': 'ninja'},
          ),
        ],
      ),
    );

    final commandsJson = context.toJson()['commands']! as Map<String, Object?>;
    final readiness =
        commandsJson['nativeToolCommandReadiness']! as List<Object?>;
    final runBuild = readiness.whereType<Map<String, Object?>>().singleWhere(
      (entry) => entry['commandId'] == 'runBuild',
    );

    expect(runBuild['ready'], isTrue);
    expect(runBuild['toolchainId'], 'native-ninja-build-tool');
    expect(runBuild['toolFamily'], 'ninja');
    expect(runBuild['requiredToolFamilies'], <String>['cmake', 'ninja']);
    expect(runBuild['candidateToolchainIds'], <String>[
      'native-ninja-build-tool',
    ]);
  });

  test('agent command readiness requires saveAll for dirty native tools', () {
    const document = DocumentState(
      documentId: '/workspace/demo/main.cc',
      text: 'int main() { return 0; }\n',
      revision: 1,
    );
    const selection = SelectionState(baseOffset: 0, extentOffset: 0);

    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: selection,
      diagnostics: const <Diagnostic>[],
      dirtyDocumentIds: const <String>['/workspace/demo/dirty.cc'],
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-dirty-native-tools',
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
            id: 'native-clang-format-formatter',
            kind: ToolchainKind.formatter,
            displayName: 'clang-format Formatter',
            executablePath: '/usr/bin/clang-format',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'clang-format'},
          ),
          ToolchainStateEntry(
            id: 'native-clang-tidy-static-analyzer',
            kind: ToolchainKind.staticAnalyzer,
            displayName: 'clang-tidy Static Analyzer',
            executablePath: '/usr/bin/clang-tidy',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'clang-tidy'},
          ),
          ToolchainStateEntry(
            id: 'native-ctest-test-runner',
            kind: ToolchainKind.testRunner,
            displayName: 'CTest Test Runner',
            executablePath: '/usr/bin/ctest',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'ctest'},
          ),
        ],
      ),
    );

    final commandsJson = context.toJson()['commands']! as Map<String, Object?>;
    final readiness =
        commandsJson['nativeToolCommandReadiness']! as List<Object?>;
    final byCommandId = <String, Map<String, Object?>>{};
    for (final entry in readiness) {
      final readinessJson = entry! as Map<String, Object?>;
      byCommandId[readinessJson['commandId']! as String] = readinessJson;
    }

    expect(byCommandId['runBuild']!['ready'], isFalse);
    expect(byCommandId['runBuild']!['requiredCommandId'], 'saveAll');
    expect(byCommandId['runBuild']!['dirtyDocumentIds'], <String>[
      '/workspace/demo/dirty.cc',
    ]);
    expect(byCommandId['formatActiveDocument']!['ready'], isTrue);
    expect(byCommandId['runStaticAnalysis']!['requiredCommandId'], 'saveAll');
    expect(byCommandId['runTests']!['requiredCommandId'], 'saveAll');
  });

  test('agent document context truncates oversized active document text', () {
    final context = AgentSessionContext.fromEditorState(
      document: DocumentState(
        documentId: 'large.styio',
        text: List<String>.filled(50010, 'x').join(),
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
    );

    final documentJson = context.toJson()['document']! as Map<String, Object?>;

    expect((documentJson['text']! as String).length, 50000);
    expect(documentJson['textStart'], 0);
    expect(documentJson['textEnd'], 50000);
    expect(documentJson['textTruncated'], isTrue);
  });

  test(
    'agent document context keeps selected window for oversized active document',
    () {
      final prefix = List<String>.filled(60000, 'a').join();
      final suffix = List<String>.filled(100, 'b').join();
      final context = AgentSessionContext.fromEditorState(
        document: DocumentState(
          documentId: 'large.styio',
          text: '${prefix}needle$suffix',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(60000),
        diagnostics: const <Diagnostic>[],
      );

      final documentJson =
          context.toJson()['document']! as Map<String, Object?>;

      expect((documentJson['text']! as String).length, 50000);
      expect(documentJson['text'], contains('needle'));
      expect(documentJson['textStart'], greaterThan(0));
      expect(documentJson['textEnd'], 60106);
      expect(documentJson['textTruncated'], isTrue);
    },
  );

  test('agent session context serializes selected context channels only', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>['main.styio'],
      activeFilePath: 'main.styio',
    );

    final json = context.toJsonForChannels(const <String>[
      'file',
      'debug',
      'workspace',
      'agent',
      'language',
      'commands',
      'skills',
      'testing',
      'toolchains',
      'ideCapabilities',
    ]);

    expect(json['schemaVersion'], 88);
    expect(json.containsKey('document'), isTrue);
    expect(json.containsKey('debug'), isTrue);
    expect(json.containsKey('workspace'), isTrue);
    expect(json.containsKey('agent'), isTrue);
    expect(json.containsKey('language'), isTrue);
    expect(json.containsKey('commands'), isTrue);
    expect(json.containsKey('skills'), isTrue);
    expect(json.containsKey('testing'), isTrue);
    expect(json.containsKey('toolchains'), isTrue);
    expect(json.containsKey('ideCapabilities'), isTrue);
    expect(json.containsKey('selection'), isFalse);
    expect(json.containsKey('diagnostics'), isFalse);
    expect(json.containsKey('runtime'), isFalse);
  });

  test(
    'agent session context serializes structured patch application result',
    () {
      final recordedAt = DateTime.utc(2026, 5, 19, 2, 3, 4);
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value := 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        lastPatchApplication: AgentPatchApplicationContext(
          patchId: 'patch-1',
          summary: 'Change value.',
          baseRevision: 1,
          documentIds: const <String>['src/main.styio'],
          editCount: 1,
          operationCounts: const <String, int>{'replace': 1},
          applied: true,
          pendingPatchRetained: false,
          message: 'Applied 1 agent patch edit(s).',
          appliedEditCount: 1,
          appliedOperationCounts: const <String, int>{'replace': 1},
          changedDocumentIds: const <String>['src/main.styio'],
          skippedNoOpDocumentIds: const <String>['src/noop.styio'],
          recordedAt: recordedAt,
        ),
      );

      final agentJson = context.toJson()['agent']! as Map<String, Object?>;
      final patchApplication =
          agentJson['lastPatchApplication']! as Map<String, Object?>;
      final recentPatchApplications =
          agentJson['recentPatchApplications']! as List<Object?>;
      final filteredJson = context.toJsonForChannels(const <String>['agent']);
      final filteredAgentJson = filteredJson['agent']! as Map<String, Object?>;
      final validationPlan =
          agentJson['validationPlan']! as Map<String, Object?>;
      final validationResult =
          agentJson['validationResult']! as Map<String, Object?>;
      final validationPipeline =
          agentJson['validationPipeline']! as Map<String, Object?>;
      final validationCommandPlans =
          validationPlan['commandPlans']! as List<Object?>;

      expect(patchApplication['patchId'], 'patch-1');
      expect(patchApplication['summary'], 'Change value.');
      expect(patchApplication['baseRevision'], 1);
      expect(patchApplication['documentIds'], <String>['src/main.styio']);
      expect(patchApplication['editCount'], 1);
      expect(patchApplication['operationCounts'], <String, int>{'replace': 1});
      expect(patchApplication['applied'], isTrue);
      expect(patchApplication['pendingPatchRetained'], isFalse);
      expect(patchApplication['message'], 'Applied 1 agent patch edit(s).');
      expect(patchApplication['appliedEditCount'], 1);
      expect(patchApplication['appliedOperationCounts'], <String, int>{
        'replace': 1,
      });
      expect(patchApplication['changedDocumentIds'], <String>[
        'src/main.styio',
      ]);
      expect(patchApplication['createdDocumentIds'], <String>[]);
      expect(patchApplication['deletedDocumentIds'], <String>[]);
      expect(patchApplication['skippedNoOpDocumentIds'], <String>[
        'src/noop.styio',
      ]);
      expect(patchApplication['recordedAt'], recordedAt.toIso8601String());
      final patchValidationSnapshot =
          patchApplication['validationSnapshot']! as Map<String, Object?>;
      expect(patchValidationSnapshot['planStatus'], 'ready');
      expect(patchValidationSnapshot['resultStatus'], 'notStarted');
      expect(patchValidationSnapshot['pipelineStatus'], 'ready');
      expect(patchValidationSnapshot['nextCommandId'], 'saveAll');
      expect(
        patchValidationSnapshot['missingCommandIds'],
        contains('runTests'),
      );
      expect(recentPatchApplications.length, 1);
      expect(
        (recentPatchApplications.single! as Map<String, Object?>)['patchId'],
        'patch-1',
      );
      expect(
        filteredAgentJson['lastPatchApplication'],
        isA<Map<String, Object?>>(),
      );
      expect(validationPlan['status'], 'ready');
      expect(validationPlan['shouldRun'], isTrue);
      expect(validationResult['status'], 'notStarted');
      expect(validationResult['missingCommandIds'], contains('saveAll'));
      expect(validationResult['missingCommandIds'], contains('runTests'));
      expect(validationPipeline['status'], 'ready');
      expect(validationPipeline['nextCommandId'], 'saveAll');
      expect(validationPipeline['progressNumerator'], 0);
      expect(
        validationPlan['commandHints'],
        containsAll(<String>[
          AppCommandId.refreshLanguageService.name,
          AppCommandId.refreshWorkspaceDiagnostics.name,
          AppCommandId.collectProjectLanguageContext.name,
          AppCommandId.runTests.name,
          AppCommandId.runTestConfiguration.name,
        ]),
      );
      expect(
        validationPlan['registeredCommandIds'],
        containsAll(<String>[
          AppCommandId.saveAll.name,
          AppCommandId.refreshLanguageService.name,
          AppCommandId.refreshWorkspaceDiagnostics.name,
          AppCommandId.collectProjectLanguageContext.name,
          AppCommandId.runTests.name,
          AppCommandId.runTestConfiguration.name,
        ]),
      );
      expect(
        validationPlan['todoItems'],
        isNot(
          contains(
            'TODO: bind validation command hints to real command execution routes.',
          ),
        ),
      );
      final projectLanguagePlan = validationCommandPlans
          .cast<Map<String, Object?>>()
          .singleWhere(
            (commandPlan) =>
                commandPlan['commandId'] ==
                AppCommandId.collectProjectLanguageContext.name,
          );
      expect(projectLanguagePlan['phase'], 'languageEvidence');
      expect(projectLanguagePlan['requiresInput'], isFalse);
      final runConfigurationPlan = validationCommandPlans
          .cast<Map<String, Object?>>()
          .singleWhere(
            (commandPlan) =>
                commandPlan['commandId'] ==
                AppCommandId.runTestConfiguration.name,
          );
      expect(runConfigurationPlan['phase'], 'testing');
      expect(runConfigurationPlan['required'], isFalse);
      expect(runConfigurationPlan['requiresInput'], isTrue);
      expect(
        runConfigurationPlan['inputSource'],
        'testing.configurationSet.selectedConfigurationId',
      );
      expect(filteredJson.containsKey('document'), isFalse);
    },
  );

  test('agent session context summarizes coding validation results', () {
    final patchApplication = AgentPatchApplicationContext(
      patchId: 'patch-validated',
      summary: 'Validated change.',
      documentIds: const <String>['src/main.styio'],
      editCount: 1,
      operationCounts: const <String, int>{'replace': 1},
      applied: true,
      pendingPatchRetained: false,
      message: 'Applied.',
      appliedEditCount: 1,
      changedDocumentIds: const <String>['src/main.styio'],
      recordedAt: DateTime.utc(2026, 5, 19, 3, 4, 5),
    );
    final commandResults = <AgentCommandResultContext>[
      for (final commandId in <String>[
        AppCommandId.saveAll.name,
        AppCommandId.refreshLanguageService.name,
        AppCommandId.refreshWorkspaceDiagnostics.name,
        AppCommandId.collectProjectLanguageContext.name,
        AppCommandId.runTests.name,
      ])
        AgentCommandResultContext(
          commandId: commandId,
          applied: true,
          message: '$commandId completed.',
        ),
    ];
    final context =
        AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: 'src/main.styio',
            text: 'value := 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const <Diagnostic>[],
        ).withAgentCodingState(
          lastPatchApplication: patchApplication,
          recentCommandResults: commandResults,
        );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final lastPatchApplication =
        agentJson['lastPatchApplication']! as Map<String, Object?>;
    final validationResult =
        agentJson['validationResult']! as Map<String, Object?>;
    final validationPipeline =
        agentJson['validationPipeline']! as Map<String, Object?>;
    final patchValidationSnapshot =
        lastPatchApplication['validationSnapshot']! as Map<String, Object?>;

    expect(validationResult['status'], 'passed');
    expect(validationResult['summary'], 'Agent coding validation passed.');
    expect(validationPipeline['status'], 'complete');
    expect(validationPipeline['progressNumerator'], 5);
    expect(validationPipeline['progressDenominator'], 5);
    expect(
      validationResult['completedCommandIds'],
      containsAll(<String>[
        AppCommandId.saveAll.name,
        AppCommandId.refreshLanguageService.name,
        AppCommandId.refreshWorkspaceDiagnostics.name,
        AppCommandId.collectProjectLanguageContext.name,
        AppCommandId.runTests.name,
      ]),
    );
    expect(validationResult['failedCommandIds'], isEmpty);
    expect(validationResult['missingCommandIds'], isEmpty);
    expect(patchValidationSnapshot['resultStatus'], 'passed');
    expect(patchValidationSnapshot['pipelineStatus'], 'complete');
    expect(
      patchValidationSnapshot['completedCommandIds'],
      contains('runTests'),
    );
  });

  test('agent session context reports failed patch validation follow-up', () {
    final context =
        AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: 'src/main.styio',
            text: 'value := 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const <Diagnostic>[],
        ).withAgentCodingState(
          lastPatchApplication: AgentPatchApplicationContext(
            patchId: 'patch-failed',
            summary: 'Failed change.',
            documentIds: const <String>['src/main.styio'],
            editCount: 1,
            applied: false,
            pendingPatchRetained: true,
            message: 'Patch failed.',
            recordedAt: DateTime.utc(2026, 5, 20),
          ),
        );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final validationPlan = agentJson['validationPlan']! as Map<String, Object?>;

    expect(validationPlan['status'], 'blocked');
    expect(validationPlan['shouldRun'], isFalse);
    expect(
      validationPlan['requiredSteps'],
      containsAll(<String>[
        'inspectPatchApplicationFailure',
        'reviseGeneratedPatch',
      ]),
    );
    expect(
      validationPlan['todoItems'],
      contains('Link failed patch application to diagnostics and retry flow.'),
    );
    expect(
      (validationPlan['todoItems']! as List<Object?>).join('\n'),
      isNot(contains('TODO:')),
    );
  });

  test('agent session context serializes current pending patch', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      pendingPatch: const AgentPendingPatchContext(
        patchId: 'patch-pending',
        summary: 'Change value.',
        baseRevision: 1,
        documentIds: <String>['src/main.styio'],
        editCount: 1,
        operationCounts: <String, int>{'replace': 1},
        edits: <AgentPendingPatchEditContext>[
          AgentPendingPatchEditContext(
            documentId: 'src/main.styio',
            operation: 'replace',
            start: 9,
            end: 10,
            replacementTextSample: '2',
            replacementTextLength: 1,
            replacementTextTruncated: false,
          ),
        ],
        editsTruncated: false,
      ),
      recentPatchProposals: const <AgentPendingPatchContext>[
        AgentPendingPatchContext(
          patchId: 'patch-pending',
          summary: 'Change value.',
          baseRevision: 1,
          documentIds: <String>['src/main.styio'],
          editCount: 1,
          operationCounts: <String, int>{'replace': 1},
          edits: <AgentPendingPatchEditContext>[
            AgentPendingPatchEditContext(
              documentId: 'src/main.styio',
              operation: 'replace',
              start: 9,
              end: 10,
              replacementTextSample: '2',
              replacementTextLength: 1,
              replacementTextTruncated: false,
            ),
          ],
          editsTruncated: false,
        ),
      ],
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final pendingPatch = agentJson['pendingPatch']! as Map<String, Object?>;
    final recentPatchProposals =
        agentJson['recentPatchProposals']! as List<Object?>;
    final changeReviewGate =
        agentJson['changeReviewGate']! as Map<String, Object?>;
    final autonomyPolicy = agentJson['autonomyPolicy']! as Map<String, Object?>;
    final validationPlan = agentJson['validationPlan']! as Map<String, Object?>;
    final validationCommandPlans =
        validationPlan['commandPlans']! as List<Object?>;
    final edits = pendingPatch['edits']! as List<Object?>;
    final firstEdit = edits.single! as Map<String, Object?>;

    expect(pendingPatch['patchId'], 'patch-pending');
    expect(pendingPatch['summary'], 'Change value.');
    expect(pendingPatch['baseRevision'], 1);
    expect(pendingPatch['documentIds'], <String>['src/main.styio']);
    expect(pendingPatch['editCount'], 1);
    expect(pendingPatch['operationCounts'], <String, int>{'replace': 1});
    expect(pendingPatch['editsTruncated'], isFalse);
    expect(firstEdit['documentId'], 'src/main.styio');
    expect(firstEdit['operation'], 'replace');
    expect(firstEdit['replacementTextSample'], '2');
    expect(firstEdit['replacementTextLength'], 1);
    expect(firstEdit['replacementTextTruncated'], isFalse);
    expect(
      (recentPatchProposals.single! as Map<String, Object?>)['patchId'],
      'patch-pending',
    );
    expect(
      agentJson['suggestedCommandIds'],
      contains(AppCommandId.collectAgentCodingCheckpoint.name),
    );
    expect(changeReviewGate['status'], 'needsReview');
    expect(changeReviewGate['canApplyPreview'], isTrue);
    expect(changeReviewGate['requiresUserReview'], isTrue);
    expect(
      changeReviewGate['requiredReviewSteps'],
      containsAll(<String>[
        'reviewWorkspaceEditPreview',
        'confirmGeneratedPatchScope',
      ]),
    );
    expect(
      changeReviewGate['reviewSurfaceActionIds'],
      containsAll(<String>[
        'reviewWorkspaceEditPreview',
        'applyPendingPatch',
        'dismissPendingPatch',
        'collectAgentCodingCheckpoint',
      ]),
    );
    expect(autonomyPolicy['mode'], 'reviewBeforeApply');
    expect(autonomyPolicy['canProposePatches'], isTrue);
    expect(autonomyPolicy['canApplyWithoutReview'], isFalse);
    expect(autonomyPolicy['requiresExplicitUserApproval'], isTrue);
    expect(validationPlan['status'], 'waitingForReview');
    expect(validationPlan['shouldRun'], isFalse);
    expect(
      validationPlan['todoItems'],
      contains('Start validation automatically after reviewed apply succeeds.'),
    );
    expect(
      (validationPlan['todoItems']! as List<Object?>).join('\n'),
      isNot(contains('TODO:')),
    );
    expect(
      validationPlan['requiredSteps'],
      containsAll(<String>[
        'completeChangeReviewGate',
        'applyReviewedWorkspaceEdit',
      ]),
    );
    expect(
      validationPlan['registeredCommandIds'],
      contains(AppCommandId.collectAgentCodingCheckpoint.name),
    );
    expect(
      (validationCommandPlans.single! as Map<String, Object?>)['commandId'],
      AppCommandId.collectAgentCodingCheckpoint.name,
    );
  });

  test('agent session context serializes pending IDE command suggestions', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      pendingIdeCommands: const <AgentPendingIdeCommandContext>[
        AgentPendingIdeCommandContext(
          commandId: 'stageSourceControl',
          reason: 'Stage the changed file.',
          prerequisiteForCommandId: 'planSourceControlCommitDraft',
          text: 'Stage changed files.',
        ),
      ],
      recentIdeCommandSuggestions: const <AgentPendingIdeCommandContext>[
        AgentPendingIdeCommandContext(
          commandId: 'runBuild',
          reason: 'Use the registered build command.',
          prerequisiteForCommandId: 'saveAll',
          text: 'Run the build.',
        ),
      ],
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final pendingIdeCommands =
        agentJson['pendingIdeCommands']! as List<Object?>;
    final recentIdeCommandSuggestions =
        agentJson['recentIdeCommandSuggestions']! as List<Object?>;
    final command = pendingIdeCommands.single! as Map<String, Object?>;
    final recentCommand =
        recentIdeCommandSuggestions.single! as Map<String, Object?>;

    expect(agentJson['suggestedCommandIds'], <String>['stageSourceControl']);
    expect(command['commandId'], 'stageSourceControl');
    expect(command['registered'], isTrue);
    expect(command['requiresInput'], isTrue);
    expect(command['inputMissing'], isTrue);
    expect(command['inputLabel'], 'Changed file path(s)');
    expect(command['inputContract'], contains('workspace-relative'));
    expect(command['inputExamples'], contains('src/main.styio'));
    expect(command['reason'], 'Stage the changed file.');
    expect(command['prerequisiteForCommandId'], 'planSourceControlCommitDraft');
    expect(command['text'], 'Stage changed files.');
    expect(recentCommand['commandId'], 'runBuild');
  });

  test('agent session context serializes recent coding plans', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      recentCodingPlans: const <AgentCodingPlanContext>[
        AgentCodingPlanContext(
          summary: 'Update active document safely.',
          steps: <String>['Inspect IDE facts.', 'Prepare patch.'],
          acceptanceCriteria: <String>['Patch preview is shown.'],
          risks: <String>['Dirty inactive files.'],
          text: 'Plan before patch.',
        ),
      ],
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final recentCodingPlans = agentJson['recentCodingPlans']! as List<Object?>;
    final plan = recentCodingPlans.single! as Map<String, Object?>;

    expect(plan['summary'], 'Update active document safely.');
    expect(plan['steps'], <String>['Inspect IDE facts.', 'Prepare patch.']);
    expect(plan['acceptanceCriteria'], <String>['Patch preview is shown.']);
    expect(plan['risks'], <String>['Dirty inactive files.']);
    expect(plan['text'], 'Plan before patch.');
  });

  test('agent session context serializes semantic panel view models', () {
    final semanticPanel = SemanticSnapshotPanelViewModel.fromState(
      SemanticSnapshotPanelEventState.empty(
        SemanticSnapshotPanelEventTarget.problems,
      ).record(
        SemanticSnapshotPanelEvent(
          target: SemanticSnapshotPanelEventTarget.problems,
          kind: SemanticSnapshotTelemetryEventKind.codeActionApply,
          documentId: 'src/main.styio',
          message: 'Applied quick fix.',
          payload: <String, Object?>{
            'status': 'applied',
            'label': 'Insert assignment',
          },
          timestamp: DateTime.utc(2026, 5, 20, 7),
        ),
      ),
    );
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value\n',
        revision: 1,
      ),
      selection: const SelectionState(baseOffset: 0, extentOffset: 0),
      diagnostics: const <Diagnostic>[],
      semanticPanelViewModels: <SemanticSnapshotPanelViewModel>[semanticPanel],
    );

    final languageJson = context.toJson()['language']! as Map<String, Object?>;
    final panels = languageJson['semanticPanelViewModels']! as List<Object?>;
    final panel = panels.single! as Map<String, Object?>;
    final items = panel['items']! as List<Object?>;

    expect(context.schemaVersion, 88);
    expect(languageJson['semanticPanelViewModelCount'], 1);
    expect(languageJson['semanticPanelViewModelsTruncated'], isFalse);
    expect(panel['target'], 'problems');
    expect(panel['codeActionCount'], 1);
    expect((items.single! as Map<String, Object?>)['severity'], 'success');
    expect(
      (items.single! as Map<String, Object?>)['actionLabel'],
      'Insert assignment',
    );
  });

  test('agent session context serializes semantic confidence matrix', () {
    const document = DocumentState(
      documentId: 'fixture://agent-semantic-confidence',
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);
    final matrix = SemanticSnapshotFeatureMatrix.fromSnapshot(
      snapshot: snapshot,
      source: SemanticSnapshotProviderSource.localBuilderFallback,
    );
    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      semanticFeatureMatrix: matrix,
    );

    final languageJson = context.toJson()['language']! as Map<String, Object?>;
    final semanticMatrix =
        languageJson['semanticFeatureMatrix']! as Map<String, Object?>;

    expect(semanticMatrix['source'], 'local-builder-fallback');
    expect(semanticMatrix['preferredSource'], 'local-fallback');
    expect(semanticMatrix['fallbackActive'], isTrue);
    expect(semanticMatrix['conflictPolicy'], contains('Prefer StyioService'));
    expect(semanticMatrix['localFallbackFeatureCount'], greaterThan(0));
    expect(semanticMatrix['serviceBackedFeatureCount'], 0);
    expect(semanticMatrix['unavailableFeatures'], contains('rename-safety'));
  });

  test('agent session context serializes recent diagnostic summaries', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      recentDiagnosticSummaries: const <AgentDiagnosticSummaryContext>[
        AgentDiagnosticSummaryContext(
          title: 'Build failed.',
          summary: 'Parser target failed with one error.',
          severity: 'error',
          diagnosticCount: 1,
          affectedDocuments: <String>['src/parser.cc'],
          suggestedCommandIds: <String>['runBuild'],
          text: 'Diagnostics summarized.',
        ),
      ],
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final recentDiagnosticSummaries =
        agentJson['recentDiagnosticSummaries']! as List<Object?>;
    final summary = recentDiagnosticSummaries.single! as Map<String, Object?>;

    expect(summary['title'], 'Build failed.');
    expect(summary['summary'], 'Parser target failed with one error.');
    expect(summary['severity'], 'error');
    expect(summary['diagnosticCount'], 1);
    expect(summary['affectedDocuments'], <String>['src/parser.cc']);
    expect(summary['suggestedCommandIds'], <String>['runBuild']);
    expect(summary['text'], 'Diagnostics summarized.');
  });

  test('agent session context serializes last provider failure', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      lastProviderFailure: const AgentProviderFailureContext(
        kind: 'timeout',
        message: 'provider timed out',
        operation: 'agent.provider.postJson',
        recoveryHint: 'Retry the provider request.',
      ),
      providerSelectionPlan: const AgentProviderSelectionPlan(
        status: AgentProviderSelectionStatus.ready,
        route: AgentProviderRoute.webHosted,
        protocol: 'openai-compatible',
        requiresCredential: true,
        credentialReadiness: AgentProviderCredentialReadiness.available,
        executionStatus: AgentProviderExecutionResolutionStatus.fallbackReady,
        selectedEndpointIndex: 1,
        selectedProvider: AgentProviderRegistrationManifest(
          providerId: 'cloud',
          displayName: 'Cloud Provider',
          kind: AgentProviderKind.cloudOpenAICompatible,
          priority: 10,
          supportsCodePatch: true,
          supportedRoutes: <String>['web-hosted'],
          supportedProtocols: <String>['openai-compatible'],
          capabilities: <String>['plan', 'code_patch'],
        ),
        candidates: <AgentProviderRegistrationManifest>[
          AgentProviderRegistrationManifest(
            providerId: 'cloud',
            displayName: 'Cloud Provider',
            kind: AgentProviderKind.cloudOpenAICompatible,
            priority: 10,
            supportsCodePatch: true,
            supportedRoutes: <String>['web-hosted'],
            supportedProtocols: <String>['openai-compatible'],
            capabilities: <String>['plan', 'code_patch'],
          ),
        ],
        message: 'Agent provider registration is ready.',
      ),
      providerExecutionResolution: const AgentProviderExecutionResolution(
        profileId: 'cloud',
        status: AgentProviderExecutionResolutionStatus.fallbackReady,
        selectedEndpointIndex: 1,
        endpoints: <AgentProviderEndpointReadiness>[
          AgentProviderEndpointReadiness(
            endpointIndex: 0,
            fallback: false,
            endpoint: AgentProviderEndpoint(
              route: AgentProviderRoute.webHosted,
              baseUrl: 'https://primary.example.test/v1',
              model: 'gpt-primary',
              requiresCredential: true,
            ),
            plan: AgentProviderExecutionPlan(
              routeKind: AgentProviderExecutionRouteKind.cloud,
              providerKind: AgentProviderKind.cloudOpenAICompatible,
              route: AgentProviderRoute.webHosted,
              endpointBaseUrl: 'https://primary.example.test/v1',
            ),
            credentialReadiness: AgentProviderCredentialReadiness.unavailable,
          ),
          AgentProviderEndpointReadiness(
            endpointIndex: 1,
            fallback: true,
            endpoint: AgentProviderEndpoint(
              route: AgentProviderRoute.webHosted,
              baseUrl: 'https://fallback.example.test/v1',
              model: 'gpt-fallback',
            ),
            plan: AgentProviderExecutionPlan(
              routeKind: AgentProviderExecutionRouteKind.cloud,
              providerKind: AgentProviderKind.cloudOpenAICompatible,
              route: AgentProviderRoute.webHosted,
              endpointBaseUrl: 'https://fallback.example.test/v1',
            ),
            credentialReadiness: AgentProviderCredentialReadiness.available,
          ),
        ],
      ),
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final failure = agentJson['lastProviderFailure']! as Map<String, Object?>;
    final providerExecution =
        agentJson['providerExecution']! as Map<String, Object?>;
    final providerSelection =
        agentJson['providerSelection']! as Map<String, Object?>;
    final endpoints = providerExecution['endpoints']! as List<Object?>;
    final codingReadiness =
        context.toJson()['codingReadiness']! as Map<String, Object?>;

    expect(agentJson['suggestedCommandIds'], <String>[
      'retryAgentProvider',
      'replayAgentPrompt',
    ]);
    expect(failure['kind'], 'timeout');
    expect(failure['message'], 'provider timed out');
    expect(failure['operation'], 'agent.provider.postJson');
    expect(failure['recoveryHint'], 'Retry the provider request.');
    expect(providerExecution['status'], 'fallback_ready');
    expect(providerSelection['status'], 'ready');
    expect(providerSelection['requiresCredential'], isTrue);
    expect(providerSelection['executable'], isTrue);
    expect(providerSelection['credentialReadiness'], 'available');
    expect(providerSelection['executionStatus'], 'fallback_ready');
    expect(providerSelection['selectedEndpointIndex'], 1);
    expect(providerSelection['candidateCount'], 1);
    expect(
      (providerSelection['selectedProvider']!
          as Map<String, Object?>)['providerId'],
      'cloud',
    );
    expect(providerExecution['selectedEndpointIndex'], 1);
    expect(providerExecution['missingCredentialEndpointCount'], 1);
    expect(
      (endpoints.first! as Map<String, Object?>)['requiresCredential'],
      isTrue,
    );
    expect(
      (endpoints.first! as Map<String, Object?>)['credentialReadiness'],
      'unavailable',
    );
    expect(
      codingReadiness['issueCodes'],
      contains('agent.provider.route.degraded'),
    );
    expect(
      (codingReadiness['todoItems']! as List<Object?>).join('\n'),
      isNot(contains('surface provider fallback health')),
    );
  });

  test(
    'agent session context serializes bounded patch application history',
    () {
      final patchApplications = List<AgentPatchApplicationContext>.generate(
        14,
        (index) => AgentPatchApplicationContext(
          patchId: 'patch-$index',
          applied: index.isEven,
          pendingPatchRetained: index.isOdd,
          message: 'Patch $index completed.',
          editCount: index + 1,
        ),
      );
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value := 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        lastPatchApplication: patchApplications.first,
        recentPatchApplications: patchApplications,
      );

      final agentJson = context.toJson()['agent']! as Map<String, Object?>;
      final lastPatchApplication =
          agentJson['lastPatchApplication']! as Map<String, Object?>;
      final recentPatchApplications =
          agentJson['recentPatchApplications']! as List<Object?>;

      expect(lastPatchApplication['patchId'], 'patch-0');
      expect(recentPatchApplications.length, 12);
      expect(
        (recentPatchApplications.first! as Map<String, Object?>)['patchId'],
        'patch-0',
      );
      expect(
        (recentPatchApplications.last! as Map<String, Object?>)['patchId'],
        'patch-11',
      );
    },
  );

  test('agent session context truncates oversized diagnostics list', () {
    final diagnostics = <Diagnostic>[
      for (var index = 0; index < 105; index += 1)
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'warning-$index',
          message: 'diagnostic $index',
          range: SourceRange(start: index, end: index + 1),
        ),
    ];
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: diagnostics,
    );

    final json = context.toJson();
    final diagnosticsJson = json['diagnostics']! as List<Object?>;

    expect(json['diagnosticCount'], 105);
    expect(json['diagnosticsTruncated'], isTrue);
    expect(diagnosticsJson.length, 100);
    expect(
      (diagnosticsJson.last! as Map<String, Object?>)['code'],
      'warning-99',
    );
  });

  test('agent runtime context keeps stdout and stderr tails', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      lastExecutionSession: ExecutionSession(
        sessionId: 'run-tail',
        kind: 'run',
        status: ExecutionSessionStatus.succeeded,
        statusMessage: 'done',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: <ExecutionLogEvent>[
          for (var index = 0; index < 55; index += 1)
            ExecutionLogEvent(message: 'out-$index'),
        ],
        stderrEvents: <ExecutionLogEvent>[
          for (var index = 0; index < 55; index += 1)
            ExecutionLogEvent(message: 'err-$index'),
        ],
      ),
    );

    final runtimeJson = context.toJson()['runtime']! as Map<String, Object?>;

    expect((runtimeJson['stdoutTail']! as List<Object?>).length, 50);
    expect((runtimeJson['stderrTail']! as List<Object?>).length, 50);
    expect(runtimeJson['stdoutEventCount'], 55);
    expect(runtimeJson['stdoutTruncated'], isTrue);
    expect(runtimeJson['stderrEventCount'], 55);
    expect(runtimeJson['stderrTruncated'], isTrue);
    expect(runtimeJson['stdoutTail'], contains('out-54'));
    expect(runtimeJson['stdoutTail'], isNot(contains('out-0')));
    expect(runtimeJson['stderrTail'], contains('err-54'));
    expect(runtimeJson['stderrTail'], isNot(contains('err-0')));
  });

  test('agent runtime context caps unique runtime event kinds', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      lastExecutionSession: const ExecutionSession(
        sessionId: 'run-events',
        kind: 'run',
        status: ExecutionSessionStatus.succeeded,
        statusMessage: 'done',
        diagnostics: <Diagnostic>[],
        stdoutEvents: <ExecutionLogEvent>[],
        stderrEvents: <ExecutionLogEvent>[],
      ),
      lastRuntimeEvents: <RuntimeEventEnvelope>[
        for (var index = 0; index < 55; index += 1)
          RuntimeEventEnvelope(
            schemaVersion: 1,
            sessionId: 'run-events',
            sequence: index,
            timestamp: DateTime.utc(2026, 5, 18, 0, 0, index),
            eventKind: 'runtime.kind.$index',
            origin: 'test',
            payload: const <String, Object?>{},
          ),
      ],
    );

    final runtimeJson = context.toJson()['runtime']! as Map<String, Object?>;
    final eventKinds = runtimeJson['eventKinds']! as List<Object?>;

    expect(eventKinds.length, 50);
    expect(runtimeJson['eventKindCount'], 55);
    expect(runtimeJson['eventKindsTruncated'], isTrue);
    expect(eventKinds.first, 'runtime.kind.0');
    expect(eventKinds.last, 'runtime.kind.49');
    expect(eventKinds, isNot(contains('runtime.kind.54')));
  });

  test(
    'agent workspace context keeps active file when file list is truncated',
    () {
      final files = <String>[
        for (var index = 0; index < 250; index += 1) 'file_$index.styio',
      ];
      const activeFile = 'deep/active.styio';
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: activeFile,
          text: 'value = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: files,
        activeFilePath: activeFile,
      );

      final workspaceJson =
          context.toJson()['workspace']! as Map<String, Object?>;
      final visibleFiles = workspaceJson['files']! as List<Object?>;

      expect(workspaceJson['fileCount'], 250);
      expect(workspaceJson['filesTruncated'], isTrue);
      expect(visibleFiles.length, 200);
      expect(visibleFiles, contains(activeFile));
    },
  );

  test('agent workspace context deduplicates workspace files', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>['main.styio', 'main.styio', 'other.styio'],
      openDocumentIds: const <String>[
        'main.styio',
        'main.styio',
        'other.styio',
      ],
      dirtyDocumentIds: const <String>['other.styio', 'other.styio'],
      activeFilePath: 'main.styio',
    );

    final workspaceJson =
        context.toJson()['workspace']! as Map<String, Object?>;

    expect(workspaceJson['fileCount'], 2);
    expect(workspaceJson['files'], <String>['main.styio', 'other.styio']);
    expect(workspaceJson['openDocumentIds'], <String>[
      'main.styio',
      'other.styio',
    ]);
    expect(workspaceJson['dirtyDocumentIds'], <String>['other.styio']);
  });

  test(
    'agent workspace context caps document samples and keeps active first',
    () {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'active.styio',
          text: 'active = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: <String>[
          'active.styio',
          for (var index = 0; index < 12; index += 1) 'file_$index.styio',
        ],
        workspaceDocuments: <DocumentState>[
          const DocumentState(
            documentId: 'active.styio',
            text: 'duplicate active should be skipped\n',
            revision: 99,
          ),
          for (var index = 0; index < 12; index += 1)
            DocumentState(
              documentId: 'file_$index.styio',
              text: 'value_$index = $index\n',
              revision: index,
            ),
        ],
        activeFilePath: 'active.styio',
      );

      final workspaceJson =
          context.toJson()['workspace']! as Map<String, Object?>;
      final samples = workspaceJson['documentSamples']! as List<Object?>;

      expect(workspaceJson['documentSampleCount'], 13);
      expect(workspaceJson['documentSamplesTruncated'], isTrue);
      expect(samples.length, 10);
      expect(
        (samples.first! as Map<String, Object?>)['documentId'],
        'active.styio',
      );
      expect((samples.first! as Map<String, Object?>)['text'], 'active = 1\n');
      expect((samples.first! as Map<String, Object?>)['active'], isTrue);
      expect(
        samples.map(
          (sample) => (sample! as Map<String, Object?>)['documentId'],
        ),
        isNot(contains('file_11.styio')),
      );
    },
  );

  test('agent workspace context detects C++ build facts from file list', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.cc',
        text: 'int main() { return 0; }\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>[
        'CMakeLists.txt',
        'CMakePresets.json',
        'CMakeUserPresets.json',
        'build/compile_commands.json',
        'build/build.ninja',
        'build/CTestTestfile.cmake',
        '.clangd',
        '.clang-format',
        '.clang-tidy',
        'src/main.cc',
      ],
      activeFilePath: 'src/main.cc',
    );

    final workspaceJson =
        context.toJson()['workspace']! as Map<String, Object?>;
    final buildFacts = workspaceJson['buildFacts']! as Map<String, Object?>;
    final skillsJson = context.toJson()['skills']! as Map<String, Object?>;

    expect(buildFacts['hasCompilationDatabase'], isTrue);
    expect(buildFacts['compilationDatabasePaths'], <String>[
      'build/compile_commands.json',
    ]);
    expect(buildFacts['hasCMakeLists'], isTrue);
    expect(buildFacts['cmakeListsPaths'], <String>['CMakeLists.txt']);
    expect(buildFacts['hasCMakePresets'], isTrue);
    expect(buildFacts['cmakePresetPaths'], <String>['CMakePresets.json']);
    expect(buildFacts['hasCMakeUserPresets'], isTrue);
    expect(buildFacts['cmakeUserPresetPaths'], <String>[
      'CMakeUserPresets.json',
    ]);
    expect(buildFacts['hasNinjaBuild'], isTrue);
    expect(buildFacts['ninjaBuildPaths'], <String>['build/build.ninja']);
    expect(buildFacts['hasClangdConfig'], isTrue);
    expect(buildFacts['clangdConfigPaths'], <String>['.clangd']);
    expect(buildFacts['hasClangFormatConfig'], isTrue);
    expect(buildFacts['clangFormatConfigPaths'], <String>['.clang-format']);
    expect(buildFacts['hasClangTidyConfig'], isTrue);
    expect(buildFacts['clangTidyConfigPaths'], <String>['.clang-tidy']);
    expect(buildFacts['hasCTestConfig'], isTrue);
    expect(buildFacts['ctestConfigPaths'], <String>[
      'build/CTestTestfile.cmake',
    ]);
    expect(buildFacts['buildSystemHints'], <String>[
      'compilation-database',
      'cmake',
      'cmake-presets',
      'cmake-user-presets',
      'ninja',
      'clangd',
    ]);
    expect(buildFacts['toolingHints'], <String>[
      'compilation-database',
      'cmake',
      'cmake-presets',
      'cmake-user-presets',
      'ninja',
      'clangd',
      'clang-format',
      'clang-tidy',
      'ctest',
    ]);
    expect(buildFacts['pathsTruncated'], isFalse);
    expect(
      skillsJson['activeSkillIds'],
      contains('cpp-clang-toolchain-defaults'),
    );
    expect(skillsJson['activeSkillIds'], contains('cpp-clang-version-handoff'));
    expect(skillsJson['activeSkillIds'], contains('cpp-compilation-database'));
    expect(skillsJson['activeSkillIds'], contains('cpp-clang-format-tidy'));
    expect(skillsJson['activeSkillIds'], contains('cpp-cmake-build-graph'));
    expect(skillsJson['activeSkillIds'], contains('cpp-clangd-indexing'));
    expect(skillsJson['activeSkillIds'], contains('cpp-test-debug-loop'));
    expect(
      skillsJson['activeSkillIds'],
      contains('reference-grounded-ide-development'),
    );
    expect(skillsJson['activationReasons'], isA<Map<String, Object?>>());
  });

  test(
    'agent workspace context activates Styio-first skills for Styio documents',
    () {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'src/main.styio',
          text: 'state value = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: const <String>['src/main.styio'],
        activeFilePath: 'src/main.styio',
      );

      final skillsJson = context.toJson()['skills']! as Map<String, Object?>;
      final activeSkillIds = skillsJson['activeSkillIds']! as List<Object?>;
      final activationReasons =
          skillsJson['activationReasons']! as Map<String, Object?>;

      expect(activeSkillIds.first, 'styio-language-service-truth');
      expect(activeSkillIds, contains('styio-agent-command-loop'));
      expect(activeSkillIds, contains('styio-ide-feature-loop'));
      expect(activeSkillIds, contains('styio-fixture-confidence-matrix'));
      expect(activeSkillIds, isNot(contains('styio-cpp-compiler-project')));
      expect(activeSkillIds, isNot(contains('cpp-clang-toolchain-defaults')));
      expect(
        activationReasons['styio-language-service-truth'],
        contains(
          'Styio source files require StyioService-backed syntax and semantic facts instead of Vityo-side grammar guesses.',
        ),
      );
    },
  );

  test(
    'agent workspace context activates Styio compiler skill with native evidence',
    () {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'src/main.styio',
          text: 'state value = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: const <String>[
          'src/main.styio',
          'compiler/CMakeLists.txt',
          'compiler/src/parser.cpp',
        ],
        activeFilePath: 'src/main.styio',
      );

      final skillsJson = context.toJson()['skills']! as Map<String, Object?>;
      final activeSkillIds = skillsJson['activeSkillIds']! as List<Object?>;
      final activationReasons =
          skillsJson['activationReasons']! as Map<String, Object?>;

      expect(activeSkillIds, contains('styio-language-service-truth'));
      expect(activeSkillIds, contains('cpp-clang-toolchain-defaults'));
      expect(activeSkillIds, contains('styio-cpp-compiler-project'));
      expect(
        activationReasons['styio-cpp-compiler-project'],
        contains(
          'Styio source files appear together with native build evidence, so compiler-project workflow may be relevant.',
        ),
      );
    },
  );

  test('agent workspace context activates Styio skills from service status', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'README.md',
        text: '# Demo\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>['README.md'],
      activeFilePath: 'README.md',
      languageServiceStatus: _agentLanguageServiceStatus,
    );

    final skillsJson = context.toJson()['skills']! as Map<String, Object?>;
    final activeSkillIds = skillsJson['activeSkillIds']! as List<Object?>;
    final activationReasons =
        skillsJson['activationReasons']! as Map<String, Object?>;

    expect(activeSkillIds, contains('styio-language-service-truth'));
    expect(activeSkillIds, contains('styio-agent-command-loop'));
    expect(activeSkillIds, contains('styio-ide-feature-loop'));
    expect(activeSkillIds, isNot(contains('styio-fixture-confidence-matrix')));
    expect(activeSkillIds, isNot(contains('cpp-clang-toolchain-defaults')));
    expect(
      activationReasons['styio-language-service-truth'],
      contains(
        'StyioService status is available, so Agent coding should prefer real language facts over generic editing guesses.',
      ),
    );
    expect(
      activationReasons['styio-language-service-truth'],
      contains(
        'StyioService capability health is degraded with 1 missing and 1 blocked capability/capabilities.',
      ),
    );
    expect(
      activationReasons['styio-language-service-truth'],
      contains(
        'Styio language provider readiness is degraded with 2 missing IDE language capability/capabilities.',
      ),
    );
    expect(
      activationReasons['styio-language-service-truth'],
      contains(
        'Styio semantic facts are not ready, so avoid symbol-sensitive edits unless resolvedElement, resolvedReference, or semantic panel facts are present.',
      ),
    );
  });

  test(
    'agent workspace context activates native skills for Ninja build files',
    () {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'README.md',
          text: '# Demo\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: const <String>['build/build.ninja'],
        activeFilePath: 'README.md',
      );

      final skillsJson = context.toJson()['skills']! as Map<String, Object?>;
      final activeSkillIds = skillsJson['activeSkillIds']! as List<Object?>;
      final activationReasons =
          skillsJson['activationReasons']! as Map<String, Object?>;

      expect(activeSkillIds, contains('cpp-clang-toolchain-defaults'));
      expect(activeSkillIds, contains('cpp-clang-version-handoff'));
      expect(activeSkillIds, contains('cpp-cmake-build-graph'));
      expect(
        activationReasons['cpp-cmake-build-graph'],
        contains(
          'Ninja build files are present and configured native build targets should guide build edits.',
        ),
      );
    },
  );

  test(
    'agent workspace context activates clang tooling skill for underscore clang-format',
    () {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'README.md',
          text: '# Demo\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: const <String>['_clang-format'],
        activeFilePath: 'README.md',
      );

      final skillsJson = context.toJson()['skills']! as Map<String, Object?>;
      final activeSkillIds = skillsJson['activeSkillIds']! as List<Object?>;
      final activationReasons =
          skillsJson['activationReasons']! as Map<String, Object?>;

      expect(activeSkillIds, contains('cpp-clang-format-tidy'));
      expect(
        activationReasons['cpp-clang-format-tidy'],
        contains(
          'A clang-format configuration file is present and should guide formatting commands.',
        ),
      );
    },
  );

  test(
    'agent workspace context activates native skills for C++ module files',
    () {
      final context = AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'README.md',
          text: '# Demo\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const <Diagnostic>[],
        workspaceFiles: const <String>['src/parser.cppm', 'src/runtime.mpp'],
        activeFilePath: 'README.md',
      );

      final skillsJson = context.toJson()['skills']! as Map<String, Object?>;
      final activeSkillIds = skillsJson['activeSkillIds']! as List<Object?>;

      expect(activeSkillIds, contains('cpp-clang-toolchain-defaults'));
      expect(activeSkillIds, contains('cpp-clang-version-handoff'));
      expect(activeSkillIds, contains('cpp-project-orientation'));
      expect(activeSkillIds, contains('cpp-safe-editing'));
    },
  );

  test('agent workspace context serializes latest workspace search result', () {
    final search = AgentWorkspaceSearchResultContext.fromDocuments(
      query: 'needle',
      documents: const <DocumentState>[
        DocumentState(
          documentId: 'src/main.styio',
          text: 'needle := 1\nother\nneedle -> @stdout\n',
          revision: 1,
        ),
      ],
    );
    const symbolSearch = WorkspaceSymbolSearchResult(
      matches: <WorkspaceSymbolMatch>[
        WorkspaceSymbolMatch(
          documentId: 'src/main.styio',
          name: 'needle',
          kind: ResolvedElementKind.variable,
          nameRange: SourceRange(start: 0, end: 6),
          declarationRange: SourceRange(start: 0, end: 11),
          lineNumber: 1,
          lineText: 'needle := 1',
          score: 1000,
          detail: 'Styio binding',
        ),
      ],
    );
    final symbolContext =
        AgentWorkspaceSymbolSearchResultContext.fromWorkspaceResult(
          query: 'needle',
          scannedDocumentCount: 1,
          result: symbolSearch,
        );
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'needle := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      workspaceFiles: const <String>['src/main.styio'],
      lastWorkspaceSearch: search,
      lastWorkspaceSymbolSearch: symbolContext,
      activeFilePath: 'src/main.styio',
    );

    final workspaceJson =
        context.toJson()['workspace']! as Map<String, Object?>;
    final lastSearch = workspaceJson['lastSearch']! as Map<String, Object?>;
    final lastSymbolSearch =
        workspaceJson['lastSymbolSearch']! as Map<String, Object?>;
    final matches = lastSearch['matches']! as List<Object?>;
    final symbolMatches = lastSymbolSearch['matches']! as List<Object?>;

    expect(lastSearch['query'], 'needle');
    expect(lastSearch['scannedDocumentCount'], 1);
    expect(lastSearch['matchCount'], 2);
    expect(lastSearch['matchesTruncated'], isFalse);
    expect(
      (matches.first! as Map<String, Object?>)['documentId'],
      'src/main.styio',
    );
    expect((matches.first! as Map<String, Object?>)['lineNumber'], 1);
    expect((matches.last! as Map<String, Object?>)['lineNumber'], 3);
    expect(lastSymbolSearch['query'], 'needle');
    expect(lastSymbolSearch['scannedDocumentCount'], 1);
    expect(lastSymbolSearch['matchCount'], 1);
    expect(lastSymbolSearch['matchesTruncated'], isFalse);
    expect(
      (symbolMatches.single! as Map<String, Object?>)['documentId'],
      'src/main.styio',
    );
    expect((symbolMatches.single! as Map<String, Object?>)['name'], 'needle');
    expect((symbolMatches.single! as Map<String, Object?>)['kind'], 'variable');
    expect((symbolMatches.single! as Map<String, Object?>)['lineNumber'], 1);
    expect(
      (symbolMatches.single! as Map<String, Object?>)['snapshotConfidence'],
      'service-backed',
    );
    expect(
      (symbolMatches.single! as Map<String, Object?>)['detail'],
      'Styio binding',
    );
  });

  test('agent command context serializes latest IDE command result', () {
    final completedAt = DateTime.utc(2026, 5, 19, 1, 2, 3);
    final commandResult = AgentCommandResultContext(
      commandId: 'searchWorkspace',
      input: 'value',
      applied: true,
      message: 'Agent command searchWorkspace completed for value.',
      metadata: <String, Object?>{
        'buildResult': <String, Object?>{
          'status': 'failed',
          'exitCode': 1,
          'startedAt': completedAt,
          'targets': <Object?>['parser', Object()],
          'unsupported': Object(),
        },
        'backendRouteSelection': <String, Object?>{
          'routeKind': 'blocked',
          'adapterKind': 'none',
          'allowed': false,
          'previewOnly': false,
          'blockedReason': 'no-backend-route',
          'unsupported': Object(),
        },
        'unsupported': Object(),
      },
      completedAt: completedAt,
    );
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      lastCommandResult: commandResult,
    );

    final commandsJson = context.toJson()['commands']! as Map<String, Object?>;
    final lastResult = commandsJson['lastResult']! as Map<String, Object?>;
    final recentResults = commandsJson['recentResults']! as List<Object?>;

    expect(lastResult['commandId'], 'searchWorkspace');
    expect(lastResult['input'], 'value');
    expect(lastResult['applied'], isTrue);
    expect(lastResult['message'], contains('completed'));
    expect(lastResult['completedAt'], completedAt.toIso8601String());
    final metadata = lastResult['metadata']! as Map<String, Object?>;
    final buildResult = metadata['buildResult']! as Map<String, Object?>;
    expect(buildResult['status'], 'failed');
    expect(buildResult['exitCode'], 1);
    expect(buildResult['startedAt'], completedAt.toIso8601String());
    expect(buildResult['targets'], <Object?>['parser']);
    expect(buildResult.containsKey('unsupported'), isFalse);
    final backendRouteSelection =
        metadata['backendRouteSelection']! as Map<String, Object?>;
    expect(backendRouteSelection['routeKind'], 'blocked');
    expect(backendRouteSelection['adapterKind'], 'none');
    expect(backendRouteSelection['allowed'], isFalse);
    expect(backendRouteSelection['previewOnly'], isFalse);
    expect(backendRouteSelection['blockedReason'], 'no-backend-route');
    expect(backendRouteSelection.containsKey('unsupported'), isFalse);
    expect(metadata.containsKey('unsupported'), isFalse);
    expect(recentResults.length, 1);
    expect(
      (recentResults.single! as Map<String, Object?>)['commandId'],
      'searchWorkspace',
    );
    expect(
      (recentResults.single! as Map<String, Object?>)['completedAt'],
      completedAt.toIso8601String(),
    );
  });

  test('agent command context serializes bounded command result history', () {
    final commandResults = List<AgentCommandResultContext>.generate(
      14,
      (index) => AgentCommandResultContext(
        commandId: 'command$index',
        applied: index.isEven,
        message: 'Command $index completed.',
      ),
    );
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      lastCommandResult: commandResults.first,
      recentCommandResults: commandResults,
    );

    final commandsJson = context.toJson()['commands']! as Map<String, Object?>;
    final recentResults = commandsJson['recentResults']! as List<Object?>;

    expect(recentResults.length, 12);
    expect(
      (recentResults.first! as Map<String, Object?>)['commandId'],
      'command0',
    );
    expect(
      (recentResults.last! as Map<String, Object?>)['commandId'],
      'command11',
    );
  });

  test('agent context serializes stable workspace edit preview and result', () {
    const document = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 1,
    );
    final preview = WorkspaceEditPlan.singleDocument(
      id: 'workspace-fix',
      summary: 'Replace value initializer.',
      source: WorkspaceEditSource.codeAction,
      documentId: document.documentId,
      edits: const <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: 9, end: 10), newText: '2'),
      ],
    ).preview(const <DocumentState>[document]);
    final confirmationPlan = WorkspaceEditConfirmationPlan.fromPreview(preview);
    final applyResult = WorkspaceEditApplyResultViewModel.fromTelemetry(
      confirmationPlan: confirmationPlan,
      telemetry: WorkspaceEditReviewResultTelemetry.fromApplicationResult(
        confirmationPlan: confirmationPlan,
        result: const WorkspaceEditApplicationResult(
          applied: true,
          message: 'Applied workspace fix.',
          appliedEditCount: 1,
          appliedDocumentIds: <String>['src/main.styio'],
        ),
        recordedAt: DateTime.utc(2026, 5, 21, 1, 2, 3),
      ),
      diffWindow: preview.diffWindow(documentLimit: 3, fileOperationLimit: 3),
    );
    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: const SelectionState.collapsed(0),
      diagnostics: const <Diagnostic>[],
      lastWorkspaceEditPreview: preview,
      lastWorkspaceEditApplyResult: applyResult,
    );

    final agentJson = context.toJson()['agent']! as Map<String, Object?>;
    final workspaceEdit = agentJson['workspaceEdit']! as Map<String, Object?>;
    final previewJson = workspaceEdit['preview']! as Map<String, Object?>;
    final confirmationJson =
        previewJson['confirmationPlan']! as Map<String, Object?>;
    final diffWindow = previewJson['diffWindow']! as Map<String, Object?>;
    final lastApplyResult =
        workspaceEdit['lastApplyResult']! as Map<String, Object?>;

    expect(workspaceEdit['hasPreview'], isTrue);
    expect(workspaceEdit['hasApplyResult'], isTrue);
    expect(agentJson['suggestedCommandIds'], <String>['applyQuickFix']);
    expect(workspaceEdit['suggestedCommandIds'], <String>['applyQuickFix']);
    expect(previewJson['planId'], 'workspace-fix');
    expect(previewJson['summary'], 'Replace value initializer.');
    expect(previewJson['canApply'], isTrue);
    expect(previewJson['editCount'], 1);
    expect(confirmationJson['status'], 'ready');
    expect(confirmationJson['riskLevel'], 'low');
    expect(confirmationJson['blockingReasons'], isEmpty);
    expect(diffWindow['documentLimit'], 3);
    expect(diffWindow['totalDocumentCount'], 1);
    expect(lastApplyResult['planId'], 'workspace-fix');
    expect(lastApplyResult['successful'], isTrue);
    expect(lastApplyResult['appliedEditCount'], 1);
    expect(lastApplyResult['appliedDocumentIds'], <String>['src/main.styio']);
  });
}

const _agentLanguageServiceStatus = LanguageServiceStatusSurface(
  runtimeState: 'active',
  severity: LanguageServiceStatusSeverity.ready,
  title: 'StyioService ready',
  message: 'StyioService has 2 usable capability result(s).',
  toolchainId: 'styio-cli-nightly',
  parserEngine: 'nightly',
  grammarVersion: '2026.05',
  usableCapabilityCount: 2,
  freshCapabilityCount: 1,
  capabilityHealth: 'degraded',
  missingCapabilityCount: 1,
  blockedCapabilityCount: 1,
  providerReadiness: 'degraded',
  providerReadinessSummary:
      'Styio language providers cover 8/10 required IDE capabilities.',
  providerMissingCapabilityCount: 2,
  cacheLookupHits: 6,
  cacheLookupMisses: 2,
  cacheLookupCount: 8,
  cacheLookupHitRate: 0.75,
  primaryCapabilityStates: <String, String>{
    'diagnostics': 'available',
    'completion': 'derived',
    'hover': 'unsupported',
  },
  capabilities: <LanguageServiceCapabilityStatusItem>[
    LanguageServiceCapabilityStatusItem(
      capability: 'diagnostics',
      state: 'available',
      usable: true,
      fresh: true,
    ),
    LanguageServiceCapabilityStatusItem(
      capability: 'completion',
      state: 'derived',
      usable: true,
      fresh: false,
    ),
    LanguageServiceCapabilityStatusItem(
      capability: 'hover',
      state: 'unsupported',
      usable: false,
      fresh: false,
    ),
  ],
  localFallbackEnabled: true,
);
