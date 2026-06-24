import 'package:flutter/material.dart';

import '../../view_ide/workspace/source_control_commit_draft_store.dart';
import '../../view_ide/workspace/source_control_status.dart';
import '../platform/viewport_profile.dart';

class SourceControlSurface extends StatelessWidget {
  const SourceControlSurface({
    super.key,
    required this.viewportProfile,
    required this.workspaceFileCount,
    required this.changedDocumentIds,
    this.status,
    this.diffPreview,
    this.diffWindowBinding,
    this.commitDraft,
    this.commitDialogState,
    this.branchSnapshot,
    this.historySnapshot,
    this.adapterRegistry,
    this.lastHunkActionResult,
    this.pendingHunkDiscardConfirmation,
    this.onOpenFile,
    this.onSaveAll,
    this.onRefresh,
    this.onPreviewDiff,
    this.onStagePaths,
    this.onUnstagePaths,
    this.onSwitchBranch,
    this.onOpenCommit,
    this.onConfirmDiffAction,
    this.onSelectHunkAction,
    this.onConfirmHunkDiscard,
  });

  final ViewportProfile viewportProfile;
  final int workspaceFileCount;
  final List<String> changedDocumentIds;
  final SourceControlStatusSnapshot? status;
  final SourceControlDiffSnapshot? diffPreview;
  final SourceControlDiffWindowBinding? diffWindowBinding;
  final SourceControlCommitDraft? commitDraft;
  final SourceControlCommitDialogState? commitDialogState;
  final SourceControlBranchSnapshot? branchSnapshot;
  final SourceControlHistorySnapshot? historySnapshot;
  final SourceControlProviderAdapterRegistry? adapterRegistry;
  final SourceControlPartialPatchResult? lastHunkActionResult;
  final SourceControlHunkDiscardConfirmationPlan?
  pendingHunkDiscardConfirmation;
  final Future<void> Function(String documentId)? onOpenFile;
  final Future<void> Function()? onSaveAll;
  final Future<void> Function()? onRefresh;
  final Future<void> Function(String documentId)? onPreviewDiff;
  final Future<void> Function(List<String> paths)? onStagePaths;
  final Future<void> Function(List<String> paths)? onUnstagePaths;
  final Future<void> Function(SourceControlBranchSwitchPlan plan)?
  onSwitchBranch;
  final Future<void> Function()? onOpenCommit;
  final Future<void> Function(SourceControlDiffConfirmationPlan plan)?
  onConfirmDiffAction;
  final Future<void> Function(SourceControlDiffHunkActionPlan plan)?
  onSelectHunkAction;
  final Future<void> Function()? onConfirmHunkDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final providerKind =
        status?.providerKind.wireValue ?? 'local-dirty-documents';
    final gitChanges = status?.changes ?? const <SourceControlFileChange>[];
    final statusAvailable = status?.available ?? true;
    final stagedPaths = gitChanges
        .where((change) => change.staged)
        .map((change) => change.path)
        .toList(growable: false);
    final unstagedPaths = gitChanges
        .where((change) => change.unstaged)
        .map((change) => change.path)
        .toList(growable: false);
    final providerAdapters =
        adapterRegistry?.adapters ??
        const <SourceControlProviderAdapterDescriptor>[];
    final activeDiffWindowBinding =
        diffWindowBinding ??
        (diffPreview == null
            ? null
            : SourceControlDiffWindowBinding(snapshot: diffPreview!));
    final activeDiffWindow = activeDiffWindowBinding?.window;

    return Card(
      key: const ValueKey('source-control-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Source Control', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Local IDE change surface backed by dirty editor documents and injectable SCM providers. Stage, unstage, branch switch planning, history summaries, and commit dialog state are surfaced here. TODO: add richer diff confirmation.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Chip(label: Text('workspace-files $workspaceFileCount')),
                  Chip(label: Text('changed ${changedDocumentIds.length}')),
                  Chip(label: Text('provider $providerKind')),
                  if (!statusAvailable)
                    const Chip(label: Text('provider unavailable')),
                  if (status?.branchName.isNotEmpty == true)
                    Chip(label: Text('branch ${status!.branchName}')),
                  if (branchSnapshot != null)
                    Chip(
                      label: Text(
                        'branches ${branchSnapshot!.branches.length}',
                      ),
                    ),
                  if (historySnapshot != null)
                    Chip(
                      label: Text('history ${historySnapshot!.entries.length}'),
                    ),
                  if (providerAdapters.isNotEmpty)
                    Chip(label: Text('providers ${providerAdapters.length}')),
                  if (commitDraft != null)
                    Chip(
                      label: Text(
                        commitDraft!.hasMessage
                            ? 'draft ready'
                            : 'draft pending',
                      ),
                    ),
                  if (commitDialogState != null)
                    Chip(
                      label: Text(
                        'commit-dialog ${commitDialogState!.status.wireValue}',
                      ),
                    ),
                  if (status != null)
                    Chip(label: Text('git ${gitChanges.length}')),
                  if (status != null)
                    Chip(label: Text('staged ${stagedPaths.length}')),
                  if (status != null)
                    Chip(label: Text('unstaged ${unstagedPaths.length}')),
                ],
              ),
              if (commitDraft != null ||
                  branchSnapshot != null ||
                  historySnapshot != null ||
                  providerAdapters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (commitDraft != null)
                      _CommitDraftCard(
                        draft: commitDraft!,
                        dialogState: commitDialogState,
                      ),
                    if (branchSnapshot != null)
                      _BranchPickerSummary(
                        snapshot: branchSnapshot!,
                        onSwitchBranch: onSwitchBranch,
                      ),
                    if (historySnapshot != null)
                      _HistorySummary(snapshot: historySnapshot!),
                    if (providerAdapters.isNotEmpty)
                      _ProviderAdapterSummary(adapters: providerAdapters),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (!statusAvailable && status?.message.isNotEmpty == true) ...[
                Text(
                  status!.message,
                  key: const ValueKey('source-control-provider-message'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('source-control-save-all'),
                    onPressed: changedDocumentIds.isEmpty ? null : onSaveAll,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save All'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('source-control-refresh'),
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('source-control-stage-all'),
                    onPressed: unstagedPaths.isEmpty || onStagePaths == null
                        ? null
                        : () {
                            onStagePaths!(unstagedPaths);
                          },
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text('Stage All'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('source-control-unstage-all'),
                    onPressed: stagedPaths.isEmpty || onUnstagePaths == null
                        ? null
                        : () {
                            onUnstagePaths!(stagedPaths);
                          },
                    icon: const Icon(Icons.remove_done_rounded),
                    label: const Text('Unstage All'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('source-control-open-commit'),
                    onPressed: stagedPaths.isEmpty ? null : onOpenCommit,
                    icon: const Icon(Icons.commit_rounded),
                    label: const Text('Commit...'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (gitChanges.isNotEmpty) ...[
                Text('Git Changes', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SizedBox(
                  height: compact ? 160 : 220,
                  child: ListView.separated(
                    key: const ValueKey('source-control-git-change-list'),
                    itemCount: gitChanges.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final change = gitChanges[index];
                      return ListTile(
                        key: ValueKey(
                          'source-control-git-change-${change.path}',
                        ),
                        dense: true,
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(change.path),
                        subtitle: Text(change.summary),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (change.originalPath.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('from ${change.originalPath}'),
                              ),
                            IconButton(
                              key: ValueKey(
                                'source-control-preview-diff-${change.path}',
                              ),
                              tooltip: 'Preview diff',
                              onPressed: onPreviewDiff == null
                                  ? null
                                  : () {
                                      onPreviewDiff!(change.path);
                                    },
                              icon: const Icon(Icons.difference_outlined),
                            ),
                          ],
                        ),
                        onTap: onOpenFile == null
                            ? null
                            : () {
                                onOpenFile!(change.path);
                              },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (diffPreview != null) ...[
                Text('Diff Preview', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('source-control-diff-review-summary'),
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      label: Text(
                        'hunks ${diffPreview!.reviewSummary.hunkCount}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        '+${diffPreview!.reviewSummary.additionCount} -${diffPreview!.reviewSummary.deletionCount}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'diff-lines ${diffPreview!.reviewSummary.lineCount}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'virtual-window ${activeDiffWindow!.startLine}-${activeDiffWindow.endLine}/${activeDiffWindow.totalLineCount}',
                      ),
                    ),
                    if (activeDiffWindow.hasPrevious)
                      const Chip(label: Text('has previous window')),
                    if (activeDiffWindow.hasNext)
                      const Chip(label: Text('has next window')),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('source-control-diff-preview'),
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      activeDiffWindowBinding!.visibleText,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _DiffConfirmationControls(
                  snapshot: diffPreview!,
                  onConfirmDiffAction: onConfirmDiffAction,
                ),
                const SizedBox(height: 8),
                _DiffHunkActionSelection(
                  snapshot: diffPreview!,
                  lastHunkActionResult: lastHunkActionResult,
                  pendingHunkDiscardConfirmation:
                      pendingHunkDiscardConfirmation,
                  onSelectHunkAction: onSelectHunkAction,
                  onConfirmHunkDiscard: onConfirmHunkDiscard,
                ),
                const SizedBox(height: 12),
              ],
              Text('Changes', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (changedDocumentIds.isEmpty)
                Text(
                  'No dirty editor documents are currently tracked.',
                  style: theme.textTheme.bodySmall,
                )
              else
                SizedBox(
                  height: compact ? 160 : 220,
                  child: ListView.separated(
                    key: const ValueKey('source-control-change-list'),
                    itemCount: changedDocumentIds.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final documentId = changedDocumentIds[index];
                      return ListTile(
                        key: ValueKey('source-control-change-$documentId'),
                        dense: true,
                        leading: const Icon(Icons.edit_note_rounded),
                        title: Text(documentId),
                        subtitle: const Text('modified in editor buffer'),
                        trailing: const Icon(Icons.open_in_new_rounded),
                        onTap: onOpenFile == null
                            ? null
                            : () {
                                onOpenFile!(documentId);
                              },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiffConfirmationControls extends StatelessWidget {
  const _DiffConfirmationControls({
    required this.snapshot,
    this.onConfirmDiffAction,
  });

  final SourceControlDiffSnapshot snapshot;
  final Future<void> Function(SourceControlDiffConfirmationPlan plan)?
  onConfirmDiffAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stagePlan = SourceControlDiffConfirmationPlan.fromDiff(
      snapshot: snapshot,
      kind: SourceControlActionKind.stage,
    );
    final discardPlan = SourceControlDiffConfirmationPlan.fromDiff(
      snapshot: snapshot,
      kind: SourceControlActionKind.discard,
    );
    return Container(
      key: const ValueKey('source-control-diff-confirmation'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Diff confirmation', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Confirm actions only after the visible diff review summary has been loaded. TODO: add per-hunk selection before executing partial actions.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                label: Text(
                  '+${stagePlan.reviewSummary.additionCount} -${stagePlan.reviewSummary.deletionCount}',
                ),
              ),
              Chip(label: Text('stage risk ${stagePlan.risk.wireValue}')),
              Chip(label: Text('discard risk ${discardPlan.risk.wireValue}')),
              if (discardPlan.requiresConfirmation)
                const Chip(label: Text('discard requires confirmation')),
              if (!stagePlan.canRun) Chip(label: Text(stagePlan.blockedReason)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('source-control-confirm-diff-stage'),
                onPressed: stagePlan.canRun && onConfirmDiffAction != null
                    ? () {
                        onConfirmDiffAction!(stagePlan);
                      }
                    : null,
                icon: const Icon(Icons.add_task_rounded),
                label: const Text('Stage Reviewed Diff'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('source-control-confirm-diff-discard'),
                onPressed: discardPlan.canRun && onConfirmDiffAction != null
                    ? () {
                        onConfirmDiffAction!(discardPlan);
                      }
                    : null,
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Discard Reviewed Diff'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiffHunkActionSelection extends StatelessWidget {
  const _DiffHunkActionSelection({
    required this.snapshot,
    this.lastHunkActionResult,
    this.pendingHunkDiscardConfirmation,
    this.onSelectHunkAction,
    this.onConfirmHunkDiscard,
  });

  final SourceControlDiffSnapshot snapshot;
  final SourceControlPartialPatchResult? lastHunkActionResult;
  final SourceControlHunkDiscardConfirmationPlan?
  pendingHunkDiscardConfirmation;
  final Future<void> Function(SourceControlDiffHunkActionPlan plan)?
  onSelectHunkAction;
  final Future<void> Function()? onConfirmHunkDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hunks = snapshot.hunks;
    return Container(
      key: const ValueKey('source-control-hunk-action-selection'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hunk action selection', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Select hunk-level stage/discard plans and route them through the configured SCM partial patch provider.',
            style: theme.textTheme.bodySmall,
          ),
          if (lastHunkActionResult != null) ...[
            const SizedBox(height: 8),
            _HunkActionResultRow(result: lastHunkActionResult!),
          ],
          if (pendingHunkDiscardConfirmation != null) ...[
            const SizedBox(height: 8),
            _HunkDiscardConfirmationCard(
              plan: pendingHunkDiscardConfirmation!,
              onConfirmHunkDiscard: onConfirmHunkDiscard,
            ),
          ],
          const SizedBox(height: 8),
          if (hunks.isEmpty)
            Text(
              'No parsed diff hunks are available.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final hunk in hunks.take(6))
              Card(
                key: ValueKey('source-control-hunk-${hunk.hunkIndex}'),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hunk.summary, style: theme.textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(hunk.header, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            key: ValueKey(
                              'source-control-hunk-stage-${hunk.hunkIndex}',
                            ),
                            onPressed: onSelectHunkAction == null
                                ? null
                                : () {
                                    onSelectHunkAction!(
                                      SourceControlDiffHunkActionPlan.fromDiff(
                                        snapshot: snapshot,
                                        kind: SourceControlActionKind.stage,
                                        selectedHunkIndexes: <int>[
                                          hunk.hunkIndex,
                                        ],
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.add_task_rounded),
                            label: const Text('Stage Hunk'),
                          ),
                          OutlinedButton.icon(
                            key: ValueKey(
                              'source-control-hunk-discard-${hunk.hunkIndex}',
                            ),
                            onPressed: onSelectHunkAction == null
                                ? null
                                : () {
                                    onSelectHunkAction!(
                                      SourceControlDiffHunkActionPlan.fromDiff(
                                        snapshot: snapshot,
                                        kind: SourceControlActionKind.discard,
                                        selectedHunkIndexes: <int>[
                                          hunk.hunkIndex,
                                        ],
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('Discard Hunk'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          if (hunks.length > 6)
            Text(
              'TODO: virtualize older diff hunk rows.',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _HunkDiscardConfirmationCard extends StatelessWidget {
  const _HunkDiscardConfirmationCard({
    required this.plan,
    this.onConfirmHunkDiscard,
  });

  final SourceControlHunkDiscardConfirmationPlan plan;
  final Future<void> Function()? onConfirmHunkDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('source-control-hunk-discard-confirmation'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.18),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan.dialogTitle, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(plan.warning, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text('path ${plan.path}')),
              Chip(label: Text('selected ${plan.selectedHunkIndexes.length}')),
              if (!plan.readyForDialog) Chip(label: Text(plan.blockedReason)),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('source-control-review-hunk-discard'),
            onPressed: plan.readyForDialog && onConfirmHunkDiscard != null
                ? () => _showDiscardDialog(context)
                : null,
            icon: const Icon(Icons.warning_amber_rounded),
            label: Text(plan.confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiscardDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('source-control-hunk-discard-dialog'),
          title: Text(plan.dialogTitle),
          content: Text(plan.warning),
          actions: [
            TextButton(
              key: const ValueKey('source-control-cancel-hunk-discard'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('source-control-confirm-hunk-discard'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(plan.confirmLabel),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      await onConfirmHunkDiscard?.call();
    }
  }
}

class _HunkActionResultRow extends StatelessWidget {
  const _HunkActionResultRow({required this.result});

  final SourceControlPartialPatchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('source-control-hunk-action-result'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: result.applied
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(
            label: Text(
              result.applied ? 'hunk action applied' : 'hunk action failed',
            ),
          ),
          Chip(label: Text(result.kind.wireValue)),
          Chip(label: Text('${result.selectedHunkIndexes.length} hunk(s)')),
          if (result.exitCode != null)
            Chip(label: Text('exit ${result.exitCode}')),
          if (result.message.isNotEmpty) Text(result.message),
        ],
      ),
    );
  }
}

class _ProviderAdapterSummary extends StatelessWidget {
  const _ProviderAdapterSummary({required this.adapters});

  final List<SourceControlProviderAdapterDescriptor> adapters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SourceControlSummaryCard(
      key: const ValueKey('source-control-provider-adapter-summary'),
      title: 'SCM Providers',
      lines: adapters
          .map(
            (adapter) =>
                '${adapter.label}: ${adapter.capabilities.take(4).map((capability) => capability.wireValue).join(', ')}',
          )
          .toList(growable: false),
      icon: Icons.extension_rounded,
      color: theme.colorScheme.primaryContainer,
    );
  }
}

class _CommitDraftCard extends StatelessWidget {
  const _CommitDraftCard({required this.draft, this.dialogState});

  final SourceControlCommitDraft draft;
  final SourceControlCommitDialogState? dialogState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = draft.toCommitActionPlan();
    return _SourceControlSummaryCard(
      key: const ValueKey('source-control-commit-draft-card'),
      title: 'Commit Draft',
      lines: <String>[
        draft.hasMessage ? draft.message.trim() : 'Missing commit message',
        'selected ${draft.selectedPaths.length} · risk ${plan.risk.wireValue}',
        plan.canRun ? 'ready to commit' : plan.blockedReason,
        if (dialogState != null)
          dialogState!.canSubmit
              ? 'dialog ready'
              : 'dialog ${dialogState!.status.wireValue}',
        if (dialogState?.validationMessage.isNotEmpty == true)
          dialogState!.validationMessage,
      ],
      icon: Icons.commit_rounded,
      color: theme.colorScheme.tertiaryContainer,
    );
  }
}

class _BranchPickerSummary extends StatelessWidget {
  const _BranchPickerSummary({required this.snapshot, this.onSwitchBranch});

  final SourceControlBranchSnapshot snapshot;
  final Future<void> Function(SourceControlBranchSwitchPlan plan)?
  onSwitchBranch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('source-control-branch-picker-summary'),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 340),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Branches', style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.available
                ? 'current ${snapshot.currentBranch}'
                : snapshot.message,
            style: theme.textTheme.bodySmall,
          ),
          Text(
            'available ${snapshot.branches.length}',
            style: theme.textTheme.bodySmall,
          ),
          if (snapshot.branches.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final branch in snapshot.branches.take(6))
                  _BranchSwitchButton(
                    snapshot: snapshot,
                    branch: branch,
                    onSwitchBranch: onSwitchBranch,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BranchSwitchButton extends StatelessWidget {
  const _BranchSwitchButton({
    required this.snapshot,
    required this.branch,
    required this.onSwitchBranch,
  });

  final SourceControlBranchSnapshot snapshot;
  final String branch;
  final Future<void> Function(SourceControlBranchSwitchPlan plan)?
  onSwitchBranch;

  @override
  Widget build(BuildContext context) {
    final plan = SourceControlBranchSwitchPlan.fromSnapshot(
      snapshot: snapshot,
      targetBranch: branch,
    );
    return OutlinedButton(
      key: ValueKey('source-control-switch-branch-$branch'),
      onPressed: plan.canRun && onSwitchBranch != null
          ? () {
              onSwitchBranch!(plan);
            }
          : null,
      child: Text(branch),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.snapshot});

  final SourceControlHistorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = snapshot.entries.isEmpty ? null : snapshot.entries.first;
    return Container(
      key: const ValueKey('source-control-history-summary'),
      width: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, size: 18),
              const SizedBox(width: 6),
              Text('History', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            snapshot.available
                ? 'entries ${snapshot.entries.length}'
                : snapshot.message,
            style: theme.textTheme.bodySmall,
          ),
          if (latest != null)
            Text(
              'latest ${latest.shortRevision} · ${latest.summary}',
              style: theme.textTheme.bodySmall,
            ),
          for (final entry in snapshot.entries.take(5))
            _HistoryEntryTile(entry: entry),
          if (snapshot.entries.length > 5)
            Text(
              'TODO: virtualize older history rows.',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _HistoryEntryTile extends StatelessWidget {
  const _HistoryEntryTile({required this.entry});

  final SourceControlHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailLines = <String>[
      'revision ${entry.revision}',
      if (entry.author.isNotEmpty) 'author ${entry.author}',
      if (entry.authoredAt.isNotEmpty) 'authored ${entry.authoredAt}',
      'TODO: wire commit diff preview for this history row.',
    ];
    return ExpansionTile(
      key: ValueKey('source-control-history-entry-${entry.shortRevision}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8, bottom: 6),
      title: Text(
        '${entry.shortRevision} · ${entry.summary}',
        style: theme.textTheme.bodySmall,
      ),
      children: [
        for (final line in detailLines)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(line, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _SourceControlSummaryCard extends StatelessWidget {
  const _SourceControlSummaryCard({
    super.key,
    required this.title,
    required this.lines,
    required this.icon,
    required this.color,
  });

  final String title;
  final List<String> lines;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(title, style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines.where((line) => line.trim().isNotEmpty))
            Text(line, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
