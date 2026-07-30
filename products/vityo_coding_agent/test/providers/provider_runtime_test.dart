import 'package:vityo_coding_agent/vityo_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  test('usage budget validates provider receipts', () {
    const budget = UsageBudget(
      maxContextTokens: 8,
      maxOutputTokens: 4,
      maxTotalTokens: 10,
      maxCostMicros: 20,
    );
    expect(
      () => budget.validateUsage(
        const ModelUsage(inputTokens: 7, outputTokens: 4),
      ),
      throwsA(
        isA<ProviderFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProviderFailureKind.budgetExceeded,
        ),
      ),
    );
  });

  test('stream reducer rejects malformed tool arguments', () {
    final reducer = ProviderStreamReducer(
      maxBufferedOutputBytes: 64,
      maxToolArgumentBytes: 64,
    );
    expect(
      () => reducer.add(
        const ModelToolCallDelta(
          id: 'call',
          name: 'workspace.read',
          argumentsFragment: '{bad',
          done: true,
        ),
      ),
      throwsA(
        isA<ProviderFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProviderFailureKind.protocol,
        ),
      ),
    );
  });
}
