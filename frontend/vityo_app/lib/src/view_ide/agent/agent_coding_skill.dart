class AgentCodingSkill {
  const AgentCodingSkill({
    required this.skillId,
    required this.title,
    required this.appliesTo,
    required this.toolchainDefaults,
    required this.instructions,
    required this.validationHints,
  });

  final String skillId;
  final String title;
  final List<String> appliesTo;
  final List<String> toolchainDefaults;
  final List<String> instructions;
  final List<String> validationHints;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'skillId': skillId,
      'title': title,
      'appliesTo': appliesTo,
      'toolchainDefaults': toolchainDefaults,
      'instructions': instructions,
      'validationHints': validationHints,
    };
  }
}

class AgentCodingSkillCatalog {
  const AgentCodingSkillCatalog._();

  static const List<AgentCodingSkill> defaultSkills = <AgentCodingSkill>[
    AgentCodingSkill(
      skillId: 'styio-language-service-truth',
      title: 'Styio Language Service Truth',
      appliesTo: <String>[
        'Styio',
        'StyioService',
        'syntax diagnostics',
        'semantic facts',
        'language service',
      ],
      toolchainDefaults: <String>[
        'Treat StyioService as the source of truth for lexing, parsing, diagnostics, semantic facts, references, completion, hover, and semantic tokens.',
        'Prefer a versioned Styio syntax contract or embedded Styio parser facade over Vityo-side grammar guesses.',
      ],
      instructions: <String>[
        'Do not invent Styio syntax when adding examples, tests, documentation, or code actions.',
        'Keep Vityo responsible for IDE workflow, UI rendering, provider orchestration, and workspace edit application.',
        'Record unimplemented Styio semantic details as explicit unsupported capability facts instead of encoding speculative parser rules in Vityo.',
      ],
      validationHints: <String>[
        'Validate Styio fixtures through the configured styio-nightly parser or the embedded StyioService syntax API when available.',
        'Keep Styio language tests in external fixture files with true/false expectations encoded in filenames.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'styio-agent-command-loop',
      title: 'Styio Agent Command Loop',
      appliesTo: <String>[
        'Styio',
        'agent coding',
        'language commands',
        'refreshLanguageService',
        'quick fix',
        'code action',
      ],
      toolchainDefaults: <String>[
        'Read language.serviceStatus.suggestedCommandIds before making syntax-sensitive edits.',
        'Use refreshLanguageService when StyioService facts are stale, degraded, unavailable, or missing semantic facts.',
        'Read language.focusedDiagnostics.suggestedCommandIds and language.codeActions before proposing manual diagnostic fixes.',
      ],
      instructions: <String>[
        'Prefer registered IDE commands over direct patches when the command exposes the needed language operation.',
        'Use previewQuickFix before applyQuickFix when the diagnostic fix may touch multiple documents.',
        'If the Styio command path is scaffolded or unavailable, report the missing command integration through capability readiness and keep the patch local to Vityo UI/workflow code.',
      ],
      validationHints: <String>[
        'Cover command-loop changes with agent context, provider prompt, or shell command tests.',
        'Assert command ids and input contracts explicitly so agents cannot invent unsupported commands.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'styio-ide-feature-loop',
      title: 'Styio IDE Feature Loop',
      appliesTo: <String>[
        'Styio',
        'completion',
        'hover',
        'diagnostics',
        'semantic tokens',
        'definition',
        'references',
        'rename',
      ],
      toolchainDefaults: <String>[
        'Build completion, hover, diagnostics, and semantic highlighting from SemanticSnapshot and resolved language facts.',
        'Use ResolvedElement and ResolvedReference for definition, references, rename, code action, and hover ownership.',
      ],
      instructions: <String>[
        'Keep feature providers thin: adapt StyioService facts to Vityo UI contracts without reimplementing language semantics.',
        'Prefer provider registry wiring for replaceable language implementations and syntax-contract upgrades.',
        'Separate raw language facts from product presentation such as sorting, filtering, widgets, and theme colors.',
      ],
      validationHints: <String>[
        'Cover every feature adapter with a test that asserts the Vityo contract shape, not only raw Styio text.',
        'Use fixture-backed diagnostics and semantic snapshots when language rules are involved.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'styio-fixture-confidence-matrix',
      title: 'Styio Fixture Confidence Matrix',
      appliesTo: <String>[
        'Styio',
        'fixture',
        'parser test',
        'syntax validation',
        'true positive',
        'false negative',
      ],
      toolchainDefaults: <String>[
        'Track expected parser outcome and actual parser result separately.',
        'Use true.styio and false.styio filename markers to make expected outcomes machine-readable.',
      ],
      instructions: <String>[
        'Classify syntax fixture results as true positive, true negative, false positive, or false negative.',
        'Treat false positives and false negatives as gate failures unless the fixture carries an explicit deferred expectation marker.',
        'Keep the confidence matrix separate from normal editor rendering and product UI code.',
      ],
      validationHints: <String>[
        'Run the batch fixture gate after changing Styio examples, language fixtures, or syntax-validation adapters.',
        'Report the exact fixture filename, expectation, actual result, and confidence class for every mismatch.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-clang-toolchain-defaults',
      title: 'C++ Clang Toolchain Defaults',
      appliesTo: <String>['C++', 'C', 'Styio compiler', 'native build tooling'],
      toolchainDefaults: <String>[
        'Prefer clang for C compilation.',
        'Prefer clang++ for C++ compilation.',
        'Prefer compile_commands.json when available.',
        'Prefer CMake compiler variables CMAKE_C_COMPILER=clang and CMAKE_CXX_COMPILER=clang++ when the project allows local compiler selection.',
      ],
      instructions: <String>[
        'Treat Clang diagnostics as the default source of compiler truth for native code.',
        'Do not replace an existing project compiler contract without explicit user approval.',
        'Keep generated build directories, compile databases, and local artifacts out of source patches unless the repository already tracks them.',
      ],
      validationHints: <String>[
        'Use targeted compiler or test commands that match the touched native files.',
        'If validation is not allowed in the current session, describe the exact command that should be run later.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-clang-version-handoff',
      title: 'C++ Clang Version Handoff',
      appliesTo: <String>[
        'C++',
        'Clang',
        'CMake',
        'Ninja',
        'agent toolchain selection',
      ],
      toolchainDefaults: <String>[
        'Use registered Clang/C++ version candidates instead of editing compiler configuration files by hand.',
        'Prefer the IDE-provided preferredBuildEngineHandoff before composing CMake or Ninja commands.',
      ],
      instructions: <String>[
        'Use selectClangCppVersion with a registered versionId and optional C++ standard before native build or test work that requires a different compiler version.',
        'After selecting a Clang/C++ version, inspect commands.lastResult.metadata.preferredBuildEngineHandoff before proposing build commands.',
        'If toolchainSelectionStatus is not selected, use the settings recovery route instead of guessing another compiler path.',
      ],
      validationHints: <String>[
        'Validate handoff changes with the narrowest available CMake configure/build or Ninja build command.',
        'When a build engine is unavailable, report the missing registered toolchain instead of inventing an executable path.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-project-orientation',
      title: 'C++ Project Orientation',
      appliesTo: <String>[
        'C++',
        'CMake',
        'Ninja',
        'Make',
        'LLVM style repositories',
      ],
      toolchainDefaults: <String>[
        'Inspect CMakeLists.txt, build scripts, and compile_commands.json before proposing broad native-code edits.',
        'Use headers, source files, tests, and generated artifacts as distinct ownership surfaces.',
      ],
      instructions: <String>[
        'Map the touched symbol across declarations, definitions, call sites, and tests before emitting multi-file patches.',
        'Prefer small ownership-preserving edits over broad mechanical rewrites.',
        'Respect public headers and ABI-sensitive boundaries.',
      ],
      validationHints: <String>[
        'Prefer the narrowest test target that covers the edited component.',
        'Prefer compile-only validation for parser, semantic, or lowering edits when a full test suite is too broad.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-safe-editing',
      title: 'C++ Safe Editing',
      appliesTo: <String>[
        'C++',
        'systems code',
        'compiler frontend',
        'runtime',
      ],
      toolchainDefaults: <String>[
        'Assume C++17 or later only when the project manifest, build file, or existing code proves it.',
      ],
      instructions: <String>[
        'Preserve RAII, ownership, const-correctness, exception-safety, and lifetime invariants.',
        'Avoid introducing raw owning pointers when value types, references, smart pointers, or existing project abstractions fit.',
        'Do not silence diagnostics with casts or broad pragmas unless the existing codebase has the same local pattern and the reason is explicit.',
      ],
      validationHints: <String>[
        'When editing memory or ownership code, include a test or targeted runtime scenario that would fail on the old behavior.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-compilation-database',
      title: 'C++ Compilation Database',
      appliesTo: <String>['C++', 'C', 'compile_commands.json', 'clang tooling'],
      toolchainDefaults: <String>[
        'Prefer compile_commands.json as the authoritative per-file compiler argument source when it exists.',
        'Treat missing compile database entries as uncertainty; do not invent include paths or feature macros.',
      ],
      instructions: <String>[
        'Before changing a translation unit, account for its include paths, defines, language standard, and generated headers from the compile database when available.',
        'Do not patch compile_commands.json as source unless the repository intentionally tracks it.',
        'If a file is absent from the compile database, fall back to nearby CMake targets or existing build scripts and state the uncertainty.',
      ],
      validationHints: <String>[
        'Prefer clang++ -fsyntax-only with the compile database arguments for the touched file when a narrow compile check is available.',
        'For generated compile databases, validate by regenerating from the build system rather than editing the JSON by hand.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-clang-format-tidy',
      title: 'C++ clang-format and clang-tidy',
      appliesTo: <String>[
        'C++',
        'C',
        'clang-format',
        'clang-tidy',
        'native static analysis',
      ],
      toolchainDefaults: <String>[
        'Prefer registered clang-format and clang-tidy toolchain commands when available.',
        'Respect .clang-format and .clang-tidy configuration files instead of inventing style or analyzer rules.',
      ],
      instructions: <String>[
        'Use formatActiveDocument for formatting-only work and runStaticAnalysis for clang-tidy-style diagnostics when the IDE command readiness is satisfied.',
        'If runStaticAnalysis requires compile_commands.json, use the required build command before static analysis instead of inventing include paths or compile flags.',
        'Keep formatting-only changes separate from semantic C++ fixes unless the user explicitly asks for a combined cleanup.',
      ],
      validationHints: <String>[
        'For formatting work, validate through the registered formatter command rather than manually applying style guesses.',
        'For static-analysis work, read the structured staticAnalysisResult diagnostics before proposing follow-up code edits.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-cmake-build-graph',
      title: 'C++ CMake Build Graph',
      appliesTo: <String>['C++', 'CMake', 'Ninja', 'native build targets'],
      toolchainDefaults: <String>[
        'Prefer CMake target ownership over directory-wide assumptions.',
        'Prefer Ninja target validation when the configured generator is Ninja.',
      ],
      instructions: <String>[
        'Map source files to CMake targets before adding dependencies, include directories, compiler definitions, or tests.',
        'Keep public include directories, private include directories, link libraries, and compile definitions in their target-appropriate scope.',
        'Do not add global CMake flags when a target-local property is sufficient.',
      ],
      validationHints: <String>[
        'Use the narrowest affected CMake target build when available.',
        'When build files change, validate both configure and target build steps if the session permits validation.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-clangd-indexing',
      title: 'C++ clangd Indexing',
      appliesTo: <String>[
        'C++',
        'clangd',
        'go to definition',
        'references',
        'rename',
      ],
      toolchainDefaults: <String>[
        'Treat clangd facts as editor assistance and Clang compiler diagnostics as compiler truth.',
        'Use compile_commands.json or clangd configuration as the indexing input when present.',
      ],
      instructions: <String>[
        'For symbol edits, preserve declarations, definitions, overrides, template instantiations, and call sites as separate review surfaces.',
        'Do not assume a textual match is a safe reference; prefer resolved symbol facts when available.',
        'When rename/reference data is incomplete, keep edits local and state the missing index coverage.',
      ],
      validationHints: <String>[
        'Prefer symbol-level tests or targeted compile checks after rename, signature, or include changes.',
        'When semantic index validation is unavailable, include the exact unresolved risk in the response.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'cpp-test-debug-loop',
      title: 'C++ Test and Debug Loop',
      appliesTo: <String>[
        'C++',
        'unit tests',
        'integration tests',
        'debugging',
      ],
      toolchainDefaults: <String>[
        'Prefer existing repo-local test runners and build presets over ad hoc commands.',
        'Prefer sanitizer or debug builds only when the project already exposes them or the user asks for them.',
      ],
      instructions: <String>[
        'Tie every behavior change to an existing or new test at the closest ownership boundary.',
        'Separate compile failures, test failures, runtime crashes, and benchmark regressions in the diagnosis.',
        'Do not hide flaky or environment-dependent failures behind broad retries.',
      ],
      validationHints: <String>[
        'Run the smallest deterministic test that covers the changed behavior.',
        'If a debugger or sanitizer is needed, state the exact configuration and why normal tests are insufficient.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'reference-grounded-ide-development',
      title: 'Reference-Grounded IDE Development',
      appliesTo: <String>[
        'IDE architecture',
        'editor features',
        'language service',
        'debug adapter',
        'extension system',
        'agent coding',
      ],
      toolchainDefaults: <String>[
        'Use VS Code, IntelliJ Community, Eclipse Theia, Monaco Editor, LSP, clangd, and Tree-sitter as reference implementations for IDE-facing work.',
        'Treat C++ language-service behavior as clangd-style unless the active language service provides stronger project-specific facts.',
      ],
      instructions: <String>[
        'Before designing a new IDE feature, map the feature to an existing mature open-source precedent or state why Vityo intentionally differs.',
        'Separate reference evidence from product-specific Vityo behavior; do not copy implementation details blindly across architecture boundaries.',
        'Prefer stable contracts, explicit capability states, and verifiable degradation paths over hidden fallback behavior.',
      ],
      validationHints: <String>[
        'Every code change must have a targeted test, integration test, or documented gate that covers the changed behavior.',
        'When relying on an external reference design, name the reference surface and validate the Vityo artifact that implements the local contract.',
      ],
    ),
    AgentCodingSkill(
      skillId: 'styio-cpp-compiler-project',
      title: 'Styio C++ Compiler Project',
      appliesTo: <String>[
        'Styio compiler',
        'compiler parser',
        'compiler semantic analysis',
        'IR lowering',
        'native runtime',
      ],
      toolchainDefaults: <String>[
        'Treat Styio as a C++ compiler project by default.',
        'Use Clang/clang++ as the preferred native compiler family unless the repository selects another compiler.',
      ],
      instructions: <String>[
        'Do not invent Styio language syntax in tests; use repository fixtures or parser source of truth.',
        'Keep parser, semantic analysis, lowering, runtime, and benchmark ownership separate.',
        'For language-facing changes, prefer external fixture files and explicit expected-success or expected-failure names.',
      ],
      validationHints: <String>[
        'Use the Styio parser or compiler fixture gate for syntax-sensitive changes.',
        'Use repo-local checkpoint or feature gates when the user requests validation.',
      ],
    ),
  ];

  static AgentSkillContext defaultContext() {
    return const AgentSkillContext(skills: defaultSkills);
  }

  static AgentSkillContext contextForWorkspace({
    required String activeDocumentId,
    required Iterable<String> workspaceFiles,
    bool styioServiceAvailable = false,
    String? styioServiceCapabilityHealth,
    int styioServiceMissingCapabilityCount = 0,
    int styioServiceBlockedCapabilityCount = 0,
    String? styioProviderReadiness,
    int styioProviderMissingCapabilityCount = 0,
    bool styioSemanticFactsReady = false,
  }) {
    final normalizedPaths = <String>[
      activeDocumentId,
      ...workspaceFiles,
    ].map(_normalizeSkillPath).toList(growable: false);
    final hasStyio = normalizedPaths.any((path) => path.endsWith('.styio'));
    final hasNativeSource = normalizedPaths.any(_isNativeSourcePath);
    final hasCompilationDatabase = normalizedPaths.any(
      (path) => path.endsWith('/compile_commands.json'),
    );
    final hasCMake = normalizedPaths.any(_isCMakePath);
    final hasNinjaBuild = normalizedPaths.any(
      (path) => path.endsWith('/build.ninja'),
    );
    final hasClangdConfig = normalizedPaths.any(
      (path) => path.endsWith('/.clangd'),
    );
    final hasClangFormatConfig = normalizedPaths.any(
      (path) =>
          path.endsWith('/.clang-format') || path.endsWith('/_clang-format'),
    );
    final hasClangTidyConfig = normalizedPaths.any(
      (path) => path.endsWith('/.clang-tidy'),
    );
    final hasCTest = normalizedPaths.any(
      (path) => path.endsWith('/ctesttestfile.cmake'),
    );
    final hasTestPath = normalizedPaths.any(_isTestPath);
    final hasNativeProjectEvidence =
        hasNativeSource ||
        hasCompilationDatabase ||
        hasCMake ||
        hasNinjaBuild ||
        hasClangdConfig ||
        hasClangFormatConfig ||
        hasClangTidyConfig;
    final activationReasons = <String, List<String>>{};

    void activate(String skillId, List<String> reasons) {
      activationReasons.putIfAbsent(skillId, () => <String>[]).addAll(reasons);
    }

    activate('reference-grounded-ide-development', <String>[
      'IDE-facing work should remain grounded in mature editor, language service, and agent coding references.',
    ]);

    if (hasStyio || styioServiceAvailable) {
      activate('styio-language-service-truth', <String>[
        hasStyio
            ? 'Styio source files require StyioService-backed syntax and semantic facts instead of Vityo-side grammar guesses.'
            : 'StyioService status is available, so Agent coding should prefer real language facts over generic editing guesses.',
        if (styioServiceCapabilityHealth != null)
          'StyioService capability health is $styioServiceCapabilityHealth with $styioServiceMissingCapabilityCount missing and $styioServiceBlockedCapabilityCount blocked capability/capabilities.',
        if (styioProviderReadiness != null)
          'Styio language provider readiness is $styioProviderReadiness with $styioProviderMissingCapabilityCount missing IDE language capability/capabilities.',
        if (!styioSemanticFactsReady)
          'Styio semantic facts are not ready, so avoid symbol-sensitive edits unless resolvedElement, resolvedReference, or semantic panel facts are present.',
      ]);
      activate('styio-ide-feature-loop', <String>[
        hasStyio
            ? 'Styio IDE features should adapt completion, hover, diagnostics, semantic tokens, definition, references, and rename from language facts.'
            : 'Active language-service status can provide diagnostics, completion, hover, semantic token, and definition readiness for Agent decisions.',
      ]);
      activate('styio-agent-command-loop', <String>[
        hasStyio
            ? 'Styio source editing should prefer language-service refresh, project language context, diagnostics, and quick-fix commands before manual patches.'
            : 'StyioService status is present, so Agent coding should use language service suggestedCommandIds and registered command loops before speculative edits.',
      ]);
    }

    if (hasStyio) {
      activate('styio-fixture-confidence-matrix', <String>[
        'Styio syntax-sensitive work should use fixture expectations and confidence classification.',
      ]);
    }

    if (hasStyio && hasNativeProjectEvidence) {
      activate('styio-cpp-compiler-project', <String>[
        'Styio source files appear together with native build evidence, so compiler-project workflow may be relevant.',
      ]);
    }

    if (hasNativeProjectEvidence) {
      activate('cpp-clang-toolchain-defaults', <String>[
        'The workspace has Styio, C/C++, CMake, Clang, or compile database evidence.',
      ]);
      activate('cpp-clang-version-handoff', <String>[
        'Native-code work can use registered Clang/C++ version selection and IDE-provided CMake/Ninja handoff facts.',
      ]);
      activate('cpp-project-orientation', <String>[
        'Native-code changes require target, source, header, and test ownership orientation.',
      ]);
      activate('cpp-safe-editing', <String>[
        'Native-code edits must preserve ownership, lifetime, and diagnostic correctness.',
      ]);
    }

    if (hasCompilationDatabase) {
      activate('cpp-compilation-database', <String>[
        'compile_commands.json is present and should guide per-file compiler arguments.',
      ]);
      activate('cpp-clangd-indexing', <String>[
        'compile_commands.json can feed clangd-style symbol and reference facts.',
      ]);
    }

    if (hasClangFormatConfig || hasClangTidyConfig) {
      activate('cpp-clang-format-tidy', <String>[
        hasClangFormatConfig && hasClangTidyConfig
            ? 'clang-format and .clang-tidy configuration files are present and should guide formatting and static-analysis commands.'
            : hasClangFormatConfig
            ? 'A clang-format configuration file is present and should guide formatting commands.'
            : '.clang-tidy is present and should guide static-analysis commands.',
      ]);
    }

    if (hasCMake || hasNinjaBuild) {
      activate('cpp-cmake-build-graph', <String>[
        hasCMake
            ? 'CMake project files are present and target ownership should guide build edits.'
            : 'Ninja build files are present and configured native build targets should guide build edits.',
      ]);
    }

    if (hasClangdConfig) {
      activate('cpp-clangd-indexing', <String>[
        '.clangd is present and should guide language-service indexing assumptions.',
      ]);
    }

    if (hasCTest || hasTestPath) {
      activate('cpp-test-debug-loop', <String>[
        'The workspace has CTest or test path evidence for targeted validation planning.',
      ]);
    }

    final activeSkillIds = defaultSkills
        .map((skill) => skill.skillId)
        .where(activationReasons.containsKey)
        .toList(growable: false);
    final orderedReasons = <String, List<String>>{
      for (final skillId in activeSkillIds)
        skillId: List<String>.unmodifiable(activationReasons[skillId]!),
    };
    return AgentSkillContext(
      skills: defaultSkills,
      activeSkillIds: activeSkillIds,
      activationReasons: orderedReasons,
    );
  }
}

class AgentSkillContext {
  const AgentSkillContext({
    required this.skills,
    this.activeSkillIds = const <String>[],
    this.activationReasons = const <String, List<String>>{},
  });

  final List<AgentCodingSkill> skills;
  final List<String> activeSkillIds;
  final Map<String, List<String>> activationReasons;

  int get skillCount => skills.length;
  int get activeSkillCount => activeSkillIds.length;

  List<String> get skillIds {
    return skills.map((skill) => skill.skillId).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'skillCount': skillCount,
      'skillIds': skillIds,
      'activeSkillCount': activeSkillCount,
      'activeSkillIds': activeSkillIds,
      if (activationReasons.isNotEmpty) 'activationReasons': activationReasons,
      'skills': skills.map((skill) => skill.toJson()).toList(growable: false),
    };
  }
}

String _normalizeSkillPath(String path) {
  final normalized = path.trim().replaceAll('\\', '/').toLowerCase();
  if (normalized.startsWith('/')) {
    return normalized;
  }
  return '/$normalized';
}

bool _isNativeSourcePath(String path) {
  return path.endsWith('.c') ||
      path.endsWith('.cc') ||
      path.endsWith('.cpp') ||
      path.endsWith('.cxx') ||
      path.endsWith('.h') ||
      path.endsWith('.hh') ||
      path.endsWith('.hpp') ||
      path.endsWith('.hxx') ||
      path.endsWith('.ixx') ||
      path.endsWith('.cppm') ||
      path.endsWith('.ccm') ||
      path.endsWith('.cxxm') ||
      path.endsWith('.mpp');
}

bool _isCMakePath(String path) {
  return path.endsWith('/cmakelists.txt') ||
      path.endsWith('/cmakepresets.json') ||
      path.endsWith('/cmakeuserpresets.json') ||
      path.endsWith('.cmake');
}

bool _isTestPath(String path) {
  return path.contains('/test/') ||
      path.contains('/tests/') ||
      path.contains('/testing/') ||
      path.contains('/unittest/') ||
      path.contains('/unittests/') ||
      path.contains('/integration_test/') ||
      path.endsWith('_test.cc') ||
      path.endsWith('_test.cpp') ||
      path.endsWith('_tests.cc') ||
      path.endsWith('_tests.cpp');
}
