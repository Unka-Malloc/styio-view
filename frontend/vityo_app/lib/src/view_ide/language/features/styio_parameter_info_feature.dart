import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../semantic/styio_symbol_index.dart';

class StyioParameterInfoFeature {
  const StyioParameterInfoFeature({
    this.symbolIndex = const StyioSymbolIndex(),
  });

  final StyioSymbolIndex symbolIndex;

  ParameterInfoPayload? parameterInfoAt({
    required DocumentState document,
    required int offset,
  }) {
    return symbolIndex.parameterInfoAt(document.text, offset);
  }
}
