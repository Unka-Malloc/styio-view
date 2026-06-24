import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../view_ide/language/language_contract.dart';
import '../../view_ide/language/semantic_snapshot_panel.dart';
import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/workspace/workspace.dart';
import '../platform/viewport_profile.dart';

class ProblemsSurface extends StatefulWidget {
  const ProblemsSurface({
    super.key,
    required this.viewportProfile,
    required this.documentId,
    required this.diagnostics,
    this.workspaceDiagnostics,
    this.diagnosticsProducerLifecycles =
        const <WorkspaceDiagnosticsProducerLifecycleSnapshot>[],
    this.onSelectDiagnostic,
    this.onSelectWorkspaceDiagnostic,
    this.onRefreshWorkspaceDiagnostics,
    this.onCancelDiagnosticsProducer,
    this.workspaceEditPreview,
    this.workspaceEditDiffWindow,
    this.severityFilter = const <DiagnosticSeverity>[],
    this.filterState,
    this.onPreviewWorkspaceQuickFix,
    this.onApplyWorkspaceQuickFix,
    this.workspaceEditReviewControls,
    this.workspaceEditApplyResult,
    this.quickFixReviewPlan,
    this.quickFixTelemetry,
    this.semanticSnapshotPanelViewModel,
    this.diagnosticsPanelState,
    this.onDiagnosticsPanelStateChanged,
    this.onApplyWorkspaceEdit,
    this.onCancelWorkspaceEdit,
    this.onApplyQuickFixReviewPlan,
    this.onCancelQuickFixReviewPlan,
    this.onPreviewDiagnosticQuickFix,
    this.onApplyDiagnosticQuickFix,
  });

  final ViewportProfile viewportProfile;
  final String documentId;
  final List<Diagnostic> diagnostics;
  final WorkspaceDiagnosticsSnapshot? workspaceDiagnostics;
  final List<WorkspaceDiagnosticsProducerLifecycleSnapshot>
  diagnosticsProducerLifecycles;
  final ValueChanged<Diagnostic>? onSelectDiagnostic;
  final ValueChanged<WorkspaceDiagnostic>? onSelectWorkspaceDiagnostic;
  final Future<void> Function()? onRefreshWorkspaceDiagnostics;
  final Future<void> Function(
    WorkspaceDiagnosticsProducerLifecycleSnapshot snapshot,
  )?
  onCancelDiagnosticsProducer;
  final WorkspaceEditPreview? workspaceEditPreview;
  final WorkspaceEditDiffWindow? workspaceEditDiffWindow;
  final List<DiagnosticSeverity> severityFilter;
  final WorkspaceDiagnosticsFilterState? filterState;
  final Future<void> Function()? onPreviewWorkspaceQuickFix;
  final Future<void> Function()? onApplyWorkspaceQuickFix;
  final WorkspaceEditReviewControls? workspaceEditReviewControls;
  final WorkspaceEditApplyResultViewModel? workspaceEditApplyResult;
  final WorkspaceQuickFixReviewPlan? quickFixReviewPlan;
  final WorkspaceQuickFixTelemetrySnapshot? quickFixTelemetry;
  final SemanticSnapshotPanelViewModel? semanticSnapshotPanelViewModel;
  final DiagnosticsPanelState? diagnosticsPanelState;
  final ValueChanged<DiagnosticsPanelState>? onDiagnosticsPanelStateChanged;
  final Future<void> Function(WorkspaceEditReviewControls controls)?
  onApplyWorkspaceEdit;
  final Future<void> Function(WorkspaceEditReviewControls controls)?
  onCancelWorkspaceEdit;
  final Future<void> Function(WorkspaceQuickFixReviewPlan plan)?
  onApplyQuickFixReviewPlan;
  final Future<void> Function(WorkspaceQuickFixReviewPlan plan)?
  onCancelQuickFixReviewPlan;
  final Future<void> Function(DiagnosticsQuickFixCommandRoute route)?
  onPreviewDiagnosticQuickFix;
  final Future<void> Function(DiagnosticsQuickFixCommandRoute route)?
  onApplyDiagnosticQuickFix;

  @override
  State<ProblemsSurface> createState() => _ProblemsSurfaceState();
}

class _ProblemsSurfaceState extends State<ProblemsSurface> {
  var _selectedIndex = 0;

  void _activateEntry(WorkspaceDiagnostic entry) {
    widget.onSelectWorkspaceDiagnostic?.call(entry);
    widget.onSelectDiagnostic?.call(entry.diagnostic);
    widget.onDiagnosticsPanelStateChanged?.call(
      DiagnosticsPanelState.fromDiagnostic(
        workspaceId:
            widget.diagnosticsPanelState?.workspaceId ??
            widget.workspaceDiagnostics?.providerId ??
            'active-document',
        diagnostic: entry,
        filterState:
            widget.filterState ??
            WorkspaceDiagnosticsFilterState(severities: widget.severityFilter),
      ),
    );
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
    final restoredIndex = _restoredProblemIndex(
      widget.diagnosticsPanelState,
      visibleProblemEntries,
    );
    final selectedIndex = visibleProblemEntries.isEmpty
        ? -1
        : _clampedProblemIndex(
            restoredIndex ?? _selectedIndex,
            visibleProblemEntries.length,
          );
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
                    if (widget.diagnosticsPanelState?.hasSelection ?? false)
                      Chip(
                        key: const ValueKey('problems-restored-panel-state'),
                        label: Text(
                          'restored ${widget.diagnosticsPanelState!.selectedDiagnosticCode}',
                        ),
                      ),
                    for (final entry in severityCounts.entries)
                      Chip(label: Text('${entry.key} ${entry.value}')),
                  ],
                ),
                if (widget.workspaceEditPreview != null) ...[
                  const SizedBox(height: 12),
                  _WorkspaceEditPreviewCard(
                    preview: widget.workspaceEditPreview!,
                    diffWindow: widget.workspaceEditDiffWindow,
                    reviewControls: workspaceEditReviewControls!,
                    onApply: widget.onApplyWorkspaceEdit,
                    onCancel: widget.onCancelWorkspaceEdit,
                  ),
                ],
                if (widget.workspaceEditApplyResult != null) ...[
                  const SizedBox(height: 12),
                  _WorkspaceEditApplyResultCard(
                    result: widget.workspaceEditApplyResult!,
                  ),
                ],
                if (widget.quickFixTelemetry != null) ...[
                  const SizedBox(height: 12),
                  _WorkspaceQuickFixTelemetryCard(
                    telemetry: widget.quickFixTelemetry!,
                  ),
                ],
                if (widget.diagnosticsProducerLifecycles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DiagnosticsProducerLifecyclePanel(
                    snapshots: widget.diagnosticsProducerLifecycles,
                    onCancel: widget.onCancelDiagnosticsProducer,
                  ),
                ],
                if (widget.quickFixReviewPlan != null) ...[
                  const SizedBox(height: 12),
                  _WorkspaceQuickFixReviewCard(
                    reviewPlan: widget.quickFixReviewPlan!,
                    onApply: widget.onApplyQuickFixReviewPlan,
                    onCancel: widget.onCancelQuickFixReviewPlan,
                  ),
                ],
                if (widget.semanticSnapshotPanelViewModel != null) ...[
                  const SizedBox(height: 12),
                  _SemanticSnapshotProblemsCard(
                    viewModel: widget.semanticSnapshotPanelViewModel!,
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
                        _ProblemQuickFixSelection(
                          entry: selectedEntry!,
                          onPreview: widget.onPreviewDiagnosticQuickFix,
                          onApply: widget.onApplyDiagnosticQuickFix,
                        ),
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

int? _restoredProblemIndex(
  DiagnosticsPanelState? state,
  List<WorkspaceDiagnostic> entries,
) {
  if (state == null || !state.hasSelection) {
    return null;
  }
  final index = entries.indexWhere((entry) {
    final diagnostic = entry.diagnostic;
    return entry.documentId == state.selectedDocumentId &&
        diagnostic.code == state.selectedDiagnosticCode &&
        diagnostic.range.start == state.selectedRangeStart &&
        diagnostic.range.end == state.selectedRangeEnd;
  });
  return index < 0 ? null : index;
}

class _SemanticSnapshotProblemsCard extends StatelessWidget {
  const _SemanticSnapshotProblemsCard({required this.viewModel});

  final SemanticSnapshotPanelViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('problems-semantic-snapshot-panel'),
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
          Text(
            'Semantic ${viewModel.title}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text('revision ${viewModel.revision}')),
              Chip(label: Text('items ${viewModel.itemCount}')),
              Chip(label: Text('code-actions ${viewModel.codeActionCount}')),
            ],
          ),
          const SizedBox(height: 8),
          if (viewModel.empty)
            Text(
              'No semantic panel events recorded.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final item in viewModel.items.take(5))
              ListTile(
                key: ValueKey('problems-semantic-event-${item.id}'),
                dense: true,
                leading: Icon(
                  item.severity == 'success'
                      ? Icons.check_circle_outline
                      : item.severity == 'warning'
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline,
                ),
                title: Text(
                  item.actionLabel.isEmpty ? item.title : item.actionLabel,
                ),
                subtitle: Text(
                  '${item.documentId} · ${item.kind.wireValue} · ${item.message}',
                ),
              ),
        ],
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

class _ProblemQuickFixSelection extends StatelessWidget {
  const _ProblemQuickFixSelection({
    required this.entry,
    this.onPreview,
    this.onApply,
  });

  final WorkspaceDiagnostic entry;
  final Future<void> Function(DiagnosticsQuickFixCommandRoute route)? onPreview;
  final Future<void> Function(DiagnosticsQuickFixCommandRoute route)? onApply;

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
          for (final indexedFix in entry.quickFixes.indexed)
            _ProblemQuickFixRouteRow(
              entry: entry,
              quickFixIndex: indexedFix.$1,
              fix: indexedFix.$2,
              onPreview: onPreview,
              onApply: onApply,
            ),
        ],
      ),
    );
  }
}

class _ProblemQuickFixRouteRow extends StatelessWidget {
  const _ProblemQuickFixRouteRow({
    required this.entry,
    required this.quickFixIndex,
    required this.fix,
    this.onPreview,
    this.onApply,
  });

  final WorkspaceDiagnostic entry;
  final int quickFixIndex;
  final DiagnosticQuickFix fix;
  final Future<void> Function(DiagnosticsQuickFixCommandRoute route)? onPreview;
  final Future<void> Function(DiagnosticsQuickFixCommandRoute route)? onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewRoute = DiagnosticsQuickFixCommandRoute.preview(
      diagnostic: entry,
      quickFixIndex: quickFixIndex,
    );
    final applyRoute = DiagnosticsQuickFixCommandRoute.apply(
      diagnostic: entry,
      quickFixIndex: quickFixIndex,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${fix.label} · edits ${fix.edits.length}',
            style: theme.textTheme.bodySmall,
          ),
          OutlinedButton(
            key: ValueKey(
              'problems-preview-fix-${entry.diagnostic.code}-$quickFixIndex',
            ),
            onPressed: previewRoute.enabled && onPreview != null
                ? () {
                    onPreview!(previewRoute);
                  }
                : null,
            child: const Text('Preview Fix'),
          ),
          FilledButton.tonal(
            key: ValueKey(
              'problems-apply-fix-${entry.diagnostic.code}-$quickFixIndex',
            ),
            onPressed: applyRoute.enabled && onApply != null
                ? () {
                    onApply!(applyRoute);
                  }
                : null,
            child: const Text('Apply Fix'),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsProducerLifecyclePanel extends StatelessWidget {
  const _DiagnosticsProducerLifecyclePanel({
    required this.snapshots,
    this.onCancel,
  });

  final List<WorkspaceDiagnosticsProducerLifecycleSnapshot> snapshots;
  final Future<void> Function(
    WorkspaceDiagnosticsProducerLifecycleSnapshot snapshot,
  )?
  onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('problems-diagnostics-producer-lifecycle-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Diagnostics producers', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final snapshot in snapshots)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                key: ValueKey(
                  'problems-diagnostics-producer-lifecycle-${snapshot.providerId}',
                ),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${snapshot.providerId} · ${snapshot.status.name}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (snapshot.canCancel && onCancel != null)
                        TextButton.icon(
                          key: ValueKey(
                            'problems-diagnostics-producer-cancel-${snapshot.providerId}',
                          ),
                          onPressed: () {
                            onCancel!(snapshot);
                          },
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Cancel'),
                        ),
                    ],
                  ),
                  if (snapshot.message.isNotEmpty)
                    Text(snapshot.message, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    key: ValueKey(
                      'problems-diagnostics-producer-progress-${snapshot.providerId}',
                    ),
                    value: snapshot.progress,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snapshot.hasProgress
                        ? 'progress ${(snapshot.progress! * 100).round()}%'
                        : 'progress indeterminate',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceEditApplyResultCard extends StatelessWidget {
  const _WorkspaceEditApplyResultCard({required this.result});

  final WorkspaceEditApplyResultViewModel result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (result.status) {
      WorkspaceEditReviewResultStatus.applied => theme.colorScheme.primary,
      WorkspaceEditReviewResultStatus.canceled => theme.colorScheme.secondary,
      WorkspaceEditReviewResultStatus.blocked => theme.colorScheme.tertiary,
      WorkspaceEditReviewResultStatus.failed => theme.colorScheme.error,
    };
    return Container(
      key: const ValueKey('problems-workspace-edit-apply-result'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${result.status.wireValue} · ${result.source.wireValue} · '
            '${result.affectedDocumentCount} affected document(s) · '
            '${result.appliedEditCount} applied edit(s)',
            key: const ValueKey('problems-workspace-edit-apply-result-summary'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result.message,
            key: const ValueKey('problems-workspace-edit-apply-result-message'),
            style: theme.textTheme.bodySmall,
          ),
          if (result.rollbackApplied) ...[
            const SizedBox(height: 4),
            Text(
              'Rollback was applied.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (result.appliedDocumentIds.isNotEmpty ||
              result.createdDocumentIds.isNotEmpty ||
              result.deletedDocumentIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final documentId in result.appliedDocumentIds.take(4))
                  Chip(label: Text('applied $documentId')),
                for (final documentId in result.createdDocumentIds.take(4))
                  Chip(label: Text('created $documentId')),
                for (final documentId in result.deletedDocumentIds.take(4))
                  Chip(label: Text('deleted $documentId')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceQuickFixTelemetryCard extends StatelessWidget {
  const _WorkspaceQuickFixTelemetryCard({required this.telemetry});

  final WorkspaceQuickFixTelemetrySnapshot telemetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('problems-quick-fix-telemetry'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick-fix outcomes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text('outcomes ${telemetry.outcomes.length}')),
              Chip(label: Text('applied ${telemetry.appliedCount}')),
              Chip(label: Text('blocked ${telemetry.blockedCount}')),
              if (telemetry.updatedAt != null)
                Chip(label: Text('updated ${telemetry.updatedAt!.toUtc()}')),
            ],
          ),
          const SizedBox(height: 8),
          if (telemetry.outcomes.isEmpty)
            Text(
              'No quick-fix outcomes have been recorded.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final outcome in telemetry.outcomes.take(6))
              ListTile(
                key: ValueKey(
                  'problems-quick-fix-outcome-${outcome.planId}-${outcome.outcomeKind.wireValue}',
                ),
                dense: true,
                leading: Icon(
                  outcome.applied
                      ? Icons.check_circle_outline
                      : outcome.blocked
                      ? Icons.block_rounded
                      : Icons.pending_actions_rounded,
                ),
                title: Text(
                  '${outcome.outcomeKind.wireValue} ${outcome.diagnosticCode} #${outcome.quickFixIndex}',
                ),
                subtitle: Text(
                  '${outcome.documentId} · ${outcome.confirmationStatus.wireValue} · ${outcome.message}',
                ),
              ),
          if (telemetry.outcomes.length > 6)
            Text(
              'TODO: virtualize older quick-fix outcome rows.',
              style: theme.textTheme.bodySmall,
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
    this.diffWindow,
    this.cardKey = const ValueKey('problems-workspace-edit-preview'),
    this.applyKey = const ValueKey('problems-workspace-edit-apply'),
    this.cancelKey = const ValueKey('problems-workspace-edit-cancel'),
    this.title = 'Workspace edit preview',
    this.onApply,
    this.onCancel,
  });

  final WorkspaceEditPreview preview;
  final WorkspaceEditReviewControls reviewControls;
  final WorkspaceEditDiffWindow? diffWindow;
  final Key cardKey;
  final Key applyKey;
  final Key cancelKey;
  final String title;
  final Future<void> Function(WorkspaceEditReviewControls controls)? onApply;
  final Future<void> Function(WorkspaceEditReviewControls controls)? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmation = reviewControls.confirmationPlan;
    final effectiveWindow =
        diffWindow ??
        preview.diffWindow(documentLimit: 3, fileOperationLimit: 3);
    final sampleDocuments = effectiveWindow.documents
        .where((document) => document.changed)
        .toList(growable: false);
    final hiddenDocumentCount =
        effectiveWindow.totalDocumentCount -
        (effectiveWindow.documentOffset + effectiveWindow.documents.length);
    final sampleFileOperations = effectiveWindow.fileOperations;
    final hiddenFileOperationCount =
        effectiveWindow.totalFileOperationCount -
        (effectiveWindow.fileOperationOffset +
            effectiveWindow.fileOperations.length);

    return Container(
      key: cardKey,
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
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${preview.summary} · ${preview.editCount} edit(s) · '
            '${effectiveWindow.totalDocumentCount} document(s)',
            key: const ValueKey('problems-workspace-edit-preview-summary'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Diff window documents ${effectiveWindow.documentOffset}+${effectiveWindow.documents.length}/${effectiveWindow.totalDocumentCount} · '
            'file operations ${effectiveWindow.fileOperationOffset}+${effectiveWindow.fileOperations.length}/${effectiveWindow.totalFileOperationCount}',
            key: const ValueKey('problems-workspace-edit-diff-window'),
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
                key: applyKey,
                onPressed: reviewControls.apply.enabled && onApply != null
                    ? () {
                        onApply!(reviewControls);
                      }
                    : null,
                icon: const Icon(Icons.done_all_rounded),
                label: Text(reviewControls.apply.label),
              ),
              OutlinedButton.icon(
                key: cancelKey,
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
          for (final operation in sampleFileOperations)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${operation.operation.kind.wireValue}: '
                '${operation.operation.documentId} · ${operation.status.wireValue}',
                key: ValueKey(
                  'problems-workspace-edit-file-operation-${operation.operation.documentId}',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (hiddenFileOperationCount > 0)
            Text(
              '+$hiddenFileOperationCount more file operation(s)',
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

class _WorkspaceQuickFixReviewCard extends StatelessWidget {
  const _WorkspaceQuickFixReviewCard({
    required this.reviewPlan,
    this.onApply,
    this.onCancel,
  });

  final WorkspaceQuickFixReviewPlan reviewPlan;
  final Future<void> Function(WorkspaceQuickFixReviewPlan plan)? onApply;
  final Future<void> Function(WorkspaceQuickFixReviewPlan plan)? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = reviewPlan.preview;
    final controls = reviewPlan.controls;
    return Container(
      key: const ValueKey('problems-quick-fix-review'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick-fix review', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${reviewPlan.diagnostic.documentId} · '
            '${reviewPlan.diagnostic.diagnostic.code} · '
            'fix ${reviewPlan.quickFixIndex}',
            key: const ValueKey('problems-quick-fix-review-summary'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${reviewPlan.confirmationPlan.status.wireValue} · '
            '${reviewPlan.confirmationPlan.message}',
            key: const ValueKey('problems-quick-fix-review-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: reviewPlan.ready
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          if (preview != null && controls != null) ...[
            const SizedBox(height: 10),
            _WorkspaceEditPreviewCard(
              cardKey: const ValueKey('problems-quick-fix-review-preview'),
              applyKey: const ValueKey('problems-quick-fix-review-apply'),
              cancelKey: const ValueKey('problems-quick-fix-review-cancel'),
              title: 'Quick-fix diff preview',
              preview: preview,
              diffWindow: reviewPlan.diffWindow(
                documentLimit: 3,
                fileOperationLimit: 3,
              ),
              reviewControls: controls,
              onApply: onApply == null ? null : (_) => onApply!(reviewPlan),
              onCancel: onCancel == null ? null : (_) => onCancel!(reviewPlan),
            ),
          ],
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
