import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:styio_ide/src/view_ide/runtime/runtime.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/semantic_telemetry_controller.dart';

void main() {
  test('diagnostic action records typed runtime and panel evidence', () async {
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    final panelState = SemanticSnapshotPanelEventStateController();
    final controller = SemanticTelemetryController(
      panelStateController: panelState,
      panelEventStore: null,
      panelWorkspaceId: 'workspace',
      quickFixTelemetryStore: null,
      quickFixWorkspaceId: 'workspace',
      runtimeOutputBuffer: buffer,
      activeDocumentPath: () => 'main.styio',
      log: (_) {},
    );
    addTearDown(controller.dispose);

    controller.publishDiagnosticAction(
      action: 'previewQuickFix',
      succeeded: true,
      message: 'Preview collected.',
      metadata: const <String, Object?>{'scope': 'workspace'},
    );
    await Future<void>.delayed(Duration.zero);

    final event = buffer.snapshot.events.single;
    expect(event.channelId, 'diagnostics.activity');
    expect(event.kind, RuntimeOutputChannelKind.languageService);
    expect(event.metadata['activeDocumentPath'], 'main.styio');
    expect(event.metadata['succeeded'], isTrue);
    final panelEvent = panelState
        .stateFor(SemanticSnapshotPanelEventTarget.problems)
        .events
        .single;
    expect(
      panelEvent.kind,
      SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
    );
    expect(panelEvent.documentId, 'main.styio');
  });

  test(
    'semantic token counts are emitted as typed language evidence',
    () async {
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final panelState = SemanticSnapshotPanelEventStateController();
      final controller = SemanticTelemetryController(
        panelStateController: panelState,
        panelEventStore: null,
        panelWorkspaceId: 'workspace',
        quickFixTelemetryStore: null,
        quickFixWorkspaceId: 'workspace',
        runtimeOutputBuffer: buffer,
        activeDocumentPath: () => 'main.styio',
        log: (_) {},
      );
      addTearDown(controller.dispose);

      controller.recordSemanticTokens(
        documentId: 'main.styio',
        semanticSpanCount: 4,
        semanticBlockCount: 2,
        documentSymbolCount: 1,
        inlayHintCount: 3,
        diagnosticCount: 0,
      );
      await Future<void>.delayed(Duration.zero);

      final event = buffer.snapshot.events.single;
      expect(event.kind, RuntimeOutputChannelKind.languageService);
      final payload = event.metadata['payload']! as Map<String, Object?>;
      expect(payload['semanticSpanCount'], 4);
      expect(payload['semanticBlockCount'], 2);
      expect(payload['source'], 'editor-analysis');
    },
  );
}
