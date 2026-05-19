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
  });
}
