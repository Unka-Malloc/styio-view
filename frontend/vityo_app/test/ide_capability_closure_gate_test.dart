import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('IDE capability closure gate accepts framework with explicit TODOs', () {
    final snapshot = const VityoIdeCapabilityFramework().snapshot();
    final report = const IdeCapabilityClosureGate().evaluate(snapshot);
    final json = report.toJson();

    expect(report.isFrameworkClosed, isTrue);
    expect(report.hasHardFailures, isFalse);
    expect(report.missingRequiredCapabilityIds, isEmpty);
    expect(report.dependencyGaps, isEmpty);
    expect(report.duplicateCapabilityIds, isEmpty);
    expect(report.todoItems, isNotEmpty);
    expect(
      report.todoItems.every((item) => item.todo.startsWith('TODO:')),
      isTrue,
    );
    expect(report.readyItems, isNotEmpty);
    expect(report.failedItems, isEmpty);
    expect(json['isFrameworkClosed'], isTrue);
    expect(
      json['severityCounts'],
      containsPair(IdeCapabilityClosureSeverity.todo.wireValue, greaterThan(0)),
    );
  });

  test('IDE capability closure gate fails missing required capabilities', () {
    final snapshot = const VityoIdeCapabilityFramework().snapshot();
    final reducedSnapshot = IdeCapabilityFrameworkSnapshot(
      version: 'missing-required-test',
      entries: snapshot.entries
          .where((entry) => entry.id != 'agent.coding-loop')
          .toList(growable: false),
    );

    final report = const IdeCapabilityClosureGate().evaluate(reducedSnapshot);

    expect(report.isFrameworkClosed, isFalse);
    expect(report.missingRequiredCapabilityIds, contains('agent.coding-loop'));
    expect(
      report.failedItems.map((item) => item.capabilityId),
      contains('agent.coding-loop'),
    );
  });

  test(
    'IDE capability closure gate fails deferred capability without TODO',
    () {
      const snapshot = IdeCapabilityFrameworkSnapshot(
        version: 'missing-todo-test',
        entries: <IdeCapabilityDescriptor>[
          IdeCapabilityDescriptor(
            id: 'foundation.datastore',
            layer: IdeCapabilityLayer.foundation,
            title: 'DataStore ownership and persistence',
            status: IdeCapabilityStatus.scaffolded,
            ownerPath: 'lib/src/view_ide/foundation/datastore',
          ),
        ],
      );

      final report = const IdeCapabilityClosureGate().evaluate(snapshot);

      final datastoreFailure = report.failedItems.singleWhere(
        (item) => item.capabilityId == 'foundation.datastore',
      );

      expect(report.isFrameworkClosed, isFalse);
      expect(datastoreFailure.reason, contains('TODO marker'));
    },
  );
}
