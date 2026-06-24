import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import 'language_service_foundation.dart';
import 'project_styio_language_service.dart';
import 'styio_language_service.dart';

enum SemanticSnapshotProviderSource { serviceAnalysis, localBuilderFallback }

enum SemanticSnapshotRenameSafetyScope { document, workspace }

enum SemanticSnapshotCodeActionApplyStatus {
  proposed,
  applied,
  blocked,
  failed,
}

enum SemanticSnapshotConsumerFeature {
  hover,
  definition,
  references,
  completion,
  semanticTokens,
  renameSafety,
  codeActions,
}

enum SemanticSnapshotFeatureConfidence {
  serviceBacked,
  localFallback,
  unavailable,
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

extension SemanticSnapshotRenameSafetyScopeX
    on SemanticSnapshotRenameSafetyScope {
  String get wireValue {
    return switch (this) {
      SemanticSnapshotRenameSafetyScope.document => 'document',
      SemanticSnapshotRenameSafetyScope.workspace => 'workspace',
    };
  }
}

extension SemanticSnapshotCodeActionApplyStatusX
    on SemanticSnapshotCodeActionApplyStatus {
  String get wireValue {
    return switch (this) {
      SemanticSnapshotCodeActionApplyStatus.proposed => 'proposed',
      SemanticSnapshotCodeActionApplyStatus.applied => 'applied',
      SemanticSnapshotCodeActionApplyStatus.blocked => 'blocked',
      SemanticSnapshotCodeActionApplyStatus.failed => 'failed',
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

extension SemanticSnapshotFeatureConfidenceX
    on SemanticSnapshotFeatureConfidence {
  String get wireValue {
    return switch (this) {
      SemanticSnapshotFeatureConfidence.serviceBacked => 'service-backed',
      SemanticSnapshotFeatureConfidence.localFallback => 'local-fallback',
      SemanticSnapshotFeatureConfidence.unavailable => 'unavailable',
    };
  }
}

class SemanticSnapshotProviderResult {
  const SemanticSnapshotProviderResult({
    required this.snapshot,
    required this.source,
    required this.message,
    this.codeActionFactCount = 0,
  });

  final SemanticSnapshot snapshot;
  final SemanticSnapshotProviderSource source;
  final String message;
  final int codeActionFactCount;

  bool get usedFallback =>
      source == SemanticSnapshotProviderSource.localBuilderFallback;

  SemanticSnapshotFeatureMatrix get featureMatrix {
    return SemanticSnapshotFeatureMatrix.fromSnapshot(
      snapshot: snapshot,
      source: source,
      codeActionFactCount: codeActionFactCount,
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
      'codeActionFactCount': codeActionFactCount,
      'usedFallback': usedFallback,
      'featureMatrix': featureMatrix.toJson(),
    };
  }
}

class SemanticSnapshotFeatureSupport {
  const SemanticSnapshotFeatureSupport({
    required this.feature,
    required this.available,
    required this.confidence,
    required this.reason,
  });

  final SemanticSnapshotConsumerFeature feature;
  final bool available;
  final SemanticSnapshotFeatureConfidence confidence;
  final String reason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'feature': feature.wireValue,
      'available': available,
      'confidence': confidence.wireValue,
      'reason': reason,
    };
  }
}

class SemanticSnapshotFeatureMatrix {
  const SemanticSnapshotFeatureMatrix({
    required this.source,
    required this.supports,
    this.codeActionFactCount = 0,
  });

  factory SemanticSnapshotFeatureMatrix.fromSnapshot({
    required SemanticSnapshot snapshot,
    required SemanticSnapshotProviderSource source,
    int codeActionFactCount = 0,
  }) {
    final hasTokens = snapshot.tokens.isNotEmpty;
    final hasElements = snapshot.elements.isNotEmpty;
    final hasReferences = snapshot.references.isNotEmpty;
    final serviceBacked =
        source == SemanticSnapshotProviderSource.serviceAnalysis;
    final availableConfidence = serviceBacked
        ? SemanticSnapshotFeatureConfidence.serviceBacked
        : SemanticSnapshotFeatureConfidence.localFallback;
    return SemanticSnapshotFeatureMatrix(
      source: source,
      codeActionFactCount: codeActionFactCount,
      supports: <SemanticSnapshotFeatureSupport>[
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.hover,
          available: hasElements,
          confidence: hasElements
              ? availableConfidence
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: hasElements
              ? 'Resolved elements are available.'
              : 'Hover needs resolved element facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.definition,
          available: hasReferences,
          confidence: hasReferences
              ? availableConfidence
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: hasReferences
              ? 'Resolved references are available.'
              : 'Definition needs resolved reference facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.references,
          available: hasReferences,
          confidence: hasReferences
              ? availableConfidence
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: hasReferences
              ? 'Resolved references are available.'
              : 'Find references needs resolved reference facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.completion,
          available: hasElements,
          confidence: hasElements
              ? availableConfidence
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: hasElements
              ? 'Resolved elements can seed completion candidates.'
              : 'Completion needs symbols or semantic candidates.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.semanticTokens,
          available: hasTokens,
          confidence: hasTokens
              ? availableConfidence
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: hasTokens
              ? 'Semantic or syntax token spans are available.'
              : 'Semantic highlighting needs token spans.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.renameSafety,
          available: serviceBacked && hasElements && hasReferences,
          confidence: serviceBacked && hasElements && hasReferences
              ? SemanticSnapshotFeatureConfidence.serviceBacked
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: serviceBacked && hasElements && hasReferences
              ? 'StyioService-backed resolved elements and references are available.'
              : 'Rename safety must come from StyioService semantic facts.',
        ),
        SemanticSnapshotFeatureSupport(
          feature: SemanticSnapshotConsumerFeature.codeActions,
          available: codeActionFactCount > 0,
          confidence: codeActionFactCount > 0
              ? SemanticSnapshotFeatureConfidence.serviceBacked
              : SemanticSnapshotFeatureConfidence.unavailable,
          reason: codeActionFactCount > 0
              ? 'StyioService raw edit code action facts are available.'
              : 'Code actions require StyioService raw edit facts, not just snapshot facts.',
        ),
      ],
    );
  }

  final SemanticSnapshotProviderSource source;
  final List<SemanticSnapshotFeatureSupport> supports;
  final int codeActionFactCount;

  bool supportsFeature(SemanticSnapshotConsumerFeature feature) {
    return supportFor(feature).available;
  }

  SemanticSnapshotFeatureSupport supportFor(
    SemanticSnapshotConsumerFeature feature,
  ) {
    for (final support in supports) {
      if (support.feature == feature) {
        return support;
      }
    }
    return SemanticSnapshotFeatureSupport(
      feature: feature,
      available: false,
      confidence: SemanticSnapshotFeatureConfidence.unavailable,
      reason: 'Feature is not represented in the semantic snapshot matrix.',
    );
  }

  List<SemanticSnapshotConsumerFeature> get unavailableFeatures {
    return supports
        .where((support) => !support.available)
        .map((support) => support.feature)
        .toList(growable: false);
  }

  int get availableFeatureCount {
    return supports.where((support) => support.available).length;
  }

  int get serviceBackedFeatureCount {
    return supports
        .where(
          (support) =>
              support.available &&
              support.confidence ==
                  SemanticSnapshotFeatureConfidence.serviceBacked,
        )
        .length;
  }

  int get localFallbackFeatureCount {
    return supports
        .where(
          (support) =>
              support.available &&
              support.confidence ==
                  SemanticSnapshotFeatureConfidence.localFallback,
        )
        .length;
  }

  int get unavailableFeatureCount {
    return supports.where((support) => !support.available).length;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.wireValue,
      'availableFeatureCount': availableFeatureCount,
      'serviceBackedFeatureCount': serviceBackedFeatureCount,
      'localFallbackFeatureCount': localFallbackFeatureCount,
      'unavailableFeatureCount': unavailableFeatureCount,
      'codeActionFactCount': codeActionFactCount,
      'supports': supports
          .map((support) => support.toJson())
          .toList(growable: false),
      'unavailableFeatures': unavailableFeatures
          .map((feature) => feature.wireValue)
          .toList(growable: false),
    };
  }
}

class SemanticSnapshotCodeActionFact {
  const SemanticSnapshotCodeActionFact({
    required this.id,
    required this.label,
    required this.edits,
    this.detail = '',
    this.diagnosticCode = '',
  });

  final String id;
  final String label;
  final List<FormattingEdit> edits;
  final String detail;
  final String diagnosticCode;

  bool get hasEdits => edits.isNotEmpty;

  SemanticSnapshotCodeActionApplyResult reportApplyResult({
    required SemanticSnapshotCodeActionApplyStatus status,
    required String message,
    int? appliedEditCount,
    DateTime? timestamp,
  }) {
    return SemanticSnapshotCodeActionApplyResult(
      actionId: id,
      label: label,
      diagnosticCode: diagnosticCode,
      status: status,
      editCount: edits.length,
      appliedEditCount: appliedEditCount ?? 0,
      message: message,
      timestamp: timestamp,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'detail': detail,
      'diagnosticCode': diagnosticCode,
      'hasEdits': hasEdits,
      'editCount': edits.length,
      'edits': edits.map(_formattingEditToJson).toList(growable: false),
    };
  }
}

class SemanticSnapshotCodeActionApplyResult {
  const SemanticSnapshotCodeActionApplyResult({
    required this.actionId,
    required this.label,
    required this.diagnosticCode,
    required this.status,
    required this.editCount,
    required this.appliedEditCount,
    required this.message,
    this.timestamp,
  });

  final String actionId;
  final String label;
  final String diagnosticCode;
  final SemanticSnapshotCodeActionApplyStatus status;
  final int editCount;
  final int appliedEditCount;
  final String message;
  final DateTime? timestamp;

  bool get successful =>
      status == SemanticSnapshotCodeActionApplyStatus.applied;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'actionId': actionId,
      'label': label,
      'diagnosticCode': diagnosticCode,
      'status': status.wireValue,
      'successful': successful,
      'editCount': editCount,
      'appliedEditCount': appliedEditCount,
      'message': message,
      if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
    };
  }
}

class SemanticSnapshotCodeActionResult {
  const SemanticSnapshotCodeActionResult({
    required this.source,
    required this.diagnosticCode,
    required this.actions,
    required this.message,
  });

  final SemanticSnapshotProviderSource source;
  final String diagnosticCode;
  final List<SemanticSnapshotCodeActionFact> actions;
  final String message;

  bool get available => actions.any((action) => action.hasEdits);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.wireValue,
      'diagnosticCode': diagnosticCode,
      'available': available,
      'actionCount': actions.length,
      'message': message,
      'actions': actions
          .map((action) => action.toJson())
          .toList(growable: false),
    };
  }
}

class SemanticSnapshotRenameSafetyResult {
  const SemanticSnapshotRenameSafetyResult({
    required this.source,
    required this.available,
    required this.safe,
    required this.newName,
    required this.message,
    this.scope = SemanticSnapshotRenameSafetyScope.document,
    this.targetName = '',
    this.referenceCount = 0,
    this.editCount = 0,
    this.affectedDocumentIds = const <String>[],
    this.conflicts = const <RenameConflict>[],
    this.conflictMessages = const <String>[],
  });

  final SemanticSnapshotProviderSource source;
  final SemanticSnapshotRenameSafetyScope scope;
  final bool available;
  final bool safe;
  final String targetName;
  final String newName;
  final int referenceCount;
  final int editCount;
  final List<String> affectedDocumentIds;
  final List<RenameConflict> conflicts;
  final List<String> conflictMessages;
  final String message;

  bool get canApply => available && safe && editCount > 0;

  int get affectedDocumentCount => affectedDocumentIds.length;

  int get conflictCount => conflicts.length + conflictMessages.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.wireValue,
      'scope': scope.wireValue,
      'available': available,
      'safe': safe,
      'canApply': canApply,
      'targetName': targetName,
      'newName': newName,
      'referenceCount': referenceCount,
      'editCount': editCount,
      'affectedDocumentCount': affectedDocumentCount,
      'affectedDocumentIds': affectedDocumentIds,
      'conflictCount': conflictCount,
      'message': message,
      'conflicts': conflicts
          .map(
            (conflict) => <String, Object?>{
              'message': conflict.message,
              'range': _sourceRangeToJson(conflict.range),
            },
          )
          .toList(growable: false),
      if (conflictMessages.isNotEmpty) 'conflictMessages': conflictMessages,
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
    final serviceAnalysis = languageService.analyzeDocument(document);
    final serviceSnapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: serviceAnalysis,
    );

    // Verify snapshot identity consistency.
    if (serviceSnapshot.documentId != document.documentId) {
      throw ArgumentError(
        'Snapshot documentId mismatch: ${serviceSnapshot.documentId} vs ${document.documentId}',
      );
    }
    if (serviceSnapshot.revision != document.revision) {
      throw ArgumentError(
        'Snapshot revision mismatch: ${serviceSnapshot.revision} vs ${document.revision}',
      );
    }

    final codeActionFactCount = _codeActionFactCount(
      document: document,
      diagnostics: serviceAnalysis.diagnostics,
    );
    if (!_shouldUseFallback(document, serviceSnapshot)) {
      return SemanticSnapshotProviderResult(
        snapshot: serviceSnapshot,
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        message: 'Semantic snapshot produced from StyioService analysis facts.',
        codeActionFactCount: codeActionFactCount,
      );
    }

    final fallbackSnapshot = _tryBuildFallback(document);
    if (fallbackSnapshot == null || !_hasSemanticFacts(fallbackSnapshot)) {
      return SemanticSnapshotProviderResult(
        snapshot: serviceSnapshot,
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        message:
            'Semantic snapshot kept service analysis facts; local fallback produced no additional semantic facts.',
        codeActionFactCount: codeActionFactCount,
      );
    }

    return SemanticSnapshotProviderResult(
      snapshot: fallbackSnapshot,
      source: SemanticSnapshotProviderSource.localBuilderFallback,
      message:
          'Using local semantic snapshot fallback because StyioService did not provide complete symbol and reference facts.',
      codeActionFactCount: codeActionFactCount,
    );
  }

  int _codeActionFactCount({
    required DocumentState document,
    required Iterable<Diagnostic> diagnostics,
  }) {
    var count = 0;
    for (final diagnostic in diagnostics) {
      count += languageService
          .quickFixesForDiagnostic(document, diagnostic)
          .length;
    }
    return count;
  }

  SemanticSnapshotCodeActionResult codeActionsForDiagnostic({
    required DocumentState document,
    required Diagnostic diagnostic,
  }) {
    final fixes = languageService.quickFixesForDiagnostic(document, diagnostic);
    final actions = <SemanticSnapshotCodeActionFact>[
      for (var index = 0; index < fixes.length; index += 1)
        SemanticSnapshotCodeActionFact(
          id: '${diagnostic.code}.$index',
          label: fixes[index].label,
          detail: fixes[index].detail,
          diagnosticCode: diagnostic.code,
          edits: List<FormattingEdit>.unmodifiable(fixes[index].edits),
        ),
    ];
    return SemanticSnapshotCodeActionResult(
      source: SemanticSnapshotProviderSource.serviceAnalysis,
      diagnosticCode: diagnostic.code,
      actions: List<SemanticSnapshotCodeActionFact>.unmodifiable(actions),
      message: actions.isEmpty
          ? 'StyioService produced no raw edit code action facts.'
          : 'StyioService produced ${actions.length} raw edit code action fact(s).',
    );
  }

  SemanticSnapshotRenameSafetyResult renameSafetyAt({
    required DocumentState document,
    required int offset,
    required String newName,
  }) {
    final plan = languageService.renameAt(document, offset, newName);
    if (plan == null) {
      return SemanticSnapshotRenameSafetyResult(
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        available: false,
        safe: false,
        newName: newName,
        message:
            'StyioService did not produce a rename plan for this location.',
      );
    }
    return SemanticSnapshotRenameSafetyResult(
      source: SemanticSnapshotProviderSource.serviceAnalysis,
      available: true,
      safe: !plan.hasConflicts,
      targetName: plan.target.name,
      newName: plan.newName,
      referenceCount: plan.references.length,
      editCount: plan.edits.length,
      affectedDocumentIds: document.documentId.isEmpty
          ? const <String>[]
          : <String>[document.documentId],
      conflicts: List<RenameConflict>.unmodifiable(plan.conflicts),
      conflictMessages: List<String>.unmodifiable(
        plan.conflicts.map((conflict) => conflict.message),
      ),
      message: plan.hasConflicts
          ? 'StyioService blocked rename with ${plan.conflicts.length} conflict(s).'
          : 'StyioService produced a safe rename plan.',
    );
  }

  SemanticSnapshotRenameSafetyResult workspaceRenameSafetyFromPreview({
    required StyioProjectRenamePreview? preview,
    required String newName,
  }) {
    if (preview == null) {
      return SemanticSnapshotRenameSafetyResult(
        source: SemanticSnapshotProviderSource.serviceAnalysis,
        scope: SemanticSnapshotRenameSafetyScope.workspace,
        available: false,
        safe: false,
        newName: newName,
        message:
            'StyioService did not produce a workspace rename preview for this location.',
      );
    }
    final affectedDocumentIds = preview.editsByDocument.keys.toList(
      growable: false,
    )..sort();
    final conflictMessages = <String>[
      if (preview.conflict != null) preview.conflict!,
    ];
    return SemanticSnapshotRenameSafetyResult(
      source: SemanticSnapshotProviderSource.serviceAnalysis,
      scope: SemanticSnapshotRenameSafetyScope.workspace,
      available: true,
      safe: !preview.hasConflict,
      targetName: preview.oldName,
      newName: preview.newName,
      referenceCount: preview.editCount,
      editCount: preview.editCount,
      affectedDocumentIds: List<String>.unmodifiable(affectedDocumentIds),
      conflictMessages: List<String>.unmodifiable(conflictMessages),
      message: preview.hasConflict
          ? 'StyioService blocked workspace rename: ${preview.conflict}'
          : 'StyioService produced a safe workspace rename across ${affectedDocumentIds.length} document(s).',
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

Map<String, Object?> _formattingEditToJson(FormattingEdit edit) {
  return <String, Object?>{
    'range': _sourceRangeToJson(edit.range),
    'newText': edit.newText,
  };
}

Map<String, Object?> _sourceRangeToJson(SourceRange range) {
  return <String, Object?>{'start': range.start, 'end': range.end};
}
