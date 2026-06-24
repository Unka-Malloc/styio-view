import '../../editor/document_state.dart';
import '../../foundation/foundation.dart';
import '../contract/language_contract.dart';
import '../syntax/styio_syntax_highlighter.dart';

enum ResolvedElementKind {
  function,
  variable,
  type,
  resource,
  parameter,
  unknown,
}

enum ResolvedReferenceAccess { declaration, read, write }

class ResolvedElement {
  const ResolvedElement({
    required this.name,
    required this.kind,
    required this.nameRange,
    required this.declarationRange,
    this.detail,
    this.documentation,
  });

  final String name;
  final ResolvedElementKind kind;
  final SourceRange nameRange;
  final SourceRange declarationRange;
  final String? detail;
  final String? documentation;
}

class ResolvedReference {
  const ResolvedReference({
    required this.name,
    required this.range,
    required this.target,
    required this.access,
    required this.isDeclaration,
  });

  final String name;
  final SourceRange range;
  final ResolvedElement target;
  final ResolvedReferenceAccess access;
  final bool isDeclaration;
}

class CapabilityGap {
  const CapabilityGap({
    required this.capabilityId,
    required this.reason,
    this.detail = '',
    this.resolution = '',
  });

  final String capabilityId;
  final String reason;
  final String detail;
  final String resolution;
}

class SemanticSnapshot {
  const SemanticSnapshot({
    required this.documentId,
    required this.revision,
    required this.tokens,
    required this.elements,
    required this.references,
    this.workspaceGraphHash = '',
    this.toolchainId = '',
    this.providerId = '',
    this.protocolVersion = '',
    this.semanticPayloadVersion = '',
    this.producedAt,
    this.freshness = 'unknown',
    this.source = 'unknown',
    this.partialReason = '',
    this.capabilityGaps = const [],
  });

  final String documentId;
  final int revision;
  final String workspaceGraphHash;
  final String toolchainId;
  final String providerId;
  final String protocolVersion;
  final String semanticPayloadVersion;
  final DateTime? producedAt;
  final String freshness;
  final String source;
  final String partialReason;
  final List<TokenSpan> tokens;
  final List<ResolvedElement> elements;
  final List<ResolvedReference> references;
  final List<CapabilityGap> capabilityGaps;

  DateTime get effectiveProducedAt => producedAt ?? DateTime.now();

  String get cacheKey =>
      '$documentId:$revision:$workspaceGraphHash:$toolchainId:$providerId:$protocolVersion:$semanticPayloadVersion';

  bool get isFresh => freshness == 'fresh';

  bool get isStale => freshness == 'stale';

  bool get isPartial => partialReason.isNotEmpty;

  factory SemanticSnapshot.fromAnalysis({
    required DocumentState document,
    required StyioDocumentAnalysis analysis,
  }) {
    bool isSafeRange(SourceRange range) {
      return range.start >= 0 &&
          range.end >= range.start &&
          range.end <= document.length;
    }

    final elementsByRange = <String, ResolvedElement>{};
    final elements = <ResolvedElement>[];
    for (final symbol in analysis.documentSymbols) {
      if (!isSafeRange(symbol.nameRange) ||
          !isSafeRange(symbol.declarationRange)) {
        continue;
      }
      final element = ResolvedElement(
        name: symbol.name,
        kind: _resolvedElementKindFromSymbolKind(symbol.kind),
        nameRange: symbol.nameRange,
        declarationRange: symbol.declarationRange,
        detail: symbol.detail,
        documentation: symbol.documentation,
      );
      elementsByRange[_rangeKey(symbol.nameRange)] = element;
      elementsByRange[_rangeKey(symbol.declarationRange)] = element;
      elements.add(element);
    }

    final references = <ResolvedReference>[];
    final referenceKeys = <String>{};
    for (final element in elements) {
      final referenceKey =
          '${_rangeKey(element.nameRange)}->${_rangeKey(element.nameRange)}';
      referenceKeys.add(referenceKey);
      references.add(
        ResolvedReference(
          name: element.name,
          range: element.nameRange,
          target: element,
          access: ResolvedReferenceAccess.declaration,
          isDeclaration: true,
        ),
      );
    }

    for (final span in analysis.referenceSpans) {
      if (!isSafeRange(span.range) || !isSafeRange(span.targetRange)) {
        continue;
      }
      final target = elementsByRange[_rangeKey(span.targetRange)];
      if (target == null) {
        continue;
      }
      final referenceRange = _analysisReferenceRange(span, target);
      if (!isSafeRange(referenceRange)) {
        continue;
      }
      final referenceKey =
          '${_rangeKey(referenceRange)}->${_rangeKey(target.nameRange)}';
      if (!referenceKeys.add(referenceKey)) {
        continue;
      }
      references.add(
        ResolvedReference(
          name: span.name,
          range: referenceRange,
          target: target,
          access: _resolvedReferenceAccessFromReferenceAccess(span.access),
          isDeclaration: span.isDeclaration,
        ),
      );
    }

    return SemanticSnapshot(
      documentId: document.documentId,
      revision: document.revision,
      tokens: List.unmodifiable(
        analysis.tokenSpans.where((token) => isSafeRange(token.range)),
      ),
      elements: List.unmodifiable(elements),
      references: List.unmodifiable(references),
      workspaceGraphHash: '',
      toolchainId: '',
      providerId: '',
      protocolVersion: '',
      semanticPayloadVersion: '',
      producedAt: DateTime.now(),
      freshness: 'fresh',
      source: 'service',
      partialReason: '',
      capabilityGaps: const [],
    );
  }

  bool isStaleFor(DocumentState document, {String? currentWorkspaceGraphHash, String? currentToolchainId}) {
    if (document.documentId != documentId || document.revision != revision) return true;
    if (currentWorkspaceGraphHash != null && workspaceGraphHash.isNotEmpty && workspaceGraphHash != currentWorkspaceGraphHash) return true;
    if (currentToolchainId != null && toolchainId.isNotEmpty && toolchainId != currentToolchainId) return true;
    return false;
  }

  ResolvedElement? elementAt(int offset) {
    final reference = referenceAt(offset);
    if (reference != null) {
      return reference.target;
    }

    for (final element in elements) {
      if (_rangeContains(element.nameRange, offset)) {
        return element;
      }
    }
    return null;
  }

  ResolvedReference? referenceAt(int offset) {
    for (final reference in references) {
      if (_rangeContains(reference.range, offset)) {
        return reference;
      }
    }
    return null;
  }

  List<ResolvedReference> referencesFor(ResolvedElement target) {
    return references
        .where(
          (reference) =>
              _sameRange(reference.target.nameRange, target.nameRange),
        )
        .toList(growable: false);
  }

  List<ResolvedElement> completionCandidatesAt(int offset) {
    final seen = <String>{};
    final candidates = <ResolvedElement>[];

    for (final element in elements) {
      if (element.nameRange.start > offset) {
        continue;
      }
      final key = '${element.kind.name}:${element.name}';
      if (seen.add(key)) {
        candidates.add(element);
      }
    }

    return candidates;
  }
}

class SemanticSnapshotCacheKey {
  const SemanticSnapshotCacheKey({
    required this.documentId,
    required this.revision,
    required this.workspaceGraphHash,
    required this.toolchainId,
    required this.providerId,
    required this.protocolVersion,
    required this.semanticPayloadVersion,
  });

  final String documentId;
  final int revision;
  final String workspaceGraphHash;
  final String toolchainId;
  final String providerId;
  final String protocolVersion;
  final String semanticPayloadVersion;

  String get compositeKey =>
      '$documentId:$revision:$workspaceGraphHash:$toolchainId:$providerId:$protocolVersion:$semanticPayloadVersion';
}

SourceRange _analysisReferenceRange(
  ReferenceSpan span,
  ResolvedElement target,
) {
  final declarationReference =
      span.isDeclaration || span.access == ReferenceAccess.declaration;
  if (!declarationReference) {
    return span.range;
  }
  if (_sameRange(span.range, target.nameRange)) {
    return span.range;
  }
  if (_sameRange(span.range, target.declarationRange) ||
      _rangeContainsRange(span.range, target.nameRange)) {
    return target.nameRange;
  }
  return span.range;
}

class SemanticSnapshotBuilder {
  const SemanticSnapshotBuilder({
    this.syntaxHighlighter = const StyioSyntaxHighlighter(),
  });

  final StyioSyntaxHighlighter syntaxHighlighter;

  SemanticSnapshot build(DocumentState document) {
    final tokens = syntaxHighlighter.tokenize(document.text);
    final significantTokens = _significantTokens(tokens);
    final elements = _collectElements(document.text, significantTokens);
    final references = _collectReferences(significantTokens, elements);

    return SemanticSnapshot(
      documentId: document.documentId,
      revision: document.revision,
      tokens: List.unmodifiable(tokens),
      elements: List.unmodifiable(elements),
      references: List.unmodifiable(references),
      workspaceGraphHash: '',
      toolchainId: '',
      providerId: 'local-fallback',
      protocolVersion: '',
      semanticPayloadVersion: '',
      producedAt: DateTime.now(),
      freshness: 'fresh',
      source: 'fallback',
      partialReason: '',
      capabilityGaps: const [],
    );
  }

  List<TokenSpan> _significantTokens(List<TokenSpan> tokens) {
    return tokens
        .where((token) {
          final lexeme = token.lexeme.trim();
          return lexeme.isNotEmpty &&
              !lexeme.startsWith('//') &&
              !lexeme.startsWith('/*');
        })
        .toList(growable: false);
  }

  List<ResolvedElement> _collectElements(
    String source,
    List<TokenSpan> tokens,
  ) {
    final elements = <ResolvedElement>[];

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      final next = _tokenAt(tokens, index + 1);

      if (token.lexeme == '#' && next != null && _isIdentifier(next.lexeme)) {
        elements.add(
          _element(
            source: source,
            nameToken: next,
            kind: ResolvedElementKind.function,
            detail: 'Styio function',
          ),
        );
        continue;
      }

      if (token.lexeme == 'schema' &&
          next != null &&
          _isIdentifier(next.lexeme)) {
        elements.add(
          _element(
            source: source,
            nameToken: next,
            kind: ResolvedElementKind.type,
            detail: 'Styio schema',
          ),
        );
        continue;
      }

      if (token.lexeme == '@' && next != null && _isIdentifier(next.lexeme)) {
        elements.add(
          _element(
            source: source,
            nameToken: next,
            kind: ResolvedElementKind.resource,
            detail: 'Styio resource',
          ),
        );
        continue;
      }

      if (_isIdentifier(token.lexeme) &&
          next != null &&
          _isDeclarationOperator(next.lexeme)) {
        elements.add(
          _element(
            source: source,
            nameToken: token,
            kind: ResolvedElementKind.variable,
            detail: 'Styio binding',
          ),
        );
      }
    }

    return elements;
  }

  ResolvedElement _element({
    required String source,
    required TokenSpan nameToken,
    required ResolvedElementKind kind,
    required String detail,
  }) {
    return ResolvedElement(
      name: nameToken.lexeme,
      kind: kind,
      nameRange: nameToken.range,
      declarationRange: _lineRange(source, nameToken.range.start),
      detail: detail,
    );
  }

  List<ResolvedReference> _collectReferences(
    List<TokenSpan> tokens,
    List<ResolvedElement> elements,
  ) {
    final references = <ResolvedReference>[];

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (!_isIdentifier(token.lexeme)) {
        continue;
      }

      final declaration = _declarationForToken(elements, token);
      if (declaration != null) {
        references.add(
          ResolvedReference(
            name: token.lexeme,
            range: token.range,
            target: declaration,
            access: ResolvedReferenceAccess.declaration,
            isDeclaration: true,
          ),
        );
        continue;
      }

      final target = _nearestPriorElement(elements, token);
      if (target == null) {
        continue;
      }

      references.add(
        ResolvedReference(
          name: token.lexeme,
          range: token.range,
          target: target,
          access: _referenceAccess(tokens, index),
          isDeclaration: false,
        ),
      );
    }

    return references;
  }

  ResolvedElement? _declarationForToken(
    List<ResolvedElement> elements,
    TokenSpan token,
  ) {
    for (final element in elements) {
      if (element.name == token.lexeme &&
          _sameRange(element.nameRange, token.range)) {
        return element;
      }
    }
    return null;
  }

  ResolvedElement? _nearestPriorElement(
    List<ResolvedElement> elements,
    TokenSpan token,
  ) {
    ResolvedElement? target;
    for (final element in elements) {
      if (element.name != token.lexeme ||
          element.nameRange.start > token.range.start) {
        continue;
      }
      if (target == null || element.nameRange.start > target.nameRange.start) {
        target = element;
      }
    }
    return target;
  }

  ResolvedReferenceAccess _referenceAccess(List<TokenSpan> tokens, int index) {
    final next = _tokenAt(tokens, index + 1);
    if (next != null && _isWriteOperator(next.lexeme)) {
      return ResolvedReferenceAccess.write;
    }
    return ResolvedReferenceAccess.read;
  }

  TokenSpan? _tokenAt(List<TokenSpan> tokens, int index) {
    if (index < 0 || index >= tokens.length) {
      return null;
    }
    return tokens[index];
  }

  bool _isDeclarationOperator(String lexeme) {
    return lexeme == ':=' || lexeme == '=';
  }

  bool _isWriteOperator(String lexeme) {
    return lexeme == '=' ||
        lexeme == '+=' ||
        lexeme == '-=' ||
        lexeme == '*=' ||
        lexeme == '/=' ||
        lexeme == '%=';
  }

  bool _isIdentifier(String lexeme) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(lexeme);
  }

  SourceRange _lineRange(String source, int offset) {
    var start = offset.clamp(0, source.length);
    while (start > 0 && source[start - 1] != '\n') {
      start -= 1;
    }

    var end = offset.clamp(0, source.length);
    while (end < source.length && source[end] != '\n') {
      end += 1;
    }

    return SourceRange(start: start, end: end);
  }
}

class LanguageProviderDescriptor {
  const LanguageProviderDescriptor({
    required this.languageId,
    required this.providerId,
    required this.displayName,
    this.priority = 0,
    this.capabilities = const <String>{},
  });

  final String languageId;
  final String providerId;
  final String displayName;
  final int priority;
  final Set<String> capabilities;
}

class LanguageProviderRegistryManifestEntry {
  LanguageProviderRegistryManifestEntry({
    required this.languageId,
    required this.providerId,
    required this.displayName,
    required this.priority,
    Iterable<String> capabilities = const <String>[],
  }) : capabilities = List.unmodifiable(_sortedStrings(capabilities));

  factory LanguageProviderRegistryManifestEntry.fromDescriptor(
    LanguageProviderDescriptor descriptor,
  ) {
    return LanguageProviderRegistryManifestEntry(
      languageId: descriptor.languageId,
      providerId: descriptor.providerId,
      displayName: descriptor.displayName,
      priority: descriptor.priority,
      capabilities: descriptor.capabilities,
    );
  }

  factory LanguageProviderRegistryManifestEntry.fromJson(
    Map<String, Object?> json,
  ) {
    return LanguageProviderRegistryManifestEntry(
      languageId: _jsonString(json['languageId']),
      providerId: _jsonString(json['providerId']),
      displayName: _jsonString(json['displayName']),
      priority: _jsonInt(json['priority']),
      capabilities: _jsonStringList(json['capabilities']),
    );
  }

  final String languageId;
  final String providerId;
  final String displayName;
  final int priority;
  final List<String> capabilities;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'languageId': languageId,
      'providerId': providerId,
      'displayName': displayName,
      'priority': priority,
      'capabilities': capabilities,
    };
  }
}

class LanguageProviderRegistryManifest {
  LanguageProviderRegistryManifest({
    this.schemaVersion = 'vityo-language-provider-registry-manifest-v1',
    required Iterable<LanguageProviderRegistryManifestEntry> entries,
  }) : entries = List.unmodifiable(entries);

  factory LanguageProviderRegistryManifest.fromJson(Map<String, Object?> json) {
    final entries = <LanguageProviderRegistryManifestEntry>[];
    final rawEntries = json['entries'];
    if (rawEntries is List) {
      for (final rawEntry in rawEntries) {
        if (rawEntry is Map) {
          entries.add(
            LanguageProviderRegistryManifestEntry.fromJson(
              Map<String, Object?>.from(rawEntry),
            ),
          );
        }
      }
    }
    return LanguageProviderRegistryManifest(
      schemaVersion: _jsonString(
        json['schemaVersion'],
        fallback: 'vityo-language-provider-registry-manifest-v1',
      ),
      entries: entries,
    );
  }

  final String schemaVersion;
  final List<LanguageProviderRegistryManifestEntry> entries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class LanguageProviderRegistryManifestChange {
  const LanguageProviderRegistryManifestChange({
    required this.kind,
    required this.key,
    required this.scope,
    this.workspaceId,
    this.manifest,
  });

  final FoundationDataStoreChangeKind kind;
  final String key;
  final FoundationResourceScope scope;
  final String? workspaceId;
  final LanguageProviderRegistryManifest? manifest;
}

class LanguageProviderRegistryManifestStore {
  const LanguageProviderRegistryManifestStore({
    required FoundationDataStoreOwner owner,
    this.namespaceName = 'service.language.provider-registry',
    this.schemaVersion = 1,
  }) : _owner = owner;

  final FoundationDataStoreOwner _owner;
  final String namespaceName;
  final int schemaVersion;

  Future<void> writeManifest({
    required String key,
    required LanguageProviderRegistryManifest manifest,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _owner.writeJson(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
      value: manifest.toJson(),
    );
  }

  Future<LanguageProviderRegistryManifest?> readManifest({
    required String key,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return null;
    }
    return LanguageProviderRegistryManifest.fromJson(value);
  }

  Future<bool> deleteManifest({
    required String key,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _owner.delete(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
    );
  }

  Stream<LanguageProviderRegistryManifestChange> watch({
    String? key,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _owner
        .watchJson(
          namespaceName: namespaceName,
          key: key,
          schemaVersion: schemaVersion,
          scope: scope,
          workspaceId: workspaceId,
        )
        .map((change) {
          return LanguageProviderRegistryManifestChange(
            kind: change.kind,
            key: change.key,
            scope: change.scope,
            workspaceId: change.workspaceId,
            manifest: change.value == null
                ? null
                : LanguageProviderRegistryManifest.fromJson(change.value!),
          );
        });
  }
}

class LanguageProviderRegistration<T> {
  const LanguageProviderRegistration({
    required this.descriptor,
    required this.provider,
  });

  final LanguageProviderDescriptor descriptor;
  final T provider;
}

class LanguageProviderRegistry<T> {
  final Map<String, List<LanguageProviderRegistration<T>>> _registrations =
      <String, List<LanguageProviderRegistration<T>>>{};

  void register(LanguageProviderRegistration<T> registration) {
    final normalizedRegistration = _normalizedRegistration(registration);
    final bucket = _registrations.putIfAbsent(
      normalizedRegistration.descriptor.languageId,
      () => <LanguageProviderRegistration<T>>[],
    );

    bucket.removeWhere(
      (current) =>
          current.descriptor.providerId ==
          normalizedRegistration.descriptor.providerId,
    );
    bucket.add(normalizedRegistration);
    bucket.sort((left, right) {
      final priority = right.descriptor.priority.compareTo(
        left.descriptor.priority,
      );
      if (priority != 0) {
        return priority;
      }
      return left.descriptor.providerId.compareTo(right.descriptor.providerId);
    });
  }

  bool unregister({required String languageId, required String providerId}) {
    final bucket = _registrations[_normalizedProviderLanguageId(languageId)];
    if (bucket == null) {
      return false;
    }

    final before = bucket.length;
    final normalizedProviderId = _normalizedProviderId(providerId);
    bucket.removeWhere(
      (registration) =>
          registration.descriptor.providerId == normalizedProviderId,
    );
    if (bucket.isEmpty) {
      _registrations.remove(_normalizedProviderLanguageId(languageId));
    }
    return before != bucket.length;
  }

  T? resolve(String languageId, {String? capability}) {
    final bucket = _providersFor(languageId, capability: capability);
    if (bucket == null || bucket.isEmpty) {
      return null;
    }
    return bucket.first.provider;
  }

  List<LanguageProviderRegistration<T>> providersFor(
    String languageId, {
    String? capability,
  }) {
    return List.unmodifiable(
      _providersFor(languageId, capability: capability) ??
          <LanguageProviderRegistration<T>>[],
    );
  }

  List<LanguageProviderRegistration<T>> get registrations {
    return List.unmodifiable(_registrations.values.expand((bucket) => bucket));
  }

  LanguageProviderRegistryManifest manifest({
    String? languageId,
    String? capability,
  }) {
    final registrations = <LanguageProviderRegistration<T>>[];
    if (languageId == null) {
      for (final bucket in _registrations.values) {
        registrations.addAll(_filterCapability(bucket, capability));
      }
    } else {
      registrations.addAll(
        _providersFor(languageId, capability: capability) ??
            <LanguageProviderRegistration<T>>[],
      );
    }

    final entries =
        registrations
            .map(
              (registration) =>
                  LanguageProviderRegistryManifestEntry.fromDescriptor(
                    registration.descriptor,
                  ),
            )
            .toList(growable: false)
          ..sort(_compareManifestEntry);

    return LanguageProviderRegistryManifest(entries: entries);
  }

  List<LanguageProviderRegistration<T>>? _providersFor(
    String languageId, {
    String? capability,
  }) {
    final bucket = _registrations[_normalizedProviderLanguageId(languageId)];
    if (bucket == null || capability == null) {
      return bucket;
    }
    return _filterCapability(bucket, capability);
  }

  List<LanguageProviderRegistration<T>> _filterCapability(
    List<LanguageProviderRegistration<T>> bucket,
    String? capability,
  ) {
    if (capability == null) {
      return bucket;
    }
    final normalizedCapability = _normalizedProviderCapability(capability);
    return bucket
        .where(
          (registration) => registration.descriptor.capabilities.any(
            (candidate) =>
                _normalizedProviderCapability(candidate) ==
                normalizedCapability,
          ),
        )
        .toList(growable: false);
  }

  LanguageProviderRegistration<T> _normalizedRegistration(
    LanguageProviderRegistration<T> registration,
  ) {
    return LanguageProviderRegistration<T>(
      descriptor: LanguageProviderDescriptor(
        languageId: _normalizedProviderLanguageId(
          registration.descriptor.languageId,
        ),
        providerId: _normalizedProviderId(registration.descriptor.providerId),
        displayName: _normalizedProviderDisplayName(
          registration.descriptor.displayName,
          providerId: registration.descriptor.providerId,
        ),
        priority: registration.descriptor.priority,
        capabilities: Set.unmodifiable(
          registration.descriptor.capabilities
              .map(_canonicalProviderCapability)
              .where((capability) => capability.isNotEmpty),
        ),
      ),
      provider: registration.provider,
    );
  }
}

String _normalizedProviderLanguageId(String languageId) {
  return languageId.trim().toLowerCase();
}

String _normalizedProviderId(String providerId) {
  return providerId.trim();
}

String _normalizedProviderDisplayName(String displayName, {required String providerId}) {
  final normalized = displayName.trim();
  if (normalized.isNotEmpty) {
    return normalized;
  }
  return _normalizedProviderId(providerId);
}

String _canonicalProviderCapability(String capability) {
  final normalized = capability.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.replaceAll(RegExp(r'[\s_]+'), '-');
}

String _normalizedProviderCapability(String capability) {
  return capability.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
}

bool _rangeContains(SourceRange range, int offset) {
  return range.contains(offset);
}

bool _rangeContainsRange(SourceRange range, SourceRange child) {
  return range.start <= child.start && range.end >= child.end;
}

bool _sameRange(SourceRange left, SourceRange right) {
  return left.start == right.start && left.end == right.end;
}

String _rangeKey(SourceRange range) {
  return '${range.start}:${range.end}';
}

ResolvedElementKind _resolvedElementKindFromSymbolKind(SymbolKind kind) {
  return switch (kind) {
    SymbolKind.function => ResolvedElementKind.function,
    SymbolKind.resource => ResolvedElementKind.resource,
    SymbolKind.variable => ResolvedElementKind.variable,
    SymbolKind.parameter => ResolvedElementKind.parameter,
    SymbolKind.task => ResolvedElementKind.function,
    SymbolKind.state => ResolvedElementKind.type,
    SymbolKind.pipeline => ResolvedElementKind.unknown,
  };
}

ResolvedReferenceAccess _resolvedReferenceAccessFromReferenceAccess(
  ReferenceAccess access,
) {
  return switch (access) {
    ReferenceAccess.declaration => ResolvedReferenceAccess.declaration,
    ReferenceAccess.read => ResolvedReferenceAccess.read,
    ReferenceAccess.write => ResolvedReferenceAccess.write,
  };
}

SymbolKind symbolKindFromResolvedElementKind(ResolvedElementKind kind) {
  return switch (kind) {
    ResolvedElementKind.function => SymbolKind.function,
    ResolvedElementKind.resource => SymbolKind.resource,
    ResolvedElementKind.parameter => SymbolKind.parameter,
    ResolvedElementKind.type => SymbolKind.state,
    ResolvedElementKind.variable ||
    ResolvedElementKind.unknown => SymbolKind.variable,
  };
}

ReferenceAccess referenceAccessFromResolvedReferenceAccess(
  ResolvedReferenceAccess access,
) {
  return switch (access) {
    ResolvedReferenceAccess.declaration => ReferenceAccess.declaration,
    ResolvedReferenceAccess.read => ReferenceAccess.read,
    ResolvedReferenceAccess.write => ReferenceAccess.write,
  };
}

List<String> _sortedStrings(Iterable<String> values) {
  return values.toSet().toList(growable: false)..sort();
}

String _jsonString(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

int _jsonInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}

int _compareManifestEntry(
  LanguageProviderRegistryManifestEntry left,
  LanguageProviderRegistryManifestEntry right,
) {
  final language = left.languageId.compareTo(right.languageId);
  if (language != 0) {
    return language;
  }
  final priority = right.priority.compareTo(left.priority);
  if (priority != 0) {
    return priority;
  }
  return left.providerId.compareTo(right.providerId);
}
