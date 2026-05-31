import '../editor/document_state.dart';
import '../language/language.dart';
import 'workspace_document_store_types.dart';
import 'workspace_type_definition.dart';
import 'workspace_type_hierarchy.dart';

enum WorkspaceImplementationStatus {
  completed,
  emptyPattern,
  emptyWorkspace,
  noTypes,
  noImplementations,
  hitLimit,
}

class WorkspaceImplementationQuery {
  const WorkspaceImplementationQuery({
    required this.pattern,
    this.includeGlobs = const <String>['**/*.styio'],
    this.excludeGlobs = const <String>[],
    this.maxResults = 100,
  });

  final String pattern;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final int maxResults;

  WorkspaceImplementationQuery copyWith({
    String? pattern,
    List<String>? includeGlobs,
    List<String>? excludeGlobs,
    int? maxResults,
  }) {
    return WorkspaceImplementationQuery(
      pattern: pattern ?? this.pattern,
      includeGlobs: includeGlobs ?? this.includeGlobs,
      excludeGlobs: excludeGlobs ?? this.excludeGlobs,
      maxResults: maxResults ?? this.maxResults,
    );
  }
}

class WorkspaceImplementationItem {
  const WorkspaceImplementationItem({
    required this.filePath,
    required this.name,
    required this.kind,
    required this.range,
    required this.line,
    required this.column,
    required this.previewText,
    required this.references,
  });

  final String filePath;
  final String name;
  final WorkspaceTypeDefinitionKind kind;
  final SourceRange range;
  final int line;
  final int column;
  final String previewText;
  final List<WorkspaceTypeHierarchyLocation> references;

  String get kindLabel {
    return switch (kind) {
      WorkspaceTypeDefinitionKind.schema => 'schema',
      WorkspaceTypeDefinitionKind.state => 'state',
    };
  }

  int get referenceCount => references.length;

  WorkspaceTypeHierarchyLocation get firstReference => references.first;
}

class WorkspaceImplementationResult {
  const WorkspaceImplementationResult({
    required this.query,
    required this.status,
    required this.filesSearched,
    required this.typesIndexed,
    required this.target,
    required this.implementations,
    this.message,
  });

  final WorkspaceImplementationQuery query;
  final WorkspaceImplementationStatus status;
  final int filesSearched;
  final int typesIndexed;
  final WorkspaceTypeHierarchySymbol? target;
  final List<WorkspaceImplementationItem> implementations;
  final String? message;

  bool get hitLimit => status == WorkspaceImplementationStatus.hitLimit;

  int get implementationCount => implementations.length;

  int get referenceCount => implementations.fold<int>(
    0,
    (count, implementation) => count + implementation.referenceCount,
  );

  int get matchedFileCount =>
      implementations.map((item) => item.filePath).toSet().length;
}

class WorkspaceImplementationService {
  const WorkspaceImplementationService({
    required this.documentStore,
    StyioSyntaxHighlighter syntaxHighlighter =
        const StyioSyntaxHighlighter(),
  }) : _syntaxHighlighter = syntaxHighlighter;

  final WorkspaceDocumentStore documentStore;
  final StyioSyntaxHighlighter _syntaxHighlighter;

  Future<WorkspaceImplementationResult> findImplementations({
    required List<String> filePaths,
    required WorkspaceImplementationQuery query,
    Map<String, DocumentState> overlayDocuments =
        const <String, DocumentState>{},
  }) async {
    final hierarchyService = WorkspaceTypeHierarchyService(
      documentStore: documentStore,
      syntaxHighlighter: _syntaxHighlighter,
    );
    final hierarchy = await hierarchyService.buildHierarchy(
      filePaths: filePaths,
      query: WorkspaceTypeHierarchyQuery(
        pattern: query.pattern,
        direction: WorkspaceTypeHierarchyDirection.subtypes,
        includeGlobs: query.includeGlobs,
        excludeGlobs: query.excludeGlobs,
        maxResults: query.maxResults,
      ),
      overlayDocuments: overlayDocuments,
    );
    final implementations = [
      for (final relation in hierarchy.relations)
        WorkspaceImplementationItem(
          filePath: relation.symbol.filePath,
          name: relation.symbol.name,
          kind: relation.symbol.kind,
          range: relation.symbol.range,
          line: relation.symbol.line,
          column: relation.symbol.column,
          previewText: relation.symbol.previewText,
          references: List<WorkspaceTypeHierarchyLocation>.unmodifiable(
            relation.locations,
          ),
        ),
    ];

    return WorkspaceImplementationResult(
      query: query,
      status: _statusForHierarchy(hierarchy),
      filesSearched: hierarchy.filesSearched,
      typesIndexed: hierarchy.typesIndexed,
      target: hierarchy.target,
      implementations: List<WorkspaceImplementationItem>.unmodifiable(
        implementations,
      ),
      message: _messageForHierarchy(hierarchy),
    );
  }

  static WorkspaceImplementationStatus _statusForHierarchy(
    WorkspaceTypeHierarchyResult hierarchy,
  ) {
    return switch (hierarchy.status) {
      WorkspaceTypeHierarchyStatus.completed =>
        WorkspaceImplementationStatus.completed,
      WorkspaceTypeHierarchyStatus.emptyPattern =>
        WorkspaceImplementationStatus.emptyPattern,
      WorkspaceTypeHierarchyStatus.emptyWorkspace =>
        WorkspaceImplementationStatus.emptyWorkspace,
      WorkspaceTypeHierarchyStatus.noTypes =>
        WorkspaceImplementationStatus.noTypes,
      WorkspaceTypeHierarchyStatus.noRelations =>
        WorkspaceImplementationStatus.noImplementations,
      WorkspaceTypeHierarchyStatus.hitLimit =>
        WorkspaceImplementationStatus.hitLimit,
    };
  }

  static String? _messageForHierarchy(WorkspaceTypeHierarchyResult hierarchy) {
    return switch (hierarchy.status) {
      WorkspaceTypeHierarchyStatus.emptyPattern =>
        'Go to Implementation requires a type name.',
      WorkspaceTypeHierarchyStatus.noTypes => hierarchy.message,
      WorkspaceTypeHierarchyStatus.noRelations =>
        hierarchy.target == null
            ? hierarchy.message
            : 'No implementations found for ${hierarchy.target!.name}.',
      WorkspaceTypeHierarchyStatus.hitLimit =>
        hierarchy.message ??
            'Go to Implementation stopped after '
                '${hierarchy.query.maxResults} reference(s).',
      WorkspaceTypeHierarchyStatus.completed ||
      WorkspaceTypeHierarchyStatus.emptyWorkspace => null,
    };
  }
}
