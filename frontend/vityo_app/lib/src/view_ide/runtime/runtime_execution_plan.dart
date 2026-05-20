import 'runtime_task_lifecycle.dart';

enum RuntimeExecutionPlanStatus {
  ready,
  blockedUnrunnable,
  blockedMissingDependency,
}

extension RuntimeExecutionPlanStatusX on RuntimeExecutionPlanStatus {
  String get wireValue => switch (this) {
    RuntimeExecutionPlanStatus.ready => 'ready',
    RuntimeExecutionPlanStatus.blockedUnrunnable => 'blocked-unrunnable',
    RuntimeExecutionPlanStatus.blockedMissingDependency =>
      'blocked-missing-dependency',
  };
}

class RuntimeExecutionPlan {
  const RuntimeExecutionPlan({
    required this.definition,
    required this.status,
    required this.message,
    this.executionOrder = const <String>[],
    this.missingDependencies = const <String>[],
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  factory RuntimeExecutionPlan.fromJson(Map<String, Object?> json) {
    final definition = json['definition'];
    return RuntimeExecutionPlan(
      definition: definition is Map<String, Object?>
          ? RuntimeTaskDefinition.fromJson(definition)
          : definition is Map
          ? RuntimeTaskDefinition.fromJson(
              definition.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const RuntimeTaskDefinition(
              id: '',
              label: '',
              kind: RuntimeTaskKind.shell,
              command: '',
            ),
      status: _planStatusFromWire(json['status']),
      message: json['message'] as String? ?? '',
      executionOrder: _jsonStringList(json['executionOrder']),
      missingDependencies: _jsonStringList(json['missingDependencies']),
      metadata: _jsonObjectMap(json['metadata']),
      todo: json['todo'] as String? ?? '',
    );
  }

  final RuntimeTaskDefinition definition;
  final RuntimeExecutionPlanStatus status;
  final String message;
  final List<String> executionOrder;
  final List<String> missingDependencies;
  final Map<String, Object?> metadata;
  final String todo;

  bool get ready => status == RuntimeExecutionPlanStatus.ready;

  RuntimeTaskSnapshot applyTo(RuntimeTaskLifecycleController controller) {
    controller.register(definition);
    if (ready) {
      return controller.queue(definition.id, message: message);
    }
    return controller.block(
      definition.id,
      message: message,
      metadata: <String, Object?>{
        'planStatus': status.wireValue,
        if (missingDependencies.isNotEmpty)
          'missingDependencies': missingDependencies,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'definition': definition.toJson(),
      'status': status.wireValue,
      'message': message,
      'ready': ready,
      'executionOrder': executionOrder,
      'missingDependencies': missingDependencies,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class RuntimeExecutionPlanner {
  const RuntimeExecutionPlanner();

  RuntimeExecutionPlan plan({
    required RuntimeTaskDefinition definition,
    Iterable<RuntimeTaskDefinition> availableDefinitions =
        const <RuntimeTaskDefinition>[],
  }) {
    if (!definition.runnable) {
      return RuntimeExecutionPlan(
        definition: definition,
        status: RuntimeExecutionPlanStatus.blockedUnrunnable,
        message: 'Task ${definition.id} is blocked because it has no command.',
      );
    }
    final availableIds = <String>{
      definition.id,
      for (final available in availableDefinitions) available.id,
    };
    final missingDependencies = definition.dependsOn
        .where((dependencyId) => !availableIds.contains(dependencyId))
        .toList(growable: false);
    if (missingDependencies.isNotEmpty) {
      return RuntimeExecutionPlan(
        definition: definition,
        status: RuntimeExecutionPlanStatus.blockedMissingDependency,
        message:
            'Task ${definition.id} is blocked by missing dependencies: ${missingDependencies.join(', ')}.',
        missingDependencies: missingDependencies,
      );
    }
    return RuntimeExecutionPlan(
      definition: definition,
      status: RuntimeExecutionPlanStatus.ready,
      message: 'Task ${definition.id} is ready to run.',
      executionOrder: <String>[...definition.dependsOn, definition.id],
      todo:
          'TODO: hand ready plans to the shell/toolchain execution manager and attach output streams.',
    );
  }
}

RuntimeExecutionPlanStatus _planStatusFromWire(Object? value) {
  return switch (value) {
    'ready' => RuntimeExecutionPlanStatus.ready,
    'blocked-unrunnable' => RuntimeExecutionPlanStatus.blockedUnrunnable,
    'blocked-missing-dependency' =>
      RuntimeExecutionPlanStatus.blockedMissingDependency,
    _ => RuntimeExecutionPlanStatus.blockedUnrunnable,
  };
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}
