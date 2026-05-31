import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_definition.dart';
import 'workspace_document_store_types.dart';
import 'workspace_type_definition.dart';

enum WorkspaceDeclarationStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noDeclarations,
  hitLimit,
}

enum WorkspaceDeclarationKind { function, resource, task, schema, state }

class WorkspaceDeclarationQuery {
  const WorkspaceDeclarationQuery({
    required this.pattern,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 50,
  });

  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceDeclarationQuery copyWith({
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceDeclarationQuery(
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceDeclarationItem {
  const WorkspaceDeclarationItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    this.type,
  });

  factory WorkspaceDeclarationItem.fromDefinition(
    WorkspaceDefinitionItem item,
  ) {
    return WorkspaceDeclarationItem(
      filePath: item.filePath,
      name: item.name,
      kind: switch (item.kind) {
        StyioProjectSymbolKind.function => WorkspaceDeclarationKind.function,
        StyioProjectSymbolKind.resource => WorkspaceDeclarationKind.resource,
        StyioProjectSymbolKind.task => WorkspaceDeclarationKind.task,
      },
      range: item.range,
      line: item.line,
      column: item.column,
      previewText: item.previewText,
      type: item.type,
    );
  }

  factory WorkspaceDeclarationItem.fromTypeDefinition(
    WorkspaceTypeDefinitionItem item,
  ) {
    return WorkspaceDeclarationItem(
      filePath: item.filePath,
      name: item.name,
      kind: switch (item.kind) {
        WorkspaceTypeDefinitionKind.schema => WorkspaceDeclarationKind.schema,
        WorkspaceTypeDefinitionKind.state => WorkspaceDeclarationKind.state,
      },
      range: item.range,
      line: item.line,
      column: item.column,
      previewText: item.previewText,
    );
  }

  final String filePath;
  final String name;
  final WorkspaceDeclarationKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final String? type;

  String get kindLabel {
    return switch (kind) {
      WorkspaceDeclarationKind.function => 'function',
      WorkspaceDeclarationKind.resource => 'resource',
      WorkspaceDeclarationKind.task => 'task',
      WorkspaceDeclarationKind.schema => 'schema',
      WorkspaceDeclarationKind.state => 'state',
    };
  }
}

class WorkspaceDeclarationResult {
  const WorkspaceDeclarationResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.declarationsIndexed,
    required this.declarations,
    this.message,
  });

  final WorkspaceDeclarationQuery query;
  final WorkspaceDeclarationStatus status;
  final int filesSearched;
  final int declarationsIndexed;
  final List<WorkspaceDeclarationItem> declarations;
  final String? message;

  bool get hitLimit => status == WorkspaceDeclarationStatus.hitLimit;

  int get matchCount => declarations.length;

  int get matchedFileCount =>
      declarations.map((declaration) => declaration.filePath).toSet().length;
}

class WorkspaceDeclarationService {
  const WorkspaceDeclarationService({
    required this.documentStore,
    WorkspaceDefinitionService? definitionService,
    WorkspaceTypeDefinitionService? typeDefinitionService,
  }) : _definitionService = definitionService,
       _typeDefinitionService = typeDefinitionService;

  final WorkspaceDocumentStore documentStore;
  final WorkspaceDefinitionService? _definitionService;
  final WorkspaceTypeDefinitionService? _typeDefinitionService;

  Future<WorkspaceDeclarationResult> findDeclarations({
    required List<String> filePaths,
    required WorkspaceDeclarationQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final maxResults = query.maxResults <= 0 ? 50 : query.maxResults;
    final definitionService =
        _definitionService ??
        WorkspaceDefinitionService(documentStore: documentStore);
    final typeDefinitionService =
        _typeDefinitionService ??
        WorkspaceTypeDefinitionService(documentStore: documentStore);
    final delegateLimit = maxResults + 1;

    final definitionResult = await definitionService.findDefinitions(
      filePaths: filePaths,
      query: WorkspaceDefinitionQuery(
        pattern: query.pattern,
        includeGlobs: query.includeGlobs,
        excludeGlobs: query.excludeGlobs,
        maxResults: delegateLimit,
      ),
      overlayDocuments: overlayDocuments,
    );
    final typeResult = await typeDefinitionService.findTypeDefinitions(
      filePaths: filePaths,
      query: WorkspaceTypeDefinitionQuery(
        pattern: query.pattern,
        includeGlobs: query.includeGlobs,
        excludeGlobs: query.excludeGlobs,
        maxResults: delegateLimit,
      ),
      overlayDocuments: overlayDocuments,
    );

    final filesSearched = _max(
      definitionResult.filesSearched,
      typeResult.filesSearched,
    );
    final declarationsIndexed =
        definitionResult.definitionsIndexed + typeResult.typesIndexed;

    if (definitionResult.status == WorkspaceDefinitionStatus.emptyPattern &&
        typeResult.status == WorkspaceTypeDefinitionStatus.emptyPattern) {
      return WorkspaceDeclarationResult(
        query: query,
        status: WorkspaceDeclarationStatus.emptyPattern,
        filesSearched: 0,
        declarationsIndexed: 0,
        declarations: const <WorkspaceDeclarationItem>[],
        message: 'Go to Declaration requires a symbol name.',
      );
    }

    if (definitionResult.status == WorkspaceDefinitionStatus.emptyWorkspace &&
        typeResult.status == WorkspaceTypeDefinitionStatus.emptyWorkspace) {
      return WorkspaceDeclarationResult(
        query: query,
        status: WorkspaceDeclarationStatus.emptyWorkspace,
        filesSearched: 0,
        declarationsIndexed: 0,
        declarations: const <WorkspaceDeclarationItem>[],
      );
    }

    final declarations = <WorkspaceDeclarationItem>[
      for (final item in definitionResult.definitions)
        WorkspaceDeclarationItem.fromDefinition(item),
      for (final item in typeResult.types)
        WorkspaceDeclarationItem.fromTypeDefinition(item),
    ];

    if (declarations.isEmpty) {
      return WorkspaceDeclarationResult(
        query: query,
        status: WorkspaceDeclarationStatus.noDeclarations,
        filesSearched: filesSearched,
        declarationsIndexed: declarationsIndexed,
        declarations: const <WorkspaceDeclarationItem>[],
        message: 'No workspace declarations match `${query.pattern}`.',
      );
    }

    final normalizedPattern = _normalizedPattern(query.pattern);
    final scoredDeclarations = <_ScoredWorkspaceDeclaration>[];
    for (var index = 0; index < declarations.length; index += 1) {
      final declaration = declarations[index];
      scoredDeclarations.add(
        _ScoredWorkspaceDeclaration(
          declaration: declaration,
          score:
              _scoreDeclaration(
                declaration: declaration,
                normalizedPattern: normalizedPattern,
                declarationIndex: index,
              ) ??
              const _WorkspaceDeclarationScore(value: 0),
          declarationIndex: index,
        ),
      );
    }

    scoredDeclarations.sort(_compareScoredDeclarations);
    final limitedDeclarations = scoredDeclarations
        .take(maxResults)
        .map((entry) => entry.declaration)
        .toList(growable: false);
    final hitLimit =
        scoredDeclarations.length > maxResults ||
        definitionResult.hitLimit ||
        typeResult.hitLimit;

    return WorkspaceDeclarationResult(
      query: query,
      status: hitLimit
          ? WorkspaceDeclarationStatus.hitLimit
          : WorkspaceDeclarationStatus.completed,
      filesSearched: filesSearched,
      declarationsIndexed: declarationsIndexed,
      declarations: List<WorkspaceDeclarationItem>.unmodifiable(
        limitedDeclarations,
      ),
      message: hitLimit
          ? 'Go to Declaration stopped after $maxResults declaration(s).'
          : null,
    );
  }

  static int _max(int first, int second) {
    return first >= second ? first : second;
  }

  static _WorkspaceDeclarationScore? _scoreDeclaration({
    required WorkspaceDeclarationItem declaration,
    required String normalizedPattern,
    required int declarationIndex,
  }) {
    final normalizedName = declaration.name.toLowerCase();
    final normalizedKind = declaration.kindLabel;
    final normalizedPath = declaration.filePath
        .replaceAll('\\', '/')
        .toLowerCase();
    final normalizedType = declaration.type?.toLowerCase();
    final kindBoost = _kindBoost(declaration.kind);

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

    final compactPattern = normalizedPattern.replaceAll(RegExp(r'\s+'), '');
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
    final cappedDeclarationIndex = declarationIndex > 250
        ? 250
        : declarationIndex;
    return fallback.withBoost(kindBoost - cappedDeclarationIndex);
  }

  static _WorkspaceDeclarationScore? _directMatch({
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
      return _WorkspaceDeclarationScore(value: exactScore);
    }
    if (candidate.startsWith(pattern)) {
      return _WorkspaceDeclarationScore(
        value: prefixScore - (candidate.length - pattern.length),
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _WorkspaceDeclarationScore(value: containsScore - index);
    }
    return null;
  }

  static _WorkspaceDeclarationScore? _orderedCharacterMatch({
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
    return _WorkspaceDeclarationScore(value: score);
  }

  static _WorkspaceDeclarationScore? _bestScore(
    _WorkspaceDeclarationScore? first,
    _WorkspaceDeclarationScore? second,
  ) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.value >= second.value ? first : second;
  }

  static String _normalizedPattern(String pattern) {
    return pattern
        .trim()
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^[@#]+'), '')
        .toLowerCase();
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

  static int _kindBoost(WorkspaceDeclarationKind kind) {
    return switch (kind) {
      WorkspaceDeclarationKind.function => 260,
      WorkspaceDeclarationKind.schema => 250,
      WorkspaceDeclarationKind.state => 240,
      WorkspaceDeclarationKind.resource => 210,
      WorkspaceDeclarationKind.task => 200,
    };
  }

  static int _compareScoredDeclarations(
    _ScoredWorkspaceDeclaration first,
    _ScoredWorkspaceDeclaration second,
  ) {
    final scoreCompare = second.score.value.compareTo(first.score.value);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final nameCompare = first.declaration.name.toLowerCase().compareTo(
      second.declaration.name.toLowerCase(),
    );
    if (nameCompare != 0) {
      return nameCompare;
    }
    final fileCompare = first.declaration.filePath.compareTo(
      second.declaration.filePath,
    );
    if (fileCompare != 0) {
      return fileCompare;
    }
    final rangeCompare = first.declaration.range.start.compareTo(
      second.declaration.range.start,
    );
    if (rangeCompare != 0) {
      return rangeCompare;
    }
    return first.declarationIndex.compareTo(second.declarationIndex);
  }
}

class _WorkspaceDeclarationScore {
  const _WorkspaceDeclarationScore({required this.value});

  final int value;

  _WorkspaceDeclarationScore withBoost(int boost) {
    return _WorkspaceDeclarationScore(value: value + boost);
  }
}

class _ScoredWorkspaceDeclaration {
  const _ScoredWorkspaceDeclaration({
    required this.declaration,
    required this.score,
    required this.declarationIndex,
  });

  final WorkspaceDeclarationItem declaration;
  final _WorkspaceDeclarationScore score;
  final int declarationIndex;
}
