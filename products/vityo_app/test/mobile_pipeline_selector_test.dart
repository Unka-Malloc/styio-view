import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';

void main() {
  test('mobile pipeline selector only lists type-safe candidates', () {
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'normalizePrice',
          kind: SymbolKind.pipeline,
          nameRange: SourceRange(start: 9, end: 23),
          declarationRange: SourceRange(start: 0, end: 42),
          detail: 'price pipeline',
        ),
        DocumentSymbol(
          name: 'renderText',
          kind: SymbolKind.pipeline,
          nameRange: SourceRange(start: 52, end: 62),
          declarationRange: SourceRange(start: 43, end: 80),
          detail: 'text pipeline',
        ),
        DocumentSymbol(
          name: 'helper',
          kind: SymbolKind.function,
          nameRange: SourceRange(start: 90, end: 96),
          declarationRange: SourceRange(start: 83, end: 110),
        ),
        DocumentSymbol(
          name: 'unsignedPipeline',
          kind: SymbolKind.pipeline,
          nameRange: SourceRange(start: 120, end: 136),
          declarationRange: SourceRange(start: 112, end: 150),
        ),
      ],
      referenceSpans: <ReferenceSpan>[],
    );

    final candidates = const MobilePipelineSelector().candidatesFor(
      analysis: analysis,
      request: const PipelineSelectorTypeRequest(
        inputType: 'PriceTick',
        outputType: 'NormalizedPrice',
      ),
      signaturesByName: const <String, PipelineTypeSignature>{
        'normalizePrice': PipelineTypeSignature(
          inputType: 'PriceTick',
          outputType: 'NormalizedPrice',
        ),
        'renderText': PipelineTypeSignature(
          inputType: 'string',
          outputType: 'Widget',
        ),
      },
    );

    expect(candidates.map((candidate) => candidate.name), <String>[
      'normalizePrice',
    ]);
    expect(candidates.single.inputType, 'PriceTick');
    expect(candidates.single.outputType, 'NormalizedPrice');
  });

  test('mobile pipeline selector excludes duplicate unsafe entries', () {
    const analysis = StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'normalize',
          kind: SymbolKind.pipeline,
          nameRange: SourceRange(start: 0, end: 9),
          declarationRange: SourceRange(start: 0, end: 20),
        ),
        DocumentSymbol(
          name: 'normalize',
          kind: SymbolKind.pipeline,
          nameRange: SourceRange(start: 30, end: 39),
          declarationRange: SourceRange(start: 30, end: 52),
        ),
      ],
      referenceSpans: <ReferenceSpan>[],
    );

    final candidates = const MobilePipelineSelector().candidatesFor(
      analysis: analysis,
      request: const PipelineSelectorTypeRequest(inputType: 'PriceTick'),
      signaturesByName: const <String, PipelineTypeSignature>{
        'normalize': PipelineTypeSignature(
          inputType: 'PriceTick',
          outputType: 'PriceTick',
        ),
      },
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.nameRange.start, 0);
  });
}
