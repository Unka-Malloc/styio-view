import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'execution_adapter.dart';
import 'hosted_control_plane.dart';

final Map<String, List<RuntimeEventEnvelope>> _runtimeEventRegistry =
    <String, List<RuntimeEventEnvelope>>{};

abstract class RuntimeEventAdapter {
  AdapterCapabilitySnapshot get capabilitySnapshot;

  Stream<RuntimeEventEnvelope> sessionEvents(String sessionId);
}

void recordRuntimeEventsForSession(
  String sessionId,
  List<RuntimeEventEnvelope> events,
) {
  if (sessionId.isEmpty) {
    return;
  }
  _runtimeEventRegistry[sessionId] = List<RuntimeEventEnvelope>.unmodifiable(
    events,
  );
}

void clearRuntimeEventsForSession(String sessionId) {
  if (sessionId.isEmpty) {
    return;
  }
  _runtimeEventRegistry.remove(sessionId);
}

RuntimeEventAdapter createRuntimeEventAdapter({
  required PlatformTarget platformTarget,
}) {
  final hostedConfig = resolveHostedControlPlaneConfig(
    platformTarget: platformTarget,
  );
  if (hostedConfig != null) {
    return const _PublishedRuntimeEventAdapter(
      capabilitySnapshot: AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cloud,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail:
              'Hosted runtime events are separate from cloud language-service traffic.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail:
              'Hosted runtime adapter follows the same shared control-plane project route.',
          supportedContractVersions: <int>[1],
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail: 'Hosted execution is live through the shared control plane.',
          supportedContractVersions: <int>[1],
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail:
              'Hosted execution publishes replayable runtime event payloads through the shared control plane.',
          supportedContractVersions: <int>[1],
        ),
      ),
    );
  }

  return switch (platformTarget) {
    PlatformTarget.ios || PlatformTarget.web => const NoopRuntimeEventAdapter(
      capabilitySnapshot: AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cloud,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Cloud runtime events remain unpublished.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail:
              'Cloud runtime event adapter does not expose project graph data.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Cloud execution requires a hosted control-plane route.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Cloud runtime events require a hosted control-plane route.',
        ),
      ),
    ),
    _ => const _PublishedRuntimeEventAdapter(
      capabilitySnapshot: AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail:
              'CLI runtime event adapter does not expose language-service data.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail:
              'CLI runtime event adapter does not expose project graph data.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.partial,
          detail:
              'CLI execution is live for single-file and spio-routed project workflows.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.partial,
          detail:
              'Local CLI execution publishes replayable runtime event artifacts for completed sessions.',
          supportedContractVersions: <int>[1],
        ),
      ),
    ),
  };
}

class NoopRuntimeEventAdapter implements RuntimeEventAdapter {
  const NoopRuntimeEventAdapter({required this.capabilitySnapshot});

  @override
  final AdapterCapabilitySnapshot capabilitySnapshot;

  @override
  Stream<RuntimeEventEnvelope> sessionEvents(String sessionId) {
    return const Stream<RuntimeEventEnvelope>.empty();
  }
}

class _PublishedRuntimeEventAdapter implements RuntimeEventAdapter {
  const _PublishedRuntimeEventAdapter({required this.capabilitySnapshot});

  @override
  final AdapterCapabilitySnapshot capabilitySnapshot;

  @override
  Stream<RuntimeEventEnvelope> sessionEvents(String sessionId) {
    return _publishedRuntimeEvents(sessionId);
  }
}

Stream<RuntimeEventEnvelope> _publishedRuntimeEvents(String sessionId) {
  final events = _runtimeEventRegistry[sessionId];
  if (events == null || events.isEmpty) {
    return const Stream<RuntimeEventEnvelope>.empty();
  }
  return Stream<RuntimeEventEnvelope>.fromIterable(events);
}
