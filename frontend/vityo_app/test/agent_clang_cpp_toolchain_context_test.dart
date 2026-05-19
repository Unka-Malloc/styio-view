import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('agent context exposes Clang C++ version manager handoff facts', () {
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: '/workspace/demo/main.cc',
        text: 'int main() { return 0; }\n',
        revision: 1,
      ),
      selection: const SelectionState(baseOffset: 0, extentOffset: 0),
      diagnostics: const <Diagnostic>[],
      clangCppVersionPreference: const ClangCppVersionPreference(
        versionId: 'native-clang-cpp-compiler',
        cppStandard: CppLanguageStandard.cpp23,
      ),
      toolchainSnapshot: const ToolchainStateSnapshot(
        targetId: 'agent-clang-cpp-toolchains',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-clang-cpp-compiler',
            kind: ToolchainKind.compiler,
            displayName: 'Clang C/C++ Compiler',
            executablePath: '/usr/bin/clang++',
            active: true,
            version: '18.1.8',
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': '/usr/bin/clang',
              'cxxCompilerPath': '/usr/bin/clang++',
              'clangVendor': 'llvm',
              'defaultForNativeCode': true,
            },
          ),
          ToolchainStateEntry(
            id: 'native-cmake-build-tool',
            kind: ToolchainKind.buildTool,
            displayName: 'CMake Build System',
            executablePath: '/usr/bin/cmake',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'cmake'},
          ),
          ToolchainStateEntry(
            id: 'native-ninja-build-tool',
            kind: ToolchainKind.buildTool,
            displayName: 'Ninja Build Tool',
            executablePath: '/usr/bin/ninja',
            active: false,
            metadata: <String, Object?>{'toolFamily': 'ninja'},
          ),
        ],
      ),
    );

    final json = context.toJson();
    final toolchainsJson = json['toolchains']! as Map<String, Object?>;
    final clangCppJson = toolchainsJson['clangCpp']! as Map<String, Object?>;
    final candidatesJson = clangCppJson['candidates']! as List<Object?>;
    final selectionJson = clangCppJson['selection']! as Map<String, Object?>;
    final selectedCandidateJson =
        selectionJson['candidate']! as Map<String, Object?>;

    expect(clangCppJson['candidateCount'], 1);
    expect(
      (candidatesJson.single! as Map<String, Object?>)['version'],
      '18.1.8',
    );
    expect(
      ((candidatesJson.single! as Map<String, Object?>)['metadata']!
          as Map<String, Object?>)['clangVendor'],
      'llvm',
    );
    expect(clangCppJson['activeVersionId'], 'native-clang-cpp-compiler');
    expect(clangCppJson['requestedVersionId'], 'native-clang-cpp-compiler');
    expect(clangCppJson['preferenceStatus'], 'configured');
    expect(clangCppJson['cmakeAvailable'], isTrue);
    expect(clangCppJson['cmakeToolchainId'], 'native-cmake-build-tool');
    expect(clangCppJson['cmakeExecutablePath'], '/usr/bin/cmake');
    expect(clangCppJson['ninjaAvailable'], isTrue);
    expect(clangCppJson['ninjaToolchainId'], 'native-ninja-build-tool');
    expect(clangCppJson['ninjaExecutablePath'], '/usr/bin/ninja');
    expect(selectedCandidateJson['version'], '18.1.8');
    expect(selectionJson['cmakeConfigureArguments'], <String>[
      '-DCMAKE_C_COMPILER=/usr/bin/clang',
      '-DCMAKE_CXX_COMPILER=/usr/bin/clang++',
      '-DCMAKE_CXX_STANDARD=23',
      '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
      '-DCMAKE_CXX_EXTENSIONS=OFF',
      '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
    ]);
    expect(selectionJson['cmakeNinjaConfigureArguments'], <String>[
      '-G',
      'Ninja',
      '-DCMAKE_C_COMPILER=/usr/bin/clang',
      '-DCMAKE_CXX_COMPILER=/usr/bin/clang++',
      '-DCMAKE_CXX_STANDARD=23',
      '-DCMAKE_CXX_STANDARD_REQUIRED=ON',
      '-DCMAKE_CXX_EXTENSIONS=OFF',
      '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON',
      '-DCMAKE_MAKE_PROGRAM=/usr/bin/ninja',
    ]);
    expect(selectionJson['ninjaEnvironment'], <String, String>{
      'CC': '/usr/bin/clang',
      'CXX': '/usr/bin/clang++',
      'CXXFLAGS': '-std=c++23',
    });
    final handoffs = selectionJson['buildEngineHandoffs']! as List<Object?>;
    final preferredHandoff =
        selectionJson['preferredBuildEngineHandoff']! as Map<String, Object?>;

    expect(handoffs.length, 3);
    expect(preferredHandoff['engineFamily'], 'cmake');
    expect(preferredHandoff['generatorFamily'], 'ninja');
    expect(preferredHandoff['executablePath'], '/usr/bin/cmake');
    expect(
      preferredHandoff['arguments'],
      selectionJson['cmakeNinjaConfigureArguments'],
    );
  });
}
