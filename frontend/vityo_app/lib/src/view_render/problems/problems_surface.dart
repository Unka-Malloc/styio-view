import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../view_ide/language/language_contract.dart';
import '../../view_ide/workspace/workspace.dart';
import '../platform/viewport_profile.dart';

class ProblemsSurface extends StatefulWidget {
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
    this.workspaceEditReviewControls,
    this.onApplyWorkspaceEdit,
    this.onCancelWorkspaceEdit,
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
  final WorkspaceEditReviewControls? workspaceEditReviewControls;
  final Future<void> Function(WorkspaceEditReviewControls controls)?
  onApplyWorkspaceEdit;
  final Future<void> Function(WorkspaceEditReviewControls controls)?
  onCancelWorkspaceEdit;

  @override
  State<ProblemsSurface> createState() => _ProblemsSurfaceState();
}

class _ProblemsSurfaceState extends State<ProblemsSurface> {
  var _selectedIndex = 0;

  void _activateEntry(WorkspaceDiagnostic entry) {
    widget.onSelectWorkspaceDiagnostic?.call(entry);
    widget.onSelectDiagnostic?.call(entry.diagnostic);
  }

  void _selectIndex(int index, List<WorkspaceDiagnostic> entries) {
    if (entries.isEmpty) {
      return;
    }
    setState(() {
      _selectedIndex = index.clamp(0, entries.length - 1);
    });
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    List<WorkspaceDiagnostic> entries,
  ) {
    if (event is! KeyDownEvent || entries.isEmpty) {
      return KeyEventResult.ignored;
    }
    final selectedIndex = _clampedProblemIndex(_selectedIndex, entries.length);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectIndex(selectedIndex + 1, entries);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectIndex(selectedIndex - 1, entries);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _activateEntry(entries[selectedIndex]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final problemEntries =
        widget.workspaceDiagnostics?.diagnostics ??
        widget.diagnostics
            .map(
              (diagnostic) => WorkspaceDiagnostic(
                documentId: widget.documentId,
                diagnostic: diagnostic,
              ),
            )
            .toList(growable: false);
    final diagnosticsFilter =
        widget.filterState ??
        WorkspaceDiagnosticsFilterState(severities: widget.severityFilter);
    final view = WorkspaceDiagnosticsView.fromDiagnostics(
      providerId: widget.workspaceDiagnostics?.providerId ?? 'active-document',
      diagnostics: problemEntries,
      filter: diagnosticsFilter,
    );
    final visibleProblemEntries = view.visibleDiagnostics;
    final selectedIndex = visibleProblemEntries.isEmpty
        ? -1
        : _clampedProblemIndex(_selectedIndex, visibleProblemEntries.length);
    final selectedEntry = selectedIndex < 0
        ? null
        : visibleProblemEntries[selectedIndex];
    final workspaceEditReviewControls = widget.workspaceEditPreview == null
        ? null
        : widget.workspaceEditReviewControls ??
              WorkspaceEditReviewControls.fromPreview(
                widget.workspaceEditPreview!,
              );
    final documentGroups = view.documentGroups;
    final severityCounts = view.severityCounts;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event, visibleProblemEntries),
      child: Card(
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
                    if (widget.onRefreshWorkspaceDiagnostics != null)
                      TextButton.icon(
                        key: const ValueKey('problems-refresh-workspace'),
                        onPressed: widget.onRefreshWorkspaceDiagnostics,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Refresh'),
                      ),
                    if (widget.onPreviewWorkspaceQuickFix != null)
                      TextButton.icon(
                        key: const ValueKey(
                          'problems-preview-workspace-quick-fix',
                        ),
                        onPressed: widget.onPreviewWorkspaceQuickFix,
                        icon: const Icon(Icons.difference_outlined),
                        label: const Text('Preview Project Fix'),
                      ),
                    if (widget.onApplyWorkspaceQuickFix != null)
                      TextButton.icon(
                        key: const ValueKey(
                          'problems-apply-workspace-quick-fix',
                        ),
                        onPressed: widget.onApplyWorkspaceQuickFix,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Apply Project Fix'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Diagnostics surface backed by active document diagnostics or a workspace diagnostics snapshot, with grouping, filters, quick-fix confirmation, and keyboard navigation. TODO: add persisted problem state.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('document ${widget.documentId}')),
                    if (widget.workspaceDiagnostics != null)
                      Chip(
                        label: Text(
                          'workspace-documents ${widget.workspaceDiagnostics!.documentIds.length}',
                        ),
                      ),
                    Chip(label: Text('total ${problemEntries.length}')),
                    Chip(
                      label: Text('visible ${visibleProblemEntries.length}'),
                    ),
                    Chip(label: Text('groups ${documentGroups.length}')),
                    if (selectedIndex >= 0)
                      Chip(
                        key: const ValueKey('problems-selected-diagnostic'),
                        label: Text(
                          'selected ${visibleProblemEntries[selectedIndex].diagnostic.code}',
                        ),
                      ),
                    if (selectedEntry?.hasQuickFixes ?? false)
                      Chip(
                        key: const ValueKey('problems-selected-quick-fixes'),
                        label: Text(
                          'selected-fixes ${selectedEntry!.quickFixes.length}',
                        ),
                      ),
                    if (diagnosticsFilter.active)
                      Chip(label: Text('filter ${diagnosticsFilter.summary}')),
                    for (final entry in severityCounts.entries)
                      Chip(label: Text('${entry.key} ${entry.value}')),
                  ],
                ),
                if (widget.workspaceEditPreview != null) ...[
                  const SizedBox(height: 12),
                  _WorkspaceEditPreviewCard(
                    preview: widget.workspaceEditPreview!,
                    reviewControls: workspaceEditReviewControls!,
                    onApply: widget.onApplyWorkspaceEdit,
                    onCancel: widget.onCancelWorkspaceEdit,
                  ),
                ],
                const SizedBox(height: 12),
                if (problemEntries.isEmpty)
                  Text(
                    widget.workspaceDiagnostics == null
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
                      if (selectedEntry?.hasQuickFixes ?? false) ...[
                        const SizedBox(height: 10),
                        _ProblemQuickFixSelection(entry: selectedEntry!),
                      ],
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
                            final selected = index == selectedIndex;
                            return ListTile(
                              key: ValueKey(
                                'problems-diagnostic-${diagnostic.code}',
                              ),
                              dense: true,
                              selected: selected,
                              selectedTileColor:
                                  theme.colorScheme.primaryContainer,
                              leading: Icon(
                                _diagnosticIcon(diagnostic.severity),
                                color: _diagnosticColor(diagnostic.severity),
                              ),
                              title: Text(diagnostic.message),
                              subtitle: Text(
                                '${entry.documentId} · ${diagnostic.severity.name} · ${diagnostic.code} · offsets ${diagnostic.range.start}-${diagnostic.range.end}',
                              ),
                              trailing: entry.hasQuickFixes
                                  ? Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Chip(
                                          label: Text(
                                            'fixes ${entry.quickFixes.length}',
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_rounded),
                                      ],
                                    )
                                  : const Icon(Icons.arrow_forward_rounded),
                              onTap:
                                  widget.onSelectDiagnostic == null &&
                                      widget.onSelectWorkspaceDiagnostic == null
                                  ? null
                                  : () {
                                      _selectIndex(
                                        index,
                                        visibleProblemEntries,
                                      );
                                      _activateEntry(entry);
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
      ),
    );
  }
}

int _clampedProblemIndex(int index, int length) {
  if (length <= 0) {
    return -1;
  }
  return index.clamp(0, length - 1);
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

class _ProblemQuickFixSelection extends StatelessWidget {
  const _ProblemQuickFixSelection({required this.entry});

  final WorkspaceDiagnostic entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('problems-quick-fix-selection'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Fixes: ${entry.diagnostic.code}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          for (final fix in entry.quickFixes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${fix.label} · edits ${fix.edits.length}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceEditPreviewCard extends StatelessWidget {
  const _WorkspaceEditPreviewCard({
    required this.preview,
    required this.reviewControls,
    this.onApply,
    this.onCancel,
  });

  final WorkspaceEditPreview preview;
  final WorkspaceEditReviewControls reviewControls;
  final Future<void> Function(WorkspaceEditReviewControls controls)? onApply;
  final Future<void> Function(WorkspaceEditReviewControls controls)? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmation = reviewControls.confirmationPlan;
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
          Text(
            '${confirmation.status.wireValue} · ${confirmation.message}',
            key: const ValueKey('problems-workspace-edit-confirmation-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: confirmation.ready
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                key: const ValueKey('problems-workspace-edit-apply'),
                onPressed: reviewControls.apply.enabled && onApply != null
                    ? () {
                        onApply!(reviewControls);
                      }
                    : null,
                icon: const Icon(Icons.done_all_rounded),
                label: Text(reviewControls.apply.label),
              ),
              OutlinedButton.icon(
                key: const ValueKey('problems-workspace-edit-cancel'),
                onPressed: reviewControls.cancel.enabled && onCancel != null
                    ? () {
                        onCancel!(reviewControls);
                      }
                    : null,
                icon: const Icon(Icons.close_rounded),
                label: Text(reviewControls.cancel.label),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final document in sampleDocuments)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${document.documentId} · rev ${document.revision} · '
                    '${document.edits.length} edit(s)',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'Before: ${_workspaceEditPreviewSnippet(document.beforeText)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    'After: ${_workspaceEditPreviewSnippet(document.afterText)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
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

String _workspaceEditPreviewSnippet(String text, {int maxLength = 96}) {
  final normalized = text
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(2)
      .join(' / ')
      .trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 3)}...';
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
