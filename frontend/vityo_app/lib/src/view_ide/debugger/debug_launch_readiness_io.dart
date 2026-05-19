import 'dart:io';

import 'debug_launch_contract.dart';

typedef DebugExecutableLookup = Future<String?> Function(String executableName);
typedef DebugPathExists = Future<bool> Function(String path);

class DebugLaunchIoReadiness {
  const DebugLaunchIoReadiness({
    required this.ready,
    required this.reason,
    this.resolvedDebuggerExecutablePath,
  });

  final bool ready;
  final String reason;
  final String? resolvedDebuggerExecutablePath;
}

class DebugLaunchIoReadinessProbe {
  const DebugLaunchIoReadinessProbe({
    this.lookupExecutable = _lookupExecutable,
    this.fileExists = _fileExists,
    this.directoryExists = _directoryExists,
  });

  final DebugExecutableLookup lookupExecutable;
  final DebugPathExists fileExists;
  final DebugPathExists directoryExists;

  Future<DebugLaunchIoReadiness> check(DebugLaunchConfiguration launch) async {
    if (!launch.ready) {
      return DebugLaunchIoReadiness(ready: false, reason: launch.reason);
    }
    final resolvedDebugger = await _resolveDebuggerExecutable(
      launch.debuggerExecutablePath,
    );
    if (resolvedDebugger == null) {
      return DebugLaunchIoReadiness(
        ready: false,
        reason:
            'Debug launch blocked: debugger executable ${launch.debuggerExecutablePath} is not available.',
      );
    }
    final programPath = launch.programPath;
    if (programPath == null || !await fileExists(programPath)) {
      return DebugLaunchIoReadiness(
        ready: false,
        reason:
            'Debug launch blocked: program ${programPath ?? '<missing>'} does not exist.',
        resolvedDebuggerExecutablePath: resolvedDebugger,
      );
    }
    if (!await directoryExists(launch.cwd)) {
      return DebugLaunchIoReadiness(
        ready: false,
        reason: 'Debug launch blocked: cwd ${launch.cwd} does not exist.',
        resolvedDebuggerExecutablePath: resolvedDebugger,
      );
    }
    return DebugLaunchIoReadiness(
      ready: true,
      reason: 'Debug launch IO prerequisites are available.',
      resolvedDebuggerExecutablePath: resolvedDebugger,
    );
  }

  Future<String?> _resolveDebuggerExecutable(String executablePath) async {
    final trimmed = executablePath.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (_looksLikePath(trimmed)) {
      return await fileExists(trimmed) ? trimmed : null;
    }
    return lookupExecutable(trimmed);
  }
}

bool _looksLikePath(String value) {
  return value.startsWith('/') ||
      value.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
      value.contains('/') ||
      value.contains(r'\');
}

Future<String?> _lookupExecutable(String executableName) async {
  final result = await Process.run('/bin/sh', <String>[
    '-c',
    r'command -v "$1"',
    'vityo-debug-launch-lookup',
    executableName,
  ]);
  if (result.exitCode != 0) {
    return null;
  }
  final output = result.stdout.toString().trim();
  return output.isEmpty ? null : output.split('\n').first.trim();
}

Future<bool> _fileExists(String path) {
  return File(path).exists();
}

Future<bool> _directoryExists(String path) {
  return Directory(path).exists();
}
