import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceCodeActionsStatus {
  completed,
  emptyWorkspace,
  noActions,
  hitLimit,
}

class WorkspaceCodeActionsQuery {
  const WorkspaceCodeActionsQuery({
    this.pattern = '',
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 50,
  });

  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceCodeActionsQuery copyWith({
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceCodeActionsQuery(
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceCodeActionDocumentPreview {
  const WorkspaceCodeActionDocumentPreview({
    required this.filePath,
    required this.editCount,
    required this.firstEditRange,
    required this.line,
    required this.column,
    required this.previewText,
  });

  final String filePath;
  final int editCount;
  final SourceRange firstEditRange;
  final int line;
  final int column;
  final String previewText;
}

class WorkspaceCodeActionItem {
  const WorkspaceCodeActionItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.documents,
  });

  final String id;
  final String label;
  final String detail;
  final List<WorkspaceCodeActionDocumentPreview> documents;

  int get editCount => documents.fold(
    0,
    (count, document) => count + document.editCount,
  );

  int get changedFileCount => documents.length;

  List<String> get filePaths =>
      List<String>.unmodifiable(documents.map((document) => document.filePath));
}

class WorkspaceCodeActionsResult {
  const WorkspaceCodeActionsResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.diagnosticsScanned,
    required this.actions,
    this.message,
  });

  final WorkspaceCodeActionsQuery query;
  final WorkspaceCodeActionsStatus status;
  final int filesSearched;
  final int diagnosticsScanned;
  final List<WorkspaceCodeActionItem> actions;
  final String? message;

  bool get hitLimit => status == WorkspaceCodeActionsStatus.hitLimit;

  int get actionCount => actions.length;

  int get editCount => actions.fold(
    0,
    (count, action) => count + action.editCount,
  );

  int get matchedFileCount => actions
      .expand((action) => action.documents.map((document) => document.filePath))
      .toSet()
      .length;
}

class WorkspaceCodeActionApplyResult {
  const WorkspaceCodeActionApplyResult({
    required this.preview,
    required this.actionId,
    required this.applied,
    required this.changedDocuments,
    this.action,
    this.message,
  });

  final WorkspaceCodeActionsResult preview;
  final String actionId;
  final WorkspaceCodeActionItem? action;
  final bool applied;
  final Map<String, DocumentState> changedDocuments;
  final String? message;

  int get documentsChanged => changedDocuments.length;

  int get editsApplied => applied ? action?.editCount ?? 0 : 0;
}

class WorkspaceCodeActionsService {
  const WorkspaceCodeActionsService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceCodeActionsResult> collectCodeActions({
    required List<String> filePaths,
    required WorkspaceCodeActionsQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final preview = await _collectCodeActionPreview(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    return preview.result;
  }

  Future<WorkspaceCodeActionApplyResult> applyCodeAction({
    required List<String> filePaths,
    required WorkspaceCodeActionsQuery query,
    required String actionId,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final preview = await _collectCodeActionPreview(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _WorkspaceCodeActionCandidate? candidate;
    for (final current in preview.candidates) {
      if (current.item.id == actionId) {
        candidate = current;
        break;
      }
    }
    if (candidate == null) {
      return WorkspaceCodeActionApplyResult(
        preview: preview.result,
        actionId: actionId,
        applied: false,
        changedDocuments: const <String, DocumentState>{},
        message: 'Workspace Code Action `$actionId` is no longer available.',
      );
    }

    final documentsById = {
      for (final document in preview.documents) document.documentId: document,
    };
    final changedDocuments = <String, DocumentState>{};
    for (final document in candidate.fix.apply(preview.documents)) {
      final before = documentsById[document.documentId];
      if (before == null || before.text == document.text) {
        continue;
      }
      await documentStore.saveDocument(document);
      changedDocuments[document.documentId] = document;
    }

    return WorkspaceCodeActionApplyResult(
      preview: preview.result,
      actionId: actionId,
      action: candidate.item,
      applied: changedDocuments.isNotEmpty,
      changedDocuments: Map<String, DocumentState>.unmodifiable(
        changedDocuments,
      ),
      message: changedDocuments.isEmpty
          ? 'Workspace Code Action did not change any documents.'
          : 'Applied `${candidate.item.label}`.',
    );
  }

  Future<_WorkspaceCodeActionsPreview> _collectCodeActionPreview({
    required List<String> filePaths,
    required WorkspaceCodeActionsQuery query,
    required Map<String, DocumentState> overlayDocuments,
  }) async {
    final documents = await _loadIndexableDocuments(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    if (documents.isEmpty) {
      return _WorkspaceCodeActionsPreview(
        documents: const <DocumentState>[],
        candidates: const <_WorkspaceCodeActionCandidate>[],
        result: WorkspaceCodeActionsResult(
          query: query,
          status: WorkspaceCodeActionsStatus.emptyWorkspace,
          filesSearched: 0,
          diagnosticsScanned: 0,
          actions: const <WorkspaceCodeActionItem>[],
          message:
              'Code Actions requires at least one Styio workspace file.',
        ),
      );
    }

    final analysis = _projectLanguageService.analyzeProject(documents);
    final fixes = _projectLanguageService
        .workspaceQuickFixesForProjectDiagnostics(
      documents: documents,
      diagnostics: analysis.diagnostics,
      analysis: analysis,
    );
    final allCandidates = _buildCandidates(
      documents: documents,
      fixes: fixes,
    );
    final normalizedPattern = _normalizedPattern(query.pattern);
    final filteredCandidates = allCandidates
        .where((candidate) => _matchesPattern(candidate.item, normalizedPattern))
        .toList(growable: false);
    final maxResults = query.maxResults <= 0 ? 50 : query.maxResults;
    final limitedCandidates = filteredCandidates
        .take(maxResults)
        .toList(growable: false);
    final status = allCandidates.isEmpty || filteredCandidates.isEmpty
        ? WorkspaceCodeActionsStatus.noActions
        : filteredCandidates.length > maxResults
        ? WorkspaceCodeActionsStatus.hitLimit
        : WorkspaceCodeActionsStatus.completed;

    return _WorkspaceCodeActionsPreview(
      documents: documents,
      candidates: List<_WorkspaceCodeActionCandidate>.unmodifiable(
        limitedCandidates,
      ),
      result: WorkspaceCodeActionsResult(
        query: query,
        status: status,
        filesSearched: documents.length,
        diagnosticsScanned: analysis.diagnostics.length,
        actions: List<WorkspaceCodeActionItem>.unmodifiable(
          limitedCandidates.map((candidate) => candidate.item),
        ),
        message: _resultMessage(
          status: status,
          query: query,
          maxResults: maxResults,
        ),
      ),
    );
  }

  Future<List<DocumentState>> _loadIndexableDocuments({
    required List<String> filePaths,
    required WorkspaceCodeActionsQuery query,
    required Map<String, DocumentState> overlayDocuments,
  }) async {
    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    final documents = <DocumentState>[];
    for (final filePath in uniqueFilePaths) {
      documents.add(
        overlayDocuments[filePath] ?? await documentStore.loadDocument(filePath),
      );
    }
    return documents;
  }

  static List<_WorkspaceCodeActionCandidate> _buildCandidates({
    required List<DocumentState> documents,
    required List<StyioProjectWorkspaceFix> fixes,
  }) {
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final idCounts = <String, int>{};
    final candidates = <_WorkspaceCodeActionCandidate>[];
    for (final fix in fixes) {
      final preview = fix.preview(documents);
      if (!preview.hasChanges) {
        continue;
      }
      final id = _nextActionId(preview.label, idCounts);
      final documentPreviews = <WorkspaceCodeActionDocumentPreview>[];
      for (final documentPreview in preview.documents) {
        if (!documentPreview.changed || documentPreview.edits.isEmpty) {
          continue;
        }
        final document = documentsById[documentPreview.documentId];
        if (document == null) {
          continue;
        }
        final firstEdit = [...documentPreview.edits]..sort(
          (first, second) => first.range.start.compareTo(second.range.start),
        );
        final range = firstEdit.first.range;
        final position = document.positionForOffset(range.start);
        documentPreviews.add(
          WorkspaceCodeActionDocumentPreview(
            filePath: documentPreview.documentId,
            editCount: documentPreview.edits.length,
            firstEditRange: range,
            line: position.line,
            column: position.column,
            previewText: _linePreview(document, position.line),
          ),
        );
      }
      if (documentPreviews.isEmpty) {
        continue;
      }
      documentPreviews.sort(_compareDocumentPreviews);
      candidates.add(
        _WorkspaceCodeActionCandidate(
          fix: fix,
          item: WorkspaceCodeActionItem(
            id: id,
            label: preview.label,
            detail: preview.detail,
            documents: List<WorkspaceCodeActionDocumentPreview>.unmodifiable(
              documentPreviews,
            ),
          ),
        ),
      );
    }
    candidates.sort(_compareCandidates);
    return List<_WorkspaceCodeActionCandidate>.unmodifiable(candidates);
  }

  static String? _resultMessage({
    required WorkspaceCodeActionsStatus status,
    required WorkspaceCodeActionsQuery query,
    required int maxResults,
  }) {
    return switch (status) {
      WorkspaceCodeActionsStatus.completed => null,
      WorkspaceCodeActionsStatus.emptyWorkspace =>
        'Code Actions requires at least one Styio workspace file.',
      WorkspaceCodeActionsStatus.noActions =>
        query.pattern.trim().isEmpty
            ? 'No workspace code actions.'
            : 'No workspace code actions match `${query.pattern.trim()}`.',
      WorkspaceCodeActionsStatus.hitLimit =>
        'Code Actions stopped after $maxResults action(s).',
    };
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
    WorkspaceCodeActionsQuery query,
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

  static bool _matchesPattern(
    WorkspaceCodeActionItem item,
    String normalizedPattern,
  ) {
    if (normalizedPattern.isEmpty) {
      return true;
    }
    return item.id.contains(normalizedPattern) ||
        item.label.toLowerCase().contains(normalizedPattern) ||
        item.detail.toLowerCase().contains(normalizedPattern) ||
        item.documents.any(
          (document) =>
              _displayPath(document.filePath).toLowerCase().contains(
                normalizedPattern,
              ) ||
              document.previewText.toLowerCase().contains(normalizedPattern),
        );
  }

  static String _nextActionId(String label, Map<String, int> idCounts) {
    final base = _slug(label);
    final count = idCounts.update(base, (value) => value + 1, ifAbsent: () => 1);
    return count == 1 ? base : '$base-$count';
  }

  static String _slug(String label) {
    final normalized = label.toLowerCase();
    final buffer = StringBuffer();
    var pendingDash = false;
    for (var index = 0; index < normalized.length; index += 1) {
      final code = normalized.codeUnitAt(index);
      final isAlphaNumeric =
          (code >= 0x30 && code <= 0x39) || (code >= 0x61 && code <= 0x7a);
      if (isAlphaNumeric) {
        if (pendingDash && buffer.length > 0) {
          buffer.write('-');
        }
        buffer.writeCharCode(code);
        pendingDash = false;
      } else {
        pendingDash = true;
      }
    }
    return buffer.length == 0 ? 'workspace-code-action' : buffer.toString();
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

  static int _compareCandidates(
    _WorkspaceCodeActionCandidate first,
    _WorkspaceCodeActionCandidate second,
  ) {
    final fileCompare = first.item.documents.first.filePath.compareTo(
      second.item.documents.first.filePath,
    );
    if (fileCompare != 0) {
      return fileCompare;
    }
    final editCompare = second.item.editCount.compareTo(first.item.editCount);
    if (editCompare != 0) {
      return editCompare;
    }
    return first.item.label.compareTo(second.item.label);
  }

  static int _compareDocumentPreviews(
    WorkspaceCodeActionDocumentPreview first,
    WorkspaceCodeActionDocumentPreview second,
  ) {
    final fileCompare = first.filePath.compareTo(second.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    return first.firstEditRange.start.compareTo(second.firstEditRange.start);
  }
}

class _WorkspaceCodeActionsPreview {
  const _WorkspaceCodeActionsPreview({
    required this.documents,
    required this.candidates,
    required this.result,
  });

  final List<DocumentState> documents;
  final List<_WorkspaceCodeActionCandidate> candidates;
  final WorkspaceCodeActionsResult result;
}

class _WorkspaceCodeActionCandidate {
  const _WorkspaceCodeActionCandidate({
    required this.fix,
    required this.item,
  });

  final StyioProjectWorkspaceFix fix;
  final WorkspaceCodeActionItem item;
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
