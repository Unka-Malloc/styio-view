import 'ide_capability_framework.dart';

enum IdeCapabilityClosureSeverity { ready, todo, fail }

extension IdeCapabilityClosureSeverityX on IdeCapabilityClosureSeverity {
  String get wireValue {
    return switch (this) {
      IdeCapabilityClosureSeverity.ready => 'ready',
      IdeCapabilityClosureSeverity.todo => 'todo',
      IdeCapabilityClosureSeverity.fail => 'fail',
    };
  }
}

class IdeCapabilityDependencyGap {
  const IdeCapabilityDependencyGap({
    required this.capabilityId,
    required this.missingDependencyId,
  });

  final String capabilityId;
  final String missingDependencyId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capabilityId': capabilityId,
      'missingDependencyId': missingDependencyId,
    };
  }
}

class IdeCapabilityClosureItem {
  const IdeCapabilityClosureItem({
    required this.capabilityId,
    required this.layer,
    required this.title,
    required this.status,
    required this.severity,
    required this.ownerPath,
    required this.reason,
    required this.blocksRuntimeMaturity,
    this.todo = '',
  });

  final String capabilityId;
  final IdeCapabilityLayer layer;
  final String title;
  final IdeCapabilityStatus status;
  final IdeCapabilityClosureSeverity severity;
  final String ownerPath;
  final String reason;
  final bool blocksRuntimeMaturity;
  final String todo;

  bool get isHardFailure => severity == IdeCapabilityClosureSeverity.fail;
  bool get isFollowUp => severity == IdeCapabilityClosureSeverity.todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capabilityId': capabilityId,
      'layer': layer.wireValue,
      'title': title,
      'status': status.wireValue,
      'severity': severity.wireValue,
      'ownerPath': ownerPath,
      'reason': reason,
      'blocksRuntimeMaturity': blocksRuntimeMaturity,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class IdeCapabilityClosureReport {
  const IdeCapabilityClosureReport({
    required this.version,
    required this.items,
    required this.missingRequiredCapabilityIds,
    required this.dependencyGaps,
    required this.duplicateCapabilityIds,
  });

  final String version;
  final List<IdeCapabilityClosureItem> items;
  final List<String> missingRequiredCapabilityIds;
  final List<IdeCapabilityDependencyGap> dependencyGaps;
  final List<String> duplicateCapabilityIds;

  Iterable<IdeCapabilityClosureItem> get readyItems {
    return items.where(
      (item) => item.severity == IdeCapabilityClosureSeverity.ready,
    );
  }

  Iterable<IdeCapabilityClosureItem> get todoItems {
    return items.where((item) => item.isFollowUp);
  }

  Iterable<IdeCapabilityClosureItem> get failedItems {
    return items.where((item) => item.isHardFailure);
  }

  int get readyCount => readyItems.length;
  int get todoCount => todoItems.length;
  int get failedCount => failedItems.length;

  int get hardFailureCount {
    return failedCount +
        missingRequiredCapabilityIds.length +
        dependencyGaps.length +
        duplicateCapabilityIds.length;
  }

  List<String> get todoCapabilityIds {
    return todoItems.map((item) => item.capabilityId).toList(growable: false);
  }

  List<String> get runtimeMaturityBlockingTodoCapabilityIds {
    final ids = todoItems
        .where((item) => item.blocksRuntimeMaturity)
        .map((item) => item.capabilityId)
        .toList(growable: false);
    ids.sort();
    return List<String>.unmodifiable(ids);
  }

  List<String> get nonBlockingTodoCapabilityIds {
    final ids = todoItems
        .where((item) => !item.blocksRuntimeMaturity)
        .map((item) => item.capabilityId)
        .toList(growable: false);
    ids.sort();
    return List<String>.unmodifiable(ids);
  }

  List<String> get failedCapabilityIds {
    return failedItems
        .map((item) => item.capabilityId)
        .toList(growable: false);
  }

  List<String> get runtimeMaturityBlockerCapabilityIds {
    final ids = <String>{
      ...runtimeMaturityBlockingTodoCapabilityIds,
      ...failedCapabilityIds,
      ...missingRequiredCapabilityIds,
      for (final gap in dependencyGaps) gap.capabilityId,
      ...duplicateCapabilityIds,
    }.toList(growable: false);
    ids.sort();
    return List<String>.unmodifiable(ids);
  }

  bool get hasHardFailures {
    return failedItems.isNotEmpty ||
        missingRequiredCapabilityIds.isNotEmpty ||
        dependencyGaps.isNotEmpty ||
        duplicateCapabilityIds.isNotEmpty;
  }

  bool get isFrameworkClosed => !hasHardFailures;
  bool get isRuntimeMature => isFrameworkClosed && todoItems.isEmpty;
  bool get isRuntimeContractMature {
    return isFrameworkClosed && runtimeMaturityBlockerCapabilityIds.isEmpty;
  }

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in IdeCapabilityClosureSeverity.values)
        severity.wireValue: items
            .where((item) => item.severity == severity)
            .length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'isFrameworkClosed': isFrameworkClosed,
      'isRuntimeMature': isRuntimeMature,
      'isRuntimeContractMature': isRuntimeContractMature,
      'readyCount': readyCount,
      'todoCount': todoCount,
      'failedCount': failedCount,
      'hardFailureCount': hardFailureCount,
      'severityCounts': severityCounts,
      'todoCapabilityIds': todoCapabilityIds,
      'runtimeMaturityBlockingTodoCapabilityIds':
          runtimeMaturityBlockingTodoCapabilityIds,
      'nonBlockingTodoCapabilityIds': nonBlockingTodoCapabilityIds,
      'failedCapabilityIds': failedCapabilityIds,
      'runtimeMaturityBlockerCapabilityIds':
          runtimeMaturityBlockerCapabilityIds,
      'missingRequiredCapabilityIds': missingRequiredCapabilityIds,
      'duplicateCapabilityIds': duplicateCapabilityIds,
      'dependencyGaps': dependencyGaps
          .map((gap) => gap.toJson())
          .toList(growable: false),
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }
}

class IdeCapabilityClosureGate {
  const IdeCapabilityClosureGate();

  IdeCapabilityClosureReport evaluate(IdeCapabilityFrameworkSnapshot snapshot) {
    final capabilityIds = <String>{};
    final duplicateCapabilityIds = <String>{};

    for (final entry in snapshot.entries) {
      if (!capabilityIds.add(entry.id)) {
        duplicateCapabilityIds.add(entry.id);
      }
    }

    final dependencyGaps = <IdeCapabilityDependencyGap>[
      for (final entry in snapshot.entries)
        for (final dependencyId in entry.dependencies)
          if (!capabilityIds.contains(dependencyId))
            IdeCapabilityDependencyGap(
              capabilityId: entry.id,
              missingDependencyId: dependencyId,
            ),
    ];

    final missingRequiredCapabilityIds = snapshot.missingRequiredCapabilityIds
        .toList(growable: false);

    final items = <IdeCapabilityClosureItem>[
      for (final entry in snapshot.entries)
        _evaluateEntry(
          entry,
          dependencyGaps
              .where((gap) => gap.capabilityId == entry.id)
              .toList(growable: false),
          duplicateCapabilityIds.contains(entry.id),
        ),
      for (final missingId in missingRequiredCapabilityIds)
        IdeCapabilityClosureItem(
          capabilityId: missingId,
          layer: IdeCapabilityLayer.foundation,
          title: 'Missing required capability',
          status: IdeCapabilityStatus.todo,
          severity: IdeCapabilityClosureSeverity.fail,
          ownerPath: '',
          reason: 'Required capability is not declared in the framework.',
          blocksRuntimeMaturity: true,
          todo: 'TODO: add this required IDE capability to the framework.',
        ),
    ];

    return IdeCapabilityClosureReport(
      version: '${snapshot.version}-closure-gate-v1',
      items: items,
      missingRequiredCapabilityIds: missingRequiredCapabilityIds,
      dependencyGaps: dependencyGaps,
      duplicateCapabilityIds: duplicateCapabilityIds.toList(growable: false),
    );
  }

  IdeCapabilityClosureItem _evaluateEntry(
    IdeCapabilityDescriptor entry,
    List<IdeCapabilityDependencyGap> dependencyGaps,
    bool duplicated,
  ) {
    if (duplicated) {
      return _fail(entry, 'Capability id is declared more than once.');
    }

    if (entry.ownerPath.trim().isEmpty) {
      return _fail(entry, 'Capability owner path is missing.');
    }

    if (dependencyGaps.isNotEmpty) {
      final missingIds = dependencyGaps
          .map((gap) => gap.missingDependencyId)
          .join(', ');
      return _fail(entry, 'Missing dependency capability: $missingIds.');
    }

    if (entry.status == IdeCapabilityStatus.todo ||
        entry.status == IdeCapabilityStatus.scaffolded) {
      if (!entry.todo.startsWith('TODO:')) {
        return _fail(
          entry,
          'Non-ready capability must keep an explicit TODO marker.',
        );
      }

      return IdeCapabilityClosureItem(
        capabilityId: entry.id,
        layer: entry.layer,
        title: entry.title,
        status: entry.status,
        severity: IdeCapabilityClosureSeverity.todo,
        ownerPath: entry.ownerPath,
        reason: 'Framework slot exists and implementation detail is deferred.',
        blocksRuntimeMaturity: entry.blocksRuntimeMaturity,
        todo: entry.todo,
      );
    }

    return IdeCapabilityClosureItem(
      capabilityId: entry.id,
      layer: entry.layer,
      title: entry.title,
      status: entry.status,
      severity: IdeCapabilityClosureSeverity.ready,
      ownerPath: entry.ownerPath,
      reason: 'Capability is declared and wired to an owner path.',
      blocksRuntimeMaturity: false,
      todo: entry.todo,
    );
  }

  IdeCapabilityClosureItem _fail(IdeCapabilityDescriptor entry, String reason) {
    return IdeCapabilityClosureItem(
      capabilityId: entry.id,
      layer: entry.layer,
      title: entry.title,
      status: entry.status,
      severity: IdeCapabilityClosureSeverity.fail,
      ownerPath: entry.ownerPath,
      reason: reason,
      blocksRuntimeMaturity: true,
      todo: entry.todo,
    );
  }
}

// ---------------------------------------------------------------------------
// Agent-safe capability projection -- strips runtime values, keeps only
// metadata suitable for agent context consumption.
// ---------------------------------------------------------------------------

/// An agent-safe projection of a capability item.
///
/// Strips implementation detail and runtime values; keeps only the metadata
/// that is safe and useful for agent context (capability existence, status,
/// blocking facts, owner path, TODO markers).
class IdeCapabilityAgentSafeProjection {
  const IdeCapabilityAgentSafeProjection({
    required this.capabilityId,
    required this.layer,
    required this.title,
    required this.status,
    required this.isBlocking,
    required this.ownerPath,
  });

  final String capabilityId;
  final String layer;
  final String title;
  final String status;
  final bool isBlocking;
  final String ownerPath;

  /// Serializes to a plain metadata-only map suitable for agent context.
  /// No runtime values, no internal paths beyond owner directory, no secrets.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capabilityId': capabilityId,
      'layer': layer,
      'title': title,
      'status': status,
      'isBlocking': isBlocking,
      'ownerPath': ownerPath,
    };
  }
}

/// Produces an agent-safe projection of the closure report.
///
/// The projection excludes internal diagnostic detail, implementation paths,
/// and raw payloads. Only capability ids, statuses, blocking facts, and
/// owner-layer metadata are included.
class IdeCapabilityAgentSafeProjector {
  const IdeCapabilityAgentSafeProjector();

  /// Project [report] into a list of agent-safe items suitable for
  /// surfacing to agent context without leaking implementation internals.
  List<IdeCapabilityAgentSafeProjection> project(
    IdeCapabilityClosureReport report,
  ) {
    return report.items.map((item) {
      return IdeCapabilityAgentSafeProjection(
        capabilityId: item.capabilityId,
        layer: item.layer.wireValue,
        title: item.title,
        status: item.status.wireValue,
        isBlocking: item.blocksRuntimeMaturity,
        ownerPath: item.ownerPath,
      );
    }).toList(growable: false);
  }

  /// A single metadata-only summary map safe for passing into agent system
  /// context without leaking runtime values or sensitive paths.
  Map<String, Object?> summarize(IdeCapabilityClosureReport report) {
    return <String, Object?>{
      'version': report.version,
      'readyCount': report.readyCount,
      'todoCount': report.todoCount,
      'failedCount': report.failedCount,
      'hardFailureCount': report.hardFailureCount,
      'isFrameworkClosed': report.isFrameworkClosed,
      'isRuntimeMature': report.isRuntimeMature,
      'blockingCapabilityIds': report.runtimeMaturityBlockerCapabilityIds,
      'nonBlockingTodoCapabilityIds': report.nonBlockingTodoCapabilityIds,
      'items': project(report).map((p) => p.toJson()).toList(growable: false),
    };
  }
}
