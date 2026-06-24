import 'agent_profile.dart';
import 'agent_provider_kind.dart';

enum AgentToolPermissionMode { never, review, always }

extension AgentToolPermissionModeX on AgentToolPermissionMode {
  String get wireValue => switch (this) {
    AgentToolPermissionMode.never => 'never',
    AgentToolPermissionMode.review => 'review',
    AgentToolPermissionMode.always => 'always',
  };
}

class AgentToolSchemaProperty {
  const AgentToolSchemaProperty({
    required this.name,
    required this.type,
    this.description = '',
    this.required = false,
  });

  final String name;
  final String type;
  final String description;
  final bool required;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'type': type,
      'required': required,
      if (description.isNotEmpty) 'description': description,
    };
  }

  Map<String, Object?> toJsonSchema() {
    final schema = _agentToolPropertyTypeJsonSchema(type);
    if (description.isNotEmpty) {
      schema['description'] = description;
    }
    return schema;
  }
}

class AgentToolDefinition {
  const AgentToolDefinition({
    required this.toolId,
    required this.displayName,
    required this.description,
    this.priority = 0,
    this.builtin = true,
    this.supportedProviderKinds = const <AgentProviderKind>[],
    this.supportedProtocols = const <String>[],
    this.supportedModelPatterns = const <String>[],
    this.capabilities = const <String>[],
    this.schema = const <AgentToolSchemaProperty>[],
    this.resultSchema = const <AgentToolSchemaProperty>[],
    this.permissionMode = AgentToolPermissionMode.review,
    this.outputLimit,
    this.providerOutputLimits = const <AgentProviderKind, int>{},
    this.todo = '',
  });

  final String toolId;
  final String displayName;
  final String description;
  final int priority;
  final bool builtin;
  final List<AgentProviderKind> supportedProviderKinds;
  final List<String> supportedProtocols;
  final List<String> supportedModelPatterns;
  final List<String> capabilities;
  final List<AgentToolSchemaProperty> schema;
  final List<AgentToolSchemaProperty> resultSchema;
  final AgentToolPermissionMode permissionMode;
  final int? outputLimit;
  final Map<AgentProviderKind, int> providerOutputLimits;
  final String todo;

  bool supports(AgentToolSelectionContext context) {
    return _providerKindMatches(context) &&
        _protocolMatches(context) &&
        _modelMatches(context);
  }

  bool _providerKindMatches(AgentToolSelectionContext context) {
    return supportedProviderKinds.isEmpty ||
        supportedProviderKinds.contains(context.providerKind);
  }

  bool _protocolMatches(AgentToolSelectionContext context) {
    final protocols = supportedProtocols
        .map((protocol) => protocol.trim().toLowerCase())
        .where((protocol) => protocol.isNotEmpty)
        .toSet();
    return protocols.isEmpty || protocols.contains(context.protocol);
  }

  bool _modelMatches(AgentToolSelectionContext context) {
    final patterns = supportedModelPatterns
        .map((pattern) => pattern.trim().toLowerCase())
        .where((pattern) => pattern.isNotEmpty)
        .toList(growable: false);
    return patterns.isEmpty ||
        patterns.any((pattern) => context.model.contains(pattern));
  }

  int? outputLimitFor(AgentToolSelectionContext context) {
    return _positiveLimit(providerOutputLimits[context.providerKind]) ??
        _positiveLimit(outputLimit);
  }

  Map<String, Object?> parametersJsonSchema({
    bool additionalProperties = false,
  }) {
    return _agentToolObjectJsonSchema(
      schema,
      additionalProperties: additionalProperties,
    );
  }

  Map<String, Object?> resultJsonSchema({bool additionalProperties = true}) {
    return _agentToolObjectJsonSchema(
      resultSchema,
      additionalProperties: additionalProperties,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'toolId': toolId,
      'displayName': displayName,
      'description': description,
      'priority': priority,
      'builtin': builtin,
      'permissionMode': permissionMode.wireValue,
      'supportedProviderKinds': supportedProviderKinds
          .map((kind) => kind.wireValue)
          .toList(growable: false),
      'supportedProtocols': supportedProtocols,
      'supportedModelPatterns': supportedModelPatterns,
      'capabilities': capabilities,
      'schema': schema.map((property) => property.toJson()).toList(),
      if (resultSchema.isNotEmpty)
        'resultSchema': resultSchema
            .map((property) => property.toJson())
            .toList(growable: false),
      if (resultSchema.isNotEmpty) 'resultJsonSchema': resultJsonSchema(),
      if (outputLimit != null) 'outputLimit': outputLimit,
      if (providerOutputLimits.isNotEmpty)
        'providerOutputLimits': providerOutputLimits.map(
          (kind, limit) => MapEntry(kind.wireValue, limit),
        ),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class AgentToolSelectionContext {
  const AgentToolSelectionContext({
    required this.providerKind,
    required this.protocol,
    required this.model,
  });

  factory AgentToolSelectionContext.fromProfile({
    required AgentPromptProfile profile,
    required AgentProviderKind providerKind,
  }) {
    return AgentToolSelectionContext(
      providerKind: providerKind,
      protocol: profile.endpoint.protocol.trim().toLowerCase(),
      model: profile.endpoint.model.trim().toLowerCase(),
    );
  }

  final AgentProviderKind providerKind;
  final String protocol;
  final String model;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'protocol': protocol,
      'model': model,
    };
  }
}

class AgentToolSelection {
  const AgentToolSelection({
    required this.context,
    required this.tools,
    this.rejectedToolIds = const <String>[],
    this.todoItems = const <String>[],
  });

  final AgentToolSelectionContext context;
  final List<AgentToolDefinition> tools;
  final List<String> rejectedToolIds;
  final List<String> todoItems;

  List<String> get toolIds {
    return tools.map((tool) => tool.toolId).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'context': context.toJson(),
      'toolCount': tools.length,
      'toolIds': toolIds,
      'rejectedToolIds': rejectedToolIds,
      'tools': tools.map((tool) => tool.toJson()).toList(growable: false),
      'todoItems': todoItems,
    };
  }
}

class AgentToolRegistry {
  AgentToolRegistry({Iterable<AgentToolDefinition> tools = defaultAgentTools}) {
    for (final tool in tools) {
      register(tool);
    }
  }

  final Map<String, AgentToolDefinition> _tools =
      <String, AgentToolDefinition>{};

  static const List<AgentToolDefinition>
  defaultAgentTools = <AgentToolDefinition>[
    AgentToolDefinition(
      toolId: 'readWorkspaceFile',
      displayName: 'Read Workspace File',
      description:
          'Read an IDE-owned workspace file through Vityo workspace/file binding.',
      priority: 100,
      permissionMode: AgentToolPermissionMode.never,
      capabilities: <String>['workspace.read', 'context.file'],
      schema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(
          name: 'path',
          type: 'string',
          required: true,
          description: 'Workspace-relative file path.',
        ),
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(
          name: 'document',
          type: 'object',
          required: true,
        ),
      ],
      todo:
          'Route inactive document reads through File System Manager/DataStore once the backend workspace service is attached.',
    ),
    AgentToolDefinition(
      toolId: 'previewWorkspaceEdit',
      displayName: 'Preview Workspace Edit',
      description:
          'Build a reviewable workspace edit preview before applying generated changes.',
      priority: 90,
      permissionMode: AgentToolPermissionMode.review,
      capabilities: <String>['workspace.edit.preview', 'change.review'],
      schema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(
          name: 'patch',
          type: 'string|object',
          description:
              'Structured patch object or JSON string. If omitted, top-level edits may be used.',
        ),
        AgentToolSchemaProperty(
          name: 'edits',
          type: 'array',
          description: 'Structured workspace edit operations.',
        ),
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(name: 'patch', type: 'object', required: true),
        AgentToolSchemaProperty(
          name: 'conversion',
          type: 'object',
          required: true,
        ),
      ],
    ),
    AgentToolDefinition(
      toolId: 'applyWorkspacePatch',
      displayName: 'Apply Workspace Patch',
      description:
          'Apply a structured patch after preview and review gates pass.',
      priority: 80,
      supportedProtocols: <String>['openai-responses'],
      supportedModelPatterns: <String>['gpt'],
      permissionMode: AgentToolPermissionMode.review,
      capabilities: <String>['workspace.patch.apply'],
      schema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(
          name: 'patch',
          type: 'string|object',
          description:
              'Structured patch object or JSON string. If omitted, top-level edits may be used.',
        ),
        AgentToolSchemaProperty(
          name: 'edits',
          type: 'array',
          description: 'Structured workspace edit operations.',
        ),
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(name: 'patch', type: 'object', required: true),
        AgentToolSchemaProperty(name: 'result', type: 'object', required: true),
      ],
      todo:
          'Review patches that overlap dirty or externally modified documents before apply.',
    ),
    AgentToolDefinition(
      toolId: 'runIdeCommand',
      displayName: 'Run IDE Command',
      description:
          'Request a registered Vityo IDE command by command id and typed input.',
      priority: 70,
      permissionMode: AgentToolPermissionMode.review,
      capabilities: <String>['ide.command'],
      schema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(
          name: 'commandId',
          type: 'string',
          required: true,
          description: 'Registered Vityo command id.',
        ),
        AgentToolSchemaProperty(
          name: 'input',
          type: 'string|object',
          description: 'Command input matching the command contract.',
        ),
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(name: 'command', type: 'object'),
        AgentToolSchemaProperty(name: 'result', type: 'object'),
      ],
    ),
    AgentToolDefinition(
      toolId: 'collectStyioLanguageContext',
      displayName: 'Collect Styio Language Context',
      description:
          'Collect current Styio language facts from the IDE context without re-parsing source.',
      priority: 65,
      permissionMode: AgentToolPermissionMode.never,
      capabilities: <String>[
        'language.context',
        'language.diagnostics',
        'language.semantic',
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(
          name: 'language',
          type: 'object',
          required: true,
        ),
      ],
      todo:
          'Prefer StyioService-authored facts when the external service exposes the full semantic contract.',
    ),
    AgentToolDefinition(
      toolId: 'collectAgentValidationContext',
      displayName: 'Collect Agent Validation Context',
      description:
          'Collect the current agent validation plan, runnable IDE command ids, results, and testing context.',
      priority: 62,
      permissionMode: AgentToolPermissionMode.never,
      capabilities: <String>[
        'agent.validation',
        'agent.validation.pipeline',
        'agent.validation.command.results',
        'testing.context',
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(
          name: 'validation',
          type: 'object',
          required: true,
        ),
      ],
    ),
    AgentToolDefinition(
      toolId: 'collectAgentRecoveryContext',
      displayName: 'Collect Agent Recovery Context',
      description:
          'Collect recoverable agent session state, replay drafts, retry/failover command plans, persisted tool execution journals, and tool session transcripts.',
      priority: 61,
      permissionMode: AgentToolPermissionMode.never,
      capabilities: <String>[
        'agent.recovery',
        'agent.replay',
        'agent.session.history',
        'agent.tool.execution.journal',
        'agent.tool.session.transcript',
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(
          name: 'recovery',
          type: 'object',
          required: true,
        ),
      ],
    ),
    AgentToolDefinition(
      toolId: 'collectAgentCodingCheckpoint',
      displayName: 'Collect Agent Coding Checkpoint',
      description:
          'Collect current IDE, language, testing, toolchain, and agent loop facts.',
      priority: 60,
      permissionMode: AgentToolPermissionMode.never,
      capabilities: <String>['agent.checkpoint'],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string', required: true),
        AgentToolSchemaProperty(
          name: 'checkpoint',
          type: 'object',
          required: true,
        ),
      ],
    ),
    AgentToolDefinition(
      toolId: 'openLocalShell',
      displayName: 'Open Local Shell',
      description:
          'Request a local shell-backed execution route when the provider uses a local bridge.',
      priority: 10,
      supportedProviderKinds: <AgentProviderKind>[
        AgentProviderKind.localBridge,
      ],
      permissionMode: AgentToolPermissionMode.review,
      capabilities: <String>[
        'runtime.shell',
        'network',
        'destructive',
      ],
      schema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(
          name: 'command',
          type: 'string',
          required: true,
          description: 'Command to run through the local execution route.',
        ),
      ],
      resultSchema: <AgentToolSchemaProperty>[
        AgentToolSchemaProperty(name: 'source', type: 'string'),
        AgentToolSchemaProperty(name: 'execution', type: 'object'),
      ],
      todo:
          'Bind to Execution Manager and PTY Manager with local bridge safety review.',
    ),
  ];

  List<AgentToolDefinition> get tools {
    final values = _tools.values.toList(growable: false);
    values.sort(_compareTools);
    return List<AgentToolDefinition>.unmodifiable(values);
  }

  void register(AgentToolDefinition tool) {
    final toolId = tool.toolId.trim();
    if (toolId.isEmpty) {
      throw ArgumentError.value(tool.toolId, 'toolId', 'Tool id is required.');
    }
    _tools[toolId] = tool;
  }

  AgentToolSelection select(AgentToolSelectionContext context) {
    final accepted = <AgentToolDefinition>[];
    final rejected = <String>[];
    final todos = <String>{};
    for (final tool in tools) {
      if (tool.supports(context)) {
        accepted.add(tool);
        if (tool.todo.isNotEmpty) {
          todos.add(tool.todo);
        }
      } else {
        rejected.add(tool.toolId);
      }
    }
    return AgentToolSelection(
      context: context,
      tools: List<AgentToolDefinition>.unmodifiable(accepted),
      rejectedToolIds: List<String>.unmodifiable(rejected),
      todoItems: List<String>.unmodifiable(todos),
    );
  }

  AgentToolSelection selectForProfile({
    required AgentPromptProfile profile,
    required AgentProviderKind providerKind,
  }) {
    return select(
      AgentToolSelectionContext.fromProfile(
        profile: profile,
        providerKind: providerKind,
      ),
    );
  }

  int? outputLimitForTool({
    required String toolId,
    required AgentToolSelectionContext context,
  }) {
    final tool = _tools[toolId.trim()];
    if (tool == null || !tool.supports(context)) {
      return null;
    }
    return tool.outputLimitFor(context);
  }

  Map<String, Object?> manifest() {
    return <String, Object?>{
      'toolCount': tools.length,
      'tools': tools.map((tool) => tool.toJson()).toList(growable: false),
    };
  }
}

int? _positiveLimit(int? value) {
  return value == null || value <= 0 ? null : value;
}

int _compareTools(AgentToolDefinition left, AgentToolDefinition right) {
  final priority = right.priority.compareTo(left.priority);
  if (priority != 0) {
    return priority;
  }
  return left.toolId.compareTo(right.toolId);
}

Map<String, Object?> _agentToolObjectJsonSchema(
  List<AgentToolSchemaProperty> schema, {
  required bool additionalProperties,
}) {
  return <String, Object?>{
    'type': 'object',
    'additionalProperties': additionalProperties,
    'properties': <String, Object?>{
      for (final property in schema) property.name: property.toJsonSchema(),
    },
    'required': schema
        .where((property) => property.required)
        .map((property) => property.name)
        .toList(growable: false),
  };
}

Map<String, Object?> _agentToolPropertyTypeJsonSchema(String type) {
  final types = type
      .split('|')
      .map((item) => item.trim().toLowerCase())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (types.length > 1) {
    return <String, Object?>{
      'oneOf': types.map(_agentToolPropertyTypeJsonSchema).toList(),
    };
  }
  final normalized = types.isEmpty ? 'object' : types.single;
  return switch (normalized) {
    'string' => <String, Object?>{'type': 'string'},
    'array' => <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': true,
      },
    },
    'boolean' || 'bool' => <String, Object?>{'type': 'boolean'},
    'number' => <String, Object?>{'type': 'number'},
    'integer' || 'int' => <String, Object?>{'type': 'integer'},
    'object' => <String, Object?>{
      'type': 'object',
      'additionalProperties': true,
    },
    'any' || 'json' => <String, Object?>{'additionalProperties': true},
    _ => <String, Object?>{'additionalProperties': true},
  };
}
