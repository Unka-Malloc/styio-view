import 'package:flutter/foundation.dart';

import '../../agent/agent.dart';
import '../../commands/commands.dart';
import '../../editor/editor.dart';
import '../../interaction/interaction.dart';
import '../../language/language_contract.dart';
import '../../language/service/service.dart';
import '../../language/syntax/styio_syntax_highlighter.dart';
import '../../language/syntax_validation/syntax_validation.dart';

typedef SemanticTokensTelemetryRecorder =
    void Function({required String documentId});

/// Owns the project language facts exposed to the editor and coding agent.
final class ProjectLanguageContextController extends ChangeNotifier {
  ProjectLanguageContextController({
    required this.languageService,
    required this.editorController,
    required this.documentSamples,
    required this.loadDocuments,
    required this.cacheDocument,
    required this.languageServiceStatus,
    required this.lastDaemonRestartDispatch,
    required this.compareReferences,
    required this.log,
    required this.recordSemanticTokensTelemetry,
  });

  final ProjectStyioLanguageService languageService;
  final EditorSessionController editorController;
  final List<DocumentState> Function() documentSamples;
  final Future<List<DocumentState>> Function() loadDocuments;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final LanguageServiceStatusSurface Function() languageServiceStatus;
  final StyioServiceDaemonRestartDispatchResult? Function()
  lastDaemonRestartDispatch;
  final int Function(
    StyioProjectSymbolReference left,
    StyioProjectSymbolReference right,
  )
  compareReferences;
  final void Function(String message) log;
  final SemanticTokensTelemetryRecorder recordSemanticTokensTelemetry;

  HoverPayload? get projectHoverAtSelection {
    final hover = languageService.hoverAt(
      documents: documentSamples(),
      documentId: editorController.document.documentId,
      offset: editorController.selection.extentOffset,
    );
    if (hover == null) {
      return null;
    }
    final range =
        editorController.tokenAtSelection?.range ??
        SourceRange(
          start: editorController.selection.start,
          end: editorController.selection.end,
        );
    return HoverPayload(range: range, markdown: hover.label);
  }

  HoverPayload? get mergedHoverAtSelection =>
      projectHoverAtSelection ?? editorController.hoverAtSelection;

  List<CompletionItem> get projectCompletionsAtSelection {
    return languageService.completionsAt(
      documents: documentSamples(),
      documentId: editorController.document.documentId,
      offset: editorController.selection.extentOffset,
    );
  }

  List<CompletionItem> get mergedCompletionsAtSelection {
    final completions = <CompletionItem>[];
    final seen = <String>{};
    for (final completion in <CompletionItem>[
      ...editorController.completionsAtSelection,
      ...projectCompletionsAtSelection,
    ]) {
      final key =
          '${completion.kind.name}:${completion.label}:${completion.insertText}';
      if (seen.add(key)) {
        completions.add(completion);
      }
    }
    return List<CompletionItem>.unmodifiable(completions);
  }

  Future<Map<String, Object?>> collect() async {
    final documents = await loadDocuments();
    final documentId = editorController.document.documentId;
    final offset = editorController.selection.extentOffset;
    for (final document in documents) {
      if (document.documentId != documentId) {
        cacheDocument(document.documentId, document);
      }
    }
    final hover = languageService.hoverAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    final definitions = languageService.definitionsAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    final references =
        languageService
            .referencesAt(
              documents: documents,
              documentId: documentId,
              offset: offset,
            )
            .toList(growable: false)
          ..sort(compareReferences);
    final completions = languageService.completionsAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    const syntaxHighlighter = StyioSyntaxHighlighter();
    const syntaxValidator = StyioSyntaxValidator();
    final syntaxValidationReport = syntaxValidator.validateWithReport(
      documentId: documentId,
      source: editorController.document.text,
      tokens: syntaxHighlighter.tokenize(editorController.document.text),
    );
    final analysis = languageService.analyzeProject(documents);
    final fixes = languageService.workspaceQuickFixesForProjectDiagnostics(
      documents: documents,
      diagnostics: analysis.diagnostics,
      analysis: analysis,
    );
    final status = languageServiceStatus();
    final semanticFeatureMatrix = AgentSemanticFeatureMatrixContext.fromMatrix(
      editorController.semanticFeatureMatrix,
    ).toJson();
    final syntaxValidationAuthority = <String, Object?>{
      'preferredSource': status.syntaxValidationReady
          ? 'styio-service'
          : 'vityo-ide-syntax-contract',
      'fallbackSource': 'vityo-ide-syntax-contract',
      'fallbackActive': !status.syntaxValidationReady,
      'conflictPolicy':
          'Prefer StyioService syntax diagnostics when syntaxValidationReady is true; use the IDE syntax contract report only as fallback evidence.',
    };
    final suggestedCommandIds = <String>[
      if (status.refreshRecommended) AppCommandId.refreshLanguageService.name,
      if (definitions.isNotEmpty) AppCommandId.goToDefinition.name,
      if (references.isNotEmpty) AppCommandId.nextReference.name,
      if (fixes.isNotEmpty) AppCommandId.previewQuickFix.name,
      if (fixes.isNotEmpty) AppCommandId.applyQuickFix.name,
    ];
    final restartDispatch = lastDaemonRestartDispatch();
    final metadata = <String, Object?>{
      'documentId': documentId,
      'offset': offset,
      'documentCount': documents.length,
      'languageServiceStatus': status.toJson(),
      'semanticFeatureMatrix': semanticFeatureMatrix,
      'syntaxValidationAuthority': syntaxValidationAuthority,
      'syntaxValidationReport': syntaxValidationReport.toJson(),
      if (restartDispatch != null)
        'styioServiceDaemonRestartDispatch': restartDispatch.toJson(),
      if (suggestedCommandIds.isNotEmpty)
        'suggestedCommandIds': suggestedCommandIds,
      'diagnosticCount': analysis.diagnostics.length,
      'diagnostics': analysis.diagnostics
          .take(50)
          .map(_projectDiagnosticToJson)
          .toList(growable: false),
      'workspaceQuickFixCount': fixes.length,
      'workspaceQuickFixes': fixes
          .take(20)
          .map(_projectWorkspaceFixToJson)
          .toList(growable: false),
      if (hover != null)
        'hover': <String, Object?>{
          'label': hover.label,
          'definitionCount': hover.definitions.length,
        },
      'definitionCount': definitions.length,
      'definitions': definitions
          .take(20)
          .map(_projectSymbolDefinitionToJson)
          .toList(growable: false),
      'referenceCount': references.length,
      'references': references
          .take(50)
          .map(_projectSymbolReferenceToJson)
          .toList(growable: false),
      'completionCount': completions.length,
      'completions': completions
          .take(50)
          .map(_completionItemToJson)
          .toList(growable: false),
    };
    log(
      'Project language context collected: '
      '${definitions.length} definition(s), '
      '${references.length} reference(s), '
      '${completions.length} completion(s), '
      '${analysis.diagnostics.length} diagnostic(s), '
      '${fixes.length} quick fix candidate(s).',
    );
    recordSemanticTokensTelemetry(documentId: documentId);
    notifyListeners();
    return metadata;
  }

  Map<String, Object?> _projectDiagnosticToJson(
    StyioProjectDiagnostic diagnostic,
  ) => <String, Object?>{
    'documentId': diagnostic.documentId,
    'severity': diagnostic.diagnostic.severity.name,
    'code': diagnostic.diagnostic.code,
    'message': diagnostic.diagnostic.message,
    'range': _sourceRangeToJson(diagnostic.diagnostic.range),
  };

  Map<String, Object?> _projectWorkspaceFixToJson(
    StyioProjectWorkspaceFix fix,
  ) => <String, Object?>{
    'label': fix.label,
    if (fix.detail.isNotEmpty) 'detail': fix.detail,
    'affectedDocumentIds': fix.editsByDocument.keys.toList(growable: false),
    'editCount': fix.editsByDocument.values.fold<int>(
      0,
      (count, edits) => count + edits.length,
    ),
  };

  Map<String, Object?> _projectSymbolDefinitionToJson(
    StyioProjectSymbolDefinition definition,
  ) => <String, Object?>{
    'documentId': definition.documentId,
    'kind': definition.kind.name,
    'name': definition.name,
    'range': _sourceRangeToJson(definition.range),
    if (definition.type != null) 'type': definition.type,
  };

  Map<String, Object?> _projectSymbolReferenceToJson(
    StyioProjectSymbolReference reference,
  ) => <String, Object?>{
    'documentId': reference.documentId,
    'name': reference.name,
    'range': _sourceRangeToJson(reference.range),
    'isDefinition': reference.isDefinition,
  };

  Map<String, Object?> _completionItemToJson(CompletionItem completion) =>
      <String, Object?>{
        'label': completion.label,
        'kind': completion.kind.name,
        'insertText': completion.insertText,
        if (completion.detail.isNotEmpty) 'detail': completion.detail,
        if (completion.documentation.isNotEmpty)
          'documentation': completion.documentation,
        if (completion.replacementRange != null)
          'replacementRange': _sourceRangeToJson(completion.replacementRange!),
      };

  Map<String, Object?> _sourceRangeToJson(SourceRange range) =>
      <String, Object?>{'start': range.start, 'end': range.end};
}
