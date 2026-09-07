import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../environment/system_compatibility/process/process.dart';

List<String>? _debugExecutableCandidates;

void debugOverridePafioExecutableCandidates(List<String>? candidates) {
  _debugExecutableCandidates = candidates == null
      ? null
      : List<String>.unmodifiable(candidates);
}

Future<String?> resolvePafioBinary(
  PlatformManagerBundle platformManagers, {
  Map<String, String> environment = const <String, String>{},
}) async {
  final defaultCandidates = <String>[
    if (environment['VITYO_PAFIO_BIN'] case final explicit?
        when explicit.isNotEmpty)
      explicit,
    if (platformManagers.context.fileSystem.operatingSystem == 'windows')
      r'C:\Program Files\Pafio\pafio.exe'
    else ...const <String>[
      '/usr/local/bin/pafio',
      '/usr/bin/pafio',
      '/opt/homebrew/bin/pafio',
    ],
  ];
  final candidates = _debugExecutableCandidates ?? defaultCandidates;
  for (final candidate in candidates) {
    try {
      final result = await platformManagers.process.run(
        ProcessCommandRequest(
          executablePath: candidate,
          arguments: const <String>['--version'],
          environment: environment,
          timeout: const Duration(seconds: 5),
          serviceKind: ProcessServiceKind.pafio,
        ),
      );
      if (result.succeeded) return candidate;
    } on Object {
      continue;
    }
  }
  return null;
}
