import 'package:flutter/material.dart';

import '../../view_ide/backend_toolchain/execution_adapter.dart';
import '../platform/viewport_profile.dart';
import '../../view_ide/runtime/runtime_replay_summary.dart';
import '../../view_ide/shell_runtime/shell_runtime.dart';

class DebugConsoleSurface extends StatelessWidget {
  const DebugConsoleSurface({
    super.key,
    required this.viewportProfile,
    required this.entries,
    required this.runtimeEvents,
    this.debugSession = const DebugSessionSnapshot(
      status: DebugSessionStatus.idle,
      message: 'No debug session has been started.',
    ),
    this.onSelectStackFrame,
    this.onSelectThread,
  });

  final ViewportProfile viewportProfile;
  final List<String> entries;
  final List<RuntimeEventEnvelope> runtimeEvents;
  final DebugSessionSnapshot debugSession;
  final ValueChanged<String>? onSelectStackFrame;
  final ValueChanged<String>? onSelectThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latestRuntimeEvent = runtimeEvents.isEmpty
        ? null
        : runtimeEvents.last;
    final latestEntry = latestRuntimeEvent == null
        ? null
        : formatRuntimeEvent(latestRuntimeEvent);
    final replay = summarizeRuntimeReplay(runtimeEvents);
    final graph = summarizeRuntimeGraph(runtimeEvents);
    final debugLanes = summarizeRuntimeDebugLanes(runtimeEvents);
    final debugDigest = summarizeRuntimeDebugDigest(debugLanes);
    final replayFamilies = replay.families;
    final replayWindow = runtimeEvents.isEmpty
        ? 'No runtime replay window yet.'
        : 'window ${formatRuntimeClock(runtimeEvents.first.timestamp)} -> ${formatRuntimeClock(runtimeEvents.last.timestamp)}';
    final latestLine =
        latestEntry ??
        (entries.isEmpty ? 'No host events yet.' : entries.first);
    final combinedEntries = <String>[
      ...runtimeEvents.reversed.map(formatRuntimeEvent),
      ...entries,
    ];

    return Card(
      key: ValueKey('debug-surface-${viewportProfile.label.toLowerCase()}'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (viewportProfile.isMobile)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Debug Console', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Compact development log aligned to the mobile shell.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Chip(label: Text('host ${entries.length}')),
                      Chip(label: Text('runtime ${runtimeEvents.length}')),
                      Chip(label: Text('${replayFamilies.length} family')),
                      Chip(label: Text(viewportProfile.label)),
                    ],
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Debug Console',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Desktop development log slot fed by shell logs plus published runtime-event replay.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Chip(label: Text('host ${entries.length}')),
                      Chip(label: Text('runtime ${runtimeEvents.length}')),
                      Chip(label: Text('${replayFamilies.length} family')),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: viewportProfile.isMobile ? 180 : 120,
                    ),
                    child: SingleChildScrollView(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3ECDD),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              latestLine,
                              style: theme.textTheme.bodySmall,
                              maxLines: viewportProfile.isMobile ? 3 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              replayWindow,
                              style: theme.textTheme.bodySmall,
                            ),
                            if (replayFamilies.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'families ${replayFamilies.join(', ')}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (graph.routeNodes.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                graph.summarySentence,
                                style: theme.textTheme.bodySmall,
                              ),
                              if (graph.routeTraceLabel != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'route ${graph.routeTraceLabel!}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                              ...graph.nodeDetails
                                  .take(3)
                                  .map(
                                    (detail) => Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'node ${detail.label}: ${detail.filterLabel}',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          if (detail.timelineLabel != null)
                                            Text(
                                              'timeline ${detail.timelineLabel!}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          if (detail.relationLabel != null)
                                            Text(
                                              'relations ${detail.relationLabel!}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ...graph.edgeDetails
                                  .take(2)
                                  .map(
                                    (detail) => Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'edge ${detail.label}: ${detail.filterLabel}',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          if (detail.timelineLabel != null)
                                            Text(
                                              'timeline ${detail.timelineLabel!}',
                                              style: theme.textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                            ],
                            if (debugDigest != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'debug $debugDigest',
                                style: theme.textTheme.bodySmall,
                              ),
                              ...debugLanes.map(
                                (lane) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${lane.title}: ${lane.traceLabel ?? lane.latestEventKind}${lane.detailLabel == null ? '' : ' · ${lane.detailLabel!}'}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      Text(
                                        'filter ${lane.filterLabel}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: viewportProfile.isMobile ? 220 : 190,
                    ),
                    child: SingleChildScrollView(
                      child: _DebuggerSessionSection(
                        session: debugSession,
                        onSelectStackFrame: onSelectStackFrame,
                        onSelectThread: onSelectThread,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: viewportProfile.isMobile ? 220 : 160,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF29282B),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: ListView.separated(
                        reverse: false,
                        itemCount: combinedEntries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return Text(
                            combinedEntries[index],
                            style: const TextStyle(
                              color: Color(0xFFF2F0EC),
                              height: 1.35,
                              fontFamily: 'monospace',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebuggerSessionSection extends StatelessWidget {
  const _DebuggerSessionSection({
    required this.session,
    this.onSelectStackFrame,
    this.onSelectThread,
  });

  final DebugSessionSnapshot session;
  final ValueChanged<String>? onSelectStackFrame;
  final ValueChanged<String>? onSelectThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakpoints = session.breakpoints;
    final threads = session.threads;
    final frames = session.stackFrames;
    final variables = session.variables;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF7),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Debugger Session', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'status ${session.status.name}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(session.message, style: theme.textTheme.bodySmall),
          if (session.debuggerLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              'debugger ${session.debuggerLabel}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'breakpoints ${breakpoints.length}',
            style: theme.textTheme.bodySmall,
          ),
          ...breakpoints
              .take(4)
              .map(
                (breakpoint) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${breakpoint.filePath}:${breakpoint.line + 1}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          const SizedBox(height: 8),
          Text('Threads', style: theme.textTheme.titleSmall),
          if (threads.isEmpty)
            Text('No threads captured.', style: theme.textTheme.bodySmall)
          else
            ...threads
                .take(6)
                .map(
                  (thread) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: GestureDetector(
                      key: ValueKey('debug-thread-${thread.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onSelectThread == null
                          ? null
                          : () => onSelectThread!(thread.id),
                      child: Text(
                        '${thread.id} · ${thread.name}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 8),
          Text('Call Stack', style: theme.textTheme.titleSmall),
          if (frames.isEmpty)
            Text('No stack frames captured.', style: theme.textTheme.bodySmall)
          else
            ...frames
                .take(4)
                .map(
                  (frame) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: GestureDetector(
                      key: ValueKey('debug-stack-frame-${frame.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onSelectStackFrame == null
                          ? null
                          : () => onSelectStackFrame!(frame.id),
                      child: Text(
                        '${frame.name} · ${frame.filePath}:${frame.line + 1}:${frame.column + 1}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 8),
          Text('Variables', style: theme.textTheme.titleSmall),
          if (variables.isEmpty)
            Text('No variables captured.', style: theme.textTheme.bodySmall)
          else
            ...variables
                .take(6)
                .map(
                  (variable) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${variable.name} = ${variable.value}${variable.type == null ? '' : ' : ${variable.type}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
