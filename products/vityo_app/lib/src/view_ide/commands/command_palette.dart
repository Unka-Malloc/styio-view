import 'app_commands.dart';

typedef CommandBlockedReasonResolver =
    String? Function(AppCommandId commandId);

enum CommandPaletteStatus { completed, noCommands, hitLimit }

class CommandPaletteQuery {
  const CommandPaletteQuery({
    this.pattern = '',
    this.maxResults = 50,
    this.includeBlocked = true,
  });

  final String pattern;
  final int maxResults;
  final bool includeBlocked;

  CommandPaletteQuery copyWith({
    String? pattern,
    int? maxResults,
    bool? includeBlocked,
  }) {
    return CommandPaletteQuery(
      pattern: pattern ?? this.pattern,
      maxResults: maxResults ?? this.maxResults,
      includeBlocked: includeBlocked ?? this.includeBlocked,
    );
  }
}

class CommandPaletteMatch {
  const CommandPaletteMatch({required this.start, required this.end});

  final int start;
  final int end;
}

class CommandPaletteItem {
  const CommandPaletteItem({
    required this.commandId,
    required this.label,
    required this.shortcutHint,
    required this.description,
    required this.category,
    required this.score,
    required this.matches,
    this.blockedReason,
    this.recentRank,
  });

  final AppCommandId commandId;
  final String label;
  final String shortcutHint;
  final String description;
  final String category;
  final int score;
  final List<CommandPaletteMatch> matches;
  final String? blockedReason;
  final int? recentRank;

  bool get enabled => blockedReason == null;

  bool get isRecent => recentRank != null;
}

class CommandPaletteResult {
  const CommandPaletteResult({
    required this.query,
    required this.status,
    required this.commandsSearched,
    required this.items,
  });

  final CommandPaletteQuery query;
  final CommandPaletteStatus status;
  final int commandsSearched;
  final List<CommandPaletteItem> items;

  bool get hitLimit => status == CommandPaletteStatus.hitLimit;

  int get matchCount => items.length;

  int get blockedCount => items.where((item) => !item.enabled).length;
}

class CommandPaletteService {
  const CommandPaletteService();

  CommandPaletteResult findCommands({
    required List<AppCommandDescriptor> commands,
    required CommandPaletteQuery query,
    List<AppCommandId> recentCommandIds = const <AppCommandId>[],
    CommandBlockedReasonResolver? blockedReasonForCommand,
  }) {
    if (commands.isEmpty) {
      return CommandPaletteResult(
        query: query,
        status: CommandPaletteStatus.noCommands,
        commandsSearched: 0,
        items: const <CommandPaletteItem>[],
      );
    }

    final recentRanks = _recentRanks(recentCommandIds);
    final normalizedPattern = _normalizedPattern(query.pattern);
    final maxResults = query.maxResults <= 0 ? 50 : query.maxResults;
    final scoredItems = <_ScoredCommandPaletteItem>[];

    for (var index = 0; index < commands.length; index += 1) {
      final command = commands[index];
      final blockedReason = blockedReasonForCommand?.call(command.id);
      if (!query.includeBlocked && blockedReason != null) {
        continue;
      }
      final score = _scoreCommand(
        command: command,
        normalizedPattern: normalizedPattern,
        recentRank: recentRanks[command.id],
        registryIndex: index,
      );
      if (score == null) {
        continue;
      }

      scoredItems.add(
        _ScoredCommandPaletteItem(
          item: CommandPaletteItem(
            commandId: command.id,
            label: command.label,
            shortcutHint: command.shortcutHint,
            description: command.description,
            category: _categoryFor(command.id),
            score: blockedReason == null ? score.value : score.value - 250,
            matches: List<CommandPaletteMatch>.unmodifiable(score.matches),
            blockedReason: blockedReason,
            recentRank: recentRanks[command.id],
          ),
          registryIndex: index,
        ),
      );
    }

    scoredItems.sort(_compareCommandPaletteItems);
    final limitedItems = scoredItems
        .take(maxResults)
        .map((entry) => entry.item)
        .toList(growable: false);

    return CommandPaletteResult(
      query: query,
      status: scoredItems.length > maxResults
          ? CommandPaletteStatus.hitLimit
          : CommandPaletteStatus.completed,
      commandsSearched: commands.length,
      items: List<CommandPaletteItem>.unmodifiable(limitedItems),
    );
  }

  static Map<AppCommandId, int> _recentRanks(
    List<AppCommandId> recentCommandIds,
  ) {
    final ranks = <AppCommandId, int>{};
    for (final commandId in recentCommandIds) {
      if (ranks.containsKey(commandId)) {
        continue;
      }
      ranks[commandId] = ranks.length;
    }
    return ranks;
  }

  static _CommandPaletteScore? _scoreCommand({
    required AppCommandDescriptor command,
    required String normalizedPattern,
    required int? recentRank,
    required int registryIndex,
  }) {
    final recentBoost = _recentBoost(recentRank);
    final primaryBoost = command.primary ? 450 : 0;

    if (normalizedPattern.isEmpty) {
      final cappedIndex = registryIndex > 999 ? 999 : registryIndex;
      final baseScore = recentRank == null
          ? 1400 + primaryBoost - cappedIndex
          : 6000 - recentRank;
      return _CommandPaletteScore(value: baseScore, matches: const []);
    }

    final normalizedLabel = command.label.toLowerCase();
    final normalizedId = _commandIdSearchText(command.id);
    final normalizedDescription = command.description.toLowerCase();
    final normalizedShortcut = command.shortcutHint.toLowerCase();

    final labelDirect = _directMatch(
      candidate: normalizedLabel,
      pattern: normalizedPattern,
      exactScore: 10000,
      prefixScore: 9000,
      containsScore: 8000,
    );
    if (labelDirect != null) {
      return labelDirect.withBoost(recentBoost + primaryBoost);
    }

    final idDirect = _directMatch(
      candidate: normalizedId,
      pattern: normalizedPattern,
      exactScore: 7600,
      prefixScore: 7200,
      containsScore: 6800,
    );
    if (idDirect != null) {
      return idDirect.withBoost(recentBoost + primaryBoost ~/ 2);
    }

    final shortcutDirect = normalizedShortcut.contains(normalizedPattern)
        ? const _CommandPaletteScore(value: 6200, matches: [])
        : null;
    if (shortcutDirect != null) {
      return shortcutDirect.withBoost(recentBoost);
    }

    final descriptionDirect = normalizedDescription.contains(normalizedPattern)
        ? const _CommandPaletteScore(value: 5600, matches: [])
        : null;
    if (descriptionDirect != null) {
      return descriptionDirect.withBoost(recentBoost);
    }

    final compactPattern = normalizedPattern.replaceAll(RegExp(r'\s+'), '');
    if (compactPattern.isEmpty) {
      return null;
    }

    final labelFuzzy = _orderedCharacterMatch(
      candidate: normalizedLabel,
      pattern: compactPattern,
      baseScore: 4800,
    );
    final idFuzzy = _orderedCharacterMatch(
      candidate: normalizedId,
      pattern: compactPattern,
      baseScore: 4100,
    );
    final fuzzyScore = _bestScore(labelFuzzy, idFuzzy);
    return fuzzyScore?.withBoost(recentBoost + primaryBoost ~/ 3);
  }

  static _CommandPaletteScore? _directMatch({
    required String candidate,
    required String pattern,
    required int exactScore,
    required int prefixScore,
    required int containsScore,
  }) {
    if (candidate == pattern) {
      return _CommandPaletteScore(
        value: exactScore,
        matches: <CommandPaletteMatch>[
          CommandPaletteMatch(start: 0, end: pattern.length),
        ],
      );
    }
    if (candidate.startsWith(pattern)) {
      return _CommandPaletteScore(
        value: prefixScore - (candidate.length - pattern.length),
        matches: <CommandPaletteMatch>[
          CommandPaletteMatch(start: 0, end: pattern.length),
        ],
      );
    }
    final index = candidate.indexOf(pattern);
    if (index >= 0) {
      return _CommandPaletteScore(
        value: containsScore - index,
        matches: <CommandPaletteMatch>[
          CommandPaletteMatch(start: index, end: index + pattern.length),
        ],
      );
    }
    return null;
  }

  static _CommandPaletteScore? _orderedCharacterMatch({
    required String candidate,
    required String pattern,
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

    return _CommandPaletteScore(
      value: score,
      matches: _rangesFromIndices(indices),
    );
  }

  static _CommandPaletteScore? _bestScore(
    _CommandPaletteScore? first,
    _CommandPaletteScore? second,
  ) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.value >= second.value ? first : second;
  }

  static List<CommandPaletteMatch> _rangesFromIndices(List<int> indices) {
    if (indices.isEmpty) {
      return const <CommandPaletteMatch>[];
    }
    final ranges = <CommandPaletteMatch>[];
    var rangeStart = indices.first;
    var previous = indices.first;
    for (final index in indices.skip(1)) {
      if (index == previous + 1) {
        previous = index;
        continue;
      }
      ranges.add(CommandPaletteMatch(start: rangeStart, end: previous + 1));
      rangeStart = index;
      previous = index;
    }
    ranges.add(CommandPaletteMatch(start: rangeStart, end: previous + 1));
    return ranges;
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
        previous == '/';
  }

  static String _normalizedPattern(String pattern) {
    return pattern.trim().toLowerCase();
  }

  static String _commandIdSearchText(AppCommandId commandId) {
    return commandId.name
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .toLowerCase();
  }

  static String _categoryFor(AppCommandId commandId) {
    return switch (commandId) {
      AppCommandId.run ||
      AppCommandId.runSelectedTarget ||
      AppCommandId.runMinimalCompilableUnit => 'Execution',
      AppCommandId.commandPalette ||
      AppCommandId.quickOpen ||
      AppCommandId.navigateBack ||
      AppCommandId.navigateForward ||
      AppCommandId.showRecentLocations ||
      AppCommandId.showWorkspaceDocumentLinks ||
      AppCommandId.showWorkspaceDocumentHighlights ||
      AppCommandId.showWorkspaceCodeLenses ||
      AppCommandId.goToWorkspaceDeclaration ||
      AppCommandId.goToWorkspaceDefinition ||
      AppCommandId.goToWorkspaceTypeDefinition ||
      AppCommandId.goToWorkspaceImplementation ||
      AppCommandId.showWorkspaceTypeHierarchy ||
      AppCommandId.showWorkspaceOutline ||
      AppCommandId.searchWorkspaceSymbols ||
      AppCommandId.findWorkspaceReferences ||
      AppCommandId.showWorkspaceCallHierarchy ||
      AppCommandId.searchWorkspace ||
      AppCommandId.showWorkspaceProblems ||
      AppCommandId.showRuntime ||
      AppCommandId.showAgent ||
      AppCommandId.showDebug ||
      AppCommandId.openSettings => 'Navigation',
      AppCommandId.renameWorkspaceSymbol ||
      AppCommandId.showWorkspaceCodeActions => 'Refactor',
      AppCommandId.fetchDependencies ||
      AppCommandId.vendorDependencies => 'Dependencies',
      AppCommandId.useActiveCompiler ||
      AppCommandId.pinActiveCompiler ||
      AppCommandId.clearPinnedCompiler => 'Toolchain',
      AppCommandId.packProject ||
      AppCommandId.preparePublish => 'Deployment',
      AppCommandId.refreshModules => 'Modules',
      AppCommandId.save ||
      AppCommandId.saveAll ||
      AppCommandId.openFile ||
      AppCommandId.reloadFile ||
      AppCommandId.acceptExternalChange => 'Editor',
      _ => 'Other',
    };
  }

  static int _recentBoost(int? recentRank) {
    if (recentRank == null) {
      return 0;
    }
    final boost = 320 - recentRank * 20;
    return boost < 20 ? 20 : boost;
  }

  static int _compareCommandPaletteItems(
    _ScoredCommandPaletteItem first,
    _ScoredCommandPaletteItem second,
  ) {
    final scoreCompare = second.item.score.compareTo(first.item.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    if (first.item.enabled != second.item.enabled) {
      return first.item.enabled ? -1 : 1;
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
    final labelCompare = first.item.label.compareTo(second.item.label);
    if (labelCompare != 0) {
      return labelCompare;
    }
    return first.registryIndex.compareTo(second.registryIndex);
  }
}

class _CommandPaletteScore {
  const _CommandPaletteScore({required this.value, required this.matches});

  final int value;
  final List<CommandPaletteMatch> matches;

  _CommandPaletteScore withBoost(int boost) {
    if (boost == 0) {
      return this;
    }
    return _CommandPaletteScore(value: value + boost, matches: matches);
  }
}

class _ScoredCommandPaletteItem {
  const _ScoredCommandPaletteItem({
    required this.item,
    required this.registryIndex,
  });

  final CommandPaletteItem item;
  final int registryIndex;
}
