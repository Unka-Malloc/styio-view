enum ToolchainKind {
  compiler,
  runner,
  buildTool,
  debugger,
  formatter,
  staticAnalyzer,
  testRunner,
  packageManager,
  terminal,
  languageService,
}

extension ToolchainKindX on ToolchainKind {
  String get wireValue => switch (this) {
    ToolchainKind.compiler => 'compiler',
    ToolchainKind.runner => 'runner',
    ToolchainKind.buildTool => 'build-tool',
    ToolchainKind.debugger => 'debugger',
    ToolchainKind.formatter => 'formatter',
    ToolchainKind.staticAnalyzer => 'static-analyzer',
    ToolchainKind.testRunner => 'test-runner',
    ToolchainKind.packageManager => 'package-manager',
    ToolchainKind.terminal => 'terminal',
    ToolchainKind.languageService => 'language-service',
  };
}

ToolchainKind toolchainKindFromWireValue(String? value) {
  return switch (value) {
    'compiler' => ToolchainKind.compiler,
    'runner' => ToolchainKind.runner,
    'build-tool' => ToolchainKind.buildTool,
    'debugger' => ToolchainKind.debugger,
    'formatter' => ToolchainKind.formatter,
    'static-analyzer' => ToolchainKind.staticAnalyzer,
    'test-runner' => ToolchainKind.testRunner,
    'package-manager' => ToolchainKind.packageManager,
    'terminal' => ToolchainKind.terminal,
    'language-service' => ToolchainKind.languageService,
    _ => ToolchainKind.runner,
  };
}

class ToolchainDescriptor {
  const ToolchainDescriptor({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.executablePath,
    this.version,
    this.channel,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final ToolchainKind kind;
  final String displayName;
  final String executablePath;
  final String? version;
  final String? channel;
  final Map<String, Object?> metadata;

  factory ToolchainDescriptor.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    return ToolchainDescriptor(
      id: json['id'] as String? ?? '',
      kind: toolchainKindFromWireValue(json['kind'] as String?),
      displayName: json['displayName'] as String? ?? '',
      executablePath: json['executablePath'] as String? ?? '',
      version: json['version'] as String?,
      channel: json['channel'] as String?,
      metadata: metadata is Map<String, Object?>
          ? metadata
          : metadata is Map
          ? metadata.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.wireValue,
      'displayName': displayName,
      'executablePath': executablePath,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
      'metadata': metadata,
    };
  }
}

class ToolchainCatalogSnapshot {
  const ToolchainCatalogSnapshot({
    required this.descriptors,
    required this.activeToolchainIds,
  });

  factory ToolchainCatalogSnapshot.fromJson(Map<String, Object?> json) {
    final descriptors = json['descriptors'];
    final activeToolchainIds = json['activeToolchainIds'];
    return ToolchainCatalogSnapshot(
      descriptors: descriptors is List
          ? descriptors
                .map(_descriptorFromJson)
                .whereType<ToolchainDescriptor>()
                .where((descriptor) => descriptor.id.isNotEmpty)
                .toList(growable: false)
          : const <ToolchainDescriptor>[],
      activeToolchainIds: activeToolchainIds is Map<String, Object?>
          ? activeToolchainIds.map(
              (key, value) => MapEntry<ToolchainKind, String>(
                toolchainKindFromWireValue(key),
                value.toString(),
              ),
            )
          : activeToolchainIds is Map
          ? activeToolchainIds.map(
              (key, value) => MapEntry<ToolchainKind, String>(
                toolchainKindFromWireValue(key.toString()),
                value.toString(),
              ),
            )
          : const <ToolchainKind, String>{},
    );
  }

  final List<ToolchainDescriptor> descriptors;
  final Map<ToolchainKind, String> activeToolchainIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'descriptors': descriptors
          .map((descriptor) => descriptor.toJson())
          .toList(growable: false),
      'activeToolchainIds': activeToolchainIds.map(
        (kind, id) => MapEntry<String, Object?>(kind.wireValue, id),
      ),
    };
  }

  static ToolchainDescriptor? _descriptorFromJson(Object? value) {
    if (value is Map<String, Object?>) {
      return ToolchainDescriptor.fromJson(value);
    }
    if (value is Map) {
      return ToolchainDescriptor.fromJson(
        value.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        ),
      );
    }
    return null;
  }
}

class ToolchainCatalog {
  final Map<String, ToolchainDescriptor> _descriptors =
      <String, ToolchainDescriptor>{};
  final Map<ToolchainKind, String> _activeByKind = <ToolchainKind, String>{};

  void register(ToolchainDescriptor descriptor, {bool activate = false}) {
    if (_descriptors.containsKey(descriptor.id)) {
      throw StateError('Toolchain ${descriptor.id} is already registered.');
    }
    _descriptors[descriptor.id] = descriptor;
    if (activate) {
      _activeByKind[descriptor.kind] = descriptor.id;
    }
  }

  bool unregister(String id) {
    final descriptor = _descriptors.remove(id);
    if (descriptor == null) {
      return false;
    }
    if (_activeByKind[descriptor.kind] == id) {
      _activeByKind.remove(descriptor.kind);
    }
    return true;
  }

  ToolchainDescriptor? lookup(String id) => _descriptors[id];

  List<ToolchainDescriptor> list({ToolchainKind? kind}) {
    final values = _descriptors.values
        .where((descriptor) {
          return kind == null || descriptor.kind == kind;
        })
        .toList(growable: false);
    values.sort((left, right) => left.id.compareTo(right.id));
    return values;
  }

  void activate(String id) {
    final descriptor = _descriptors[id];
    if (descriptor == null) {
      throw StateError('Toolchain $id is not registered.');
    }
    _activeByKind[descriptor.kind] = id;
  }

  bool deactivate(ToolchainKind kind) {
    return _activeByKind.remove(kind) != null;
  }

  ToolchainDescriptor? active(ToolchainKind kind) {
    final id = _activeByKind[kind];
    return id == null ? null : _descriptors[id];
  }

  ToolchainCatalogSnapshot snapshot() {
    return ToolchainCatalogSnapshot(
      descriptors: list(),
      activeToolchainIds: Map<ToolchainKind, String>.unmodifiable(
        _activeByKind,
      ),
    );
  }

  void restore(ToolchainCatalogSnapshot snapshot) {
    _descriptors.clear();
    _activeByKind.clear();
    for (final descriptor in snapshot.descriptors) {
      _descriptors[descriptor.id] = descriptor;
    }
    for (final entry in snapshot.activeToolchainIds.entries) {
      if (_descriptors.containsKey(entry.value)) {
        _activeByKind[entry.key] = entry.value;
      }
    }
  }
}
