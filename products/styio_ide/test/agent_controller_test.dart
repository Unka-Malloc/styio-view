import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/agent_client/agent.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/agent_controller.dart';

void main() {
  test('agent controller keeps newest bounded command receipts', () {
    final controller = AgentController(maxCommandResultRecords: 2);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    for (var index = 0; index < 3; index += 1) {
      controller.recordCommandResult(
        AgentCommandResultContext(
          commandId: 'command-$index',
          applied: true,
          message: 'completed',
        ),
      );
    }

    expect(controller.lastCommandResult?.commandId, 'command-2');
    expect(
      controller.recentCommandResults.map((result) => result.commandId),
      <String>['command-2', 'command-1'],
    );
    expect(notifications, 3);
    controller.dispose();
  });

  test('agent controller publishes provider profile manifest changes', () {
    final controller = AgentController();
    const manifest = AgentPromptProfileManifest(
      entries: <AgentPromptProfileManifestEntry>[
        AgentPromptProfileManifestEntry(
          key: 'local',
          profileId: 'local-profile',
          displayName: 'Local',
          route: 'local',
          protocol: 'openai-compatible',
          model: 'local-model',
          requiresCredential: false,
        ),
      ],
    );

    controller.replaceProviderProfileManifest(manifest);

    expect(controller.providerProfileManifest.entries.single.key, 'local');
    controller.dispose();
  });
}
