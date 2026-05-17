import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/platform/viewport_profile.dart';
import 'package:vityo_app/src/runtime/debug_console_surface.dart';
import 'package:vityo_app/src/runtime/runtime_surface.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';

void main() {
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

  testWidgets('debug console includes runtime event replay lines', (
    tester,
  ) async {
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
      ),
    );

    expect(find.text('Debug Console'), findsOneWidget);
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
}

ProjectGraphSnapshot _projectGraph() {
  return const ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: <String>[],
    manifestPath: '/workspace/demo/spio.toml',
    lockfilePath: '/workspace/demo/spio.lock',
    toolchainPinPath: '/workspace/demo/spio-toolchain.toml',
    vendorRoot: '/workspace/demo/.spio/vendor',
    buildRoot: '/workspace/demo/.spio/build',
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
