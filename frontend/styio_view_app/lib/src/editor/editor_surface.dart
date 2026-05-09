import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../language/language_contract.dart';
import '../platform/viewport_profile.dart';
import 'document_state.dart';
import 'editor_controller.dart';
import 'editor_render_layers.dart';
import 'selection_state.dart';

class EditorSurface extends StatelessWidget {
  const EditorSurface({
    super.key,
    required this.controller,
    required this.viewportProfile,
  });

  final EditorSessionController controller;
  final ViewportProfile viewportProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final document = controller.document;
        final selection = controller.selection;
        final renderPlan = controller.renderPlan;
        final analysis = controller.analysis;
        final hover = controller.hoverAtSelection;
        final completions = controller.completionsAtSelection;
        final activeReferences = controller.referencesAtSelection;
        final activeToken = controller.tokenAtSelection;
        final activeSemanticKind = controller.semanticKindAtSelection;
        final summaryPills = <String>[
          'lines ${document.lines.length}',
          'chars ${document.length}',
          'tokens ${analysis.tokenCount}',
          'semantic ${analysis.semanticCount}',
          'symbols ${analysis.symbolCount}',
          'diagnostics ${analysis.diagnosticCount}',
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
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: visibleSummaryPills
                          .map((label) => _CapabilityPill(label: label))
                          .toList(growable: false),
                    ),
                    if (!dense) ...[
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: renderPlan.activeLayers
                                  .map(
                                    (layer) => _CapabilityPill(
                                      label: 'layer ${layer.name}',
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final mobileFamily = viewportProfile.isMobile;
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
                                      child: ListView(
                                        key: ValueKey(
                                          'editor-language-layout-scroll-${viewportProfile.label.toLowerCase()}',
                                        ),
                                        children: [
                                          SizedBox(
                                            height: 220,
                                            child: _SourcePreviewPane(
                                              controller: controller,
                                              viewportProfile: viewportProfile,
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
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            height: 180,
                                            child: _LanguageServicePane(
                                              controller: controller,
                                              viewportProfile: viewportProfile,
                                              analysis: analysis,
                                              hover: hover,
                                              completions: completions,
                                              activeToken: activeToken,
                                              activeSemanticKind:
                                                  activeSemanticKind,
                                            ),
                                          ),
                                        ],
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
                                              viewportProfile: viewportProfile,
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
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            height: inspectorHeight,
                                            child: _LanguageServicePane(
                                              controller: controller,
                                              viewportProfile: viewportProfile,
                                              analysis: analysis,
                                              hover: hover,
                                              completions: completions,
                                              activeToken: activeToken,
                                              activeSemanticKind:
                                                  activeSemanticKind,
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
                                            viewportProfile: viewportProfile,
                                            hover: hover,
                                            completions: completions,
                                            activeReferences: activeReferences,
                                            activeToken: activeToken,
                                            activeSemanticKind:
                                                activeSemanticKind,
                                            document: document,
                                            selection: selection,
                                            analysis: analysis,
                                            renderPlan: renderPlan,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        SizedBox(
                                          width: constraints.maxWidth >= 760
                                              ? 300
                                              : 248,
                                          child: _LanguageServicePane(
                                            controller: controller,
                                            viewportProfile: viewportProfile,
                                            analysis: analysis,
                                            hover: hover,
                                            completions: completions,
                                            activeToken: activeToken,
                                            activeSemanticKind:
                                                activeSemanticKind,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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

  @override
  State<_SourcePreviewPane> createState() => _SourcePreviewPaneState();
}

class _SourcePreviewPaneState extends State<_SourcePreviewPane> {
  static const double _gutterWidth = 62;
  static const double _estimatedCharacterWidth = 8.4;
  static const double _estimatedLineHeight = 34;

  late final FocusNode _focusNode;
  late final FocusNode _inlineRenameFocusNode;
  late final TextEditingController _inlineRenameController;
  int? _dragBaseOffset;
  bool _inlineRenameOpen = false;
  bool _usagesPanelOpen = false;
  bool _quickDocumentationOpen = false;
  bool _parameterInfoOpen = false;
  bool _completionLookupOpen = false;
  bool _surroundLookupOpen = false;
  int _completionLookupIndex = 0;
  int _surroundLookupIndex = 0;
  String? _inlineRenameError;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'editor-source-pane');
    _focusNode.addListener(_handleFocusChanged);
    _inlineRenameFocusNode = FocusNode(debugLabel: 'editor-inline-rename');
    _inlineRenameController = TextEditingController();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _inlineRenameFocusNode.dispose();
    _inlineRenameController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
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
    if (_usagesPanelOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      _closeUsagesPanel();
      return KeyEventResult.handled;
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

    if (commandPressed &&
        altPressed &&
        event.logicalKey == LogicalKeyboardKey.keyT) {
      return _openSurroundLookup()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (commandPressed) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyB:
          return widget.controller.selectDefinitionAtSelection()
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
      return widget.controller.applyFirstQuickFixAtSelection()
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
        widget.controller.moveCaretToLineBoundary(
          end: false,
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
          widget.controller.insertText(character!);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
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
    final applied = widget.controller.applyRename(newName);
    if (applied) {
      setState(() {
        _inlineRenameOpen = false;
        _inlineRenameError = null;
      });
      _focusNode.requestFocus();
      return true;
    }

    setState(() {
      _inlineRenameError = newName.isEmpty
          ? 'Enter a Styio identifier.'
          : 'Invalid rename target.';
    });
    return false;
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

  bool _openQuickDocumentation() {
    if (widget.hover == null &&
        widget.controller.definitionAtSelection == null &&
        widget.activeToken == null) {
      return false;
    }
    setState(() {
      _quickDocumentationOpen = true;
    });
    return true;
  }

  void _closeQuickDocumentation() {
    setState(() {
      _quickDocumentationOpen = false;
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
    });
    return true;
  }

  void _closeCompletionLookup() {
    setState(() {
      _completionLookupOpen = false;
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
    });
    _focusNode.requestFocus();
    return true;
  }

  void _applyCompletionFromLookup(CompletionItem item) {
    widget.controller.applyCompletionItem(item);
    setState(() {
      _completionLookupOpen = false;
      _completionLookupIndex = 0;
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
        final contentPadding = dense ? 12.0 : 18.0;

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
              padding: EdgeInsets.all(contentPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Source Buffer', style: theme.textTheme.titleMedium),
                      _CapabilityPill(
                        label: _focusNode.hasFocus
                            ? 'editing'
                            : 'click to focus',
                      ),
                    ],
                  ),
                  if (!dense) ...[
                    const SizedBox(height: 6),
                    Text(
                      compact
                          ? 'Glyph substitution stays display-only while one editor surface owns input.'
                          : 'Desktop keyboard input is live. Token spans color the buffer, semantic ranges add structure, and glyph substitution stays display-only.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView(
                      children: [
                        if (_inlineRenameOpen) ...[
                          _buildInlineRenamePanel(context),
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
                          lineStarts: lineStarts,
                          semanticBlocks: semanticBlocks,
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

  Widget _buildInlineRenamePanel(BuildContext context) {
    final theme = Theme.of(context);
    final renameText = _inlineRenameController.text.trim();
    final renamePreview = widget.controller.renamePlanAtSelection(renameText);
    final definition = widget.controller.definitionAtSelection;
    final usageCount = widget.controller.referencesAtSelection.length;
    final helperText = renamePreview == null
        ? _inlineRenameError
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
                helperText: renamePreview == null ? null : helperText,
                errorText: renamePreview == null ? helperText : null,
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

  Widget _buildQuickDocumentationPanel(BuildContext context) {
    final theme = Theme.of(context);
    final hover = widget.hover;
    final token = widget.activeToken;
    final definition = widget.controller.definitionAtSelection;
    final references = widget.controller.referencesAtSelection;
    final title = definition == null
        ? token == null
              ? 'Quick Documentation'
              : 'Quick Documentation: ${token.lexeme}'
        : 'Quick Documentation: ${definition.symbol.name}';
    final body = hover?.markdown ?? 'No documentation payload at the caret.';

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
            Text(body, style: theme.textTheme.bodySmall),
            if (token != null) ...[
              const SizedBox(height: 8),
              Text(
                'Token ${token.kind.name} · ${_formatRange(token.range)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (definition != null) ...[
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
            ],
          ],
        ),
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
              const SizedBox(height: 8),
              Text(
                activeParameter == null
                    ? 'No active parameter'
                    : 'Argument ${parameterInfo.activeParameterIndex + 1} of '
                          '${parameterInfo.parameters.length}: '
                          '${activeParameter.displayText}',
                style: theme.textTheme.bodySmall,
              ),
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
    final position = widget.document.positionForOffset(reference.range.start);
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
                reference.isDeclaration
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reference.isDeclaration ? 'declaration' : 'usage'} · '
                      '${reference.kind.name} · $location',
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
                        ...compactCompletions.map(
                          (item) => _InlineActionChip(
                            key: ValueKey(
                              'inline-completion-action-${item.label}',
                            ),
                            icon: Icons.auto_awesome_rounded,
                            label: item.label,
                            onTap: () => controller.applyCompletionItem(item),
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
                              ...compactCompletions.map(
                                (item) => _InlineActionChip(
                                  key: ValueKey(
                                    'inline-completion-action-${item.label}',
                                  ),
                                  icon: Icons.auto_awesome_rounded,
                                  label: '${item.label} · ${item.kind.name}',
                                  onTap: () =>
                                      controller.applyCompletionItem(item),
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
  });

  final EditorSessionController controller;
  final ViewportProfile viewportProfile;
  final StyioDocumentAnalysis analysis;
  final HoverPayload? hover;
  final List<CompletionItem> completions;
  final TokenSpan? activeToken;
  final SemanticKind? activeSemanticKind;

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

    if (widget.viewportProfile.isMobile) {
      return KeyedSubtree(
        key: const ValueKey('language-pane-mobile'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Expanded(
              child: ListView(
                children: [
                  _InspectorCard(
                    key: ValueKey(
                      'language-mobile-section-${_selectedSection.name}',
                    ),
                    title: _selectedSection.label,
                    child: _buildSectionContent(
                      context,
                      section: _selectedSection,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return KeyedSubtree(
      key: const ValueKey('language-pane-desktop'),
      child: ListView(
        children: [
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
        if (renamePreview != null) ...[
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
                  '${reference.isDeclaration ? 'decl' : 'use'} · '
                  '${_formatRange(reference.range)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
      ],
    );
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
  required List<int> lineStarts,
  required List<_SemanticLineBlock> semanticBlocks,
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
  var lineIndex = 0;

  while (lineIndex < document.lines.length) {
    final block = blockByStart[lineIndex];
    if (block != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SemanticBlockCard(
            label: block.label,
            child: Column(
              children: [
                for (
                  var blockLine = block.startLine;
                  blockLine <= block.endLine;
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
                    onTapLine: onTapLine,
                    onPanStartLine: onPanStartLine,
                    onPanUpdateLine: onPanUpdateLine,
                    onPanEnd: onPanEnd,
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
        onTapLine: onTapLine,
        onPanStartLine: onPanStartLine,
        onPanUpdateLine: onPanUpdateLine,
        onPanEnd: onPanEnd,
      ),
    );
    lineIndex += 1;
  }

  return children;
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
}) {
  final spans = <InlineSpan>[];
  final caretOffset = selection.isCollapsed ? selection.end : null;
  final selectionRange = selection.isCollapsed
      ? null
      : SourceRange(start: selection.start, end: selection.end);
  final lineTokens = analysis.tokenSpans
      .where((token) => token.range.intersects(lineRange))
      .toList(growable: false);

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
          enableGlyphSubstitution:
              renderPlan.activeLayers.contains(EditorRenderLayer.decoration) &&
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

  return spans;
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
  required bool enableGlyphSubstitution,
}) {
  final style = _textStyleForToken(
    context,
    tokenKind: token.kind,
    semanticKind: semanticKind,
    diagnosticSeverity: diagnosticSeverity,
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
  return reference.isDeclaration
      ? const Color(0xFFF5DA91)
      : const Color(0xFFDDEACB);
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
}) {
  Color color;
  FontWeight weight = FontWeight.w500;

  switch (tokenKind) {
    case TokenKind.keyword:
      color = const Color(0xFF6450A7);
      break;
    case TokenKind.identifier:
      color = const Color(0xFF2C2725);
      break;
    case TokenKind.number:
      color = const Color(0xFF0F7B68);
      break;
    case TokenKind.string:
      color = const Color(0xFFAF5B33);
      break;
    case TokenKind.comment:
      color = const Color(0xFF9A9185);
      break;
    case TokenKind.operator:
      color = const Color(0xFF255A96);
      break;
    case TokenKind.punctuation:
      color = const Color(0xFF6D655E);
      break;
    case TokenKind.whitespace:
      color = const Color(0xFF2C2725);
      weight = FontWeight.w400;
      break;
    case TokenKind.unknown:
      color = const Color(0xFFCB4D45);
      break;
  }

  switch (semanticKind) {
    case SemanticKind.function:
      color = const Color(0xFFAA4D7D);
      weight = FontWeight.w700;
      break;
    case SemanticKind.pipeline:
      color = const Color(0xFF25637A);
      weight = FontWeight.w700;
      break;
    case SemanticKind.state:
      color = const Color(0xFF847A22);
      weight = FontWeight.w700;
      break;
    case SemanticKind.resource:
      color = const Color(0xFF8B5E28);
      weight = FontWeight.w700;
      break;
    case SemanticKind.variable:
      color = const Color(0xFF6A4C33);
      weight = FontWeight.w600;
      break;
    case SemanticKind.parameter:
      color = const Color(0xFF355E97);
      weight = FontWeight.w600;
      break;
    case SemanticKind.typeName:
      color = const Color(0xFF4D6D2A);
      weight = FontWeight.w700;
      break;
    case null:
      break;
  }

  var decoration = TextDecoration.none;
  var decorationColor = color;
  var decorationStyle = TextDecorationStyle.solid;

  if (diagnosticSeverity != null) {
    decoration = TextDecoration.underline;
    decorationStyle = TextDecorationStyle.wavy;
    switch (diagnosticSeverity) {
      case DiagnosticSeverity.error:
        decorationColor = const Color(0xFFCB4D45);
        break;
      case DiagnosticSeverity.warning:
        decorationColor = const Color(0xFFD5962A);
        break;
      case DiagnosticSeverity.hint:
        decorationColor = const Color(0xFF6980B5);
        break;
    }
  }

  return Theme.of(context).textTheme.bodyMedium!.copyWith(
    fontFamily: 'monospace',
    color: color,
    fontWeight: weight,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
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
  const _SemanticBlockCard({required this.label, required this.child});

  final String label;
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
              Text(label, style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
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
