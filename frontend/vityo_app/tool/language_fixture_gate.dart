import 'dart:convert';
import 'dart:io';

import 'package:vityo_app/src/view_ide/environment/system_compatibility/file_system/file_system_manager.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/file_system/file_system_manager_io.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/process/process_manager.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/process/process_manager_io.dart';
import 'package:vityo_app/src/view_ide/language/service/language_fixture_confidence_matrix.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_runtime.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runLanguageFixtureGateCommand(arguments);
}

Future<int> runLanguageFixtureGateCommand(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  FileSystemManager? fileSystemManager,
  ProcessManager? processManager,
  Map<String, String>? environment,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final config = LanguageFixtureGateCommandConfig.parse(
    arguments,
    environment: environment ?? Platform.environment,
  );
  if (config.help) {
    stdoutSink.writeln(LanguageFixtureGateCommandConfig.usage);
    return 0;
  }
  final fs = fileSystemManager ?? await createPlatformFileSystemManager();
  final process = processManager ?? await createPlatformProcessManager();
  final protocol = StyioCliJsonlProtocol(parserEngine: config.parserEngine);
  final catalog = ToolchainCatalog()
    ..register(
      ToolchainDescriptor(
        id: 'local-styio-language-service',
        kind: ToolchainKind.languageService,
        displayName: 'Local Styio Language Service',
        executablePath: config.styioExecutable,
        metadata: <String, Object?>{'contract': protocol.protocolVersion},
      ),
      activate: true,
    );
  final gate = StyioServiceFixtureGate.fromToolchainRuntime(
    fileSystemManager: fs,
    runtime: ToolchainRuntime(catalog: catalog, processManager: process),
    protocol: protocol,
    timeout: config.timeout,
  );
  final matrix = await gate.run(roots: config.roots);
  stderrSink.writeln(formatLanguageFixtureGateSummary(matrix));
  stdoutSink.writeln(const JsonEncoder.withIndent('  ').convert(matrix.toJson()));
  if (matrix.entries.isEmpty) {
    stderrSink.writeln('No .styio fixtures found.');
    return 1;
  }
  if (!matrix.gatePassed) {
    stderrSink.writeln(
      'Language fixture gate failed: ${matrix.failures.length} failing item(s).',
    );
    for (final failure in matrix.failures) {
      stderrSink.writeln(
        '${failure.matrixClass.name}: ${failure.path} '
        '(expected ${failure.expectation.name}, actual ${failure.actualResult.name})',
      );
    }
    return 1;
  }
  return 0;
}

String formatLanguageFixtureGateSummary(
  LanguageFixtureConfidenceMatrix matrix,
) {
  final summary = matrix.summary;
  return 'Language fixture gate: '
      '${matrix.gatePassed ? 'passed' : 'failed'}; '
      '${summary['passed']}/${summary['total']} matched; '
      'TP=${summary[LanguageFixtureConfidenceClass.truePositive.name]}, '
      'TN=${summary[LanguageFixtureConfidenceClass.trueNegative.name]}, '
      'FP=${summary[LanguageFixtureConfidenceClass.falsePositive.name]}, '
      'FN=${summary[LanguageFixtureConfidenceClass.falseNegative.name]}, '
      'unlabeled=${summary[LanguageFixtureConfidenceClass.unlabeled.name]}';
}

class LanguageFixtureGateCommandConfig {
  const LanguageFixtureGateCommandConfig({
    required this.styioExecutable,
    required this.roots,
    required this.parserEngine,
    required this.timeout,
    this.help = false,
  });

  final String styioExecutable;
  final List<String> roots;
  final String parserEngine;
  final Duration timeout;
  final bool help;

  static const String usage = '''
Usage:
  dart run tool/language_fixture_gate.dart [options] [fixture roots...]

Options:
  --styio <path>          Styio executable path. Defaults to STYIO or styio.
  --root <path>           Fixture root. Can be repeated.
  --parser-engine <name>  Styio parser engine. Defaults to nightly.
  --timeout-ms <number>   Per-fixture toolchain timeout. Defaults to 10000.
  -h, --help              Show this help.

If no fixture root is provided, the command scans the parser-backed fixture
roots used by repository CI:
  test/fixtures/language_service
  test/fixtures/styio_language/syntax_contract
''';

  static LanguageFixtureGateCommandConfig parse(
    List<String> arguments, {
    required Map<String, String> environment,
  }) {
    var styioExecutable = environment['STYIO'] ?? 'styio';
    var parserEngine = 'nightly';
    var timeout = const Duration(seconds: 10);
    var help = false;
    final roots = <String>[];
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      switch (argument) {
        case '-h':
        case '--help':
          help = true;
          break;
        case '--styio':
          styioExecutable = _requiredValue(arguments, index, argument);
          index += 1;
          break;
        case '--root':
        case '--fixture-root':
          roots.add(_requiredValue(arguments, index, argument));
          index += 1;
          break;
        case '--parser-engine':
          parserEngine = _requiredValue(arguments, index, argument);
          index += 1;
          break;
        case '--timeout-ms':
          timeout = Duration(
            milliseconds: int.parse(_requiredValue(arguments, index, argument)),
          );
          index += 1;
          break;
        default:
          roots.add(argument);
          break;
      }
    }
    return LanguageFixtureGateCommandConfig(
      styioExecutable: styioExecutable,
      roots: roots.isEmpty
          ? const <String>[
              'test/fixtures/language_service',
              'test/fixtures/styio_language/syntax_contract',
            ]
          : roots,
      parserEngine: parserEngine,
      timeout: timeout,
      help: help,
    );
  }

  static String _requiredValue(
    List<String> arguments,
    int index,
    String option,
  ) {
    final valueIndex = index + 1;
    if (valueIndex >= arguments.length) {
      throw ArgumentError('Missing value for $option.');
    }
    return arguments[valueIndex];
  }
}
