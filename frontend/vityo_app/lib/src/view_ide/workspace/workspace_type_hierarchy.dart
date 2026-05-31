import '../editor/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';
import 'workspace_type_definition.dart';

enum WorkspaceTypeHierarchyStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noTypes,
  noRelations,
  hitLimit,
}

enum WorkspaceTypeHierarchyDirection { supertypes, subtypes }

class WorkspaceTypeHierarchyQuery {
  const WorkspaceTypeHierarchyQuery({
    required this.pattern,
    this.direction = WorkspaceTypeHierarchyDirection.supertypes,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final WorkspaceTypeHierarchyDirection direction;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceTypeHierarchyQuery copyWith({
    String? pattern,
    WorkspaceTypeHierarchyDirection? direction,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceTypeHierarchyQuery(
      pattern: pattern ?? this.pattern,
      direction: direction ?? this.direction,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceTypeHierarchySymbol {
  const WorkspaceTypeHierarchySymbol({
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

class WorkspaceTypeHierarchyLocation {
  const WorkspaceTypeHierarchyLocation({
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

class WorkspaceTypeHierarchyRelation {
  const WorkspaceTypeHierarchyRelation({
    required this.symbol,
    required this.locations,
  });

  final WorkspaceTypeHierarchySymbol symbol;
  final List<WorkspaceTypeHierarchyLocation> locations;

  int get referenceCount => locations.length;

  WorkspaceTypeHierarchyLocation get firstLocation => locations.first;
}

class WorkspaceTypeHierarchyResult {
  const WorkspaceTypeHierarchyResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.typesIndexed,
    required this.target,
    required this.relations,
    this.message,
  });

  final WorkspaceTypeHierarchyQuery query;
  final WorkspaceTypeHierarchyStatus status;
  final int filesSearched;
  final int typesIndexed;
  final WorkspaceTypeHierarchySymbol? target;
  final List<WorkspaceTypeHierarchyRelation> relations;
  final String? message;

  bool get hitLimit => status == WorkspaceTypeHierarchyStatus.hitLimit;

  int get relationCount => relations.length;

  int get referenceCount => relations.fold<int>(
    0,
    (count, relation) => count + relation.referenceCount,
  );

  int get matchedFileCount =>
      relations.map((relation) => relation.symbol.filePath).toSet().length;
}

class WorkspaceTypeHierarchyService {
  const WorkspaceTypeHierarchyService({
    required this.documentStore,
    StyioSyntaxHighlighter syntaxHighlighter =
        const StyioSyntaxHighlighter(),
  }) : _syntaxHighlighter = syntaxHighlighter;

  final WorkspaceDocumentStore documentStore;
  final StyioSyntaxHighlighter _syntaxHighlighter;

  Future<WorkspaceTypeHierarchyResult> buildHierarchy({
    required List<String> filePaths,
    required WorkspaceTypeHierarchyQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final normalizedPattern = _normalizedPattern(query.pattern);
    if (normalizedPattern.isEmpty) {
      return WorkspaceTypeHierarchyResult(
        query: query,
        status: WorkspaceTypeHierarchyStatus.emptyPattern,
        filesSearched: 0,
        typesIndexed: 0,
        target: null,
        relations: const <WorkspaceTypeHierarchyRelation>[],
        message: 'Type Hierarchy requires a type name.',
      );
    }

    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceTypeHierarchyResult(
        query: query,
        status: WorkspaceTypeHierarchyStatus.emptyWorkspace,
        filesSearched: 0,
        typesIndexed: 0,
        target: null,
        relations: const <WorkspaceTypeHierarchyRelation>[],
      );
    }

    final documentsById = <String, DocumentState>{};
    final declarations = <_WorkspaceTypeHierarchyDeclaration>[];
    final referencesByDeclaration =
        <_WorkspaceTypeHierarchyDeclaration, List<_WorkspaceTypeReference>>{};

    for (final filePath in uniqueFilePaths) {
      final document =
          overlayDocuments[filePath] ??
          await documentStore.loadDocument(filePath);
      documentsById[document.documentId] = document;
      final declarationsForDocument = _typeDeclarations(document);
      declarations.addAll(declarationsForDocument);
      for (final declaration in declarationsForDocument) {
        referencesByDeclaration[declaration] = _typeReferences(
          document,
          declaration,
        );
      }
    }

    if (declarations.isEmpty) {
      return WorkspaceTypeHierarchyResult(
        query: query,
        status: WorkspaceTypeHierarchyStatus.noTypes,
        filesSearched: documentsById.length,
        typesIndexed: 0,
        target: null,
        relations: const <WorkspaceTypeHierarchyRelation>[],
        message: 'No workspace type declarations are available.',
      );
    }

    final scoredTargets = <_ScoredWorkspaceTypeHierarchyDeclaration>[];
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
      scoredTargets.add(
        _ScoredWorkspaceTypeHierarchyDeclaration(
          declaration: declaration,
          score: score,
        ),
      );
    }

    if (scoredTargets.isEmpty) {
      return WorkspaceTypeHierarchyResult(
        query: query,
        status: WorkspaceTypeHierarchyStatus.noTypes,
        filesSearched: documentsById.length,
        typesIndexed: declarations.length,
        target: null,
        relations: const <WorkspaceTypeHierarchyRelation>[],
        message: 'No workspace type declarations match `${query.pattern}`.',
      );
    }

    scoredTargets.sort(_compareScoredDeclarations);
    final targetDeclaration = scoredTargets.first.declaration;
    final targetDocument = documentsById[targetDeclaration.filePath];
    final target = targetDocument == null
        ? null
        : _symbolForDeclaration(targetDeclaration, targetDocument);
    if (target == null) {
      return WorkspaceTypeHierarchyResult(
        query: query,
        status: WorkspaceTypeHierarchyStatus.noTypes,
        filesSearched: documentsById.length,
        typesIndexed: declarations.length,
        target: null,
        relations: const <WorkspaceTypeHierarchyRelation>[],
      );
    }

    final declarationsByName =
        <String, List<_WorkspaceTypeHierarchyDeclaration>>{};
    for (final declaration in declarations) {
      declarationsByName
          .putIfAbsent(declaration.name.toLowerCase(), () => [])
          .add(declaration);
    }

    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final accumulators = <String, _TypeHierarchyRelationAccumulator>{};
    var locationCount = 0;
    var hitLimit = false;

    void addRelation({
      required _WorkspaceTypeHierarchyDeclaration declaration,
      required WorkspaceTypeHierarchyLocation location,
    }) {
      if (hitLimit || declaration == targetDeclaration) {
        return;
      }
      final document = documentsById[declaration.filePath];
      if (document == null) {
        return;
      }
      final symbol = _symbolForDeclaration(declaration, document);
      final key = _declarationKey(declaration);
      accumulators
          .putIfAbsent(key, () => _TypeHierarchyRelationAccumulator(symbol))
          .locations
          .add(location);
      locationCount += 1;
      if (locationCount >= maxResults) {
        hitLimit = true;
      }
    }

    switch (query.direction) {
      case WorkspaceTypeHierarchyDirection.supertypes:
        final references =
            referencesByDeclaration[targetDeclaration] ??
            const <_WorkspaceTypeReference>[];
        for (final reference in references) {
          final relatedDeclarations =
              declarationsByName[reference.name.toLowerCase()] ??
              const <_WorkspaceTypeHierarchyDeclaration>[];
          for (final declaration in relatedDeclarations) {
            addRelation(declaration: declaration, location: reference.location);
            if (hitLimit) {
              break;
            }
          }
          if (hitLimit) {
            break;
          }
        }
      case WorkspaceTypeHierarchyDirection.subtypes:
        for (final declaration in declarations) {
          final references =
              referencesByDeclaration[declaration] ??
              const <_WorkspaceTypeReference>[];
          for (final reference in references) {
            if (reference.name.toLowerCase() !=
                targetDeclaration.name.toLowerCase()) {
              continue;
            }
            addRelation(declaration: declaration, location: reference.location);
            if (hitLimit) {
              break;
            }
          }
          if (hitLimit) {
            break;
          }
        }
    }

    final relations = accumulators.values
        .map(
          (accumulator) => WorkspaceTypeHierarchyRelation(
            symbol: accumulator.symbol,
            locations: List<WorkspaceTypeHierarchyLocation>.unmodifiable(
              accumulator.locations,
            ),
          ),
        )
        .toList(growable: false)
      ..sort(_compareRelations);
    final directionLabel =
        query.direction == WorkspaceTypeHierarchyDirection.supertypes
        ? 'supertypes'
        : 'subtypes';

    return WorkspaceTypeHierarchyResult(
      query: query,
      status: hitLimit
          ? WorkspaceTypeHierarchyStatus.hitLimit
          : relations.isEmpty
          ? WorkspaceTypeHierarchyStatus.noRelations
          : WorkspaceTypeHierarchyStatus.completed,
      filesSearched: documentsById.length,
      typesIndexed: declarations.length,
      target: target,
      relations: List<WorkspaceTypeHierarchyRelation>.unmodifiable(relations),
      message: relations.isEmpty
          ? 'No $directionLabel found for ${target.name}.'
          : hitLimit
          ? 'Type Hierarchy stopped after $maxResults reference(s).'
          : null,
    );
  }

  List<_WorkspaceTypeHierarchyDeclaration> _typeDeclarations(
    DocumentState document,
  ) {
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final declarations = <_WorkspaceTypeHierarchyDeclaration>[];
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
        _WorkspaceTypeHierarchyDeclaration(
          filePath: document.documentId,
          name: nameToken.lexeme,
          kind: token.lexeme == 'schema'
              ? WorkspaceTypeDefinitionKind.schema
              : WorkspaceTypeDefinitionKind.state,
          nameRange: nameToken.range,
          bodyRange: _bodyRange(document, tokens, nameIndex),
        ),
      );
    }
    return declarations;
  }

  List<_WorkspaceTypeReference> _typeReferences(
    DocumentState document,
    _WorkspaceTypeHierarchyDeclaration declaration,
  ) {
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final references = <_WorkspaceTypeReference>[];
    final normalizedDeclarationName = declaration.name.toLowerCase();
    for (final token in tokens) {
      if (token.kind != TokenKind.identifier ||
          !declaration.bodyRange.contains(token.range.start) ||
          token.range.start == declaration.nameRange.start ||
          token.lexeme.toLowerCase() == normalizedDeclarationName) {
        continue;
      }
      final position = document.positionForOffset(token.range.start);
      references.add(
        _WorkspaceTypeReference(
          name: token.lexeme,
          location: WorkspaceTypeHierarchyLocation(
            filePath: document.documentId,
            range: token.range,
            line: position.line,
            column: position.column,
            previewText: _linePreview(document, position.line),
          ),
        ),
      );
    }
    return references;
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

  static SourceRange _bodyRange(
    DocumentState document,
    List<TokenSpan> tokens,
    int nameIndex,
  ) {
    final openingIndex = _nextPunctuationIndex(tokens, nameIndex + 1, '{');
    if (openingIndex != null) {
      final closingIndex = _matchingBraceIndex(tokens, openingIndex);
      if (closingIndex != null) {
        return SourceRange(
          start: tokens[openingIndex].range.end,
          end: tokens[closingIndex].range.start,
        );
      }
      return SourceRange(
        start: tokens[openingIndex].range.end,
        end: document.length,
      );
    }
    final nameToken = tokens[nameIndex];
    final line = document.positionForOffset(nameToken.range.end).line;
    return SourceRange(
      start: nameToken.range.end,
      end: document.offsetForLineColumn(
        line: line,
        column: document.lines[line].length,
      ),
    );
  }

  static int? _nextPunctuationIndex(
    List<TokenSpan> tokens,
    int startIndex,
    String lexeme,
  ) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == lexeme) {
        return index;
      }
      if (token.kind == TokenKind.keyword) {
        return null;
      }
    }
    return null;
  }

  static int? _matchingBraceIndex(List<TokenSpan> tokens, int openingIndex) {
    var depth = 0;
    for (var index = openingIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.punctuation) {
        continue;
      }
      if (token.lexeme == '{') {
        depth += 1;
        continue;
      }
      if (token.lexeme == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
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
    WorkspaceTypeHierarchyQuery query,
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

  static WorkspaceTypeHierarchySymbol _symbolForDeclaration(
    _WorkspaceTypeHierarchyDeclaration declaration,
    DocumentState document,
  ) {
    final position = document.positionForOffset(declaration.nameRange.start);
    return WorkspaceTypeHierarchySymbol(
      filePath: declaration.filePath,
      name: declaration.name,
      kind: declaration.kind,
      range: declaration.nameRange,
      line: position.line,
      column: position.column,
      previewText: _linePreview(document, position.line),
    );
  }

  static int? _scoreDeclaration({
    required _WorkspaceTypeHierarchyDeclaration declaration,
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
    _ScoredWorkspaceTypeHierarchyDeclaration first,
    _ScoredWorkspaceTypeHierarchyDeclaration second,
  ) {
    final scoreCompare = first.score.compareTo(second.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    return _compareDeclarations(first.declaration, second.declaration);
  }

  static int _compareRelations(
    WorkspaceTypeHierarchyRelation first,
    WorkspaceTypeHierarchyRelation second,
  ) {
    final nameCompare = first.symbol.name.compareTo(second.symbol.name);
    if (nameCompare != 0) {
      return nameCompare;
    }
    final fileCompare = first.symbol.filePath.compareTo(second.symbol.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    return first.symbol.range.start.compareTo(second.symbol.range.start);
  }

  static int _compareDeclarations(
    _WorkspaceTypeHierarchyDeclaration first,
    _WorkspaceTypeHierarchyDeclaration second,
  ) {
    final fileCompare = first.filePath.compareTo(second.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    return first.nameRange.start.compareTo(second.nameRange.start);
  }

  static String _declarationKey(
    _WorkspaceTypeHierarchyDeclaration declaration,
  ) {
    return '${declaration.filePath}:${declaration.nameRange.start}';
  }

  static String _linePreview(DocumentState document, int line) {
    final lines = document.lines;
    if (lines.isEmpty) {
      return '';
    }
    return lines[line.clamp(0, lines.length - 1)].trimRight();
  }

  static String _normalizedPattern(String pattern) {
    return pattern.trim().toLowerCase();
  }

  static String _displayPath(String filePath) {
    return filePath.replaceAll('\\', '/');
  }
}

class _WorkspaceTypeHierarchyDeclaration {
  const _WorkspaceTypeHierarchyDeclaration({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.nameRange,
    required this.bodyRange,
  });

  final String filePath;
  final String name;
  final WorkspaceTypeDefinitionKind kind;
  final SourceRange nameRange;
  final SourceRange bodyRange;
}

class _WorkspaceTypeReference {
  const _WorkspaceTypeReference({
    required this.name,
    required this.location,
  });

  final String name;
  final WorkspaceTypeHierarchyLocation location;
}

class _ScoredWorkspaceTypeHierarchyDeclaration {
  const _ScoredWorkspaceTypeHierarchyDeclaration({
    required this.declaration,
    required this.score,
  });

  final _WorkspaceTypeHierarchyDeclaration declaration;
  final int score;
}

class _TypeHierarchyRelationAccumulator {
  _TypeHierarchyRelationAccumulator(this.symbol);

  final WorkspaceTypeHierarchySymbol symbol;
  final List<WorkspaceTypeHierarchyLocation> locations =
      <WorkspaceTypeHierarchyLocation>[];
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
