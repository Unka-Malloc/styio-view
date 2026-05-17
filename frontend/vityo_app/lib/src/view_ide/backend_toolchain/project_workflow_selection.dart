import 'dart:io';

import 'project_graph_contract.dart';

class ProjectWorkflowSelection {
  const ProjectWorkflowSelection({
    required this.command,
    required this.kind,
    required this.args,
    required this.successMessage,
    this.packageName,
    this.targetName,
    this.targetKind,
  });

  final String command;
  final String kind;
  final List<String> args;
  final String successMessage;
  final String? packageName;
  final String? targetName;
  final String? targetKind;
}

ProjectWorkflowSelection selectProjectWorkflow({
  required ProjectGraphSnapshot projectGraph,
  required String activeFilePath,
}) {
  ProjectTargetDescriptor? target;
  for (final candidate in projectGraph.targets) {
    if (candidate.filePath == activeFilePath) {
      target = candidate;
      break;
    }
  }

  if (target == null) {
    final packageName = packageNameForPath(
      projectGraph: projectGraph,
      activeFilePath: activeFilePath,
    );
    final packageTargets = packageName == null
        ? const <ProjectTargetDescriptor>[]
        : projectGraph.targets
              .where((candidate) => candidate.packageName == packageName)
              .toList(growable: false);
    if (packageTargets.length == 1) {
      target = packageTargets.single;
    } else if (projectGraph.targets.length == 1) {
      target = projectGraph.targets.single;
    } else {
      return ProjectWorkflowSelection(
        command: 'build',
        kind: 'build',
        args: packageName == null ? const <String>[] : packageArgs(packageName),
        successMessage: packageName == null
            ? 'Project build completed through spio.'
            : 'Project package build completed through spio.',
        packageName: packageName,
      );
    }
  }

  switch (target.kind) {
    case ProjectTargetKind.test:
      return ProjectWorkflowSelection(
        command: 'test',
        kind: 'test',
        args: <String>[
          ...packageArgs(target.packageName),
          '--test',
          target.name,
        ],
        successMessage: 'Project test target completed through spio.',
        packageName: target.packageName,
        targetName: target.name,
        targetKind: target.kind.label,
      );
    case ProjectTargetKind.lib:
      return ProjectWorkflowSelection(
        command: 'build',
        kind: 'build',
        args: <String>[...packageArgs(target.packageName), '--lib'],
        successMessage: 'Project library build completed through spio.',
        packageName: target.packageName,
        targetKind: target.kind.label,
      );
    case ProjectTargetKind.bin:
      return ProjectWorkflowSelection(
        command: 'run',
        kind: 'run',
        args: <String>[
          ...packageArgs(target.packageName),
          '--bin',
          target.name,
        ],
        successMessage: 'Project binary run completed through spio.',
        packageName: target.packageName,
        targetName: target.name,
        targetKind: target.kind.label,
      );
  }
}

List<String> packageArgs(String packageName) {
  if (packageName.isEmpty) {
    return const <String>[];
  }
  return <String>['--package', packageName];
}

String? packageNameForPath({
  required ProjectGraphSnapshot projectGraph,
  required String activeFilePath,
}) {
  if (!_isAbsolutePath(activeFilePath)) {
    return null;
  }

  for (final package in projectGraph.packages) {
    if (_pathIsWithinRoot(activeFilePath, package.rootPath)) {
      return package.packageName;
    }
  }
  return null;
}

bool _pathIsWithinRoot(String path, String rootPath) {
  if (!_isAbsolutePath(path) || !_isAbsolutePath(rootPath)) {
    return false;
  }

  final absolutePath = File(path).absolute.path;
  final absoluteRoot = Directory(rootPath).absolute.path;
  if (absolutePath == absoluteRoot) {
    return true;
  }
  final prefix = absoluteRoot.endsWith(Platform.pathSeparator)
      ? absoluteRoot
      : '$absoluteRoot${Platform.pathSeparator}';
  return absolutePath.startsWith(prefix);
}

bool _isAbsolutePath(String path) {
  return path.startsWith(Platform.pathSeparator) ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}
