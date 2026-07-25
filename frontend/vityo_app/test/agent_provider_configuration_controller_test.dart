import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/platform/platform.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_provider_configuration_controller.dart';

void main() {
  test(
    'missing configurator exposes empty manifest without session access',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);

      final manifest = await fixture.controller.refreshManifest();

      expect(manifest.entries, isEmpty);
      expect(fixture.sessionAccesses, 0);
    },
  );

  test(
    'save and failover degrade honestly when configurator is absent',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);

      final saved = await fixture.controller.saveAndMount(
        AgentPromptProfile.defaultForPlatform(PlatformTarget.windows),
      );
      final failedOver = await fixture.controller.failover('missing');

      expect(saved, isNull);
      expect(failedOver, isNull);
      expect(fixture.logs, hasLength(2));
      expect(fixture.sessionAccesses, 0);
    },
  );
}

final class _Fixture {
  _Fixture() {
    controller = AgentProviderConfigurationController(
      configurator: null,
      sessionController: () {
        sessionAccesses += 1;
        throw StateError('session must not be accessed');
      },
      agentController: agent,
      runtimeOutputBuffer: buffer,
      log: logs.add,
      notify: () {},
    );
  }

  final AgentController agent = AgentController();
  final RuntimeOutputLiveBuffer buffer = RuntimeOutputLiveBuffer();
  final List<String> logs = <String>[];
  late final AgentProviderConfigurationController controller;
  int sessionAccesses = 0;

  void dispose() {
    buffer.dispose();
    agent.dispose();
  }
}
