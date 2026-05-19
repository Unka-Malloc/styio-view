import '../language/language_contract.dart';

class PipelineSelectorTypeRequest {
  const PipelineSelectorTypeRequest({
    required this.inputType,
    this.outputType,
  });

  final String inputType;
  final String? outputType;
}

class PipelineTypeSignature {
  const PipelineTypeSignature({
    required this.inputType,
    required this.outputType,
  });

  final String inputType;
  final String outputType;
}

class MobilePipelineCandidate {
  const MobilePipelineCandidate({
    required this.name,
    required this.nameRange,
    required this.declarationRange,
    required this.inputType,
    required this.outputType,
    this.detail = '',
  });

  final String name;
  final SourceRange nameRange;
  final SourceRange declarationRange;
  final String inputType;
  final String outputType;
  final String detail;
}

class MobilePipelineSelector {
  const MobilePipelineSelector();

  List<MobilePipelineCandidate> candidatesFor({
    required StyioDocumentAnalysis analysis,
    required PipelineSelectorTypeRequest request,
    required Map<String, PipelineTypeSignature> signaturesByName,
  }) {
    final candidates = <MobilePipelineCandidate>[];
    final seenNames = <String>{};

    for (final symbol in analysis.documentSymbols) {
      if (symbol.kind != SymbolKind.pipeline || !seenNames.add(symbol.name)) {
        continue;
      }
      final signature = signaturesByName[symbol.name];
      if (signature == null ||
          signature.inputType != request.inputType ||
          (request.outputType != null &&
              signature.outputType != request.outputType)) {
        continue;
      }
      candidates.add(
        MobilePipelineCandidate(
          name: symbol.name,
          nameRange: symbol.nameRange,
          declarationRange: symbol.declarationRange,
          inputType: signature.inputType,
          outputType: signature.outputType,
          detail: symbol.detail,
        ),
      );
    }

    return List.unmodifiable(candidates);
  }
}
