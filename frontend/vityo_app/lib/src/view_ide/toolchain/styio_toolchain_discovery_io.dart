import 'dart:io' as io;

import '../environment/environment.dart';
import 'toolchain_catalog.dart';

const List<String> _defaultStyioExecutableCandidates = <String>[
  '/usr/local/bin/styio',
  '/usr/bin/styio',
  '/opt/homebrew/bin/styio',
  '/home/linuxbrew/.linuxbrew/bin/styio',
];

Future<ToolchainCatalog> createPlatformStyioLanguageToolchainCatalog({
  PlatformManagerBundle? platformManagers,
  Map<String, String>? environment,
  Iterable<String> candidatePaths = _defaultStyioExecutableCandidates,
}) async {
  final catalog = ToolchainCatalog();
  final executablePath = platformManagers == null
      ? _discoverLocalStyioExecutablePath(
          environment: environment ?? io.Platform.environment,
          candidatePaths: candidatePaths,
        )
      : await _discoverManagedStyioExecutablePath(
          platformManagers,
          environment: environment ?? const <String, String>{},
          candidatePaths: candidatePaths,
        );
  if (executablePath == null) {
    return catalog;
  }

  catalog.register(
    ToolchainDescriptor(
      id: 'local-styio-language-service',
      kind: ToolchainKind.languageService,
      displayName: 'Local Styio Language Service',
      executablePath: executablePath,
      metadata: const <String, Object?>{
        'source': 'platform-discovery',
        'contract': 'styio-cli-jsonl-v1',
      },
    ),
    activate: true,
  );
  return catalog;
}

String? _discoverLocalStyioExecutablePath({
  required Map<String, String> environment,
  required Iterable<String> candidatePaths,
}) {
  final override = environment['VITYO_STYIO_BIN'];
  if (_isExecutableFile(override)) {
    return override;
  }

  for (final candidate in candidatePaths) {
    if (_isExecutableFile(candidate)) {
      return candidate;
    }
  }

  try {
    final result = io.Process.runSync('which', const <String>['styio']);
    if (result.exitCode == 0) {
      final path = result.stdout.toString().trim();
      if (_isExecutableFile(path)) {
        return path;
      }
    }
  } on Object {
    return null;
  }

  return null;
}

Future<String?> _discoverManagedStyioExecutablePath(
  PlatformManagerBundle platformManagers, {
  required Map<String, String> environment,
  required Iterable<String> candidatePaths,
}) async {
  final override = environment['VITYO_STYIO_BIN'];
  if (await _isExecutablePath(platformManagers, override)) {
    return override;
  }

  for (final candidate in candidatePaths) {
    if (await _isExecutablePath(platformManagers, candidate)) {
      return candidate;
    }
  }

  final lookupExecutable =
      platformManagers.context.fileSystem.operatingSystem.toLowerCase() ==
          'windows'
      ? 'where'
      : 'which';
  final lookup = await platformManagers.process.run(
    ProcessCommandRequest(
      executablePath: lookupExecutable,
      arguments: const <String>['styio'],
      environment: environment,
    ),
  );
  if (!lookup.succeeded) {
    return null;
  }
  for (final line in lookup.stdout.split(RegExp(r'\r?\n'))) {
    final path = line.trim();
    if (await _isExecutablePath(platformManagers, path)) {
      return path;
    }
  }
  return null;
}

Future<bool> _isExecutablePath(
  PlatformManagerBundle platformManagers,
  String? path,
) async {
  if (path == null || path.isEmpty) {
    return false;
  }
  if (!await platformManagers.fileSystem.exists(path)) {
    return false;
  }
  return platformManagers.fileSystem.isExecutable(path);
}

bool _isExecutableFile(String? path) {
  if (path == null || path.isEmpty) {
    return false;
  }
  final stat = io.FileStat.statSync(path);
  if (stat.type != io.FileSystemEntityType.file) {
    return false;
  }
  return true;
}
