import 'package:flutter/material.dart';

import '../../view_ide/language/language_contract.dart';
import '../../view_ide/workspace/workspace.dart';
import '../platform/viewport_profile.dart';

class ProblemsSurface extends StatelessWidget {
  const ProblemsSurface({
    super.key,
    required this.viewportProfile,
    required this.documentId,
    required this.diagnostics,
    this.workspaceDiagnostics,
    this.onSelectDiagnostic,
    this.onSelectWorkspaceDiagnostic,
    this.onRefreshWorkspaceDiagnostics,
    this.workspaceEditPreview,
    this.severityFilter = const <DiagnosticSeverity>[],
    this.filterState,
    this.onPreviewWorkspaceQuickFix,
    this.onApplyWorkspaceQuickFix,
  });

  final ViewportProfile viewportProfile;
  final String documentId;
  final List<Diagnostic> diagnostics;
  final WorkspaceDiagnosticsSnapshot? workspaceDiagnostics;
  final ValueChanged<Diagnostic>? onSelectDiagnostic;
  final ValueChanged<WorkspaceDiagnostic>? onSelectWorkspaceDiagnostic;
  final Future<void> Function()? onRefreshWorkspaceDiagnostics;
  final WorkspaceEditPreview? workspaceEditPreview;
  final List<DiagnosticSeverity> severityFilter;
  final WorkspaceDiagnosticsFilterState? filterState;
  final Future<void> Function()? onPreviewWorkspaceQuickFix;
  final Future<void> Function()? onApplyWorkspaceQuickFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final problemEntries =
        workspaceDiagnostics?.diagnostics ??
        diagnostics
            .map(
              (diagnostic) => WorkspaceDiagnostic(
                documentId: documentId,
                diagnostic: diagnostic,
              ),
            )
            .toList(growable: false);
    final diagnosticsFilter =
        filterState ??
        WorkspaceDiagnosticsFilterState(severities: severityFilter);
    final view = WorkspaceDiagnosticsView.fromDiagnostics(
      providerId: workspaceDiagnostics?.providerId ?? 'active-document',
      diagnostics: problemEntries,
      filter: diagnosticsFilter,
    );
    final visibleProblemEntries = view.visibleDiagnostics;
    final documentGroups = view.documentGroups;
    final severityCounts = view.severityCounts;

    return Card(
      key: const ValueKey('problems-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Problems', style: theme.textTheme.titleLarge),
                  if (onRefreshWorkspaceDiagnostics != null)
                    TextButton.icon(
                      key: const ValueKey('problems-refresh-workspace'),
                      onPressed: onRefreshWorkspaceDiagnostics,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                  if (onPreviewWorkspaceQuickFix != null)
                    TextButton.icon(
                      key: const ValueKey(
                        'problems-preview-workspace-quick-fix',
                      ),
                      onPressed: onPreviewWorkspaceQuickFix,
                      icon: const Icon(Icons.difference_outlined),
                      label: const Text('Preview Project Fix'),
                    ),
                  if (onApplyWorkspaceQuickFix != null)
                    TextButton.icon(
                      key: const ValueKey('problems-apply-workspace-quick-fix'),
                      onPressed: onApplyWorkspaceQuickFix,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('Apply Project Fix'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Diagnostics surface backed by active document diagnostics or a workspace diagnostics snapshot. TODO: add grouping, filters, fix confirmation, and persisted problem state.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Chip(label: Text('document $documentId')),
                  if (workspaceDiagnostics != null)
                    Chip(
                      label: Text(
                        'workspace-documents ${workspaceDiagnostics!.documentIds.length}',
                      ),
                    ),
                  Chip(label: Text('total ${problemEntries.length}')),
                  Chip(label: Text('visible ${visibleProblemEntries.length}')),
                  Chip(label: Text('groups ${documentGroups.length}')),
                  if (diagnosticsFilter.active)
                    Chip(label: Text('filter ${diagnosticsFilter.summary}')),
                  for (final entry in severityCounts.entries)
                    Chip(label: Text('${entry.key} ${entry.value}')),
                ],
              ),
              if (workspaceEditPreview != null) ...[
                const SizedBox(height: 12),
                _WorkspaceEditPreviewCard(preview: workspaceEditPreview!),
              ],
              const SizedBox(height: 12),
              if (problemEntries.isEmpty)
                Text(
                  workspaceDiagnostics == null
                      ? 'No diagnostics for the active document.'
                      : 'No diagnostics for the workspace.',
                  style: theme.textTheme.bodySmall,
                )
              else if (visibleProblemEntries.isEmpty)
                Text(
                  'No diagnostics match the active severity filter.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProblemsDocumentGroupSummary(groups: documentGroups),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: compact ? 180 : 220,
                      child: ListView.separated(
                        key: const ValueKey('problems-diagnostic-list'),
                        itemCount: visibleProblemEntries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = visibleProblemEntries[index];
                          final diagnostic = entry.diagnostic;
                          return ListTile(
                            key: ValueKey(
                              'problems-diagnostic-${diagnostic.code}',
                            ),
                            dense: true,
                            leading: Icon(
                              _diagnosticIcon(diagnostic.severity),
                              color: _diagnosticColor(diagnostic.severity),
                            ),
                            title: Text(diagnostic.message),
                            subtitle: Text(
                              '${entry.documentId} · ${diagnostic.severity.name} · ${diagnostic.code} · offsets ${diagnostic.range.start}-${diagnostic.range.end}',
                            ),
                            trailing: const Icon(Icons.arrow_forward_rounded),
                            onTap:
                                onSelectDiagnostic == null &&
                                    onSelectWorkspaceDiagnostic == null
                                ? null
                                : () {
                                    onSelectWorkspaceDiagnostic?.call(entry);
                                    onSelectDiagnostic?.call(diagnostic);
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProblemsDocumentGroupSummary extends StatelessWidget {
  const _ProblemsDocumentGroupSummary({required this.groups});

  final List<WorkspaceDiagnosticsDocumentGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('problems-document-group-summary'),
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = groups[index];
          return Container(
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.documentId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'total ${group.totalCount} · '
                  'error ${group.severityCounts['error']} · '
                  'warning ${group.severityCounts['warning']} · '
                  'hint ${group.severityCounts['hint']}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceEditPreviewCard extends StatelessWidget {
  const _WorkspaceEditPreviewCard({required this.preview});

  final WorkspaceEditPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changedDocuments = preview.documents
        .where((document) => document.changed)
        .toList(growable: false);
    final sampleDocuments = changedDocuments.take(3).toList(growable: false);
    final hiddenDocumentCount =
        changedDocuments.length - sampleDocuments.length;

    return Container(
      key: const ValueKey('problems-workspace-edit-preview'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Workspace edit preview', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${preview.summary} · ${preview.editCount} edit(s) · '
            '${changedDocuments.length} document(s)',
            key: const ValueKey('problems-workspace-edit-preview-summary'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            preview.canApply
                ? 'Preview ready to apply.'
                : 'Preview blocked until missing documents are loaded.',
            key: const ValueKey('problems-workspace-edit-preview-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: preview.canApply
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          for (final document in sampleDocuments)
            Text(
              '${document.documentId} · rev ${document.revision} · '
              '${document.edits.length} edit(s)',
              style: theme.textTheme.bodySmall,
            ),
          if (hiddenDocumentCount > 0)
            Text(
              '+$hiddenDocumentCount more document(s)',
              style: theme.textTheme.bodySmall,
            ),
          if (preview.hasMissingDocuments)
            Text(
              'Missing preview documents: ${preview.missingDocumentIds.join(', ')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

IconData _diagnosticIcon(DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.error => Icons.error_outline_rounded,
    DiagnosticSeverity.warning => Icons.warning_amber_rounded,
    DiagnosticSeverity.hint => Icons.lightbulb_outline_rounded,
  };
}

Color _diagnosticColor(DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.error => const Color(0xFFC8473A),
    DiagnosticSeverity.warning => const Color(0xFFB7791F),
    DiagnosticSeverity.hint => const Color(0xFF2F6F87),
  };
}
