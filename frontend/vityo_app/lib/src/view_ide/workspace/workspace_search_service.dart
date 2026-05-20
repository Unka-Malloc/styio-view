import '../editor/document_state.dart';
import '../language/contract/language_contract.dart';
import '../language/service/language_service_foundation.dart';
import '../language/service/semantic_snapshot_provider.dart';
import 'workspace_document_store_types.dart';

class WorkspaceSearchMatch {
  const WorkspaceSearchMatch({
    required this.documentId,
    required this.range,
    required this.text,
    required this.lineNumber,
    required this.lineText,
  });

  final String documentId;
  final SourceRange range;
  final String text;
  final int lineNumber;
  final String lineText;
}

class WorkspaceSearchFailure {
  const WorkspaceSearchFailure({
    required this.documentId,
    required this.message,
  });

  final String documentId;
  final String message;
}

class WorkspaceSearchResult {
  const WorkspaceSearchResult({
    required this.matches,
    this.failures = const <WorkspaceSearchFailure>[],
    this.truncated = false,
  });

  final List<WorkspaceSearchMatch> matches;
  final List<WorkspaceSearchFailure> failures;
  final bool truncated;
}

class WorkspaceSearchIndexDocument {
  WorkspaceSearchIndexDocument._({
    required this.documentId,
    required this.text,
    required this.revision,
    required this.lineCount,
    required this.byteLength,
  });

  factory WorkspaceSearchIndexDocument.fromDocument(DocumentState document) {
    return WorkspaceSearchIndexDocument._(
      documentId: document.documentId,
      text: document.text,
      revision: document.revision,
      lineCount: _countWorkspaceSearchLines(document.text),
      byteLength: document.text.length,
    );
  }

  final String documentId;
  final String text;
  final int revision;
  final int lineCount;
  final int byteLength;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'lineCount': lineCount,
      'byteLength': byteLength,
    };
  }

  DocumentState toDocumentState() {
    return DocumentState(
      documentId: documentId,
      text: text,
      revision: revision,
    );
  }
}

class WorkspaceSearchIndex {
  const WorkspaceSearchIndex({
    required this.documents,
    required this.createdAt,
    this.truncated = false,
  });

  final List<WorkspaceSearchIndexDocument> documents;
  final DateTime createdAt;
  final bool truncated;

  int get documentCount => documents.length;

  int get totalByteLength =>
      documents.fold<int>(0, (total, document) => total + document.byteLength);

  int get totalLineCount =>
      documents.fold<int>(0, (total, document) => total + document.lineCount);

  List<String> get documentIds {
    return documents
        .map((document) => document.documentId)
        .toList(growable: false);
  }

  WorkspaceSearchResult search({
    required String query,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
    int maxMatches = 1000,
  }) {
    if (query.isEmpty || maxMatches <= 0) {
      return const WorkspaceSearchResult(matches: <WorkspaceSearchMatch>[]);
    }
    final matches = <WorkspaceSearchMatch>[];
    var omitted = false;

    for (
      var documentIndex = 0;
      documentIndex < documents.length;
      documentIndex += 1
    ) {
      if (matches.length >= maxMatches) {
        omitted = true;
        break;
      }
      final document = documents[documentIndex].toDocumentState();
      final documentResult = _searchDocument(
        document,
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        useRegex: useRegex,
        remaining: maxMatches - matches.length,
      );
      matches.addAll(documentResult.matches);
      if (documentResult.truncated ||
          (matches.length >= maxMatches &&
              documentIndex < documents.length - 1)) {
        omitted = true;
        break;
      }
    }

    return WorkspaceSearchResult(
      matches: List.unmodifiable(matches),
      truncated: omitted || truncated,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'createdAt': createdAt.toIso8601String(),
      'documentCount': documentCount,
      'totalByteLength': totalByteLength,
      'totalLineCount': totalLineCount,
      'truncated': truncated,
      'documents': documents
          .map((document) => document.toJson())
          .toList(growable: false),
      // TODO(search-index): Persist only metadata plus an invalidation key when
      // the File System Manager exposes stable document mtime/content hashes.
    };
  }
}

class WorkspaceSearchIndexBuildResult {
  const WorkspaceSearchIndexBuildResult({
    required this.index,
    this.failures = const <WorkspaceSearchFailure>[],
  });

  final WorkspaceSearchIndex index;
  final List<WorkspaceSearchFailure> failures;
}

class WorkspaceReplaceDocumentResult {
  const WorkspaceReplaceDocumentResult({
    required this.documentId,
    required this.replacementCount,
    required this.revision,
  });

  final String documentId;
  final int replacementCount;
  final int revision;
}

class WorkspaceReplaceResult {
  const WorkspaceReplaceResult({
    required this.documents,
    this.failures = const <WorkspaceSearchFailure>[],
    this.truncated = false,
  });

  final List<WorkspaceReplaceDocumentResult> documents;
  final List<WorkspaceSearchFailure> failures;
  final bool truncated;

  int get replacementCount => documents.fold<int>(
    0,
    (total, document) => total + document.replacementCount,
  );
}

class WorkspaceReplacePreviewDocument {
  const WorkspaceReplacePreviewDocument({
    required this.documentId,
    required this.beforeText,
    required this.afterText,
    required this.replacementCount,
    required this.revision,
  });

  final String documentId;
  final String beforeText;
  final String afterText;
  final int replacementCount;
  final int revision;

  bool get changed => beforeText != afterText;
}

class WorkspaceReplacePreview {
  const WorkspaceReplacePreview({
    required this.documents,
    this.failures = const <WorkspaceSearchFailure>[],
    this.truncated = false,
  });

  final List<WorkspaceReplacePreviewDocument> documents;
  final List<WorkspaceSearchFailure> failures;
  final bool truncated;

  int get replacementCount => documents.fold<int>(
    0,
    (total, document) => total + document.replacementCount,
  );
}

class WorkspaceQuickOpenMatch {
  const WorkspaceQuickOpenMatch({
    required this.documentId,
    required this.label,
    required this.score,
  });

  final String documentId;
  final String label;
  final int score;
}

class WorkspaceQuickOpenResult {
  const WorkspaceQuickOpenResult({
    required this.matches,
    this.truncated = false,
  });

  final List<WorkspaceQuickOpenMatch> matches;
  final bool truncated;
}

class WorkspaceSymbolMatch {
  const WorkspaceSymbolMatch({
    required this.documentId,
    required this.name,
    required this.kind,
    required this.nameRange,
    required this.declarationRange,
    required this.lineNumber,
    required this.lineText,
    required this.score,
    this.detail,
  });

  final String documentId;
  final String name;
  final ResolvedElementKind kind;
  final SourceRange nameRange;
  final SourceRange declarationRange;
  final int lineNumber;
  final String lineText;
  final int score;
  final String? detail;
}

class WorkspaceSymbolSearchResult {
  const WorkspaceSymbolSearchResult({
    required this.matches,
    this.failures = const <WorkspaceSearchFailure>[],
    this.truncated = false,
  });

  final List<WorkspaceSymbolMatch> matches;
  final List<WorkspaceSearchFailure> failures;
  final bool truncated;
}

class WorkspaceSymbolSearchService {
  const WorkspaceSymbolSearchService({
    required this.documentStore,
    required this.semanticSnapshotProvider,
  });

  final WorkspaceDocumentStore documentStore;
  final SemanticSnapshotProvider semanticSnapshotProvider;

  Future<WorkspaceSymbolSearchResult> searchSymbols({
    required Iterable<String> documentIds,
    required String query,
    Set<ResolvedElementKind> kinds = const <ResolvedElementKind>{},
    int maxResults = 100,
  }) async {
    if (maxResults <= 0) {
      return const WorkspaceSymbolSearchResult(
        matches: <WorkspaceSymbolMatch>[],
      );
    }
    final normalizedQuery = query.trim().toLowerCase();
    final matches = <WorkspaceSymbolMatch>[];
    final failures = <WorkspaceSearchFailure>[];
    var truncated = false;

    for (final documentId in _uniqueDocumentIds(documentIds)) {
      if (matches.length >= maxResults) {
        truncated = true;
        break;
      }
      late final DocumentState document;
      try {
        document = await documentStore.loadDocument(documentId);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      final snapshot = semanticSnapshotProvider.snapshotFor(document).snapshot;
      for (final element in snapshot.elements) {
        if (matches.length >= maxResults) {
          truncated = true;
          break;
        }
        if (kinds.isNotEmpty && !kinds.contains(element.kind)) {
          continue;
        }
        final score = _scoreWorkspaceSymbolMatch(
          name: element.name,
          documentId: document.documentId,
          query: normalizedQuery,
        );
        if (score == null) {
          continue;
        }
        matches.add(
          WorkspaceSymbolMatch(
            documentId: document.documentId,
            name: element.name,
            kind: element.kind,
            nameRange: element.nameRange,
            declarationRange: element.declarationRange,
            lineNumber: _lineNumberForOffset(
              document.text,
              element.nameRange.start,
            ),
            lineText: _lineTextForOffset(
              document.text,
              element.nameRange.start,
            ),
            score: score,
            detail: element.detail,
          ),
        );
      }
      if (truncated) {
        break;
      }
    }

    matches.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) {
        return byScore;
      }
      final byName = left.name.compareTo(right.name);
      if (byName != 0) {
        return byName;
      }
      return left.documentId.compareTo(right.documentId);
    });
    return WorkspaceSymbolSearchResult(
      matches: List.unmodifiable(matches),
      failures: List.unmodifiable(failures),
      truncated: truncated,
    );
  }
}

class WorkspaceQuickOpenService {
  const WorkspaceQuickOpenService();

  WorkspaceQuickOpenResult searchFiles({
    required Iterable<String> documentIds,
    required String query,
    int maxResults = 20,
  }) {
    if (maxResults <= 0) {
      return const WorkspaceQuickOpenResult(
        matches: <WorkspaceQuickOpenMatch>[],
      );
    }
    final orderedDocumentIds = _uniqueDocumentIds(documentIds);
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      final matches = orderedDocumentIds
          .take(maxResults)
          .map(
            (documentId) => WorkspaceQuickOpenMatch(
              documentId: documentId,
              label: _workspaceFileLabel(documentId),
              score: 0,
            ),
          )
          .toList(growable: false);
      return WorkspaceQuickOpenResult(
        matches: matches,
        truncated: orderedDocumentIds.length > maxResults,
      );
    }

    final matches = <WorkspaceQuickOpenMatch>[];
    for (final documentId in orderedDocumentIds) {
      final score = _scoreWorkspaceQuickOpenMatch(documentId, normalizedQuery);
      if (score == null) {
        continue;
      }
      matches.add(
        WorkspaceQuickOpenMatch(
          documentId: documentId,
          label: _workspaceFileLabel(documentId),
          score: score,
        ),
      );
    }
    matches.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) {
        return byScore;
      }
      return left.documentId.compareTo(right.documentId);
    });
    return WorkspaceQuickOpenResult(
      matches: List.unmodifiable(matches.take(maxResults)),
      truncated: matches.length > maxResults,
    );
  }
}

class WorkspaceSearchService {
  const WorkspaceSearchService({required this.documentStore});

  final WorkspaceDocumentStore documentStore;

  Future<WorkspaceSearchIndexBuildResult> buildIndex({
    required Iterable<String> documentIds,
    int maxDocuments = 5000,
  }) async {
    if (maxDocuments <= 0) {
      return WorkspaceSearchIndexBuildResult(
        index: WorkspaceSearchIndex(
          documents: const <WorkspaceSearchIndexDocument>[],
          createdAt: DateTime.now().toUtc(),
          truncated: documentIds.isNotEmpty,
        ),
      );
    }

    final documents = <WorkspaceSearchIndexDocument>[];
    final failures = <WorkspaceSearchFailure>[];
    final orderedDocumentIds = _uniqueDocumentIds(documentIds);
    var truncated = false;

    for (
      var documentIndex = 0;
      documentIndex < orderedDocumentIds.length;
      documentIndex += 1
    ) {
      if (documents.length >= maxDocuments) {
        truncated = true;
        break;
      }
      final documentId = orderedDocumentIds[documentIndex];
      late final DocumentState document;
      try {
        document = await documentStore.loadDocument(documentId);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      documents.add(WorkspaceSearchIndexDocument.fromDocument(document));
    }

    return WorkspaceSearchIndexBuildResult(
      index: WorkspaceSearchIndex(
        documents: List.unmodifiable(documents),
        createdAt: DateTime.now().toUtc(),
        truncated: truncated,
      ),
      failures: List.unmodifiable(failures),
    );
  }

  Future<WorkspaceSearchResult> search({
    required Iterable<String> documentIds,
    required String query,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
    int maxMatches = 1000,
  }) async {
    if (query.isEmpty || maxMatches <= 0) {
      return const WorkspaceSearchResult(matches: <WorkspaceSearchMatch>[]);
    }
    final matches = <WorkspaceSearchMatch>[];
    final failures = <WorkspaceSearchFailure>[];
    var truncated = false;

    final orderedDocumentIds = _uniqueDocumentIds(documentIds);
    for (
      var documentIndex = 0;
      documentIndex < orderedDocumentIds.length;
      documentIndex += 1
    ) {
      final documentId = orderedDocumentIds[documentIndex];
      if (matches.length >= maxMatches) {
        truncated = true;
        break;
      }
      late final DocumentState document;
      try {
        document = await documentStore.loadDocument(documentId);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      final documentResult = _searchDocument(
        document,
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        useRegex: useRegex,
        remaining: maxMatches - matches.length,
      );
      matches.addAll(documentResult.matches);
      if (documentResult.truncated ||
          (matches.length >= maxMatches &&
              documentIndex < orderedDocumentIds.length - 1)) {
        truncated = true;
        break;
      }
    }

    return WorkspaceSearchResult(
      matches: List.unmodifiable(matches),
      failures: List.unmodifiable(failures),
      truncated: truncated,
    );
  }

  Future<WorkspaceReplaceResult> replaceAll({
    required Iterable<String> documentIds,
    required String query,
    required String replacement,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
    int maxReplacements = 1000,
  }) async {
    if (query.isEmpty || maxReplacements <= 0) {
      return const WorkspaceReplaceResult(
        documents: <WorkspaceReplaceDocumentResult>[],
      );
    }
    final documents = <WorkspaceReplaceDocumentResult>[];
    final failures = <WorkspaceSearchFailure>[];
    var truncated = false;
    var replacementCount = 0;

    for (final documentId in _uniqueDocumentIds(documentIds)) {
      if (replacementCount >= maxReplacements) {
        truncated = true;
        break;
      }
      late final DocumentState document;
      try {
        document = await documentStore.loadDocument(documentId);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      final searchResult = _searchDocument(
        document,
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        useRegex: useRegex,
        remaining: maxReplacements - replacementCount,
      );
      final effectiveMatches = searchResult.matches
          .where((match) => match.text != replacement)
          .toList(growable: false);
      if (effectiveMatches.isEmpty) {
        if (searchResult.truncated) {
          truncated = true;
          break;
        }
        continue;
      }
      final nextDocument = DocumentState(
        documentId: document.documentId,
        text: _replaceWorkspaceMatches(
          document.text,
          effectiveMatches,
          replacement,
        ),
        revision: document.revision + 1,
      );
      try {
        await documentStore.saveDocument(nextDocument);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      replacementCount += effectiveMatches.length;
      documents.add(
        WorkspaceReplaceDocumentResult(
          documentId: document.documentId,
          replacementCount: effectiveMatches.length,
          revision: nextDocument.revision,
        ),
      );
      if (searchResult.truncated) {
        truncated = true;
        break;
      }
    }

    return WorkspaceReplaceResult(
      documents: List.unmodifiable(documents),
      failures: List.unmodifiable(failures),
      truncated: truncated,
    );
  }

  Future<WorkspaceReplacePreview> previewReplaceAll({
    required Iterable<String> documentIds,
    required String query,
    required String replacement,
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
    int maxReplacements = 1000,
  }) async {
    if (query.isEmpty || maxReplacements <= 0) {
      return const WorkspaceReplacePreview(
        documents: <WorkspaceReplacePreviewDocument>[],
      );
    }
    final documents = <WorkspaceReplacePreviewDocument>[];
    final failures = <WorkspaceSearchFailure>[];
    var truncated = false;
    var replacementCount = 0;

    for (final documentId in _uniqueDocumentIds(documentIds)) {
      if (replacementCount >= maxReplacements) {
        truncated = true;
        break;
      }
      late final DocumentState document;
      try {
        document = await documentStore.loadDocument(documentId);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      final searchResult = _searchDocument(
        document,
        query: query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        useRegex: useRegex,
        remaining: maxReplacements - replacementCount,
      );
      final effectiveMatches = searchResult.matches
          .where((match) => match.text != replacement)
          .toList(growable: false);
      if (effectiveMatches.isEmpty) {
        if (searchResult.truncated) {
          truncated = true;
          break;
        }
        continue;
      }
      replacementCount += effectiveMatches.length;
      documents.add(
        WorkspaceReplacePreviewDocument(
          documentId: document.documentId,
          beforeText: document.text,
          afterText: _replaceWorkspaceMatches(
            document.text,
            effectiveMatches,
            replacement,
          ),
          replacementCount: effectiveMatches.length,
          revision: document.revision,
        ),
      );
      if (searchResult.truncated) {
        truncated = true;
        break;
      }
    }

    return WorkspaceReplacePreview(
      documents: List.unmodifiable(documents),
      failures: List.unmodifiable(failures),
      truncated: truncated,
    );
  }

  Future<WorkspaceReplaceResult> applyReplacePreview(
    WorkspaceReplacePreview preview,
  ) async {
    final documents = <WorkspaceReplaceDocumentResult>[];
    final failures = <WorkspaceSearchFailure>[];

    for (final previewDocument in preview.documents) {
      late final DocumentState current;
      try {
        current = await documentStore.loadDocument(previewDocument.documentId);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: previewDocument.documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      if (current.revision != previewDocument.revision ||
          current.text != previewDocument.beforeText) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: previewDocument.documentId,
            message:
                'document changed since replace preview revision ${previewDocument.revision}',
          ),
        );
        continue;
      }
      final nextDocument = DocumentState(
        documentId: previewDocument.documentId,
        text: previewDocument.afterText,
        revision: current.revision + 1,
      );
      try {
        await documentStore.saveDocument(nextDocument);
      } on Object catch (error) {
        failures.add(
          WorkspaceSearchFailure(
            documentId: previewDocument.documentId,
            message: error.toString(),
          ),
        );
        continue;
      }
      documents.add(
        WorkspaceReplaceDocumentResult(
          documentId: nextDocument.documentId,
          replacementCount: previewDocument.replacementCount,
          revision: nextDocument.revision,
        ),
      );
    }

    return WorkspaceReplaceResult(
      documents: List.unmodifiable(documents),
      failures: List.unmodifiable(failures),
      truncated: preview.truncated,
    );
  }
}

List<String> _uniqueDocumentIds(Iterable<String> documentIds) {
  final seen = <String>{};
  final ordered = <String>[];
  for (final documentId in documentIds) {
    if (seen.add(documentId)) {
      ordered.add(documentId);
    }
  }
  return ordered;
}

String _replaceWorkspaceMatches(
  String source,
  List<WorkspaceSearchMatch> matches,
  String replacement,
) {
  var next = source;
  final descending = matches.toList(growable: false)
    ..sort((left, right) => right.range.start.compareTo(left.range.start));
  for (final match in descending) {
    next = next.replaceRange(match.range.start, match.range.end, replacement);
  }
  return next;
}

_WorkspaceDocumentSearchResult _searchDocument(
  DocumentState document, {
  required String query,
  required bool caseSensitive,
  required bool wholeWord,
  required bool useRegex,
  required int remaining,
}) {
  if (useRegex) {
    return _regexSearchDocument(
      document,
      pattern: query,
      caseSensitive: caseSensitive,
      wholeWord: wholeWord,
      remaining: remaining,
    );
  }
  final source = document.text;
  final haystack = caseSensitive ? source : source.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  final matches = <WorkspaceSearchMatch>[];
  var truncated = false;
  var offset = 0;
  while (offset <= haystack.length - needle.length) {
    final index = haystack.indexOf(needle, offset);
    if (index < 0) {
      break;
    }
    final end = index + needle.length;
    if (!wholeWord || _isWholeWordWorkspaceSearchMatch(source, index, end)) {
      if (matches.length >= remaining) {
        truncated = true;
        break;
      }
      matches.add(
        WorkspaceSearchMatch(
          documentId: document.documentId,
          range: SourceRange(start: index, end: end),
          text: source.substring(index, end),
          lineNumber: _lineNumberForOffset(source, index),
          lineText: _lineTextForOffset(source, index),
        ),
      );
    }
    offset = end;
  }
  return _WorkspaceDocumentSearchResult(matches: matches, truncated: truncated);
}

_WorkspaceDocumentSearchResult _regexSearchDocument(
  DocumentState document, {
  required String pattern,
  required bool caseSensitive,
  required bool wholeWord,
  required int remaining,
}) {
  late final RegExp expression;
  try {
    expression = RegExp(pattern, caseSensitive: caseSensitive);
  } on FormatException {
    return const _WorkspaceDocumentSearchResult(
      matches: <WorkspaceSearchMatch>[],
      truncated: false,
    );
  }
  final source = document.text;
  final matches = <WorkspaceSearchMatch>[];
  var truncated = false;
  for (final match in expression.allMatches(source)) {
    if (match.start == match.end) {
      continue;
    }
    if (wholeWord &&
        !_isWholeWordWorkspaceSearchMatch(source, match.start, match.end)) {
      continue;
    }
    if (matches.length >= remaining) {
      truncated = true;
      break;
    }
    matches.add(
      WorkspaceSearchMatch(
        documentId: document.documentId,
        range: SourceRange(start: match.start, end: match.end),
        text: match.group(0) ?? source.substring(match.start, match.end),
        lineNumber: _lineNumberForOffset(source, match.start),
        lineText: _lineTextForOffset(source, match.start),
      ),
    );
  }
  return _WorkspaceDocumentSearchResult(matches: matches, truncated: truncated);
}

class _WorkspaceDocumentSearchResult {
  const _WorkspaceDocumentSearchResult({
    required this.matches,
    required this.truncated,
  });

  final List<WorkspaceSearchMatch> matches;
  final bool truncated;
}

int _lineNumberForOffset(String source, int offset) {
  var line = 1;
  for (var index = 0; index < offset && index < source.length; index += 1) {
    if (source.codeUnitAt(index) == 10) {
      line += 1;
    }
  }
  return line;
}

String _lineTextForOffset(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset <= 0 ? 0 : offset - 1) + 1;
  final nextNewline = source.indexOf('\n', offset);
  final lineEnd = nextNewline < 0 ? source.length : nextNewline;
  return source.substring(lineStart, lineEnd);
}

bool _isWholeWordWorkspaceSearchMatch(String source, int start, int end) {
  final before = start <= 0 ? null : source.codeUnitAt(start - 1);
  final after = end >= source.length ? null : source.codeUnitAt(end);
  return !_isWorkspaceSearchWordCharacter(before) &&
      !_isWorkspaceSearchWordCharacter(after);
}

bool _isWorkspaceSearchWordCharacter(int? codeUnit) {
  if (codeUnit == null) {
    return false;
  }
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122) ||
      codeUnit == 95;
}

int _countWorkspaceSearchLines(String source) {
  if (source.isEmpty) {
    return 0;
  }
  var count = 1;
  for (var index = 0; index < source.length; index += 1) {
    if (source.codeUnitAt(index) == 10 && index < source.length - 1) {
      count += 1;
    }
  }
  return count;
}

String _workspaceFileLabel(String documentId) {
  final normalized = documentId.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

int? _scoreWorkspaceQuickOpenMatch(String documentId, String query) {
  final normalizedPath = documentId.replaceAll('\\', '/').toLowerCase();
  final label = _workspaceFileLabel(documentId).toLowerCase();
  if (normalizedPath == query) {
    return 1000;
  }
  if (label == query) {
    return 950;
  }
  if (normalizedPath.startsWith(query)) {
    return 900 - normalizedPath.length;
  }
  if (label.startsWith(query)) {
    return 850 - label.length;
  }
  final labelIndex = label.indexOf(query);
  if (labelIndex >= 0) {
    return 700 - labelIndex - label.length;
  }
  final pathIndex = normalizedPath.indexOf(query);
  if (pathIndex >= 0) {
    return 650 - pathIndex - normalizedPath.length;
  }
  final fuzzyPenalty = _workspaceQuickOpenFuzzyPenalty(normalizedPath, query);
  if (fuzzyPenalty == null) {
    return null;
  }
  return 400 - fuzzyPenalty;
}

int? _scoreWorkspaceSymbolMatch({
  required String name,
  required String documentId,
  required String query,
}) {
  if (query.isEmpty) {
    return 0;
  }
  final normalizedName = name.toLowerCase();
  final normalizedPath = documentId.replaceAll('\\', '/').toLowerCase();
  if (normalizedName == query) {
    return 1000;
  }
  if (normalizedName.startsWith(query)) {
    return 900 - normalizedName.length;
  }
  final nameIndex = normalizedName.indexOf(query);
  if (nameIndex >= 0) {
    return 750 - nameIndex - normalizedName.length;
  }
  final pathIndex = normalizedPath.indexOf(query);
  if (pathIndex >= 0) {
    return 500 - pathIndex - normalizedPath.length;
  }
  final fuzzyPenalty = _workspaceQuickOpenFuzzyPenalty(normalizedName, query);
  if (fuzzyPenalty == null) {
    return null;
  }
  return 350 - fuzzyPenalty;
}

int? _workspaceQuickOpenFuzzyPenalty(String path, String query) {
  var pathIndex = 0;
  var previousMatch = -1;
  var penalty = 0;
  for (var queryIndex = 0; queryIndex < query.length; queryIndex += 1) {
    final nextIndex = path.indexOf(query[queryIndex], pathIndex);
    if (nextIndex < 0) {
      return null;
    }
    if (previousMatch >= 0) {
      penalty += nextIndex - previousMatch - 1;
    } else {
      penalty += nextIndex;
    }
    previousMatch = nextIndex;
    pathIndex = nextIndex + 1;
  }
  return penalty + path.length - query.length;
}
