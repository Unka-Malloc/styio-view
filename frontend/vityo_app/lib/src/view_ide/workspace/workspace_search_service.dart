import '../editor/document_state.dart';
import '../language/contract/language_contract.dart';
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

class WorkspaceSearchService {
  const WorkspaceSearchService({required this.documentStore});

  final WorkspaceDocumentStore documentStore;

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
    for (var documentIndex = 0;
        documentIndex < orderedDocumentIds.length;
        documentIndex += 1) {
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
  return _WorkspaceDocumentSearchResult(
    matches: matches,
    truncated: truncated,
  );
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
  return _WorkspaceDocumentSearchResult(
    matches: matches,
    truncated: truncated,
  );
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
