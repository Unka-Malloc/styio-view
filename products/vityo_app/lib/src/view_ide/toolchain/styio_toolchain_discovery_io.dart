import '../environment/environment.dart';
import 'toolchain_catalog.dart';

const List<String> _defaultStyioExecutableCandidates = <String>[
  '/usr/local/bin/styio',
  '/usr/bin/styio',
  '/opt/homebrew/bin/styio',
  '/home/linuxbrew/.linuxbrew/bin/styio',
];

Future<ToolchainCatalog> createPlatformStyioLanguageToolchainCatalog({
  required PlatformManagerBundle platformManagers,
  Map<String, String> environment = const <String, String>{},
  Iterable<String> candidatePaths = _defaultStyioExecutableCandidates,
}) async {
  final catalog = ToolchainCatalog();
  final executablePath = await _discoverManagedStyioExecutablePath(
    platformManagers,
    environment: environment,
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

Future<String?> _discoverManagedStyioExecutablePath(
  PlatformManagerBundle platformManagers, {
  required Map<String, String> environment,
  required Iterable<String> candidatePaths,
}) async {
  final isWindows =
      platformManagers.context.fileSystem.operatingSystem.toLowerCase() ==
      'windows';
  final override = environment['VITYO_STYIO_BIN'];
  for (final candidate in _styioExecutableCandidates(override, isWindows)) {
    if (await _isExecutablePath(platformManagers, candidate)) {
      return candidate;
    }
  }

  for (final candidate in candidatePaths) {
    for (final executable in _styioExecutableCandidates(candidate, isWindows)) {
      if (await _isExecutablePath(platformManagers, executable)) {
        return executable;
      }
    }
  }

  return null;
}

Iterable<String> _styioExecutableCandidates(
  String? path,
  bool isWindows,
) sync* {
  if (path == null || path.isEmpty) {
    return;
  }
  if (isWindows && !_hasWindowsExecutableExtension(path)) {
    yield '$path.exe';
    yield '$path.cmd';
    yield '$path.bat';
  }
  yield path;
}

bool _hasWindowsExecutableExtension(String path) {
  return RegExp(r'\.(bat|cmd|com|exe)$', caseSensitive: false).hasMatch(path);
}

Future<bool> _isExecutablePath(
  PlatformManagerBundle platformManagers,
  String? path,
) async {
  if (path == null || path.isEmpty) {
    return false;
  }
  try {
    if (!await platformManagers.fileSystem.exists(path)) {
      return false;
    }
    return await platformManagers.fileSystem.isExecutable(path);
  } on Object {
    return false;
  }
}
