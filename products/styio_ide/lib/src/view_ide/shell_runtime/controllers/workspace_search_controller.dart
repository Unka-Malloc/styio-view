import '../../agent_client/agent.dart';
import '../../../ide/editor/editor.dart';
import '../../language/service/service.dart';
import '../../../ide/workspace/workspace.dart';

/// Owns the shared document scan used for workspace text and symbol search.
final class WorkspaceSearchController {
  WorkspaceSearchController({
    required this.workspaceController,
    required this.documentStore,
    required this.languageService,
    required this.documentSamples,
    required this.publishResults,
    required this.log,
  });

  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore documentStore;
  final ProjectStyioLanguageService languageService;
  final List<DocumentState> Function() documentSamples;
  final void Function(
    AgentWorkspaceSearchResultContext text,
    AgentWorkspaceSymbolSearchResultContext symbols,
  )
  publishResults;
  final void Function(String message) log;

  Future<bool> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      log('Agent command searchWorkspace skipped: missing input.');
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
        log('Agent command searchWorkspace skipped $filePath: $error');
      }
    }
    final textSearch = AgentWorkspaceSearchResultContext.fromDocuments(
      query: normalizedQuery,
      documents: documents,
    );
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
    final symbolSearch =
        AgentWorkspaceSymbolSearchResultContext.fromWorkspaceResult(
          query: normalizedQuery,
          scannedDocumentCount: documents.length,
          result: symbolResult,
        );
    publishResults(textSearch, symbolSearch);
    log(
      'Agent command searchWorkspace found '
      '${textSearch.matchCount} text match(es) and '
      '${symbolSearch.matchCount} symbol match(es) for "$normalizedQuery".',
    );
    return true;
  }
}
