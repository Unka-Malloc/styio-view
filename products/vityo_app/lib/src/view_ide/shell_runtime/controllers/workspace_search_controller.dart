import '../../../ide/editor/editor.dart';
import '../../../ide/workspace/workspace.dart';
import '../../language/service/service.dart';

/// Owns the shared document scan used for workspace text and symbol search.
final class WorkspaceSearchController {
  WorkspaceSearchController({
    required this.workspaceController,
    required this.documentStore,
    required this.languageService,
    required this.documentSamples,
    required this.log,
  });

  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService languageService;
  final List<DocumentState> Function() documentSamples;
  final void Function(String message) log;

  WorkspaceSearchResult? _lastTextSearch;
  WorkspaceSymbolSearchResult? _lastSymbolSearch;
  String? _lastQuery;
  int _lastScannedDocumentCount = 0;

  WorkspaceSearchResult? get lastTextSearch => _lastTextSearch;
  WorkspaceSymbolSearchResult? get lastSymbolSearch => _lastSymbolSearch;
  String? get lastQuery => _lastQuery;
  int get lastScannedDocumentCount => _lastScannedDocumentCount;

  Future<bool> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      log('Workspace search skipped: missing input.');
      return false;
    }
    final documents = <DocumentState>[];
    final seen = <String>{};
    for (final document in documentSamples()) {
      if (seen.add(document.documentId)) {
        documents.add(document);
      }
    }
    for (final filePath in workspaceController.files) {
      if (documents.length >= 100) {
        break;
      }
      if (!seen.add(filePath)) {
        continue;
      }
      try {
        documents.add(await documentStore.loadDocument(filePath));
      } on Object catch (error) {
        log('Workspace search skipped $filePath: $error');
      }
    }
    final index = WorkspaceSearchIndex(
      documents: <WorkspaceSearchIndexDocument>[
        for (final document in documents)
          WorkspaceSearchIndexDocument.fromDocument(document),
      ],
      createdAt: DateTime.now().toUtc(),
    );
    final textSearch = index.search(query: normalizedQuery, maxMatches: 50);
    final symbolResult =
        await WorkspaceSymbolSearchService(
          documentStore: InMemoryWorkspaceDocumentStore(
            seededDocuments: <String, DocumentState>{
              for (final document in documents) document.documentId: document,
            },
          ),
          semanticSnapshotProvider: SemanticSnapshotProvider(
            languageService: languageService.documentService,
          ),
        ).searchSymbols(
          documentIds: documents.map((document) => document.documentId),
          query: normalizedQuery,
        );
    _lastQuery = normalizedQuery;
    _lastScannedDocumentCount = documents.length;
    _lastTextSearch = textSearch;
    _lastSymbolSearch = symbolResult;
    log(
      'Workspace search found '
      '${textSearch.matches.length} text match(es) and '
      '${symbolResult.matches.length} symbol match(es) for "$normalizedQuery".',
    );
    return true;
  }
}
