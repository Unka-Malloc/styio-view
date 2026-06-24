import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_provider.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';

void main() {
  test('semantic snapshot provider prefers StyioService analysis facts', () {
    const document = DocumentState(
      documentId: 'fixture://semantic-provider-service',
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://semantic-provider-service',
        revision: 1,
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 10),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 11, end: 16),
            targetRange: SourceRange(start: 0, end: 5),
            access: ReferenceAccess.read,
          ),
        ],
      ),
    );
    final provider = SemanticSnapshotProvider(
      languageService: CachedStyioLanguageService(
        cache: cache,
        allowLocalFallback: false,
      ),
    );

    final result = provider.snapshotFor(document);

    expect(result.source, SemanticSnapshotProviderSource.serviceAnalysis);
    expect(result.usedFallback, isFalse);
    expect(result.snapshot.elements.single.name, 'value');
    expect(result.snapshot.references, hasLength(2));
    expect(result.snapshot.referenceAt(11)?.target.name, 'value');
    expect(
      result.featureMatrix.supportsFeature(
        SemanticSnapshotConsumerFeature.definition,
      ),
      isTrue,
    );
    expect(
      result.featureMatrix
          .supportFor(SemanticSnapshotConsumerFeature.definition)
          .confidence,
      SemanticSnapshotFeatureConfidence.serviceBacked,
    );
    expect(
      result.featureMatrix.supportsFeature(
        SemanticSnapshotConsumerFeature.renameSafety,
      ),
      isTrue,
    );
    expect(
      result.featureMatrix.supportsFeature(
        SemanticSnapshotConsumerFeature.codeActions,
      ),
      isFalse,
    );
    expect(result.toJson()['source'], 'service-analysis');
    expect(
      ((result.toJson()['featureMatrix']!
              as Map<String, Object?>)['unavailableFeatures']!
          as List<Object?>),
      contains('code-actions'),
    );
    expect(
      (result.toJson()['featureMatrix']!
          as Map<String, Object?>)['serviceBackedFeatureCount'],
      greaterThan(0),
    );
    expect(
      (result.toJson()['featureMatrix']!
          as Map<String, Object?>)['localFallbackFeatureCount'],
      0,
    );
  });

  test(
    'semantic snapshot provider falls back when service has no semantic facts',
    () {
      const document = DocumentState(
        documentId: 'fixture://semantic-provider-fallback',
        text: 'value := 1\nvalue\n',
        revision: 1,
      );
      final provider = SemanticSnapshotProvider(
        languageService: CachedStyioLanguageService(
          cache: StyioServiceResultCache(),
          allowLocalFallback: false,
        ),
      );

      final result = provider.snapshotFor(document);

      expect(
        result.source,
        SemanticSnapshotProviderSource.localBuilderFallback,
      );
      expect(result.usedFallback, isTrue);
      expect(
        result.message,
        startsWith('Using local semantic snapshot fallback'),
      );
      expect(result.snapshot.elements.map((element) => element.name), [
        'value',
      ]);
      expect(result.snapshot.references, hasLength(2));
      expect(
        result.featureMatrix.supportsFeature(
          SemanticSnapshotConsumerFeature.references,
        ),
        isTrue,
      );
      expect(
        result.featureMatrix
            .supportFor(SemanticSnapshotConsumerFeature.references)
            .confidence,
        SemanticSnapshotFeatureConfidence.localFallback,
      );
      expect(
        result.featureMatrix.supportsFeature(
          SemanticSnapshotConsumerFeature.renameSafety,
        ),
        isFalse,
      );
      expect(
        result.featureMatrix
            .supportFor(SemanticSnapshotConsumerFeature.renameSafety)
            .confidence,
        SemanticSnapshotFeatureConfidence.unavailable,
      );
      expect(result.toJson()['usedFallback'], isTrue);
      expect(
        (result.toJson()['featureMatrix']!
            as Map<String, Object?>)['localFallbackFeatureCount'],
        greaterThan(0),
      );
      expect(
        (result.toJson()['featureMatrix']!
            as Map<String, Object?>)['serviceBackedFeatureCount'],
        0,
      );
      expect(
        (((result.toJson()['featureMatrix']!
                    as Map<String, Object?>)['supports']!
                as List<Object?>)
            .cast<Map<String, Object?>>()
            .singleWhere(
              (entry) => entry['feature'] == 'references',
            ))['confidence'],
        'local-fallback',
      );
    },
  );

  test('semantic snapshot provider exposes StyioService code action facts', () {
    const service = LocalStyioLanguageService();
    const document = DocumentState(
      documentId: 'fixture://semantic-provider-code-actions',
      text: '#main := () => {\n  value := 1\n',
      revision: 1,
    );
    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'local.unclosed-delimiter',
        );
    const provider = SemanticSnapshotProvider(languageService: service);

    final snapshotResult = provider.snapshotFor(document);
    final result = provider.codeActionsForDiagnostic(
      document: document,
      diagnostic: diagnostic,
    );
    final json = result.toJson();

    expect(snapshotResult.codeActionFactCount, 1);
    expect(
      snapshotResult.featureMatrix.supportsFeature(
        SemanticSnapshotConsumerFeature.codeActions,
      ),
      isTrue,
    );
    expect(
      snapshotResult.featureMatrix
          .supportFor(SemanticSnapshotConsumerFeature.codeActions)
          .confidence,
      SemanticSnapshotFeatureConfidence.serviceBacked,
    );
    expect(snapshotResult.toJson()['codeActionFactCount'], 1);
    expect(snapshotResult.featureMatrix.toJson()['codeActionFactCount'], 1);
    expect(result.source, SemanticSnapshotProviderSource.serviceAnalysis);
    expect(result.available, isTrue);
    expect(result.actions.single.diagnosticCode, 'local.unclosed-delimiter');
    expect(result.actions.single.hasEdits, isTrue);
    expect(result.actions.single.edits.single.range.start, document.length);
    final applyResult = result.actions.single.reportApplyResult(
      status: SemanticSnapshotCodeActionApplyStatus.applied,
      appliedEditCount: 1,
      message: 'Applied from Problems panel.',
      timestamp: DateTime.utc(2026, 5, 20, 13),
    );
    expect(applyResult.successful, isTrue);
    expect(applyResult.toJson()['status'], 'applied');
    expect(applyResult.toJson()['appliedEditCount'], 1);
    final applyEvent = const SemanticSnapshotEventBridge().codeActionApplyEvent(
      documentId: document.documentId,
      result: applyResult,
      timestamp: DateTime.utc(2026, 5, 20, 13, 1),
    );
    expect(applyEvent.toJson()['kind'], 'language-service');
    expect(applyEvent.metadata['semanticEventKind'], 'code-action-apply');
    expect(applyEvent.metadata['documentId'], document.documentId);
    expect(json['available'], isTrue);
    expect(
      ((json['actions']! as List<Object?>).single!
          as Map<String, Object?>)['editCount'],
      1,
    );
  });

  test(
    'semantic snapshot provider exposes StyioService rename safety facts',
    () {
      const service = LocalStyioLanguageService();
      const document = DocumentState(
        documentId: 'fixture://semantic-provider-rename',
        text: 'value := 1\nvalue\n',
        revision: 1,
      );
      const provider = SemanticSnapshotProvider(languageService: service);
      final referenceOffset = document.text.lastIndexOf('value') + 1;

      final result = provider.renameSafetyAt(
        document: document,
        offset: referenceOffset,
        newName: 'nextValue',
      );

      expect(result.source, SemanticSnapshotProviderSource.serviceAnalysis);
      expect(result.available, isTrue);
      expect(result.safe, isTrue);
      expect(result.canApply, isTrue);
      expect(result.targetName, 'value');
      expect(result.newName, 'nextValue');
      expect(result.referenceCount, 2);
      expect(result.editCount, 2);
      expect(result.affectedDocumentIds, <String>[
        'fixture://semantic-provider-rename',
      ]);
      expect(result.toJson()['scope'], 'document');
      expect(result.toJson()['canApply'], isTrue);
      final event = const SemanticSnapshotEventBridge().renameSafetyEvent(
        documentId: document.documentId,
        result: result,
        timestamp: DateTime.utc(2026, 5, 20, 14),
      );
      expect(event.metadata['semanticEventKind'], 'rename-safety');
      expect(event.message, contains('is safe'));
    },
  );

  test('semantic snapshot provider exposes workspace rename safety facts', () {
    const projectService = ProjectStyioLanguageService();
    const provider = SemanticSnapshotProvider(
      languageService: LocalStyioLanguageService(),
    );
    const documents = <DocumentState>[
      DocumentState(
        documentId: 'lib/runtime.styio',
        text: '''
@prices : f64|..2| := {}

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/runtime }
price = 1.0
value = blend(price, 2.0)
price -> @prices
''',
        revision: 0,
      ),
    ];
    final source = documents[1].text;
    final preview = projectService.renamePreviewAt(
      documents: documents,
      documentId: 'main.styio',
      offset: source.indexOf('blend'),
      newName: 'mix',
    );

    final result = provider.workspaceRenameSafetyFromPreview(
      preview: preview,
      newName: 'mix',
    );
    final json = result.toJson();

    expect(result.scope, SemanticSnapshotRenameSafetyScope.workspace);
    expect(result.safe, isTrue);
    expect(result.canApply, isTrue);
    expect(result.affectedDocumentIds, <String>[
      'lib/runtime.styio',
      'main.styio',
    ]);
    expect(result.editCount, 2);
    expect(json['scope'], 'workspace');
    expect(json['affectedDocumentCount'], 2);
  });
}
