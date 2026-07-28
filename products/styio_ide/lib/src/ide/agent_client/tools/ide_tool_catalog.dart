import 'dart:async';
import 'dart:collection';

enum ContextSensitivity { public, internal, sensitive }

enum IdeToolRisk {
  readOnly,
  mutating,
  network,
  credential,
  destructive,
  openWorld,
}

final class IdeToolFailure implements Exception {
  const IdeToolFailure(this.code, this.message);

  final String code;
  final String message;
}

final class IdeToolDescriptor {
  IdeToolDescriptor({
    required this.name,
    required this.title,
    required this.description,
    required this.requiredCapabilityId,
    required Map<String, Object?> inputSchema,
    required Map<String, Object?> outputSchema,
    required Set<IdeToolRisk> risks,
    this.requiresWorkspacePath = false,
    Map<String, Object?> annotations = const <String, Object?>{},
  }) : inputSchema = UnmodifiableMapView(inputSchema),
       outputSchema = UnmodifiableMapView(outputSchema),
       risks = Set<IdeToolRisk>.unmodifiable(risks),
       annotations = UnmodifiableMapView(annotations) {
    if (name.trim().isEmpty ||
        name.length > 128 ||
        title.trim().isEmpty ||
        description.trim().isEmpty ||
        requiredCapabilityId.trim().isEmpty) {
      throw ArgumentError('tool descriptor identifiers must be bounded');
    }
    if (inputSchema['type'] != 'object' || outputSchema['type'] != 'object') {
      throw ArgumentError('tool schemas must describe JSON objects');
    }
    if (this.risks.isEmpty) {
      throw ArgumentError('tool risks are authoritative and required');
    }
  }

  final String name;
  final String title;
  final String description;
  final String requiredCapabilityId;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final Set<IdeToolRisk> risks;
  final bool requiresWorkspacePath;
  final Map<String, Object?> annotations;

  Map<String, Object?> toMcpJson() => <String, Object?>{
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'outputSchema': outputSchema,
    if (annotations.isNotEmpty) 'annotations': annotations,
    '_meta': <String, Object?>{
      'styio/capabilityId': requiredCapabilityId,
      'styio/risks': risks.map((risk) => risk.name).toList(growable: false)
        ..sort(),
      'styio/requiresWorkspacePath': requiresWorkspacePath,
    },
  };
}

final class IdeToolInvocation {
  IdeToolInvocation({
    required this.callId,
    required this.sessionId,
    required Map<String, Object?> arguments,
    this.expectedWorkspaceRevision,
  }) : arguments = UnmodifiableMapView(arguments);

  final String callId;
  final String sessionId;
  final Map<String, Object?> arguments;
  final int? expectedWorkspaceRevision;
}

final class IdeToolResult {
  IdeToolResult({
    required Map<String, Object?> structuredContent,
    required this.workspaceRevision,
    required this.provenance,
    required this.sensitivity,
  }) : structuredContent = UnmodifiableMapView(structuredContent);

  final Map<String, Object?> structuredContent;
  final int workspaceRevision;
  final String provenance;
  final ContextSensitivity sensitivity;
}

abstract interface class IdeToolAdapter {
  IdeToolDescriptor get descriptor;

  Future<IdeToolResult> invoke(IdeToolInvocation invocation);
}

final class ToolCatalogChange {
  const ToolCatalogChange({required this.sessionId, required this.revision});

  final String sessionId;
  final int revision;
}

final class ToolLookup {
  const ToolLookup._({this.adapter, required this.code});

  final IdeToolAdapter? adapter;
  final String code;

  bool get visible => adapter != null;
}

final class IdeToolCatalog {
  IdeToolCatalog({required Iterable<IdeToolAdapter> adapters}) {
    for (final adapter in adapters) {
      _insert(adapter);
    }
  }

  final Map<String, IdeToolAdapter> _adapters = <String, IdeToolAdapter>{};
  final Map<String, Set<String>> _capabilities = <String, Set<String>>{};
  final Map<String, int> _revisions = <String, int>{};
  final StreamController<ToolCatalogChange> _changes =
      StreamController<ToolCatalogChange>.broadcast(sync: true);
  bool _closed = false;

  Stream<ToolCatalogChange> get changes => _changes.stream;

  IdeToolDescriptor? descriptorFor(String name) => _adapters[name]?.descriptor;

  void replaceCapabilities(String sessionId, Set<String> capabilityIds) {
    _ensureOpen();
    _capabilities[sessionId] = Set<String>.unmodifiable(capabilityIds);
    _notify(sessionId);
  }

  List<IdeToolDescriptor> visibleTools(
    String sessionId, {
    required bool hasRoots,
  }) {
    final capabilities = _capabilities[sessionId] ?? const <String>{};
    final descriptors =
        _adapters.values
            .map((adapter) => adapter.descriptor)
            .where(
              (descriptor) =>
                  capabilities.contains(descriptor.requiredCapabilityId) &&
                  (!descriptor.requiresWorkspacePath || hasRoots),
            )
            .toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
    return List<IdeToolDescriptor>.unmodifiable(descriptors);
  }

  ToolLookup lookup(String sessionId, String name, {required bool hasRoots}) {
    final adapter = _adapters[name];
    if (adapter == null) {
      return const ToolLookup._(code: 'tool_not_found');
    }
    final capabilities = _capabilities[sessionId] ?? const <String>{};
    if (!capabilities.contains(adapter.descriptor.requiredCapabilityId)) {
      return const ToolLookup._(code: 'capability_revoked');
    }
    if (adapter.descriptor.requiresWorkspacePath && !hasRoots) {
      return const ToolLookup._(code: 'root_revoked');
    }
    return ToolLookup._(adapter: adapter, code: 'available');
  }

  void register(IdeToolAdapter adapter) {
    registerAll(<IdeToolAdapter>[adapter]);
  }

  void registerAll(Iterable<IdeToolAdapter> adapters) {
    _ensureOpen();
    final additions = adapters.toList(growable: false);
    final names = <String>{};
    for (final adapter in additions) {
      if (_adapters.containsKey(adapter.descriptor.name) ||
          !names.add(adapter.descriptor.name)) {
        throw ArgumentError.value(
          adapter.descriptor.name,
          'adapter',
          'tool name is already registered',
        );
      }
    }
    for (final adapter in additions) {
      _adapters[adapter.descriptor.name] = adapter;
    }
    _notifyAll();
  }

  void unregister(String name) {
    unregisterAll(<String>[name]);
  }

  void unregisterAll(Iterable<String> names) {
    _ensureOpen();
    var changed = false;
    for (final name in names.toSet()) {
      changed = _adapters.remove(name) != null || changed;
    }
    if (changed) {
      _notifyAll();
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _changes.close();
  }

  void _insert(IdeToolAdapter adapter) {
    final existing = _adapters[adapter.descriptor.name];
    if (existing != null) {
      throw ArgumentError.value(
        adapter.descriptor.name,
        'adapter',
        'tool name is already registered',
      );
    }
    _adapters[adapter.descriptor.name] = adapter;
  }

  void _notify(String sessionId) {
    final revision = (_revisions[sessionId] ?? 0) + 1;
    _revisions[sessionId] = revision;
    _changes.add(ToolCatalogChange(sessionId: sessionId, revision: revision));
  }

  void _notifyAll() {
    for (final sessionId in _capabilities.keys.toList(growable: false)) {
      _notify(sessionId);
    }
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('tool catalog is closed');
    }
  }
}
