import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import 'current_project_document_rule_provider.dart';
import 'project_document_rule_provider.dart';

class ProjectDocumentRuleProviderDescriptor {
  const ProjectDocumentRuleProviderDescriptor({
    required this.providerId,
    required this.displayName,
    this.priority = 0,
  });

  final String providerId;
  final String displayName;
  final int priority;
}

class ProjectDocumentRuleRegistration {
  const ProjectDocumentRuleRegistration({
    required this.descriptor,
    required this.provider,
  });

  final ProjectDocumentRuleProviderDescriptor descriptor;
  final ProjectDocumentRuleProvider provider;
}

class ProjectDocumentRuleRegistry implements ProjectDocumentRuleProvider {
  const ProjectDocumentRuleRegistry({
    this.registrations = const <ProjectDocumentRuleRegistration>[],
  });

  static const current = ProjectDocumentRuleRegistry(
    registrations: <ProjectDocumentRuleRegistration>[
      ProjectDocumentRuleRegistration(
        descriptor: ProjectDocumentRuleProviderDescriptor(
          providerId: 'current-project-document-rules',
          displayName: 'Current project document rules',
          priority: 0,
        ),
        provider: CurrentProjectDocumentRuleProvider(),
      ),
    ],
  );

  final List<ProjectDocumentRuleRegistration> registrations;

  List<ProjectDocumentRuleRegistration> get orderedRegistrations {
    return List<ProjectDocumentRuleRegistration>.of(registrations)
      ..sort((left, right) {
        final priority = right.descriptor.priority.compareTo(
          left.descriptor.priority,
        );
        if (priority != 0) {
          return priority;
        }
        return left.descriptor.providerId.compareTo(
          right.descriptor.providerId,
        );
      });
  }

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    final analyses = [
      for (final registration in orderedRegistrations)
        registration.provider.analysisFactsFor(document),
    ];
    return StyioDocumentAnalysis(
      tokenSpans: _dedupeTokenSpans(analyses.expand((item) => item.tokenSpans)),
      semanticSpans: _dedupeSemanticSpans(
        analyses.expand((item) => item.semanticSpans),
      ),
      diagnostics: _dedupeDiagnostics(
        analyses.expand((item) => item.diagnostics),
      ),
      formattingEdits: _dedupeFormattingEdits(
        analyses.expand((item) => item.formattingEdits),
      ),
      semanticBlocks: _dedupeSemanticBlocks(
        analyses.expand((item) => item.semanticBlocks),
      ),
      inlayHints: _dedupeInlayHints(analyses.expand((item) => item.inlayHints)),
      documentSymbols: _dedupeDocumentSymbols(
        analyses.expand((item) => item.documentSymbols),
      ),
      referenceSpans: _dedupeReferenceSpans(
        analyses.expand((item) => item.referenceSpans),
      ),
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return _dedupeDiagnostics(
      orderedRegistrations.expand(
        (registration) => registration.provider.diagnosticsFor(document),
      ),
    );
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _dedupeQuickFixes(
      orderedRegistrations.expand(
        (registration) => registration.provider.quickFixesForDiagnostic(
          document,
          diagnostic,
        ),
      ),
    );
  }

  List<TokenSpan> _dedupeTokenSpans(Iterable<TokenSpan> tokens) {
    final deduped = <TokenSpan>[];
    final seen = <String>{};
    for (final token in tokens) {
      final key = '${token.kind.name}:${token.range.start}:${token.range.end}:${token.lexeme}';
      if (seen.add(key)) {
        deduped.add(token);
      }
    }
    return deduped;
  }

  List<SemanticSpan> _dedupeSemanticSpans(Iterable<SemanticSpan> spans) {
    final deduped = <SemanticSpan>[];
    final seen = <String>{};
    for (final span in spans) {
      final key =
          '${span.kind.name}:${span.range.start}:${span.range.end}:'
          '${span.modifiers.join(',')}';
      if (seen.add(key)) {
        deduped.add(span);
      }
    }
    return deduped;
  }

  List<Diagnostic> _dedupeDiagnostics(Iterable<Diagnostic> diagnostics) {
    final deduped = <Diagnostic>[];
    final seen = <String>{};
    for (final diagnostic in diagnostics) {
      final key =
          '${diagnostic.code}:${diagnostic.range.start}:'
          '${diagnostic.range.end}:${diagnostic.message}';
      if (seen.add(key)) {
        deduped.add(diagnostic);
      }
    }
    return deduped;
  }

  List<FormattingEdit> _dedupeFormattingEdits(Iterable<FormattingEdit> edits) {
    final deduped = <FormattingEdit>[];
    final seen = <String>{};
    for (final edit in edits) {
      final key = '${edit.range.start}:${edit.range.end}:${edit.newText}';
      if (seen.add(key)) {
        deduped.add(edit);
      }
    }
    return deduped;
  }

  List<SemanticBlockRange> _dedupeSemanticBlocks(
    Iterable<SemanticBlockRange> blocks,
  ) {
    final deduped = <SemanticBlockRange>[];
    final seen = <String>{};
    for (final block in blocks) {
      final key = '${block.label}:${block.range.start}:${block.range.end}';
      if (seen.add(key)) {
        deduped.add(block);
      }
    }
    return deduped;
  }

  List<InlayHint> _dedupeInlayHints(Iterable<InlayHint> hints) {
    final deduped = <InlayHint>[];
    final seen = <String>{};
    for (final hint in hints) {
      final key =
          '${hint.kind.name}:${hint.position}:${hint.range.start}:'
          '${hint.range.end}:${hint.label}';
      if (seen.add(key)) {
        deduped.add(hint);
      }
    }
    return deduped;
  }

  List<DocumentSymbol> _dedupeDocumentSymbols(
    Iterable<DocumentSymbol> symbols,
  ) {
    final deduped = <DocumentSymbol>[];
    final seen = <String>{};
    for (final symbol in symbols) {
      final key =
          '${symbol.kind.name}:${symbol.name}:'
          '${symbol.nameRange.start}:${symbol.nameRange.end}:'
          '${symbol.declarationRange.start}:${symbol.declarationRange.end}';
      if (seen.add(key)) {
        deduped.add(symbol);
      }
    }
    return deduped;
  }

  List<ReferenceSpan> _dedupeReferenceSpans(
    Iterable<ReferenceSpan> references,
  ) {
    final deduped = <ReferenceSpan>[];
    final seen = <String>{};
    for (final reference in references) {
      final key =
          '${reference.name}:${reference.kind.name}:'
          '${reference.range.start}:${reference.range.end}:'
          '${reference.targetRange.start}:${reference.targetRange.end}';
      if (seen.add(key)) {
        deduped.add(reference);
      }
    }
    return deduped;
  }

  List<DiagnosticQuickFix> _dedupeQuickFixes(
    Iterable<DiagnosticQuickFix> fixes,
  ) {
    final deduped = <DiagnosticQuickFix>[];
    final seen = <String>{};
    for (final fix in fixes) {
      final edits = fix.edits
          .map((edit) => '${edit.range.start}:${edit.range.end}:${edit.newText}')
          .join('|');
      final key = '${fix.label}:$edits';
      if (seen.add(key)) {
        deduped.add(fix);
      }
    }
    return deduped;
  }
}
