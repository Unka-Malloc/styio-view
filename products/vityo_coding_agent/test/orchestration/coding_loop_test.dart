import 'package:vityo_coding_agent/vityo_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  group('CodingPlan', () {
    test('selects prerequisite-ready steps in stable ID order', () {
      final plan = CodingPlan(
        taskId: 'task',
        steps: <CodingStep>[
          _step('20-second', ownedResource: 'lib/second.dart'),
          _step('10-first'),
          _step(
            '30-dependent',
            prerequisites: const <String>{'10-first'},
            ownedResource: 'lib/dependent.dart',
          ),
        ],
      );

      expect(plan.readySteps(const <String>{}).map((step) => step.id), <String>[
        '10-first',
        '20-second',
      ]);
      expect(
        plan.readySteps(const <String>{'10-first'}).map((step) => step.id),
        <String>['20-second', '30-dependent'],
      );
    });

    test('rejects cycles and unordered overlapping ownership', () {
      expect(
        () => CodingPlan(
          taskId: 'task',
          steps: <CodingStep>[
            _step('one', prerequisites: const <String>{'two'}),
            _step('two', prerequisites: const <String>{'one'}),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => CodingPlan(
          taskId: 'task',
          steps: <CodingStep>[_step('one'), _step('two')],
        ),
        throwsArgumentError,
      );
    });
  });

  group('ValidationPlanner', () {
    const planner = ValidationPlanner();
    final task = CodingTask(
      id: 'task',
      goal: 'focused validation',
      rootId: 'root',
      allowedResources: const <String>{'lib/main.dart', 'test/main_test.dart'},
      budget: const CodingLoopBudget(
        maxPlanSteps: 2,
        maxTransitions: 16,
        maxRepairsPerStep: 1,
        maxRepeatedFailures: 2,
        maxChangedResources: 2,
      ),
    );
    final changeSet = CodingChangeSet(
      id: 'change',
      stepId: 'step',
      baseWorkspaceRevision: 1,
      resources: const <CodingResourceReplacement>[
        CodingResourceReplacement(
          resource: 'lib/main.dart',
          baseDocumentRevision: 1,
          replacement: 'fixed',
        ),
      ],
    );

    test('orders focused validation requests deterministically', () {
      final requests = planner.plan(
        task: task,
        step: _step(
          'step',
          validations: const <CodingValidationTarget>[
            CodingValidationTarget(
              id: 'test-main',
              kind: CodingValidationKind.test,
              scope: 'test/main_test.dart',
            ),
            CodingValidationTarget(
              id: 'analyze-main',
              kind: CodingValidationKind.analyze,
              scope: 'lib/main.dart',
            ),
          ],
        ),
        changeSet: changeSet,
      );

      expect(requests.map((request) => request.id), <String>[
        'analyze-main',
        'test-main',
      ]);
    });

    test('rejects whole-workspace and unfocused analyze targets', () {
      for (final scope in <String>['.', 'lib/*.dart', 'test/main_test.dart']) {
        expect(
          () => planner.plan(
            task: task,
            step: _step(
              'step',
              validations: <CodingValidationTarget>[
                CodingValidationTarget(
                  id: 'invalid',
                  kind: CodingValidationKind.analyze,
                  scope: scope,
                ),
              ],
            ),
            changeSet: changeSet,
          ),
          throwsArgumentError,
        );
      }
    });

    test('bounds per-step validation fan-out', () {
      expect(
        () => planner.plan(
          task: task,
          step: _step(
            'step',
            validations: const <CodingValidationTarget>[
              CodingValidationTarget(
                id: 'analyze-main',
                kind: CodingValidationKind.analyze,
                scope: 'lib/main.dart',
              ),
              CodingValidationTarget(
                id: 'test-main',
                kind: CodingValidationKind.test,
                scope: 'test/main_test.dart',
              ),
              CodingValidationTarget(
                id: 'format-main',
                kind: CodingValidationKind.format,
                scope: 'lib/main.dart',
              ),
            ],
          ),
          changeSet: changeSet,
        ),
        throwsArgumentError,
      );
    });
  });

  test('CodingTask rejects non-rooted resource scopes', () {
    for (final resource in <String>[
      '../secret',
      '/absolute/path',
      r'C:\absolute\path',
      'lib/*.dart',
      'lib//main.dart',
    ]) {
      expect(
        () => CodingTask(
          id: 'task',
          goal: 'stay in the controlled root',
          rootId: 'root',
          allowedResources: <String>{resource},
          budget: const CodingLoopBudget(
            maxPlanSteps: 1,
            maxTransitions: 1,
            maxRepairsPerStep: 0,
            maxRepeatedFailures: 1,
            maxChangedResources: 1,
          ),
        ),
        throwsArgumentError,
      );
    }
  });
}

CodingStep _step(
  String id, {
  Set<String> prerequisites = const <String>{},
  String ownedResource = 'lib/main.dart',
  List<CodingValidationTarget> validations = const <CodingValidationTarget>[
    CodingValidationTarget(
      id: 'analyze-main',
      kind: CodingValidationKind.analyze,
      scope: 'lib/main.dart',
    ),
  ],
}) => CodingStep(
  id: id,
  title: id,
  prerequisites: prerequisites,
  ownedResources: <String>{ownedResource},
  acceptanceCriteria: const <String>{'focused facts pass'},
  validations: validations,
);
