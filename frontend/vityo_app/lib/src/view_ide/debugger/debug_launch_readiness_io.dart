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
  final currentExecutable = _currentExecutableFor(executableName);
  if (currentExecutable != null) {
    return currentExecutable;
  }
  final result = await _runExecutableLookup(executableName);
  if (result == null || result.exitCode != 0) {
    return null;
  }
  final output = result.stdout.toString().trim();
  return _executableLookupPathFromOutput(executableName, output);
}

String? _currentExecutableFor(String executableName) {
  final normalizedName = executableName.trim().toLowerCase();
  if (normalizedName.isEmpty) {
    return null;
  }
  final currentPath = Platform.resolvedExecutable;
  final windowsDartExecutable = _windowsDartExecutableFor(
    currentPath: currentPath,
    executableName: normalizedName,
  );
  if (windowsDartExecutable != null) {
    return windowsDartExecutable;
  }
  final currentName = currentPath
      .split(RegExp(r'[\\/]'))
      .last
      .toLowerCase();
  if (normalizedName == currentName ||
      normalizedName == currentName.replaceFirst(RegExp(r'\.exe$'), '')) {
    return currentPath;
  }
  return null;
}

String? _windowsDartExecutableFor({
  required String currentPath,
  required String executableName,
}) {
  if (!Platform.isWindows ||
      (executableName != 'dart' && executableName != 'dart.exe')) {
    return null;
  }
  final currentFile = File(currentPath);
  for (final candidate in _windowsDartExecutableCandidates(currentFile)) {
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  return null;
}

List<File> _windowsDartExecutableCandidates(File currentFile) {
  final separator = Platform.pathSeparator;
  final currentName = currentFile.path
      .split(RegExp(r'[\\/]'))
      .last
      .toLowerCase();
  return <File>[
    if (currentName == 'dart.exe') currentFile,
    File('${currentFile.path}.exe'),
    File([currentFile.parent.path, 'dart.exe'].join(separator)),
    File(
      [
        currentFile.parent.path,
        'cache',
        'dart-sdk',
        'bin',
        'dart.exe',
      ].join(separator),
    ),
  ];
}

Future<ProcessResult?> _runExecutableLookup(String executableName) async {
  try {
    if (Platform.isWindows) {
      return await Process.run('where.exe', <String>[executableName]);
    }
    return await Process.run('/bin/sh', <String>[
      '-c',
      r'command -v "$1"',
      'vityo-debug-launch-lookup',
      executableName,
    ]);
  } on Object {
    return null;
  }
}

String? _executableLookupPathFromOutput(String executableName, String output) {
  if (output.isEmpty) {
    return null;
  }
  final lines = output
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  if (Platform.isWindows &&
      (executableName.toLowerCase() == 'dart' ||
          executableName.toLowerCase() == 'dart.exe')) {
    for (final line in lines) {
      final dartExecutable = _windowsDartExecutableFor(
        currentPath: line,
        executableName: executableName.toLowerCase(),
      );
      if (dartExecutable != null) {
        return dartExecutable;
      }
    }
  }
  return lines.isEmpty ? null : lines.first;
}

Future<bool> _fileExists(String path) {
  return File(path).exists();
}

Future<bool> _directoryExists(String path) {
  return Directory(path).exists();
}
