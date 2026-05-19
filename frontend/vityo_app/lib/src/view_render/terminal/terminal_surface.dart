import 'package:flutter/material.dart';

import '../../view_ide/toolchain/toolchain.dart';
import '../platform/viewport_profile.dart';

class TerminalSurface extends StatelessWidget {
  const TerminalSurface({
    super.key,
    required this.viewportProfile,
    required this.logEntries,
    required this.runtimeEventSummaries,
    this.sessionSnapshot,
    this.onRunActiveTarget,
    this.onSendInput,
  });

  final ViewportProfile viewportProfile;
  final List<String> logEntries;
  final List<String> runtimeEventSummaries;
  final TerminalSessionSnapshot? sessionSnapshot;
  final Future<void> Function()? onRunActiveTarget;
  final Future<void> Function(String input)? onSendInput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final combinedEntries = <String>[
      for (final event in runtimeEventSummaries) 'runtime  $event',
      for (final output in sessionSnapshot?.outputLines ?? const <String>[])
        'pty      $output',
      for (final log in logEntries) 'shell    $log',
    ];

    return Card(
      key: const ValueKey('terminal-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Integrated Terminal', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Shell/runtime output entry backed by Vityo execution logs. TODO: connect interactive PTY stdin/stdout sessions through TerminalRuntime and PtyManager.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('logs ${logEntries.length}')),
                Chip(
                  label: Text('runtime-events ${runtimeEventSummaries.length}'),
                ),
                if (sessionSnapshot == null)
                  const Chip(label: Text('pty scaffolded'))
                else ...[
                  Chip(label: Text('pty-state ${sessionSnapshot!.state.name}')),
                  Chip(
                    label: Text(
                      'pty-lines ${sessionSnapshot!.outputLines.length}',
                    ),
                  ),
                ],
              ],
            ),
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
              Expanded(
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
    );
  }
}
