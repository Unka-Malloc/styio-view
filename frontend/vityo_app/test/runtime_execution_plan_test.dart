import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('runtime execution planner creates ready dependency order', () {
    const configure = RuntimeTaskDefinition(
      id: 'configure',
      label: 'Configure',
      kind: RuntimeTaskKind.build,
      command: 'cmake',
    );
    const build = RuntimeTaskDefinition(
      id: 'build',
      label: 'Build',
      kind: RuntimeTaskKind.build,
      command: 'cmake',
      arguments: <String>['--build', 'build'],
      dependsOn: <String>['configure'],
    );
    final plan = const RuntimeExecutionPlanner().plan(
      definition: build,
      availableDefinitions: const <RuntimeTaskDefinition>[configure],
    );
    final restored = RuntimeExecutionPlan.fromJson(plan.toJson());

    expect(plan.status, RuntimeExecutionPlanStatus.ready);
    expect(plan.executionOrder, <String>['configure', 'build']);
    expect(restored.ready, isTrue);
    expect(restored.executionOrder, <String>['configure', 'build']);
  });

  test(
    'runtime execution plan applies blocked state to lifecycle controller',
    () {
      final controller = RuntimeTaskLifecycleController(
        clock: () => DateTime.utc(2026, 5, 20),
      );
      const definition = RuntimeTaskDefinition(
        id: 'test',
        label: 'Test',
        kind: RuntimeTaskKind.test,
        command: 'ctest',
        dependsOn: <String>['build'],
      );

      final plan = const RuntimeExecutionPlanner().plan(definition: definition);
      final snapshot = plan.applyTo(controller);

      expect(plan.status, RuntimeExecutionPlanStatus.blockedMissingDependency);
      expect(snapshot.status, RuntimeTaskStatus.blocked);
      expect(
        snapshot.events.last.metadata['planStatus'],
        'blocked-missing-dependency',
      );
      expect(snapshot.events.last.metadata['missingDependencies'], <String>[
        'build',
      ]);
    },
  );

  test('runtime execution planner blocks unrunnable definitions', () {
    const definition = RuntimeTaskDefinition(
      id: 'missing-command',
      label: 'Missing command',
      kind: RuntimeTaskKind.shell,
      command: '',
    );

    final plan = const RuntimeExecutionPlanner().plan(definition: definition);

    expect(plan.ready, isFalse);
    expect(plan.status, RuntimeExecutionPlanStatus.blockedUnrunnable);
    expect(plan.toJson()['ready'], isFalse);
  });
}
