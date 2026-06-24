import 'package:flutter/material.dart';

import '../../agent/agent_context.dart';
import '../../view_ide/workspace/workspace.dart';
import '../platform/viewport_profile.dart';

class WorkspaceSearchSurface extends StatefulWidget {
  const WorkspaceSearchSurface({
    super.key,
    required this.viewportProfile,
    required this.workspaceFileCount,
    this.workspaceFiles = const <String>[],
    this.lastSearch,
    this.lastSymbolSearch,
    this.lastReplacePreview,
    this.lastReplacePreviewWindow,
    this.searchIndex,
    this.searchHistory,
    this.searchFilters,
    this.replaceExpansionState,
    this.onSearch,
    this.onOpenFile,
    this.onPreviewReplace,
    this.onApplyReplacePreview,
    this.onToggleReplaceDocumentExpansion,
    this.onOpenMatch,
    this.onOpenSymbolMatch,
  });

  final ViewportProfile viewportProfile;
  final int workspaceFileCount;
  final List<String> workspaceFiles;
  final AgentWorkspaceSearchResultContext? lastSearch;
  final AgentWorkspaceSymbolSearchResultContext? lastSymbolSearch;
  final WorkspaceReplacePreview? lastReplacePreview;
  final WorkspaceReplacePreviewWindow? lastReplacePreviewWindow;
  final WorkspaceSearchIndex? searchIndex;
  final WorkspaceSearchHistory? searchHistory;
  final WorkspaceSearchFilterState? searchFilters;
  final WorkspaceReplacePreviewExpansionState? replaceExpansionState;
  final Future<void> Function(String query)? onSearch;
  final Future<void> Function(String documentId)? onOpenFile;
  final Future<void> Function(String query, String replacement)?
  onPreviewReplace;
  final Future<void> Function(WorkspaceReplacePreview preview)?
  onApplyReplacePreview;
  final Future<void> Function(String documentId)?
  onToggleReplaceDocumentExpansion;
  final Future<void> Function(AgentWorkspaceSearchMatchContext match)?
  onOpenMatch;
  final Future<void> Function(AgentWorkspaceSymbolMatchContext match)?
  onOpenSymbolMatch;

  @override
  State<WorkspaceSearchSurface> createState() => _WorkspaceSearchSurfaceState();
}

class _WorkspaceSearchSurfaceState extends State<WorkspaceSearchSurface> {
  late final TextEditingController _queryController;
  late final TextEditingController _quickOpenController;
  late final TextEditingController _replaceController;
  static const _quickOpenService = WorkspaceQuickOpenService();
  var _submitting = false;
  var _previewingReplace = false;
  var _applyingReplace = false;
  var _quickOpenQuery = '';

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: widget.lastSearch?.query ?? '',
    );
    _quickOpenController = TextEditingController();
    _replaceController = TextEditingController();
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
    _quickOpenController.dispose();
    _replaceController.dispose();
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

  Future<void> _previewReplace() async {
    final query = _queryController.text.trim();
    if (query.isEmpty ||
        widget.onPreviewReplace == null ||
        _previewingReplace) {
      return;
    }
    setState(() {
      _previewingReplace = true;
    });
    try {
      await widget.onPreviewReplace!(query, _replaceController.text);
    } finally {
      if (mounted) {
        setState(() {
          _previewingReplace = false;
        });
      }
    }
  }

  Future<void> _applyReplacePreview() async {
    final preview = widget.lastReplacePreview;
    if (preview == null ||
        preview.documents.isEmpty ||
        widget.onApplyReplacePreview == null ||
        _applyingReplace) {
      return;
    }
    setState(() {
      _applyingReplace = true;
    });
    try {
      await widget.onApplyReplacePreview!(preview);
    } finally {
      if (mounted) {
        setState(() {
          _applyingReplace = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final lastSearch = widget.lastSearch;
    final lastSymbolSearch = widget.lastSymbolSearch;
    final searchIndex = widget.searchIndex;
    final searchHistory = widget.searchHistory;
    final searchFilters = widget.searchFilters;
    final quickOpenResult = _quickOpenService.searchFiles(
      documentIds: widget.workspaceFiles,
      query: _quickOpenQuery,
      maxResults: compact ? 4 : 6,
    );

    return Card(
      key: const ValueKey('workspace-search-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: ListView(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Workspace Search',
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Text and symbol search entry for workspace-wide edits, quick navigation, indexed search summaries, persisted history, persisted result filters, virtualized replace-preview windows, persisted multi-file diff expansion state, and agent-confirmed code changes.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('files ${widget.workspaceFileCount}')),
                if (searchIndex != null) ...[
                  Chip(label: Text('index-docs ${searchIndex.documentCount}')),
                  Chip(
                    label: Text('index-lines ${searchIndex.totalLineCount}'),
                  ),
                  Chip(
                    label: Text('index-bytes ${searchIndex.totalByteLength}'),
                  ),
                  Chip(
                    label: Text(
                      'index-key ${searchIndex.invalidationKey.documentIds.length}',
                    ),
                  ),
                ],
                if (searchHistory != null)
                  Chip(label: Text('history ${searchHistory.records.length}')),
                if (widget.replaceExpansionState != null)
                  Chip(
                    label: Text(
                      'expanded ${widget.replaceExpansionState!.expandedDocumentIds.length}',
                    ),
                  ),
                if (searchFilters != null) ...[
                  Chip(
                    label: Text(
                      searchFilters.active
                          ? 'filters active'
                          : 'filters inactive',
                    ),
                  ),
                  if (searchFilters.caseSensitive)
                    const Chip(label: Text('case-sensitive')),
                  if (searchFilters.wholeWord)
                    const Chip(label: Text('whole-word')),
                  if (searchFilters.useRegex) const Chip(label: Text('regex')),
                  if (searchFilters.includeGlob.trim().isNotEmpty)
                    Chip(label: Text('include ${searchFilters.includeGlob}')),
                  if (searchFilters.excludeGlob.trim().isNotEmpty)
                    Chip(label: Text('exclude ${searchFilters.excludeGlob}')),
                ],
              ],
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('workspace-replace-input'),
                    controller: _replaceController,
                    decoration: const InputDecoration(
                      labelText: 'Replacement preview',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  key: const ValueKey('workspace-replace-preview-submit'),
                  onPressed:
                      widget.onPreviewReplace == null || _previewingReplace
                      ? null
                      : _previewReplace,
                  icon: _previewingReplace
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.find_replace_rounded),
                  label: Text(_previewingReplace ? 'Previewing' : 'Preview'),
                ),
              ],
            ),
            if (widget.lastReplacePreview != null) ...[
              const SizedBox(height: 10),
              _WorkspaceReplacePreviewView(
                preview: widget.lastReplacePreview!,
                window: widget.lastReplacePreviewWindow,
                expansionState: widget.replaceExpansionState,
                applying: _applyingReplace,
                onApply: widget.onApplyReplacePreview == null
                    ? null
                    : _applyReplacePreview,
                onToggleDocumentExpansion:
                    widget.onToggleReplaceDocumentExpansion,
              ),
            ],
            if (searchHistory != null && searchHistory.records.isNotEmpty) ...[
              const SizedBox(height: 12),
              _WorkspaceSearchHistoryView(history: searchHistory),
            ],
            const SizedBox(height: 12),
            Text('Quick Open', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('workspace-quick-open-input'),
              controller: _quickOpenController,
              decoration: const InputDecoration(
                labelText: 'Open file by path',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _quickOpenQuery = value;
                });
              },
            ),
            const SizedBox(height: 8),
            if (widget.workspaceFiles.isEmpty)
              Text(
                'No workspace files available for quick open.',
                style: theme.textTheme.bodySmall,
              )
            else if (quickOpenResult.matches.isEmpty)
              Text(
                'No files match "$_quickOpenQuery".',
                style: theme.textTheme.bodySmall,
              )
            else
              SizedBox(
                height: compact ? 112 : 136,
                child: ListView.separated(
                  key: const ValueKey('workspace-quick-open-list'),
                  itemCount: quickOpenResult.matches.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final match = quickOpenResult.matches[index];
                    return ListTile(
                      key: ValueKey('workspace-quick-open-${match.documentId}'),
                      dense: true,
                      title: Text(match.label),
                      subtitle: Text(match.documentId),
                      trailing:
                          quickOpenResult.truncated &&
                              index == quickOpenResult.matches.length - 1
                          ? const Chip(label: Text('more'))
                          : const Icon(Icons.open_in_new_rounded),
                      onTap: widget.onOpenFile == null
                          ? null
                          : () {
                              widget.onOpenFile!(match.documentId);
                            },
                    );
                  },
                ),
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
            if (lastSymbolSearch != null) ...[
              const SizedBox(height: 12),
              _WorkspaceSymbolSearchResultView(
                result: lastSymbolSearch,
                onOpenMatch: widget.onOpenSymbolMatch,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSearchHistoryView extends StatelessWidget {
  const _WorkspaceSearchHistoryView({required this.history});

  final WorkspaceSearchHistory history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = history.records.take(4).toList(growable: false);
    return Column(
      key: const ValueKey('workspace-search-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Search', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final record in records)
          ListTile(
            key: ValueKey(
              'workspace-search-history-${record.mode.wireValue}-${record.query}',
            ),
            dense: true,
            leading: const Icon(Icons.history_rounded),
            title: Text(record.query),
            subtitle: Text(
              record.replacement.isEmpty
                  ? record.mode.wireValue
                  : '${record.mode.wireValue} -> ${record.replacement}',
            ),
          ),
      ],
    );
  }
}

class _WorkspaceSymbolSearchResultView extends StatelessWidget {
  const _WorkspaceSymbolSearchResultView({
    required this.result,
    required this.onOpenMatch,
  });

  final AgentWorkspaceSymbolSearchResultContext result;
  final Future<void> Function(AgentWorkspaceSymbolMatchContext match)?
  onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('workspace-symbol-search-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Chip(label: Text('symbols ${result.matchCount}')),
            Chip(label: Text('symbol query ${result.query}')),
            Chip(label: Text('symbol scanned ${result.scannedDocumentCount}')),
            Chip(label: Text('symbol truncated ${result.matchesTruncated}')),
          ],
        ),
        const SizedBox(height: 10),
        Text('Symbols', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (result.matches.isEmpty)
          Text('No symbols found.', style: theme.textTheme.bodySmall)
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              key: const ValueKey('workspace-symbol-search-match-list'),
              itemCount: result.matches.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final match = result.matches[index];
                return ListTile(
                  key: ValueKey(
                    'workspace-symbol-search-match-${match.documentId}-${match.name}-${match.start}',
                  ),
                  dense: true,
                  title: Text('${match.name} · ${match.kind}'),
                  subtitle: Text(
                    '${match.documentId} · line ${match.lineNumber}: ${match.lineText}'
                    ' · semantic ${match.snapshotConfidence}',
                  ),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: onOpenMatch == null
                      ? null
                      : () {
                          onOpenMatch!(match);
                        },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _WorkspaceReplacePreviewView extends StatelessWidget {
  const _WorkspaceReplacePreviewView({
    required this.preview,
    this.window,
    this.expansionState,
    required this.applying,
    required this.onApply,
    this.onToggleDocumentExpansion,
  });

  final WorkspaceReplacePreview preview;
  final WorkspaceReplacePreviewWindow? window;
  final WorkspaceReplacePreviewExpansionState? expansionState;
  final bool applying;
  final Future<void> Function()? onApply;
  final Future<void> Function(String documentId)? onToggleDocumentExpansion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeWindow = window ?? preview.window();
    return Column(
      key: const ValueKey('workspace-replace-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Chip(label: Text('replacements ${preview.replacementCount}')),
            Chip(label: Text('documents ${preview.documents.length}')),
            Chip(
              label: Text(
                'replace-window ${activeWindow.documentOffset}-${activeWindow.endDocumentOffset}/${activeWindow.totalDocumentCount}',
              ),
            ),
            if (activeWindow.hasPreviousDocuments)
              const Chip(label: Text('has previous documents')),
            if (activeWindow.hasMoreDocuments)
              const Chip(label: Text('has more documents')),
            Chip(label: Text('failures ${preview.failures.length}')),
            Chip(label: Text('truncated ${preview.truncated}')),
            if (expansionState != null)
              Chip(
                label: Text(
                  'expanded ${expansionState!.expandedDocumentIds.length}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Apply uses this preview only if document revisions still match.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              key: const ValueKey('workspace-replace-apply-submit'),
              onPressed:
                  preview.documents.isEmpty || onApply == null || applying
                  ? null
                  : onApply,
              icon: applying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_rounded),
              label: Text(applying ? 'Applying' : 'Apply Preview'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (preview.documents.isEmpty)
          Text(
            'No replacement changes found.',
            style: theme.textTheme.bodySmall,
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              key: const ValueKey('workspace-replace-preview-list'),
              itemCount: activeWindow.documents.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final document = activeWindow.documents[index];
                final expanded =
                    expansionState?.isExpanded(document.documentId) ?? false;
                return ListTile(
                  dense: true,
                  title: Text(document.documentId),
                  trailing: IconButton(
                    key: ValueKey(
                      'workspace-replace-toggle-${document.documentId}',
                    ),
                    tooltip: expanded ? 'Collapse diff' : 'Expand diff',
                    onPressed: onToggleDocumentExpansion == null
                        ? null
                        : () {
                            onToggleDocumentExpansion!(document.documentId);
                          },
                    icon: Icon(
                      expanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${document.replacementCount} replacement(s), revision ${document.revision}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expanded
                            ? 'Before full: ${_workspaceReplacePreviewExpandedText(document.beforeText)}'
                            : 'Before: ${_workspaceReplacePreviewSnippet(document.beforeText)}',
                      ),
                      Text(
                        expanded
                            ? 'After full: ${_workspaceReplacePreviewExpandedText(document.afterText)}'
                            : 'After: ${_workspaceReplacePreviewSnippet(document.afterText)}',
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

String _workspaceReplacePreviewExpandedText(
  String text, {
  int maxLength = 240,
}) {
  final normalized = text
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .join(' / ')
      .trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return '${normalized.substring(0, maxLength - 3)}...';
}

String _workspaceReplacePreviewSnippet(String text, {int maxLength = 96}) {
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

class _WorkspaceSearchResultView extends StatelessWidget {
  const _WorkspaceSearchResultView({
    required this.result,
    required this.onOpenMatch,
  });

  final AgentWorkspaceSearchResultContext result;
  final Future<void> Function(AgentWorkspaceSearchMatchContext match)?
  onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
          SizedBox(
            height: 180,
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
                  subtitle: Text('line ${match.lineNumber}: ${match.lineText}'),
                  trailing: const Icon(Icons.open_in_new_rounded),
                  onTap: onOpenMatch == null
                      ? null
                      : () {
                          onOpenMatch!(match);
                        },
                );
              },
            ),
          ),
      ],
    );
  }
}
