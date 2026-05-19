import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/terminal/terminal.dart';

void main() {
  testWidgets('terminal surface renders shell output and run handoff', (
    tester,
  ) async {
    var runCount = 0;

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
            onRunActiveTarget: () async {
              runCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('terminal-surface')), findsOneWidget);
    expect(find.text('Integrated Terminal'), findsOneWidget);
    expect(find.text('logs 2'), findsOneWidget);
    expect(find.text('runtime-events 1'), findsOneWidget);
    expect(find.text('pty scaffolded'), findsOneWidget);
    expect(find.textContaining('shell booted'), findsOneWidget);
    expect(find.textContaining('runtime  stdout: ok'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('terminal-run-active-target')));
    await tester.pump();

    expect(runCount, 1);
  });
}
