import 'dart:convert';

import '../src/view_ide/backend_toolchain/project_graph_contract.dart';
import '../src/view_ide/environment/system_compatibility/process/process.dart';

/// Consumes the system compiler through `styio --machine-info=json`.
///
/// Vityo does not ask Pafio for compiler discovery or inspect Pafio storage.
class StyioCompilerAdapter {
  const StyioCompilerAdapter({
    required this.binaryPath,
    required this.processManager,
    this.environment = const <String, String>{},
  });

  final String binaryPath;
  final ProcessManager processManager;
  final Map<String, String> environment;

  Future<CompilerHandshakeSnapshot?> inspect() async {
    try {
      final result = await processManager.run(
        ProcessCommandRequest(
          executablePath: binaryPath,
          arguments: const <String>['--machine-info=json'],
          environment: environment,
          serviceKind: ProcessServiceKind.styio,
        ),
      );
      if (!result.succeeded) return null;
      return decode(result.stdout, binaryPath: binaryPath);
    } on Object {
      return null;
    }
  }

  static CompilerHandshakeSnapshot decode(
    String payload, {
    required String binaryPath,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (error) {
      throw StyioCompilerContractException(
        'styio --machine-info=json emitted invalid JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const StyioCompilerContractException(
        'styio --machine-info=json must emit one JSON object.',
      );
    }
    final contracts = <String, List<int>>{};
    final rawContracts =
        decoded['supported_contract_versions'] ??
        decoded['supported_contracts'];
    if (rawContracts is Map<String, dynamic>) {
      for (final entry in rawContracts.entries) {
        final versions = entry.value;
        if (versions is List) {
          contracts[entry.key] = versions
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false);
        }
      }
    }
    return CompilerHandshakeSnapshot(
      binaryPath: binaryPath,
      tool: decoded['tool'] as String? ?? 'styio',
      compilerVersion: decoded['compiler_version'] as String? ?? 'unknown',
      channel: decoded['channel'] as String? ?? 'unknown',
      variant: decoded['variant'] as String? ?? 'unknown',
      capabilities: (decoded['capabilities'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false),
      supportedContractVersions: contracts,
      integrationPhase:
          decoded['active_integration_phase'] as String? ??
          (contracts['compile_plan']?.isNotEmpty == true
              ? 'compile-plan-live'
              : 'system-compiler'),
      supportedAdapterModes:
          (decoded['supported_adapter_modes'] as List? ?? const <Object>[])
              .whereType<String>()
              .toList(growable: false),
      featureFlags: _boolMap(decoded['feature_flags']),
    );
  }
}

class StyioCompilerContractException implements Exception {
  const StyioCompilerContractException(this.message);

  final String message;

  @override
  String toString() => 'StyioCompilerContractException: $message';
}

Map<String, bool> _boolMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    return const <String, bool>{};
  }
  return <String, bool>{
    for (final entry in value.entries)
      if (entry.value is bool) entry.key: entry.value as bool,
  };
}
