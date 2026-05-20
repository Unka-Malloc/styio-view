import '../../editor/document_state.dart';
import 'language_service_foundation.dart';
import 'styio_language_service.dart';

enum SemanticSnapshotProviderSource { serviceAnalysis, localBuilderFallback }

enum SemanticSnapshotConsumerFeature {
  hover,
  definition,
  references,
  completion,
  semanticTokens,
  renameSafety,
  codeActions,
}

extension SemanticSnapshotProviderSourceX on SemanticSnapshotProviderSource {
  String get wireValue {
    return switch (this) {
      SemanticSnapshotProviderSource.serviceAnalysis => 'service-analysis',
      SemanticSnapshotProviderSource.localBuilderFallback =>
        'local-builder-fallback',
    };
  }
}

extension SemanticSnapshotConsumerFeatureX on SemanticSnapshotConsumerFeature {
  String get wireValue {
    return switch (this) {
      SemanticSnapshotConsumerFeature.hover => 'hover',
      SemanticSnapshotConsumerFeature.definition => 'definition',
      SemanticSnapshotConsumerFeature.references => 'references',
      SemanticSnapshotConsumerFeature.completion => 'completion',
      SemanticSnapshotConsumerFeature.semanticTokens => 'semantic-tokens',
      SemanticSnapshotConsumerFeature.renameSafety => 'rename-safety',
      SemanticSnapshotConsumerFeature.codeActions => 'code-actions',
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

  SemanticSnapshotFeatureMatrix get featureMatrix {
    return SemanticSnapshotFeatureMatrix.fromSnapshot(
      snapshot: snapshot,
      source: source,
    );
  }

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
      'featureMatrix': featureMatrix.toJson(),
    };
  }
}

class SemanticSnapshotFeatureSupport {
  const SemanticSnapshotFeatureSupport({
    required this.feature,
    required this.available,
    required this.reason,
  });

  final SemanticSnapshotConsumerFeature feature;
  final bool available;
  final String reason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'feature': feature.wireValue,
      'available': available,
      'reason': reason,
    };
  }
}

class SemanticSnapshotFeatureMatrix {
  const SemanticSnapshotFeatureMatrix({
    required this.source,
    required this.supports,
  });

  factory SemanticSnapshotFeatureMatrix.fromSnapshot({
    required SemanticSnapshot snapshot,
    required SemanticSnapshotProviderSource source,
  }) {
    final hasTokens = snapshot.tokens.isNotEmpty;
    final hasElements = snapshot.elements.isNotEmpty;
    final hasReferences = snapshot.references.isNotEmpty;
    final serviceBacked =
        source == SemanticSnapshotProviderSource.serviceAnalysis;
    return SemanticSnapshotFeatureMatrix(
      source: source,
      supports: <SemanticSnapshotFeatureSupport>[
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.hover,
          available: hasElements,
          reason: hasElements
              ? 'Resolved elements are available.'
              : 'Hover needs resolved element facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.definition,
          available: hasReferences,
          reason: hasReferences
              ? 'Resolved references are available.'
              : 'Definition needs resolved reference facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.references,
          available: hasReferences,
          reason: hasReferences
              ? 'Resolved references are available.'
              : 'Find references needs resolved reference facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.completion,
          available: hasElements,
          reason: hasElements
              ? 'Resolved elements can seed completion candidates.'
              : 'Completion needs symbols or semantic candidates.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.semanticTokens,
          available: hasTokens,
          reason: hasTokens
              ? 'Semantic or syntax token spans are available.'
              : 'Semantic highlighting needs token spans.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.renameSafety,
          available: serviceBacked && hasElements && hasReferences,
          reason: serviceBacked && hasElements && hasReferences
              ? 'StyioService-backed resolved elements and references are available.'
              : 'Rename safety must come from StyioService semantic facts.',
        ),
        const SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.codeActions,
          available: false,
          reason:
              'Code actions require StyioService raw edit facts, not just snapshot facts.',
        ),
      ],
    );
  }

  final SemanticSnapshotProviderSource source;
  final List<SemanticSnapshotFeatureSupport> supports;

  bool supportsFeature(SemanticSnapshotConsumerFeature feature) {
    for (final support in supports) {
      if (support.feature == feature) {
        return support.available;
      }
    }
    return false;
  }

  List<SemanticSnapshotConsumerFeature> get unavailableFeatures {
    return supports
        .where((support) => !support.available)
        .map((support) => support.feature)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.wireValue,
      'supports': supports
          .map((support) => support.toJson())
          .toList(growable: false),
      'unavailableFeatures': unavailableFeatures
          .map((feature) => feature.wireValue)
          .toList(growable: false),
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
