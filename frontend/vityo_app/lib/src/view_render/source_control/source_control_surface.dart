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
    this.commitDraft,
    this.commitDialogState,
    this.branchSnapshot,
    this.historySnapshot,
    this.onOpenFile,
    this.onSaveAll,
    this.onRefresh,
    this.onPreviewDiff,
    this.onStagePaths,
    this.onUnstagePaths,
    this.onOpenCommit,
  });

  final ViewportProfile viewportProfile;
  final int workspaceFileCount;
  final List<String> changedDocumentIds;
  final SourceControlStatusSnapshot? status;
  final SourceControlDiffSnapshot? diffPreview;
  final SourceControlCommitDraft? commitDraft;
  final SourceControlCommitDialogState? commitDialogState;
  final SourceControlBranchSnapshot? branchSnapshot;
  final SourceControlHistorySnapshot? historySnapshot;
  final Future<void> Function(String documentId)? onOpenFile;
  final Future<void> Function()? onSaveAll;
  final Future<void> Function()? onRefresh;
  final Future<void> Function(String documentId)? onPreviewDiff;
  final Future<void> Function(List<String> paths)? onStagePaths;
  final Future<void> Function(List<String> paths)? onUnstagePaths;
  final Future<void> Function()? onOpenCommit;

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
                'Local IDE change surface backed by dirty editor documents and injectable SCM providers. Stage and unstage use the source control action provider when configured. Commit dialog state records draft validation. TODO: add branch picker, history view, and richer diff confirmation.',
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
                  historySnapshot != null) ...[
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
                      _BranchPickerSummary(snapshot: branchSnapshot!),
                    if (historySnapshot != null)
                      _HistorySummary(snapshot: historySnapshot!),
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
                      diffPreview!.available
                          ? (diffPreview!.unifiedDiff.trim().isEmpty
                                ? diffPreview!.message
                                : diffPreview!.unifiedDiff)
                          : diffPreview!.message,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
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
  const _BranchPickerSummary({required this.snapshot});

  final SourceControlBranchSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SourceControlSummaryCard(
      key: const ValueKey('source-control-branch-picker-summary'),
      title: 'Branches',
      lines: <String>[
        snapshot.available
            ? 'current ${snapshot.currentBranch}'
            : snapshot.message,
        'available ${snapshot.branches.length}',
        if (snapshot.branches.isNotEmpty) snapshot.branches.take(4).join(', '),
      ],
      icon: Icons.account_tree_rounded,
      color: theme.colorScheme.secondaryContainer,
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
    return _SourceControlSummaryCard(
      key: const ValueKey('source-control-history-summary'),
      title: 'History',
      lines: <String>[
        snapshot.available
            ? 'entries ${snapshot.entries.length}'
            : snapshot.message,
        if (latest != null) '${latest.shortRevision} · ${latest.summary}',
      ],
      icon: Icons.history_rounded,
      color: theme.colorScheme.surfaceContainerHighest,
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
