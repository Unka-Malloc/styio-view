library;

import 'coding_plan.dart';

final class LoopGuard {
  LoopGuard(this.budget);

  final CodingLoopBudget budget;
  int _transitions = 0;
  final Map<String, int> _failureCounts = <String, int>{};

  int get transitions => _transitions;

  bool advance() {
    if (_transitions >= budget.maxTransitions) return false;
    _transitions += 1;
    return true;
  }

  bool recordFailure(String stepId, String fingerprint) {
    final key = '$stepId\u0000$fingerprint';
    final count = (_failureCounts[key] ?? 0) + 1;
    _failureCounts[key] = count;
    return count >= budget.maxRepeatedFailures;
  }
}
