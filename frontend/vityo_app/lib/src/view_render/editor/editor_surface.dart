import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/language/language_contract.dart';
import '../platform/viewport_profile.dart';
import '../../view_ide/editor/document_state.dart';
import '../../view_ide/editor/editor_controller.dart';
import '../../view_ide/editor/render_plan/render_plan.dart';
import '../../view_ide/editor/selection_state.dart';
import 'editor_text_style_binding.dart';

List<CompletionItem> mergeCompletionItems(
  Iterable<CompletionItem> primary,
  Iterable<CompletionItem> fallback,
) {
  final completions = <CompletionItem>[];
  final seen = <String>{};
  for (final completion in [...primary, ...fallback]) {
    final key =
        '${completion.kind.name}:${completion.label}:${completion.insertText}';
    if (seen.add(key)) {
      completions.add(completion);
    }
  }
  return List<CompletionItem>.unmodifiable(completions);
}

class EditorSurface extends StatelessWidget {
  const EditorSurface({
    super.key,
    required this.controller,
    required this.viewportProfile,
    this.languageServiceStatus,
    this.fileBindingSnapshot,
    this.closeRequestSurface,
    this.semanticThemeBinding,
    this.onAcceptExternalChange,
    this.onSaveLocalChanges,
    this.onDiscardLocalChanges,
    this.onSaveAndCloseRequest,
    this.onDiscardAndCloseRequest,
    this.onSwitchToCloseRequestFile,
    this.onCancelCloseRequest,
    this.projectHoverAtSelection,
    this.projectCompletionsAtSelection = const <CompletionItem>[],
    this.openDocumentIds = const <String>[],
    this.dirtyDocumentIds = const <String>[],
    this.activeDocumentId,
    this.onSelectDocument,
    this.onCloseDocument,
    this.onRefreshLanguageService,
  });

  final EditorSessionController controller;
  final ViewportProfile viewportProfile;
  final LanguageServiceStatusSurface? languageServiceStatus;
  final DocumentResourceBindingSnapshot? fileBindingSnapshot;
  final EditorCloseRequestSurface? closeRequestSurface;
  final EditorSemanticThemeBinding? semanticThemeBinding;
  final VoidCallback? onAcceptExternalChange;
  final VoidCallback? onSaveLocalChanges;
  final VoidCallback? onDiscardLocalChanges;
  final VoidCallback? onSaveAndCloseRequest;
  final VoidCallback? onDiscardAndCloseRequest;
  final VoidCallback? onSwitchToCloseRequestFile;
  final VoidCallback? onCancelCloseRequest;
  final HoverPayload? projectHoverAtSelection;
  final List<CompletionItem> projectCompletionsAtSelection;
  final List<String> openDocumentIds;
  final List<String> dirtyDocumentIds;
  final String? activeDocumentId;
  final ValueChanged<String>? onSelectDocument;
  final ValueChanged<String>? onCloseDocument;
  final VoidCallback? onRefreshLanguageService;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final document = controller.document;
        final selection = controller.selection;
        final renderPlan = controller.renderPlan;
        final semanticThemeBinding =
            this.semanticThemeBinding ??
            EditorSemanticThemeBinding.fromTheme(
              EditorSemanticTheme.foundation(),
            );
        final analysis = controller.analysis;
        final hover = projectHoverAtSelection ?? controller.hoverAtSelection;
        final completions = mergeCompletionItems(
          controller.completionsAtSelection,
          projectCompletionsAtSelection,
        );
        final activeReferences = controller.referencesAtSelection;
        final activeToken = controller.tokenAtSelection;
        final activeSemanticKind = controller.semanticKindAtSelection;
        final serviceStatus = languageServiceStatus;
        final fileBindingStatus = _fileBindingStatusFor(fileBindingSnapshot);
        final closeRequest = closeRequestSurface;
        final activeOpenDocumentId = activeDocumentId ?? document.documentId;
        final visibleOpenDocumentIds = openDocumentIds.isEmpty
            ? <String>[document.documentId]
            : openDocumentIds;
        final visibleServiceStatus = serviceStatus;
        final summaryPills = <String>[
          'lines ${document.lines.length}',
          'chars ${document.length}',
          'tokens ${analysis.tokenCount}',
          'semantic ${analysis.semanticCount}',
          'symbols ${analysis.symbolCount}',
          'diagnostics ${analysis.diagnosticCount}',
          if (visibleServiceStatus != null)
            'service ${visibleServiceStatus.severity.name}',
          selection.isCollapsed
              ? 'caret ${selection.end}'
              : 'selection ${selection.start}-${selection.end}',
          'undo ${controller.canUndo ? "on" : "off"}',
          'redo ${controller.canRedo ? "on" : "off"}',
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                viewportProfile.isMobile ||
                constraints.maxWidth < 780 ||
                constraints.maxHeight < 560;
            final dense =
                (viewportProfile.isMobile && constraints.maxWidth < 640) ||
                constraints.maxWidth < 560 ||
                constraints.maxHeight < 430;
            final outerPadding = dense ? 16.0 : 24.0;
            final innerPadding = dense ? 14.0 : 18.0;
            final visibleSummaryPills = dense
                ? summaryPills.take(4).toList(growable: false)
                : summaryPills;

            return Card(
              key: ValueKey(
                'editor-viewport-${viewportProfile.label.toLowerCase()}',
              ),
              child: Padding(
                padding: EdgeInsets.all(outerPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.documentId,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Chip(label: Text('rev ${document.revision}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _OpenDocumentTabStrip(
                      documentIds: visibleOpenDocumentIds,
                      dirtyDocumentIds: dirtyDocumentIds,
                      activeDocumentId: activeOpenDocumentId,
                      onSelectDocument: onSelectDocument,
                      onCloseDocument: onCloseDocument,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: visibleSummaryPills
                          .map((label) => _CapabilityPill(label: label))
                          .toList(growable: false),
                    ),
                    if (closeRequest != null &&
                        closeRequest.requiresUserChoice) ...[
                      const SizedBox(height: 12),
                      _CloseRequestBanner(
                        request: closeRequest,
                        onSaveLocalChanges:
                            onSaveAndCloseRequest ?? onSaveLocalChanges,
                        onDiscardLocalChanges:
                            onDiscardAndCloseRequest ?? onDiscardLocalChanges,
                        onSwitchToCloseRequestFile: onSwitchToCloseRequestFile,
                        onCancelCloseRequest: onCancelCloseRequest,
                      ),
                    ] else if (fileBindingStatus != null) ...[
                      const SizedBox(height: 12),
                      _FileBindingStatusBanner(
                        status: fileBindingStatus,
                        onAcceptExternalChange: onAcceptExternalChange,
                        onSaveLocalChanges: onSaveLocalChanges,
                        onDiscardLocalChanges: onDiscardLocalChanges,
                      ),
                    ],
                    if (!dense && fileBindingStatus == null) ...[
                      const SizedBox(height: 14),
                      Text(
                        compact
                            ? 'Token, semantic, diagnostic, and formatting layers stay isolated while sharing one editor surface.'
                            : 'M2/M3 editor anchor: token layer drives base highlighting, semantic layer overlays meaning, diagnostics stay separate, and formatting returns patch-like edits.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        padding: EdgeInsets.all(innerPadding),
                        child: LayoutBuilder(
                          builder: (context, sourceConstraints) {
                            final showLayerToolbar =
                                !dense && sourceConstraints.maxHeight >= 128;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showLayerToolbar) ...[
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      ...renderPlan.activeLayers.map(
                                        (layer) => _CapabilityPill(
                                          label: 'layer ${layer.name}',
                                        ),
                                      ),
                                      FilterChip(
                                        key: const ValueKey(
                                          'editor-glyph-substitution-toggle',
                                        ),
                                        selected:
                                            renderPlan.glyphSubstitutionEnabled,
                                        label: Text(
                                          renderPlan.glyphSubstitutionEnabled
                                              ? 'glyph substitution on'
                                              : 'glyph substitution off',
                                        ),
                                        onSelected: (_) {
                                          controller.toggleGlyphSubstitution();
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final mobileFamily =
                                          viewportProfile.isMobile;
                                      final scrollStackedPane =
                                          mobileFamily &&
                                          constraints.maxHeight < 460;
                                      final inspectorHeight =
                                          constraints.maxHeight >= 720
                                          ? 240.0
                                          : constraints.maxHeight >= 560
                                          ? 200.0
                                          : 160.0;

                                      if (scrollStackedPane) {
                                        return KeyedSubtree(
                                          key: const ValueKey(
                                            'editor-language-family-mobile',
                                          ),
                                          child: SingleChildScrollView(
                                            key: ValueKey(
                                              'editor-language-layout-scroll-${viewportProfile.label.toLowerCase()}',
                                            ),
                                            child: Column(
                                              children: [
                                                SizedBox(
                                                  height: 320,
                                                  child: _SourcePreviewPane(
                                                    controller: controller,
                                                    viewportProfile:
                                                        viewportProfile,
                                                    hover: hover,
                                                    completions: completions,
                                                    activeReferences:
                                                        activeReferences,
                                                    activeToken: activeToken,
                                                    activeSemanticKind:
                                                        activeSemanticKind,
                                                    document: document,
                                                    selection: selection,
                                                    analysis: analysis,
                                                    renderPlan: renderPlan,
                                                    semanticThemeBinding:
                                                        semanticThemeBinding,
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                SizedBox(
                                                  height: 180,
                                                  child: _LanguageServicePane(
                                                    controller: controller,
                                                    viewportProfile:
                                                        viewportProfile,
                                                    analysis: analysis,
                                                    hover: hover,
                                                    completions: completions,
                                                    activeToken: activeToken,
                                                    activeSemanticKind:
                                                        activeSemanticKind,
                                                    languageServiceStatus:
                                                        visibleServiceStatus,
                                                    onRefreshLanguageService:
                                                        onRefreshLanguageService,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      if (mobileFamily) {
                                        return KeyedSubtree(
                                          key: const ValueKey(
                                            'editor-language-family-mobile',
                                          ),
                                          child: Column(
                                            key: const ValueKey(
                                              'editor-language-layout-mobile',
                                            ),
                                            children: [
                                              Expanded(
                                                child: _SourcePreviewPane(
                                                  controller: controller,
                                                  viewportProfile:
                                                      viewportProfile,
                                                  hover: hover,
                                                  completions: completions,
                                                  activeReferences:
                                                      activeReferences,
                                                  activeToken: activeToken,
                                                  activeSemanticKind:
                                                      activeSemanticKind,
                                                  document: document,
                                                  selection: selection,
                                                  analysis: analysis,
                                                  renderPlan: renderPlan,
                                                  semanticThemeBinding:
                                                      semanticThemeBinding,
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              SizedBox(
                                                height: inspectorHeight,
                                                child: _LanguageServicePane(
                                                  controller: controller,
                                                  viewportProfile:
                                                      viewportProfile,
                                                  analysis: analysis,
                                                  hover: hover,
                                                  completions: completions,
                                                  activeToken: activeToken,
                                                  activeSemanticKind:
                                                      activeSemanticKind,
                                                  languageServiceStatus:
                                                      visibleServiceStatus,
                                                  onRefreshLanguageService:
                                                      onRefreshLanguageService,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      return KeyedSubtree(
                                        key: const ValueKey(
                                          'editor-language-family-desktop',
                                        ),
                                        child: Row(
                                          key: const ValueKey(
                                            'editor-language-layout-desktop',
                                          ),
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: _SourcePreviewPane(
                                                controller: controller,
                                                viewportProfile:
                                                    viewportProfile,
                                                hover: hover,
                                                completions: completions,
                                                activeReferences:
                                                    activeReferences,
                                                activeToken: activeToken,
                                                activeSemanticKind:
                                                    activeSemanticKind,
                                                document: document,
                                                selection: selection,
                                                analysis: analysis,
                                                renderPlan: renderPlan,
                                                semanticThemeBinding:
                                                    semanticThemeBinding,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            SizedBox(
                                              width: constraints.maxWidth >= 760
                                                  ? 300
                                                  : 248,
                                              child: _LanguageServicePane(
                                                controller: controller,
                                                viewportProfile:
                                                    viewportProfile,
                                                analysis: analysis,
                                                hover: hover,
                                                completions: completions,
                                                activeToken: activeToken,
                                                activeSemanticKind:
                                                    activeSemanticKind,
                                                languageServiceStatus:
                                                    visibleServiceStatus,
                                                onRefreshLanguageService:
                                                    onRefreshLanguageService,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CloseRequestBanner extends StatelessWidget {
  const _CloseRequestBanner({
    required this.request,
    required this.onSaveLocalChanges,
    required this.onDiscardLocalChanges,
    required this.onSwitchToCloseRequestFile,
    required this.onCancelCloseRequest,
  });

  final EditorCloseRequestSurface request;
  final VoidCallback? onSaveLocalChanges;
  final VoidCallback? onDiscardLocalChanges;
  final VoidCallback? onSwitchToCloseRequestFile;
  final VoidCallback? onCancelCloseRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('editor-close-request-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.36),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Close blocked', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(request.message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (request.canSwitchToFile)
            OutlinedButton(
              key: const ValueKey('editor-close-request-switch'),
              onPressed: onSwitchToCloseRequestFile,
              child: const Text('Switch to file'),
            ),
          OutlinedButton(
            key: const ValueKey('editor-close-request-save'),
            onPressed: request.canSave ? onSaveLocalChanges : null,
            child: const Text('Save changes'),
          ),
          TextButton(
            key: const ValueKey('editor-close-request-discard'),
            onPressed: request.canDiscard ? onDiscardLocalChanges : null,
            child: const Text('Discard changes'),
          ),
          TextButton(
            key: const ValueKey('editor-close-request-cancel'),
            onPressed: onCancelCloseRequest,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _OpenDocumentTabStrip extends StatelessWidget {
  const _OpenDocumentTabStrip({
    required this.documentIds,
    required this.dirtyDocumentIds,
    required this.activeDocumentId,
    required this.onSelectDocument,
    required this.onCloseDocument,
  });

  final List<String> documentIds;
  final List<String> dirtyDocumentIds;
  final String activeDocumentId;
  final ValueChanged<String>? onSelectDocument;
  final ValueChanged<String>? onCloseDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('editor-open-file-tab-strip'),
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: documentIds.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final documentId = documentIds[index];
          final active = documentId == activeDocumentId;
          final dirty = dirtyDocumentIds.contains(documentId);
          return _OpenDocumentTab(
            documentId: documentId,
            active: active,
            dirty: dirty,
            onSelectDocument: onSelectDocument,
            onCloseDocument: onCloseDocument,
            color: active
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surface,
            borderColor: active
                ? theme.colorScheme.primary.withValues(alpha: 0.42)
                : theme.dividerColor,
          );
        },
      ),
    );
  }
}

class _OpenDocumentTab extends StatelessWidget {
  const _OpenDocumentTab({
    required this.documentId,
    required this.active,
    required this.dirty,
    required this.onSelectDocument,
    required this.onCloseDocument,
    required this.color,
    required this.borderColor,
  });

  final String documentId;
  final bool active;
  final bool dirty;
  final ValueChanged<String>? onSelectDocument;
  final ValueChanged<String>? onCloseDocument;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: ValueKey('editor-open-file-tab-$documentId'),
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active ? null : () => onSelectDocument?.call(documentId),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  _documentTabLabel(documentId),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (dirty) ...[
                const SizedBox(width: 6),
                Text(
                  '•',
                  key: ValueKey('editor-open-file-tab-dirty-$documentId'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: active
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('editor-open-file-tab-close-$documentId'),
                tooltip: 'Close $documentId',
                icon: const Icon(Icons.close_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: onCloseDocument == null
                    ? null
                    : () => onCloseDocument!(documentId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _documentTabLabel(String documentId) {
  final normalized = documentId.replaceAll('\\', '/');
  final segments = normalized.split('/').where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? documentId : segments.last;
}

class _FileBindingStatus {
  const _FileBindingStatus({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionEnabled,
    required this.action,
    this.secondaryActionLabel,
    this.secondaryActionEnabled = false,
    this.secondaryAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final bool actionEnabled;
  final _FileBindingStatusAction action;
  final String? secondaryActionLabel;
  final bool secondaryActionEnabled;
  final _FileBindingStatusAction? secondaryAction;
}

enum _FileBindingStatusAction {
  acceptExternal,
  saveLocal,
  discardLocal,
  unavailable,
}

_FileBindingStatus? _fileBindingStatusFor(
  DocumentResourceBindingSnapshot? snapshot,
) {
  return switch (snapshot?.state) {
    DocumentResourceBindingState.boundDirty => const _FileBindingStatus(
      title: 'Unsaved local changes',
      message:
          'Save this file or discard local changes before closing the tab.',
      actionLabel: 'Save changes',
      actionEnabled: true,
      action: _FileBindingStatusAction.saveLocal,
      secondaryActionLabel: 'Discard changes',
      secondaryActionEnabled: true,
      secondaryAction: _FileBindingStatusAction.discardLocal,
    ),
    DocumentResourceBindingState.externalChanged => const _FileBindingStatus(
      title: 'External file change',
      message:
          'The backing file changed on disk. Reload to use the external revision.',
      actionLabel: 'Reload external',
      actionEnabled: true,
      action: _FileBindingStatusAction.acceptExternal,
    ),
    DocumentResourceBindingState.conflicted => const _FileBindingStatus(
      title: 'External file conflict',
      message:
          'The backing file changed while this editor has unsaved local edits.',
      actionLabel: 'Use external version',
      actionEnabled: true,
      action: _FileBindingStatusAction.acceptExternal,
    ),
    DocumentResourceBindingState.deletedOnDisk => const _FileBindingStatus(
      title: 'Backing file deleted',
      message: 'The backing file was deleted or became unavailable.',
      actionLabel: 'Reload unavailable',
      actionEnabled: false,
      action: _FileBindingStatusAction.unavailable,
    ),
    DocumentResourceBindingState.readonly => const _FileBindingStatus(
      title: 'Backing file is read-only',
      message: 'The current file cannot be saved until it becomes writable.',
      actionLabel: 'Read-only',
      actionEnabled: false,
      action: _FileBindingStatusAction.unavailable,
    ),
    DocumentResourceBindingState.providerUnavailable =>
      const _FileBindingStatus(
        title: 'File provider unavailable',
        message: 'The current file provider is unavailable.',
        actionLabel: 'Provider unavailable',
        actionEnabled: false,
        action: _FileBindingStatusAction.unavailable,
      ),
    _ => null,
  };
}

class _FileBindingStatusBanner extends StatelessWidget {
  const _FileBindingStatusBanner({
    required this.status,
    required this.onAcceptExternalChange,
    required this.onSaveLocalChanges,
    required this.onDiscardLocalChanges,
  });

  final _FileBindingStatus status;
  final VoidCallback? onAcceptExternalChange;
  final VoidCallback? onSaveLocalChanges;
  final VoidCallback? onDiscardLocalChanges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionCallback = switch (status.action) {
      _FileBindingStatusAction.acceptExternal => onAcceptExternalChange,
      _FileBindingStatusAction.saveLocal => onSaveLocalChanges,
      _FileBindingStatusAction.discardLocal => onDiscardLocalChanges,
      _FileBindingStatusAction.unavailable => null,
    };
    final secondaryActionCallback = switch (status.secondaryAction) {
      _FileBindingStatusAction.acceptExternal => onAcceptExternalChange,
      _FileBindingStatusAction.saveLocal => onSaveLocalChanges,
      _FileBindingStatusAction.discardLocal => onDiscardLocalChanges,
      _FileBindingStatusAction.unavailable => null,
      null => null,
    };
    return Container(
      key: const ValueKey('editor-file-binding-status-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.36),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(status.message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          OutlinedButton(
            key: const ValueKey('editor-file-binding-accept-external'),
            onPressed: status.actionEnabled ? actionCallback : null,
            child: Text(status.actionLabel),
          ),
          if (status.secondaryActionLabel case final label?)
            TextButton(
              key: const ValueKey('editor-file-binding-secondary-action'),
              onPressed: status.secondaryActionEnabled
                  ? secondaryActionCallback
                  : null,
              child: Text(label),
            ),
        ],
      ),
    );
  }
}

class _SourcePreviewPane extends StatefulWidget {
  const _SourcePreviewPane({
    required this.controller,
    required this.viewportProfile,
    required this.hover,
    required this.completions,
    required this.activeReferences,
    required this.activeToken,
    required this.activeSemanticKind,
    required this.document,
    required this.selection,
    required this.analysis,
    required this.renderPlan,
    required this.semanticThemeBinding,
  });

  final EditorSessionController controller;
  final ViewportProfile viewportProfile;
  final HoverPayload? hover;
  final List<CompletionItem> completions;
  final List<ReferenceSpan> activeReferences;
  final TokenSpan? activeToken;
  final SemanticKind? activeSemanticKind;
  final DocumentState document;
  final SelectionState selection;
  final StyioDocumentAnalysis analysis;
  final EditorRenderPlan renderPlan;
  final EditorSemanticThemeBinding semanticThemeBinding;

  @override
  State<_SourcePreviewPane> createState() => _SourcePreviewPaneState();
}

class _SourcePreviewPaneState extends State<_SourcePreviewPane> {
  static const double _gutterWidth = 62;
  static const double _estimatedCharacterWidth = 8.4;
  static const double _estimatedLineHeight = 34;
  static const int _maxRenderedPreviewLines = 400;

  late final FocusNode _focusNode;
  late final FocusNode _inlineRenameFocusNode;
  late final FocusNode _introduceVariableFocusNode;
  late final FocusNode _extractFunctionFocusNode;
  late final FocusNode _changeSignatureNameFocusNode;
  late final FocusNode _changeSignatureParametersFocusNode;
  late final ScrollController _sourceScrollController;
  late final TextEditingController _inlineRenameController;
  late final TextEditingController _introduceVariableController;
  late final TextEditingController _extractFunctionController;
  late final TextEditingController _changeSignatureNameController;
  late final TextEditingController _changeSignatureParametersController;
  int? _dragBaseOffset;
  bool _inlineRenameOpen = false;
  bool _introduceVariablePanelOpen = false;
  bool _extractFunctionPanelOpen = false;
  bool _changeSignaturePanelOpen = false;
  bool _usagesPanelOpen = false;
  bool _safeDeletePanelOpen = false;
  bool _inlineVariablePanelOpen = false;
  bool _quickDocumentationOpen = false;
  bool _quickDocumentationForCompletion = false;
  bool _parameterInfoOpen = false;
  bool _quickFixLookupOpen = false;
  int _quickFixLookupIndex = 0;
  bool _symbolLookupOpen = false;
  int _symbolLookupIndex = 0;
  String _symbolLookupQuery = '';
  bool _completionLookupOpen = false;
  bool _surroundLookupOpen = false;
  int _completionLookupIndex = 0;
  int _surroundLookupIndex = 0;
  final Set<String> _collapsedSemanticBlockKeys = <String>{};
  String? _inlineRenameError;
  String? _introduceVariableError;
  String? _extractFunctionError;
  String? _changeSignatureError;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'editor-source-pane');
    _focusNode.addListener(_handleFocusChanged);
    _inlineRenameFocusNode = FocusNode(debugLabel: 'editor-inline-rename');
    _introduceVariableFocusNode = FocusNode(
      debugLabel: 'editor-introduce-variable',
    );
    _extractFunctionFocusNode = FocusNode(debugLabel: 'editor-extract-method');
    _changeSignatureNameFocusNode = FocusNode(
      debugLabel: 'editor-change-signature-name',
    );
    _changeSignatureParametersFocusNode = FocusNode(
      debugLabel: 'editor-change-signature-parameters',
    );
    _sourceScrollController = ScrollController()
      ..addListener(_handleSourceScrollChanged);
    _inlineRenameController = TextEditingController();
    _introduceVariableController = TextEditingController();
    _extractFunctionController = TextEditingController();
    _changeSignatureNameController = TextEditingController();
    _changeSignatureParametersController = TextEditingController();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _inlineRenameFocusNode.dispose();
    _introduceVariableFocusNode.dispose();
    _extractFunctionFocusNode.dispose();
    _changeSignatureNameFocusNode.dispose();
    _changeSignatureParametersFocusNode.dispose();
    _sourceScrollController
      ..removeListener(_handleSourceScrollChanged)
      ..dispose();
    _inlineRenameController.dispose();
    _introduceVariableController.dispose();
    _extractFunctionController.dispose();
    _changeSignatureNameController.dispose();
    _changeSignatureParametersController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSourceScrollChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final commandPressed =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final altPressed = HardwareKeyboard.instance.isAltPressed;
    if (_inlineRenameFocusNode.hasFocus) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyInlineRename()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.escape:
          _closeInlineRename();
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_introduceVariableFocusNode.hasFocus) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyIntroduceVariable()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.escape:
          _closeIntroduceVariablePanel();
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_extractFunctionFocusNode.hasFocus) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyExtractFunction()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.escape:
          _closeExtractFunctionPanel();
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_changeSignatureNameFocusNode.hasFocus ||
        _changeSignatureParametersFocusNode.hasFocus) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyChangeSignature()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.escape:
          _closeChangeSignaturePanel();
          return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_usagesPanelOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      _closeUsagesPanel();
      return KeyEventResult.handled;
    }
    if (_safeDeletePanelOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeSafeDeletePanel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applySafeDelete()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
    }
    if (_inlineVariablePanelOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeInlineVariablePanel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyInlineVariable()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
    }
    if (_introduceVariablePanelOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeIntroduceVariablePanel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyIntroduceVariable()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
    }
    if (_extractFunctionPanelOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeExtractFunctionPanel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyExtractFunction()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
    }
    if (_changeSignaturePanelOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeChangeSignaturePanel();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
          return _applyChangeSignature()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
    }
    if (_quickDocumentationOpen &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeQuickDocumentation();
      return KeyEventResult.handled;
    }
    if (_parameterInfoOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      _closeParameterInfo();
      return KeyEventResult.handled;
    }
    if (_quickFixLookupOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeQuickFixLookup();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _moveQuickFixLookupSelection(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _moveQuickFixLookupSelection(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
        case LogicalKeyboardKey.tab:
          return _applySelectedQuickFix()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        default:
          if (!commandPressed && _isPlainTextCharacter(event.character)) {
            setState(() {
              _quickFixLookupOpen = false;
              _quickFixLookupIndex = 0;
            });
          }
      }
    }
    if (_symbolLookupOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeSymbolLookup();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _moveSymbolLookupSelection(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _moveSymbolLookupSelection(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
        case LogicalKeyboardKey.tab:
          return _applySelectedSymbol()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.backspace:
          if (_symbolLookupQuery.isEmpty) {
            return KeyEventResult.handled;
          }
          setState(() {
            _symbolLookupQuery = _symbolLookupQuery.substring(
              0,
              _symbolLookupQuery.length - 1,
            );
            _symbolLookupIndex = 0;
          });
          return KeyEventResult.handled;
        default:
          if (!commandPressed && _isPlainTextCharacter(event.character)) {
            setState(() {
              _symbolLookupQuery += event.character!;
              _symbolLookupIndex = 0;
            });
            return KeyEventResult.handled;
          }
      }
    }
    if (_surroundLookupOpen) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeSurroundLookup();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _moveSurroundLookupSelection(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _moveSurroundLookupSelection(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
        case LogicalKeyboardKey.tab:
          return _applySelectedSurroundTemplate()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        default:
          if (!commandPressed && _isPlainTextCharacter(event.character)) {
            setState(() {
              _surroundLookupOpen = false;
            });
          }
      }
    }
    if (_completionLookupOpen) {
      if (event.logicalKey == LogicalKeyboardKey.keyQ &&
          (commandPressed || !_isPlainTextCharacter(event.character))) {
        return _openCompletionQuickDocumentation()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _closeCompletionLookup();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          _moveCompletionLookupSelection(1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          _moveCompletionLookupSelection(-1);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
        case LogicalKeyboardKey.tab:
          return _applySelectedCompletion()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        default:
          if (!commandPressed && _isPlainTextCharacter(event.character)) {
            setState(() {
              _completionLookupOpen = false;
            });
          }
      }
    }

    if ((commandPressed || altPressed) &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      widget.controller.moveCaretByWord(
        forward: event.logicalKey == LogicalKeyboardKey.arrowRight,
        expandSelection: shiftPressed,
      );
      return KeyEventResult.handled;
    }

    if (commandPressed &&
        altPressed &&
        event.logicalKey == LogicalKeyboardKey.keyT) {
      return _openSurroundLookup()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed &&
        altPressed &&
        !shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyV) {
      return _openIntroduceVariablePanel()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed &&
        altPressed &&
        !shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyM) {
      return _openExtractFunctionPanel()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed &&
        altPressed &&
        !shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyN) {
      return _openInlineVariablePanel()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed &&
        altPressed &&
        shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyN) {
      return _openSymbolLookup()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (!commandPressed &&
        altPressed &&
        event.logicalKey == LogicalKeyboardKey.delete) {
      final opened = _openSafeDeletePanel();
      if (opened) {
        return KeyEventResult.handled;
      }
    }

    if ((commandPressed || altPressed) &&
        (event.logicalKey == LogicalKeyboardKey.backspace ||
            event.logicalKey == LogicalKeyboardKey.delete)) {
      return widget.controller.deleteToWordBoundary(
            forward: event.logicalKey == LogicalKeyboardKey.delete,
          )
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed &&
        (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.numpadSubtract)) {
      return _toggleSemanticBlockAtSelection()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed &&
        !altPressed &&
        !shiftPressed &&
        event.logicalKey == LogicalKeyboardKey.f6) {
      return _openChangeSignaturePanel()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyB:
          return widget.controller.selectDefinitionAtSelection()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyC:
          return _copySelectionToClipboard()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyD:
          return widget.controller.duplicateLineOrSelection()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.space:
          return _openCompletionLookup()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyJ:
          return (shiftPressed
                  ? widget.controller.joinLinesAtSelection()
                  : widget.controller.applyBestCompletionAtSelection())
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyM:
          if (!shiftPressed) {
            return KeyEventResult.ignored;
          }
          return widget.controller.moveCaretToMatchingBrace()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyQ:
          return _openQuickDocumentation()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyP:
          return _openParameterInfo()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.slash:
        case LogicalKeyboardKey.numpadDivide:
          return widget.controller.toggleLineComment()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyW:
          return (shiftPressed
                  ? widget.controller.shrinkSelectionStructurally()
                  : widget.controller.extendSelectionStructurally())
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.keyY:
          if (shiftPressed) {
            return KeyEventResult.ignored;
          }
          return widget.controller.deleteLineAtSelection()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
      return KeyEventResult.ignored;
    }

    if (altPressed && event.logicalKey == LogicalKeyboardKey.f7) {
      return _openUsagesPanel()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (altPressed &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      return _openQuickFixLookup()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (shiftPressed && event.logicalKey == LogicalKeyboardKey.f6) {
      return _openInlineRename()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (altPressed && shiftPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          return widget.controller.moveLineOrSelection(down: false)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        case LogicalKeyboardKey.arrowDown:
          return widget.controller.moveLineOrSelection(down: true)
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
      }
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        widget.controller.moveCaretHorizontally(
          -1,
          expandSelection: shiftPressed,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        widget.controller.moveCaretHorizontally(
          1,
          expandSelection: shiftPressed,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        widget.controller.moveCaretVertically(
          -1,
          expandSelection: shiftPressed,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        widget.controller.moveCaretVertically(1, expandSelection: shiftPressed);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        widget.controller.moveCaretToSmartLineStart(
          expandSelection: shiftPressed,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        widget.controller.moveCaretToLineBoundary(
          end: true,
          expandSelection: shiftPressed,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
        widget.controller.backspace();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
        widget.controller.deleteForward();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        widget.controller.insertNewline();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
        if (shiftPressed) {
          return widget.controller.outdentLineOrSelection()
              ? KeyEventResult.handled
              : KeyEventResult.ignored;
        }
        if (widget.controller.shouldIndentLineAtSelection &&
            widget.controller.indentLineOrSelection()) {
          return KeyEventResult.handled;
        }
        if (!shiftPressed &&
            widget.controller.applyTokenCompletionAtSelection()) {
          return KeyEventResult.handled;
        }
        widget.controller.insertText('  ');
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f2:
        return (shiftPressed
                ? widget.controller.selectPreviousDiagnosticAtSelection()
                : widget.controller.selectNextDiagnosticAtSelection())
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      case LogicalKeyboardKey.f3:
        return (shiftPressed
                ? widget.controller.selectPreviousReferenceAtSelection()
                : widget.controller.selectNextReferenceAtSelection())
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      default:
        final character = event.character;
        if (_isPlainTextCharacter(character)) {
          widget.controller.insertTypedCharacter(character!);
          _openCompletionLookupAfterTyping(character);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
  }

  bool _copySelectionToClipboard() {
    final selectedSourceText = widget.controller.selectedSourceText;
    if (selectedSourceText == null) {
      return false;
    }
    Clipboard.setData(ClipboardData(text: selectedSourceText));
    return true;
  }

  bool _isPlainTextCharacter(String? character) {
    if (character == null || character.isEmpty) {
      return false;
    }

    final codeUnit = character.codeUnitAt(0);
    if (codeUnit < 0x20 || codeUnit == 0x7F) {
      return false;
    }

    return character != '\n' && character != '\r';
  }

  void _openCompletionLookupAfterTyping(String character) {
    if (!_shouldAutoPopupCompletion(character)) {
      return;
    }
    final completions = widget.completions;
    if (completions.isEmpty) {
      return;
    }
    final activeSpan = widget.controller.tokenAtSelection;
    if (activeSpan == null ||
        activeSpan.kind == TokenKind.comment ||
        activeSpan.kind == TokenKind.string ||
        activeSpan.kind == TokenKind.number ||
        activeSpan.kind == TokenKind.whitespace) {
      return;
    }
    setState(() {
      _completionLookupOpen = true;
      _completionLookupIndex = 0;
      _surroundLookupOpen = false;
      _symbolLookupOpen = false;
      _quickFixLookupOpen = false;
    });
  }

  CompletionItem? _selectedCompletionItem() {
    if (widget.completions.isEmpty) {
      return null;
    }
    final selectedIndex = _completionLookupIndex
        .clamp(0, widget.completions.length - 1)
        .toInt();
    return widget.completions[selectedIndex];
  }

  bool _shouldAutoPopupCompletion(String character) {
    if (character.length != 1) {
      return false;
    }
    final codeUnit = character.codeUnitAt(0);
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
        character == '_' ||
        character == '@' ||
        character == '#';
  }

  bool _toggleSemanticBlockAtSelection() {
    final semanticBlock = _semanticBlockAtSelection();
    if (semanticBlock == null) {
      return false;
    }
    _toggleSemanticBlock(semanticBlock);
    return true;
  }

  _SemanticLineBlock? _semanticBlockAtSelection() {
    if (!widget.renderPlan.activeLayers.contains(EditorRenderLayer.overlay)) {
      return null;
    }

    final lineStarts = widget.document.lineStarts;
    final selectionLine = widget.document
        .positionForOffset(widget.selection.extentOffset)
        .line;
    final candidates =
        _resolveLineBlocks(
              document: widget.document,
              lineStarts: lineStarts,
              blocks: widget.analysis.semanticBlocks,
            )
            .where(
              (block) =>
                  block.startLine <= selectionLine &&
                  selectionLine <= block.endLine &&
                  block.endLine > block.startLine,
            )
            .toList(growable: false);
    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((left, right) {
      final leftSpan = left.endLine - left.startLine;
      final rightSpan = right.endLine - right.startLine;
      return leftSpan.compareTo(rightSpan);
    });
    return candidates.first;
  }

  void _toggleSemanticBlock(_SemanticLineBlock block) {
    final key = _semanticBlockKey(block);
    setState(() {
      if (!_collapsedSemanticBlockKeys.add(key)) {
        _collapsedSemanticBlockKeys.remove(key);
      }
    });
  }

  bool _openInlineRename() {
    final definition = widget.controller.definitionAtSelection;
    if (definition == null) {
      return false;
    }

    setState(() {
      _inlineRenameOpen = true;
      _inlineRenameError = null;
      _inlineRenameController.text = definition.symbol.name;
      _inlineRenameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: definition.symbol.name.length,
      );
      _introduceVariablePanelOpen = false;
      _extractFunctionPanelOpen = false;
      _changeSignaturePanelOpen = false;
      _safeDeletePanelOpen = false;
      _inlineVariablePanelOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inlineRenameOpen) {
        _inlineRenameFocusNode.requestFocus();
      }
    });
    return true;
  }

  void _closeInlineRename() {
    setState(() {
      _inlineRenameOpen = false;
      _inlineRenameError = null;
    });
    _focusNode.requestFocus();
  }

  bool _applyInlineRename() {
    final newName = _inlineRenameController.text.trim();
    final renamePlan = widget.controller.renamePlanAtSelection(newName);
    if (renamePlan != null &&
        !renamePlan.hasConflicts &&
        widget.controller.applyRename(newName)) {
      setState(() {
        _inlineRenameOpen = false;
        _inlineRenameError = null;
      });
      _focusNode.requestFocus();
      return true;
    }

    setState(() {
      _inlineRenameError = _renameUnavailableMessage(newName, renamePlan);
    });
    return false;
  }

  String _renameUnavailableMessage(String newName, RenamePlan? renamePlan) {
    if (newName.isEmpty) {
      return 'Enter a Styio identifier.';
    }
    if (renamePlan != null && renamePlan.hasConflicts) {
      return _formatRenameConflict(renamePlan.conflicts.first);
    }
    return 'Invalid rename target.';
  }

  bool _openIntroduceVariablePanel() {
    if (widget.selection.isCollapsed) {
      return false;
    }
    final initialName = _availableIntroduceVariableName();
    if (widget.controller.introduceVariablePlanAtSelection(initialName) ==
        null) {
      return false;
    }
    setState(() {
      _introduceVariablePanelOpen = true;
      _introduceVariableError = null;
      _introduceVariableController.text = initialName;
      _introduceVariableController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialName.length,
      );
      _extractFunctionPanelOpen = false;
      _changeSignaturePanelOpen = false;
      _inlineVariablePanelOpen = false;
      _safeDeletePanelOpen = false;
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _introduceVariablePanelOpen) {
        _introduceVariableFocusNode.requestFocus();
      }
    });
    return true;
  }

  void _closeIntroduceVariablePanel() {
    setState(() {
      _introduceVariablePanelOpen = false;
      _introduceVariableError = null;
    });
    _focusNode.requestFocus();
  }

  bool _applyIntroduceVariable() {
    final name = _introduceVariableController.text.trim();
    final plan = widget.controller.introduceVariablePlanAtSelection(name);
    if (plan != null &&
        !plan.hasConflicts &&
        widget.controller.applyIntroduceVariableAtSelection(name)) {
      setState(() {
        _introduceVariablePanelOpen = false;
        _introduceVariableError = null;
      });
      _focusNode.requestFocus();
      return true;
    }

    setState(() {
      _introduceVariableError = _introduceVariableUnavailableMessage(plan);
    });
    return false;
  }

  String _introduceVariableUnavailableMessage(IntroduceVariablePlan? plan) {
    if (plan != null && plan.hasConflicts) {
      return _formatIntroduceVariableConflict(plan.conflicts.first);
    }
    return 'Select a Styio expression.';
  }

  String _formatIntroduceVariableConflict(IntroduceVariableConflict conflict) {
    return '${conflict.message} Conflict at '
        '${_formatUsageLocationForRange(conflict.range)}.';
  }

  String _availableIntroduceVariableName() {
    const baseName = 'extractedValue';
    final existingNames = {
      for (final symbol in widget.analysis.documentSymbols) symbol.name,
    };
    if (!existingNames.contains(baseName)) {
      return baseName;
    }
    for (var suffix = 2; suffix < 100; suffix += 1) {
      final candidate = '$baseName$suffix';
      if (!existingNames.contains(candidate)) {
        return candidate;
      }
    }
    return '${baseName}100';
  }

  bool _openExtractFunctionPanel() {
    if (widget.selection.isCollapsed) {
      return false;
    }
    final initialName = _availableExtractFunctionName();
    if (widget.controller.extractFunctionPlanAtSelection(initialName) == null) {
      return false;
    }
    setState(() {
      _extractFunctionPanelOpen = true;
      _extractFunctionError = null;
      _extractFunctionController.text = initialName;
      _extractFunctionController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialName.length,
      );
      _introduceVariablePanelOpen = false;
      _changeSignaturePanelOpen = false;
      _inlineVariablePanelOpen = false;
      _safeDeletePanelOpen = false;
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _extractFunctionPanelOpen) {
        _extractFunctionFocusNode.requestFocus();
      }
    });
    return true;
  }

  void _closeExtractFunctionPanel() {
    setState(() {
      _extractFunctionPanelOpen = false;
      _extractFunctionError = null;
    });
    _focusNode.requestFocus();
  }

  bool _applyExtractFunction() {
    final name = _extractFunctionController.text.trim();
    final plan = widget.controller.extractFunctionPlanAtSelection(name);
    if (plan != null &&
        !plan.hasConflicts &&
        widget.controller.applyExtractFunctionAtSelection(name)) {
      setState(() {
        _extractFunctionPanelOpen = false;
        _extractFunctionError = null;
      });
      _focusNode.requestFocus();
      return true;
    }

    setState(() {
      _extractFunctionError = _extractFunctionUnavailableMessage(plan);
    });
    return false;
  }

  String _extractFunctionUnavailableMessage(ExtractFunctionPlan? plan) {
    if (plan != null && plan.hasConflicts) {
      return _formatExtractFunctionConflict(plan.conflicts.first);
    }
    return 'Select Styio code.';
  }

  String _formatExtractFunctionConflict(ExtractFunctionConflict conflict) {
    return '${conflict.message} Conflict at '
        '${_formatUsageLocationForRange(conflict.range)}.';
  }

  String _availableExtractFunctionName() {
    const baseName = 'extractedFunction';
    final existingNames = {
      for (final symbol in widget.analysis.documentSymbols) symbol.name,
    };
    if (!existingNames.contains(baseName)) {
      return baseName;
    }
    for (var suffix = 2; suffix < 100; suffix += 1) {
      final candidate = '$baseName$suffix';
      if (!existingNames.contains(candidate)) {
        return candidate;
      }
    }
    return '${baseName}100';
  }

  bool _openChangeSignaturePanel() {
    final seedPlan = _changeSignatureSeedPlan();
    if (seedPlan == null) {
      return false;
    }
    final parameterText = seedPlan.originalParameters
        .map((parameter) => parameter.name)
        .join(', ');
    setState(() {
      _changeSignaturePanelOpen = true;
      _changeSignatureError = null;
      _changeSignatureNameController.text = seedPlan.originalName;
      _changeSignatureNameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: seedPlan.originalName.length,
      );
      _changeSignatureParametersController.text = parameterText;
      _changeSignatureParametersController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: parameterText.length,
      );
      _inlineRenameOpen = false;
      _introduceVariablePanelOpen = false;
      _extractFunctionPanelOpen = false;
      _inlineVariablePanelOpen = false;
      _safeDeletePanelOpen = false;
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _changeSignaturePanelOpen) {
        _changeSignatureNameFocusNode.requestFocus();
      }
    });
    return true;
  }

  void _closeChangeSignaturePanel() {
    setState(() {
      _changeSignaturePanelOpen = false;
      _changeSignatureError = null;
    });
    _focusNode.requestFocus();
  }

  bool _applyChangeSignature() {
    final seedPlan = _changeSignatureSeedPlan();
    final parameterUpdates = seedPlan == null
        ? null
        : _changeSignatureParameterUpdates(seedPlan);
    final newName = _changeSignatureNameController.text.trim();
    final plan = parameterUpdates == null
        ? null
        : widget.controller.changeSignaturePlanAtSelection(
            newName: newName,
            parameters: parameterUpdates,
          );
    final updatesToApply = parameterUpdates;
    if (updatesToApply != null &&
        plan != null &&
        !plan.hasConflicts &&
        widget.controller.applyChangeSignatureAtSelection(
          newName: newName,
          parameters: updatesToApply,
        )) {
      setState(() {
        _changeSignaturePanelOpen = false;
        _changeSignatureError = null;
      });
      _focusNode.requestFocus();
      return true;
    }

    setState(() {
      _changeSignatureError = _changeSignatureUnavailableMessage(
        seedPlan: seedPlan,
        parameterUpdates: parameterUpdates,
        plan: plan,
      );
    });
    return false;
  }

  ChangeSignaturePlan? _changeSignatureSeedPlan() {
    final definition = widget.controller.definitionAtSelection;
    if (definition == null || definition.symbol.kind != SymbolKind.function) {
      return null;
    }
    return widget.controller.changeSignaturePlanAtSelection(
      newName: definition.symbol.name,
      parameters: const <ChangeSignatureParameterUpdate>[],
    );
  }

  List<ChangeSignatureParameterUpdate>? _changeSignatureParameterUpdates(
    ChangeSignaturePlan seedPlan,
  ) {
    final originalNames = seedPlan.originalParameters
        .map((parameter) => parameter.name)
        .toList(growable: false);
    final enteredNames = _changeSignatureParametersController.text
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    final originalNameSet = originalNames.toSet();
    final enteredNameSet = enteredNames.toSet();
    final reusesExistingParameters =
        enteredNameSet.length == enteredNames.length &&
        enteredNameSet.every(originalNameSet.contains);
    if (reusesExistingParameters) {
      return [
        for (final name in enteredNames)
          ChangeSignatureParameterUpdate(originalName: name, name: name),
      ];
    }

    if (enteredNames.length != originalNames.length) {
      return null;
    }

    return [
      for (var index = 0; index < originalNames.length; index += 1)
        ChangeSignatureParameterUpdate(
          originalName: originalNames[index],
          name: enteredNames[index],
        ),
    ];
  }

  String _changeSignatureUnavailableMessage({
    required ChangeSignaturePlan? seedPlan,
    required List<ChangeSignatureParameterUpdate>? parameterUpdates,
    required ChangeSignaturePlan? plan,
  }) {
    if (seedPlan == null) {
      return 'Place the caret on a Styio function.';
    }
    if (parameterUpdates == null) {
      return 'Enter up to ${seedPlan.originalParameters.length} comma-separated '
          'parameter${seedPlan.originalParameters.length == 1 ? '' : 's'}.';
    }
    if (plan != null && plan.hasConflicts) {
      return _formatChangeSignatureConflict(plan.conflicts.first);
    }
    return 'Enter a changed Styio function signature.';
  }

  String _formatChangeSignatureConflict(ChangeSignatureConflict conflict) {
    return '${conflict.message} Conflict at '
        '${_formatUsageLocationForRange(conflict.range)}.';
  }

  String _formatRenameConflict(RenameConflict conflict) {
    return '${conflict.message} Conflict at '
        '${_formatUsageLocationForRange(conflict.range)}.';
  }

  bool _openUsagesPanel() {
    if (widget.controller.definitionAtSelection == null ||
        widget.controller.referencesAtSelection.isEmpty) {
      return false;
    }
    setState(() {
      _usagesPanelOpen = true;
    });
    return true;
  }

  void _closeUsagesPanel() {
    setState(() {
      _usagesPanelOpen = false;
    });
    _focusNode.requestFocus();
  }

  bool _openSafeDeletePanel() {
    if (widget.controller.safeDeletePlanAtSelection == null) {
      return false;
    }
    setState(() {
      _safeDeletePanelOpen = true;
      _extractFunctionPanelOpen = false;
      _introduceVariablePanelOpen = false;
      _changeSignaturePanelOpen = false;
      _inlineVariablePanelOpen = false;
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    return true;
  }

  void _closeSafeDeletePanel() {
    setState(() {
      _safeDeletePanelOpen = false;
    });
    _focusNode.requestFocus();
  }

  bool _applySafeDelete() {
    final applied = widget.controller.applySafeDeleteAtSelection();
    if (!applied) {
      return false;
    }
    setState(() {
      _safeDeletePanelOpen = false;
    });
    _focusNode.requestFocus();
    return true;
  }

  bool _openInlineVariablePanel() {
    if (widget.controller.inlineVariablePlanAtSelection == null) {
      return false;
    }
    setState(() {
      _inlineVariablePanelOpen = true;
      _extractFunctionPanelOpen = false;
      _introduceVariablePanelOpen = false;
      _changeSignaturePanelOpen = false;
      _safeDeletePanelOpen = false;
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    return true;
  }

  void _closeInlineVariablePanel() {
    setState(() {
      _inlineVariablePanelOpen = false;
    });
    _focusNode.requestFocus();
  }

  bool _applyInlineVariable() {
    final applied = widget.controller.applyInlineVariableAtSelection();
    if (!applied) {
      return false;
    }
    setState(() {
      _inlineVariablePanelOpen = false;
    });
    _focusNode.requestFocus();
    return true;
  }

  bool _openQuickDocumentation() {
    if (widget.hover == null &&
        widget.controller.definitionAtSelection == null &&
        widget.activeToken == null) {
      return false;
    }
    setState(() {
      _quickDocumentationOpen = true;
      _quickDocumentationForCompletion = false;
    });
    return true;
  }

  bool _openCompletionQuickDocumentation() {
    if (_selectedCompletionItem() == null) {
      return false;
    }
    setState(() {
      _quickDocumentationOpen = true;
      _quickDocumentationForCompletion = true;
    });
    return true;
  }

  void _closeQuickDocumentation() {
    setState(() {
      _quickDocumentationOpen = false;
      _quickDocumentationForCompletion = false;
    });
    _focusNode.requestFocus();
  }

  bool _openParameterInfo() {
    if (widget.controller.parameterInfoAtSelection == null) {
      return false;
    }
    setState(() {
      _parameterInfoOpen = true;
    });
    return true;
  }

  void _closeParameterInfo() {
    setState(() {
      _parameterInfoOpen = false;
    });
    _focusNode.requestFocus();
  }

  bool _openCompletionLookup() {
    if (widget.completions.isEmpty) {
      return false;
    }
    setState(() {
      _completionLookupOpen = true;
      _completionLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
    });
    return true;
  }

  void _closeCompletionLookup() {
    setState(() {
      _completionLookupOpen = false;
      if (_quickDocumentationForCompletion) {
        _quickDocumentationOpen = false;
        _quickDocumentationForCompletion = false;
      }
    });
    _focusNode.requestFocus();
  }

  void _moveCompletionLookupSelection(int delta) {
    if (widget.completions.isEmpty) {
      _closeCompletionLookup();
      return;
    }
    setState(() {
      _completionLookupIndex =
          (_completionLookupIndex + delta) % widget.completions.length;
      if (_completionLookupIndex < 0) {
        _completionLookupIndex += widget.completions.length;
      }
    });
  }

  bool _applySelectedCompletion() {
    if (widget.completions.isEmpty) {
      _closeCompletionLookup();
      return false;
    }
    final selectedIndex = _completionLookupIndex
        .clamp(0, widget.completions.length - 1)
        .toInt();
    widget.controller.applyCompletionItem(widget.completions[selectedIndex]);
    setState(() {
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      if (_quickDocumentationForCompletion) {
        _quickDocumentationOpen = false;
        _quickDocumentationForCompletion = false;
      }
    });
    _focusNode.requestFocus();
    return true;
  }

  void _applyCompletionFromLookup(CompletionItem item) {
    widget.controller.applyCompletionItem(item);
    setState(() {
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      if (_quickDocumentationForCompletion) {
        _quickDocumentationOpen = false;
        _quickDocumentationForCompletion = false;
      }
    });
    _focusNode.requestFocus();
  }

  bool _openSurroundLookup() {
    if (widget.controller.surroundTemplatesAtSelection.isEmpty) {
      return false;
    }
    setState(() {
      _surroundLookupOpen = true;
      _surroundLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
    });
    return true;
  }

  void _closeSurroundLookup() {
    setState(() {
      _surroundLookupOpen = false;
    });
    _focusNode.requestFocus();
  }

  void _moveSurroundLookupSelection(int delta) {
    final templates = widget.controller.surroundTemplatesAtSelection;
    if (templates.isEmpty) {
      _closeSurroundLookup();
      return;
    }
    setState(() {
      _surroundLookupIndex = (_surroundLookupIndex + delta) % templates.length;
      if (_surroundLookupIndex < 0) {
        _surroundLookupIndex += templates.length;
      }
    });
  }

  bool _applySelectedSurroundTemplate() {
    final templates = widget.controller.surroundTemplatesAtSelection;
    if (templates.isEmpty) {
      _closeSurroundLookup();
      return false;
    }
    final selectedIndex = _surroundLookupIndex
        .clamp(0, templates.length - 1)
        .toInt();
    widget.controller.applySurroundTemplateAtSelection(
      templates[selectedIndex],
    );
    setState(() {
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    _focusNode.requestFocus();
    return true;
  }

  bool _openSymbolLookup() {
    if (widget.analysis.documentSymbols.isEmpty) {
      return false;
    }
    setState(() {
      _symbolLookupOpen = true;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
    });
    return true;
  }

  void _closeSymbolLookup() {
    setState(() {
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
    });
    _focusNode.requestFocus();
  }

  List<DocumentSymbol> _symbolLookupMatches() {
    final query = _symbolLookupQuery.trim();
    if (query.isEmpty) {
      return widget.analysis.documentSymbols;
    }
    return widget.analysis.documentSymbols
        .where((symbol) => _matchesSymbolLookupQuery(symbol, query))
        .toList(growable: false);
  }

  bool _matchesSymbolLookupQuery(DocumentSymbol symbol, String query) {
    final normalizedQuery = query.toLowerCase();
    final normalizedName = symbol.name.toLowerCase();
    return normalizedName.contains(normalizedQuery) ||
        _charactersAppearInOrder(normalizedQuery, normalizedName);
  }

  bool _charactersAppearInOrder(String needle, String haystack) {
    if (needle.isEmpty) {
      return true;
    }
    var needleIndex = 0;
    for (var index = 0; index < haystack.length; index += 1) {
      if (haystack.codeUnitAt(index) == needle.codeUnitAt(needleIndex)) {
        needleIndex += 1;
        if (needleIndex == needle.length) {
          return true;
        }
      }
    }
    return false;
  }

  void _moveSymbolLookupSelection(int delta) {
    final symbols = _symbolLookupMatches();
    if (symbols.isEmpty) {
      return;
    }
    setState(() {
      _symbolLookupIndex = (_symbolLookupIndex + delta) % symbols.length;
      if (_symbolLookupIndex < 0) {
        _symbolLookupIndex += symbols.length;
      }
    });
  }

  bool _applySelectedSymbol() {
    final symbols = _symbolLookupMatches();
    if (symbols.isEmpty) {
      return false;
    }
    final selectedIndex = _symbolLookupIndex
        .clamp(0, symbols.length - 1)
        .toInt();
    final applied = widget.controller.selectDocumentSymbol(
      symbols[selectedIndex],
    );
    if (!applied) {
      return false;
    }
    setState(() {
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
    });
    _focusNode.requestFocus();
    return true;
  }

  void _selectSymbolFromLookup(DocumentSymbol symbol) {
    if (!widget.controller.selectDocumentSymbol(symbol)) {
      return;
    }
    setState(() {
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
    });
    _focusNode.requestFocus();
  }

  List<DiagnosticQuickFix> _quickFixLookupItems() {
    return widget.controller.contextActionsAtSelection;
  }

  bool _openQuickFixLookup() {
    if (_quickFixLookupItems().isEmpty) {
      return false;
    }
    setState(() {
      _quickFixLookupOpen = true;
      _quickFixLookupIndex = 0;
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
      _symbolLookupOpen = false;
      _symbolLookupIndex = 0;
      _symbolLookupQuery = '';
    });
    return true;
  }

  void _closeQuickFixLookup() {
    setState(() {
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
    });
    _focusNode.requestFocus();
  }

  void _moveQuickFixLookupSelection(int delta) {
    final quickFixes = _quickFixLookupItems();
    if (quickFixes.isEmpty) {
      _closeQuickFixLookup();
      return;
    }
    setState(() {
      _quickFixLookupIndex = (_quickFixLookupIndex + delta) % quickFixes.length;
      if (_quickFixLookupIndex < 0) {
        _quickFixLookupIndex += quickFixes.length;
      }
    });
  }

  bool _applySelectedQuickFix() {
    final quickFixes = _quickFixLookupItems();
    if (quickFixes.isEmpty) {
      _closeQuickFixLookup();
      return false;
    }
    final selectedIndex = _quickFixLookupIndex
        .clamp(0, quickFixes.length - 1)
        .toInt();
    widget.controller.applyDiagnosticQuickFix(quickFixes[selectedIndex]);
    setState(() {
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
    });
    _focusNode.requestFocus();
    return true;
  }

  void _applyQuickFixFromLookup(DiagnosticQuickFix quickFix) {
    widget.controller.applyDiagnosticQuickFix(quickFix);
    setState(() {
      _quickFixLookupOpen = false;
      _quickFixLookupIndex = 0;
    });
    _focusNode.requestFocus();
  }

  void _applySurroundTemplateFromLookup(SurroundTemplate template) {
    widget.controller.applySurroundTemplateAtSelection(template);
    setState(() {
      _surroundLookupOpen = false;
      _surroundLookupIndex = 0;
    });
    _focusNode.requestFocus();
  }

  void _handleLineTapDown(int lineIndex, TapDownDetails details) {
    _focusNode.requestFocus();
    _dragBaseOffset = null;
    widget.controller.selectCollapsed(
      _offsetForLocalPosition(
        originLineIndex: lineIndex,
        localPosition: details.localPosition,
      ),
    );
  }

  void _handleLinePanStart(int lineIndex, DragStartDetails details) {
    _focusNode.requestFocus();
    final offset = _offsetForLocalPosition(
      originLineIndex: lineIndex,
      localPosition: details.localPosition,
    );
    _dragBaseOffset = offset;
    widget.controller.selectRange(baseOffset: offset, extentOffset: offset);
  }

  void _handleLinePanUpdate(int lineIndex, DragUpdateDetails details) {
    final baseOffset = _dragBaseOffset;
    if (baseOffset == null) {
      return;
    }
    widget.controller.selectRange(
      baseOffset: baseOffset,
      extentOffset: _offsetForLocalPosition(
        originLineIndex: lineIndex,
        localPosition: details.localPosition,
      ),
    );
  }

  void _handleLinePanEnd(DragEndDetails details) {
    _dragBaseOffset = null;
  }

  int _offsetForLocalPosition({
    required int originLineIndex,
    required Offset localPosition,
  }) {
    final lineDelta = (localPosition.dy / _estimatedLineHeight).floor();
    final targetLine = (originLineIndex + lineDelta).clamp(
      0,
      widget.document.lines.length - 1,
    );
    final lineText = widget.document.lines[targetLine];
    final relativeDx = (localPosition.dx - _gutterWidth).clamp(
      0.0,
      double.infinity,
    );
    final column = (relativeDx / _estimatedCharacterWidth).round().clamp(
      0,
      lineText.length,
    );
    return widget.document.offsetForLineColumn(
      line: targetLine,
      column: column,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineStarts = widget.document.lineStarts;
    final semanticBlocks =
        widget.renderPlan.activeLayers.contains(EditorRenderLayer.overlay)
        ? _resolveLineBlocks(
            document: widget.document,
            lineStarts: lineStarts,
            blocks: widget.analysis.semanticBlocks,
          )
        : const <_SemanticLineBlock>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            widget.viewportProfile.isMobile ||
            constraints.maxWidth < 480 ||
            constraints.maxHeight < 300;
        final dense =
            (widget.viewportProfile.isMobile && constraints.maxWidth < 520) ||
            constraints.maxWidth < 380 ||
            constraints.maxHeight < 240;
        final cramped = constraints.maxHeight < 120;
        final contentPadding = dense ? 12.0 : 18.0;
        final scrollOffset = _sourceScrollController.hasClients
            ? _sourceScrollController.offset
            : _sourceScrollController.initialScrollOffset;
        final viewportBinding =
            EditorRenderViewportBinding.fromScrollControllerFacts(
              scrollOffsetPixels: scrollOffset,
              viewportHeightPixels: constraints.maxHeight,
              lineHeightPixels: _estimatedLineHeight,
              overscanLineCount: dense ? 4 : 8,
              totalLineCount: widget.document.lines.length,
            );
        final renderPipelinePlan = EditorRenderPipelinePlan.fromRenderFacts(
          renderPlan: widget.renderPlan,
          lineCount: widget.document.lines.length,
          viewportBinding: viewportBinding,
          maxRenderedLines: _maxRenderedPreviewLines,
        );

        return Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            child: Container(
              key: const ValueKey('source-buffer-surface'),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2E9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? const Color(0xFF8B7CC5)
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              padding: EdgeInsets.all(cramped ? 8 : contentPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!cramped)
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Source Buffer',
                          style: theme.textTheme.titleMedium,
                        ),
                        _CapabilityPill(
                          label: _focusNode.hasFocus
                              ? 'editing'
                              : 'click to focus',
                        ),
                        _CapabilityPill(
                          label: viewportBinding.boundToScrollController
                              ? 'viewport bound'
                              : 'viewport unbound',
                        ),
                        _CapabilityPill(
                          label:
                              'visible ${viewportBinding.viewportFirstLine + 1}+${viewportBinding.viewportLineCapacity}',
                        ),
                        _CapabilityPill(
                          label: 'renderer ${renderPipelinePlan.rendererKind}',
                        ),
                      ],
                    ),
                  if (!dense && !cramped) ...[
                    const SizedBox(height: 6),
                    Text(
                      compact
                          ? 'Glyph substitution stays display-only while one editor surface owns input.'
                          : 'Desktop keyboard input is live. Token spans color the buffer, semantic ranges add structure, and glyph substitution stays display-only.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (!cramped) const SizedBox(height: 14),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('source-buffer-scroll'),
                      controller: _sourceScrollController,
                      children: [
                        KeyedSubtree(
                          key: ValueKey(
                            viewportBinding.boundToScrollController
                                ? 'source-viewport-binding-bound'
                                : 'source-viewport-binding-unbound',
                          ),
                          child: const SizedBox.shrink(),
                        ),
                        if (_inlineRenameOpen) ...[
                          _buildInlineRenamePanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_introduceVariablePanelOpen) ...[
                          _buildIntroduceVariablePanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_extractFunctionPanelOpen) ...[
                          _buildExtractFunctionPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_changeSignaturePanelOpen) ...[
                          _buildChangeSignaturePanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_surroundLookupOpen) ...[
                          _buildSurroundLookupPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_completionLookupOpen) ...[
                          _buildCompletionLookupPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_symbolLookupOpen) ...[
                          _buildSymbolLookupPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_quickFixLookupOpen) ...[
                          _buildQuickFixLookupPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_quickDocumentationOpen) ...[
                          _buildQuickDocumentationPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_parameterInfoOpen) ...[
                          _buildParameterInfoPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_usagesPanelOpen) ...[
                          _buildUsagesPanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_safeDeletePanelOpen) ...[
                          _buildSafeDeletePanel(context),
                          const SizedBox(height: 12),
                        ],
                        if (_inlineVariablePanelOpen) ...[
                          _buildInlineVariablePanel(context),
                          const SizedBox(height: 12),
                        ],
                        ..._buildPreviewChildren(
                          context,
                          controller: widget.controller,
                          viewportProfile: widget.viewportProfile,
                          hover: widget.hover,
                          completions: widget.completions,
                          activeReferences: widget.activeReferences,
                          activeToken: widget.activeToken,
                          activeSemanticKind: widget.activeSemanticKind,
                          document: widget.document,
                          selection: widget.selection,
                          analysis: widget.analysis,
                          renderPlan: widget.renderPlan,
                          semanticThemeBinding: widget.semanticThemeBinding,
                          lineStarts: lineStarts,
                          semanticBlocks: semanticBlocks,
                          maxRenderedLineCount: _maxRenderedPreviewLines,
                          collapsedSemanticBlockKeys:
                              _collapsedSemanticBlockKeys,
                          onToggleSemanticBlock: _toggleSemanticBlock,
                          onTapLine: _handleLineTapDown,
                          onPanStartLine: _handleLinePanStart,
                          onPanUpdateLine: _handleLinePanUpdate,
                          onPanEnd: _handleLinePanEnd,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickFixLookupPanel(BuildContext context) {
    final theme = Theme.of(context);
    final quickFixes = _quickFixLookupItems();
    final diagnostics = widget.controller.diagnosticsAtSelection;
    final actionCount = quickFixes.length;
    final selectedIndex = quickFixes.isEmpty
        ? -1
        : _quickFixLookupIndex.clamp(0, quickFixes.length - 1).toInt();
    final selectedQuickFix = selectedIndex < 0
        ? null
        : quickFixes[selectedIndex];

    return Material(
      key: const ValueKey('source-quick-fix-lookup'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tips_and_updates_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Context Actions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-quick-fix-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeQuickFixLookup,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${diagnostics.length} diagnostic'
              '${diagnostics.length == 1 ? '' : 's'} at caret, '
              '$actionCount context action'
              '${actionCount == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (quickFixes.isEmpty)
              Text(
                'No context actions at the current caret.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (var index = 0; index < quickFixes.length; index += 1) ...[
                _QuickFixLookupTile(
                  key: ValueKey('source-quick-fix-item-$index'),
                  quickFix: quickFixes[index],
                  selected: index == selectedIndex,
                  onTap: () => _applyQuickFixFromLookup(quickFixes[index]),
                ),
                if (index < quickFixes.length - 1) const SizedBox(height: 6),
              ],
            if (selectedQuickFix != null) ...[
              const SizedBox(height: 10),
              _buildQuickFixPreviewPanel(context, selectedQuickFix),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFixPreviewPanel(
    BuildContext context,
    DiagnosticQuickFix quickFix,
  ) {
    final theme = Theme.of(context);
    final edits = quickFix.edits;
    return Container(
      key: const ValueKey('source-quick-fix-preview'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C2)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview ${edits.length} edit${edits.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < edits.length; index += 1) ...[
            Text(
              _formatQuickFixEditPreview(edits[index]),
              key: ValueKey('source-quick-fix-preview-edit-$index'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (index < edits.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  String _formatQuickFixEditPreview(FormattingEdit edit) {
    final start = edit.range.start.clamp(0, widget.document.length);
    final end = edit.range.end.clamp(start, widget.document.length);
    final range = SourceRange(start: start, end: end);
    final location = _formatUsageLocationForRange(range);
    final newText = _formatPreviewText(edit.newText);
    if (range.isCollapsed) {
      return 'Insert $newText at $location';
    }
    final oldText = _formatPreviewText(
      widget.document.text.substring(start, end),
    );
    if (edit.newText.isEmpty) {
      return 'Delete $oldText at $location';
    }
    return 'Replace $oldText with $newText at $location';
  }

  String _formatPreviewText(String text) {
    final escaped = text.replaceAll('\n', r'\n');
    if (escaped.isEmpty) {
      return 'empty text';
    }
    const maxLength = 40;
    final compact = escaped.length <= maxLength
        ? escaped
        : '${escaped.substring(0, maxLength - 1)}...';
    return '`$compact`';
  }

  Widget _buildSymbolLookupPanel(BuildContext context) {
    final theme = Theme.of(context);
    final symbols = _symbolLookupMatches();
    final selectedIndex = symbols.isEmpty
        ? -1
        : _symbolLookupIndex.clamp(0, symbols.length - 1).toInt();
    final queryLabel = _symbolLookupQuery.isEmpty
        ? 'All current-file symbols'
        : _symbolLookupQuery;

    return Material(
      key: const ValueKey('source-symbol-lookup'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_search_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Go to Symbol',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-symbol-lookup-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeSymbolLookup,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('source-symbol-lookup-query'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD8D0C2)),
              ),
              child: Text(
                queryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall!.copyWith(
                  fontWeight: _symbolLookupQuery.isEmpty
                      ? FontWeight.w500
                      : FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (symbols.isEmpty)
              Text(
                'No current-file symbols match.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${symbols.length} current-file symbol'
                '${symbols.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < symbols.length; index += 1) ...[
                _SymbolLookupTile(
                  key: ValueKey('source-symbol-lookup-item-$index'),
                  symbol: symbols[index],
                  selected: index == selectedIndex,
                  location: _formatUsageLocationForRange(
                    symbols[index].nameRange,
                  ),
                  onTap: () => _selectSymbolFromLookup(symbols[index]),
                ),
                if (index < symbols.length - 1) const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineRenamePanel(BuildContext context) {
    final theme = Theme.of(context);
    final renameText = _inlineRenameController.text.trim();
    final renamePreview = widget.controller.renamePlanAtSelection(renameText);
    final definition = widget.controller.definitionAtSelection;
    final usageCount = widget.controller.referencesAtSelection.length;
    final helperText = renamePreview == null
        ? _inlineRenameError
        : renamePreview.hasConflicts
        ? _formatRenameConflict(renamePreview.conflicts.first)
        : 'Preview ${renamePreview.edits.length} edit'
              '${renamePreview.edits.length == 1 ? '' : 's'} across '
              '$usageCount current-file usage'
              '${usageCount == 1 ? '' : 's'}';

    return Material(
      key: const ValueKey('source-inline-rename-panel'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.drive_file_rename_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    definition == null
                        ? 'Rename symbol'
                        : 'Rename ${definition.symbol.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('source-inline-rename-input'),
              focusNode: _inlineRenameFocusNode,
              controller: _inlineRenameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: 'New name',
                helperText: renamePreview == null || renamePreview.hasConflicts
                    ? null
                    : helperText,
                errorText: renamePreview == null || renamePreview.hasConflicts
                    ? helperText
                    : null,
              ),
              onChanged: (_) {
                setState(() {
                  _inlineRenameError = null;
                });
              },
              onSubmitted: (_) => _applyInlineRename(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineActionChip(
                  key: const ValueKey('source-inline-rename-apply'),
                  icon: Icons.check_rounded,
                  label: 'Refactor',
                  onTap: _applyInlineRename,
                ),
                _InlineActionChip(
                  key: const ValueKey('source-inline-rename-cancel'),
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: _closeInlineRename,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroduceVariablePanel(BuildContext context) {
    final theme = Theme.of(context);
    final variableName = _introduceVariableController.text.trim();
    final plan = widget.controller.introduceVariablePlanAtSelection(
      variableName,
    );
    final helperText = plan == null
        ? _introduceVariableError
        : plan.hasConflicts
        ? _formatIntroduceVariableConflict(plan.conflicts.first)
        : 'Preview ${plan.edits.length} edit'
              '${plan.edits.length == 1 ? '' : 's'} for '
              '` ${plan.expressionText} `';

    return Material(
      key: const ValueKey('source-introduce-variable-panel'),
      color: const Color(0xFFF0F7F4),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_box_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Introduce Variable',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('source-introduce-variable-input'),
              focusNode: _introduceVariableFocusNode,
              controller: _introduceVariableController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: 'Variable name',
                helperText: plan == null || plan.hasConflicts
                    ? null
                    : helperText,
                errorText: plan == null || plan.hasConflicts
                    ? helperText
                    : null,
              ),
              onChanged: (_) {
                setState(() {
                  _introduceVariableError = null;
                });
              },
              onSubmitted: (_) => _applyIntroduceVariable(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineActionChip(
                  key: const ValueKey('source-introduce-variable-apply'),
                  icon: Icons.check_rounded,
                  label: 'Introduce',
                  onTap: _applyIntroduceVariable,
                ),
                _InlineActionChip(
                  key: const ValueKey('source-introduce-variable-cancel'),
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: _closeIntroduceVariablePanel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtractFunctionPanel(BuildContext context) {
    final theme = Theme.of(context);
    final functionName = _extractFunctionController.text.trim();
    final plan = widget.controller.extractFunctionPlanAtSelection(functionName);
    final duplicateCount = plan?.duplicateOccurrences.length ?? 0;
    final duplicateLabel = duplicateCount == 1 ? 'duplicate' : 'duplicates';
    final duplicateHelperSuffix = duplicateCount == 0
        ? ''
        : ', $duplicateCount $duplicateLabel';
    final duplicatePreviewSuffix = duplicateCount == 0
        ? ''
        : ' and $duplicateCount $duplicateLabel';
    final helperText = plan == null
        ? _extractFunctionError
        : plan.hasConflicts
        ? _formatExtractFunctionConflict(plan.conflicts.first)
        : 'Preview ${plan.edits.length} edit'
              '${plan.edits.length == 1 ? '' : 's'} and '
              '${plan.parameters.length} parameter'
              '${plan.parameters.length == 1 ? '' : 's'}'
              '$duplicateHelperSuffix';

    return Material(
      key: const ValueKey('source-extract-function-panel'),
      color: const Color(0xFFF0F7F4),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.functions_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Extract Function',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('source-extract-function-input'),
              focusNode: _extractFunctionFocusNode,
              controller: _extractFunctionController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: 'Function name',
                helperText: plan == null || plan.hasConflicts
                    ? null
                    : helperText,
                errorText: plan == null || plan.hasConflicts
                    ? helperText
                    : null,
              ),
              onChanged: (_) {
                setState(() {
                  _extractFunctionError = null;
                });
              },
              onSubmitted: (_) => _applyExtractFunction(),
            ),
            if (plan != null && !plan.hasConflicts) ...[
              const SizedBox(height: 8),
              Text(
                'Replace selection'
                '$duplicatePreviewSuffix '
                'with `${plan.callText}`',
                key: const ValueKey('source-extract-function-preview'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineActionChip(
                  key: const ValueKey('source-extract-function-apply'),
                  icon: Icons.check_rounded,
                  label: 'Extract',
                  onTap: _applyExtractFunction,
                ),
                _InlineActionChip(
                  key: const ValueKey('source-extract-function-cancel'),
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: _closeExtractFunctionPanel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeSignaturePanel(BuildContext context) {
    final theme = Theme.of(context);
    final seedPlan = _changeSignatureSeedPlan();
    final parameterUpdates = seedPlan == null
        ? null
        : _changeSignatureParameterUpdates(seedPlan);
    final functionName = _changeSignatureNameController.text.trim();
    final plan = parameterUpdates == null
        ? null
        : widget.controller.changeSignaturePlanAtSelection(
            newName: functionName,
            parameters: parameterUpdates,
          );
    final helperText = plan == null
        ? _changeSignatureError ??
              _changeSignatureUnavailableMessage(
                seedPlan: seedPlan,
                parameterUpdates: parameterUpdates,
                plan: plan,
              )
        : plan.hasConflicts
        ? _formatChangeSignatureConflict(plan.conflicts.first)
        : 'Preview ${plan.edits.length} edit'
              '${plan.edits.length == 1 ? '' : 's'} across '
              '${plan.references.length} reference'
              '${plan.references.length == 1 ? '' : 's'}';
    final originalSignature = seedPlan == null
        ? ''
        : '${seedPlan.originalName}'
              '(${seedPlan.originalParameters.map((item) => item.name).join(', ')})';
    final nextSignature = plan == null
        ? ''
        : '${plan.newName}'
              '(${plan.newParameters.map((item) => item.name).join(', ')})';

    return Material(
      key: const ValueKey('source-change-signature-panel'),
      color: const Color(0xFFF4F5FB),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Change Signature',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('source-change-signature-name-input'),
              focusNode: _changeSignatureNameFocusNode,
              controller: _changeSignatureNameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: 'Function name',
                helperText: plan == null || plan.hasConflicts
                    ? null
                    : helperText,
                errorText: plan == null || plan.hasConflicts
                    ? helperText
                    : null,
              ),
              onChanged: (_) {
                setState(() {
                  _changeSignatureError = null;
                });
              },
              onSubmitted: (_) {
                _changeSignatureParametersFocusNode.requestFocus();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('source-change-signature-parameters-input'),
              focusNode: _changeSignatureParametersFocusNode,
              controller: _changeSignatureParametersController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'Parameters',
                helperText:
                    'Rename in place, reorder, or remove existing names.',
              ),
              onChanged: (_) {
                setState(() {
                  _changeSignatureError = null;
                });
              },
              onSubmitted: (_) => _applyChangeSignature(),
            ),
            if (plan != null && !plan.hasConflicts) ...[
              const SizedBox(height: 8),
              Text(
                'Change `$originalSignature` to `$nextSignature`',
                key: const ValueKey('source-change-signature-preview'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineActionChip(
                  key: const ValueKey('source-change-signature-apply'),
                  icon: Icons.check_rounded,
                  label: 'Change',
                  onTap: _applyChangeSignature,
                ),
                _InlineActionChip(
                  key: const ValueKey('source-change-signature-cancel'),
                  icon: Icons.close_rounded,
                  label: 'Cancel',
                  onTap: _closeChangeSignaturePanel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsagesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final definition = widget.controller.definitionAtSelection;
    final references = widget.controller.referencesAtSelection;
    return Material(
      key: const ValueKey('source-usages-panel'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_search_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    definition == null
                        ? 'Find Usages'
                        : 'Find Usages: ${definition.symbol.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-usages-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeUsagesPanel,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${references.length} current-file usage'
              '${references.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < references.length; index += 1) ...[
              _UsageResultTile(
                key: ValueKey('source-usage-$index'),
                reference: references[index],
                selected: _isRangeSelected(references[index].range),
                location: _formatUsageLocation(references[index]),
                preview: _usageLinePreview(references[index]),
                onTap: () =>
                    widget.controller.selectReference(references[index]),
              ),
              if (index < references.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSafeDeletePanel(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.controller.safeDeletePlanAtSelection;
    final conflicts = plan?.conflicts ?? const <SafeDeleteConflict>[];
    return Material(
      key: const ValueKey('source-safe-delete-panel'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.delete_sweep_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan == null
                        ? 'Safe Delete'
                        : 'Safe Delete: ${plan.target.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-safe-delete-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeSafeDeletePanel,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (plan == null)
              Text(
                'No symbol target at the current caret.',
                style: theme.textTheme.bodySmall,
              )
            else if (conflicts.isNotEmpty) ...[
              Text(
                '${conflicts.length} blocker'
                '${conflicts.length == 1 ? '' : 's'} found',
                key: const ValueKey('source-safe-delete-blockers'),
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < conflicts.length; index += 1) ...[
                _SafeDeleteConflictTile(
                  key: ValueKey('source-safe-delete-conflict-$index'),
                  conflict: conflicts[index],
                  location: _formatUsageLocationForRange(
                    conflicts[index].range,
                  ),
                  preview: _linePreviewForRange(conflicts[index].range),
                  onTap: () => widget.controller.selectRange(
                    baseOffset: conflicts[index].range.start,
                    extentOffset: conflicts[index].range.end,
                  ),
                ),
                if (index < conflicts.length - 1) const SizedBox(height: 6),
              ],
            ] else ...[
              Text(
                'Delete declaration with ${plan.edits.length} edit'
                '${plan.edits.length == 1 ? '' : 's'}',
                key: const ValueKey('source-safe-delete-preview'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _InlineActionChip(
                key: const ValueKey('source-safe-delete-apply'),
                icon: Icons.check_rounded,
                label: 'Delete safely',
                onTap: _applySafeDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineVariablePanel(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.controller.inlineVariablePlanAtSelection;
    final conflicts = plan?.conflicts ?? const <InlineVariableConflict>[];
    return Material(
      key: const ValueKey('source-inline-variable-panel'),
      color: const Color(0xFFF0F7F4),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.call_merge_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan == null
                        ? 'Inline Variable'
                        : 'Inline Variable: ${plan.target.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-inline-variable-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeInlineVariablePanel,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (plan == null)
              Text(
                'No variable target at the current caret.',
                style: theme.textTheme.bodySmall,
              )
            else if (conflicts.isNotEmpty) ...[
              Text(
                '${conflicts.length} blocker'
                '${conflicts.length == 1 ? '' : 's'} found',
                key: const ValueKey('source-inline-variable-blockers'),
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < conflicts.length; index += 1) ...[
                _InlineVariableConflictTile(
                  key: ValueKey('source-inline-variable-conflict-$index'),
                  conflict: conflicts[index],
                  location: _formatUsageLocationForRange(
                    conflicts[index].range,
                  ),
                  preview: _linePreviewForRange(conflicts[index].range),
                  onTap: () => widget.controller.selectRange(
                    baseOffset: conflicts[index].range.start,
                    extentOffset: conflicts[index].range.end,
                  ),
                ),
                if (index < conflicts.length - 1) const SizedBox(height: 6),
              ],
            ] else ...[
              Text(
                'Replace ${plan.references.length} usage'
                '${plan.references.length == 1 ? '' : 's'} with '
                '` ${plan.initializerText} ` and delete the declaration',
                key: const ValueKey('source-inline-variable-preview'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _InlineActionChip(
                key: const ValueKey('source-inline-variable-apply'),
                icon: Icons.check_rounded,
                label: 'Inline all',
                onTap: _applyInlineVariable,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickDocumentationPanel(BuildContext context) {
    final theme = Theme.of(context);
    final completionItem = _quickDocumentationForCompletion
        ? _selectedCompletionItem()
        : null;
    final hover = widget.hover;
    final token = widget.activeToken;
    final definition = widget.controller.definitionAtSelection;
    final references = widget.controller.referencesAtSelection;
    final title = completionItem != null
        ? 'Quick Documentation: ${completionItem.label}'
        : definition == null
        ? token == null
              ? 'Quick Documentation'
              : 'Quick Documentation: ${token.lexeme}'
        : 'Quick Documentation: ${definition.symbol.name}';
    final body = completionItem == null
        ? hover?.markdown ?? 'No documentation payload at the caret.'
        : completionItem.documentation.isNotEmpty
        ? completionItem.documentation
        : completionItem.detail.isEmpty
        ? '${completionItem.kind.name} completion'
        : completionItem.detail;

    return Material(
      key: const ValueKey('source-quick-doc-panel'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.article_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-quick-doc-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeQuickDocumentation,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              key: const ValueKey('source-quick-doc-body'),
              style: theme.textTheme.bodySmall,
            ),
            if (completionItem != null) ...[
              const SizedBox(height: 8),
              Text(
                'Completion ${completionItem.kind.name} · '
                'insert ${_formatPreviewText(completionItem.insertText)}',
                key: const ValueKey('source-quick-doc-completion-insert'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (completionItem == null && token != null) ...[
              const SizedBox(height: 8),
              Text(
                'Token ${token.kind.name} · ${_formatRange(token.range)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (completionItem == null && definition != null) ...[
              const SizedBox(height: 8),
              Text(
                'Definition ${_formatUsageLocationForRange(definition.symbol.nameRange)} '
                '· ${definition.symbol.kind.name}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${references.length} current-file usage'
                '${references.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InlineActionChip(
                    key: const ValueKey('source-quick-doc-definition'),
                    icon: Icons.subdirectory_arrow_left_rounded,
                    label: 'Go to definition',
                    onTap: widget.controller.selectDefinitionAtSelection,
                  ),
                  _InlineActionChip(
                    key: const ValueKey('source-quick-doc-usages'),
                    icon: Icons.manage_search_rounded,
                    label: 'Find usages',
                    onTap: _openUsagesPanel,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionLookupPanel(BuildContext context) {
    final theme = Theme.of(context);
    final completions = widget.completions;
    final selectedIndex = completions.isEmpty
        ? -1
        : _completionLookupIndex.clamp(0, completions.length - 1).toInt();
    final selectedCompletion = selectedIndex < 0
        ? null
        : completions[selectedIndex];

    return Material(
      key: const ValueKey('source-completion-lookup'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Code Completion',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-completion-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeCompletionLookup,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (completions.isEmpty)
              Text(
                'No completion items at the current caret.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${completions.length} current-file suggestion'
                '${completions.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < completions.length; index += 1) ...[
                _CompletionLookupTile(
                  key: ValueKey('source-completion-item-$index'),
                  item: completions[index],
                  selected: index == selectedIndex,
                  onTap: () => _applyCompletionFromLookup(completions[index]),
                ),
                if (index < completions.length - 1) const SizedBox(height: 6),
              ],
              if (selectedCompletion != null) ...[
                const SizedBox(height: 10),
                _buildCompletionPreviewPanel(context, selectedCompletion),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionPreviewPanel(
    BuildContext context,
    CompletionItem item,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('source-completion-preview'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8D0C2)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            key: const ValueKey('source-completion-preview-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.detail.isEmpty ? '${item.kind.name} completion' : item.detail,
            key: const ValueKey('source-completion-preview-detail'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Insert ${_formatPreviewText(item.insertText)}',
            key: const ValueKey('source-completion-preview-insert'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _InlineActionChip(
            key: const ValueKey('source-completion-preview-doc'),
            icon: Icons.article_rounded,
            label: 'Documentation',
            onTap: _openCompletionQuickDocumentation,
          ),
        ],
      ),
    );
  }

  Widget _buildSurroundLookupPanel(BuildContext context) {
    final theme = Theme.of(context);
    final templates = widget.controller.surroundTemplatesAtSelection;
    final selectedIndex = templates.isEmpty
        ? -1
        : _surroundLookupIndex.clamp(0, templates.length - 1).toInt();

    return Material(
      key: const ValueKey('source-surround-lookup'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.data_object_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Surround With',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-surround-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeSurroundLookup,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (templates.isEmpty)
              Text(
                'No surround templates at the current selection.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${templates.length} Styio surround template'
                '${templates.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < templates.length; index += 1) ...[
                _SurroundTemplateTile(
                  key: ValueKey('source-surround-template-$index'),
                  template: templates[index],
                  selected: index == selectedIndex,
                  onTap: () =>
                      _applySurroundTemplateFromLookup(templates[index]),
                ),
                if (index < templates.length - 1) const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParameterInfoPanel(BuildContext context) {
    final theme = Theme.of(context);
    final parameterInfo = widget.controller.parameterInfoAtSelection;
    final activeParameter = parameterInfo?.activeParameter;

    return Material(
      key: const ValueKey('source-parameter-info-panel'),
      color: const Color(0xFFFDF8EE),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.functions_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    parameterInfo == null
                        ? 'Parameter Info'
                        : 'Parameter Info: ${parameterInfo.callableName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InlineActionChip(
                  key: const ValueKey('source-parameter-info-close'),
                  icon: Icons.close_rounded,
                  label: 'Close',
                  onTap: _closeParameterInfo,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (parameterInfo == null)
              Text(
                'No parameter info at the current caret.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                parameterInfo.signature,
                style: theme.textTheme.bodySmall!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (parameterInfo.documentation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  parameterInfo.documentation,
                  key: const ValueKey('source-parameter-info-doc'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                activeParameter == null
                    ? 'No active parameter'
                    : 'Argument ${parameterInfo.activeParameterIndex + 1} of '
                          '${parameterInfo.parameters.length}: '
                          '${activeParameter.displayText}',
                style: theme.textTheme.bodySmall,
              ),
              if (activeParameter?.documentation.isNotEmpty ?? false) ...[
                const SizedBox(height: 6),
                Text(
                  activeParameter!.documentation,
                  key: const ValueKey('source-parameter-info-active-doc'),
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              for (
                var index = 0;
                index < parameterInfo.parameters.length;
                index += 1
              ) ...[
                _ParameterInfoParameterTile(
                  key: ValueKey('source-parameter-info-param-$index'),
                  parameter: parameterInfo.parameters[index],
                  active: index == parameterInfo.activeParameterIndex,
                ),
                if (index < parameterInfo.parameters.length - 1)
                  const SizedBox(height: 6),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatUsageLocation(ReferenceSpan reference) {
    return _formatUsageLocationForRange(reference.range);
  }

  String _formatUsageLocationForRange(SourceRange range) {
    final position = widget.document.positionForOffset(range.start);
    return '${position.line + 1}:${position.column + 1}';
  }

  String _formatRange(SourceRange range) {
    return '${range.start}-${range.end}';
  }

  String _usageLinePreview(ReferenceSpan reference) {
    return _linePreviewForRange(reference.range);
  }

  String _linePreviewForRange(SourceRange range) {
    final position = widget.document.positionForOffset(range.start);
    if (position.line < 0 || position.line >= widget.document.lines.length) {
      return '';
    }
    return widget.document.lines[position.line].trim();
  }

  bool _isRangeSelected(SourceRange range) {
    final selection = widget.selection;
    if (selection.isCollapsed) {
      return range.contains(selection.end) || range.end == selection.end;
    }
    final selectionRange = SourceRange(
      start: selection.start,
      end: selection.end,
    );
    return range.intersects(selectionRange);
  }
}

class _UsageResultTile extends StatelessWidget {
  const _UsageResultTile({
    super.key,
    required this.reference,
    required this.selected,
    required this.location,
    required this.preview,
    required this.onTap,
  });

  final ReferenceSpan reference;
  final bool selected;
  final String location;
  final String preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accessLabel = _referenceAccessLabel(reference);
    return Material(
      color: selected ? const Color(0xFFE6E0F5) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _referenceAccessIcon(reference),
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$accessLabel · ${reference.kind.name} · $location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafeDeleteConflictTile extends StatelessWidget {
  const _SafeDeleteConflictTile({
    super.key,
    required this.conflict,
    required this.location,
    required this.preview,
    required this.onTap,
  });

  final SafeDeleteConflict conflict;
  final String location;
  final String preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${conflict.message} · $location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineVariableConflictTile extends StatelessWidget {
  const _InlineVariableConflictTile({
    super.key,
    required this.conflict,
    required this.location,
    required this.preview,
    required this.onTap,
  });

  final InlineVariableConflict conflict;
  final String location;
  final String preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${conflict.message} · $location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _referenceAccessLabel(ReferenceSpan reference) {
  if (reference.isDeclaration) {
    return 'declaration';
  }
  return switch (reference.access) {
    ReferenceAccess.declaration => 'declaration',
    ReferenceAccess.read => 'read',
    ReferenceAccess.write => 'write',
  };
}

IconData _referenceAccessIcon(ReferenceSpan reference) {
  if (reference.isDeclaration) {
    return Icons.radio_button_checked_rounded;
  }
  return switch (reference.access) {
    ReferenceAccess.declaration => Icons.radio_button_checked_rounded,
    ReferenceAccess.read => Icons.radio_button_unchecked_rounded,
    ReferenceAccess.write => Icons.output_rounded,
  };
}

class _QuickFixLookupTile extends StatelessWidget {
  const _QuickFixLookupTile({
    super.key,
    required this.quickFix,
    required this.selected,
    required this.onTap,
  });

  final DiagnosticQuickFix quickFix;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? const Color(0xFFE6E0F5) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.keyboard_return_rounded
                    : Icons.tips_and_updates_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quickFix.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (quickFix.detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        quickFix.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SymbolLookupTile extends StatelessWidget {
  const _SymbolLookupTile({
    super.key,
    required this.symbol,
    required this.selected,
    required this.location,
    required this.onTap,
  });

  final DocumentSymbol symbol;
  final bool selected;
  final String location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? const Color(0xFFE6E0F5) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.keyboard_return_rounded
                    : _symbolLookupIcon(symbol.kind),
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${symbol.name} · ${symbol.kind.name} · $location',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (symbol.detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        symbol.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _symbolLookupIcon(SymbolKind kind) {
  switch (kind) {
    case SymbolKind.function:
      return Icons.functions_rounded;
    case SymbolKind.pipeline:
      return Icons.account_tree_rounded;
    case SymbolKind.state:
      return Icons.flag_rounded;
    case SymbolKind.resource:
      return Icons.storage_rounded;
    case SymbolKind.variable:
      return Icons.label_rounded;
    case SymbolKind.parameter:
      return Icons.input_rounded;
    case SymbolKind.task:
      return Icons.task_alt_rounded;
  }
}

class _CompletionLookupTile extends StatelessWidget {
  const _CompletionLookupTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CompletionItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? const Color(0xFFE6E0F5) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.keyboard_return_rounded
                    : Icons.auto_awesome_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.label} · ${item.kind.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (item.detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurroundTemplateTile extends StatelessWidget {
  const _SurroundTemplateTile({
    super.key,
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final SurroundTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? const Color(0xFFE6E0F5) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.keyboard_return_rounded
                    : Icons.data_object_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (template.detail.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        template.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParameterInfoParameterTile extends StatelessWidget {
  const _ParameterInfoParameterTile({
    super.key,
    required this.parameter,
    required this.active,
  });

  final ParameterInfoParameter parameter;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE6E0F5) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Icon(
            active ? Icons.chevron_right_rounded : Icons.input_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parameter.displayText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightedLineRow extends StatelessWidget {
  const _HighlightedLineRow({
    super.key,
    required this.document,
    required this.selection,
    required this.analysis,
    required this.activeReferences,
    required this.activeTokenRange,
    required this.lineIndex,
    required this.lineStarts,
    required this.renderPlan,
    required this.semanticThemeBinding,
    required this.onTapDown,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final DocumentState document;
  final SelectionState selection;
  final StyioDocumentAnalysis analysis;
  final List<ReferenceSpan> activeReferences;
  final SourceRange? activeTokenRange;
  final int lineIndex;
  final List<int> lineStarts;
  final EditorRenderPlan renderPlan;
  final EditorSemanticThemeBinding semanticThemeBinding;
  final ValueChanged<TapDownDetails> onTapDown;
  final ValueChanged<DragStartDetails> onPanStart;
  final ValueChanged<DragUpdateDetails> onPanUpdate;
  final ValueChanged<DragEndDetails> onPanEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineText = document.lines[lineIndex];
    final lineStart = lineStarts[lineIndex];
    final lineEnd = lineStart + lineText.length;
    final lineRange = SourceRange(start: lineStart, end: lineEnd);
    final caretOnLine =
        selection.isCollapsed &&
        selection.end >= lineStart &&
        selection.end <= lineEnd;
    final lineDiagnostics = analysis.diagnostics
        .where((diagnostic) => diagnostic.range.intersects(lineRange))
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: onTapDown,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: caretOnLine ? const Color(0xFFF0E8DA) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    '${lineIndex + 1}'.padLeft(2, '0'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Container(
                  width: 8,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1, right: 12),
                  decoration: BoxDecoration(
                    color: _diagnosticStripeColor(context, lineDiagnostics),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: _buildLineSpans(
                        context,
                        document.text,
                        lineRange,
                        analysis,
                        activeReferences: activeReferences,
                        activeTokenRange: activeTokenRange,
                        selection: selection,
                        renderPlan: renderPlan,
                        semanticThemeBinding: semanticThemeBinding,
                      ),
                    ),
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineLanguageFeedback extends StatelessWidget {
  const _InlineLanguageFeedback({
    super.key,
    required this.controller,
    required this.viewportProfile,
    required this.diagnostics,
    required this.hover,
    required this.completions,
    required this.formattingEdits,
    required this.activeToken,
    required this.activeSemanticKind,
  });

  final EditorSessionController controller;
  final ViewportProfile viewportProfile;
  final List<Diagnostic> diagnostics;
  final HoverPayload? hover;
  final List<CompletionItem> completions;
  final List<FormattingEdit> formattingEdits;
  final TokenSpan? activeToken;
  final SemanticKind? activeSemanticKind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compactCompletions = completions.take(3).toList(growable: false);
    final quickFixes = controller.quickFixesForDiagnostics(diagnostics);
    const fallbackMessage =
        'Caret context ready. Move across tokens to inspect hover and completion results.';

    return Padding(
      padding: const EdgeInsets.only(left: 68, right: 8, bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5EFE4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        padding: const EdgeInsets.all(12),
        child: viewportProfile.isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InlineFeedbackHeader(
                    diagnostics: diagnostics,
                    hover: hover,
                    completions: compactCompletions,
                    formattingEdits: formattingEdits,
                    quickFixes: quickFixes,
                    activeToken: activeToken,
                  ),
                  if (activeToken != null) ...[
                    Text(
                      'Token `${activeToken!.lexeme}` · ${activeToken!.kind.name}'
                      '${activeSemanticKind != null ? ' · ${activeSemanticKind!.name}' : ''}'
                      ' · ${activeToken!.range.start}-${activeToken!.range.end}',
                      key: const ValueKey('active-token-context'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (diagnostics.isNotEmpty) ...[
                    Text(
                      diagnostics.first.message,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (hover != null) ...[
                    if (diagnostics.isNotEmpty) const SizedBox(height: 10),
                    Text(hover!.markdown, style: theme.textTheme.bodySmall),
                  ],
                  if (compactCompletions.isNotEmpty ||
                      formattingEdits.isNotEmpty ||
                      quickFixes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var index = 0;
                          index < quickFixes.length;
                          index += 1
                        )
                          _InlineActionChip(
                            key: ValueKey('inline-diagnostic-fix-$index'),
                            icon: Icons.build_circle_rounded,
                            label: quickFixes[index].label,
                            onTap: () => controller.applyDiagnosticQuickFix(
                              quickFixes[index],
                            ),
                          ),
                        for (
                          var index = 0;
                          index < compactCompletions.length;
                          index += 1
                        )
                          _InlineActionChip(
                            key: ValueKey(
                              'inline-completion-action-$index-${compactCompletions[index].label}',
                            ),
                            icon: Icons.auto_awesome_rounded,
                            label: compactCompletions[index].label,
                            onTap: () => controller.applyCompletionItem(
                              compactCompletions[index],
                            ),
                          ),
                        if (formattingEdits.isNotEmpty)
                          _InlineActionChip(
                            key: const ValueKey('inline-format-action'),
                            icon: Icons.auto_fix_high_rounded,
                            label: 'Apply format',
                            onTap: () => controller.applyFormattingEdits(
                              formattingEdits,
                            ),
                          ),
                      ],
                    ),
                  ] else if (diagnostics.isEmpty && hover == null) ...[
                    const SizedBox(height: 10),
                    Text(fallbackMessage, style: theme.textTheme.bodySmall),
                  ],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _InlineFeedbackHeader(
                      diagnostics: diagnostics,
                      hover: hover,
                      completions: compactCompletions,
                      formattingEdits: formattingEdits,
                      quickFixes: quickFixes,
                      activeToken: activeToken,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (activeToken != null)
                          Text(
                            'Token `${activeToken!.lexeme}` · ${activeToken!.kind.name}'
                            '${activeSemanticKind != null ? ' · ${activeSemanticKind!.name}' : ''}'
                            ' · ${activeToken!.range.start}-${activeToken!.range.end}',
                            key: const ValueKey('active-token-context'),
                            style: theme.textTheme.bodySmall,
                          ),
                        if (activeToken != null &&
                            (diagnostics.isNotEmpty ||
                                hover != null ||
                                compactCompletions.isNotEmpty ||
                                formattingEdits.isNotEmpty ||
                                quickFixes.isNotEmpty))
                          const SizedBox(height: 10),
                        if (diagnostics.isNotEmpty)
                          Text(
                            diagnostics.first.message,
                            style: theme.textTheme.bodySmall,
                          )
                        else if (hover != null)
                          Text(
                            hover!.markdown,
                            style: theme.textTheme.bodySmall,
                          )
                        else if (compactCompletions.isEmpty &&
                            formattingEdits.isEmpty &&
                            quickFixes.isEmpty)
                          Text(
                            fallbackMessage,
                            style: theme.textTheme.bodySmall,
                          ),
                        if (compactCompletions.isNotEmpty ||
                            formattingEdits.isNotEmpty ||
                            quickFixes.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (
                                var index = 0;
                                index < quickFixes.length;
                                index += 1
                              )
                                _InlineActionChip(
                                  key: ValueKey('inline-diagnostic-fix-$index'),
                                  icon: Icons.build_circle_rounded,
                                  label: quickFixes[index].label,
                                  onTap: () =>
                                      controller.applyDiagnosticQuickFix(
                                        quickFixes[index],
                                      ),
                                ),
                              for (
                                var index = 0;
                                index < compactCompletions.length;
                                index += 1
                              )
                                _InlineActionChip(
                                  key: ValueKey(
                                    'inline-completion-action-$index-${compactCompletions[index].label}',
                                  ),
                                  icon: Icons.auto_awesome_rounded,
                                  label:
                                      '${compactCompletions[index].label} · ${compactCompletions[index].kind.name}',
                                  onTap: () => controller.applyCompletionItem(
                                    compactCompletions[index],
                                  ),
                                ),
                              if (formattingEdits.isNotEmpty)
                                _InlineActionChip(
                                  key: const ValueKey('inline-format-action'),
                                  icon: Icons.auto_fix_high_rounded,
                                  label: 'Apply format',
                                  onTap: () => controller.applyFormattingEdits(
                                    formattingEdits,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InlineFeedbackHeader extends StatelessWidget {
  const _InlineFeedbackHeader({
    required this.diagnostics,
    required this.hover,
    required this.completions,
    required this.formattingEdits,
    required this.quickFixes,
    required this.activeToken,
  });

  final List<Diagnostic> diagnostics;
  final HoverPayload? hover;
  final List<CompletionItem> completions;
  final List<FormattingEdit> formattingEdits;
  final List<DiagnosticQuickFix> quickFixes;
  final TokenSpan? activeToken;

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[];

    if (diagnostics.isNotEmpty) {
      pills.add(
        _InlineFeedbackBadge(
          label: diagnostics.first.severity.name,
          color: _severityColor(diagnostics.first.severity),
        ),
      );
    }

    if (hover != null) {
      pills.add(
        const _InlineFeedbackBadge(label: 'hover', color: Color(0xFF6A85B6)),
      );
    }

    if (completions.isNotEmpty) {
      pills.add(
        _InlineFeedbackBadge(
          label: '${completions.length} suggestions',
          color: const Color(0xFF6B7B3E),
        ),
      );
    }

    if (formattingEdits.isNotEmpty) {
      pills.add(
        _InlineFeedbackBadge(
          label: '${formattingEdits.length} format edit',
          color: const Color(0xFF8D6C3B),
        ),
      );
    }

    if (quickFixes.isNotEmpty) {
      pills.add(
        _InlineFeedbackBadge(
          label: '${quickFixes.length} quick fix',
          color: const Color(0xFF8A5A3B),
        ),
      );
    }

    if (activeToken != null) {
      pills.add(
        _InlineFeedbackBadge(
          label: 'token ${activeToken!.kind.name}',
          color: const Color(0xFF57676B),
        ),
      );
    }

    if (pills.isEmpty) {
      pills.add(
        const _InlineFeedbackBadge(
          label: 'active line',
          color: Color(0xFF7C736C),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }
}

class _InlineActionChip extends StatelessWidget {
  const _InlineActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: const Color(0xFFEDE6D9),
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineFeedbackBadge extends StatelessWidget {
  const _InlineFeedbackBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

enum _LanguageInspectorSection {
  diagnostics,
  blocks,
  inlays,
  symbols,
  resolve,
  token,
  hover,
  completions,
  formatting,
}

extension on _LanguageInspectorSection {
  String get label {
    switch (this) {
      case _LanguageInspectorSection.diagnostics:
        return 'Diagnostics';
      case _LanguageInspectorSection.blocks:
        return 'Blocks';
      case _LanguageInspectorSection.inlays:
        return 'Inlays';
      case _LanguageInspectorSection.symbols:
        return 'Symbols';
      case _LanguageInspectorSection.resolve:
        return 'Resolve';
      case _LanguageInspectorSection.token:
        return 'Token';
      case _LanguageInspectorSection.hover:
        return 'Hover';
      case _LanguageInspectorSection.completions:
        return 'Complete';
      case _LanguageInspectorSection.formatting:
        return 'Format';
    }
  }
}

class _LanguageServicePane extends StatefulWidget {
  const _LanguageServicePane({
    required this.controller,
    required this.viewportProfile,
    required this.analysis,
    required this.hover,
    required this.completions,
    required this.activeToken,
    required this.activeSemanticKind,
    required this.languageServiceStatus,
    required this.onRefreshLanguageService,
  });

  final EditorSessionController controller;
  final ViewportProfile viewportProfile;
  final StyioDocumentAnalysis analysis;
  final HoverPayload? hover;
  final List<CompletionItem> completions;
  final TokenSpan? activeToken;
  final SemanticKind? activeSemanticKind;
  final LanguageServiceStatusSurface? languageServiceStatus;
  final VoidCallback? onRefreshLanguageService;

  @override
  State<_LanguageServicePane> createState() => _LanguageServicePaneState();
}

class _LanguageServicePaneState extends State<_LanguageServicePane> {
  _LanguageInspectorSection _selectedSection =
      _LanguageInspectorSection.diagnostics;
  final TextEditingController _renameController = TextEditingController();
  String? _renameSeedKey;

  @override
  void dispose() {
    _renameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    final showServiceStatusCard = widget.languageServiceStatus != null;

    if (widget.viewportProfile.isMobile) {
      return KeyedSubtree(
        key: const ValueKey('language-pane-mobile'),
        child: ListView(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CapabilityPill(label: 'token ${analysis.tokenCount}'),
                _CapabilityPill(label: 'diag ${analysis.diagnosticCount}'),
                _CapabilityPill(
                  label: 'blocks ${analysis.semanticBlocks.length}',
                ),
                _CapabilityPill(label: 'symbols ${analysis.symbolCount}'),
                if (widget.languageServiceStatus != null)
                  _CapabilityPill(
                    label:
                        'service ${widget.languageServiceStatus!.severity.name}',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (
                    var index = 0;
                    index < _LanguageInspectorSection.values.length;
                    index += 1
                  ) ...[
                    if (index > 0) const SizedBox(width: 8),
                    _InspectorTabChip(
                      label: _LanguageInspectorSection.values[index].label,
                      active:
                          _selectedSection ==
                          _LanguageInspectorSection.values[index],
                      onTap: () {
                        setState(() {
                          _selectedSection =
                              _LanguageInspectorSection.values[index];
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _InspectorCard(
              key: ValueKey('language-mobile-section-${_selectedSection.name}'),
              title: _selectedSection.label,
              child: _buildSectionContent(context, section: _selectedSection),
            ),
          ],
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('language-pane-desktop'),
      child: ListView(
        children: [
          if (showServiceStatusCard) ...[
            _InspectorCard(
              key: const ValueKey('language-service-status-card'),
              title: 'StyioService Status',
              child: _buildServiceStatusContent(context),
            ),
            const SizedBox(height: 12),
          ],
          _InspectorCard(
            title: 'Language Layers',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CapabilityPill(label: 'token ${analysis.tokenCount}'),
                _CapabilityPill(label: 'semantic ${analysis.semanticCount}'),
                _CapabilityPill(label: 'symbols ${analysis.symbolCount}'),
                _CapabilityPill(label: 'refs ${analysis.referenceCount}'),
                _CapabilityPill(label: 'diag ${analysis.diagnosticCount}'),
                _CapabilityPill(
                  label: 'format ${analysis.formattingEdits.length}',
                ),
                _CapabilityPill(
                  label: 'blocks ${analysis.semanticBlocks.length}',
                ),
                _CapabilityPill(label: 'inlays ${analysis.inlayHintCount}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-diagnostics'),
            title: 'Diagnostics',
            child: _buildDiagnosticsContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-blocks'),
            title: 'Semantic Blocks',
            child: _buildSemanticBlocksContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-inlays'),
            title: 'Inlay Hints',
            child: _buildInlayHintsContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-symbols'),
            title: 'Document Symbols',
            child: _buildDocumentSymbolsContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-resolve'),
            title: 'Resolve @ Caret',
            child: _buildResolveContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-token'),
            title: 'Token @ Caret',
            child: _buildTokenContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-hover'),
            title: 'Hover @ Caret',
            child: _buildHoverContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-completions'),
            title: 'Completion Preview',
            child: _buildCompletionContent(context),
          ),
          const SizedBox(height: 12),
          _InspectorCard(
            key: const ValueKey('language-desktop-section-formatting'),
            title: 'Formatting Contract',
            child: _buildFormattingContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent(
    BuildContext context, {
    required _LanguageInspectorSection section,
  }) {
    switch (section) {
      case _LanguageInspectorSection.diagnostics:
        return _buildDiagnosticsContent(context);
      case _LanguageInspectorSection.blocks:
        return _buildSemanticBlocksContent(context);
      case _LanguageInspectorSection.inlays:
        return _buildInlayHintsContent(context);
      case _LanguageInspectorSection.symbols:
        return _buildDocumentSymbolsContent(context);
      case _LanguageInspectorSection.resolve:
        return _buildResolveContent(context);
      case _LanguageInspectorSection.token:
        return _buildTokenContent(context);
      case _LanguageInspectorSection.hover:
        return _buildHoverContent(context);
      case _LanguageInspectorSection.completions:
        return _buildCompletionContent(context);
      case _LanguageInspectorSection.formatting:
        return _buildFormattingContent(context);
    }
  }

  Widget _buildServiceStatusContent(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.languageServiceStatus!;
    final primaryStates = status.primaryCapabilityStates.entries
        .take(4)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(status.message, style: theme.textTheme.bodySmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CapabilityPill(label: 'runtime ${status.runtimeState}'),
            _CapabilityPill(label: 'severity ${status.severity.name}'),
            _CapabilityPill(label: 'health ${status.capabilityHealth}'),
            _CapabilityPill(label: 'usable ${status.usableCapabilityCount}'),
            _CapabilityPill(label: 'fresh ${status.freshCapabilityCount}'),
            _CapabilityPill(label: 'missing ${status.missingCapabilityCount}'),
            _CapabilityPill(label: 'blocked ${status.blockedCapabilityCount}'),
            if (status.cacheLookupCount > 0) ...[
              _CapabilityPill(
                label: 'cache lookups ${status.cacheLookupCount}',
              ),
              _CapabilityPill(label: 'cache hits ${status.cacheLookupHits}'),
              _CapabilityPill(
                label: 'cache misses ${status.cacheLookupMisses}',
              ),
            ],
            for (final entry in primaryStates)
              _CapabilityPill(label: '${entry.key} ${entry.value}'),
          ],
        ),
        if (status.refreshRecommended) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('language-service-refresh-action'),
            onPressed: widget.onRefreshLanguageService,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Refresh language service'),
          ),
        ],
      ],
    );
  }

  Widget _buildDiagnosticsContent(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.analysis.diagnostics.isEmpty) {
      return Text(
        'No diagnostics from the linter layer.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      key: const ValueKey('language-problems-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var index = 0;
          index < widget.analysis.diagnostics.length;
          index += 1
        ) ...[
          Builder(
            builder: (context) {
              final diagnostic = widget.analysis.diagnostics[index];
              final quickFixes = widget.controller.quickFixesForDiagnostics([
                diagnostic,
              ]);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _isRangeSelected(diagnostic.range)
                      ? const Color(0xFFE6E0F5)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    key: ValueKey('language-diagnostic-$index'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => widget.controller.selectDiagnostic(diagnostic),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _diagnosticIcon(diagnostic.severity),
                                size: 16,
                                color: _diagnosticColor(diagnostic.severity),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '[${diagnostic.severity.name}] '
                                  '${diagnostic.message} · '
                                  '${_formatRange(diagnostic.range)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          if (quickFixes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (
                                  var fixIndex = 0;
                                  fixIndex < quickFixes.length;
                                  fixIndex += 1
                                )
                                  _InlineActionChip(
                                    key: ValueKey(
                                      'language-diagnostic-fix-$index-$fixIndex',
                                    ),
                                    icon: Icons.build_circle_rounded,
                                    label: quickFixes[fixIndex].label,
                                    onTap: () => widget.controller
                                        .applyDiagnosticQuickFix(
                                          quickFixes[fixIndex],
                                        ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  IconData _diagnosticIcon(DiagnosticSeverity severity) {
    switch (severity) {
      case DiagnosticSeverity.error:
        return Icons.error_rounded;
      case DiagnosticSeverity.warning:
        return Icons.warning_rounded;
      case DiagnosticSeverity.hint:
        return Icons.info_rounded;
    }
  }

  Color _diagnosticColor(DiagnosticSeverity severity) {
    switch (severity) {
      case DiagnosticSeverity.error:
        return const Color(0xFFB3261E);
      case DiagnosticSeverity.warning:
        return const Color(0xFF8A5A00);
      case DiagnosticSeverity.hint:
        return const Color(0xFF496184);
    }
  }

  Widget _buildSemanticBlocksContent(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.analysis.semanticBlocks.isEmpty) {
      return Text(
        'No semantic block surfaces resolved yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.analysis.semanticBlocks
          .take(4)
          .map(
            (block) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${block.label} · ${_formatRange(block.range)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildInlayHintsContent(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.analysis.inlayHints.isEmpty) {
      return Text(
        'No inlay hints for the current document.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      key: const ValueKey('language-inlay-hints-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var index = 0;
          index < widget.analysis.inlayHints.length;
          index += 1
        )
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.analysis.inlayHints[index].label} · '
              '${widget.analysis.inlayHints[index].kind.name} · '
              '${_formatRange(widget.analysis.inlayHints[index].range)}',
              key: ValueKey('language-inlay-hint-$index'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildDocumentSymbolsContent(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.analysis.documentSymbols.isEmpty) {
      return Text(
        'No document symbols resolved yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      key: const ValueKey('language-document-symbols-tree'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.analysis.documentSymbols
          .map(
            (symbol) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: _isSymbolSelected(symbol)
                    ? const Color(0xFFE6E0F5)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  key: ValueKey(
                    'language-document-symbol-${symbol.kind.name}-'
                    '${symbol.name}-${symbol.nameRange.start}',
                  ),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.controller.selectDocumentSymbol(symbol),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _symbolIcon(symbol.kind),
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${symbol.name} · ${symbol.kind.name} · '
                            '${_formatRange(symbol.nameRange)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  bool _isSymbolSelected(DocumentSymbol symbol) {
    return _isRangeSelected(symbol.nameRange);
  }

  bool _isRangeSelected(SourceRange range) {
    final selection = widget.controller.selection;
    if (selection.isCollapsed) {
      return range.contains(selection.end) || range.end == selection.end;
    }
    final selectionRange = SourceRange(
      start: selection.start,
      end: selection.end,
    );
    return range.intersects(selectionRange);
  }

  IconData _symbolIcon(SymbolKind kind) {
    switch (kind) {
      case SymbolKind.function:
        return Icons.functions_rounded;
      case SymbolKind.pipeline:
        return Icons.account_tree_rounded;
      case SymbolKind.state:
        return Icons.flag_rounded;
      case SymbolKind.resource:
        return Icons.storage_rounded;
      case SymbolKind.variable:
        return Icons.label_rounded;
      case SymbolKind.parameter:
        return Icons.input_rounded;
      case SymbolKind.task:
        return Icons.task_alt_rounded;
    }
  }

  Widget _buildResolveContent(BuildContext context) {
    final theme = Theme.of(context);
    final definition = widget.controller.definitionAtSelection;
    final references = widget.controller.referencesAtSelection;
    if (definition == null) {
      return Text(
        'No definition target at the current caret.',
        style: theme.textTheme.bodySmall,
      );
    }
    final renameSeedKey =
        '${definition.symbol.name}:${definition.symbol.nameRange.start}:'
        '${definition.symbol.nameRange.end}';
    if (_renameSeedKey != renameSeedKey) {
      _renameSeedKey = renameSeedKey;
      _renameController.text = '${definition.symbol.name}_next';
    }
    final renameText = _renameController.text.trim();
    final renamePreview = widget.controller.renamePlanAtSelection(renameText);

    return Column(
      key: const ValueKey('language-resolve-context'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${definition.symbol.name} · ${definition.symbol.kind.name}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Definition ${_formatRange(definition.symbol.nameRange)} · '
          'origin ${_formatRange(definition.originRange)}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _InlineActionChip(
          key: const ValueKey('language-go-to-definition'),
          icon: Icons.subdirectory_arrow_left_rounded,
          label: 'Go to definition',
          onTap: widget.controller.selectDefinitionAtSelection,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InlineActionChip(
              key: const ValueKey('language-previous-usage'),
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'Previous usage',
              onTap: widget.controller.selectPreviousReferenceAtSelection,
            ),
            _InlineActionChip(
              key: const ValueKey('language-next-usage'),
              icon: Icons.keyboard_arrow_down_rounded,
              label: 'Next usage',
              onTap: widget.controller.selectNextReferenceAtSelection,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${references.length} current-file usage'
          '${references.length == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('language-rename-input'),
          controller: _renameController,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            labelText: 'Rename',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (renamePreview != null && renamePreview.hasConflicts) ...[
          Text(
            _formatRenameConflict(renamePreview.conflicts.first),
            key: const ValueKey('language-rename-conflict'),
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ] else if (renamePreview != null) ...[
          Text(
            'Rename preview ${renamePreview.edits.length} edit'
            '${renamePreview.edits.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _InlineActionChip(
            key: const ValueKey('language-apply-rename'),
            icon: Icons.drive_file_rename_outline_rounded,
            label: 'Apply rename',
            onTap: () => widget.controller.applyRename(renameText),
          ),
        ],
        const SizedBox(height: 8),
        ...references
            .take(4)
            .map(
              (reference) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${_referenceAccessLabel(reference)} · '
                  '${_formatRange(reference.range)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
      ],
    );
  }

  String _formatRenameConflict(RenameConflict conflict) {
    final position = widget.controller.document.positionForOffset(
      conflict.range.start,
    );
    return '${conflict.message} Conflict at '
        '${position.line + 1}:${position.column + 1}.';
  }

  Widget _buildHoverContent(BuildContext context) {
    return Text(
      widget.hover?.markdown ?? 'No hover payload at the current caret.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _buildTokenContent(BuildContext context) {
    final theme = Theme.of(context);
    final token = widget.activeToken;
    if (token == null) {
      return Text(
        'No token resolved at the current caret.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      key: const ValueKey('language-token-context'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lexeme `${token.lexeme}`', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Kind ${token.kind.name}', style: theme.textTheme.bodySmall),
        if (widget.activeSemanticKind != null) ...[
          const SizedBox(height: 8),
          Text(
            'Semantic ${widget.activeSemanticKind!.name}',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Range ${_formatRange(token.range)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCompletionContent(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.completions.isEmpty) {
      return Text(
        'No completion items at the current caret.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.completions
          .take(4)
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item.label} · ${item.kind.name} · ${item.detail}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _InlineActionChip(
                    key: ValueKey('language-apply-completion-${item.label}'),
                    icon: Icons.auto_awesome_rounded,
                    label: 'Apply',
                    onTap: () => widget.controller.applyCompletionItem(item),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildFormattingContent(BuildContext context) {
    final theme = Theme.of(context);
    final edits = widget.analysis.formattingEdits;
    if (edits.isEmpty) {
      return Text(
        'Formatter returned no TextEdit patches.',
        style: theme.textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Formatter returns ${edits.length} TextEdit patch item(s), not direct document mutation.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ...edits
            .take(3)
            .map(
              (edit) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_formatRange(edit.range)} -> ${edit.newText.replaceAll('\n', r'\n')}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
        _InlineActionChip(
          key: const ValueKey('language-apply-formatting'),
          icon: Icons.auto_fix_high_rounded,
          label: 'Apply format edits',
          onTap: () => widget.controller.applyFormattingEdits(edits),
        ),
      ],
    );
  }

  String _formatRange(SourceRange range) {
    return '${range.start}-${range.end}';
  }
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InspectorTabChip extends StatelessWidget {
  const _InspectorTabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFE7DA) : const Color(0xFFF7F2E9),
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(label),
      ),
    );
  }
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEDE6D9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(label),
      ),
    );
  }
}

List<Widget> _buildPreviewChildren(
  BuildContext context, {
  required EditorSessionController controller,
  required ViewportProfile viewportProfile,
  required HoverPayload? hover,
  required List<CompletionItem> completions,
  required List<ReferenceSpan> activeReferences,
  required TokenSpan? activeToken,
  required SemanticKind? activeSemanticKind,
  required DocumentState document,
  required SelectionState selection,
  required StyioDocumentAnalysis analysis,
  required EditorRenderPlan renderPlan,
  required EditorSemanticThemeBinding semanticThemeBinding,
  required List<int> lineStarts,
  required List<_SemanticLineBlock> semanticBlocks,
  required int maxRenderedLineCount,
  required Set<String> collapsedSemanticBlockKeys,
  required ValueChanged<_SemanticLineBlock> onToggleSemanticBlock,
  required void Function(int lineIndex, TapDownDetails details) onTapLine,
  required void Function(int lineIndex, DragStartDetails details)
  onPanStartLine,
  required void Function(int lineIndex, DragUpdateDetails details)
  onPanUpdateLine,
  required ValueChanged<DragEndDetails> onPanEnd,
}) {
  final children = <Widget>[];
  final blockByStart = <int, _SemanticLineBlock>{
    for (final block in semanticBlocks) block.startLine: block,
  };
  final activeLineIndex = document
      .positionForOffset(selection.extentOffset)
      .line;
  final renderedLineCount = document.lines.length < maxRenderedLineCount
      ? document.lines.length
      : maxRenderedLineCount;
  final renderStartLine = _previewRenderStartLine(
    totalLineCount: document.lines.length,
    maxRenderedLineCount: maxRenderedLineCount,
    activeLineIndex: activeLineIndex,
  );
  final renderEndLine = renderStartLine + renderedLineCount;
  var lineIndex = renderStartLine;

  while (lineIndex < renderEndLine) {
    final block = blockByStart[lineIndex];
    if (block != null) {
      final collapsed = collapsedSemanticBlockKeys.contains(
        _semanticBlockKey(block),
      );
      final visibleLimitEnd = renderEndLine - 1;
      final visibleBlockEnd = collapsed
          ? block.startLine
          : block.endLine < visibleLimitEnd
          ? block.endLine
          : visibleLimitEnd;
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SemanticBlockCard(
            block: block,
            label: block.label,
            collapsed: collapsed,
            onToggle: () => onToggleSemanticBlock(block),
            child: Column(
              children: [
                for (
                  var blockLine = block.startLine;
                  blockLine <= visibleBlockEnd;
                  blockLine += 1
                )
                  ..._buildLineWithInlineFeedback(
                    context,
                    controller: controller,
                    viewportProfile: viewportProfile,
                    hover: hover,
                    completions: completions,
                    activeReferences: activeReferences,
                    activeToken: activeToken,
                    activeSemanticKind: activeSemanticKind,
                    document: document,
                    selection: selection,
                    analysis: analysis,
                    lineIndex: blockLine,
                    activeLineIndex: activeLineIndex,
                    lineStarts: lineStarts,
                    renderPlan: renderPlan,
                    semanticThemeBinding: semanticThemeBinding,
                    onTapLine: onTapLine,
                    onPanStartLine: onPanStartLine,
                    onPanUpdateLine: onPanUpdateLine,
                    onPanEnd: onPanEnd,
                  ),
                if (collapsed)
                  _CollapsedBlockSummary(
                    key: ValueKey('source-fold-summary-${block.startLine}'),
                    hiddenLineCount: block.endLine - block.startLine,
                  ),
              ],
            ),
          ),
        ),
      );
      lineIndex = block.endLine + 1;
      continue;
    }

    children.addAll(
      _buildLineWithInlineFeedback(
        context,
        controller: controller,
        viewportProfile: viewportProfile,
        hover: hover,
        completions: completions,
        activeReferences: activeReferences,
        activeToken: activeToken,
        activeSemanticKind: activeSemanticKind,
        document: document,
        selection: selection,
        analysis: analysis,
        lineIndex: lineIndex,
        activeLineIndex: activeLineIndex,
        lineStarts: lineStarts,
        renderPlan: renderPlan,
        semanticThemeBinding: semanticThemeBinding,
        onTapLine: onTapLine,
        onPanStartLine: onPanStartLine,
        onPanUpdateLine: onPanUpdateLine,
        onPanEnd: onPanEnd,
      ),
    );
    lineIndex += 1;
  }

  if (renderedLineCount < document.lines.length) {
    children.add(
      _LargeDocumentPreviewTruncationBanner(
        renderedLineCount: renderedLineCount,
        totalLineCount: document.lines.length,
        renderStartLine: renderStartLine,
        renderEndLine: renderEndLine,
        activeLineIndex: activeLineIndex,
      ),
    );
  }

  return children;
}

int _previewRenderStartLine({
  required int totalLineCount,
  required int maxRenderedLineCount,
  required int activeLineIndex,
}) {
  if (totalLineCount <= maxRenderedLineCount) {
    return 0;
  }
  final maxStartLine = totalLineCount - maxRenderedLineCount;
  var startLine = activeLineIndex - (maxRenderedLineCount ~/ 2);
  if (startLine < 0) {
    return 0;
  }
  if (startLine > maxStartLine) {
    return maxStartLine;
  }
  return startLine;
}

class _LargeDocumentPreviewTruncationBanner extends StatelessWidget {
  const _LargeDocumentPreviewTruncationBanner({
    required this.renderedLineCount,
    required this.totalLineCount,
    required this.renderStartLine,
    required this.renderEndLine,
    required this.activeLineIndex,
  });

  final int renderedLineCount;
  final int totalLineCount;
  final int renderStartLine;
  final int renderEndLine;
  final int activeLineIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('source-large-document-truncation-banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Large document preview: rendering lines ${renderStartLine + 1}-$renderEndLine of $totalLineCount.',
            style: theme.textTheme.bodySmall,
          ),
          if (activeLineIndex < renderStartLine ||
              activeLineIndex >= renderEndLine) ...[
            const SizedBox(height: 4),
            Text(
              'Current caret line ${activeLineIndex + 1} is outside the rendered preview window.',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

List<Widget> _buildLineWithInlineFeedback(
  BuildContext context, {
  required EditorSessionController controller,
  required ViewportProfile viewportProfile,
  required HoverPayload? hover,
  required List<CompletionItem> completions,
  required List<ReferenceSpan> activeReferences,
  required TokenSpan? activeToken,
  required SemanticKind? activeSemanticKind,
  required DocumentState document,
  required SelectionState selection,
  required StyioDocumentAnalysis analysis,
  required int lineIndex,
  required int activeLineIndex,
  required List<int> lineStarts,
  required EditorRenderPlan renderPlan,
  required EditorSemanticThemeBinding semanticThemeBinding,
  required void Function(int lineIndex, TapDownDetails details) onTapLine,
  required void Function(int lineIndex, DragStartDetails details)
  onPanStartLine,
  required void Function(int lineIndex, DragUpdateDetails details)
  onPanUpdateLine,
  required ValueChanged<DragEndDetails> onPanEnd,
}) {
  final widgets = <Widget>[
    _HighlightedLineRow(
      key: ValueKey('source-line-$lineIndex'),
      document: document,
      selection: selection,
      analysis: analysis,
      activeReferences: activeReferences,
      activeTokenRange: activeToken?.range,
      lineIndex: lineIndex,
      lineStarts: lineStarts,
      renderPlan: renderPlan,
      semanticThemeBinding: semanticThemeBinding,
      onTapDown: (details) => onTapLine(lineIndex, details),
      onPanStart: (details) => onPanStartLine(lineIndex, details),
      onPanUpdate: (details) => onPanUpdateLine(lineIndex, details),
      onPanEnd: onPanEnd,
    ),
  ];

  if (lineIndex != activeLineIndex) {
    return widgets;
  }

  final lineText = document.lines[lineIndex];
  final lineRange = SourceRange(
    start: lineStarts[lineIndex],
    end: lineStarts[lineIndex] + lineText.length,
  );
  final lineDiagnostics = analysis.diagnostics
      .where((diagnostic) => diagnostic.range.intersects(lineRange))
      .toList(growable: false);

  widgets.add(
    _InlineLanguageFeedback(
      key: ValueKey(
        'inline-language-feedback-${viewportProfile.label.toLowerCase()}',
      ),
      controller: controller,
      viewportProfile: viewportProfile,
      diagnostics: lineDiagnostics,
      hover: hover,
      completions: completions,
      formattingEdits: analysis.formattingEdits,
      activeToken: activeToken,
      activeSemanticKind: activeSemanticKind,
    ),
  );

  return widgets;
}

List<InlineSpan> _buildLineSpans(
  BuildContext context,
  String source,
  SourceRange lineRange,
  StyioDocumentAnalysis analysis, {
  required List<ReferenceSpan> activeReferences,
  required SourceRange? activeTokenRange,
  required SelectionState selection,
  required EditorRenderPlan renderPlan,
  required EditorSemanticThemeBinding semanticThemeBinding,
}) {
  final spans = <InlineSpan>[];
  final caretOffset = selection.isCollapsed ? selection.end : null;
  final selectionRange = selection.isCollapsed
      ? null
      : SourceRange(start: selection.start, end: selection.end);
  final lineTokens = analysis.tokenSpans
      .where((token) => token.range.intersects(lineRange))
      .toList(growable: false);
  final lineInlayHints =
      analysis.inlayHints
          .where(
            (hint) =>
                hint.position >= lineRange.start &&
                hint.position <= lineRange.end,
          )
          .toList(growable: false)
        ..sort((left, right) => left.position.compareTo(right.position));
  var inlayHintIndex = 0;

  void appendInlayHintsThrough(int boundary) {
    while (inlayHintIndex < lineInlayHints.length &&
        lineInlayHints[inlayHintIndex].position <= boundary) {
      final hint = lineInlayHints[inlayHintIndex];
      _appendCaretIfNeeded(
        spans,
        context,
        caretOffset: caretOffset,
        boundary: hint.position,
      );
      spans.add(_inlayHintSpan(hint));
      inlayHintIndex += 1;
    }
  }

  if (lineTokens.isEmpty) {
    _appendCaretIfNeeded(
      spans,
      context,
      caretOffset: caretOffset,
      boundary: lineRange.start,
    );
    spans.add(
      TextSpan(
        text: ' ',
        style: _textStyleForToken(
          context,
          tokenKind: TokenKind.whitespace,
          semanticKind: null,
          diagnosticSeverity: null,
          semanticThemeBinding: semanticThemeBinding,
        ),
      ),
    );
    if (lineRange.end != lineRange.start) {
      _appendCaretIfNeeded(
        spans,
        context,
        caretOffset: caretOffset,
        boundary: lineRange.end,
      );
    }
    return spans;
  }

  var cursor = lineRange.start;
  for (final token in lineTokens) {
    final start = token.range.start.clamp(lineRange.start, lineRange.end);
    final end = token.range.end.clamp(lineRange.start, lineRange.end);

    if (start > cursor) {
      final style = _textStyleForToken(
        context,
        tokenKind: TokenKind.whitespace,
        semanticKind: null,
        diagnosticSeverity: null,
        semanticThemeBinding: semanticThemeBinding,
      );
      _appendCaretIfNeeded(
        spans,
        context,
        caretOffset: caretOffset,
        boundary: cursor,
      );
      _appendCaretAwareText(
        spans,
        context,
        text: source.substring(cursor, start),
        start: cursor,
        style: style,
        caretOffset: caretOffset,
        selectionRange: selectionRange,
      );
    }

    if (end > start) {
      appendInlayHintsThrough(start);
      final tokenRange = SourceRange(start: start, end: end);
      _appendCaretIfNeeded(
        spans,
        context,
        caretOffset: caretOffset,
        boundary: start,
      );
      spans.addAll(
        _inlineSpansForToken(
          context,
          token: token,
          lineSlice: source.substring(start, end),
          segmentStart: start,
          caretOffset: caretOffset,
          selectionRange: selectionRange,
          semanticKind: _semanticKindForRange(
            analysis.semanticSpans,
            tokenRange,
          ),
          diagnosticSeverity: _diagnosticSeverityForRange(
            analysis.diagnostics,
            tokenRange,
          ),
          activeReference: _referenceForRange(activeReferences, tokenRange),
          activeToken:
              activeTokenRange != null &&
              _sameRange(activeTokenRange, tokenRange),
          semanticThemeBinding: semanticThemeBinding,
          enableGlyphSubstitution:
              renderPlan.activeLayers.contains(EditorRenderLayer.decoration) &&
              renderPlan.glyphSubstitutionEnabled &&
              !_selectionTouchesRange(selectionRange, caretOffset, tokenRange),
        ),
      );
      cursor = end;
    }
  }

  if (cursor < lineRange.end) {
    final style = _textStyleForToken(
      context,
      tokenKind: TokenKind.whitespace,
      semanticKind: null,
      diagnosticSeverity: null,
      semanticThemeBinding: semanticThemeBinding,
    );
    _appendCaretIfNeeded(
      spans,
      context,
      caretOffset: caretOffset,
      boundary: cursor,
    );
    _appendCaretAwareText(
      spans,
      context,
      text: source.substring(cursor, lineRange.end),
      start: cursor,
      style: style,
      caretOffset: caretOffset,
      selectionRange: selectionRange,
    );
  }

  _appendCaretIfNeeded(
    spans,
    context,
    caretOffset: caretOffset,
    boundary: lineRange.end,
  );
  appendInlayHintsThrough(lineRange.end);

  return spans;
}

InlineSpan _inlayHintSpan(InlayHint hint) {
  return TextSpan(
    text: '${hint.label} ',
    style: const TextStyle(
      color: Color(0xFF6E5F49),
      backgroundColor: Color(0xFFECE4D8),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
  );
}

List<InlineSpan> _inlineSpansForToken(
  BuildContext context, {
  required TokenSpan token,
  required String lineSlice,
  required int segmentStart,
  required int? caretOffset,
  required SourceRange? selectionRange,
  required SemanticKind? semanticKind,
  required DiagnosticSeverity? diagnosticSeverity,
  required ReferenceSpan? activeReference,
  required bool activeToken,
  required EditorSemanticThemeBinding semanticThemeBinding,
  required bool enableGlyphSubstitution,
}) {
  final style = _textStyleForToken(
    context,
    tokenKind: token.kind,
    semanticKind: semanticKind,
    diagnosticSeverity: diagnosticSeverity,
    semanticThemeBinding: semanticThemeBinding,
  );
  final referenceHighlightColor = _referenceHighlightColor(activeReference);

  if (enableGlyphSubstitution && token.kind == TokenKind.operator) {
    final glyph = _glyphForOperator(token.lexeme);
    if (glyph != null) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: activeToken
                  ? const Color(0xFFE6E0F5)
                  : referenceHighlightColor ?? Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Icon(glyph, size: 16, color: style.color),
            ),
          ),
        ),
      ];
    }
  }

  final spans = <InlineSpan>[];
  _appendCaretAwareText(
    spans,
    context,
    text: lineSlice,
    start: segmentStart,
    style: selectionRange == null
        ? style.copyWith(
            backgroundColor: activeToken
                ? const Color(0xFFE6E0F5)
                : referenceHighlightColor,
          )
        : style,
    caretOffset: caretOffset,
    selectionRange: selectionRange,
  );
  return spans;
}

bool _sameRange(SourceRange left, SourceRange right) {
  return left.start == right.start && left.end == right.end;
}

ReferenceSpan? _referenceForRange(
  List<ReferenceSpan> references,
  SourceRange range,
) {
  for (final reference in references) {
    if (_sameRange(reference.range, range)) {
      return reference;
    }
  }
  return null;
}

Color? _referenceHighlightColor(ReferenceSpan? reference) {
  if (reference == null) {
    return null;
  }
  if (reference.isDeclaration) {
    return const Color(0xFFF5DA91);
  }
  return switch (reference.access) {
    ReferenceAccess.declaration => const Color(0xFFF5DA91),
    ReferenceAccess.read => const Color(0xFFDDEACB),
    ReferenceAccess.write => const Color(0xFFD8EAF6),
  };
}

bool _selectionTouchesRange(
  SourceRange? selectionRange,
  int? caretOffset,
  SourceRange range,
) {
  if (selectionRange != null && selectionRange.intersects(range)) {
    return true;
  }
  if (caretOffset == null) {
    return false;
  }
  return caretOffset > range.start && caretOffset < range.end;
}

WidgetSpan _caretSpan(BuildContext context) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(
      width: 2,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface,
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  );
}

void _appendCaretIfNeeded(
  List<InlineSpan> spans,
  BuildContext context, {
  required int? caretOffset,
  required int boundary,
}) {
  if (caretOffset == boundary) {
    spans.add(_caretSpan(context));
  }
}

void _appendCaretAwareText(
  List<InlineSpan> spans,
  BuildContext context, {
  required String text,
  required int start,
  required TextStyle style,
  required int? caretOffset,
  required SourceRange? selectionRange,
}) {
  if (text.isEmpty) {
    return;
  }

  final boundaries = <int>{0, text.length};
  if (caretOffset != null &&
      caretOffset > start &&
      caretOffset < start + text.length) {
    boundaries.add(caretOffset - start);
  }
  if (selectionRange != null) {
    final selectionStart = selectionRange.start - start;
    final selectionEnd = selectionRange.end - start;
    if (selectionStart > 0 && selectionStart < text.length) {
      boundaries.add(selectionStart);
    }
    if (selectionEnd > 0 && selectionEnd < text.length) {
      boundaries.add(selectionEnd);
    }
  }

  final ordered = boundaries.toList()..sort();
  for (var index = 0; index < ordered.length - 1; index += 1) {
    final segmentStart = ordered[index];
    final segmentEnd = ordered[index + 1];
    if (segmentEnd <= segmentStart) {
      continue;
    }

    final absoluteStart = start + segmentStart;
    final absoluteEnd = start + segmentEnd;
    final selected =
        selectionRange != null &&
        absoluteStart < selectionRange.end &&
        selectionRange.start < absoluteEnd;

    spans.add(
      TextSpan(
        text: text.substring(segmentStart, segmentEnd),
        style: selected
            ? style.copyWith(backgroundColor: const Color(0xFFCFD8F8))
            : style,
      ),
    );

    if (caretOffset != null &&
        caretOffset == absoluteEnd &&
        caretOffset < start + text.length) {
      spans.add(_caretSpan(context));
    }
  }
}

IconData? _glyphForOperator(String lexeme) {
  switch (lexeme) {
    case '->':
      return Icons.arrow_right_alt_rounded;
    case '|>':
      return Icons.play_arrow_rounded;
    default:
      return null;
  }
}

SemanticKind? _semanticKindForRange(
  List<SemanticSpan> spans,
  SourceRange range,
) {
  for (final span in spans) {
    if (span.range.intersects(range)) {
      return span.kind;
    }
  }
  return null;
}

DiagnosticSeverity? _diagnosticSeverityForRange(
  List<Diagnostic> diagnostics,
  SourceRange range,
) {
  for (final diagnostic in diagnostics) {
    if (diagnostic.range.intersects(range)) {
      return diagnostic.severity;
    }
  }
  return null;
}

Color _diagnosticStripeColor(
  BuildContext context,
  List<Diagnostic> diagnostics,
) {
  final theme = Theme.of(context);
  if (diagnostics.any((item) => item.severity == DiagnosticSeverity.error)) {
    return _severityColor(DiagnosticSeverity.error);
  }
  if (diagnostics.any((item) => item.severity == DiagnosticSeverity.warning)) {
    return _severityColor(DiagnosticSeverity.warning);
  }
  if (diagnostics.any((item) => item.severity == DiagnosticSeverity.hint)) {
    return _severityColor(DiagnosticSeverity.hint);
  }
  return theme.dividerColor;
}

Color _severityColor(DiagnosticSeverity severity) {
  switch (severity) {
    case DiagnosticSeverity.error:
      return const Color(0xFFCB4D45);
    case DiagnosticSeverity.warning:
      return const Color(0xFFD5962A);
    case DiagnosticSeverity.hint:
      return const Color(0xFF6980B5);
  }
}

TextStyle _textStyleForToken(
  BuildContext context, {
  required TokenKind tokenKind,
  required SemanticKind? semanticKind,
  required DiagnosticSeverity? diagnosticSeverity,
  required EditorSemanticThemeBinding semanticThemeBinding,
}) {
  return EditorFlutterTextStyleBinding(
    semanticThemeBinding: semanticThemeBinding,
  ).styleForToken(
    baseStyle: Theme.of(context).textTheme.bodyMedium!,
    tokenKind: tokenKind,
    semanticKind: semanticKind,
    diagnosticSeverity: diagnosticSeverity,
  );
}

List<_SemanticLineBlock> _resolveLineBlocks({
  required DocumentState document,
  required List<int> lineStarts,
  required List<SemanticBlockRange> blocks,
}) {
  if (blocks.isEmpty) {
    return const <_SemanticLineBlock>[];
  }

  final resolved = <_SemanticLineBlock>[];
  for (final block in blocks) {
    final startLine = _lineIndexForOffset(lineStarts, block.range.start);
    final endLine = _lineIndexForOffset(
      lineStarts,
      (block.range.end - 1).clamp(0, document.length),
    );
    if (startLine <= endLine) {
      resolved.add(
        _SemanticLineBlock(
          startLine: startLine,
          endLine: endLine,
          label: block.label,
        ),
      );
    }
  }

  resolved.sort((left, right) => left.startLine.compareTo(right.startLine));
  return resolved;
}

int _lineIndexForOffset(List<int> lineStarts, int offset) {
  for (var index = lineStarts.length - 1; index >= 0; index -= 1) {
    if (offset >= lineStarts[index]) {
      return index;
    }
  }
  return 0;
}

class _SemanticBlockCard extends StatelessWidget {
  const _SemanticBlockCard({
    required this.block,
    required this.label,
    required this.collapsed,
    required this.onToggle,
    required this.child,
  });

  final _SemanticLineBlock block;
  final String label;
  final bool collapsed;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD8D0C2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.code_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
              Tooltip(
                message: collapsed ? 'Expand block' : 'Collapse block',
                child: IconButton(
                  key: ValueKey('source-fold-toggle-${block.startLine}'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    collapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                  ),
                  onPressed: onToggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CollapsedBlockSummary extends StatelessWidget {
  const _CollapsedBlockSummary({super.key, required this.hiddenLineCount});

  final int hiddenLineCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 62, top: 2, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F2E9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFD8D0C2)),
        ),
        child: Text(
          '$hiddenLineCount folded ${hiddenLineCount == 1 ? 'line' : 'lines'}',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

String _semanticBlockKey(_SemanticLineBlock block) {
  return '${block.startLine}:${block.endLine}:${block.label}';
}

class _SemanticLineBlock {
  const _SemanticLineBlock({
    required this.startLine,
    required this.endLine,
    required this.label,
  });

  final int startLine;
  final int endLine;
  final String label;
}
