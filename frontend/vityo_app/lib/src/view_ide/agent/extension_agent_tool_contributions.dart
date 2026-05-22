import '../module_host/module_host.dart';
import '../runtime/extension_host_supervisor_execution.dart';
import '../runtime/runtime_execution_plan.dart';
import '../runtime/runtime_output_channels.dart';
import 'agent_provider_kind.dart';
import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_registry.dart';

enum ExtensionAgentToolContributionStatus { ready, invalidRoute }

class ExtensionAgentToolContribution {
  const ExtensionAgentToolContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.handlerId = '',
    this.tool,
  });

  factory ExtensionAgentToolContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.agentProviderRegistry ||
        route.registryTargetId != 'agent.tools') {
      return ExtensionAgentToolContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionAgentToolContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready agent tool route.',
      );
    }
    final toolId =
        _metadataString(route.contribution.metadata, 'toolId') ??
        route.contribution.id;
    final tool = AgentToolDefinition(
      toolId: toolId,
      displayName:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          toolId,
      description:
          _metadataString(route.contribution.metadata, 'description') ??
          route.contribution.title ??
          'Extension agent tool $toolId.',
      priority: route.contribution.metadata['priority'] as int? ?? 0,
      builtin: false,
      supportedProviderKinds:
          _metadataStringList(
                route.contribution.metadata,
                'supportedProviderKinds',
              )
              .map(_agentProviderKindFromWire)
              .whereType<AgentProviderKind>()
              .toList(growable: false),
      supportedProtocols: _metadataStringList(
        route.contribution.metadata,
        'supportedProtocols',
      ),
      supportedModelPatterns: _metadataStringList(
        route.contribution.metadata,
        'supportedModelPatterns',
      ),
      capabilities: _metadataStringList(
        route.contribution.metadata,
        'capabilities',
      ),
      schema: _metadataToolSchema(route.contribution.metadata),
      resultSchema: _metadataToolSchema(
        route.contribution.metadata,
        key: 'resultSchema',
      ),
      permissionMode:
          _permissionModeFromWire(
            _metadataString(route.contribution.metadata, 'permissionMode'),
          ) ??
          AgentToolPermissionMode.review,
      outputLimit: _metadataInt(route.contribution.metadata, 'outputLimit'),
      providerOutputLimits: _metadataProviderOutputLimits(
        route.contribution.metadata,
      ),
      todo: _metadataString(route.contribution.metadata, 'todo') ?? '',
    );
    return ExtensionAgentToolContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionAgentToolContributionStatus.ready,
      message: 'Agent tool contribution ${route.contribution.id} is ready.',
      handlerId:
          _metadataString(route.contribution.metadata, 'handlerId') ??
          route.contribution.id,
      tool: tool,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionAgentToolContributionStatus status;
  final String message;
  final String handlerId;
  final AgentToolDefinition? tool;

  bool get ready => status == ExtensionAgentToolContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (handlerId.isNotEmpty) 'handlerId': handlerId,
      if (tool != null) 'tool': tool!.toJson(),
    };
  }
}

class ExtensionAgentToolContributionCatalog {
  const ExtensionAgentToolContributionCatalog({required this.contributions});

  factory ExtensionAgentToolContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionAgentToolContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.agentProviderRegistry)
          .where((route) => route.registryTargetId == 'agent.tools')
          .map(ExtensionAgentToolContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionAgentToolContribution> contributions;

  List<ExtensionAgentToolContribution> get readyContributions {
    return contributions
        .where(
          (contribution) => contribution.ready && contribution.tool != null,
        )
        .toList(growable: false);
  }

  List<AgentToolDefinition> get readyTools {
    return readyContributions
        .map((contribution) => contribution.tool)
        .whereType<AgentToolDefinition>()
        .toList(growable: false);
  }

  AgentToolRegistry toRegistry({bool includeDefaultTools = true}) {
    return AgentToolRegistry(
      tools: <AgentToolDefinition>[
        if (includeDefaultTools) ...AgentToolRegistry.defaultAgentTools,
        ...readyTools,
      ],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-agent-tool-contributions.v1',
      'contributionCount': contributions.length,
      'readyToolCount': readyTools.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}

typedef ExtensionAgentToolHandler =
    Future<AgentToolCallDispatchResult> Function(
      AgentToolCallDispatchRequest request,
    );

class ExtensionAgentToolHostRequest {
  const ExtensionAgentToolHostRequest({
    required this.extensionId,
    required this.contributionId,
    required this.handlerId,
    required this.toolCall,
  });

  final String extensionId;
  final String contributionId;
  final String handlerId;
  final AgentToolCallDispatchRequest toolCall;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'handlerId': handlerId,
      'toolCall': toolCall.toJson(),
    };
  }
}

typedef ExtensionAgentToolHostBridge =
    Future<AgentToolCallDispatchResult> Function(
      ExtensionAgentToolHostRequest request,
    );

typedef ExtensionAgentToolHostInvoker =
    Future<AgentToolCallDispatchResult> Function(
      ExtensionAgentToolHostInvocation invocation,
    );

class ExtensionAgentToolHostInvocation {
  const ExtensionAgentToolHostInvocation({
    required this.request,
    required this.plan,
    required this.dispatchResult,
    required this.timestamp,
  });

  final ExtensionAgentToolHostRequest request;
  final ExtensionHostSupervisorExecutionPlan plan;
  final RuntimeExecutionDispatchResult dispatchResult;
  final DateTime timestamp;

  String get extensionId => request.extensionId;
  String get contributionId => request.contributionId;
  String get handlerId => request.handlerId;
  AgentToolCallDispatchRequest get toolCall => request.toolCall;
  bool get dispatched => dispatchResult.dispatched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'handlerId': handlerId,
      'toolCall': toolCall.toJson(),
      'dispatched': dispatched,
      'timestamp': timestamp.toIso8601String(),
      'plan': plan.toJson(),
      'dispatchResult': dispatchResult.toJson(),
    };
  }
}

class ExtensionAgentToolActivatedHostBridge {
  ExtensionAgentToolActivatedHostBridge({
    required ExtensionHostSupervisorSnapshot snapshot,
    required RuntimeOutputLiveBuffer buffer,
    ExtensionManifestRegistry? manifestRegistry,
    ExtensionHostSupervisorExecutionBridge? supervisorBridge,
    ExtensionAgentToolHostInvoker? invoker,
    DateTime Function()? clock,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : _snapshot = snapshot,
       _buffer = buffer,
       _manifestRegistry = manifestRegistry,
       _supervisorBridge =
           supervisorBridge ?? ExtensionHostSupervisorExecutionBridge(),
       _invoker = invoker,
       _clock = clock ?? DateTime.now,
       _metadata = Map<String, Object?>.unmodifiable(metadata);

  final ExtensionHostSupervisorSnapshot _snapshot;
  final RuntimeOutputLiveBuffer _buffer;
  final ExtensionManifestRegistry? _manifestRegistry;
  final ExtensionHostSupervisorExecutionBridge _supervisorBridge;
  final ExtensionAgentToolHostInvoker? _invoker;
  final DateTime Function() _clock;
  final Map<String, Object?> _metadata;

  Future<AgentToolCallDispatchResult> call(
    ExtensionAgentToolHostRequest request,
  ) async {
    final record = _snapshot.lookup(request.extensionId);
    if (record == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.toolCall.callId,
        toolId: request.toolCall.toolId,
        message:
            'Extension host ${request.extensionId} is not present in the '
            'active supervisor snapshot.',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-activated-host-bridge',
          'missingSupervisorRecord': true,
          'extensionId': request.extensionId,
          'handlerId': request.handlerId,
        },
      );
    }
    if (!record.active) {
      return AgentToolCallDispatchResult.failure(
        callId: request.toolCall.callId,
        toolId: request.toolCall.toolId,
        message:
            'Extension host ${request.extensionId} is not active '
            '(${record.status.wireValue}).',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-activated-host-bridge',
          'inactiveExtensionHost': true,
          'extensionId': request.extensionId,
          'handlerId': request.handlerId,
          'supervisorStatus': record.status.wireValue,
          'supervisorAction': record.action.wireValue,
        },
      );
    }
    final timestamp = _clock();
    final plan = ExtensionHostSupervisorExecutionPlan.fromRecord(
      record,
      manifest: _manifestRegistry?.lookup(request.extensionId),
    );
    final dispatchResult = _supervisorBridge.dispatchPlan(
      plan: plan,
      buffer: _buffer,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'agentToolHostBridge': true,
        'toolId': request.toolCall.toolId,
        'callId': request.toolCall.callId,
        'handlerId': request.handlerId,
        ..._metadata,
      },
    );
    if (!dispatchResult.dispatched) {
      return AgentToolCallDispatchResult.failure(
        callId: request.toolCall.callId,
        toolId: request.toolCall.toolId,
        message:
            'Extension host ${request.extensionId} could not be dispatched '
            'for agent tool ${request.toolCall.toolId}.',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-activated-host-bridge',
          'extensionHostDispatchBlocked': true,
          'extensionId': request.extensionId,
          'handlerId': request.handlerId,
          'dispatchStatus': dispatchResult.status.wireValue,
          'managerId': dispatchResult.binding.managerId,
        },
      );
    }
    final invoker = _invoker;
    if (invoker == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.toolCall.callId,
        toolId: request.toolCall.toolId,
        message:
            'Extension host ${request.extensionId} is active, but no '
            'agent tool host invoker is attached for handler '
            '${request.handlerId}.',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-activated-host-bridge',
          'missingHostInvoker': true,
          'extensionHostDispatched': true,
          'extensionId': request.extensionId,
          'handlerId': request.handlerId,
          'dispatchStatus': dispatchResult.status.wireValue,
          'managerId': dispatchResult.binding.managerId,
        },
      );
    }
    try {
      return await invoker(
        ExtensionAgentToolHostInvocation(
          request: request,
          plan: plan,
          dispatchResult: dispatchResult,
          timestamp: timestamp,
        ),
      );
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: request.toolCall.callId,
        toolId: request.toolCall.toolId,
        message:
            'Extension host ${request.extensionId} failed handler '
            '${request.handlerId}: $error',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-activated-host-bridge',
          'hostInvocationFailed': true,
          'extensionId': request.extensionId,
          'handlerId': request.handlerId,
        },
      );
    }
  }
}

class ExtensionAgentToolHostInvokerRegistration {
  const ExtensionAgentToolHostInvokerRegistration({
    required this.extensionId,
    required this.handlerId,
    required this.label,
    required this.invoker,
    this.available = true,
    this.metadata = const <String, Object?>{},
  });

  final String extensionId;
  final String handlerId;
  final String label;
  final ExtensionAgentToolHostInvoker invoker;
  final bool available;
  final Map<String, Object?> metadata;

  bool accepts(ExtensionAgentToolHostInvocation invocation) {
    return available &&
        extensionId == invocation.extensionId &&
        handlerId == invocation.handlerId;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'handlerId': handlerId,
      'label': label,
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionAgentToolHostInvokerRegistry {
  ExtensionAgentToolHostInvokerRegistry({
    Iterable<ExtensionAgentToolHostInvokerRegistration> registrations =
        const <ExtensionAgentToolHostInvokerRegistration>[],
  }) {
    for (final registration in registrations) {
      register(registration);
    }
  }

  final List<ExtensionAgentToolHostInvokerRegistration> _registrations =
      <ExtensionAgentToolHostInvokerRegistration>[];

  List<ExtensionAgentToolHostInvokerRegistration> get registrations {
    return List<ExtensionAgentToolHostInvokerRegistration>.unmodifiable(
      _registrations,
    );
  }

  void register(ExtensionAgentToolHostInvokerRegistration registration) {
    _registrations.removeWhere(
      (candidate) =>
          candidate.extensionId == registration.extensionId &&
          candidate.handlerId == registration.handlerId,
    );
    _registrations.add(registration);
  }

  ExtensionAgentToolHostInvokerRegistration? resolve(
    ExtensionAgentToolHostInvocation invocation,
  ) {
    for (final registration in _registrations) {
      if (registration.accepts(invocation)) {
        return registration;
      }
    }
    return null;
  }

  Future<AgentToolCallDispatchResult> invoke(
    ExtensionAgentToolHostInvocation invocation,
  ) async {
    final registration = resolve(invocation);
    if (registration == null) {
      return AgentToolCallDispatchResult.failure(
        callId: invocation.toolCall.callId,
        toolId: invocation.toolCall.toolId,
        message:
            'No Extension Host agent tool invoker is registered for '
            '${invocation.extensionId}/${invocation.handlerId}.',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-host-invoker-registry',
          'missingHostInvokerRegistration': true,
          'extensionId': invocation.extensionId,
          'handlerId': invocation.handlerId,
        },
      );
    }
    try {
      final result = await registration.invoker(invocation);
      return AgentToolCallDispatchResult(
        callId: result.callId,
        toolId: result.toolId,
        success: result.success,
        message: result.message,
        output: result.output,
        metadata: <String, Object?>{
          ...registration.metadata,
          ...result.metadata,
          'extensionId': invocation.extensionId,
          'handlerId': invocation.handlerId,
          'invokerLabel': registration.label,
        },
      );
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: invocation.toolCall.callId,
        toolId: invocation.toolCall.toolId,
        message:
            'Extension Host agent tool invoker '
            '${invocation.extensionId}/${invocation.handlerId} failed: $error',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-host-invoker-registry',
          'hostInvokerFailed': true,
          'extensionId': invocation.extensionId,
          'handlerId': invocation.handlerId,
        },
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-agent-tool-host-invoker-registry.v1',
      'registrationCount': _registrations.length,
      'registrations': _registrations
          .map((registration) => registration.toJson())
          .toList(growable: false),
    };
  }
}

typedef ExtensionAgentToolHostRpcTransport =
    Future<AgentToolCallDispatchResult> Function(
      ExtensionAgentToolHostRpcRequest request,
    );

class ExtensionAgentToolHostRpcRequest {
  const ExtensionAgentToolHostRpcRequest({
    required this.invocation,
    required this.transportId,
    required this.label,
    required this.action,
    this.endpoint = '',
    this.metadata = const <String, Object?>{},
  });

  final ExtensionAgentToolHostInvocation invocation;
  final String transportId;
  final String label;
  final ExtensionHostSupervisorAction action;
  final String endpoint;
  final Map<String, Object?> metadata;

  String get extensionId => invocation.extensionId;
  String get contributionId => invocation.contributionId;
  String get handlerId => invocation.handlerId;
  AgentToolCallDispatchRequest get toolCall => invocation.toolCall;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'transportId': transportId,
      'label': label,
      'action': action.wireValue,
      if (endpoint.isNotEmpty) 'endpoint': endpoint,
      'extensionId': extensionId,
      'contributionId': contributionId,
      'handlerId': handlerId,
      'toolCall': toolCall.toJson(),
      'invocation': invocation.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionAgentToolHostRpcTransportRegistration {
  const ExtensionAgentToolHostRpcTransportRegistration({
    required this.extensionId,
    required this.handlerId,
    required this.action,
    required this.transportId,
    required this.label,
    required this.transport,
    this.endpoint = '',
    this.available = true,
    this.metadata = const <String, Object?>{},
  });

  final String extensionId;
  final String handlerId;
  final ExtensionHostSupervisorAction action;
  final String transportId;
  final String label;
  final ExtensionAgentToolHostRpcTransport transport;
  final String endpoint;
  final bool available;
  final Map<String, Object?> metadata;

  bool accepts(ExtensionAgentToolHostInvocation invocation) {
    return available &&
        extensionId == invocation.extensionId &&
        handlerId == invocation.handlerId &&
        action == invocation.plan.record.action;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'handlerId': handlerId,
      'action': action.wireValue,
      'transportId': transportId,
      'label': label,
      if (endpoint.isNotEmpty) 'endpoint': endpoint,
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionAgentToolHostRpcTransportRegistry {
  ExtensionAgentToolHostRpcTransportRegistry({
    Iterable<ExtensionAgentToolHostRpcTransportRegistration> registrations =
        const <ExtensionAgentToolHostRpcTransportRegistration>[],
  }) {
    for (final registration in registrations) {
      register(registration);
    }
  }

  final List<ExtensionAgentToolHostRpcTransportRegistration> _registrations =
      <ExtensionAgentToolHostRpcTransportRegistration>[];

  List<ExtensionAgentToolHostRpcTransportRegistration> get registrations {
    return List<ExtensionAgentToolHostRpcTransportRegistration>.unmodifiable(
      _registrations,
    );
  }

  void register(ExtensionAgentToolHostRpcTransportRegistration registration) {
    _registrations.removeWhere(
      (candidate) =>
          candidate.extensionId == registration.extensionId &&
          candidate.handlerId == registration.handlerId &&
          candidate.action == registration.action,
    );
    _registrations.add(registration);
  }

  ExtensionAgentToolHostRpcTransportRegistration? resolve(
    ExtensionAgentToolHostInvocation invocation,
  ) {
    for (final registration in _registrations) {
      if (registration.accepts(invocation)) {
        return registration;
      }
    }
    return null;
  }

  Future<AgentToolCallDispatchResult> invoke(
    ExtensionAgentToolHostInvocation invocation,
  ) async {
    final registration = resolve(invocation);
    if (registration == null) {
      return AgentToolCallDispatchResult.failure(
        callId: invocation.toolCall.callId,
        toolId: invocation.toolCall.toolId,
        message:
            'No Extension Host RPC transport is registered for '
            '${invocation.extensionId}/${invocation.handlerId} on '
            '${invocation.plan.record.action.wireValue}.',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-host-rpc-transport-registry',
          'missingRpcTransportBinding': true,
          'extensionId': invocation.extensionId,
          'handlerId': invocation.handlerId,
          'extensionHostAction': invocation.plan.record.action.wireValue,
        },
      );
    }
    final request = ExtensionAgentToolHostRpcRequest(
      invocation: invocation,
      transportId: registration.transportId,
      label: registration.label,
      action: registration.action,
      endpoint: registration.endpoint,
      metadata: registration.metadata,
    );
    try {
      final result = await registration.transport(request);
      return AgentToolCallDispatchResult(
        callId: result.callId,
        toolId: result.toolId,
        success: result.success,
        message: result.message,
        output: result.output,
        metadata: <String, Object?>{
          ...registration.metadata,
          ...result.metadata,
          'extensionId': invocation.extensionId,
          'handlerId': invocation.handlerId,
          'extensionHostAction': registration.action.wireValue,
          'transportId': registration.transportId,
          'transportLabel': registration.label,
          if (registration.endpoint.isNotEmpty)
            'endpoint': registration.endpoint,
        },
      );
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: invocation.toolCall.callId,
        toolId: invocation.toolCall.toolId,
        message:
            'Extension Host RPC transport ${registration.transportId} failed '
            'for ${invocation.extensionId}/${invocation.handlerId}: $error',
        metadata: <String, Object?>{
          'source': 'extension-agent-tool-host-rpc-transport-registry',
          'rpcTransportFailed': true,
          'extensionId': invocation.extensionId,
          'handlerId': invocation.handlerId,
          'transportId': registration.transportId,
        },
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-agent-tool-host-rpc-transport-registry.v1',
      'registrationCount': _registrations.length,
      'registrations': _registrations
          .map((registration) => registration.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionAgentToolHostRpcTransportCatalogIssue {
  const ExtensionAgentToolHostRpcTransportCatalogIssue({
    required this.extensionId,
    required this.handlerId,
    required this.issueCode,
    required this.message,
    this.action,
  });

  final String extensionId;
  final String handlerId;
  final String issueCode;
  final String message;
  final ExtensionHostSupervisorAction? action;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'handlerId': handlerId,
      'issueCode': issueCode,
      'message': message,
      if (action != null) 'action': action!.wireValue,
    };
  }
}

class ExtensionAgentToolHostRpcTransportCatalog {
  const ExtensionAgentToolHostRpcTransportCatalog({
    required this.registrations,
    required this.issues,
  });

  factory ExtensionAgentToolHostRpcTransportCatalog.fromContributions({
    required ExtensionAgentToolContributionCatalog catalog,
    required ExtensionHostSupervisorSnapshot snapshot,
    required Map<
      ExtensionHostSupervisorAction,
      ExtensionAgentToolHostRpcTransport
    >
    transports,
    Map<ExtensionHostSupervisorAction, String> transportIds =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, String> labels =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, String> endpoints =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, Map<String, Object?>> metadataByAction =
        const <ExtensionHostSupervisorAction, Map<String, Object?>>{},
  }) {
    final registrations = <ExtensionAgentToolHostRpcTransportRegistration>[];
    final issues = <ExtensionAgentToolHostRpcTransportCatalogIssue>[];
    for (final contribution in catalog.readyContributions) {
      final tool = contribution.tool;
      if (tool == null) {
        continue;
      }
      final record = snapshot.lookup(contribution.extensionId);
      if (record == null || !record.active) {
        issues.add(
          ExtensionAgentToolHostRpcTransportCatalogIssue(
            extensionId: contribution.extensionId,
            handlerId: contribution.handlerId,
            issueCode: 'inactive-extension-host',
            message:
                'Extension host ${contribution.extensionId} is not active for '
                'agent tool ${tool.toolId}.',
            action: record?.action,
          ),
        );
        continue;
      }
      final action = record.action;
      final transport = transports[action];
      if (transport == null) {
        issues.add(
          ExtensionAgentToolHostRpcTransportCatalogIssue(
            extensionId: contribution.extensionId,
            handlerId: contribution.handlerId,
            issueCode: 'missing-rpc-transport',
            message:
                'No RPC transport backend is registered for '
                '${contribution.extensionId}/${contribution.handlerId} on '
                '${action.wireValue}.',
            action: action,
          ),
        );
        continue;
      }
      registrations.add(
        ExtensionAgentToolHostRpcTransportRegistration(
          extensionId: contribution.extensionId,
          handlerId: contribution.handlerId,
          action: action,
          transportId: transportIds[action] ?? _defaultRpcTransportId(action),
          label: labels[action] ?? _defaultRpcTransportLabel(action),
          endpoint: endpoints[action] ?? '',
          transport: transport,
          metadata: <String, Object?>{
            'source': 'extension-agent-tool-host-rpc-transport-catalog',
            'contributionId': contribution.contributionId,
            'toolId': tool.toolId,
            ...?metadataByAction[action],
          },
        ),
      );
    }
    return ExtensionAgentToolHostRpcTransportCatalog(
      registrations:
          List<ExtensionAgentToolHostRpcTransportRegistration>.unmodifiable(
            registrations,
          ),
      issues: List<ExtensionAgentToolHostRpcTransportCatalogIssue>.unmodifiable(
        issues,
      ),
    );
  }

  final List<ExtensionAgentToolHostRpcTransportRegistration> registrations;
  final List<ExtensionAgentToolHostRpcTransportCatalogIssue> issues;

  bool get ready => issues.isEmpty;

  ExtensionAgentToolHostRpcTransportRegistry toRegistry() {
    return ExtensionAgentToolHostRpcTransportRegistry(
      registrations: registrations,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-agent-tool-host-rpc-transport-catalog.v1',
      'ready': ready,
      'registrationCount': registrations.length,
      'issueCount': issues.length,
      'registrations': registrations
          .map((registration) => registration.toJson())
          .toList(growable: false),
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }
}

class ExtensionAgentToolExecutionRegistry {
  ExtensionAgentToolExecutionRegistry({
    required ExtensionAgentToolContributionCatalog catalog,
    Map<String, ExtensionAgentToolHandler> handlers =
        const <String, ExtensionAgentToolHandler>{},
  }) : _toolIds = catalog.readyTools.map((tool) => tool.toolId).toSet(),
       _handlers = Map<String, ExtensionAgentToolHandler>.unmodifiable(
         handlers,
       );

  factory ExtensionAgentToolExecutionRegistry.fromHostBridge({
    required ExtensionAgentToolContributionCatalog catalog,
    required ExtensionAgentToolHostBridge hostBridge,
    Map<String, ExtensionAgentToolHandler> handlers =
        const <String, ExtensionAgentToolHandler>{},
  }) {
    final bridgedHandlers = <String, ExtensionAgentToolHandler>{};
    for (final contribution in catalog.readyContributions) {
      final tool = contribution.tool;
      if (tool == null) {
        continue;
      }
      bridgedHandlers[tool.toolId] = (request) {
        return hostBridge(
          ExtensionAgentToolHostRequest(
            extensionId: contribution.extensionId,
            contributionId: contribution.contributionId,
            handlerId: contribution.handlerId,
            toolCall: request,
          ),
        );
      };
    }
    return ExtensionAgentToolExecutionRegistry(
      catalog: catalog,
      handlers: <String, ExtensionAgentToolHandler>{
        ...bridgedHandlers,
        ...handlers,
      },
    );
  }

  final Set<String> _toolIds;
  final Map<String, ExtensionAgentToolHandler> _handlers;

  Set<String> get toolIds => Set<String>.unmodifiable(_toolIds);

  Set<String> get handlerToolIds {
    return Set<String>.unmodifiable(_handlers.keys.toSet());
  }

  bool canHandle(String toolId) {
    return _toolIds.contains(toolId) && _handlers.containsKey(toolId);
  }

  Future<AgentToolCallDispatchResult> dispatch(
    AgentToolCallDispatchRequest request,
  ) async {
    if (!_toolIds.contains(request.toolId)) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Extension agent tool ${request.toolId} is not declared by the active extension catalog.',
        metadata: const <String, Object?>{
          'source': 'extension-agent-tool-execution-registry',
          'missingDeclaration': true,
        },
      );
    }
    final handler = _handlers[request.toolId];
    if (handler == null) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message:
            'Extension agent tool ${request.toolId} has no registered execution handler.',
        metadata: const <String, Object?>{
          'source': 'extension-agent-tool-execution-registry',
          'missingHandler': true,
        },
      );
    }
    try {
      return await handler(request);
    } on Object catch (error) {
      return AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'Extension agent tool ${request.toolId} failed: $error',
        metadata: const <String, Object?>{
          'source': 'extension-agent-tool-execution-registry',
        },
      );
    }
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-agent-tool-execution-registry.v1',
      'toolIds': toolIds.toList(growable: false),
      'handlerToolIds': handlerToolIds.toList(growable: false),
      'missingHandlerToolIds': _toolIds
          .where((toolId) => !_handlers.containsKey(toolId))
          .toList(growable: false),
    };
  }
}

String _defaultRpcTransportId(ExtensionHostSupervisorAction action) {
  return switch (action) {
    ExtensionHostSupervisorAction.runInProcess => 'in-process-rpc',
    ExtensionHostSupervisorAction.spawnLocalProcess => 'local-process-rpc',
    ExtensionHostSupervisorAction.spawnWebWorker => 'web-worker-rpc',
    ExtensionHostSupervisorAction.connectRemoteService => 'remote-service-rpc',
    ExtensionHostSupervisorAction.none => 'inactive-extension-host-rpc',
  };
}

String _defaultRpcTransportLabel(ExtensionHostSupervisorAction action) {
  return switch (action) {
    ExtensionHostSupervisorAction.runInProcess => 'In-Process RPC',
    ExtensionHostSupervisorAction.spawnLocalProcess => 'Local Process RPC',
    ExtensionHostSupervisorAction.spawnWebWorker => 'Web Worker RPC',
    ExtensionHostSupervisorAction.connectRemoteService => 'Remote Service RPC',
    ExtensionHostSupervisorAction.none => 'Inactive Extension Host RPC',
  };
}

List<AgentToolSchemaProperty> _metadataToolSchema(
  Map<String, Object?> metadata, {
  String key = 'schema',
}) {
  final value = metadata[key];
  if (value is! List) {
    return const <AgentToolSchemaProperty>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => item.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      )
      .where((item) => _metadataString(item, 'name') != null)
      .map(
        (item) => AgentToolSchemaProperty(
          name: _metadataString(item, 'name')!,
          type: _metadataString(item, 'type') ?? 'string',
          description: _metadataString(item, 'description') ?? '',
          required: item['required'] as bool? ?? false,
        ),
      )
      .toList(growable: false);
}

Map<AgentProviderKind, int> _metadataProviderOutputLimits(
  Map<String, Object?> metadata,
) {
  final value = metadata['providerOutputLimits'];
  if (value is! Map) {
    return const <AgentProviderKind, int>{};
  }
  final result = <AgentProviderKind, int>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final limit = entry.value;
    if (key is! String || limit is! int || limit <= 0) {
      continue;
    }
    final providerKind = _agentProviderKindFromWire(key);
    if (providerKind == null) {
      continue;
    }
    result[providerKind] = limit;
  }
  return Map<AgentProviderKind, int>.unmodifiable(result);
}

AgentToolPermissionMode? _permissionModeFromWire(String? value) {
  return switch (value) {
    'never' => AgentToolPermissionMode.never,
    'review' => AgentToolPermissionMode.review,
    'always' => AgentToolPermissionMode.always,
    _ => null,
  };
}

AgentProviderKind? _agentProviderKindFromWire(String value) {
  return switch (value) {
    'cloud_openai_compatible' => AgentProviderKind.cloudOpenAICompatible,
    'local_bridge' => AgentProviderKind.localBridge,
    'local_only_fallback' => AgentProviderKind.localOnlyFallback,
    _ => null,
  };
}

int? _metadataInt(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is int && value > 0 ? value : null;
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

List<String> _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .map((item) => item.trim())
      .toList(growable: false);
}
