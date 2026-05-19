import '../../workspace/workspace.dart';
import 'project_styio_language_service.dart';

class StyioWorkspaceDiagnosticsProvider
    implements WorkspaceDiagnosticsProvider {
  const StyioWorkspaceDiagnosticsProvider({
    this.providerId = 'styio-language',
    this.projectService = const ProjectStyioLanguageService(),
  });

  @override
  final String providerId;
  final ProjectStyioLanguageService projectService;

  @override
  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  ) async {
    final requestedIds = request.documentIds.toSet();
    final documents = request.documents
        .where(
          (document) =>
              requestedIds.isEmpty ||
              requestedIds.contains(document.documentId),
        )
        .toList(growable: false);
    if (documents.isEmpty) {
      return WorkspaceDiagnosticsSnapshot(
        providerId: providerId,
        diagnostics: const <WorkspaceDiagnostic>[],
        message: 'No documents were available for Styio diagnostics.',
      );
    }

    final analysis = projectService.analyzeProject(documents);
    final diagnostics = analysis.diagnostics
        .map(
          (diagnostic) => WorkspaceDiagnostic(
            documentId: diagnostic.documentId,
            diagnostic: diagnostic.diagnostic,
            providerId: providerId,
            source: 'styio-language',
          ),
        )
        .toList(growable: false);

    return WorkspaceDiagnosticsSnapshot(
      providerId: providerId,
      diagnostics: List<WorkspaceDiagnostic>.unmodifiable(diagnostics),
      message: diagnostics.isEmpty
          ? 'Styio diagnostics completed without workspace problems.'
          : 'Styio diagnostics reported ${diagnostics.length} problem(s).',
    );
  }
}
