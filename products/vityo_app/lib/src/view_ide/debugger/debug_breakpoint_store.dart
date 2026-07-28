import '../foundation/foundation.dart';
import 'debug_launch_contract.dart';

class DebugBreakpointSet {
  const DebugBreakpointSet({
    required this.workspaceId,
    this.breakpoints = const <DebugLaunchBreakpoint>[],
    this.updatedAt,
  });

  factory DebugBreakpointSet.fromJson(Map<String, Object?> json) {
    return DebugBreakpointSet(
      workspaceId: json['workspaceId'] as String? ?? '',
      breakpoints: _jsonBreakpoints(json['breakpoints']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<DebugLaunchBreakpoint> breakpoints;
  final DateTime? updatedAt;

  List<DebugLaunchBreakpoint> breakpointsForFile(String filePath) {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      return const <DebugLaunchBreakpoint>[];
    }
    return breakpoints
        .where((breakpoint) => breakpoint.filePath == normalizedPath)
        .toList(growable: false);
  }

  DebugBreakpointSet replaceFileBreakpoints({
    required String filePath,
    required Iterable<DebugLaunchBreakpoint> breakpoints,
  }) {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      return this;
    }
    final nextBreakpoints = <DebugLaunchBreakpoint>[
      ...this.breakpoints.where(
        (breakpoint) => breakpoint.filePath != normalizedPath,
      ),
      ...breakpoints.map(
        (breakpoint) => DebugLaunchBreakpoint(
          filePath: normalizedPath,
          line: breakpoint.line,
          enabled: breakpoint.enabled,
        ),
      ),
    ];
    return copyWith(
      breakpoints: _normalizeBreakpoints(nextBreakpoints),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  DebugBreakpointSet upsertBreakpoint(DebugLaunchBreakpoint breakpoint) {
    final normalizedPath = breakpoint.filePath.trim();
    if (normalizedPath.isEmpty || breakpoint.line <= 0) {
      return this;
    }
    final nextBreakpoints = breakpoints
        .where(
          (existing) =>
              existing.filePath != normalizedPath ||
              existing.line != breakpoint.line,
        )
        .toList(growable: true);
    nextBreakpoints.add(
      DebugLaunchBreakpoint(
        filePath: normalizedPath,
        line: breakpoint.line,
        enabled: breakpoint.enabled,
      ),
    );
    return copyWith(
      breakpoints: _normalizeBreakpoints(nextBreakpoints),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  DebugBreakpointSet removeBreakpoint({
    required String filePath,
    required int line,
  }) {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty || line <= 0) {
      return this;
    }
    return copyWith(
      breakpoints: _normalizeBreakpoints(
        breakpoints.where(
          (breakpoint) =>
              breakpoint.filePath != normalizedPath || breakpoint.line != line,
        ),
      ),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  DebugBreakpointSet copyWith({
    String? workspaceId,
    List<DebugLaunchBreakpoint>? breakpoints,
    DateTime? updatedAt,
  }) {
    return DebugBreakpointSet(
      workspaceId: workspaceId ?? this.workspaceId,
      breakpoints: breakpoints == null
          ? this.breakpoints
          : _normalizeBreakpoints(breakpoints),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'breakpointCount': breakpoints.length,
      'breakpoints': breakpoints
          .map((breakpoint) => breakpoint.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class DebugBreakpointStore {
  DebugBreakpointStore.fromDataStore({required FoundationDataStore dataStore})
    : this(
        owner: FoundationDataStoreOwner(
          descriptor: const FoundationDataStoreOwnerDescriptor(
            ownerId: 'debug.breakpoints',
            layer: 'debugger',
            stateFamily: 'breakpoints',
            allowedNamespaces: <String>{_namespaceName},
          ),
          dataStore: dataStore,
        ),
      );

  const DebugBreakpointStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'debug.breakpoints';
  static const String _key = 'breakpoints';

  final FoundationDataStoreOwner _owner;

  Future<void> saveBreakpointSet(DebugBreakpointSet set) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: set.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: set.workspaceId,
    );
  }

  Future<DebugBreakpointSet> readBreakpointSet({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return DebugBreakpointSet(workspaceId: workspaceId);
    }
    final set = DebugBreakpointSet.fromJson(value);
    return set.workspaceId.isEmpty
        ? set.copyWith(workspaceId: workspaceId)
        : set;
  }

  Future<DebugBreakpointSet> replaceFileBreakpoints({
    required String workspaceId,
    required String filePath,
    required Iterable<DebugLaunchBreakpoint> breakpoints,
  }) async {
    final current = await readBreakpointSet(workspaceId: workspaceId);
    final next = current.replaceFileBreakpoints(
      filePath: filePath,
      breakpoints: breakpoints,
    );
    await saveBreakpointSet(next);
    return next;
  }

  Future<bool> deleteBreakpointSet({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchBreakpointSet({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<DebugLaunchBreakpoint> _jsonBreakpoints(Object? value) {
  if (value is! List) {
    return const <DebugLaunchBreakpoint>[];
  }
  return _normalizeBreakpoints(
    value.whereType<Map>().map(
      (breakpoint) => DebugLaunchBreakpoint.fromJson(
        breakpoint.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        ),
      ),
    ),
  );
}

List<DebugLaunchBreakpoint> _normalizeBreakpoints(
  Iterable<DebugLaunchBreakpoint> breakpoints,
) {
  final byLocation = <String, DebugLaunchBreakpoint>{};
  for (final breakpoint in breakpoints) {
    final filePath = breakpoint.filePath.trim();
    if (filePath.isEmpty || breakpoint.line <= 0) {
      continue;
    }
    byLocation['$filePath:${breakpoint.line}'] = DebugLaunchBreakpoint(
      filePath: filePath,
      line: breakpoint.line,
      enabled: breakpoint.enabled,
    );
  }
  final normalized = byLocation.values.toList(growable: false)
    ..sort((left, right) {
      final pathOrder = left.filePath.compareTo(right.filePath);
      return pathOrder == 0 ? left.line.compareTo(right.line) : pathOrder;
    });
  return List<DebugLaunchBreakpoint>.unmodifiable(normalized);
}
