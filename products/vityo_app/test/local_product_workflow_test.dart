import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/owner_adapters/pafio_metadata_adapter.dart';
import 'package:vityo_app/owner_adapters/styio_compiler_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';

const _reportMarker = 'VITYO_PRODUCT_REPORT ';

void main() {
  final enabled = _enabled(Platform.environment['VITYO_PRODUCT_GATE']);

  test(
    'real Pafio metadata and system Styio contracts compose a local project',
    () async {
      final pafioBinary = _requiredEnvironment('VITYO_PAFIO_BIN');
      final manifestPath = _requiredEnvironment(
        'VITYO_PRODUCT_MANIFEST_PATH',
      );
      final styioBinary = _requiredEnvironment('VITYO_STYIO_BIN');
      final environment = <String, String>{
        ...Platform.environment,
        'VITYO_STYIO_BIN': styioBinary,
      };

      final metadata = await PafioMetadataAdapter(
        binaryPath: pafioBinary,
      ).load(manifestPath: manifestPath);
      final compiler = await StyioCompilerAdapter(
        environment: environment,
      ).inspect();
      expect(compiler, isNotNull);

      final graph = metadata.toProjectGraph(activeCompiler: compiler);
      expect(graph.manifestPath, manifestPath);
      expect(graph.hasAuthoritativeProjectGraphFacts, isTrue);
      expect(
        graph.toolchain.source,
        ToolchainResolutionSource.environment,
      );

      final report = <String, Object?>{
        'scenario': 'vityo-owner-adapters',
        'ok': true,
        'metadata': 'v1',
        'compiler': 'machine-info',
        'package_count': graph.packages.length,
        'target_count': graph.targets.length,
      };
      // The external product gate consumes this one-line machine report.
      stdout.writeln('$_reportMarker${jsonEncode(report)}');
    },
    skip: enabled ? false : 'requires VITYO_PRODUCT_GATE=1',
  );
}

bool _enabled(String? value) {
  return const <String>{'1', 'true', 'yes', 'on'}.contains(
    value?.trim().toLowerCase(),
  );
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required by the opt-in product gate.');
  }
  return value;
}
