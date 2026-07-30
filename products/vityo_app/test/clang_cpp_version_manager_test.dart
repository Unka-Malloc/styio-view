import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('parses common Clang version output facts', () {
    final llvm = ClangCppVersionFacts.parse(
      'clang version 18.1.8\nTarget: x86_64-unknown-linux-gnu\n',
    );
    final apple = ClangCppVersionFacts.parse(
      'Apple clang version 15.0.0 (clang-1500.3.9.4)\n',
    );
    final ubuntu = ClangCppVersionFacts.parse(
      'Ubuntu clang version 17.0.6 (++20231208085813+6009708b4367-1~exp1)\n',
    );

    expect(llvm, isNotNull);
    expect(llvm!.version, '18.1.8');
    expect(llvm.vendor, 'llvm');
    expect(llvm.toMetadata()['clangVersionSource'], 'clang++ --version');
    expect(apple, isNotNull);
    expect(apple!.version, '15.0.0');
    expect(apple.vendor, 'apple');
    expect(ubuntu, isNotNull);
    expect(ubuntu!.version, '17.0.6');
    expect(ubuntu.vendor, 'ubuntu');
    expect(ClangCppVersionFacts.parse('not clang'), isNull);
  });

  test(
    'selects active Clang C++ version and hands compilers to CMake and Ninja',
    () {
      final catalog = ToolchainCatalog();
      catalog
        ..register(
          const ToolchainDescriptor(
            id: 'clang-18',
            kind: ToolchainKind.compiler,
            displayName: 'Clang 18',
            executablePath: '/opt/clang-18/bin/clang++',
            version: '18.1.8',
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': '/opt/clang-18/bin/clang',
              'cxxCompilerPath': '/opt/clang-18/bin/clang++',
              'source': 'manual',
              'languages': <String>['c', 'cpp'],
            },
          ),
          activate: true,
        )
        ..register(
          const ToolchainDescriptor(
            id: 'cmake',
            kind: ToolchainKind.buildTool,
            displayName: 'CMake',
            executablePath: '/usr/bin/cmake',
            metadata: <String, Object?>{'toolFamily': 'cmake'},
          ),
        )
        ..register(
          const ToolchainDescriptor(
            id: 'ninja',
            kind: ToolchainKind.buildTool,
            displayName: 'Ninja',
            executablePath: '/usr/bin/ninja',
            metadata: <String, Object?>{'toolFamily': 'ninja'},
          ),
        );

      final manager = ClangCppVersionManager.fromCatalog(
        catalog,
        defaultCppStandard: CppLanguageStandard.cpp23,
      );
      final selection = manager.select();

      expect(manager.hasCandidates, isTrue);
      expect(selection, isNotNull);
      expect(selection!.candidate.versionId, 'clang-18');
      expect(selection.cmakeAvailable, isTrue);
      expect(selection.ninjaAvailable, isTrue);
      expect(manager.cmakeToolchainId, 'cmake');
      expect(manager.cmakeExecutablePath, '/usr/bin/cmake');
      expect(manager.ninjaToolchainId, 'ninja');
      expect(manager.ninjaExecutablePath, '/usr/bin/ninja');
      expect(selection.cmakeConfigureArguments, <String>[
        '-DCMAKE_C_COMPILER=/opt/clang-18/bin/clang',
        '-DCMAKE_CXX_COMPILER=/opt/clang-18/bin/clang++',
        '-DCMAKE_CXX_STANDARD=23',
        '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
        '-DCMAKE_CXX_EXTENSIONS=OFF',
        '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
      ]);
      expect(selection.cmakeNinjaConfigureArguments, <String>[
        '-G',
        'Ninja',
        '-DCMAKE_C_COMPILER=/opt/clang-18/bin/clang',
        '-DCMAKE_CXX_COMPILER=/opt/clang-18/bin/clang++',
        '-DCMAKE_CXX_STANDARD=23',
        '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
        '-DCMAKE_CXX_EXTENSIONS=OFF',
        '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
        '-DCMAKE_MAKE_PROGRAM=/usr/bin/ninja',
      ]);
      expect(selection.buildEngineHandoffs.length, 3);
      expect(
        selection.preferredBuildEngineHandoff!.toManifest(),
        <String, Object?>{
          'engineFamily': 'cmake',
          'executablePath': '/usr/bin/cmake',
          'generatorFamily': 'ninja',
          'arguments': selection.cmakeNinjaConfigureArguments,
        },
      );
      expect(selection.buildEngineHandoffs.last.toManifest(), <String, Object?>{
        'engineFamily': 'ninja',
        'executablePath': '/usr/bin/ninja',
        'environment': <String, String>{
          'CC': '/opt/clang-18/bin/clang',
          'CXX': '/opt/clang-18/bin/clang++',
          'CXXFLAGS': '-std=c++23',
        },
        'arguments': <String>[],
      });
      expect(selection.ninjaEnvironment(), <String, String>{
        'CC': '/opt/clang-18/bin/clang',
        'CXX': '/opt/clang-18/bin/clang++',
        'CXXFLAGS': '-std=c++23',
      });
      expect(
        selection.ninjaEnvironment(
          baseEnvironment: const <String, String>{'CXXFLAGS': '-O2'},
        )['CXXFLAGS'],
        '-O2 -std=c++23',
      );
    },
  );

  test(
    'selects a non-active Clang C++ version without requiring build engines',
    () {
      final catalog = ToolchainCatalog();
      catalog
        ..register(
          const ToolchainDescriptor(
            id: 'clang-17',
            kind: ToolchainKind.compiler,
            displayName: 'Clang 17',
            executablePath: '/opt/clang-17/bin/clang++',
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': '/opt/clang-17/bin/clang',
              'cxxCompilerPath': '/opt/clang-17/bin/clang++',
            },
          ),
          activate: true,
        )
        ..register(
          const ToolchainDescriptor(
            id: 'clang-18',
            kind: ToolchainKind.compiler,
            displayName: 'Clang 18',
            executablePath: '/opt/clang-18/bin/clang++',
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': '/opt/clang-18/bin/clang',
              'cxxCompilerPath': '/opt/clang-18/bin/clang++',
            },
          ),
        );

      final manager = ClangCppVersionManager.fromCatalog(catalog);
      final selection = manager.select(
        versionId: 'clang-18',
        cppStandard: CppLanguageStandard.cpp20,
      );

      expect(selection, isNotNull);
      expect(selection!.candidate.versionId, 'clang-18');
      expect(selection.cmakeAvailable, isFalse);
      expect(selection.ninjaAvailable, isFalse);
      expect(selection.buildEngineHandoffs, isEmpty);
      expect(selection.preferredBuildEngineHandoff, isNull);
      expect(
        selection.cmakeConfigureArguments,
        contains('-DCMAKE_CXX_STANDARD=20'),
      );
    },
  );

  test('applies persisted Clang C++ version preference when available', () {
    final catalog = ToolchainCatalog();
    catalog
      ..register(
        const ToolchainDescriptor(
          id: 'clang-17',
          kind: ToolchainKind.compiler,
          displayName: 'Clang 17',
          executablePath: '/opt/clang-17/bin/clang++',
          metadata: <String, Object?>{
            'compilerFamily': 'clang',
            'cCompilerPath': '/opt/clang-17/bin/clang',
            'cxxCompilerPath': '/opt/clang-17/bin/clang++',
          },
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'clang-18',
          kind: ToolchainKind.compiler,
          displayName: 'Clang 18',
          executablePath: '/opt/clang-18/bin/clang++',
          metadata: <String, Object?>{
            'compilerFamily': 'clang',
            'cCompilerPath': '/opt/clang-18/bin/clang',
            'cxxCompilerPath': '/opt/clang-18/bin/clang++',
          },
        ),
      );

    final manager = ClangCppVersionManager.fromCatalog(
      catalog,
      preference: const ClangCppVersionPreference(
        versionId: 'clang-18',
        cppStandard: CppLanguageStandard.cpp23,
      ),
    );
    final selection = manager.select();

    expect(selection, isNotNull);
    expect(selection!.candidate.versionId, 'clang-18');
    expect(selection.cppStandard, CppLanguageStandard.cpp23);
    expect(
      manager.preferenceStatus,
      ClangCppVersionPreferenceStatus.configured,
    );
  });

  test(
    'reports missing Clang C++ preference while falling back to active compiler',
    () {
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'clang-17',
            kind: ToolchainKind.compiler,
            displayName: 'Clang 17',
            executablePath: '/opt/clang-17/bin/clang++',
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': '/opt/clang-17/bin/clang',
              'cxxCompilerPath': '/opt/clang-17/bin/clang++',
            },
          ),
          activate: true,
        );

      final manager = ClangCppVersionManager.fromCatalog(
        catalog,
        preference: const ClangCppVersionPreference(versionId: 'clang-99'),
      );
      final selection = manager.select();

      expect(manager.requestedVersionId, 'clang-99');
      expect(
        manager.preferenceStatus,
        ClangCppVersionPreferenceStatus.missingPreferred,
      );
      expect(manager.preferenceMessage, contains('clang-99'));
      expect(selection, isNotNull);
      expect(selection!.candidate.versionId, 'clang-17');
    },
  );

  test('ignores non-Clang and incomplete compiler descriptors', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'gcc',
          kind: ToolchainKind.compiler,
          displayName: 'GCC',
          executablePath: '/usr/bin/g++',
          metadata: <String, Object?>{
            'compilerFamily': 'gcc',
            'cCompilerPath': '/usr/bin/gcc',
            'cxxCompilerPath': '/usr/bin/g++',
          },
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'incomplete-clang',
          kind: ToolchainKind.compiler,
          displayName: 'Incomplete Clang',
          executablePath: '/usr/bin/clang++',
          metadata: <String, Object?>{
            'compilerFamily': 'clang',
            'cxxCompilerPath': '/usr/bin/clang++',
          },
        ),
      );

    final manager = ClangCppVersionManager.fromCatalog(catalog);

    expect(manager.hasCandidates, isFalse);
    expect(manager.select(), isNull);
  });
}
