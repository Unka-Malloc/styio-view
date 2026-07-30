import 'dart:async';

import 'package:vityo_coding_agent/vityo_coding_agent.dart';

Future<void> main() async {
  await _reducesFragmentedStreamsAndRecordsUsage();
  await _enforcesCancellationTimeoutAndBudgets();
  await _failsOverOnlyBeforeAReplaySafeEffect();
}

Future<void> _reducesFragmentedStreamsAndRecordsUsage() async {
  final incompatible = _FakeProvider(
    id: 'text-only',
    capabilities: const ModelProviderCapabilities(
      contextTokens: 4096,
      outputTokens: 1024,
      supportsTools: false,
      maxConcurrency: 1,
    ),
    events: const <ModelEvent>[],
  );
  final compatible = _FakeProvider(
    id: 'tools',
    capabilities: const ModelProviderCapabilities(
      contextTokens: 8192,
      outputTokens: 2048,
      supportsTools: true,
      maxConcurrency: 2,
    ),
    events: const <ModelEvent>[
      ModelTextDelta('hel'),
      ModelTextDelta('lo'),
      ModelToolCallDelta(
        id: 'call-1',
        name: 'workspace.read',
        argumentsFragment: '{"path":',
      ),
      ModelToolCallDelta(
        id: 'call-1',
        argumentsFragment: '"lib/main.dart"}',
        done: true,
      ),
      ModelUsageEvent(
        ModelUsage(
          inputTokens: 12,
          outputTokens: 7,
          costMicros: 90,
        ),
      ),
      ModelCompleted(finishReason: ModelFinishReason.toolCalls),
    ],
  );
  final router = ProviderRouter(
    providers: <ModelProvider>[incompatible, compatible],
    budget: UsageBudget(
      maxContextTokens: 64,
      maxOutputTokens: 32,
      maxTotalTokens: 96,
      maxCostMicros: 1000,
    ),
  );
  final cancellation = AgentCancellationController();
  final receipt = await router.generate(
    const ModelRequest(
      requestId: 'fragmented',
      messages: <ModelMessage>[
        ModelMessage.user('inspect the entrypoint'),
      ],
      tools: <ModelToolDefinition>[
        ModelToolDefinition(
          name: 'workspace.read',
          description: 'Read one approved workspace file',
          inputSchema: <String, Object?>{
            'type': 'object',
            'required': <String>['path'],
          },
        ),
      ],
      estimatedContextTokens: 12,
      outputTokenLimit: 16,
      retrySafety: ModelRetrySafety.readOnly,
    ),
    requirements: const ProviderRequirements(
      requiresTools: true,
      minimumContextTokens: 4096,
      minimumOutputTokens: 512,
    ),
    cancellation: cancellation.token,
  );

  _expect(receipt.providerId == 'tools', 'router must select a compatible provider');
  _expect(incompatible.callCount == 0, 'incompatible providers must not be invoked');
  _expect(receipt.text == 'hello', 'fragmented text must reduce in order');
  _expect(receipt.toolCalls.length == 1, 'one fragmented tool call must complete');
  _expect(
    receipt.toolCalls.single.name == 'workspace.read' &&
        receipt.toolCalls.single.arguments['path'] == 'lib/main.dart',
    'tool arguments must decode only after the complete bounded fragment',
  );
  _expect(
    receipt.usage.inputTokens == 12 &&
        receipt.usage.outputTokens == 7 &&
        receipt.usage.costMicros == 90,
    'a correlated usage receipt must be returned',
  );
  _expect(
    receipt.finishReason == ModelFinishReason.toolCalls,
    'finish reason must remain provider-neutral',
  );
}

Future<void> _enforcesCancellationTimeoutAndBudgets() async {
  final neverCompletes = _FakeProvider(
    id: 'slow',
    capabilities: const ModelProviderCapabilities(
      contextTokens: 4096,
      outputTokens: 1024,
      supportsTools: false,
      maxConcurrency: 1,
    ),
    streamFactory: (_, cancellation) async* {
      await cancellation.whenCancelled;
    },
  );
  final router = ProviderRouter(
    providers: <ModelProvider>[neverCompletes],
    budget: UsageBudget(
      maxContextTokens: 8,
      maxOutputTokens: 8,
      maxTotalTokens: 12,
      maxCostMicros: 100,
    ),
  );

  await _expectFailure(
    () => router.generate(
      const ModelRequest(
        requestId: 'missing-tools',
        messages: <ModelMessage>[ModelMessage.user('use a tool')],
        estimatedContextTokens: 1,
        outputTokenLimit: 1,
        retrySafety: ModelRetrySafety.readOnly,
      ),
      requirements: const ProviderRequirements(requiresTools: true),
      cancellation: AgentCancellationController().token,
    ),
    ProviderFailureKind.invalidRequest,
  );
  await _expectFailure(
    () => router.generate(
      const ModelRequest(
        requestId: 'context-budget',
        messages: <ModelMessage>[ModelMessage.user('too large')],
        estimatedContextTokens: 9,
        outputTokenLimit: 1,
        retrySafety: ModelRetrySafety.readOnly,
      ),
      requirements: const ProviderRequirements(),
      cancellation: AgentCancellationController().token,
    ),
    ProviderFailureKind.budgetExceeded,
  );
  _expect(
    neverCompletes.callCount == 0,
    'context/output budgets must fail before provider invocation',
  );

  final controller = AgentCancellationController();
  final cancelled = router.generate(
    const ModelRequest(
      requestId: 'cancelled',
      messages: <ModelMessage>[ModelMessage.user('wait')],
      estimatedContextTokens: 1,
      outputTokenLimit: 1,
      retrySafety: ModelRetrySafety.readOnly,
    ),
    requirements: const ProviderRequirements(),
    cancellation: controller.token,
  );
  scheduleMicrotask(controller.cancel);
  await _expectFailure(() => cancelled, ProviderFailureKind.cancelled);

  await _expectFailure(
    () => router.generate(
      ModelRequest(
        requestId: 'timeout',
        messages: const <ModelMessage>[ModelMessage.user('wait')],
        estimatedContextTokens: 1,
        outputTokenLimit: 1,
        retrySafety: ModelRetrySafety.readOnly,
        deadline: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      ),
      requirements: const ProviderRequirements(),
      cancellation: AgentCancellationController().token,
    ),
    ProviderFailureKind.timeout,
  );

  final oversized = _FakeProvider(
    id: 'oversized',
    capabilities: const ModelProviderCapabilities(
      contextTokens: 4096,
      outputTokens: 1024,
      supportsTools: false,
      maxConcurrency: 1,
    ),
    events: const <ModelEvent>[
      ModelTextDelta('0123456789'),
      ModelCompleted(),
    ],
  );
  await _expectFailure(
    () => ProviderRouter(
      providers: <ModelProvider>[oversized],
      budget: UsageBudget(
        maxContextTokens: 8,
        maxOutputTokens: 8,
        maxTotalTokens: 16,
        maxCostMicros: 100,
        maxBufferedOutputBytes: 8,
      ),
    ).generate(
      const ModelRequest(
        requestId: 'output-budget',
        messages: <ModelMessage>[ModelMessage.user('overflow')],
        estimatedContextTokens: 1,
        outputTokenLimit: 8,
        retrySafety: ModelRetrySafety.readOnly,
      ),
      requirements: const ProviderRequirements(),
      cancellation: AgentCancellationController().token,
    ),
    ProviderFailureKind.budgetExceeded,
  );
}

Future<void> _failsOverOnlyBeforeAReplaySafeEffect() async {
  final fallback = _FakeProvider(
    id: 'fallback',
    capabilities: const ModelProviderCapabilities(
      contextTokens: 4096,
      outputTokens: 1024,
      supportsTools: false,
      maxConcurrency: 1,
    ),
    events: const <ModelEvent>[
      ModelTextDelta('ok'),
      ModelUsageEvent(ModelUsage(inputTokens: 1, outputTokens: 1)),
      ModelCompleted(),
    ],
  );
  final rateLimited = _FakeProvider(
    id: 'limited',
    capabilities: fallback.capabilitiesValue,
    failure: const ProviderFailure(
      kind: ProviderFailureKind.rateLimited,
      message: 'retry elsewhere',
      retryable: true,
      effectState: ModelEffectState.none,
    ),
  );
  final safeRouter = ProviderRouter(
    providers: <ModelProvider>[rateLimited, fallback],
    budget: UsageBudget(
      maxContextTokens: 16,
      maxOutputTokens: 16,
      maxTotalTokens: 32,
      maxCostMicros: 100,
    ),
  );
  final safeReceipt = await safeRouter.generate(
    const ModelRequest(
      requestId: 'safe-fallback',
      messages: <ModelMessage>[ModelMessage.user('read')],
      estimatedContextTokens: 1,
      outputTokenLimit: 4,
      retrySafety: ModelRetrySafety.readOnly,
    ),
    requirements: const ProviderRequirements(),
    cancellation: AgentCancellationController().token,
  );
  _expect(
    safeReceipt.providerId == 'fallback' &&
        rateLimited.callCount == 1 &&
        fallback.callCount == 1,
    'retryable pre-effect failure may use one compatible fallback',
  );

  final uncertain = _FakeProvider(
    id: 'uncertain',
    capabilities: fallback.capabilitiesValue,
    failure: const ProviderFailure(
      kind: ProviderFailureKind.transientUnavailable,
      message: 'effect outcome unknown',
      retryable: true,
      effectState: ModelEffectState.uncertain,
    ),
  );
  final forbiddenFallback = _FakeProvider(
    id: 'must-not-run',
    capabilities: fallback.capabilitiesValue,
    events: fallback.eventsValue,
  );
  await _expectFailure(
    () => ProviderRouter(
      providers: <ModelProvider>[uncertain, forbiddenFallback],
      budget: UsageBudget(
        maxContextTokens: 16,
        maxOutputTokens: 16,
        maxTotalTokens: 32,
        maxCostMicros: 100,
      ),
    ).generate(
      const ModelRequest(
        requestId: 'uncertain-effect',
        messages: <ModelMessage>[ModelMessage.user('mutate')],
        estimatedContextTokens: 1,
        outputTokenLimit: 4,
        retrySafety: ModelRetrySafety.idempotentMutation,
        idempotencyKey: 'effect-1',
      ),
      requirements: const ProviderRequirements(),
      cancellation: AgentCancellationController().token,
    ),
    ProviderFailureKind.transientUnavailable,
  );
  _expect(
    forbiddenFallback.callCount == 0,
    'an uncertain or committed effect must never be replayed on fallback',
  );

  final authentication = _FakeProvider(
    id: 'auth',
    capabilities: fallback.capabilitiesValue,
    failure: const ProviderFailure(
      kind: ProviderFailureKind.authentication,
      message: 'credential rejected',
      retryable: false,
      effectState: ModelEffectState.none,
    ),
  );
  await _expectFailure(
    () => ProviderRouter(
      providers: <ModelProvider>[authentication, forbiddenFallback],
      budget: UsageBudget(
        maxContextTokens: 16,
        maxOutputTokens: 16,
        maxTotalTokens: 32,
        maxCostMicros: 100,
      ),
    ).generate(
      const ModelRequest(
        requestId: 'auth-failure',
        messages: <ModelMessage>[ModelMessage.user('read')],
        estimatedContextTokens: 1,
        outputTokenLimit: 4,
        retrySafety: ModelRetrySafety.readOnly,
      ),
      requirements: const ProviderRequirements(),
      cancellation: AgentCancellationController().token,
    ),
    ProviderFailureKind.authentication,
  );
  _expect(
    forbiddenFallback.callCount == 0,
    'authentication and invalid-request failures must not fail over',
  );
}

final class _FakeProvider implements ModelProvider {
  _FakeProvider({
    required this.id,
    required ModelProviderCapabilities capabilities,
    List<ModelEvent> events = const <ModelEvent>[],
    this.failure,
    Stream<ModelEvent> Function(
      ModelRequest request,
      AgentCancellationToken cancellation,
    )?
    streamFactory,
  }) : capabilitiesValue = capabilities,
       eventsValue = List<ModelEvent>.unmodifiable(events),
       _streamFactory = streamFactory;

  @override
  final String id;
  final ModelProviderCapabilities capabilitiesValue;
  final List<ModelEvent> eventsValue;
  final ProviderFailure? failure;
  final Stream<ModelEvent> Function(
    ModelRequest request,
    AgentCancellationToken cancellation,
  )?
  _streamFactory;
  int callCount = 0;

  @override
  Future<ModelProviderCapabilities> capabilities() async => capabilitiesValue;

  @override
  Stream<ModelEvent> stream(
    ModelRequest request,
    AgentCancellationToken cancellation,
  ) async* {
    callCount += 1;
    if (failure case final value?) {
      throw value;
    }
    final factory = _streamFactory;
    if (factory != null) {
      yield* factory(request, cancellation);
      return;
    }
    for (final event in eventsValue) {
      if (cancellation.isCancelled) {
        throw const ProviderFailure(
          kind: ProviderFailureKind.cancelled,
          message: 'cancelled',
          retryable: false,
          effectState: ModelEffectState.none,
        );
      }
      yield event;
    }
  }
}

Future<void> _expectFailure(
  Future<Object?> Function() action,
  ProviderFailureKind kind,
) async {
  try {
    await action();
  } on ProviderFailure catch (error) {
    _expect(
      error.kind == kind,
      'expected ${kind.name}, received ${error.kind.name}',
    );
    _expect(
      error.message.length <= 1024,
      'provider failures must expose bounded diagnostics',
    );
    return;
  }
  throw StateError('expected ProviderFailure(${kind.name})');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
