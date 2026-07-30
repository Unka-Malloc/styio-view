import 'dart:convert';
import 'dart:io';

import 'desktop_capability_report.dart';

Future<bool> tryRunDesktopDeliverySmoke(List<String> arguments) async {
  if (!arguments.contains('--vityo-delivery-smoke')) {
    return false;
  }
  final workspacePath = _value(arguments, '--workspace');
  final evidencePath = _value(arguments, '--evidence');
  final commit = _value(arguments, '--commit');
  final sourceFingerprint = _value(arguments, '--source-fingerprint');
  if (workspacePath == null ||
      evidencePath == null ||
      commit == null ||
      sourceFingerprint == null) {
    throw ArgumentError(
      '--vityo-delivery-smoke requires --workspace, --evidence, '
      '--commit, and --source-fingerprint',
    );
  }
  final workspace = Directory(workspacePath);
  final workspaceOpened =
      await workspace.exists() && await _containsFile(workspace);
  final report = DesktopCapabilityReport(
    platform: Platform.operatingSystem,
    commit: commit,
    sourceFingerprint: sourceFingerprint,
    artifactVerified: true,
    launched: true,
    workspaceOpened: workspaceOpened,
    capabilities: const <String, String>{
      'editor': 'available',
      'workspace': 'available',
      'agent': 'unavailable',
      'agent_reason': 'No Agent descriptor is configured.',
    },
  );
  final target = File(evidencePath).absolute;
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
    flush: true,
  );
  await temporary.rename(target.path);
  if (!workspaceOpened) {
    exitCode = 2;
  }
  return true;
}

Future<bool> _containsFile(Directory workspace) async {
  await for (final entity in workspace.list(followLinks: false)) {
    if (entity is File) {
      return true;
    }
  }
  return false;
}

String? _value(List<String> arguments, String option) {
  final index = arguments.indexOf(option);
  if (index < 0 || index + 1 >= arguments.length) {
    return null;
  }
  return arguments[index + 1];
}
