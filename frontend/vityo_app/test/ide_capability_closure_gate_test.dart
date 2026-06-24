import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('IDE capability closure gate accepts framework with explicit TODOs', () {
    final snapshot = const VityoIdeCapabilityFramework().snapshot();
    final report = const IdeCapabilityClosureGate().evaluate(snapshot);
    final json = report.toJson();

    expect(report.isFrameworkClosed, isTrue);
    expect(report.isRuntimeMature, isFalse);
    expect(report.isRuntimeContractMature, isTrue);
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
    expect(json['isRuntimeMature'], isFalse);
    expect(json['isRuntimeContractMature'], isTrue);
    expect(report.nonBlockingTodoCapabilityIds, contains('runtime.execution'));
    expect(
      report.runtimeMaturityBlockerCapabilityIds,
      isNot(contains('runtime.execution')),
    );
    expect(
      json['severityCounts'],
      containsPair(IdeCapabilityClosureSeverity.todo.wireValue, greaterThan(0)),
    );
  });

  test('IDE capability closure gate separates detail TODOs from blockers', () {
    final baseSnapshot = const VityoIdeCapabilityFramework().snapshot();
    final snapshot = IdeCapabilityFrameworkSnapshot(
      version: 'detail-todo-test',
      entries: <IdeCapabilityDescriptor>[
        for (final entry in baseSnapshot.entries)
          IdeCapabilityDescriptor(
            id: entry.id,
            layer: entry.layer,
            title: entry.title,
            status: entry.status,
            ownerPath: entry.ownerPath,
            summary: entry.summary,
            todo: entry.todo,
            runtimeMaturityBlocking: entry.needsFollowUp ? false : null,
            references: entry.references,
            dependencies: entry.dependencies,
          ),
      ],
    );

    final report = const IdeCapabilityClosureGate().evaluate(snapshot);
    final json = report.toJson();

    expect(report.isFrameworkClosed, isTrue);
    expect(report.isRuntimeMature, isFalse);
    expect(report.isRuntimeContractMature, isTrue);
    expect(report.todoCapabilityIds, isNotEmpty);
    expect(report.nonBlockingTodoCapabilityIds, contains('runtime.execution'));
    expect(report.runtimeMaturityBlockingTodoCapabilityIds, isEmpty);
    expect(report.runtimeMaturityBlockerCapabilityIds, isEmpty);
    expect(json['isRuntimeContractMature'], isTrue);
    expect(json['nonBlockingTodoCapabilityIds'], contains('runtime.execution'));
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
