import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';

void main() {
  test('semantic snapshot bridge dispatches code actions to Problems sink', () {
    final received = <SemanticSnapshotPanelEvent>[];
    const bridge = SemanticSnapshotEventBridge();
    final dispatcher = SemanticSnapshotPanelEventDispatcher(
      sinks: <SemanticSnapshotPanelEventSink>[
        SemanticSnapshotPanelEventSink.problems(handle: received.add),
        SemanticSnapshotPanelEventSink.refactor(handle: received.add),
      ],
    );
    final event = bridge.codeActionDiscoveryEvent(
      documentId: 'src/main.styio',
      timestamp: DateTime.utc(2026, 5, 20, 1),
      result: const SemanticSnapshotCodeActionResult(
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        diagnosticCode: 'missing-assignment',
        message: '1 action.',
        actions: <SemanticSnapshotCodeActionFact>[
          SemanticSnapshotCodeActionFact(
            id: 'insert-assignment',
            label: 'Insert assignment',
            diagnosticCode: 'missing-assignment',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 9, end: 9),
                newText: ' = value',
              ),
            ],
          ),
        ],
      ),
    );

    final report = dispatcher.dispatch(event);

    expect(report.delivered, isTrue);
    expect(report.deliveredSinkIds, <String>['problems-panel']);
    expect(report.skippedSinkIds, <String>['refactor-panel']);
    expect(received.single.target, SemanticSnapshotPanelEventTarget.problems);
    expect(
      received.single.kind,
      SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
    );
    expect(received.single.documentId, 'src/main.styio');
    expect(received.single.payload['diagnosticCode'], 'missing-assignment');
    expect(report.toJson()['delivered'], isTrue);
  });

  test(
    'semantic snapshot bridge dispatches diagnostics and semantic tokens',
    () {
      final received = <SemanticSnapshotPanelEvent>[];
      const bridge = SemanticSnapshotEventBridge();
      final dispatcher = SemanticSnapshotPanelEventDispatcher(
        sinks: <SemanticSnapshotPanelEventSink>[
          SemanticSnapshotPanelEventSink.problems(handle: received.add),
          SemanticSnapshotPanelEventSink.refactor(handle: received.add),
        ],
      );

      final diagnosticsReport = dispatcher.dispatch(
        bridge.diagnosticsSnapshotEvent(
          documentId: 'src/main.styio',
          providerId: 'styio-service',
          diagnosticCount: 2,
          hasErrors: true,
          severityCounts: const <String, int>{
            'error': 1,
            'warning': 1,
            'info': 0,
          },
          documentCount: 1,
          sourceCount: 1,
          timestamp: DateTime.utc(2026, 5, 21, 1),
        ),
      );
      final tokenReport = dispatcher.dispatch(
        bridge.semanticTokensEvent(
          documentId: 'src/main.styio',
          semanticSpanCount: 3,
          semanticBlockCount: 1,
          documentSymbolCount: 1,
          inlayHintCount: 0,
          diagnosticCount: 2,
          timestamp: DateTime.utc(2026, 5, 21, 2),
        ),
      );

      final state = SemanticSnapshotPanelEventState.empty(
        SemanticSnapshotPanelEventTarget.problems,
      ).record(received.first).record(received.last);
      final viewModel = SemanticSnapshotPanelViewModel.fromState(state);

      expect(diagnosticsReport.deliveredSinkIds, <String>['problems-panel']);
      expect(tokenReport.deliveredSinkIds, <String>['problems-panel']);
      expect(
        received.map((event) => event.kind),
        <SemanticSnapshotTelemetryEventKind>[
          SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot,
          SemanticSnapshotTelemetryEventKind.semanticTokens,
        ],
      );
      expect(viewModel.diagnosticEventCount, 1);
      expect(viewModel.semanticTokenEventCount, 1);
      expect(viewModel.items.first.actionLabel, '3 semantic token(s)');
      expect(viewModel.items.last.actionLabel, '2 diagnostic(s)');
      expect(viewModel.toJson()['diagnosticEventCount'], 1);
      expect(viewModel.toJson()['semanticTokenEventCount'], 1);
    },
  );

  test(
    'semantic snapshot bridge dispatches rename safety to Refactor sink',
    () {
      final received = <SemanticSnapshotPanelEvent>[];
      const bridge = SemanticSnapshotEventBridge();
      final dispatcher = SemanticSnapshotPanelEventDispatcher(
        sinks: <SemanticSnapshotPanelEventSink>[
          SemanticSnapshotPanelEventSink.problems(handle: received.add),
          SemanticSnapshotPanelEventSink.refactor(handle: received.add),
        ],
      );
      final event = bridge.renameSafetyEvent(
        documentId: 'src/main.styio',
        timestamp: DateTime.utc(2026, 5, 20, 2),
        result: const SemanticSnapshotRenameSafetyResult(
          source: SemanticSnapshotProviderSource.serviceAnalysis,
          available: true,
          safe: true,
          targetName: 'oldName',
          newName: 'newName',
          referenceCount: 2,
          editCount: 2,
          affectedDocumentIds: <String>['src/main.styio'],
          message: 'Rename is safe.',
        ),
      );

      final report = dispatcher.dispatch(event);

      expect(report.deliveredSinkIds, <String>['refactor-panel']);
      expect(report.skippedSinkIds, <String>['problems-panel']);
      expect(received.single.target, SemanticSnapshotPanelEventTarget.refactor);
      expect(
        received.single.kind,
        SemanticSnapshotTelemetryEventKind.renameSafety,
      );
      expect(received.single.payload['newName'], 'newName');
    },
  );

  test(
    'semantic snapshot panel state controller records dispatched events',
    () {
      final controller = SemanticSnapshotPanelEventStateController();
      const bridge = SemanticSnapshotEventBridge();
      final dispatcher = SemanticSnapshotPanelEventDispatcher(
        sinks: <SemanticSnapshotPanelEventSink>[
          controller.sinkFor(SemanticSnapshotPanelEventTarget.problems),
          controller.sinkFor(SemanticSnapshotPanelEventTarget.refactor),
        ],
      );
      final event = bridge.codeActionApplyEvent(
        documentId: 'src/main.styio',
        timestamp: DateTime.utc(2026, 5, 20, 3),
        result: const SemanticSnapshotCodeActionApplyResult(
          actionId: 'insert-assignment',
          label: 'Insert assignment',
          diagnosticCode: 'missing-assignment',
          status: SemanticSnapshotCodeActionApplyStatus.applied,
          editCount: 1,
          appliedEditCount: 1,
          message: 'Applied.',
        ),
      );

      final report = dispatcher.dispatch(event);
      final state = controller.stateFor(
        SemanticSnapshotPanelEventTarget.problems,
      );

      expect(report.deliveredSinkIds, <String>['problems-state-store']);
      expect(state.revision, 1);
      expect(state.events.single.documentId, 'src/main.styio');
      expect(
        state.events.single.kind,
        SemanticSnapshotTelemetryEventKind.codeActionApply,
      );
    },
  );

  test('semantic snapshot panel state projects UI view models', () {
    final problemsState =
        SemanticSnapshotPanelEventState.empty(
          SemanticSnapshotPanelEventTarget.problems,
        ).record(
          SemanticSnapshotPanelEvent(
            target: SemanticSnapshotPanelEventTarget.problems,
            kind: SemanticSnapshotTelemetryEventKind.codeActionApply,
            documentId: 'src/main.styio',
            message: 'Applied.',
            payload: <String, Object?>{
              'status': 'applied',
              'label': 'Insert assignment',
            },
            timestamp: DateTime.utc(2026, 5, 20, 5),
          ),
        );
    final refactorState =
        SemanticSnapshotPanelEventState.empty(
          SemanticSnapshotPanelEventTarget.refactor,
        ).record(
          SemanticSnapshotPanelEvent(
            target: SemanticSnapshotPanelEventTarget.refactor,
            kind: SemanticSnapshotTelemetryEventKind.renameSafety,
            documentId: 'src/main.styio',
            message: 'Rename may conflict.',
            payload: <String, Object?>{'safe': false, 'newName': 'nextName'},
            timestamp: DateTime.utc(2026, 5, 20, 6),
          ),
        );

    final problems = SemanticSnapshotPanelViewModel.fromState(problemsState);
    final refactor = SemanticSnapshotPanelViewModel.fromState(refactorState);

    expect(problems.title, 'Problems');
    expect(problems.codeActionCount, 1);
    expect(problems.items.single.severity, 'success');
    expect(problems.items.single.actionLabel, 'Insert assignment');
    expect(refactor.title, 'Refactor');
    expect(refactor.renameSafetyCount, 1);
    expect(refactor.items.single.severity, 'warning');
    expect(refactor.items.single.actionLabel, 'Rename to nextName');
    expect(problems.toJson()['itemCount'], 1);
    expect(refactor.toJson()['renameSafetyCount'], 1);
  });

  test('semantic snapshot panel event store persists telemetry', () async {
    final store = SemanticSnapshotPanelEventStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    final now = DateTime.now().toUtc();
    final event = SemanticSnapshotPanelEvent(
      target: SemanticSnapshotPanelEventTarget.refactor,
      kind: SemanticSnapshotTelemetryEventKind.renameSafety,
      documentId: 'src/main.styio',
      message: 'Rename is safe.',
      payload: <String, Object?>{'newName': 'nextName'},
      timestamp: now,
    );

    final state = await store.recordEvent(workspaceId: 'demo', event: event);
    final restored = await store.readState(
      workspaceId: 'demo',
      target: SemanticSnapshotPanelEventTarget.refactor,
    );

    expect(state.revision, 1);
    expect(restored.events.single.payload['newName'], 'nextName');
    expect(restored.toJson()['target'], 'refactor');
    expect(
      await store.clearState(
        workspaceId: 'demo',
        target: SemanticSnapshotPanelEventTarget.refactor,
      ),
      isTrue,
    );
    expect(
      (await store.readState(
        workspaceId: 'demo',
        target: SemanticSnapshotPanelEventTarget.refactor,
      )).events,
      isEmpty,
    );
  });

  test(
    'semantic snapshot panel event store applies retention policy',
    () async {
      final store = SemanticSnapshotPanelEventStore.fromDataStore(
        dataStore: await _createDataStore(),
        retentionPolicy: const SemanticSnapshotPanelEventRetentionPolicy(
          maxEventsPerTarget: 2,
          maxEventAge: Duration(days: 1),
        ),
      );

      Future<SemanticSnapshotPanelEventState> record(
        String message,
        DateTime timestamp,
      ) {
        return store.recordEvent(
          workspaceId: 'demo',
          event: SemanticSnapshotPanelEvent(
            target: SemanticSnapshotPanelEventTarget.problems,
            kind: SemanticSnapshotTelemetryEventKind.codeActionApply,
            documentId: 'src/main.styio',
            message: message,
            payload: const <String, Object?>{'status': 'applied'},
            timestamp: timestamp,
          ),
        );
      }

      final now = DateTime.now().toUtc();
      await record('old event', now.subtract(const Duration(days: 2)));
      await record('new event 1', now.subtract(const Duration(hours: 2)));
      await record('new event 2', now.subtract(const Duration(hours: 1)));
      final state = await record('new event 3', now);
      final restored = await store.readState(
        workspaceId: 'demo',
        target: SemanticSnapshotPanelEventTarget.problems,
      );

      expect(state.events, hasLength(2));
      expect(state.events.first.message, 'new event 3');
      expect(state.events.last.message, 'new event 2');
      expect(restored.events.map((event) => event.message), <String>[
        'new event 3',
        'new event 2',
      ]);
      expect(store.retentionPolicy.toJson()['maxEventsPerTarget'], 2);
    },
  );
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_semantic_panel_event_test_',
  );
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
