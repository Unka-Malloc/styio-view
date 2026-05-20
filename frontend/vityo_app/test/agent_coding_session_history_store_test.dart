import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

void main() {
  test('agent coding session history stores response summaries', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_coding_session_history_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final store = AgentCodingSessionHistoryStore.fromDataStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
    );
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.macos);
    const response = AgentProviderResponseEnvelope(
      requestId: 'agent-1',
      role: 'assistant',
      finishReason: 'stop',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.text,
          text: 'Use the language service snapshot.',
        ),
        AgentContentPart(
          kind: AgentContentPartKind.plan,
          text: 'Plan',
          plan: AgentCodingPlan(
            summary: 'Wire the store.',
            steps: <String>['Add store', 'Add tests'],
            acceptanceCriteria: <String>['History persists'],
          ),
        ),
      ],
    );
    final record = AgentCodingSessionHistoryRecord.fromResponse(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
      prompt: 'Continue the IDE closure.',
      response: response,
      createdAt: DateTime.utc(2026, 5, 20),
      completedAt: DateTime.utc(2026, 5, 20, 0, 1),
    );

    await store.appendRecord(workspaceId: 'demo', record: record);
    final restored = await store.readHistory(workspaceId: 'demo');

    expect(restored.records.single.requestId, 'agent-1');
    expect(restored.records.single.succeeded, isTrue);
    expect(restored.records.single.planCount, 1);
    expect(
      restored.records.single.responseTextSample,
      contains('language service snapshot'),
    );
    expect(restored.toJson()['recordCount'], 1);
  });

  test('agent coding session history stores failures', () {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.macos);

    final record = AgentCodingSessionHistoryRecord.failure(
      requestId: 'agent-failed',
      profile: profile,
      providerKind: AgentProviderKind.localOnlyFallback,
      prompt: 'Apply patch',
      errorMessage: 'Provider timed out.',
      createdAt: DateTime.utc(2026, 5, 20),
      completedAt: DateTime.utc(2026, 5, 20, 0, 1),
    );
    final restored = AgentCodingSessionHistoryRecord.fromJson(record.toJson());

    expect(restored.outcome, AgentCodingSessionOutcome.failed);
    expect(restored.succeeded, isFalse);
    expect(restored.errorMessage, 'Provider timed out.');
  });
}
