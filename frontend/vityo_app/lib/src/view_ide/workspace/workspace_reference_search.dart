import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceReferenceSearchStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noDefinitions,
  hitLimit,
}

class WorkspaceReferenceSearchQuery {
  const WorkspaceReferenceSearchQuery({
    required this.pattern,
    this.includeDefinitions = true,
    this.accessKinds = const <ReferenceAccess>{
      ReferenceAccess.declaration,
      ReferenceAccess.read,
      ReferenceAccess.write,
    },
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final bool includeDefinitions;
  final Set<ReferenceAccess> accessKinds;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceReferenceSearchQuery copyWith({
    String? pattern,
    bool? includeDefinitions,
    Set<ReferenceAccess>? accessKinds,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceReferenceSearchQuery(
      pattern: pattern ?? this.pattern,
      includeDefinitions: includeDefinitions ?? this.includeDefinitions,
      accessKinds: accessKinds ?? this.accessKinds,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceReferenceDefinition {
  const WorkspaceReferenceDefinition({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.referenceCount,
    this.type,
  });

  final String filePath;
  final String name;
  final StyioProjectSymbolKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final int referenceCount;
  final String? type;

  String get kindLabel => _projectSymbolKindLabel(kind);
}

class WorkspaceReferenceSearchItem {
  const WorkspaceReferenceSearchItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    required this.isDefinition,
    required this.access,
    required this.definition,
  });

  final String filePath;
  final String name;
  final StyioProjectSymbolKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final bool isDefinition;
  final ReferenceAccess access;
  final WorkspaceReferenceDefinition definition;

  String get accessLabel {
    return switch (access) {
      ReferenceAccess.declaration => 'declaration',
      ReferenceAccess.read => 'read',
      ReferenceAccess.write => 'write',
    };
  }
}

class WorkspaceReferenceSearchResult {
  const WorkspaceReferenceSearchResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.definitionsSearched,
    required this.definitions,
    required this.references,
    this.message,
  });

  final WorkspaceReferenceSearchQuery query;
  final WorkspaceReferenceSearchStatus status;
  final int filesSearched;
  final int definitionsSearched;
  final List<WorkspaceReferenceDefinition> definitions;
  final List<WorkspaceReferenceSearchItem> references;
  final String? message;

  bool get hitLimit => status == WorkspaceReferenceSearchStatus.hitLimit;

  int get matchCount => references.length;

  int get matchedFileCount =>
      references.map((reference) => reference.filePath).toSet().length;

  int get declarationCount => _countAccess(ReferenceAccess.declaration);

  int get readCount => _countAccess(ReferenceAccess.read);

  int get writeCount => _countAccess(ReferenceAccess.write);

  int _countAccess(ReferenceAccess access) {
    return references
        .where((reference) => reference.access == access)
        .length;
  }
}

class WorkspaceReferenceSearchService {
  const WorkspaceReferenceSearchService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceReferenceSearchResult> findReferences({
    required List<String> filePaths,
    required WorkspaceReferenceSearchQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final normalizedPattern = _normalizedPattern(query.pattern);
    if (normalizedPattern.isEmpty) {
      return WorkspaceReferenceSearchResult(
        query: query,
        status: WorkspaceReferenceSearchStatus.emptyPattern,
        filesSearched: 0,
        definitionsSearched: 0,
        definitions: const <WorkspaceReferenceDefinition>[],
        references: const <WorkspaceReferenceSearchItem>[],
        message: 'Find Usages requires a symbol name.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceReferenceSearchResult(
        query: query,
        status: WorkspaceReferenceSearchStatus.emptyWorkspace,
        filesSearched: 0,
        definitionsSearched: 0,
        definitions: const <WorkspaceReferenceDefinition>[],
        references: const <WorkspaceReferenceSearchItem>[],
      );
    }

    final documents = <DocumentState>[];
    for (final filePath in uniqueFilePaths) {
      documents.add(
        overlayDocuments[filePath] ?? await documentStore.loadDocument(filePath),
      );
    }
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final analysis = _projectLanguageService.analyzeProject(documents);
    final definitions = _definitionsForDocuments(
      analysis.symbolSnapshot,
      documents,
    );
    final scoredDefinitions = <_ScoredWorkspaceReferenceDefinition>[];

    for (var index = 0; index < definitions.length; index += 1) {
      final definition = definitions[index];
      final score = _scoreDefinition(
        definition: definition,
        normalizedPattern: normalizedPattern,
        definitionIndex: index,
      );
      if (score == null) {
        continue;
      }
      scoredDefinitions.add(
        _ScoredWorkspaceReferenceDefinition(
          definition: definition,
          score: score,
          definitionIndex: index,
        ),
      );
    }

    if (scoredDefinitions.isEmpty) {
      return WorkspaceReferenceSearchResult(
        query: query,
        status: WorkspaceReferenceSearchStatus.noDefinitions,
        filesSearched: documents.length,
        definitionsSearched: definitions.length,
        definitions: const <WorkspaceReferenceDefinition>[],
        references: const <WorkspaceReferenceSearchItem>[],
        message: 'No workspace symbols match `${query.pattern}`.',
      );
    }

    scoredDefinitions.sort(_compareScoredDefinitions);
    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final resultDefinitions = <WorkspaceReferenceDefinition>[];
    final references = <WorkspaceReferenceSearchItem>[];
    final seenReferences = <String>{};

    for (final scoredDefinition in scoredDefinitions) {
      final definition = scoredDefinition.definition;
      final projectReferences = analysis.symbolSnapshot.referencesFor(
        definition,
      );
      final visibleReferences = [
        for (final reference in projectReferences)
          if (_includesReference(reference, query)) reference,
      ];
      final definitionDocument = documentsById[definition.documentId];
      if (definitionDocument == null) {
        continue;
      }
      final definitionPosition = definitionDocument.positionForOffset(
        definition.range.start,
      );
      final resultDefinition = WorkspaceReferenceDefinition(
        filePath: definition.documentId,
        name: definition.name,
        kind: definition.kind,
        range: definition.range,
        line: definitionPosition.line,
        column: definitionPosition.column,
        referenceCount: visibleReferences.length,
        type: definition.type,
      );
      resultDefinitions.add(resultDefinition);

      for (final reference in visibleReferences) {
        final document = documentsById[reference.documentId];
        if (document == null) {
          continue;
        }
        final key =
            '${reference.documentId}:${reference.range.start}:'
            '${reference.range.end}:${definition.documentId}:'
            '${definition.range.start}:${definition.range.end}';
        if (!seenReferences.add(key)) {
          continue;
        }
        final position = document.positionForOffset(reference.range.start);
        references.add(
          WorkspaceReferenceSearchItem(
            filePath: reference.documentId,
            name: reference.name,
            kind: definition.kind,
            range: reference.range,
            line: position.line,
            column: position.column,
            previewText: _linePreview(document, position.line),
            isDefinition: reference.isDefinition,
            access: reference.access,
            definition: resultDefinition,
          ),
        );
        if (references.length >= maxResults) {
          return WorkspaceReferenceSearchResult(
            query: query,
            status: WorkspaceReferenceSearchStatus.hitLimit,
            filesSearched: documents.length,
            definitionsSearched: definitions.length,
            definitions: List<WorkspaceReferenceDefinition>.unmodifiable(
              resultDefinitions,
            ),
            references: List<WorkspaceReferenceSearchItem>.unmodifiable(
              references,
            ),
            message: 'Find Usages stopped after $maxResults reference(s).',
          );
        }
      }
    }

    return WorkspaceReferenceSearchResult(
      query: query,
      status: WorkspaceReferenceSearchStatus.completed,
      filesSearched: documents.length,
      definitionsSearched: definitions.length,
      definitions: List<WorkspaceReferenceDefinition>.unmodifiable(
        resultDefinitions,
      ),
      references: List<WorkspaceReferenceSearchItem>.unmodifiable(references),
    );
  }

  static bool _includesReference(
    StyioProjectSymbolReference reference,
    WorkspaceReferenceSearchQuery query,
  ) {
    if (reference.isDefinition && !query.includeDefinitions) {
      return false;
    }
    return query.accessKinds.contains(reference.access);
  }

  static List<StyioProjectSymbolDefinition> _definitionsForDocuments(
    StyioProjectSymbolSnapshot snapshot,
    List<DocumentState> documents,
  ) {
    final definitions = <StyioProjectSymbolDefinition>[];
    for (final document in documents) {
      definitions.addAll(
        snapshot.functionsFor(document.documentId).map(
              (function) => StyioProjectSymbolDefinition(
                documentId: document.documentId,
                kind: StyioProjectSymbolKind.function,
                name: function.name,
                range: function.range,
                type: function.returnType,
              ),
            ),
      );
      definitions.addAll(
        snapshot.resourcesFor(document.documentId).map(
              (resource) => StyioProjectSymbolDefinition(
                documentId: document.documentId,
                kind: StyioProjectSymbolKind.resource,
                name: resource.name,
                range: resource.range,
                type: resource.type,
              ),
            ),
      );
      definitions.addAll(
        snapshot.tasksFor(document.documentId).map(
              (task) => StyioProjectSymbolDefinition(
                documentId: document.documentId,
                kind: StyioProjectSymbolKind.task,
                name: task.name,
                range: task.range,
                type: task.returnType,
              ),
            ),
      );
    }
    return definitions;
  }

  static List<String> _uniqueFilePaths(List<String> filePaths) {
    final seen = <String>{};
    final unique = <String>[];
    for (final filePath in filePaths) {
      if (seen.add(filePath)) {
        unique.add(filePath);
      }
    }
    return unique;
  }

  static bool _isIndexable(
    String filePath,
    WorkspaceReferenceSearchQuery query,
  ) {
    final normalized = _displayPath(filePath).toLowerCase();
    if (!normalized.endsWith('.styio')) {
      return false;
    }
    if (query.includeGlobs.isNotEmpty &&
        !_matchesAnyGlob(filePath, query.includeGlobs)) {
      return false;
    }
    if (query.excludeGlobs.isNotEmpty &&
        _matchesAnyGlob(filePath, query.excludeGlobs)) {
      return false;
    }
    return true;
  }

  static bool _matchesAnyGlob(String filePath, List<String> globs) {
    return globs.any((glob) => _GlobMatcher(glob).matches(filePath));
  }

  static _WorkspaceReferenceDefinitionScore? _scoreDefinition({
    required StyioProjectSymbolDefinition definition,
    required String normalizedPattern,
    required int definitionIndex,
  }) {
    final normalizedName = definition.name.toLowerCase();
    final normalizedKind = definition.kind.name;
    final normalizedPath = _displayPath(definition.documentId).toLowerCase();
    final kindBoost = _kindBoost(definition.kind);

    final nameDirect = _directMatch(
      candidate: normalizedName,
      pattern: normalizedPattern,
      exactScore: 11000,
      prefixScore: 9800,
      containsScore: 8600,
    );
    if (nameDirect != null) {
      return nameDirect.withBoost(kindBoost);
    }

    final compactPattern = _compactPattern(normalizedPattern);
    final nameFuzzy = _orderedCharacterMatch(
      candidate: normalizedName,
      pattern: compactPattern,
      baseScore: 5600,
    );
    if (nameFuzzy != null) {
      return nameFuzzy.withBoost(kindBoost);
    }

    final kindDirect = _directMatch(
      candidate: normalizedKind,
      pattern: normalizedPattern,
      exactScore: 3600,
      prefixScore: 3200,
      containsScore: 2800,
    );
    final pathDirect = _directMatch(
      candidate: normalizedPath,
      pattern: normalizedPattern,
      exactScore: 3200,
      prefixScore: 3000,
      containsScore: 2600,
    );
    final fallback = _bestScore(kindDirect, pathDirect);
    if (fallback == null) {
      return null;
    }
    final cappedDefinitionIndex = definitionIndex > 250
        ? 250
        : definitionIndex;
    return fallback.withBoost(kindBoost - cappedDefinitionIndex);
  }

  static _WorkspaceReferenceDefinitionScore? _directMatch({
    required String candidate,
    required String pattern,
    required int exactScore,
    required int prefixScore,
    required int containsScore,
  }) {
    if (pattern.isEmpty) {
      return null;
    }
    if (candidate == pattern) {
      return _WorkspaceReferenceDefinitionScore(value: exactScore);
    }
    if (candidate.startsWith(pattern)) {
      return _WorkspaceReferenceDefinitionScore(
        value: prefixScore - (candidate.length - pattern.length),
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _WorkspaceReferenceDefinitionScore(value: containsScore - index);
    }
    return null;
  }

  static _WorkspaceReferenceDefinitionScore? _orderedCharacterMatch({
    required String candidate,
    required String pattern,
    required int baseScore,
  }) {
    if (pattern.isEmpty) {
      return null;
    }
    var cursor = 0;
    var lastIndex = -2;
    var firstIndex = -1;
    var score = baseScore;

    for (
      var patternIndex = 0;
      patternIndex < pattern.length;
      patternIndex += 1
    ) {
      final char = pattern[patternIndex];
      final matchIndex = candidate.indexOf(char, cursor);
      if (matchIndex < 0) {
        return null;
      }
      firstIndex = firstIndex < 0 ? matchIndex : firstIndex;
      score += 12;
      if (matchIndex == lastIndex + 1) {
        score += 10;
      }
      if (_isWordBoundary(candidate, matchIndex)) {
        score += 8;
      }
      score -= matchIndex - cursor;
      cursor = matchIndex + 1;
      lastIndex = matchIndex;
    }

    if (firstIndex >= 0) {
      score -= firstIndex;
    }
    return _WorkspaceReferenceDefinitionScore(value: score);
  }

  static _WorkspaceReferenceDefinitionScore? _bestScore(
    _WorkspaceReferenceDefinitionScore? first,
    _WorkspaceReferenceDefinitionScore? second,
  ) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.value >= second.value ? first : second;
  }

  static String _linePreview(DocumentState document, int line) {
    final lines = document.lines;
    if (lines.isEmpty) {
      return '';
    }
    return lines[line.clamp(0, lines.length - 1)].trimRight();
  }

  static String _normalizedPattern(String pattern) {
    return pattern.trim().replaceAll('\\', '/').toLowerCase();
  }

  static String _compactPattern(String pattern) {
    return pattern.replaceAll(RegExp(r'\s+'), '');
  }

  static String _displayPath(String filePath) {
    return filePath.replaceAll('\\', '/');
  }

  static bool _isWordBoundary(String candidate, int index) {
    if (index == 0) {
      return true;
    }
    final previous = candidate[index - 1];
    return previous == ' ' ||
        previous == '-' ||
        previous == '_' ||
        previous == '.' ||
        previous == '/' ||
        previous == ':';
  }

  static int _kindBoost(StyioProjectSymbolKind kind) {
    return switch (kind) {
      StyioProjectSymbolKind.function => 260,
      StyioProjectSymbolKind.resource => 210,
      StyioProjectSymbolKind.task => 200,
    };
  }

  static int _compareScoredDefinitions(
    _ScoredWorkspaceReferenceDefinition first,
    _ScoredWorkspaceReferenceDefinition second,
  ) {
    final scoreCompare = second.score.value.compareTo(first.score.value);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final nameCompare = first.definition.name.toLowerCase().compareTo(
      second.definition.name.toLowerCase(),
    );
    if (nameCompare != 0) {
      return nameCompare;
    }
    final fileCompare = first.definition.documentId.compareTo(
      second.definition.documentId,
    );
    if (fileCompare != 0) {
      return fileCompare;
    }
    return first.definitionIndex.compareTo(second.definitionIndex);
  }
}

String _projectSymbolKindLabel(StyioProjectSymbolKind kind) {
  return switch (kind) {
    StyioProjectSymbolKind.function => 'function',
    StyioProjectSymbolKind.resource => 'resource',
    StyioProjectSymbolKind.task => 'task',
  };
}

class _WorkspaceReferenceDefinitionScore {
  const _WorkspaceReferenceDefinitionScore({required this.value});

  final int value;

  _WorkspaceReferenceDefinitionScore withBoost(int boost) {
    if (boost == 0) {
      return this;
    }
    return _WorkspaceReferenceDefinitionScore(value: value + boost);
  }
}

class _ScoredWorkspaceReferenceDefinition {
  const _ScoredWorkspaceReferenceDefinition({
    required this.definition,
    required this.score,
    required this.definitionIndex,
  });

  final StyioProjectSymbolDefinition definition;
  final _WorkspaceReferenceDefinitionScore score;
  final int definitionIndex;
}

class _GlobMatcher {
  _GlobMatcher(this.glob) : _regex = RegExp(_globToRegex(glob));

  final String glob;
  final RegExp _regex;

  bool matches(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final target = glob.contains('/') ? normalized : _baseName(normalized);
    return _regex.hasMatch(target);
  }

  static String _baseName(String filePath) {
    final slash = filePath.lastIndexOf('/');
    return slash < 0 ? filePath : filePath.substring(slash + 1);
  }

  static String _globToRegex(String glob) {
    final buffer = StringBuffer('^');
    for (var index = 0; index < glob.length; index += 1) {
      final char = glob[index];
      if (char == '*') {
        final isDoubleStar =
            index + 1 < glob.length && glob[index + 1] == '*';
        if (isDoubleStar) {
          index += 1;
          if (index + 1 < glob.length && glob[index + 1] == '/') {
            buffer.write('(?:.*/)?');
            index += 1;
          } else {
            buffer.write('.*');
          }
        } else {
          buffer.write('[^/]*');
        }
        continue;
      }
      if (char == '?') {
        buffer.write('[^/]');
        continue;
      }
      buffer.write(RegExp.escape(char));
    }
    buffer.write(r'$');
    return buffer.toString();
  }
}
