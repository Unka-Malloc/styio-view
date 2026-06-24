import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../semantic/styio_task_return_inference.dart';
import 'project_styio_document_service.dart';
import 'styio_language_service.dart';

class ProjectStyioLanguageService {
  const ProjectStyioLanguageService({
    StyioLanguageService documentService = const ProjectStyioDocumentService(),
    StyioProjectAnalysisCache? analysisCache,
    this.allowLocalProjectFallback = true,
  }) : _documentService = documentService,
       _analysisCache = analysisCache;

  static const _taskReturnInference = StyioTaskReturnInference();

  final StyioLanguageService _documentService;
  final StyioProjectAnalysisCache? _analysisCache;
  final bool allowLocalProjectFallback;

  StyioLanguageService get documentService => _documentService;

  StyioProjectAnalysis analyzeProject(List<DocumentState> documents) {
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    _analysisCache?.retainDocuments(documentsById.keys);
    final analyses = {
      for (final document in documents)
        document.documentId: _analyzeDocument(document),
    };
    if (!allowLocalProjectFallback) {
      return _strictProjectAnalysis(analyses);
    }
    final projectIndexes = {
      for (final document in documents)
        document.documentId: _projectDocumentIndex(document),
    };
    final importsByDocument = {
      for (final entry in projectIndexes.entries)
        entry.key: entry.value.imports,
    };
    final symbolSnapshot = _symbolSnapshot(
      documents: documents,
      importsByDocument: importsByDocument,
      projectIndexes: projectIndexes,
    );
    final signatureSnapshot = symbolSnapshot.signatureSnapshot;
    final diagnostics = <StyioProjectDiagnostic>[];
    diagnostics.addAll(
      _importCycleDiagnostics(
        symbolSnapshot: symbolSnapshot,
        documentsById: documentsById,
      ),
    );
    diagnostics.addAll(
      _conflictingTaskReturnContextDiagnostics(
        documents: documents,
        analyses: analyses,
        projectIndexes: projectIndexes,
      ),
    );

    for (final document in documents) {
      final importedSymbols = _importedSymbolsFor(
        documentId: document.documentId,
        importsByDocument: importsByDocument,
        analyses: analyses,
        documentsById: documentsById,
        diagnostics: diagnostics,
      );
      final importedResources = _importedResourcesFor(
        documentId: document.documentId,
        importsByDocument: importsByDocument,
        documentsById: documentsById,
        symbolSnapshot: symbolSnapshot,
      );
      final importedTasks = _importedTasksFor(
        documentId: document.documentId,
        importsByDocument: importsByDocument,
        documentsById: documentsById,
        symbolSnapshot: symbolSnapshot,
      );
      final importedFunctions = _importedFunctionsFor(
        documentId: document.documentId,
        importsByDocument: importsByDocument,
        documentsById: documentsById,
        signatureSnapshot: signatureSnapshot,
      );
      diagnostics.addAll(
        _importedCallDiagnostics(
          document: document,
          importedFunctions: importedFunctions,
        ),
      );
      diagnostics.addAll(
        _importedResourceWriteDiagnostics(
          document: document,
          importedResources: importedResources,
          importedFunctions: importedFunctions,
        ),
      );
      diagnostics.addAll(
        _importedTaskAwaitDiagnostics(
          document: document,
          importedTasks: importedTasks,
          importsByDocument: importsByDocument,
          documentsById: documentsById,
          analyses: analyses,
        ),
      );
      diagnostics.addAll(
        _unusedImportDiagnostics(
          document: document,
          importsByDocument: importsByDocument,
          analyses: analyses,
          documentsById: documentsById,
        ),
      );
      diagnostics.addAll(
        _unusedExportedSymbolDiagnostics(
          document: document,
          symbolSnapshot: symbolSnapshot,
        ),
      );
      final analysis = analyses[document.documentId]!;
      for (final diagnostic in analysis.diagnostics) {
        if (_isResolvedByImportedSymbol(
          document: document,
          diagnostic: diagnostic,
          importedSymbols: importedSymbols,
          diagnostics: diagnostics,
        )) {
          continue;
        }
        if (_isResolvedByImportedResource(
          document: document,
          diagnostic: diagnostic,
          importedResources: importedResources,
          diagnostics: diagnostics,
        )) {
          continue;
        }
        if (_isResolvedByImportedTask(
          document: document,
          diagnostic: diagnostic,
          importedTasks: importedTasks,
          diagnostics: diagnostics,
        )) {
          continue;
        }
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: diagnostic,
          ),
        );
      }
    }

    return StyioProjectAnalysis(
      documentAnalyses: analyses,
      diagnostics: List<StyioProjectDiagnostic>.unmodifiable(diagnostics),
      symbolSnapshot: symbolSnapshot,
      signatureSnapshot: signatureSnapshot,
    );
  }

  StyioProjectAnalysis _strictProjectAnalysis(
    Map<String, StyioDocumentAnalysis> analyses,
  ) {
    const symbolSnapshot = StyioProjectSymbolSnapshot._(
      functionsByDocument: <String, List<StyioFunctionSignature>>{},
      resourcesByDocument: <String, List<StyioResourceSymbol>>{},
      tasksByDocument: <String, List<StyioTaskSymbol>>{},
      sourceByDocument: <String, String>{},
      importsByDocument: <String, List<_StyioImportDirective>>{},
    );
    return StyioProjectAnalysis(
      documentAnalyses: Map<String, StyioDocumentAnalysis>.unmodifiable(
        analyses,
      ),
      diagnostics: const <StyioProjectDiagnostic>[],
      symbolSnapshot: symbolSnapshot,
      signatureSnapshot: symbolSnapshot.signatureSnapshot,
    );
  }

  List<DiagnosticQuickFix> quickFixesForProjectDiagnostic({
    required List<DocumentState> documents,
    required StyioProjectDiagnostic diagnostic,
    StyioProjectAnalysis? analysis,
  }) {
    final document = _documentByIdOrNull(documents, diagnostic.documentId);
    if (document == null) {
      return const <DiagnosticQuickFix>[];
    }

    switch (diagnostic.diagnostic.code) {
      case 'unused-import':
        final fix = _removeProjectImportFix(
          document: document,
          diagnostic: diagnostic,
          label: 'Remove unused import',
          detail: 'Delete the import that contributes no visible symbols.',
        );
        return fix == null ? const <DiagnosticQuickFix>[] : [fix];
      case 'unresolved-import':
        final fix = _removeProjectImportFix(
          document: document,
          diagnostic: diagnostic,
          label: 'Remove unresolved import',
          detail: 'Delete the import that does not resolve in this workspace.',
        );
        return [
          if (fix != null) fix,
          ..._quickFixesForUnresolvedProjectImportTarget(
            documents: documents,
            document: document,
            diagnostic: diagnostic,
          ),
        ];
      case 'import-cycle':
        final fix = _removeProjectImportFix(
          document: document,
          diagnostic: diagnostic,
          label: 'Remove cyclic import',
          detail: 'Delete this import edge to break the project import cycle.',
        );
        return fix == null ? const <DiagnosticQuickFix>[] : [fix];
      case 'unused-exported-symbol':
        final fix = _removeUnusedExportedSymbolFix(
          document: document,
          diagnostic: diagnostic,
        );
        return fix == null ? const <DiagnosticQuickFix>[] : [fix];
      case 'resource-write-type-mismatch':
        return _dedupeQuickFixes([
          ..._quickFixesForImportedResourceWriteMismatch(
            document,
            diagnostic.diagnostic,
          ),
          ..._documentQuickFixesForProjectDiagnostic(document, diagnostic),
        ]);
      case 'await-result-type-mismatch':
        return _dedupeQuickFixes([
          ..._quickFixesForImportedTaskAwaitMismatch(
            document,
            diagnostic.diagnostic,
          ),
          ..._documentQuickFixesForProjectDiagnostic(document, diagnostic),
        ]);
      case 'await-fallback-type-mismatch':
        return _documentQuickFixesForProjectDiagnostic(document, diagnostic);
      case 'missing-task-return-value':
        final documentFixes = _documentQuickFixesForProjectDiagnostic(
          document,
          diagnostic,
        );
        if (documentFixes.isNotEmpty) {
          return documentFixes;
        }
        return _quickFixesForImportedMissingTaskReturnValue(
          documents: documents,
          document: document,
          diagnostic: diagnostic,
        );
      case 'unresolved-task-return-value':
        final documentFixes = _documentQuickFixesForProjectDiagnostic(
          document,
          diagnostic,
        );
        if (documentFixes.isNotEmpty) {
          return documentFixes;
        }
        return _quickFixesForImportedUnresolvedTaskReturnValue(
          documents: documents,
          document: document,
          diagnostic: diagnostic,
        );
      case 'argument-type-mismatch':
        return _dedupeQuickFixes([
          ..._quickFixesForImportedArgumentTypeMismatch(
            document,
            diagnostic.diagnostic,
          ),
          ..._documentQuickFixesForProjectDiagnostic(document, diagnostic),
        ]);
      case 'unknown-named-argument':
      case 'duplicate-named-argument':
      case 'missing-call-argument':
      case 'too-many-call-arguments':
        return [
          ..._quickFixesForImportedCallArgumentIssue(
            document: document,
            diagnostic: diagnostic.diagnostic,
            analysis: analysis ?? analyzeProject(documents),
          ),
          ..._documentQuickFixesForProjectDiagnostic(document, diagnostic),
        ];
      case 'unresolved-reference':
        return [
          ..._quickFixesForMissingProjectImport(
            documents: documents,
            document: document,
            diagnostic: diagnostic,
            analysis: analysis ?? analyzeProject(documents),
          ),
          ..._documentQuickFixesForProjectDiagnostic(document, diagnostic),
        ];
      case 'unresolved-resource':
      case 'unresolved-task-await':
        return [
          ..._quickFixesForMissingProjectImport(
            documents: documents,
            document: document,
            diagnostic: diagnostic,
            analysis: analysis ?? analyzeProject(documents),
          ),
          ..._documentQuickFixesForProjectDiagnostic(document, diagnostic),
        ];
      case 'ambiguous-imported-symbol':
        return _quickFixesForAmbiguousProjectImport(
          documents: documents,
          document: document,
          diagnostic: diagnostic,
          analysis: analysis ?? analyzeProject(documents),
        );
    }
    return _documentQuickFixesForProjectDiagnostic(document, diagnostic);
  }

  List<StyioProjectWorkspaceFix> workspaceQuickFixesForProjectDiagnostics({
    required List<DocumentState> documents,
    required List<StyioProjectDiagnostic> diagnostics,
    StyioProjectAnalysis? analysis,
  }) {
    final resolvedAnalysis = analysis ?? analyzeProject(documents);
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final importEditsByDocument = <String, List<FormattingEdit>>{};
    final exportedSymbolEditsByDocument = <String, List<FormattingEdit>>{};
    final typeEditsByDocument = <String, List<FormattingEdit>>{};
    final runtimeDeclarationEditsByDocument = <String, List<FormattingEdit>>{};
    final importedCallEditsByDocument = <String, List<FormattingEdit>>{};
    final invalidResourceWriteEditsByDocument =
        <String, List<FormattingEdit>>{};
    final unreachableCodeEditsByDocument = <String, List<FormattingEdit>>{};
    final syntaxCleanupEditsByDocument = <String, List<FormattingEdit>>{};
    final expressionSimplificationEditsByDocument =
        <String, List<FormattingEdit>>{};
    final seenImportEdits = <String>{};
    final seenExportedSymbolEdits = <String>{};
    final seenTypeEdits = <String>{};
    final seenRuntimeDeclarationEdits = <String>{};
    final seenImportedCallEdits = <String>{};
    final seenInvalidResourceWriteEdits = <String>{};
    final seenUnreachableCodeEdits = <String>{};
    final seenSyntaxCleanupEdits = <String>{};
    final seenExpressionSimplificationEdits = <String>{};
    for (final diagnostic in diagnostics) {
      final isImportFix = _isDeterministicProjectImportFix(
        diagnostic.diagnostic.code,
      );
      final isImportStyleFix = _isDeterministicProjectImportStyleFix(
        diagnostic.diagnostic.code,
      );
      final isExportedSymbolFix = _isDeterministicUnusedExportedSymbolFix(
        diagnostic.diagnostic.code,
      );
      final isTypeFix = _isDeterministicProjectTypeFix(
        diagnostic.diagnostic.code,
      );
      final isRuntimeDeclarationFix = _isDeterministicRuntimeDeclarationFix(
        diagnostic.diagnostic.code,
      );
      final isImportedCallFix = _isDeterministicImportedCallFix(
        diagnostic.diagnostic.code,
      );
      final isInvalidResourceWriteFix = _isDeterministicInvalidResourceWriteFix(
        diagnostic.diagnostic.code,
      );
      final isUnreachableCodeFix = _isDeterministicUnreachableCodeFix(
        diagnostic.diagnostic.code,
      );
      final isSyntaxCleanupFix = _isDeterministicSyntaxCleanupFix(
        diagnostic.diagnostic.code,
      );
      final isExpressionSimplificationFix =
          _isDeterministicExpressionSimplificationFix(
            diagnostic.diagnostic.code,
          );
      final isMissingTaskReturnFix =
          diagnostic.diagnostic.code == 'missing-task-return' ||
          diagnostic.diagnostic.code == 'conditional-task-return';
      final isInvalidTaskReturnFix =
          diagnostic.diagnostic.code == 'invalid-task-return-expression';
      if (isImportedCallFix &&
          _shouldSkipWorkspaceImportedCallFix(diagnostic, diagnostics)) {
        continue;
      }
      if (!isImportFix &&
          !isImportStyleFix &&
          !isExportedSymbolFix &&
          !isTypeFix &&
          !isRuntimeDeclarationFix &&
          !isImportedCallFix &&
          !isInvalidResourceWriteFix &&
          !isUnreachableCodeFix &&
          !isSyntaxCleanupFix &&
          !isExpressionSimplificationFix &&
          !isMissingTaskReturnFix &&
          !isInvalidTaskReturnFix) {
        continue;
      }
      if (isMissingTaskReturnFix) {
        final edit = _workspaceMissingTaskReturnEdit(
          documentsById: documentsById,
          analysis: resolvedAnalysis,
          diagnostic: diagnostic,
        );
        if (edit == null) {
          continue;
        }
        _addWorkspaceFixEdit(
          documentsById: documentsById,
          editsByDocument: typeEditsByDocument,
          seenEdits: seenTypeEdits,
          documentId: edit.key,
          edit: edit.value,
        );
        continue;
      }
      if (isInvalidTaskReturnFix) {
        final importedEdit = _workspaceInvalidTaskReturnExpressionEdit(
          documentsById: documentsById,
          analysis: resolvedAnalysis,
          diagnostic: diagnostic,
        );
        if (importedEdit != null) {
          _addWorkspaceFixEdit(
            documentsById: documentsById,
            editsByDocument: typeEditsByDocument,
            seenEdits: seenTypeEdits,
            documentId: importedEdit.key,
            edit: importedEdit.value,
          );
          continue;
        }

        final fixes = quickFixesForProjectDiagnostic(
          documents: documents,
          diagnostic: diagnostic,
          analysis: resolvedAnalysis,
        );
        if (fixes.length != 1) {
          continue;
        }
        for (final edit in fixes.single.edits) {
          _addWorkspaceFixEdit(
            documentsById: documentsById,
            editsByDocument: typeEditsByDocument,
            seenEdits: seenTypeEdits,
            documentId: diagnostic.documentId,
            edit: edit,
          );
        }
        continue;
      }
      final fixes = isImportFix
          ? _workspaceProjectImportFixes(documents, diagnostic)
          : quickFixesForProjectDiagnostic(
              documents: documents,
              diagnostic: diagnostic,
              analysis: resolvedAnalysis,
            );
      if (fixes.length != 1) {
        continue;
      }
      final editsByDocument = isImportFix
          ? importEditsByDocument
          : isImportStyleFix
          ? importEditsByDocument
          : isExportedSymbolFix
          ? exportedSymbolEditsByDocument
          : isTypeFix
          ? typeEditsByDocument
          : isRuntimeDeclarationFix
          ? runtimeDeclarationEditsByDocument
          : isImportedCallFix
          ? importedCallEditsByDocument
          : isUnreachableCodeFix
          ? unreachableCodeEditsByDocument
          : isSyntaxCleanupFix
          ? syntaxCleanupEditsByDocument
          : isExpressionSimplificationFix
          ? expressionSimplificationEditsByDocument
          : invalidResourceWriteEditsByDocument;
      final seenEdits = isImportFix
          ? seenImportEdits
          : isImportStyleFix
          ? seenImportEdits
          : isExportedSymbolFix
          ? seenExportedSymbolEdits
          : isTypeFix
          ? seenTypeEdits
          : isRuntimeDeclarationFix
          ? seenRuntimeDeclarationEdits
          : isImportedCallFix
          ? seenImportedCallEdits
          : isUnreachableCodeFix
          ? seenUnreachableCodeEdits
          : isSyntaxCleanupFix
          ? seenSyntaxCleanupEdits
          : isExpressionSimplificationFix
          ? seenExpressionSimplificationEdits
          : seenInvalidResourceWriteEdits;
      for (final edit in fixes.single.edits) {
        _addWorkspaceFixEdit(
          documentsById: documentsById,
          editsByDocument: editsByDocument,
          seenEdits: seenEdits,
          documentId: diagnostic.documentId,
          edit: edit,
        );
      }
    }
    final fixes = <StyioProjectWorkspaceFix>[];
    if (importEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Clean up project imports',
          detail:
              'Remove unresolved, unused, cyclic, duplicate, or unsorted '
              'imports with deterministic project fixes.',
          editsByDocument: {
            for (final entry in importEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (exportedSymbolEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Remove unused exported symbols',
          detail:
              'Delete exported declarations that have no project references.',
          editsByDocument: {
            for (final entry in exportedSymbolEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (typeEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Fix project type mismatches',
          detail:
              'Apply deterministic Styio type fixes across imported calls, '
              'resource writes, task awaits, and task returns.',
          editsByDocument: {
            for (final entry in typeEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (runtimeDeclarationEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Remove duplicate Styio runtime declarations',
          detail:
              'Delete duplicate resource and task declarations across the '
              'workspace.',
          editsByDocument: {
            for (final entry in runtimeDeclarationEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (importedCallEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Fix imported function calls',
          detail: 'Apply deterministic fixes for imported function arguments.',
          editsByDocument: {
            for (final entry in importedCallEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (invalidResourceWriteEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Remove invalid resource writes',
          detail: 'Delete writes that target read-only Styio resources.',
          editsByDocument: {
            for (final entry in invalidResourceWriteEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (unreachableCodeEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Remove unreachable project code',
          detail: 'Delete unreachable Styio statements across the workspace.',
          editsByDocument: {
            for (final entry in unreachableCodeEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (syntaxCleanupEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Clean up redundant project syntax',
          detail:
              'Remove redundant Styio type annotations and parentheses across '
              'the workspace.',
          editsByDocument: {
            for (final entry in syntaxCleanupEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (expressionSimplificationEditsByDocument.isNotEmpty) {
      fixes.add(
        StyioProjectWorkspaceFix(
          label: 'Simplify project expressions',
          detail:
              'Apply deterministic Styio numeric and boolean expression '
              'simplifications across the workspace.',
          editsByDocument: {
            for (final entry in expressionSimplificationEditsByDocument.entries)
              entry.key: List<FormattingEdit>.unmodifiable(entry.value),
          },
        ),
      );
    }
    if (fixes.isEmpty) {
      return const <StyioProjectWorkspaceFix>[];
    }
    return List<StyioProjectWorkspaceFix>.unmodifiable(fixes);
  }

  bool _isDeterministicProjectImportFix(String code) {
    return code == 'unresolved-import' ||
        code == 'unused-import' ||
        code == 'import-cycle';
  }

  bool _isDeterministicProjectImportStyleFix(String code) {
    return code == 'duplicate-import' || code == 'import-block-not-optimized';
  }

  bool _isDeterministicUnusedExportedSymbolFix(String code) {
    return code == 'unused-exported-symbol';
  }

  bool _isDeterministicProjectTypeFix(String code) {
    return code == 'argument-type-mismatch' ||
        code == 'resource-write-type-mismatch' ||
        code == 'await-result-type-mismatch' ||
        code == 'await-fallback-type-mismatch' ||
        code == 'missing-function-return' ||
        code == 'missing-task-return-value' ||
        code == 'unresolved-task-return-value';
  }

  bool _isDeterministicRuntimeDeclarationFix(String code) {
    return code == 'duplicate-resource-declaration' ||
        code == 'duplicate-task-declaration';
  }

  bool _isDeterministicImportedCallFix(String code) {
    return code == 'missing-call-argument' ||
        code == 'too-many-call-arguments' ||
        code == 'unknown-named-argument' ||
        code == 'duplicate-named-argument';
  }

  bool _isDeterministicInvalidResourceWriteFix(String code) {
    return code == 'read-only-resource-write';
  }

  bool _isDeterministicUnreachableCodeFix(String code) {
    return code == 'unreachable-code';
  }

  bool _isDeterministicSyntaxCleanupFix(String code) {
    return code == 'redundant-type-annotation' ||
        code == 'redundant-parentheses';
  }

  bool _isDeterministicExpressionSimplificationFix(String code) {
    return code == 'simplifiable-numeric-expression' ||
        code == 'simplifiable-boolean-negation' ||
        code == 'simplifiable-boolean-comparison' ||
        code == 'simplifiable-boolean-expression' ||
        code == 'simplifiable-negated-comparison' ||
        code == 'simplifiable-demorgan-expression';
  }

  bool _shouldSkipWorkspaceImportedCallFix(
    StyioProjectDiagnostic diagnostic,
    List<StyioProjectDiagnostic> diagnostics,
  ) {
    if (diagnostic.diagnostic.code != 'missing-call-argument') {
      return false;
    }
    return diagnostics.any(
      (other) =>
          other.documentId == diagnostic.documentId &&
          (other.diagnostic.code == 'unknown-named-argument' ||
              other.diagnostic.code == 'duplicate-named-argument') &&
          diagnostic.diagnostic.range.intersects(other.diagnostic.range),
    );
  }

  bool _addWorkspaceFixEdit({
    required Map<String, DocumentState> documentsById,
    required Map<String, List<FormattingEdit>> editsByDocument,
    required Set<String> seenEdits,
    required String documentId,
    required FormattingEdit edit,
  }) {
    final document = documentsById[documentId];
    if (document == null ||
        !isFormattingEditValidForDocument(
          documentLength: document.length,
          edit: edit,
        )) {
      return false;
    }
    final key =
        '$documentId:${edit.range.start}:${edit.range.end}:${edit.newText}';
    if (!seenEdits.add(key)) {
      return false;
    }
    final documentEdits = editsByDocument.putIfAbsent(
      documentId,
      () => <FormattingEdit>[],
    );
    if (documentEdits.any(
      (existing) => _formattingEditsConflict(existing, edit),
    )) {
      return false;
    }
    documentEdits.add(edit);
    return true;
  }

  bool _formattingEditsConflict(FormattingEdit left, FormattingEdit right) {
    final leftIsInsertion = left.range.start == left.range.end;
    final rightIsInsertion = right.range.start == right.range.end;
    if (leftIsInsertion && rightIsInsertion) {
      return left.range.start == right.range.start;
    }
    if (leftIsInsertion) {
      return right.range.start <= left.range.start &&
          left.range.start <= right.range.end;
    }
    if (rightIsInsertion) {
      return left.range.start <= right.range.start &&
          right.range.start <= left.range.end;
    }
    return left.range.start < right.range.end &&
        right.range.start < left.range.end;
  }

  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _documentService.quickFixesForDiagnostic(document, diagnostic);
  }

  List<DiagnosticQuickFix> _documentQuickFixesForProjectDiagnostic(
    DocumentState document,
    StyioProjectDiagnostic diagnostic,
  ) {
    return quickFixesForDiagnostic(document, diagnostic.diagnostic);
  }

  List<DiagnosticQuickFix> _dedupeQuickFixes(
    Iterable<DiagnosticQuickFix> fixes,
  ) {
    final deduped = <DiagnosticQuickFix>[];
    final seen = <String>{};
    for (final fix in fixes) {
      final editKey = fix.edits
          .map(
            (edit) => '${edit.range.start}:${edit.range.end}:${edit.newText}',
          )
          .join('|');
      final key = '${fix.label}:$editKey';
      if (seen.add(key)) {
        deduped.add(fix);
      }
    }
    return List<DiagnosticQuickFix>.unmodifiable(deduped);
  }

  List<DiagnosticQuickFix> _workspaceProjectImportFixes(
    List<DocumentState> documents,
    StyioProjectDiagnostic diagnostic,
  ) {
    final document = _documentByIdOrNull(documents, diagnostic.documentId);
    if (document == null) {
      return const <DiagnosticQuickFix>[];
    }

    final code = diagnostic.diagnostic.code;
    if (code == 'unused-import') {
      final fix = _removeProjectImportFix(
        document: document,
        diagnostic: diagnostic,
        label: 'Remove unused import',
        detail: 'Delete the import that contributes no visible symbols.',
      );
      return fix == null ? const <DiagnosticQuickFix>[] : [fix];
    }
    if (code == 'unresolved-import') {
      final fix = _removeProjectImportFix(
        document: document,
        diagnostic: diagnostic,
        label: 'Remove unresolved import',
        detail: 'Delete the import that does not resolve in this workspace.',
      );
      return fix == null ? const <DiagnosticQuickFix>[] : [fix];
    }
    if (code == 'import-cycle') {
      final fix = _removeProjectImportFix(
        document: document,
        diagnostic: diagnostic,
        label: 'Remove cyclic import',
        detail: 'Delete this import edge to break the project import cycle.',
      );
      return fix == null ? const <DiagnosticQuickFix>[] : [fix];
    }
    return const <DiagnosticQuickFix>[];
  }

  List<StyioProjectSymbolDefinition> definitionsAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
  }) {
    final targetDocument = _documentByIdOrNull(documents, documentId);
    if (targetDocument == null ||
        offset < 0 ||
        offset > targetDocument.text.length) {
      return const <StyioProjectSymbolDefinition>[];
    }
    if (_isOffsetInImportDirective(targetDocument.text, offset)) {
      return const <StyioProjectSymbolDefinition>[];
    }
    final name = _identifierAt(targetDocument.text, offset);
    if (name == null) {
      return const <StyioProjectSymbolDefinition>[];
    }
    return analyzeProject(
      documents,
    ).symbolSnapshot.definitionsVisibleFrom(documentId: documentId, name: name);
  }

  StyioProjectHover? hoverAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
  }) {
    final definitions = definitionsAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    if (definitions.isEmpty) {
      return null;
    }
    return StyioProjectHover.fromDefinitions(definitions);
  }

  List<CompletionItem> completionsAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
  }) {
    final targetDocument = _documentByIdOrNull(documents, documentId);
    if (targetDocument == null ||
        offset < 0 ||
        offset > targetDocument.text.length) {
      return const <CompletionItem>[];
    }
    final importContext = _importCompletionContext(targetDocument.text, offset);
    if (importContext != null) {
      return _importCompletions(
        documents: documents,
        currentDocumentId: documentId,
        context: importContext,
      );
    }
    final prefix = _identifierPrefixBefore(targetDocument.text, offset);
    final analysis = analyzeProject(documents);
    final definitions = analysis.symbolSnapshot.definitionsVisibleFromDocument(
      documentId,
    );
    final items = <CompletionItem>[];
    final seen = <String>{};
    for (final definition in definitions) {
      if (prefix.isNotEmpty && !definition.name.startsWith(prefix)) {
        continue;
      }
      final key =
          '${definition.kind.name}:${definition.name}:${definition.type}';
      if (!seen.add(key)) {
        continue;
      }
      items.add(_completionItemForDefinition(definition));
    }
    return List<CompletionItem>.unmodifiable(items);
  }

  ParameterInfoPayload? parameterInfoAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
  }) {
    final targetDocument = _documentByIdOrNull(documents, documentId);
    if (targetDocument == null ||
        offset < 0 ||
        offset > targetDocument.text.length) {
      return null;
    }
    final call = _projectFunctionCallAt(targetDocument.text, offset);
    if (call == null) {
      return null;
    }

    final analysis = analyzeProject(documents);
    final definitions = analysis.symbolSnapshot
        .definitionsVisibleFrom(documentId: documentId, name: call.name)
        .where(
          (definition) => definition.kind == StyioProjectSymbolKind.function,
        )
        .toList(growable: false);
    if (definitions.length != 1) {
      return null;
    }
    final signature = _signatureForDefinition(
      analysis.signatureSnapshot,
      definitions.single,
    );
    if (signature == null) {
      return null;
    }

    final parameters = [
      for (final parameter in signature.parameters)
        ParameterInfoParameter(
          name: parameter.name,
          range: const SourceRange(start: -1, end: -1),
          type: parameter.type,
        ),
    ];
    var activeParameterIndex = _activeProjectParameterIndex(
      call: call,
      offset: offset,
    );
    _ArgumentSlice? activeArgument;
    for (final argument in _argumentSlices(
      call.argumentText,
      call.argumentRange.start,
    )) {
      if (argument.range.contains(offset)) {
        activeArgument = argument;
        break;
      }
    }
    if (activeArgument != null) {
      final namedSeparator = _topLevelNamedArgumentSeparator(
        activeArgument.text,
      );
      if (namedSeparator != null) {
        final argumentName = activeArgument.text
            .substring(0, namedSeparator)
            .trim();
        final namedIndex = signature.parameters.indexWhere(
          (parameter) => parameter.name == argumentName,
        );
        if (namedIndex >= 0) {
          activeParameterIndex = namedIndex;
        }
      }
    }
    if (parameters.isEmpty) {
      activeParameterIndex = -1;
    } else {
      activeParameterIndex = activeParameterIndex.clamp(
        0,
        parameters.length - 1,
      );
    }

    return ParameterInfoPayload(
      callableName: signature.name,
      signature: _signatureDisplayText(signature),
      parameters: List<ParameterInfoParameter>.unmodifiable(parameters),
      activeParameterIndex: activeParameterIndex,
      invocationRange: SourceRange(
        start: call.callableRange.start,
        end: call.closingParenthesis + 1,
      ),
      callableRange: call.callableRange,
    );
  }

  List<CompletionItem> namedArgumentCompletionsAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
  }) {
    final targetDocument = _documentByIdOrNull(documents, documentId);
    if (targetDocument == null ||
        offset < 0 ||
        offset > targetDocument.text.length) {
      return const <CompletionItem>[];
    }
    final call = _projectFunctionCallAt(targetDocument.text, offset);
    if (call == null) {
      return const <CompletionItem>[];
    }
    final context = _projectNamedArgumentCompletionContext(
      source: targetDocument.text,
      call: call,
      offset: offset,
    );
    if (context == null) {
      return const <CompletionItem>[];
    }

    final analysis = analyzeProject(documents);
    final definitions = analysis.symbolSnapshot
        .definitionsVisibleFrom(documentId: documentId, name: call.name)
        .where(
          (definition) => definition.kind == StyioProjectSymbolKind.function,
        )
        .toList(growable: false);
    if (definitions.length != 1) {
      return const <CompletionItem>[];
    }
    final signature = _signatureForDefinition(
      analysis.signatureSnapshot,
      definitions.single,
    );
    if (signature == null || signature.parameters.isEmpty) {
      return const <CompletionItem>[];
    }

    final arguments =
        _argumentSlices(call.argumentText, call.argumentRange.start)
            .where(
              (argument) => !argument.range.intersects(context.segmentRange),
            )
            .toList(growable: false);
    final providedNames = _providedProjectParameterNames(
      signature: signature,
      arguments: arguments,
    );

    return [
      for (final parameter in signature.parameters)
        if (!providedNames.contains(parameter.name) &&
            (context.prefix.isEmpty ||
                parameter.name.startsWith(context.prefix)))
          CompletionItem(
            label: '${parameter.name}:',
            kind: CompletionItemKind.snippet,
            insertText: '${parameter.name}: ',
            detail:
                'Named argument for `${signature.name}`'
                '${parameter.type.isEmpty ? '' : ' · ${parameter.type}'}',
            replacementRange: context.replacementRange,
          ),
    ];
  }

  List<InlayHint> inlayHintsFor({
    required List<DocumentState> documents,
    required String documentId,
  }) {
    final targetDocument = _documentByIdOrNull(documents, documentId);
    if (targetDocument == null) {
      return const <InlayHint>[];
    }
    final analysis = analyzeProject(documents);
    final hints = <InlayHint>[];
    for (final call in _projectFunctionCalls(targetDocument.text)) {
      final definitions = analysis.symbolSnapshot
          .definitionsVisibleFrom(documentId: documentId, name: call.name)
          .where(
            (definition) => definition.kind == StyioProjectSymbolKind.function,
          )
          .toList(growable: false);
      if (definitions.length != 1) {
        continue;
      }
      final signature = _signatureForDefinition(
        analysis.signatureSnapshot,
        definitions.single,
      );
      if (signature == null || signature.parameters.isEmpty) {
        continue;
      }
      hints.addAll(
        _parameterInlayHintsForCall(call: call, signature: signature),
      );
    }
    return List<InlayHint>.unmodifiable(hints);
  }

  List<CompletionItem> _importCompletions({
    required List<DocumentState> documents,
    required String currentDocumentId,
    required _StyioImportCompletionContext context,
  }) {
    final items = <CompletionItem>[];
    for (final document in documents) {
      if (document.documentId == currentDocumentId) {
        continue;
      }
      final target = _canonicalImportTarget(document.documentId);
      if (context.prefix.isNotEmpty && !target.startsWith(context.prefix)) {
        continue;
      }
      items.add(
        CompletionItem(
          label: target,
          kind: CompletionItemKind.snippet,
          insertText: target,
          detail: 'workspace import',
          replacementRange: context.replacementRange,
        ),
      );
    }
    items.sort((left, right) => left.label.compareTo(right.label));
    return List<CompletionItem>.unmodifiable(items);
  }

  List<StyioProjectSymbolReference> referencesAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
  }) {
    final targetDocument = _documentByIdOrNull(documents, documentId);
    if (targetDocument == null ||
        offset < 0 ||
        offset > targetDocument.text.length) {
      return const <StyioProjectSymbolReference>[];
    }
    if (_isOffsetInImportDirective(targetDocument.text, offset)) {
      return const <StyioProjectSymbolReference>[];
    }
    final name = _identifierAt(targetDocument.text, offset);
    if (name == null) {
      return const <StyioProjectSymbolReference>[];
    }
    final analysis = analyzeProject(documents);
    final definitions = analysis.symbolSnapshot.definitionsVisibleFrom(
      documentId: documentId,
      name: name,
    );
    if (definitions.isEmpty) {
      return const <StyioProjectSymbolReference>[];
    }

    final references = <StyioProjectSymbolReference>[];
    final seen = <String>{};
    for (final definition in definitions) {
      for (final reference in analysis.symbolSnapshot.referencesFor(
        definition,
      )) {
        final key =
            '${reference.documentId}:${reference.range.start}:${reference.range.end}';
        if (seen.add(key)) {
          references.add(reference);
        }
      }
    }
    return List<StyioProjectSymbolReference>.unmodifiable(references);
  }

  StyioProjectRenamePreview? renamePreviewAt({
    required List<DocumentState> documents,
    required String documentId,
    required int offset,
    required String newName,
  }) {
    if (!_isValidIdentifier(newName)) {
      return StyioProjectRenamePreview.conflict(
        oldName: '',
        newName: newName,
        conflict: 'New name `$newName` is not a valid Styio identifier.',
      );
    }
    final analysis = analyzeProject(documents);
    final references = referencesAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    if (references.isEmpty) {
      return null;
    }
    final oldName = references.first.name;
    final visibleConflicts = <StyioProjectSymbolDefinition>[];
    final seenConflicts = <String>{};
    for (final affectedDocumentId in {
      documentId,
      for (final reference in references) reference.documentId,
    }) {
      for (final definition in analysis.symbolSnapshot.definitionsVisibleFrom(
        documentId: affectedDocumentId,
        name: newName,
      )) {
        if (definition.name == oldName) {
          continue;
        }
        final key =
            '${definition.documentId}:${definition.kind.name}:'
            '${definition.range.start}:${definition.range.end}';
        if (seenConflicts.add(key)) {
          visibleConflicts.add(definition);
        }
      }
    }
    if (visibleConflicts.isNotEmpty) {
      return StyioProjectRenamePreview.conflict(
        oldName: oldName,
        newName: newName,
        conflict:
            'New name `$newName` conflicts with ${visibleConflicts.length} visible symbol'
            '${visibleConflicts.length == 1 ? '' : 's'}.',
      );
    }
    final editsByDocument = <String, List<SourceRange>>{};
    for (final reference in references) {
      editsByDocument
          .putIfAbsent(reference.documentId, () => <SourceRange>[])
          .add(reference.range);
    }
    return StyioProjectRenamePreview(
      oldName: oldName,
      newName: newName,
      editsByDocument: {
        for (final entry in editsByDocument.entries)
          entry.key: List<SourceRange>.unmodifiable(entry.value),
      },
    );
  }

  DocumentState? _documentByIdOrNull(
    List<DocumentState> documents,
    String documentId,
  ) {
    for (final document in documents) {
      if (document.documentId == documentId) {
        return document;
      }
    }
    return null;
  }

  DiagnosticQuickFix? _removeProjectImportFix({
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
    required String label,
    required String detail,
  }) {
    final range = diagnostic.diagnostic.range;
    if (range.start < 0 ||
        range.end > document.text.length ||
        range.start >= range.end) {
      return null;
    }
    return DiagnosticQuickFix(
      label: label,
      detail: detail,
      edits: [
        FormattingEdit(
          range: _lineRemovalRange(document.text, range),
          newText: '',
        ),
      ],
    );
  }

  DiagnosticQuickFix? _removeUnusedExportedSymbolFix({
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
  }) {
    final range = diagnostic.diagnostic.range;
    if (range.start < 0 ||
        range.end > document.text.length ||
        range.start >= range.end) {
      return null;
    }
    return DiagnosticQuickFix(
      label: 'Remove unused exported symbol',
      detail: 'Delete the exported declaration because it has no references.',
      edits: [
        FormattingEdit(
          range: _declarationRemovalRange(document.text, range),
          newText: '',
        ),
      ],
    );
  }

  List<DiagnosticQuickFix> _quickFixesForUnresolvedProjectImportTarget({
    required List<DocumentState> documents,
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
  }) {
    final target = _importTargetTextForRange(
      document.text,
      diagnostic.diagnostic.range,
    );
    if (target == null) {
      return const <DiagnosticQuickFix>[];
    }

    final candidates = <_ImportTargetSuggestion>[];
    for (final workspaceDocument in documents) {
      if (workspaceDocument.documentId == document.documentId) {
        continue;
      }
      final candidate = _canonicalImportTarget(workspaceDocument.documentId);
      final distance = _editDistance(target, candidate);
      final threshold = (candidate.length / 3).ceil().clamp(1, 4);
      if (distance <= threshold ||
          candidate.endsWith('/$target') ||
          target.endsWith('/$candidate')) {
        candidates.add(
          _ImportTargetSuggestion(target: candidate, distance: distance),
        );
      }
    }
    candidates.sort((left, right) {
      final byDistance = left.distance.compareTo(right.distance);
      return byDistance == 0 ? left.target.compareTo(right.target) : byDistance;
    });

    final offered = <String>{};
    return [
      for (final candidate in candidates.take(3))
        if (offered.add(candidate.target))
          DiagnosticQuickFix(
            label: 'Change import to `${candidate.target}`',
            detail: 'Update the unresolved import to a workspace document.',
            edits: [
              FormattingEdit(
                range: diagnostic.diagnostic.range,
                newText: candidate.target,
              ),
            ],
          ),
    ];
  }

  String? _importTargetTextForRange(String source, SourceRange range) {
    if (range.start < 0 ||
        range.end > source.length ||
        range.start >= range.end) {
      return null;
    }
    final target = source.substring(range.start, range.end).trim();
    return target.isEmpty ? null : target;
  }

  List<DiagnosticQuickFix> _quickFixesForImportedResourceWriteMismatch(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final expectedType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'expects',
    );
    final replacement = expectedType == null
        ? null
        : _defaultLiteralForProjectType(expectedType);
    if (replacement == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacementRange = _trimmedRange(document.text, diagnostic.range);
    if (replacementRange.start >= replacementRange.end) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Change resource write value to $expectedType literal',
        detail:
            'Rewrite the value sent to the imported resource as a '
            '`$expectedType` literal.',
        edits: [FormattingEdit(range: replacementRange, newText: replacement)],
      ),
    ];
  }

  List<DiagnosticQuickFix> _quickFixesForImportedArgumentTypeMismatch(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final expectedType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'expects',
    );
    final replacement = expectedType == null
        ? null
        : _defaultLiteralForProjectType(expectedType);
    if (replacement == null ||
        !diagnostic.message.contains('from imported function')) {
      return const <DiagnosticQuickFix>[];
    }
    final replacementRange = _trimmedRange(document.text, diagnostic.range);
    if (replacementRange.start >= replacementRange.end) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Change argument to $expectedType literal',
        detail:
            'Rewrite the imported function argument as a `$expectedType` '
            'literal.',
        edits: [FormattingEdit(range: replacementRange, newText: replacement)],
      ),
    ];
  }

  List<DiagnosticQuickFix> _quickFixesForImportedCallArgumentIssue({
    required DocumentState document,
    required Diagnostic diagnostic,
    required StyioProjectAnalysis analysis,
  }) {
    final call = _projectCallForDiagnosticRange(
      document.text,
      diagnostic.range,
    );
    if (call == null) {
      return const <DiagnosticQuickFix>[];
    }
    final signature = _uniqueImportedSignatureForCall(
      documentId: document.documentId,
      call: call,
      analysis: analysis,
    );
    if (signature == null) {
      return const <DiagnosticQuickFix>[];
    }
    final arguments = _argumentSlices(
      call.argumentText,
      call.argumentRange.start,
    );

    if (diagnostic.code == 'missing-call-argument') {
      final missing = _missingRequiredImportedParameters(
        signature: signature,
        arguments: arguments,
      );
      if (missing.isEmpty) {
        return const <DiagnosticQuickFix>[];
      }
      final placeholders = missing
          .map((parameter) => _defaultLiteralForProjectType(parameter.type))
          .map((literal) => literal ?? 'value')
          .toList(growable: false);
      return [
        DiagnosticQuickFix(
          label: 'Insert missing argument${missing.length == 1 ? '' : 's'}',
          detail:
              'Append placeholder value${missing.length == 1 ? '' : 's'} '
              'for imported function `${signature.name}`.',
          edits: [
            FormattingEdit(
              range: SourceRange(
                start: call.argumentRange.end,
                end: call.argumentRange.end,
              ),
              newText:
                  '${arguments.isEmpty ? '' : ', '}${placeholders.join(', ')}',
            ),
          ],
        ),
      ];
    }

    if (diagnostic.code == 'too-many-call-arguments') {
      if (arguments.length <= signature.parameterCount) {
        return const <DiagnosticQuickFix>[];
      }
      return [
        DiagnosticQuickFix(
          label:
              'Remove extra argument${arguments.length - signature.parameterCount == 1 ? '' : 's'}',
          detail:
              'Rewrite `${signature.name}` arguments to match the imported '
              'signature.',
          edits: [
            FormattingEdit(
              range: call.argumentRange,
              newText: arguments
                  .take(signature.parameterCount)
                  .map((argument) => argument.text.trim())
                  .join(', '),
            ),
          ],
        ),
      ];
    }

    if (diagnostic.code == 'duplicate-named-argument') {
      final duplicateArgument = _argumentSliceContainingRange(
        arguments,
        diagnostic.range,
      );
      if (duplicateArgument == null) {
        return const <DiagnosticQuickFix>[];
      }
      final argumentName = document.text.substring(
        diagnostic.range.start,
        diagnostic.range.end,
      );
      return [
        DiagnosticQuickFix(
          label: 'Remove duplicate `$argumentName` argument',
          detail:
              'Delete the duplicate named argument from imported function '
              '`${signature.name}`.',
          edits: [
            FormattingEdit(
              range: call.argumentRange,
              newText: _argumentTextWithoutSlice(arguments, duplicateArgument),
            ),
          ],
        ),
      ];
    }

    if (diagnostic.code == 'unknown-named-argument') {
      final argumentName = document.text.substring(
        diagnostic.range.start,
        diagnostic.range.end,
      );
      final suggestion = _closestProjectParameterName(
        argumentName,
        signature.parameters.map((parameter) => parameter.name),
      );
      if (suggestion == null) {
        return const <DiagnosticQuickFix>[];
      }
      return [
        DiagnosticQuickFix(
          label: 'Change argument name to `$suggestion`',
          detail:
              'Rename the argument to match imported function '
              '`${signature.name}`.',
          edits: [FormattingEdit(range: diagnostic.range, newText: suggestion)],
        ),
      ];
    }

    return const <DiagnosticQuickFix>[];
  }

  _ProjectFunctionCall? _projectCallForDiagnosticRange(
    String source,
    SourceRange range,
  ) {
    for (final call in _projectFunctionCalls(source)) {
      if (call.argumentRange.intersects(range)) {
        return call;
      }
    }
    return null;
  }

  StyioFunctionSignature? _uniqueImportedSignatureForCall({
    required String documentId,
    required _ProjectFunctionCall call,
    required StyioProjectAnalysis analysis,
  }) {
    final definitions = analysis.symbolSnapshot
        .definitionsVisibleFrom(documentId: documentId, name: call.name)
        .where(
          (definition) =>
              definition.kind == StyioProjectSymbolKind.function &&
              definition.documentId != documentId,
        )
        .toList(growable: false);
    if (definitions.length != 1) {
      return null;
    }
    return _signatureForDefinition(
      analysis.signatureSnapshot,
      definitions.single,
    );
  }

  _ArgumentSlice? _argumentSliceContainingRange(
    List<_ArgumentSlice> arguments,
    SourceRange range,
  ) {
    for (final argument in arguments) {
      if (argument.range.intersects(range)) {
        return argument;
      }
    }
    return null;
  }

  String _argumentTextWithoutSlice(
    List<_ArgumentSlice> arguments,
    _ArgumentSlice removed,
  ) {
    return [
      for (final argument in arguments)
        if (argument.range.start != removed.range.start ||
            argument.range.end != removed.range.end)
          argument.text.trim(),
    ].join(', ');
  }

  String? _closestProjectParameterName(
    String name,
    Iterable<String> candidates,
  ) {
    _ImportTargetSuggestion? best;
    for (final candidate in candidates) {
      final distance = _editDistance(name, candidate);
      final threshold = (candidate.length / 3).ceil().clamp(1, 3);
      if (distance > threshold) {
        continue;
      }
      if (best == null ||
          distance < best.distance ||
          (distance == best.distance && candidate.compareTo(best.target) < 0)) {
        best = _ImportTargetSuggestion(target: candidate, distance: distance);
      }
    }
    return best?.target;
  }

  List<DiagnosticQuickFix> _quickFixesForImportedTaskAwaitMismatch(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final actualType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'returns',
    );
    if (actualType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final typeRange = _awaitBindingTypeRange(document.text, diagnostic.range);
    if (typeRange == null) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Change await binding type to $actualType',
        detail:
            'Update the await binding type to match the imported task result.',
        edits: [FormattingEdit(range: typeRange, newText: actualType)],
      ),
    ];
  }

  List<DiagnosticQuickFix> _quickFixesForImportedMissingTaskReturnValue({
    required List<DocumentState> documents,
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
  }) {
    final source = document.text;
    final taskName = _firstBacktickCaptureAfter(
      diagnostic.diagnostic.message,
      'Task',
    );
    if (taskName == null ||
        diagnostic.diagnostic.range.start < 0 ||
        diagnostic.diagnostic.range.end > source.length ||
        diagnostic.diagnostic.range.start >= diagnostic.diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    final expectedType = _uniqueImportedAwaitBindingTypeForTask(
      documents: documents,
      definitionDocumentId: document.documentId,
      taskName: taskName,
    );
    final replacement = expectedType == null
        ? null
        : _defaultLiteralForProjectType(expectedType);
    if (replacement == null) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Insert imported task return expression',
        detail:
            'Insert a default `$expectedType` expression in '
            '`${document.documentId}` from project await context.',
        edits: [
          FormattingEdit(
            range: SourceRange(
              start: diagnostic.diagnostic.range.end,
              end: diagnostic.diagnostic.range.end,
            ),
            newText: ' $replacement',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _quickFixesForImportedUnresolvedTaskReturnValue({
    required List<DocumentState> documents,
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
  }) {
    final source = document.text;
    final taskName = _firstBacktickCaptureAfter(
      diagnostic.diagnostic.message,
      'Task',
    );
    final valueName = _firstBacktickCaptureAfter(
      diagnostic.diagnostic.message,
      'value',
    );
    if (taskName == null ||
        valueName == null ||
        diagnostic.diagnostic.range.start < 0 ||
        diagnostic.diagnostic.range.end > source.length ||
        diagnostic.diagnostic.range.start >= diagnostic.diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    final expectedType = _uniqueImportedAwaitBindingTypeForTask(
      documents: documents,
      definitionDocumentId: document.documentId,
      taskName: taskName,
    );
    final replacement = expectedType == null
        ? null
        : _defaultLiteralForProjectType(expectedType);
    if (replacement == null) {
      return const <DiagnosticQuickFix>[];
    }

    final indent = _lineIndentAt(source, diagnostic.diagnostic.range.start);
    return [
      DiagnosticQuickFix(
        label: 'Create imported task local binding `$valueName`',
        detail:
            'Create `$valueName` in `${document.documentId}` using the '
            'project await type `$expectedType`.',
        edits: [
          FormattingEdit(
            range: _lineInsertionRange(
              source,
              diagnostic.diagnostic.range.start,
            ),
            newText: '$indent$valueName = $replacement\n',
          ),
        ],
      ),
    ];
  }

  String? _uniqueImportedAwaitBindingTypeForTask({
    required Iterable<DocumentState> documents,
    required String definitionDocumentId,
    required String taskName,
  }) {
    final types = _importedAwaitBindingTypesForTask(
      documents: documents,
      definitionDocumentId: definitionDocumentId,
      taskName: taskName,
    );
    return types.length == 1 ? types.single : null;
  }

  Set<String> _importedAwaitBindingTypesForTask({
    required Iterable<DocumentState> documents,
    required String definitionDocumentId,
    required String taskName,
  }) {
    final escapedTaskName = RegExp.escape(taskName);
    final awaitPattern = RegExp(
      r'\?\|\s*'
      '$escapedTaskName'
      r'\s*->\s*[A-Za-z_][A-Za-z0-9_]*\s*:\s*'
      r'([A-Za-z_][A-Za-z0-9_]*)',
    );
    final types = <String>{};
    for (final document in documents) {
      if (document.documentId == definitionDocumentId) {
        continue;
      }
      if (!_documentImportsDefinition(document, definitionDocumentId)) {
        continue;
      }
      for (final match in awaitPattern.allMatches(document.text)) {
        if (_isOffsetInIgnoredText(document.text, match.start)) {
          continue;
        }
        types.add(match.group(1)!);
      }
    }
    return Set<String>.unmodifiable(types);
  }

  bool _documentImportsDefinition(
    DocumentState document,
    String definitionDocumentId,
  ) {
    return _projectDocumentIndex(document).imports.any(
      (directive) =>
          !_isExternalImport(directive.target) &&
          _resolveImportTarget(directive.target, [definitionDocumentId]) ==
              definitionDocumentId,
    );
  }

  MapEntry<String, FormattingEdit>? _workspaceMissingTaskReturnEdit({
    required Map<String, DocumentState> documentsById,
    required StyioProjectAnalysis analysis,
    required StyioProjectDiagnostic diagnostic,
  }) {
    final document = documentsById[diagnostic.documentId];
    if (document == null ||
        diagnostic.diagnostic.range.start < 0 ||
        diagnostic.diagnostic.range.end > document.length ||
        diagnostic.diagnostic.range.start >= diagnostic.diagnostic.range.end) {
      return null;
    }

    final taskName = document.text.substring(
      diagnostic.diagnostic.range.start,
      diagnostic.diagnostic.range.end,
    );
    final expectedType = _missingTaskReturnExpectedType(
      diagnostic.diagnostic.message,
    );
    final replacement = expectedType == null
        ? null
        : _defaultLiteralForProjectType(expectedType);
    if (replacement == null) {
      return null;
    }

    final definitions = analysis.symbolSnapshot
        .definitionsVisibleFrom(
          documentId: diagnostic.documentId,
          name: taskName,
        )
        .where((definition) => definition.kind == StyioProjectSymbolKind.task)
        .toList(growable: false);
    if (definitions.length != 1) {
      return null;
    }

    final definition = definitions.single;
    final targetDocument = documentsById[definition.documentId];
    if (targetDocument == null) {
      return null;
    }
    final awaitTypes = _importedAwaitBindingTypesForTask(
      documents: documentsById.values,
      definitionDocumentId: definition.documentId,
      taskName: taskName,
    );
    if (awaitTypes.length > 1) {
      return null;
    }
    final edit = _taskReturnInsertionEdit(
      source: targetDocument.text,
      nameRange: definition.range,
      replacement: replacement,
    );
    if (edit == null) {
      return null;
    }
    return MapEntry(definition.documentId, edit);
  }

  MapEntry<String, FormattingEdit>? _workspaceInvalidTaskReturnExpressionEdit({
    required Map<String, DocumentState> documentsById,
    required StyioProjectAnalysis analysis,
    required StyioProjectDiagnostic diagnostic,
  }) {
    final document = documentsById[diagnostic.documentId];
    if (document == null) {
      return null;
    }

    final taskName = _identifierTextForRange(
      document.text,
      diagnostic.diagnostic.range,
    );
    if (taskName == null) {
      return null;
    }

    final definitions = analysis.symbolSnapshot
        .definitionsVisibleFrom(
          documentId: diagnostic.documentId,
          name: taskName,
        )
        .where((definition) => definition.kind == StyioProjectSymbolKind.task)
        .toList(growable: false);
    if (definitions.length != 1) {
      return null;
    }

    final definition = definitions.single;
    final targetDocument = documentsById[definition.documentId];
    if (targetDocument == null) {
      return null;
    }

    final expectedTypeFromMessage = _missingTaskReturnExpectedType(
      diagnostic.diagnostic.message,
    );
    final expectedTypeFromAwaitContext = _uniqueImportedAwaitBindingTypeForTask(
      documents: documentsById.values,
      definitionDocumentId: definition.documentId,
      taskName: taskName,
    );
    if (expectedTypeFromAwaitContext == null) {
      return null;
    }
    if (expectedTypeFromMessage != null &&
        expectedTypeFromMessage != expectedTypeFromAwaitContext) {
      return null;
    }
    final expectedType =
        expectedTypeFromMessage ?? expectedTypeFromAwaitContext;
    final replacement = _defaultLiteralForProjectType(expectedType);
    if (replacement == null) {
      return null;
    }

    final edit = _taskInvalidReturnReplacementEdit(
      source: targetDocument.text,
      nameRange: definition.range,
      replacement: replacement,
    );
    if (edit == null) {
      return null;
    }
    return MapEntry(definition.documentId, edit);
  }

  String? _missingTaskReturnExpectedType(String message) {
    final bindingText = _firstBacktickCaptureAfter(message, 'for');
    final colon = bindingText?.lastIndexOf(':') ?? -1;
    if (bindingText == null || colon < 0) {
      return null;
    }
    final expectedType = bindingText.substring(colon + 1).trim();
    return expectedType.isEmpty ? null : expectedType;
  }

  FormattingEdit? _taskReturnInsertionEdit({
    required String source,
    required SourceRange nameRange,
    required String replacement,
  }) {
    if (nameRange.start < 0 ||
        nameRange.end > source.length ||
        nameRange.start >= nameRange.end) {
      return null;
    }
    final lineEndIndex = source.indexOf('\n', nameRange.end);
    final declarationLineEnd = lineEndIndex < 0 ? source.length : lineEndIndex;
    final openingBrace = source.indexOf('{', nameRange.end);
    if (openingBrace < 0 || openingBrace > declarationLineEnd) {
      return null;
    }
    final closingBrace = _matchingBraceInSource(source, openingBrace);
    if (closingBrace == null) {
      return null;
    }

    final closingIndent = _lineIndentBefore(source, closingBrace);
    final returnIndent = '$closingIndent  ';
    final insertText = closingBrace > 0 && source[closingBrace - 1] == '\n'
        ? '$returnIndent<| $replacement\n'
        : '\n$returnIndent<| $replacement\n$closingIndent';
    return FormattingEdit(
      range: SourceRange(start: closingBrace, end: closingBrace),
      newText: insertText,
    );
  }

  FormattingEdit? _taskInvalidReturnReplacementEdit({
    required String source,
    required SourceRange nameRange,
    required String replacement,
  }) {
    if (nameRange.start < 0 ||
        nameRange.end > source.length ||
        nameRange.start >= nameRange.end) {
      return null;
    }
    final lineEndIndex = source.indexOf('\n', nameRange.end);
    final declarationLineEnd = lineEndIndex < 0 ? source.length : lineEndIndex;
    final openingBrace = source.indexOf('{', nameRange.end);
    if (openingBrace < 0 || openingBrace > declarationLineEnd) {
      return null;
    }
    final closingBrace = _matchingBraceInSource(source, openingBrace);
    if (closingBrace == null) {
      return null;
    }

    final bodyStart = openingBrace + 1;
    final scan = _taskReturnInference.scan(
      body: source.substring(bodyStart, closingBrace),
      bodyStartOffset: bodyStart,
      functionReturnTypes: _localFunctionReturnTypes(source),
    );
    if (scan.invalidExpressions.length != 1) {
      return null;
    }
    return FormattingEdit(
      range: scan.invalidExpressions.single.range,
      newText: replacement,
    );
  }

  SourceRange _lineInsertionRange(String source, int offset) {
    final lineStart = _lineStartAt(source, offset);
    return SourceRange(start: lineStart, end: lineStart);
  }

  String _lineIndentAt(String source, int offset) {
    final lineStart = _lineStartAt(source, offset);
    var index = lineStart;
    while (index < source.length) {
      final char = source[index];
      if (char != ' ' && char != '\t') {
        break;
      }
      index += 1;
    }
    return source.substring(lineStart, index);
  }

  int _lineStartAt(String source, int offset) {
    final bounded = offset < 0
        ? 0
        : offset > source.length
        ? source.length
        : offset;
    if (bounded == 0) {
      return 0;
    }
    final previousNewline = source.lastIndexOf('\n', bounded - 1);
    return previousNewline < 0 ? 0 : previousNewline + 1;
  }

  String? _firstBacktickCaptureAfter(String message, String marker) {
    final markerIndex = message.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    final match = RegExp(
      r'`([^`]+)`',
    ).firstMatch(message.substring(markerIndex + marker.length));
    return match?.group(1);
  }

  String? _defaultLiteralForProjectType(String typeName) {
    final normalized = typeName.trim();
    if (normalized == 'bool') {
      return 'false';
    }
    if (normalized == 'string' || normalized == 'String') {
      return '""';
    }
    if (normalized.startsWith('f')) {
      return '0.0';
    }
    if (normalized.startsWith('i') || normalized.startsWith('u')) {
      return '0';
    }
    return null;
  }

  SourceRange _trimmedRange(String source, SourceRange range) {
    var start = range.start.clamp(0, source.length);
    var end = range.end.clamp(start, source.length);
    while (start < end && source.codeUnitAt(start) <= 0x20) {
      start += 1;
    }
    while (end > start && source.codeUnitAt(end - 1) <= 0x20) {
      end -= 1;
    }
    return SourceRange(start: start, end: end);
  }

  SourceRange? _awaitBindingTypeRange(String source, SourceRange bindingRange) {
    if (bindingRange.start < 0 ||
        bindingRange.end > source.length ||
        bindingRange.start >= bindingRange.end) {
      return null;
    }
    final lineEndIndex = source.indexOf('\n', bindingRange.end);
    final lineEnd = lineEndIndex < 0 ? source.length : lineEndIndex;
    final colon = source.indexOf(':', bindingRange.end);
    if (colon < 0 || colon >= lineEnd) {
      return null;
    }
    var typeStart = colon + 1;
    while (typeStart < lineEnd && source.codeUnitAt(typeStart) <= 0x20) {
      typeStart += 1;
    }
    var typeEnd = typeStart;
    while (typeEnd < lineEnd &&
        _isIdentifierCodeUnit(source.codeUnitAt(typeEnd))) {
      typeEnd += 1;
    }
    if (typeStart >= typeEnd) {
      return null;
    }
    return SourceRange(start: typeStart, end: typeEnd);
  }

  int _editDistance(String left, String right) {
    if (left == right) {
      return 0;
    }
    if (left.isEmpty) {
      return right.length;
    }
    if (right.isEmpty) {
      return left.length;
    }

    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = leftIndex + 1;
      for (var rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
        final substitutionCost =
            left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1;
        final deletion = previous[rightIndex + 1] + 1;
        final insertion = current[rightIndex] + 1;
        final substitution = previous[rightIndex] + substitutionCost;
        current[rightIndex + 1] = [
          deletion,
          insertion,
          substitution,
        ].reduce((value, element) => value < element ? value : element);
      }
      previous = current;
    }
    return previous.last;
  }

  List<DiagnosticQuickFix> _quickFixesForMissingProjectImport({
    required List<DocumentState> documents,
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
    required StyioProjectAnalysis analysis,
  }) {
    final name = _identifierTextForRange(
      document.text,
      diagnostic.diagnostic.range,
    );
    if (name == null) {
      return const <DiagnosticQuickFix>[];
    }

    if (analysis.symbolSnapshot
        .definitionsVisibleFrom(documentId: document.documentId, name: name)
        .isNotEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    final existingTargets = analysis.symbolSnapshot
        .importTargetsFor(document.documentId)
        .toSet();
    final targetsByDocument = <String, String>{};
    for (final definition in analysis.symbolSnapshot.definitionsFor(name)) {
      if (definition.documentId == document.documentId) {
        continue;
      }
      final target = _canonicalImportTarget(definition.documentId);
      if (existingTargets.contains(target)) {
        continue;
      }
      targetsByDocument[definition.documentId] = target;
    }
    final targets = targetsByDocument.values.toList(growable: false)..sort();
    return [
      for (final target in targets)
        DiagnosticQuickFix(
          label: 'Import `$name` from $target',
          detail: 'Add a workspace import that declares `$name`.',
          edits: [_addProjectImportEdit(document.text, target)],
        ),
    ];
  }

  List<DiagnosticQuickFix> _quickFixesForAmbiguousProjectImport({
    required List<DocumentState> documents,
    required DocumentState document,
    required StyioProjectDiagnostic diagnostic,
    required StyioProjectAnalysis analysis,
  }) {
    final name = _identifierTextForRange(
      document.text,
      diagnostic.diagnostic.range,
    );
    if (name == null) {
      return const <DiagnosticQuickFix>[];
    }

    final documentsById = {
      for (final workspaceDocument in documents)
        workspaceDocument.documentId: workspaceDocument,
    };
    final usedNames = _identifierNamesOutsideImports(document.text);
    final importDirectives = _parseImports(document.text);
    final fixes = <DiagnosticQuickFix>[];
    final offeredTargets = <String>{};

    for (final directive in importDirectives) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        continue;
      }
      final declaresAmbiguousName = analysis.symbolSnapshot
          .definitionsFor(name)
          .any((definition) => definition.documentId == importedDocumentId);
      if (!declaresAmbiguousName) {
        continue;
      }

      final exportedNames = _projectExportedNames(
        analysis.symbolSnapshot,
        importedDocumentId,
      );
      final unsafeUsedExports = exportedNames
          .where(usedNames.contains)
          .where((exportedName) => exportedName != name)
          .where(
            (exportedName) => !_projectNameRemainsVisibleWithoutImport(
              name: exportedName,
              currentDocumentId: document.documentId,
              removedDirective: directive,
              importDirectives: importDirectives,
              documentIds: documentsById.keys,
              symbolSnapshot: analysis.symbolSnapshot,
            ),
          );
      if (unsafeUsedExports.isNotEmpty ||
          !offeredTargets.add(directive.target)) {
        continue;
      }

      fixes.add(
        DiagnosticQuickFix(
          label: 'Remove import `${directive.target}`',
          detail:
              'Delete this import to resolve ambiguous `$name` without '
              'removing other referenced symbols.',
          edits: [
            FormattingEdit(
              range: _lineRemovalRange(document.text, directive.targetRange),
              newText: '',
            ),
          ],
        ),
      );
    }

    return fixes;
  }

  bool _projectNameRemainsVisibleWithoutImport({
    required String name,
    required String currentDocumentId,
    required _StyioImportDirective removedDirective,
    required List<_StyioImportDirective> importDirectives,
    required Iterable<String> documentIds,
    required StyioProjectSymbolSnapshot symbolSnapshot,
  }) {
    for (final definition in symbolSnapshot.definitionsFor(name)) {
      if (definition.documentId == currentDocumentId) {
        return true;
      }
    }

    for (final directive in importDirectives) {
      if (directive.target == removedDirective.target &&
          directive.targetRange.start == removedDirective.targetRange.start &&
          directive.targetRange.end == removedDirective.targetRange.end) {
        continue;
      }
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentIds,
      );
      if (importedDocumentId == null) {
        continue;
      }
      if (symbolSnapshot
          .definitionsFor(name)
          .any((definition) => definition.documentId == importedDocumentId)) {
        return true;
      }
    }
    return false;
  }

  Set<String> _projectExportedNames(
    StyioProjectSymbolSnapshot symbolSnapshot,
    String documentId,
  ) {
    return {
      for (final signature in symbolSnapshot.functionsFor(documentId))
        signature.name,
      for (final resource in symbolSnapshot.resourcesFor(documentId))
        resource.name,
      for (final task in symbolSnapshot.tasksFor(documentId)) task.name,
    };
  }

  String? _identifierTextForRange(String source, SourceRange range) {
    if (range.start < 0 ||
        range.end > source.length ||
        range.start >= range.end) {
      return null;
    }
    final text = source.substring(range.start, range.end);
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(text)) {
      return text;
    }
    final resourceText = text.trim();
    if (resourceText.startsWith('@')) {
      final name = resourceText.substring(1).trim();
      if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
        return name;
      }
    }
    return null;
  }

  FormattingEdit _addProjectImportEdit(String source, String target) {
    final offset = _projectImportInsertionOffset(source);
    return FormattingEdit(
      range: SourceRange(start: offset, end: offset),
      newText: '@import { $target }\n',
    );
  }

  int _projectImportInsertionOffset(String source) {
    var lineStart = 0;
    var insertionOffset = 0;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      if (!line.trimLeft().startsWith('@import')) {
        break;
      }
      insertionOffset = newline < 0 ? lineEnd : newline + 1;
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return insertionOffset;
  }

  SourceRange _lineRemovalRange(String source, SourceRange range) {
    final normalizedStart = range.start.clamp(0, source.length);
    final normalizedEnd = range.end.clamp(normalizedStart, source.length);
    final previousNewline = normalizedStart <= 0
        ? -1
        : source.lastIndexOf('\n', normalizedStart - 1);
    final lineStart = previousNewline + 1;
    final nextNewline = source.indexOf('\n', normalizedEnd);
    if (nextNewline >= 0) {
      return SourceRange(start: lineStart, end: nextNewline + 1);
    }
    if (lineStart > 0) {
      return SourceRange(start: lineStart - 1, end: source.length);
    }
    return SourceRange(start: 0, end: source.length);
  }

  SourceRange _declarationRemovalRange(String source, SourceRange nameRange) {
    final lineRange = _lineRemovalRange(source, nameRange);
    final lineEnd = source.indexOf('\n', nameRange.end);
    final declarationLineEnd = lineEnd < 0 ? source.length : lineEnd;
    final lineText = source.substring(lineRange.start, declarationLineEnd);
    if (!lineText.trimLeft().startsWith('fn ')) {
      return lineRange;
    }

    final openingBrace = source.indexOf('{', lineRange.start);
    if (openingBrace < 0 || openingBrace > declarationLineEnd) {
      return lineRange;
    }
    final closingBrace = _matchingBraceInSource(source, openingBrace);
    if (closingBrace == null) {
      return lineRange;
    }
    final afterClosingNewline = source.indexOf('\n', closingBrace + 1);
    return SourceRange(
      start: lineRange.start,
      end: afterClosingNewline < 0 ? source.length : afterClosingNewline + 1,
    );
  }

  int? _matchingBraceInSource(String source, int openingBrace) {
    if (openingBrace < 0 ||
        openingBrace >= source.length ||
        source[openingBrace] != '{') {
      return null;
    }
    var depth = 0;
    for (var index = openingBrace; index < source.length; index += 1) {
      final char = source[index];
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  String _lineIndentBefore(String source, int offset) {
    final lineStart = offset <= 0
        ? 0
        : source.lastIndexOf('\n', offset - 1) + 1;
    final buffer = StringBuffer();
    for (var index = lineStart; index < offset; index += 1) {
      final char = source[index];
      if (char != ' ' && char != '\t') {
        return '';
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  StyioProjectSymbolSnapshot _symbolSnapshot({
    required List<DocumentState> documents,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, _StyioProjectDocumentIndex> projectIndexes,
  }) {
    return StyioProjectSymbolSnapshot._(
      functionsByDocument: {
        for (final entry in projectIndexes.entries)
          entry.key: entry.value.functions,
      },
      resourcesByDocument: {
        for (final entry in projectIndexes.entries)
          entry.key: entry.value.resources,
      },
      tasksByDocument: {
        for (final entry in projectIndexes.entries)
          entry.key: entry.value.tasks,
      },
      sourceByDocument: {
        for (final document in documents) document.documentId: document.text,
      },
      importsByDocument: importsByDocument,
    );
  }

  String? _identifierAt(String source, int offset) {
    if (source.isEmpty) {
      return null;
    }
    final normalizedOffset = offset == source.length ? offset - 1 : offset;
    if (normalizedOffset < 0 || normalizedOffset >= source.length) {
      return null;
    }
    if (_isOffsetInIgnoredText(source, normalizedOffset)) {
      return null;
    }
    if (!_isIdentifierCodeUnit(source.codeUnitAt(normalizedOffset))) {
      return null;
    }
    var start = normalizedOffset;
    while (start > 0 && _isIdentifierCodeUnit(source.codeUnitAt(start - 1))) {
      start -= 1;
    }
    var end = normalizedOffset + 1;
    while (end < source.length &&
        _isIdentifierCodeUnit(source.codeUnitAt(end))) {
      end += 1;
    }
    return source.substring(start, end);
  }

  String _identifierPrefixBefore(String source, int offset) {
    final normalizedOffset = offset.clamp(0, source.length);
    var start = normalizedOffset;
    while (start > 0 && _isIdentifierCodeUnit(source.codeUnitAt(start - 1))) {
      start -= 1;
    }
    return source.substring(start, normalizedOffset);
  }

  bool _isOffsetInImportDirective(String source, int offset) {
    if (source.isEmpty) {
      return false;
    }
    final normalizedOffset = offset == source.length ? offset - 1 : offset;
    if (normalizedOffset < 0 || normalizedOffset >= source.length) {
      return false;
    }
    final lineSearchStart = normalizedOffset == 0 ? 0 : normalizedOffset - 1;
    final lineStart = source.lastIndexOf('\n', lineSearchStart) + 1;
    final lineEnd = source.indexOf('\n', normalizedOffset);
    final absoluteLineEnd = lineEnd < 0 ? source.length : lineEnd;
    final line = source.substring(lineStart, absoluteLineEnd);
    final trimmedLeft = line.replaceFirst(RegExp(r'^\s+'), '');
    if (!trimmedLeft.startsWith('@import')) {
      return false;
    }
    final importStart = lineStart + line.length - trimmedLeft.length;
    return normalizedOffset >= importStart &&
        normalizedOffset <= absoluteLineEnd;
  }

  _StyioImportCompletionContext? _importCompletionContext(
    String source,
    int offset,
  ) {
    final normalizedOffset = offset.clamp(0, source.length);
    final lineSearchStart = normalizedOffset == 0 ? 0 : normalizedOffset - 1;
    final lineStart = source.lastIndexOf('\n', lineSearchStart) + 1;
    final newline = source.indexOf('\n', normalizedOffset);
    final lineEnd = newline < 0 ? source.length : newline;
    final line = source.substring(lineStart, lineEnd);
    final trimmedLeft = line.replaceFirst(RegExp(r'^\s+'), '');
    final leadingWhitespace = line.length - trimmedLeft.length;
    if (!trimmedLeft.startsWith('@import')) {
      return null;
    }

    final importStart = lineStart + leadingWhitespace;
    final openBrace = line.indexOf('{', leadingWhitespace);
    final closeBrace = line.lastIndexOf('}');
    final targetStart = openBrace >= 0
        ? lineStart + openBrace + 1
        : importStart + '@import'.length;
    final targetEnd = openBrace >= 0 && closeBrace > openBrace
        ? lineStart + closeBrace
        : lineEnd;
    if (normalizedOffset < targetStart || normalizedOffset > targetEnd) {
      return null;
    }
    final prefixStart =
        targetStart +
        source.substring(targetStart, normalizedOffset).length -
        source.substring(targetStart, normalizedOffset).trimLeft().length;
    final prefix = source.substring(prefixStart, normalizedOffset).trimRight();
    return _StyioImportCompletionContext(
      prefix: prefix,
      replacementRange: SourceRange(start: prefixStart, end: normalizedOffset),
    );
  }

  String _canonicalImportTarget(String documentId) {
    return documentId.endsWith('.styio')
        ? documentId.substring(0, documentId.length - '.styio'.length)
        : documentId;
  }

  StyioFunctionSignature? _signatureForDefinition(
    StyioProjectSignatureSnapshot signatureSnapshot,
    StyioProjectSymbolDefinition definition,
  ) {
    for (final signature in signatureSnapshot.functionsFor(
      definition.documentId,
    )) {
      if (signature.name == definition.name &&
          signature.range.start == definition.range.start &&
          signature.range.end == definition.range.end) {
        return signature;
      }
    }
    return null;
  }

  String _signatureDisplayText(StyioFunctionSignature signature) {
    final parameters = signature.parameters
        .map((parameter) {
          final typed = parameter.type.isEmpty
              ? parameter.name
              : '${parameter.name}: ${parameter.type}';
          return parameter.hasDefault ? '$typed = ...' : typed;
        })
        .join(', ');
    final returnType = signature.returnType == null
        ? ''
        : ': ${signature.returnType}';
    return '${signature.name}($parameters)$returnType';
  }

  Set<String> _providedProjectParameterNames({
    required StyioFunctionSignature signature,
    required List<_ArgumentSlice> arguments,
  }) {
    final providedNames = <String>{};
    final parameterNames = signature.parameters
        .map((parameter) => parameter.name)
        .toSet();
    var positionalIndex = 0;
    for (final argument in arguments) {
      final namedSeparator = _topLevelNamedArgumentSeparator(argument.text);
      if (namedSeparator != null) {
        final name = argument.text.substring(0, namedSeparator).trim();
        if (parameterNames.contains(name)) {
          providedNames.add(name);
        }
        continue;
      }
      while (positionalIndex < signature.parameters.length &&
          providedNames.contains(signature.parameters[positionalIndex].name)) {
        positionalIndex += 1;
      }
      if (positionalIndex < signature.parameters.length) {
        providedNames.add(signature.parameters[positionalIndex].name);
      }
      positionalIndex += 1;
    }
    return providedNames;
  }

  _ProjectFunctionCall? _projectFunctionCallAt(String source, int offset) {
    _ProjectFunctionCall? best;
    final pattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\(');
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start) ||
          _isFunctionDeclarationCallMatch(source, match.start)) {
        continue;
      }
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      final opening = source.indexOf('(', nameStart + name.length);
      if (opening < 0 ||
          _isHashFunctionDeclarationCallMatch(
            source: source,
            nameStart: nameStart,
            openingParenthesis: opening,
          )) {
        continue;
      }
      final closing = _matchingParenthesis(source, opening);
      if (closing == null || offset < opening || offset > closing) {
        continue;
      }
      if (best != null && opening <= best.openingParenthesis) {
        continue;
      }
      best = _ProjectFunctionCall(
        name: name,
        callableRange: SourceRange(
          start: nameStart,
          end: nameStart + name.length,
        ),
        openingParenthesis: opening,
        closingParenthesis: closing,
        argumentText: source.substring(opening + 1, closing),
        argumentRange: SourceRange(start: opening + 1, end: closing),
      );
    }
    return best;
  }

  List<_ProjectFunctionCall> _projectFunctionCalls(String source) {
    final calls = <_ProjectFunctionCall>[];
    final pattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*\(');
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start) ||
          _isFunctionDeclarationCallMatch(source, match.start)) {
        continue;
      }
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      final opening = source.indexOf('(', nameStart + name.length);
      if (opening < 0 ||
          _isHashFunctionDeclarationCallMatch(
            source: source,
            nameStart: nameStart,
            openingParenthesis: opening,
          )) {
        continue;
      }
      final closing = _matchingParenthesis(source, opening);
      if (closing == null) {
        continue;
      }
      calls.add(
        _ProjectFunctionCall(
          name: name,
          callableRange: SourceRange(
            start: nameStart,
            end: nameStart + name.length,
          ),
          openingParenthesis: opening,
          closingParenthesis: closing,
          argumentText: source.substring(opening + 1, closing),
          argumentRange: SourceRange(start: opening + 1, end: closing),
        ),
      );
    }
    return calls;
  }

  bool _isHashFunctionDeclarationCallMatch({
    required String source,
    required int nameStart,
    required int openingParenthesis,
  }) {
    final lineSearchStart = nameStart == 0 ? 0 : nameStart - 1;
    final lineStart = source.lastIndexOf('\n', lineSearchStart) + 1;
    final prefix = source.substring(lineStart, nameStart).trimLeft();
    final betweenNameAndParen = source.substring(nameStart, openingParenthesis);
    return prefix.startsWith('#') && betweenNameAndParen.contains(':=');
  }

  _ProjectNamedArgumentCompletionContext?
  _projectNamedArgumentCompletionContext({
    required String source,
    required _ProjectFunctionCall call,
    required int offset,
  }) {
    if (offset < call.argumentRange.start || offset > call.argumentRange.end) {
      return null;
    }
    final relativeOffset = offset - call.argumentRange.start;
    var segmentStart = 0;
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var index = 0;
    while (index < call.argumentText.length) {
      final char = call.argumentText[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(call.argumentText, index);
        continue;
      }
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth -= 1;
      } else if (char == '[') {
        bracketDepth += 1;
      } else if (char == ']') {
        bracketDepth -= 1;
      } else if (char == '{') {
        braceDepth += 1;
      } else if (char == '}') {
        braceDepth -= 1;
      } else if (char == ',' &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        if (relativeOffset <= index) {
          break;
        }
        segmentStart = index + 1;
      }
      index += 1;
    }
    final segmentEnd = index >= call.argumentText.length
        ? call.argumentText.length
        : index;
    final segmentAbsoluteStart = call.argumentRange.start + segmentStart;
    final segmentAbsoluteEnd = call.argumentRange.start + segmentEnd;
    final beforeCursor = source.substring(segmentAbsoluteStart, offset);
    if (_topLevelNamedArgumentSeparator(beforeCursor) != null) {
      return null;
    }
    var replacementStart = offset;
    while (replacementStart > segmentAbsoluteStart &&
        _isIdentifierCodeUnit(source.codeUnitAt(replacementStart - 1))) {
      replacementStart -= 1;
    }
    return _ProjectNamedArgumentCompletionContext(
      prefix: source.substring(replacementStart, offset),
      segmentRange: SourceRange(
        start: segmentAbsoluteStart,
        end: segmentAbsoluteEnd,
      ),
      replacementRange: SourceRange(start: replacementStart, end: offset),
    );
  }

  int _activeProjectParameterIndex({
    required _ProjectFunctionCall call,
    required int offset,
  }) {
    var activeParameterIndex = 0;
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var index = 0;
    while (index < call.argumentText.length) {
      final absoluteOffset = call.argumentRange.start + index;
      if (absoluteOffset >= offset) {
        break;
      }
      final char = call.argumentText[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(call.argumentText, index);
        continue;
      }
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth -= 1;
      } else if (char == '[') {
        bracketDepth += 1;
      } else if (char == ']') {
        bracketDepth -= 1;
      } else if (char == '{') {
        braceDepth += 1;
      } else if (char == '}') {
        braceDepth -= 1;
      } else if (char == ',' &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        activeParameterIndex += 1;
      }
      index += 1;
    }
    return activeParameterIndex;
  }

  List<InlayHint> _parameterInlayHintsForCall({
    required _ProjectFunctionCall call,
    required StyioFunctionSignature signature,
  }) {
    final hints = <InlayHint>[];
    final providedNames = <String>{};
    var positionalIndex = 0;
    for (final argument in _argumentSlices(
      call.argumentText,
      call.argumentRange.start,
    )) {
      final namedSeparator = _topLevelNamedArgumentSeparator(argument.text);
      if (namedSeparator != null) {
        providedNames.add(argument.text.substring(0, namedSeparator).trim());
        continue;
      }
      while (positionalIndex < signature.parameters.length &&
          providedNames.contains(signature.parameters[positionalIndex].name)) {
        positionalIndex += 1;
      }
      if (positionalIndex >= signature.parameters.length) {
        continue;
      }
      final parameter = signature.parameters[positionalIndex];
      positionalIndex += 1;
      providedNames.add(parameter.name);
      if (argument.text == parameter.name) {
        continue;
      }
      hints.add(
        InlayHint(
          label: '${parameter.name}:',
          kind: InlayHintKind.parameter,
          position: argument.range.start,
          range: argument.range,
        ),
      );
    }
    return hints;
  }

  CompletionItem _completionItemForDefinition(
    StyioProjectSymbolDefinition definition,
  ) {
    switch (definition.kind) {
      case StyioProjectSymbolKind.function:
        return CompletionItem(
          label: definition.name,
          kind: CompletionItemKind.function,
          insertText: '${definition.name}()',
          detail: definition.type == null
              ? 'function'
              : 'function: ${definition.type}',
        );
      case StyioProjectSymbolKind.resource:
        return CompletionItem(
          label: '@${definition.name}',
          kind: CompletionItemKind.variable,
          insertText: '@${definition.name}',
          detail: definition.type == null
              ? 'resource'
              : 'resource: ${definition.type}',
        );
      case StyioProjectSymbolKind.task:
        return CompletionItem(
          label: definition.name,
          kind: CompletionItemKind.variable,
          insertText: definition.name,
          detail: definition.type == null ? 'task' : 'task: ${definition.type}',
        );
    }
  }

  bool _isIdentifierCodeUnit(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x5f;
  }

  bool _isValidIdentifier(String name) {
    if (name.isEmpty || !_isIdentifierStartCodeUnit(name.codeUnitAt(0))) {
      return false;
    }
    for (var index = 1; index < name.length; index += 1) {
      if (!_isIdentifierCodeUnit(name.codeUnitAt(index))) {
        return false;
      }
    }
    return true;
  }

  bool _isIdentifierStartCodeUnit(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        codeUnit == 0x5f;
  }

  StyioDocumentAnalysis _analyzeDocument(DocumentState document) {
    final cachedAnalysis = _analysisCache?.lookup(document);
    if (cachedAnalysis != null) {
      return cachedAnalysis;
    }

    final analysis = _documentService.analyzeDocument(document);
    _analysisCache?.store(document, analysis);
    return analysis;
  }

  _StyioProjectDocumentIndex _projectDocumentIndex(DocumentState document) {
    final cachedIndex = _analysisCache?._lookupProjectIndex(document);
    if (cachedIndex != null) {
      return cachedIndex;
    }

    final index = _StyioProjectDocumentIndex(
      functions: _functionSignatures(document.text),
      resources: _resourceSymbols(document.text),
      tasks: _taskSymbols(document.text),
      imports: _parseImports(document.text),
    );
    _analysisCache?._storeProjectIndex(document, index);
    return index;
  }

  List<StyioProjectDiagnostic> _importCycleDiagnostics({
    required StyioProjectSymbolSnapshot symbolSnapshot,
    required Map<String, DocumentState> documentsById,
  }) {
    final edges = <String, List<String>>{
      for (final documentId in documentsById.keys) documentId: <String>[],
    };
    for (final entry in symbolSnapshot._importsByDocument.entries) {
      for (final directive in entry.value) {
        if (_isExternalImport(directive.target)) {
          continue;
        }
        final importedDocumentId = _resolveImportTarget(
          directive.target,
          documentsById.keys,
        );
        if (importedDocumentId != null) {
          edges[entry.key]!.add(importedDocumentId);
        }
      }
    }

    final diagnostics = <StyioProjectDiagnostic>[];
    final reported = <String>{};
    for (final entry in symbolSnapshot._importsByDocument.entries) {
      for (final directive in entry.value) {
        if (_isExternalImport(directive.target)) {
          continue;
        }
        final importedDocumentId = _resolveImportTarget(
          directive.target,
          documentsById.keys,
        );
        if (importedDocumentId == null) {
          continue;
        }
        if (!_hasImportPath(
          edges: edges,
          start: importedDocumentId,
          target: entry.key,
          visited: <String>{},
        )) {
          continue;
        }
        final key = '${entry.key}:${directive.targetRange.start}';
        if (!reported.add(key)) {
          continue;
        }
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: entry.key,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'import-cycle',
              message:
                  'Import `${directive.target}` participates in a cyclic '
                  'workspace import graph.',
              range: directive.targetRange,
            ),
          ),
        );
      }
    }
    return diagnostics;
  }

  List<StyioProjectDiagnostic> _conflictingTaskReturnContextDiagnostics({
    required List<DocumentState> documents,
    required Map<String, StyioDocumentAnalysis> analyses,
    required Map<String, _StyioProjectDocumentIndex> projectIndexes,
  }) {
    final diagnostics = <StyioProjectDiagnostic>[];
    final reported = <String>{};
    for (final document in documents) {
      final analysis = analyses[document.documentId];
      if (analysis == null) {
        continue;
      }
      for (final diagnostic in analysis.diagnostics) {
        if (diagnostic.code != 'missing-task-return-value' &&
            diagnostic.code != 'unresolved-task-return-value') {
          continue;
        }
        final taskName = _firstBacktickCaptureAfter(diagnostic.message, 'Task');
        if (taskName == null) {
          continue;
        }
        final key = '${document.documentId}:$taskName';
        if (!reported.add(key)) {
          continue;
        }
        final types = _importedAwaitBindingTypesForTask(
          documents: documents,
          definitionDocumentId: document.documentId,
          taskName: taskName,
        ).toList(growable: false)..sort();
        if (types.length < 2) {
          continue;
        }
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'conflicting-task-return-context',
              message:
                  'Task `$taskName` is awaited as conflicting result types: '
                  '${types.map((type) => '`$type`').join(', ')}.',
              range: diagnostic.range,
            ),
          ),
        );
      }

      final projectIndex = projectIndexes[document.documentId];
      if (projectIndex == null) {
        continue;
      }
      for (final task in projectIndex.tasks) {
        if (task.returnType != null) {
          continue;
        }
        final key = '${document.documentId}:${task.name}';
        if (!reported.add(key)) {
          continue;
        }
        final types = _importedAwaitBindingTypesForTask(
          documents: documents,
          definitionDocumentId: document.documentId,
          taskName: task.name,
        ).toList(growable: false)..sort();
        if (types.length < 2) {
          continue;
        }
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'conflicting-task-return-context',
              message:
                  'Task `${task.name}` is awaited as conflicting result '
                  'types: ${types.map((type) => '`$type`').join(', ')}.',
              range: task.range,
            ),
          ),
        );
      }
    }
    return diagnostics;
  }

  bool _hasImportPath({
    required Map<String, List<String>> edges,
    required String start,
    required String target,
    required Set<String> visited,
  }) {
    if (start == target) {
      return true;
    }
    if (!visited.add(start)) {
      return false;
    }
    for (final next in edges[start] ?? const <String>[]) {
      if (_hasImportPath(
        edges: edges,
        start: next,
        target: target,
        visited: visited,
      )) {
        return true;
      }
    }
    return false;
  }

  List<StyioProjectDiagnostic> _unusedImportDiagnostics({
    required DocumentState document,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, StyioDocumentAnalysis> analyses,
    required Map<String, DocumentState> documentsById,
  }) {
    final identifiers = _identifierNamesOutsideImports(document.text);
    final diagnostics = <StyioProjectDiagnostic>[];
    for (final directive in importsByDocument[document.documentId]!) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        continue;
      }
      final exportedNames = {
        for (final symbol in analyses[importedDocumentId]!.documentSymbols)
          symbol.name,
      };
      if (exportedNames.isEmpty ||
          exportedNames.any((name) => identifiers.contains(name))) {
        continue;
      }
      diagnostics.add(
        StyioProjectDiagnostic(
          documentId: document.documentId,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unused-import',
            message:
                'Import `${directive.target}` is not used by this document.',
            range: directive.targetRange,
          ),
        ),
      );
    }
    return diagnostics;
  }

  List<StyioProjectDiagnostic> _unusedExportedSymbolDiagnostics({
    required DocumentState document,
    required StyioProjectSymbolSnapshot symbolSnapshot,
  }) {
    final diagnostics = <StyioProjectDiagnostic>[];
    for (final definition in symbolSnapshot.definitionsVisibleFromDocument(
      document.documentId,
    )) {
      if (definition.documentId != document.documentId) {
        continue;
      }
      final references = symbolSnapshot.referencesFor(definition);
      if (references.any((reference) => !reference.isDefinition)) {
        continue;
      }
      diagnostics.add(
        StyioProjectDiagnostic(
          documentId: document.documentId,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unused-exported-symbol',
            message:
                '${definition.kind.name} `${definition.name}` is exported in the project but never referenced.',
            range: definition.range,
          ),
        ),
      );
    }
    return diagnostics;
  }

  Set<String> _identifierNamesOutsideImports(String source) {
    final identifiers = <String>{};
    for (final line in source.split('\n')) {
      if (line.trimLeft().startsWith('@import')) {
        continue;
      }
      for (final match in RegExp(
        r'\b[A-Za-z_][A-Za-z0-9_]*\b',
      ).allMatches(line)) {
        identifiers.add(match.group(0)!);
      }
    }
    return identifiers;
  }

  Map<String, List<DocumentSymbol>> _importedSymbolsFor({
    required String documentId,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, StyioDocumentAnalysis> analyses,
    required Map<String, DocumentState> documentsById,
    required List<StyioProjectDiagnostic> diagnostics,
  }) {
    final importedSymbols = <String, List<DocumentSymbol>>{};
    for (final directive in importsByDocument[documentId]!) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'unresolved-import',
              message:
                  'Import `${directive.target}` does not resolve to a workspace document.',
              range: directive.targetRange,
            ),
          ),
        );
        continue;
      }

      for (final symbol in analyses[importedDocumentId]!.documentSymbols) {
        importedSymbols
            .putIfAbsent(symbol.name, () => <DocumentSymbol>[])
            .add(symbol);
      }
    }
    return importedSymbols;
  }

  Map<String, List<StyioResourceSymbol>> _importedResourcesFor({
    required String documentId,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, DocumentState> documentsById,
    required StyioProjectSymbolSnapshot symbolSnapshot,
  }) {
    final importedResources = <String, List<StyioResourceSymbol>>{};
    for (final directive in importsByDocument[documentId]!) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        continue;
      }
      for (final resource in symbolSnapshot.resourcesFor(importedDocumentId)) {
        importedResources
            .putIfAbsent(resource.name, () => <StyioResourceSymbol>[])
            .add(resource);
      }
    }
    return importedResources;
  }

  Map<String, List<StyioTaskSymbol>> _importedTasksFor({
    required String documentId,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, DocumentState> documentsById,
    required StyioProjectSymbolSnapshot symbolSnapshot,
  }) {
    final importedTasks = <String, List<StyioTaskSymbol>>{};
    for (final directive in importsByDocument[documentId]!) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        continue;
      }
      final importedDocument = documentsById[importedDocumentId];
      final transitiveImportedFunctions = _importedFunctionsFor(
        documentId: importedDocumentId,
        importsByDocument: importsByDocument,
        documentsById: documentsById,
        signatureSnapshot: symbolSnapshot.signatureSnapshot,
      );
      for (final task in symbolSnapshot.tasksFor(importedDocumentId)) {
        final returnType =
            task.returnType ??
            (importedDocument == null
                ? null
                : _taskReturnTypeForTaskSymbol(
                    source: importedDocument.text,
                    task: task,
                    importedFunctions: transitiveImportedFunctions,
                  ));
        importedTasks
            .putIfAbsent(task.name, () => <StyioTaskSymbol>[])
            .add(
              returnType == task.returnType
                  ? task
                  : StyioTaskSymbol(
                      name: task.name,
                      returnType: returnType,
                      hasConditionalReturn: task.hasConditionalReturn,
                      hasInvalidReturnExpression:
                          task.hasInvalidReturnExpression,
                      range: task.range,
                    ),
            );
      }
    }
    return importedTasks;
  }

  Map<String, List<StyioFunctionSignature>> _importedFunctionsFor({
    required String documentId,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, DocumentState> documentsById,
    required StyioProjectSignatureSnapshot signatureSnapshot,
  }) {
    final functions = <String, List<StyioFunctionSignature>>{};
    for (final directive in importsByDocument[documentId]!) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        continue;
      }
      for (final signature in signatureSnapshot.functionsFor(
        importedDocumentId,
      )) {
        functions.putIfAbsent(signature.name, () => []).add(signature);
      }
    }
    return functions;
  }

  List<StyioProjectDiagnostic> _importedCallDiagnostics({
    required DocumentState document,
    required Map<String, List<StyioFunctionSignature>> importedFunctions,
  }) {
    final diagnostics = <StyioProjectDiagnostic>[];
    for (final entry in importedFunctions.entries) {
      if (entry.value.length != 1) {
        continue;
      }
      final signature = entry.value.single;
      final localTypes = _localValueTypes(
        document.text,
        importedFunctions: importedFunctions,
      );
      for (final call in _callsTo(document.text, signature.name)) {
        final arguments = _argumentSlices(
          call.argumentText,
          call.argumentRange.start,
        );
        diagnostics.addAll(
          _importedNamedArgumentDiagnostics(
            document: document,
            signature: signature,
            arguments: arguments,
          ),
        );
        final missingRequiredParameters = _missingRequiredImportedParameters(
          signature: signature,
          arguments: arguments,
        );
        if (missingRequiredParameters.isNotEmpty) {
          diagnostics.add(
            StyioProjectDiagnostic(
              documentId: document.documentId,
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'missing-call-argument',
                message:
                    'Imported function `${signature.name}` is missing '
                    'required argument'
                    '${missingRequiredParameters.length == 1 ? '' : 's'} '
                    '${missingRequiredParameters.map((parameter) => '`${parameter.name}`').join(', ')}.',
                range: call.argumentRange,
              ),
            ),
          );
          continue;
        }
        final argumentCount = arguments.length;
        if (argumentCount < signature.requiredParameterCount) {
          diagnostics.add(
            StyioProjectDiagnostic(
              documentId: document.documentId,
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'missing-call-argument',
                message:
                    'Imported function `${signature.name}` requires '
                    '${signature.requiredParameterCount} argument'
                    '${signature.requiredParameterCount == 1 ? '' : 's'}.',
                range: call.argumentRange,
              ),
            ),
          );
          continue;
        }
        if (argumentCount > signature.parameterCount) {
          diagnostics.add(
            StyioProjectDiagnostic(
              documentId: document.documentId,
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'too-many-call-arguments',
                message:
                    'Imported function `${signature.name}` accepts '
                    '${signature.parameterCount} argument'
                    '${signature.parameterCount == 1 ? '' : 's'}.',
                range: call.argumentRange,
              ),
            ),
          );
          continue;
        }

        for (var index = 0; index < arguments.length; index += 1) {
          final argument = arguments[index];
          final parameter = _parameterForArgument(
            signature: signature,
            argument: argument,
            positionalIndex: index,
          );
          if (parameter == null || parameter.type.isEmpty) {
            continue;
          }
          final expression = _argumentExpression(argument.text);
          final actualType =
              _inferExpressionType(expression, localTypes) ??
              _inferImportedCallReturnType(expression, importedFunctions);
          if (actualType == null ||
              _isAssignable(
                actualType: actualType,
                expectedType: parameter.type,
              )) {
            continue;
          }
          diagnostics.add(
            StyioProjectDiagnostic(
              documentId: document.documentId,
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'argument-type-mismatch',
                message:
                    'Argument `${parameter.name}` expects `${parameter.type}` '
                    'but receives `$actualType` from imported function '
                    '`${signature.name}`.',
                range: argument.range,
              ),
            ),
          );
        }
      }
    }
    diagnostics.addAll(
      _importedReturnTypeDiagnostics(
        document: document,
        importedFunctions: importedFunctions,
      ),
    );
    return diagnostics;
  }

  List<StyioFunctionParameter> _missingRequiredImportedParameters({
    required StyioFunctionSignature signature,
    required List<_ArgumentSlice> arguments,
  }) {
    final supplied = <String>{};
    var positionalIndex = 0;
    for (final argument in arguments) {
      final namedSeparator = _topLevelNamedArgumentSeparator(argument.text);
      if (namedSeparator != null) {
        final argumentName = argument.text.substring(0, namedSeparator).trim();
        if (signature.parameters.any(
          (parameter) => parameter.name == argumentName,
        )) {
          supplied.add(argumentName);
        }
        continue;
      }
      if (positionalIndex < signature.parameters.length) {
        supplied.add(signature.parameters[positionalIndex].name);
      }
      positionalIndex += 1;
    }
    return signature.parameters
        .where((parameter) => !parameter.hasDefault)
        .where((parameter) => !supplied.contains(parameter.name))
        .toList(growable: false);
  }

  List<StyioProjectDiagnostic> _importedNamedArgumentDiagnostics({
    required DocumentState document,
    required StyioFunctionSignature signature,
    required List<_ArgumentSlice> arguments,
  }) {
    final diagnostics = <StyioProjectDiagnostic>[];
    final suppliedNames = <String>{};
    for (final argument in arguments) {
      final namedSeparator = _topLevelNamedArgumentSeparator(argument.text);
      if (namedSeparator == null) {
        continue;
      }
      final argumentName = argument.text.substring(0, namedSeparator).trim();
      final argumentNameStart =
          argument.range.start + argument.text.indexOf(argumentName);
      final argumentNameRange = SourceRange(
        start: argumentNameStart,
        end: argumentNameStart + argumentName.length,
      );

      if (!signature.parameters.any(
        (parameter) => parameter.name == argumentName,
      )) {
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'unknown-named-argument',
              message:
                  'Imported function `${signature.name}` has no parameter '
                  'named `$argumentName`.',
              range: argumentNameRange,
            ),
          ),
        );
      }
      if (!suppliedNames.add(argumentName)) {
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'duplicate-named-argument',
              message:
                  'Argument `$argumentName` is already supplied in imported '
                  'function call `${signature.name}`.',
              range: argumentNameRange,
            ),
          ),
        );
      }
    }
    return diagnostics;
  }

  List<StyioProjectDiagnostic> _importedResourceWriteDiagnostics({
    required DocumentState document,
    required Map<String, List<StyioResourceSymbol>> importedResources,
    required Map<String, List<StyioFunctionSignature>> importedFunctions,
  }) {
    final localTypes = _localValueTypes(
      document.text,
      importedFunctions: importedFunctions,
    );
    final diagnostics = <StyioProjectDiagnostic>[];
    var lineStart = 0;
    while (lineStart <= document.text.length) {
      final newline = document.text.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? document.text.length : newline;
      final line = document.text.substring(lineStart, lineEnd);
      final arrowIndex = line.indexOf('->');
      if (arrowIndex >= 0) {
        final targetMatch = RegExp(
          r'@\s*([A-Za-z_][A-Za-z0-9_]*)',
        ).firstMatch(line.substring(arrowIndex + 2));
        if (targetMatch != null) {
          final targetName = targetMatch.group(1)!;
          final resources = importedResources[targetName];
          if (resources != null && resources.length == 1) {
            final resource = resources.single;
            final expression = line.substring(0, arrowIndex).trim();
            final actualType =
                _inferExpressionType(expression, localTypes) ??
                _inferImportedCallReturnType(expression, importedFunctions);
            if (actualType != null &&
                !_isAssignable(
                  actualType: actualType,
                  expectedType: resource.type,
                )) {
              diagnostics.add(
                StyioProjectDiagnostic(
                  documentId: document.documentId,
                  diagnostic: Diagnostic(
                    severity: DiagnosticSeverity.error,
                    code: 'resource-write-type-mismatch',
                    message:
                        'Imported resource `@$targetName` expects '
                        '`${resource.type}` but receives `$actualType`.',
                    range: SourceRange(
                      start: lineStart,
                      end: lineStart + arrowIndex,
                    ),
                  ),
                ),
              );
            }
          }
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return diagnostics;
  }

  List<StyioProjectDiagnostic> _importedTaskAwaitDiagnostics({
    required DocumentState document,
    required Map<String, List<StyioTaskSymbol>> importedTasks,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, DocumentState> documentsById,
    required Map<String, StyioDocumentAnalysis> analyses,
  }) {
    final diagnostics = <StyioProjectDiagnostic>[];
    final localTypes = _localValueTypes(document.text);
    final pattern = RegExp(
      r'\?\|\s*([A-Za-z_][A-Za-z0-9_]*)\s*->\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9_]*)(?:\s*\|\s*([^\n]+))?',
    );
    for (final match in pattern.allMatches(document.text)) {
      if (_isOffsetInIgnoredText(document.text, match.start)) {
        continue;
      }
      final taskName = match.group(1)!;
      final bindingName = match.group(2)!;
      final expectedType = match.group(3)!;
      final tasks = importedTasks[taskName];
      if (tasks == null || tasks.length != 1) {
        continue;
      }
      final task = tasks.single;
      final taskNameStart = match.start + match.group(0)!.indexOf(taskName);
      if (task.returnType == null) {
        if (_hasImportedBlockingTaskReturnValueDiagnostic(
          documentId: document.documentId,
          taskName: taskName,
          importsByDocument: importsByDocument,
          documentsById: documentsById,
          analyses: analyses,
        )) {
          continue;
        }
        final hasInvalidReturn = task.hasInvalidReturnExpression;
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.error,
              code: hasInvalidReturn
                  ? 'invalid-task-return-expression'
                  : task.hasConditionalReturn
                  ? 'conditional-task-return'
                  : 'missing-task-return',
              message: hasInvalidReturn
                  ? 'Await target `$taskName` has a return expression whose '
                        'type cannot be inferred for '
                        '`$bindingName: $expectedType`.'
                  : task.hasConditionalReturn
                  ? 'Await target `$taskName` only returns from conditional '
                        'branches for `$bindingName: $expectedType`.'
                  : 'Await target `$taskName` does not return a value for '
                        '`$bindingName: $expectedType`.',
              range: SourceRange(
                start: taskNameStart,
                end: taskNameStart + taskName.length,
              ),
            ),
          ),
        );
      } else if (!_isAssignable(
        actualType: task.returnType!,
        expectedType: expectedType,
      )) {
        final bindingStart = match.start + match.group(0)!.indexOf(bindingName);
        diagnostics.add(
          StyioProjectDiagnostic(
            documentId: document.documentId,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'await-result-type-mismatch',
              message:
                  'Await binding `$bindingName` expects `$expectedType` but '
                  'imported task `$taskName` returns `${task.returnType}`.',
              range: SourceRange(
                start: bindingStart,
                end: bindingStart + bindingName.length,
              ),
            ),
          ),
        );
      }
      final fallbackExpression = match.group(4);
      if (fallbackExpression == null) {
        continue;
      }
      final fallbackType = _inferExpressionType(fallbackExpression, localTypes);
      if (fallbackType == null ||
          _isAssignable(actualType: fallbackType, expectedType: expectedType)) {
        continue;
      }
      final matchedText = match.group(0)!;
      final fallbackPipe = matchedText.lastIndexOf('|');
      final fallbackOffsetInMatch = matchedText.indexOf(
        fallbackExpression,
        fallbackPipe + 1,
      );
      if (fallbackOffsetInMatch < 0) {
        continue;
      }
      final trimmedFallback = fallbackExpression.trimLeft();
      final fallbackStart =
          match.start +
          fallbackOffsetInMatch +
          (fallbackExpression.length - trimmedFallback.length);
      diagnostics.add(
        StyioProjectDiagnostic(
          documentId: document.documentId,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'await-fallback-type-mismatch',
            message:
                'Await fallback for `$bindingName` expects `$expectedType` '
                'but receives `$fallbackType`.',
            range: SourceRange(
              start: fallbackStart,
              end: fallbackStart + trimmedFallback.trimRight().length,
            ),
          ),
        ),
      );
    }
    return diagnostics;
  }

  bool _hasImportedBlockingTaskReturnValueDiagnostic({
    required String documentId,
    required String taskName,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
    required Map<String, DocumentState> documentsById,
    required Map<String, StyioDocumentAnalysis> analyses,
  }) {
    final directives =
        importsByDocument[documentId] ?? const <_StyioImportDirective>[];
    for (final directive in directives) {
      if (_isExternalImport(directive.target)) {
        continue;
      }
      final importedDocumentId = _resolveImportTarget(
        directive.target,
        documentsById.keys,
      );
      if (importedDocumentId == null) {
        continue;
      }
      final analysis = analyses[importedDocumentId];
      if (analysis == null) {
        continue;
      }
      final hasBlockingReturnValueDiagnostic = analysis.diagnostics.any(
        (diagnostic) =>
            (diagnostic.code == 'missing-task-return-value' ||
                diagnostic.code == 'unresolved-task-return-value') &&
            _firstBacktickCaptureAfter(diagnostic.message, 'Task') == taskName,
      );
      if (hasBlockingReturnValueDiagnostic) {
        return true;
      }
    }
    return false;
  }

  List<StyioFunctionSignature> _functionSignatures(String source) {
    final signatures = <StyioFunctionSignature>[];
    final pattern = RegExp(
      r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*(?::\s*([A-Za-z][A-Za-z0-9_]*))?',
    );
    for (final match in pattern.allMatches(source)) {
      final name = match.group(1)!;
      final parameterText = match.group(2) ?? '';
      final returnType = match.group(3);
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      final parameters = _splitArguments(parameterText);
      signatures.add(
        StyioFunctionSignature(
          name: name,
          returnType: returnType,
          range: SourceRange(start: nameStart, end: nameStart + name.length),
          parameters: parameters.map(_parseParameter).toList(growable: false),
        ),
      );
    }
    final hashPattern = RegExp(
      r'#\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*\(([^)]*)\)\s*=>\s*\{',
    );
    for (final match in hashPattern.allMatches(source)) {
      final name = match.group(1)!;
      final parameterText = match.group(2) ?? '';
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      final openingBrace = source.indexOf('{', match.start);
      final closingBrace = _matchingBrace(source, openingBrace);
      final body = openingBrace >= 0 && closingBrace != null
          ? source.substring(openingBrace + 1, closingBrace)
          : '';
      final parameters = _splitArguments(parameterText);
      signatures.add(
        StyioFunctionSignature(
          name: name,
          returnType: _taskReturnType(body),
          range: SourceRange(start: nameStart, end: nameStart + name.length),
          parameters: parameters.map(_parseParameter).toList(growable: false),
        ),
      );
    }
    return signatures;
  }

  StyioFunctionParameter _parseParameter(String parameterText) {
    final defaultSeparator = parameterText.indexOf('=');
    final withoutDefault = defaultSeparator < 0
        ? parameterText.trim()
        : parameterText.substring(0, defaultSeparator).trim();
    final colon = withoutDefault.indexOf(':');
    if (colon < 0) {
      return StyioFunctionParameter(
        name: withoutDefault.trim(),
        type: '',
        hasDefault: defaultSeparator >= 0,
      );
    }
    return StyioFunctionParameter(
      name: withoutDefault.substring(0, colon).trim(),
      type: withoutDefault.substring(colon + 1).trim(),
      hasDefault: defaultSeparator >= 0,
    );
  }

  List<_ImportedFunctionCall> _callsTo(String source, String functionName) {
    final calls = <_ImportedFunctionCall>[];
    final pattern = RegExp('\\b${RegExp.escape(functionName)}\\s*\\(');
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      if (_isFunctionDeclarationCallMatch(source, match.start)) {
        continue;
      }
      final opening = source.indexOf('(', match.start);
      final closing = _matchingParenthesis(source, opening);
      if (opening < 0 || closing == null) {
        continue;
      }
      calls.add(
        _ImportedFunctionCall(
          argumentText: source.substring(opening + 1, closing),
          argumentRange: SourceRange(start: opening + 1, end: closing),
        ),
      );
    }
    return calls;
  }

  List<StyioResourceSymbol> _resourceSymbols(String source) {
    final resources = <StyioResourceSymbol>[];
    final pattern = RegExp(
      r'@\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9_]*)',
    );
    for (final match in pattern.allMatches(source)) {
      final name = match.group(1)!;
      if (name == 'import') {
        continue;
      }
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      resources.add(
        StyioResourceSymbol(
          name: name,
          type: match.group(2)!,
          range: SourceRange(start: nameStart, end: nameStart + name.length),
        ),
      );
    }
    return resources;
  }

  List<StyioTaskSymbol> _taskSymbols(String source) {
    final tasks = <StyioTaskSymbol>[];
    final functionReturnTypes = _localFunctionReturnTypes(source);
    final pattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\|\|>\s*\{');
    for (final match in pattern.allMatches(source)) {
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      final openingBrace = source.indexOf('{', match.start);
      final closingBrace = _matchingBrace(source, openingBrace);
      final body = openingBrace >= 0 && closingBrace != null
          ? source.substring(openingBrace + 1, closingBrace)
          : '';
      final returnScan = _taskReturnInference.scan(
        body: body,
        functionReturnTypes: functionReturnTypes,
      );
      tasks.add(
        StyioTaskSymbol(
          name: name,
          returnType: returnScan.values.isEmpty
              ? null
              : returnScan.values.first.type,
          hasConditionalReturn: returnScan.conditionalValueRanges.isNotEmpty,
          hasInvalidReturnExpression: returnScan.invalidExpressions.isNotEmpty,
          range: SourceRange(start: nameStart, end: nameStart + name.length),
        ),
      );
    }
    return tasks;
  }

  Map<String, String> _localFunctionReturnTypes(String source) {
    final types = <String, String>{};
    for (final signature in _functionSignatures(source)) {
      final returnType = signature.returnType;
      if (returnType != null && returnType.isNotEmpty) {
        types.putIfAbsent(signature.name, () => returnType);
      }
    }
    return types;
  }

  String? _taskReturnType(
    String body, {
    Map<String, String> functionReturnTypes = const <String, String>{},
    Map<String, List<StyioFunctionSignature>> importedFunctions =
        const <String, List<StyioFunctionSignature>>{},
  }) {
    return _taskReturnInference.firstReturnType(
      body: body,
      functionReturnTypes: {
        ..._uniqueImportedFunctionReturnTypes(importedFunctions),
        ...functionReturnTypes,
      },
    );
  }

  String? _taskReturnTypeForTaskSymbol({
    required String source,
    required StyioTaskSymbol task,
    required Map<String, List<StyioFunctionSignature>> importedFunctions,
  }) {
    if (task.range.start < 0 ||
        task.range.end > source.length ||
        task.range.start >= task.range.end) {
      return null;
    }
    final openingBrace = source.indexOf('{', task.range.end);
    if (openingBrace < 0) {
      return null;
    }
    final closingBrace = _matchingBrace(source, openingBrace);
    if (closingBrace == null) {
      return null;
    }
    return _taskReturnType(
      source.substring(openingBrace + 1, closingBrace),
      importedFunctions: importedFunctions,
    );
  }

  bool _isFunctionDeclarationCallMatch(String source, int functionNameStart) {
    final prefixStart = (functionNameStart - 4).clamp(0, source.length);
    final prefix = source.substring(prefixStart, functionNameStart);
    return RegExp(r'\bfn\s+$').hasMatch(prefix);
  }

  int? _matchingBrace(String source, int openingBrace) {
    if (openingBrace < 0 ||
        openingBrace >= source.length ||
        source[openingBrace] != '{') {
      return null;
    }
    var depth = 0;
    var index = openingBrace;
    while (index < source.length) {
      final char = source[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(source, index);
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
      index += 1;
    }
    return null;
  }

  int? _matchingParenthesis(String source, int opening) {
    if (opening < 0 || opening >= source.length || source[opening] != '(') {
      return null;
    }
    var depth = 0;
    var index = opening;
    while (index < source.length) {
      final char = source[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(source, index);
        continue;
      }
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
      index += 1;
    }
    return null;
  }

  int _skipQuotedText(String source, int openingQuote) {
    final quote = source[openingQuote];
    var index = openingQuote + 1;
    while (index < source.length) {
      if (source[index] == '\\' && index + 1 < source.length) {
        index += 2;
        continue;
      }
      if (source[index] == quote) {
        return index + 1;
      }
      index += 1;
    }
    return source.length;
  }

  List<_ArgumentSlice> _argumentSlices(String argumentText, int baseOffset) {
    final arguments = <_ArgumentSlice>[];
    var start = 0;
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var index = 0;
    while (index < argumentText.length) {
      final char = argumentText[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(argumentText, index);
        continue;
      }
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth -= 1;
      } else if (char == '[') {
        bracketDepth += 1;
      } else if (char == ']') {
        bracketDepth -= 1;
      } else if (char == '{') {
        braceDepth += 1;
      } else if (char == '}') {
        braceDepth -= 1;
      } else if (char == ',' &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        _addArgumentSlice(arguments, argumentText, baseOffset, start, index);
        start = index + 1;
      }
      index += 1;
    }
    _addArgumentSlice(
      arguments,
      argumentText,
      baseOffset,
      start,
      argumentText.length,
    );
    return arguments;
  }

  void _addArgumentSlice(
    List<_ArgumentSlice> arguments,
    String argumentText,
    int baseOffset,
    int start,
    int end,
  ) {
    var trimmedStart = start;
    var trimmedEnd = end;
    while (trimmedStart < trimmedEnd &&
        argumentText.codeUnitAt(trimmedStart) <= 0x20) {
      trimmedStart += 1;
    }
    while (trimmedEnd > trimmedStart &&
        argumentText.codeUnitAt(trimmedEnd - 1) <= 0x20) {
      trimmedEnd -= 1;
    }
    if (trimmedStart >= trimmedEnd) {
      return;
    }
    arguments.add(
      _ArgumentSlice(
        text: argumentText.substring(trimmedStart, trimmedEnd),
        range: SourceRange(
          start: baseOffset + trimmedStart,
          end: baseOffset + trimmedEnd,
        ),
      ),
    );
  }

  List<String> _splitArguments(String argumentText) {
    final arguments = <String>[];
    var start = 0;
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var index = 0;
    while (index < argumentText.length) {
      final char = argumentText[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(argumentText, index);
        continue;
      }
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth -= 1;
      } else if (char == '[') {
        bracketDepth += 1;
      } else if (char == ']') {
        bracketDepth -= 1;
      } else if (char == '{') {
        braceDepth += 1;
      } else if (char == '}') {
        braceDepth -= 1;
      } else if (char == ',' &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        final argument = argumentText.substring(start, index).trim();
        if (argument.isNotEmpty) {
          arguments.add(argument);
        }
        start = index + 1;
      }
      index += 1;
    }
    final tail = argumentText.substring(start).trim();
    if (tail.isNotEmpty) {
      arguments.add(tail);
    }
    return arguments;
  }

  StyioFunctionParameter? _parameterForArgument({
    required StyioFunctionSignature signature,
    required _ArgumentSlice argument,
    required int positionalIndex,
  }) {
    final namedSeparator = _topLevelNamedArgumentSeparator(argument.text);
    if (namedSeparator != null) {
      final name = argument.text.substring(0, namedSeparator).trim();
      for (final parameter in signature.parameters) {
        if (parameter.name == name) {
          return parameter;
        }
      }
      return null;
    }
    if (positionalIndex >= signature.parameters.length) {
      return null;
    }
    return signature.parameters[positionalIndex];
  }

  int? _topLevelNamedArgumentSeparator(String text) {
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    for (var index = 0; index < text.length; index += 1) {
      final char = text[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(text, index) - 1;
        continue;
      }
      if (char == '(') {
        parenDepth += 1;
      } else if (char == ')') {
        parenDepth -= 1;
      } else if (char == '[') {
        bracketDepth += 1;
      } else if (char == ']') {
        bracketDepth -= 1;
      } else if (char == '{') {
        braceDepth += 1;
      } else if (char == '}') {
        braceDepth -= 1;
      } else if (char == ':' &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        final name = text.substring(0, index).trim();
        return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)
            ? index
            : null;
      }
    }
    return null;
  }

  String _argumentExpression(String text) {
    final namedSeparator = _topLevelNamedArgumentSeparator(text);
    if (namedSeparator == null) {
      return text.trim();
    }
    return text.substring(namedSeparator + 1).trim();
  }

  List<StyioProjectDiagnostic> _importedReturnTypeDiagnostics({
    required DocumentState document,
    required Map<String, List<StyioFunctionSignature>> importedFunctions,
  }) {
    final diagnostics = <StyioProjectDiagnostic>[];
    var lineStart = 0;
    while (lineStart <= document.text.length) {
      final newline = document.text.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? document.text.length : newline;
      final line = document.text.substring(lineStart, lineEnd);
      final match = RegExp(
        r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      ).firstMatch(line);
      if (match != null) {
        final name = match.group(1)!;
        final expectedType = match.group(2)!;
        final functionName = match.group(3)!;
        final signature = _uniqueImportedFunctionSignature(
          importedFunctions,
          functionName,
        );
        if (signature?.returnType != null &&
            !_isAssignable(
              actualType: signature!.returnType!,
              expectedType: expectedType,
            )) {
          final initializerStart =
              lineStart + match.start + match.group(0)!.indexOf(functionName);
          diagnostics.add(
            StyioProjectDiagnostic(
              documentId: document.documentId,
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'initializer-type-mismatch',
                message:
                    'Initializer for `$name` expects `$expectedType`, got '
                    '`${signature.returnType}` from imported function '
                    '`$functionName`.',
                range: SourceRange(start: initializerStart, end: lineEnd),
              ),
            ),
          );
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return diagnostics;
  }

  Map<String, String> _localValueTypes(
    String source, {
    Map<String, List<StyioFunctionSignature>> importedFunctions =
        const <String, List<StyioFunctionSignature>>{},
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    return _taskReturnInference.localValueTypes(
      source,
      functionReturnTypes: {
        ..._uniqueImportedFunctionReturnTypes(importedFunctions),
        ...functionReturnTypes,
      },
    );
  }

  String? _inferExpressionType(
    String expression,
    Map<String, String> localTypes, {
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    return _taskReturnInference.inferExpressionType(
      expression,
      localTypes,
      functionReturnTypes: functionReturnTypes,
    );
  }

  Map<String, String> _uniqueImportedFunctionReturnTypes(
    Map<String, List<StyioFunctionSignature>> importedFunctions,
  ) {
    final types = <String, String>{};
    for (final entry in importedFunctions.entries) {
      if (entry.value.length != 1) {
        continue;
      }
      final returnType = entry.value.single.returnType;
      if (returnType == null || returnType.isEmpty) {
        continue;
      }
      types[entry.key] = returnType;
    }
    return types;
  }

  String? _inferImportedCallReturnType(
    String expression,
    Map<String, List<StyioFunctionSignature>> importedFunctions,
  ) {
    final trimmed = expression.trim();
    final match = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*\(').firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return _uniqueImportedFunctionSignature(
      importedFunctions,
      match.group(1)!,
    )?.returnType;
  }

  StyioFunctionSignature? _uniqueImportedFunctionSignature(
    Map<String, List<StyioFunctionSignature>> importedFunctions,
    String functionName,
  ) {
    final candidates = importedFunctions[functionName];
    if (candidates == null || candidates.length != 1) {
      return null;
    }
    return candidates.single;
  }

  bool _isAssignable({
    required String actualType,
    required String expectedType,
  }) {
    if (actualType == expectedType) {
      return true;
    }
    return expectedType == 'f64' && actualType == 'i64';
  }

  bool _isResolvedByImportedSymbol({
    required DocumentState document,
    required Diagnostic diagnostic,
    required Map<String, List<DocumentSymbol>> importedSymbols,
    required List<StyioProjectDiagnostic> diagnostics,
  }) {
    if (diagnostic.code != 'unresolved-reference' ||
        diagnostic.range.start < 0 ||
        diagnostic.range.end > document.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return false;
    }

    final name = document.text.substring(
      diagnostic.range.start,
      diagnostic.range.end,
    );
    final candidates = importedSymbols[name];
    if (candidates == null || candidates.isEmpty) {
      return false;
    }
    if (candidates.length > 1) {
      _addProjectDiagnosticIfAbsent(
        diagnostics,
        StyioProjectDiagnostic(
          documentId: document.documentId,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'ambiguous-imported-symbol',
            message: 'Imported symbol `$name` is declared by multiple imports.',
            range: diagnostic.range,
          ),
        ),
      );
    }
    return true;
  }

  bool _isResolvedByImportedResource({
    required DocumentState document,
    required Diagnostic diagnostic,
    required Map<String, List<StyioResourceSymbol>> importedResources,
    required List<StyioProjectDiagnostic> diagnostics,
  }) {
    if (diagnostic.code != 'unresolved-resource' ||
        diagnostic.range.start < 0 ||
        diagnostic.range.end > document.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return false;
    }

    final name = document.text.substring(
      diagnostic.range.start,
      diagnostic.range.end,
    );
    final candidates = importedResources[name];
    if (candidates == null || candidates.isEmpty) {
      return false;
    }
    if (candidates.length > 1) {
      _addProjectDiagnosticIfAbsent(
        diagnostics,
        StyioProjectDiagnostic(
          documentId: document.documentId,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'ambiguous-imported-symbol',
            message:
                'Imported resource `@$name` is declared by multiple imports.',
            range: diagnostic.range,
          ),
        ),
      );
    }
    return true;
  }

  bool _isResolvedByImportedTask({
    required DocumentState document,
    required Diagnostic diagnostic,
    required Map<String, List<StyioTaskSymbol>> importedTasks,
    required List<StyioProjectDiagnostic> diagnostics,
  }) {
    if (diagnostic.code != 'unresolved-task-await' ||
        diagnostic.range.start < 0 ||
        diagnostic.range.end > document.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return false;
    }

    final name = document.text.substring(
      diagnostic.range.start,
      diagnostic.range.end,
    );
    final candidates = importedTasks[name];
    if (candidates == null || candidates.isEmpty) {
      return false;
    }
    if (candidates.length > 1) {
      _addProjectDiagnosticIfAbsent(
        diagnostics,
        StyioProjectDiagnostic(
          documentId: document.documentId,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'ambiguous-imported-symbol',
            message: 'Imported task `$name` is declared by multiple imports.',
            range: diagnostic.range,
          ),
        ),
      );
    }
    return true;
  }

  void _addProjectDiagnosticIfAbsent(
    List<StyioProjectDiagnostic> diagnostics,
    StyioProjectDiagnostic candidate,
  ) {
    final candidateDiagnostic = candidate.diagnostic;
    final exists = diagnostics.any((existing) {
      final diagnostic = existing.diagnostic;
      return existing.documentId == candidate.documentId &&
          diagnostic.code == candidateDiagnostic.code &&
          diagnostic.range.start == candidateDiagnostic.range.start &&
          diagnostic.range.end == candidateDiagnostic.range.end;
    });
    if (!exists) {
      diagnostics.add(candidate);
    }
  }

  List<_StyioImportDirective> _parseImports(String source) {
    final imports = <_StyioImportDirective>[];
    var lineStart = 0;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final trimmedLeft = line.replaceFirst(RegExp(r'^\s+'), '');
      final leadingWhitespace = line.length - trimmedLeft.length;
      final importStart = lineStart + leadingWhitespace;
      if (trimmedLeft.startsWith('@import')) {
        final target = _importTargetFromLine(trimmedLeft);
        if (target != null && target.isNotEmpty) {
          final targetStartInLine = trimmedLeft.indexOf(target);
          imports.add(
            _StyioImportDirective(
              target: target,
              targetRange: SourceRange(
                start: importStart + targetStartInLine,
                end: importStart + targetStartInLine + target.length,
              ),
            ),
          );
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return imports;
  }

  String? _importTargetFromLine(String lineText) {
    final openBrace = lineText.indexOf('{');
    final closeBrace = lineText.lastIndexOf('}');
    if (openBrace >= 0 && closeBrace > openBrace) {
      return lineText.substring(openBrace + 1, closeBrace).trim();
    }
    return lineText.replaceFirst('@import', '').trim();
  }

  bool _isExternalImport(String target) {
    return target.startsWith('styio/');
  }

  String? _resolveImportTarget(String target, Iterable<String> documentIds) {
    final candidates = <String>{
      target,
      '$target.styio',
      if (target.startsWith('./')) target.substring(2),
      if (target.startsWith('./')) '${target.substring(2)}.styio',
    };
    for (final documentId in documentIds) {
      if (candidates.contains(documentId)) {
        return documentId;
      }
      if (candidates.any((candidate) => documentId.endsWith('/$candidate'))) {
        return documentId;
      }
    }
    return null;
  }
}

class StyioProjectAnalysisCache {
  final Map<String, _CachedStyioDocumentAnalysis> _documentAnalyses =
      <String, _CachedStyioDocumentAnalysis>{};
  final Map<String, _CachedStyioProjectDocumentIndex> _projectDocumentIndexes =
      <String, _CachedStyioProjectDocumentIndex>{};
  var _projectIndexCacheHits = 0;
  var _projectIndexCacheMisses = 0;

  int get documentCount => _documentAnalyses.length;
  int get projectIndexCount => _projectDocumentIndexes.length;
  int get projectIndexCacheHits => _projectIndexCacheHits;
  int get projectIndexCacheMisses => _projectIndexCacheMisses;

  void clear() {
    _documentAnalyses.clear();
    _projectDocumentIndexes.clear();
    _projectIndexCacheHits = 0;
    _projectIndexCacheMisses = 0;
  }

  void retainDocuments(Iterable<String> documentIds) {
    final retained = documentIds.toSet();
    _documentAnalyses.removeWhere((documentId, _) {
      return !retained.contains(documentId);
    });
    _projectDocumentIndexes.removeWhere((documentId, _) {
      return !retained.contains(documentId);
    });
  }

  StyioDocumentAnalysis? lookup(DocumentState document) {
    final cached = _documentAnalyses[document.documentId];
    if (cached == null ||
        cached.revision != document.revision ||
        cached.text != document.text) {
      return null;
    }
    return cached.analysis;
  }

  void store(DocumentState document, StyioDocumentAnalysis analysis) {
    _documentAnalyses[document.documentId] = _CachedStyioDocumentAnalysis(
      revision: document.revision,
      text: document.text,
      analysis: analysis,
    );
  }

  _StyioProjectDocumentIndex? _lookupProjectIndex(DocumentState document) {
    final cached = _projectDocumentIndexes[document.documentId];
    if (cached == null ||
        cached.revision != document.revision ||
        cached.text != document.text) {
      _projectIndexCacheMisses += 1;
      return null;
    }
    _projectIndexCacheHits += 1;
    return cached.index;
  }

  void _storeProjectIndex(
    DocumentState document,
    _StyioProjectDocumentIndex index,
  ) {
    _projectDocumentIndexes[document.documentId] =
        _CachedStyioProjectDocumentIndex(
          revision: document.revision,
          text: document.text,
          index: index,
        );
  }
}

class StyioProjectWorkspaceFix {
  const StyioProjectWorkspaceFix({
    required this.label,
    required this.editsByDocument,
    this.detail = '',
  });

  final String label;
  final Map<String, List<FormattingEdit>> editsByDocument;
  final String detail;

  StyioProjectWorkspaceFixPreview preview(List<DocumentState> documents) {
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final previews = <StyioProjectWorkspaceDocumentPreview>[];
    for (final entry in editsByDocument.entries) {
      final document = documentsById[entry.key];
      if (document == null) {
        continue;
      }
      final edits = normalizeFormattingEditsForDocument(
        documentLength: document.length,
        edits: entry.value,
      );
      if (edits.isEmpty) {
        continue;
      }
      previews.add(
        StyioProjectWorkspaceDocumentPreview(
          documentId: document.documentId,
          beforeText: document.text,
          afterText: _applyFormattingEditsToText(document.text, edits),
          edits: edits,
        ),
      );
    }
    return StyioProjectWorkspaceFixPreview(
      label: label,
      detail: detail,
      documents: List.unmodifiable(previews),
    );
  }

  List<DocumentState> apply(List<DocumentState> documents) {
    final previewByDocumentId = {
      for (final documentPreview in preview(documents).documents)
        documentPreview.documentId: documentPreview,
    };
    return List.unmodifiable([
      for (final document in documents)
        if (previewByDocumentId[document.documentId] case final preview?
            when preview.changed)
          DocumentState(
            documentId: document.documentId,
            text: preview.afterText,
            revision: document.revision + 1,
          )
        else
          document,
    ]);
  }
}

class StyioProjectWorkspaceFixPreview {
  const StyioProjectWorkspaceFixPreview({
    required this.label,
    required this.documents,
    this.detail = '',
  });

  final String label;
  final String detail;
  final List<StyioProjectWorkspaceDocumentPreview> documents;

  bool get hasChanges => documents.any((document) => document.changed);
}

class StyioProjectWorkspaceDocumentPreview {
  const StyioProjectWorkspaceDocumentPreview({
    required this.documentId,
    required this.beforeText,
    required this.afterText,
    required this.edits,
  });

  final String documentId;
  final String beforeText;
  final String afterText;
  final List<FormattingEdit> edits;

  bool get changed => beforeText != afterText;
}

String _applyFormattingEditsToText(String text, List<FormattingEdit> edits) {
  final descending = edits.toList(growable: false)
    ..sort((left, right) => right.range.start.compareTo(left.range.start));
  var result = text;
  for (final edit in descending) {
    result = result.replaceRange(
      edit.range.start,
      edit.range.end,
      edit.newText,
    );
  }
  return result;
}

class StyioProjectAnalysis {
  const StyioProjectAnalysis({
    required this.documentAnalyses,
    required this.diagnostics,
    required this.symbolSnapshot,
    required this.signatureSnapshot,
  });

  final Map<String, StyioDocumentAnalysis> documentAnalyses;
  final List<StyioProjectDiagnostic> diagnostics;
  final StyioProjectSymbolSnapshot symbolSnapshot;
  final StyioProjectSignatureSnapshot signatureSnapshot;

  List<StyioProjectDiagnostic> diagnosticsFor(String documentId) {
    return diagnostics
        .where((diagnostic) => diagnostic.documentId == documentId)
        .toList(growable: false);
  }
}

class StyioProjectSymbolSnapshot {
  const StyioProjectSymbolSnapshot._({
    required Map<String, List<StyioFunctionSignature>> functionsByDocument,
    required Map<String, List<StyioResourceSymbol>> resourcesByDocument,
    required Map<String, List<StyioTaskSymbol>> tasksByDocument,
    required Map<String, String> sourceByDocument,
    required Map<String, List<_StyioImportDirective>> importsByDocument,
  }) : _functionsByDocument = functionsByDocument,
       _resourcesByDocument = resourcesByDocument,
       _tasksByDocument = tasksByDocument,
       _sourceByDocument = sourceByDocument,
       _importsByDocument = importsByDocument;

  final Map<String, List<StyioFunctionSignature>> _functionsByDocument;
  final Map<String, List<StyioResourceSymbol>> _resourcesByDocument;
  final Map<String, List<StyioTaskSymbol>> _tasksByDocument;
  final Map<String, String> _sourceByDocument;
  final Map<String, List<_StyioImportDirective>> _importsByDocument;

  StyioProjectSignatureSnapshot get signatureSnapshot {
    return StyioProjectSignatureSnapshot._(_functionsByDocument);
  }

  List<StyioFunctionSignature> functionsFor(String documentId) {
    return List<StyioFunctionSignature>.unmodifiable(
      _functionsByDocument[documentId] ?? const <StyioFunctionSignature>[],
    );
  }

  List<String> importTargetsFor(String documentId) {
    return List<String>.unmodifiable(
      (_importsByDocument[documentId] ?? const <_StyioImportDirective>[]).map(
        (directive) => directive.target,
      ),
    );
  }

  List<StyioResourceSymbol> resourcesFor(String documentId) {
    return List<StyioResourceSymbol>.unmodifiable(
      _resourcesByDocument[documentId] ?? const <StyioResourceSymbol>[],
    );
  }

  List<StyioTaskSymbol> tasksFor(String documentId) {
    return List<StyioTaskSymbol>.unmodifiable(
      _tasksByDocument[documentId] ?? const <StyioTaskSymbol>[],
    );
  }

  List<StyioProjectSymbolDefinition> definitionsFor(String name) {
    final definitions = <StyioProjectSymbolDefinition>[];
    for (final documentId in _functionsByDocument.keys) {
      definitions.addAll(_definitionsInDocument(documentId, name));
    }
    return List<StyioProjectSymbolDefinition>.unmodifiable(definitions);
  }

  List<StyioProjectSymbolDefinition> definitionsVisibleFrom({
    required String documentId,
    required String name,
  }) {
    final definitions = <StyioProjectSymbolDefinition>[];
    for (final visibleDocumentId in _visibleDocumentIdsFrom(documentId)) {
      definitions.addAll(_definitionsInDocument(visibleDocumentId, name));
    }
    return List<StyioProjectSymbolDefinition>.unmodifiable(definitions);
  }

  List<StyioProjectSymbolDefinition> definitionsVisibleFromDocument(
    String documentId,
  ) {
    final visibleDocumentIds = _visibleDocumentIdsFrom(documentId);
    final definitions = <StyioProjectSymbolDefinition>[];
    for (final visibleDocumentId in visibleDocumentIds) {
      definitions.addAll(_definitionsInDocument(visibleDocumentId));
    }
    return List<StyioProjectSymbolDefinition>.unmodifiable(definitions);
  }

  List<StyioProjectSymbolReference> referencesFor(
    StyioProjectSymbolDefinition definition,
  ) {
    final references = <StyioProjectSymbolReference>[];
    for (final documentId in _sourceByDocument.keys) {
      if (!_definitionVisibleFromDocument(
        documentId: documentId,
        definition: definition,
      )) {
        continue;
      }
      final source = _sourceByDocument[documentId] ?? '';
      final scope = _StyioScopeModel(source);
      for (final range in _identifierRangesInText(source, definition.name)) {
        final isDefinition =
            definition.documentId == documentId &&
            definition.range.start == range.start &&
            definition.range.end == range.end;
        if (!isDefinition &&
            (scope.isImportDirectiveText(range) ||
                scope.shadowsProjectSymbol(
                  name: definition.name,
                  range: range,
                ))) {
          continue;
        }
        references.add(
          StyioProjectSymbolReference(
            documentId: documentId,
            name: definition.name,
            range: range,
            isDefinition: isDefinition,
            access: isDefinition
                ? ReferenceAccess.declaration
                : _referenceAccessForRange(
                    source: source,
                    range: range,
                    definition: definition,
                  ),
          ),
        );
      }
    }
    return List<StyioProjectSymbolReference>.unmodifiable(references);
  }

  bool _definitionVisibleFromDocument({
    required String documentId,
    required StyioProjectSymbolDefinition definition,
  }) {
    return definitionsVisibleFrom(
      documentId: documentId,
      name: definition.name,
    ).any((candidate) => _sameDefinition(candidate, definition));
  }

  bool _sameDefinition(
    StyioProjectSymbolDefinition left,
    StyioProjectSymbolDefinition right,
  ) {
    return left.documentId == right.documentId &&
        left.kind == right.kind &&
        left.name == right.name &&
        left.range.start == right.range.start &&
        left.range.end == right.range.end;
  }

  ReferenceAccess _referenceAccessForRange({
    required String source,
    required SourceRange range,
    required StyioProjectSymbolDefinition definition,
  }) {
    if (definition.kind == StyioProjectSymbolKind.resource) {
      final previous = _previousSignificantLexeme(source, range.start);
      if (previous == '@') {
        final beforeAt = _previousSignificantLexeme(
          source,
          _previousSignificantStart(source, range.start) ?? range.start,
        );
        if (beforeAt == '->' || beforeAt == '>>') {
          return ReferenceAccess.write;
        }
      }
    }

    return ReferenceAccess.read;
  }

  String? _previousSignificantLexeme(String source, int offset) {
    final start = _previousSignificantStart(source, offset);
    if (start == null) {
      return null;
    }
    final codeUnit = source.codeUnitAt(start);
    if (_isIdentifierCodeUnit(codeUnit)) {
      var cursor = start;
      while (cursor > 0 && _isIdentifierCodeUnit(source.codeUnitAt(cursor - 1))) {
        cursor -= 1;
      }
      return source.substring(cursor, start + 1);
    }
    if (start > 0) {
      final pair = source.substring(start - 1, start + 1);
      if (pair == '->' || pair == '>>') {
        return pair;
      }
    }
    return source[start];
  }

  int? _previousSignificantStart(String source, int offset) {
    var cursor = offset - 1;
    while (cursor >= 0 && _isWhitespaceCodeUnit(source.codeUnitAt(cursor))) {
      cursor -= 1;
    }
    return cursor < 0 ? null : cursor;
  }

  bool _isWhitespaceCodeUnit(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d;
  }

  List<SourceRange> _identifierRangesInText(String source, String name) {
    final ranges = <SourceRange>[];
    var index = 0;
    while (index < source.length) {
      final ignoredEnd = _ignoredTextEndAt(source, index);
      if (ignoredEnd != null) {
        index = ignoredEnd;
        continue;
      }
      final next = source.indexOf(name, index);
      if (next < 0) {
        break;
      }
      if (_isOffsetInIgnoredText(source, next)) {
        index = next + name.length;
        continue;
      }
      final before = next == 0 ? null : source.codeUnitAt(next - 1);
      final after = next + name.length >= source.length
          ? null
          : source.codeUnitAt(next + name.length);
      if (!_isNullableIdentifierCodeUnit(before) &&
          !_isNullableIdentifierCodeUnit(after)) {
        ranges.add(SourceRange(start: next, end: next + name.length));
      }
      index = next + name.length;
    }
    return ranges;
  }

  bool _isNullableIdentifierCodeUnit(int? codeUnit) {
    return codeUnit != null && _isIdentifierCodeUnit(codeUnit);
  }

  bool _isIdentifierCodeUnit(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x5f;
  }

  Set<String> _visibleDocumentIdsFrom(String documentId) {
    final visibleDocumentIds = <String>{documentId};
    for (final directive
        in _importsByDocument[documentId] ?? const <_StyioImportDirective>[]) {
      if (directive.target.startsWith('styio/')) {
        continue;
      }
      final importedDocumentId = _resolveSnapshotImportTarget(
        directive.target,
        _functionsByDocument.keys,
      );
      if (importedDocumentId != null) {
        visibleDocumentIds.add(importedDocumentId);
      }
    }
    return visibleDocumentIds;
  }

  List<StyioProjectSymbolDefinition> _definitionsInDocument(
    String documentId, [
    String? name,
  ]) {
    return [
      for (final function
          in _functionsByDocument[documentId] ??
              const <StyioFunctionSignature>[])
        if (name == null || function.name == name)
          StyioProjectSymbolDefinition(
            documentId: documentId,
            kind: StyioProjectSymbolKind.function,
            name: function.name,
            range: function.range,
            type: function.returnType,
          ),
      for (final resource
          in _resourcesByDocument[documentId] ?? const <StyioResourceSymbol>[])
        if (name == null || resource.name == name)
          StyioProjectSymbolDefinition(
            documentId: documentId,
            kind: StyioProjectSymbolKind.resource,
            name: resource.name,
            range: resource.range,
            type: resource.type,
          ),
      for (final task
          in _tasksByDocument[documentId] ?? const <StyioTaskSymbol>[])
        if (name == null || task.name == name)
          StyioProjectSymbolDefinition(
            documentId: documentId,
            kind: StyioProjectSymbolKind.task,
            name: task.name,
            range: task.range,
            type: task.returnType,
          ),
    ];
  }

  String? _resolveSnapshotImportTarget(
    String target,
    Iterable<String> documentIds,
  ) {
    final candidates = <String>{
      target,
      '$target.styio',
      if (target.startsWith('./')) target.substring(2),
      if (target.startsWith('./')) '${target.substring(2)}.styio',
    };
    for (final documentId in documentIds) {
      if (candidates.contains(documentId)) {
        return documentId;
      }
      if (candidates.any((candidate) => documentId.endsWith('/$candidate'))) {
        return documentId;
      }
    }
    return null;
  }
}

class StyioProjectSignatureSnapshot {
  const StyioProjectSignatureSnapshot._(this._functionsByDocument);

  final Map<String, List<StyioFunctionSignature>> _functionsByDocument;

  List<StyioFunctionSignature> functionsFor(String documentId) {
    return List<StyioFunctionSignature>.unmodifiable(
      _functionsByDocument[documentId] ?? const <StyioFunctionSignature>[],
    );
  }
}

class _StyioScopeModel {
  const _StyioScopeModel(this.source);

  final String source;

  bool shadowsProjectSymbol({
    required String name,
    required SourceRange range,
  }) {
    return _isShadowedByFunctionParameter(name: name, range: range) ||
        _isShadowedByLocalBinding(name: name, range: range) ||
        _isFunctionParameterDefinition(range);
  }

  bool isImportDirectiveText(SourceRange range) {
    final lineSearchStart = range.start == 0 ? 0 : range.start - 1;
    final lineStart = source.lastIndexOf('\n', lineSearchStart) + 1;
    final lineEnd = source.indexOf('\n', range.end);
    final absoluteLineEnd = lineEnd < 0 ? source.length : lineEnd;
    final line = source.substring(lineStart, absoluteLineEnd);
    final trimmedLeft = line.replaceFirst(RegExp(r'^\s+'), '');
    if (!trimmedLeft.startsWith('@import')) {
      return false;
    }
    final importStart = lineStart + line.length - trimmedLeft.length;
    return range.start >= importStart && range.end <= absoluteLineEnd;
  }

  bool _isShadowedByFunctionParameter({
    required String name,
    required SourceRange range,
  }) {
    final pattern = RegExp(
      r'\bfn\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)\s*(?::\s*[A-Za-z][A-Za-z0-9_]*)?\s*\{',
    );
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final openingBrace = source.lastIndexOf('{', match.end - 1);
      final closingBrace = _matchingBrace(openingBrace);
      if (openingBrace < 0 ||
          closingBrace == null ||
          range.start < match.start ||
          range.end > closingBrace) {
        continue;
      }
      if (_functionParameterNames(match.group(1) ?? '').contains(name)) {
        return true;
      }
    }
    return false;
  }

  bool _isShadowedByLocalBinding({
    required String name,
    required SourceRange range,
  }) {
    final pattern = RegExp(
      r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z][A-Za-z0-9_]*)?\s=',
      multiLine: true,
    );
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      if (match.group(1) != name) {
        continue;
      }
      final nameStart = match.start + match.group(0)!.indexOf(match.group(1)!);
      if (range.start >= nameStart) {
        return true;
      }
    }
    return false;
  }

  bool _isFunctionParameterDefinition(SourceRange range) {
    final lineStart = source.lastIndexOf('\n', range.start - 1) + 1;
    final lineEnd = source.indexOf('\n', range.end);
    final line = source.substring(
      lineStart,
      lineEnd < 0 ? source.length : lineEnd,
    );
    final offsetInLine = range.start - lineStart;
    final fnIndex = line.indexOf(RegExp(r'\bfn\s+'));
    final openParen = line.indexOf('(');
    final closeParen = line.indexOf(')');
    final colonAfterName = line.indexOf(':', offsetInLine);
    return fnIndex >= 0 &&
        openParen >= 0 &&
        closeParen > openParen &&
        offsetInLine > openParen &&
        offsetInLine < closeParen &&
        colonAfterName > offsetInLine &&
        colonAfterName < closeParen;
  }

  Set<String> _functionParameterNames(String parameterText) {
    final names = <String>{};
    for (final parameter in parameterText.split(',')) {
      final colon = parameter.indexOf(':');
      final name = colon < 0
          ? parameter.trim()
          : parameter.substring(0, colon).trim();
      if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
        names.add(name);
      }
    }
    return names;
  }

  int? _matchingBrace(int openingBrace) {
    if (openingBrace < 0 ||
        openingBrace >= source.length ||
        source[openingBrace] != '{') {
      return null;
    }
    var depth = 0;
    var index = openingBrace;
    while (index < source.length) {
      final char = source[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(index);
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
      index += 1;
    }
    return null;
  }

  int _skipQuotedText(int openingQuote) {
    final quote = source[openingQuote];
    var index = openingQuote + 1;
    while (index < source.length) {
      if (source[index] == '\\' && index + 1 < source.length) {
        index += 2;
        continue;
      }
      if (source[index] == quote) {
        return index + 1;
      }
      index += 1;
    }
    return source.length;
  }
}

bool _isOffsetInIgnoredText(String source, int offset) {
  var index = 0;
  while (index < source.length && index <= offset) {
    final ignoredEnd = _ignoredTextEndAt(source, index);
    if (ignoredEnd != null) {
      if (offset < ignoredEnd) {
        return true;
      }
      index = ignoredEnd;
      continue;
    }
    index += 1;
  }
  return false;
}

int? _ignoredTextEndAt(String source, int index) {
  if (index < 0 || index >= source.length) {
    return null;
  }
  final char = source[index];
  if (char == '"' || char == "'") {
    return _quotedTextEnd(source, index);
  }
  if (char == '/' && index + 1 < source.length) {
    final next = source[index + 1];
    if (next == '/') {
      final newline = source.indexOf('\n', index + 2);
      return newline < 0 ? source.length : newline;
    }
    if (next == '*') {
      final closing = source.indexOf('*/', index + 2);
      return closing < 0 ? source.length : closing + 2;
    }
  }
  return null;
}

int _quotedTextEnd(String source, int openingQuote) {
  final quote = source[openingQuote];
  var index = openingQuote + 1;
  while (index < source.length) {
    if (source[index] == '\\' && index + 1 < source.length) {
      index += 2;
      continue;
    }
    if (source[index] == quote) {
      return index + 1;
    }
    index += 1;
  }
  return source.length;
}

enum StyioProjectSymbolKind { function, resource, task }

class StyioProjectSymbolDefinition {
  const StyioProjectSymbolDefinition({
    required this.documentId,
    required this.kind,
    required this.name,
    required this.range,
    required this.type,
  });

  final String documentId;
  final StyioProjectSymbolKind kind;
  final String name;
  final SourceRange range;
  final String? type;
}

class StyioProjectHover {
  const StyioProjectHover({required this.label, required this.definitions});

  factory StyioProjectHover.fromDefinitions(
    List<StyioProjectSymbolDefinition> definitions,
  ) {
    final first = definitions.first;
    final typeSuffix = first.type == null ? '' : ': ${first.type}';
    final ambiguitySuffix = definitions.length == 1
        ? ''
        : ' (${definitions.length} definitions)';
    return StyioProjectHover(
      label: '${first.kind.name} ${first.name}$typeSuffix$ambiguitySuffix',
      definitions: List<StyioProjectSymbolDefinition>.unmodifiable(definitions),
    );
  }

  final String label;
  final List<StyioProjectSymbolDefinition> definitions;
}

class StyioProjectSymbolReference {
  const StyioProjectSymbolReference({
    required this.documentId,
    required this.name,
    required this.range,
    required this.isDefinition,
    this.access = ReferenceAccess.read,
  });

  final String documentId;
  final String name;
  final SourceRange range;
  final bool isDefinition;
  final ReferenceAccess access;
}

class StyioProjectRenamePreview {
  const StyioProjectRenamePreview({
    required this.oldName,
    required this.newName,
    required this.editsByDocument,
    this.conflict,
  });

  const StyioProjectRenamePreview.conflict({
    required this.oldName,
    required this.newName,
    required String this.conflict,
  }) : editsByDocument = const <String, List<SourceRange>>{};

  final String oldName;
  final String newName;
  final Map<String, List<SourceRange>> editsByDocument;
  final String? conflict;

  bool get hasConflict => conflict != null;

  int get editCount {
    return editsByDocument.values.fold<int>(
      0,
      (count, edits) => count + edits.length,
    );
  }
}

class StyioResourceSymbol {
  const StyioResourceSymbol({
    required this.name,
    required this.type,
    required this.range,
  });

  final String name;
  final String type;
  final SourceRange range;
}

class StyioTaskSymbol {
  const StyioTaskSymbol({
    required this.name,
    required this.returnType,
    required this.range,
    this.hasConditionalReturn = false,
    this.hasInvalidReturnExpression = false,
  });

  final String name;
  final String? returnType;
  final SourceRange range;
  final bool hasConditionalReturn;
  final bool hasInvalidReturnExpression;
}

class StyioProjectDiagnostic {
  const StyioProjectDiagnostic({
    required this.documentId,
    required this.diagnostic,
  });

  final String documentId;
  final Diagnostic diagnostic;
}

class _CachedStyioDocumentAnalysis {
  const _CachedStyioDocumentAnalysis({
    required this.revision,
    required this.text,
    required this.analysis,
  });

  final int revision;
  final String text;
  final StyioDocumentAnalysis analysis;
}

class _StyioProjectDocumentIndex {
  const _StyioProjectDocumentIndex({
    required this.functions,
    required this.resources,
    required this.tasks,
    required this.imports,
  });

  final List<StyioFunctionSignature> functions;
  final List<StyioResourceSymbol> resources;
  final List<StyioTaskSymbol> tasks;
  final List<_StyioImportDirective> imports;
}

class _CachedStyioProjectDocumentIndex {
  const _CachedStyioProjectDocumentIndex({
    required this.revision,
    required this.text,
    required this.index,
  });

  final int revision;
  final String text;
  final _StyioProjectDocumentIndex index;
}

class _StyioImportDirective {
  const _StyioImportDirective({
    required this.target,
    required this.targetRange,
  });

  final String target;
  final SourceRange targetRange;
}

class _StyioImportCompletionContext {
  const _StyioImportCompletionContext({
    required this.prefix,
    required this.replacementRange,
  });

  final String prefix;
  final SourceRange replacementRange;
}

class _ProjectFunctionCall {
  const _ProjectFunctionCall({
    required this.name,
    required this.callableRange,
    required this.openingParenthesis,
    required this.closingParenthesis,
    required this.argumentText,
    required this.argumentRange,
  });

  final String name;
  final SourceRange callableRange;
  final int openingParenthesis;
  final int closingParenthesis;
  final String argumentText;
  final SourceRange argumentRange;
}

class _ProjectNamedArgumentCompletionContext {
  const _ProjectNamedArgumentCompletionContext({
    required this.prefix,
    required this.segmentRange,
    required this.replacementRange,
  });

  final String prefix;
  final SourceRange segmentRange;
  final SourceRange replacementRange;
}

class StyioFunctionSignature {
  const StyioFunctionSignature({
    required this.name,
    required this.returnType,
    required this.parameters,
    this.range = const SourceRange(start: -1, end: -1),
  });

  final String name;
  final String? returnType;
  final List<StyioFunctionParameter> parameters;
  final SourceRange range;

  int get parameterCount => parameters.length;

  int get requiredParameterCount {
    return parameters.where((parameter) => !parameter.hasDefault).length;
  }
}

class StyioFunctionParameter {
  const StyioFunctionParameter({
    required this.name,
    required this.type,
    required this.hasDefault,
  });

  final String name;
  final String type;
  final bool hasDefault;
}

class _ImportedFunctionCall {
  const _ImportedFunctionCall({
    required this.argumentText,
    required this.argumentRange,
  });

  final String argumentText;
  final SourceRange argumentRange;
}

class _ArgumentSlice {
  const _ArgumentSlice({required this.text, required this.range});

  final String text;
  final SourceRange range;
}

class _ImportTargetSuggestion {
  const _ImportTargetSuggestion({required this.target, required this.distance});

  final String target;
  final int distance;
}
