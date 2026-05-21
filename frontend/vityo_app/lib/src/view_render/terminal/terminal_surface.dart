import 'package:flutter/material.dart';

import '../../view_ide/environment/environment.dart';
import '../../view_ide/runtime/runtime.dart';
import '../../view_ide/toolchain/toolchain.dart';
import '../platform/viewport_profile.dart';

class TerminalSurface extends StatelessWidget {
  const TerminalSurface({
    super.key,
    required this.viewportProfile,
    required this.logEntries,
    required this.runtimeEventSummaries,
    this.liveOutputSnapshot,
    this.sessionSnapshot,
    this.startPlan,
    this.onRunActiveTarget,
    this.onStartSession,
    this.onSendInput,
    this.onResizeSession,
    this.onSendSignal,
    this.onCloseSession,
    this.recoveryPlan,
    this.onApplyRecovery,
  });

  final ViewportProfile viewportProfile;
  final List<String> logEntries;
  final List<String> runtimeEventSummaries;
  final RuntimeOutputPanelSnapshot? liveOutputSnapshot;
  final TerminalSessionSnapshot? sessionSnapshot;
  final TerminalRuntimeStartPlan? startPlan;
  final Future<void> Function()? onRunActiveTarget;
  final Future<void> Function()? onStartSession;
  final Future<void> Function(String input)? onSendInput;
  final Future<void> Function(int rows, int cols)? onResizeSession;
  final Future<void> Function(PtySignal signal)? onSendSignal;
  final Future<void> Function()? onCloseSession;
  final TerminalSessionRecoveryPlan? recoveryPlan;
  final Future<void> Function(TerminalSessionRecoveryPlan plan)?
  onApplyRecovery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final combinedEntries = <String>[
      for (final event
          in liveOutputSnapshot?.visibleEvents ?? const <RuntimeOutputEvent>[])
        'output   ${event.kind.wireValue} ${event.message}',
      for (final event in runtimeEventSummaries) 'runtime  $event',
      for (final output in sessionSnapshot?.outputLines ?? const <String>[])
        'pty      $output',
      for (final log in logEntries) 'shell    $log',
    ];

    return Card(
      key: const ValueKey('terminal-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Integrated Terminal', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Shell/runtime output entry backed by Vityo execution logs, TerminalRuntime session snapshots, RuntimeOutputLiveBuffer panel snapshots, explicit start/resize/signal/close controls, recovery action controls, and PTY start-plan readiness. TODO: connect native OS PTY resize/signals.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Chip(label: Text('logs ${logEntries.length}')),
                  Chip(
                    label: Text(
                      'runtime-events ${runtimeEventSummaries.length}',
                    ),
                  ),
                  if (startPlan == null)
                    const Chip(label: Text('start-plan TODO'))
                  else ...[
                    Chip(
                      label: Text(
                        'start-plan ${startPlan!.supported ? 'ready' : 'blocked'}',
                      ),
                    ),
                    Chip(
                      label: Text('terminal-profile ${startPlan!.profileId}'),
                    ),
                    Chip(
                      label: Text('pty-provider ${startPlan!.providerKind}'),
                    ),
                  ],
                  if (liveOutputSnapshot != null) ...[
                    Chip(
                      label: Text(
                        'live-events ${liveOutputSnapshot!.visibleEvents.length}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'live-channels ${liveOutputSnapshot!.channelSnapshot.visibleChannels.length}',
                      ),
                    ),
                  ],
                  if (recoveryPlan != null)
                    Chip(
                      label: Text('recovery ${recoveryPlan!.action.wireValue}'),
                    ),
                  if (sessionSnapshot == null)
                    const Chip(label: Text('pty scaffolded'))
                  else ...[
                    Chip(label: Text('session ${sessionSnapshot!.sessionId}')),
                    Chip(
                      label: Text('pty-state ${sessionSnapshot!.state.name}'),
                    ),
                    Chip(
                      label: Text(
                        'pty-lines ${sessionSnapshot!.outputLines.length}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'pty-events ${sessionSnapshot!.events.length}',
                      ),
                    ),
                    if (sessionSnapshot!.lastResize != null)
                      Chip(
                        label: Text(
                          'resize ${sessionSnapshot!.lastResize!.rows}x${sessionSnapshot!.lastResize!.cols}',
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('terminal-start-session'),
                    onPressed: onStartSession,
                    icon: const Icon(Icons.terminal_rounded),
                    label: const Text('Start Terminal'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('terminal-resize-session'),
                    onPressed:
                        sessionSnapshot == null || onResizeSession == null
                        ? null
                        : () {
                            onResizeSession!(24, 80);
                          },
                    icon: const Icon(Icons.fit_screen_rounded),
                    label: const Text('Resize 24x80'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('terminal-send-interrupt'),
                    onPressed: sessionSnapshot == null || onSendSignal == null
                        ? null
                        : () {
                            onSendSignal!(PtySignal.interrupt);
                          },
                    icon: const Icon(Icons.keyboard_command_key_rounded),
                    label: const Text('Send Ctrl-C'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('terminal-close-session'),
                    onPressed: sessionSnapshot == null ? null : onCloseSession,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Close Terminal'),
                  ),
                  if (recoveryPlan?.hasRecoveryAction == true)
                    FilledButton.icon(
                      key: const ValueKey('terminal-apply-recovery-action'),
                      onPressed: onApplyRecovery == null
                          ? null
                          : () {
                              onApplyRecovery!(recoveryPlan!);
                            },
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: Text(_recoveryActionLabel(recoveryPlan!)),
                    ),
                ],
              ),
              if (recoveryPlan?.hasRecoveryAction == true) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('terminal-recovery-plan'),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery action',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        recoveryPlan!.message,
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'action ${recoveryPlan!.action.wireValue}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (startPlan != null) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('terminal-start-plan'),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start plan', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Text(
                        'shell ${startPlan!.executablePath} ${startPlan!.rows}x${startPlan!.cols}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (startPlan!.workingDirectory != null)
                        Text(
                          'cwd ${startPlan!.workingDirectory}',
                          style: theme.textTheme.bodySmall,
                        ),
                      Text(
                        'backend ${startPlan!.backendExecutablePath}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (startPlan!.backendArguments.isNotEmpty)
                        Text(
                          'args ${startPlan!.backendArguments.join(' ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (startPlan!.unsupportedMessage != null)
                        Text(
                          key: const ValueKey('terminal-start-plan-message'),
                          startPlan!.unsupportedMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('terminal-command-input'),
                      enabled: onSendInput != null,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        labelText: 'Terminal input',
                        helperText: onSendInput == null
                            ? 'TODO: enable after interactive PTY sessions are wired.'
                            : 'Send input to the active PTY session.',
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: onSendInput,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    key: const ValueKey('terminal-run-active-target'),
                    onPressed: onRunActiveTarget,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Run'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Output', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (combinedEntries.isEmpty)
                Text(
                  'No terminal, shell, or runtime output has been recorded.',
                  style: theme.textTheme.bodySmall,
                )
              else
                SizedBox(
                  height: compact ? 180 : 220,
                  child: Container(
                    key: const ValueKey('terminal-output-buffer'),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111A1F),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: ListView.builder(
                      itemCount: combinedEntries.length,
                      itemBuilder: (context, index) {
                        return Text(
                          combinedEntries[index],
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFD9E7DE),
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
      ),
    );
  }
}

String _recoveryActionLabel(TerminalSessionRecoveryPlan plan) {
  return switch (plan.action) {
    TerminalSessionRecoveryAction.replayStartPlan => 'Replay Terminal',
    TerminalSessionRecoveryAction.rebindOutputSubscription => 'Rebind Output',
    TerminalSessionRecoveryAction.closeStaleSession => 'Close Stale',
    TerminalSessionRecoveryAction.markUnsupported => 'Mark Unsupported',
    TerminalSessionRecoveryAction.none => 'No Recovery',
  };
}
