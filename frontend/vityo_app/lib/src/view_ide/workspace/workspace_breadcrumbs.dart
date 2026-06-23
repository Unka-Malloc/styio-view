import '../editor/document/document_state.dart';
import '../language/language.dart';

enum WorkspaceBreadcrumbsStatus {
  ready,
  pathOnly,
  emptyWorkspace,
}

enum WorkspaceBreadcrumbItemKind {
  folder,
  file,
  symbol,
}

class WorkspaceBreadcrumbsQuery {
  const WorkspaceBreadcrumbsQuery({
    required this.targetFilePath,
    required this.caretOffset,
  });

  final String targetFilePath;
  final int caretOffset;
}

class WorkspaceBreadcrumbItem {
  const WorkspaceBreadcrumbItem({
    required this.label,
    required this.kind,
    required this.filePath,
    this.symbolKind,
    this.range,
    this.line,
    this.column,
    this.previewText = '',
  });

  final String label;
  final WorkspaceBreadcrumbItemKind kind;
  final String filePath;
  final SymbolKind? symbolKind;
  final SourceRange? range;
  final int? line;
  final int? column;
  final String previewText;

  bool get selectable =>
      kind == WorkspaceBreadcrumbItemKind.file ||
      kind == WorkspaceBreadcrumbItemKind.symbol;

  String get kindLabel => symbolKind?.name ?? kind.name;
}

class WorkspaceBreadcrumbsResult {
  const WorkspaceBreadcrumbsResult({
    required this.query,
    required this.status,
    required this.filePath,
    required this.caretOffset,
    required this.symbolsIndexed,
    required this.items,
    this.activeSymbol,
    this.message,
  });

  final WorkspaceBreadcrumbsQuery query;
  final WorkspaceBreadcrumbsStatus status;
  final String filePath;
  final int caretOffset;
  final int symbolsIndexed;
  final List<WorkspaceBreadcrumbItem> items;
  final WorkspaceBreadcrumbItem? activeSymbol;
  final String? message;

  int get itemCount => items.length;

  bool get hasSymbolContext => activeSymbol != null;
}

class WorkspaceBreadcrumbsService {
  const WorkspaceBreadcrumbsService({
    ProjectStyioDocumentService documentLanguageService =
        const ProjectStyioDocumentService(),
  }) : _documentLanguageService = documentLanguageService;

  final ProjectStyioDocumentService _documentLanguageService;

  WorkspaceBreadcrumbsResult buildForDocument({
    required List<String> filePaths,
    required DocumentState document,
    required WorkspaceBreadcrumbsQuery query,
  }) {
    final targetFilePath = _displayPath(query.targetFilePath);
    final workspaceFiles = _uniqueFilePaths(filePaths).map(_displayPath).toSet();
    if (targetFilePath.isEmpty || !workspaceFiles.contains(targetFilePath)) {
      return WorkspaceBreadcrumbsResult(
        query: query,
        status: WorkspaceBreadcrumbsStatus.emptyWorkspace,
        filePath: targetFilePath,
        caretOffset: query.caretOffset,
        symbolsIndexed: 0,
        items: const <WorkspaceBreadcrumbItem>[],
        message: 'Breadcrumbs require an active workspace file.',
      );
    }

    final pathItems = _pathItems(targetFilePath);
    final symbolItems = _symbolItemsForDocument(
      document: document,
      filePath: targetFilePath,
      caretOffset: query.caretOffset,
    );
    final activeSymbol = symbolItems.activeSymbol;
    final items = <WorkspaceBreadcrumbItem>[
      ...pathItems,
      if (activeSymbol != null) activeSymbol,
    ];

    final status = activeSymbol == null
        ? WorkspaceBreadcrumbsStatus.pathOnly
        : WorkspaceBreadcrumbsStatus.ready;

    return WorkspaceBreadcrumbsResult(
      query: query,
      status: status,
      filePath: targetFilePath,
      caretOffset: query.caretOffset,
      symbolsIndexed: symbolItems.symbolsIndexed,
      items: List<WorkspaceBreadcrumbItem>.unmodifiable(items),
      activeSymbol: activeSymbol,
      message: status == WorkspaceBreadcrumbsStatus.pathOnly
          ? 'No active document symbol at the caret.'
          : null,
    );
  }

  _SymbolBreadcrumbs _symbolItemsForDocument({
    required DocumentState document,
    required String filePath,
    required int caretOffset,
  }) {
    if (!_isStyioFile(filePath)) {
      return const _SymbolBreadcrumbs(symbolsIndexed: 0);
    }
    final analysis = _documentLanguageService.analyzeDocument(document);
    final symbols = analysis.documentSymbols;
    final activeSymbol = _activeSymbolForOffset(
      symbols: symbols,
      caretOffset: caretOffset.clamp(0, document.length).toInt(),
    );
    if (activeSymbol == null) {
      return _SymbolBreadcrumbs(symbolsIndexed: symbols.length);
    }

    final position = document.positionForOffset(activeSymbol.nameRange.start);
    return _SymbolBreadcrumbs(
      symbolsIndexed: symbols.length,
      activeSymbol: WorkspaceBreadcrumbItem(
        label: activeSymbol.name,
        kind: WorkspaceBreadcrumbItemKind.symbol,
        filePath: filePath,
        symbolKind: activeSymbol.kind,
        range: activeSymbol.nameRange,
        line: position.line,
        column: position.column,
        previewText: _linePreview(document, position.line),
      ),
    );
  }

  static DocumentSymbol? _activeSymbolForOffset({
    required List<DocumentSymbol> symbols,
    required int caretOffset,
  }) {
    DocumentSymbol? containing;
    for (final symbol in symbols) {
      if (!_containsCaret(symbol.declarationRange, caretOffset)) {
        continue;
      }
      if (containing == null ||
          _rangeLength(symbol.declarationRange) <
              _rangeLength(containing.declarationRange) ||
          symbol.declarationRange.start > containing.declarationRange.start) {
        containing = symbol;
      }
    }
    if (containing != null) {
      return containing;
    }

    DocumentSymbol? previousContainer;
    DocumentSymbol? previous;
    for (final symbol in symbols) {
      final anchor = symbol.nameRange.start;
      if (anchor > caretOffset) {
        continue;
      }
      if (previous == null || anchor > previous.nameRange.start) {
        previous = symbol;
      }
      if (!_isContainerSymbol(symbol.kind)) {
        continue;
      }
      if (previousContainer == null ||
          anchor > previousContainer.nameRange.start) {
        previousContainer = symbol;
      }
    }
    return previousContainer ?? previous;
  }

  static bool _isContainerSymbol(SymbolKind kind) {
    return switch (kind) {
      SymbolKind.function ||
      SymbolKind.pipeline ||
      SymbolKind.state ||
      SymbolKind.resource ||
      SymbolKind.task => true,
      SymbolKind.variable || SymbolKind.parameter => false,
    };
  }

  static List<WorkspaceBreadcrumbItem> _pathItems(String filePath) {
    final segments = filePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return const <WorkspaceBreadcrumbItem>[];
    }

    final items = <WorkspaceBreadcrumbItem>[];
    final cumulative = <String>[];
    for (var index = 0; index < segments.length; index += 1) {
      cumulative.add(segments[index]);
      final isFile = index == segments.length - 1;
      items.add(
        WorkspaceBreadcrumbItem(
          label: segments[index],
          kind: isFile
              ? WorkspaceBreadcrumbItemKind.file
              : WorkspaceBreadcrumbItemKind.folder,
          filePath: isFile ? filePath : cumulative.join('/'),
          range: isFile ? const SourceRange(start: 0, end: 0) : null,
        ),
      );
    }
    return List<WorkspaceBreadcrumbItem>.unmodifiable(items);
  }

  static bool _containsCaret(SourceRange range, int caretOffset) {
    return caretOffset >= range.start && caretOffset <= range.end;
  }

  static int _rangeLength(SourceRange range) {
    return range.end - range.start;
  }

  static String _linePreview(DocumentState document, int line) {
    final lines = document.lines;
    if (lines.isEmpty) {
      return '';
    }
    return lines[line.clamp(0, lines.length - 1).toInt()].trimRight();
  }

  static bool _isStyioFile(String filePath) {
    return _displayPath(filePath).toLowerCase().endsWith('.styio');
  }

  static List<String> _uniqueFilePaths(List<String> filePaths) {
    final seen = <String>{};
    final unique = <String>[];
    for (final filePath in filePaths) {
      if (seen.add(filePath)) {
        unique.add(filePath);
      }
    }
    return unique;
  }

  static String _displayPath(String filePath) {
    return filePath.trim().replaceAll('\\', '/');
  }
}

class _SymbolBreadcrumbs {
  const _SymbolBreadcrumbs({
    required this.symbolsIndexed,
    this.activeSymbol,
  });

  final int symbolsIndexed;
  final WorkspaceBreadcrumbItem? activeSymbol;
}
