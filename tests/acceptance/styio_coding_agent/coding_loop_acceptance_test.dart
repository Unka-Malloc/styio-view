import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:styio_coding_agent/styio_coding_agent.dart';

Future<void> main() async {
  await _runsReferenceFixturesThroughReviewableTransactions();
  await _repairsFromRefreshedFactsAndStopsRepeatedFailure();
  await _surfacesConflictPermissionCapabilityAndValidationBlockers();
  await _honorsCancellationSteeringAndTransitionBudgets();
}

Future<void> _runsReferenceFixturesThroughReviewableTransactions() async {
  for (final fixtureName in <String>['bug_fix', 'refactor']) {
    final fixture = _loadFixture(fixtureName);
    final task = _taskFromFixture(fixture);
    final plan = _planFromFixture(fixture);
    final workspace = _FakeWorkspace.fromFixture(fixture);
    final planner = _ScriptedPlanner(
      plan: plan,
      scripts: _scriptsFromFixture(fixture),
    );
    final approval = _Approval(allowed: true);
    final outcome =
        await CodingLoop(
          planner: planner,
          workspace: workspace,
          approval: approval,
          steering: const _Steering(),
          validationPlanner: const ValidationPlanner(),
        ).run(
          task,
          CodingSessionContext(
            sessionId: 'session-$fixtureName',
            cancellation: AgentCancellationController().token,
          ),
        );

    _expect(
      outcome.status == CodingTaskStatus.completed &&
          outcome.blocker == null &&
          outcome.completedStepIds.length == plan.steps.length,
      '$fixtureName must complete every planned step',
    );
    _expect(
      workspace.previewed.length == plan.steps.length &&
          approval.reviewedPreviewIds.length == plan.steps.length &&
          workspace.committed.length == plan.steps.length,
      '$fixtureName must preview, review, and transactionally commit each step',
    );
    _expect(
      workspace.commitOrder.join(',') ==
          plan.steps.map((step) => step.id).join(','),
      '$fixtureName must respect deterministic prerequisite order',
    );
    _expect(
      workspace.observationCount >= plan.steps.length + 1 &&
          outcome.finalObservation?.workspaceRevision ==
              workspace.workspaceRevision,
      '$fixtureName must refresh host facts after edits',
    );
    _expect(
      outcome.validationReceipts.isNotEmpty &&
          outcome.validationReceipts.every(
            (receipt) =>
                receipt.outcome == CodingValidationOutcome.passed &&
                receipt.workspaceRevision > 0 &&
                receipt.provenance.isNotEmpty &&
                receipt.scope != '.' &&
                receipt.scope.isNotEmpty,
          ),
      '$fixtureName completion must be supported by focused revisioned facts',
    );
    _expect(
      outcome.transactionReceipts.every(
        (receipt) =>
            receipt.outcome == CodingTransactionOutcome.committed &&
            receipt.effectId.isNotEmpty,
      ),
      '$fixtureName must retain effect receipts',
    );
    final expected = Map<String, Object?>.from(fixture['expected']! as Map);
    for (final entry in expected.entries) {
      _expect(
        workspace.documents[entry.key] == entry.value,
        '$fixtureName final workspace fact differs for ${entry.key}',
      );
    }
  }
}

Future<void> _repairsFromRefreshedFactsAndStopsRepeatedFailure() async {
  final task = _task(
    id: 'repair',
    budget: const CodingLoopBudget(
      maxPlanSteps: 2,
      maxTransitions: 24,
      maxRepairsPerStep: 3,
      maxRepeatedFailures: 2,
      maxChangedResources: 2,
    ),
  );
  final step = _step(
    'fix',
    validations: const <CodingValidationTarget>[
      CodingValidationTarget(
        id: 'analyze-main',
        kind: CodingValidationKind.analyze,
        scope: 'lib/main.dart',
      ),
    ],
  );
  final plan = CodingPlan(taskId: task.id, steps: <CodingStep>[step]);
  final repairedWorkspace = _FakeWorkspace(
    documents: <String, String>{'lib/main.dart': 'old'},
  );
  final repaired =
      await CodingLoop(
        planner: _ScriptedPlanner(
          plan: plan,
          scripts: <String, List<Map<String, String>>>{
            'fix': <Map<String, String>>[
              <String, String>{'lib/main.dart': 'BROKEN first attempt'},
              <String, String>{'lib/main.dart': 'fixed after facts'},
            ],
          },
        ),
        workspace: repairedWorkspace,
        approval: _Approval(allowed: true),
        steering: const _Steering(),
        validationPlanner: const ValidationPlanner(),
      ).run(
        task,
        CodingSessionContext(
          sessionId: 'repair-session',
          cancellation: AgentCancellationController().token,
        ),
      );
  _expect(
    repaired.status == CodingTaskStatus.completed &&
        repaired.repairCount == 1 &&
        repairedWorkspace.committed.length == 2 &&
        repairedWorkspace.observationCount >= 3,
    'failed validation must repair from refreshed post-edit facts',
  );

  final repeatedWorkspace = _FakeWorkspace(
    documents: <String, String>{'lib/main.dart': 'old'},
    forcedValidationFingerprint: 'same-failure',
  );
  final repeated =
      await CodingLoop(
        planner: _ScriptedPlanner(
          plan: plan,
          scripts: <String, List<Map<String, String>>>{
            'fix': <Map<String, String>>[
              <String, String>{'lib/main.dart': 'BROKEN one'},
              <String, String>{'lib/main.dart': 'BROKEN two'},
              <String, String>{'lib/main.dart': 'BROKEN three'},
            ],
          },
        ),
        workspace: repeatedWorkspace,
        approval: _Approval(allowed: true),
        steering: const _Steering(),
        validationPlanner: const ValidationPlanner(),
      ).run(
        task,
        CodingSessionContext(
          sessionId: 'repeat-session',
          cancellation: AgentCancellationController().token,
        ),
      );
  _expect(
    repeated.status == CodingTaskStatus.blocked &&
        repeated.blocker?.code == CodingBlockerCode.repeatedFailure &&
        repeatedWorkspace.committed.length == 2,
    'identical failure fingerprints must trip the bounded loop guard',
  );
}

Future<void>
_surfacesConflictPermissionCapabilityAndValidationBlockers() async {
  final scenarios = <(String, _FakeWorkspace, _Approval, CodingBlockerCode)>[
    (
      'stale',
      _FakeWorkspace(
        documents: <String, String>{'lib/main.dart': 'old'},
        previewOverride: CodingTransactionOutcome.conflict,
      ),
      _Approval(allowed: true),
      CodingBlockerCode.staleRevision,
    ),
    (
      'permission',
      _FakeWorkspace(documents: <String, String>{'lib/main.dart': 'old'}),
      _Approval(allowed: false),
      CodingBlockerCode.permissionDenied,
    ),
    (
      'capability',
      _FakeWorkspace(
        documents: <String, String>{'lib/main.dart': 'old'},
        previewOverride: CodingTransactionOutcome.capabilityUnavailable,
      ),
      _Approval(allowed: true),
      CodingBlockerCode.capabilityDenied,
    ),
  ];
  for (final scenario in scenarios) {
    final outcome = await _singleStepLoop(
      workspace: scenario.$2,
      approval: scenario.$3,
      replacement: 'fixed',
    );
    _expect(
      outcome.status == CodingTaskStatus.blocked &&
          outcome.blocker?.code == scenario.$4 &&
          scenario.$2.committed.isEmpty,
      '${scenario.$1} must block truthfully before mutation',
    );
  }

  final validationWorkspace = _FakeWorkspace(
    documents: <String, String>{'lib/main.dart': 'old'},
    forcedValidationFingerprint: 'always-fails',
  );
  final task = _task(
    id: 'validation-limit',
    budget: const CodingLoopBudget(
      maxPlanSteps: 2,
      maxTransitions: 24,
      maxRepairsPerStep: 1,
      maxRepeatedFailures: 5,
      maxChangedResources: 2,
    ),
  );
  final step = _step(
    'fix',
    validations: const <CodingValidationTarget>[
      CodingValidationTarget(
        id: 'analyze-main',
        kind: CodingValidationKind.analyze,
        scope: 'lib/main.dart',
      ),
    ],
  );
  final failed =
      await CodingLoop(
        planner: _ScriptedPlanner(
          plan: CodingPlan(taskId: task.id, steps: <CodingStep>[step]),
          scripts: <String, List<Map<String, String>>>{
            'fix': <Map<String, String>>[
              <String, String>{'lib/main.dart': 'BROKEN one'},
              <String, String>{'lib/main.dart': 'BROKEN two'},
            ],
          },
        ),
        workspace: validationWorkspace,
        approval: _Approval(allowed: true),
        steering: const _Steering(),
        validationPlanner: const ValidationPlanner(),
      ).run(
        task,
        CodingSessionContext(
          sessionId: 'validation-session',
          cancellation: AgentCancellationController().token,
        ),
      );
  _expect(
    failed.blocker?.code == CodingBlockerCode.validationFailed &&
        failed.repairCount == 1,
    'validation failure must stop after the configured repair limit',
  );
}

Future<void> _honorsCancellationSteeringAndTransitionBudgets() async {
  final cancelledController = AgentCancellationController()..cancel();
  final cancelled = await _singleStepLoop(
    workspace: _FakeWorkspace(
      documents: <String, String>{'lib/main.dart': 'old'},
    ),
    approval: _Approval(allowed: true),
    replacement: 'fixed',
    cancellation: cancelledController.token,
  );
  _expect(
    cancelled.status == CodingTaskStatus.cancelled &&
        cancelled.transactionReceipts.isEmpty,
    'pre-cancelled task must not produce effects',
  );

  final steeredWorkspace = _FakeWorkspace(
    documents: <String, String>{'lib/main.dart': 'old'},
  );
  final steered = await _singleStepLoop(
    workspace: steeredWorkspace,
    approval: _Approval(allowed: true),
    replacement: 'fixed',
    steering: _Steering(
      directives: <CodingSteeringDirective>[
        const CodingSteeringDirective.block('user changed direction'),
      ],
    ),
  );
  _expect(
    steered.blocker?.code == CodingBlockerCode.steered &&
        steeredWorkspace.previewed.isEmpty,
    'user steering must be observed between transitions before effects',
  );

  final budgetWorkspace = _FakeWorkspace(
    documents: <String, String>{'lib/main.dart': 'old'},
  );
  final budgeted = await _singleStepLoop(
    workspace: budgetWorkspace,
    approval: _Approval(allowed: true),
    replacement: 'fixed',
    budget: const CodingLoopBudget(
      maxPlanSteps: 2,
      maxTransitions: 1,
      maxRepairsPerStep: 0,
      maxRepeatedFailures: 1,
      maxChangedResources: 2,
    ),
  );
  _expect(
    budgeted.blocker?.code == CodingBlockerCode.budgetExceeded &&
        budgetWorkspace.committed.isEmpty,
    'transition budget must terminate before unbounded work',
  );
}

Future<CodingTaskOutcome> _singleStepLoop({
  required _FakeWorkspace workspace,
  required _Approval approval,
  required String replacement,
  AgentCancellationToken? cancellation,
  CodingSteeringPort steering = const _Steering(),
  CodingLoopBudget budget = const CodingLoopBudget(
    maxPlanSteps: 2,
    maxTransitions: 16,
    maxRepairsPerStep: 0,
    maxRepeatedFailures: 2,
    maxChangedResources: 2,
  ),
}) {
  final task = _task(id: 'single', budget: budget);
  final step = _step('fix');
  return CodingLoop(
    planner: _ScriptedPlanner(
      plan: CodingPlan(taskId: task.id, steps: <CodingStep>[step]),
      scripts: <String, List<Map<String, String>>>{
        'fix': <Map<String, String>>[
          <String, String>{'lib/main.dart': replacement},
        ],
      },
    ),
    workspace: workspace,
    approval: approval,
    steering: steering,
    validationPlanner: const ValidationPlanner(),
  ).run(
    task,
    CodingSessionContext(
      sessionId: 'single-session',
      cancellation: cancellation ?? AgentCancellationController().token,
    ),
  );
}

CodingTask _task({required String id, required CodingLoopBudget budget}) =>
    CodingTask(
      id: id,
      goal: 'Fix the synthetic fixture',
      rootId: 'root',
      allowedResources: const <String>{'lib/main.dart', 'test/main_test.dart'},
      budget: budget,
    );

CodingStep _step(
  String id, {
  Set<String> prerequisites = const <String>{},
  List<CodingValidationTarget> validations = const <CodingValidationTarget>[
    CodingValidationTarget(
      id: 'analyze-main',
      kind: CodingValidationKind.analyze,
      scope: 'lib/main.dart',
    ),
  ],
}) => CodingStep(
  id: id,
  title: 'Synthetic $id',
  prerequisites: prerequisites,
  ownedResources: const <String>{'lib/main.dart'},
  acceptanceCriteria: const <String>{'focused validation passes'},
  validations: validations,
);

Map<String, Object?> _loadFixture(String name) => Map<String, Object?>.from(
  jsonDecode(File('fixtures/coding_tasks/$name.json').readAsStringSync())
      as Map,
);

CodingTask _taskFromFixture(Map<String, Object?> fixture) => CodingTask(
  id: fixture['id']! as String,
  goal: fixture['goal']! as String,
  rootId: 'root',
  allowedResources: Set<String>.from(fixture['allowedResources']! as List),
  budget: const CodingLoopBudget(
    maxPlanSteps: 8,
    maxTransitions: 48,
    maxRepairsPerStep: 2,
    maxRepeatedFailures: 2,
    maxChangedResources: 4,
  ),
);

CodingPlan _planFromFixture(Map<String, Object?> fixture) => CodingPlan(
  taskId: fixture['id']! as String,
  steps: <CodingStep>[
    for (final raw in fixture['steps']! as List)
      CodingStep(
        id: (raw as Map)['id']! as String,
        title: raw['title']! as String,
        prerequisites: Set<String>.from(raw['prerequisites']! as List),
        ownedResources: Set<String>.from(raw['ownedResources']! as List),
        acceptanceCriteria: Set<String>.from(
          raw['acceptanceCriteria']! as List,
        ),
        validations: <CodingValidationTarget>[
          for (final target in raw['validations']! as List)
            CodingValidationTarget(
              id: (target as Map)['id']! as String,
              kind: CodingValidationKind.values.byName(
                target['kind']! as String,
              ),
              scope: target['scope']! as String,
            ),
        ],
      ),
  ],
);

Map<String, List<Map<String, String>>> _scriptsFromFixture(
  Map<String, Object?> fixture,
) => <String, List<Map<String, String>>>{
  for (final raw in fixture['steps']! as List)
    (raw as Map)['id']! as String: <Map<String, String>>[
      Map<String, String>.from(raw['replacement']! as Map),
    ],
};

final class _ScriptedPlanner implements CodingPlanner {
  _ScriptedPlanner({
    required this.plan,
    required Map<String, List<Map<String, String>>> scripts,
  }) : _scripts = <String, Queue<Map<String, String>>>{
         for (final entry in scripts.entries)
           entry.key: Queue<Map<String, String>>.of(entry.value),
       };

  final CodingPlan plan;
  final Map<String, Queue<Map<String, String>>> _scripts;

  @override
  Future<CodingPlan> createPlan(
    CodingTask task,
    CodingObservation observation,
    AgentCancellationToken cancellation,
  ) async => plan;

  @override
  Future<CodingStepAction> propose(
    CodingTask task,
    CodingPlan plan,
    CodingStep step,
    CodingObservation observation,
    RepairFeedback? repair,
    AgentCancellationToken cancellation,
  ) async {
    final replacements = _scripts[step.id]!.removeFirst();
    return CodingStepAction(
      changeSet: CodingChangeSet(
        id: '${step.id}-${observation.workspaceRevision}-${repair?.attempt ?? 0}',
        stepId: step.id,
        baseWorkspaceRevision: observation.workspaceRevision,
        resources: <CodingResourceReplacement>[
          for (final entry in replacements.entries)
            CodingResourceReplacement(
              resource: entry.key,
              baseDocumentRevision: observation.documentRevisions[entry.key]!,
              replacement: entry.value,
            ),
        ],
      ),
    );
  }
}

final class _FakeWorkspace implements CodingWorkspacePort {
  _FakeWorkspace({
    required Map<String, String> documents,
    this.previewOverride,
    this.forcedValidationFingerprint,
  }) : documents = Map<String, String>.of(documents),
       documentRevisions = <String, int>{
         for (final resource in documents.keys) resource: 1,
       };

  factory _FakeWorkspace.fromFixture(Map<String, Object?> fixture) =>
      _FakeWorkspace(
        documents: Map<String, String>.from(fixture['initial']! as Map),
      );

  final Map<String, String> documents;
  final Map<String, int> documentRevisions;
  final CodingTransactionOutcome? previewOverride;
  final String? forcedValidationFingerprint;
  int workspaceRevision = 1;
  int observationCount = 0;
  int _sequence = 0;
  final List<CodingChangeSet> previewed = <CodingChangeSet>[];
  final List<CodingTransactionReceipt> committed = <CodingTransactionReceipt>[];
  final List<String> commitOrder = <String>[];
  final List<CodingValidationRequest> validationRequests =
      <CodingValidationRequest>[];
  final Map<String, CodingChangeSet> _prepared = <String, CodingChangeSet>{};

  @override
  Future<CodingObservation> observe(
    CodingTask task,
    AgentCancellationToken cancellation,
  ) async {
    observationCount += 1;
    return CodingObservation(
      workspaceRevision: workspaceRevision,
      documentRevisions: documentRevisions,
      facts: <String, Object?>{'documents': Map<String, String>.of(documents)},
      provenance: 'fixture-workspace',
    );
  }

  @override
  Future<CodingChangePreview> preview(
    CodingChangeSet changeSet,
    AgentCancellationToken cancellation,
  ) async {
    previewed.add(changeSet);
    final override = previewOverride;
    if (override != null) {
      return CodingChangePreview(
        id: 'preview-${++_sequence}',
        changeSet: changeSet,
        outcome: override,
      );
    }
    final stale =
        changeSet.baseWorkspaceRevision != workspaceRevision ||
        changeSet.resources.any(
          (resource) =>
              documentRevisions[resource.resource] !=
              resource.baseDocumentRevision,
        );
    final preview = CodingChangePreview(
      id: 'preview-${++_sequence}',
      changeSet: changeSet,
      outcome: stale
          ? CodingTransactionOutcome.conflict
          : CodingTransactionOutcome.ready,
    );
    if (!stale) _prepared[preview.id] = changeSet;
    return preview;
  }

  @override
  Future<CodingTransactionReceipt> commit(
    String previewId,
    AgentCancellationToken cancellation,
  ) async {
    final changeSet = _prepared.remove(previewId);
    if (changeSet == null) {
      return CodingTransactionReceipt(
        id: 'transaction-${++_sequence}',
        outcome: CodingTransactionOutcome.failed,
        workspaceRevision: workspaceRevision,
        effectId: '',
      );
    }
    for (final resource in changeSet.resources) {
      documents[resource.resource] = resource.replacement;
      documentRevisions[resource.resource] =
          documentRevisions[resource.resource]! + 1;
    }
    workspaceRevision += 1;
    commitOrder.add(changeSet.stepId);
    final receipt = CodingTransactionReceipt(
      id: 'transaction-${++_sequence}',
      outcome: CodingTransactionOutcome.committed,
      workspaceRevision: workspaceRevision,
      effectId: 'effect-${changeSet.id}',
    );
    committed.add(receipt);
    return receipt;
  }

  @override
  Future<CodingValidationReceipt> validate(
    CodingValidationRequest request,
    int expectedWorkspaceRevision,
    AgentCancellationToken cancellation,
  ) async {
    validationRequests.add(request);
    final passed =
        expectedWorkspaceRevision == workspaceRevision &&
        !documents.values.any((content) => content.contains('BROKEN')) &&
        forcedValidationFingerprint == null;
    return CodingValidationReceipt(
      id: 'validation-${++_sequence}',
      kind: request.kind,
      scope: request.scope,
      workspaceRevision: workspaceRevision,
      outcome: passed
          ? CodingValidationOutcome.passed
          : CodingValidationOutcome.failed,
      fingerprint:
          forcedValidationFingerprint ??
          '${request.kind.name}:${request.scope}:$workspaceRevision:$passed',
      provenance: 'fixture-validator',
    );
  }
}

final class _Approval implements CodingApprovalPort {
  _Approval({required this.allowed});

  final bool allowed;
  final List<String> reviewedPreviewIds = <String>[];

  @override
  Future<bool> approve(
    CodingChangePreview preview,
    AgentCancellationToken cancellation,
  ) async {
    reviewedPreviewIds.add(preview.id);
    return allowed;
  }
}

final class _Steering implements CodingSteeringPort {
  const _Steering({
    List<CodingSteeringDirective> directives =
        const <CodingSteeringDirective>[],
  }) : _directives = directives;

  final List<CodingSteeringDirective> _directives;

  @override
  Future<CodingSteeringDirective> poll(String taskId) async =>
      _directives.isEmpty
      ? const CodingSteeringDirective.continueTask()
      : _directives.first;
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
