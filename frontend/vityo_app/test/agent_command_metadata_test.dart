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

  test('agent command metadata resolves toolchain selection status', () {
    final selection = toolchainSelectionFromAgentMetadata(
      const <String, Object?>{
        'toolchainSelectionStatus': ' missing ',
        'toolchainId': ' clang-18 ',
        'cppStandard': ' c++23 ',
        'toolchainSelectionMessage': ' unsupported standard ',
      },
    );

    expect(selection, isNotNull);
    expect(selection?.status, 'missing');
    expect(selection?.toolchainId, 'clang-18');
    expect(selection?.cppStandard, 'c++23');
    expect(selection?.selectionMessage, 'unsupported standard');
    expect(selection?.selected, isFalse);
    expect(selection?.settingsRecoveryRecommended, isTrue);
  });

  test('agent command metadata ignores missing toolchain selection status', () {
    expect(
      toolchainSelectionFromAgentMetadata(const <String, Object?>{
        'toolchainSelectionStatus': ' ',
        'toolchainId': 'clang-18',
      }),
      isNull,
    );
  });
}
