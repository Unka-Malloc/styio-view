import '../editor/document_state.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceTextSearchStatus {
  completed,
  emptyPattern,
  invalidPattern,
  hitLimit,
}

class WorkspaceTextSearchQuery {
  const WorkspaceTextSearchQuery({
    required this.pattern,
    this.literal = true,
    this.caseSensitive = false,
    this.includeGlobs = const <String>[],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final bool literal;
  final bool caseSensitive;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceTextSearchQuery copyWith({
    String? pattern,
    bool? literal,
    bool? caseSensitive,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceTextSearchQuery(
      pattern: pattern ?? this.pattern,
      literal: literal ?? this.literal,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceTextSearchMatch {
  const WorkspaceTextSearchMatch({
    required this.filePath,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
  });

  final String filePath;
  final WorkspaceTextRange range;
  final int line;
  final int column;
  final String previewText;
}

class WorkspaceTextSearchResult {
  const WorkspaceTextSearchResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.matches,
    this.message,
  });

  final WorkspaceTextSearchQuery query;
  final WorkspaceTextSearchStatus status;
  final int filesSearched;
  final List<WorkspaceTextSearchMatch> matches;
  final String? message;

  bool get hitLimit => status == WorkspaceTextSearchStatus.hitLimit;

  int get matchCount => matches.length;

  int get matchedFileCount =>
      matches.map((match) => match.filePath).toSet().length;
}

class WorkspaceTextReplaceQuery {
  const WorkspaceTextReplaceQuery({
    required this.pattern,
    required this.replacement,
    this.literal = true,
    this.caseSensitive = false,
    this.includeGlobs = const <String>[],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final String replacement;
  final bool literal;
  final bool caseSensitive;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceTextSearchQuery get searchQuery {
    return WorkspaceTextSearchQuery(
      pattern: pattern,
      literal: literal,
      caseSensitive: caseSensitive,
      includeGlobs: includeGlobs,
      excludeGlobs: excludeGlobs,
      maxResults: maxResults,
    );
  }
}

class WorkspaceTextReplaceMatch {
  const WorkspaceTextReplaceMatch({
    required this.filePath,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    required this.replacementText,
    required this.replacementPreviewText,
  });

  final String filePath;
  final WorkspaceTextRange range;
  final int line;
  final int column;
  final String previewText;
  final String replacementText;
  final String replacementPreviewText;

  WorkspaceTextSearchMatch get searchMatch {
    return WorkspaceTextSearchMatch(
      filePath: filePath,
      range: range,
      line: line,
      column: column,
      previewText: previewText,
    );
  }
}

class WorkspaceTextReplacePreview {
  const WorkspaceTextReplacePreview({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.matches,
    this.message,
  });

  final WorkspaceTextReplaceQuery query;
  final WorkspaceTextSearchStatus status;
  final int filesSearched;
  final List<WorkspaceTextReplaceMatch> matches;
  final String? message;

  bool get hitLimit => status == WorkspaceTextSearchStatus.hitLimit;

  bool get canApply =>
      status == WorkspaceTextSearchStatus.completed && matches.isNotEmpty;

  int get replacementCount => matches.length;

  int get matchedFileCount =>
      matches.map((match) => match.filePath).toSet().length;

  WorkspaceTextSearchResult get searchResult {
    return WorkspaceTextSearchResult(
      query: query.searchQuery,
      status: status,
      filesSearched: filesSearched,
      matches: List<WorkspaceTextSearchMatch>.unmodifiable(
        matches.map((match) => match.searchMatch),
      ),
      message: message,
    );
  }
}

class WorkspaceTextReplaceApplyResult {
  const WorkspaceTextReplaceApplyResult({
    required this.preview,
    required this.applied,
    required this.changedDocuments,
    this.message,
  });

  final WorkspaceTextReplacePreview preview;
  final bool applied;
  final Map<String, DocumentState> changedDocuments;
  final String? message;

  int get documentsChanged => changedDocuments.length;

  int get replacementsApplied => applied ? preview.replacementCount : 0;
}

class WorkspaceTextSearchService {
  const WorkspaceTextSearchService({required this.documentStore});

  final WorkspaceDocumentStore documentStore;

  Future<WorkspaceTextSearchResult> searchFiles({
    required List<String> filePaths,
    required WorkspaceTextSearchQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    if (query.pattern.isEmpty) {
      return WorkspaceTextSearchResult(
        query: query,
        status: WorkspaceTextSearchStatus.emptyPattern,
        filesSearched: 0,
        matches: const <WorkspaceTextSearchMatch>[],
        message: 'Workspace search requires a non-empty pattern.',
      );
    }

    final matcher = _TextMatcher.fromQuery(query);
    if (matcher == null) {
      return WorkspaceTextSearchResult(
        query: query,
        status: WorkspaceTextSearchStatus.invalidPattern,
        filesSearched: 0,
        matches: const <WorkspaceTextSearchMatch>[],
        message: 'Workspace search pattern is not a valid regular expression.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIncluded(filePath, query))
        .toList(growable: false);
    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final matches = <WorkspaceTextSearchMatch>[];
    var filesSearched = 0;

    for (final filePath in uniqueFilePaths) {
      final document =
          overlayDocuments[filePath] ??
          await documentStore.loadDocument(filePath);
      filesSearched += 1;

      for (final textMatch in matcher.matchesIn(document.text)) {
        final range = textMatch.range;
        final position = document.positionForOffset(range.start);
        matches.add(
          WorkspaceTextSearchMatch(
            filePath: filePath,
            range: range,
            line: position.line,
            column: position.column,
            previewText: _linePreview(document, position.line),
          ),
        );
        if (matches.length >= maxResults) {
          return WorkspaceTextSearchResult(
            query: query,
            status: WorkspaceTextSearchStatus.hitLimit,
            filesSearched: filesSearched,
            matches: List<WorkspaceTextSearchMatch>.unmodifiable(matches),
            message: 'Workspace search stopped after $maxResults match(es).',
          );
        }
      }
    }

    return WorkspaceTextSearchResult(
      query: query,
      status: WorkspaceTextSearchStatus.completed,
      filesSearched: filesSearched,
      matches: List<WorkspaceTextSearchMatch>.unmodifiable(matches),
    );
  }

  Future<WorkspaceTextReplacePreview> previewReplaceFiles({
    required List<String> filePaths,
    required WorkspaceTextReplaceQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final searchQuery = query.searchQuery;
    if (query.pattern.isEmpty) {
      return WorkspaceTextReplacePreview(
        query: query,
        status: WorkspaceTextSearchStatus.emptyPattern,
        filesSearched: 0,
        matches: const <WorkspaceTextReplaceMatch>[],
        message: 'Workspace replace requires a non-empty pattern.',
      );
    }

    final matcher = _TextMatcher.fromQuery(searchQuery);
    if (matcher == null) {
      return WorkspaceTextReplacePreview(
        query: query,
        status: WorkspaceTextSearchStatus.invalidPattern,
        filesSearched: 0,
        matches: const <WorkspaceTextReplaceMatch>[],
        message:
            'Workspace replace pattern is not a valid regular expression.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIncluded(filePath, searchQuery))
        .toList(growable: false);
    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final matches = <WorkspaceTextReplaceMatch>[];
    var filesSearched = 0;

    for (final filePath in uniqueFilePaths) {
      final document =
          overlayDocuments[filePath] ??
          await documentStore.loadDocument(filePath);
      filesSearched += 1;

      for (final textMatch in matcher.matchesIn(document.text)) {
        final range = textMatch.range;
        final position = document.positionForOffset(range.start);
        final replacementText = matcher.replacementFor(
          textMatch,
          query.replacement,
        );
        matches.add(
          WorkspaceTextReplaceMatch(
            filePath: filePath,
            range: range,
            line: position.line,
            column: position.column,
            previewText: _linePreview(document, position.line),
            replacementText: replacementText,
            replacementPreviewText: _replacementPreview(
              document,
              range,
              replacementText,
            ),
          ),
        );
        if (matches.length >= maxResults) {
          return WorkspaceTextReplacePreview(
            query: query,
            status: WorkspaceTextSearchStatus.hitLimit,
            filesSearched: filesSearched,
            matches: List<WorkspaceTextReplaceMatch>.unmodifiable(matches),
            message:
                'Workspace replace stopped after $maxResults match(es).',
          );
        }
      }
    }

    return WorkspaceTextReplacePreview(
      query: query,
      status: WorkspaceTextSearchStatus.completed,
      filesSearched: filesSearched,
      matches: List<WorkspaceTextReplaceMatch>.unmodifiable(matches),
    );
  }

  Future<WorkspaceTextReplaceApplyResult> applyReplaceFiles({
    required List<String> filePaths,
    required WorkspaceTextReplaceQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final preview = await previewReplaceFiles(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    if (!preview.canApply) {
      return WorkspaceTextReplaceApplyResult(
        preview: preview,
        applied: false,
        changedDocuments: const <String, DocumentState>{},
        message:
            preview.message ?? 'Workspace replace has no applicable edits.',
      );
    }

    final changedDocuments = <String, DocumentState>{};
    final matchesByFile = <String, List<WorkspaceTextReplaceMatch>>{};
    for (final match in preview.matches) {
      final fileMatches = matchesByFile.putIfAbsent(
        match.filePath,
        () => <WorkspaceTextReplaceMatch>[],
      );
      fileMatches.add(match);
    }

    for (final entry in matchesByFile.entries) {
      final document =
          overlayDocuments[entry.key] ??
          await documentStore.loadDocument(entry.key);
      var nextDocument = document;
      final descendingMatches = [...entry.value]..sort(
        (first, second) => second.range.start.compareTo(first.range.start),
      );
      for (final match in descendingMatches) {
        nextDocument = nextDocument.replaceRange(
          start: match.range.start,
          end: match.range.end,
          replacement: match.replacementText,
        );
      }
      await documentStore.saveDocument(nextDocument);
      changedDocuments[entry.key] = nextDocument;
    }

    return WorkspaceTextReplaceApplyResult(
      preview: preview,
      applied: changedDocuments.isNotEmpty,
      changedDocuments: Map<String, DocumentState>.unmodifiable(
        changedDocuments,
      ),
      message: changedDocuments.isEmpty
          ? 'Workspace replace did not change any documents.'
          : 'Replaced ${preview.replacementCount} occurrence(s) across '
                '${changedDocuments.length} file(s).',
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

  static bool _isIncluded(String filePath, WorkspaceTextSearchQuery query) {
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

  static String _linePreview(DocumentState document, int line) {
    final lines = document.lines;
    if (lines.isEmpty) {
      return '';
    }
    return lines[line.clamp(0, lines.length - 1)].trimRight();
  }

  static String _replacementPreview(
    DocumentState document,
    WorkspaceTextRange range,
    String replacement,
  ) {
    final nextDocument = document.replaceRange(
      start: range.start,
      end: range.end,
      replacement: replacement,
    );
    final position = nextDocument.positionForOffset(range.start);
    return _linePreview(nextDocument, position.line);
  }
}

class WorkspaceTextRange {
  const WorkspaceTextRange({required this.start, required this.end});

  final int start;
  final int end;
}

class _TextMatcher {
  const _TextMatcher._({
    required this.literalPattern,
    required this.caseSensitive,
    this.regex,
  });

  final String literalPattern;
  final bool caseSensitive;
  final RegExp? regex;

  static _TextMatcher? fromQuery(WorkspaceTextSearchQuery query) {
    if (query.literal) {
      return _TextMatcher._(
        literalPattern: query.pattern,
        caseSensitive: query.caseSensitive,
      );
    }
    try {
      return _TextMatcher._(
        literalPattern: query.pattern,
        caseSensitive: query.caseSensitive,
        regex: RegExp(query.pattern, caseSensitive: query.caseSensitive),
      );
    } on FormatException {
      return null;
    }
  }

  Iterable<_TextMatch> matchesIn(String text) sync* {
    final regexMatcher = regex;
    if (regexMatcher != null) {
      for (final match in regexMatcher.allMatches(text)) {
        if (match.start == match.end) {
          continue;
        }
        yield _TextMatch(
          range: WorkspaceTextRange(start: match.start, end: match.end),
          regexMatch: match,
        );
      }
      return;
    }

    final haystack = caseSensitive ? text : text.toLowerCase();
    final needle = caseSensitive ? literalPattern : literalPattern.toLowerCase();
    var cursor = 0;
    while (cursor <= haystack.length) {
      final index = haystack.indexOf(needle, cursor);
      if (index < 0) {
        return;
      }
      yield _TextMatch(
        range: WorkspaceTextRange(start: index, end: index + needle.length),
      );
      cursor = index + needle.length;
    }
  }

  String replacementFor(_TextMatch match, String replacement) {
    final regexMatch = match.regexMatch;
    if (regexMatch == null) {
      return replacement;
    }
    return _expandRegexReplacement(replacement, regexMatch);
  }

  static String _expandRegexReplacement(String replacement, Match match) {
    final buffer = StringBuffer();
    for (var index = 0; index < replacement.length; index += 1) {
      final char = replacement[index];
      if (char == '\\' &&
          index + 1 < replacement.length &&
          replacement[index + 1] == r'$') {
        buffer.write(r'$');
        index += 1;
        continue;
      }
      if (char != r'$') {
        buffer.write(char);
        continue;
      }

      final digitStart = index + 1;
      if (digitStart >= replacement.length ||
          !_isAsciiDigit(replacement[digitStart])) {
        buffer.write(char);
        continue;
      }

      var digitEnd = digitStart;
      while (digitEnd < replacement.length &&
          _isAsciiDigit(replacement[digitEnd])) {
        digitEnd += 1;
      }

      var consumedEnd = digitStart;
      String? groupText;
      for (var groupEnd = digitEnd; groupEnd > digitStart; groupEnd -= 1) {
        final groupIndex = int.tryParse(
          replacement.substring(digitStart, groupEnd),
        );
        if (groupIndex == null) {
          continue;
        }
        if (groupIndex == 0 || groupIndex <= match.groupCount) {
          groupText = match.group(groupIndex) ?? '';
          consumedEnd = groupEnd;
          break;
        }
      }

      if (groupText == null) {
        buffer.write(char);
        continue;
      }

      buffer.write(groupText);
      index = consumedEnd - 1;
    }
    return buffer.toString();
  }

  static bool _isAsciiDigit(String char) {
    return char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
  }
}

class _TextMatch {
  const _TextMatch({required this.range, this.regexMatch});

  final WorkspaceTextRange range;
  final Match? regexMatch;
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
