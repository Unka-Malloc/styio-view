import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
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
      expect(selection.cmakeConfigureArguments, <String>[
        '-DCMAKE_C_COMPILER=/opt/clang-18/bin/clang',
        '-DCMAKE_CXX_COMPILER=/opt/clang-18/bin/clang++',
        '-DCMAKE_CXX_STANDARD=23',
        '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
        '-DCMAKE_CXX_EXTENSIONS=OFF',
      ]);
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
  });

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
