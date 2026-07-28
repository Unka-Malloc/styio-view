library;

import 'coding_plan.dart';

final class ValidationPlanner {
  const ValidationPlanner();

  List<CodingValidationRequest> plan({
    required CodingTask task,
    required CodingStep step,
    required CodingChangeSet changeSet,
  }) {
    final changed = changeSet.resources
        .map((resource) => resource.resource)
        .toSet();
    final ids = <String>{};
    final requests = <CodingValidationRequest>[];
    for (final target in step.validations) {
      if (requests.length >= task.budget.maxChangedResources ||
          !ids.add(target.id) ||
          !task.allowedResources.contains(target.scope) ||
          target.scope == '.' ||
          target.scope.contains('*') ||
          (target.kind == CodingValidationKind.analyze &&
              !changed.contains(target.scope))) {
        throw ArgumentError('Validation target is not focused or is invalid.');
      }
      requests.add(
        CodingValidationRequest(
          id: target.id,
          kind: target.kind,
          scope: target.scope,
        ),
      );
    }
    requests.sort((left, right) {
      final kind = left.kind.index.compareTo(right.kind.index);
      return kind != 0 ? kind : left.id.compareTo(right.id);
    });
    return List<CodingValidationRequest>.unmodifiable(requests);
  }
}
