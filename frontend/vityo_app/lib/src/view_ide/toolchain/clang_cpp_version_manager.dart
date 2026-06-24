import 'clang_cpp_version_configuration.dart';
import 'toolchain_catalog.dart';
import 'toolchain_manager.dart';

enum ClangCppVersionPreferenceStatus {
  configured,
  activeDefault,
  missingPreferred,
  unselected,
  unavailable,
}

class ClangCppVersionCandidate {
  const ClangCppVersionCandidate({
    required this.versionId,
    required this.displayName,
    required this.cCompilerPath,
    required this.cxxCompilerPath,
    this.version,
    this.source,
    this.metadata = const <String, Object?>{},
  });

  final String versionId;
  final String displayName;
  final String cCompilerPath;
  final String cxxCompilerPath;
  final String? version;
  final String? source;
  final Map<String, Object?> metadata;

  static ClangCppVersionCandidate? fromDescriptor(
    ToolchainDescriptor descriptor,
  ) {
    if (descriptor.kind != ToolchainKind.compiler) {
      return null;
    }
    if (_stringValue(descriptor.metadata['compilerFamily']) != 'clang') {
      return null;
    }
    final cCompilerPath = _stringValue(descriptor.metadata['cCompilerPath']);
    final cxxCompilerPath = _stringValue(
      descriptor.metadata['cxxCompilerPath'],
    );
    if (cCompilerPath == null || cxxCompilerPath == null) {
      return null;
    }
    return ClangCppVersionCandidate(
      versionId: descriptor.id,
      displayName: descriptor.displayName,
      cCompilerPath: cCompilerPath,
      cxxCompilerPath: cxxCompilerPath,
      version:
          descriptor.version ??
          _stringValue(descriptor.metadata['clangVersion']) ??
          _stringValue(descriptor.metadata['version']),
      source: _stringValue(descriptor.metadata['source']),
      metadata: Map<String, Object?>.unmodifiable(descriptor.metadata),
    );
  }

  Map<String, Object?> toManifest() {
    return <String, Object?>{
      'versionId': versionId,
      'displayName': displayName,
      'cCompilerPath': cCompilerPath,
      'cxxCompilerPath': cxxCompilerPath,
      if (version != null) 'version': version,
      if (source != null) 'source': source,
      'metadata': metadata,
    };
  }
}

class ClangCppVersionSelection {
  const ClangCppVersionSelection({
    required this.candidate,
    required this.cppStandard,
    required this.cmakeAvailable,
    required this.ninjaAvailable,
    this.cmakeExecutablePath,
    this.ninjaExecutablePath,
  });

  final ClangCppVersionCandidate candidate;
  final CppLanguageStandard cppStandard;
  final bool cmakeAvailable;
  final bool ninjaAvailable;
  final String? cmakeExecutablePath;
  final String? ninjaExecutablePath;

  List<ClangCppBuildEngineHandoff> get buildEngineHandoffs {
    final handoffs = <ClangCppBuildEngineHandoff>[];
    if (cmakeExecutablePath != null && ninjaExecutablePath != null) {
      handoffs.add(
        ClangCppBuildEngineHandoff(
          engineFamily: 'cmake',
          executablePath: cmakeExecutablePath!,
          generatorFamily: 'ninja',
          arguments: cmakeNinjaConfigureArguments,
        ),
      );
    }
    if (cmakeExecutablePath != null) {
      handoffs.add(
        ClangCppBuildEngineHandoff(
          engineFamily: 'cmake',
          executablePath: cmakeExecutablePath!,
          arguments: cmakeConfigureArguments,
        ),
      );
    }
    if (ninjaExecutablePath != null) {
      handoffs.add(
        ClangCppBuildEngineHandoff(
          engineFamily: 'ninja',
          executablePath: ninjaExecutablePath!,
          environment: ninjaEnvironment(),
        ),
      );
    }
    return List<ClangCppBuildEngineHandoff>.unmodifiable(handoffs);
  }

  ClangCppBuildEngineHandoff? get preferredBuildEngineHandoff {
    final handoffs = buildEngineHandoffs;
    return handoffs.isEmpty ? null : handoffs.first;
  }

  List<String> get cmakeConfigureArguments {
    return <String>[
      '-DCMAKE_C_COMPILER=${candidate.cCompilerPath}',
      '-DCMAKE_CXX_COMPILER=${candidate.cxxCompilerPath}',
      '-DCMAKE_CXX_STANDARD=${cppStandard.cmakeValue}',
      '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
      '-DCMAKE_CXX_EXTENSIONS=OFF',
      '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
    ];
  }

  List<String> get cmakeNinjaConfigureArguments {
    if (ninjaExecutablePath == null) {
      return cmakeConfigureArguments;
    }
    return <String>[
      '-G',
      'Ninja',
      ...cmakeConfigureArguments,
      '-DCMAKE_MAKE_PROGRAM=$ninjaExecutablePath',
    ];
  }

  Map<String, String> ninjaEnvironment({
    Map<String, String> baseEnvironment = const <String, String>{},
  }) {
    final environment = Map<String, String>.of(baseEnvironment);
    environment['CC'] = candidate.cCompilerPath;
    environment['CXX'] = candidate.cxxCompilerPath;
    final existingCxxFlags = environment['CXXFLAGS'];
    environment['CXXFLAGS'] =
        existingCxxFlags == null || existingCxxFlags.trim().isEmpty
        ? cppStandard.compilerFlag
        : '$existingCxxFlags ${cppStandard.compilerFlag}';
    return Map<String, String>.unmodifiable(environment);
  }

  Map<String, Object?> toManifest() {
    return <String, Object?>{
      'candidate': candidate.toManifest(),
      'cppStandard': cppStandard.cmakeValue,
      'cmakeAvailable': cmakeAvailable,
      if (cmakeExecutablePath != null)
        'cmakeExecutablePath': cmakeExecutablePath,
      'ninjaAvailable': ninjaAvailable,
      if (ninjaExecutablePath != null)
        'ninjaExecutablePath': ninjaExecutablePath,
      'cmakeConfigureArguments': cmakeConfigureArguments,
      if (ninjaExecutablePath != null)
        'cmakeNinjaConfigureArguments': cmakeNinjaConfigureArguments,
      'ninjaEnvironment': ninjaEnvironment(),
      'buildEngineHandoffs': buildEngineHandoffs
          .map((handoff) => handoff.toManifest())
          .toList(growable: false),
      if (preferredBuildEngineHandoff != null)
        'preferredBuildEngineHandoff': preferredBuildEngineHandoff!
            .toManifest(),
    };
  }
}

class ClangCppBuildEngineHandoff {
  const ClangCppBuildEngineHandoff({
    required this.engineFamily,
    required this.executablePath,
    this.generatorFamily,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
  });

  final String engineFamily;
  final String executablePath;
  final String? generatorFamily;
  final List<String> arguments;
  final Map<String, String> environment;

  Map<String, Object?> toManifest() {
    return <String, Object?>{
      'engineFamily': engineFamily,
      'executablePath': executablePath,
      if (generatorFamily != null) 'generatorFamily': generatorFamily,
      'arguments': arguments,
      if (environment.isNotEmpty) 'environment': environment,
    };
  }
}

class ClangCppVersionManager {
  ClangCppVersionManager({
    required Iterable<ClangCppVersionCandidate> candidates,
    required this.activeVersionId,
    required this.cmakeAvailable,
    required this.ninjaAvailable,
    this.defaultCppStandard = CppLanguageStandard.cpp20,
    this.requestedVersionId,
    this.preferenceStatus = ClangCppVersionPreferenceStatus.activeDefault,
    this.preferenceMessage,
    this.cmakeToolchainId,
    this.cmakeExecutablePath,
    this.ninjaToolchainId,
    this.ninjaExecutablePath,
  }) : candidates = List<ClangCppVersionCandidate>.unmodifiable(candidates);

  factory ClangCppVersionManager.fromCatalog(
    ToolchainCatalog catalog, {
    CppLanguageStandard defaultCppStandard = CppLanguageStandard.cpp20,
    ClangCppVersionPreference? preference,
  }) {
    final candidates = catalog
        .list(kind: ToolchainKind.compiler)
        .map(ClangCppVersionCandidate.fromDescriptor)
        .whereType<ClangCppVersionCandidate>()
        .toList(growable: false);
    final activeCandidate = ClangCppVersionCandidate.fromDescriptor(
      catalog.active(ToolchainKind.compiler) ??
          const ToolchainDescriptor(
            id: '',
            kind: ToolchainKind.compiler,
            displayName: '',
            executablePath: '',
          ),
    );
    final resolution = _resolvePreference(
      candidates,
      preference?.versionId,
      fallbackVersionId: activeCandidate?.versionId,
    );
    final cmake = _selectCatalogBuildTool(catalog, 'cmake');
    final ninja = _selectCatalogBuildTool(catalog, 'ninja');
    return ClangCppVersionManager(
      candidates: candidates,
      activeVersionId: resolution.selectedVersionId,
      cmakeAvailable: cmake != null,
      ninjaAvailable: ninja != null,
      defaultCppStandard: preference?.cppStandard ?? defaultCppStandard,
      requestedVersionId: preference?.versionId,
      preferenceStatus: resolution.status,
      preferenceMessage: resolution.message,
      cmakeToolchainId: cmake?.id,
      cmakeExecutablePath: cmake?.executablePath,
      ninjaToolchainId: ninja?.id,
      ninjaExecutablePath: ninja?.executablePath,
    );
  }

  factory ClangCppVersionManager.fromSnapshot(
    ToolchainStateSnapshot? snapshot, {
    CppLanguageStandard defaultCppStandard = CppLanguageStandard.cpp20,
    ClangCppVersionPreference? preference,
  }) {
    if (snapshot == null) {
      return ClangCppVersionManager(
        candidates: const <ClangCppVersionCandidate>[],
        activeVersionId: null,
        cmakeAvailable: false,
        ninjaAvailable: false,
        defaultCppStandard: preference?.cppStandard ?? defaultCppStandard,
        requestedVersionId: preference?.versionId,
        preferenceStatus: ClangCppVersionPreferenceStatus.unavailable,
        preferenceMessage: 'No toolchain snapshot is available.',
      );
    }
    final candidates = snapshot
        .list(kind: ToolchainKind.compiler)
        .map(_descriptorFromStateEntry)
        .map(ClangCppVersionCandidate.fromDescriptor)
        .whereType<ClangCppVersionCandidate>()
        .toList(growable: false);
    final activeEntry = snapshot.active(ToolchainKind.compiler);
    final activeCandidate = activeEntry == null
        ? null
        : ClangCppVersionCandidate.fromDescriptor(
            _descriptorFromStateEntry(activeEntry),
          );
    final resolution = _resolvePreference(
      candidates,
      preference?.versionId,
      fallbackVersionId: activeCandidate?.versionId,
    );
    final cmake = _selectSnapshotBuildTool(snapshot, 'cmake');
    final ninja = _selectSnapshotBuildTool(snapshot, 'ninja');
    return ClangCppVersionManager(
      candidates: candidates,
      activeVersionId: resolution.selectedVersionId,
      cmakeAvailable: cmake != null,
      ninjaAvailable: ninja != null,
      defaultCppStandard: preference?.cppStandard ?? defaultCppStandard,
      requestedVersionId: preference?.versionId,
      preferenceStatus: resolution.status,
      preferenceMessage: resolution.message,
      cmakeToolchainId: cmake?.id,
      cmakeExecutablePath: cmake?.executablePath,
      ninjaToolchainId: ninja?.id,
      ninjaExecutablePath: ninja?.executablePath,
    );
  }

  final List<ClangCppVersionCandidate> candidates;
  final String? activeVersionId;
  final String? requestedVersionId;
  final bool cmakeAvailable;
  final bool ninjaAvailable;
  final CppLanguageStandard defaultCppStandard;
  final ClangCppVersionPreferenceStatus preferenceStatus;
  final String? preferenceMessage;
  final String? cmakeToolchainId;
  final String? cmakeExecutablePath;
  final String? ninjaToolchainId;
  final String? ninjaExecutablePath;

  bool get hasCandidates => candidates.isNotEmpty;

  ClangCppVersionCandidate? get activeCandidate {
    if (activeVersionId != null) {
      return candidateFor(activeVersionId!);
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  ClangCppVersionCandidate? candidateFor(String versionId) {
    for (final candidate in candidates) {
      if (candidate.versionId == versionId) {
        return candidate;
      }
    }
    return null;
  }

  ClangCppVersionSelection? select({
    String? versionId,
    CppLanguageStandard? cppStandard,
  }) {
    final candidate = versionId == null
        ? activeCandidate
        : candidateFor(versionId);
    if (candidate == null) {
      return null;
    }
    return ClangCppVersionSelection(
      candidate: candidate,
      cppStandard: cppStandard ?? defaultCppStandard,
      cmakeAvailable: cmakeAvailable,
      ninjaAvailable: ninjaAvailable,
      cmakeExecutablePath: cmakeExecutablePath,
      ninjaExecutablePath: ninjaExecutablePath,
    );
  }

  Map<String, Object?> toManifest() {
    return <String, Object?>{
      'activeVersionId': activeVersionId,
      if (requestedVersionId != null) 'requestedVersionId': requestedVersionId,
      'preferenceStatus': preferenceStatus.name,
      if (preferenceMessage != null) 'preferenceMessage': preferenceMessage,
      'defaultCppStandard': defaultCppStandard.cmakeValue,
      'cmakeAvailable': cmakeAvailable,
      if (cmakeToolchainId != null) 'cmakeToolchainId': cmakeToolchainId,
      if (cmakeExecutablePath != null)
        'cmakeExecutablePath': cmakeExecutablePath,
      'ninjaAvailable': ninjaAvailable,
      if (ninjaToolchainId != null) 'ninjaToolchainId': ninjaToolchainId,
      if (ninjaExecutablePath != null)
        'ninjaExecutablePath': ninjaExecutablePath,
      'candidates': candidates
          .map((candidate) => candidate.toManifest())
          .toList(growable: false),
    };
  }

  static ToolchainDescriptor? _selectCatalogBuildTool(
    ToolchainCatalog catalog,
    String toolFamily,
  ) {
    final active = catalog.active(ToolchainKind.buildTool);
    if (_stringValue(active?.metadata['toolFamily']) == toolFamily) {
      return active;
    }
    for (final descriptor in catalog.list(kind: ToolchainKind.buildTool)) {
      if (_stringValue(descriptor.metadata['toolFamily']) == toolFamily) {
        return descriptor;
      }
    }
    return null;
  }

  static ToolchainStateEntry? _selectSnapshotBuildTool(
    ToolchainStateSnapshot snapshot,
    String toolFamily,
  ) {
    final active = snapshot.active(ToolchainKind.buildTool);
    if (_stringValue(active?.metadata['toolFamily']) == toolFamily) {
      return active;
    }
    for (final entry in snapshot.list(kind: ToolchainKind.buildTool)) {
      if (_stringValue(entry.metadata['toolFamily']) == toolFamily) {
        return entry;
      }
    }
    return null;
  }

  static _ClangCppPreferenceResolution _resolvePreference(
    Iterable<ClangCppVersionCandidate> candidates,
    String? preferredVersionId, {
    String? fallbackVersionId,
  }) {
    final candidateList = candidates.toList(growable: false);
    if (candidateList.isEmpty) {
      return const _ClangCppPreferenceResolution(
        status: ClangCppVersionPreferenceStatus.unavailable,
        selectedVersionId: null,
        message: 'No Clang/C++ compiler candidates are registered.',
      );
    }
    if (preferredVersionId != null) {
      for (final candidate in candidateList) {
        if (candidate.versionId == preferredVersionId) {
          return _ClangCppPreferenceResolution(
            status: ClangCppVersionPreferenceStatus.configured,
            selectedVersionId: preferredVersionId,
            message: null,
          );
        }
      }
      if (fallbackVersionId != null) {
        return _ClangCppPreferenceResolution(
          status: ClangCppVersionPreferenceStatus.missingPreferred,
          selectedVersionId: fallbackVersionId,
          message:
              'Configured Clang/C++ version $preferredVersionId is not available; using active compiler $fallbackVersionId.',
        );
      }
      return _ClangCppPreferenceResolution(
        status: ClangCppVersionPreferenceStatus.missingPreferred,
        selectedVersionId: candidateList.length == 1
            ? candidateList.single.versionId
            : null,
        message:
            'Configured Clang/C++ version $preferredVersionId is not available.',
      );
    }
    if (fallbackVersionId != null) {
      return _ClangCppPreferenceResolution(
        status: ClangCppVersionPreferenceStatus.activeDefault,
        selectedVersionId: fallbackVersionId,
        message: null,
      );
    }
    if (candidateList.length == 1) {
      return _ClangCppPreferenceResolution(
        status: ClangCppVersionPreferenceStatus.activeDefault,
        selectedVersionId: candidateList.single.versionId,
        message: null,
      );
    }
    return const _ClangCppPreferenceResolution(
      status: ClangCppVersionPreferenceStatus.unselected,
      selectedVersionId: null,
      message: 'Multiple Clang/C++ candidates exist, but none is active.',
    );
  }
}

class _ClangCppPreferenceResolution {
  const _ClangCppPreferenceResolution({
    required this.status,
    required this.selectedVersionId,
    required this.message,
  });

  final ClangCppVersionPreferenceStatus status;
  final String? selectedVersionId;
  final String? message;
}

ToolchainDescriptor _descriptorFromStateEntry(ToolchainStateEntry entry) {
  return ToolchainDescriptor(
    id: entry.id,
    kind: entry.kind,
    displayName: entry.displayName,
    executablePath: entry.executablePath,
    version: entry.version,
    channel: entry.channel,
    metadata: entry.metadata,
  );
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
