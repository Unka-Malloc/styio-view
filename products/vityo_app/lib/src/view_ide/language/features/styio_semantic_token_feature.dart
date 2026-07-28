import '../contract/language_contract.dart';
import '../service/language_service_foundation.dart';

class StyioSemanticTokenFeature {
  const StyioSemanticTokenFeature();

  List<SemanticSpan> semanticSpans({required SemanticSnapshot snapshot}) {
    return <SemanticSpan>[
      for (final element in snapshot.elements)
        SemanticSpan(
          range: element.nameRange,
          kind: _semanticKind(element.kind),
          modifiers: const <String>['declaration'],
        ),
      for (final reference in snapshot.references)
        if (!reference.isDeclaration)
          SemanticSpan(
            range: reference.range,
            kind: _semanticKind(reference.target.kind),
          ),
    ];
  }

  SemanticKind _semanticKind(ResolvedElementKind kind) {
    switch (kind) {
      case ResolvedElementKind.function:
        return SemanticKind.function;
      case ResolvedElementKind.resource:
        return SemanticKind.resource;
      case ResolvedElementKind.parameter:
        return SemanticKind.parameter;
      case ResolvedElementKind.type:
        return SemanticKind.typeName;
      case ResolvedElementKind.variable:
      case ResolvedElementKind.unknown:
        return SemanticKind.variable;
    }
  }
}
