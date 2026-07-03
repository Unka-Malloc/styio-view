import 'package:flutter/material.dart';

import '../../view_ide/backend_toolchain/adapter_contracts.dart';
import '../../view_ide/backend_toolchain/execution_adapter.dart';
import '../../view_ide/backend_toolchain/execution_route_summary.dart';
import '../../view_ide/backend_toolchain/project_graph_contract.dart';
import '../../view_ide/commands/commands.dart';
import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/module_host/module_definition.dart';
import '../../view_ide/module_host/module_manifest.dart';
import '../../view_ide/platform/platform_target.dart';
import '../../view_ide/runtime/runtime_output_channels.dart';
import '../../view_ide/runtime/runtime_surface_feature_registry.dart';
import '../../view_ide/runtime/runtime_replay_summary.dart';
import '../../view_ide/shell_runtime/shell_runtime.dart';
import '../native_tool_result_summary.dart';
import '../platform/viewport_profile.dart';

typedef ToolchainRecoveryActionHandler =
    Future<void> Function(ToolchainRecoveryAction action);

class RuntimeSurface extends StatelessWidget {
  const RuntimeSurface({
    super.key,
    required this.platformTarget,
    required this.viewportProfile,
    required this.projectGraph,
    required this.toolchainStatus,
    this.onToolchainRecoveryAction,
    required this.mountedModules,
    required this.adapterCapabilities,
    required this.executionSession,
    required this.runtimeEvents,
    this.nativeToolResults = const <NativeToolResultRecord>[],
    this.outputSnapshot,
    this.outputChannelFilter = const RuntimeOutputChannelFilterState(),
    this.onOpenNativeToolDiagnostics,
  });

  final PlatformTarget platformTarget;
  final ViewportProfile viewportProfile;
  final ProjectGraphSnapshot projectGraph;
  final ToolchainStatusSurface toolchainStatus;
  final ToolchainRecoveryActionHandler? onToolchainRecoveryAction;
  final List<ModuleDefinition> mountedModules;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;
  final ExecutionSession? executionSession;
  final List<RuntimeEventEnvelope> runtimeEvents;
  final List<NativeToolResultRecord> nativeToolResults;
  final RuntimeOutputPanelSnapshot? outputSnapshot;
  final RuntimeOutputChannelFilterState outputChannelFilter;
  final ValueChanged<AppCommandId>? onOpenNativeToolDiagnostics;

  @override
  Widget build(BuildContext context) {
    final runtimeFeatures = runtimeSurfaceFeatureEntriesFor(mountedModules);
    final routeSelection = selectBackendExecutionRoute(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      adapterCapabilities: adapterCapabilities,
    );
    final replay = summarizeRuntimeReplay(runtimeEvents);
    final graph = summarizeRuntimeGraph(runtimeEvents);
    final debugLanes = summarizeRuntimeDebugLanes(runtimeEvents);
    final laneCount =
        runtimeFeatures.any(
          (feature) => feature.slot == ModuleSlot.localRuntime,
        )
        ? 3
        : (replay.lanes.isNotEmpty ? replay.lanes.length : 1);
    final executionCapability = _executionCapabilityFor(
      adapterCapabilities,
      routeSelection.adapterKind,
    );
    final cardSpacing = viewportProfile.isMobile ? 12.0 : 14.0;

    return _SurfaceFrame(
      key: ValueKey('runtime-surface-${viewportProfile.label.toLowerCase()}'),
      title: 'Runtime Surface',
      subtitle:
          '${platformTarget.label} runtime route aligned to the ${viewportProfile.label.toLowerCase()} shell.',
      child: viewportProfile.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricSection(
                  title: 'Execution Route',
                  body:
                      '${routeSelection.title} (${routeSelection.routeKind.wireValue}). ${routeSelection.detail} ${executionCapability.detail}',
                  accent: const Color(0xFFD9E8F8),
                ),
                SizedBox(height: cardSpacing),
                _ToolchainStatusSection(
                  status: toolchainStatus,
                  onRecoveryAction: onToolchainRecoveryAction,
                ),
                SizedBox(height: cardSpacing),
                _MetricSection(
                  title: 'Lane Preview',
                  body: runtimeEvents.isEmpty
                      ? '$laneCount lane slot(s) reserved. Runtime lanes will populate when a project session publishes replayable runtime events.'
                      : '$laneCount lane slot(s) inferred from ${runtimeEvents.length} published runtime event(s). ${replay.summarySentence}',
                  accent: const Color(0xFFEDE6D9),
                ),
                SizedBox(height: cardSpacing),
                _MetricSection(
                  title: 'Registry Gate',
                  body:
                      '${runtimeFeatures.length} runtime-related feature(s) mounted. Unsupported semantic subsets will continue to degrade explicitly.',
                  accent: const Color(0xFFE4E7D2),
                ),
                SizedBox(height: cardSpacing),
                _ExecutionSessionSection(
                  executionSession: executionSession,
                  runtimeEventCount: runtimeEvents.length,
                ),
                SizedBox(height: cardSpacing),
                _NativeToolResultSection(
                  results: nativeToolResults,
                  onOpenNativeToolDiagnostics: onOpenNativeToolDiagnostics,
                ),
                SizedBox(height: cardSpacing),
                _OutputChannelSection(
                  executionSession: executionSession,
                  runtimeEvents: runtimeEvents,
                  nativeToolResults: nativeToolResults,
                  outputSnapshot: outputSnapshot,
                  filter: outputChannelFilter,
                ),
                SizedBox(height: cardSpacing),
                _RuntimeGraphSection(graph: graph),
                SizedBox(height: cardSpacing),
                _RuntimeLaneSection(replay: replay),
                SizedBox(height: cardSpacing),
                _RuntimeDebugLaneSection(debugLanes: debugLanes),
                SizedBox(height: cardSpacing),
                _RuntimeEventSection(replay: replay),
                SizedBox(height: cardSpacing),
                _ModuleChipSection(
                  title: 'Mounted Runtime Modules',
                  features: runtimeFeatures,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricSection(
                  title: 'Execution Route',
                  body:
                      '${routeSelection.title} (${routeSelection.routeKind.wireValue}). ${routeSelection.detail} ${executionCapability.detail}',
                  accent: const Color(0xFFD9E8F8),
                ),
                SizedBox(height: cardSpacing),
                _ToolchainStatusSection(
                  status: toolchainStatus,
                  onRecoveryAction: onToolchainRecoveryAction,
                ),
                SizedBox(height: cardSpacing),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MetricSection(
                        title: 'Lane Preview',
                        body: runtimeEvents.isEmpty
                            ? '$laneCount lane slot(s) reserved. Local runtime capable targets expose broader lane previews once runtime events are captured.'
                            : '$laneCount lane slot(s) inferred from ${runtimeEvents.length} published runtime event(s). ${replay.summarySentence}',
                        accent: const Color(0xFFEDE6D9),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _MetricSection(
                        title: 'Registry Gate',
                        body:
                            '${runtimeFeatures.length} runtime-related feature(s) mounted. Surface features load from mounted module registry entries at startup.',
                        accent: const Color(0xFFE4E7D2),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: cardSpacing),
                _ExecutionSessionSection(
                  executionSession: executionSession,
                  runtimeEventCount: runtimeEvents.length,
                ),
                SizedBox(height: cardSpacing),
                _NativeToolResultSection(
                  results: nativeToolResults,
                  onOpenNativeToolDiagnostics: onOpenNativeToolDiagnostics,
                ),
                SizedBox(height: cardSpacing),
                _OutputChannelSection(
                  executionSession: executionSession,
                  runtimeEvents: runtimeEvents,
                  nativeToolResults: nativeToolResults,
                  outputSnapshot: outputSnapshot,
                  filter: outputChannelFilter,
                ),
                SizedBox(height: cardSpacing),
                _RuntimeGraphSection(graph: graph),
                SizedBox(height: cardSpacing),
                _RuntimeLaneSection(replay: replay),
                SizedBox(height: cardSpacing),
                _RuntimeDebugLaneSection(debugLanes: debugLanes),
                SizedBox(height: cardSpacing),
                _RuntimeEventSection(replay: replay),
                SizedBox(height: cardSpacing),
                _ModuleChipSection(
                  title: 'Mounted Runtime Modules',
                  features: runtimeFeatures,
                ),
              ],
            ),
    );
  }
}

AdapterEndpointCapability _executionCapabilityFor(
  List<AdapterCapabilitySnapshot> adapterCapabilities,
  AdapterKind adapterKind,
) {
  return adapterCapabilities
      .firstWhere(
        (snapshot) => snapshot.adapterKind == adapterKind,
        orElse: () => AdapterCapabilitySnapshot(
          adapterKind: adapterKind,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No ${adapterKind.name} adapter resolved.',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No ${adapterKind.name} adapter resolved.',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No ${adapterKind.name} adapter resolved.',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No ${adapterKind.name} adapter resolved.',
          ),
        ),
      )
      .execution;
}

class _ToolchainStatusSection extends StatelessWidget {
  const _ToolchainStatusSection({
    required this.status,
    required this.onRecoveryAction,
  });

  final ToolchainStatusSurface status;
  final ToolchainRecoveryActionHandler? onRecoveryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (status.severity) {
      ToolchainStatusSeverity.ready => const Color(0xFFDFF0DE),
      ToolchainStatusSeverity.unavailable => const Color(0xFFF0E8D6),
      ToolchainStatusSeverity.blocked => const Color(0xFFF4E8D8),
      ToolchainStatusSeverity.failed => const Color(0xFFF3D8D6),
    };

    return Container(
      key: const ValueKey('toolchain-status-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(status.message, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(label: Text('source ${status.source}')),
              if (status.version != null)
                Chip(label: Text('version ${status.version}')),
              if (status.channel != null)
                Chip(label: Text('channel ${status.channel}')),
              if (status.lastCommand != null)
                Chip(label: Text('command ${status.lastCommand}')),
            ],
          ),
          if (status.recoveryActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Recovery', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: status.recoveryActions
                  .map(
                    (action) => OutlinedButton(
                      key: ValueKey('toolchain-recovery-${action.id}'),
                      onPressed: onRecoveryAction == null
                          ? null
                          : () {
                              onRecoveryAction!(action);
                            },
                      child: Text(action.label),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

Color _runtimeAccentColor(RuntimeAccent accent) {
  switch (accent) {
    case RuntimeAccent.failed:
      return const Color(0xFFF3D8D6);
    case RuntimeAccent.completed:
      return const Color(0xFFDFF0DE);
    case RuntimeAccent.active:
      return const Color(0xFFECE4CF);
    case RuntimeAccent.observed:
      return const Color(0xFFE5E8EE);
    case RuntimeAccent.thread:
      return const Color(0xFFE2EBF9);
    case RuntimeAccent.test:
      return const Color(0xFFE7F2DE);
    case RuntimeAccent.log:
      return const Color(0xFFF4E8D8);
  }
}

class _SurfaceFrame extends StatelessWidget {
  const _SurfaceFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.body,
    required this.accent,
  });

  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ExecutionSessionSection extends StatelessWidget {
  const _ExecutionSessionSection({
    required this.executionSession,
    required this.runtimeEventCount,
  });

  final ExecutionSession? executionSession;
  final int runtimeEventCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = executionSession;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Execution Status', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (session == null)
            Text(
              'No execution session has been started yet.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            Text(
              '${session.kind} · ${session.status.name}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(session.statusMessage, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              'session ${session.sessionId} · $runtimeEventCount runtime event(s)',
              style: theme.textTheme.bodySmall,
            ),
            if (session.unitRange != null) ...[
              const SizedBox(height: 6),
              Text(
                'unit ${session.unitRange!.start}-${session.unitRange!.end}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (session.diagnostics.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${session.diagnostics.length} diagnostic(s) returned from the execution route.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (session.stdoutEvents.isNotEmpty ||
                session.stderrEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${session.stdoutEvents.length} stdout event(s) · ${session.stderrEvents.length} stderr event(s)',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _NativeToolResultSection extends StatelessWidget {
  const _NativeToolResultSection({
    required this.results,
    this.onOpenNativeToolDiagnostics,
  });

  final List<NativeToolResultRecord> results;
  final ValueChanged<AppCommandId>? onOpenNativeToolDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentResults = results.take(4).toList(growable: false);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1EA),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Native Tool Results', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (recentResults.isEmpty)
            Text(
              'No native build, format, static-analysis, or test command has completed yet.',
              style: theme.textTheme.bodySmall,
            )
          else
            ...recentResults.map((result) {
              final statusLabel = result.applied ? 'passed' : 'blocked';
              final diagnosticCount = nativeToolMetadataDiagnosticCount(
                result.metadata,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${result.label} · $statusLabel',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(result.message, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          nativeToolMetadataSummaryText(
                            result.metadata,
                            describeUnstructured: true,
                          )!,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (diagnosticCount > 0 &&
                            onOpenNativeToolDiagnostics != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            key: ValueKey(
                              'runtime-native-tool-open-diagnostics-${result.commandId}',
                            ),
                            onPressed: () {
                              onOpenNativeToolDiagnostics!(result.command);
                            },
                            child: Text('Open diagnostics ($diagnosticCount)'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _RuntimeEventSection extends StatelessWidget {
  const _RuntimeEventSection({required this.replay});

  final RuntimeReplaySummary replay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EFE6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Runtime Event Replay', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (replay.events.isEmpty)
            Text(
              'No published runtime events have been captured yet. Run a project session through pafio to populate compile/run replay data.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            Text(
              '${replay.events.length} event(s) across ${replay.families.length} family/families. ${replay.windowLabel}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Latest ${replay.latestEvent!.eventKind} from ${replay.latestEvent!.origin}.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: replay.families
                  .map((family) => Chip(label: Text(family)))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            ...replay.events
                .take(6)
                .map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '#${event.sequence} ${formatRuntimeClock(event.timestamp)} ${event.eventKind} · ${event.origin}${runtimePayloadSuffix(event.payload)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _OutputChannelSection extends StatelessWidget {
  const _OutputChannelSection({
    required this.executionSession,
    required this.runtimeEvents,
    required this.nativeToolResults,
    required this.outputSnapshot,
    required this.filter,
  });

  final ExecutionSession? executionSession;
  final List<RuntimeEventEnvelope> runtimeEvents;
  final List<NativeToolResultRecord> nativeToolResults;
  final RuntimeOutputPanelSnapshot? outputSnapshot;
  final RuntimeOutputChannelFilterState filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = _mergedOutputChannels(
      baseChannels: _outputChannels(
        executionSession: executionSession,
        runtimeEvents: runtimeEvents,
        nativeToolResults: nativeToolResults,
      ),
      liveSnapshot: outputSnapshot,
    );
    final snapshot = RuntimeOutputChannelSnapshot(
      channels: channels,
      filter: filter,
    );
    final subscriptionPlan = RuntimeOutputStreamSubscriptionPlan.forManager(
      taskId: executionSession?.sessionId ?? 'runtime-surface-preview',
      managerId: 'runtime-surface',
      routeKind: 'output-panel',
      channelIds: channels.map((channel) => channel.id),
      kinds: channels.map((channel) => channel.kind),
      status: RuntimeOutputSubscriptionStatus.active,
      retentionPolicy: const RuntimeOutputRetentionPolicy.workspaceHistory(),
      metadata: const <String, Object?>{'source': 'runtime-surface'},
    );
    final visibleChannels = snapshot.visibleChannels;
    final liveEvents =
        outputSnapshot?.visibleEvents ?? const <RuntimeOutputEvent>[];
    return Container(
      key: const ValueKey('runtime-output-channels'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8ECF6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Output Channels', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Filtered output channel summary for runtime events, process streams, native tool activity, RuntimeOutputLiveBuffer snapshots, ShellManagerRuntimeExecutionAdapter streams, language-service output, and debug output producers.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Subscription ${subscriptionPlan.summary}',
            style: theme.textTheme.bodySmall,
          ),
          if (filter.active) ...[
            const SizedBox(height: 6),
            Chip(label: Text('filter ${filter.summary}')),
          ],
          const SizedBox(height: 10),
          if (visibleChannels.isEmpty)
            Text(
              'No output has been captured yet.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final channel in visibleChannels)
                  Chip(label: Text('${channel.id} ${channel.eventCount}')),
              ],
            ),
            const SizedBox(height: 10),
            for (final channel in visibleChannels.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${channel.label}: ${channel.latestMessage}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          if (liveEvents.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Live Output Events', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final event in liveEvents.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${event.channelId} ${event.kind.wireValue} ${event.message}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

List<RuntimeOutputChannelSummary> _mergedOutputChannels({
  required List<RuntimeOutputChannelSummary> baseChannels,
  required RuntimeOutputPanelSnapshot? liveSnapshot,
}) {
  final channels = <String, RuntimeOutputChannelSummary>{
    for (final channel in baseChannels) channel.id: channel,
  };
  for (final channel
      in liveSnapshot?.channelSnapshot.channels ??
          const <RuntimeOutputChannelSummary>[]) {
    final existing = channels[channel.id];
    channels[channel.id] = existing == null
        ? channel
        : RuntimeOutputChannelSummary(
            id: channel.id,
            label: channel.label,
            kind: channel.kind,
            eventCount: existing.eventCount + channel.eventCount,
            latestMessage: channel.latestMessage.isEmpty
                ? existing.latestMessage
                : channel.latestMessage,
          );
  }
  return channels.values.toList(growable: false);
}

List<RuntimeOutputChannelSummary> _outputChannels({
  required ExecutionSession? executionSession,
  required List<RuntimeEventEnvelope> runtimeEvents,
  required List<NativeToolResultRecord> nativeToolResults,
}) {
  return <RuntimeOutputChannelSummary>[
    RuntimeOutputChannelSummary(
      id: 'runtime-events',
      label: 'Runtime events',
      kind: RuntimeOutputChannelKind.runtimeEvents,
      eventCount: runtimeEvents.length,
      latestMessage: runtimeEvents.isEmpty
          ? 'No runtime event.'
          : '${runtimeEvents.last.eventKind} from ${runtimeEvents.last.origin}',
    ),
    RuntimeOutputChannelSummary(
      id: 'stdout',
      label: 'Stdout',
      kind: RuntimeOutputChannelKind.stdout,
      eventCount: executionSession?.stdoutEvents.length ?? 0,
      latestMessage: executionSession?.stdoutEvents.isEmpty ?? true
          ? 'No stdout event.'
          : executionSession!.stdoutEvents.last.message,
    ),
    RuntimeOutputChannelSummary(
      id: 'stderr',
      label: 'Stderr',
      kind: RuntimeOutputChannelKind.stderr,
      eventCount: executionSession?.stderrEvents.length ?? 0,
      latestMessage: executionSession?.stderrEvents.isEmpty ?? true
          ? 'No stderr event.'
          : executionSession!.stderrEvents.last.message,
    ),
    RuntimeOutputChannelSummary(
      id: 'native-tools',
      label: 'Native tools',
      kind: RuntimeOutputChannelKind.nativeTools,
      eventCount: nativeToolResults.length,
      latestMessage: nativeToolResults.isEmpty
          ? 'No native tool result.'
          : nativeToolResults.first.message,
    ),
  ];
}

class _RuntimeLaneSection extends StatelessWidget {
  const _RuntimeLaneSection({required this.replay});

  final RuntimeReplaySummary replay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF0E8F6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Runtime Lanes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (replay.lanes.isEmpty)
            Text(
              'No active runtime lanes yet. Lane summaries appear once runtime replay is published.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: replay.lanes
                  .map(
                    (lane) => Container(
                      width: 220,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _runtimeAccentColor(lane.accent),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lane.family, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            lane.statusLabel,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${lane.eventCount} event(s) · ${lane.windowLabel}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (lane.detailLabel != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              lane.detailLabel!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'latest ${lane.latestEventKind}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _RuntimeGraphSection extends StatelessWidget {
  const _RuntimeGraphSection({required this.graph});

  final RuntimeGraphSummary graph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE5ECF6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Execution Graph', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (graph.routeNodes.isEmpty)
            Text(
              'No execution graph can be derived yet. Run a project session through pafio to publish runtime replay first.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            Text(graph.summarySentence, style: theme.textTheme.bodySmall),
            if (graph.routeTraceLabel != null) ...[
              const SizedBox(height: 10),
              Text('Route Trace', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(graph.routeTraceLabel!, style: theme.textTheme.bodySmall),
            ],
            if (graph.routeCheckpoints.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Route Checkpoints', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...graph.routeCheckpoints
                  .take(8)
                  .map(
                    (checkpoint) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${checkpoint.clockLabel} ${checkpoint.label} · ${checkpoint.sourceEventKind}${checkpoint.detailLabel == null ? '' : ' · ${checkpoint.detailLabel!}'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
            ],
            if (graph.nodeDetails.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Node Detail', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: graph.nodeDetails
                    .take(4)
                    .map(
                      (detail) => Container(
                        width: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDE8F6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.label,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${detail.checkpointCount} checkpoint(s)',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              detail.windowLabel,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'filter ${detail.filterLabel}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: detail.filterTokens
                                  .map((token) => Chip(label: Text(token)))
                                  .toList(growable: false),
                            ),
                            if (detail.timelineLabel != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'timeline ${detail.timelineLabel!}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (detail.relationLabel != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'relations ${detail.relationLabel!}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (detail.timelineCheckpoints.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Node Timeline',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 6),
                              ...detail.timelineCheckpoints
                                  .take(2)
                                  .map(
                                    (checkpoint) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '${checkpoint.clockLabel} ${checkpoint.sourceEventKind}${checkpoint.detailLabel == null ? '' : ' · ${checkpoint.detailLabel!}'}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                            ],
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 10),
            Text('Route Nodes', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: graph.routeNodes
                  .map((node) => Chip(label: Text(node)))
                  .toList(growable: false),
            ),
            if (graph.transitionEdges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Transition Edges', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...graph.transitionEdges.map(
                (edge) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(edge, style: theme.textTheme.bodySmall),
                ),
              ),
              if (graph.edgeDetails.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Edge Timeline', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: graph.edgeDetails
                      .take(3)
                      .map(
                        (detail) => Container(
                          width: 220,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD7E6EC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail.label,
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${detail.checkpointCount} checkpoint(s)',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                detail.windowLabel,
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'filter ${detail.filterLabel}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: detail.filterTokens
                                    .map((token) => Chip(label: Text(token)))
                                    .toList(growable: false),
                              ),
                              if (detail.timelineLabel != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'timeline ${detail.timelineLabel!}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                              if (detail.timelineCheckpoints.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...detail.timelineCheckpoints
                                    .take(2)
                                    .map(
                                      (checkpoint) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          '${checkpoint.clockLabel} ${checkpoint.sourceEventKind}${checkpoint.detailLabel == null ? '' : ' · ${checkpoint.detailLabel!}'}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ),
                              ],
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
            if (graph.observedNodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Observed Nodes', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (graph.observedDigestLabel != null) ...[
                Text(
                  graph.observedDigestLabel!,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: graph.observedNodes
                    .map((node) => Chip(label: Text(node)))
                    .toList(growable: false),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RuntimeDebugLaneSection extends StatelessWidget {
  const _RuntimeDebugLaneSection({required this.debugLanes});

  final List<RuntimeDebugLaneSummary> debugLanes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF2ECDF),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Debug Lanes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (debugLanes.isEmpty)
            Text(
              'No debug lanes have been derived yet. Thread, test, and log events will be promoted here once replay data is published.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: debugLanes
                  .map(
                    (lane) => Container(
                      width: 220,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _runtimeAccentColor(lane.accent),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lane.title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(
                            lane.statusLabel,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${lane.eventCount} event(s) · ${lane.windowLabel}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'filter ${lane.filterLabel}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: lane.filterTokens
                                .map((token) => Chip(label: Text(token)))
                                .toList(growable: false),
                          ),
                          if (lane.traceLabel != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'trace ${lane.traceLabel!}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          if (lane.detailLabel != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              lane.detailLabel!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          if (lane.checkpoints.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Focused Timeline',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            ...lane.checkpoints
                                .take(3)
                                .map(
                                  (checkpoint) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${checkpoint.clockLabel} ${checkpoint.eventKind}${checkpoint.detailLabel == null ? '' : ' · ${checkpoint.detailLabel!}'}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'latest ${lane.latestEventKind}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _ModuleChipSection extends StatelessWidget {
  const _ModuleChipSection({required this.title, required this.features});

  final String title;
  final List<RuntimeSurfaceFeatureEntry> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          if (features.isEmpty)
            Text(
              'No runtime modules are mounted for this target.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: features
                  .map((feature) => Chip(label: Text(feature.displayName)))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}
