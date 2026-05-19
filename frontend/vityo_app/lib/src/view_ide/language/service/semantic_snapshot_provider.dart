import '../../editor/document_state.dart';
import 'language_service_foundation.dart';
import 'styio_language_service.dart';

enum SemanticSnapshotProviderSource { serviceAnalysis, localBuilderFallback }

extension SemanticSnapshotProviderSourceX on SemanticSnapshotProviderSource {
  String get wireValue {
    return switch (this) {
      SemanticSnapshotProviderSource.serviceAnalysis => 'service-analysis',
      SemanticSnapshotProviderSource.localBuilderFallback =>
        'local-builder-fallback',
    };
  }
}

class SemanticSnapshotProviderResult {
  const SemanticSnapshotProviderResult({
    required this.snapshot,
    required this.source,
    required this.message,
  });

  final SemanticSnapshot snapshot;
  final SemanticSnapshotProviderSource source;
  final String message;

  bool get usedFallback =>
      source == SemanticSnapshotProviderSource.localBuilderFallback;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': snapshot.documentId,
      'revision': snapshot.revision,
      'source': source.wireValue,
      'message': message,
      'tokenCount': snapshot.tokens.length,
      'elementCount': snapshot.elements.length,
      'referenceCount': snapshot.references.length,
      'usedFallback': usedFallback,
    };
  }
}

class SemanticSnapshotProvider {
  const SemanticSnapshotProvider({
    required this.languageService,
    this.fallbackBuilder = const SemanticSnapshotBuilder(),
    this.allowLocalBuilderFallback = true,
  });

  final StyioLanguageService languageService;
  final SemanticSnapshotBuilder fallbackBuilder;
  final bool allowLocalBuilderFallback;

  SemanticSnapshotProviderResult snapshotFor(DocumentState document) {
    final serviceSnapshot = languageService.semanticSnapshot(document);
    if (!_shouldUseFallback(document, serviceSnapshot)) {
      return SemanticSnapshotProviderResult(
        snapshot: serviceSnapshot,
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        message: 'Semantic snapshot produced from StyioService analysis facts.',
      );
    }

    final fallbackSnapshot = _tryBuildFallback(document);
    if (fallbackSnapshot == null || !_hasSemanticFacts(fallbackSnapshot)) {
      return SemanticSnapshotProviderResult(
        snapshot: serviceSnapshot,
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        message:
            'Semantic snapshot kept service analysis facts; local fallback produced no additional semantic facts.',
      );
    }

    return SemanticSnapshotProviderResult(
      snapshot: fallbackSnapshot,
      source: SemanticSnapshotProviderSource.localBuilderFallback,
      message:
          'TODO: replace local semantic snapshot fallback once StyioService emits complete symbol and reference facts.',
    );
  }

  bool _shouldUseFallback(DocumentState document, SemanticSnapshot snapshot) {
    return allowLocalBuilderFallback &&
        document.text.trim().isNotEmpty &&
        !_hasSemanticFacts(snapshot);
  }

  SemanticSnapshot? _tryBuildFallback(DocumentState document) {
    try {
      return fallbackBuilder.build(document);
    } on Object {
      return null;
    }
  }

  bool _hasSemanticFacts(SemanticSnapshot snapshot) {
    return snapshot.elements.isNotEmpty || snapshot.references.isNotEmpty;
  }
}
