import '../editor/document/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceCodeLensStatus {
  completed,
  emptyWorkspace,
  noLenses,
  hitLimit,
}

enum WorkspaceCodeLensKind { references }

class WorkspaceCodeLensQuery {
  const WorkspaceCodeLensQuery({
    required this.targetFilePath,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String targetFilePath;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceCodeLensQuery copyWith({
    String? targetFilePath,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceCodeLensQuery(
      targetFilePath: targetFilePath ?? this.targetFilePath,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceCodeLensItem {
  const WorkspaceCodeLensItem({
    required this.filePath,
    required this.symbolName,
    required this.symbolKind,
    required this.kind,
    required this.commandTitle,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    required this.referenceCount,
    required this.usageCount,
    this.type,
  });

  final String filePath;
  final String symbolName;
  final StyioProjectSymbolKind symbolKind;
  final WorkspaceCodeLensKind kind;
  final String commandTitle;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final int referenceCount;
  final int usageCount;
  final String? type;

  String get kindLabel {
    return switch (kind) {
      WorkspaceCodeLensKind.references => 'references',
    };
  }

  String get symbolKindLabel {
    return switch (symbolKind) {
      StyioProjectSymbolKind.function => 'function',
      StyioProjectSymbolKind.resource => 'resource',
      StyioProjectSymbolKind.task => 'task',
    };
  }
}

class WorkspaceCodeLensResult {
  const WorkspaceCodeLensResult({
    required this.query,
    required this.status,
    required this.filePath,
    required this.filesSearched,
    required this.symbolsIndexed,
    required this.lenses,
    this.message,
  });

  final WorkspaceCodeLensQuery query;
  final WorkspaceCodeLensStatus status;
  final String filePath;
  final int filesSearched;
  final int symbolsIndexed;
  final List<WorkspaceCodeLensItem> lenses;
  final String? message;

  bool get hitLimit => status == WorkspaceCodeLensStatus.hitLimit;

  int get lensCount => lenses.length;

  int get referencedSymbolCount =>
      lenses.where((lens) => lens.usageCount > 0).length;
}

class WorkspaceCodeLensService {
  const WorkspaceCodeLensService({
    required this.documentStore,
    ProjectStyioLanguageService projectLanguageService =
        const ProjectStyioLanguageService(),
  }) : _projectLanguageService = projectLanguageService;

  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService _projectLanguageService;

  Future<WorkspaceCodeLensResult> collectCodeLenses({
    required List<String> filePaths,
    required WorkspaceCodeLensQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final targetFilePath = query.targetFilePath;
    final uniqueFilePaths = _uniqueFilePaths(filePaths)
        .where((filePath) => _isIndexable(filePath, query))
        .toList(growable: false);
    if (!uniqueFilePaths.contains(targetFilePath)) {
      return WorkspaceCodeLensResult(
        query: query,
        status: WorkspaceCodeLensStatus.emptyWorkspace,
        filePath: targetFilePath,
        filesSearched: 0,
        symbolsIndexed: 0,
        lenses: const <WorkspaceCodeLensItem>[],
        message: 'Code Lens requires an active Styio workspace file.',
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
    final targetDocument = documentsById[targetFilePath];
    if (targetDocument == null) {
      return WorkspaceCodeLensResult(
        query: query,
        status: WorkspaceCodeLensStatus.emptyWorkspace,
        filePath: targetFilePath,
        filesSearched: documents.length,
        symbolsIndexed: 0,
        lenses: const <WorkspaceCodeLensItem>[],
        message: 'Code Lens requires an active Styio workspace file.',
      );
    }

    final analysis = _projectLanguageService.analyzeProject(documents);
    final definitions = _definitionsForDocument(
      analysis.symbolSnapshot,
      targetFilePath,
    );
    if (definitions.isEmpty) {
      return WorkspaceCodeLensResult(
        query: query,
        status: WorkspaceCodeLensStatus.noLenses,
        filePath: targetFilePath,
        filesSearched: documents.length,
        symbolsIndexed: 0,
        lenses: const <WorkspaceCodeLensItem>[],
        message: 'No code lenses found in $targetFilePath.',
      );
    }

    final maxResults = query.maxResults <= 0 ? 100 : query.maxResults;
    final lenses = <WorkspaceCodeLensItem>[];
    for (final definition in definitions) {
      final references = analysis.symbolSnapshot.referencesFor(definition);
      final usageCount = references
          .where((reference) => !reference.isDefinition)
          .length;
      final position = targetDocument.positionForOffset(
        definition.range.start,
      );
      lenses.add(
        WorkspaceCodeLensItem(
          filePath: targetFilePath,
          symbolName: definition.name,
          symbolKind: definition.kind,
          kind: WorkspaceCodeLensKind.references,
          commandTitle: _referenceCommandTitle(usageCount),
          range: definition.range,
          line: position.line,
          column: position.column,
          previewText: _linePreview(targetDocument, position.line),
          referenceCount: references.length,
          usageCount: usageCount,
          type: definition.type,
        ),
      );
    }

    lenses.sort(_compareCodeLensItems);
    final limitedLenses = lenses.take(maxResults).toList(growable: false);
    return WorkspaceCodeLensResult(
      query: query,
      status: lenses.length > maxResults
          ? WorkspaceCodeLensStatus.hitLimit
          : WorkspaceCodeLensStatus.completed,
      filePath: targetFilePath,
      filesSearched: documents.length,
      symbolsIndexed: definitions.length,
      lenses: List<WorkspaceCodeLensItem>.unmodifiable(limitedLenses),
      message: lenses.length > maxResults
          ? 'Code Lens stopped after $maxResults lens(es).'
          : null,
    );
  }

  static List<StyioProjectSymbolDefinition> _definitionsForDocument(
    StyioProjectSymbolSnapshot snapshot,
    String documentId,
  ) {
    return <StyioProjectSymbolDefinition>[
      for (final function in snapshot.functionsFor(documentId))
        StyioProjectSymbolDefinition(
          documentId: documentId,
          kind: StyioProjectSymbolKind.function,
          name: function.name,
          range: function.range,
          type: function.returnType,
        ),
      for (final resource in snapshot.resourcesFor(documentId))
        StyioProjectSymbolDefinition(
          documentId: documentId,
          kind: StyioProjectSymbolKind.resource,
          name: resource.name,
          range: resource.range,
          type: resource.type,
        ),
      for (final task in snapshot.tasksFor(documentId))
        StyioProjectSymbolDefinition(
          documentId: documentId,
          kind: StyioProjectSymbolKind.task,
          name: task.name,
          range: task.range,
          type: task.returnType,
        ),
    ];
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

  static bool _isIndexable(String filePath, WorkspaceCodeLensQuery query) {
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

  static String _referenceCommandTitle(int usageCount) {
    if (usageCount == 0) {
      return 'No usages';
    }
    return '$usageCount ${usageCount == 1 ? 'usage' : 'usages'}';
  }

  static int _compareCodeLensItems(
    WorkspaceCodeLensItem first,
    WorkspaceCodeLensItem second,
  ) {
    final lineCompare = first.line.compareTo(second.line);
    if (lineCompare != 0) {
      return lineCompare;
    }
    final columnCompare = first.column.compareTo(second.column);
    if (columnCompare != 0) {
      return columnCompare;
    }
    return first.symbolName.compareTo(second.symbolName);
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
