import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/terminal/terminal.dart';

void main() {
  testWidgets('terminal surface renders shell output and run handoff', (
    tester,
  ) async {
    var runCount = 0;
    var startCount = 0;
    var closeCount = 0;
    int? resizeRows;
    int? resizeCols;
    String? sentInput;
    PtySignal? sentSignal;
    TerminalSessionRecoveryPlan? appliedRecovery;
    final startPlan = TerminalRuntimeStartPlan(
      profileId: 'sh',
      executablePath: '/bin/sh',
      workingDirectory: '/workspace/vityo',
      rows: 24,
      cols: 80,
      ptyPlan: PtyAdapter(PtyFacts.linuxDebianArm(scriptUtilityPath: '/script'))
          .plan(
            const PtySessionRequest(
              executablePath: '/bin/sh',
              workingDirectory: '/workspace/vityo',
              rows: 24,
              cols: 80,
            ),
          ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            logEntries: const <String>['shell booted', 'stdout: ok'],
            runtimeEventSummaries: const <String>['stdout: ok'],
            sessionSnapshot: const TerminalSessionSnapshot(
              sessionId: 'pty-1',
              state: PtySessionState.running,
              outputLines: <String>['interactive ok'],
            ),
            startPlan: startPlan,
            onRunActiveTarget: () async {
              runCount += 1;
            },
            onStartSession: () async {
              startCount += 1;
            },
            onSendInput: (input) async {
              sentInput = input;
            },
            onResizeSession: (rows, cols) async {
              resizeRows = rows;
              resizeCols = cols;
            },
            onSendSignal: (signal) async {
              sentSignal = signal;
            },
            onCloseSession: () async {
              closeCount += 1;
            },
            recoveryPlan: const TerminalSessionRecoveryPlan(
              action: TerminalSessionRecoveryAction.rebindOutputSubscription,
              sessionId: 'pty-1',
              profileId: 'sh',
              canRetry: true,
              message: 'Output subscription is detached.',
            ),
            onApplyRecovery: (plan) async {
              appliedRecovery = plan;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('terminal-surface')), findsOneWidget);
    expect(find.text('Integrated Terminal'), findsOneWidget);
    expect(find.text('logs 2'), findsOneWidget);
    expect(find.text('runtime-events 1'), findsOneWidget);
    expect(find.text('start-plan ready'), findsOneWidget);
    expect(find.text('terminal-profile sh'), findsOneWidget);
    expect(find.text('pty-provider ${startPlan.providerKind}'), findsOneWidget);
    expect(find.byKey(const ValueKey('terminal-start-plan')), findsOneWidget);
    expect(find.textContaining('/bin/sh'), findsWidgets);
    expect(find.text('session pty-1'), findsOneWidget);
    expect(find.text('pty-state running'), findsOneWidget);
    expect(find.text('pty-lines 1'), findsOneWidget);
    expect(find.text('pty-events 0'), findsOneWidget);
    expect(find.text('recovery rebind-output-subscription'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('terminal-recovery-plan')),
      findsOneWidget,
    );
    expect(find.textContaining('shell booted'), findsOneWidget);
    expect(find.textContaining('runtime  stdout: ok'), findsOneWidget);
    expect(find.textContaining('pty      interactive ok'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-command-input')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('terminal-command-input')),
      'echo ok',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-start-session')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-start-session')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-resize-session')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-resize-session')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-send-interrupt')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-send-interrupt')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-close-session')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-close-session')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-run-active-target')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('terminal-run-active-target')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('terminal-apply-recovery-action')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('terminal-apply-recovery-action')),
    );
    await tester.pump();

    expect(sentInput, 'echo ok');
    expect(startCount, 1);
    expect(resizeRows, 24);
    expect(resizeCols, 80);
    expect(sentSignal, PtySignal.interrupt);
    expect(closeCount, 1);
    expect(runCount, 1);
    expect(
      appliedRecovery?.action,
      TerminalSessionRecoveryAction.rebindOutputSubscription,
    );
  });

  testWidgets('terminal surface renders live output snapshot events', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            logEntries: const <String>[],
            runtimeEventSummaries: const <String>[],
            liveOutputSnapshot: RuntimeOutputPanelSnapshot(
              events: <RuntimeOutputEvent>[
                RuntimeOutputEvent(
                  channelId: 'runtime.terminal',
                  label: 'Terminal',
                  kind: RuntimeOutputChannelKind.stdout,
                  message: 'live stdout',
                  timestamp: DateTime.utc(2026, 5, 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('live-events 1'), findsOneWidget);
    expect(find.text('live-channels 1'), findsOneWidget);
    expect(find.textContaining('output   stdout live stdout'), findsOneWidget);
  });
}
