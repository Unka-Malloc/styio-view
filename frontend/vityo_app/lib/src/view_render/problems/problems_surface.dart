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
    this.onApplyWorkspaceQuickFix,
  });

  final ViewportProfile viewportProfile;
  final String documentId;
  final List<Diagnostic> diagnostics;
  final WorkspaceDiagnosticsSnapshot? workspaceDiagnostics;
  final ValueChanged<Diagnostic>? onSelectDiagnostic;
  final ValueChanged<WorkspaceDiagnostic>? onSelectWorkspaceDiagnostic;
  final Future<void> Function()? onRefreshWorkspaceDiagnostics;
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
    final severityCounts = <DiagnosticSeverity, int>{
      for (final severity in DiagnosticSeverity.values) severity: 0,
    };
    for (final entry in problemEntries) {
      final severity = entry.diagnostic.severity;
      severityCounts[severity] = (severityCounts[severity] ?? 0) + 1;
    }

    return Card(
      key: const ValueKey('problems-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Problems', style: theme.textTheme.titleLarge),
                ),
                if (onRefreshWorkspaceDiagnostics != null)
                  TextButton.icon(
                    key: const ValueKey('problems-refresh-workspace'),
                    onPressed: onRefreshWorkspaceDiagnostics,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
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
              'Diagnostics surface backed by active document diagnostics or a workspace diagnostics snapshot. TODO: add grouping, filters, quick-fix preview, and persisted problem state.',
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
                for (final entry in severityCounts.entries)
                  Chip(label: Text('${entry.key.name} ${entry.value}')),
              ],
            ),
            const SizedBox(height: 12),
            if (problemEntries.isEmpty)
              Text(
                workspaceDiagnostics == null
                    ? 'No diagnostics for the active document.'
                    : 'No diagnostics for the workspace.',
                style: theme.textTheme.bodySmall,
              )
            else
              Expanded(
                child: ListView.separated(
                  key: const ValueKey('problems-diagnostic-list'),
                  itemCount: problemEntries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = problemEntries[index];
                    final diagnostic = entry.diagnostic;
                    return ListTile(
                      key: ValueKey('problems-diagnostic-${diagnostic.code}'),
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
