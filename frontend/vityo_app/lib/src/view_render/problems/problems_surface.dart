import 'package:flutter/material.dart';

import '../../view_ide/language/language_contract.dart';
import '../platform/viewport_profile.dart';

class ProblemsSurface extends StatelessWidget {
  const ProblemsSurface({
    super.key,
    required this.viewportProfile,
    required this.documentId,
    required this.diagnostics,
    this.onSelectDiagnostic,
  });

  final ViewportProfile viewportProfile;
  final String documentId;
  final List<Diagnostic> diagnostics;
  final ValueChanged<Diagnostic>? onSelectDiagnostic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final severityCounts = <DiagnosticSeverity, int>{
      for (final severity in DiagnosticSeverity.values) severity: 0,
    };
    for (final diagnostic in diagnostics) {
      severityCounts[diagnostic.severity] =
          (severityCounts[diagnostic.severity] ?? 0) + 1;
    }

    return Card(
      key: const ValueKey('problems-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Problems', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Active document diagnostics surface. TODO: add workspace-wide grouping, filters, quick-fix preview, and persisted problem state.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('document $documentId')),
                Chip(label: Text('total ${diagnostics.length}')),
                for (final entry in severityCounts.entries)
                  Chip(label: Text('${entry.key.name} ${entry.value}')),
              ],
            ),
            const SizedBox(height: 12),
            if (diagnostics.isEmpty)
              Text(
                'No diagnostics for the active document.',
                style: theme.textTheme.bodySmall,
              )
            else
              Expanded(
                child: ListView.separated(
                  key: const ValueKey('problems-diagnostic-list'),
                  itemCount: diagnostics.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final diagnostic = diagnostics[index];
                    return ListTile(
                      key: ValueKey('problems-diagnostic-${diagnostic.code}'),
                      dense: true,
                      leading: Icon(
                        _diagnosticIcon(diagnostic.severity),
                        color: _diagnosticColor(diagnostic.severity),
                      ),
                      title: Text(diagnostic.message),
                      subtitle: Text(
                        '${diagnostic.severity.name} · ${diagnostic.code} · offsets ${diagnostic.range.start}-${diagnostic.range.end}',
                      ),
                      trailing: const Icon(Icons.arrow_forward_rounded),
                      onTap: onSelectDiagnostic == null
                          ? null
                          : () {
                              onSelectDiagnostic!(diagnostic);
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
