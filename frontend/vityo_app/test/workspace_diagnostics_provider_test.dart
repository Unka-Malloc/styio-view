import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace diagnostics snapshot groups and counts diagnostics', () {
    const snapshot = WorkspaceDiagnosticsSnapshot(
      providerId: 'language',
      diagnostics: <WorkspaceDiagnostic>[
        WorkspaceDiagnostic(
          documentId: 'main.styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'syntax-error',
            message: 'Unexpected token.',
            range: SourceRange(start: 0, end: 1),
          ),
        ),
        WorkspaceDiagnostic(
          documentId: 'lib/math.styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unused-binding',
            message: 'Binding is unused.',
            range: SourceRange(start: 3, end: 8),
          ),
        ),
      ],
    );

    final json = snapshot.toJson();

    expect(snapshot.totalCount, 2);
    expect(snapshot.hasErrors, isTrue);
    expect(snapshot.documentIds, <String>['lib/math.styio', 'main.styio']);
    expect(snapshot.severityCounts['error'], 1);
    expect(snapshot.severityCounts['warning'], 1);
    expect(snapshot.diagnosticsFor('main.styio'), hasLength(1));
    expect(
      snapshot.diagnosticsForSeverity(DiagnosticSeverity.error),
      hasLength(1),
    );
    expect(snapshot.documentGroups, hasLength(2));
    expect(snapshot.documentGroups.first.documentId, 'main.styio');
    expect(snapshot.documentGroups.first.hasErrors, isTrue);
    expect(snapshot.documentGroups.first.severityCounts['error'], 1);
    expect(snapshot.sourceGroups.single.source, 'language');
    expect(snapshot.sourceGroups.single.totalCount, 2);
    expect(json['diagnostics'], isNotEmpty);
    expect(json['documentGroups'], isNotEmpty);
    expect(json['sourceGroups'], isNotEmpty);
  });

  test('workspace diagnostics stream unifies sources and quick fixes', () {
    const snapshot = WorkspaceDiagnosticsSnapshot(
      providerId: 'mixed',
      diagnostics: <WorkspaceDiagnostic>[
        WorkspaceDiagnostic(
          documentId: 'main.styio',
          providerId: 'styio-language',
          source: 'styio-language',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'local.unclosed-delimiter',
            message: 'Missing delimiter.',
            range: SourceRange(start: 0, end: 1),
          ),
          quickFixes: <DiagnosticQuickFix>[
            DiagnosticQuickFix(
              label: 'Insert matching delimiter',
              edits: <FormattingEdit>[
                FormattingEdit(
                  range: SourceRange(start: 1, end: 1),
                  newText: '}',
                ),
              ],
            ),
          ],
        ),
        WorkspaceDiagnostic(
          documentId: 'native.log',
          providerId: 'native-tool',
          source: 'native-tool',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'tool.warning',
            message: 'Native tool warning.',
            range: SourceRange(start: 2, end: 3),
          ),
        ),
      ],
    );

    final stream = snapshot.streamSnapshot;
    final json = stream.toJson();

    expect(stream.totalCount, 2);
    expect(stream.quickFixReadyCount, 1);
    expect(stream.sourceKindCounts['styio-project'], 1);
    expect(stream.sourceKindCounts['native-tool'], 1);
    expect(stream.entries.first.hasQuickFixes, isTrue);
    expect(json['quickFixReadyCount'], 1);
    expect(json['entries'], isNotEmpty);
    expect(
      ((json['entries']! as List<Object?>).first!
          as Map<String, Object?>)['quickFixLabels'],
      <String>['Insert matching delimiter'],
    );
  });

  test(
    'workspace diagnostics producer execution plan targets toolchain route',
    () {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
        documents: <DocumentState>[
          DocumentState(
            documentId: 'src/main.styio',
            text: '>_("demo")\n',
            revision: 1,
          ),
        ],
      );

      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'native-static-analysis',
        request: request,
        command: 'clang-tidy',
        arguments: const <String>['src/main.cc'],
        workingDirectory: '/workspace/vityo',
      );

      expect(plan.ready, isTrue);
      expect(plan.definition.kind, RuntimeTaskKind.toolchain);
      expect(plan.definition.metadata['toolchainKind'], 'static-analyzer');
      expect(
        plan.handoff.target,
        RuntimeExecutionHandoffTarget.toolchainManager,
      );
      expect(plan.binding.managerId, 'toolchain-manager');
      expect(plan.binding.routeKind, 'toolchain-task');
      expect(
        plan.binding.outputChannel.kind,
        RuntimeOutputChannelKind.nativeTools,
      );
      expect(plan.binding.metadata['diagnosticsProducer'], isTrue);
      expect(plan.toJson()['ready'], isTrue);
    },
  );

  test(
    'workspace diagnostics producer lifecycle reports progress and cancellation',
    () {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio', 'src/lib.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
        workingDirectory: '/workspace/vityo',
      );
      final controller = WorkspaceDiagnosticsProducerLifecycleController();

      final queued = controller.register(plan);
      final running = controller.start(
        plan,
        message: 'Styio diagnostics started.',
      );
      final progress = controller.reportProgress(
        plan,
        progress: 0.5,
        message: 'Scanned 1 of 2 documents.',
      );
      final route = controller.cancellationRouteFor(
        plan,
        processHandleId: 'styio-check-1',
        reason: 'User cancelled diagnostics.',
      );
      final cancelled = controller.requestCancellation(
        plan,
        reason: 'User cancelled diagnostics.',
      );

      expect(queued.status, RuntimeTaskStatus.queued);
      expect(queued.canCancel, isTrue);
      expect(running.status, RuntimeTaskStatus.running);
      expect(progress.progress, 0.5);
      expect(progress.message, 'Scanned 1 of 2 documents.');
      expect(progress.toJson()['canCancel'], isTrue);
      expect(route.canCancel, isTrue);
      expect(route.processHandleBound, isTrue);
      expect(route.routeKind, 'process-handle');
      expect(route.toJson()['managerId'], 'toolchain-manager');
      expect(route.toJson()['processHandleId'], 'styio-check-1');
      expect(cancelled.status, RuntimeTaskStatus.cancelled);
      expect(cancelled.cancellationRequested, isTrue);
      expect(cancelled.canCancel, isFalse);
      expect(controller.snapshots, hasLength(1));
      expect(
        controller.snapshotForProvider('styio-project-diagnostics')?.taskId,
        'diagnostics.styio-project-diagnostics',
      );
    },
  );

  test(
    'workspace diagnostics producer cancellation adapter records termination',
    () async {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final controller = WorkspaceDiagnosticsProducerLifecycleController();
      controller.start(plan, message: 'Styio diagnostics started.');

      final cancelled = await controller.requestProcessCancellation(
        plan,
        reason: 'User cancelled diagnostics.',
        adapter: WorkspaceDiagnosticsProducerCancellationAdapter(
          cancel: ({required plan, required current, required reason}) async {
            expect(plan.providerId, 'styio-project-diagnostics');
            expect(current.status, RuntimeTaskStatus.running);
            expect(reason, 'User cancelled diagnostics.');
            return const WorkspaceDiagnosticsProducerCancellationResult.accepted(
              processTerminated: true,
              message: 'Terminated diagnostics process.',
              metadata: <String, Object?>{'pid': 42},
            );
          },
        ),
      );
      final cancellationEvent = cancelled.taskSnapshot.events.last;
      final cancellationMetadata =
          cancellationEvent.metadata['diagnosticsProducerCancellation']!
              as Map<String, Object?>;

      expect(cancelled.status, RuntimeTaskStatus.cancelled);
      expect(cancelled.cancellationRequested, isTrue);
      expect(cancelled.message, 'Terminated diagnostics process.');
      expect(cancellationMetadata['processTerminated'], isTrue);
      expect(
        (cancellationMetadata['metadata']! as Map<String, Object?>)['pid'],
        42,
      );
    },
  );

  test(
    'workspace diagnostics producer process cancellation adapter binds handle',
    () async {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final controller = WorkspaceDiagnosticsProducerLifecycleController();
      controller.start(plan, message: 'Styio diagnostics started.');
      final handle = _FakeWorkspaceDiagnosticsProcessCancellationHandle(
        handleId: 'toolchain-process-42',
        result: const WorkspaceDiagnosticsProducerCancellationResult.accepted(
          processTerminated: true,
          message: 'Terminated native diagnostics process.',
          metadata: <String, Object?>{'pid': 42},
        ),
      );

      final cancelled = await controller.requestProcessCancellation(
        plan,
        reason: 'User cancelled diagnostics.',
        adapter: WorkspaceDiagnosticsProducerCancellationAdapter.processHandle(
          handle,
        ),
      );
      final cancellationEvent = cancelled.taskSnapshot.events.last;
      final cancellationMetadata =
          cancellationEvent.metadata['diagnosticsProducerCancellation']!
              as Map<String, Object?>;
      final processMetadata =
          cancellationMetadata['metadata']! as Map<String, Object?>;

      expect(handle.cancelledProviderIds, <String>[
        'styio-project-diagnostics',
      ]);
      expect(handle.lastCurrentStatus, RuntimeTaskStatus.running);
      expect(handle.lastReason, 'User cancelled diagnostics.');
      expect(cancelled.status, RuntimeTaskStatus.cancelled);
      expect(cancelled.message, 'Terminated native diagnostics process.');
      expect(processMetadata['pid'], 42);
      expect(processMetadata['processHandleId'], 'toolchain-process-42');
    },
  );

  test(
    'workspace diagnostics binds runtime process handles into cancellation registry',
    () async {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final dispatch = RuntimeExecutionManagerRegistry.defaultManagers()
          .dispatch(
            plan.binding,
            timestamp: DateTime.utc(2026, 5, 21, 7),
            metadata: const <String, Object?>{'processHandleId': 'diag-42'},
          );
      final registry = WorkspaceDiagnosticsProducerProcessHandleRegistry();
      final terminationRequests =
          <WorkspaceDiagnosticsProducerTerminationRequest>[];
      final binding = const WorkspaceDiagnosticsProducerProcessHandleBinder().bind(
        plan: plan,
        result: dispatch,
        registry: registry,
        terminate: (request) async {
          terminationRequests.add(request);
          return const WorkspaceDiagnosticsProducerCancellationResult.accepted(
            processTerminated: true,
            message: 'Diagnostics process terminated.',
          );
        },
      );
      final controller = WorkspaceDiagnosticsProducerLifecycleController();
      controller.start(plan, message: 'Styio diagnostics started.');
      final adapter = registry.adapterForProvider('styio-project-diagnostics');

      final cancelled = await controller.requestProcessCancellation(
        plan,
        reason: 'agent cancelled diagnostics',
        adapter: adapter!,
      );

      expect(binding.registered, isTrue);
      expect(binding.processHandleId, 'diag-42');
      expect(registry.handleForProvider(plan.providerId)?.handleId, 'diag-42');
      expect(cancelled.status, RuntimeTaskStatus.cancelled);
      expect(cancelled.cancellationRequested, isTrue);
      expect(terminationRequests.single.processHandleId, 'diag-42');
      expect(terminationRequests.single.managerId, 'toolchain-manager');
      expect(terminationRequests.single.routeKind, 'toolchain-task');
    },
  );

  test(
    'workspace diagnostics binds typed runtime process handle pid fallback',
    () {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final dispatch = RuntimeExecutionManagerRegistry.defaultManagers()
          .dispatch(
            plan.binding,
            timestamp: DateTime.utc(2026, 5, 21, 8),
            metadata: const <String, Object?>{
              'pid': 7788,
              'processHandleSource': 'toolchain-manager',
            },
          );
      final registry = WorkspaceDiagnosticsProducerProcessHandleRegistry();
      final binding = const WorkspaceDiagnosticsProducerProcessHandleBinder().bind(
        plan: plan,
        result: dispatch,
        registry: registry,
        terminate: (request) async {
          return const WorkspaceDiagnosticsProducerCancellationResult.accepted(
            processTerminated: true,
            message: 'Diagnostics process terminated.',
          );
        },
      );
      final processHandle =
          binding.metadata['processHandle']! as Map<String, Object?>;

      expect(binding.registered, isTrue);
      expect(binding.processHandleId, '7788');
      expect(processHandle['pid'], 7788);
      expect(processHandle['source'], 'toolchain-manager');
      expect(registry.handleForProvider(plan.providerId)?.handleId, '7788');
    },
  );

  test(
    'workspace diagnostics controller resolves producer process handles',
    () async {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final lifecycleController =
          WorkspaceDiagnosticsProducerLifecycleController()
            ..start(plan, message: 'Styio diagnostics started.');
      final handle = _FakeWorkspaceDiagnosticsProcessCancellationHandle(
        handleId: 'toolchain-process-99',
        result: const WorkspaceDiagnosticsProducerCancellationResult.accepted(
          processTerminated: true,
          message: 'Terminated registered diagnostics process.',
          metadata: <String, Object?>{'pid': 99},
        ),
      );
      final registry = WorkspaceDiagnosticsProducerProcessHandleRegistry()
        ..register(providerId: 'styio-project-diagnostics', handle: handle);
      final controller = WorkspaceDiagnosticsController(
        provider: const StaticWorkspaceDiagnosticsProvider(
          providerId: 'static',
          snapshot: WorkspaceDiagnosticsSnapshot(
            providerId: 'static',
            diagnostics: <WorkspaceDiagnostic>[],
          ),
        ),
        producerLifecycleController: lifecycleController,
        producerProcessHandleRegistry: registry,
      );
      addTearDown(controller.dispose);

      final cancelled = await controller.cancelDiagnosticsProducer(
        lifecycleController.snapshots.single,
        reason: 'User cancelled diagnostics.',
      );

      expect(cancelled?.status, RuntimeTaskStatus.cancelled);
      expect(cancelled?.message, 'Terminated registered diagnostics process.');
      expect(handle.cancelledProviderIds, <String>[
        'styio-project-diagnostics',
      ]);
      expect(registry.toJson()['providerCount'], 1);
      expect(
        registry.adapterForProvider('styio-project-diagnostics'),
        isNotNull,
      );
    },
  );

  test(
    'workspace diagnostics producer cancellation adapter can reject requests',
    () async {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['src/main.styio'],
        activeDocumentId: 'src/main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final controller = WorkspaceDiagnosticsProducerLifecycleController();
      controller.start(plan, message: 'Styio diagnostics started.');

      final rejected = await controller.requestProcessCancellation(
        plan,
        reason: 'User cancelled diagnostics.',
        adapter: WorkspaceDiagnosticsProducerCancellationAdapter(
          cancel: ({required plan, required current, required reason}) async {
            return const WorkspaceDiagnosticsProducerCancellationResult.rejected(
              message: 'No process handle is bound.',
            );
          },
        ),
      );

      expect(rejected.status, RuntimeTaskStatus.running);
      expect(rejected.cancellationRequested, isFalse);
      expect(rejected.canCancel, isTrue);
      expect(rejected.message, 'No process handle is bound.');
    },
  );

  test('workspace diagnostics view applies serializable filters', () {
    const snapshot = WorkspaceDiagnosticsSnapshot(
      providerId: 'language',
      diagnostics: <WorkspaceDiagnostic>[
        WorkspaceDiagnostic(
          documentId: 'src/main.styio',
          source: 'styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'syntax-error',
            message: 'Unexpected token.',
            range: SourceRange(start: 0, end: 1),
          ),
        ),
        WorkspaceDiagnostic(
          documentId: 'test/parser.styio',
          source: 'fixture',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'fixture-warning',
            message: 'Fixture warning.',
            range: SourceRange(start: 2, end: 4),
          ),
        ),
      ],
    );
    const filter = WorkspaceDiagnosticsFilterState(
      severities: <DiagnosticSeverity>[DiagnosticSeverity.warning],
      documentQuery: 'test/',
      sources: <String>['fixture'],
    );

    final reloadedFilter = WorkspaceDiagnosticsFilterState.fromJson(
      filter.toJson(),
    );
    final view = WorkspaceDiagnosticsView.fromSnapshot(
      snapshot,
      filter: reloadedFilter,
    );
    final json = view.toJson();

    expect(reloadedFilter.active, isTrue);
    expect(reloadedFilter.summary, 'warning · document test/ · source fixture');
    expect(view.totalCount, 2);
    expect(view.visibleCount, 1);
    expect(view.visibleDiagnostics.single.documentId, 'test/parser.styio');
    expect(view.documentGroups.single.documentId, 'test/parser.styio');
    expect(view.sourceGroups.single.source, 'fixture');
    expect(json['visibleCount'], 1);
    expect(json['sourceGroups'], isNotEmpty);
  });

  test('workspace quick fix confirmation plan reports readiness', () {
    const readyPreview = WorkspaceEditPreview(
      planId: 'fix-ready',
      summary: 'Apply workspace fix',
      source: WorkspaceEditSource.codeAction,
      documents: <WorkspaceEditDocumentPreview>[
        WorkspaceEditDocumentPreview(
          documentId: 'src/main.styio',
          revision: 1,
          beforeText: 'before',
          afterText: 'after',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 6),
              newText: 'after',
            ),
          ],
        ),
      ],
    );
    const blockedPreview = WorkspaceEditPreview(
      planId: 'fix-blocked',
      summary: 'Apply blocked workspace fix',
      source: WorkspaceEditSource.codeAction,
      documents: <WorkspaceEditDocumentPreview>[],
      missingDocumentIds: <String>['src/missing.styio'],
    );

    final ready = WorkspaceQuickFixConfirmationPlan.fromPreview(readyPreview);
    final blocked = WorkspaceQuickFixConfirmationPlan.fromPreview(
      blockedPreview,
    );
    final missing = WorkspaceQuickFixConfirmationPlan.fromPreview(null);

    expect(ready.ready, isTrue);
    expect(ready.affectedDocumentIds, <String>['src/main.styio']);
    expect(ready.toJson()['todo'], contains('diff preview'));
    expect(
      blocked.status,
      WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments,
    );
    expect(blocked.missingDocumentIds, <String>['src/missing.styio']);
    expect(
      missing.status,
      WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
    );
  });

  test('workspace diagnostic quick fix review bridges into workspace edit', () {
    const diagnostic = WorkspaceDiagnostic(
      documentId: 'src/main.styio',
      source: 'styio-language',
      diagnostic: Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'missing-assignment',
        message: 'Variable declaration is missing `=`.',
        range: SourceRange(start: 0, end: 9),
      ),
      quickFixes: <DiagnosticQuickFix>[
        DiagnosticQuickFix(
          label: 'Insert assignment',
          detail: 'Append assignment.',
          edits: <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 9, end: 9),
              newText: ' = value',
            ),
          ],
        ),
      ],
    );
    const documents = <DocumentState>[
      DocumentState(
        documentId: 'src/main.styio',
        text: 'let count\n',
        revision: 3,
      ),
    ];

    final review = WorkspaceQuickFixReviewPlan.fromDiagnostic(
      diagnostic: diagnostic,
      documents: documents,
    );
    final window = review.diffWindow();
    final missing = WorkspaceQuickFixReviewPlan.fromDiagnostic(
      diagnostic: diagnostic,
      documents: documents,
      quickFixIndex: 4,
    );

    expect(review.ready, isTrue);
    expect(review.plan?.source, WorkspaceEditSource.codeAction);
    expect(review.preview?.canApply, isTrue);
    expect(review.controls?.canApply, isTrue);
    expect(window?.documents.single.afterText, 'let count = value\n');
    expect(review.toJson()['todo'], contains('producer telemetry'));
    expect(missing.ready, isFalse);
    expect(
      missing.confirmationPlan.status,
      WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
    );
  });

  test('workspace diagnostics provider registry resolves active provider', () {
    final snapshot = const WorkspaceDiagnosticsSnapshot(
      providerId: 'high',
      diagnostics: <WorkspaceDiagnostic>[],
    );
    final registry = WorkspaceDiagnosticsProviderRegistry()
      ..register(
        WorkspaceDiagnosticsProviderRegistration(
          id: 'low',
          provider: StaticWorkspaceDiagnosticsProvider(
            providerId: 'low',
            snapshot: snapshot,
          ),
          priority: 1,
          state: FoundationRegistryEntryState.active,
        ),
      )
      ..register(
        WorkspaceDiagnosticsProviderRegistration(
          id: 'high',
          provider: StaticWorkspaceDiagnosticsProvider(
            providerId: 'high',
            snapshot: snapshot,
          ),
          priority: 10,
          state: FoundationRegistryEntryState.active,
          metadata: const <String, Object?>{'source': 'styio-service'},
        ),
      );

    final resolved = registry.resolve();
    final manifest = registry.manifest().toJson();
    final entries = manifest['entries']! as List<Object?>;

    expect(resolved?.id, 'high');
    expect(registry.provider(), same(resolved?.value));
    expect(entries, hasLength(2));
    expect(
      ((entries.first! as Map<String, Object?>)['metadata']!
          as Map<String, Object?>)['providerContract'],
      'workspace-diagnostics-provider',
    );
  });

  test(
    'static workspace diagnostics provider returns configured snapshot',
    () async {
      const snapshot = WorkspaceDiagnosticsSnapshot(
        providerId: 'static',
        diagnostics: <WorkspaceDiagnostic>[
          WorkspaceDiagnostic(
            documentId: 'main.styio',
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: 'style',
              message: 'Prefer explicit name.',
              range: SourceRange(start: 0, end: 1),
            ),
          ),
        ],
      );
      const provider = StaticWorkspaceDiagnosticsProvider(
        providerId: 'static',
        snapshot: snapshot,
      );

      final result = await provider.collect(
        const WorkspaceDiagnosticsRequest(
          documentIds: <String>['main.styio'],
          activeDocumentId: 'main.styio',
        ),
      );

      expect(result.providerId, 'static');
      expect(result.totalCount, 1);
      expect(result.diagnostics.single.diagnostic.code, 'style');
    },
  );

  test('workspace diagnostics controller caches provider snapshot', () async {
    const snapshot = WorkspaceDiagnosticsSnapshot(
      providerId: 'static',
      diagnostics: <WorkspaceDiagnostic>[
        WorkspaceDiagnostic(
          documentId: 'main.styio',
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'styio.controller',
            message: 'controller diagnostic',
            range: SourceRange(start: 0, end: 1),
          ),
        ),
      ],
    );
    final controller = WorkspaceDiagnosticsController(
      provider: const StaticWorkspaceDiagnosticsProvider(
        providerId: 'static',
        snapshot: snapshot,
      ),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });

    final result = await controller.refresh(
      const WorkspaceDiagnosticsRequest(documentIds: <String>['main.styio']),
    );

    expect(result, same(snapshot));
    expect(controller.snapshot, same(snapshot));
    expect(controller.hasSnapshot, isTrue);
    expect(notifications, 1);

    controller.clear();

    expect(controller.snapshot, isNull);
    expect(notifications, 2);
  });

  test(
    'workspace diagnostics controller cancels registered producer lifecycle',
    () async {
      const request = WorkspaceDiagnosticsRequest(
        documentIds: <String>['main.styio'],
        activeDocumentId: 'main.styio',
      );
      final plan = WorkspaceDiagnosticsProducerExecutionPlan.nativeTool(
        providerId: 'styio-project-diagnostics',
        request: request,
        command: 'styio',
        arguments: const <String>['check', '.'],
      );
      final lifecycleController =
          WorkspaceDiagnosticsProducerLifecycleController()
            ..start(plan, message: 'Styio diagnostics started.');
      final controller = WorkspaceDiagnosticsController(
        provider: const StaticWorkspaceDiagnosticsProvider(
          providerId: 'static',
          snapshot: WorkspaceDiagnosticsSnapshot(
            providerId: 'static',
            diagnostics: <WorkspaceDiagnostic>[],
          ),
        ),
        producerLifecycleController: lifecycleController,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });

      final cancelled = await controller.cancelDiagnosticsProducer(
        controller.diagnosticsProducerLifecycles.single,
      );

      expect(cancelled?.toJson()['status'], 'cancelled');
      expect(cancelled?.cancellationRequested, isTrue);
      expect(
        controller.diagnosticsProducerLifecycles.single.canCancel,
        isFalse,
      );
      expect(notifications, 1);
    },
  );

  test('workspace diagnostics controller records provider failure', () async {
    final controller = WorkspaceDiagnosticsController(
      provider: const _FailingWorkspaceDiagnosticsProvider(),
    );
    addTearDown(controller.dispose);

    final result = await controller.refresh(
      const WorkspaceDiagnosticsRequest(documentIds: <String>['main.styio']),
    );

    expect(result.providerId, 'failing');
    expect(result.totalCount, 0);
    expect(result.message, contains('Workspace diagnostics unavailable'));
    expect(controller.snapshot, same(result));
  });

  test('workspace diagnostics filter store persists problem filters', () async {
    final store = WorkspaceDiagnosticsFilterStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    const filter = WorkspaceDiagnosticsFilterState(
      severities: <DiagnosticSeverity>[DiagnosticSeverity.warning],
      documentQuery: 'test/',
      sources: <String>['fixture'],
    );

    await store.saveFilter(workspaceId: 'demo', filter: filter);
    final restored = await store.readFilter(workspaceId: 'demo');

    expect(restored.summary, 'warning · document test/ · source fixture');
    expect(restored.matches(_workspaceDiagnostic('test/main.styio')), isTrue);
    expect(restored.matches(_workspaceDiagnostic('src/main.styio')), isFalse);
    expect(await store.deleteFilter(workspaceId: 'demo'), isTrue);
    expect((await store.readFilter(workspaceId: 'demo')).active, isFalse);
  });

  test(
    'workspace diagnostics controller applies persisted problem filter',
    () async {
      final store = WorkspaceDiagnosticsFilterStore.fromDataStore(
        dataStore: await _createDataStore(),
      );
      await store.saveFilter(
        workspaceId: 'demo',
        filter: const WorkspaceDiagnosticsFilterState(
          severities: <DiagnosticSeverity>[DiagnosticSeverity.warning],
        ),
      );
      final controller = WorkspaceDiagnosticsController(
        provider: StaticWorkspaceDiagnosticsProvider(
          providerId: 'static',
          snapshot: WorkspaceDiagnosticsSnapshot(
            providerId: 'static',
            diagnostics: <WorkspaceDiagnostic>[
              _workspaceDiagnostic('src/main.styio'),
              _workspaceDiagnostic(
                'test/main.styio',
                severity: DiagnosticSeverity.error,
              ),
            ],
          ),
        ),
        filterStore: store,
        workspaceId: 'demo',
      );
      addTearDown(controller.dispose);

      await controller.loadFilter();
      await controller.refresh(
        const WorkspaceDiagnosticsRequest(
          documentIds: <String>['src/main.styio', 'test/main.styio'],
        ),
      );

      expect(controller.filterState.summary, 'warning');
      expect(controller.view?.visibleCount, 1);
      expect(
        controller.view?.visibleDiagnostics.single.documentId,
        'src/main.styio',
      );
    },
  );
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_workspace_diagnostics_filter_test_',
  );
  // ignore: discarded_futures
  addTearDown(() => tempRoot.delete(recursive: true));
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}

WorkspaceDiagnostic _workspaceDiagnostic(
  String documentId, {
  DiagnosticSeverity severity = DiagnosticSeverity.warning,
}) {
  return WorkspaceDiagnostic(
    documentId: documentId,
    source: documentId.startsWith('test/') ? 'fixture' : 'styio',
    diagnostic: Diagnostic(
      severity: severity,
      code: severity.name,
      message: '${severity.name} diagnostic',
      range: const SourceRange(start: 0, end: 1),
    ),
  );
}

class _FakeWorkspaceDiagnosticsProcessCancellationHandle
    implements WorkspaceDiagnosticsProcessCancellationHandle {
  _FakeWorkspaceDiagnosticsProcessCancellationHandle({
    required this.handleId,
    required this.result,
  });

  @override
  final String handleId;

  final WorkspaceDiagnosticsProducerCancellationResult result;
  final List<String> cancelledProviderIds = <String>[];
  RuntimeTaskStatus? lastCurrentStatus;
  String lastReason = '';

  @override
  Future<WorkspaceDiagnosticsProducerCancellationResult>
  cancelDiagnosticsProducer({
    required WorkspaceDiagnosticsProducerExecutionPlan plan,
    required WorkspaceDiagnosticsProducerLifecycleSnapshot current,
    required String reason,
  }) async {
    cancelledProviderIds.add(plan.providerId);
    lastCurrentStatus = current.status;
    lastReason = reason;
    return result;
  }
}

class _FailingWorkspaceDiagnosticsProvider
    implements WorkspaceDiagnosticsProvider {
  const _FailingWorkspaceDiagnosticsProvider();

  @override
  String get providerId => 'failing';

  @override
  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  ) async {
    throw StateError('fixture failure');
  }
}
