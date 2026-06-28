import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/diagnostic_revision_gate.dart';
import 'package:vityo_app/src/view_ide/language/service/language_analysis_scheduler.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_service.dart';

void main() {
  const document = DocumentState(
    documentId: 'fixture://scheduler',
    text: '#main := () => {\n  value := 1\n  value\n}\n',
    revision: 1,
  );

  test('returns revision-bound metadata for smart diagnostics', () async {
    final service = _CountingLanguageService();
    final scheduler = LanguageAnalysisScheduler(
      smartService: service,
      fallbackService: _CountingLanguageService(),
      defaultDebounce: Duration.zero,
    );

    final result = await scheduler.diagnostics(
      document,
      range: const SourceRange(start: 0, end: 8),
      debounce: Duration.zero,
    );

    expect(result.documentId, document.documentId);
    expect(result.revision, document.revision);
    expect(result.range.start, 0);
    expect(result.range.end, 8);
    expect(result.analysisMode, LanguageAnalysisMode.smart);
    expect(result.isPartial, isTrue);
    expect(result.value.single.code, 'counted.1');
    expect(service.analyzeCount, 1);
  });

  test('debounces and marks superseded pending requests stale', () async {
    final smartService = _CompletionLanguageService('smart');
    final scheduler = LanguageAnalysisScheduler(
      smartService: smartService,
      fallbackService: _CompletionLanguageService('fallback'),
      defaultDebounce: const Duration(milliseconds: 50),
    );
    final nextDocument = document.replaceRange(
      start: document.length,
      end: document.length,
      replacement: 'next := value\n',
    );

    final first = scheduler.completeAt(document, 1);
    final second = scheduler.completeAt(
      nextDocument,
      1,
      debounce: Duration.zero,
    );

    final firstResult = await first;
    final secondResult = await second;

    expect(firstResult.status, LanguageAnalysisResultStatus.stale);
    expect(firstResult.isPartial, isTrue);
    expect(secondResult.status, LanguageAnalysisResultStatus.completed);
    expect(secondResult.value.single.label, 'smart');
    expect(smartService.completionCount, 1);
    expect(scheduler.generationFor(document.documentId), 2);
  });

  test('discards running stale analysis after a newer revision', () async {
    final backend = _CompleterAnalysisBackend();
    final scheduler = LanguageAnalysisScheduler(
      smartService: _CountingLanguageService(),
      fallbackService: _CountingLanguageService(),
      backend: backend,
      defaultDebounce: Duration.zero,
      defaultTimeout: const Duration(seconds: 5),
    );
    final nextDocument = document.replaceRange(
      start: document.length,
      end: document.length,
      replacement: 'next := value\n',
    );

    final first = scheduler.analyzeDocument(document, debounce: Duration.zero);
    await _pumpAsync();
    expect(backend.pending, hasLength(1));

    final second = scheduler.analyzeDocument(
      nextDocument,
      debounce: Duration.zero,
    );
    await _pumpAsync();
    expect(backend.pending, hasLength(2));

    backend.completePendingAt(0, document, code: 'stale.analysis');
    final firstResult = await first;
    backend.completePendingAt(1, nextDocument, code: 'fresh.analysis');
    final secondResult = await second;

    expect(firstResult.status, LanguageAnalysisResultStatus.stale);
    expect(firstResult.value.diagnostics, isEmpty);
    expect(secondResult.status, LanguageAnalysisResultStatus.completed);
    expect(secondResult.value.diagnostics.single.code, 'fresh.analysis');
  });

  test('cancels pending debounced document analysis', () async {
    final scheduler = LanguageAnalysisScheduler(
      smartService: _CountingLanguageService(),
      defaultDebounce: const Duration(seconds: 1),
    );

    final pending = scheduler.hoverAt(document, 1);
    final cancelled = scheduler.cancelDocument(document.documentId);
    final result = await pending;

    expect(cancelled, isTrue);
    expect(result.status, LanguageAnalysisResultStatus.cancelled);
    expect(result.documentId, document.documentId);
    expect(result.revision, document.revision);
  });

  test('cancels running document analysis by generation', () async {
    final backend = _CompleterAnalysisBackend();
    final scheduler = LanguageAnalysisScheduler(
      smartService: _CountingLanguageService(),
      fallbackService: _CountingLanguageService(),
      backend: backend,
      defaultDebounce: Duration.zero,
      defaultTimeout: const Duration(seconds: 5),
    );

    final pending = scheduler.analyzeDocument(
      document,
      debounce: Duration.zero,
    );
    await _pumpAsync();
    final cancelled = scheduler.cancelDocument(document.documentId);
    backend.completePendingAt(0, document, code: 'cancelled.analysis');
    final result = await pending;

    expect(cancelled, isTrue);
    expect(result.status, LanguageAnalysisResultStatus.cancelled);
    expect(result.value.diagnostics, isEmpty);
  });

  test('uses dumb fallback with typed indexUnavailable gap', () async {
    final smartService = _CompletionLanguageService('smart');
    final fallbackService = _CompletionLanguageService('fallback');
    final scheduler = LanguageAnalysisScheduler(
      smartService: smartService,
      fallbackService: fallbackService,
      defaultDebounce: Duration.zero,
    )..enterDumbMode(reason: 'semantic index warming');

    final result = await scheduler.completeAt(
      document,
      1,
      debounce: Duration.zero,
    );

    expect(result.analysisMode, LanguageAnalysisMode.dumb);
    expect(result.isPartial, isTrue);
    expect(result.value.single.label, 'fallback');
    expect(smartService.completionCount, 0);
    expect(fallbackService.completionCount, 1);
    expect(
      result.capabilityGaps.single.reason,
      CapabilityGapReason.indexUnavailable,
    );
    expect(result.toJson()['analysisMode'], 'dumb');
  });

  test('falls back on timeout with typed timeout gap', () async {
    final fallbackService = _CompletionLanguageService('fallback');
    final scheduler = LanguageAnalysisScheduler(
      smartService: _HangingLanguageService(),
      fallbackService: fallbackService,
      backend: const _HangingSmartBackend(),
      defaultDebounce: Duration.zero,
      defaultTimeout: const Duration(milliseconds: 1),
    );

    final result = await scheduler.completeAt(
      document,
      1,
      debounce: Duration.zero,
    );

    expect(result.status, LanguageAnalysisResultStatus.timeout);
    expect(result.analysisMode, LanguageAnalysisMode.dumb);
    expect(result.value.single.label, 'fallback');
    expect(result.capabilityGaps.single.reason, CapabilityGapReason.timeout);
    expect(fallbackService.completionCount, 1);
  });

  test('conservative incremental cache reuses exact revisions', () async {
    final cache = LanguageIncrementalAnalysisCache();
    final service = _CountingLanguageService();

    final first = await cache.resolve(
      document: document,
      analyze: () => service.analyzeDocument(document),
    );
    final second = await cache.resolve(
      document: document,
      analyze: () => service.analyzeDocument(document),
    );
    final invalidation = cache.applyChange(
      const LanguageDocumentChange(
        documentId: 'fixture://scheduler',
        baseRevision: 1,
        resultRevision: 2,
        replacedRange: SourceRange(start: 0, end: 0),
        replacementText: '// ',
      ),
    );
    final nextDocument = document.replaceRange(
      start: 0,
      end: 0,
      replacement: '// ',
    );
    final third = await cache.resolve(
      document: nextDocument,
      analyze: () => service.analyzeDocument(nextDocument),
    );

    expect(first.tokenSpans, isNotEmpty);
    expect(first.reuse, LanguageIncrementalReuse.none);
    expect(second.reuse, LanguageIncrementalReuse.exactRevision);
    expect(invalidation.requiresFullReparse, isTrue);
    expect(third.reuse, LanguageIncrementalReuse.conservativeReparse);
    expect(service.analyzeCount, 2);
  });
}

Future<void> _pumpAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _CountingLanguageService extends LocalStyioLanguageService {
  var analyzeCount = 0;

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    analyzeCount += 1;
    final base = super.analyzeDocument(document);
    return _analysisWithDiagnostic(
      document,
      base: base,
      code: 'counted.$analyzeCount',
    );
  }
}

class _CompletionLanguageService extends LocalStyioLanguageService {
  _CompletionLanguageService(this.label);

  final String label;
  var completionCount = 0;

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    completionCount += 1;
    return <CompletionItem>[
      CompletionItem(
        label: label,
        kind: CompletionItemKind.variable,
        insertText: label,
      ),
    ];
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    return HoverPayload(
      range: SourceRange(start: offset, end: offset),
      markdown: label,
    );
  }
}

class _HangingLanguageService extends LocalStyioLanguageService {}

class _HangingSmartBackend extends StyioLanguageServiceAnalysisBackend {
  const _HangingSmartBackend();

  @override
  FutureOr<List<CompletionItem>> completeAt(
    StyioLanguageService service,
    DocumentState document,
    int offset,
  ) {
    if (service is _HangingLanguageService) {
      return Completer<List<CompletionItem>>().future;
    }
    return super.completeAt(service, document, offset);
  }
}

class _CompleterAnalysisBackend extends StyioLanguageServiceAnalysisBackend {
  final List<Completer<StyioDocumentAnalysis>> pending =
      <Completer<StyioDocumentAnalysis>>[];

  @override
  Future<StyioDocumentAnalysis> analyzeDocument(
    StyioLanguageService service,
    DocumentState document,
  ) {
    final completer = Completer<StyioDocumentAnalysis>();
    pending.add(completer);
    return completer.future;
  }

  void completePendingAt(
    int index,
    DocumentState document, {
    required String code,
  }) {
    pending[index].complete(_analysisWithDiagnostic(document, code: code));
  }
}

StyioDocumentAnalysis _analysisWithDiagnostic(
  DocumentState document, {
  StyioDocumentAnalysis? base,
  required String code,
}) {
  final safeEnd = document.length < 8 ? document.length : 8;
  return StyioDocumentAnalysis(
    tokenSpans: base?.tokenSpans ?? const <TokenSpan>[],
    semanticSpans: base?.semanticSpans ?? const <SemanticSpan>[],
    diagnostics: <Diagnostic>[
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: code,
        message: code,
        range: SourceRange(start: 0, end: safeEnd),
      ),
    ],
    formattingEdits: base?.formattingEdits ?? const <FormattingEdit>[],
    semanticBlocks: base?.semanticBlocks ?? const <SemanticBlockRange>[],
    inlayHints: base?.inlayHints ?? const <InlayHint>[],
    documentSymbols: base?.documentSymbols ?? const <DocumentSymbol>[],
    referenceSpans: base?.referenceSpans ?? const <ReferenceSpan>[],
  );
}
