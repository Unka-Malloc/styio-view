import 'dart:async';

import '../../editor/document_state.dart';
import '../../runtime/runtime_output_channels.dart';
import 'styio_service_connector.dart';

enum StyioServiceSubscriptionEventKind {
  started,
  analyzed,
  stale,
  failed,
  cancelled,
  disposed,
}

typedef StyioServiceDocumentContextResolver =
    String? Function(DocumentState document);

class StyioServiceSubscriptionEvent {
  StyioServiceSubscriptionEvent({
    required this.kind,
    required this.documentId,
    required this.revision,
    required this.generation,
    required this.message,
    this.report,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final StyioServiceSubscriptionEventKind kind;
  final String documentId;
  final int revision;
  final int generation;
  final String message;
  final StyioServiceAnalysisReport? report;
  final DateTime emittedAt;

  bool get analyzed => kind == StyioServiceSubscriptionEventKind.analyzed;
  bool get stale => kind == StyioServiceSubscriptionEventKind.stale;
  bool get failed => kind == StyioServiceSubscriptionEventKind.failed;
  bool get cachedResponseStored => report?.cachedResponseStored ?? false;

  List<RuntimeOutputEvent> semanticPanelEvents({
    StyioServiceResponseTelemetryBridge bridge =
        const StyioServiceResponseTelemetryBridge(),
  }) {
    final response = report?.response;
    if (response == null) {
      return const <RuntimeOutputEvent>[];
    }
    return bridge.eventsForResponse(response, timestamp: emittedAt);
  }

  Map<String, Object?> toJson() {
    final response = report?.response;
    return <String, Object?>{
      'kind': kind.name,
      'documentId': documentId,
      'revision': revision,
      'generation': generation,
      'message': message,
      'cachedResponseStored': cachedResponseStored,
      'semanticPanelEventCount': semanticPanelEvents().length,
      if (response != null) 'response': response.toJson(),
      if (report?.cacheSnapshot != null)
        'cacheSnapshot': report!.cacheSnapshot!.toJson(),
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

class StyioServiceSubscriptionController {
  StyioServiceSubscriptionController({required this.driver});

  final StyioServiceAnalysisDriver driver;
  final StreamController<StyioServiceSubscriptionEvent> _events =
      StreamController<StyioServiceSubscriptionEvent>.broadcast(sync: true);

  StreamSubscription<DocumentState>? _documentSubscription;
  var _generation = 0;
  var _disposed = false;

  Stream<StyioServiceSubscriptionEvent> get events => _events.stream;
  bool get disposed => _disposed;
  bool get listening => _documentSubscription != null;
  int get generation => _generation;

  void bindDocumentStream(
    Stream<DocumentState> documents, {
    StyioServiceDocumentContextResolver? filePathForDocument,
    StyioServiceDocumentContextResolver? configPathForDocument,
    StyioServiceDocumentContextResolver? workingDirectoryForDocument,
  }) {
    _ensureActive();
    unawaited(_documentSubscription?.cancel());
    _documentSubscription = documents.listen((document) {
      unawaited(
        refresh(
          document,
          filePath: filePathForDocument?.call(document),
          configPath: configPathForDocument?.call(document),
          workingDirectory: workingDirectoryForDocument?.call(document),
        ),
      );
    });
  }

  Future<StyioServiceSubscriptionEvent> refresh(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
  }) async {
    _ensureActive();
    final generation = ++_generation;
    _emit(
      StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.started,
        documentId: document.documentId,
        revision: document.revision,
        generation: generation,
        message: 'StyioService background analysis started.',
      ),
    );
    try {
      final report = await driver.analyzeDocumentWithReport(
        document,
        filePath: filePath,
        configPath: configPath,
        workingDirectory: workingDirectory,
      );
      if (generation != _generation || _disposed) {
        return _emit(
          StyioServiceSubscriptionEvent(
            kind: StyioServiceSubscriptionEventKind.stale,
            documentId: document.documentId,
            revision: document.revision,
            generation: generation,
            report: report,
            message:
                'StyioService background analysis completed after a newer request.',
          ),
        );
      }
      return _emit(
        StyioServiceSubscriptionEvent(
          kind: StyioServiceSubscriptionEventKind.analyzed,
          documentId: document.documentId,
          revision: document.revision,
          generation: generation,
          report: report,
          message: 'StyioService background analysis completed.',
        ),
      );
    } catch (error) {
      if (generation != _generation || _disposed) {
        return _emit(
          StyioServiceSubscriptionEvent(
            kind: StyioServiceSubscriptionEventKind.stale,
            documentId: document.documentId,
            revision: document.revision,
            generation: generation,
            message:
                'StyioService background analysis failure ignored after a newer request.',
          ),
        );
      }
      return _emit(
        StyioServiceSubscriptionEvent(
          kind: StyioServiceSubscriptionEventKind.failed,
          documentId: document.documentId,
          revision: document.revision,
          generation: generation,
          message: 'StyioService background analysis failed: $error',
        ),
      );
    }
  }

  Future<StyioServiceSubscriptionEvent> cancel({
    String message = 'StyioService background subscription cancelled.',
  }) async {
    _ensureActive();
    _generation += 1;
    await _documentSubscription?.cancel();
    _documentSubscription = null;
    return _emit(
      StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.cancelled,
        documentId: '',
        revision: 0,
        generation: _generation,
        message: message,
      ),
    );
  }

  Future<StyioServiceSubscriptionEvent> dispose() async {
    if (_disposed) {
      return StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.disposed,
        documentId: '',
        revision: 0,
        generation: _generation,
        message: 'StyioService background subscription already disposed.',
      );
    }
    _generation += 1;
    await _documentSubscription?.cancel();
    _documentSubscription = null;
    _disposed = true;
    final event = _emit(
      StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.disposed,
        documentId: '',
        revision: 0,
        generation: _generation,
        message: 'StyioService background subscription disposed.',
      ),
    );
    await _events.close();
    return event;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('StyioService background subscription is disposed.');
    }
  }

  StyioServiceSubscriptionEvent _emit(StyioServiceSubscriptionEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
    return event;
  }
}
