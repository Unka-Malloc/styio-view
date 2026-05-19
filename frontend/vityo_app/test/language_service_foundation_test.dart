import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';

void main() {
  test('semantic snapshot resolves elements and references from fixture', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 7,
    );

    final snapshot = const SemanticSnapshotBuilder().build(document);

    expect(snapshot.documentId, document.documentId);
    expect(snapshot.revision, document.revision);
    expect(snapshot.tokens, isNotEmpty);
    expect(snapshot.elements.map((element) => element.name), contains('value'));

    final referenceOffset = source.lastIndexOf('value');
    final reference = snapshot.referenceAt(referenceOffset);

    expect(reference, isNotNull);
    expect(reference!.name, 'value');
    expect(reference.isDeclaration, isFalse);
    expect(reference.target.name, 'value');
    expect(snapshot.elementAt(referenceOffset)?.name, 'value');
    expect(snapshot.referencesFor(reference.target), hasLength(2));
    expect(snapshot.isStaleFor(document), isFalse);
    expect(
      snapshot.isStaleFor(
        DocumentState(
          documentId: document.documentId,
          text: document.text,
          revision: document.revision + 1,
        ),
      ),
      isTrue,
    );
  });

  test('completion candidates are scoped from prior declarations', () {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
    final snapshot = const SemanticSnapshotBuilder().build(document);

    final candidates = snapshot.completionCandidatesAt(source.length);

    expect(candidates.map((element) => element.name), contains('value'));
  });

  test('semantic snapshot binds resolved elements from analysis facts', () {
    const document = DocumentState(
      documentId: 'fixture://analysis',
      text: 'value := 1\nvalue\n',
      revision: 3,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
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
          range: SourceRange(start: 0, end: 5),
          targetRange: SourceRange(start: 0, end: 10),
          isDeclaration: true,
          access: ReferenceAccess.declaration,
        ),
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 11, end: 16),
          targetRange: SourceRange(start: 0, end: 5),
          access: ReferenceAccess.read,
        ),
      ],
    );

    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    expect(snapshot.elements.single.name, 'value');
    expect(snapshot.references, hasLength(2));
    expect(snapshot.referenceAt(0)?.target.name, 'value');
    expect(
      snapshot.referenceAt(0)?.access,
      ResolvedReferenceAccess.declaration,
    );
    expect(snapshot.referenceAt(11)?.target.name, 'value');
    expect(snapshot.referenceAt(11)?.access, ResolvedReferenceAccess.read);
    expect(snapshot.elementAt(11)?.kind, ResolvedElementKind.variable);
  });

  test('semantic snapshot filters analysis facts outside the document', () {
    const document = DocumentState(
      documentId: 'fixture://unsafe-analysis-facts',
      text: 'value\n',
      revision: 1,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[
        TokenSpan(
          range: SourceRange(start: 0, end: 5),
          kind: TokenKind.identifier,
          lexeme: 'value',
        ),
        TokenSpan(
          range: SourceRange(start: 0, end: 99),
          kind: TokenKind.identifier,
          lexeme: 'unsafe',
        ),
      ],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 5),
        ),
        DocumentSymbol(
          name: 'unsafe',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 99),
          declarationRange: SourceRange(start: 0, end: 99),
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 5),
          targetRange: SourceRange(start: 0, end: 5),
          access: ReferenceAccess.read,
        ),
        ReferenceSpan(
          name: 'unsafe',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 99),
          targetRange: SourceRange(start: 0, end: 99),
          access: ReferenceAccess.read,
        ),
      ],
    );

    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    expect(snapshot.tokens.map((token) => token.lexeme), <String>['value']);
    expect(snapshot.elements.map((element) => element.name), <String>['value']);
    expect(
      snapshot.references.map((reference) => reference.name),
      isNot(contains('unsafe')),
    );
  });

  test('semantic snapshot preserves state symbols as resolved types', () {
    const document = DocumentState(
      documentId: 'fixture://state-symbol',
      text: 'schema User\nUser\n',
      revision: 3,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'User',
          kind: SymbolKind.state,
          nameRange: SourceRange(start: 7, end: 11),
          declarationRange: SourceRange(start: 0, end: 11),
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'User',
          kind: SymbolKind.state,
          range: SourceRange(start: 12, end: 16),
          targetRange: SourceRange(start: 7, end: 11),
        ),
      ],
    );

    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    expect(snapshot.elements.single.kind, ResolvedElementKind.type);
    expect(
      symbolKindFromResolvedElementKind(snapshot.elements.single.kind),
      SymbolKind.state,
    );
    expect(snapshot.referenceAt(13)?.target.kind, ResolvedElementKind.type);
  });

  test('semantic snapshot accepts declaration range as reference target', () {
    const document = DocumentState(
      documentId: 'fixture://analysis-declaration-target',
      text: 'value := 1\nvalue\n',
      revision: 4,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
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
          targetRange: SourceRange(start: 0, end: 10),
          access: ReferenceAccess.read,
        ),
      ],
    );

    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    expect(snapshot.referenceAt(11)?.target.nameRange.start, 0);
    expect(snapshot.referencesFor(snapshot.elements.single), hasLength(2));
  });

  test('semantic snapshot narrows declaration references to symbol names', () {
    const document = DocumentState(
      documentId: 'fixture://analysis-declaration-reference-range',
      text: 'value := 1\nvalue\n',
      revision: 4,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
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
          range: SourceRange(start: 0, end: 10),
          targetRange: SourceRange(start: 0, end: 10),
          isDeclaration: true,
          access: ReferenceAccess.declaration,
        ),
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 11, end: 16),
          targetRange: SourceRange(start: 0, end: 10),
          access: ReferenceAccess.read,
        ),
      ],
    );

    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    expect(snapshot.referencesFor(snapshot.elements.single), hasLength(2));
    final declarationRange = snapshot
        .referencesFor(snapshot.elements.single)
        .first
        .range;
    expect(declarationRange.start, 0);
    expect(declarationRange.end, 5);
    expect(snapshot.referenceAt(4)?.isDeclaration, isTrue);
    expect(snapshot.referenceAt(5), isNull);
    expect(snapshot.referenceAt(6), isNull);
  });

  test('semantic snapshot uses half open source ranges', () {
    const document = DocumentState(
      documentId: 'fixture://semantic-range-boundary',
      text: 'value\nvalue\n',
      revision: 5,
    );
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: SourceRange(start: 0, end: 5),
          declarationRange: SourceRange(start: 0, end: 5),
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: SourceRange(start: 6, end: 11),
          targetRange: SourceRange(start: 0, end: 5),
          access: ReferenceAccess.read,
        ),
      ],
    );

    final snapshot = SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analysis,
    );

    expect(snapshot.referenceAt(4)?.name, 'value');
    expect(snapshot.referenceAt(5), isNull);
    expect(snapshot.elementAt(4)?.name, 'value');
    expect(snapshot.elementAt(5), isNull);
    expect(snapshot.referenceAt(10)?.access, ResolvedReferenceAccess.read);
    expect(snapshot.referenceAt(11), isNull);
  });

  test('language provider registry prefers highest priority provider', () {
    final registry = LanguageProviderRegistry<String>();

    registry
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'fallback',
            displayName: 'Fallback Styio provider',
            priority: 1,
          ),
          provider: 'fallback-provider',
        ),
      )
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'styio-service',
            displayName: 'StyioService provider',
            priority: 10,
            capabilities: <String>{
              'completion',
              'diagnostics',
              'hover',
              'semantic-tokens',
            },
          ),
          provider: 'styio-service-provider',
        ),
      );

    expect(registry.resolve('styio'), 'styio-service-provider');
    expect(registry.providersFor('styio'), hasLength(2));
    expect(
      registry.unregister(languageId: 'styio', providerId: 'styio-service'),
      isTrue,
    );
    expect(registry.resolve('styio'), 'fallback-provider');
  });

  test('language provider registry resolves by capability', () {
    final registry = LanguageProviderRegistry<String>();

    registry
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'completion-provider',
            displayName: 'Completion provider',
            priority: 5,
            capabilities: <String>{'completion'},
          ),
          provider: 'completion-service',
        ),
      )
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'diagnostic-provider',
            displayName: 'Diagnostic provider',
            priority: 10,
            capabilities: <String>{'diagnostics'},
          ),
          provider: 'diagnostic-service',
        ),
      );

    expect(
      registry.resolve('styio', capability: 'completion'),
      'completion-service',
    );
    expect(
      registry.resolve('styio', capability: 'diagnostics'),
      'diagnostic-service',
    );
    expect(registry.resolve('styio', capability: 'hover'), isNull);
    expect(
      registry.providersFor('styio', capability: 'completion'),
      hasLength(1),
    );
  });

  test('language provider registry normalizes and freezes registrations', () {
    final capabilities = <String>{
      ' Completion ',
      'semantic_tokens',
      'HOVER',
      '',
    };
    final registry = LanguageProviderRegistry<String>()
      ..register(
        LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: ' Styio ',
            providerId: ' styio-service ',
            displayName: ' Styio Service ',
            priority: 10,
            capabilities: capabilities,
          ),
          provider: 'styio-service-provider',
        ),
      );

    capabilities
      ..clear()
      ..add('diagnostics');

    final registrations = registry.providersFor('STYIO');
    final descriptor = registrations.single.descriptor;
    final manifest = registry.manifest(languageId: 'styio');

    expect(registry.resolve('styio', capability: 'completion'), 'styio-service-provider');
    expect(
      registry.resolve('styio', capability: 'semantic-tokens'),
      'styio-service-provider',
    );
    expect(registry.resolve('styio', capability: 'diagnostics'), isNull);
    expect(descriptor.languageId, 'styio');
    expect(descriptor.providerId, 'styio-service');
    expect(descriptor.displayName, 'Styio Service');
    expect(descriptor.capabilities, <String>{
      'completion',
      'hover',
      'semantic-tokens',
    });
    expect(
      () => descriptor.capabilities.add('diagnostics'),
      throwsUnsupportedError,
    );
    expect(manifest.entries.single.capabilities, <String>[
      'completion',
      'hover',
      'semantic-tokens',
    ]);
    expect(
      registry.unregister(
        languageId: ' STYIO ',
        providerId: ' styio-service ',
      ),
      isTrue,
    );
    expect(registry.providersFor('styio'), isEmpty);
  });

  test('language provider registry manifest is metadata-only', () {
    final registry = LanguageProviderRegistry<String>();

    registry
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'fallback',
            displayName: 'Fallback provider',
            priority: 1,
            capabilities: <String>{'hover', 'completion'},
          ),
          provider: 'runtime-provider-secret',
        ),
      )
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'styio-service',
            displayName: 'StyioService provider',
            priority: 10,
            capabilities: <String>{'diagnostics', 'completion'},
          ),
          provider: 'styio-service-runtime',
        ),
      )
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'markdown',
            providerId: 'markdown-service',
            displayName: 'Markdown provider',
            priority: 3,
            capabilities: <String>{'hover'},
          ),
          provider: 'markdown-runtime',
        ),
      );

    final manifest = registry.manifest();

    expect(
      manifest.schemaVersion,
      'vityo-language-provider-registry-manifest-v1',
    );
    expect(
      manifest.entries.map(
        (entry) => '${entry.languageId}:${entry.providerId}',
      ),
      <String>[
        'markdown:markdown-service',
        'styio:styio-service',
        'styio:fallback',
      ],
    );
    expect(manifest.entries[1].capabilities, <String>[
      'completion',
      'diagnostics',
    ]);

    final encoded = jsonEncode(manifest.toJson());

    expect(encoded, isNot(contains('runtime-provider-secret')));
    expect(encoded, isNot(contains('styio-service-runtime')));
    expect(encoded, isNot(contains('markdown-runtime')));
  });

  test('language provider registry manifest filters and round trips', () {
    final registry = LanguageProviderRegistry<String>();

    registry
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'completion-provider',
            displayName: 'Completion provider',
            priority: 5,
            capabilities: <String>{'completion'},
          ),
          provider: 'completion-service',
        ),
      )
      ..register(
        const LanguageProviderRegistration<String>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'diagnostic-provider',
            displayName: 'Diagnostic provider',
            priority: 10,
            capabilities: <String>{'diagnostics'},
          ),
          provider: 'diagnostic-service',
        ),
      );

    final manifest = registry.manifest(
      languageId: 'styio',
      capability: 'completion',
    );
    final restored = LanguageProviderRegistryManifest.fromJson(
      manifest.toJson(),
    );

    expect(restored.entries, hasLength(1));
    expect(restored.entries.single.languageId, 'styio');
    expect(restored.entries.single.providerId, 'completion-provider');
    expect(restored.entries.single.displayName, 'Completion provider');
    expect(restored.entries.single.priority, 5);
    expect(restored.entries.single.capabilities, <String>['completion']);
  });

  test(
    'language provider registry manifest store persists metadata only',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_language_provider_manifest_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      addTearDown(datastore.close);
      final owner = FoundationDataStoreOwner(
        descriptor: const FoundationDataStoreOwnerDescriptor(
          ownerId: 'service.language',
          layer: 'service',
          stateFamily: 'language-provider-registry',
          allowedNamespaces: <String>{'service.language.provider-registry'},
        ),
        dataStore: datastore,
      );
      final manifestStore = LanguageProviderRegistryManifestStore(owner: owner);
      final registry = LanguageProviderRegistry<String>()
        ..register(
          const LanguageProviderRegistration<String>(
            descriptor: LanguageProviderDescriptor(
              languageId: 'styio',
              providerId: 'styio-service',
              displayName: 'StyioService provider',
              priority: 10,
              capabilities: <String>{'diagnostics', 'hover'},
            ),
            provider: 'runtime-provider-must-not-be-written',
          ),
        );
      final changes = <LanguageProviderRegistryManifestChange>[];
      final subscription = manifestStore
          .watch(
            key: 'workspace-providers',
            scope: FoundationResourceScope.workspace,
            workspaceId: 'demo-workspace',
          )
          .listen(changes.add);
      addTearDown(subscription.cancel);

      await manifestStore.writeManifest(
        key: 'workspace-providers',
        manifest: registry.manifest(languageId: 'styio'),
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      );
      final loaded = await manifestStore.readManifest(
        key: 'workspace-providers',
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      );
      final deleted = await manifestStore.deleteManifest(
        key: 'workspace-providers',
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      );

      expect(loaded, isNotNull);
      expect(loaded!.entries.single.providerId, 'styio-service');
      expect(loaded.entries.single.capabilities, <String>[
        'diagnostics',
        'hover',
      ]);
      expect(jsonEncode(loaded.toJson()), isNot(contains('runtime-provider')));
      expect(deleted, isTrue);
      expect(
        await manifestStore.readManifest(
          key: 'workspace-providers',
          scope: FoundationResourceScope.workspace,
          workspaceId: 'demo-workspace',
        ),
        isNull,
      );
      expect(
        changes.map((change) => change.kind),
        <FoundationDataStoreChangeKind>[
          FoundationDataStoreChangeKind.written,
          FoundationDataStoreChangeKind.deleted,
        ],
      );
      expect(changes.first.manifest!.entries.single.languageId, 'styio');
      expect(changes.last.manifest, isNull);
    },
  );
}
