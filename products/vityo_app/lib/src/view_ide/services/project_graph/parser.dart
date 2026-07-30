import 'algorithms.dart';
import 'model.dart';

class StyioProjectGraphParser {
  const StyioProjectGraphParser();

  StyioProjectGraph parse({
    required Uri workspaceRootUri,
    required StyioCanonicalProjectFiles canonicalFiles,
    String? hostPlatform,
  }) {
    final sortedFiles = List<StyioCanonicalProjectFile>.from(
      canonicalFiles.files,
    )..sort((left, right) => left.normalizedPath.compareTo(right.normalizedPath));
    final nodes = <String, StyioProjectNode>{};
    final edges = <StyioProjectEdge>[];
    final diagnostics = <StyioGraphDiagnostic>[];
    final workspaceNode = StyioProjectNode(
      id: 'workspace:${workspaceRootUri.toString()}',
      kind: StyioProjectNodeKind.workspace,
      label: workspaceRootUri.toString(),
      path: workspaceRootUri.path.isEmpty ? '.' : workspaceRootUri.path,
    );
    nodes[workspaceNode.id] = workspaceNode;

    for (final file in sortedFiles) {
      final node = StyioProjectNode(
        id: 'file:${file.normalizedPath}',
        kind: StyioProjectNodeKind.canonicalFile,
        label: file.normalizedPath,
        path: file.normalizedPath,
        data: <String, Object?>{
          'kind': file.kind.label,
          'contentHash': file.contentHash,
        },
      );
      nodes[node.id] = node;
    }

    if (sortedFiles.isEmpty) {
      diagnostics.add(
        const StyioGraphDiagnostic(
          severity: StyioGraphDiagnosticSeverity.warning,
          code: StyioGraphDiagnosticCode.emptyProject,
          message: 'No Styio canonical project files were provided.',
        ),
      );
      return StyioProjectGraph(
        workspaceRootUri: workspaceRootUri,
        nodes: nodes,
        edges: edges,
        modules: const <StyioProjectModule>[],
        targets: const <StyioProjectTarget>[],
        canonicalFiles: sortedFiles,
        toolchain: const StyioToolchainSelection(),
        diagnostics: diagnostics,
      );
    }

    final manifests = sortedFiles
        .where((file) => file.kind == StyioCanonicalProjectFileKind.manifest)
        .toList(growable: false);
    if (manifests.isEmpty) {
      diagnostics.add(
        const StyioGraphDiagnostic(
          severity: StyioGraphDiagnosticSeverity.warning,
          code: StyioGraphDiagnosticCode.missingManifest,
          message: 'No Styio manifest was present in canonical project files.',
        ),
      );
      return StyioProjectGraph(
        workspaceRootUri: workspaceRootUri,
        nodes: nodes,
        edges: edges,
        modules: const <StyioProjectModule>[],
        targets: const <StyioProjectTarget>[],
        canonicalFiles: sortedFiles,
        toolchain: _toolchainFromFiles(sortedFiles),
        diagnostics: diagnostics,
      );
    }

    final manifestByDirectory = <String, _ParsedManifest>{};
    for (final file in manifests) {
      final parsed = _parseManifest(file);
      manifestByDirectory[parsed.rootPath] = parsed;
    }

    final rootManifest = _selectRootManifest(
      workspaceRootUri: workspaceRootUri,
      manifests: manifestByDirectory.values,
    );
    if (rootManifest == null) {
      diagnostics.add(
        const StyioGraphDiagnostic(
          severity: StyioGraphDiagnosticSeverity.error,
          code: StyioGraphDiagnosticCode.missingManifest,
          message: 'Canonical files did not include a workspace root manifest.',
        ),
      );
      return StyioProjectGraph(
        workspaceRootUri: workspaceRootUri,
        nodes: nodes,
        edges: edges,
        modules: const <StyioProjectModule>[],
        targets: const <StyioProjectTarget>[],
        canonicalFiles: sortedFiles,
        toolchain: _toolchainFromFiles(sortedFiles),
        diagnostics: diagnostics,
      );
    }

    final selectedManifests = <_ParsedManifest>[];
    final seenManifestPaths = <String>{};
    void addManifest(_ParsedManifest manifest, {required bool isWorkspaceMember}) {
      if (!seenManifestPaths.add(manifest.path)) {
        return;
      }
      selectedManifests.add(manifest.copyWith(isWorkspaceMember: isWorkspaceMember));
    }

    addManifest(rootManifest, isWorkspaceMember: false);
    for (final memberPath in rootManifest.workspaceMembers) {
      final memberRoot = styioJoinPath(rootManifest.rootPath, memberPath);
      final memberManifest = manifestByDirectory[memberRoot];
      if (memberManifest == null) {
        final nodeId = 'missing-module:$memberPath';
        nodes[nodeId] = StyioProjectNode(
          id: nodeId,
          kind: StyioProjectNodeKind.missingModule,
          label: memberPath,
          path: memberRoot,
        );
        edges.add(
          StyioProjectEdge(
            from: workspaceNode.id,
            to: nodeId,
            kind: StyioProjectEdgeKind.workspaceMember,
            label: memberPath,
          ),
        );
        diagnostics.add(
          StyioGraphDiagnostic(
            severity: StyioGraphDiagnosticSeverity.error,
            code: StyioGraphDiagnosticCode.missingModule,
            message: 'Workspace member `$memberPath` has no canonical manifest.',
            source: memberPath,
          ),
        );
        continue;
      }
      addManifest(memberManifest, isWorkspaceMember: true);
    }

    final modules = <StyioProjectModule>[];
    final targets = <StyioProjectTarget>[];
    final parsedByModuleId = <String, _ParsedManifest>{};
    for (final manifest in selectedManifests) {
      if (manifest.moduleName == null) {
        continue;
      }
      final moduleId = styioModuleId(manifest.moduleName!);
      parsedByModuleId[moduleId] = manifest;
    }

    final moduleIdByRoot = <String, String>{};
    final moduleIdByName = <String, String>{};
    for (final entry in parsedByModuleId.entries) {
      moduleIdByRoot[entry.value.rootPath] = entry.key;
      moduleIdByName[entry.value.moduleName!] = entry.key;
      moduleIdByName[entry.value.moduleName!.split('/').last] = entry.key;
    }

    for (final entry in parsedByModuleId.entries) {
      final moduleId = entry.key;
      final manifest = entry.value;
      final resolvedDependencies = <StyioProjectDependency>[];
      for (final dependency in manifest.dependencies) {
        final targetModuleId = _resolveDependencyTarget(
          dependency: dependency,
          sourceRoot: manifest.rootPath,
          moduleIdByRoot: moduleIdByRoot,
          moduleIdByName: moduleIdByName,
        );
        resolvedDependencies.add(
          dependency.toPublicDependency(targetModuleId: targetModuleId),
        );
      }

      final moduleTargets = manifest.targets
          .map(
            (target) => StyioProjectTarget(
              id: '$moduleId:${target.kind.label}:${target.name}',
              moduleId: moduleId,
              kind: target.kind,
              name: target.name,
              path: styioJoinPath(manifest.rootPath, target.path),
            ),
          )
          .toList(growable: false);
      targets.addAll(moduleTargets);
      modules.add(
        StyioProjectModule(
          id: moduleId,
          name: manifest.moduleName!,
          version: manifest.moduleVersion ?? '0.0.0',
          rootPath: manifest.rootPath,
          manifestPath: manifest.path,
          platforms: _sortedUnique(manifest.platforms),
          dependencies: resolvedDependencies,
          targets: moduleTargets,
          isWorkspaceMember: manifest.isWorkspaceMember,
        ),
      );
    }

    final moduleById = <String, StyioProjectModule>{
      for (final module in modules) module.id: module,
    };
    for (final module in modules) {
      nodes[module.id] = StyioProjectNode(
        id: module.id,
        kind: StyioProjectNodeKind.module,
        label: module.name,
        path: module.rootPath,
        data: <String, Object?>{
          'version': module.version,
          'platforms': module.platforms,
          'isWorkspaceMember': module.isWorkspaceMember,
        },
      );
      edges.add(
        StyioProjectEdge(
          from: workspaceNode.id,
          to: module.id,
          kind: StyioProjectEdgeKind.workspaceMember,
          label: module.name,
        ),
      );
      edges.add(
        StyioProjectEdge(
          from: module.id,
          to: 'file:${module.manifestPath}',
          kind: StyioProjectEdgeKind.manifest,
          label: styioBasename(module.manifestPath),
        ),
      );
      for (final target in module.targets) {
        nodes[target.id] = StyioProjectNode(
          id: target.id,
          kind: StyioProjectNodeKind.target,
          label: target.name,
          path: target.path,
          data: <String, Object?>{'kind': target.kind.label},
        );
        edges.add(
          StyioProjectEdge(
            from: module.id,
            to: target.id,
            kind: StyioProjectEdgeKind.targetEntry,
            label: target.kind.label,
          ),
        );
      }
    }

    for (final module in modules) {
      for (final dependency in module.dependencies) {
        final edgeKind = dependency.kind == StyioDependencyKind.runtime
            ? StyioProjectEdgeKind.moduleDependency
            : StyioProjectEdgeKind.devDependency;
        if (dependency.targetModuleId == null) {
          final externalId = 'external:${dependency.name}';
          nodes.putIfAbsent(
            externalId,
            () => StyioProjectNode(
              id: externalId,
              kind: StyioProjectNodeKind.externalDependency,
              label: dependency.name,
              data: <String, Object?>{
                'requirement': dependency.requirement,
                if (dependency.packageName != null)
                  'packageName': dependency.packageName,
              },
            ),
          );
          edges.add(
            StyioProjectEdge(
              from: module.id,
              to: externalId,
              kind: edgeKind,
              label: dependency.name,
              data: dependency.toStableJson(),
            ),
          );
          if (dependency.pathSource != null) {
            diagnostics.add(
              StyioGraphDiagnostic(
                severity: StyioGraphDiagnosticSeverity.error,
                code: StyioGraphDiagnosticCode.missingDependency,
                message:
                    'Dependency `${dependency.name}` points to `${dependency.pathSource}` but no module manifest was loaded there.',
                source: module.id,
              ),
            );
          }
          continue;
        }

        edges.add(
          StyioProjectEdge(
            from: module.id,
            to: dependency.targetModuleId!,
            kind: edgeKind,
            label: dependency.name,
            data: dependency.toStableJson(),
          ),
        );
        final target = moduleById[dependency.targetModuleId!];
        if (target != null) {
          diagnostics.addAll(
            _dependencyDiagnostics(
              source: module,
              target: target,
              dependency: dependency,
            ),
          );
        }
      }
    }

    final toolchain = _toolchainFromFiles(
      sortedFiles,
      manifestToolchain: rootManifest.toolchain,
    );
    if (!toolchain.isEmpty) {
      final toolchainId =
          'toolchain:${toolchain.channel ?? 'unspecified'}:${toolchain.version ?? 'unspecified'}';
      nodes[toolchainId] = StyioProjectNode(
        id: toolchainId,
        kind: StyioProjectNodeKind.toolchain,
        label: toolchainId.substring('toolchain:'.length),
        path: toolchain.pinPath,
        data: toolchain.toStableJson(),
      );
      edges.add(
        StyioProjectEdge(
          from: workspaceNode.id,
          to: toolchainId,
          kind: StyioProjectEdgeKind.toolchainPin,
          label: toolchain.channel ?? toolchain.version ?? 'toolchain',
        ),
      );
      diagnostics.addAll(
        _toolchainDiagnostics(
          manifestToolchain: rootManifest.toolchain,
          resolvedToolchain: toolchain,
          hostPlatform: hostPlatform,
        ),
      );
    }

    if (hostPlatform != null) {
      for (final module in modules) {
        if (module.platforms.isNotEmpty &&
            !module.platforms.contains(hostPlatform)) {
          diagnostics.add(
            StyioGraphDiagnostic(
              severity: StyioGraphDiagnosticSeverity.warning,
              code: StyioGraphDiagnosticCode.platformConflict,
              message:
                  'Module `${module.name}` does not declare support for host platform `$hostPlatform`.',
              source: module.id,
            ),
          );
        }
      }
    }

    final dependencyGraph = StyioProjectGraph(
      workspaceRootUri: workspaceRootUri,
      nodes: nodes,
      edges: edges,
      modules: modules,
      targets: targets,
      canonicalFiles: sortedFiles,
      toolchain: toolchain,
      workspaceMembers: rootManifest.workspaceMembers,
      diagnostics: diagnostics,
    ).moduleDependencyGraph();
    diagnostics.addAll(
      StyioProjectGraphAlgorithms.cycleDiagnostics(dependencyGraph),
    );
    if (StyioProjectGraphAlgorithms.kahnTopologicalSort(dependencyGraph) ==
            null &&
        modules.isNotEmpty) {
      diagnostics.add(
        const StyioGraphDiagnostic(
          severity: StyioGraphDiagnosticSeverity.warning,
          code: StyioGraphDiagnosticCode.topologicalSortBlocked,
          message:
              'Topological sort is blocked because the module graph contains a cycle.',
        ),
      );
    }

    modules.sort((left, right) => left.id.compareTo(right.id));
    targets.sort((left, right) => left.id.compareTo(right.id));
    edges.sort((left, right) => left.identityKey.compareTo(right.identityKey));
    final sortedNodes = Map<String, StyioProjectNode>.fromEntries(
      nodes.entries.toList()..sort((left, right) => left.key.compareTo(right.key)),
    );

    return StyioProjectGraph(
      workspaceRootUri: workspaceRootUri,
      nodes: sortedNodes,
      edges: edges,
      modules: modules,
      targets: targets,
      canonicalFiles: sortedFiles,
      toolchain: toolchain,
      workspaceMembers: rootManifest.workspaceMembers,
      diagnostics: diagnostics,
    );
  }

  _ParsedManifest? _selectRootManifest({
    required Uri workspaceRootUri,
    required Iterable<_ParsedManifest> manifests,
  }) {
    final workspaceRoot = styioNormalizePath(
      workspaceRootUri.path.isEmpty ? '.' : workspaceRootUri.path,
    );
    final sorted = manifests.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final manifest in sorted) {
      if (manifest.rootPath == workspaceRoot ||
          (workspaceRoot == '.' && manifest.rootPath == '.')) {
        return manifest;
      }
    }
    for (final manifest in sorted) {
      if (manifest.rootPath == '.') {
        return manifest;
      }
    }
    return sorted.isEmpty ? null : sorted.first;
  }

  _ParsedManifest _parseManifest(StyioCanonicalProjectFile file) {
    var section = _ManifestSection.root;
    _MutableTarget? pendingTarget;
    String? moduleName;
    String? moduleVersion;
    final modulePlatforms = <String>[];
    final workspaceMembers = <String>[];
    final dependencies = <_ParsedDependency>[];
    final targets = <_ParsedTarget>[];
    var toolchain = const StyioToolchainSelection();

    void flushPendingTarget() {
      final target = pendingTarget;
      if (target == null || target.path == null) {
        pendingTarget = null;
        return;
      }
      final targetName = target.kind == StyioTargetKind.lib
          ? (moduleName?.split('/').last ?? 'lib')
          : (target.name ?? target.kind.label);
      targets.add(
        _ParsedTarget(
          kind: target.kind,
          name: targetName,
          path: target.path!,
        ),
      );
      pendingTarget = null;
    }

    for (final rawLine in file.content.split('\n')) {
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('[[') && line.endsWith(']]')) {
        flushPendingTarget();
        section = _sectionFromHeader(line.substring(2, line.length - 2).trim());
        pendingTarget = _targetForSection(section, arrayHeader: true);
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        flushPendingTarget();
        section = _sectionFromHeader(line.substring(1, line.length - 1).trim());
        pendingTarget = _targetForSection(section, arrayHeader: false);
        continue;
      }

      final separator = line.indexOf('=');
      if (separator == -1) {
        continue;
      }
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      switch (section) {
        case _ManifestSection.module:
          if (key == 'name') {
            moduleName = _parseString(value);
          } else if (key == 'version') {
            moduleVersion = _parseString(value);
          } else if (key == 'platform' || key == 'target') {
            final platform = _parseString(value);
            if (platform != null) {
              modulePlatforms.add(platform);
            }
          } else if (key == 'platforms' || key == 'targets') {
            modulePlatforms.addAll(_parseStringArray(value));
          }
        case _ManifestSection.workspace:
          if (key == 'members') {
            workspaceMembers.addAll(_parseStringArray(value));
          } else if (key == 'platforms' || key == 'targets') {
            modulePlatforms.addAll(_parseStringArray(value));
          }
        case _ManifestSection.dependencies:
        case _ManifestSection.devDependencies:
          dependencies.add(
            _parseDependency(
              name: key,
              value: value,
              kind: section == _ManifestSection.dependencies
                  ? StyioDependencyKind.runtime
                  : StyioDependencyKind.dev,
            ),
          );
        case _ManifestSection.toolchain:
          toolchain = _parseToolchainField(
            current: toolchain,
            key: key,
            value: value,
          );
        case _ManifestSection.lib:
        case _ManifestSection.bin:
        case _ManifestSection.test:
          _applyTargetField(pendingTarget, key, value);
        case _ManifestSection.root:
        case _ManifestSection.other:
      }
    }
    flushPendingTarget();

    return _ParsedManifest(
      path: file.normalizedPath,
      rootPath: styioDirname(file.normalizedPath),
      moduleName: moduleName,
      moduleVersion: moduleVersion,
      platforms: _sortedUnique(modulePlatforms),
      workspaceMembers: _sortedUnique(workspaceMembers),
      dependencies: dependencies,
      targets: targets,
      toolchain: toolchain,
    );
  }
}

List<StyioGraphDiagnostic> _dependencyDiagnostics({
  required StyioProjectModule source,
  required StyioProjectModule target,
  required StyioProjectDependency dependency,
}) {
  final diagnostics = <StyioGraphDiagnostic>[];
  if (dependency.requirement.isNotEmpty &&
      !_versionSatisfies(target.version, dependency.requirement)) {
    diagnostics.add(
      StyioGraphDiagnostic(
        severity: StyioGraphDiagnosticSeverity.error,
        code: StyioGraphDiagnosticCode.versionConflict,
        message:
            'Dependency `${dependency.name}` requires `${dependency.requirement}` but `${target.name}` is `${target.version}`.',
        source: source.id,
      ),
    );
  }
  final sourcePlatforms = source.platforms.toSet();
  final targetPlatforms = target.platforms.toSet();
  if (sourcePlatforms.isNotEmpty &&
      targetPlatforms.isNotEmpty &&
      sourcePlatforms.intersection(targetPlatforms).isEmpty) {
    diagnostics.add(
      StyioGraphDiagnostic(
        severity: StyioGraphDiagnosticSeverity.error,
        code: StyioGraphDiagnosticCode.platformConflict,
        message:
            'Module `${source.name}` depends on `${target.name}`, but their declared platforms do not overlap.',
        source: source.id,
      ),
    );
  }
  return diagnostics;
}

List<StyioGraphDiagnostic> _toolchainDiagnostics({
  required StyioToolchainSelection manifestToolchain,
  required StyioToolchainSelection resolvedToolchain,
  required String? hostPlatform,
}) {
  final diagnostics = <StyioGraphDiagnostic>[];
  if (manifestToolchain.version != null &&
      resolvedToolchain.pinPath != null &&
      resolvedToolchain.version != null &&
      manifestToolchain.version != resolvedToolchain.version) {
    diagnostics.add(
      StyioGraphDiagnostic(
        severity: StyioGraphDiagnosticSeverity.warning,
        code: StyioGraphDiagnosticCode.versionConflict,
        message:
            'Toolchain pin `${resolvedToolchain.version}` conflicts with manifest version `${manifestToolchain.version}`.',
        source: resolvedToolchain.pinPath,
      ),
    );
  }
  if (hostPlatform != null &&
      resolvedToolchain.platforms.isNotEmpty &&
      !resolvedToolchain.platforms.contains(hostPlatform)) {
    diagnostics.add(
      StyioGraphDiagnostic(
        severity: StyioGraphDiagnosticSeverity.warning,
        code: StyioGraphDiagnosticCode.platformConflict,
        message:
            'Toolchain does not declare support for host platform `$hostPlatform`.',
        source: resolvedToolchain.pinPath,
      ),
    );
  }
  return diagnostics;
}

StyioToolchainSelection _toolchainFromFiles(
  List<StyioCanonicalProjectFile> files, {
  StyioToolchainSelection manifestToolchain = const StyioToolchainSelection(),
}) {
  final pins = files
      .where((file) => file.kind == StyioCanonicalProjectFileKind.toolchainPin)
      .toList(growable: false)
    ..sort((left, right) => left.normalizedPath.compareTo(right.normalizedPath));
  if (pins.isEmpty) {
    return manifestToolchain;
  }
  var pinned = const StyioToolchainSelection();
  for (final pin in pins) {
    for (final rawLine in pin.content.split('\n')) {
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty || line.startsWith('[')) {
        continue;
      }
      final separator = line.indexOf('=');
      if (separator == -1) {
        continue;
      }
      pinned = _parseToolchainField(
        current: pinned,
        key: line.substring(0, separator).trim(),
        value: line.substring(separator + 1).trim(),
        pinPath: pin.normalizedPath,
      );
    }
  }
  return StyioToolchainSelection(
    channel: pinned.channel ?? manifestToolchain.channel,
    version: pinned.version ?? manifestToolchain.version,
    platforms: pinned.platforms.isNotEmpty
        ? pinned.platforms
        : manifestToolchain.platforms,
    pinPath: pinned.pinPath,
  );
}

StyioToolchainSelection _parseToolchainField({
  required StyioToolchainSelection current,
  required String key,
  required String value,
  String? pinPath,
}) {
  if (key == 'channel') {
    return StyioToolchainSelection(
      channel: _parseString(value) ?? current.channel,
      version: current.version,
      platforms: current.platforms,
      pinPath: pinPath ?? current.pinPath,
    );
  }
  if (key == 'version') {
    return StyioToolchainSelection(
      channel: current.channel,
      version: _parseString(value) ?? current.version,
      platforms: current.platforms,
      pinPath: pinPath ?? current.pinPath,
    );
  }
  if (key == 'platforms' || key == 'targets') {
    return StyioToolchainSelection(
      channel: current.channel,
      version: current.version,
      platforms: _sortedUnique(<String>[
        ...current.platforms,
        ..._parseStringArray(value),
      ]),
      pinPath: pinPath ?? current.pinPath,
    );
  }
  return current;
}

String? _resolveDependencyTarget({
  required _ParsedDependency dependency,
  required String sourceRoot,
  required Map<String, String> moduleIdByRoot,
  required Map<String, String> moduleIdByName,
}) {
  if (dependency.pathSource != null) {
    final resolvedPath = styioJoinPath(sourceRoot, dependency.pathSource!);
    final byRoot = moduleIdByRoot[resolvedPath];
    if (byRoot != null) {
      return byRoot;
    }
  }
  if (dependency.packageName != null) {
    final byPackage = moduleIdByName[dependency.packageName!];
    if (byPackage != null) {
      return byPackage;
    }
  }
  return moduleIdByName[dependency.name];
}

_ParsedDependency _parseDependency({
  required String name,
  required String value,
  required StyioDependencyKind kind,
}) {
  final stringValue = _parseString(value);
  if (stringValue != null) {
    return _ParsedDependency(
      name: name,
      kind: kind,
      requirement: stringValue,
    );
  }

  final table = _parseInlineTable(value);
  final version = _stringFromValue(table['version']);
  final path = _stringFromValue(table['path']);
  final packageName = _stringFromValue(table['package']);
  final workspace = _boolFromValue(table['workspace']) ?? false;
  final platforms = _stringListFromValue(table['platforms']);
  final platform = _stringFromValue(table['platform']);
  return _ParsedDependency(
    name: name,
    kind: kind,
    requirement: workspace ? 'workspace' : (version ?? ''),
    packageName: packageName,
    pathSource: path,
    isWorkspaceReference: workspace,
    platforms: _sortedUnique(<String>[
      ...platforms,
      if (platform != null) platform,
    ]),
  );
}

Map<String, Object?> _parseInlineTable(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    return const <String, Object?>{};
  }
  final body = trimmed.substring(1, trimmed.length - 1);
  final entries = <String, Object?>{};
  for (final part in _splitTopLevel(body, ',')) {
    final separator = part.indexOf('=');
    if (separator == -1) {
      continue;
    }
    final key = part.substring(0, separator).trim();
    final raw = part.substring(separator + 1).trim();
    entries[key] = _parseTomlValue(raw);
  }
  return entries;
}

Object? _parseTomlValue(String value) {
  final string = _parseString(value);
  if (string != null) {
    return string;
  }
  final boolValue = _parseBool(value);
  if (boolValue != null) {
    return boolValue;
  }
  if (value.startsWith('[') && value.endsWith(']')) {
    return _parseStringArray(value);
  }
  return value.trim();
}

String? _parseString(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2) {
    final first = trimmed[0];
    final last = trimmed[trimmed.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return trimmed.substring(1, trimmed.length - 1);
    }
  }
  return null;
}

bool? _parseBool(String value) {
  switch (value.trim()) {
    case 'true':
      return true;
    case 'false':
      return false;
  }
  return null;
}

List<String> _parseStringArray(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
    return const <String>[];
  }
  final body = trimmed.substring(1, trimmed.length - 1);
  return _splitTopLevel(body, ',')
      .map(_parseString)
      .whereType<String>()
      .toList(growable: false);
}

String? _stringFromValue(Object? value) => value is String ? value : null;

bool? _boolFromValue(Object? value) => value is bool ? value : null;

List<String> _stringListFromValue(Object? value) =>
    value is List<String> ? value : const <String>[];

List<String> _splitTopLevel(String value, String separator) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var bracketDepth = 0;
  var braceDepth = 0;

  for (var i = 0; i < value.length; i += 1) {
    final char = value[i];
    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
    } else if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
    } else if (!inSingleQuote && !inDoubleQuote) {
      if (char == '[') {
        bracketDepth += 1;
      } else if (char == ']') {
        bracketDepth -= 1;
      } else if (char == '{') {
        braceDepth += 1;
      } else if (char == '}') {
        braceDepth -= 1;
      }
    }
    if (!inSingleQuote &&
        !inDoubleQuote &&
        bracketDepth == 0 &&
        braceDepth == 0 &&
        char == separator) {
      parts.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) {
    parts.add(tail);
  }
  return parts;
}

String _stripComment(String line) {
  var inSingleQuote = false;
  var inDoubleQuote = false;
  for (var i = 0; i < line.length; i += 1) {
    final char = line[i];
    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
    } else if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
    } else if (char == '#' && !inSingleQuote && !inDoubleQuote) {
      return line.substring(0, i);
    }
  }
  return line;
}

bool _versionSatisfies(String actual, String requirement) {
  final trimmed = requirement.trim();
  if (trimmed.isEmpty || trimmed == 'workspace') {
    return true;
  }
  final actualVersion = _SemanticVersion.parse(actual);
  if (actualVersion == null) {
    return false;
  }
  if (trimmed.startsWith('^')) {
    final lower = _SemanticVersion.parse(trimmed.substring(1));
    return lower != null &&
        actualVersion.compareTo(lower) >= 0 &&
        actualVersion.major == lower.major;
  }
  final parts = trimmed.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  if (parts.length > 1) {
    for (final part in parts) {
      if (!_versionConstraintSatisfied(actualVersion, part)) {
        return false;
      }
    }
    return true;
  }
  return _versionConstraintSatisfied(actualVersion, trimmed);
}

bool _versionConstraintSatisfied(_SemanticVersion actual, String constraint) {
  if (constraint.startsWith('>=')) {
    final version = _SemanticVersion.parse(constraint.substring(2));
    return version != null && actual.compareTo(version) >= 0;
  }
  if (constraint.startsWith('>')) {
    final version = _SemanticVersion.parse(constraint.substring(1));
    return version != null && actual.compareTo(version) > 0;
  }
  if (constraint.startsWith('<=')) {
    final version = _SemanticVersion.parse(constraint.substring(2));
    return version != null && actual.compareTo(version) <= 0;
  }
  if (constraint.startsWith('<')) {
    final version = _SemanticVersion.parse(constraint.substring(1));
    return version != null && actual.compareTo(version) < 0;
  }
  if (constraint.startsWith('=')) {
    final version = _SemanticVersion.parse(constraint.substring(1));
    return version != null && actual.compareTo(version) == 0;
  }
  final exact = _SemanticVersion.parse(constraint);
  return exact != null && actual.compareTo(exact) == 0;
}

List<String> _sortedUnique(Iterable<String> values) {
  final normalized = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return normalized;
}

_ManifestSection _sectionFromHeader(String header) {
  switch (header) {
    case 'module':
    case 'package':
      return _ManifestSection.module;
    case 'workspace':
      return _ManifestSection.workspace;
    case 'dependencies':
      return _ManifestSection.dependencies;
    case 'dev-dependencies':
      return _ManifestSection.devDependencies;
    case 'toolchain':
      return _ManifestSection.toolchain;
    case 'lib':
    case 'target.lib':
      return _ManifestSection.lib;
    case 'bin':
    case 'target.bin':
      return _ManifestSection.bin;
    case 'test':
    case 'target.test':
      return _ManifestSection.test;
  }
  return _ManifestSection.other;
}

_MutableTarget? _targetForSection(
  _ManifestSection section, {
  required bool arrayHeader,
}) {
  switch (section) {
    case _ManifestSection.lib:
      return arrayHeader ? null : _MutableTarget(kind: StyioTargetKind.lib);
    case _ManifestSection.bin:
      return arrayHeader ? _MutableTarget(kind: StyioTargetKind.bin) : null;
    case _ManifestSection.test:
      return arrayHeader ? _MutableTarget(kind: StyioTargetKind.test) : null;
    case _ManifestSection.root:
    case _ManifestSection.module:
    case _ManifestSection.workspace:
    case _ManifestSection.dependencies:
    case _ManifestSection.devDependencies:
    case _ManifestSection.toolchain:
    case _ManifestSection.other:
      return null;
  }
}

void _applyTargetField(_MutableTarget? target, String key, String value) {
  if (target == null) {
    return;
  }
  if (key == 'name') {
    target.name = _parseString(value);
  } else if (key == 'path') {
    target.path = _parseString(value);
  }
}

enum _ManifestSection {
  root,
  module,
  workspace,
  dependencies,
  devDependencies,
  toolchain,
  lib,
  bin,
  test,
  other,
}

class _ParsedManifest {
  const _ParsedManifest({
    required this.path,
    required this.rootPath,
    required this.moduleName,
    required this.moduleVersion,
    required this.platforms,
    required this.workspaceMembers,
    required this.dependencies,
    required this.targets,
    required this.toolchain,
    this.isWorkspaceMember = false,
  });

  final String path;
  final String rootPath;
  final String? moduleName;
  final String? moduleVersion;
  final List<String> platforms;
  final List<String> workspaceMembers;
  final List<_ParsedDependency> dependencies;
  final List<_ParsedTarget> targets;
  final StyioToolchainSelection toolchain;
  final bool isWorkspaceMember;

  _ParsedManifest copyWith({required bool isWorkspaceMember}) {
    return _ParsedManifest(
      path: path,
      rootPath: rootPath,
      moduleName: moduleName,
      moduleVersion: moduleVersion,
      platforms: platforms,
      workspaceMembers: workspaceMembers,
      dependencies: dependencies,
      targets: targets,
      toolchain: toolchain,
      isWorkspaceMember: isWorkspaceMember,
    );
  }
}

class _ParsedDependency {
  const _ParsedDependency({
    required this.name,
    required this.kind,
    required this.requirement,
    this.packageName,
    this.pathSource,
    this.isWorkspaceReference = false,
    this.platforms = const <String>[],
  });

  final String name;
  final StyioDependencyKind kind;
  final String requirement;
  final String? packageName;
  final String? pathSource;
  final bool isWorkspaceReference;
  final List<String> platforms;

  StyioProjectDependency toPublicDependency({String? targetModuleId}) {
    return StyioProjectDependency(
      name: name,
      kind: kind,
      requirement: requirement,
      packageName: packageName,
      pathSource: pathSource,
      targetModuleId: targetModuleId,
      platforms: platforms,
    );
  }
}

class _ParsedTarget {
  const _ParsedTarget({
    required this.kind,
    required this.name,
    required this.path,
  });

  final StyioTargetKind kind;
  final String name;
  final String path;
}

class _MutableTarget {
  _MutableTarget({required this.kind});

  final StyioTargetKind kind;
  String? name;
  String? path;
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch);

  static _SemanticVersion? parse(String value) {
    final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(
      value.trim(),
    );
    if (match == null) {
      return null;
    }
    return _SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2) ?? '0'),
      int.parse(match.group(3) ?? '0'),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_SemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) {
      return majorCompare;
    }
    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) {
      return minorCompare;
    }
    return patch.compareTo(other.patch);
  }
}

