import '../environment/environment.dart';
import 'clang_cpp_version_parser.dart';
import 'toolchain_catalog.dart';

const List<String> _defaultClangCandidatePaths = <String>[
  '/usr/bin/clang',
  '/usr/local/bin/clang',
  '/opt/homebrew/bin/clang',
  '/home/linuxbrew/.linuxbrew/bin/clang',
];

const List<String> _defaultClangxxCandidatePaths = <String>[
  '/usr/bin/clang++',
  '/usr/local/bin/clang++',
  '/opt/homebrew/bin/clang++',
  '/home/linuxbrew/.linuxbrew/bin/clang++',
];

const List<String> _defaultCmakeCandidatePaths = <String>[
  '/usr/bin/cmake',
  '/usr/local/bin/cmake',
  '/opt/homebrew/bin/cmake',
  '/home/linuxbrew/.linuxbrew/bin/cmake',
];

const List<String> _defaultNinjaCandidatePaths = <String>[
  '/usr/bin/ninja',
  '/usr/local/bin/ninja',
  '/opt/homebrew/bin/ninja',
  '/home/linuxbrew/.linuxbrew/bin/ninja',
];

const List<String> _defaultClangdCandidatePaths = <String>[
  '/usr/bin/clangd',
  '/usr/local/bin/clangd',
  '/opt/homebrew/bin/clangd',
  '/home/linuxbrew/.linuxbrew/bin/clangd',
];

const List<String> _defaultLldbCandidatePaths = <String>[
  '/usr/bin/lldb',
  '/usr/local/bin/lldb',
  '/opt/homebrew/bin/lldb',
  '/home/linuxbrew/.linuxbrew/bin/lldb',
];

const List<String> _defaultGdbCandidatePaths = <String>[
  '/usr/bin/gdb',
  '/usr/local/bin/gdb',
  '/opt/homebrew/bin/gdb',
  '/home/linuxbrew/.linuxbrew/bin/gdb',
];

const List<String> _defaultClangFormatCandidatePaths = <String>[
  '/usr/bin/clang-format',
  '/usr/local/bin/clang-format',
  '/opt/homebrew/bin/clang-format',
  '/home/linuxbrew/.linuxbrew/bin/clang-format',
];

const List<String> _defaultClangTidyCandidatePaths = <String>[
  '/usr/bin/clang-tidy',
  '/usr/local/bin/clang-tidy',
  '/opt/homebrew/bin/clang-tidy',
  '/home/linuxbrew/.linuxbrew/bin/clang-tidy',
];

const List<String> _defaultCtestCandidatePaths = <String>[
  '/usr/bin/ctest',
  '/usr/local/bin/ctest',
  '/opt/homebrew/bin/ctest',
  '/home/linuxbrew/.linuxbrew/bin/ctest',
];

Future<ToolchainCatalog> createPlatformNativeCompilerToolchainCatalog({
  required PlatformManagerBundle platformManagers,
  Map<String, String> environment = const <String, String>{},
  Iterable<String> cCompilerCandidatePaths = _defaultClangCandidatePaths,
  Iterable<String> cxxCompilerCandidatePaths = _defaultClangxxCandidatePaths,
  Iterable<String> cmakeCandidatePaths = _defaultCmakeCandidatePaths,
  Iterable<String> ninjaCandidatePaths = _defaultNinjaCandidatePaths,
  Iterable<String> clangdCandidatePaths = _defaultClangdCandidatePaths,
  Iterable<String> lldbCandidatePaths = _defaultLldbCandidatePaths,
  Iterable<String> gdbCandidatePaths = _defaultGdbCandidatePaths,
  Iterable<String> clangFormatCandidatePaths =
      _defaultClangFormatCandidatePaths,
  Iterable<String> clangTidyCandidatePaths = _defaultClangTidyCandidatePaths,
  Iterable<String> ctestCandidatePaths = _defaultCtestCandidatePaths,
  Future<String?> Function(String executablePath)? clangVersionOutputProbe,
}) async {
  final catalog = ToolchainCatalog();
  final effectiveEnvironment = environment;
  Future<String?> discover(
    String overrideKey,
    String executableName,
    Iterable<String> candidatePaths,
  ) => _discoverManagedExecutablePath(
    platformManagers,
    overrideKey: overrideKey,
    executableName: executableName,
    environment: effectiveEnvironment,
    candidatePaths: candidatePaths,
  );
  final cCompilerPath = await discover(
    'VITYO_CLANG_BIN',
    'clang',
    cCompilerCandidatePaths,
  );
  final cxxCompilerPath = await discover(
    'VITYO_CLANGXX_BIN',
    'clang++',
    cxxCompilerCandidatePaths,
  );
  final cmakePath = await discover(
    'VITYO_CMAKE_BIN',
    'cmake',
    cmakeCandidatePaths,
  );
  final ninjaPath = await discover(
    'VITYO_NINJA_BIN',
    'ninja',
    ninjaCandidatePaths,
  );
  final clangdPath = await discover(
    'VITYO_CLANGD_BIN',
    'clangd',
    clangdCandidatePaths,
  );
  final lldbPath = await discover('VITYO_LLDB_BIN', 'lldb', lldbCandidatePaths);
  final gdbPath = await discover('VITYO_GDB_BIN', 'gdb', gdbCandidatePaths);
  final clangFormatPath = await discover(
    'VITYO_CLANG_FORMAT_BIN',
    'clang-format',
    clangFormatCandidatePaths,
  );
  final clangTidyPath = await discover(
    'VITYO_CLANG_TIDY_BIN',
    'clang-tidy',
    clangTidyCandidatePaths,
  );
  final ctestPath = await discover(
    'VITYO_CTEST_BIN',
    'ctest',
    ctestCandidatePaths,
  );

  if (cCompilerPath != null && cxxCompilerPath != null) {
    final clangVersionFacts = parseClangCppVersionOutput(
      await (clangVersionOutputProbe == null
          ? _probeClangVersionOutput(
              cxxCompilerPath,
              platformManagers: platformManagers,
              environment: effectiveEnvironment,
            )
          : clangVersionOutputProbe(cxxCompilerPath)),
    );
    catalog.register(
      ToolchainDescriptor(
        id: 'native-clang-cpp-compiler',
        kind: ToolchainKind.compiler,
        displayName: 'Clang C/C++ Compiler',
        executablePath: cxxCompilerPath,
        version: clangVersionFacts?.version,
        metadata: <String, Object?>{
          'source': 'platform-discovery',
          'compilerFamily': 'clang',
          'cCompilerPath': cCompilerPath,
          'cxxCompilerPath': cxxCompilerPath,
          'languages': const <String>['c', 'cpp'],
          'defaultForNativeCode': true,
          if (clangVersionFacts != null) ...clangVersionFacts.toMetadata(),
        },
      ),
      activate: true,
    );
  }

  if (cmakePath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-cmake-build-tool',
        kind: ToolchainKind.buildTool,
        displayName: 'CMake Build System',
        executablePath: cmakePath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'cmake',
          'toolRole': 'build-system-generator',
          'projectModel': 'cmake',
          'supportsPresets': true,
          'languages': <String>['c', 'cpp'],
        },
      ),
    );
  }
  if (ninjaPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-ninja-build-tool',
        kind: ToolchainKind.buildTool,
        displayName: 'Ninja Build Tool',
        executablePath: ninjaPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'ninja',
          'toolRole': 'build-executor',
          'buildSystem': 'ninja',
          'languages': <String>['c', 'cpp'],
        },
      ),
    );
  }
  if (clangdPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-clangd-language-service',
        kind: ToolchainKind.languageService,
        displayName: 'clangd C/C++ Language Server',
        executablePath: clangdPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'clangd',
          'toolRole': 'native-language-service',
          'languages': <String>['c', 'cpp'],
          'consumesCompileCommands': true,
        },
      ),
    );
  }
  if (lldbPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-lldb-debugger',
        kind: ToolchainKind.debugger,
        displayName: 'LLDB Native Debugger',
        executablePath: lldbPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'lldb',
          'toolRole': 'native-debugger',
          'debuggerKind': 'lldb',
          'languages': <String>['c', 'cpp'],
        },
      ),
    );
  }
  if (gdbPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-gdb-debugger',
        kind: ToolchainKind.debugger,
        displayName: 'GDB Native Debugger',
        executablePath: gdbPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'gdb',
          'toolRole': 'native-debugger',
          'debuggerKind': 'gdb',
          'languages': <String>['c', 'cpp'],
        },
      ),
    );
  }
  if (clangFormatPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-clang-format-formatter',
        kind: ToolchainKind.formatter,
        displayName: 'clang-format Formatter',
        executablePath: clangFormatPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'clang-format',
          'toolRole': 'formatter',
          'languages': <String>['c', 'cpp'],
          'configurationFiles': <String>['.clang-format', '_clang-format'],
        },
      ),
    );
  }
  if (clangTidyPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-clang-tidy-static-analyzer',
        kind: ToolchainKind.staticAnalyzer,
        displayName: 'clang-tidy Static Analyzer',
        executablePath: clangTidyPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'clang-tidy',
          'toolRole': 'static-analysis',
          'languages': <String>['c', 'cpp'],
          'consumesCompileCommands': true,
          'configurationFiles': <String>['.clang-tidy'],
        },
      ),
    );
  }
  if (ctestPath != null) {
    catalog.register(
      ToolchainDescriptor(
        id: 'native-ctest-test-runner',
        kind: ToolchainKind.testRunner,
        displayName: 'CTest Test Runner',
        executablePath: ctestPath,
        metadata: const <String, Object?>{
          'source': 'platform-discovery',
          'toolFamily': 'ctest',
          'toolRole': 'test-runner',
          'projectModel': 'cmake',
          'supportsPresets': true,
          'languages': <String>['c', 'cpp'],
        },
      ),
    );
  }
  return catalog;
}

Future<String?> _probeClangVersionOutput(
  String executablePath, {
  required PlatformManagerBundle platformManagers,
  required Map<String, String> environment,
}) async {
  try {
    final result = await platformManagers.process.run(
      ProcessCommandRequest(
        executablePath: executablePath,
        arguments: const <String>['--version'],
        environment: environment,
      ),
    );
    if (!result.succeeded) {
      return null;
    }
    return '${result.stdout}\n${result.stderr}'.trim();
  } on Object {
    return null;
  }
}

Future<String?> _discoverManagedExecutablePath(
  PlatformManagerBundle platformManagers, {
  required String overrideKey,
  required String executableName,
  required Map<String, String> environment,
  required Iterable<String> candidatePaths,
}) async {
  final isWindows =
      platformManagers.context.fileSystem.operatingSystem.toLowerCase() ==
      'windows';
  final override = environment[overrideKey];
  for (final candidate in _executableCandidates(override, isWindows)) {
    if (await _isExecutablePath(platformManagers, candidate)) {
      return candidate;
    }
  }

  for (final candidate in candidatePaths) {
    for (final executable in _executableCandidates(candidate, isWindows)) {
      if (await _isExecutablePath(platformManagers, executable)) {
        return executable;
      }
    }
  }

  final lookupExecutable = isWindows ? 'where.exe' : 'which';
  final lookup = await platformManagers.process.run(
    ProcessCommandRequest(
      executablePath: lookupExecutable,
      arguments: <String>[executableName],
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

Iterable<String> _executableCandidates(String? path, bool isWindows) sync* {
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
