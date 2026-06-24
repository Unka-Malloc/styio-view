import '../../editor/document_state.dart';
import '../../foundation/foundation.dart';
import '../contract/language_contract.dart';
import 'language_service_foundation.dart';
import 'styio_service_capability.dart';
import 'styio_service_connector.dart';

export 'styio_service_capability.dart';

enum StyioServiceCapabilityState {
  available,
  derived,
  empty,
  unsupported,
  unavailable,
  failed,
  protocolError,
  stale,
}

enum StyioServiceCapabilityHealth { ready, degraded, unavailable }

extension StyioServiceCapabilityHealthX on StyioServiceCapabilityHealth {
  String get wireValue {
    return switch (this) {
      StyioServiceCapabilityHealth.ready => 'ready',
      StyioServiceCapabilityHealth.degraded => 'degraded',
      StyioServiceCapabilityHealth.unavailable => 'unavailable',
    };
  }
}

class StyioServiceCapabilityStatus {
  const StyioServiceCapabilityStatus({
    required this.capability,
    required this.state,
    this.message,
  });

  final StyioServiceCapability capability;
  final StyioServiceCapabilityState state;
  final String? message;

  bool get hasFreshPayload => state == StyioServiceCapabilityState.available;

  bool get isUsable =>
      state == StyioServiceCapabilityState.available ||
      state == StyioServiceCapabilityState.derived;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capability': capability.wireValue,
      'state': state.name,
      if (message != null) 'message': message,
    };
  }
}

class StyioServiceCapabilityHealthSummary {
  const StyioServiceCapabilityHealthSummary({
    required this.health,
    required this.totalCount,
    required this.freshCount,
    required this.usableCount,
    required this.missingCapabilities,
    required this.blockedCapabilities,
  });

  final StyioServiceCapabilityHealth health;
  final int totalCount;
  final int freshCount;
  final int usableCount;
  final List<StyioServiceCapability> missingCapabilities;
  final List<StyioServiceCapability> blockedCapabilities;

  bool get fullyReady =>
      health == StyioServiceCapabilityHealth.ready &&
      missingCapabilities.isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'health': health.wireValue,
      'totalCount': totalCount,
      'freshCount': freshCount,
      'usableCount': usableCount,
      'missingCount': missingCapabilities.length,
      'blockedCount': blockedCapabilities.length,
      'fullyReady': fullyReady,
      'missingCapabilities': missingCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      'blockedCapabilities': blockedCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
    };
  }
}

class StyioServiceCapabilitySnapshot {
  const StyioServiceCapabilitySnapshot({
    required this.documentId,
    required this.revision,
    required this.protocolVersion,
    required this.statuses,
    this.toolchainId = '',
    this.parserEngine,
    this.grammarVersion,
  });

  final String documentId;
  final int revision;
  final String protocolVersion;
  final String toolchainId;
  final String? parserEngine;
  final String? grammarVersion;
  final Map<StyioServiceCapability, StyioServiceCapabilityStatus> statuses;

  StyioServiceCapabilityState stateOf(StyioServiceCapability capability) {
    return statuses[capability]?.state ?? StyioServiceCapabilityState.empty;
  }

  Set<StyioServiceCapability> get capabilitiesWithFreshPayload {
    return statuses.entries
        .where((entry) => entry.value.hasFreshPayload)
        .map((entry) => entry.key)
        .toSet();
  }

  Set<StyioServiceCapability> get capabilitiesWithUsableResult {
    return statuses.entries
        .where((entry) => entry.value.isUsable)
        .map((entry) => entry.key)
        .toSet();
  }

  StyioServiceCapabilityHealthSummary get healthSummary {
    final missing = <StyioServiceCapability>[];
    final blocked = <StyioServiceCapability>[];
    var freshCount = 0;
    var usableCount = 0;
    for (final entry in statuses.entries) {
      final status = entry.value;
      if (status.hasFreshPayload) {
        freshCount += 1;
      }
      if (status.isUsable) {
        usableCount += 1;
      } else {
        missing.add(entry.key);
      }
      if (_isBlockedCapabilityState(status.state)) {
        blocked.add(entry.key);
      }
    }
    final health = statuses.isEmpty || usableCount == 0
        ? StyioServiceCapabilityHealth.unavailable
        : missing.isEmpty
        ? StyioServiceCapabilityHealth.ready
        : StyioServiceCapabilityHealth.degraded;
    return StyioServiceCapabilityHealthSummary(
      health: health,
      totalCount: statuses.length,
      freshCount: freshCount,
      usableCount: usableCount,
      missingCapabilities: List<StyioServiceCapability>.unmodifiable(missing),
      blockedCapabilities: List<StyioServiceCapability>.unmodifiable(blocked),
    );
  }

  Set<String> providerCapabilityWireValues({bool includeDerived = true}) {
    final capabilities = includeDerived
        ? capabilitiesWithUsableResult
        : capabilitiesWithFreshPayload;
    return capabilities.map((capability) => capability.wireValue).toSet();
  }

  LanguageProviderDescriptor providerDescriptor({
    required String languageId,
    required String providerId,
    required String displayName,
    int priority = 0,
    bool includeDerived = true,
  }) {
    return LanguageProviderDescriptor(
      languageId: languageId,
      providerId: providerId,
      displayName: displayName,
      priority: priority,
      capabilities: providerCapabilityWireValues(
        includeDerived: includeDerived,
      ),
    );
  }

  LanguageProviderRegistration<T> providerRegistration<T>({
    required String languageId,
    required String providerId,
    required String displayName,
    required T provider,
    int priority = 0,
    bool includeDerived = true,
  }) {
    return LanguageProviderRegistration<T>(
      descriptor: providerDescriptor(
        languageId: languageId,
        providerId: providerId,
        displayName: displayName,
        priority: priority,
        includeDerived: includeDerived,
      ),
      provider: provider,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'protocolVersion': protocolVersion,
      'toolchainId': toolchainId,
      if (parserEngine != null) 'parserEngine': parserEngine,
      if (grammarVersion != null) 'grammarVersion': grammarVersion,
      'statuses': statuses.values
          .map((status) => status.toJson())
          .toList(growable: false),
      'healthSummary': healthSummary.toJson(),
    };
  }
}

bool _isBlockedCapabilityState(StyioServiceCapabilityState state) {
  return switch (state) {
    StyioServiceCapabilityState.unsupported ||
    StyioServiceCapabilityState.unavailable ||
    StyioServiceCapabilityState.failed ||
    StyioServiceCapabilityState.protocolError ||
    StyioServiceCapabilityState.stale => true,
    StyioServiceCapabilityState.available ||
    StyioServiceCapabilityState.derived ||
    StyioServiceCapabilityState.empty => false,
  };
}

class StyioServiceCapabilityDetector {
  const StyioServiceCapabilityDetector();

  StyioServiceCapabilitySnapshot detectReport(
    StyioServiceAnalysisReport report, {
    Iterable<StyioServiceCapability> expectedCapabilities =
        StyioServiceCapability.values,
  }) {
    return detect(
      report.response,
      document: report.document,
      expectedCapabilities: expectedCapabilities,
    );
  }

  StyioServiceCapabilitySnapshot detect(
    StyioServiceResponse response, {
    DocumentState? document,
    String? toolchainId,
    Iterable<StyioServiceCapability> expectedCapabilities =
        StyioServiceCapability.values,
  }) {
    final stale = document != null && response.isStaleFor(document);
    final statuses = <StyioServiceCapability, StyioServiceCapabilityStatus>{};
    for (final capability in expectedCapabilities) {
      statuses[capability] = StyioServiceCapabilityStatus(
        capability: capability,
        state: _stateFor(
          response,
          capability,
          document: document,
          stale: stale,
        ),
        message:
            lookupStyioServiceCapabilityValue(
              response.capabilityMessages,
              capability,
            ) ??
            response.message,
      );
    }
    return StyioServiceCapabilitySnapshot(
      documentId: response.documentId,
      revision: response.revision,
      protocolVersion: response.protocolVersion,
      toolchainId: toolchainId ?? response.toolchainId,
      parserEngine: response.parserEngine,
      grammarVersion: response.grammarVersion,
      statuses:
          Map<
            StyioServiceCapability,
            StyioServiceCapabilityStatus
          >.unmodifiable(statuses),
    );
  }

  StyioServiceCapabilityState _stateFor(
    StyioServiceResponse response,
    StyioServiceCapability capability, {
    DocumentState? document,
    required bool stale,
  }) {
    if (stale || response.status == StyioServiceStatus.stale) {
      return StyioServiceCapabilityState.stale;
    }
    final explicitState = _explicitStateFor(response, capability);
    if (explicitState != null) {
      return explicitState;
    }
    if (_hasPayload(response, capability, document: document)) {
      return StyioServiceCapabilityState.available;
    }
    if ((capability == StyioServiceCapability.analysis ||
            capability == StyioServiceCapability.syntax) &&
        response.status == StyioServiceStatus.succeeded) {
      return StyioServiceCapabilityState.available;
    }
    if (capability == StyioServiceCapability.diagnostics &&
        response.status == StyioServiceStatus.succeeded) {
      return StyioServiceCapabilityState.available;
    }
    if (_canDeriveFromSemanticFacts(response, capability, document: document)) {
      return StyioServiceCapabilityState.derived;
    }
    return switch (response.status) {
      StyioServiceStatus.succeeded => StyioServiceCapabilityState.empty,
      StyioServiceStatus.unavailable => StyioServiceCapabilityState.unavailable,
      StyioServiceStatus.failed => StyioServiceCapabilityState.failed,
      StyioServiceStatus.protocolError =>
        StyioServiceCapabilityState.protocolError,
      StyioServiceStatus.stale => StyioServiceCapabilityState.stale,
    };
  }

  StyioServiceCapabilityState? _explicitStateFor(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    final raw = lookupStyioServiceCapabilityValue(
      response.capabilityStates,
      capability,
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return switch (raw.trim().toLowerCase().replaceAll('_', '-')) {
      'available' || 'supported' => StyioServiceCapabilityState.available,
      'derived' => StyioServiceCapabilityState.derived,
      'empty' => StyioServiceCapabilityState.empty,
      'unsupported' => StyioServiceCapabilityState.unsupported,
      'unavailable' => StyioServiceCapabilityState.unavailable,
      'failed' || 'error' => StyioServiceCapabilityState.failed,
      'protocol-error' ||
      'protocolerror' => StyioServiceCapabilityState.protocolError,
      'stale' => StyioServiceCapabilityState.stale,
      _ => null,
    };
  }

  bool _hasPayload(
    StyioServiceResponse response,
    StyioServiceCapability capability, {
    DocumentState? document,
  }) {
    if (document == null) {
      return _hasRawPayload(response, capability);
    }
    return switch (capability) {
      StyioServiceCapability.analysis => _hasAnySafePayload(response, document),
      StyioServiceCapability.syntax ||
      StyioServiceCapability.diagnostics => response.diagnostics.any(
        (diagnostic) => _isSafeRange(document, diagnostic.range),
      ),
      StyioServiceCapability.completion => response.completions.any(
        (item) =>
            item.replacementRange == null ||
            _isSafeRange(document, item.replacementRange!),
      ),
      StyioServiceCapability.hover => response.hovers.any(
        (hover) => _isSafeRange(document, hover.range),
      ),
      StyioServiceCapability.semanticTokens => response.semanticSpans.any(
        (span) => _isSafeRange(document, span.range),
      ),
      StyioServiceCapability.formatting => response.formattingEdits.any(
        (edit) => isFormattingEditValidForDocument(
          documentLength: document.length,
          edit: edit,
        ),
      ),
      StyioServiceCapability.semanticBlocks => response.semanticBlocks.any(
        (block) => _isSafeRange(document, block.range),
      ),
      StyioServiceCapability.inlayHints => response.inlayHints.any(
        (hint) =>
            _isSafeOffset(document, hint.position) &&
            _isSafeRange(document, hint.range),
      ),
      StyioServiceCapability.documentSymbols => response.documentSymbols.any(
        (symbol) =>
            _isSafeRange(document, symbol.nameRange) &&
            _isSafeRange(document, symbol.declarationRange),
      ),
      StyioServiceCapability.references => response.referenceSpans.any(
        (reference) =>
            _isSafeRange(document, reference.range) &&
            _isSafeRange(document, reference.targetRange),
      ),
      StyioServiceCapability.definition => response.definitionTargets.any(
        (definition) =>
            _isSafeRange(document, definition.originRange) &&
            _isSafeRange(document, definition.symbol.nameRange) &&
            _isSafeRange(document, definition.symbol.declarationRange),
      ),
      StyioServiceCapability.codeActions => response.codeActions.any(
        (action) => _hasUsableEdits(document, action.edits),
      ),
      StyioServiceCapability.rename => response.renamePlans.any(
        (plan) => _hasUsableEdits(document, plan.edits),
      ),
      StyioServiceCapability.safeDelete => response.safeDeletePlans.any(
        (plan) => _hasUsableEdits(document, plan.edits),
      ),
      StyioServiceCapability.inlineVariable => response.inlineVariablePlans.any(
        (plan) => _hasUsableEdits(document, plan.edits),
      ),
      StyioServiceCapability.introduceVariable =>
        response.introduceVariablePlans.any(
          (plan) => _hasUsableEdits(document, plan.edits),
        ),
      StyioServiceCapability.extractFunction =>
        response.extractFunctionPlans.any(
          (plan) => _hasUsableEdits(document, plan.edits),
        ),
      StyioServiceCapability.changeSignature =>
        response.changeSignaturePlans.any(
          (plan) => _hasUsableEdits(document, plan.edits),
        ),
      StyioServiceCapability.parameterInfo => response.parameterInfos.any(
        (payload) =>
            _isSafeRange(document, payload.invocationRange) &&
            _isSafeRange(document, payload.callableRange) &&
            payload.parameters.every(
              (parameter) => _isSafeRange(document, parameter.range),
            ),
      ),
      StyioServiceCapability.surround => response.surroundTemplates.isNotEmpty,
    };
  }

  bool _hasRawPayload(
    StyioServiceResponse response,
    StyioServiceCapability capability,
  ) {
    return switch (capability) {
      StyioServiceCapability.analysis => response.hasPayload,
      StyioServiceCapability.syntax => response.diagnostics.isNotEmpty,
      StyioServiceCapability.diagnostics => response.diagnostics.isNotEmpty,
      StyioServiceCapability.completion => response.completions.isNotEmpty,
      StyioServiceCapability.hover => response.hovers.isNotEmpty,
      StyioServiceCapability.semanticTokens =>
        response.semanticSpans.isNotEmpty,
      StyioServiceCapability.formatting => response.formattingEdits.isNotEmpty,
      StyioServiceCapability.semanticBlocks =>
        response.semanticBlocks.isNotEmpty,
      StyioServiceCapability.inlayHints => response.inlayHints.isNotEmpty,
      StyioServiceCapability.documentSymbols =>
        response.documentSymbols.isNotEmpty,
      StyioServiceCapability.references => response.referenceSpans.isNotEmpty,
      StyioServiceCapability.definition =>
        response.definitionTargets.isNotEmpty,
      StyioServiceCapability.codeActions => response.codeActions.any(
        (action) => _hasRawUsableEdits(action.edits),
      ),
      StyioServiceCapability.rename => response.renamePlans.any(
        (plan) => _hasRawUsableEdits(plan.edits),
      ),
      StyioServiceCapability.safeDelete => response.safeDeletePlans.any(
        (plan) => _hasRawUsableEdits(plan.edits),
      ),
      StyioServiceCapability.inlineVariable => response.inlineVariablePlans.any(
        (plan) => _hasRawUsableEdits(plan.edits),
      ),
      StyioServiceCapability.introduceVariable =>
        response.introduceVariablePlans.any(
          (plan) => _hasRawUsableEdits(plan.edits),
        ),
      StyioServiceCapability.extractFunction =>
        response.extractFunctionPlans.any(
          (plan) => _hasRawUsableEdits(plan.edits),
        ),
      StyioServiceCapability.changeSignature =>
        response.changeSignaturePlans.any(
          (plan) => _hasRawUsableEdits(plan.edits),
        ),
      StyioServiceCapability.parameterInfo =>
        response.parameterInfos.isNotEmpty,
      StyioServiceCapability.surround => response.surroundTemplates.isNotEmpty,
    };
  }

  bool _canDeriveFromSemanticFacts(
    StyioServiceResponse response,
    StyioServiceCapability capability, {
    DocumentState? document,
  }) {
    if (response.status != StyioServiceStatus.succeeded) {
      return false;
    }
    final hasSymbols = document == null
        ? response.documentSymbols.isNotEmpty
        : response.documentSymbols.any(
            (symbol) =>
                _isSafeRange(document, symbol.nameRange) &&
                _isSafeRange(document, symbol.declarationRange),
          );
    final hasReferences = document == null
        ? response.referenceSpans.isNotEmpty
        : response.referenceSpans.any(
            (reference) =>
                _isSafeRange(document, reference.range) &&
                _isSafeRange(document, reference.targetRange),
          );
    return switch (capability) {
      StyioServiceCapability.completion ||
      StyioServiceCapability.hover ||
      StyioServiceCapability.semanticTokens => hasSymbols,
      StyioServiceCapability.definition ||
      StyioServiceCapability.rename ||
      StyioServiceCapability.safeDelete ||
      StyioServiceCapability.inlineVariable ||
      StyioServiceCapability.changeSignature => hasSymbols && hasReferences,
      _ => false,
    };
  }

  bool _hasAnySafePayload(
    StyioServiceResponse response,
    DocumentState document,
  ) {
    return StyioServiceCapability.values.any(
      (capability) =>
          capability != StyioServiceCapability.analysis &&
          _hasPayload(response, capability, document: document),
    );
  }

  bool _hasSafeEdits(DocumentState document, List<FormattingEdit> edits) {
    return normalizeFormattingEditsForDocument(
          documentLength: document.length,
          edits: edits,
        ).length ==
        edits.length;
  }

  bool _hasUsableEdits(DocumentState document, List<FormattingEdit> edits) {
    return edits.isNotEmpty && _hasSafeEdits(document, edits);
  }

  bool _hasRawUsableEdits(List<FormattingEdit> edits) {
    return edits.isNotEmpty;
  }

  bool _isSafeRange(DocumentState document, SourceRange range) {
    return range.start >= 0 &&
        range.end >= range.start &&
        range.end <= document.length;
  }

  bool _isSafeOffset(DocumentState document, int offset) {
    return offset >= 0 && offset <= document.length;
  }
}

class StyioServiceCapabilityRegistrar<T> {
  const StyioServiceCapabilityRegistrar();

  LanguageProviderRegistration<T> refresh({
    required LanguageProviderRegistry<T> registry,
    required StyioServiceCapabilitySnapshot snapshot,
    required String languageId,
    required String providerId,
    required String displayName,
    required T provider,
    int priority = 0,
    bool includeDerived = true,
  }) {
    final registration = snapshot.providerRegistration<T>(
      languageId: languageId,
      providerId: providerId,
      displayName: displayName,
      provider: provider,
      priority: priority,
      includeDerived: includeDerived,
    );
    registry.register(registration);
    return registration;
  }

  LanguageProviderRegistration<T> refreshFromReport({
    required LanguageProviderRegistry<T> registry,
    required StyioServiceAnalysisReport report,
    required String languageId,
    required String providerId,
    required String displayName,
    required T provider,
    StyioServiceCapabilityDetector detector =
        const StyioServiceCapabilityDetector(),
    int priority = 0,
    bool includeDerived = true,
    Iterable<StyioServiceCapability> expectedCapabilities =
        StyioServiceCapability.values,
  }) {
    return refresh(
      registry: registry,
      snapshot: detector.detectReport(
        report,
        expectedCapabilities: expectedCapabilities,
      ),
      languageId: languageId,
      providerId: providerId,
      displayName: displayName,
      provider: provider,
      priority: priority,
      includeDerived: includeDerived,
    );
  }

  bool unregister({
    required LanguageProviderRegistry<T> registry,
    required String languageId,
    required String providerId,
  }) {
    return registry.unregister(languageId: languageId, providerId: providerId);
  }
}

class StyioServiceCapabilityNegotiationResult<T> {
  const StyioServiceCapabilityNegotiationResult({
    required this.report,
    required this.registration,
  });

  final StyioServiceAnalysisReport report;
  final LanguageProviderRegistration<T> registration;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'report': <String, Object?>{
        'documentId': report.documentId,
        'revision': report.revision,
        'protocolVersion': report.response.protocolVersion,
        if (report.response.parserEngine != null)
          'parserEngine': report.response.parserEngine,
        if (report.response.grammarVersion != null)
          'grammarVersion': report.response.grammarVersion,
        'serviceSucceeded': report.serviceSucceeded,
        'cachedResponseStored': report.cachedResponseStored,
      },
      'registration': <String, Object?>{
        'languageId': registration.descriptor.languageId,
        'providerId': registration.descriptor.providerId,
        'displayName': registration.descriptor.displayName,
        'priority': registration.descriptor.priority,
        'capabilities': registration.descriptor.capabilities.toList(
          growable: false,
        ),
      },
    };
  }
}

class StyioServiceCapabilityNegotiator<T> {
  StyioServiceCapabilityNegotiator({
    StyioServiceCapabilityRegistrar<T>? registrar,
  }) : registrar = registrar ?? StyioServiceCapabilityRegistrar<T>();

  final StyioServiceCapabilityRegistrar<T> registrar;

  Future<StyioServiceCapabilityNegotiationResult<T>> analyzeAndRefresh({
    required StyioServiceAnalysisDriver driver,
    required DocumentState document,
    required LanguageProviderRegistry<T> registry,
    required String languageId,
    required String providerId,
    required String displayName,
    required T provider,
    int priority = 0,
    bool includeDerived = true,
    String? filePath,
    String? configPath,
    String? workingDirectory,
    Iterable<StyioServiceCapability> expectedCapabilities =
        StyioServiceCapability.values,
  }) async {
    final report = await driver.analyzeDocumentWithReport(
      document,
      filePath: filePath,
      configPath: configPath,
      workingDirectory: workingDirectory,
    );
    final registration = registrar.refreshFromReport(
      registry: registry,
      report: report,
      languageId: languageId,
      providerId: providerId,
      displayName: displayName,
      provider: provider,
      priority: priority,
      includeDerived: includeDerived,
      expectedCapabilities: expectedCapabilities,
    );
    return StyioServiceCapabilityNegotiationResult<T>(
      report: report,
      registration: registration,
    );
  }
}

class StyioServiceCapabilitySession<T> {
  StyioServiceCapabilitySession({
    required StyioServiceAnalysisDriver driver,
    required LanguageProviderRegistry<T> registry,
    required String languageId,
    required String providerId,
    required String displayName,
    required T provider,
    int priority = 0,
    bool includeDerived = true,
    Iterable<StyioServiceCapability> expectedCapabilities =
        StyioServiceCapability.values,
    LanguageProviderRegistryManifestStore? manifestStore,
    String manifestKey = 'styio-service-providers',
    FoundationResourceScope manifestScope = FoundationResourceScope.user,
    String? manifestWorkspaceId,
    StyioServiceCapabilityNegotiator<T>? negotiator,
  }) : _driver = driver,
       _registry = registry,
       _languageId = languageId,
       _providerId = providerId,
       _displayName = displayName,
       _provider = provider,
       _priority = priority,
       _includeDerived = includeDerived,
       _expectedCapabilities = expectedCapabilities,
       _manifestStore = manifestStore,
       _manifestKey = manifestKey,
       _manifestScope = manifestScope,
       _manifestWorkspaceId = manifestWorkspaceId,
       _negotiator = negotiator ?? StyioServiceCapabilityNegotiator<T>();

  final StyioServiceAnalysisDriver _driver;
  final LanguageProviderRegistry<T> _registry;
  final String _languageId;
  final String _providerId;
  final String _displayName;
  final T _provider;
  final int _priority;
  final bool _includeDerived;
  final Iterable<StyioServiceCapability> _expectedCapabilities;
  final LanguageProviderRegistryManifestStore? _manifestStore;
  final String _manifestKey;
  final FoundationResourceScope _manifestScope;
  final String? _manifestWorkspaceId;
  final StyioServiceCapabilityNegotiator<T> _negotiator;

  StyioServiceCapabilityNegotiationResult<T>? _lastResult;
  bool _disposed = false;

  bool get disposed => _disposed;

  StyioServiceCapabilityNegotiationResult<T>? get lastResult => _lastResult;

  Future<StyioServiceCapabilityNegotiationResult<T>> refresh(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
  }) async {
    if (_disposed) {
      throw StateError('StyioService capability session is disposed.');
    }
    final result = await _negotiator.analyzeAndRefresh(
      driver: _driver,
      document: document,
      filePath: filePath,
      configPath: configPath,
      workingDirectory: workingDirectory,
      registry: _registry,
      languageId: _languageId,
      providerId: _providerId,
      displayName: _displayName,
      provider: _provider,
      priority: _priority,
      includeDerived: _includeDerived,
      expectedCapabilities: _expectedCapabilities,
    );
    _lastResult = result;
    await _syncManifest();
    return result;
  }

  Future<bool> dispose() async {
    if (_disposed) {
      return false;
    }
    _disposed = true;
    final unregistered = _registry.unregister(
      languageId: _languageId,
      providerId: _providerId,
    );
    await _syncManifest();
    return unregistered;
  }

  Future<void> _syncManifest() async {
    final manifestStore = _manifestStore;
    if (manifestStore == null) {
      return;
    }
    final manifest = _registry.manifest(languageId: _languageId);
    if (manifest.entries.isEmpty) {
      await manifestStore.deleteManifest(
        key: _manifestKey,
        scope: _manifestScope,
        workspaceId: _manifestWorkspaceId,
      );
      return;
    }
    await manifestStore.writeManifest(
      key: _manifestKey,
      manifest: manifest,
      scope: _manifestScope,
      workspaceId: _manifestWorkspaceId,
    );
  }
}
