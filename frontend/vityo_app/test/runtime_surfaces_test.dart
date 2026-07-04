import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/platform/viewport_profile.dart';
import 'package:vityo_app/src/runtime/debug_console_surface.dart';
import 'package:vityo_app/src/runtime/runtime_surface.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart'
    hide DebugSessionSnapshot, DebugSessionStatus;
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';

void main() {
  testWidgets('runtime surface renders live output buffer events', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeSurface(
          platformTarget: PlatformTarget.macos,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1440,
            height: 900,
          ),
          projectGraph: _projectGraph(),
          toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
            _projectGraph().toolchain,
          ),
          mountedModules: const [],
          adapterCapabilities: const <AdapterCapabilitySnapshot>[],
          executionSession: null,
          runtimeEvents: const <RuntimeEventEnvelope>[],
          outputSnapshot: RuntimeOutputPanelSnapshot(
            events: <RuntimeOutputEvent>[
              RuntimeOutputEvent(
                channelId: 'shell.runtime',
                label: 'Shell run',
                kind: RuntimeOutputChannelKind.stdout,
                message: 'handoff-ok',
                timestamp: DateTime.utc(2026, 5, 20, 12),
                metadata: const <String, Object?>{'managerId': 'shell-manager'},
              ),
              RuntimeOutputEvent(
                channelId: 'shell.runtime',
                label: 'Shell run',
                kind: RuntimeOutputChannelKind.runtimeEvents,
                message: 'Runtime shell handoff shell-run completed.',
                timestamp: DateTime.utc(2026, 5, 20, 12),
                metadata: const <String, Object?>{
                  'runtimeShellExecutionStatus': 'executed',
                },
              ),
              RuntimeOutputEvent(
                channelId: 'debug.demo',
                label: 'Debug',
                kind: RuntimeOutputChannelKind.debug,
                message:
                    'launched debug-styio: Debug adapter launched through runtime execution route.',
                timestamp: DateTime.utc(2026, 5, 20, 12, 1),
                metadata: const <String, Object?>{
                  'debugRuntimeExecution': 'dap-launcher',
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Live Output Events'), findsOneWidget);
    expect(find.text('shell.runtime stdout handoff-ok'), findsOneWidget);
    expect(
      find.text(
        'shell.runtime runtime-events Runtime shell handoff shell-run completed.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'debug.demo debug launched debug-styio: Debug adapter launched through runtime execution route.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('runtime surface renders published runtime event replay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeSurface(
          platformTarget: PlatformTarget.macos,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1440,
            height: 900,
          ),
          projectGraph: _projectGraph(),
          toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
            _projectGraph().toolchain,
          ),
          onToolchainRecoveryAction: (_) async {},
          mountedModules: const [],
          adapterCapabilities: const <AdapterCapabilitySnapshot>[
            AdapterCapabilitySnapshot(
              adapterKind: AdapterKind.cli,
              languageService: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.unavailable,
                detail: 'not used in runtime surface test',
              ),
              projectGraph: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.unavailable,
                detail: 'not used in runtime surface test',
              ),
              execution: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.available,
                detail: 'project execution is live',
              ),
              runtimeEvents: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.available,
                detail: 'runtime events are published',
                supportedContractVersions: <int>[1],
              ),
            ),
          ],
          executionSession: const ExecutionSession(
            sessionId: 'runtime-session-test',
            kind: 'test',
            status: ExecutionSessionStatus.succeeded,
            statusMessage: 'test runtime replay available',
            diagnostics: [],
            stdoutEvents: <ExecutionLogEvent>[],
            stderrEvents: <ExecutionLogEvent>[],
          ),
          outputChannelFilter: const RuntimeOutputChannelFilterState(
            kinds: <RuntimeOutputChannelKind>[
              RuntimeOutputChannelKind.runtimeEvents,
            ],
          ),
          runtimeEvents: <RuntimeEventEnvelope>[
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 1,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
              eventKind: 'compile.started',
              origin: 'styio.compile-plan',
              payload: const <String, Object?>{'intent': 'run'},
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 2,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
              eventKind: 'unit.entered',
              origin: 'styio.compile-plan',
              payload: const <String, Object?>{
                'unit_id': 'demo/app::test:smoke',
              },
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 3,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
              eventKind: 'unit.test.started',
              origin: 'styio.tests',
              payload: const <String, Object?>{
                'unit_id': 'demo/app::test:smoke',
                'test_name': 'smoke',
              },
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 4,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
              eventKind: 'transition.fired',
              origin: 'styio.session',
              payload: const <String, Object?>{
                'from': 'empty',
                'to': 'tokenized',
              },
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 5,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
              eventKind: 'state.changed',
              origin: 'styio.session',
              payload: const <String, Object?>{'phase': 'executed'},
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 6,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
              eventKind: 'thread.spawned',
              origin: 'styio.runtime',
              payload: const <String, Object?>{'thread_id': 'main'},
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 7,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
              eventKind: 'log.emitted',
              origin: 'styio.runtime',
              payload: const <String, Object?>{
                'stream': 'stdout',
                'message': 'compile-plan-run',
              },
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 8,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
              eventKind: 'unit.test.finished',
              origin: 'styio.tests',
              payload: const <String, Object?>{
                'unit_id': 'demo/app::test:smoke',
                'test_name': 'smoke',
                'success': true,
              },
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 9,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
              eventKind: 'unit.exited',
              origin: 'styio.compile-plan',
              payload: const <String, Object?>{
                'unit_id': 'demo/app::test:smoke',
                'success': true,
              },
            ),
            RuntimeEventEnvelope(
              schemaVersion: 1,
              sessionId: 'runtime-session-test',
              sequence: 10,
              timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
              eventKind: 'run.finished',
              origin: 'styio.runtime',
              payload: const <String, Object?>{'success': true},
            ),
          ],
        ),
      ),
    );

    expect(find.text('Runtime Event Replay'), findsOneWidget);
    expect(find.text('Output Channels'), findsOneWidget);
    expect(
      find.textContaining('runtime-surface -> output-panel'),
      findsOneWidget,
    );
    expect(find.text('filter kinds runtime-events'), findsOneWidget);
    expect(find.text('runtime-events 10'), findsOneWidget);
    expect(
      find.text('Runtime events: run.finished from styio.runtime'),
      findsOneWidget,
    );
    expect(find.text('Execution Graph'), findsOneWidget);
    expect(
      find.text(
        '10 event(s) across 8 family/families. Window 00:00:00 -> 00:00:01.',
      ),
      findsOneWidget,
    );
    expect(find.text('Runtime Lanes'), findsOneWidget);
    expect(find.text('Debug Lanes'), findsOneWidget);
    expect(
      find.text(
        '8 node(s) / 1 explicit edge(s) derived from 10 runtime event(s). Terminal node run.finished.',
      ),
      findsOneWidget,
    );
    expect(find.text('Route Nodes'), findsOneWidget);
    expect(find.text('Route Trace'), findsOneWidget);
    expect(find.text('Route Checkpoints'), findsOneWidget);
    expect(find.text('Node Detail'), findsOneWidget);
    expect(find.text('Node Timeline'), findsWidgets);
    expect(find.text('Transition Edges'), findsOneWidget);
    expect(find.text('Edge Timeline'), findsOneWidget);
    expect(find.text('Observed Nodes'), findsOneWidget);
    expect(
      find.textContaining(
        'empty -> tokenized -> compile.started -> unit.entered -> unit.test.started',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '00:00:00 compile.started · compile.started · intent=run',
      ),
      findsOneWidget,
    );
    expect(find.text('empty -> tokenized'), findsWidgets);
    expect(find.text('edge=empty -> tokenized'), findsWidgets);
    expect(find.text('event=transition.fired'), findsWidgets);
    expect(
      find.text('filter edge=empty -> tokenized · event=transition.fired'),
      findsOneWidget,
    );
    expect(find.text('timeline transition.fired'), findsWidgets);
    expect(find.text('relations out empty -> tokenized'), findsOneWidget);
    expect(find.text('relations in empty -> tokenized'), findsOneWidget);
    expect(find.text('node=compile.started'), findsWidgets);
    expect(find.text('event=compile.started'), findsWidgets);
    expect(find.text('detail=intent=run'), findsWidgets);
    expect(
      find.text(
        'filter node=compile.started · event=compile.started · detail=intent=run',
      ),
      findsOneWidget,
    );
    expect(find.text('00:00:00 -> 00:00:00'), findsWidgets);
    expect(find.text('timeline compile.started'), findsWidgets);
    expect(find.text('phase=executed'), findsWidgets);
    expect(find.text('compile'), findsWidgets);
    expect(find.text('run'), findsWidgets);
    expect(find.text('unit'), findsWidgets);
    expect(find.text('unit.test'), findsWidgets);
    expect(find.text('transition'), findsWidgets);
    expect(find.text('state'), findsWidgets);
    expect(find.text('thread'), findsWidgets);
    expect(find.text('log'), findsWidgets);
    expect(find.text('Thread Lane'), findsOneWidget);
    expect(find.text('Test Lane'), findsOneWidget);
    expect(find.text('Log Lane'), findsOneWidget);
    expect(find.text('spawned thread lane'), findsOneWidget);
    expect(find.text('completed test lane'), findsOneWidget);
    expect(find.text('streaming log lane'), findsOneWidget);
    expect(find.text('Focused Timeline'), findsNWidgets(3));
    expect(find.text('family=thread'), findsWidgets);
    expect(find.text('family=unit.test'), findsWidgets);
    expect(find.text('family=log'), findsWidgets);
    expect(find.text('thread_id=main'), findsWidgets);
    expect(find.text('stream=stdout'), findsWidgets);
    expect(find.text('filter family=thread · thread_id=main'), findsOneWidget);
    expect(
      find.text('filter family=unit.test · test_name=smoke'),
      findsOneWidget,
    );
    expect(find.text('filter family=log · stream=stdout'), findsOneWidget);
    expect(find.text('trace thread.spawned'), findsOneWidget);
    expect(
      find.text('trace unit.test.started -> unit.test.finished'),
      findsOneWidget,
    );
    expect(find.text('trace log.emitted'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('smoke'), findsWidgets);
    expect(find.text('stdout · compile-plan-run'), findsOneWidget);
    expect(
      find.textContaining('00:00:01 log.emitted · stream=stdout'),
      findsOneWidget,
    );
    expect(find.text('completed lane'), findsNWidgets(3));
    expect(find.text('active lane'), findsNWidgets(2));
    expect(find.text('observed lane'), findsNWidgets(3));
    expect(
      find.textContaining('#1 00:00:00 compile.started · styio.compile-plan'),
      findsOneWidget,
    );
    expect(find.text('unit_id=demo/app::test:smoke'), findsWidgets);
    expect(find.text('test_name=smoke'), findsWidgets);
    expect(
      find.text('Latest run.finished from styio.runtime.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('session runtime-session-test · 10 runtime event(s)'),
      findsOneWidget,
    );
  });

  testWidgets('runtime surface renders live agent activity output channel', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeSurface(
          platformTarget: PlatformTarget.macos,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1440,
            height: 900,
          ),
          projectGraph: _projectGraph(),
          toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
            _projectGraph().toolchain,
          ),
          mountedModules: const [],
          adapterCapabilities: const <AdapterCapabilitySnapshot>[],
          executionSession: null,
          runtimeEvents: const <RuntimeEventEnvelope>[],
          outputSnapshot: RuntimeOutputPanelSnapshot(
            events: <RuntimeOutputEvent>[
              RuntimeOutputEvent(
                channelId: 'agent.activity',
                label: 'Agent Activity',
                kind: RuntimeOutputChannelKind.agent,
                message: 'Patch plan ready.',
                timestamp: DateTime.utc(2026, 5, 20),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('agent.activity 1'), findsOneWidget);
    expect(find.text('Agent Activity: Patch plan ready.'), findsOneWidget);
  });

  testWidgets('runtime surface renders native tool result history', (
    tester,
  ) async {
    AppCommandId? openedDiagnosticsCommand;
    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeSurface(
          platformTarget: PlatformTarget.macos,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1440,
            height: 900,
          ),
          projectGraph: _projectGraph(),
          toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
            _projectGraph().toolchain,
          ),
          mountedModules: const [],
          adapterCapabilities: const <AdapterCapabilitySnapshot>[],
          executionSession: null,
          runtimeEvents: const <RuntimeEventEnvelope>[],
          onOpenNativeToolDiagnostics: (command) {
            openedDiagnosticsCommand = command;
          },
          nativeToolResults: <NativeToolResultRecord>[
            NativeToolResultRecord(
              command: AppCommandId.formatActiveDocument,
              label: 'Format Active Document',
              applied: true,
              message: 'Format Active Document completed.',
              metadata: const <String, Object?>{
                'formatResult': <String, Object?>{
                  'status': 'passed',
                  'changed': true,
                },
              },
              diagnostics: const [],
              completedAt: DateTime.utc(2026, 5, 19),
            ),
            NativeToolResultRecord(
              command: AppCommandId.runStaticAnalysis,
              label: 'Run Static Analysis',
              applied: true,
              message: 'Run Static Analysis completed.',
              metadata: const <String, Object?>{
                'staticAnalysisResult': <String, Object?>{
                  'status': 'passed',
                  'diagnosticCount': 2,
                },
              },
              diagnostics: const [],
              completedAt: DateTime.utc(2026, 5, 19),
            ),
            NativeToolResultRecord(
              command: AppCommandId.runTests,
              label: 'Run Tests',
              applied: true,
              message: 'Run Tests completed.',
              metadata: const <String, Object?>{
                'testResult': <String, Object?>{
                  'status': 'passed',
                  'passedCount': 2,
                  'totalCount': 2,
                },
              },
              diagnostics: const [],
              completedAt: DateTime.utc(2026, 5, 19),
            ),
            NativeToolResultRecord(
              command: AppCommandId.runBuild,
              label: 'Run Build',
              applied: true,
              message: 'Run Build completed.',
              metadata: const <String, Object?>{
                'buildResult': <String, Object?>{
                  'status': 'passed',
                  'diagnosticCount': 1,
                },
              },
              diagnostics: const [],
              completedAt: DateTime.utc(2026, 5, 19),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Native Tool Results'), findsOneWidget);
    expect(find.text('Format Active Document · passed'), findsOneWidget);
    expect(find.text('Run Static Analysis · passed'), findsOneWidget);
    expect(find.text('Run Tests · passed'), findsOneWidget);
    expect(find.text('Run Build · passed'), findsOneWidget);
    expect(find.text('format passed · changed yes'), findsOneWidget);
    expect(find.text('static analysis passed · diagnostics 2'), findsOneWidget);
    expect(find.text('tests passed · 2 passed / 2 total'), findsOneWidget);
    expect(find.text('build passed · diagnostics 1'), findsOneWidget);
    expect(find.text('Open diagnostics (2)'), findsOneWidget);
    expect(find.text('Open diagnostics (1)'), findsOneWidget);

    await tester.ensureVisible(find.text('Open diagnostics (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open diagnostics (2)'));
    await tester.pump();

    expect(openedDiagnosticsCommand, AppCommandId.runStaticAnalysis);

    await tester.ensureVisible(find.text('Open diagnostics (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open diagnostics (1)'));
    await tester.pump();

    expect(openedDiagnosticsCommand, AppCommandId.runBuild);
  });

  testWidgets('debug console includes runtime event replay lines', (
    tester,
  ) async {
    String? selectedFrameId;
    String? selectedThreadId;
    final debugCommands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebugConsoleSurface(
            viewportProfile: const ViewportProfile(
              family: ViewportFamily.desktop,
              width: 1440,
              height: 900,
            ),
            entries: const <String>['12:00:00  host log line'],
            debugSession: const DebugSessionSnapshot(
              status: DebugSessionStatus.configured,
              message:
                  'Debug session configured with Fake LLDB; process launch adapter is not attached yet.',
              debuggerId: 'fake-lldb',
              debuggerLabel: 'Fake LLDB',
              breakpoints: <DebugBreakpoint>[
                DebugBreakpoint(filePath: 'src/main.cc', line: 0),
              ],
              threads: <DebugThread>[DebugThread(id: '1', name: 'main thread')],
              stackFrames: <DebugStackFrame>[
                DebugStackFrame(
                  id: 'frame-main',
                  name: 'main',
                  filePath: 'src/main.cc',
                  line: 0,
                  column: 4,
                ),
              ],
              variables: <DebugVariable>[
                DebugVariable(name: 'argc', value: '1', type: 'int'),
              ],
            ),
            runtimeEvents: <RuntimeEventEnvelope>[
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 1,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
                eventKind: 'compile.started',
                origin: 'styio.compile-plan',
                payload: const <String, Object?>{'intent': 'run'},
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 2,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
                eventKind: 'unit.entered',
                origin: 'styio.compile-plan',
                payload: const <String, Object?>{
                  'unit_id': 'demo/app::test:smoke',
                },
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 3,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
                eventKind: 'unit.test.started',
                origin: 'styio.tests',
                payload: const <String, Object?>{
                  'unit_id': 'demo/app::test:smoke',
                  'test_name': 'smoke',
                },
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 4,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
                eventKind: 'transition.fired',
                origin: 'styio.session',
                payload: const <String, Object?>{
                  'from': 'empty',
                  'to': 'tokenized',
                },
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 5,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
                eventKind: 'state.changed',
                origin: 'styio.session',
                payload: const <String, Object?>{'phase': 'executed'},
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 6,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
                eventKind: 'thread.spawned',
                origin: 'styio.runtime',
                payload: const <String, Object?>{'thread_id': 'main'},
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 7,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
                eventKind: 'log.emitted',
                origin: 'styio.runtime',
                payload: const <String, Object?>{
                  'stream': 'stdout',
                  'message': 'compile-plan-run',
                },
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 8,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
                eventKind: 'unit.test.finished',
                origin: 'styio.tests',
                payload: const <String, Object?>{
                  'unit_id': 'demo/app::test:smoke',
                  'test_name': 'smoke',
                  'success': true,
                },
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 9,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
                eventKind: 'unit.exited',
                origin: 'styio.compile-plan',
                payload: const <String, Object?>{
                  'unit_id': 'demo/app::test:smoke',
                  'success': true,
                },
              ),
              RuntimeEventEnvelope(
                schemaVersion: 1,
                sessionId: 'runtime-session-test',
                sequence: 10,
                timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
                eventKind: 'run.finished',
                origin: 'styio.runtime',
                payload: const <String, Object?>{'success': true},
              ),
            ],
            onStartDebugging: () async {
              debugCommands.add('start');
            },
            onStopDebugging: () async {
              debugCommands.add('stop');
            },
            onSelectStackFrame: (frameId) {
              selectedFrameId = frameId;
            },
            onSelectThread: (threadId) {
              selectedThreadId = threadId;
            },
          ),
        ),
      ),
    );

    expect(find.text('Debug Console'), findsOneWidget);
    expect(find.text('Debugger Session'), findsOneWidget);
    expect(find.text('status configured'), findsOneWidget);
    expect(find.text('debugger Fake LLDB'), findsOneWidget);
    expect(find.text('Debug Controls'), findsOneWidget);
    expect(
      find.text('adapter not attached · pending 0 · events 0'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('debug-control-start')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debug-control-start')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('debug-control-stop')));
    await tester.pump();
    expect(debugCommands, <String>['start', 'stop']);
    expect(find.text('breakpoints 1'), findsOneWidget);
    expect(find.text('src/main.cc:1'), findsOneWidget);
    expect(find.text('Threads'), findsOneWidget);
    expect(find.text('1 · main thread'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('debug-thread-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debug-thread-1')));
    await tester.pump();
    expect(selectedThreadId, '1');
    expect(find.text('Call Stack'), findsOneWidget);
    expect(find.text('main · src/main.cc:1:5'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('debug-stack-frame-frame-main')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('debug-stack-frame-frame-main')),
    );
    await tester.pump();
    expect(selectedFrameId, 'frame-main');
    expect(find.text('Variables'), findsOneWidget);
    expect(find.text('argc = 1 : int'), findsOneWidget);
    expect(find.text('runtime 10'), findsOneWidget);
    expect(find.text('8 family'), findsOneWidget);
    expect(
      find.textContaining('[runtime #10] 00:00:01 run.finished'),
      findsWidgets,
    );
    expect(find.text('window 00:00:00 -> 00:00:01'), findsOneWidget);
    expect(
      find.text(
        'families compile, unit, unit.test, transition, state, thread, log, run',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '8 node(s) / 1 explicit edge(s) derived from 10 runtime event(s). Terminal node run.finished.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'route empty -> tokenized -> compile.started -> unit.entered -> unit.test.started',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'node compile.started: node=compile.started · event=compile.started · detail=intent=run',
      ),
      findsOneWidget,
    );
    expect(
      find.text('node empty: node=empty · event=transition.fired'),
      findsOneWidget,
    );
    expect(find.text('relations out empty -> tokenized'), findsOneWidget);
    expect(
      find.text(
        'edge empty -> tokenized: edge=empty -> tokenized · event=transition.fired',
      ),
      findsOneWidget,
    );
    expect(find.text('timeline compile.started'), findsWidgets);
    expect(find.text('timeline transition.fired'), findsWidgets);
    expect(
      find.text('debug threads main · tests smoke · logs stdout'),
      findsOneWidget,
    );
    expect(find.text('Thread Lane: thread.spawned · main'), findsOneWidget);
    expect(
      find.text('Test Lane: unit.test.started -> unit.test.finished · smoke'),
      findsOneWidget,
    );
    expect(
      find.text('Log Lane: log.emitted · stdout · compile-plan-run'),
      findsOneWidget,
    );
    expect(find.text('filter family=thread · thread_id=main'), findsOneWidget);
    expect(
      find.text('filter family=unit.test · test_name=smoke'),
      findsOneWidget,
    );
    expect(find.text('filter family=log · stream=stdout'), findsOneWidget);
  });

  testWidgets('debug console exposes paused session stepping controls', (
    tester,
  ) async {
    final debugCommands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DebugConsoleSurface(
            viewportProfile: const ViewportProfile(
              family: ViewportFamily.desktop,
              width: 1440,
              height: 900,
            ),
            entries: const <String>[],
            runtimeEvents: const <RuntimeEventEnvelope>[],
            debugSession: const DebugSessionSnapshot(
              status: DebugSessionStatus.paused,
              message: 'Paused on breakpoint.',
              debuggerId: 'lldb-dap',
              debuggerLabel: 'LLDB DAP',
              adapterSessionStatus: 'paused',
              adapterPendingRequestCount: 1,
              adapterEventCount: 2,
            ),
            onContinueDebugging: () async {
              debugCommands.add('continue');
            },
            onStepOver: () async {
              debugCommands.add('step-over');
            },
            onStopDebugging: () async {
              debugCommands.add('stop');
            },
          ),
        ),
      ),
    );

    expect(find.text('status paused'), findsOneWidget);
    expect(find.text('adapter paused · pending 1 · events 2'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('debug-control-continue')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debug-control-continue')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('debug-control-step-over')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('debug-control-stop')));
    await tester.pump();

    expect(debugCommands, <String>['continue', 'step-over', 'stop']);
  });

  testWidgets('runtime surface route text uses primary adapter detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RuntimeSurface(
          platformTarget: PlatformTarget.web,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1440,
            height: 900,
          ),
          projectGraph: _hostedProjectGraph(),
          toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
            _hostedProjectGraph().toolchain,
          ),
          onToolchainRecoveryAction: (_) async {},
          mountedModules: const [],
          adapterCapabilities: const <AdapterCapabilitySnapshot>[
            AdapterCapabilitySnapshot(
              adapterKind: AdapterKind.cloud,
              languageService: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.partial,
                detail: 'hosted language route',
              ),
              projectGraph: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.available,
                detail: 'hosted project graph route',
              ),
              execution: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.available,
                detail: 'hosted execution detail',
              ),
              runtimeEvents: AdapterEndpointCapability(
                level: AdapterCapabilityLevel.available,
                detail: 'hosted runtime events',
              ),
            ),
          ],
          executionSession: null,
          runtimeEvents: const <RuntimeEventEnvelope>[],
        ),
      ),
    );

    expect(find.textContaining('Hosted project route'), findsOneWidget);
    expect(find.textContaining('(hosted)'), findsOneWidget);
    expect(find.textContaining('hosted execution detail'), findsOneWidget);
    expect(find.textContaining('No cli adapter resolved'), findsNothing);
  });
}

ProjectGraphSnapshot _projectGraph() {
  return const ProjectGraphSnapshot(
    id: '/workspace/demo/pafio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: <String>[],
    manifestPath: '/workspace/demo/pafio.toml',
    lockfilePath: '/workspace/demo/pafio.lock',
    toolchainPinPath: '/workspace/demo/pafio-toolchain.toml',
    vendorRoot: '/workspace/demo/.pafio/vendor',
    buildRoot: '/workspace/demo/.pafio/build',
    packages: <ProjectPackageSnapshot>[],
    dependencies: <ProjectDependencySnapshot>[],
    targets: <ProjectTargetDescriptor>[],
    editorFiles: <String>['/workspace/demo/src/main.styio'],
    toolchain: ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'test fixture toolchain',
      channel: 'stable',
      version: '0.0.1',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.present,
    activeCompiler: CompilerHandshakeSnapshot(
      binaryPath: '/toolchains/styio/bin/styio',
      tool: 'styio',
      compilerVersion: '0.0.1',
      channel: 'stable',
      variant: 'test-fixture',
      capabilities: <String>[
        'machine_info_json',
        'single_file_entry',
        'jsonl_diagnostics',
      ],
      supportedContractVersions: <String, List<int>>{
        'machine_info': <int>[1],
        'compile_plan': <int>[1],
        'runtime_events': <int>[1],
      },
      integrationPhase: 'compile-plan-live',
      featureFlags: <String, bool>{
        'compile_plan_consumer': true,
        'runtime_event_stream': true,
      },
    ),
    notes: <String>[],
  );
}

ProjectGraphSnapshot _hostedProjectGraph() {
  return ProjectGraphSnapshot(
    id: 'hosted-runtime-demo',
    title: 'Hosted Runtime Demo',
    kind: ProjectKind.hosted,
    workspaceRoot: '/workspace/hosted-runtime-demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/hosted-runtime-demo/pafio.toml',
    dependencies: const <ProjectDependencySnapshot>[],
    packages: const <ProjectPackageSnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>[
      '/workspace/hosted-runtime-demo/src/main.styio',
    ],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'hosted pin',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    hostedWorkspace: HostedWorkspaceRecordSnapshot(
      workspaceId: 'hosted-runtime-demo',
      schemaVersion: '1',
      ownerRef: 'Vityo',
      status: HostedWorkspaceStatus.active,
      entryUrl: 'https://hosted.test/workspaces/hosted-runtime-demo',
      createdAt: DateTime.utc(2026, 5, 18),
      lastActiveAt: DateTime.utc(2026, 5, 18, 1),
      retentionDays: 7,
      exportState: HostedWorkspaceExportState.notRequested,
    ),
    notes: const <String>[],
  );
}
