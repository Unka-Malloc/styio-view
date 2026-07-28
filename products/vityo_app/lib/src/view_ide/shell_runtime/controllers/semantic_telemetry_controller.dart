import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../language/service/semantic_snapshot_event_bridge.dart';
import '../../runtime/runtime.dart';
import '../../../ide/workspace/workspace.dart';

class SemanticTelemetryController extends ChangeNotifier {
  SemanticTelemetryController({
    required this.panelStateController,
    required this.panelEventStore,
    required this.panelWorkspaceId,
    required this.quickFixTelemetryStore,
    required this.quickFixWorkspaceId,
    required this.runtimeOutputBuffer,
    required this.activeDocumentPath,
    required this.log,
  });

  final SemanticSnapshotPanelEventStateController panelStateController;
  final SemanticSnapshotPanelEventStore? panelEventStore;
  final String panelWorkspaceId;
  final WorkspaceQuickFixTelemetryStore? quickFixTelemetryStore;
  final String quickFixWorkspaceId;
  final RuntimeOutputLiveBuffer runtimeOutputBuffer;
  final String Function() activeDocumentPath;
  final void Function(String message) log;

  WorkspaceQuickFixTelemetrySnapshot? _quickFixTelemetrySnapshot;

  WorkspaceQuickFixTelemetrySnapshot? get quickFixTelemetrySnapshot =>
      _quickFixTelemetrySnapshot;

  SemanticSnapshotPanelViewModel? panelViewModelFor(
    SemanticSnapshotPanelEventTarget target,
  ) {
    final viewModel = SemanticSnapshotPanelViewModel.fromState(
      panelStateController.stateFor(target),
    );
    return viewModel.empty ? null : viewModel;
  }

  List<SemanticSnapshotPanelViewModel> get panelViewModels {
    return <SemanticSnapshotPanelViewModel>[
      for (final target in SemanticSnapshotPanelEventTarget.values)
        if (panelViewModelFor(target) != null) panelViewModelFor(target)!,
    ];
  }

  Future<List<SemanticSnapshotPanelEventState>> restorePanelEvents({
    String? workspaceId,
  }) async {
    final store = panelEventStore;
    if (store == null) {
      log('Semantic panel event restore unavailable: no DataStore is wired.');
      return <SemanticSnapshotPanelEventState>[
        for (final target in SemanticSnapshotPanelEventTarget.values)
          panelStateController.stateFor(target),
      ];
    }
    final resolvedWorkspaceId = workspaceId ?? panelWorkspaceId;
    final states = <SemanticSnapshotPanelEventState>[];
    for (final target in SemanticSnapshotPanelEventTarget.values) {
      states.add(
        await store.readState(workspaceId: resolvedWorkspaceId, target: target),
      );
    }
    panelStateController.replaceStates(states);
    log(
      'Semantic panel events restored for $resolvedWorkspaceId: '
      '${panelViewModels.length} active panel(s).',
    );
    notifyListeners();
    return List<SemanticSnapshotPanelEventState>.unmodifiable(states);
  }

  Future<SemanticSnapshotPanelEventState> recordPanelEvent(
    SemanticSnapshotPanelEvent event, {
    String? workspaceId,
    int? maxEvents,
  }) async {
    final store = panelEventStore;
    final localMaxEvents =
        maxEvents ?? store?.retentionPolicy.maxEventsPerTarget ?? 50;
    var state = panelStateController.recordEvent(
      event,
      maxEvents: localMaxEvents,
    );
    if (store != null) {
      try {
        state = await store.recordEvent(
          workspaceId: workspaceId ?? panelWorkspaceId,
          event: event,
          maxEvents: maxEvents,
        );
        panelStateController.replaceState(state);
      } on Object catch (error) {
        log('Semantic panel event persistence failed: $error');
      }
    }
    notifyListeners();
    return state;
  }

  Future<SemanticSnapshotPanelEvent?> recordRuntimeOutputEvent(
    RuntimeOutputEvent event, {
    bool publishToRuntimeOutput = true,
  }) async {
    if (publishToRuntimeOutput) {
      runtimeOutputBuffer.addEvent(event);
    }
    final panelEvent = const SemanticSnapshotPanelEventDispatcher()
        .panelEventFor(event);
    if (panelEvent == null) {
      return null;
    }
    await recordPanelEvent(panelEvent);
    return panelEvent;
  }

  Future<WorkspaceQuickFixTelemetrySnapshot> restoreQuickFixTelemetry({
    String? workspaceId,
  }) async {
    final resolvedWorkspaceId = workspaceId ?? quickFixWorkspaceId;
    final store = quickFixTelemetryStore;
    if (store == null) {
      final snapshot = WorkspaceQuickFixTelemetrySnapshot(
        workspaceId: resolvedWorkspaceId,
      );
      _quickFixTelemetrySnapshot = snapshot;
      log(
        'Workspace quick-fix telemetry restore unavailable: no DataStore is wired.',
      );
      return snapshot;
    }
    final snapshot = await store.readSnapshot(workspaceId: resolvedWorkspaceId);
    _quickFixTelemetrySnapshot = snapshot;
    log(
      'Workspace quick-fix telemetry restored: '
      '${snapshot.outcomes.length} outcome(s).',
    );
    notifyListeners();
    return snapshot;
  }

  Future<WorkspaceQuickFixTelemetrySnapshot> recordQuickFixOutcome(
    WorkspaceQuickFixReviewOutcome outcome, {
    int maxOutcomes = 50,
  }) async {
    final resolvedWorkspaceId = outcome.workspaceId.isEmpty
        ? quickFixWorkspaceId
        : outcome.workspaceId;
    final normalizedOutcome = outcome.workspaceId == resolvedWorkspaceId
        ? outcome
        : WorkspaceQuickFixReviewOutcome(
            workspaceId: resolvedWorkspaceId,
            producerId: outcome.producerId,
            documentId: outcome.documentId,
            diagnosticCode: outcome.diagnosticCode,
            quickFixIndex: outcome.quickFixIndex,
            planId: outcome.planId,
            outcomeKind: outcome.outcomeKind,
            confirmationStatus: outcome.confirmationStatus,
            ready: outcome.ready,
            message: outcome.message,
            timestamp: outcome.timestamp,
            affectedDocumentIds: outcome.affectedDocumentIds,
            missingDocumentIds: outcome.missingDocumentIds,
          );
    final store = quickFixTelemetryStore;
    final base =
        _quickFixTelemetrySnapshot ??
        WorkspaceQuickFixTelemetrySnapshot(workspaceId: resolvedWorkspaceId);
    var snapshot = base.record(normalizedOutcome, maxOutcomes: maxOutcomes);
    if (store != null) {
      snapshot = await store.recordOutcome(
        outcome: normalizedOutcome,
        maxOutcomes: maxOutcomes,
      );
    }
    _quickFixTelemetrySnapshot = snapshot;
    notifyListeners();
    return snapshot;
  }

  void publishDiagnosticAction({
    required String action,
    required bool succeeded,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final documentPath = activeDocumentPath();
    final timestamp = DateTime.now().toUtc();
    runtimeOutputBuffer.addEvent(
      RuntimeOutputEvent(
        channelId: 'diagnostics.activity',
        label: 'Diagnostics Activity',
        kind: RuntimeOutputChannelKind.languageService,
        message: message,
        timestamp: timestamp,
        metadata: <String, Object?>{
          'action': action,
          'succeeded': succeeded,
          'activeDocumentPath': documentPath,
          ...metadata,
        },
      ),
    );
    final semanticKind = switch (action) {
      'previewQuickFix' =>
        SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
      'applyQuickFix' => SemanticSnapshotTelemetryEventKind.codeActionApply,
      _ => null,
    };
    if (semanticKind == null) {
      return;
    }
    unawaited(
      recordPanelEvent(
        SemanticSnapshotPanelEvent(
          target: SemanticSnapshotPanelEventTarget.problems,
          kind: semanticKind,
          documentId: documentPath,
          message: message,
          payload: <String, Object?>{
            'action': action,
            'succeeded': succeeded,
            ...metadata,
          },
          timestamp: timestamp,
        ),
      ),
    );
  }

  void recordWorkspaceDiagnostics({
    required WorkspaceDiagnosticsSnapshot snapshot,
    required String activeDocumentId,
    required String message,
  }) {
    unawaited(
      recordRuntimeOutputEvent(
        const SemanticSnapshotEventBridge().diagnosticsSnapshotEvent(
          documentId: activeDocumentId,
          providerId: snapshot.providerId,
          diagnosticCount: snapshot.totalCount,
          hasErrors: snapshot.hasErrors,
          severityCounts: snapshot.severityCounts,
          documentCount: snapshot.documentIds.length,
          sourceCount: snapshot.sourceGroups.length,
          timestamp: DateTime.now().toUtc(),
          message: message,
          payload: <String, Object?>{
            'source': 'workspace-diagnostics',
            'activeDocumentId': activeDocumentId,
          },
        ),
      ),
    );
  }

  void recordSemanticTokens({
    required String documentId,
    required int semanticSpanCount,
    required int semanticBlockCount,
    required int documentSymbolCount,
    required int inlayHintCount,
    required int diagnosticCount,
  }) {
    unawaited(
      recordRuntimeOutputEvent(
        const SemanticSnapshotEventBridge().semanticTokensEvent(
          documentId: documentId,
          semanticSpanCount: semanticSpanCount,
          semanticBlockCount: semanticBlockCount,
          documentSymbolCount: documentSymbolCount,
          inlayHintCount: inlayHintCount,
          diagnosticCount: diagnosticCount,
          timestamp: DateTime.now().toUtc(),
          payload: const <String, Object?>{'source': 'editor-analysis'},
        ),
      ),
    );
  }
}
