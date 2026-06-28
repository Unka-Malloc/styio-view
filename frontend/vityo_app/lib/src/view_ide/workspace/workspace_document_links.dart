import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceDocumentLinksStatus {
  completed,
  emptyWorkspace,
  noLinks,
  hitLimit,
}

enum WorkspaceDocumentLinkKind {
  workspaceImport,
  externalImport,
  unresolvedImport,
}

class WorkspaceDocumentLinksQuery {
  const WorkspaceDocumentLinksQuery({
    required this.targetFilePath,
    this.pattern = '',
    this.includeExternal = true,
    this.includeUnresolved = true,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String targetFilePath;
  final String pattern;
  final bool includeExternal;
  final bool includeUnresolved;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceDocumentLinksQuery copyWith({
    String? targetFilePath,
    String? pattern,
    bool? includeExternal,
    bool? includeUnresolved,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceDocumentLinksQuery(
      targetFilePath: targetFilePath ?? this.targetFilePath,
      pattern: pattern ?? this.pattern,
      includeExternal: includeExternal ?? this.includeExternal,
      includeUnresolved: includeUnresolved ?? this.includeUnresolved,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceDocumentLinkItem {
  const WorkspaceDocumentLinkItem({
    required this.sourceFilePath,
    required this.target,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    this.resolvedFilePath,
  });

  final String sourceFilePath;
  final String target;
  final WorkspaceDocumentLinkKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final String? resolvedFilePath;

  String get kindLabel {
    return switch (kind) {
      WorkspaceDocumentLinkKind.workspaceImport => 'workspace import',
      WorkspaceDocumentLinkKind.externalImport => 'external import',
      WorkspaceDocumentLinkKind.unresolvedImport => 'unresolved import',
    };
  }

  String get targetLabel => resolvedFilePath ?? target;

  bool get canOpen => resolvedFilePath != null;
}

class WorkspaceDocumentLinksResult {
  const WorkspaceDocumentLinksResult({
    required this.query,
    required this.status,
    required this.filePath,
    required this.filesSearched,
    required this.linksIndexed,
    required this.links,
    this.message,
  });

  final WorkspaceDocumentLinksQuery query;
  final WorkspaceDocumentLinksStatus status;
  final String filePath;
  final int filesSearched;
  final int linksIndexed;
  final List<WorkspaceDocumentLinkItem> links;
  final String? message;

  bool get hitLimit => status == WorkspaceDocumentLinksStatus.hitLimit;

  int get linkCount => links.length;

  int get workspaceLinkCount => links
      .where((link) => link.kind == WorkspaceDocumentLinkKind.workspaceImport)
      .length;

  int get externalLinkCount => links
      .where((link) => link.kind == WorkspaceDocumentLinkKind.externalImport)
      .length;

  int get unresolvedLinkCount => links
      .where((link) => link.kind == WorkspaceDocumentLinkKind.unresolvedImport)
      .length;
}

class WorkspaceDocumentLinksService {
  const WorkspaceDocumentLinksService({required this.documentStore});

  final WorkspaceDocumentStore documentStore;

  Future<WorkspaceDocumentLinksResult> collectLinks({
    required List<String> filePaths,
    required WorkspaceDocumentLinksQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final targetFilePath = query.targetFilePath;
    final uniqueFilePaths = _uniqueFilePaths(filePaths);
    if (!uniqueFilePaths.contains(targetFilePath) ||
        !_isIndexable(targetFilePath, query)) {
      return WorkspaceDocumentLinksResult(
        query: query,
        status: WorkspaceDocumentLinksStatus.emptyWorkspace,
        filePath: targetFilePath,
        filesSearched: 0,
        linksIndexed: 0,
        links: const <WorkspaceDocumentLinkItem>[],
        message: 'Document Links requires an active Styio workspace file.',
      );
    }

    final document =
        overlayDocuments[targetFilePath] ??
        await documentStore.loadDocument(targetFilePath);
    final documentIds = uniqueFilePaths
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    final directives = _parseImports(document);
    final normalizedPattern = _normalizedPattern(query.pattern);
    final links = <WorkspaceDocumentLinkItem>[];

    for (final directive in directives) {
      final kind = _linkKind(directive.target, documentIds);
      if (kind == WorkspaceDocumentLinkKind.externalImport &&
          !query.includeExternal) {
        continue;
      }
      if (kind == WorkspaceDocumentLinkKind.unresolvedImport &&
          !query.includeUnresolved) {
        continue;
      }
      final resolvedFilePath = kind == WorkspaceDocumentLinkKind.workspaceImport
          ? _resolveImportTarget(directive.target, documentIds)
          : null;
      if (!_matchesPattern(
        directive.target,
        resolvedFilePath,
        kind,
        normalizedPattern,
      )) {
        continue;
      }
      final position = document.positionForOffset(directive.range.start);
      links.add(
        WorkspaceDocumentLinkItem(
          sourceFilePath: targetFilePath,
          target: directive.target,
          kind: kind,
          range: directive.range,
          line: position.line,
          column: position.column,
          previewText: _linePreview(document, position.line),
          resolvedFilePath: resolvedFilePath,
        ),
      );
    }

    if (links.isEmpty) {
      return WorkspaceDocumentLinksResult(
        query: query,
        status: WorkspaceDocumentLinksStatus.noLinks,
        filePath: targetFilePath,
        filesSearched: 1,
        linksIndexed: directives.length,
        links: const <WorkspaceDocumentLinkItem>[],
        message: normalizedPattern.isEmpty
            ? 'No document links found in $targetFilePath.'
            : 'No document links match `${query.pattern}`.',
      );
    }

    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final limitedLinks = links.take(maxResults).toList(growable: false);
    return WorkspaceDocumentLinksResult(
      query: query,
      status: links.length > maxResults
          ? WorkspaceDocumentLinksStatus.hitLimit
          : WorkspaceDocumentLinksStatus.completed,
      filePath: targetFilePath,
      filesSearched: 1,
      linksIndexed: directives.length,
      links: List<WorkspaceDocumentLinkItem>.unmodifiable(limitedLinks),
      message: links.length > maxResults
          ? 'Document Links stopped after $maxResults link(s).'
          : null,
    );
  }

  static WorkspaceDocumentLinkKind _linkKind(
    String target,
    List<String> documentIds,
  ) {
    if (_isExternalImport(target)) {
      return WorkspaceDocumentLinkKind.externalImport;
    }
    return _resolveImportTarget(target, documentIds) == null
        ? WorkspaceDocumentLinkKind.unresolvedImport
        : WorkspaceDocumentLinkKind.workspaceImport;
  }

  static bool _matchesPattern(
    String target,
    String? resolvedFilePath,
    WorkspaceDocumentLinkKind kind,
    String normalizedPattern,
  ) {
    if (normalizedPattern.isEmpty) {
      return true;
    }
    return target.toLowerCase().contains(normalizedPattern) ||
        (resolvedFilePath?.toLowerCase().contains(normalizedPattern) ??
            false) ||
        kind.name.toLowerCase().contains(normalizedPattern);
  }

  static List<_WorkspaceImportDirective> _parseImports(DocumentState document) {
    final imports = <_WorkspaceImportDirective>[];
    final source = document.text;
    var lineStart = 0;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final trimmedLeft = line.replaceFirst(RegExp(r'^\s+'), '');
      final leadingWhitespace = line.length - trimmedLeft.length;
      final importStart = lineStart + leadingWhitespace;
      if (trimmedLeft.startsWith('@import')) {
        final target = _importTargetFromLine(trimmedLeft);
        if (target != null && target.isNotEmpty) {
          final targetStartInLine = trimmedLeft.indexOf(target);
          imports.add(
            _WorkspaceImportDirective(
              target: target,
              range: SourceRange(
                start: importStart + targetStartInLine,
                end: importStart + targetStartInLine + target.length,
              ),
            ),
          );
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return imports;
  }

  static String? _importTargetFromLine(String lineText) {
    final openBrace = lineText.indexOf('{');
    final closeBrace = lineText.lastIndexOf('}');
    if (openBrace >= 0 && closeBrace > openBrace) {
      return lineText.substring(openBrace + 1, closeBrace).trim();
    }
    return lineText.replaceFirst('@import', '').trim();
  }

  static bool _isExternalImport(String target) {
    return target.startsWith('styio/');
  }

  static String? _resolveImportTarget(
    String target,
    Iterable<String> documentIds,
  ) {
    final candidates = <String>{
      target,
      '$target.styio',
      if (target.startsWith('./')) target.substring(2),
      if (target.startsWith('./')) '${target.substring(2)}.styio',
    };
    for (final documentId in documentIds) {
      if (candidates.contains(documentId)) {
        return documentId;
      }
      if (candidates.any((candidate) => documentId.endsWith('/$candidate'))) {
        return documentId;
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

  static bool _isIndexable(String filePath, WorkspaceDocumentLinksQuery query) {
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

  static String _normalizedPattern(String pattern) {
    return pattern.trim().replaceAll('\\', '/').toLowerCase();
  }
}

class _WorkspaceImportDirective {
  const _WorkspaceImportDirective({
    required this.target,
    required this.range,
  });

  final String target;
  final SourceRange range;
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
      final regex = RegExp(
        '^$expression\$',
      );
      return regex.hasMatch(normalized);
    }
    return normalized == _pattern;
  }
}
