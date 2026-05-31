import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceDefinitionStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noDefinitions,
  hitLimit,
}

class WorkspaceDefinitionQuery {
  const WorkspaceDefinitionQuery({
    required this.pattern,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 50,
  });

  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceDefinitionQuery copyWith({
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceDefinitionQuery(
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceDefinitionItem {
  const WorkspaceDefinitionItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    this.type,
  });

  final String filePath;
  final String name;
  final StyioProjectSymbolKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final String? type;

  String get kindLabel => _projectSymbolKindLabel(kind);
}

class WorkspaceDefinitionResult {
  const WorkspaceDefinitionResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.definitionsIndexed,
    required this.definitions,
    this.message,
  });

  final WorkspaceDefinitionQuery query;
  final WorkspaceDefinitionStatus status;
  final int filesSearched;
  final int definitionsIndexed;
  final List<WorkspaceDefinitionItem> definitions;
  final String? message;

  bool get hitLimit => status == WorkspaceDefinitionStatus.hitLimit;

  int get matchCount => definitions.length;

  int get matchedFileCount =>
      definitions.map((definition) => definition.filePath).toSet().length;
}

class WorkspaceDefinitionService {
  const WorkspaceDefinitionService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceDefinitionResult> findDefinitions({
    required List<String> filePaths,
    required WorkspaceDefinitionQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final normalizedPattern = _normalizedPattern(query.pattern);
    if (normalizedPattern.isEmpty) {
      return WorkspaceDefinitionResult(
        query: query,
        status: WorkspaceDefinitionStatus.emptyPattern,
        filesSearched: 0,
        definitionsIndexed: 0,
        definitions: const <WorkspaceDefinitionItem>[],
        message: 'Go to Definition requires a symbol name.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceDefinitionResult(
        query: query,
        status: WorkspaceDefinitionStatus.emptyWorkspace,
        filesSearched: 0,
        definitionsIndexed: 0,
        definitions: const <WorkspaceDefinitionItem>[],
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
    final scoredDefinitions = <_ScoredWorkspaceDefinition>[];

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
        _ScoredWorkspaceDefinition(
          definition: definition,
          score: score,
          definitionIndex: index,
        ),
      );
    }

    if (scoredDefinitions.isEmpty) {
      return WorkspaceDefinitionResult(
        query: query,
        status: WorkspaceDefinitionStatus.noDefinitions,
        filesSearched: documents.length,
        definitionsIndexed: definitions.length,
        definitions: const <WorkspaceDefinitionItem>[],
        message: 'No workspace definitions match `${query.pattern}`.',
      );
    }

    scoredDefinitions.sort(_compareScoredDefinitions);
    final maxResults = query.maxResults <= 0 ? 50 : query.maxResults;
    final resultDefinitions = <WorkspaceDefinitionItem>[];

    for (final scoredDefinition in scoredDefinitions.take(maxResults)) {
      final definition = scoredDefinition.definition;
      final document = documentsById[definition.documentId];
      if (document == null) {
        continue;
      }
      final position = document.positionForOffset(definition.range.start);
      resultDefinitions.add(
        WorkspaceDefinitionItem(
          filePath: definition.documentId,
          name: definition.name,
          kind: definition.kind,
          range: definition.range,
          line: position.line,
          column: position.column,
          previewText: _linePreview(document, position.line),
          type: definition.type,
        ),
      );
    }

    return WorkspaceDefinitionResult(
      query: query,
      status: scoredDefinitions.length > maxResults
          ? WorkspaceDefinitionStatus.hitLimit
          : WorkspaceDefinitionStatus.completed,
      filesSearched: documents.length,
      definitionsIndexed: definitions.length,
      definitions: List<WorkspaceDefinitionItem>.unmodifiable(
        resultDefinitions,
      ),
      message: scoredDefinitions.length > maxResults
          ? 'Go to Definition stopped after $maxResults definition(s).'
          : null,
    );
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
    WorkspaceDefinitionQuery query,
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

  static _WorkspaceDefinitionScore? _scoreDefinition({
    required StyioProjectSymbolDefinition definition,
    required String normalizedPattern,
    required int definitionIndex,
  }) {
    final normalizedName = definition.name.toLowerCase();
    final normalizedKind = definition.kind.name;
    final normalizedPath = _displayPath(definition.documentId).toLowerCase();
    final normalizedType = definition.type?.toLowerCase();
    final kindBoost = _kindBoost(definition.kind);

    final nameDirect = _directMatch(
      candidate: normalizedName,
      pattern: normalizedPattern,
      exactScore: 12000,
      prefixScore: 10200,
      containsScore: 9000,
    );
    if (nameDirect != null) {
      return nameDirect.withBoost(kindBoost);
    }

    final compactPattern = _compactPattern(normalizedPattern);
    final nameFuzzy = _orderedCharacterMatch(
      candidate: normalizedName,
      pattern: compactPattern,
      baseScore: 6200,
    );
    if (nameFuzzy != null) {
      return nameFuzzy.withBoost(kindBoost);
    }

    final kindDirect = _directMatch(
      candidate: normalizedKind,
      pattern: normalizedPattern,
      exactScore: 3800,
      prefixScore: 3400,
      containsScore: 3000,
    );
    final pathDirect = _directMatch(
      candidate: normalizedPath,
      pattern: normalizedPattern,
      exactScore: 3400,
      prefixScore: 3100,
      containsScore: 2800,
    );
    final typeDirect = normalizedType == null
        ? null
        : _directMatch(
            candidate: normalizedType,
            pattern: normalizedPattern,
            exactScore: 2600,
            prefixScore: 2400,
            containsScore: 2200,
          );
    final fallback = _bestScore(_bestScore(kindDirect, pathDirect), typeDirect);
    if (fallback == null) {
      return null;
    }
    final cappedDefinitionIndex = definitionIndex > 250
        ? 250
        : definitionIndex;
    return fallback.withBoost(kindBoost - cappedDefinitionIndex);
  }

  static _WorkspaceDefinitionScore? _directMatch({
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
      return _WorkspaceDefinitionScore(value: exactScore);
    }
    if (candidate.startsWith(pattern)) {
      return _WorkspaceDefinitionScore(
        value: prefixScore - (candidate.length - pattern.length),
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _WorkspaceDefinitionScore(value: containsScore - index);
    }
    return null;
  }

  static _WorkspaceDefinitionScore? _orderedCharacterMatch({
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
    return _WorkspaceDefinitionScore(value: score);
  }

  static _WorkspaceDefinitionScore? _bestScore(
    _WorkspaceDefinitionScore? first,
    _WorkspaceDefinitionScore? second,
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
    return pattern
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^[@#]+'), '')
        .toLowerCase();
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
    _ScoredWorkspaceDefinition first,
    _ScoredWorkspaceDefinition second,
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

class _WorkspaceDefinitionScore {
  const _WorkspaceDefinitionScore({required this.value});

  final int value;

  _WorkspaceDefinitionScore withBoost(int boost) {
    if (boost == 0) {
      return this;
    }
    return _WorkspaceDefinitionScore(value: value + boost);
  }
}

class _ScoredWorkspaceDefinition {
  const _ScoredWorkspaceDefinition({
    required this.definition,
    required this.score,
    required this.definitionIndex,
  });

  final StyioProjectSymbolDefinition definition;
  final _WorkspaceDefinitionScore score;
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
