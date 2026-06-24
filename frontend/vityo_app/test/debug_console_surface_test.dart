import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/viewport_profile.dart';
import 'package:vityo_app/src/runtime/debug_console_surface.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_launcher.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_telemetry_store.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  testWidgets('debug console renders launch plan and telemetry summaries', (
    tester,
  ) async {
    final plan = DapDebugAdapterExecutionPlan.fromConfiguration(
      profileId: 'debug-styio',
      launchConfiguration: DebugLaunchConfiguration.fromToolchainDescriptor(
        debugger: const ToolchainDescriptor(
          id: 'lldb-dap',
          kind: ToolchainKind.debugger,
          displayName: 'LLDB DAP',
          executablePath: '/usr/bin/lldb-dap',
          metadata: <String, Object?>{
            'adapterProtocol': 'dap',
            'programPath': 'build/vityo',
          },
        ),
        workspaceRoot: '/workspace/vityo',
      ),
    );
    final telemetry = DebugLaunchTelemetrySnapshot(
      workspaceId: 'demo',
      records: <DebugLaunchTelemetryRecord>[
        DebugLaunchTelemetryRecord.fromExecutionPlan(
          workspaceId: 'demo',
          plan: plan,
          status: DebugLaunchTelemetryStatus.planned,
          timestamp: DateTime.utc(2026, 5, 20, 16),
        ),
      ],
    );
    final buffer = RuntimeOutputLiveBuffer();
    final dispatch = RuntimeExecutionManagerRegistry.defaultManagers()
        .dispatchToLiveBuffer(
          plan.outputBinding,
          buffer: buffer,
          timestamp: DateTime.utc(2026, 5, 20, 16, 1),
          metadata: const <String, Object?>{
            'debugRuntimeExecution': 'dap-launcher',
          },
        );
    final execution = DebugRuntimeExecutionResult(
      plan: plan,
      status: DebugRuntimeExecutionStatus.failed,
      telemetry: telemetry,
      outputEvents: const <RuntimeOutputEvent>[],
      dispatchResult: dispatch,
    );
    var retried = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 760,
            child: DebugConsoleSurface(
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 760,
              ),
              entries: const <String>[],
              runtimeEvents: const [],
              debugLaunchPlan: plan,
              debugTelemetry: telemetry,
              debugRuntimeExecution: execution,
              onRetryDebugLaunch: () async {
                retried = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('debug-launch-plan-section')),
      findsOneWidget,
    );
    expect(find.text('Debug Launch Plan'), findsOneWidget);
    expect(find.text('profile debug-styio'), findsOneWidget);
    expect(find.text('plan ready'), findsOneWidget);
    expect(find.text('ready true'), findsOneWidget);
    expect(find.text('route ready'), findsOneWidget);
    expect(find.text('telemetry 1'), findsOneWidget);
    expect(find.text('successful 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('debug-launch-plan-message')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('debug-launch-plan-adapter')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('debug-launch-plan-output')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('debug-launch-telemetry-latest')),
      findsOneWidget,
    );
    expect(find.text('execution failed'), findsOneWidget);
    expect(find.text('dispatch dispatched'), findsOneWidget);
    expect(find.text('output 0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('debug-runtime-execution-message')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('debug-runtime-execution-output')),
      findsOneWidget,
    );
    final retryButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('debug-runtime-retry-launch')),
    );
    retryButton.onPressed!();
    await tester.pump();
    expect(retried, isTrue);
  });
}
