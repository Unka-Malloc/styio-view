import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceRenameStatus {
  ready,
  noChanges,
  emptyWorkspace,
  noTarget,
  conflict,
}

class WorkspaceRenameQuery {
  const WorkspaceRenameQuery({
    required this.targetFilePath,
    required this.targetOffset,
    required this.newName,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
  });

  final String targetFilePath;
  final int targetOffset;
  final String newName;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;

  WorkspaceRenameQuery copyWith({
    String? targetFilePath,
    int? targetOffset,
    String? newName,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
  }) {
    return WorkspaceRenameQuery(
      targetFilePath: targetFilePath ?? this.targetFilePath,
      targetOffset: targetOffset ?? this.targetOffset,
      newName: newName ?? this.newName,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
    );
  }
}

class WorkspaceRenameEdit {
  const WorkspaceRenameEdit({
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

class WorkspaceRenameResult {
  const WorkspaceRenameResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.oldName,
    required this.newName,
    required this.edits,
    this.message,
  });

  final WorkspaceRenameQuery query;
  final WorkspaceRenameStatus status;
  final int filesSearched;
  final String oldName;
  final String newName;
  final List<WorkspaceRenameEdit> edits;
  final String? message;

  bool get hasConflict => status == WorkspaceRenameStatus.conflict;

  bool get canApply =>
      status == WorkspaceRenameStatus.ready && edits.isNotEmpty;

  int get editCount => edits.length;

  int get matchedFileCount => edits.map((edit) => edit.filePath).toSet().length;
}

class WorkspaceRenameApplyResult {
  const WorkspaceRenameApplyResult({
    required this.preview,
    required this.applied,
    required this.changedDocuments,
    this.message,
  });

  final WorkspaceRenameResult preview;
  final bool applied;
  final Map<String, DocumentState> changedDocuments;
  final String? message;

  int get documentsChanged => changedDocuments.length;

  int get editsApplied => applied ? preview.editCount : 0;
}

class WorkspaceRenameService {
  const WorkspaceRenameService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceRenameResult> previewRename({
    required List<String> filePaths,
    required WorkspaceRenameQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final documents = await _loadIndexableDocuments(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    if (documents.isEmpty) {
      return WorkspaceRenameResult(
        query: query,
        status: WorkspaceRenameStatus.emptyWorkspace,
        filesSearched: 0,
        oldName: '',
        newName: query.newName,
        edits: const <WorkspaceRenameEdit>[],
        message: 'Rename Symbol requires at least one Styio workspace file.',
      );
    }

    final preview = _projectLanguageService.renamePreviewAt(
      documents: documents,
      documentId: query.targetFilePath,
      offset: query.targetOffset,
      newName: query.newName.trim(),
    );
    if (preview == null) {
      return WorkspaceRenameResult(
        query: query,
        status: WorkspaceRenameStatus.noTarget,
        filesSearched: documents.length,
        oldName: '',
        newName: query.newName,
        edits: const <WorkspaceRenameEdit>[],
        message: 'Rename Symbol needs a resolvable symbol under the caret.',
      );
    }
    if (preview.hasConflict) {
      return WorkspaceRenameResult(
        query: query,
        status: WorkspaceRenameStatus.conflict,
        filesSearched: documents.length,
        oldName: preview.oldName,
        newName: preview.newName,
        edits: const <WorkspaceRenameEdit>[],
        message: preview.conflict,
      );
    }
    if (preview.oldName == preview.newName) {
      return WorkspaceRenameResult(
        query: query,
        status: WorkspaceRenameStatus.noChanges,
        filesSearched: documents.length,
        oldName: preview.oldName,
        newName: preview.newName,
        edits: const <WorkspaceRenameEdit>[],
        message:
            '`${preview.oldName}` is already the current symbol name.',
      );
    }

    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final edits = <WorkspaceRenameEdit>[];
    for (final entry in preview.editsByDocument.entries) {
      final document = documentsById[entry.key];
      if (document == null) {
        continue;
      }
      for (final range in entry.value) {
        final position = document.positionForOffset(range.start);
        edits.add(
          WorkspaceRenameEdit(
            filePath: entry.key,
            range: range,
            line: position.line,
            column: position.column,
            previewText: _linePreview(document, position.line),
          ),
        );
      }
    }
    edits.sort(_compareEdits);

    return WorkspaceRenameResult(
      query: query,
      status: WorkspaceRenameStatus.ready,
      filesSearched: documents.length,
      oldName: preview.oldName,
      newName: preview.newName,
      edits: List<WorkspaceRenameEdit>.unmodifiable(edits),
    );
  }

  Future<WorkspaceRenameApplyResult> applyRename({
    required List<String> filePaths,
    required WorkspaceRenameQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final preview = await previewRename(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    if (!preview.canApply) {
      return WorkspaceRenameApplyResult(
        preview: preview,
        applied: false,
        changedDocuments: const <String, DocumentState>{},
        message: preview.message ?? 'Rename Symbol has no applicable edits.',
      );
    }

    final documents = await _loadIndexableDocuments(
      filePaths: filePaths,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final editsByDocument = <String, List<WorkspaceRenameEdit>>{};
    for (final edit in preview.edits) {
      final documentEdits = editsByDocument.putIfAbsent(
        edit.filePath,
        () => <WorkspaceRenameEdit>[],
      );
      documentEdits.add(edit);
    }

    final changedDocuments = <String, DocumentState>{};
    for (final entry in editsByDocument.entries) {
      final document = documentsById[entry.key];
      if (document == null) {
        continue;
      }
      var nextDocument = document;
      final descendingEdits = [...entry.value]..sort(
        (first, second) => second.range.start.compareTo(first.range.start),
      );
      for (final edit in descendingEdits) {
        nextDocument = nextDocument.replaceRange(
          start: edit.range.start,
          end: edit.range.end,
          replacement: preview.newName,
        );
      }
      await documentStore.saveDocument(nextDocument);
      changedDocuments[entry.key] = nextDocument;
    }

    return WorkspaceRenameApplyResult(
      preview: preview,
      applied: changedDocuments.isNotEmpty,
      changedDocuments: Map<String, DocumentState>.unmodifiable(
        changedDocuments,
      ),
      message: changedDocuments.isEmpty
          ? 'Rename Symbol did not change any documents.'
          : 'Renamed `${preview.oldName}` to `${preview.newName}`.',
    );
  }

  Future<List<DocumentState>> _loadIndexableDocuments({
    required List<String> filePaths,
    required WorkspaceRenameQuery query,
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

  static bool _isIndexable(String filePath, WorkspaceRenameQuery query) {
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

  static String _displayPath(String filePath) {
    return filePath.replaceAll('\\', '/');
  }

  static int _compareEdits(
    WorkspaceRenameEdit first,
    WorkspaceRenameEdit second,
  ) {
    final fileCompare = first.filePath.compareTo(second.filePath);
    if (fileCompare != 0) {
      return fileCompare;
    }
    return first.range.start.compareTo(second.range.start);
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
