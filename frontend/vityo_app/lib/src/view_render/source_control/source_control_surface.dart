import 'package:flutter/material.dart';

import '../../view_ide/workspace/source_control_status.dart';
import '../platform/viewport_profile.dart';

class SourceControlSurface extends StatelessWidget {
  const SourceControlSurface({
    super.key,
    required this.viewportProfile,
    required this.workspaceFileCount,
    required this.changedDocumentIds,
    this.status,
    this.onOpenFile,
    this.onSaveAll,
    this.onRefresh,
  });

  final ViewportProfile viewportProfile;
  final int workspaceFileCount;
  final List<String> changedDocumentIds;
  final SourceControlStatusSnapshot? status;
  final Future<void> Function(String documentId)? onOpenFile;
  final Future<void> Function()? onSaveAll;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final providerKind =
        status?.providerKind.wireValue ?? 'local-dirty-documents';
    final gitChanges = status?.changes ?? const <SourceControlFileChange>[];
    final statusAvailable = status?.available ?? true;

    return Card(
      key: const ValueKey('source-control-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Source Control', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Local IDE change surface backed by dirty editor documents and injectable SCM providers. TODO: wire Git runner through Platform/Process Manager, staging, commit, diff, branch, and history contracts.',
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
                if (status != null)
                  Chip(label: Text('git ${gitChanges.length}')),
              ],
            ),
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
              ],
            ),
            const SizedBox(height: 12),
            if (gitChanges.isNotEmpty) ...[
              Text('Git Changes', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  key: const ValueKey('source-control-git-change-list'),
                  itemCount: gitChanges.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final change = gitChanges[index];
                    return ListTile(
                      key: ValueKey('source-control-git-change-${change.path}'),
                      dense: true,
                      leading: const Icon(Icons.account_tree_outlined),
                      title: Text(change.path),
                      subtitle: Text(change.summary),
                      trailing: change.originalPath.isEmpty
                          ? null
                          : Text('from ${change.originalPath}'),
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
            Text('Changes', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (changedDocumentIds.isEmpty)
              Text(
                'No dirty editor documents are currently tracked.',
                style: theme.textTheme.bodySmall,
              )
            else
              Expanded(
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
    );
  }
}
