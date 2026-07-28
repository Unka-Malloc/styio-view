import '../../agent_client/agent.dart';
import '../../runtime/runtime.dart';
import 'agent_controller.dart';

/// Owns Agent provider profile persistence, mounting, failover, and retry telemetry.
final class AgentProviderConfigurationController {
  const AgentProviderConfigurationController({
    required this.configurator,
    required this.sessionController,
    required this.agentController,
    required this.runtimeOutputBuffer,
    required this.log,
    required this.notify,
  });

  final AgentProviderConfigurator? configurator;
  final AgentCodingSessionController Function() sessionController;
  final AgentController agentController;
  final RuntimeOutputLiveBuffer runtimeOutputBuffer;
  final void Function(String message) log;
  final void Function() notify;

  Future<AgentPromptProfileManifest> refreshManifest() async {
    final activeConfigurator = configurator;
    if (activeConfigurator == null) {
      agentController.replaceProviderProfileManifest(
        const AgentPromptProfileManifest(),
      );
      return agentController.providerProfileManifest;
    }
    try {
      agentController.replaceProviderProfileManifest(
        await activeConfigurator.savedProfileManifest(),
      );
      notify();
    } on Object catch (error) {
      log(
        'Agent provider profile manifest refresh failed: '
        '${sanitizeAgentError(error.toString())}',
      );
    }
    return agentController.providerProfileManifest;
  }

  Future<AgentProviderConfigurationResult?> saveAndMount(
    AgentPromptProfile profile, {
    String? bearerToken,
  }) async {
    final activeConfigurator = configurator;
    if (activeConfigurator == null) {
      log('Agent provider profile save unavailable: no configurator is wired.');
      return null;
    }
    final result = await activeConfigurator.saveAndMount(
      profile: profile,
      controller: sessionController(),
      bearerToken: bearerToken,
      retryTelemetrySink: _publishRetryTelemetry,
    );
    await refreshManifest();
    log(result.message);
    return result;
  }

  Future<AgentProviderConfigurationResult?> failover(String profileKey) async {
    final activeConfigurator = configurator;
    if (activeConfigurator == null) {
      log('Agent provider failover unavailable: no configurator is wired.');
      return null;
    }
    final result = await activeConfigurator.mountSavedProfile(
      key: profileKey,
      controller: sessionController(),
      retryTelemetrySink: _publishRetryTelemetry,
    );
    await refreshManifest();
    log(result.message);
    return result;
  }

  void _publishRetryTelemetry(
    AgentProviderRequest request,
    AgentProviderRetryExecution<AgentProviderResponseEnvelope> execution,
  ) {
    const binding = AgentProviderStreamRuntimeOutputBinding();
    runtimeOutputBuffer.addEvent(
      binding.retryEventFor(execution, requestId: request.requestId),
    );
  }
}
