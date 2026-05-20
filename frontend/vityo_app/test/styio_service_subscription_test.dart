import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_subscription.dart';

void main() {
  test(
    'StyioService subscription analyzes document streams into cache events',
    () async {
      const document = DocumentState(
        documentId: 'fixture://streamed',
        text: 'value := 1\n',
        revision: 7,
      );
      final cache = StyioServiceResultCache();
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
          diagnostics: const <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'styio.demo',
              message: 'demo warning',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
          semanticSpans: const <SemanticSpan>[
            SemanticSpan(
              kind: SemanticKind.variable,
              range: SourceRange(start: 0, end: 5),
            ),
          ],
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(
          connector: connector,
          resultCache: cache,
        ),
      );
      addTearDown(controller.dispose);
      final documents = StreamController<DocumentState>();
      addTearDown(documents.close);
      controller.bindDocumentStream(documents.stream);

      documents.add(document);
      final event = await controller.events.firstWhere(
        (event) => event.kind == StyioServiceSubscriptionEventKind.analyzed,
      );

      expect(event.analyzed, isTrue);
      expect(event.cachedResponseStored, isTrue);
      expect(event.report?.serviceSucceeded, isTrue);
      expect(event.semanticPanelEvents(), hasLength(2));
      expect(event.toJson()['semanticPanelEventCount'], 2);
      expect(
        cache.lookupDocument(
          documentId: document.documentId,
          revision: document.revision,
          protocolVersion: 'styio-cli-jsonl-v1',
        ),
        isNotNull,
      );
    },
  );

  test(
    'StyioService subscription marks superseded responses as stale',
    () async {
      const firstDocument = DocumentState(
        documentId: 'fixture://stale',
        text: 'first := 1\n',
        revision: 1,
      );
      const secondDocument = DocumentState(
        documentId: 'fixture://stale',
        text: 'second := 2\n',
        revision: 2,
      );
      final connector = _CompleterStyioServiceConnector();
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);

      final first = controller.refresh(firstDocument);
      await Future<void>.delayed(Duration.zero);
      final second = controller.refresh(secondDocument);
      await Future<void>.delayed(Duration.zero);

      connector.completeAt(0);
      final stale = await first;
      connector.completeAt(1);
      final analyzed = await second;

      expect(stale.kind, StyioServiceSubscriptionEventKind.stale);
      expect(stale.revision, 1);
      expect(analyzed.kind, StyioServiceSubscriptionEventKind.analyzed);
      expect(analyzed.revision, 2);
      expect(controller.generation, 2);
    },
  );

  test(
    'StyioService subscription cancellation stops document stream intake',
    () async {
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);
      final documents = StreamController<DocumentState>();
      addTearDown(documents.close);
      controller.bindDocumentStream(documents.stream);

      final event = await controller.cancel();

      expect(event.kind, StyioServiceSubscriptionEventKind.cancelled);
      expect(controller.listening, isFalse);
    },
  );
}

typedef _StyioServiceResponseFactory =
    StyioServiceResponse Function(StyioServiceDocument request);

class _FactoryStyioServiceConnector implements StyioServiceConnector {
  const _FactoryStyioServiceConnector(this.factory);

  final _StyioServiceResponseFactory factory;

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    return factory(document);
  }
}

class _CompleterStyioServiceConnector implements StyioServiceConnector {
  final List<_PendingStyioServiceRequest> pending =
      <_PendingStyioServiceRequest>[];

  @override
  Future<StyioServiceResponse> analyzeDocument(StyioServiceDocument document) {
    final completer = Completer<StyioServiceResponse>();
    pending.add(_PendingStyioServiceRequest(document, completer));
    return completer.future;
  }

  void completeAt(int index) {
    final request = pending[index].document;
    pending[index].completer.complete(
      StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: request.documentId,
        revision: request.revision,
      ),
    );
  }
}

class _PendingStyioServiceRequest {
  const _PendingStyioServiceRequest(this.document, this.completer);

  final StyioServiceDocument document;
  final Completer<StyioServiceResponse> completer;
}
