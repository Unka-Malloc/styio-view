import 'dart:convert';
import 'dart:io';

import '../src/view_ide/backend_toolchain/project_graph_contract.dart';

/// Vityo's only local Pafio project-model entry is `pafio metadata --json`.
///
/// The adapter deliberately consumes the public metadata v1 document. It does
/// not inspect pafio.toml, pafio.lock, project cache directories, or Pafio's
/// process environment.
class PafioMetadataAdapter {
  const PafioMetadataAdapter({required this.binaryPath});

  final String binaryPath;

  Future<PafioMetadataDocument> load({required String manifestPath}) async {
    final result = await Process.run(binaryPath, <String>[
      'metadata',
      '--json',
      '--manifest-path',
      manifestPath,
    ]);
    if (result.exitCode != 0) {
      throw PafioMetadataException(
        'pafio metadata --json exited with code ${result.exitCode}: '
        '${_boundedText(result.stderr)}',
      );
    }
    return decode(result.stdout as String);
  }

  static PafioMetadataDocument decode(String payload) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (error) {
      throw PafioMetadataException(
        'pafio metadata --json emitted invalid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PafioMetadataException(
        'pafio metadata --json must emit one JSON object.',
      );
    }
    return PafioMetadataDocument.fromJson(decoded);
  }
}

class PafioMetadataDocument {
  PafioMetadataDocument._({
    required this.package,
    required this.workspace,
    required this.dependencies,
    required this.targets,
    required this.lock,
    required this.resolution,
    required this.vendor,
  });

  static const Set<String> _topLevelFields = <String>{
    'package',
    'workspace',
    'dependencies',
    'targets',
    'lock',
    'resolution',
    'vendor',
  };

  final Map<String, dynamic> package;
  final Map<String, dynamic> workspace;
  final List<Map<String, dynamic>> dependencies;
  final List<Map<String, dynamic>> targets;
  final Map<String, dynamic> lock;
  final Map<String, dynamic> resolution;
  final Map<String, dynamic> vendor;

  factory PafioMetadataDocument.fromJson(Map<String, dynamic> payload) {
    final actualFields = payload.keys.toSet();
    if (actualFields.length != _topLevelFields.length ||
        !actualFields.containsAll(_topLevelFields)) {
      throw const PafioMetadataException(
        'Pafio metadata v1 must contain exactly package, workspace, '
        'dependencies, targets, lock, resolution, and vendor.',
      );
    }
    return PafioMetadataDocument._(
      package: _object(payload, 'package'),
      workspace: _object(payload, 'workspace'),
      dependencies: _objectList(payload, 'dependencies'),
      targets: _objectList(payload, 'targets'),
      lock: _object(payload, 'lock'),
      resolution: _object(payload, 'resolution'),
      vendor: _object(payload, 'vendor'),
    );
  }

  ProjectGraphSnapshot toProjectGraph({
    CompilerHandshakeSnapshot? activeCompiler,
  }) {
    final workspaceRoot = _requiredString(workspace, 'root', 'workspace');
    final manifestPath = _requiredString(
      workspace,
      'manifest_path',
      'workspace',
    );
    final members = _stringList(workspace, 'members');
    final rawPackages = _objectList(workspace, 'packages');
    final packageById = <String, Map<String, dynamic>>{
      for (final item in rawPackages)
        _requiredString(item, 'id', 'workspace package'): item,
    };

    final targetsByPackageId = <String, List<ProjectTargetDescriptor>>{};
    final projectTargets = targets
        .map((target) {
          final packageId = _requiredString(target, 'package_id', 'target');
          final packageName = _requiredString(
            packageById[packageId] ?? const <String, dynamic>{},
            'name',
            'target package',
          );
          final kind = _targetKind(_requiredString(target, 'kind', 'target'));
          final name = _requiredString(target, 'name', 'target');
          final descriptor = ProjectTargetDescriptor(
            id: '$packageId:${kind.label}:$name',
            packageName: packageName,
            kind: kind,
            name: name,
            filePath: _requiredString(target, 'path', 'target'),
          );
          targetsByPackageId
              .putIfAbsent(packageId, () => <ProjectTargetDescriptor>[])
              .add(descriptor);
          return descriptor;
        })
        .toList(growable: false);

    final dependenciesByPackageId = <String, List<ProjectDependencySnapshot>>{};
    final projectDependencies = dependencies
        .map((dependency) {
          final parentId = _requiredString(
            dependency,
            'parent_package_id',
            'dependency',
          );
          final source = _object(dependency, 'source');
          final sourceKind = _dependencySourceKind(
            _requiredString(source, 'kind', 'dependency source'),
          );
          final location = _requiredString(
            source,
            'location',
            'dependency source',
          );
          final requirement = dependency['requirement'];
          if (requirement != null && requirement is! String) {
            throw const PafioMetadataException(
              'dependency.requirement must be a string or null.',
            );
          }
          final snapshot = ProjectDependencySnapshot(
            sourcePackageName: _requiredString(
              packageById[parentId] ?? const <String, dynamic>{},
              'name',
              'dependency parent package',
            ),
            dependencyName: _requiredString(dependency, 'alias', 'dependency'),
            kind: _dependencyKind(
              _requiredString(dependency, 'kind', 'dependency'),
            ),
            requirement: requirement as String? ?? '',
            packageIdentity: _requiredString(
              dependency,
              'package',
              'dependency',
            ),
            sourceKind: sourceKind,
            pathSource: sourceKind == ProjectDependencySourceKind.path
                ? location
                : null,
            gitSource: sourceKind == ProjectDependencySourceKind.git
                ? location
                : null,
            gitRevision: source['rev'] as String?,
            registryRoot: sourceKind == ProjectDependencySourceKind.registry
                ? location
                : null,
            requestedVersion: requirement,
            publishBlocking:
                sourceKind != ProjectDependencySourceKind.registry ||
                requirement == null,
          );
          dependenciesByPackageId
              .putIfAbsent(parentId, () => <ProjectDependencySnapshot>[])
              .add(snapshot);
          return snapshot;
        })
        .toList(growable: false);

    final projectPackages = rawPackages
        .map((rawPackage) {
          final packageId = _requiredString(
            rawPackage,
            'id',
            'workspace package',
          );
          return ProjectPackageSnapshot(
            packageName: _requiredString(
              rawPackage,
              'name',
              'workspace package',
            ),
            version: _requiredString(
              rawPackage,
              'version',
              'workspace package',
            ),
            rootPath: _requiredString(rawPackage, 'root', 'workspace package'),
            manifestPath: _requiredString(
              rawPackage,
              'manifest_path',
              'workspace package',
            ),
            targets: List<ProjectTargetDescriptor>.unmodifiable(
              targetsByPackageId[packageId] ??
                  const <ProjectTargetDescriptor>[],
            ),
            dependencies: List<ProjectDependencySnapshot>.unmodifiable(
              dependenciesByPackageId[packageId] ??
                  const <ProjectDependencySnapshot>[],
            ),
            isWorkspaceMember: rawPackage['source_kind'] == 'workspace',
            publishEnabled: rawPackage['publish'] == true,
          );
        })
        .toList(growable: false);

    final rootPackageIds = _stringList(workspace, 'root_package_ids');
    final rootPackageName = package['name'] as String?;
    final hasWorkspace = members.isNotEmpty || rootPackageIds.length > 1;
    final projectKind = hasWorkspace
        ? (package.isEmpty ? ProjectKind.workspace : ProjectKind.combinedRoot)
        : ProjectKind.package;
    final editorFiles = projectTargets
        .map((target) => target.filePath)
        .toSet()
        .toList(growable: false);

    return ProjectGraphSnapshot(
      id: manifestPath,
      title: rootPackageName ?? 'Workspace Project',
      kind: projectKind,
      workspaceRoot: workspaceRoot,
      workspaceMembers: members,
      manifestPath: manifestPath,
      lockfilePath: _optionalString(lock, 'path'),
      vendorRoot: _optionalString(vendor, 'root'),
      packages: projectPackages,
      dependencies: projectDependencies,
      targets: projectTargets,
      editorFiles: editorFiles,
      toolchain: activeCompiler == null
          ? const ToolchainStatusSnapshot(
              source: ToolchainResolutionSource.unavailable,
              detail:
                  'System Styio was not discovered through its public machine contract.',
            )
          : ToolchainStatusSnapshot(
              source: ToolchainResolutionSource.environment,
              detail:
                  'System Styio ${activeCompiler.compilerVersion} reported its public machine contract.',
              channel: activeCompiler.channel,
              version: activeCompiler.compilerVersion,
            ),
      lockState: lock['present'] == true
          ? ProjectLockState.unknown
          : ProjectLockState.missing,
      vendorState: vendor['present'] == true
          ? ProjectVendorState.present
          : ProjectVendorState.missing,
      activeCompiler: activeCompiler,
      sourceConfidenceByField:
          ProjectGraphSnapshot.machinePayloadSourceConfidence(),
      notes: const <String>[
        'Project facts loaded exclusively from Pafio metadata v1.',
      ],
    );
  }
}

class PafioMetadataException implements Exception {
  const PafioMetadataException(this.message);

  final String message;

  @override
  String toString() => 'PafioMetadataException: $message';
}

Map<String, dynamic> _object(Map<String, dynamic> parent, String field) {
  final value = parent[field];
  if (value is! Map<String, dynamic>) {
    throw PafioMetadataException('$field must be a JSON object.');
  }
  return value;
}

List<Map<String, dynamic>> _objectList(
  Map<String, dynamic> parent,
  String field,
) {
  final value = parent[field];
  if (value is! List) {
    throw PafioMetadataException('$field must be a JSON array.');
  }
  final result = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      throw PafioMetadataException('$field entries must be JSON objects.');
    }
    result.add(item);
  }
  return List<Map<String, dynamic>>.unmodifiable(result);
}

List<String> _stringList(Map<String, dynamic> parent, String field) {
  final value = parent[field];
  if (value is! List || value.any((item) => item is! String)) {
    throw PafioMetadataException('$field must be an array of strings.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

String _requiredString(
  Map<String, dynamic> parent,
  String field,
  String context,
) {
  final value = parent[field];
  if (value is! String || value.isEmpty) {
    throw PafioMetadataException('$context.$field must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> parent, String field) {
  final value = parent[field];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw PafioMetadataException('$field must be a string or null.');
  }
  return value;
}

ProjectTargetKind _targetKind(String value) {
  return switch (value) {
    'lib' => ProjectTargetKind.lib,
    'bin' => ProjectTargetKind.bin,
    'test' => ProjectTargetKind.test,
    _ => throw PafioMetadataException('unsupported target kind: $value'),
  };
}

ProjectDependencyKind _dependencyKind(String value) {
  return switch (value) {
    'normal' => ProjectDependencyKind.runtime,
    'dev' => ProjectDependencyKind.dev,
    _ => throw PafioMetadataException('unsupported dependency kind: $value'),
  };
}

ProjectDependencySourceKind _dependencySourceKind(String value) {
  return switch (value) {
    'path' => ProjectDependencySourceKind.path,
    'git' => ProjectDependencySourceKind.git,
    'registry' => ProjectDependencySourceKind.registry,
    _ => throw PafioMetadataException(
      'unsupported dependency source kind: $value',
    ),
  };
}

String _boundedText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.length <= 512 ? text : '${text.substring(0, 512)}…';
}
