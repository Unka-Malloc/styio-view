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

      for (final range in matcher.rangesIn(document.text)) {
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

  Iterable<WorkspaceTextRange> rangesIn(String text) sync* {
    final regexMatcher = regex;
    if (regexMatcher != null) {
      for (final match in regexMatcher.allMatches(text)) {
        if (match.start == match.end) {
          continue;
        }
        yield WorkspaceTextRange(start: match.start, end: match.end);
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
      yield WorkspaceTextRange(start: index, end: index + needle.length);
      cursor = index + needle.length;
    }
  }
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
