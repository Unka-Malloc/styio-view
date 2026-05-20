import 'package:flutter_test/flutter_test.dart';
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
}
