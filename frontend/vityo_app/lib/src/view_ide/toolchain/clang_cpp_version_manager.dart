import 'toolchain_catalog.dart';
import 'toolchain_manager.dart';

enum CppLanguageStandard {
  cpp14(cmakeValue: '14', compilerFlag: '-std=c++14'),
  cpp17(cmakeValue: '17', compilerFlag: '-std=c++17'),
  cpp20(cmakeValue: '20', compilerFlag: '-std=c++20'),
  cpp23(cmakeValue: '23', compilerFlag: '-std=c++23'),
  cpp26(cmakeValue: '26', compilerFlag: '-std=c++26');

  const CppLanguageStandard({
    required this.cmakeValue,
    required this.compilerFlag,
  });

  final String cmakeValue;
  final String compilerFlag;
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
  });

  final ClangCppVersionCandidate candidate;
  final CppLanguageStandard cppStandard;
  final bool cmakeAvailable;
  final bool ninjaAvailable;

  List<String> get cmakeConfigureArguments {
    return <String>[
      '-DCMAKE_C_COMPILER=${candidate.cCompilerPath}',
      '-DCMAKE_CXX_COMPILER=${candidate.cxxCompilerPath}',
      '-DCMAKE_CXX_STANDARD=${cppStandard.cmakeValue}',
      '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
      '-DCMAKE_CXX_EXTENSIONS=OFF',
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
      'ninjaAvailable': ninjaAvailable,
      'cmakeConfigureArguments': cmakeConfigureArguments,
      'ninjaEnvironment': ninjaEnvironment(),
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
  }) : candidates = List<ClangCppVersionCandidate>.unmodifiable(candidates);

  factory ClangCppVersionManager.fromCatalog(
    ToolchainCatalog catalog, {
    CppLanguageStandard defaultCppStandard = CppLanguageStandard.cpp20,
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
    return ClangCppVersionManager(
      candidates: candidates,
      activeVersionId: activeCandidate?.versionId,
      cmakeAvailable: _hasBuildTool(catalog, 'cmake'),
      ninjaAvailable: _hasBuildTool(catalog, 'ninja'),
      defaultCppStandard: defaultCppStandard,
    );
  }

  factory ClangCppVersionManager.fromSnapshot(
    ToolchainStateSnapshot? snapshot, {
    CppLanguageStandard defaultCppStandard = CppLanguageStandard.cpp20,
  }) {
    if (snapshot == null) {
      return ClangCppVersionManager(
        candidates: const <ClangCppVersionCandidate>[],
        activeVersionId: null,
        cmakeAvailable: false,
        ninjaAvailable: false,
        defaultCppStandard: defaultCppStandard,
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
    return ClangCppVersionManager(
      candidates: candidates,
      activeVersionId: activeCandidate?.versionId,
      cmakeAvailable: _snapshotHasBuildTool(snapshot, 'cmake'),
      ninjaAvailable: _snapshotHasBuildTool(snapshot, 'ninja'),
      defaultCppStandard: defaultCppStandard,
    );
  }

  final List<ClangCppVersionCandidate> candidates;
  final String? activeVersionId;
  final bool cmakeAvailable;
  final bool ninjaAvailable;
  final CppLanguageStandard defaultCppStandard;

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
    );
  }

  Map<String, Object?> toManifest() {
    return <String, Object?>{
      'activeVersionId': activeVersionId,
      'defaultCppStandard': defaultCppStandard.cmakeValue,
      'cmakeAvailable': cmakeAvailable,
      'ninjaAvailable': ninjaAvailable,
      'candidates': candidates
          .map((candidate) => candidate.toManifest())
          .toList(growable: false),
    };
  }

  static bool _hasBuildTool(ToolchainCatalog catalog, String toolFamily) {
    return catalog.list(kind: ToolchainKind.buildTool).any((descriptor) {
      return _stringValue(descriptor.metadata['toolFamily']) == toolFamily;
    });
  }

  static bool _snapshotHasBuildTool(
    ToolchainStateSnapshot snapshot,
    String toolFamily,
  ) {
    return snapshot.list(kind: ToolchainKind.buildTool).any((entry) {
      return _stringValue(entry.metadata['toolFamily']) == toolFamily;
    });
  }
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
