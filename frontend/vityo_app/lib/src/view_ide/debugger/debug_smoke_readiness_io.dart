import 'dart:io';

typedef ExecutableLookup = Future<String?> Function(String executableName);

class DebugSmokeReadiness {
  const DebugSmokeReadiness({
    required this.ready,
    required this.reason,
    this.adapterPath,
    this.compilerPath,
  });

  final bool ready;
  final String reason;
  final String? adapterPath;
  final String? compilerPath;
}

class CppDapSmokeReadinessProbe {
  const CppDapSmokeReadinessProbe({this.lookupExecutable = _lookupExecutable});

  final ExecutableLookup lookupExecutable;

  Future<DebugSmokeReadiness> detect({
    Map<String, String> environment = const <String, String>{},
  }) async {
    final adapterPath = await _resolveFirst(
      override: environment['VITYO_DAP_ADAPTER'],
      candidates: const <String>['lldb-dap', 'lldb-vscode', 'codelldb'],
    );
    if (adapterPath == null) {
      return const DebugSmokeReadiness(
        ready: false,
        reason:
            'Real DAP smoke blocked: no lldb-dap, lldb-vscode, or codelldb executable is available.',
      );
    }

    final compilerPath = await _resolveFirst(
      override: environment['CXX'],
      candidates: const <String>['clang++', 'g++'],
    );
    if (compilerPath == null) {
      return const DebugSmokeReadiness(
        ready: false,
        reason:
            'Real DAP smoke blocked: no C++ compiler is available from CXX, clang++, or g++.',
      );
    }

    return DebugSmokeReadiness(
      ready: true,
      reason: 'Real DAP smoke prerequisites are available.',
      adapterPath: adapterPath,
      compilerPath: compilerPath,
    );
  }

  Future<String?> _resolveFirst({
    required String? override,
    required List<String> candidates,
  }) async {
    final overrideValue = override?.trim();
    if (overrideValue != null && overrideValue.isNotEmpty) {
      return overrideValue;
    }
    for (final candidate in candidates) {
      final resolved = await lookupExecutable(candidate);
      if (resolved != null && resolved.trim().isNotEmpty) {
        return resolved;
      }
    }
    return null;
  }
}

Future<String?> _lookupExecutable(String executableName) async {
  final result = await Process.run('/bin/sh', <String>[
    '-c',
    r'command -v "$1"',
    'vityo-lookup',
    executableName,
  ]);
  if (result.exitCode != 0) {
    return null;
  }
  final output = result.stdout.toString().trim();
  return output.isEmpty ? null : output.split('\n').first.trim();
}
