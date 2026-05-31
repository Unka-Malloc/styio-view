import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceOutlineStatus {
  completed,
  emptyWorkspace,
  noSymbols,
  hitLimit,
}

class WorkspaceOutlineQuery {
  const WorkspaceOutlineQuery({
    required this.targetFilePath,
    this.pattern = '',
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String targetFilePath;
  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceOutlineQuery copyWith({
    String? targetFilePath,
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceOutlineQuery(
      targetFilePath: targetFilePath ?? this.targetFilePath,
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceOutlineItem {
  const WorkspaceOutlineItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.detail,
    required this.nameRange,
    required this.declarationRange,
    required this.line,
    required this.column,
    required this.previewText,
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

  String get kindLabel => kind.name;
}

class WorkspaceOutlineResult {
  const WorkspaceOutlineResult({
    required this.query,
    required this.status,
    required this.filePath,
    required this.filesSearched,
    required this.symbolsIndexed,
    required this.items,
    this.message,
  });

  final WorkspaceOutlineQuery query;
  final WorkspaceOutlineStatus status;
  final String filePath;
  final int filesSearched;
  final int symbolsIndexed;
  final List<WorkspaceOutlineItem> items;
  final String? message;

  bool get hitLimit => status == WorkspaceOutlineStatus.hitLimit;

  int get matchCount => items.length;
}

class WorkspaceOutlineService {
  const WorkspaceOutlineService({
    required this.documentStore,
    ProjectStyioDocumentService documentLanguageService =
        const ProjectStyioDocumentService(),
  }) : _documentLanguageService = documentLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioDocumentService _documentLanguageService;

  Future<WorkspaceOutlineResult> collectOutline({
    required List<String> filePaths,
    required WorkspaceOutlineQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final targetFilePath = query.targetFilePath;
    if (!_uniqueFilePaths(filePaths).contains(targetFilePath) ||
        !_isIndexable(targetFilePath, query)) {
      return WorkspaceOutlineResult(
        query: query,
        status: WorkspaceOutlineStatus.emptyWorkspace,
        filePath: targetFilePath,
        filesSearched: 0,
        symbolsIndexed: 0,
        items: const <WorkspaceOutlineItem>[],
        message: 'Outline requires an active Styio workspace file.',
      );
    }

    final overlayDocument = overlayDocuments[targetFilePath];
    final document =
        overlayDocument ?? await documentStore.loadDocument(targetFilePath);
    final analysis = _documentLanguageService.analyzeDocument(document);
    final normalizedPattern = _normalizedPattern(query.pattern);
    final symbols = analysis.documentSymbols;
    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final items = <WorkspaceOutlineItem>[];

    for (final symbol in symbols) {
      final position = document.positionForOffset(symbol.nameRange.start);
      final previewText = _linePreview(document, position.line);
      if (!_matchesPattern(
        filePath: targetFilePath,
        symbol: symbol,
        previewText: previewText,
        normalizedPattern: normalizedPattern,
      )) {
        continue;
      }
      items.add(
        WorkspaceOutlineItem(
          filePath: targetFilePath,
          name: symbol.name,
          kind: symbol.kind,
          detail: symbol.detail,
          nameRange: symbol.nameRange,
          declarationRange: symbol.declarationRange,
          line: position.line,
          column: position.column,
          previewText: previewText,
        ),
      );
    }
    items.sort(_compareItems);

    final limitedItems = items.take(maxResults).toList(growable: false);
    final status = _resultStatus(
      symbolsIndexed: symbols.length,
      matches: items.length,
      maxResults: maxResults,
    );

    return WorkspaceOutlineResult(
      query: query,
      status: status,
      filePath: targetFilePath,
      filesSearched: 1,
      symbolsIndexed: symbols.length,
      items: List<WorkspaceOutlineItem>.unmodifiable(limitedItems),
      message: _resultMessage(
        status: status,
        query: query,
        maxResults: maxResults,
      ),
    );
  }

  static String? _resultMessage({
    required WorkspaceOutlineStatus status,
    required WorkspaceOutlineQuery query,
    required int maxResults,
  }) {
    return switch (status) {
      WorkspaceOutlineStatus.completed => null,
      WorkspaceOutlineStatus.emptyWorkspace =>
        'Outline requires an active Styio workspace file.',
      WorkspaceOutlineStatus.noSymbols =>
        query.pattern.trim().isEmpty
            ? 'No document symbols in this file.'
            : 'No document symbols match `${query.pattern.trim()}`.',
      WorkspaceOutlineStatus.hitLimit =>
        'Outline stopped after $maxResults symbol(s).',
    };
  }

  static WorkspaceOutlineStatus _resultStatus({
    required int symbolsIndexed,
    required int matches,
    required int maxResults,
  }) {
    if (symbolsIndexed == 0 || matches == 0) {
      return WorkspaceOutlineStatus.noSymbols;
    }
    if (matches > maxResults) {
      return WorkspaceOutlineStatus.hitLimit;
    }
    return WorkspaceOutlineStatus.completed;
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

  static bool _isIndexable(String filePath, WorkspaceOutlineQuery query) {
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

  static bool _matchesPattern({
    required String filePath,
    required DocumentSymbol symbol,
    required String previewText,
    required String normalizedPattern,
  }) {
    if (normalizedPattern.isEmpty) {
      return true;
    }
    return _displayPath(filePath).toLowerCase().contains(normalizedPattern) ||
        symbol.name.toLowerCase().contains(normalizedPattern) ||
        symbol.kind.name.contains(normalizedPattern) ||
        symbol.detail.toLowerCase().contains(normalizedPattern) ||
        previewText.toLowerCase().contains(normalizedPattern);
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

  static String _displayPath(String filePath) {
    return filePath.replaceAll('\\', '/');
  }

  static int _compareItems(
    WorkspaceOutlineItem first,
    WorkspaceOutlineItem second,
  ) {
    final rangeCompare = first.declarationRange.start.compareTo(
      second.declarationRange.start,
    );
    if (rangeCompare != 0) {
      return rangeCompare;
    }
    return first.name.compareTo(second.name);
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
