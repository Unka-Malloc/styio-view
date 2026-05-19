import '../toolchain/toolchain_catalog.dart';

enum DebugLaunchReadiness { ready, missingProgram, unsupportedProtocol }

extension DebugLaunchReadinessX on DebugLaunchReadiness {
  String get wireValue => switch (this) {
    DebugLaunchReadiness.ready => 'ready',
    DebugLaunchReadiness.missingProgram => 'missing-program',
    DebugLaunchReadiness.unsupportedProtocol => 'unsupported-protocol',
  };
}

class DebugLaunchBreakpoint {
  const DebugLaunchBreakpoint({
    required this.filePath,
    required this.line,
    this.enabled = true,
  });

  final String filePath;
  final int line;
  final bool enabled;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'filePath': filePath,
      'line': line,
      'enabled': enabled,
    };
  }
}

class DebugLaunchConfiguration {
  const DebugLaunchConfiguration({
    required this.readiness,
    required this.reason,
    required this.debuggerId,
    required this.debuggerLabel,
    required this.debuggerExecutablePath,
    this.debuggerArguments = const <String>[],
    required this.adapterProtocol,
    required this.programPath,
    required this.cwd,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.stopOnEntry = false,
    this.breakpoints = const <DebugLaunchBreakpoint>[],
  });

  factory DebugLaunchConfiguration.fromToolchainDescriptor({
    required ToolchainDescriptor debugger,
    required String workspaceRoot,
    Iterable<DebugLaunchBreakpoint> breakpoints =
        const <DebugLaunchBreakpoint>[],
  }) {
    final protocol =
        _metadataString(debugger.metadata, 'adapterProtocol') ??
        _metadataString(debugger.metadata, 'debugAdapterProtocol') ??
        'dap';
    final normalizedProtocol = protocol.toLowerCase();
    final programPath = _resolveLaunchPath(
      _metadataString(debugger.metadata, 'programPath') ??
          _metadataString(debugger.metadata, 'launchProgram') ??
          _metadataString(debugger.metadata, 'program') ??
          _metadataString(debugger.metadata, 'executableTarget'),
      workspaceRoot,
    );
    final cwd =
        _resolveLaunchPath(
          _metadataString(debugger.metadata, 'cwd'),
          workspaceRoot,
        ) ??
        workspaceRoot;
    final List<String> arguments =
        _metadataStringList(debugger.metadata, 'arguments') ??
        _metadataStringList(debugger.metadata, 'args') ??
        const <String>[];
    final List<String> debuggerArguments =
        _metadataStringList(debugger.metadata, 'debuggerArguments') ??
        _metadataStringList(debugger.metadata, 'debugAdapterArguments') ??
        _metadataStringList(debugger.metadata, 'adapterArguments') ??
        const <String>[];
    final environment = _metadataStringMap(debugger.metadata, 'environment');
    final stopOnEntry =
        _metadataBool(debugger.metadata, 'stopOnEntry') ?? false;
    final launchBreakpoints = breakpoints.toList(growable: false);
    if (normalizedProtocol != 'dap') {
      return DebugLaunchConfiguration(
        readiness: DebugLaunchReadiness.unsupportedProtocol,
        reason:
            'Debug launch blocked: debugger ${debugger.id} uses unsupported protocol $protocol.',
        debuggerId: debugger.id,
        debuggerLabel: debugger.displayName,
        debuggerExecutablePath: debugger.executablePath,
        debuggerArguments: debuggerArguments,
        adapterProtocol: protocol,
        programPath: programPath,
        cwd: cwd,
        arguments: arguments,
        environment: environment,
        stopOnEntry: stopOnEntry,
        breakpoints: launchBreakpoints,
      );
    }
    if (programPath == null || programPath.trim().isEmpty) {
      return DebugLaunchConfiguration(
        readiness: DebugLaunchReadiness.missingProgram,
        reason:
            'Debug launch blocked: debugger ${debugger.id} does not declare metadata.programPath.',
        debuggerId: debugger.id,
        debuggerLabel: debugger.displayName,
        debuggerExecutablePath: debugger.executablePath,
        debuggerArguments: debuggerArguments,
        adapterProtocol: protocol,
        programPath: null,
        cwd: cwd,
        arguments: arguments,
        environment: environment,
        stopOnEntry: stopOnEntry,
        breakpoints: launchBreakpoints,
      );
    }
    return DebugLaunchConfiguration(
      readiness: DebugLaunchReadiness.ready,
      reason: 'Debug launch configuration is ready.',
      debuggerId: debugger.id,
      debuggerLabel: debugger.displayName,
      debuggerExecutablePath: debugger.executablePath,
      debuggerArguments: debuggerArguments,
      adapterProtocol: protocol,
      programPath: programPath,
      cwd: cwd,
      arguments: arguments,
      environment: environment,
      stopOnEntry: stopOnEntry,
      breakpoints: launchBreakpoints,
    );
  }

  final DebugLaunchReadiness readiness;
  final String reason;
  final String debuggerId;
  final String debuggerLabel;
  final String debuggerExecutablePath;
  final List<String> debuggerArguments;
  final String adapterProtocol;
  final String? programPath;
  final String cwd;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool stopOnEntry;
  final List<DebugLaunchBreakpoint> breakpoints;

  bool get ready => readiness == DebugLaunchReadiness.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'readiness': readiness.wireValue,
      'ready': ready,
      'reason': reason,
      'debuggerId': debuggerId,
      'debuggerLabel': debuggerLabel,
      'debuggerExecutablePath': debuggerExecutablePath,
      'debuggerArguments': debuggerArguments,
      'adapterProtocol': adapterProtocol,
      if (programPath != null) 'programPath': programPath,
      'cwd': cwd,
      'arguments': arguments,
      'environment': environment,
      'stopOnEntry': stopOnEntry,
      'breakpointCount': breakpoints.length,
      'breakpoints': breakpoints
          .map((breakpoint) => breakpoint.toJson())
          .toList(growable: false),
    };
  }
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool? _metadataBool(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is bool ? value : null;
}

List<String>? _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is List) {
    return value
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
  if (value is String && value.trim().isNotEmpty) {
    return <String>[value.trim()];
  }
  return null;
}

Map<String, String> _metadataStringMap(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final mapKey = entry.key;
    final mapValue = entry.value;
    if (mapKey is String && mapValue is String && mapKey.trim().isNotEmpty) {
      result[mapKey.trim()] = mapValue;
    }
  }
  return Map<String, String>.unmodifiable(result);
}

String? _resolveLaunchPath(String? path, String workspaceRoot) {
  final normalizedPath = path?.trim();
  if (normalizedPath == null || normalizedPath.isEmpty) {
    return null;
  }
  if (_isAbsolutePath(normalizedPath)) {
    return normalizedPath;
  }
  final root = workspaceRoot.trim();
  if (root.isEmpty) {
    return normalizedPath;
  }
  final separator = root.contains('\\') ? '\\' : '/';
  if (root.endsWith('/') || root.endsWith('\\')) {
    return '$root$normalizedPath';
  }
  return '$root$separator$normalizedPath';
}

bool _isAbsolutePath(String path) {
  return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}
