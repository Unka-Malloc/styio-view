import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceCallHierarchyStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noDefinitions,
  hitLimit,
}

enum WorkspaceCallHierarchyDirection { incoming, outgoing }

enum WorkspaceCallHierarchySymbolKind { function, task, topLevel }

class WorkspaceCallHierarchyQuery {
  const WorkspaceCallHierarchyQuery({
    required this.pattern,
    this.direction = WorkspaceCallHierarchyDirection.incoming,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final WorkspaceCallHierarchyDirection direction;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceCallHierarchyQuery copyWith({
    String? pattern,
    WorkspaceCallHierarchyDirection? direction,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceCallHierarchyQuery(
      pattern: pattern ?? this.pattern,
      direction: direction ?? this.direction,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceCallHierarchySymbol {
  const WorkspaceCallHierarchySymbol({
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
  final WorkspaceCallHierarchySymbolKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final String? type;

  bool get isTopLevel => kind == WorkspaceCallHierarchySymbolKind.topLevel;

  String get kindLabel => _callHierarchySymbolKindLabel(kind);
}

class WorkspaceCallHierarchyLocation {
  const WorkspaceCallHierarchyLocation({
    required this.filePath,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
  });

  final String filePath;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
}

class WorkspaceCallHierarchyCall {
  const WorkspaceCallHierarchyCall({
    required this.symbol,
    required this.locations,
  });

  final WorkspaceCallHierarchySymbol symbol;
  final List<WorkspaceCallHierarchyLocation> locations;

  int get referenceCount => locations.length;

  WorkspaceCallHierarchyLocation get firstLocation => locations.first;
}

class WorkspaceCallHierarchyResult {
  const WorkspaceCallHierarchyResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.definitionsSearched,
    required this.target,
    required this.calls,
    this.message,
  });

  final WorkspaceCallHierarchyQuery query;
  final WorkspaceCallHierarchyStatus status;
  final int filesSearched;
  final int definitionsSearched;
  final WorkspaceCallHierarchySymbol? target;
  final List<WorkspaceCallHierarchyCall> calls;
  final String? message;

  bool get hitLimit => status == WorkspaceCallHierarchyStatus.hitLimit;

  int get callCount => calls.length;

  int get referenceCount => calls.fold<int>(
    0,
    (count, call) => count + call.referenceCount,
  );

  int get matchedFileCount =>
      calls.map((call) => call.symbol.filePath).toSet().length;
}

class WorkspaceCallHierarchyService {
  const WorkspaceCallHierarchyService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceCallHierarchyResult> buildHierarchy({
    required List<String> filePaths,
    required WorkspaceCallHierarchyQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final normalizedPattern = _normalizedPattern(query.pattern);
    if (normalizedPattern.isEmpty) {
      return WorkspaceCallHierarchyResult(
        query: query,
        status: WorkspaceCallHierarchyStatus.emptyPattern,
        filesSearched: 0,
        definitionsSearched: 0,
        target: null,
        calls: const <WorkspaceCallHierarchyCall>[],
        message: 'Call Hierarchy requires a symbol name.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceCallHierarchyResult(
        query: query,
        status: WorkspaceCallHierarchyStatus.emptyWorkspace,
        filesSearched: 0,
        definitionsSearched: 0,
        target: null,
        calls: const <WorkspaceCallHierarchyCall>[],
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
    final definitions = _callableDefinitionsForDocuments(
      analysis.symbolSnapshot,
      documents,
    );
    final scoredDefinitions = <_ScoredCallHierarchyDefinition>[];

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
        _ScoredCallHierarchyDefinition(
          definition: definition,
          score: score,
          definitionIndex: index,
        ),
      );
    }

    if (scoredDefinitions.isEmpty) {
      return WorkspaceCallHierarchyResult(
        query: query,
        status: WorkspaceCallHierarchyStatus.noDefinitions,
        filesSearched: documents.length,
        definitionsSearched: definitions.length,
        target: null,
        calls: const <WorkspaceCallHierarchyCall>[],
        message: 'No callable workspace symbols match `${query.pattern}`.',
      );
    }

    scoredDefinitions.sort(_compareScoredDefinitions);
    final targetDefinition = scoredDefinitions.first.definition;
    final extentsByDocument = _callableExtentsForDocuments(
      documents: documents,
      definitions: definitions,
    );
    final targetExtent = _extentForDefinition(
      extentsByDocument,
      targetDefinition,
    );
    final targetDocument = documentsById[targetDefinition.documentId];
    final target = targetDocument == null
        ? null
        : _symbolForDefinition(targetDefinition, targetDocument);
    if (target == null) {
      return WorkspaceCallHierarchyResult(
        query: query,
        status: WorkspaceCallHierarchyStatus.noDefinitions,
        filesSearched: documents.length,
        definitionsSearched: definitions.length,
        target: null,
        calls: const <WorkspaceCallHierarchyCall>[],
      );
    }

    final accumulatorByKey = <String, _CallAccumulator>{};
    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    var locationCount = 0;
    var hitLimit = false;

    void addCall({
      required WorkspaceCallHierarchySymbol symbol,
      required WorkspaceCallHierarchyLocation location,
    }) {
      if (hitLimit) {
        return;
      }
      final key = _symbolKey(symbol);
      accumulatorByKey
          .putIfAbsent(key, () => _CallAccumulator(symbol))
          .locations
          .add(location);
      locationCount += 1;
      if (locationCount >= maxResults) {
        hitLimit = true;
      }
    }

    switch (query.direction) {
      case WorkspaceCallHierarchyDirection.incoming:
        for (final reference in analysis.symbolSnapshot.referencesFor(
          targetDefinition,
        )) {
          if (reference.isDefinition) {
            continue;
          }
          final document = documentsById[reference.documentId];
          if (document == null) {
            continue;
          }
          final callerExtent = _enclosingCallableExtent(
            extentsByDocument,
            reference.documentId,
            reference.range.start,
          );
          final callerSymbol = callerExtent == null
              ? _topLevelSymbolForDocument(document)
              : _symbolForDefinition(callerExtent.definition, document);
          addCall(
            symbol: callerSymbol,
            location: _locationForReference(document, reference.range),
          );
          if (hitLimit) {
            break;
          }
        }
      case WorkspaceCallHierarchyDirection.outgoing:
        final extent = targetExtent;
        if (extent != null) {
          for (final definition in definitions) {
            for (final reference in analysis.symbolSnapshot.referencesFor(
              definition,
            )) {
              if (reference.isDefinition ||
                  reference.documentId != targetDefinition.documentId ||
                  !extent.range.contains(reference.range.start)) {
                continue;
              }
              final document = documentsById[reference.documentId];
              final calleeDocument = documentsById[definition.documentId];
              if (document == null || calleeDocument == null) {
                continue;
              }
              addCall(
                symbol: _symbolForDefinition(definition, calleeDocument),
                location: _locationForReference(document, reference.range),
              );
              if (hitLimit) {
                break;
              }
            }
            if (hitLimit) {
              break;
            }
          }
        }
    }

    final calls = accumulatorByKey.values
        .map(
          (accumulator) => WorkspaceCallHierarchyCall(
            symbol: accumulator.symbol,
            locations: List<WorkspaceCallHierarchyLocation>.unmodifiable(
              accumulator.locations,
            ),
          ),
        )
        .toList(growable: false)
      ..sort(_compareCalls);
    final directionLabel =
        query.direction == WorkspaceCallHierarchyDirection.incoming
        ? 'incoming'
        : 'outgoing';

    return WorkspaceCallHierarchyResult(
      query: query,
      status: hitLimit
          ? WorkspaceCallHierarchyStatus.hitLimit
          : WorkspaceCallHierarchyStatus.completed,
      filesSearched: documents.length,
      definitionsSearched: definitions.length,
      target: target,
      calls: List<WorkspaceCallHierarchyCall>.unmodifiable(calls),
      message: calls.isEmpty
          ? 'No $directionLabel calls found for `${target.name}`.'
          : hitLimit
          ? 'Call Hierarchy stopped after $maxResults reference(s).'
          : null,
    );
  }

  static List<StyioProjectSymbolDefinition> _callableDefinitionsForDocuments(
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
    definitions.sort((first, second) {
      final fileCompare = first.documentId.compareTo(second.documentId);
      if (fileCompare != 0) {
        return fileCompare;
      }
      return first.range.start.compareTo(second.range.start);
    });
    return definitions;
  }

  static Map<String, List<_CallableExtent>> _callableExtentsForDocuments({
    required List<DocumentState> documents,
    required List<StyioProjectSymbolDefinition> definitions,
  }) {
    final definitionsByDocument = <String, List<StyioProjectSymbolDefinition>>{};
    for (final definition in definitions) {
      definitionsByDocument
          .putIfAbsent(
            definition.documentId,
            () => <StyioProjectSymbolDefinition>[],
          )
          .add(definition);
    }

    final extentsByDocument = <String, List<_CallableExtent>>{};
    for (final document in documents) {
      final documentDefinitions =
          definitionsByDocument[document.documentId] ??
          const <StyioProjectSymbolDefinition>[];
      if (documentDefinitions.isEmpty) {
        continue;
      }
      final sortedDefinitions = [...documentDefinitions]
        ..sort((first, second) => first.range.start.compareTo(
          second.range.start,
        ));
      final extents = <_CallableExtent>[];
      for (var index = 0; index < sortedDefinitions.length; index += 1) {
        final definition = sortedDefinitions[index];
        final nextDefinitionStart = index + 1 < sortedDefinitions.length
            ? sortedDefinitions[index + 1].range.start
            : document.length;
        final start = _lineStartForOffset(document, definition.range.start);
        final blockEnd = _matchingBlockEnd(document.text, start);
        final end = blockEnd == null || blockEnd > nextDefinitionStart
            ? nextDefinitionStart
            : blockEnd;
        extents.add(
          _CallableExtent(
            definition: definition,
            range: SourceRange(start: start, end: end),
          ),
        );
      }
      extentsByDocument[document.documentId] =
          List<_CallableExtent>.unmodifiable(extents);
    }
    return extentsByDocument;
  }

  static _CallableExtent? _extentForDefinition(
    Map<String, List<_CallableExtent>> extentsByDocument,
    StyioProjectSymbolDefinition definition,
  ) {
    final extents = extentsByDocument[definition.documentId];
    if (extents == null) {
      return null;
    }
    for (final extent in extents) {
      if (_sameDefinition(extent.definition, definition)) {
        return extent;
      }
    }
    return null;
  }

  static _CallableExtent? _enclosingCallableExtent(
    Map<String, List<_CallableExtent>> extentsByDocument,
    String documentId,
    int offset,
  ) {
    final extents = extentsByDocument[documentId];
    if (extents == null) {
      return null;
    }
    for (final extent in extents.reversed) {
      if (extent.range.contains(offset)) {
        return extent;
      }
    }
    return null;
  }

  static WorkspaceCallHierarchySymbol _symbolForDefinition(
    StyioProjectSymbolDefinition definition,
    DocumentState document,
  ) {
    final position = document.positionForOffset(definition.range.start);
    return WorkspaceCallHierarchySymbol(
      filePath: definition.documentId,
      name: definition.name,
      kind: _symbolKindForDefinition(definition.kind),
      range: definition.range,
      line: position.line,
      column: position.column,
      previewText: _linePreview(document, position.line),
      type: definition.type,
    );
  }

  static WorkspaceCallHierarchySymbol _topLevelSymbolForDocument(
    DocumentState document,
  ) {
    return WorkspaceCallHierarchySymbol(
      filePath: document.documentId,
      name: '<top-level>',
      kind: WorkspaceCallHierarchySymbolKind.topLevel,
      range: const SourceRange(start: 0, end: 0),
      line: 0,
      column: 0,
      previewText: document.lines.isEmpty ? '' : document.lines.first,
    );
  }

  static WorkspaceCallHierarchyLocation _locationForReference(
    DocumentState document,
    SourceRange range,
  ) {
    final position = document.positionForOffset(range.start);
    return WorkspaceCallHierarchyLocation(
      filePath: document.documentId,
      range: range,
      line: position.line,
      column: position.column,
      previewText: _linePreview(document, position.line),
    );
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
    WorkspaceCallHierarchyQuery query,
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

  static _CallHierarchyDefinitionScore? _scoreDefinition({
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

  static _CallHierarchyDefinitionScore? _directMatch({
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
      return _CallHierarchyDefinitionScore(value: exactScore);
    }
    if (candidate.startsWith(pattern)) {
      return _CallHierarchyDefinitionScore(
        value: prefixScore - (candidate.length - pattern.length),
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _CallHierarchyDefinitionScore(value: containsScore - index);
    }
    return null;
  }

  static _CallHierarchyDefinitionScore? _orderedCharacterMatch({
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
    return _CallHierarchyDefinitionScore(value: score);
  }

  static _CallHierarchyDefinitionScore? _bestScore(
    _CallHierarchyDefinitionScore? first,
    _CallHierarchyDefinitionScore? second,
  ) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.value >= second.value ? first : second;
  }

  static WorkspaceCallHierarchySymbolKind _symbolKindForDefinition(
    StyioProjectSymbolKind kind,
  ) {
    return switch (kind) {
      StyioProjectSymbolKind.function =>
        WorkspaceCallHierarchySymbolKind.function,
      StyioProjectSymbolKind.task => WorkspaceCallHierarchySymbolKind.task,
      StyioProjectSymbolKind.resource =>
        WorkspaceCallHierarchySymbolKind.topLevel,
    };
  }

  static int _lineStartForOffset(DocumentState document, int offset) {
    final starts = document.lineStarts;
    final safeOffset = offset.clamp(0, document.length);
    for (var index = starts.length - 1; index >= 0; index -= 1) {
      if (safeOffset >= starts[index]) {
        return starts[index];
      }
    }
    return 0;
  }

  static int? _matchingBlockEnd(String source, int start) {
    final openIndex = source.indexOf('{', start);
    if (openIndex < 0) {
      return null;
    }
    var depth = 0;
    for (var index = openIndex; index < source.length; index += 1) {
      final char = source[index];
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index + 1;
        }
      }
    }
    return source.length;
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

  static bool _sameDefinition(
    StyioProjectSymbolDefinition first,
    StyioProjectSymbolDefinition second,
  ) {
    return first.documentId == second.documentId &&
        first.kind == second.kind &&
        first.name == second.name &&
        first.range.start == second.range.start &&
        first.range.end == second.range.end;
  }

  static int _kindBoost(StyioProjectSymbolKind kind) {
    return switch (kind) {
      StyioProjectSymbolKind.function => 260,
      StyioProjectSymbolKind.task => 220,
      StyioProjectSymbolKind.resource => 0,
    };
  }

  static int _compareScoredDefinitions(
    _ScoredCallHierarchyDefinition first,
    _ScoredCallHierarchyDefinition second,
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

  static int _compareCalls(
    WorkspaceCallHierarchyCall first,
    WorkspaceCallHierarchyCall second,
  ) {
    final fileCompare = first.symbol.filePath.compareTo(second.symbol.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    final lineCompare = first.firstLocation.line.compareTo(
      second.firstLocation.line,
    );
    if (lineCompare != 0) {
      return lineCompare;
    }
    return first.symbol.name.compareTo(second.symbol.name);
  }

  static String _symbolKey(WorkspaceCallHierarchySymbol symbol) {
    return '${symbol.kind.name}:${symbol.filePath}:'
        '${symbol.range.start}:${symbol.range.end}:${symbol.name}';
  }
}

String _callHierarchySymbolKindLabel(WorkspaceCallHierarchySymbolKind kind) {
  return switch (kind) {
    WorkspaceCallHierarchySymbolKind.function => 'function',
    WorkspaceCallHierarchySymbolKind.task => 'task',
    WorkspaceCallHierarchySymbolKind.topLevel => 'top level',
  };
}

class _CallableExtent {
  const _CallableExtent({required this.definition, required this.range});

  final StyioProjectSymbolDefinition definition;
  final SourceRange range;
}

class _CallAccumulator {
  _CallAccumulator(this.symbol);

  final WorkspaceCallHierarchySymbol symbol;
  final List<WorkspaceCallHierarchyLocation> locations =
      <WorkspaceCallHierarchyLocation>[];
}

class _CallHierarchyDefinitionScore {
  const _CallHierarchyDefinitionScore({required this.value});

  final int value;

  _CallHierarchyDefinitionScore withBoost(int boost) {
    if (boost == 0) {
      return this;
    }
    return _CallHierarchyDefinitionScore(value: value + boost);
  }
}

class _ScoredCallHierarchyDefinition {
  const _ScoredCallHierarchyDefinition({
    required this.definition,
    required this.score,
    required this.definitionIndex,
  });

  final StyioProjectSymbolDefinition definition;
  final _CallHierarchyDefinitionScore score;
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
