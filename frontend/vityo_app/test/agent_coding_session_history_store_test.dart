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
    final checkpoint = await store.readCheckpoint(workspaceId: 'demo');
    final recoveryPlan = await store.readRecoveryPlan(workspaceId: 'demo');

    expect(restored.records.single.requestId, 'agent-1');
    expect(restored.records.single.succeeded, isTrue);
    expect(restored.records.single.planCount, 1);
    expect(
      restored.records.single.responseTextSample,
      contains('language service snapshot'),
    );
    expect(restored.toJson()['recordCount'], 1);
    expect(checkpoint.status, AgentCodingSessionCheckpointStatus.ready);
    expect(checkpoint.latestRequestId, 'agent-1');
    expect(checkpoint.latestOutcome, AgentCodingSessionOutcome.succeeded);
    expect(checkpoint.needsRecovery, isFalse);
    expect(
      AgentCodingSessionCheckpoint.fromJson(checkpoint.toJson()).status,
      AgentCodingSessionCheckpointStatus.ready,
    );
    expect(recoveryPlan.status, AgentCodingSessionRecoveryStatus.notNeeded);
    expect(
      recoveryPlan.recommendedAction,
      AgentCodingSessionRecoveryAction.none,
    );
    expect(
      recoveryPlan.commandFor(
        AgentCodingSessionRecoveryAction.retrySameProvider,
      ),
      isNull,
    );
  });

  test('agent coding session history stores failure checkpoints', () {
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
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[restored],
      updatedAt: DateTime.utc(2026, 5, 20, 0, 2),
    );
    final checkpoint = history.toCheckpoint();
    final recoveryPlan = history.toRecoveryPlan();

    expect(restored.outcome, AgentCodingSessionOutcome.failed);
    expect(restored.succeeded, isFalse);
    expect(restored.errorMessage, 'Provider timed out.');
    expect(checkpoint.status, AgentCodingSessionCheckpointStatus.needsRecovery);
    expect(checkpoint.needsRecovery, isTrue);
    expect(checkpoint.latestPromptSample, 'Apply patch');
    expect(checkpoint.recoveryTodo, contains('TODO:'));
    expect(checkpoint.toJson()['latestOutcome'], 'failed');
    expect(recoveryPlan.status, AgentCodingSessionRecoveryStatus.available);
    expect(
      recoveryPlan.recommendedAction,
      AgentCodingSessionRecoveryAction.retrySameProvider,
    );
    expect(recoveryPlan.canRetryProvider, isTrue);
    expect(recoveryPlan.canFailoverProvider, isTrue);
    expect(recoveryPlan.canReplayPrompt, isTrue);
    expect(
      AgentCodingSessionRecoveryPlan.fromJson(
        recoveryPlan.toJson(),
      ).canReplayPrompt,
      isTrue,
    );
    final retryCommand = recoveryPlan.commandFor(
      AgentCodingSessionRecoveryAction.retrySameProvider,
    );
    final failoverCommand = recoveryPlan.commandFor(
      AgentCodingSessionRecoveryAction.failoverProvider,
    );
    expect(retryCommand?.commandId, 'retryAgentProvider');
    expect(retryCommand?.requestId, 'agent-failed');
    expect(retryCommand?.promptSample, 'Apply patch');
    expect(retryCommand?.requiresProviderSelection, isFalse);
    expect(failoverCommand?.commandId, 'failoverAgentProvider');
    expect(failoverCommand?.requiresProviderSelection, isTrue);
    expect(failoverCommand?.toJson()['todo'], contains('TODO:'));
  });
}
