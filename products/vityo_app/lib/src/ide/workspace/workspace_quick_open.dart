enum WorkspaceQuickOpenStatus { completed, emptyWorkspace, hitLimit }

class WorkspaceQuickOpenQuery {
  const WorkspaceQuickOpenQuery({this.pattern = '', this.maxResults = 50});

  final String pattern;
  final int maxResults;

  WorkspaceQuickOpenQuery copyWith({String? pattern, int? maxResults}) {
    return WorkspaceQuickOpenQuery(
      pattern: pattern ?? this.pattern,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceQuickOpenMatch {
  const WorkspaceQuickOpenMatch({required this.start, required this.end});

  final int start;
  final int end;
}

class WorkspaceQuickOpenItem {
  const WorkspaceQuickOpenItem({
    required this.filePath,
    required this.fileName,
    required this.parentPath,
    required this.score,
    required this.matches,
    this.recentRank,
  });

  final String filePath;
  final String fileName;
  final String parentPath;
  final int score;
  final List<WorkspaceQuickOpenMatch> matches;
  final int? recentRank;

  bool get isRecent => recentRank != null;
}

class WorkspaceQuickOpenResult {
  const WorkspaceQuickOpenResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.items,
  });

  final WorkspaceQuickOpenQuery query;
  final WorkspaceQuickOpenStatus status;
  final int filesSearched;
  final List<WorkspaceQuickOpenItem> items;

  bool get hitLimit => status == WorkspaceQuickOpenStatus.hitLimit;

  int get matchCount => items.length;
}

class WorkspaceQuickOpenService {
  const WorkspaceQuickOpenService();

  WorkspaceQuickOpenResult findFiles({
    required List<String> filePaths,
    required WorkspaceQuickOpenQuery query,
    List<String> recentFilePaths = const <String>[],
  }) {
    final uniqueFilePaths = _uniqueFilePaths(filePaths);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceQuickOpenResult(
        query: query,
        status: WorkspaceQuickOpenStatus.emptyWorkspace,
        filesSearched: 0,
        items: const <WorkspaceQuickOpenItem>[],
      );
    }

    final fileSet = uniqueFilePaths.toSet();
    final recentRanks = _recentRanks(
      fileSet: fileSet,
      recentFilePaths: recentFilePaths,
    );
    final normalizedPattern = _normalizedPattern(query.pattern);
    final maxResults = query.maxResults <= 0 ? 50 : query.maxResults;
    final scoredItems = <_ScoredQuickOpenItem>[];

    for (var index = 0; index < uniqueFilePaths.length; index += 1) {
      final filePath = uniqueFilePaths[index];
      final score = _scoreFile(
        filePath: filePath,
        normalizedPattern: normalizedPattern,
        recentRank: recentRanks[filePath],
        projectIndex: index,
      );
      if (score == null) {
        continue;
      }
      scoredItems.add(
        _ScoredQuickOpenItem(
          item: WorkspaceQuickOpenItem(
            filePath: filePath,
            fileName: _fileName(filePath),
            parentPath: _parentPath(filePath),
            score: score.value,
            matches: List<WorkspaceQuickOpenMatch>.unmodifiable(score.matches),
            recentRank: recentRanks[filePath],
          ),
          projectIndex: index,
        ),
      );
    }

    scoredItems.sort(_compareQuickOpenItems);
    final limitedItems = scoredItems
        .take(maxResults)
        .map((entry) => entry.item)
        .toList(growable: false);

    return WorkspaceQuickOpenResult(
      query: query,
      status: scoredItems.length > maxResults
          ? WorkspaceQuickOpenStatus.hitLimit
          : WorkspaceQuickOpenStatus.completed,
      filesSearched: uniqueFilePaths.length,
      items: List<WorkspaceQuickOpenItem>.unmodifiable(limitedItems),
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

  static Map<String, int> _recentRanks({
    required Set<String> fileSet,
    required List<String> recentFilePaths,
  }) {
    final ranks = <String, int>{};
    for (final filePath in recentFilePaths) {
      if (!fileSet.contains(filePath) || ranks.containsKey(filePath)) {
        continue;
      }
      ranks[filePath] = ranks.length;
    }
    return ranks;
  }

  static _QuickOpenScore? _scoreFile({
    required String filePath,
    required String normalizedPattern,
    required int? recentRank,
    required int projectIndex,
  }) {
    final displayPath = _displayPath(filePath);
    final normalizedPath = displayPath.toLowerCase();
    final fileNameStart = normalizedPath.lastIndexOf('/') + 1;
    final normalizedFileName = normalizedPath.substring(fileNameStart);
    final recentBoost = _recentBoost(recentRank);

    if (normalizedPattern.isEmpty) {
      final cappedIndex = projectIndex > 999 ? 999 : projectIndex;
      final baseScore = recentRank == null
          ? 1000 - cappedIndex
          : 5000 - recentRank;
      return _QuickOpenScore(value: baseScore, matches: const []);
    }

    final directFileNameMatch = _directMatch(
      candidate: normalizedFileName,
      pattern: normalizedPattern,
      offset: fileNameStart,
      exactScore: 10000,
      prefixScore: 9000,
      containsScore: 8000,
    );
    if (directFileNameMatch != null) {
      return directFileNameMatch.withBoost(recentBoost);
    }

    final directPathMatch = _directMatch(
      candidate: normalizedPath,
      pattern: normalizedPattern,
      offset: 0,
      exactScore: 7600,
      prefixScore: 7200,
      containsScore: 6800,
    );
    if (directPathMatch != null) {
      return directPathMatch.withBoost(recentBoost);
    }

    final compactPattern = _compactPattern(normalizedPattern);
    if (compactPattern.isEmpty) {
      return null;
    }

    final fileNameFuzzy = _orderedCharacterMatch(
      candidate: normalizedFileName,
      pattern: compactPattern,
      offset: fileNameStart,
      baseScore: 5200,
    );
    final pathFuzzy = _orderedCharacterMatch(
      candidate: normalizedPath,
      pattern: compactPattern,
      offset: 0,
      baseScore: 4200,
    );
    final fuzzyScore = _bestScore(fileNameFuzzy, pathFuzzy);
    return fuzzyScore?.withBoost(recentBoost);
  }

  static _QuickOpenScore? _directMatch({
    required String candidate,
    required String pattern,
    required int offset,
    required int exactScore,
    required int prefixScore,
    required int containsScore,
  }) {
    if (candidate == pattern) {
      return _QuickOpenScore(
        value: exactScore,
        matches: <WorkspaceQuickOpenMatch>[
          WorkspaceQuickOpenMatch(start: offset, end: offset + pattern.length),
        ],
      );
    }
    if (candidate.startsWith(pattern)) {
      return _QuickOpenScore(
        value: prefixScore - (candidate.length - pattern.length),
        matches: <WorkspaceQuickOpenMatch>[
          WorkspaceQuickOpenMatch(start: offset, end: offset + pattern.length),
        ],
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _QuickOpenScore(
        value: containsScore - index,
        matches: <WorkspaceQuickOpenMatch>[
          WorkspaceQuickOpenMatch(
            start: offset + index,
            end: offset + index + pattern.length,
          ),
        ],
      );
    }
    return null;
  }

  static _QuickOpenScore? _orderedCharacterMatch({
    required String candidate,
    required String pattern,
    required int offset,
    required int baseScore,
  }) {
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
      if (_isPathBoundary(candidate, matchIndex)) {
        score += 8;
      }
      score -= matchIndex - cursor;
      cursor = matchIndex + 1;
      lastIndex = matchIndex;
    }

    if (indices.isNotEmpty) {
      score -= indices.first;
    }

    return _QuickOpenScore(
      value: score,
      matches: _rangesFromIndices(indices, offset),
    );
  }

  static _QuickOpenScore? _bestScore(
    _QuickOpenScore? first,
    _QuickOpenScore? second,
  ) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.value >= second.value ? first : second;
  }

  static List<WorkspaceQuickOpenMatch> _rangesFromIndices(
    List<int> indices,
    int offset,
  ) {
    if (indices.isEmpty) {
      return const <WorkspaceQuickOpenMatch>[];
    }
    final ranges = <WorkspaceQuickOpenMatch>[];
    var rangeStart = indices.first;
    var previous = indices.first;
    for (final index in indices.skip(1)) {
      if (index == previous + 1) {
        previous = index;
        continue;
      }
      ranges.add(
        WorkspaceQuickOpenMatch(
          start: offset + rangeStart,
          end: offset + previous + 1,
        ),
      );
      rangeStart = index;
      previous = index;
    }
    ranges.add(
      WorkspaceQuickOpenMatch(
        start: offset + rangeStart,
        end: offset + previous + 1,
      ),
    );
    return ranges;
  }

  static bool _isPathBoundary(String candidate, int index) {
    if (index == 0) {
      return true;
    }
    final previous = candidate[index - 1];
    return previous == '/' ||
        previous == '-' ||
        previous == '_' ||
        previous == '.';
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

  static String _fileName(String filePath) {
    final displayPath = _displayPath(filePath);
    final slash = displayPath.lastIndexOf('/');
    return slash < 0 ? displayPath : displayPath.substring(slash + 1);
  }

  static String _parentPath(String filePath) {
    final displayPath = _displayPath(filePath);
    final slash = displayPath.lastIndexOf('/');
    return slash <= 0 ? '' : displayPath.substring(0, slash);
  }

  static int _recentBoost(int? recentRank) {
    if (recentRank == null) {
      return 0;
    }
    final boost = 300 - recentRank * 20;
    return boost < 20 ? 20 : boost;
  }

  static int _compareQuickOpenItems(
    _ScoredQuickOpenItem first,
    _ScoredQuickOpenItem second,
  ) {
    final scoreCompare = second.item.score.compareTo(first.item.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final firstRecentRank = first.item.recentRank;
    final secondRecentRank = second.item.recentRank;
    if (firstRecentRank != null && secondRecentRank != null) {
      final recentCompare = firstRecentRank.compareTo(secondRecentRank);
      if (recentCompare != 0) {
        return recentCompare;
      }
    } else if (firstRecentRank != null) {
      return -1;
    } else if (secondRecentRank != null) {
      return 1;
    }
    final lengthCompare = first.item.filePath.length.compareTo(
      second.item.filePath.length,
    );
    if (lengthCompare != 0) {
      return lengthCompare;
    }
    final pathCompare = first.item.filePath.compareTo(second.item.filePath);
    if (pathCompare != 0) {
      return pathCompare;
    }
    return first.projectIndex.compareTo(second.projectIndex);
  }
}

class _QuickOpenScore {
  const _QuickOpenScore({required this.value, required this.matches});

  final int value;
  final List<WorkspaceQuickOpenMatch> matches;

  _QuickOpenScore withBoost(int boost) {
    if (boost == 0) {
      return this;
    }
    return _QuickOpenScore(value: value + boost, matches: matches);
  }
}

class _ScoredQuickOpenItem {
  const _ScoredQuickOpenItem({
    required this.item,
    required this.projectIndex,
  });

  final WorkspaceQuickOpenItem item;
  final int projectIndex;
}
