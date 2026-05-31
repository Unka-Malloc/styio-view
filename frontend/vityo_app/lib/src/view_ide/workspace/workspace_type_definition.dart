import '../editor/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceTypeDefinitionStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noTypes,
  hitLimit,
}

enum WorkspaceTypeDefinitionKind { schema, state }

class WorkspaceTypeDefinitionQuery {
  const WorkspaceTypeDefinitionQuery({
    required this.pattern,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 50,
  });

  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceTypeDefinitionQuery copyWith({
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceTypeDefinitionQuery(
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceTypeDefinitionItem {
  const WorkspaceTypeDefinitionItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
  });

  final String filePath;
  final String name;
  final WorkspaceTypeDefinitionKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;

  String get kindLabel {
    return switch (kind) {
      WorkspaceTypeDefinitionKind.schema => 'schema',
      WorkspaceTypeDefinitionKind.state => 'state',
    };
  }
}

class WorkspaceTypeDefinitionResult {
  const WorkspaceTypeDefinitionResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.typesIndexed,
    required this.types,
    this.message,
  });

  final WorkspaceTypeDefinitionQuery query;
  final WorkspaceTypeDefinitionStatus status;
  final int filesSearched;
  final int typesIndexed;
  final List<WorkspaceTypeDefinitionItem> types;
  final String? message;

  bool get hitLimit => status == WorkspaceTypeDefinitionStatus.hitLimit;

  int get matchCount => types.length;

  int get matchedFileCount => types.map((type) => type.filePath).toSet().length;
}

class WorkspaceTypeDefinitionService {
  const WorkspaceTypeDefinitionService({
    required this.documentStore,
    StyioSyntaxHighlighter syntaxHighlighter =
        const StyioSyntaxHighlighter(),
  }) : _syntaxHighlighter = syntaxHighlighter;

  final WorkspaceDocumentStore documentStore;
  final StyioSyntaxHighlighter _syntaxHighlighter;

  Future<WorkspaceTypeDefinitionResult> findTypeDefinitions({
    required List<String> filePaths,
    required WorkspaceTypeDefinitionQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final normalizedPattern = _normalizedPattern(query.pattern);
    if (normalizedPattern.isEmpty) {
      return WorkspaceTypeDefinitionResult(
        query: query,
        status: WorkspaceTypeDefinitionStatus.emptyPattern,
        filesSearched: 0,
        typesIndexed: 0,
        types: const <WorkspaceTypeDefinitionItem>[],
        message: 'Go to Type Definition requires a type name.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceTypeDefinitionResult(
        query: query,
        status: WorkspaceTypeDefinitionStatus.emptyWorkspace,
        filesSearched: 0,
        typesIndexed: 0,
        types: const <WorkspaceTypeDefinitionItem>[],
      );
    }

    final declarations = <_WorkspaceTypeDeclaration>[];
    final documentsById = <String, DocumentState>{};
    for (final filePath in uniqueFilePaths) {
      final document =
          overlayDocuments[filePath] ??
          await documentStore.loadDocument(filePath);
      documentsById[document.documentId] = document;
      declarations.addAll(_typeDeclarations(document));
    }

    final scoredTypes = <_ScoredWorkspaceTypeDeclaration>[];
    for (var index = 0; index < declarations.length; index += 1) {
      final declaration = declarations[index];
      final score = _scoreDeclaration(
        declaration: declaration,
        normalizedPattern: normalizedPattern,
        declarationIndex: index,
      );
      if (score == null) {
        continue;
      }
      scoredTypes.add(
        _ScoredWorkspaceTypeDeclaration(
          declaration: declaration,
          score: score,
        ),
      );
    }

    if (scoredTypes.isEmpty) {
      return WorkspaceTypeDefinitionResult(
        query: query,
        status: WorkspaceTypeDefinitionStatus.noTypes,
        filesSearched: documentsById.length,
        typesIndexed: declarations.length,
        types: const <WorkspaceTypeDefinitionItem>[],
        message: 'No workspace type definitions match `${query.pattern}`.',
      );
    }

    scoredTypes.sort(_compareScoredDeclarations);
    final maxResults = query.maxResults <= 0 ? 50 : query.maxResults;
    final resultTypes = <WorkspaceTypeDefinitionItem>[];

    for (final scoredType in scoredTypes.take(maxResults)) {
      final declaration = scoredType.declaration;
      final document = documentsById[declaration.filePath];
      if (document == null) {
        continue;
      }
      final position = document.positionForOffset(declaration.range.start);
      resultTypes.add(
        WorkspaceTypeDefinitionItem(
          filePath: declaration.filePath,
          name: declaration.name,
          kind: declaration.kind,
          range: declaration.range,
          line: position.line,
          column: position.column,
          previewText: _linePreview(document, position.line),
        ),
      );
    }

    return WorkspaceTypeDefinitionResult(
      query: query,
      status: scoredTypes.length > maxResults
          ? WorkspaceTypeDefinitionStatus.hitLimit
          : WorkspaceTypeDefinitionStatus.completed,
      filesSearched: documentsById.length,
      typesIndexed: declarations.length,
      types: List<WorkspaceTypeDefinitionItem>.unmodifiable(resultTypes),
      message: scoredTypes.length > maxResults
          ? 'Go to Type Definition stopped after $maxResults type(s).'
          : null,
    );
  }

  List<_WorkspaceTypeDeclaration> _typeDeclarations(DocumentState document) {
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final declarations = <_WorkspaceTypeDeclaration>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.keyword) {
        continue;
      }
      if (token.lexeme != 'schema' && token.lexeme != 'state') {
        continue;
      }
      final nameIndex = _nextIdentifierIndex(tokens, index + 1);
      if (nameIndex == null) {
        continue;
      }
      final nameToken = tokens[nameIndex];
      declarations.add(
        _WorkspaceTypeDeclaration(
          filePath: document.documentId,
          name: nameToken.lexeme,
          kind: token.lexeme == 'schema'
              ? WorkspaceTypeDefinitionKind.schema
              : WorkspaceTypeDefinitionKind.state,
          range: nameToken.range,
        ),
      );
    }
    return declarations;
  }

  static int? _nextIdentifierIndex(List<TokenSpan> tokens, int startIndex) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      return token.kind == TokenKind.identifier ? index : null;
    }
    return null;
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
    WorkspaceTypeDefinitionQuery query,
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

  static String _linePreview(DocumentState document, int line) {
    final lines = document.lines;
    if (lines.isEmpty) {
      return '';
    }
    return lines[line.clamp(0, lines.length - 1)].trimRight();
  }

  static int? _scoreDeclaration({
    required _WorkspaceTypeDeclaration declaration,
    required String normalizedPattern,
    required int declarationIndex,
  }) {
    final name = declaration.name.toLowerCase();
    final filePath = declaration.filePath.toLowerCase();
    final kind = declaration.kind.name.toLowerCase();
    if (name == normalizedPattern) {
      return declarationIndex;
    }
    if (name.startsWith(normalizedPattern)) {
      return 1000 + name.length + declarationIndex;
    }
    final nameIndex = name.indexOf(normalizedPattern);
    if (nameIndex >= 0) {
      return 2000 + nameIndex + name.length + declarationIndex;
    }
    if (kind == normalizedPattern) {
      return 3000 + declarationIndex;
    }
    final pathIndex = filePath.indexOf(normalizedPattern);
    if (pathIndex >= 0) {
      return 4000 + pathIndex + declarationIndex;
    }
    return null;
  }

  static int _compareScoredDeclarations(
    _ScoredWorkspaceTypeDeclaration first,
    _ScoredWorkspaceTypeDeclaration second,
  ) {
    final scoreCompare = first.score.compareTo(second.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final fileCompare = first.declaration.filePath.compareTo(
      second.declaration.filePath,
    );
    if (fileCompare != 0) {
      return fileCompare;
    }
    return first.declaration.range.start.compareTo(
      second.declaration.range.start,
    );
  }

  static String _normalizedPattern(String pattern) {
    return pattern.trim().toLowerCase();
  }

  static String _displayPath(String filePath) {
    return filePath.replaceAll('\\', '/');
  }
}

class _WorkspaceTypeDeclaration {
  const _WorkspaceTypeDeclaration({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
  });

  final String filePath;
  final String name;
  final WorkspaceTypeDefinitionKind kind;
  final SourceRange range;
}

class _ScoredWorkspaceTypeDeclaration {
  const _ScoredWorkspaceTypeDeclaration({
    required this.declaration,
    required this.score,
  });

  final _WorkspaceTypeDeclaration declaration;
  final int score;
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
