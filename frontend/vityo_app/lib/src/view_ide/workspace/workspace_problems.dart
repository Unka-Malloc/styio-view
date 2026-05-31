import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceProblemsStatus { completed, emptyWorkspace, hitLimit }

class WorkspaceProblemsQuery {
  const WorkspaceProblemsQuery({
    this.pattern = '',
    this.severities = const <DiagnosticSeverity>{
      DiagnosticSeverity.error,
      DiagnosticSeverity.warning,
      DiagnosticSeverity.hint,
    },
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 200,
  });

  final String pattern;
  final Set<DiagnosticSeverity> severities;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceProblemsQuery copyWith({
    String? pattern,
    Set<DiagnosticSeverity>? severities,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceProblemsQuery(
      pattern: pattern ?? this.pattern,
      severities: severities ?? this.severities,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceProblemItem {
  const WorkspaceProblemItem({
    required this.filePath,
    required this.diagnostic,
    required this.line,
    required this.column,
    required this.previewText,
  });

  final String filePath;
  final Diagnostic diagnostic;
  final int line;
  final int column;
  final String previewText;

  DiagnosticSeverity get severity => diagnostic.severity;

  SourceRange get range => diagnostic.range;
}

class WorkspaceProblemsResult {
  const WorkspaceProblemsResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.diagnosticsScanned,
    required this.problems,
    this.message,
  });

  final WorkspaceProblemsQuery query;
  final WorkspaceProblemsStatus status;
  final int filesSearched;
  final int diagnosticsScanned;
  final List<WorkspaceProblemItem> problems;
  final String? message;

  bool get hitLimit => status == WorkspaceProblemsStatus.hitLimit;

  int get problemCount => problems.length;

  int get matchedFileCount =>
      problems.map((problem) => problem.filePath).toSet().length;

  int get errorCount => _countSeverity(DiagnosticSeverity.error);

  int get warningCount => _countSeverity(DiagnosticSeverity.warning);

  int get hintCount => _countSeverity(DiagnosticSeverity.hint);

  int _countSeverity(DiagnosticSeverity severity) {
    return problems
        .where((problem) => problem.diagnostic.severity == severity)
        .length;
  }
}

class WorkspaceProblemsService {
  const WorkspaceProblemsService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceProblemsResult> collectProblems({
    required List<String> filePaths,
    required WorkspaceProblemsQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (uniqueFilePaths.isEmpty) {
      return WorkspaceProblemsResult(
        query: query,
        status: WorkspaceProblemsStatus.emptyWorkspace,
        filesSearched: 0,
        diagnosticsScanned: 0,
        problems: const <WorkspaceProblemItem>[],
      );
    }

    final documents = <DocumentState>[];
    for (final filePath in uniqueFilePaths) {
      documents.add(
        overlayDocuments[filePath] ?? await documentStore.loadDocument(filePath),
      );
    }
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final analysis = _projectLanguageService.analyzeProject(documents);
    final maxResults = query.maxResults <= 0 ? 200 : query.maxResults;
    final normalizedPattern = _normalizedPattern(query.pattern);
    final problems = <WorkspaceProblemItem>[];
    var diagnosticsScanned = 0;

    for (final projectDiagnostic in analysis.diagnostics) {
      diagnosticsScanned += 1;
      final diagnostic = projectDiagnostic.diagnostic;
      if (!query.severities.contains(diagnostic.severity)) {
        continue;
      }
      if (!_matchesPattern(
        projectDiagnostic.documentId,
        diagnostic,
        normalizedPattern,
      )) {
        continue;
      }
      final document = documentsById[projectDiagnostic.documentId];
      if (document == null) {
        continue;
      }
      final position = document.positionForOffset(diagnostic.range.start);
      problems.add(
        WorkspaceProblemItem(
          filePath: projectDiagnostic.documentId,
          diagnostic: diagnostic,
          line: position.line,
          column: position.column,
          previewText: _linePreview(document, position.line),
        ),
      );
      if (problems.length >= maxResults) {
        problems.sort(_compareProblemItems);
        return WorkspaceProblemsResult(
          query: query,
          status: WorkspaceProblemsStatus.hitLimit,
          filesSearched: documents.length,
          diagnosticsScanned: diagnosticsScanned,
          problems: List<WorkspaceProblemItem>.unmodifiable(problems),
          message: 'Problems stopped after $maxResults diagnostic(s).',
        );
      }
    }

    problems.sort(_compareProblemItems);
    return WorkspaceProblemsResult(
      query: query,
      status: WorkspaceProblemsStatus.completed,
      filesSearched: documents.length,
      diagnosticsScanned: diagnosticsScanned,
      problems: List<WorkspaceProblemItem>.unmodifiable(problems),
      message: problems.isEmpty ? 'No workspace problems.' : null,
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

  static bool _isIndexable(
    String filePath,
    WorkspaceProblemsQuery query,
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
    String filePath,
    Diagnostic diagnostic,
    String normalizedPattern,
  ) {
    if (normalizedPattern.isEmpty) {
      return true;
    }
    return _displayPath(filePath).toLowerCase().contains(normalizedPattern) ||
        diagnostic.code.toLowerCase().contains(normalizedPattern) ||
        diagnostic.message.toLowerCase().contains(normalizedPattern) ||
        diagnostic.severity.name.contains(normalizedPattern);
  }

  static int _compareProblemItems(
    WorkspaceProblemItem first,
    WorkspaceProblemItem second,
  ) {
    final severityCompare = _severityRank(
      first.severity,
    ).compareTo(_severityRank(second.severity));
    if (severityCompare != 0) {
      return severityCompare;
    }
    final fileCompare = first.filePath.compareTo(second.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    final lineCompare = first.line.compareTo(second.line);
    if (lineCompare != 0) {
      return lineCompare;
    }
    final columnCompare = first.column.compareTo(second.column);
    if (columnCompare != 0) {
      return columnCompare;
    }
    return first.diagnostic.code.compareTo(second.diagnostic.code);
  }

  static int _severityRank(DiagnosticSeverity severity) {
    return switch (severity) {
      DiagnosticSeverity.error => 0,
      DiagnosticSeverity.warning => 1,
      DiagnosticSeverity.hint => 2,
    };
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
