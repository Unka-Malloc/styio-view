import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceDocumentHighlightsStatus {
  completed,
  emptyWorkspace,
  emptySelection,
  noHighlights,
  hitLimit,
}

enum WorkspaceDocumentHighlightKind { text, declaration, read, write }

class WorkspaceDocumentHighlightsQuery {
  const WorkspaceDocumentHighlightsQuery({
    required this.targetFilePath,
    required this.offset,
    this.includeText = true,
    this.includeDeclarations = true,
    this.includeRead = true,
    this.includeWrite = true,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String targetFilePath;
  final int offset;
  final bool includeText;
  final bool includeDeclarations;
  final bool includeRead;
  final bool includeWrite;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceDocumentHighlightsQuery copyWith({
    String? targetFilePath,
    int? offset,
    bool? includeText,
    bool? includeDeclarations,
    bool? includeRead,
    bool? includeWrite,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceDocumentHighlightsQuery(
      targetFilePath: targetFilePath ?? this.targetFilePath,
      offset: offset ?? this.offset,
      includeText: includeText ?? this.includeText,
      includeDeclarations: includeDeclarations ?? this.includeDeclarations,
      includeRead: includeRead ?? this.includeRead,
      includeWrite: includeWrite ?? this.includeWrite,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceDocumentHighlightItem {
  const WorkspaceDocumentHighlightItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    required this.isActive,
    this.symbolKind,
  });

  final String filePath;
  final String name;
  final WorkspaceDocumentHighlightKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final bool isActive;
  final SymbolKind? symbolKind;

  String get kindLabel {
    return switch (kind) {
      WorkspaceDocumentHighlightKind.text => 'text',
      WorkspaceDocumentHighlightKind.declaration => 'declaration',
      WorkspaceDocumentHighlightKind.read => 'read',
      WorkspaceDocumentHighlightKind.write => 'write',
    };
  }

  String get symbolKindLabel {
    final kind = symbolKind;
    if (kind == null) {
      return 'text';
    }
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
}

class WorkspaceDocumentHighlightsResult {
  const WorkspaceDocumentHighlightsResult({
    required this.query,
    required this.status,
    required this.filePath,
    required this.token,
    required this.filesSearched,
    required this.highlightsIndexed,
    required this.highlights,
    this.message,
  });

  final WorkspaceDocumentHighlightsQuery query;
  final WorkspaceDocumentHighlightsStatus status;
  final String filePath;
  final String token;
  final int filesSearched;
  final int highlightsIndexed;
  final List<WorkspaceDocumentHighlightItem> highlights;
  final String? message;

  bool get hitLimit => status == WorkspaceDocumentHighlightsStatus.hitLimit;

  int get highlightCount => highlights.length;

  int get textCount => _countKind(WorkspaceDocumentHighlightKind.text);

  int get declarationCount =>
      _countKind(WorkspaceDocumentHighlightKind.declaration);

  int get readCount => _countKind(WorkspaceDocumentHighlightKind.read);

  int get writeCount => _countKind(WorkspaceDocumentHighlightKind.write);

  int _countKind(WorkspaceDocumentHighlightKind kind) {
    return highlights.where((highlight) => highlight.kind == kind).length;
  }
}

class WorkspaceDocumentHighlightsService {
  const WorkspaceDocumentHighlightsService({
    required this.documentStore,
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
  }) : _syntaxHighlighter = syntaxHighlighter,
       _symbolIndex = symbolIndex;

  final WorkspaceDocumentStore documentStore;
  final StyioSyntaxHighlighter _syntaxHighlighter;
  final StyioSymbolIndex _symbolIndex;

  Future<WorkspaceDocumentHighlightsResult> collectHighlights({
    required List<String> filePaths,
    required WorkspaceDocumentHighlightsQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final targetFilePath = query.targetFilePath;
    final uniqueFilePaths = _uniqueFilePaths(filePaths);
    if (!uniqueFilePaths.contains(targetFilePath) ||
        !_isIndexable(targetFilePath, query)) {
      return WorkspaceDocumentHighlightsResult(
        query: query,
        status: WorkspaceDocumentHighlightsStatus.emptyWorkspace,
        filePath: targetFilePath,
        token: '',
        filesSearched: 0,
        highlightsIndexed: 0,
        highlights: const <WorkspaceDocumentHighlightItem>[],
        message:
            'Document Highlights requires an active Styio workspace file.',
      );
    }

    final document =
        overlayDocuments[targetFilePath] ??
        await documentStore.loadDocument(targetFilePath);
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final token = _tokenAroundOffset(tokens, query.offset, document.length);
    if (token == null || token.kind != TokenKind.identifier) {
      return WorkspaceDocumentHighlightsResult(
        query: query,
        status: WorkspaceDocumentHighlightsStatus.emptySelection,
        filePath: targetFilePath,
        token: '',
        filesSearched: 1,
        highlightsIndexed: 0,
        highlights: const <WorkspaceDocumentHighlightItem>[],
        message: 'Document Highlights requires an identifier at the cursor.',
      );
    }

    final semanticHighlights = _semanticHighlights(
      document: document,
      tokens: tokens,
      activeToken: token,
    );
    final allHighlights = semanticHighlights.isEmpty
        ? _textualHighlights(document: document, tokens: tokens, token: token)
        : semanticHighlights;
    final visibleHighlights = [
      for (final highlight in allHighlights)
        if (_includesHighlight(highlight, query)) highlight,
    ];

    if (visibleHighlights.isEmpty) {
      return WorkspaceDocumentHighlightsResult(
        query: query,
        status: WorkspaceDocumentHighlightsStatus.noHighlights,
        filePath: targetFilePath,
        token: token.lexeme,
        filesSearched: 1,
        highlightsIndexed: allHighlights.length,
        highlights: const <WorkspaceDocumentHighlightItem>[],
        message: 'No document highlights match `${token.lexeme}`.',
      );
    }

    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final limitedHighlights = visibleHighlights
        .take(maxResults)
        .toList(growable: false);

    return WorkspaceDocumentHighlightsResult(
      query: query,
      status: visibleHighlights.length > maxResults
          ? WorkspaceDocumentHighlightsStatus.hitLimit
          : WorkspaceDocumentHighlightsStatus.completed,
      filePath: targetFilePath,
      token: token.lexeme,
      filesSearched: 1,
      highlightsIndexed: allHighlights.length,
      highlights: List<WorkspaceDocumentHighlightItem>.unmodifiable(
        limitedHighlights,
      ),
      message: visibleHighlights.length > maxResults
          ? 'Document Highlights stopped after $maxResults occurrence(s).'
          : null,
    );
  }

  List<WorkspaceDocumentHighlightItem> _semanticHighlights({
    required DocumentState document,
    required List<TokenSpan> tokens,
    required TokenSpan activeToken,
  }) {
    final snapshot = _symbolIndex.build(tokens);
    final activeReference = snapshot.referenceAt(activeToken.range);
    if (activeReference == null) {
      return const <WorkspaceDocumentHighlightItem>[];
    }

    final references = snapshot.referencesForTarget(
      activeReference.targetRange,
    );
    return [
      for (final reference in references)
        _itemFromRange(
          document: document,
          name: reference.name,
          range: reference.range,
          kind: _kindFromReference(reference),
          symbolKind: reference.kind,
          isActive: reference.range.intersects(activeToken.range),
        ),
    ]..sort(_compareHighlightItems);
  }

  List<WorkspaceDocumentHighlightItem> _textualHighlights({
    required DocumentState document,
    required List<TokenSpan> tokens,
    required TokenSpan token,
  }) {
    return [
      for (final candidate in tokens)
        if (candidate.kind == TokenKind.identifier &&
            candidate.lexeme == token.lexeme)
          _itemFromRange(
            document: document,
            name: candidate.lexeme,
            range: candidate.range,
            kind: WorkspaceDocumentHighlightKind.text,
            isActive: candidate.range.intersects(token.range),
          ),
    ]..sort(_compareHighlightItems);
  }

  static WorkspaceDocumentHighlightItem _itemFromRange({
    required DocumentState document,
    required String name,
    required SourceRange range,
    required WorkspaceDocumentHighlightKind kind,
    required bool isActive,
    SymbolKind? symbolKind,
  }) {
    final position = document.positionForOffset(range.start);
    return WorkspaceDocumentHighlightItem(
      filePath: document.documentId,
      name: name,
      kind: kind,
      range: range,
      line: position.line,
      column: position.column,
      previewText: _linePreview(document, position.line),
      isActive: isActive,
      symbolKind: symbolKind,
    );
  }

  static WorkspaceDocumentHighlightKind _kindFromReference(
    ReferenceSpan reference,
  ) {
    if (reference.isDeclaration ||
        reference.access == ReferenceAccess.declaration) {
      return WorkspaceDocumentHighlightKind.declaration;
    }
    return switch (reference.access) {
      ReferenceAccess.declaration =>
        WorkspaceDocumentHighlightKind.declaration,
      ReferenceAccess.read => WorkspaceDocumentHighlightKind.read,
      ReferenceAccess.write => WorkspaceDocumentHighlightKind.write,
    };
  }

  static bool _includesHighlight(
    WorkspaceDocumentHighlightItem highlight,
    WorkspaceDocumentHighlightsQuery query,
  ) {
    return switch (highlight.kind) {
      WorkspaceDocumentHighlightKind.text => query.includeText,
      WorkspaceDocumentHighlightKind.declaration => query.includeDeclarations,
      WorkspaceDocumentHighlightKind.read => query.includeRead,
      WorkspaceDocumentHighlightKind.write => query.includeWrite,
    };
  }

  static TokenSpan? _tokenAroundOffset(
    List<TokenSpan> tokens,
    int offset,
    int documentLength,
  ) {
    final safeOffset = offset.clamp(0, documentLength);
    TokenSpan? trailingToken;
    TokenSpan? leadingToken;

    for (final token in tokens) {
      if (token.kind == TokenKind.whitespace) {
        continue;
      }
      if (token.range.contains(safeOffset)) {
        return token;
      }
      if (token.range.end == safeOffset) {
        trailingToken = token;
      }
      if (leadingToken == null && token.range.start == safeOffset) {
        leadingToken = token;
      }
    }

    return trailingToken ?? leadingToken;
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
    WorkspaceDocumentHighlightsQuery query,
  ) {
    final normalized = filePath.replaceAll('\\', '/').toLowerCase();
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

  static String _linePreview(DocumentState document, int line) {
    final lines = document.lines;
    if (lines.isEmpty) {
      return '';
    }
    return lines[line.clamp(0, lines.length - 1)].trimRight();
  }

  static int _compareHighlightItems(
    WorkspaceDocumentHighlightItem first,
    WorkspaceDocumentHighlightItem second,
  ) {
    final lineCompare = first.line.compareTo(second.line);
    if (lineCompare != 0) {
      return lineCompare;
    }
    final columnCompare = first.column.compareTo(second.column);
    if (columnCompare != 0) {
      return columnCompare;
    }
    return first.range.end.compareTo(second.range.end);
  }
}

class _GlobMatcher {
  _GlobMatcher(String pattern)
    : _pattern = pattern.replaceAll('\\', '/').toLowerCase();

  final String _pattern;

  bool matches(String filePath) {
    final normalized = filePath.replaceAll('\\', '/').toLowerCase();
    if (_pattern == '**/*' || _pattern == '**/*.styio') {
      return normalized.endsWith('.styio');
    }
    if (_pattern.endsWith('/**')) {
      final prefix = _pattern.substring(0, _pattern.length - 3);
      return normalized == prefix || normalized.startsWith('$prefix/');
    }
    if (_pattern.startsWith('**/')) {
      final suffix = _pattern.substring(3);
      return normalized == suffix || normalized.endsWith('/$suffix');
    }
    if (_pattern.contains('*')) {
      final expression = RegExp.escape(_pattern)
          .replaceAll(r'\*\*', '.*')
          .replaceAll(r'\*', '[^/]*');
      final regex = RegExp('^$expression\$');
      return regex.hasMatch(normalized);
    }
    return normalized == _pattern;
  }
}
