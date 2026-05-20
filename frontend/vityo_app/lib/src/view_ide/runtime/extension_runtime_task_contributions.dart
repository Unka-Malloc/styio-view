import '../module_host/module_host.dart';
import 'runtime_execution_plan.dart';
import 'runtime_output_channels.dart';
import 'runtime_task_lifecycle.dart';

enum ExtensionRuntimeTaskContributionStatus {
  ready,
  invalidRoute,
  missingCommand,
}

class ExtensionRuntimeTaskContribution {
  const ExtensionRuntimeTaskContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.definition,
  });

  factory ExtensionRuntimeTaskContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.runtimeTaskRegistry) {
      return ExtensionRuntimeTaskContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionRuntimeTaskContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready runtime task route.',
      );
    }
    final command = _metadataString(route.contribution.metadata, 'command');
    if (command == null) {
      return ExtensionRuntimeTaskContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionRuntimeTaskContributionStatus.missingCommand,
        message:
            'Runtime task contribution ${route.contribution.id} does not declare metadata.command.',
      );
    }
    final definition = RuntimeTaskDefinition(
      id:
          _metadataString(route.contribution.metadata, 'taskId') ??
          route.contribution.id,
      label:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          route.contribution.id,
      kind: _runtimeTaskKindFromMetadata(route.contribution.metadata),
      command: command,
      arguments: _metadataStringList(route.contribution.metadata, 'arguments'),
      workingDirectory: _metadataString(
        route.contribution.metadata,
        'workingDirectory',
      ),
      environment: _metadataStringMap(
        route.contribution.metadata,
        'environment',
      ),
      dependsOn: _metadataStringList(route.contribution.metadata, 'dependsOn'),
      group: _metadataString(route.contribution.metadata, 'group'),
      terminalProfileId: _metadataString(
        route.contribution.metadata,
        'terminalProfileId',
      ),
      background: route.contribution.metadata['background'] as bool? ?? false,
      metadata: <String, Object?>{
        ...route.contribution.metadata,
        'extensionId': route.extensionId,
        'contributionId': route.contribution.id,
        'source': 'extension-runtime-task-contribution',
      },
    );
    return ExtensionRuntimeTaskContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionRuntimeTaskContributionStatus.ready,
      message: 'Runtime task contribution ${route.contribution.id} is ready.',
      definition: definition,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionRuntimeTaskContributionStatus status;
  final String message;
  final RuntimeTaskDefinition? definition;

  bool get ready => status == ExtensionRuntimeTaskContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (definition != null) 'definition': definition!.toJson(),
    };
  }
}

class ExtensionRuntimeTaskContributionCatalog {
  const ExtensionRuntimeTaskContributionCatalog({required this.contributions});

  factory ExtensionRuntimeTaskContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionRuntimeTaskContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.runtimeTaskRegistry)
          .map(ExtensionRuntimeTaskContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionRuntimeTaskContribution> contributions;

  List<RuntimeTaskDefinition> get readyDefinitions {
    return contributions
        .map((contribution) => contribution.definition)
        .whereType<RuntimeTaskDefinition>()
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-runtime-task-contributions.v1',
      'contributionCount': contributions.length,
      'readyDefinitionCount': readyDefinitions.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionRuntimeTaskExecutionPlan {
  const ExtensionRuntimeTaskExecutionPlan({
    required this.contribution,
    required this.executionPlan,
    required this.handoff,
    required this.binding,
  });

  factory ExtensionRuntimeTaskExecutionPlan.fromContribution(
    ExtensionRuntimeTaskContribution contribution, {
    String outputChannelId = '',
  }) {
    final definition = contribution.definition;
    final executionPlan = definition == null
        ? RuntimeExecutionPlan(
            definition: RuntimeTaskDefinition(
              id: contribution.contributionId,
              label: contribution.contributionId,
              kind: RuntimeTaskKind.run,
              command: '',
              metadata: <String, Object?>{
                'extensionId': contribution.extensionId,
                'contributionId': contribution.contributionId,
              },
            ),
            status: RuntimeExecutionPlanStatus.blockedUnrunnable,
            message: contribution.message,
          )
        : const RuntimeExecutionPlanner().plan(definition: definition);
    final target = definition == null
        ? RuntimeExecutionHandoffTarget.terminalRuntime
        : _runtimeTaskHandoffTargetFromMetadata(definition);
    final channelId = outputChannelId.trim().isEmpty
        ? 'extension.task.${contribution.extensionId}.${contribution.contributionId}'
        : outputChannelId.trim();
    final handoff = executionPlan.createHandoff(
      target: target,
      outputChannelId: channelId,
      metadata: <String, Object?>{
        'extensionId': contribution.extensionId,
        'contributionId': contribution.contributionId,
        'extensionRuntimeTask': true,
      },
    );
    final binding = handoff.bind(
      outputKind: _runtimeOutputKindForTarget(target),
      metadata: <String, Object?>{
        'extensionId': contribution.extensionId,
        'contributionId': contribution.contributionId,
        'extensionRuntimeTask': true,
      },
    );
    return ExtensionRuntimeTaskExecutionPlan(
      contribution: contribution,
      executionPlan: executionPlan,
      handoff: handoff,
      binding: binding,
    );
  }

  final ExtensionRuntimeTaskContribution contribution;
  final RuntimeExecutionPlan executionPlan;
  final RuntimeExecutionHandoff handoff;
  final RuntimeExecutionHandoffBinding binding;

  bool get ready => contribution.ready && executionPlan.ready && binding.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'contribution': contribution.toJson(),
      'executionPlan': executionPlan.toJson(),
      'handoff': handoff.toJson(),
      'binding': binding.toJson(),
    };
  }
}

class ExtensionRuntimeTaskExecutionBridge {
  ExtensionRuntimeTaskExecutionBridge({
    RuntimeExecutionManagerRegistry? registry,
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers();

  final RuntimeExecutionManagerRegistry _registry;

  RuntimeExecutionDispatchResult dispatchToLiveBuffer({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _registry.dispatchToLiveBuffer(
      plan.binding,
      buffer: buffer,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'extensionId': plan.contribution.extensionId,
        'contributionId': plan.contribution.contributionId,
        'extensionRuntimeTask': true,
        ...metadata,
      },
    );
  }
}

RuntimeTaskKind _runtimeTaskKindFromMetadata(Map<String, Object?> metadata) {
  final value = _metadataString(metadata, 'kind');
  return switch (value) {
    'shell' => RuntimeTaskKind.shell,
    'build' => RuntimeTaskKind.build,
    'test' => RuntimeTaskKind.test,
    'debug' => RuntimeTaskKind.debug,
    'agent' => RuntimeTaskKind.agent,
    'toolchain' => RuntimeTaskKind.toolchain,
    _ => RuntimeTaskKind.run,
  };
}

RuntimeExecutionHandoffTarget _runtimeTaskHandoffTargetFromMetadata(
  RuntimeTaskDefinition definition,
) {
  final explicitTarget = _metadataString(definition.metadata, 'handoffTarget');
  return switch (explicitTarget) {
    'shell-manager' => RuntimeExecutionHandoffTarget.shellManager,
    'terminal-runtime' => RuntimeExecutionHandoffTarget.terminalRuntime,
    'toolchain-manager' => RuntimeExecutionHandoffTarget.toolchainManager,
    'hosted-executor' => RuntimeExecutionHandoffTarget.hostedExecutor,
    _ => switch (definition.kind) {
      RuntimeTaskKind.shell => RuntimeExecutionHandoffTarget.shellManager,
      RuntimeTaskKind.build ||
      RuntimeTaskKind.test ||
      RuntimeTaskKind.debug ||
      RuntimeTaskKind.toolchain =>
        RuntimeExecutionHandoffTarget.toolchainManager,
      RuntimeTaskKind.run ||
      RuntimeTaskKind.agent => RuntimeExecutionHandoffTarget.terminalRuntime,
    },
  };
}

RuntimeOutputChannelKind _runtimeOutputKindForTarget(
  RuntimeExecutionHandoffTarget target,
) {
  return switch (target) {
    RuntimeExecutionHandoffTarget.shellManager =>
      RuntimeOutputChannelKind.stdout,
    RuntimeExecutionHandoffTarget.terminalRuntime =>
      RuntimeOutputChannelKind.runtimeEvents,
    RuntimeExecutionHandoffTarget.toolchainManager =>
      RuntimeOutputChannelKind.nativeTools,
    RuntimeExecutionHandoffTarget.hostedExecutor =>
      RuntimeOutputChannelKind.runtimeEvents,
  };
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

Map<String, String> _metadataStringMap(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! Map) {
    return const <String, String>{};
  }
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}
