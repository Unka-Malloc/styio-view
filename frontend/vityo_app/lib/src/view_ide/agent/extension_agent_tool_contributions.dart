import '../module_host/module_host.dart';
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
      permissionMode:
          _permissionModeFromWire(
            _metadataString(route.contribution.metadata, 'permissionMode'),
          ) ??
          AgentToolPermissionMode.review,
      outputLimit: _metadataInt(route.contribution.metadata, 'outputLimit'),
      providerOutputLimits: _metadataProviderOutputLimits(
        route.contribution.metadata,
      ),
      todo:
          _metadataString(route.contribution.metadata, 'todo') ??
          'TODO: bind extension agent tool $toolId to an extension-host executor.',
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
        .where((contribution) => contribution.ready && contribution.tool != null)
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

List<AgentToolSchemaProperty> _metadataToolSchema(
  Map<String, Object?> metadata,
) {
  final value = metadata['schema'];
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
