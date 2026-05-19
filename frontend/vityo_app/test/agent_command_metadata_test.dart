import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';

void main() {
  test('agent command metadata resolves top-level required command', () {
    expect(
      requiredCommandIdFromAgentMetadata(const <String, Object?>{
        'requiredCommand': ' runBuild ',
      }),
      'runBuild',
    );
  });

  test('agent command metadata resolves nested native tool required command', () {
    expect(
      requiredCommandIdFromAgentMetadata(const <String, Object?>{
        'testResult': <String, Object?>{
          'status': 'blocked',
          'requiredCommand': 'runBuild',
        },
      }),
      'runBuild',
    );
    expect(
      requiredCommandIdFromAgentMetadata(const <String, Object?>{
        'staticAnalysisResult': <String, Object?>{
          'status': 'blocked',
          'requiredCommand': 'runBuild',
        },
      }),
      'runBuild',
    );
  });

  test('agent command metadata ignores empty or unsupported required command', () {
    expect(
      requiredCommandIdFromAgentMetadata(const <String, Object?>{
        'requiredCommand': ' ',
      }),
      isNull,
    );
    expect(
      requiredCommandIdFromAgentMetadata(const <String, Object?>{
        'testResult': <String, Object?>{'requiredCommand': 7},
      }),
      isNull,
    );
  });

  test('agent command metadata resolves backend route selection', () {
    final route = backendRouteFromAgentMetadata(const <String, Object?>{
      'backendRouteSelection': <String, Object?>{
        'routeKind': 'blocked',
        'adapterKind': 'none',
        'allowed': false,
        'previewOnly': false,
        'blockedReason': 'no-backend-route',
      },
    });

    expect(route, isNotNull);
    expect(route?.routeKind, 'blocked');
    expect(route?.adapterKind, 'none');
    expect(route?.allowed, isFalse);
    expect(route?.previewOnly, isFalse);
    expect(route?.blocked, isTrue);
    expect(route?.blockedReason, 'no-backend-route');
  });
}
