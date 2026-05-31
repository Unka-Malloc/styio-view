import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceSymbolSearchStatus { completed, emptyWorkspace, hitLimit }

class WorkspaceSymbolSearchQuery {
  const WorkspaceSymbolSearchQuery({
    this.pattern = '',
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceSymbolSearchQuery copyWith({
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceSymbolSearchQuery(
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceSymbolSearchMatch {
  const WorkspaceSymbolSearchMatch({required this.start, required this.end});

  final int start;
  final int end;
}

class WorkspaceSymbolSearchItem {
  const WorkspaceSymbolSearchItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.detail,
    required this.nameRange,
    required this.declarationRange,
    required this.line,
    required this.column,
    required this.previewText,
    required this.score,
    required this.matches,
  });

  final String filePath;
  final String name;
  final SymbolKind kind;
  final String detail;
  final SourceRange nameRange;
  final SourceRange declarationRange;
  final int line;
  final int column;
  final String previewText;
  final int score;
  final List<WorkspaceSymbolSearchMatch> matches;

  String get kindLabel => _symbolKindLabel(kind);
}

class WorkspaceSymbolSearchResult {
  const WorkspaceSymbolSearchResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.symbolsIndexed,
    required this.items,
  });

  final WorkspaceSymbolSearchQuery query;
  final WorkspaceSymbolSearchStatus status;
  final int filesSearched;
  final int symbolsIndexed;
  final List<WorkspaceSymbolSearchItem> items;

  bool get hitLimit => status == WorkspaceSymbolSearchStatus.hitLimit;

  int get matchCount => items.length;

  int get matchedFileCount =>
      items.map((item) => item.filePath).toSet().length;
}

class WorkspaceSymbolSearchService {
  const WorkspaceSymbolSearchService({
    required this.documentStore,
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
  }) : _syntaxHighlighter = syntaxHighlighter,
       _symbolIndex = symbolIndex;

  final WorkspaceDocumentStore documentStore;
  final StyioSyntaxHighlighter _syntaxHighlighter;
  final StyioSymbolIndex _symbolIndex;

  Future<WorkspaceSymbolSearchResult> searchSymbols({
    required List<String> filePaths,
    required WorkspaceSymbolSearchQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceSymbolSearchResult(
        query: query,
        status: WorkspaceSymbolSearchStatus.emptyWorkspace,
        filesSearched: 0,
        symbolsIndexed: 0,
        items: const <WorkspaceSymbolSearchItem>[],
      );
    }

    final normalizedPattern = _normalizedPattern(query.pattern);
    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final scoredItems = <_ScoredWorkspaceSymbolItem>[];
    var filesSearched = 0;
    var symbolsIndexed = 0;

    for (
      var fileIndex = 0;
      fileIndex < uniqueFilePaths.length;
      fileIndex += 1
    ) {
      final filePath = uniqueFilePaths[fileIndex];
      final document =
          overlayDocuments[filePath] ??
          await documentStore.loadDocument(filePath);
      filesSearched += 1;

      final snapshot = _symbolIndex.build(
        _syntaxHighlighter.tokenize(document.text),
      );
      symbolsIndexed += snapshot.symbols.length;

      for (
        var symbolIndex = 0;
        symbolIndex < snapshot.symbols.length;
        symbolIndex += 1
      ) {
        final symbol = snapshot.symbols[symbolIndex];
        final score = _scoreSymbol(
          symbol: symbol,
          filePath: filePath,
          normalizedPattern: normalizedPattern,
          fileIndex: fileIndex,
          symbolIndex: symbolIndex,
        );
        if (score == null) {
          continue;
        }

        final position = document.positionForOffset(symbol.nameRange.start);
        scoredItems.add(
          _ScoredWorkspaceSymbolItem(
            item: WorkspaceSymbolSearchItem(
              filePath: filePath,
              name: symbol.name,
              kind: symbol.kind,
              detail: symbol.detail,
              nameRange: symbol.nameRange,
              declarationRange: symbol.declarationRange,
              line: position.line,
              column: position.column,
              previewText: _linePreview(document, position.line),
              score: score.value,
              matches: List<WorkspaceSymbolSearchMatch>.unmodifiable(
                score.matches,
              ),
            ),
            fileIndex: fileIndex,
            symbolIndex: symbolIndex,
          ),
        );
      }
    }

    scoredItems.sort(_compareWorkspaceSymbolItems);
    final limitedItems = scoredItems
        .take(maxResults)
        .map((entry) => entry.item)
        .toList(growable: false);

    return WorkspaceSymbolSearchResult(
      query: query,
      status: scoredItems.length > maxResults
          ? WorkspaceSymbolSearchStatus.hitLimit
          : WorkspaceSymbolSearchStatus.completed,
      filesSearched: filesSearched,
      symbolsIndexed: symbolsIndexed,
      items: List<WorkspaceSymbolSearchItem>.unmodifiable(limitedItems),
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
    WorkspaceSymbolSearchQuery query,
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

  static _WorkspaceSymbolScore? _scoreSymbol({
    required DocumentSymbol symbol,
    required String filePath,
    required String normalizedPattern,
    required int fileIndex,
    required int symbolIndex,
  }) {
    final kindBoost = _kindBoost(symbol.kind);
    if (normalizedPattern.isEmpty) {
      final cappedFileIndex = fileIndex > 999 ? 999 : fileIndex;
      final cappedSymbolIndex = symbolIndex > 99 ? 99 : symbolIndex;
      return _WorkspaceSymbolScore(
        value: 1700 + kindBoost - cappedFileIndex * 4 - cappedSymbolIndex,
        matches: const <WorkspaceSymbolSearchMatch>[],
      );
    }

    final normalizedName = symbol.name.toLowerCase();
    final normalizedKind = _symbolKindLabel(symbol.kind);
    final normalizedFilePath = _displayPath(filePath).toLowerCase();
    final splitQuery = _splitQuery(normalizedPattern);
    final symbolPattern = splitQuery.symbolPattern;
    final containerPattern = splitQuery.containerPattern;

    var score = _bestScore(
      _directMatch(
        candidate: normalizedName,
        pattern: symbolPattern,
        exactScore: 11000,
        prefixScore: 9800,
        containsScore: 8600,
      ),
      _orderedCharacterMatch(
        candidate: normalizedName,
        pattern: _compactPattern(symbolPattern),
        baseScore: 5600,
      ),
    );

    if (containerPattern.isNotEmpty) {
      final containerScore = _bestScore(
        _directMatch(
          candidate: normalizedFilePath,
          pattern: containerPattern,
          exactScore: 3200,
          prefixScore: 3000,
          containsScore: 2800,
          highlight: false,
        ),
        _directMatch(
          candidate: normalizedKind,
          pattern: containerPattern,
          exactScore: 3000,
          prefixScore: 2800,
          containsScore: 2400,
          highlight: false,
        ),
      );
      if (containerScore == null) {
        return null;
      }
      if (score == null) {
        score = containerScore;
      } else {
        score = score.withBoost(containerScore.value ~/ 2);
      }
    }

    score ??= _bestScore(
      _directMatch(
        candidate: normalizedKind,
        pattern: normalizedPattern,
        exactScore: 4600,
        prefixScore: 4200,
        containsScore: 3600,
        highlight: false,
      ),
      _directMatch(
        candidate: normalizedFilePath,
        pattern: normalizedPattern,
        exactScore: 3800,
        prefixScore: 3500,
        containsScore: 3200,
        highlight: false,
      ),
    );

    return score?.withBoost(kindBoost);
  }

  static _WorkspaceSymbolScore? _directMatch({
    required String candidate,
    required String pattern,
    required int exactScore,
    required int prefixScore,
    required int containsScore,
    bool highlight = true,
  }) {
    if (pattern.isEmpty) {
      return null;
    }
    if (candidate == pattern) {
      return _WorkspaceSymbolScore(
        value: exactScore,
        matches: highlight
            ? <WorkspaceSymbolSearchMatch>[
                WorkspaceSymbolSearchMatch(start: 0, end: pattern.length),
              ]
            : const <WorkspaceSymbolSearchMatch>[],
      );
    }
    if (candidate.startsWith(pattern)) {
      return _WorkspaceSymbolScore(
        value: prefixScore - (candidate.length - pattern.length),
        matches: highlight
            ? <WorkspaceSymbolSearchMatch>[
                WorkspaceSymbolSearchMatch(start: 0, end: pattern.length),
              ]
            : const <WorkspaceSymbolSearchMatch>[],
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _WorkspaceSymbolScore(
        value: containsScore - index,
        matches: highlight
            ? <WorkspaceSymbolSearchMatch>[
                WorkspaceSymbolSearchMatch(
                  start: index,
                  end: index + pattern.length,
                ),
              ]
            : const <WorkspaceSymbolSearchMatch>[],
      );
    }
    return null;
  }

  static _WorkspaceSymbolScore? _orderedCharacterMatch({
    required String candidate,
    required String pattern,
    required int baseScore,
  }) {
    if (pattern.isEmpty) {
      return null;
    }
    final indices = <int>[];
    var cursor = 0;
    var lastIndex = -2;
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
      indices.add(matchIndex);
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

    if (indices.isNotEmpty) {
      score -= indices.first;
    }

    return _WorkspaceSymbolScore(
      value: score,
      matches: _rangesFromIndices(indices),
    );
  }

  static _WorkspaceSymbolScore? _bestScore(
    _WorkspaceSymbolScore? first,
    _WorkspaceSymbolScore? second,
  ) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.value >= second.value ? first : second;
  }

  static List<WorkspaceSymbolSearchMatch> _rangesFromIndices(
    List<int> indices,
  ) {
    if (indices.isEmpty) {
      return const <WorkspaceSymbolSearchMatch>[];
    }
    final ranges = <WorkspaceSymbolSearchMatch>[];
    var rangeStart = indices.first;
    var previous = indices.first;
    for (final index in indices.skip(1)) {
      if (index == previous + 1) {
        previous = index;
        continue;
      }
      ranges.add(
        WorkspaceSymbolSearchMatch(start: rangeStart, end: previous + 1),
      );
      rangeStart = index;
      previous = index;
    }
    ranges.add(
      WorkspaceSymbolSearchMatch(start: rangeStart, end: previous + 1),
    );
    return ranges;
  }

  static _SplitWorkspaceSymbolQuery _splitQuery(String pattern) {
    final parts = pattern
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 1) {
      return _SplitWorkspaceSymbolQuery(
        symbolPattern: pattern,
        containerPattern: '',
      );
    }
    return _SplitWorkspaceSymbolQuery(
      symbolPattern: parts.first,
      containerPattern: parts.skip(1).join(' '),
    );
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

  static int _kindBoost(SymbolKind kind) {
    return switch (kind) {
      SymbolKind.function => 260,
      SymbolKind.pipeline => 230,
      SymbolKind.state => 220,
      SymbolKind.resource => 210,
      SymbolKind.task => 200,
      SymbolKind.variable => 120,
      SymbolKind.parameter => 80,
    };
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

  static int _compareWorkspaceSymbolItems(
    _ScoredWorkspaceSymbolItem first,
    _ScoredWorkspaceSymbolItem second,
  ) {
    final scoreCompare = second.item.score.compareTo(first.item.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final nameCompare = first.item.name.toLowerCase().compareTo(
      second.item.name.toLowerCase(),
    );
    if (nameCompare != 0) {
      return nameCompare;
    }
    final kindCompare = first.item.kindLabel.compareTo(second.item.kindLabel);
    if (kindCompare != 0) {
      return kindCompare;
    }
    final fileCompare = first.item.filePath.compareTo(second.item.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    final offsetCompare = first.item.nameRange.start.compareTo(
      second.item.nameRange.start,
    );
    if (offsetCompare != 0) {
      return offsetCompare;
    }
    final fileIndexCompare = first.fileIndex.compareTo(second.fileIndex);
    if (fileIndexCompare != 0) {
      return fileIndexCompare;
    }
    return first.symbolIndex.compareTo(second.symbolIndex);
  }
}

String _symbolKindLabel(SymbolKind kind) {
  return switch (kind) {
    SymbolKind.function => 'function',
    SymbolKind.pipeline => 'pipeline',
    SymbolKind.state => 'state',
    SymbolKind.resource => 'resource',
    SymbolKind.variable => 'variable',
    SymbolKind.parameter => 'parameter',
    SymbolKind.task => 'task',
  };
}

class _WorkspaceSymbolScore {
  const _WorkspaceSymbolScore({required this.value, required this.matches});

  final int value;
  final List<WorkspaceSymbolSearchMatch> matches;

  _WorkspaceSymbolScore withBoost(int boost) {
    if (boost == 0) {
      return this;
    }
    return _WorkspaceSymbolScore(value: value + boost, matches: matches);
  }
}

class _ScoredWorkspaceSymbolItem {
  const _ScoredWorkspaceSymbolItem({
    required this.item,
    required this.fileIndex,
    required this.symbolIndex,
  });

  final WorkspaceSymbolSearchItem item;
  final int fileIndex;
  final int symbolIndex;
}

class _SplitWorkspaceSymbolQuery {
  const _SplitWorkspaceSymbolQuery({
    required this.symbolPattern,
    required this.containerPattern,
  });

  final String symbolPattern;
  final String containerPattern;
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
