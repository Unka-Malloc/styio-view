import 'package:flutter/material.dart';

import '../../agent/agent_context.dart';
import '../platform/viewport_profile.dart';

class WorkspaceSearchSurface extends StatefulWidget {
  const WorkspaceSearchSurface({
    super.key,
    required this.viewportProfile,
    required this.workspaceFileCount,
    this.lastSearch,
    this.onSearch,
    this.onOpenMatch,
  });

  final ViewportProfile viewportProfile;
  final int workspaceFileCount;
  final AgentWorkspaceSearchResultContext? lastSearch;
  final Future<void> Function(String query)? onSearch;
  final Future<void> Function(String documentId)? onOpenMatch;

  @override
  State<WorkspaceSearchSurface> createState() => _WorkspaceSearchSurfaceState();
}

class _WorkspaceSearchSurfaceState extends State<WorkspaceSearchSurface> {
  late final TextEditingController _queryController;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: widget.lastSearch?.query ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant WorkspaceSearchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextQuery = widget.lastSearch?.query;
    if (nextQuery != null &&
        nextQuery.isNotEmpty &&
        _queryController.text != nextQuery) {
      _queryController.text = nextQuery;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final query = _queryController.text.trim();
    if (query.isEmpty || widget.onSearch == null || _submitting) {
      return;
    }
    setState(() {
      _submitting = true;
    });
    try {
      await widget.onSearch!(query);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final lastSearch = widget.lastSearch;

    return Card(
      key: const ValueKey('workspace-search-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Workspace Search', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Text search entry for workspace-wide edits and agent-confirmed navigation. TODO: add indexed search, symbol search, replace preview, and persistent result filters.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('workspace-search-query-input'),
                    controller: _queryController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Search query',
                      helperText:
                          'Scans ${widget.workspaceFileCount} workspace file(s).',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      _submit();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('workspace-search-submit'),
                  onPressed: widget.onSearch == null || _submitting
                      ? null
                      : _submit,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search_rounded),
                  label: Text(_submitting ? 'Searching' : 'Search'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (lastSearch == null)
              Text(
                'No workspace search has been run in this session.',
                style: theme.textTheme.bodySmall,
              )
            else
              _WorkspaceSearchResultView(
                result: lastSearch,
                onOpenMatch: widget.onOpenMatch,
              ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSearchResultView extends StatelessWidget {
  const _WorkspaceSearchResultView({
    required this.result,
    required this.onOpenMatch,
  });

  final AgentWorkspaceSearchResultContext result;
  final Future<void> Function(String documentId)? onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        key: const ValueKey('workspace-search-results'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(label: Text('query ${result.query}')),
              Chip(label: Text('matches ${result.matchCount}')),
              Chip(label: Text('scanned ${result.scannedDocumentCount}')),
              Chip(label: Text('truncated ${result.matchesTruncated}')),
            ],
          ),
          const SizedBox(height: 10),
          Text('Matches', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (result.matches.isEmpty)
            Text('No matches found.', style: theme.textTheme.bodySmall)
          else
            Expanded(
              child: ListView.separated(
                key: const ValueKey('workspace-search-match-list'),
                itemCount: result.matches.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final match = result.matches[index];
                  return ListTile(
                    key: ValueKey(
                      'workspace-search-match-${match.documentId}-${match.lineNumber}-${match.start}',
                    ),
                    dense: true,
                    title: Text(match.documentId),
                    subtitle: Text(
                      'line ${match.lineNumber}: ${match.lineText}',
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: onOpenMatch == null
                        ? null
                        : () {
                            onOpenMatch!(match.documentId);
                          },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
