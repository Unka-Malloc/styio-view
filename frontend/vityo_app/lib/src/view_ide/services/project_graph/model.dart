import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

enum StyioCanonicalProjectFileKind {
  manifest,
  lockfile,
  toolchainPin,
  workspaceConfig,
}

extension StyioCanonicalProjectFileKindX on StyioCanonicalProjectFileKind {
  String get label {
    switch (this) {
      case StyioCanonicalProjectFileKind.manifest:
        return 'manifest';
      case StyioCanonicalProjectFileKind.lockfile:
        return 'lockfile';
      case StyioCanonicalProjectFileKind.toolchainPin:
        return 'toolchain-pin';
      case StyioCanonicalProjectFileKind.workspaceConfig:
        return 'workspace-config';
    }
  }
}

enum StyioProjectNodeKind {
  workspace,
  module,
  target,
  externalDependency,
  missingModule,
  toolchain,
  canonicalFile,
}

extension StyioProjectNodeKindX on StyioProjectNodeKind {
  String get label {
    switch (this) {
      case StyioProjectNodeKind.workspace:
        return 'workspace';
      case StyioProjectNodeKind.module:
        return 'module';
      case StyioProjectNodeKind.target:
        return 'target';
      case StyioProjectNodeKind.externalDependency:
        return 'external-dependency';
      case StyioProjectNodeKind.missingModule:
        return 'missing-module';
      case StyioProjectNodeKind.toolchain:
        return 'toolchain';
      case StyioProjectNodeKind.canonicalFile:
        return 'canonical-file';
    }
  }
}

enum StyioProjectEdgeKind {
  manifest,
  workspaceMember,
  moduleDependency,
  devDependency,
  targetEntry,
  toolchainPin,
}

extension StyioProjectEdgeKindX on StyioProjectEdgeKind {
  String get label {
    switch (this) {
      case StyioProjectEdgeKind.manifest:
        return 'manifest';
      case StyioProjectEdgeKind.workspaceMember:
        return 'workspace-member';
      case StyioProjectEdgeKind.moduleDependency:
        return 'module-dependency';
      case StyioProjectEdgeKind.devDependency:
        return 'dev-dependency';
      case StyioProjectEdgeKind.targetEntry:
        return 'target-entry';
      case StyioProjectEdgeKind.toolchainPin:
        return 'toolchain-pin';
    }
  }
}

enum StyioDependencyKind { runtime, dev }

extension StyioDependencyKindX on StyioDependencyKind {
  String get label {
    switch (this) {
      case StyioDependencyKind.runtime:
        return 'runtime';
      case StyioDependencyKind.dev:
        return 'dev';
    }
  }
}

enum StyioTargetKind { lib, bin, test }

extension StyioTargetKindX on StyioTargetKind {
  String get label {
    switch (this) {
      case StyioTargetKind.lib:
        return 'lib';
      case StyioTargetKind.bin:
        return 'bin';
      case StyioTargetKind.test:
        return 'test';
    }
  }
}

enum StyioGraphDiagnosticSeverity { error, warning, info }

extension StyioGraphDiagnosticSeverityX on StyioGraphDiagnosticSeverity {
  String get label {
    switch (this) {
      case StyioGraphDiagnosticSeverity.error:
        return 'error';
      case StyioGraphDiagnosticSeverity.warning:
        return 'warning';
      case StyioGraphDiagnosticSeverity.info:
        return 'info';
    }
  }
}

enum StyioGraphDiagnosticCode {
  emptyProject,
  missingManifest,
  missingModule,
  missingDependency,
  dependencyCycle,
  topologicalSortBlocked,
  versionConflict,
  platformConflict,
}

extension StyioGraphDiagnosticCodeX on StyioGraphDiagnosticCode {
  String get label {
    switch (this) {
      case StyioGraphDiagnosticCode.emptyProject:
        return 'empty-project';
      case StyioGraphDiagnosticCode.missingManifest:
        return 'missing-manifest';
      case StyioGraphDiagnosticCode.missingModule:
        return 'missing-module';
      case StyioGraphDiagnosticCode.missingDependency:
        return 'missing-dependency';
      case StyioGraphDiagnosticCode.dependencyCycle:
        return 'dependency-cycle';
      case StyioGraphDiagnosticCode.topologicalSortBlocked:
        return 'topological-sort-blocked';
      case StyioGraphDiagnosticCode.versionConflict:
        return 'version-conflict';
      case StyioGraphDiagnosticCode.platformConflict:
        return 'platform-conflict';
    }
  }
}

class StyioCanonicalProjectFile {
  StyioCanonicalProjectFile({
    required this.path,
    required this.content,
    required this.kind,
    DateTime? lastModifiedAt,
  }) : lastModifiedAt = lastModifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory StyioCanonicalProjectFile.fromPath({
    required String path,
    required String content,
    DateTime? lastModifiedAt,
  }) {
    final kind = styioCanonicalProjectFileKindForPath(path);
    if (kind == null) {
      throw ArgumentError.value(
        path,
        'path',
        'Path is not a Styio canonical project file.',
      );
    }
    return StyioCanonicalProjectFile(
      path: path,
      content: content,
      kind: kind,
      lastModifiedAt: lastModifiedAt,
    );
  }

  final String path;
  final String content;
  final StyioCanonicalProjectFileKind kind;
  final DateTime lastModifiedAt;

  String get normalizedPath => styioNormalizePath(path);

  String get contentHash =>
      crypto.sha256.convert(utf8.encode(content)).toString();

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'path': normalizedPath,
      'kind': kind.label,
      'contentHash': contentHash,
    };
  }
}

class StyioCanonicalProjectFiles {
  const StyioCanonicalProjectFiles(this.files);

  final List<StyioCanonicalProjectFile> files;

  List<StyioCanonicalProjectFile> get manifests => files
      .where((file) => file.kind == StyioCanonicalProjectFileKind.manifest)
      .toList(growable: false);

  List<StyioCanonicalProjectFile> get toolchainPins => files
      .where((file) => file.kind == StyioCanonicalProjectFileKind.toolchainPin)
      .toList(growable: false);

  bool get isEmpty => files.isEmpty;
}

class StyioProjectNode {
  const StyioProjectNode({
    required this.id,
    required this.kind,
    required this.label,
    this.path,
    this.data = const <String, Object?>{},
  });

  final String id;
  final StyioProjectNodeKind kind;
  final String label;
  final String? path;
  final Map<String, Object?> data;

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.label,
      'label': label,
      if (path != null) 'path': styioNormalizePath(path!),
      if (data.isNotEmpty) 'data': data,
    };
  }

  String get signature => styioStableJson(toStableJson());
}

class StyioProjectEdge {
  const StyioProjectEdge({
    required this.from,
    required this.to,
    required this.kind,
    this.label,
    this.data = const <String, Object?>{},
  });

  final String from;
  final String to;
  final StyioProjectEdgeKind kind;
  final String? label;
  final Map<String, Object?> data;

  String get identityKey => <String>[
    kind.label,
    from,
    to,
    label ?? '',
  ].join('\u0000');

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'from': from,
      'to': to,
      'kind': kind.label,
      if (label != null) 'label': label,
      if (data.isNotEmpty) 'data': data,
    };
  }

  String get signature => styioStableJson(toStableJson());
}

class StyioProjectDependency {
  const StyioProjectDependency({
    required this.name,
    required this.kind,
    required this.requirement,
    this.packageName,
    this.pathSource,
    this.targetModuleId,
    this.platforms = const <String>[],
  });

  final String name;
  final StyioDependencyKind kind;
  final String requirement;
  final String? packageName;
  final String? pathSource;
  final String? targetModuleId;
  final List<String> platforms;

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'name': name,
      'kind': kind.label,
      'requirement': requirement,
      if (packageName != null) 'packageName': packageName,
      if (pathSource != null) 'pathSource': styioNormalizePath(pathSource!),
      if (targetModuleId != null) 'targetModuleId': targetModuleId,
      if (platforms.isNotEmpty) 'platforms': List<String>.from(platforms)..sort(),
    };
  }
}

class StyioProjectTarget {
  const StyioProjectTarget({
    required this.id,
    required this.moduleId,
    required this.kind,
    required this.name,
    required this.path,
  });

  final String id;
  final String moduleId;
  final StyioTargetKind kind;
  final String name;
  final String path;

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'id': id,
      'moduleId': moduleId,
      'kind': kind.label,
      'name': name,
      'path': styioNormalizePath(path),
    };
  }
}

class StyioProjectModule {
  const StyioProjectModule({
    required this.id,
    required this.name,
    required this.version,
    required this.rootPath,
    required this.manifestPath,
    this.platforms = const <String>[],
    this.dependencies = const <StyioProjectDependency>[],
    this.targets = const <StyioProjectTarget>[],
    this.isWorkspaceMember = false,
  });

  final String id;
  final String name;
  final String version;
  final String rootPath;
  final String manifestPath;
  final List<String> platforms;
  final List<StyioProjectDependency> dependencies;
  final List<StyioProjectTarget> targets;
  final bool isWorkspaceMember;

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'version': version,
      'rootPath': styioNormalizePath(rootPath),
      'manifestPath': styioNormalizePath(manifestPath),
      'platforms': List<String>.from(platforms)..sort(),
      'dependencies': dependencies
          .map((dependency) => dependency.toStableJson())
          .toList(growable: false)
        ..sort((left, right) => styioStableJson(left).compareTo(styioStableJson(right))),
      'targets': targets.map((target) => target.toStableJson()).toList(growable: false)
        ..sort((left, right) => (left['id'] as String).compareTo(right['id'] as String)),
      'isWorkspaceMember': isWorkspaceMember,
    };
  }
}

class StyioToolchainSelection {
  const StyioToolchainSelection({
    this.channel,
    this.version,
    this.platforms = const <String>[],
    this.pinPath,
  });

  final String? channel;
  final String? version;
  final List<String> platforms;
  final String? pinPath;

  bool get isEmpty =>
      channel == null && version == null && platforms.isEmpty && pinPath == null;

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      if (channel != null) 'channel': channel,
      if (version != null) 'version': version,
      if (platforms.isNotEmpty) 'platforms': List<String>.from(platforms)..sort(),
      if (pinPath != null) 'pinPath': styioNormalizePath(pinPath!),
    };
  }
}

class StyioGraphDiagnostic {
  const StyioGraphDiagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.source,
  });

  final StyioGraphDiagnosticSeverity severity;
  final StyioGraphDiagnosticCode code;
  final String message;
  final String? source;

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'severity': severity.label,
      'code': code.label,
      'message': message,
      if (source != null) 'source': source,
    };
  }
}

class StyioProjectGraph {
  const StyioProjectGraph({
    required this.workspaceRootUri,
    required this.nodes,
    required this.edges,
    required this.modules,
    required this.targets,
    required this.canonicalFiles,
    required this.toolchain,
    this.workspaceMembers = const <String>[],
    this.diagnostics = const <StyioGraphDiagnostic>[],
  });

  final Uri workspaceRootUri;
  final Map<String, StyioProjectNode> nodes;
  final List<StyioProjectEdge> edges;
  final List<StyioProjectModule> modules;
  final List<StyioProjectTarget> targets;
  final List<StyioCanonicalProjectFile> canonicalFiles;
  final StyioToolchainSelection toolchain;
  final List<String> workspaceMembers;
  final List<StyioGraphDiagnostic> diagnostics;

  bool get isEmpty => modules.isEmpty;

  bool get hasErrors => diagnostics.any(
        (diagnostic) =>
            diagnostic.severity == StyioGraphDiagnosticSeverity.error,
      );

  bool get hasCycles => diagnostics.any(
        (diagnostic) =>
            diagnostic.code == StyioGraphDiagnosticCode.dependencyCycle,
      );

  Map<String, List<String>> moduleDependencyGraph({
    bool includeDevDependencies = false,
  }) {
    final graph = <String, List<String>>{
      for (final module in modules) module.id: <String>[],
    };
    final moduleIds = graph.keys.toSet();
    for (final edge in edges) {
      final includeEdge = edge.kind == StyioProjectEdgeKind.moduleDependency ||
          (includeDevDependencies &&
              edge.kind == StyioProjectEdgeKind.devDependency);
      if (!includeEdge || !moduleIds.contains(edge.from) || !moduleIds.contains(edge.to)) {
        continue;
      }
      graph[edge.from]!.add(edge.to);
    }
    for (final entry in graph.entries) {
      entry.value.sort();
    }
    return graph;
  }

  Map<String, Object?> toStableJson() {
    return <String, Object?>{
      'workspaceRootUri': workspaceRootUri.toString(),
      'canonicalFiles': canonicalFiles
          .map((file) => file.toStableJson())
          .toList(growable: false)
        ..sort((left, right) => (left['path'] as String).compareTo(right['path'] as String)),
      'nodes': nodes.values.map((node) => node.toStableJson()).toList(growable: false)
        ..sort((left, right) => (left['id'] as String).compareTo(right['id'] as String)),
      'edges': edges.map((edge) => edge.toStableJson()).toList(growable: false)
        ..sort((left, right) => styioStableJson(left).compareTo(styioStableJson(right))),
      'modules': modules
          .map((module) => module.toStableJson())
          .toList(growable: false)
        ..sort((left, right) => (left['id'] as String).compareTo(right['id'] as String)),
      'targets': targets.map((target) => target.toStableJson()).toList(growable: false)
        ..sort((left, right) => (left['id'] as String).compareTo(right['id'] as String)),
      'toolchain': toolchain.toStableJson(),
      'workspaceMembers': List<String>.from(workspaceMembers)..sort(),
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toStableJson())
          .toList(growable: false)
        ..sort((left, right) => styioStableJson(left).compareTo(styioStableJson(right))),
    };
  }
}

class StyioProjectGraphDiff {
  const StyioProjectGraphDiff({
    required this.previousHash,
    required this.nextHash,
    this.addedNodes = const <StyioProjectNode>[],
    this.removedNodes = const <StyioProjectNode>[],
    this.changedNodes = const <StyioProjectNode>[],
    this.addedEdges = const <StyioProjectEdge>[],
    this.removedEdges = const <StyioProjectEdge>[],
    this.changedEdges = const <StyioProjectEdge>[],
    this.addedCanonicalFiles = const <StyioCanonicalProjectFile>[],
    this.removedCanonicalFiles = const <StyioCanonicalProjectFile>[],
    this.changedCanonicalFiles = const <StyioCanonicalProjectFile>[],
  });

  final String previousHash;
  final String nextHash;
  final List<StyioProjectNode> addedNodes;
  final List<StyioProjectNode> removedNodes;
  final List<StyioProjectNode> changedNodes;
  final List<StyioProjectEdge> addedEdges;
  final List<StyioProjectEdge> removedEdges;
  final List<StyioProjectEdge> changedEdges;
  final List<StyioCanonicalProjectFile> addedCanonicalFiles;
  final List<StyioCanonicalProjectFile> removedCanonicalFiles;
  final List<StyioCanonicalProjectFile> changedCanonicalFiles;

  bool get hasChanges =>
      previousHash != nextHash ||
      addedNodes.isNotEmpty ||
      removedNodes.isNotEmpty ||
      changedNodes.isNotEmpty ||
      addedEdges.isNotEmpty ||
      removedEdges.isNotEmpty ||
      changedEdges.isNotEmpty ||
      addedCanonicalFiles.isNotEmpty ||
      removedCanonicalFiles.isNotEmpty ||
      changedCanonicalFiles.isNotEmpty;
}

StyioCanonicalProjectFileKind? styioCanonicalProjectFileKindForPath(
  String path,
) {
  final name = styioBasename(path);
  switch (name) {
    case 'styio.toml':
    case '.styio.toml':
    case 'spio.toml':
      return StyioCanonicalProjectFileKind.manifest;
    case 'styio.lock':
    case 'spio.lock':
      return StyioCanonicalProjectFileKind.lockfile;
    case 'styio-toolchain.toml':
    case 'spio-toolchain.toml':
      return StyioCanonicalProjectFileKind.toolchainPin;
    case 'styio.workspace.toml':
      return StyioCanonicalProjectFileKind.workspaceConfig;
  }
  return null;
}

bool styioIsCanonicalProjectFilePath(String path) =>
    styioCanonicalProjectFileKindForPath(path) != null;

String styioBasename(String path) {
  final normalized = styioNormalizePath(path);
  final slash = normalized.lastIndexOf('/');
  return slash == -1 ? normalized : normalized.substring(slash + 1);
}

String styioDirname(String path) {
  final normalized = styioNormalizePath(path);
  final slash = normalized.lastIndexOf('/');
  if (slash == -1) {
    return '.';
  }
  if (slash == 0) {
    return '/';
  }
  return normalized.substring(0, slash);
}

String styioNormalizePath(String path) {
  final replaced = path.replaceAll('\\', '/');
  final isAbsolute = replaced.startsWith('/');
  final parts = <String>[];
  for (final part in replaced.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (parts.isNotEmpty && parts.last != '..') {
        parts.removeLast();
      } else if (!isAbsolute) {
        parts.add(part);
      }
      continue;
    }
    parts.add(part);
  }
  final normalized = parts.join('/');
  if (isAbsolute) {
    return normalized.isEmpty ? '/' : '/$normalized';
  }
  return normalized.isEmpty ? '.' : normalized;
}

String styioJoinPath(String base, String relative) {
  final normalizedRelative = relative.replaceAll('\\', '/');
  if (normalizedRelative.startsWith('/')) {
    return styioNormalizePath(normalizedRelative);
  }
  if (base == '.' || base.isEmpty) {
    return styioNormalizePath(normalizedRelative);
  }
  return styioNormalizePath('$base/$normalizedRelative');
}

String styioModuleId(String moduleName) => 'module:$moduleName';

String styioStableJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${styioStableJson(value[key])}').join(',')}}';
  }
  if (value is Iterable) {
    return '[${value.map(styioStableJson).join(',')}]';
  }
  return jsonEncode(value);
}
