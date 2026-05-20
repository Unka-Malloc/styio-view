import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
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
            onCloseSession: () async {
              closeCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('terminal-surface')), findsOneWidget);
    expect(find.text('Integrated Terminal'), findsOneWidget);
    expect(find.text('logs 2'), findsOneWidget);
    expect(find.text('runtime-events 1'), findsOneWidget);
    expect(find.text('session pty-1'), findsOneWidget);
    expect(find.text('pty-state running'), findsOneWidget);
    expect(find.text('pty-lines 1'), findsOneWidget);
    expect(find.text('pty-events 0'), findsOneWidget);
    expect(find.textContaining('shell booted'), findsOneWidget);
    expect(find.textContaining('runtime  stdout: ok'), findsOneWidget);
    expect(find.textContaining('pty      interactive ok'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('terminal-command-input')),
      'echo ok',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.tap(find.byKey(const ValueKey('terminal-start-session')));
    await tester.tap(find.byKey(const ValueKey('terminal-resize-session')));
    await tester.tap(find.byKey(const ValueKey('terminal-close-session')));
    await tester.tap(find.byKey(const ValueKey('terminal-run-active-target')));
    await tester.pump();

    expect(sentInput, 'echo ok');
    expect(startCount, 1);
    expect(resizeRows, 24);
    expect(resizeCols, 80);
    expect(closeCount, 1);
    expect(runCount, 1);
  });
}
