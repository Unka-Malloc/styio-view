import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_render/native_tool_result_summary.dart';

void main() {
  test('native tool summary explains required command metadata', () {
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'staticAnalysisResult': <String, Object?>{
          'status': 'blocked',
          'diagnosticCount': 0,
          'requiredCommand': 'runBuild',
        },
        'requiredCommand': 'runBuild',
      }),
      'static analysis blocked · diagnostics 0 · requires runBuild',
    );
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'testResult': <String, Object?>{
          'status': 'blocked',
          'requiredCommand': 'runBuild',
        },
        'backendRouteSelection': <String, Object?>{
          'routeKind': 'blocked',
          'adapterKind': 'none',
          'allowed': false,
          'previewOnly': false,
          'blockedReason': 'no-backend-route',
        },
      }),
      'tests blocked · requires runBuild · route blocked via none · blocked no-backend-route',
    );
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'backendRouteSelection': <String, Object?>{
          'routeKind': 'hosted',
          'adapterKind': 'hosted',
          'allowed': true,
          'previewOnly': true,
        },
      }),
      'route hosted via hosted · preview',
    );
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'completedRequiredCommandFor': 'runStaticAnalysis',
      }),
      'completed required command for runStaticAnalysis',
    );
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'requiredCommand': 'saveAll',
      }),
      'requires saveAll',
    );
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'settingsRoute': 'settings',
        'settingsSection': 'toolchain',
        'recoveryForCommandId': 'runBuild',
      }),
      'settings route settings · section toolchain · recovery for runBuild',
    );
  });

  test('native tool summary explains Clang C++ selection handoff', () {
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'toolchainSelectionStatus': 'selected',
        'toolchainId': 'fake-clang-18',
        'cppStandard': 'c++23',
        'buildEngineHandoffCount': 3,
        'preferredBuildEngineHandoff': <String, Object?>{
          'engineFamily': 'cmake',
          'generatorFamily': 'ninja',
        },
      }),
      'toolchain selection selected · fake-clang-18 · c++23 · handoff cmake+ninja',
    );
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'toolchainSelectionStatus': 'missing',
        'toolchainId': 'missing-clang',
        'cppStandard': 'c++23',
        'toolchainSelectionMessage': 'unsupported C++ standard c++2b',
        'buildEngineHandoffCount': 0,
      }),
      'toolchain selection missing · missing-clang · c++23 · unsupported C++ standard c++2b · handoffs 0',
    );
  });

  test('native tool summary explains agent coding checkpoint metadata', () {
    expect(
      nativeToolMetadataSummaryText(const <String, Object?>{
        'workspaceDiagnostics': <String, Object?>{'totalCount': 2},
        'sourceControl': <String, Object?>{'changeCount': 1},
        'sourceControlDiff': <String, Object?>{
          'path': 'src/main.styio',
          'lineCount': 7,
        },
        'projectLanguage': <String, Object?>{
          'definitionCount': 1,
          'referenceCount': 2,
          'completionCount': 3,
        },
        'languageServiceStatus': <String, Object?>{
          'syntaxValidationReady': true,
          'semanticFactsReady': false,
        },
        'testing': <String, Object?>{
          'hasLastRun': true,
          'hasFailingTests': true,
        },
      }),
      'checkpoint diagnostics 2 · source changes 1 · diff src/main.styio 7 lines · language defs 1 refs 2 completions 3 · styio syntax ready semantic not-ready · tests failing',
    );
  });
}
