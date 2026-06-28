import 'dart:async';

import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../diagnostics/diagnostic_revision_gate.dart';
import 'language_service_foundation.dart';
import 'local_styio_language_service.dart';
import 'styio_language_service.dart';

enum LanguageAnalysisMode { smart, dumb }

enum LanguageAnalysisResultStatus {
  completed,
  partial,
  stale,
  cancelled,
  timeout,
  failed,
}

enum LanguageAnalysisFeature { analysis, diagnostics, completion, hover }

typedef LanguageAnalysisResolver<T> =
    FutureOr<T> Function(
      StyioLanguageService service,
      LanguageAnalysisMode mode,
    );

extension LanguageAnalysisFeatureX on LanguageAnalysisFeature {
  String get capabilityId {
    return switch (this) {
      LanguageAnalysisFeature.analysis => 'language.analysis',
      LanguageAnalysisFeature.diagnostics => 'language.diagnostics',
      LanguageAnalysisFeature.completion => 'language.completion',
      LanguageAnalysisFeature.hover => 'language.hover',
    };
  }
}

class LanguageAnalysisResult<T> {
  const LanguageAnalysisResult({
    required this.value,
    required this.documentId,
    required this.revision,
    required this.range,
    required this.analysisMode,
    required this.isPartial,
    required this.generation,
    this.status = LanguageAnalysisResultStatus.completed,
    this.capabilityGaps = const <LanguageCapabilityGap>[],
  });

  final T value;
  final String documentId;
  final int revision;
  final SourceRange range;
  final LanguageAnalysisMode analysisMode;
  final bool isPartial;
  final int generation;
  final LanguageAnalysisResultStatus status;
  final List<LanguageCapabilityGap> capabilityGaps;

  bool get completed => status == LanguageAnalysisResultStatus.completed;
  bool get stale => status == LanguageAnalysisResultStatus.stale;
  bool get cancelled => status == LanguageAnalysisResultStatus.cancelled;
  bool get hasCapabilityGap => capabilityGaps.isNotEmpty;

  LanguageAnalysisResult<R> withValue<R>(R nextValue) {
    return LanguageAnalysisResult<R>(
      value: nextValue,
      documentId: documentId,
      revision: revision,
      range: range,
      analysisMode: analysisMode,
      isPartial: isPartial,
      generation: generation,
      status: status,
      capabilityGaps: capabilityGaps,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'range': <String, int>{'start': range.start, 'end': range.end},
      'analysisMode': analysisMode.name,
      'isPartial': isPartial,
      'generation': generation,
      'status': status.name,
      'capabilityGaps': capabilityGaps
          .map((gap) => gap.toJson())
          .toList(growable: false),
    };
  }
}

abstract class LanguageAnalysisBackend {
  const LanguageAnalysisBackend();

  FutureOr<StyioDocumentAnalysis> analyzeDocument(
    StyioLanguageService service,
    DocumentState document,
  );

  FutureOr<List<Diagnostic>> diagnostics(
    StyioLanguageService service,
    DocumentState document,
  );

  FutureOr<List<CompletionItem>> completeAt(
    StyioLanguageService service,
    DocumentState document,
    int offset,
  );

  FutureOr<HoverPayload?> hoverAt(
    StyioLanguageService service,
    DocumentState document,
    int offset,
  );
}

class StyioLanguageServiceAnalysisBackend implements LanguageAnalysisBackend {
  const StyioLanguageServiceAnalysisBackend();

  @override
  FutureOr<StyioDocumentAnalysis> analyzeDocument(
    StyioLanguageService service,
    DocumentState document,
  ) {
    return service.analyzeDocument(document);
  }

  @override
  Future<List<Diagnostic>> diagnostics(
    StyioLanguageService service,
    DocumentState document,
  ) async {
    final analysis = await analyzeDocument(service, document);
    return analysis.diagnostics;
  }

  @override
  FutureOr<List<CompletionItem>> completeAt(
    StyioLanguageService service,
    DocumentState document,
    int offset,
  ) {
    return service.completeAt(document, offset);
  }

  @override
  FutureOr<HoverPayload?> hoverAt(
    StyioLanguageService service,
    DocumentState document,
    int offset,
  ) {
    return service.hoverAt(document, offset);
  }
}

enum LanguageIncrementalReuse { none, exactRevision, conservativeReparse }

class LanguageDocumentChange {
  const LanguageDocumentChange({
    required this.documentId,
    required this.baseRevision,
    required this.resultRevision,
    required this.replacedRange,
    required this.replacementText,
  });

  final String documentId;
  final int baseRevision;
  final int resultRevision;
  final SourceRange replacedRange;
  final String replacementText;
}

class LanguageIncrementalInvalidation {
  const LanguageIncrementalInvalidation({
    required this.documentId,
    required this.baseRevision,
    required this.resultRevision,
    required this.replacedRange,
    this.reuse = LanguageIncrementalReuse.conservativeReparse,
  });

  final String documentId;
  final int baseRevision;
  final int resultRevision;
  final SourceRange replacedRange;
  final LanguageIncrementalReuse reuse;

  bool get requiresFullReparse =>
      reuse == LanguageIncrementalReuse.conservativeReparse;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'baseRevision': baseRevision,
      'resultRevision': resultRevision,
      'range': <String, int>{
        'start': replacedRange.start,
        'end': replacedRange.end,
      },
      'reuse': reuse.name,
      'requiresFullReparse': requiresFullReparse,
    };
  }
}

class LanguageCachedDocumentFacts {
  const LanguageCachedDocumentFacts({
    required this.documentId,
    required this.revision,
    required this.ownerId,
    required this.sourceText,
    required this.analysis,
    required this.tokenSpans,
    required this.semanticSnapshot,
    required this.reuse,
    required this.producedAt,
  });

  final String documentId;
  final int revision;
  final String ownerId;
  final String sourceText;
  final StyioDocumentAnalysis analysis;
  final List<TokenSpan> tokenSpans;
  final SemanticSnapshot semanticSnapshot;
  final LanguageIncrementalReuse reuse;
  final DateTime producedAt;

  bool isFreshFor(DocumentState document, {String ownerId = 'default'}) {
    return documentId == document.documentId &&
        revision == document.revision &&
        this.ownerId == ownerId &&
        sourceText == document.text;
  }

  LanguageCachedDocumentFacts asExactRevisionHit() {
    return LanguageCachedDocumentFacts(
      documentId: documentId,
      revision: revision,
      ownerId: ownerId,
      sourceText: sourceText,
      analysis: analysis,
      tokenSpans: tokenSpans,
      semanticSnapshot: semanticSnapshot,
      reuse: LanguageIncrementalReuse.exactRevision,
      producedAt: producedAt,
    );
  }
}

class LanguageIncrementalAnalysisCache {
  final Map<String, LanguageCachedDocumentFacts> _entries =
      <String, LanguageCachedDocumentFacts>{};
  final Map<String, LanguageIncrementalInvalidation> _pendingInvalidations =
      <String, LanguageIncrementalInvalidation>{};

  int get size => _entries.length;

  LanguageCachedDocumentFacts? lookup(
    DocumentState document, {
    String ownerId = 'default',
  }) {
    final entry = _entries[_cacheKey(document.documentId, ownerId)];
    if (entry == null || !entry.isFreshFor(document, ownerId: ownerId)) {
      return null;
    }
    return entry.asExactRevisionHit();
  }

  LanguageCachedDocumentFacts store({
    required DocumentState document,
    required StyioDocumentAnalysis analysis,
    String ownerId = 'default',
    DateTime? producedAt,
  }) {
    final reuse =
        _pendingInvalidations.remove(document.documentId)?.reuse ??
        LanguageIncrementalReuse.none;
    final entry = LanguageCachedDocumentFacts(
      documentId: document.documentId,
      revision: document.revision,
      ownerId: ownerId,
      sourceText: document.text,
      analysis: analysis,
      tokenSpans: List.unmodifiable(analysis.tokenSpans),
      semanticSnapshot: SemanticSnapshot.fromAnalysis(
        document: document,
        analysis: analysis,
      ),
      reuse: reuse,
      producedAt: producedAt ?? DateTime.now().toUtc(),
    );
    _entries[_cacheKey(document.documentId, ownerId)] = entry;
    return entry;
  }

  Future<LanguageCachedDocumentFacts> resolve({
    required DocumentState document,
    required FutureOr<StyioDocumentAnalysis> Function() analyze,
    String ownerId = 'default',
  }) async {
    final cached = lookup(document, ownerId: ownerId);
    if (cached != null) {
      return cached;
    }
    final analysis = await analyze();
    return store(document: document, analysis: analysis, ownerId: ownerId);
  }

  LanguageIncrementalInvalidation applyChange(LanguageDocumentChange change) {
    invalidateDocument(change.documentId);
    final invalidation = LanguageIncrementalInvalidation(
      documentId: change.documentId,
      baseRevision: change.baseRevision,
      resultRevision: change.resultRevision,
      replacedRange: change.replacedRange,
    );
    _pendingInvalidations[change.documentId] = invalidation;
    return invalidation;
  }

  int invalidateDocument(String documentId) {
    final before = _entries.length;
    _entries.removeWhere((key, entry) => entry.documentId == documentId);
    return before - _entries.length;
  }

  void clear() {
    _entries.clear();
    _pendingInvalidations.clear();
  }

  String _cacheKey(String documentId, String ownerId) {
    return '$ownerId::$documentId';
  }
}

class LanguageAnalysisScheduler {
  LanguageAnalysisScheduler({
    required this.smartService,
    StyioLanguageService? fallbackService,
    this.backend = const StyioLanguageServiceAnalysisBackend(),
    LanguageIncrementalAnalysisCache? incrementalCache,
    this.defaultDebounce = const Duration(milliseconds: 75),
    this.defaultTimeout = const Duration(seconds: 2),
    LanguageAnalysisMode initialMode = LanguageAnalysisMode.smart,
    String dumbModeReason = 'Language index is unavailable.',
  }) : fallbackService = fallbackService ?? const LocalStyioLanguageService(),
       incrementalCache =
           incrementalCache ?? LanguageIncrementalAnalysisCache(),
       _mode = initialMode,
       _dumbModeReason = dumbModeReason;

  final StyioLanguageService smartService;
  final StyioLanguageService fallbackService;
  final LanguageAnalysisBackend backend;
  final LanguageIncrementalAnalysisCache incrementalCache;
  final Duration defaultDebounce;
  final Duration defaultTimeout;

  final Map<String, _LanguageDocumentScheduleState> _states =
      <String, _LanguageDocumentScheduleState>{};
  LanguageAnalysisMode _mode;
  String _dumbModeReason;
  var _disposed = false;

  LanguageAnalysisMode get mode => _mode;
  bool get disposed => _disposed;

  void enterSmartMode() {
    _ensureActive();
    _mode = LanguageAnalysisMode.smart;
    _dumbModeReason = '';
  }

  void enterDumbMode({String reason = 'Language index is unavailable.'}) {
    _ensureActive();
    _mode = LanguageAnalysisMode.dumb;
    _dumbModeReason = reason;
  }

  int generationFor(String documentId) {
    return _states[documentId]?.generation ?? 0;
  }

  Future<LanguageAnalysisResult<StyioDocumentAnalysis>> analyzeDocument(
    DocumentState document, {
    SourceRange? range,
    Duration? debounce,
    Duration? timeout,
    bool partial = false,
  }) {
    final normalizedRange = _normalizeRange(document, range);
    return _schedule<StyioDocumentAnalysis>(
      document: document,
      feature: LanguageAnalysisFeature.analysis,
      range: normalizedRange,
      partial: partial || !_isFullRange(document, normalizedRange),
      debounce: debounce,
      timeout: timeout,
      resolve: (service, mode) =>
          _analyzeWithCache(service: service, document: document, mode: mode),
      emptyValue: () => emptyStyioDocumentAnalysis,
    );
  }

  Future<LanguageAnalysisResult<List<Diagnostic>>> diagnostics(
    DocumentState document, {
    SourceRange? range,
    Duration? debounce,
    Duration? timeout,
    bool partial = false,
  }) {
    final normalizedRange = _normalizeRange(document, range);
    final filterToRange = range != null;
    return _schedule<List<Diagnostic>>(
      document: document,
      feature: LanguageAnalysisFeature.diagnostics,
      range: normalizedRange,
      partial: partial || filterToRange,
      debounce: debounce,
      timeout: timeout,
      resolve: (service, mode) async {
        final analysis = await _analyzeWithCache(
          service: service,
          document: document,
          mode: mode,
        );
        if (!filterToRange) {
          return analysis.diagnostics;
        }
        return analysis.diagnostics
            .where((diagnostic) => diagnostic.range.intersects(normalizedRange))
            .toList(growable: false);
      },
      emptyValue: () => const <Diagnostic>[],
    );
  }

  Future<LanguageAnalysisResult<List<CompletionItem>>> completeAt(
    DocumentState document,
    int offset, {
    Duration? debounce,
    Duration? timeout,
  }) {
    final safeOffset = offset.clamp(0, document.length).toInt();
    return _schedule<List<CompletionItem>>(
      document: document,
      feature: LanguageAnalysisFeature.completion,
      range: SourceRange(start: safeOffset, end: safeOffset),
      debounce: debounce,
      timeout: timeout,
      resolve: (service, mode) {
        return backend.completeAt(service, document, safeOffset);
      },
      emptyValue: () => const <CompletionItem>[],
    );
  }

  Future<LanguageAnalysisResult<HoverPayload?>> hoverAt(
    DocumentState document,
    int offset, {
    Duration? debounce,
    Duration? timeout,
  }) {
    final safeOffset = offset.clamp(0, document.length).toInt();
    return _schedule<HoverPayload?>(
      document: document,
      feature: LanguageAnalysisFeature.hover,
      range: SourceRange(start: safeOffset, end: safeOffset),
      debounce: debounce,
      timeout: timeout,
      resolve: (service, mode) {
        return backend.hoverAt(service, document, safeOffset);
      },
      emptyValue: () => null,
    );
  }

  bool cancelDocument(
    String documentId, {
    String message = 'Language analysis cancelled.',
  }) {
    final state = _states[documentId];
    if (state == null) {
      return false;
    }
    if (state.generation > 0) {
      state.cancelledGenerations.add(state.generation);
    }
    state.generation += 1;
    state.debounceTimer?.cancel();
    state.debounceTimer = null;
    state.pending?.completeCancelled(message);
    state.pending = null;
    return true;
  }

  void cancelAll({String message = 'Language analysis cancelled.'}) {
    for (final documentId in _states.keys.toList(growable: false)) {
      cancelDocument(documentId, message: message);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    cancelAll(message: 'Language analysis scheduler disposed.');
    _disposed = true;
  }

  Future<StyioDocumentAnalysis> _analyzeWithCache({
    required StyioLanguageService service,
    required DocumentState document,
    required LanguageAnalysisMode mode,
  }) async {
    final ownerId = mode.name;
    final cached = incrementalCache.lookup(document, ownerId: ownerId);
    if (cached != null) {
      return cached.analysis;
    }
    final analysis = await backend.analyzeDocument(service, document);
    incrementalCache.store(
      document: document,
      analysis: analysis,
      ownerId: ownerId,
    );
    return analysis;
  }

  Future<LanguageAnalysisResult<T>> _schedule<T>({
    required DocumentState document,
    required LanguageAnalysisFeature feature,
    required SourceRange range,
    required LanguageAnalysisResolver<T> resolve,
    required T Function() emptyValue,
    Duration? debounce,
    Duration? timeout,
    bool partial = false,
  }) {
    _ensureActive();
    final state = _states.putIfAbsent(
      document.documentId,
      _LanguageDocumentScheduleState.new,
    );
    state.latestRevision = document.revision;
    state.generation += 1;
    final generation = state.generation;

    state.debounceTimer?.cancel();
    final pending = state.pending;
    if (pending != null && !pending.started) {
      pending.completeStale('Language analysis superseded before debounce.');
    }

    final operation = _PendingLanguageAnalysisOperation<T>(
      document: document,
      feature: feature,
      range: range,
      generation: generation,
      scheduledMode: _mode,
      partial: partial,
      timeout: timeout ?? defaultTimeout,
      resolve: resolve,
      emptyValue: emptyValue,
    );
    state.pending = operation;

    final effectiveDebounce = debounce ?? defaultDebounce;
    if (effectiveDebounce <= Duration.zero) {
      scheduleMicrotask(() => _runOperation(operation));
    } else {
      state.debounceTimer = Timer(effectiveDebounce, () {
        _runOperation(operation);
      });
    }

    return operation.completer.future;
  }

  Future<void> _runOperation<T>(
    _PendingLanguageAnalysisOperation<T> operation,
  ) async {
    if (operation.completer.isCompleted) {
      return;
    }
    operation.started = true;
    final state = _states[operation.document.documentId];
    if (state != null && state.pending == operation) {
      state.pending = null;
      state.debounceTimer = null;
    }
    if (_isOperationCancelled(operation)) {
      operation.completeCancelled(
        'Language analysis cancelled before execution.',
      );
      _clearOperationCancellation(operation);
      return;
    }
    if (_isOperationStale(operation)) {
      operation.completeStale('Language analysis discarded before execution.');
      return;
    }

    final result = await _executeOperation(operation);
    if (_isOperationCancelled(operation)) {
      operation.completeCancelled(
        'Language analysis cancelled before completion.',
      );
      _clearOperationCancellation(operation);
      return;
    }
    if (_isOperationStale(operation)) {
      operation.completeStale(
        'Language analysis completed after a newer request.',
      );
      return;
    }
    if (!operation.completer.isCompleted) {
      operation.completer.complete(result);
    }
  }

  Future<LanguageAnalysisResult<T>> _executeOperation<T>(
    _PendingLanguageAnalysisOperation<T> operation,
  ) async {
    if (_mode == LanguageAnalysisMode.dumb) {
      return _fallbackResult(
        operation: operation,
        status: LanguageAnalysisResultStatus.partial,
        reason: CapabilityGapReason.indexUnavailable,
        detail: _dumbModeReason.isEmpty
            ? 'Language index is unavailable.'
            : _dumbModeReason,
      );
    }

    try {
      final value = await _withTimeout<T>(
        () => operation.resolve(smartService, LanguageAnalysisMode.smart),
        operation.timeout,
      );
      return operation.result(
        value: value,
        mode: LanguageAnalysisMode.smart,
        status: operation.partial
            ? LanguageAnalysisResultStatus.partial
            : LanguageAnalysisResultStatus.completed,
        isPartial: operation.partial,
      );
    } on TimeoutException catch (error) {
      return _fallbackResult(
        operation: operation,
        status: LanguageAnalysisResultStatus.timeout,
        reason: CapabilityGapReason.timeout,
        detail: error.message ?? 'Language analysis timed out.',
      );
    } on Object catch (error) {
      return _fallbackResult(
        operation: operation,
        status: LanguageAnalysisResultStatus.partial,
        reason: CapabilityGapReason.providerError,
        detail: 'Language provider failed: $error',
      );
    }
  }

  Future<LanguageAnalysisResult<T>> _fallbackResult<T>({
    required _PendingLanguageAnalysisOperation<T> operation,
    required LanguageAnalysisResultStatus status,
    required CapabilityGapReason reason,
    required String detail,
  }) async {
    final gap = LanguageCapabilityGap(
      capabilityId: operation.feature.capabilityId,
      reason: reason,
      detail: detail,
      resolution: reason == CapabilityGapReason.indexUnavailable
          ? 'Wait for the language index to become available.'
          : 'Using local fallback result.',
    );
    try {
      final value = await _futureFrom<T>(
        () => operation.resolve(fallbackService, LanguageAnalysisMode.dumb),
      );
      return operation.result(
        value: value,
        mode: LanguageAnalysisMode.dumb,
        status: status,
        isPartial: true,
        capabilityGaps: <LanguageCapabilityGap>[gap],
      );
    } on Object catch (fallbackError) {
      return operation.result(
        value: operation.emptyValue(),
        mode: LanguageAnalysisMode.dumb,
        status: LanguageAnalysisResultStatus.failed,
        isPartial: true,
        capabilityGaps: <LanguageCapabilityGap>[
          gap,
          LanguageCapabilityGap(
            capabilityId: operation.feature.capabilityId,
            reason: CapabilityGapReason.providerError,
            detail: 'Local fallback failed: $fallbackError',
          ),
        ],
      );
    }
  }

  bool _isOperationCancelled(
    _PendingLanguageAnalysisOperation<Object?> operation,
  ) {
    return _states[operation.document.documentId]?.cancelledGenerations
            .contains(operation.generation) ??
        false;
  }

  void _clearOperationCancellation(
    _PendingLanguageAnalysisOperation<Object?> operation,
  ) {
    _states[operation.document.documentId]?.cancelledGenerations.remove(
      operation.generation,
    );
  }

  bool _isOperationStale(_PendingLanguageAnalysisOperation<Object?> operation) {
    if (_disposed) {
      return true;
    }
    final state = _states[operation.document.documentId];
    return state == null ||
        operation.generation != state.generation ||
        operation.document.revision != state.latestRevision;
  }

  Future<T> _withTimeout<T>(FutureOr<T> Function() create, Duration timeout) {
    if (timeout <= Duration.zero) {
      return Future<T>.error(
        TimeoutException('Language analysis timed out.', timeout),
      );
    }
    return _futureFrom(create).timeout(timeout);
  }

  Future<T> _futureFrom<T>(FutureOr<T> Function() create) {
    return Future<T>.delayed(Duration.zero, create);
  }

  SourceRange _normalizeRange(DocumentState document, SourceRange? range) {
    final requested = range ?? SourceRange(start: 0, end: document.length);
    final start = requested.start.clamp(0, document.length).toInt();
    final end = requested.end.clamp(start, document.length).toInt();
    return SourceRange(start: start, end: end);
  }

  bool _isFullRange(DocumentState document, SourceRange range) {
    return range.start == 0 && range.end == document.length;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('LanguageAnalysisScheduler is disposed.');
    }
  }
}

const emptyStyioDocumentAnalysis = StyioDocumentAnalysis(
  tokenSpans: <TokenSpan>[],
  semanticSpans: <SemanticSpan>[],
  diagnostics: <Diagnostic>[],
  formattingEdits: <FormattingEdit>[],
  semanticBlocks: <SemanticBlockRange>[],
  inlayHints: <InlayHint>[],
  documentSymbols: <DocumentSymbol>[],
  referenceSpans: <ReferenceSpan>[],
);

class _LanguageDocumentScheduleState {
  var generation = 0;
  var latestRevision = -1;
  Timer? debounceTimer;
  _PendingLanguageAnalysisOperation<Object?>? pending;
  final Set<int> cancelledGenerations = <int>{};
}

class _PendingLanguageAnalysisOperation<T> {
  _PendingLanguageAnalysisOperation({
    required this.document,
    required this.feature,
    required this.range,
    required this.generation,
    required this.scheduledMode,
    required this.partial,
    required this.timeout,
    required this.resolve,
    required this.emptyValue,
  });

  final DocumentState document;
  final LanguageAnalysisFeature feature;
  final SourceRange range;
  final int generation;
  final LanguageAnalysisMode scheduledMode;
  final bool partial;
  final Duration timeout;
  final LanguageAnalysisResolver<T> resolve;
  final T Function() emptyValue;
  final Completer<LanguageAnalysisResult<T>> completer =
      Completer<LanguageAnalysisResult<T>>();
  var started = false;

  LanguageAnalysisResult<T> result({
    required T value,
    required LanguageAnalysisMode mode,
    required LanguageAnalysisResultStatus status,
    required bool isPartial,
    List<LanguageCapabilityGap> capabilityGaps =
        const <LanguageCapabilityGap>[],
  }) {
    return LanguageAnalysisResult<T>(
      value: value,
      documentId: document.documentId,
      revision: document.revision,
      range: range,
      analysisMode: mode,
      isPartial: isPartial || capabilityGaps.isNotEmpty,
      generation: generation,
      status: status,
      capabilityGaps: List.unmodifiable(capabilityGaps),
    );
  }

  void completeStale(String detail) {
    if (completer.isCompleted) {
      return;
    }
    completer.complete(
      result(
        value: emptyValue(),
        mode: scheduledMode,
        status: LanguageAnalysisResultStatus.stale,
        isPartial: true,
      ),
    );
  }

  void completeCancelled(String detail) {
    if (completer.isCompleted) {
      return;
    }
    completer.complete(
      result(
        value: emptyValue(),
        mode: scheduledMode,
        status: LanguageAnalysisResultStatus.cancelled,
        isPartial: true,
      ),
    );
  }
}
